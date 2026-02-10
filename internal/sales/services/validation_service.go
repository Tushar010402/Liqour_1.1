package services

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	sharedModels "github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// commonBrandMisreads maps common OCR misreadings to canonical brand names
// These are hardcoded patterns based on observed OCR errors from handwritten registers
var commonBrandMisreads = map[string]string{
	// Kingfisher variations
	"GODFATHER":         "KINGFISHER STRONG",
	"GOD FATHER":        "KINGFISHER STRONG",
	"GODFATNER":         "KINGFISHER STRONG",
	"KINFISHER":         "KINGFISHER",
	"KINGFISER":         "KINGFISHER",
	"KINGFISRER":        "KINGFISHER",
	"KINDGFISHER":       "KINGFISHER",

	// Kingfisher Ultra Max variations
	"ANSTEL":            "KINGFISHER ULTRA MAX",
	"AMSTEL":            "KINGFISHER ULTRA MAX",
	"ULTRAMAX":          "KINGFISHER ULTRA MAX",
	"ULTAMAX":           "KINGFISHER ULTRA MAX",
	"ULTRA MAX":         "KINGFISHER ULTRA MAX",

	// Tuborg variations
	"TUBROG":            "TUBORG",
	"TUBORD":            "TUBORG",
	"TRUBORG":           "TUBORG",

	// Budweiser variations
	"BUDWISER":          "BUDWEISER",
	"BUDWESER":          "BUDWEISER",
	"BUDWIESER":         "BUDWEISER",
	"BUDWIEZER":         "BUDWEISER",

	// Carlsberg variations
	"CARLBURG":          "CARLSBERG",
	"CARLBSERG":         "CARLSBERG",
	"CARLSBURG":         "CARLSBERG",

	// Hoegaarden variations
	"HOEGARDEN":         "HOEGAARDEN",
	"HOEGAARDN":         "HOEGAARDEN",
	"HOEGARGEN":         "HOEGAARDEN",
	"HOGAARDEN":         "HOEGAARDEN",

	// Haywards variations
	"HAYWORD":           "HAYWARDS",
	"HAYWOOD":           "HAYWARDS",
	"HAYWARDS 5000":     "HAYWARDS",

	// Knock Out variations
	"KNOCKUT":           "KNOCK OUT",
	"KNOKOUT":           "KNOCK OUT",

	// Royal Challenge variations
	"ROYAL CHALLANGE":   "ROYAL CHALLENGE",
	"ROYALCHALLENGE":    "ROYAL CHALLENGE",

	// Old Monk variations
	"OLDMONK":           "OLD MONK",
	"OLD MONKE":         "OLD MONK",

	// McDowell's variations
	"MCDOWEL":           "MCDOWELLS",
	"MCDOWELS":          "MCDOWELLS",
	"MC DOWELLS":        "MCDOWELLS",

	// Blenders Pride variations
	"BLENDER PRIDE":     "BLENDERS PRIDE",
	"BLENDERSPRIDE":     "BLENDERS PRIDE",

	// Bagpiper variations
	"BAGPIPIR":          "BAGPIPER",
	"BAGPIPR":           "BAGPIPER",

	// Corona variations
	"CORANA":            "CORONA",
	"CORONA EXTRA":      "CORONA",

	// Heineken variations
	"HEINIKAN":          "HEINEKEN",
	"HEINEKAN":          "HEINEKEN",

	// Generic/illegible patterns
	"UNKNOWN":           "",
	"ILLEGIBLE":         "",
	"UNKNOWN ILLEGIBLE": "",

	// Common OCR misreads - only for fixing typos, not for brand variants
	"PURECRAFT":         "PURE CRAFT",
	"PURE CRAF":         "PURE CRAFT",
}

// Common variant suffixes that distinguish different products
var variantSuffixes = []string{
	"MATURED", "WHITE", "GOLD", "SILVER", "PREMIUM", "STRONG", "ULTRA",
	"LIGHT", "DARK", "RESERVE", "SELECT", "CLASSIC", "ORIGINAL",
	"MAX", "MINI", "CRAFT", "SPECIAL", "DELUXE", "AGED", "BLACK", "RED",
	"GREEN", "BLUE", "XXX", "VS", "VSOP", "XO", "RUM", "WHISKY", "BEER",
	"VODKA", "GIN", "BRANDY", "WINE", "LAGER", "ALE", "STOUT", "PILSNER",
}

// isExcludedMatch uses smart detection to check if two brands are variants of each other
// that should NOT be matched together (e.g., "OLD MONK" vs "OLD MONK MATURED RUM")
func isExcludedMatch(brand1, brand2 string) bool {
	// Normalize both brands
	brand1 = strings.ToUpper(strings.TrimSpace(brand1))
	brand2 = strings.ToUpper(strings.TrimSpace(brand2))

	// Exact match is fine - not excluded
	if brand1 == brand2 {
		return false
	}

	// Empty brands - not excluded
	if brand1 == "" || brand2 == "" {
		return false
	}

	words1 := strings.Fields(brand1)
	words2 := strings.Fields(brand2)

	// Rule 1: Prefix relationship detection
	// If one brand is a prefix of another, they're likely variants (exclude matching)
	// e.g., "OLD MONK" vs "OLD MONK MATURED RUM"
	if isPrefixBrand(words1, words2) || isPrefixBrand(words2, words1) {
		return true
	}

	// Rule 2: Same base with different variant suffix
	// e.g., "KINGFISHER STRONG" vs "KINGFISHER ULTRA MAX"
	if hasSameBaseWithDifferentVariant(words1, words2) {
		return true
	}

	// Rule 3: High word overlap but different - likely confused variants
	// e.g., brands sharing 2+ words but not identical
	if hasConfusingWordOverlap(words1, words2) {
		return true
	}

	return false
}

// isPrefixBrand checks if words1 is a prefix of words2
// e.g., ["OLD", "MONK"] is prefix of ["OLD", "MONK", "MATURED", "RUM"]
func isPrefixBrand(shorter, longer []string) bool {
	if len(shorter) >= len(longer) {
		return false
	}

	// Need at least 1 word in shorter and at least 1 extra word in longer
	if len(shorter) < 1 || len(longer) < 2 {
		return false
	}

	// Check if all words in shorter match the beginning of longer
	for i, word := range shorter {
		if !stringsEqualFuzzy(word, longer[i]) {
			return false
		}
	}

	// Verify the extra word(s) in longer are meaningful (not just noise)
	extraWords := longer[len(shorter):]
	for _, extra := range extraWords {
		if len(extra) >= 2 { // At least 2 chars to be meaningful
			return true
		}
	}

	return false
}

// hasSameBaseWithDifferentVariant checks if two brands share a base but have different variants
// e.g., "KINGFISHER STRONG" vs "KINGFISHER ULTRA"
func hasSameBaseWithDifferentVariant(words1, words2 []string) bool {
	if len(words1) < 2 || len(words2) < 2 {
		return false
	}

	// Find common prefix length
	commonLen := 0
	minLen := len(words1)
	if len(words2) < minLen {
		minLen = len(words2)
	}

	for i := 0; i < minLen; i++ {
		if stringsEqualFuzzy(words1[i], words2[i]) {
			commonLen++
		} else {
			break
		}
	}

	// Need at least 1 common word and both must have words after it
	if commonLen < 1 {
		return false
	}

	remaining1 := words1[commonLen:]
	remaining2 := words2[commonLen:]

	// Both have remaining words that differ - check if they're variant suffixes
	if len(remaining1) > 0 && len(remaining2) > 0 {
		hasVariant1 := containsVariantSuffix(remaining1)
		hasVariant2 := containsVariantSuffix(remaining2)

		// If both have variant indicators, they're different products
		if hasVariant1 && hasVariant2 {
			return true
		}

		// If only one has variant indicator, they might still be different
		if hasVariant1 || hasVariant2 {
			return true
		}
	}

	return false
}

// containsVariantSuffix checks if any word is a known variant suffix
func containsVariantSuffix(words []string) bool {
	for _, word := range words {
		for _, suffix := range variantSuffixes {
			if stringsEqualFuzzy(word, suffix) {
				return true
			}
		}
	}
	return false
}

// hasConfusingWordOverlap detects brands that share significant words but aren't identical
// This catches cases where OCR might confuse similar-sounding brands
func hasConfusingWordOverlap(words1, words2 []string) bool {
	if len(words1) == 0 || len(words2) == 0 {
		return false
	}

	// Count matching words
	matchCount := 0
	for _, w1 := range words1 {
		for _, w2 := range words2 {
			if stringsEqualFuzzy(w1, w2) {
				matchCount++
				break
			}
		}
	}

	// Calculate overlap ratio
	minWords := len(words1)
	if len(words2) < minWords {
		minWords = len(words2)
	}

	maxWords := len(words1)
	if len(words2) > maxWords {
		maxWords = len(words2)
	}

	// If they share 50%+ words but have different lengths, they're confusing variants
	// e.g., "OLD MONK RUM" vs "OLD MONK WHITE RUM" (3 of 4 match = 75%)
	overlapRatio := float64(matchCount) / float64(minWords)

	if overlapRatio >= 0.5 && len(words1) != len(words2) {
		return true
	}

	// If same length, high overlap, but not identical - also exclude
	if len(words1) == len(words2) && matchCount >= 2 && matchCount < len(words1) {
		return true
	}

	return false
}

// stringsEqualFuzzy compares two strings with minor fuzzy tolerance
func stringsEqualFuzzy(s1, s2 string) bool {
	s1 = strings.ToUpper(strings.TrimSpace(s1))
	s2 = strings.ToUpper(strings.TrimSpace(s2))

	if s1 == s2 {
		return true
	}

	// Allow for minor OCR errors (1 char difference for words > 4 chars)
	if len(s1) > 4 && len(s2) > 4 {
		diff := levenshteinDistance(s1, s2)
		return diff <= 1
	}

	return false
}

// MatchDebugLog captures detailed information about matching decisions for debugging
type MatchDebugLog struct {
	EnteredBrand      string  `json:"entered_brand"`
	OCRBrand          string  `json:"ocr_brand"`
	ResolvedOCRBrand  string  `json:"resolved_ocr_brand"`
	EnteredSize       string  `json:"entered_size"`
	OCRSize           string  `json:"ocr_size"`
	BrandSimilarity   float64 `json:"brand_similarity"`
	FirstWordSim      float64 `json:"first_word_similarity"`
	SizeMatches       bool    `json:"size_matches"`
	BrandsExcluded    bool    `json:"brands_excluded"`
	DataFingerprint   bool    `json:"data_fingerprint_match"`
	FinalConfidence   float64 `json:"final_confidence"`
	MatchDecision     string  `json:"match_decision"` // "MATCHED", "REJECTED", "EXCLUDED"
	RejectionReason   string  `json:"rejection_reason,omitempty"`
}

// logMatchDecision logs detailed matching decision for debugging
// Enable with DEBUG_MATCHING=true environment variable
func logMatchDecision(log MatchDebugLog) {
	if os.Getenv("DEBUG_MATCHING") != "true" {
		return
	}

	// Format and print debug log
	fmt.Printf("\n🔍 [Match Debug] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
	fmt.Printf("   Entered: '%s' (%s)\n", log.EnteredBrand, log.EnteredSize)
	fmt.Printf("   OCR:     '%s' -> '%s' (%s)\n", log.OCRBrand, log.ResolvedOCRBrand, log.OCRSize)
	fmt.Printf("   Brand Similarity: %.2f | First Word: %.2f\n", log.BrandSimilarity, log.FirstWordSim)
	fmt.Printf("   Size Match: %v | Excluded: %v | Fingerprint: %v\n", log.SizeMatches, log.BrandsExcluded, log.DataFingerprint)
	fmt.Printf("   Confidence: %.2f | Decision: %s\n", log.FinalConfidence, log.MatchDecision)
	if log.RejectionReason != "" {
		fmt.Printf("   Reason: %s\n", log.RejectionReason)
	}
	fmt.Printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
}

// resolveBrandMisread attempts to resolve a misread brand name using the common patterns
func resolveBrandMisread(ocrBrand string) (string, bool) {
	normalized := strings.ToUpper(strings.TrimSpace(ocrBrand))
	// Remove extra spaces
	normalized = regexp.MustCompile(`\s+`).ReplaceAllString(normalized, " ")

	// Direct lookup
	if canonical, found := commonBrandMisreads[normalized]; found && canonical != "" {
		return canonical, true
	}

	// Try with words stripped of special chars
	strippedNormalized := regexp.MustCompile(`[^\w\s]`).ReplaceAllString(normalized, "")
	if canonical, found := commonBrandMisreads[strippedNormalized]; found && canonical != "" {
		return canonical, true
	}

	return ocrBrand, false
}

// ValidationService handles AI-powered validation of daily sales records
type ValidationService struct {
	db         *database.DB
	cache      *cache.Cache
	ocrService *OCRService
	// In-memory cache of brand aliases per tenant (refreshed periodically)
	aliasCache    map[string]map[string]string // tenantID -> aliasName -> canonicalName
	aliasCacheTTL time.Time
	// AI Provider Configuration (Priority: Fomoa → ChatGPT → Gemini)
	fomoaAPIKey    string // Primary: Fomoa (qwen2.5vl:7b)
	fomoaAPIURL    string
	fomoaModel     string
	openAIAPIKey   string // 1st Fallback: OpenAI/ChatGPT
	geminiAPIKey   string // 2nd Fallback: Gemini
	httpClient     *http.Client
}

// NewValidationService creates a new validation service
func NewValidationService(db *database.DB, cache *cache.Cache, ocrService *OCRService) *ValidationService {
	// Load AI provider configurations
	fomoaKey := os.Getenv("FOMOA_API_KEY")
	fomoaURL := os.Getenv("FOMOA_API_URL")
	if fomoaURL == "" {
		fomoaURL = "https://fomoa.cloud/api/v1/chat"
	}
	fomoaModel := os.Getenv("FOMOA_MODEL")
	if fomoaModel == "" {
		fomoaModel = "fomoa-vision-2.0"
	}
	openAIKey := os.Getenv("OPENAI_API_KEY")
	geminiKey := os.Getenv("GEMINI_API_KEY")

	// Log AI provider configuration
	fmt.Println("🤖 AI Validation Service Configuration:")
	if fomoaKey != "" {
		fmt.Printf("  ✅ PRIMARY: Fomoa (%s)\n", fomoaModel)
	} else {
		fmt.Println("  ⚠️  Fomoa not configured")
	}
	if openAIKey != "" {
		fmt.Println("  ✅ FALLBACK 1: ChatGPT (gpt-4o-mini)")
	} else {
		fmt.Println("  ⚠️  ChatGPT not configured")
	}
	if geminiKey != "" {
		fmt.Println("  ✅ FALLBACK 2: Gemini")
	} else {
		fmt.Println("  ⚠️  Gemini not configured")
	}

	return &ValidationService{
		db:            db,
		cache:         cache,
		ocrService:    ocrService,
		aliasCache:    make(map[string]map[string]string),
		fomoaAPIKey:   fomoaKey,
		fomoaAPIURL:   fomoaURL,
		fomoaModel:    fomoaModel,
		openAIAPIKey:  openAIKey,
		geminiAPIKey:  geminiKey,
		httpClient: &http.Client{
			Timeout: 120 * time.Second, // 2 minute timeout for Fomoa (qwen2.5vl is slower)
		},
	}
}

// getBrandAliases returns cached brand aliases for a tenant, refreshing if needed
func (s *ValidationService) getBrandAliases(ctx context.Context, tenantID uuid.UUID) map[string]string {
	tenantKey := tenantID.String()

	// Check if cache is still valid (5 minute TTL)
	if time.Now().Before(s.aliasCacheTTL) {
		if aliases, ok := s.aliasCache[tenantKey]; ok {
			return aliases
		}
	}

	// Load aliases from database
	var aliases []models.OCRBrandAlias
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ?", tenantID).
		Find(&aliases).Error; err != nil {
		fmt.Printf("[Validation] Warning: Failed to load brand aliases: %v\n", err)
		return make(map[string]string)
	}

	// Build alias map: normalized alias name -> canonical name
	aliasMap := make(map[string]string)
	for _, alias := range aliases {
		normalizedAlias := normalizeBrandName(alias.AliasName)
		aliasMap[normalizedAlias] = alias.CanonicalBrandName
	}

	// Cache it
	s.aliasCache[tenantKey] = aliasMap
	s.aliasCacheTTL = time.Now().Add(5 * time.Minute)

	fmt.Printf("[Validation] Loaded %d brand aliases for tenant %s\n", len(aliasMap), tenantKey)
	return aliasMap
}

// resolveAlias checks if an OCR brand name has a learned alias and returns the canonical name
func (s *ValidationService) resolveAlias(ctx context.Context, tenantID uuid.UUID, ocrBrand string) string {
	aliases := s.getBrandAliases(ctx, tenantID)
	normalizedOCR := normalizeBrandName(ocrBrand)

	if canonical, found := aliases[normalizedOCR]; found {
		fmt.Printf("[Validation] Resolved alias: '%s' -> '%s'\n", ocrBrand, canonical)
		return canonical
	}
	return ocrBrand
}

// TriggerValidation initiates OCR validation for a daily sales record
// This is called async after record creation if images are attached
func (s *ValidationService) TriggerValidation(ctx context.Context, recordID uuid.UUID, tenantID uuid.UUID) error {
	fmt.Printf("[Validation] Triggering AI validation for record %s, tenant %s\n", recordID, tenantID)

	// 1. Get the daily sales record with items and product details
	var record sharedModels.DailySalesRecord
	if err := s.db.WithContext(ctx).
		Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items").
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		First(&record).Error; err != nil {
		fmt.Printf("[Validation] Error: Failed to fetch record: %v\n", err)
		return fmt.Errorf("failed to fetch record: %w", err)
	}

	// 2. Check if images exist
	if record.ImageURLs == "" {
		fmt.Printf("[Validation] No images attached, skipping validation\n")
		return s.updateValidationStatus(ctx, recordID, tenantID, "skipped", nil)
	}

	var imageURLs []string
	if err := json.Unmarshal([]byte(record.ImageURLs), &imageURLs); err != nil {
		fmt.Printf("[Validation] Warning: Failed to parse image URLs: %v\n", err)
		return s.updateValidationStatus(ctx, recordID, tenantID, "error", nil)
	}

	if len(imageURLs) == 0 {
		fmt.Printf("[Validation] Empty image URLs array, skipping validation\n")
		return s.updateValidationStatus(ctx, recordID, tenantID, "skipped", nil)
	}

	// 3. Mark as processing
	now := time.Now()
	if err := s.db.WithContext(ctx).Model(&sharedModels.DailySalesRecord{}).
		Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Updates(map[string]interface{}{
			"validation_status":       "processing",
			"validation_triggered_at": now,
		}).Error; err != nil {
		fmt.Printf("[Validation] Error: Failed to update validation status: %v\n", err)
		return err
	}

	// 4. Create OCR batch session for validation
	userID := record.CreatedByID.String()
	shopID := record.ShopID.String()

	batchSession, err := s.ocrService.CreateBatchSession(ctx, tenantID.String(), userID, shopID, "sales_validation", len(imageURLs))
	if err != nil {
		fmt.Printf("[Validation] Error: Failed to create OCR batch session: %v\n", err)
		return s.updateValidationStatus(ctx, recordID, tenantID, "error", nil)
	}

	// 5. Process images through OCR pipeline
	if err := s.ocrService.ProcessImageBatch(ctx, batchSession.ID, imageURLs); err != nil {
		fmt.Printf("[Validation] Error: Failed to process OCR batch: %v\n", err)
		return s.updateValidationStatus(ctx, recordID, tenantID, "error", nil)
	}

	// 6. Wait for OCR to complete (with timeout)
	ocrItems, err := s.waitForOCRCompletion(ctx, batchSession.ID, 60*time.Second)
	if err != nil {
		fmt.Printf("[Validation] Error: OCR processing timed out or failed: %v\n", err)
		return s.updateValidationStatus(ctx, recordID, tenantID, "error", nil)
	}

	// 7. Compare entered data vs OCR data
	validationResult, err := s.CompareEnteredVsOCR(ctx, tenantID, record.Items, ocrItems)
	if err != nil {
		fmt.Printf("[Validation] Error: Failed to compare data: %v\n", err)
		return s.updateValidationStatus(ctx, recordID, tenantID, "error", nil)
	}

	// 8. Set OCR session ID and validation time
	ocrSessionUUID, _ := uuid.Parse(batchSession.ID)
	validationResult.OCRSessionID = batchSession.ID
	validationResult.ValidatedAt = time.Now()

	// 8.5. Check for date mismatches between receipt images and record date
	dateWarnings := s.checkReceiptDateMismatch(ctx, batchSession.ID, record.RecordDate)
	if len(dateWarnings) > 0 {
		validationResult.Warnings = append(validationResult.Warnings, dateWarnings...)
		fmt.Printf("⚠️  [Validation] DATE MISMATCH DETECTED: %d receipts have different dates\n", len(dateWarnings))
	}

	// 8.6. Generate AI-powered review suggestions ONCE and store them
	// This prevents calling ChatGPT repeatedly on every GET request
	fmt.Printf("[Validation] Generating AI summary and per-item insights...\n")
	validationResult.AISummary = s.generateAISummary(validationResult)
	validationResult.PerItemInsights = s.generatePerItemInsights(validationResult)
	// MissingItemsGrouped removed - frontend no longer displays "Missing from Entry" section
	fmt.Printf("[Validation] AI summary generated - recommendation: %s\n",
		func() string {
			if validationResult.AISummary != nil {
				return validationResult.AISummary.RecommendedAction
			}
			return "none"
		}())

	// 9. Save validation result (including AI summary)
	if err := s.saveValidationResult(ctx, recordID, tenantID, ocrSessionUUID, validationResult); err != nil {
		fmt.Printf("[Validation] Error: Failed to save validation result: %v\n", err)
		return err
	}

	// 10. Create training sample for auto-learning
	if err := s.createTrainingSample(ctx, recordID, tenantID, ocrSessionUUID, imageURLs, ocrItems, record.Items, validationResult.OverallAccuracy); err != nil {
		fmt.Printf("[Validation] Warning: Failed to create training sample: %v\n", err)
	}

	// 11. Update accuracy metrics
	if err := s.updateAccuracyMetrics(ctx, tenantID, validationResult); err != nil {
		fmt.Printf("[Validation] Warning: Failed to update accuracy metrics: %v\n", err)
	}

	// 12. Auto-learn from high-accuracy samples (industrial-grade continuous learning)
	if validationResult.OverallAccuracy >= 85.0 {
		if err := s.AutoLearnFromHighAccuracySamples(ctx, tenantID, record.Items, ocrItems, validationResult.OverallAccuracy); err != nil {
			fmt.Printf("[Validation] Warning: Failed to auto-learn from sample: %v\n", err)
		}
	}

	fmt.Printf("[Validation] Completed successfully - record: %s, accuracy: %.2f%%, matched: %d, mismatched: %d\n",
		recordID, validationResult.OverallAccuracy, validationResult.MatchedItems, validationResult.MismatchedItems)

	return nil
}

// checkReceiptDateMismatch checks if OCR receipt dates match the expected record date
func (s *ValidationService) checkReceiptDateMismatch(ctx context.Context, batchID string, recordDate time.Time) []models.ValidationWarning {
	var warnings []models.ValidationWarning

	// Get OCR sessions for this batch
	var ocrSessions []models.OCRSession
	if err := s.db.WithContext(ctx).
		Where("batch_session_id = ?", batchID).
		Where("receipt_date IS NOT NULL").
		Find(&ocrSessions).Error; err != nil {
		fmt.Printf("[Validation] Warning: Could not fetch OCR sessions for date check: %v\n", err)
		return warnings
	}

	recordDateOnly := recordDate.Format("2006-01-02")

	for _, session := range ocrSessions {
		if session.ReceiptDate == nil {
			continue
		}

		receiptDateOnly := session.ReceiptDate.Format("2006-01-02")

		// Check if dates are different (more than 1 day apart to allow for edge cases)
		daysDiff := int(recordDate.Sub(*session.ReceiptDate).Hours() / 24)
		if daysDiff < 0 {
			daysDiff = -daysDiff
		}

		if daysDiff > 1 {
			warning := models.ValidationWarning{
				Type:        "date_mismatch",
				Severity:    "warning",
				Message:     fmt.Sprintf("Receipt image date (%s) doesn't match record date (%s)", receiptDateOnly, recordDateOnly),
				Details:     "The uploaded receipt images may be from a different day. This could explain data mismatches. Please verify the correct images were uploaded.",
				RecordDate:  recordDateOnly,
				ReceiptDate: receiptDateOnly,
			}
			warnings = append(warnings, warning)
			fmt.Printf("⚠️  [Validation] Date mismatch: Receipt=%s, Record=%s (diff=%d days)\n",
				receiptDateOnly, recordDateOnly, daysDiff)
		}
	}

	return warnings
}

// waitForOCRCompletion polls for OCR completion and returns the extracted items
func (s *ValidationService) waitForOCRCompletion(ctx context.Context, batchID string, timeout time.Duration) ([]models.OCRItem, error) {
	deadline := time.Now().Add(timeout)

	for time.Now().Before(deadline) {
		session, err := s.ocrService.GetBatchSession(ctx, batchID)
		if err != nil {
			return nil, err
		}

		if session.Status == "completed" || session.Status == "partial" {
			// GetBatchSession doesn't load Items, so fetch them separately
			items, err := s.ocrService.GetBatchItems(ctx, batchID)
			if err != nil {
				fmt.Printf("[Validation] Warning: Failed to fetch OCR items: %v\n", err)
				return nil, err
			}
			fmt.Printf("[Validation] OCR completed - fetched %d items from batch %s\n", len(items), batchID)
			return items, nil
		}

		if session.Status == "failed" {
			return nil, fmt.Errorf("OCR batch session failed")
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(2 * time.Second):
			// Poll every 2 seconds
		}
	}

	return nil, fmt.Errorf("OCR processing timed out")
}

// CompareEnteredVsOCR compares manually entered items against OCR extracted items
// Provides comprehensive validation including Opening, Sale, Closing stock and price verification
func (s *ValidationService) CompareEnteredVsOCR(ctx context.Context, tenantID uuid.UUID, enteredItems []sharedModels.DailySalesItem, ocrItems []models.OCRItem) (*models.ValidationResult, error) {
	startTime := time.Now()

	result := &models.ValidationResult{
		TotalItems:      len(enteredItems),
		MatchedItems:    0,
		MismatchedItems: 0,
		ExtraOCRItems:   0,
		MissingOCRItems: 0,
		Mismatches:      []models.ValidationMismatch{},
		MatchDetails:    []models.ItemMatchDetail{},
	}

	if len(ocrItems) == 0 {
		fmt.Printf("[Validation] Warning: No OCR items to compare against\n")
		result.OverallStatus = "error"
		result.ProcessingTimeMs = time.Since(startTime).Milliseconds()
		return result, nil
	}

	// Step 1: Deduplicate OCR items (same brand+size from multiple images)
	dedupedOCRItems := s.deduplicateOCRItems(ocrItems)
	result.TotalOCRItems = len(dedupedOCRItems)
	fmt.Printf("[Validation] Deduplicated OCR items: %d -> %d\n", len(ocrItems), len(dedupedOCRItems))

	// Step 2: Use AI to match OCR brand names to actual database products
	// This handles cases where OCR reads completely wrong brand names
	aiMatches, err := s.matchOCRItemsToProducts(ctx, tenantID, dedupedOCRItems)
	if err != nil {
		fmt.Printf("[Validation] Warning: AI matching failed: %v (falling back to fuzzy matching)\n", err)
	} else if aiMatches != nil {
		fmt.Printf("[Validation] AI matched %d OCR items to database products\n", len(aiMatches))
	}

	// Pre-load brand aliases for this tenant
	brandAliases := s.getBrandAliases(ctx, tenantID)
	fmt.Printf("[Validation] Using %d learned brand aliases for matching\n", len(brandAliases))

	// Track which OCR items have been matched
	ocrMatched := make([]bool, len(dedupedOCRItems))
	totalConfidence := 0.0
	confidenceCount := 0

	// Counters for comprehensive accuracy
	quantityMatches := 0
	openingMatches := 0
	closingMatches := 0
	priceMatches := 0
	stockMathValid := 0
	matchedWithData := 0

	// For each entered item, find best matching OCR item
	for _, enteredItem := range enteredItems {
		var productName, brandName, size string
		if enteredItem.Product != nil {
			productName = enteredItem.Product.Name
			size = enteredItem.Product.Size
			if enteredItem.Product.Brand != nil {
				brandName = enteredItem.Product.Brand.Name
			}
		}

		bestMatch := s.findBestOCRMatch(enteredItem, productName, brandName, size, dedupedOCRItems, ocrMatched, brandAliases)

		// Create match detail record
		matchDetail := models.ItemMatchDetail{
			ProductID:       enteredItem.ProductID,
			ProductName:     productName,
			BrandName:       brandName,
			Size:            size,
			EnteredOpening:  enteredItem.OpeningStock,
			EnteredSale:     enteredItem.Quantity,
			EnteredClosing:  enteredItem.ClosingStock,
			EnteredPrice:    enteredItem.UnitPrice,
		}

		if bestMatch.matchedIndex >= 0 {
			ocrMatched[bestMatch.matchedIndex] = true
			ocrItem := bestMatch.ocrItem
			matchDetail.MatchStatus = "matched"
			matchDetail.MatchConfidence = bestMatch.confidence
			matchDetail.OCRBrandText = ocrItem.BrandText

			// Populate AI-matched product info if available
			// This helps the frontend display the correct product name when OCR reads wrong brand
			if aiMatches != nil {
				aiKey := fmt.Sprintf("%s|%s", strings.ToLower(ocrItem.BrandText), strings.ToLower(ocrItem.SizeText))
				if aiMatch, found := aiMatches[aiKey]; found {
					matchDetail.AIMatchedProduct = aiMatch.MatchedProduct
					matchDetail.AIMatchedBrand = aiMatch.MatchedBrand
					matchDetail.AIMatchReason = aiMatch.MatchReason
					fmt.Printf("[Validation] AI matched OCR '%s' -> Product '%s' (%s)\n",
						ocrItem.BrandText, aiMatch.MatchedProduct, aiMatch.MatchReason)
				}
			}

			// Use Total Stock (Opening + Receipt) for display, as that's what salesmen enter
			ocrTotalForDisplay := ocrItem.TotalStock
			if ocrTotalForDisplay <= 0 {
				ocrTotalForDisplay = ocrItem.OpeningStock
				if ocrItem.ReceiptQty > 0 {
					ocrTotalForDisplay += ocrItem.ReceiptQty
				}
			}
			matchDetail.OCROpening = ocrTotalForDisplay
			matchDetail.OCRSale = ocrItem.SaleQuantity
			matchDetail.OCRClosing = ocrItem.ClosingStock
			if ocrItem.SellingPrice != nil {
				matchDetail.OCRPrice = *ocrItem.SellingPrice
			}

			if ocrItem.MatchConfidence != nil {
				totalConfidence += *ocrItem.MatchConfidence
				confidenceCount++
			}

			// Comprehensive comparison
			mismatches := s.compareItemDetailsComprehensive(enteredItem, ocrItem, productName, brandName, size, bestMatch.confidence, &matchDetail)

			// Count matches for each field
			matchedWithData++
			if matchDetail.OpeningMatch {
				openingMatches++
			}
			if matchDetail.SaleMatch {
				quantityMatches++
			}
			if matchDetail.ClosingMatch {
				closingMatches++
			}
			if matchDetail.PriceMatch {
				priceMatches++
			}
			if matchDetail.StockMathValid {
				stockMathValid++
			}

			if len(mismatches) > 0 {
				result.MismatchedItems++
				result.Mismatches = append(result.Mismatches, mismatches...)
			} else {
				result.MatchedItems++
			}
		} else {
			// Entered item not found in OCR
			matchDetail.MatchStatus = "not_found"

			// Determine if this is a size-specific issue
			// Check what sizes are available in OCR data
			ocrSizesFound := make(map[string]bool)
			for _, ocrItem := range ocrItems {
				if ocrItem.SizeText != "" && ocrItem.SizeText != "-1ml" {
					ocrSizesFound[strings.ToUpper(ocrItem.SizeText)] = true
				}
			}

			enteredSizeUpper := strings.ToUpper(size)
			var issueMessage, suggestedAction string

			// Check if this is a size mismatch issue
			if len(ocrSizesFound) > 0 && enteredSizeUpper != "" {
				_, sizeFoundInOCR := ocrSizesFound[enteredSizeUpper]
				if !sizeFoundInOCR {
					// Size not found in OCR - likely missing register page
					availableSizes := make([]string, 0, len(ocrSizesFound))
					for sz := range ocrSizesFound {
						availableSizes = append(availableSizes, sz)
					}
					issueMessage = fmt.Sprintf("%s (%s) not found - uploaded images only contain: %s",
						brandName, size, strings.Join(availableSizes, ", "))
					suggestedAction = fmt.Sprintf("Upload %s register image to validate this item", size)
				} else {
					issueMessage = fmt.Sprintf("%s not found in OCR images", productName)
					suggestedAction = "Verify if this item was actually sold or if receipt image is complete"
				}
			} else {
				issueMessage = "Not found in OCR images"
				suggestedAction = "Verify if this item was actually sold or if receipt image is missing"
			}

			matchDetail.Issues = append(matchDetail.Issues, issueMessage)
			result.MissingOCRItems++
			result.Mismatches = append(result.Mismatches, models.ValidationMismatch{
				ProductID:       enteredItem.ProductID,
				ProductName:     productName,
				BrandName:       brandName,
				Size:            size,
				FieldName:       "brand",
				EnteredValue:    productName,
				OCRValue:        "NOT_FOUND_IN_OCR",
				Difference:      issueMessage,
				Severity:        "high",
				MatchConfidence: 0,
				SuggestedAction: suggestedAction,
				MismatchType:    "missing_entry",
			})
		}

		result.MatchDetails = append(result.MatchDetails, matchDetail)
	}

	// Count unmatched OCR items (items in OCR but not entered)
	// Only flag items with sale_quantity > 0 as potential issues
	// Skip items with impossible OCR values (negative closing, math errors)
	for i, matched := range ocrMatched {
		if !matched {
			ocrItem := dedupedOCRItems[i]

			// Skip flagging items with impossible OCR values
			hasImpossibleValues := ocrItem.ClosingStock < 0
			hasMathError := ocrItem.OpeningStock > 0 && ocrItem.SaleQuantity > ocrItem.OpeningStock

			if hasImpossibleValues || hasMathError {
				fmt.Printf("[Validation] Skipping 'missing entry' alert for %s - OCR has impossible values (Closing: %d, Opening: %d, Sale: %d)\n",
					ocrItem.BrandText, ocrItem.ClosingStock, ocrItem.OpeningStock, ocrItem.SaleQuantity)
				continue
			}

			// Check if this OCR item has similar numbers to any already-matched entered item
			// This catches OCR brand misreads where "Kingfisher Strong" is actually "Tuborg Strong"
			isSimilarToMatchedItem := false
			ocrNormalizedSize := normalizeSize(ocrItem.SizeText)
			for _, detail := range result.MatchDetails {
				if detail.MatchStatus == "not_found" {
					continue // Skip unmatched items
				}

				// Check if sizes match
				enteredNormalizedSize := normalizeSize(detail.Size)
				if ocrNormalizedSize != enteredNormalizedSize {
					continue
				}

				// Compare sale quantities - must be same or very close
				saleDiff := absInt(ocrItem.SaleQuantity - detail.EnteredSale)
				if saleDiff > 2 {
					continue // Too different
				}

				// Compare opening stock - allow for OCR digit errors (difference of ~5-10)
				openingDiff := absInt(ocrItem.OpeningStock - detail.EnteredOpening)
				if openingDiff > 10 && !isApproximateMissedDigit(openingDiff) {
					continue
				}

				// Compare closing stock - allow for similar differences
				closingDiff := absInt(ocrItem.ClosingStock - detail.EnteredClosing)
				if closingDiff > 10 && !isApproximateMissedDigit(closingDiff) {
					continue
				}

				// Compare price - must be same or within 10%
				priceDiff := absFloat64(ocrItem.Rate - detail.EnteredPrice)
				priceThreshold := detail.EnteredPrice * 0.1
				if priceDiff > priceThreshold && priceDiff > 20 {
					continue
				}

				// All numbers match! This is likely the same item with misread brand
				fmt.Printf("[Validation] Skipping 'missing entry' alert for %s - similar numbers to already-matched %s (Sale: %d≈%d, Opening: %d≈%d, Closing: %d≈%d, Price: %.0f≈%.0f)\n",
					ocrItem.BrandText, detail.ProductName, ocrItem.SaleQuantity, detail.EnteredSale,
					ocrItem.OpeningStock, detail.EnteredOpening, ocrItem.ClosingStock, detail.EnteredClosing,
					ocrItem.Rate, detail.EnteredPrice)
				isSimilarToMatchedItem = true
				break
			}

			if isSimilarToMatchedItem {
				continue
			}

			// Only flag as extra if sale quantity > 0 (actual sale missed)
			if ocrItem.SaleQuantity > 0 {
				result.ExtraOCRItems++

				// Reduce severity if the item might be a duplicate match or OCR error
				severity := "critical"
				suggestedAction := "URGENT: Check if salesman forgot to enter this sale"

				// If sale quantity is small (1-2 units), make it a warning not critical
				if ocrItem.SaleQuantity <= 2 {
					severity = "high"
					suggestedAction = "Check if salesman forgot to enter this sale"
				}

				result.Mismatches = append(result.Mismatches, models.ValidationMismatch{
					ProductID:       uuid.Nil,
					ProductName:     ocrItem.BrandText,
					FieldName:       "brand",
					EnteredValue:    "NOT_ENTERED",
					OCRValue:        fmt.Sprintf("%s %s (Opening: %d, Sale: %d, Closing: %d, Rate: %.2f)", ocrItem.BrandText, ocrItem.SizeText, ocrItem.OpeningStock, ocrItem.SaleQuantity, ocrItem.ClosingStock, ocrItem.Rate),
					Difference:      fmt.Sprintf("Item found in receipt with %d units sold at Rs%.0f each but not entered by salesman", ocrItem.SaleQuantity, ocrItem.Rate),
					Severity:        severity,
					MatchConfidence: 0,
					SuggestedAction: suggestedAction,
					MismatchType:    "missing_entry",
				})
			}
		}
	}

	// Calculate comprehensive accuracy metrics
	if matchedWithData > 0 {
		result.QuantityAccuracy = float64(quantityMatches) / float64(matchedWithData) * 100
		result.StockMathAccuracy = float64(stockMathValid) / float64(matchedWithData) * 100
		result.PriceAccuracy = float64(priceMatches) / float64(matchedWithData) * 100
	}

	if result.TotalItems > 0 {
		result.EntryMatchRate = float64(matchedWithData) / float64(result.TotalItems) * 100
	}

	if result.TotalOCRItems > 0 {
		result.OCRCoverageRate = float64(matchedWithData) / float64(result.TotalOCRItems) * 100
	}

	// Count error types
	for _, mm := range result.Mismatches {
		switch mm.FieldName {
		case "quantity":
			result.QuantityMismatches++
		case "opening_stock":
			result.OpeningStockMismatches++
		case "closing_stock":
			result.ClosingStockMismatches++
		case "unit_price":
			result.PriceMismatches++
		case "stock_math":
			result.StockMathErrors++
		}
	}

	// Calculate overall accuracy (weighted)
	// Entry match rate (40%) + Quantity accuracy (30%) + Stock math (20%) + Price (10%)
	if matchedWithData > 0 {
		result.OverallAccuracy = result.EntryMatchRate*0.4 + result.QuantityAccuracy*0.3 + result.StockMathAccuracy*0.2 + result.PriceAccuracy*0.1
	} else {
		result.OverallAccuracy = 0
	}

	// Set OCR confidence
	if confidenceCount > 0 {
		result.OCRConfidence = totalConfidence / float64(confidenceCount)
	}

	// Determine overall status
	if result.MismatchedItems == 0 && result.ExtraOCRItems == 0 && result.MissingOCRItems == 0 {
		result.OverallStatus = "verified"
	} else {
		result.OverallStatus = "mismatches"
	}

	result.ProcessingTimeMs = time.Since(startTime).Milliseconds()

	fmt.Printf("[Validation] Comprehensive validation complete:\n")
	fmt.Printf("  - Entered: %d, OCR: %d (dedup), Matched: %d\n", len(enteredItems), len(dedupedOCRItems), matchedWithData)
	fmt.Printf("  - Entry Match Rate: %.1f%%, Quantity Acc: %.1f%%, Stock Math: %.1f%%, Price: %.1f%%\n",
		result.EntryMatchRate, result.QuantityAccuracy, result.StockMathAccuracy, result.PriceAccuracy)
	fmt.Printf("  - Overall Accuracy: %.2f%%\n", result.OverallAccuracy)

	return result, nil
}

// deduplicateOCRItems removes duplicate OCR items from multiple images
// IMPROVED: Keeps ALL variants when values differ significantly (>20% difference)
// This allows the matching logic to find the correct OCR item that matches entered data
// Resolves brand misreads BEFORE deduplication for accurate grouping
func (s *ValidationService) deduplicateOCRItems(ocrItems []models.OCRItem) []models.OCRItem {
	// Key: resolved brand + size (use resolved brand for accurate dedup)
	// Value: list of all items with this key (to check for significant differences)
	seen := make(map[string][]models.OCRItem)

	for _, item := range ocrItems {
		// Resolve brand misread BEFORE creating the key
		resolvedBrand := item.BrandText
		if canonical, resolved := resolveBrandMisread(item.BrandText); resolved {
			resolvedBrand = canonical
		}

		key := normalizeBrandName(resolvedBrand) + "|" + normalizeSize(item.SizeText)
		seen[key] = append(seen[key], item)
	}

	result := make([]models.OCRItem, 0, len(seen))
	for key, items := range seen {
		if len(items) == 1 {
			result = append(result, items[0])
			continue
		}

		// Multiple items with same brand+size - check if values differ significantly
		// If so, keep all variants to let matching logic pick the right one
		keptItems := s.selectBestOCRVariants(items)
		for _, item := range keptItems {
			result = append(result, item)
		}
		if len(keptItems) > 1 {
			fmt.Printf("[Dedup] Kept %d variants for %s (values differ significantly)\n", len(keptItems), key)
		}
	}

	fmt.Printf("[Dedup] Reduced %d OCR items to %d after smart deduplication\n", len(ocrItems), len(result))
	return result
}

// selectBestOCRVariants selects which OCR variants to keep when multiple exist for same brand+size
// Keeps items with significantly different values (allowing matching to find correct one)
// Otherwise keeps the one with best completeness score
func (s *ValidationService) selectBestOCRVariants(items []models.OCRItem) []models.OCRItem {
	if len(items) <= 1 {
		return items
	}

	// Check if values differ significantly between items
	// If sale quantities differ by more than 50%, keep both variants
	// This handles cases where OCR extracted from different receipt pages
	var distinctItems []models.OCRItem
	for _, item := range items {
		isDistinct := true
		for _, existing := range distinctItems {
			// Check if this item is "similar enough" to an existing one
			saleDiff := absInt(item.SaleQuantity - existing.SaleQuantity)
			openingDiff := absInt(item.OpeningStock - existing.OpeningStock)
			closingDiff := absInt(item.ClosingStock - existing.ClosingStock)

			// If all key values are within 20% or differ by less than 5 units, consider them duplicates
			maxSale := max(item.SaleQuantity, existing.SaleQuantity)
			maxOpening := max(item.OpeningStock, existing.OpeningStock)

			salesSimilar := maxSale == 0 || (float64(saleDiff)/float64(maxSale) < 0.2) || saleDiff <= 3
			openingSimilar := maxOpening == 0 || (float64(openingDiff)/float64(maxOpening) < 0.2) || openingDiff <= 5
			closingSimilar := closingDiff <= 5

			if salesSimilar && openingSimilar && closingSimilar {
				// Items are similar - this is a true duplicate, keep the one with better score
				existingScore := s.scoreOCRItemCompleteness(existing)
				newScore := s.scoreOCRItemCompleteness(item)
				if existing.ClosingStock < 0 {
					existingScore -= 10
				}
				if item.ClosingStock < 0 {
					newScore -= 10
				}

				if newScore > existingScore {
					// Replace existing with new item
					for i, e := range distinctItems {
						if e.ID == existing.ID {
							distinctItems[i] = item
							break
						}
					}
				}
				isDistinct = false
				break
			}
		}

		if isDistinct {
			distinctItems = append(distinctItems, item)
		}
	}

	return distinctItems
}

// scoreOCRItemCompleteness returns a score based on how complete the OCR data is
func (s *ValidationService) scoreOCRItemCompleteness(item models.OCRItem) int {
	score := 0
	if item.OpeningStock > 0 {
		score++
	}
	if item.SaleQuantity > 0 {
		score++
	}
	if item.ClosingStock > 0 {
		score++
	}
	if item.SellingPrice != nil && *item.SellingPrice > 0 {
		score++
	}
	if item.MatchConfidence != nil && *item.MatchConfidence > 90 {
		score++
	}
	return score
}

// compareItemDetailsComprehensive performs comprehensive comparison including stock validation
func (s *ValidationService) compareItemDetailsComprehensive(enteredItem sharedModels.DailySalesItem, ocrItem models.OCRItem, productName, brandName, size string, matchConfidence float64, detail *models.ItemMatchDetail) []models.ValidationMismatch {
	var mismatches []models.ValidationMismatch

	// ============================================================================
	// PRE-PROCESSING: Auto-calculate sale quantity and validate OCR data
	// ============================================================================

	// Auto-calculate sale quantity if not provided but opening/closing are
	enteredSaleQty := enteredItem.Quantity
	if enteredSaleQty == 0 && enteredItem.OpeningStock > enteredItem.ClosingStock {
		enteredSaleQty = enteredItem.OpeningStock - enteredItem.ClosingStock
		fmt.Printf("[Validation] Auto-calculated sale: %s - Opening %d - Closing %d = Sale %d\n",
			productName, enteredItem.OpeningStock, enteredItem.ClosingStock, enteredSaleQty)
	}

	// Check if salesman's data is mathematically valid
	salesmanMathValid := false
	if enteredSaleQty > 0 {
		expectedClosing := enteredItem.OpeningStock - enteredSaleQty
		salesmanMathValid = (enteredItem.ClosingStock == expectedClosing)
	} else if enteredItem.OpeningStock > 0 && enteredItem.ClosingStock >= 0 {
		// If sale not entered, check if Opening - Closing makes sense
		calculatedSale := enteredItem.OpeningStock - enteredItem.ClosingStock
		salesmanMathValid = calculatedSale >= 0
	}

	// Check if OCR data has impossible values
	ocrHasImpossibleValues := false
	ocrImpossibleReason := ""
	if ocrItem.ClosingStock < 0 {
		ocrHasImpossibleValues = true
		ocrImpossibleReason = fmt.Sprintf("OCR closing stock is negative (%d)", ocrItem.ClosingStock)
	}
	if ocrItem.OpeningStock > 0 && ocrItem.SaleQuantity > 0 {
		expectedOCRClosing := ocrItem.OpeningStock - ocrItem.SaleQuantity
		if ocrItem.TotalStock > 0 {
			expectedOCRClosing = ocrItem.TotalStock - ocrItem.SaleQuantity
		}
		if ocrItem.ClosingStock >= 0 && absInt(ocrItem.ClosingStock-expectedOCRClosing) > 5 {
			ocrHasImpossibleValues = true
			ocrImpossibleReason = fmt.Sprintf("OCR math doesn't add up: Opening %d - Sale %d ≠ Closing %d",
				ocrItem.OpeningStock, ocrItem.SaleQuantity, ocrItem.ClosingStock)
		}
	}

	// If salesman's data is valid but OCR has issues, trust salesman
	trustSalesman := salesmanMathValid && ocrHasImpossibleValues
	if trustSalesman {
		fmt.Printf("[Validation] Trusting salesman data for %s - OCR issue: %s\n", productName, ocrImpossibleReason)
	}

	// 1. Opening Stock comparison
	// IMPORTANT: In Indian liquor registers, salesmen typically enter "Total Stock" (Opening + Receipt)
	// as their "Opening Stock" in the app. OCR extracts separate columns:
	// - OpeningStock: Column 1 (stock at start of day)
	// - ReceiptQty: Column 2 (new stock received)
	// - TotalStock: Column 3 (Opening + Receipt)
	// We should compare entered Opening with OCR TotalStock (or OpeningStock+Receipt)

	ocrTotalStock := ocrItem.TotalStock
	if ocrTotalStock <= 0 {
		// If TotalStock not populated, calculate from Opening + Receipt
		ocrTotalStock = ocrItem.OpeningStock
		if ocrItem.ReceiptQty > 0 {
			ocrTotalStock += ocrItem.ReceiptQty
		}
	}

	// Store OCR Opening for display (use total stock for comparison)
	detail.OCROpening = ocrTotalStock

	if ocrTotalStock > 0 { // Only compare if OCR has data
		detail.OpeningDiff = enteredItem.OpeningStock - ocrTotalStock
		if detail.OpeningDiff == 0 {
			detail.OpeningMatch = true
		} else {
			// Check if they might have entered just OpeningStock without Receipt
			// This is a softer mismatch - give option to match either way
			if ocrItem.ReceiptQty > 0 && enteredItem.OpeningStock == ocrItem.OpeningStock {
				// User entered just Opening without Receipt - this is still valid
				detail.OpeningMatch = true
				detail.Issues = append(detail.Issues, fmt.Sprintf("Note: OCR shows receipt of %d (Total: %d = Opening %d + Receipt %d)",
					ocrItem.ReceiptQty, ocrTotalStock, ocrItem.OpeningStock, ocrItem.ReceiptQty))
			} else {
				detail.OpeningMatch = false

				ocrDisplay := strconv.Itoa(ocrTotalStock)
				if ocrItem.ReceiptQty > 0 {
					ocrDisplay = fmt.Sprintf("%d (Opening %d + Receipt %d)", ocrTotalStock, ocrItem.OpeningStock, ocrItem.ReceiptQty)
				}
				diff := absInt(detail.OpeningDiff)

				// Detect OCR missed digits pattern (difference is approximately 1000, 100, or 10)
				// This indicates OCR likely missed a leading digit due to poor handwriting
				// Use approximate matching (±10 for 1000s, ±5 for 100s) to handle slight misreads
				isLikelyOCRMissedDigit := isApproximateMissedDigit(diff)

				// Determine severity based on context
				severity := "low"
				mismatchType := "stock_discrepancy"
				suggestedAction := "Verify stock: OCR shows Opening + Receipt = Total"

				if trustSalesman {
					// Salesman's data is valid, OCR is likely wrong
					severity = "low"
					mismatchType = "ocr_misread"
					suggestedAction = "Salesman data verified - OCR may have read incorrectly"
				} else if isLikelyOCRMissedDigit {
					// Pattern suggests OCR missed a leading digit
					severity = "low"
					mismatchType = "ocr_misread"
					suggestedAction = fmt.Sprintf("Likely OCR missed digit (diff=%d) - verify salesman entry is correct", diff)
					fmt.Printf("[Validation] Detected OCR missed digit pattern for %s: entered %d, OCR %d (diff=%d)\n",
						productName, enteredItem.OpeningStock, ocrTotalStock, diff)
				} else if diff > 10 {
					severity = "high"
				} else if diff > 3 {
					severity = "medium"
				}

				detail.Issues = append(detail.Issues, fmt.Sprintf("Opening stock mismatch: entered %d, OCR shows %s", enteredItem.OpeningStock, ocrDisplay))

				mismatches = append(mismatches, models.ValidationMismatch{
					ProductID:       enteredItem.ProductID,
					ProductName:     productName,
					BrandName:       brandName,
					Size:            size,
					FieldName:       "opening_stock",
					EnteredValue:    strconv.Itoa(enteredItem.OpeningStock),
					OCRValue:        ocrDisplay,
					Difference:      fmt.Sprintf("Opening stock differs by %d units", diff),
					Severity:        severity,
					MatchConfidence: matchConfidence,
					SuggestedAction: suggestedAction,
					MismatchType:    mismatchType,
				})
			}
		}
	} else {
		detail.OpeningMatch = true // No OCR data to compare
	}

	// 2. Sale Quantity comparison (use auto-calculated if available)
	ocrQty := ocrItem.SaleQuantity
	if ocrQty == 0 {
		ocrQty = ocrItem.Quantity
	}

	// Use auto-calculated sale quantity if original was 0
	detail.SaleDiff = enteredSaleQty - ocrQty
	if detail.SaleDiff == 0 {
		detail.SaleMatch = true
	} else if enteredSaleQty == 0 && ocrQty > 0 {
		// Salesman didn't enter sale quantity, use OCR value as reference
		detail.SaleMatch = false
		detail.Issues = append(detail.Issues, fmt.Sprintf("Sale quantity not entered, OCR shows %d", ocrQty))
		// Don't create mismatch - just note it
	} else {
		detail.SaleMatch = false
		diff := absInt(detail.SaleDiff)
		detail.Issues = append(detail.Issues, fmt.Sprintf("Sale quantity mismatch: entered %d, OCR %d", enteredSaleQty, ocrQty))

		severity := "medium"
		suggestedAction := "Verify actual bottles sold"
		mismatchType := "data_entry_error"

		// Check for OCR missed digit pattern
		isLikelyOCRMissedDigit := isApproximateMissedDigit(diff)

		if trustSalesman {
			severity = "low"
			mismatchType = "ocr_misread"
			suggestedAction = "Salesman data verified - OCR may have read incorrectly"
		} else if isLikelyOCRMissedDigit {
			severity = "low"
			mismatchType = "ocr_misread"
			suggestedAction = fmt.Sprintf("Likely OCR error (diff=%d) - verify salesman entry", diff)
		} else if diff > 5 {
			severity = "critical"
			suggestedAction = "URGENT: Major quantity discrepancy - verify physical stock count"
		} else if diff > 2 {
			severity = "high"
		} else if diff == 1 {
			severity = "low"
		}

		mismatches = append(mismatches, models.ValidationMismatch{
			ProductID:       enteredItem.ProductID,
			ProductName:     productName,
			BrandName:       brandName,
			Size:            size,
			FieldName:       "quantity",
			EnteredValue:    strconv.Itoa(enteredSaleQty),
			OCRValue:        strconv.Itoa(ocrQty),
			Difference:      fmt.Sprintf("Entered %d, OCR shows %d (diff: %d)", enteredSaleQty, ocrQty, diff),
			Severity:        severity,
			MatchConfidence: matchConfidence,
			SuggestedAction: suggestedAction,
			MismatchType:    mismatchType,
		})
	}

	// 3. Closing Stock comparison
	// Handle impossible OCR values (negative closing stock)
	if ocrItem.ClosingStock < 0 {
		// OCR returned impossible value - skip comparison, trust salesman
		detail.ClosingMatch = true // Don't flag as mismatch
		fmt.Printf("[Validation] OCR closing stock impossible (%d) for %s - trusting salesman value %d\n",
			ocrItem.ClosingStock, productName, enteredItem.ClosingStock)
		detail.Issues = append(detail.Issues, fmt.Sprintf("Note: OCR read impossible closing stock (%d) - using salesman value", ocrItem.ClosingStock))
	} else if ocrItem.ClosingStock > 0 { // Only compare if OCR has valid data
		detail.ClosingDiff = enteredItem.ClosingStock - ocrItem.ClosingStock
		if detail.ClosingDiff == 0 {
			detail.ClosingMatch = true
		} else {
			detail.ClosingMatch = false
			diff := absInt(detail.ClosingDiff)
			detail.Issues = append(detail.Issues, fmt.Sprintf("Closing stock mismatch: entered %d, OCR %d", enteredItem.ClosingStock, ocrItem.ClosingStock))

			// Detect OCR missed digits pattern
			isLikelyOCRMissedDigit := isApproximateMissedDigit(diff)

			severity := "medium"
			mismatchType := "stock_discrepancy"
			suggestedAction := "Verify closing stock matches physical count"

			if trustSalesman {
				// Salesman's data is valid, OCR is likely wrong
				severity = "low"
				mismatchType = "ocr_misread"
				suggestedAction = "Salesman data verified - OCR may have read incorrectly"
			} else if isLikelyOCRMissedDigit {
				// Pattern suggests OCR missed a leading digit
				severity = "low"
				mismatchType = "ocr_misread"
				suggestedAction = fmt.Sprintf("Likely OCR missed digit (diff=%d) - verify salesman entry", diff)
				fmt.Printf("[Validation] Detected OCR missed digit for closing stock %s: entered %d, OCR %d (diff=%d)\n",
					productName, enteredItem.ClosingStock, ocrItem.ClosingStock, diff)
			} else if diff > 10 {
				severity = "high"
			} else if diff <= 2 {
				severity = "low"
			}

			mismatches = append(mismatches, models.ValidationMismatch{
				ProductID:       enteredItem.ProductID,
				ProductName:     productName,
				BrandName:       brandName,
				Size:            size,
				FieldName:       "closing_stock",
				EnteredValue:    strconv.Itoa(enteredItem.ClosingStock),
				OCRValue:        strconv.Itoa(ocrItem.ClosingStock),
				Difference:      fmt.Sprintf("Closing stock differs by %d units", diff),
				Severity:        severity,
				MatchConfidence: matchConfidence,
				SuggestedAction: suggestedAction,
				MismatchType:    mismatchType,
			})
		}
	} else {
		detail.ClosingMatch = true
	}

	// 4. Stock Math Validation: Opening - Sale = Closing
	// Use auto-calculated sale quantity for math validation
	expectedClosing := enteredItem.OpeningStock - enteredSaleQty
	if enteredItem.ClosingStock == expectedClosing {
		detail.StockMathValid = true
	} else if enteredSaleQty == 0 && enteredItem.ClosingStock <= enteredItem.OpeningStock {
		// If no sale entered but closing <= opening, the math is valid (just no sales recorded)
		detail.StockMathValid = true
		impliedSale := enteredItem.OpeningStock - enteredItem.ClosingStock
		if impliedSale > 0 {
			detail.Issues = append(detail.Issues, fmt.Sprintf("Note: Implied sale of %d units (Opening %d - Closing %d)",
				impliedSale, enteredItem.OpeningStock, enteredItem.ClosingStock))
		}
	} else {
		detail.StockMathValid = false
		diff := absInt(enteredItem.ClosingStock - expectedClosing)
		detail.Issues = append(detail.Issues, fmt.Sprintf("Stock math error: %d - %d should equal %d, not %d",
			enteredItem.OpeningStock, enteredSaleQty, expectedClosing, enteredItem.ClosingStock))

		severity := "high"
		if diff == 1 {
			severity = "medium"
		} else if diff > 5 {
			severity = "critical"
		}

		mismatches = append(mismatches, models.ValidationMismatch{
			ProductID:       enteredItem.ProductID,
			ProductName:     productName,
			BrandName:       brandName,
			Size:            size,
			FieldName:       "stock_math",
			EnteredValue:    fmt.Sprintf("Opening(%d) - Sale(%d) = %d", enteredItem.OpeningStock, enteredSaleQty, expectedClosing),
			OCRValue:        fmt.Sprintf("Closing entered: %d", enteredItem.ClosingStock),
			Difference:      fmt.Sprintf("Stock calculation error: Expected closing %d, entered %d (diff: %d)", expectedClosing, enteredItem.ClosingStock, diff),
			Severity:        severity,
			MatchConfidence: matchConfidence,
			SuggestedAction: "Check for missing sales, theft, or data entry error",
			MismatchType:    "stock_discrepancy",
		})
	}

	// 5. Price comparison
	if ocrItem.SellingPrice != nil && *ocrItem.SellingPrice > 0 {
		ocrPrice := *ocrItem.SellingPrice
		detail.PriceDiff = enteredItem.UnitPrice - ocrPrice
		priceTolerance := enteredItem.UnitPrice * 0.05 // 5% tolerance

		if absFloat64(detail.PriceDiff) <= priceTolerance {
			detail.PriceMatch = true
		} else {
			detail.PriceMatch = false
			detail.Issues = append(detail.Issues, fmt.Sprintf("Price mismatch: entered %.2f, OCR %.2f", enteredItem.UnitPrice, ocrPrice))

			severity := "low"
			priceDiff := absFloat64(detail.PriceDiff)
			if priceDiff > enteredItem.UnitPrice*0.2 {
				severity = "high"
			} else if priceDiff > enteredItem.UnitPrice*0.1 {
				severity = "medium"
			}

			mismatches = append(mismatches, models.ValidationMismatch{
				ProductID:       enteredItem.ProductID,
				ProductName:     productName,
				BrandName:       brandName,
				Size:            size,
				FieldName:       "unit_price",
				EnteredValue:    fmt.Sprintf("%.2f", enteredItem.UnitPrice),
				OCRValue:        fmt.Sprintf("%.2f", ocrPrice),
				Difference:      fmt.Sprintf("Price differs by %.2f", priceDiff),
				Severity:        severity,
				MatchConfidence: matchConfidence,
				SuggestedAction: "Verify MRP/selling price is correct",
				MismatchType:    "data_entry_error",
			})
		}
	} else {
		detail.PriceMatch = true // No OCR price data
	}

	return mismatches
}

// matchResult holds the result of finding best OCR match
type matchResult struct {
	matchedIndex int
	confidence   float64
	ocrItem      models.OCRItem
}

// findBestOCRMatch finds the best matching OCR item for an entered item
// Uses learned brand aliases, enhanced fuzzy matching, AND data fingerprint matching for accuracy
func (s *ValidationService) findBestOCRMatch(enteredItem sharedModels.DailySalesItem, productName, brandName, size string, ocrItems []models.OCRItem, alreadyMatched []bool, brandAliases map[string]string) matchResult {
	bestMatch := matchResult{matchedIndex: -1, confidence: 0}

	// Normalize entered item details
	normalizedBrand := normalizeBrandName(brandName)
	normalizedSize := normalizeSize(size)

	// Debug logging for matching
	debugMatching := os.Getenv("DEBUG_MATCHING") == "true"
	if debugMatching {
		fmt.Printf("[Match] Looking for: Brand='%s' (%s normalized), Size='%s' (%s normalized), Qty=%d, O=%d, C=%d, P=%.0f\n",
			brandName, normalizedBrand, size, normalizedSize, enteredItem.Quantity, enteredItem.OpeningStock, enteredItem.ClosingStock, enteredItem.UnitPrice)
	}

	for i, ocrItem := range ocrItems {
		if alreadyMatched[i] {
			continue
		}

		// Calculate match confidence WITH brand alias support
		confidence := s.calculateMatchConfidenceWithAliases(normalizedBrand, normalizedSize, enteredItem.Quantity, ocrItem, brandAliases)

		// DATA FINGERPRINT MATCHING: If size matches and ALL numbers match exactly,
		// this is almost certainly the same item even if OCR read the brand name wrong
		ocrSize := normalizeSize(ocrItem.SizeText)
		sizeMatches := normalizedSize == ocrSize
		ocrPrice := ocrItem.Rate

		// Get OCR values for comparison
		ocrOpening := ocrItem.OpeningStock
		if ocrItem.TotalStock > 0 && ocrItem.TotalStock > ocrItem.OpeningStock {
			ocrOpening = ocrItem.TotalStock // Use TotalStock if available (Opening + Receipt)
		}
		ocrClosing := ocrItem.ClosingStock
		ocrSale := ocrItem.SaleQuantity

		// Check for exact numerical match (data fingerprint)
		// Skip opening check if OCR has -1 (failed to read)
		ocrOpeningValid := ocrOpening >= 0
		openingMatch := ocrOpeningValid && enteredItem.OpeningStock == ocrOpening
		closingMatch := ocrClosing >= 0 && enteredItem.ClosingStock == ocrClosing
		saleMatch := enteredItem.Quantity == ocrSale && ocrSale > 0
		priceMatch := ocrPrice > 0 && (int(enteredItem.UnitPrice) == int(ocrPrice))

		// If size matches AND at least 3 out of 4 numerical values match exactly,
		// boost confidence to 0.90 (data fingerprint match)
		// BUT: Only if there's SOME brand relationship (to avoid wrong matches)
		matchCount := 0
		validFieldCount := 4
		if openingMatch {
			matchCount++
		}
		if !ocrOpeningValid {
			validFieldCount-- // Don't count opening if OCR failed to read it
		}
		if closingMatch {
			matchCount++
		}
		if saleMatch {
			matchCount++
		}
		if priceMatch {
			matchCount++
		}

		// Match if 3/4 fields match, OR if opening was invalid and 2/3 remaining fields match
		minMatches := 3
		if validFieldCount == 3 {
			minMatches = 2 // If only 3 valid fields, require 2 matches
		}

		// Check for minimum brand relationship before allowing data fingerprint match
		// This prevents matching "Kingfisher Strong" to "Tuborg Strong" just because numbers match
		ocrBrand := normalizeBrandName(ocrItem.BrandText)
		resolvedOCRBrand := ocrBrand
		if canonical, resolved := resolveBrandMisread(ocrItem.BrandText); resolved {
			resolvedOCRBrand = normalizeBrandName(canonical)
		}

		// Calculate brand similarity - FIRST WORD must match or be very similar
		// This prevents matching "TUBORG STRONG" to "KINGFISHER STRONG" just because they share "STRONG"
		brandSimilarity := calculateStringSimilarityVal(normalizedBrand, resolvedOCRBrand)

		// Extract first words for comparison
		enteredWords := strings.Fields(normalizedBrand)
		ocrWords := strings.Fields(resolvedOCRBrand)
		firstWordMatch := false
		firstWordSimilarity := 0.0
		if len(enteredWords) > 0 && len(ocrWords) > 0 {
			firstWordSimilarity = calculateStringSimilarityVal(enteredWords[0], ocrWords[0])
			firstWordMatch = firstWordSimilarity >= 0.85 // First word must be 85%+ similar (increased from 70%)
		}

		hasBrandRelationship := firstWordMatch || // First words must match
			brandSimilarity >= 0.70 || // Or overall 70%+ similar
			strings.HasPrefix(ocrBrand, normalizedBrand[:min(4, len(normalizedBrand))]) || // Same 4-char start
			strings.HasPrefix(normalizedBrand, ocrBrand[:min(4, len(ocrBrand))]) // Same 4-char start

		// Check brand exclusions before allowing data fingerprint match
		brandsExcluded := isExcludedMatch(normalizedBrand, resolvedOCRBrand)

		if sizeMatches && matchCount >= minMatches && confidence < 0.90 && hasBrandRelationship && !brandsExcluded {
			if debugMatching {
				fmt.Printf("[Match]   -> DATA FINGERPRINT: OCR '%s' matches %d/%d fields (O:%v C:%v S:%v P:%v)\n",
					ocrItem.BrandText, matchCount, validFieldCount, openingMatch, closingMatch, saleMatch, priceMatch)
			}
			confidence = 0.90 // Strong data fingerprint match
		} else if sizeMatches && matchCount >= minMatches && brandsExcluded {
			// Brands are mutually exclusive - do NOT boost confidence despite matching fields
			if debugMatching {
				fmt.Printf("[Match]   -> BLOCKED DATA FINGERPRINT: OCR '%s' vs '%s' - brands are mutually exclusive\n",
					ocrItem.BrandText, brandName)
			}
		} else if sizeMatches && matchCount >= minMatches && !hasBrandRelationship {
			// Log why we're NOT using data fingerprint (brand too different)
			if debugMatching {
				fmt.Printf("[Match]   -> SKIPPED DATA FINGERPRINT: OCR '%s' vs '%s' - brands too different (similarity=%.2f)\n",
					ocrItem.BrandText, brandName, brandSimilarity)
			}
		}

		// Extra boost for exact sale quantity match with high quantities (strong indicator)
		// But still require brand relationship
		if sizeMatches && saleMatch && enteredItem.Quantity >= 10 && priceMatch && confidence < 0.92 && hasBrandRelationship {
			confidence = 0.92
		}

		// COLUMN MISALIGNMENT DETECTION: OCR sometimes reads columns shifted
		// If OCR's "Sale" equals entered's "Opening", and brand/size match, it's likely column confusion
		// In this case, we should still match but flag for investigation
		columnMisalignment := false
		if sizeMatches && hasBrandRelationship && confidence < 0.75 {
			// Check if OCR sale = entered opening (common misalignment)
			if ocrSale == enteredItem.OpeningStock && enteredItem.OpeningStock > 10 {
				columnMisalignment = true
				if debugMatching {
					fmt.Printf("[Match]   -> COLUMN MISALIGNMENT detected: OCR Sale(%d) = Entered Opening(%d) for '%s'\n",
						ocrSale, enteredItem.OpeningStock, ocrItem.BrandText)
				}
				// Still give it a moderate confidence - it's the right item, just wrong columns
				if confidence < 0.70 {
					confidence = 0.70
				}
			}
			// Check if OCR closing = entered opening (another common pattern)
			if ocrClosing == enteredItem.OpeningStock && enteredItem.OpeningStock > 10 {
				columnMisalignment = true
				if debugMatching {
					fmt.Printf("[Match]   -> COLUMN MISALIGNMENT detected: OCR Closing(%d) = Entered Opening(%d) for '%s'\n",
						ocrClosing, enteredItem.OpeningStock, ocrItem.BrandText)
				}
				if confidence < 0.70 {
					confidence = 0.70
				}
			}
		}
		_ = columnMisalignment // Used for debugging, prevents unused variable warning

		if debugMatching && confidence > 0.3 {
			fmt.Printf("[Match]   -> OCR Item %d: '%s' (%s), confidence=%.2f\n",
				i, ocrItem.BrandText, ocrItem.SizeText, confidence)
		}

		// Minimum threshold set to 0.65 to reduce false positive matches (increased from 0.45)
		minThreshold := 0.65

		// Log significant matching decisions for debugging (when DEBUG_MATCHING=true)
		if brandsExcluded || confidence >= minThreshold {
			decision := "REJECTED"
			reason := fmt.Sprintf("Below threshold (%.2f < %.2f)", confidence, minThreshold)
			if brandsExcluded {
				decision = "EXCLUDED"
				reason = "Brands are mutually exclusive"
			} else if confidence >= minThreshold {
				decision = "CANDIDATE"
				reason = ""
			}

			logMatchDecision(MatchDebugLog{
				EnteredBrand:     brandName,
				OCRBrand:         ocrItem.BrandText,
				ResolvedOCRBrand: resolvedOCRBrand,
				EnteredSize:      size,
				OCRSize:          ocrItem.SizeText,
				BrandSimilarity:  brandSimilarity,
				FirstWordSim:     firstWordSimilarity,
				SizeMatches:      sizeMatches,
				BrandsExcluded:   brandsExcluded,
				DataFingerprint:  sizeMatches && matchCount >= minMatches && hasBrandRelationship && !brandsExcluded,
				FinalConfidence:  confidence,
				MatchDecision:    decision,
				RejectionReason:  reason,
			})
		}

		if confidence > bestMatch.confidence && confidence >= minThreshold {
			bestMatch.matchedIndex = i
			bestMatch.confidence = confidence
			bestMatch.ocrItem = ocrItem
		}
	}

	if debugMatching {
		if bestMatch.matchedIndex >= 0 {
			fmt.Printf("[Match] ✓ Best match: '%s' with confidence %.2f\n",
				bestMatch.ocrItem.BrandText, bestMatch.confidence)
		} else {
			fmt.Printf("[Match] ✗ No match found for '%s'\n", brandName)
		}
	}

	// Log final match decision
	if bestMatch.matchedIndex >= 0 {
		logMatchDecision(MatchDebugLog{
			EnteredBrand:    brandName,
			OCRBrand:        bestMatch.ocrItem.BrandText,
			EnteredSize:     size,
			OCRSize:         bestMatch.ocrItem.SizeText,
			FinalConfidence: bestMatch.confidence,
			MatchDecision:   "MATCHED",
		})
	}

	return bestMatch
}

// calculateMatchConfidenceWithAliases calculates how well an entered item matches an OCR item
// Uses learned brand aliases and improved weighting for accuracy
func (s *ValidationService) calculateMatchConfidenceWithAliases(enteredBrand, enteredSize string, enteredQty int, ocrItem models.OCRItem, brandAliases map[string]string) float64 {
	// Weights: Brand (50%), Size (30%), Quantity (20%)
	// Size is critical - 90ML vs 750ML are completely different products
	brandWeight := 0.50
	sizeWeight := 0.30
	qtyWeight := 0.20

	// 1. Brand name matching with alias resolution
	ocrBrand := normalizeBrandName(ocrItem.BrandText)

	// First, check hardcoded common misread patterns (e.g., "God Father" -> "KINGFISHER STRONG")
	resolvedBrand := ocrBrand
	if canonical, resolved := resolveBrandMisread(ocrItem.BrandText); resolved {
		resolvedBrand = normalizeBrandName(canonical)
		fmt.Printf("[Match] Resolved brand misread: '%s' -> '%s'\n", ocrItem.BrandText, canonical)
	}

	// Then check database learned aliases
	if resolvedBrand == ocrBrand { // Only if not already resolved
		if canonical, found := brandAliases[ocrBrand]; found {
			resolvedBrand = normalizeBrandName(canonical)
		}
	}

	// Calculate similarity with resolved brand
	brandSimilarity := calculateStringSimilarityVal(enteredBrand, resolvedBrand)

	// If alias didn't help, try direct comparison too
	if brandSimilarity < 0.9 {
		directSimilarity := calculateStringSimilarityVal(enteredBrand, ocrBrand)
		if directSimilarity > brandSimilarity {
			brandSimilarity = directSimilarity
		}
	}

	// Brand score calculation with smoother curve
	brandScore := 0.0
	if brandSimilarity >= 0.95 {
		brandScore = 1.0 // Perfect/near-perfect match
	} else if brandSimilarity >= 0.85 {
		brandScore = 0.9 // Strong match
	} else if brandSimilarity >= 0.75 {
		brandScore = 0.75 // Good match
	} else if brandSimilarity >= 0.60 {
		brandScore = 0.5 // Partial match
	} else if brandSimilarity >= 0.45 {
		brandScore = 0.3 // Weak match
	}
	// Below 0.45 = no score

	// 2. Size matching (30% weight) - CRITICAL for correct product identification
	ocrSize := normalizeSize(ocrItem.SizeText)
	sizeScore := 0.0
	if enteredSize == ocrSize {
		sizeScore = 1.0 // Exact match
	} else {
		// Extract numeric value from size for comparison
		enteredML := extractMLValue(enteredSize)
		ocrML := extractMLValue(ocrSize)
		if enteredML > 0 && ocrML > 0 {
			if enteredML == ocrML {
				sizeScore = 1.0 // Same ML value
			} else {
				// Different size = different product, heavily penalize
				sizeScore = 0.0
			}
		} else if strings.Contains(enteredSize, ocrSize) || strings.Contains(ocrSize, enteredSize) {
			sizeScore = 0.3 // Partial match
		}
	}

	// 3. Quantity proximity (20% weight) - use sale quantity from OCR
	ocrQty := ocrItem.SaleQuantity
	if ocrQty == 0 {
		ocrQty = ocrItem.Quantity // Fallback to closing quantity
	}

	qtyScore := 0.0
	if enteredQty == ocrQty {
		qtyScore = 1.0
	} else {
		qtyDiff := absInt(enteredQty - ocrQty)
		if qtyDiff <= 1 {
			qtyScore = 0.8
		} else if qtyDiff <= 3 {
			qtyScore = 0.5
		} else if qtyDiff <= 5 {
			qtyScore = 0.2
		}
	}

	// Calculate weighted score
	finalScore := (brandScore * brandWeight) + (sizeScore * sizeWeight) + (qtyScore * qtyWeight)

	// If size doesn't match at all, cap the score at 0.4 (they're different products)
	if sizeScore == 0 && enteredSize != "" && ocrSize != "" {
		finalScore = min(finalScore, 0.4)
	}

	return finalScore
}

// extractMLValue extracts the numeric ML value from a size string
func extractMLValue(size string) int {
	// Match patterns like "90ML", "750 ML", "180ml"
	re := regexp.MustCompile(`(\d+)\s*[Mm][Ll]`)
	matches := re.FindStringSubmatch(size)
	if len(matches) >= 2 {
		val, _ := strconv.Atoi(matches[1])
		return val
	}
	return 0
}

// compareItemDetails compares entered item details with matched OCR item
func (s *ValidationService) compareItemDetails(enteredItem sharedModels.DailySalesItem, ocrItem models.OCRItem, productName, brandName, size string, matchConfidence float64) []models.ValidationMismatch {
	var mismatches []models.ValidationMismatch

	// Compare quantity
	ocrQty := ocrItem.SaleQuantity
	if ocrQty == 0 {
		ocrQty = ocrItem.Quantity
	}

	if enteredItem.Quantity != ocrQty {
		severity := "medium"
		diff := absInt(enteredItem.Quantity - ocrQty)
		if diff > 5 {
			severity = "high"
		} else if diff <= 1 {
			severity = "low"
		}

		mismatches = append(mismatches, models.ValidationMismatch{
			ProductID:       enteredItem.ProductID,
			ProductName:     productName,
			BrandName:       brandName,
			Size:            size,
			FieldName:       "quantity",
			EnteredValue:    strconv.Itoa(enteredItem.Quantity),
			OCRValue:        strconv.Itoa(ocrQty),
			Difference:      fmt.Sprintf("Entered %d, OCR found %d (diff: %d)", enteredItem.Quantity, ocrQty, diff),
			Severity:        severity,
			MatchConfidence: matchConfidence,
			SuggestedAction: "Verify actual bottles sold",
		})
	}

	// Compare price if available in OCR
	if ocrItem.SellingPrice != nil && *ocrItem.SellingPrice > 0 {
		ocrPrice := *ocrItem.SellingPrice
		priceDiff := absFloat64(enteredItem.UnitPrice - ocrPrice)
		priceTolerance := enteredItem.UnitPrice * 0.05 // 5% tolerance

		if priceDiff > priceTolerance {
			severity := "low"
			if priceDiff > enteredItem.UnitPrice*0.1 {
				severity = "medium"
			}
			if priceDiff > enteredItem.UnitPrice*0.2 {
				severity = "high"
			}

			mismatches = append(mismatches, models.ValidationMismatch{
				ProductID:       enteredItem.ProductID,
				ProductName:     productName,
				BrandName:       brandName,
				Size:            size,
				FieldName:       "unit_price",
				EnteredValue:    fmt.Sprintf("%.2f", enteredItem.UnitPrice),
				OCRValue:        fmt.Sprintf("%.2f", ocrPrice),
				Difference:      fmt.Sprintf("Entered %.2f, OCR found %.2f (diff: %.2f)", enteredItem.UnitPrice, ocrPrice, priceDiff),
				Severity:        severity,
				MatchConfidence: matchConfidence,
				SuggestedAction: "Verify MRP/selling price",
			})
		}
	}

	return mismatches
}

// updateValidationStatus updates the validation status of a record
func (s *ValidationService) updateValidationStatus(ctx context.Context, recordID, tenantID uuid.UUID, status string, result *models.ValidationResult) error {
	updates := map[string]interface{}{
		"validation_status": status,
	}

	if status == "verified" || status == "mismatches" {
		now := time.Now()
		updates["validated_at"] = now
	}

	return s.db.WithContext(ctx).Model(&sharedModels.DailySalesRecord{}).
		Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Updates(updates).Error
}

// saveValidationResult saves the full validation result to the record
func (s *ValidationService) saveValidationResult(ctx context.Context, recordID, tenantID, ocrSessionID uuid.UUID, result *models.ValidationResult) error {
	resultJSON, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("failed to marshal validation result: %w", err)
	}

	resultStr := string(resultJSON)
	now := time.Now()

	return s.db.WithContext(ctx).Model(&sharedModels.DailySalesRecord{}).
		Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Updates(map[string]interface{}{
			"ocr_session_id":    ocrSessionID,
			"validation_status": result.OverallStatus,
			"validation_result": resultStr,
			"validated_at":      now,
		}).Error
}

// GetValidationResult retrieves the validation result for a record
func (s *ValidationService) GetValidationResult(ctx context.Context, recordID, tenantID uuid.UUID) (*models.ValidationResult, error) {
	var record sharedModels.DailySalesRecord
	if err := s.db.WithContext(ctx).
		Select("validation_status", "validation_result", "validated_at", "ocr_session_id").
		Where("id = ? AND tenant_id = ?", recordID, tenantID).
		First(&record).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("record not found")
		}
		return nil, err
	}

	if record.ValidationResult == nil || *record.ValidationResult == "" {
		// If there's an OCR session but no validation result, trigger validation
		if record.OCRSessionID != nil && *record.OCRSessionID != uuid.Nil {
			fmt.Printf("[Validation] No validation result but OCR session exists, triggering validation for record %s\n", recordID)
			if err := s.TriggerValidation(ctx, recordID, tenantID); err != nil {
				fmt.Printf("[Validation] Warning: Auto-trigger failed: %v\n", err)
				// Return status-only response as fallback
				return &models.ValidationResult{
					OverallStatus: record.ValidationStatus,
				}, nil
			}
			// Re-fetch the record with the new validation result
			if err := s.db.WithContext(ctx).
				Select("validation_status", "validation_result", "validated_at", "ocr_session_id").
				Where("id = ? AND tenant_id = ?", recordID, tenantID).
				First(&record).Error; err != nil {
				return nil, err
			}
			// If still no result, return status-only
			if record.ValidationResult == nil || *record.ValidationResult == "" {
				return &models.ValidationResult{
					OverallStatus: record.ValidationStatus,
				}, nil
			}
		} else {
			// No OCR session, return status-only response
			return &models.ValidationResult{
				OverallStatus: record.ValidationStatus,
			}, nil
		}
	}

	var result models.ValidationResult
	if err := json.Unmarshal([]byte(*record.ValidationResult), &result); err != nil {
		return nil, fmt.Errorf("failed to parse validation result: %w", err)
	}

	// AI summary is now stored with the validation result during TriggerValidation
	// Only regenerate if missing (for backwards compatibility with old records)
	if result.AISummary == nil {
		fmt.Printf("[Validation] AI summary missing, regenerating for backwards compatibility\n")
		result.AISummary = s.generateAISummary(&result)
		result.PerItemInsights = s.generatePerItemInsights(&result)
		// MissingItemsGrouped removed - frontend no longer displays "Missing from Entry" section
	}

	// Clear MissingItemsGrouped for old records (frontend doesn't use it anymore)
	result.MissingItemsGrouped = nil

	return &result, nil
}

// ConfirmValidation marks validation as confirmed by manager and saves corrections for learning
func (s *ValidationService) ConfirmValidation(ctx context.Context, recordID, tenantID, userID uuid.UUID, req models.ConfirmValidationRequest) error {
	now := time.Now()
	updates := map[string]interface{}{
		"validation_confirmed": true,
		"confirmed_by_id":      userID,
		"confirmed_at":         now,
	}

	if req.Notes != "" {
		updates["feedback_notes"] = req.Notes
	}

	if err := s.db.WithContext(ctx).Model(&sharedModels.DailySalesRecord{}).
		Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Updates(updates).Error; err != nil {
		return err
	}

	// If corrections were provided, save them for learning
	if len(req.Corrections) > 0 {
		if err := s.processCorrectionsForLearning(ctx, recordID, tenantID, req.Corrections); err != nil {
			fmt.Printf("[Validation] Warning: Failed to process corrections for learning: %v\n", err)
		}
	}

	// Mark training sample as verified
	if err := s.db.WithContext(ctx).Model(&models.OCRTrainingSample{}).
		Where("daily_sales_record_id = ? AND tenant_id = ?", recordID, tenantID).
		Updates(map[string]interface{}{
			"is_verified": true,
			"verified_at": now,
		}).Error; err != nil {
		fmt.Printf("[Validation] Warning: Failed to mark training sample as verified: %v\n", err)
	}

	fmt.Printf("[Validation] Confirmed by manager - record: %s, is_accurate: %v, corrections: %d\n",
		recordID, req.IsAccurate, len(req.Corrections))

	return nil
}

// createTrainingSample stores data for auto-learning
func (s *ValidationService) createTrainingSample(ctx context.Context, recordID, tenantID, ocrSessionID uuid.UUID, imageURLs []string, ocrItems []models.OCRItem, enteredItems []sharedModels.DailySalesItem, accuracy float64) error {
	// Serialize OCR items
	ocrJSON, err := json.Marshal(ocrItems)
	if err != nil {
		return err
	}

	// Serialize entered items (ground truth)
	enteredJSON, err := json.Marshal(enteredItems)
	if err != nil {
		return err
	}

	// Calculate detailed accuracy metrics
	brandAccuracy := s.calculateBrandAccuracy(enteredItems, ocrItems)
	quantityAccuracy := s.calculateQuantityAccuracy(enteredItems, ocrItems)
	priceAccuracy := s.calculatePriceAccuracy(enteredItems, ocrItems)

	// Create hash for first image (for deduplication)
	var imageHash string
	if len(imageURLs) > 0 {
		hash := sha256.Sum256([]byte(imageURLs[0]))
		imageHash = hex.EncodeToString(hash[:])
	}

	sample := models.OCRTrainingSample{
		ID:                 uuid.New(),
		TenantID:           tenantID,
		DailySalesRecordID: &recordID,
		OCRSessionID:       &ocrSessionID,
		ImageURL:           imageURLs[0], // Store first image
		ImageHash:          imageHash,
		OCRExtractedItems:  ocrJSON,
		VerifiedItems:      enteredJSON,
		OverallAccuracy:    accuracy,
		BrandMatchAccuracy: brandAccuracy,
		QuantityAccuracy:   quantityAccuracy,
		PriceAccuracy:      priceAccuracy,
		IsVerified:         false, // Will be marked true when manager confirms
	}

	// Use ON CONFLICT to handle duplicates
	if err := s.db.WithContext(ctx).Create(&sample).Error; err != nil {
		// Ignore duplicate key errors
		if strings.Contains(err.Error(), "duplicate key") {
			fmt.Printf("[Validation] Training sample already exists, skipping\n")
			return nil
		}
		return err
	}

	fmt.Printf("[Validation] Created training sample - id: %s, accuracy: %.2f%%, brand_accuracy: %.2f%%\n",
		sample.ID, accuracy, brandAccuracy)

	return nil
}

// updateAccuracyMetrics updates daily aggregated accuracy metrics
func (s *ValidationService) updateAccuracyMetrics(ctx context.Context, tenantID uuid.UUID, result *models.ValidationResult) error {
	today := time.Now().Truncate(24 * time.Hour)

	// Try to update existing record
	updateResult := s.db.WithContext(ctx).Model(&models.OCRAccuracyMetric{}).
		Where("tenant_id = ? AND metric_date = ?", tenantID, today).
		Updates(map[string]interface{}{
			"total_validations": gorm.Expr("total_validations + 1"),
			"auto_verified":     gorm.Expr("CASE WHEN ? = 'verified' THEN auto_verified + 1 ELSE auto_verified END", result.OverallStatus),
			"required_correction": gorm.Expr("CASE WHEN ? = 'mismatches' THEN required_correction + 1 ELSE required_correction END", result.OverallStatus),
			"avg_overall_accuracy": gorm.Expr("(avg_overall_accuracy * total_validations + ?) / (total_validations + 1)", result.OverallAccuracy),
		})

	if updateResult.RowsAffected == 0 {
		// Create new record for today
		metric := models.OCRAccuracyMetric{
			ID:                 uuid.New(),
			TenantID:           tenantID,
			MetricDate:         today,
			TotalValidations:   1,
			AutoVerified:       0,
			RequiredCorrection: 0,
			AvgOverallAccuracy: result.OverallAccuracy,
		}

		if result.OverallStatus == "verified" {
			metric.AutoVerified = 1
		} else if result.OverallStatus == "mismatches" {
			metric.RequiredCorrection = 1
		}

		return s.db.WithContext(ctx).Create(&metric).Error
	}

	return updateResult.Error
}

// GetAccuracyDashboard returns accuracy metrics for dashboard
func (s *ValidationService) GetAccuracyDashboard(ctx context.Context, tenantID uuid.UUID) (*models.AccuracyDashboard, error) {
	dashboard := &models.AccuracyDashboard{}

	// Get totals
	var totals struct {
		TotalValidations   int64
		AutoVerified       int64
		RequiredCorrection int64
		AvgAccuracy        float64
	}

	if err := s.db.WithContext(ctx).Model(&models.OCRAccuracyMetric{}).
		Where("tenant_id = ?", tenantID).
		Select(`
			COALESCE(SUM(total_validations), 0) as total_validations,
			COALESCE(SUM(auto_verified), 0) as auto_verified,
			COALESCE(SUM(required_correction), 0) as required_correction,
			COALESCE(AVG(avg_overall_accuracy), 0) as avg_accuracy
		`).
		Scan(&totals).Error; err != nil {
		return nil, err
	}

	dashboard.TotalValidations = int(totals.TotalValidations)
	dashboard.AutoVerifiedCount = int(totals.AutoVerified)
	if dashboard.TotalValidations > 0 {
		dashboard.AutoVerifiedRate = float64(dashboard.AutoVerifiedCount) / float64(dashboard.TotalValidations) * 100
	}
	dashboard.AvgOverallAccuracy = totals.AvgAccuracy

	// Get last 30 days trend
	var trendData []struct {
		MetricDate time.Time `gorm:"column:metric_date"`
		Accuracy   float64   `gorm:"column:avg_overall_accuracy"`
		Count      int       `gorm:"column:total_validations"`
	}

	thirtyDaysAgo := time.Now().AddDate(0, 0, -30)
	if err := s.db.WithContext(ctx).Model(&models.OCRAccuracyMetric{}).
		Where("tenant_id = ? AND metric_date >= ?", tenantID, thirtyDaysAgo).
		Select("metric_date, avg_overall_accuracy, total_validations").
		Order("metric_date ASC").
		Scan(&trendData).Error; err != nil {
		return nil, err
	}

	dashboard.AccuracyTrend = make([]models.AccuracyPoint, len(trendData))
	for i, d := range trendData {
		dashboard.AccuracyTrend[i] = models.AccuracyPoint{
			Date:     d.MetricDate.Format("2006-01-02"),
			Accuracy: d.Accuracy,
			Count:    d.Count,
		}
	}

	// Get training samples count
	var sampleCount int64
	s.db.WithContext(ctx).Model(&models.OCRTrainingSample{}).
		Where("tenant_id = ? AND is_verified = true", tenantID).
		Count(&sampleCount)
	dashboard.TrainingSamplesCount = int(sampleCount)

	return dashboard, nil
}

// processCorrectionsForLearning processes manager corrections and stores them as brand aliases
func (s *ValidationService) processCorrectionsForLearning(ctx context.Context, recordID, tenantID uuid.UUID, corrections []models.ValidationCorrection) error {
	for _, correction := range corrections {
		// For brand corrections, create alias
		if correction.FieldName == "brand" {
			alias := models.OCRBrandAlias{
				ID:                 uuid.New(),
				TenantID:           tenantID,
				CanonicalBrandName: correction.CorrectedValue,
				ProductID:          &correction.ProductID,
				AliasName:          correction.OriginalValue,
				OccurrenceCount:    1,
				ConfidenceScore:    100.0,
				Source:             "user_correction",
			}

			// Upsert alias
			if err := s.db.WithContext(ctx).
				Where("tenant_id = ? AND alias_name = ?", tenantID, correction.OriginalValue).
				Assign(map[string]interface{}{
					"occurrence_count": gorm.Expr("occurrence_count + 1"),
					"last_used_at":     time.Now(),
				}).
				FirstOrCreate(&alias).Error; err != nil {
				fmt.Printf("[Validation] Warning: Failed to save brand alias %s: %v\n", correction.OriginalValue, err)
			}
		}
	}

	return nil
}

// Helper functions for accuracy calculations
func (s *ValidationService) calculateBrandAccuracy(enteredItems []sharedModels.DailySalesItem, ocrItems []models.OCRItem) float64 {
	if len(enteredItems) == 0 {
		return 100.0
	}

	matches := 0
	for _, entered := range enteredItems {
		brandName := ""
		if entered.Product != nil && entered.Product.Brand != nil {
			brandName = entered.Product.Brand.Name
		}
		normalizedBrand := normalizeBrandName(brandName)

		for _, ocr := range ocrItems {
			ocrBrand := normalizeBrandName(ocr.BrandText)
			if calculateStringSimilarityVal(normalizedBrand, ocrBrand) >= 0.7 {
				matches++
				break
			}
		}
	}

	return float64(matches) / float64(len(enteredItems)) * 100
}

func (s *ValidationService) calculateQuantityAccuracy(enteredItems []sharedModels.DailySalesItem, ocrItems []models.OCRItem) float64 {
	if len(enteredItems) == 0 {
		return 100.0
	}

	exactMatches := 0
	for _, entered := range enteredItems {
		for _, ocr := range ocrItems {
			ocrQty := ocr.SaleQuantity
			if ocrQty == 0 {
				ocrQty = ocr.Quantity
			}
			if entered.Quantity == ocrQty {
				exactMatches++
				break
			}
		}
	}

	return float64(exactMatches) / float64(len(enteredItems)) * 100
}

func (s *ValidationService) calculatePriceAccuracy(enteredItems []sharedModels.DailySalesItem, ocrItems []models.OCRItem) float64 {
	if len(enteredItems) == 0 {
		return 100.0
	}

	priceMatches := 0
	priceComparisons := 0

	for _, entered := range enteredItems {
		for _, ocr := range ocrItems {
			if ocr.SellingPrice != nil && *ocr.SellingPrice > 0 {
				priceComparisons++
				priceDiff := absFloat64(entered.UnitPrice - *ocr.SellingPrice)
				tolerance := entered.UnitPrice * 0.05 // 5% tolerance
				if priceDiff <= tolerance {
					priceMatches++
				}
				break
			}
		}
	}

	if priceComparisons == 0 {
		return 100.0 // No prices to compare
	}

	return float64(priceMatches) / float64(priceComparisons) * 100
}

// Utility functions
func normalizeBrandName(name string) string {
	name = strings.ToUpper(strings.TrimSpace(name))
	// Remove common prefixes/suffixes
	name = regexp.MustCompile(`\s+`).ReplaceAllString(name, " ")
	// Remove special characters except spaces
	name = regexp.MustCompile(`[^\w\s]`).ReplaceAllString(name, "")
	return name
}

func normalizeSize(size string) string {
	size = strings.ToUpper(strings.TrimSpace(size))
	// Standardize ML/ml
	size = strings.ReplaceAll(size, "ml", "ML")
	size = strings.ReplaceAll(size, "Ml", "ML")
	// Remove spaces between number and ML
	size = regexp.MustCompile(`(\d+)\s*ML`).ReplaceAllString(size, "${1}ML")
	return size
}

// calculateStringSimilarityVal uses enhanced similarity with Levenshtein distance
// and word-based matching for better brand name comparison
func calculateStringSimilarityVal(s1, s2 string) float64 {
	// Normalize both strings for comparison
	s1 = strings.ToUpper(strings.TrimSpace(s1))
	s2 = strings.ToUpper(strings.TrimSpace(s2))

	// Exact match
	if s1 == s2 {
		return 1.0
	}
	if len(s1) == 0 || len(s2) == 0 {
		return 0.0
	}

	// Method 1: Levenshtein distance ratio
	levenshteinSim := levenshteinSimilarity(s1, s2)

	// Method 2: Word-based Jaccard similarity
	words1 := strings.Fields(s1)
	words2 := strings.Fields(s2)

	if len(words1) == 0 || len(words2) == 0 {
		return levenshteinSim
	}

	// Count word matches (including partial matches)
	matchedWords := 0
	for _, w1 := range words1 {
		bestMatch := 0.0
		for _, w2 := range words2 {
			// Check exact match
			if w1 == w2 {
				bestMatch = 1.0
				break
			}
			// Check if one contains the other
			if strings.Contains(w1, w2) || strings.Contains(w2, w1) {
				sim := float64(min(len(w1), len(w2))) / float64(max(len(w1), len(w2)))
				if sim > bestMatch {
					bestMatch = sim
				}
			}
		}
		if bestMatch >= 0.8 {
			matchedWords++
		}
	}

	totalWords := max(len(words1), len(words2))
	wordSimilarity := float64(matchedWords) / float64(totalWords)

	// Combine both methods - weighted average
	// Levenshtein is better for typos, word-based for reordering
	combined := (levenshteinSim*0.4 + wordSimilarity*0.6)

	return combined
}

// levenshteinSimilarity calculates similarity using Levenshtein distance
func levenshteinSimilarity(s1, s2 string) float64 {
	if len(s1) == 0 && len(s2) == 0 {
		return 1.0
	}
	if len(s1) == 0 || len(s2) == 0 {
		return 0.0
	}

	// Calculate Levenshtein distance
	d := levenshteinDistance(s1, s2)

	// Convert distance to similarity (0.0 to 1.0)
	maxLen := max(len(s1), len(s2))
	return 1.0 - (float64(d) / float64(maxLen))
}

// NOTE: levenshteinDistance is defined in ocr_service.go and shared

func absInt(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func absFloat64(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

// isApproximateMissedDigit detects if a difference is likely due to OCR missing leading digits
// Uses approximate matching to handle slight misreads (e.g., 995 ≈ 1000, 198 ≈ 200)
// This handles common OCR errors where handwriting causes both missed digits AND slight misreads
func isApproximateMissedDigit(diff int) bool {
	// Exact matches for common patterns
	exactMatches := []int{10, 20, 30, 40, 50, 100, 200, 300, 400, 500, 1000, 2000, 3000, 4000, 5000}
	for _, m := range exactMatches {
		if diff == m {
			return true
		}
	}

	// Approximate matches with tolerance
	// For 1000s: allow ±15 (e.g., 985-1015 matches 1000)
	// For 100s: allow ±10 (e.g., 90-110 matches 100)
	// For 10s: allow ±3 (e.g., 7-13 matches 10)
	approximateRanges := []struct {
		target    int
		tolerance int
	}{
		{1000, 15}, {2000, 15}, {3000, 15}, {4000, 15}, {5000, 15},
		{100, 10}, {200, 10}, {300, 10}, {400, 10}, {500, 10},
		{600, 10}, {700, 10}, {800, 10}, {900, 10},
		{10, 3}, {20, 3}, {30, 3}, {40, 3}, {50, 3},
	}

	for _, r := range approximateRanges {
		if diff >= r.target-r.tolerance && diff <= r.target+r.tolerance {
			return true
		}
	}

	return false
}

// =============================================================================
// INDUSTRIAL-GRADE AUTO-LEARNING ENHANCEMENTS
// =============================================================================

// AutoLearnFromHighAccuracySamples automatically creates brand aliases from
// high-accuracy validation results without requiring explicit manager corrections.
// This enables continuous learning and improvement of OCR accuracy.
func (s *ValidationService) AutoLearnFromHighAccuracySamples(ctx context.Context, tenantID uuid.UUID, enteredItems []sharedModels.DailySalesItem, ocrItems []models.OCRItem, overallAccuracy float64) error {
	// Only auto-learn from high accuracy samples (>= 85%)
	if overallAccuracy < 85.0 {
		return nil
	}

	fmt.Printf("[AutoLearn] Processing high-accuracy sample (%.2f%%) for auto-learning\n", overallAccuracy)

	aliasesCreated := 0
	for _, entered := range enteredItems {
		if entered.Product == nil || entered.Product.Brand == nil {
			continue
		}

		canonicalBrand := entered.Product.Brand.Name
		normalizedCanonical := normalizeBrandName(canonicalBrand)

		// Find matching OCR item
		for _, ocr := range ocrItems {
			ocrBrand := normalizeBrandName(ocr.BrandText)
			similarity := calculateStringSimilarityVal(normalizedCanonical, ocrBrand)

			// If good match but not exact, create an alias for future learning
			if similarity >= 0.75 && similarity < 1.0 && ocrBrand != normalizedCanonical {
				// Calculate confidence based on similarity and OCR confidence
				confidence := similarity * 100
				if ocr.MatchConfidence != nil && *ocr.MatchConfidence > 0 {
					confidence = (confidence + *ocr.MatchConfidence) / 2
				}

				alias := models.OCRBrandAlias{
					ID:                 uuid.New(),
					TenantID:           tenantID,
					CanonicalBrandName: canonicalBrand,
					AliasName:          ocr.BrandText, // Store original OCR text
					OccurrenceCount:    1,
					ConfidenceScore:    confidence,
					Source:             "auto_learned",
				}

				// Upsert - increment count if exists
				result := s.db.WithContext(ctx).
					Where("tenant_id = ? AND alias_name = ?", tenantID, ocr.BrandText).
					Assign(map[string]interface{}{
						"occurrence_count":    gorm.Expr("occurrence_count + 1"),
						"confidence_score":    gorm.Expr("GREATEST(confidence_score, ?)", confidence),
						"last_used_at":        time.Now(),
						"canonical_brand_name": canonicalBrand,
					}).
					FirstOrCreate(&alias)

				if result.Error == nil {
					aliasesCreated++
				}
				break
			}
		}
	}

	if aliasesCreated > 0 {
		fmt.Printf("[AutoLearn] Created/updated %d brand aliases from high-accuracy sample\n", aliasesCreated)
		// Invalidate alias cache to pick up new aliases
		s.aliasCacheTTL = time.Time{}
	}

	return nil
}

// FuzzyMatchBrandWithTrigram uses PostgreSQL trigram similarity for fuzzy brand matching
// This provides more accurate matching for OCR text with typos or variations
func (s *ValidationService) FuzzyMatchBrandWithTrigram(ctx context.Context, tenantID uuid.UUID, ocrBrandText string, minSimilarity float64) (*models.OCRBrandAlias, error) {
	var alias models.OCRBrandAlias

	// Use trigram similarity index for fuzzy matching
	query := `
		SELECT * FROM ocr_brand_aliases
		WHERE tenant_id = $1
		AND similarity(alias_name, $2) > $3
		ORDER BY similarity(alias_name, $2) DESC, occurrence_count DESC
		LIMIT 1
	`

	if err := s.db.WithContext(ctx).Raw(query, tenantID, ocrBrandText, minSimilarity).Scan(&alias).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}

	if alias.ID == uuid.Nil {
		return nil, nil
	}

	return &alias, nil
}

// ProcessBatchLearning processes unverified training samples and extracts learning patterns
// This should be run periodically (e.g., daily) to improve OCR accuracy over time
func (s *ValidationService) ProcessBatchLearning(ctx context.Context, tenantID uuid.UUID) (*BatchLearningResult, error) {
	result := &BatchLearningResult{
		ProcessedSamples:   0,
		NewAliasesCreated:  0,
		AccuracyImprovement: 0,
	}

	// Get unprocessed high-accuracy training samples
	var samples []models.OCRTrainingSample
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND is_used_for_training = false AND overall_accuracy >= 85", tenantID).
		Order("created_at DESC").
		Limit(100). // Process in batches
		Find(&samples).Error; err != nil {
		return nil, err
	}

	if len(samples) == 0 {
		fmt.Printf("[BatchLearning] No unprocessed samples found for tenant %s\n", tenantID)
		return result, nil
	}

	fmt.Printf("[BatchLearning] Processing %d training samples for tenant %s\n", len(samples), tenantID)

	batchID := fmt.Sprintf("batch_%s_%d", tenantID.String()[:8], time.Now().Unix())
	aliasPatterns := make(map[string]map[string]int) // ocrText -> canonicalBrand -> count

	for _, sample := range samples {
		// Parse OCR items
		var ocrItems []models.OCRItem
		if err := json.Unmarshal(sample.OCRExtractedItems, &ocrItems); err != nil {
			continue
		}

		// Parse verified items
		var verifiedItems []sharedModels.DailySalesItem
		if err := json.Unmarshal(sample.VerifiedItems, &verifiedItems); err != nil {
			continue
		}

		// Extract patterns
		for _, verified := range verifiedItems {
			if verified.Product == nil || verified.Product.Brand == nil {
				continue
			}

			canonicalBrand := verified.Product.Brand.Name
			normalizedCanonical := normalizeBrandName(canonicalBrand)

			for _, ocr := range ocrItems {
				ocrBrand := normalizeBrandName(ocr.BrandText)
				similarity := calculateStringSimilarityVal(normalizedCanonical, ocrBrand)

				if similarity >= 0.70 && ocrBrand != normalizedCanonical {
					if aliasPatterns[ocr.BrandText] == nil {
						aliasPatterns[ocr.BrandText] = make(map[string]int)
					}
					aliasPatterns[ocr.BrandText][canonicalBrand]++
				}
			}
		}

		// Mark as processed
		sample.IsUsedForTraining = true
		sample.TrainingBatchID = batchID
		s.db.WithContext(ctx).Save(&sample)
		result.ProcessedSamples++
	}

	// Create aliases from patterns that appear multiple times
	for ocrText, candidates := range aliasPatterns {
		// Find the most common canonical brand for this OCR text
		maxCount := 0
		bestCanonical := ""
		for canonical, count := range candidates {
			if count > maxCount {
				maxCount = count
				bestCanonical = canonical
			}
		}

		// Only create alias if we have at least 2 occurrences (confidence)
		if maxCount >= 2 && bestCanonical != "" {
			confidence := float64(maxCount) / float64(len(samples)) * 100
			if confidence < 50 {
				confidence = 50 // Minimum confidence for batch-learned aliases
			}

			alias := models.OCRBrandAlias{
				ID:                 uuid.New(),
				TenantID:           tenantID,
				CanonicalBrandName: bestCanonical,
				AliasName:          ocrText,
				OccurrenceCount:    maxCount,
				ConfidenceScore:    confidence,
				Source:             "batch_learning",
			}

			err := s.db.WithContext(ctx).
				Where("tenant_id = ? AND alias_name = ?", tenantID, ocrText).
				Assign(map[string]interface{}{
					"occurrence_count":    gorm.Expr("occurrence_count + ?", maxCount),
					"confidence_score":    gorm.Expr("GREATEST(confidence_score, ?)", confidence),
					"last_used_at":        time.Now(),
					"canonical_brand_name": bestCanonical,
				}).
				FirstOrCreate(&alias).Error

			if err == nil {
				result.NewAliasesCreated++
			}
		}
	}

	// Invalidate alias cache
	s.aliasCacheTTL = time.Time{}

	fmt.Printf("[BatchLearning] Completed: processed %d samples, created %d aliases\n",
		result.ProcessedSamples, result.NewAliasesCreated)

	return result, nil
}

// BatchLearningResult contains the results of batch learning processing
type BatchLearningResult struct {
	ProcessedSamples    int     `json:"processed_samples"`
	NewAliasesCreated   int     `json:"new_aliases_created"`
	AccuracyImprovement float64 `json:"accuracy_improvement"`
}

// GetAccuracyTrend returns accuracy trend data for the specified period
func (s *ValidationService) GetAccuracyTrend(ctx context.Context, tenantID uuid.UUID, days int) (*AccuracyTrendReport, error) {
	if days <= 0 {
		days = 30
	}

	startDate := time.Now().AddDate(0, 0, -days).Truncate(24 * time.Hour)

	var metrics []models.OCRAccuracyMetric
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND metric_date >= ?", tenantID, startDate).
		Order("metric_date ASC").
		Find(&metrics).Error; err != nil {
		return nil, err
	}

	report := &AccuracyTrendReport{
		TenantID:   tenantID,
		Period:     fmt.Sprintf("Last %d days", days),
		StartDate:  startDate,
		EndDate:    time.Now(),
		DailyData:  make([]DailyAccuracyData, 0),
		Alerts:     make([]AccuracyAlert, 0),
	}

	var totalAccuracy float64
	var prevAccuracy float64
	var totalValidations int

	for i, metric := range metrics {
		daily := DailyAccuracyData{
			Date:              metric.MetricDate,
			Validations:       metric.TotalValidations,
			OverallAccuracy:   metric.AvgOverallAccuracy,
			BrandAccuracy:     metric.AvgBrandAccuracy,
			QuantityAccuracy:  metric.AvgQuantityAccuracy,
			AutoVerifiedRate:  0,
		}

		if metric.TotalValidations > 0 {
			daily.AutoVerifiedRate = float64(metric.AutoVerified) / float64(metric.TotalValidations) * 100
		}

		report.DailyData = append(report.DailyData, daily)
		totalAccuracy += metric.AvgOverallAccuracy
		totalValidations += metric.TotalValidations

		// Check for accuracy drops (> 10% drop from previous day)
		if i > 0 && prevAccuracy > 0 {
			drop := prevAccuracy - metric.AvgOverallAccuracy
			if drop > 10 {
				report.Alerts = append(report.Alerts, AccuracyAlert{
					Date:      metric.MetricDate,
					AlertType: "accuracy_drop",
					Severity:  "warning",
					Message:   fmt.Sprintf("Accuracy dropped %.1f%% from previous day (%.1f%% → %.1f%%)", drop, prevAccuracy, metric.AvgOverallAccuracy),
				})
			}
		}

		// Check for low accuracy (< 70%)
		if metric.AvgOverallAccuracy < 70 && metric.TotalValidations >= 3 {
			report.Alerts = append(report.Alerts, AccuracyAlert{
				Date:      metric.MetricDate,
				AlertType: "low_accuracy",
				Severity:  "critical",
				Message:   fmt.Sprintf("Low accuracy detected: %.1f%% (threshold: 70%%)", metric.AvgOverallAccuracy),
			})
		}

		prevAccuracy = metric.AvgOverallAccuracy
	}

	if len(metrics) > 0 {
		report.AverageAccuracy = totalAccuracy / float64(len(metrics))
		report.TotalValidations = totalValidations
	}

	// Calculate trend (improvement/decline)
	if len(metrics) >= 7 {
		firstWeekAvg := calculateWeekAverage(metrics[:7])
		lastWeekAvg := calculateWeekAverage(metrics[len(metrics)-7:])
		report.TrendDirection = "stable"
		report.TrendPercentage = lastWeekAvg - firstWeekAvg

		if report.TrendPercentage > 2 {
			report.TrendDirection = "improving"
		} else if report.TrendPercentage < -2 {
			report.TrendDirection = "declining"
		}
	}

	return report, nil
}

func calculateWeekAverage(metrics []models.OCRAccuracyMetric) float64 {
	if len(metrics) == 0 {
		return 0
	}
	var sum float64
	for _, m := range metrics {
		sum += m.AvgOverallAccuracy
	}
	return sum / float64(len(metrics))
}

// AccuracyTrendReport contains comprehensive accuracy trend analysis
type AccuracyTrendReport struct {
	TenantID         uuid.UUID            `json:"tenant_id"`
	Period           string               `json:"period"`
	StartDate        time.Time            `json:"start_date"`
	EndDate          time.Time            `json:"end_date"`
	AverageAccuracy  float64              `json:"average_accuracy"`
	TotalValidations int                  `json:"total_validations"`
	TrendDirection   string               `json:"trend_direction"` // improving, declining, stable
	TrendPercentage  float64              `json:"trend_percentage"`
	DailyData        []DailyAccuracyData  `json:"daily_data"`
	Alerts           []AccuracyAlert      `json:"alerts"`
}

// DailyAccuracyData contains accuracy metrics for a single day
type DailyAccuracyData struct {
	Date             time.Time `json:"date"`
	Validations      int       `json:"validations"`
	OverallAccuracy  float64   `json:"overall_accuracy"`
	BrandAccuracy    float64   `json:"brand_accuracy"`
	QuantityAccuracy float64   `json:"quantity_accuracy"`
	AutoVerifiedRate float64   `json:"auto_verified_rate"`
}

// AccuracyAlert represents an accuracy-related alert
type AccuracyAlert struct {
	Date      time.Time `json:"date"`
	AlertType string    `json:"alert_type"` // accuracy_drop, low_accuracy, learning_opportunity
	Severity  string    `json:"severity"`   // info, warning, critical
	Message   string    `json:"message"`
}

// GetLearningStats returns statistics about the self-learning system
func (s *ValidationService) GetLearningStats(ctx context.Context, tenantID uuid.UUID) (*LearningStats, error) {
	stats := &LearningStats{
		TenantID: tenantID,
	}

	// Count brand aliases by source
	var aliasStats []struct {
		Source string
		Count  int
	}
	s.db.WithContext(ctx).Model(&models.OCRBrandAlias{}).
		Select("source, COUNT(*) as count").
		Where("tenant_id = ?", tenantID).
		Group("source").
		Scan(&aliasStats)

	for _, as := range aliasStats {
		switch as.Source {
		case "user_correction":
			stats.UserCorrectionAliases = as.Count
		case "auto_learned":
			stats.AutoLearnedAliases = as.Count
		case "batch_learning":
			stats.BatchLearnedAliases = as.Count
		}
	}
	stats.TotalAliases = stats.UserCorrectionAliases + stats.AutoLearnedAliases + stats.BatchLearnedAliases

	// Count training samples
	s.db.WithContext(ctx).Model(&models.OCRTrainingSample{}).
		Where("tenant_id = ?", tenantID).
		Count(&stats.TotalTrainingSamples)

	s.db.WithContext(ctx).Model(&models.OCRTrainingSample{}).
		Where("tenant_id = ? AND is_verified = true", tenantID).
		Count(&stats.VerifiedSamples)

	s.db.WithContext(ctx).Model(&models.OCRTrainingSample{}).
		Where("tenant_id = ? AND is_used_for_training = true", tenantID).
		Count(&stats.UsedForTraining)

	// Get average accuracy from last 30 days
	var avgAccuracy float64
	s.db.WithContext(ctx).Model(&models.OCRAccuracyMetric{}).
		Where("tenant_id = ? AND metric_date >= ?", tenantID, time.Now().AddDate(0, 0, -30)).
		Select("AVG(avg_overall_accuracy)").
		Scan(&avgAccuracy)
	stats.Last30DaysAvgAccuracy = avgAccuracy

	// Get top performing aliases (most used)
	var topAliases []models.OCRBrandAlias
	s.db.WithContext(ctx).
		Where("tenant_id = ?", tenantID).
		Order("occurrence_count DESC").
		Limit(10).
		Find(&topAliases)
	stats.TopPerformingAliases = topAliases

	return stats, nil
}

// LearningStats contains statistics about the self-learning system
type LearningStats struct {
	TenantID               uuid.UUID              `json:"tenant_id"`
	TotalAliases           int                    `json:"total_aliases"`
	UserCorrectionAliases  int                    `json:"user_correction_aliases"`
	AutoLearnedAliases     int                    `json:"auto_learned_aliases"`
	BatchLearnedAliases    int                    `json:"batch_learned_aliases"`
	TotalTrainingSamples   int64                  `json:"total_training_samples"`
	VerifiedSamples        int64                  `json:"verified_samples"`
	UsedForTraining        int64                  `json:"used_for_training"`
	Last30DaysAvgAccuracy  float64                `json:"last_30_days_avg_accuracy"`
	TopPerformingAliases   []models.OCRBrandAlias `json:"top_performing_aliases"`
}

// ============================================================================
// AI-Powered Review Suggestions Generation
// ============================================================================

// generateAISummary creates an AI summary for the manager review screen
// Uses modern analysis with clear, actionable recommendations
func (s *ValidationService) generateAISummary(result *models.ValidationResult) *models.AISummary {
	if result == nil {
		return nil
	}

	critical := 0
	warnings := 0
	matched := 0
	notInReceipt := 0

	// Issue type counters for detailed breakdown
	missingEntryCount := 0     // Items in receipt but NOT entered (fraud risk)
	quantityMismatchCount := 0 // Sale quantity differences
	priceMismatchCount := 0    // Price/rate differences
	stockMismatchCount := 0    // Opening/closing stock differences
	notFoundInOCRCount := 0    // Items entered but not found in images

	// Count issues by type from match details (per-item issues)
	for _, detail := range result.MatchDetails {
		if detail.MatchStatus == "matched" {
			matched++
			// Count specific issues for matched items
			for _, issue := range detail.Issues {
				issueLower := strings.ToLower(issue)
				if strings.Contains(issueLower, "sale") || strings.Contains(issueLower, "quantity") {
					quantityMismatchCount++
					if absInt(detail.SaleDiff) > 5 {
						critical++
					} else if absInt(detail.SaleDiff) > 2 {
						warnings++
					}
				} else if strings.Contains(issueLower, "price") || strings.Contains(issueLower, "rate") {
					priceMismatchCount++
					if absFloat64(detail.PriceDiff) > 100 {
						critical++
					} else if absFloat64(detail.PriceDiff) > 20 {
						warnings++
					}
				} else if strings.Contains(issueLower, "opening") || strings.Contains(issueLower, "closing") {
					stockMismatchCount++
					warnings++
				}
			}
		} else if detail.MatchStatus == "not_found" {
			notInReceipt++
			notFoundInOCRCount++
			// Only a warning - could be different receipt/image not uploaded
			warnings++
		}
	}

	// Count items in OCR but NOT entered by salesman - this is CRITICAL (potential fraud)
	for _, m := range result.Mismatches {
		if m.MismatchType == "missing_entry" && m.EnteredValue == "NOT_ENTERED" {
			missingEntryCount++
			// Missing entries with sale_quantity > 0 are critical
			critical++
		}
	}

	// If no match details, fallback to summary counts
	if matched == 0 && result.TotalItems > 0 {
		matched = result.TotalItems - result.MissingOCRItems
	}

	// Generate smart, actionable recommendation
	var recommendation string
	var recommendedAction string
	var confidenceLevel string

	// Build recommendation based on specific issues found
	recommendations := []string{}

	if missingEntryCount > 0 {
		recommendations = append(recommendations, fmt.Sprintf("🚨 %d items sold in receipt but NOT entered - verify immediately", missingEntryCount))
	}
	if quantityMismatchCount > 0 {
		recommendations = append(recommendations, fmt.Sprintf("📊 %d items have quantity differences - check bottle counts", quantityMismatchCount))
	}
	if priceMismatchCount > 0 {
		recommendations = append(recommendations, fmt.Sprintf("💰 %d items have price discrepancies - verify MRP", priceMismatchCount))
	}
	if notFoundInOCRCount > 0 && notFoundInOCRCount < result.TotalItems/2 {
		recommendations = append(recommendations, fmt.Sprintf("📷 %d items not found in images - check if all receipt pages uploaded", notFoundInOCRCount))
	}
	if stockMismatchCount > 0 {
		recommendations = append(recommendations, fmt.Sprintf("📦 %d items have stock discrepancies - verify opening/closing stock", stockMismatchCount))
	}

	// Combine recommendations or use default
	if len(recommendations) > 0 {
		if len(recommendations) == 1 {
			recommendation = recommendations[0]
		} else {
			recommendation = strings.Join(recommendations[:min(3, len(recommendations))], "; ")
		}
	} else if result.OverallAccuracy >= 95 {
		recommendation = "✅ All entries verified against receipts - safe to approve"
	} else if result.OverallAccuracy >= 85 {
		recommendation = "✓ Good match with minor discrepancies - review highlighted items"
	} else if result.OverallAccuracy >= 70 {
		recommendation = "⚠️ Some entries need verification - review before approving"
	} else if matched == 0 && result.TotalItems > 0 {
		recommendation = "📷 No items matched - verify correct receipt images are uploaded"
	} else {
		recommendation = "❌ Low accuracy detected - thorough manual review required"
	}

	// Determine action based on severity
	if critical > 0 {
		recommendedAction = "review"
		confidenceLevel = "low"
	} else if warnings > 3 {
		recommendedAction = "review"
		confidenceLevel = "medium"
	} else if warnings > 0 {
		recommendedAction = "review"
		confidenceLevel = "medium"
	} else if result.OverallAccuracy >= 95 && matched > 0 {
		recommendedAction = "approve"
		confidenceLevel = "high"
	} else if result.OverallAccuracy >= 85 {
		recommendedAction = "approve"
		confidenceLevel = "high"
	} else if result.OverallAccuracy >= 70 {
		recommendedAction = "review"
		confidenceLevel = "medium"
	} else {
		recommendedAction = "review"
		confidenceLevel = "low"
	}

	return &models.AISummary{
		OverallAccuracy:   result.OverallAccuracy,
		CriticalCount:     critical,
		WarningCount:      warnings,
		MatchedCount:      matched,
		MissingCount:      missingEntryCount, // Items in receipt but NOT entered
		Recommendation:    recommendation,
		ConfidenceLevel:   confidenceLevel,
		RecommendedAction: recommendedAction,
		// Issue type breakdown for accurate frontend messages
		MissingEntryCount:     missingEntryCount,    // Items in receipt but NOT entered by salesman
		QuantityMismatchCount: quantityMismatchCount, // Sale quantity differences
		PriceMismatchCount:    priceMismatchCount,   // Price/rate differences
		StockMismatchCount:    stockMismatchCount,   // Opening/closing stock differences
		NotInReceiptCount:     notInReceipt,         // Items entered but NOT found in receipt
	}
}

// generatePerItemInsights creates per-item AI insights for the review screen
func (s *ValidationService) generatePerItemInsights(result *models.ValidationResult) []models.ItemInsight {
	if result == nil || len(result.MatchDetails) == 0 {
		return nil
	}

	insights := make([]models.ItemInsight, 0, len(result.MatchDetails))

	for _, detail := range result.MatchDetails {
		// Determine status based on issues
		status := "matched"
		issues := make([]models.Issue, 0)

		// Convert string issues to Issue structs with severity
		for _, issueStr := range detail.Issues {
			severity := "warning"
			issueType := "general"
			field := ""
			enteredVal := ""
			ocrVal := ""
			suggestion := ""

			// Parse the issue string to determine type and severity
			if strings.Contains(issueStr, "Not found in OCR") {
				// Item not found in OCR images - show as warning
				issueType = "missing"
				field = "ocr_match"
				severity = "warning"
				enteredVal = detail.ProductName
				ocrVal = "Not found"
				suggestion = "Item was entered but not found in receipt images. Verify receipt images are complete."
			} else if strings.Contains(issueStr, "quantity") || strings.Contains(issueStr, "Quantity") || strings.Contains(issueStr, "Sale") {
				issueType = "quantity"
				field = "quantity"
				enteredVal = fmt.Sprintf("%d", detail.EnteredSale)
				ocrVal = fmt.Sprintf("%d", detail.OCRSale)
				if detail.SaleDiff > 5 || detail.SaleDiff < -5 {
					severity = "critical"
				}
				suggestion = "Verify actual bottles sold against physical count"
			} else if strings.Contains(issueStr, "price") || strings.Contains(issueStr, "Price") {
				issueType = "price"
				field = "rate"
				enteredVal = fmt.Sprintf("%.2f", detail.EnteredPrice)
				ocrVal = fmt.Sprintf("%.2f", detail.OCRPrice)
				if detail.PriceDiff > 50 || detail.PriceDiff < -50 {
					severity = "critical"
				}
				suggestion = "Verify MRP/selling price is correct"
			} else if strings.Contains(issueStr, "Opening") || strings.Contains(issueStr, "opening") {
				issueType = "stock"
				field = "opening_stock"
				enteredVal = fmt.Sprintf("%d", detail.EnteredOpening)
				ocrVal = fmt.Sprintf("%d", detail.OCROpening)
				if detail.OpeningDiff > 10 || detail.OpeningDiff < -10 {
					severity = "critical"
				}
				suggestion = "Verify opening stock from previous day's closing"
			} else if strings.Contains(issueStr, "Closing") || strings.Contains(issueStr, "closing") {
				issueType = "stock"
				field = "closing_stock"
				enteredVal = fmt.Sprintf("%d", detail.EnteredClosing)
				ocrVal = fmt.Sprintf("%d", detail.OCRClosing)
				suggestion = "Verify closing stock matches physical count"
			}

			issue := models.Issue{
				Type:        issueType,
				Severity:    severity,
				Field:       field,
				EnteredVal:  enteredVal,
				OCRVal:      ocrVal,
				Difference:  issueStr,
				Message:     issueStr,
				Suggestion:  suggestion,
				AutoFixable: false, // Manual review required
			}

			issues = append(issues, issue)

			// Upgrade status if needed
			if severity == "critical" {
				status = "critical"
			} else if severity == "warning" && status != "critical" {
				status = "warning"
			}
		}

		insight := models.ItemInsight{
			ProductID:       detail.ProductID.String(),
			ProductName:     detail.ProductName,
			BrandName:       detail.BrandName,
			Size:            detail.Size,
			Status:          status,
			IssueCount:      len(issues),
			Issues:          issues,
			MatchConfidence: detail.MatchConfidence * 100, // Convert to percentage
			EnteredQty:      detail.EnteredSale,
			OCRQty:          detail.OCRSale,
			EnteredRate:     detail.EnteredPrice,
			OCRRate:         detail.OCRPrice,
		}

		insights = append(insights, insight)
	}

	// Also add items from OCR that were NOT entered (missing entries - critical!)
	for _, m := range result.Mismatches {
		if m.MismatchType != "missing_entry" {
			continue
		}

		// Parse size from OCR value
		size := ""
		if strings.Contains(m.OCRValue, "ML") || strings.Contains(m.OCRValue, "ml") {
			// Extract size like "90ML" from OCR value
			parts := strings.Fields(m.OCRValue)
			for _, p := range parts {
				if strings.HasSuffix(strings.ToUpper(p), "ML") {
					size = strings.ToUpper(p)
					break
				}
			}
		}

		// Parse quantities and rate from OCRValue format: "Brand Size (Opening: X, Sale: Y, Closing: Z, Rate: R)"
		saleQty := 0
		ocrRate := 0.0

		// Try to parse from the new Difference format: "Item found in receipt with X units sold at RsY each..."
		if strings.Contains(m.Difference, "units sold at Rs") {
			fmt.Sscanf(m.Difference, "Item found in receipt with %d units sold at Rs%f each", &saleQty, &ocrRate)
		} else if strings.Contains(m.Difference, "units sold") {
			// Fallback for old format
			fmt.Sscanf(m.Difference, "Item found in receipt with %d units sold", &saleQty)
		}

		// Also try to parse Rate from OCRValue if not found in Difference
		if ocrRate == 0 && strings.Contains(m.OCRValue, "Rate:") {
			// Format: "Brand Size (Opening: X, Sale: Y, Closing: Z, Rate: R)"
			if idx := strings.Index(m.OCRValue, "Rate:"); idx >= 0 {
				rateStr := m.OCRValue[idx+5:]
				rateStr = strings.TrimPrefix(rateStr, " ")
				if endIdx := strings.Index(rateStr, ")"); endIdx > 0 {
					rateStr = rateStr[:endIdx]
				}
				fmt.Sscanf(rateStr, "%f", &ocrRate)
			}
		}

		insight := models.ItemInsight{
			ProductID:       "", // No product ID for unmatched OCR items
			ProductName:     m.ProductName,
			BrandName:       m.ProductName,
			Size:            size,
			Status:          "critical", // Missing entries are critical!
			IssueCount:      1,
			Issues: []models.Issue{
				{
					Type:        "missing_entry",
					Severity:    "critical",
					Field:       "entry",
					EnteredVal:  "Not entered",
					OCRVal:      fmt.Sprintf("%d units @ Rs%.0f", saleQty, ocrRate),
					Difference:  m.Difference,
					Message:     fmt.Sprintf("Receipt mein hai (%d units @ Rs%.0f) but entry nahi ki / Item in receipt but not entered", saleQty, ocrRate),
					Suggestion:  "Verify if salesman forgot to enter this sale or if it was intentionally skipped",
					AutoFixable: false,
				},
			},
			MatchConfidence: 0,
			EnteredQty:      0,
			OCRQty:          saleQty,
			EnteredRate:     0,
			OCRRate:         ocrRate,
		}

		insights = append(insights, insight)
	}

	return insights
}

// groupMissingItems groups missing items by severity for the review screen
func (s *ValidationService) groupMissingItems(mismatches []models.ValidationMismatch) []models.MissingItemGroup {
	if len(mismatches) == 0 {
		return nil
	}

	criticalItems := make([]models.MissingItem, 0)
	warningItems := make([]models.MissingItem, 0)

	for _, m := range mismatches {
		// Only process missing entry type mismatches
		if m.MismatchType != "missing_entry" || m.FieldName != "brand" {
			continue
		}

		// Parse the OCR value to extract details
		// Format: "BrandName SizeML (Opening: X, Sale: Y, Closing: Z)"
		item := models.MissingItem{
			BrandText: m.ProductName,
		}

		// Try to parse sale quantity from the difference string
		// e.g., "Item found in receipt with 11 units sold but not entered by salesman"
		if strings.Contains(m.Difference, "units sold") {
			parts := strings.Split(m.Difference, " ")
			for i, p := range parts {
				if p == "with" && i+1 < len(parts) {
					fmt.Sscanf(parts[i+1], "%d", &item.SaleQty)
					break
				}
			}
		}

		// Parse size from OCR value if present
		if strings.Contains(m.OCRValue, "ml") || strings.Contains(m.OCRValue, "ML") {
			// Extract size pattern like "180ml" or "750ML"
			re := strings.NewReplacer("(", " ", ")", " ", ",", " ")
			cleaned := re.Replace(m.OCRValue)
			parts := strings.Fields(cleaned)
			for _, p := range parts {
				if strings.HasSuffix(strings.ToLower(p), "ml") {
					item.Size = p
					break
				}
			}
		}

		// Parse opening/closing from OCR value
		if strings.Contains(m.OCRValue, "Opening:") {
			fmt.Sscanf(m.OCRValue, "%*[^O]Opening: %d", &item.OpeningQty)
		}
		if strings.Contains(m.OCRValue, "Closing:") {
			fmt.Sscanf(m.OCRValue, "%*[^C]Closing: %d", &item.ClosingQty)
		}

		// Determine severity based on sale quantity
		if item.SaleQty >= 5 {
			item.Severity = "critical"
			criticalItems = append(criticalItems, item)
		} else {
			item.Severity = "warning"
			warningItems = append(warningItems, item)
		}
	}

	groups := make([]models.MissingItemGroup, 0)

	if len(criticalItems) > 0 {
		groups = append(groups, models.MissingItemGroup{
			Severity: "critical",
			Count:    len(criticalItems),
			Items:    criticalItems,
		})
	}

	if len(warningItems) > 0 {
		groups = append(groups, models.MissingItemGroup{
			Severity: "warning",
			Count:    len(warningItems),
			Items:    warningItems,
		})
	}

	return groups
}

// ============================================================================
// AI-Powered OCR Brand to Product Matching
// ============================================================================

// OCRProductMatch represents a matched OCR item to database product
type OCRProductMatch struct {
	OCRBrandText   string    `json:"ocr_brand_text"`
	OCRSize        string    `json:"ocr_size"`
	MatchedProduct string    `json:"matched_product"`
	MatchedBrand   string    `json:"matched_brand"`
	ProductID      uuid.UUID `json:"product_id"`
	Confidence     float64   `json:"confidence"`
	MatchReason    string    `json:"match_reason"`
}

// matchOCRItemsToProducts uses AI to match OCR brand names to actual database products
// Uses Fomoa (primary) → ChatGPT (fallback 1) → Gemini (fallback 2)
func (s *ValidationService) matchOCRItemsToProducts(ctx context.Context, tenantID uuid.UUID, ocrItems []models.OCRItem) (map[string]OCRProductMatch, error) {
	// Check if any AI provider is configured
	if s.fomoaAPIKey == "" && s.openAIAPIKey == "" && s.geminiAPIKey == "" {
		fmt.Println("[AI Match] No AI provider configured, using fallback matching")
		return nil, nil
	}

	// Get all products for this tenant
	var products []sharedModels.Product
	if err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
		Preload("Brand").
		Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to fetch products: %w", err)
	}

	if len(products) == 0 {
		return nil, nil
	}

	// Build product list for AI
	productList := make([]string, 0)
	productMap := make(map[string]sharedModels.Product)
	for _, p := range products {
		key := fmt.Sprintf("%s|%s", p.Name, p.Size)
		productList = append(productList, key)
		productMap[key] = p
	}

	// Build OCR items list
	ocrList := make([]string, 0)
	for _, item := range ocrItems {
		if item.BrandText != "" && item.SizeText != "" && item.SaleQuantity > 0 {
			ocrList = append(ocrList, fmt.Sprintf("%s|%s|Q:%d|P:%.0f", item.BrandText, item.SizeText, item.SaleQuantity, item.Rate))
		}
	}

	if len(ocrList) == 0 {
		return nil, nil
	}

	fmt.Printf("[AI Match] Matching %d OCR items to %d products using AI (Fomoa → ChatGPT → Gemini)\n", len(ocrList), len(productList))

	// Build prompts for unified AI call
	systemPrompt := "You are a product matching assistant for a liquor store. Return only valid JSON arrays."

	userPrompt := fmt.Sprintf(`You are a product matching AI for a liquor store inventory system.

AVAILABLE PRODUCTS (format: Name|Size):
%s

OCR EXTRACTED ITEMS (format: BrandText|Size|Quantity|Price):
%s

TASK: Match each OCR item to the most likely product from the available products list.
OCR may have misread brand names (e.g., "Amstel" might be "KINGFISHER ULTRA MAX", "God Father" might be "KINGFISHER STRONG").
Match based on:
1. Size must match exactly (500ML with 500ML, 650ML with 650ML, etc.)
2. Brand name similarity (even partial matches)
3. Price point similarity (similar priced products)

Return ONLY valid JSON array with this format:
[
  {"ocr": "OCR_Brand|Size", "match": "Product_Name|Size", "confidence": 0.95, "reason": "exact match"},
  {"ocr": "OCR_Brand|Size", "match": "Product_Name|Size", "confidence": 0.8, "reason": "similar name and price"}
]

If no good match exists, use confidence 0.0 and match "NONE".
Return ONLY the JSON array, no other text.`,
		strings.Join(productList, "\n"),
		strings.Join(ocrList, "\n"))

	// Call AI with fallback (using high token limit for Fomoa - owned service)
	responseText, provider, err := s.callAIWithFallback(ctx, systemPrompt, userPrompt, 8000)
	if err != nil {
		return nil, fmt.Errorf("AI matching failed: %w", err)
	}

	fmt.Printf("[AI Match] Using %s for brand matching\n", provider)
	// Remove markdown code blocks if present
	responseText = strings.TrimPrefix(responseText, "```json")
	responseText = strings.TrimPrefix(responseText, "```")
	responseText = strings.TrimSuffix(responseText, "```")
	responseText = strings.TrimSpace(responseText)

	var matches []struct {
		OCR        string  `json:"ocr"`
		Match      string  `json:"match"`
		Confidence float64 `json:"confidence"`
		Reason     string  `json:"reason"`
	}

	if err := json.Unmarshal([]byte(responseText), &matches); err != nil {
		fmt.Printf("[AI Match] Failed to parse AI response: %v\nResponse: %s\n", err, responseText)
		return nil, nil
	}

	// Build result map
	result := make(map[string]OCRProductMatch)
	for _, m := range matches {
		if m.Match == "NONE" || m.Confidence < 0.5 {
			continue
		}

		ocrParts := strings.Split(m.OCR, "|")
		if len(ocrParts) < 2 {
			continue
		}

		product, found := productMap[m.Match]
		if !found {
			continue
		}

		brandName := ""
		if product.Brand != nil {
			brandName = product.Brand.Name
		}

		key := fmt.Sprintf("%s|%s", strings.ToLower(ocrParts[0]), strings.ToLower(ocrParts[1]))
		result[key] = OCRProductMatch{
			OCRBrandText:   ocrParts[0],
			OCRSize:        ocrParts[1],
			MatchedProduct: product.Name,
			MatchedBrand:   brandName,
			ProductID:      product.ID,
			Confidence:     m.Confidence,
			MatchReason:    m.Reason,
		}

		fmt.Printf("[AI Match] '%s' -> '%s' (%.0f%% - %s)\n", m.OCR, m.Match, m.Confidence*100, m.Reason)
	}

	fmt.Printf("[AI Match] Successfully matched %d OCR items to products\n", len(result))

	// Auto-learn: Save high-confidence matches as brand aliases
	for _, match := range result {
		if match.Confidence >= 0.85 {
			s.learnBrandAlias(ctx, tenantID, match.OCRBrandText, match.MatchedBrand)
		}
	}

	return result, nil
}

// learnBrandAlias saves a learned brand alias to the database
func (s *ValidationService) learnBrandAlias(ctx context.Context, tenantID uuid.UUID, ocrBrand, canonicalBrand string) {
	if ocrBrand == "" || canonicalBrand == "" {
		return
	}

	normalizedOCR := strings.ToLower(strings.TrimSpace(ocrBrand))
	normalizedCanonical := strings.ToLower(strings.TrimSpace(canonicalBrand))

	// Skip if they're the same
	if normalizedOCR == normalizedCanonical {
		return
	}

	// Check if alias already exists
	var existingAlias models.OCRBrandAlias
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND LOWER(alias_name) = ?", tenantID, normalizedOCR).
		First(&existingAlias).Error

	if err == nil {
		// Alias exists, update occurrence count and confidence
		now := time.Now()
		s.db.WithContext(ctx).Model(&existingAlias).Updates(map[string]interface{}{
			"occurrence_count": gorm.Expr("occurrence_count + 1"),
			"confidence_score": gorm.Expr("LEAST(confidence_score + 5, 100.0)"),
			"last_used_at":     &now,
		})
		fmt.Printf("[AI Match] Updated existing alias: '%s' -> '%s' (count +1)\n", ocrBrand, canonicalBrand)
		return
	}

	// Create new alias
	now := time.Now()
	newAlias := models.OCRBrandAlias{
		TenantID:           tenantID,
		AliasName:          ocrBrand,
		CanonicalBrandName: canonicalBrand,
		ConfidenceScore:    85.0, // Using 0-100 scale
		OccurrenceCount:    1,
		Source:             "ai_auto",
		LastUsedAt:         &now,
	}

	if err := s.db.WithContext(ctx).Create(&newAlias).Error; err != nil {
		fmt.Printf("[AI Match] Warning: Failed to save brand alias: %v\n", err)
	} else {
		fmt.Printf("[AI Match] Learned new alias: '%s' -> '%s'\n", ocrBrand, canonicalBrand)
	}
}

// ============================================================================
// ChatGPT-Powered AI Recommendations
// ============================================================================

// ChatGPTRequest represents a request to ChatGPT API
type ChatGPTRequest struct {
	Model       string              `json:"model"`
	Messages    []ChatGPTMessage    `json:"messages"`
	MaxTokens   int                 `json:"max_tokens"`
	Temperature float64             `json:"temperature"`
}

// ChatGPTMessage represents a message in ChatGPT conversation
type ChatGPTMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// ChatGPTResponse represents the response from ChatGPT API (also compatible with Fomoa)
type ChatGPTResponse struct {
	ID      string `json:"id"`
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
	Usage struct {
		TotalTokens int `json:"total_tokens"`
	} `json:"usage,omitempty"`
}

// callAIWithFallback calls AI providers with fallback: Fomoa → ChatGPT → Gemini
// Returns (response content, provider used, error)
func (s *ValidationService) callAIWithFallback(ctx context.Context, systemPrompt, userPrompt string, maxTokens int) (string, string, error) {
	var lastError error

	// 1. Try Fomoa (PRIMARY)
	if s.fomoaAPIKey != "" {
		content, err := s.callFomoa(ctx, systemPrompt, userPrompt, maxTokens)
		if err == nil {
			return content, "fomoa", nil
		}
		lastError = err
		fmt.Printf("[AI] Fomoa failed: %v, trying ChatGPT...\n", err)
	}

	// 2. Try ChatGPT (1st FALLBACK)
	if s.openAIAPIKey != "" {
		content, err := s.callChatGPT(ctx, systemPrompt, userPrompt, maxTokens)
		if err == nil {
			return content, "chatgpt", nil
		}
		lastError = err
		fmt.Printf("[AI] ChatGPT failed: %v, trying Gemini...\n", err)
	}

	// 3. Try Gemini (2nd FALLBACK)
	if s.geminiAPIKey != "" {
		content, err := s.callGemini(ctx, systemPrompt, userPrompt, maxTokens)
		if err == nil {
			return content, "gemini", nil
		}
		lastError = err
		fmt.Printf("[AI] Gemini failed: %v\n", err)
	}

	if lastError != nil {
		return "", "", fmt.Errorf("all AI providers failed, last error: %w", lastError)
	}
	return "", "", fmt.Errorf("no AI providers configured")
}

// callFomoa calls Fomoa AI API (qwen2.5vl:7b)
func (s *ValidationService) callFomoa(ctx context.Context, systemPrompt, userPrompt string, maxTokens int) (string, error) {
	request := ChatGPTRequest{
		Model: s.fomoaModel,
		Messages: []ChatGPTMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		MaxTokens:   maxTokens,
		Temperature: 0.1,
	}

	jsonBody, err := json.Marshal(request)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", s.fomoaAPIURL, bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.fomoaAPIKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("Fomoa API call failed: %w", err)
	}
	defer resp.Body.Close()

	// Read full response body for debugging
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read Fomoa response: %w", err)
	}

	// Check for non-200 status
	if resp.StatusCode != http.StatusOK {
		fmt.Printf("[AI] Fomoa error response (status %d): %s\n", resp.StatusCode, string(bodyBytes[:min(500, len(bodyBytes))]))
		return "", fmt.Errorf("Fomoa API error: status %d", resp.StatusCode)
	}

	var chatResp ChatGPTResponse
	if err := json.Unmarshal(bodyBytes, &chatResp); err != nil {
		fmt.Printf("[AI] Fomoa parse error - raw response: %s\n", string(bodyBytes[:min(500, len(bodyBytes))]))
		return "", fmt.Errorf("failed to decode Fomoa response: %w", err)
	}

	if chatResp.Error != nil {
		return "", fmt.Errorf("Fomoa API error: %s", chatResp.Error.Message)
	}

	if len(chatResp.Choices) == 0 {
		fmt.Printf("[AI] Fomoa no choices - raw response: %s\n", string(bodyBytes[:min(500, len(bodyBytes))]))
		return "", fmt.Errorf("no response from Fomoa")
	}

	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	fmt.Printf("[AI] Fomoa responded (%d tokens, model: %s)\n", chatResp.Usage.TotalTokens, s.fomoaModel)
	return content, nil
}

// callChatGPT calls OpenAI ChatGPT API
func (s *ValidationService) callChatGPT(ctx context.Context, systemPrompt, userPrompt string, maxTokens int) (string, error) {
	request := ChatGPTRequest{
		Model: "gpt-4o-mini",
		Messages: []ChatGPTMessage{
			{Role: "system", Content: systemPrompt},
			{Role: "user", Content: userPrompt},
		},
		MaxTokens:   maxTokens,
		Temperature: 0.3,
	}

	jsonBody, err := json.Marshal(request)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openAIAPIKey)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("ChatGPT API call failed: %w", err)
	}
	defer resp.Body.Close()

	var chatResp ChatGPTResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return "", fmt.Errorf("failed to decode ChatGPT response: %w", err)
	}

	if chatResp.Error != nil {
		return "", fmt.Errorf("ChatGPT API error: %s", chatResp.Error.Message)
	}

	if len(chatResp.Choices) == 0 {
		return "", fmt.Errorf("no response from ChatGPT")
	}

	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	fmt.Printf("[AI] ChatGPT responded (%d tokens)\n", chatResp.Usage.TotalTokens)
	return content, nil
}

// callGemini calls Google Gemini API
func (s *ValidationService) callGemini(ctx context.Context, systemPrompt, userPrompt string, maxTokens int) (string, error) {
	// Gemini uses a different API format
	geminiURL := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=%s", s.geminiAPIKey)

	geminiReq := map[string]interface{}{
		"contents": []map[string]interface{}{
			{
				"parts": []map[string]string{
					{"text": systemPrompt + "\n\n" + userPrompt},
				},
			},
		},
		"generationConfig": map[string]interface{}{
			"maxOutputTokens": maxTokens,
			"temperature":     0.3,
		},
	}

	jsonBody, err := json.Marshal(geminiReq)
	if err != nil {
		return "", fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", geminiURL, bytes.NewBuffer(jsonBody))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("Gemini API call failed: %w", err)
	}
	defer resp.Body.Close()

	var geminiResp struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
		Error *struct {
			Message string `json:"message"`
		} `json:"error,omitempty"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&geminiResp); err != nil {
		return "", fmt.Errorf("failed to decode Gemini response: %w", err)
	}

	if geminiResp.Error != nil {
		return "", fmt.Errorf("Gemini API error: %s", geminiResp.Error.Message)
	}

	if len(geminiResp.Candidates) == 0 || len(geminiResp.Candidates[0].Content.Parts) == 0 {
		return "", fmt.Errorf("no response from Gemini")
	}

	content := strings.TrimSpace(geminiResp.Candidates[0].Content.Parts[0].Text)
	fmt.Printf("[AI] Gemini responded\n")
	return content, nil
}

// generateAIRecommendation generates a smart recommendation using AI (Fomoa → ChatGPT → Gemini)
// Renamed from generateChatGPTRecommendation to reflect multi-provider support
func (s *ValidationService) generateChatGPTRecommendation(ctx context.Context, result *models.ValidationResult) (string, error) {
	// Check if any AI provider is configured
	if s.fomoaAPIKey == "" && s.openAIAPIKey == "" && s.geminiAPIKey == "" {
		return "", fmt.Errorf("no AI provider configured")
	}

	// Build a summary of the validation data
	userPrompt := s.buildValidationPrompt(result)

	systemPrompt := `You are an AI assistant for a liquor retail management system. Your job is to help managers review daily sales records submitted by salesmen.

When reviewing validation results that compare salesman entries with OCR-extracted data from receipts:
- Be concise and actionable (max 2-3 sentences)
- Focus on the most important discrepancies
- Use professional business language
- Give a clear recommendation: APPROVE, REVIEW, or REJECT
- Mention specific products if there are critical issues`

	// Use unified AI call with fallback (high token limit for Fomoa)
	content, provider, err := s.callAIWithFallback(ctx, systemPrompt, userPrompt, 1000)
	if err != nil {
		return "", err
	}

	fmt.Printf("[Validation] AI recommendation generated by %s\n", provider)
	return content, nil
}

// buildValidationPrompt builds the prompt for ChatGPT based on validation results
func (s *ValidationService) buildValidationPrompt(result *models.ValidationResult) string {
	var sb strings.Builder

	// Count items by status
	ocrMatched := 0
	perfectMatches := 0
	itemsWithIssues := 0
	notFoundInOCR := 0

	for _, detail := range result.MatchDetails {
		if detail.MatchStatus == "matched" {
			ocrMatched++
			if len(detail.Issues) == 0 {
				perfectMatches++
			} else {
				itemsWithIssues++
			}
		} else if detail.MatchStatus == "not_found" {
			notFoundInOCR++
		}
	}

	sb.WriteString("Daily Sales Validation Summary:\n")
	sb.WriteString(fmt.Sprintf("- Total Items Entered: %d\n", result.TotalItems))
	matchPct := 0.0
	if result.TotalItems > 0 {
		matchPct = float64(ocrMatched) / float64(result.TotalItems) * 100
	}
	sb.WriteString(fmt.Sprintf("- Items Found in Receipt: %d (%.0f%%)\n", ocrMatched, matchPct))
	sb.WriteString(fmt.Sprintf("- Perfect Matches (no discrepancies): %d\n", perfectMatches))
	sb.WriteString(fmt.Sprintf("- Items with Minor Issues: %d\n", itemsWithIssues))
	sb.WriteString(fmt.Sprintf("- Items NOT Found in Receipt: %d\n", notFoundInOCR))
	sb.WriteString(fmt.Sprintf("- Extra Items in Receipt (not entered): %d\n", result.ExtraOCRItems))
	sb.WriteString(fmt.Sprintf("- Quantity Accuracy: %.0f%%\n", result.QuantityAccuracy))
	sb.WriteString(fmt.Sprintf("- Price Accuracy: %.0f%%\n", result.PriceAccuracy))

	// List per-item details
	if len(result.MatchDetails) > 0 {
		sb.WriteString("\nPer-Item Details:\n")
		for _, detail := range result.MatchDetails {
			status := "✓ OK"
			if len(detail.Issues) > 0 {
				status = fmt.Sprintf("⚠ %d issues", len(detail.Issues))
			}
			if detail.MatchStatus == "not_found" {
				status = "❌ Not in receipt"
			}
			sb.WriteString(fmt.Sprintf("- %s: Qty %d, Rate ₹%.0f [%s]\n",
				detail.ProductName, detail.EnteredSale, detail.EnteredPrice, status))

			// Add issue details for items with problems
			for _, issue := range detail.Issues {
				sb.WriteString(fmt.Sprintf("    → %s\n", issue))
			}
		}
	}

	// Add missing items from OCR
	if result.ExtraOCRItems > 0 {
		sb.WriteString(fmt.Sprintf("\n⚠️ %d items in receipt but NOT entered - may need review\n", result.ExtraOCRItems))
	}

	sb.WriteString("\nBased on this data, provide a 2-sentence recommendation for the manager. Focus on action needed and whether to APPROVE (safe), REVIEW (minor issues), or REJECT (major issues).")

	return sb.String()
}

// generateChatGPTPerItemInsight generates AI insight for a specific product (now uses Fomoa → ChatGPT → Gemini)
func (s *ValidationService) generateChatGPTPerItemInsight(ctx context.Context, detail *models.ItemMatchDetail) (string, error) {
	// Check if any AI provider is configured
	if s.fomoaAPIKey == "" && s.openAIAPIKey == "" && s.geminiAPIKey == "" {
		return "", nil
	}

	if len(detail.Issues) == 0 {
		return "", nil
	}

	userPrompt := fmt.Sprintf(`Product: %s (%s)
Entered: Opening=%d, Sale=%d, Closing=%d, Price=%.2f
OCR Detected: Opening=%d, Sale=%d, Closing=%d, Price=%.2f
Issues: %s

In one sentence, what should the manager check for this product?`,
		detail.ProductName, detail.Size,
		detail.EnteredOpening, detail.EnteredSale, detail.EnteredClosing, detail.EnteredPrice,
		detail.OCROpening, detail.OCRSale, detail.OCRClosing, detail.OCRPrice,
		strings.Join(detail.Issues, "; "))

	systemPrompt := "You are a concise assistant. Give a one-sentence actionable insight for a liquor store manager reviewing sales discrepancies."

	// Use unified AI call with fallback (high token limit for Fomoa)
	content, _, err := s.callAIWithFallback(ctx, systemPrompt, userPrompt, 500)
	if err != nil {
		return "", err
	}

	return content, nil
}

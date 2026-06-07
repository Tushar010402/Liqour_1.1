package services

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/matching"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

// SmartSaleService handles AI-powered sales entry from receipt images
type SmartSaleService struct {
	db             *database.DB
	cache          *cache.Cache
	geminiService  *GeminiOCRService
	openaiService  *OpenAIOCRService // OpenAI GPT-4o (fallback or primary depending on SMART_SALE_PRIMARY)
	claudeService  *ClaudeOCRService // Anthropic Claude Sonnet 4.6 (v1.0.119, primary when SMART_SALE_PRIMARY=claude)
	logger         *logrus.Logger
	sizeNormalizer *SizeNormalizer
	useOpenAI      bool // Flag to use OpenAI when Claude isn't routed
	useClaude      bool // v1.0.119: Claude is the routed primary
	aliasService   *alias.AliasService
	cvSidecar      *CVSidecarClient // v1.0.133-r10: blank-row cross-check signal
}

// SaleCVHintsCtxKey is the context key carrying the CV sidecar's per-image
// blank-row signal. Set by extractFromImages right before each goroutine
// dispatches its Claude call. Empty when CV_SIDECAR_ENABLED=0 or detection
// fails — extraction proceeds without the cross-check.
type saleCVHintsCtxKeyT struct{}

var SaleCVHintsCtxKey = saleCVHintsCtxKeyT{}

// NewSmartSaleService creates a new smart sale service.
// v1.0.119: SMART_SALE_PRIMARY env routes between providers:
//   - "claude" → Anthropic Claude Sonnet 4.6 primary (matches Stock Setup), OpenAI fallback
//   - "openai" or unset → OpenAI GPT-4o primary, Gemini fallback (legacy)
//
// Claude is auto-skipped when ANTHROPIC_API_KEY is missing so we degrade
// gracefully instead of failing the whole pipeline.
// applyProductMRPUpdate writes a new MRP + selling_price to the product AND
// stamps the audit columns (last_mrp_change_at/by_id/by_name/previous) so the
// tenant can see who changed the price for the next 7 days. Single-call
// helper used by every code path that mutates products.mrp:
//   - Smart Sale apply (when user edits MRP on review screen)
//   - Stock Setup Apply (rate→MRP fallback at v1.0.122)
//   - Stock Setup Approve (rate→MRP idempotent reapply at v1.0.113)
//
// Caller passes (tx, productID, tenantID, newMRP, actorID, actorName).
// No-op when newMRP <= 1 or unchanged from current MRP — avoids audit noise
// on no-op writes (the same record approved twice shouldn't show two changes).
// v1.0.123.
func applyProductMRPUpdate(tx *gorm.DB, productID uuid.UUID, tenantID uuid.UUID, newMRP float64, actorID uuid.UUID, actorName string) error {
	if newMRP <= 1 {
		return nil
	}
	var current models.Product
	if err := tx.Select("id, mrp, selling_price").
		Where("id = ? AND tenant_id = ?", productID, tenantID).
		First(&current).Error; err != nil {
		return err
	}
	// No-op gate: same value within ₹0.5 → don't update (the +/- 0.5 absorbs
	// float-rounding noise on numeric(10,2) ↔ float64 round trips).
	if absFloat(current.MRP-newMRP) < 0.5 {
		return nil
	}
	now := time.Now()
	updates := map[string]interface{}{
		"mrp":                       newMRP,
		"selling_price":             newMRP,
		"last_mrp_change_at":        now,
		"last_mrp_change_previous":  current.MRP,
	}
	if actorID != uuid.Nil {
		updates["last_mrp_change_by_id"] = actorID
	}
	if actorName != "" {
		updates["last_mrp_change_by_name"] = actorName
	}
	return tx.Model(&models.Product{}).
		Where("id = ? AND tenant_id = ?", productID, tenantID).
		Updates(updates).Error
}

// resolveActorName fetches a user's display name for the audit columns.
// Falls back to username when first_name/last_name are empty. Best-effort:
// errors return empty string so the MRP write itself never fails on the
// name lookup.
func resolveActorName(tx *gorm.DB, actorID uuid.UUID) string {
	if actorID == uuid.Nil {
		return ""
	}
	var u models.User
	if err := tx.Select("first_name, last_name, username").
		Where("id = ?", actorID).First(&u).Error; err != nil {
		return ""
	}
	full := strings.TrimSpace(u.FirstName + " " + u.LastName)
	if full == "" {
		return u.Username
	}
	return full
}

func NewSmartSaleService(db *database.DB, cache *cache.Cache, geminiService *GeminiOCRService, logger *logrus.Logger, aliasService *alias.AliasService) *SmartSaleService {
	openaiService, _ := NewOpenAIOCRService(logger)
	useOpenAI := openaiService != nil && openaiService.apiKey != ""

	claudeService := NewClaudeOCRService(logger) // returns nil if ANTHROPIC_API_KEY unset
	primary := strings.ToLower(strings.TrimSpace(os.Getenv("SMART_SALE_PRIMARY")))
	useClaude := primary == "claude" && claudeService != nil

	switch {
	case useClaude:
		logger.Info("🧠 SmartSale: Claude Sonnet 4.6 PRIMARY (matching AI Stock Setup), OpenAI fallback")
	case useOpenAI:
		logger.Info("🧠 SmartSale: OpenAI GPT-4o PRIMARY, Gemini fallback (set SMART_SALE_PRIMARY=claude to use Claude)")
	default:
		logger.Info("🔮 SmartSale: Gemini ONLY — neither Claude nor OpenAI configured")
	}

	return &SmartSaleService{
		db:             db,
		cache:          cache,
		geminiService:  geminiService,
		openaiService:  openaiService,
		claudeService:  claudeService,
		logger:         logger,
		sizeNormalizer: NewSizeNormalizer(),
		useOpenAI:      useOpenAI,
		useClaude:      useClaude,
		aliasService:   aliasService,
		cvSidecar:      NewCVSidecarClient(logger),
	}
}

// CVSidecar exposes the cv-sidecar HTTP client so handlers can call
// /quality-check directly (preflight) without holding their own client.
// v1.0.178 — image-quality preflight handler.
func (s *SmartSaleService) CVSidecar() *CVSidecarClient {
	if s == nil {
		return nil
	}
	return s.cvSidecar
}

// hardeningEnabledForTenant gates the v1.0.131 hardening defenses (page-rescue,
// handwritten-band, opus-verifier, etc.) per tenant. Reads SMART_SALE_HARDENING_TENANTS
// env: comma-separated tenant UUIDs, "*" for all, or unset = enabled for all.
// During smoke/rollout this lets us scope new defenses to chhotu's tenant first
// before flipping on globally.
func (s *SmartSaleService) hardeningEnabledForTenant(tenantID uuid.UUID) bool {
	v := strings.TrimSpace(os.Getenv("SMART_SALE_HARDENING_TENANTS"))
	if v == "" || v == "*" {
		return true
	}
	target := tenantID.String()
	for _, t := range strings.Split(v, ",") {
		if strings.EqualFold(strings.TrimSpace(t), target) {
			return true
		}
	}
	return false
}

// SmartSaleRequest represents the request from the Flutter app
type SmartSaleRequest struct {
	ShopID         uuid.UUID `json:"shop_id"`
	ShopName       string    `json:"shop_name"`
	SaleDate       time.Time `json:"date"`
	Category       string    `json:"category"` // "beer" or "non_beer"
	Size           string    `json:"size"`     // Optional size filter like "180ML", "375ML", "750ML"
	ImageData      [][]byte  // Raw image bytes
	SavedImageURLs []string  // URLs of saved receipt images

	// Payment breakdown (passed through from ApplySmartSale)
	CashAmount   float64
	UpiAmount    float64
	CardAmount   float64
	CreditAmount float64

	// v1.0.124 — round-trip integrity, plumbed from SmartSaleApplyRequest.
	IdempotencyKey    string
	ClientPayloadHash string
}

// SmartSaleResult represents the result returned to the Flutter app
// SmartSaleBlockedRow is one row the apply refused to persist, with the
// numbers the operator needs to reconcile it. v1.0.335 — over-sell handling.
// Distinguishes the two block reasons so Flutter can render an accurate card
// instead of the previous one-size "run stock setup" message:
//   - reason="over_sell": product HAS stock but the confirmed sold qty exceeds
//     it (the Moonwalk 50-vs-11 case — almost always an OCR qty misread). The
//     operator fixes the SOLD QTY (or the opening), not the catalog.
//   - reason="no_stock": product has zero shop stock (swap row / run Stock
//     Setup or Purchase Entry).
type SmartSaleBlockedRow struct {
	ProductID   string `json:"product_id,omitempty"`
	ProductName string `json:"product_name"`
	Reason      string `json:"reason"` // "over_sell" | "no_stock"
	Sold        int    `json:"sold"`
	Available   int    `json:"available"`           // system stock + receipt (the cap)
	SystemStock int    `json:"system_stock"`        // DB stock alone
	Receipt     int    `json:"receipt,omitempty"`   // AI-read receipt added to the cap
	Short       int    `json:"short,omitempty"`     // Sold - Available (over-sell only)
	Message     string `json:"message"`             // human-readable, per row
}

type SmartSaleResult struct {
	Status            string                      `json:"status"` // success, partial, failed
	Message           string                      `json:"message"`
	// BlockedRows (v1.0.335) — populated when Status=="blocked". Structured
	// per-row reconciliation data so the review screen can show an honest
	// "sold 50 > stock 11" card with fix actions, never a raw negative close.
	BlockedRows       []SmartSaleBlockedRow       `json:"blocked_rows,omitempty"`
	DetectedShopName  string                      `json:"detected_shop_name,omitempty"`  // Shop name from image header
	DetectedSize      string                      `json:"detected_size,omitempty"`       // Size category from image (e.g., "375ML")
	DetectedSizeML    int                         `json:"detected_size_ml,omitempty"`    // Size in ML
	ExtractedItems    []SmartSaleExtractedItem    `json:"extracted_items"`
	TotalAmount       float64                     `json:"total_amount"`
	SaleRecordID      *string                     `json:"sale_record_id,omitempty"`
	Validation        *SmartSaleValidation        `json:"validation,omitempty"`
	ProcessingDetails *SmartSaleProcessingDetails `json:"processing_details,omitempty"`
	ErrorDetails      string                      `json:"error_details,omitempty"`
	ImageURLs         []string                    `json:"image_urls"`
	// CoverageSummary (v1.0.118) — per-page extraction telemetry. Mirrors
	// SmartStockSetupResult.CoverageSummary so Flutter can render the same
	// "Page 2: 18 of 23 rows recovered" banner and apply the same setup-rescue
	// chip styling. Empty when no pages needed recovery.
	CoverageSummary []SaleCoverageEntry `json:"coverage_summary,omitempty"`
}

// SaleCoverageEntry describes per-image extraction outcome (v1.0.118 + v1.0.131).
// Emitted whenever any defense activity occurred on a page OR the AI's
// RowCountOnPage exceeds the final extracted count. SetupRescueRows counts
// rows auto-injected from the latest approved stock setup.
//
// v1.0.131 added Expected (AI-reported RowCountOnPage) and StillMissing
// (Expected - AfterRecovery, clamped to 0). Flutter renders a red "Page N:
// expected X, recovered Y, still missing Z" banner whenever StillMissing > 0
// so the gap is visible to the user instead of buried in a JSONB blob.
type SaleCoverageEntry struct {
	PageNumber       int    `json:"page_number"`
	MainPassRows     int    `json:"main_pass_rows"`
	AfterVote        int    `json:"after_vote"`
	AfterRecovery    int    `json:"after_recovery"`
	SetupRescueRows  int    `json:"setup_rescue_rows,omitempty"`
	Expected         int    `json:"expected,omitempty"`        // v1.0.131 — AI-reported total row count on this page
	StillMissing     int    `json:"still_missing,omitempty"`   // v1.0.131 — max(0, Expected - AfterRecovery)
	Notes            string `json:"notes,omitempty"`
}

// SaleAlternativeMatch is a candidate product match for user selection
type SaleAlternativeMatch struct {
	ProductID    string  `json:"product_id"`
	BrandName    string  `json:"brand_name"`
	Size         string  `json:"size"`
	SellingPrice float64 `json:"selling_price"`
	Confidence   float64 `json:"confidence"`
}

// SmartSaleExtractedItem represents a single extracted item with validation
type SmartSaleExtractedItem struct {
	ProductID        *string  `json:"product_id,omitempty"`
	BrandName        string   `json:"brand_name"`
	// OriginalAIBrand is the AI's first-guess brand BEFORE the matcher
	// overwrote BrandName with the matched product's name. Surfaces to Flutter
	// so the review screen can preserve it across user mutations and round-trip
	// it on apply for alias-learning. v1.0.117.
	OriginalAIBrand  string   `json:"original_ai_brand,omitempty"`
	Size             string   `json:"size,omitempty"`
	Category         string   `json:"category"`
	Quantity         int      `json:"quantity"`
	Rate             float64  `json:"rate"`
	Amount           float64  `json:"amount"`
	ExpectedAmount   float64  `json:"expected_amount,omitempty"`  // Rate × Quantity
	IsValid          bool     `json:"is_valid"`
	ValidationStatus string   `json:"validation_status"` // matched, low_confidence, ambiguous, not_found
	OpeningStock     *int     `json:"opening_stock,omitempty"`      // From OCR
	DBStock          *int     `json:"db_stock,omitempty"`           // From database (for comparison)
	Receipt          *int     `json:"receipt,omitempty"`            // New stock received
	Total            *int     `json:"total,omitempty"`              // Opening + Receipt
	ClosingStock     *int     `json:"closing_stock,omitempty"`      // Total - Sale
	InventoryRate    *float64 `json:"inventory_rate,omitempty"`
	Confidence       float64  `json:"confidence"`
	Warnings         []string `json:"warnings"`
	Errors           []string `json:"errors"`
	SerialNumber     int      `json:"serial_number"`
	// PageNumber is the 1-based source-image index this item came from.
	// Set server-side (not from AI output); used by per-page validators and
	// lets the Flutter review UI group items under page headers so users
	// can spot "all of page 2 is missing" at a glance.
	PageNumber   int `json:"page_number,omitempty"`
	// RowNumber is the in-page position reported by the AI (1 = first row
	// on that page). Paired with PageNumber to uniquely locate the row
	// without the legacy row_number*1000 math hack.
	RowNumber    int `json:"row_number,omitempty"`
	// New fields for robust matching
	OCRText            string                 `json:"ocr_text,omitempty"`            // Raw handwritten text from register
	MatchedBrandName   string                 `json:"matched_brand_name,omitempty"`  // Full product name from DB
	MatchedExciseBrandName   string           `json:"matched_excise_brand_name,omitempty"`   // Authoritative name from saas_brands (master catalog)
	MatchedExciseDisplayName string           `json:"matched_excise_display_name,omitempty"` // Authoritative short-form excise name
	MatchConfidence    float64                `json:"match_confidence"`              // Product match quality 0-1
	AlternativeMatches []SaleAlternativeMatch `json:"alternative_matches,omitempty"` // Top 3 candidates for user selection
	NeedsReview        bool                   `json:"needs_review"`
	ReviewReason       string                 `json:"review_reason,omitempty"`
	IsZeroQuantity     bool                   `json:"is_zero_quantity,omitempty"`    // qty=0, no sale
	// v1.0.131 — NoStockBlock = true when the matched product has zero shop
	// stock at the moment of extraction. Set by flagStockUnavailable when
	// SMART_SALE_STOCK_GATE=1 (default). The apply path refuses to persist
	// a sale row with NoStockBlock=true unless the user explicitly clears
	// it (via "swap to a product that has stock" or "stop and run Stock
	// Setup first"). Implements the user's "sale only allowed for those
	// who has stocks" rule.
	NoStockBlock       bool                   `json:"no_stock_block,omitempty"`
	// Source tags how this row was produced: "main" (AI extraction), "recovery_pass"
	// (re-extract pass), "setup_rescue" (v1.0.117 — auto-injected from approved
	// stock setup when AI missed the row entirely). Drives Flutter chip rendering.
	Source             string                 `json:"source,omitempty"`
	// v1.0.124 Tier C — client-side row identity carried through the apply
	// payload and written to daily_sales_items.client_row_id for forensic
	// audits ("which UI row produced this saved sale row?").
	ClientRowID        string                 `json:"client_row_id,omitempty"`
	// v1.0.123: MRP-change audit fields, copied from the matched product so
	// Flutter can render the 7-day transparency banner. Empty when product
	// has never had its MRP changed.
	LastMRPChangeAt       *time.Time `json:"last_mrp_change_at,omitempty"`
	LastMRPChangeByName   string     `json:"last_mrp_change_by_name,omitempty"`
	LastMRPChangePrevious *float64   `json:"last_mrp_change_previous,omitempty"`
	// FieldConfidence is per-column confidence (brand/sale/rate/amount).
	// Populated by Claude natively; spread from overall confidence for
	// Gemini/OpenAI fallback. Drives the Flutter amber-underline UI so
	// users can see exactly which column the AI was unsure about.
	FieldConfidence    map[string]float64     `json:"field_confidence,omitempty"`
	// v1.0.133-r6 — user-edited MRP forwarded from apply payload to the
	// daily-sales-items insert. Pre-r6 the conversion at L939 dropped MRP
	// so unitPrice fell back to product.SellingPrice (which itself was
	// updated by applyProductMRPUpdate, but only when MRP > 1 reached the
	// pre-update step). Belt-and-braces: carry MRP through the pipeline.
	MRP float64 `json:"mrp,omitempty"`
	// v1.0.133-r6 — AI's original numeric reads carried through apply for
	// persistence into daily_sales_items.ocr_total / ocr_rate. Pre-r6 these
	// columns existed in the table but were never populated (struct fields
	// missing). Now every saved sale row has the AI's first guess preserved.
	OriginalAIQuantity *int     `json:"original_ai_quantity,omitempty"`
	OriginalAIOpening  *int     `json:"original_ai_opening,omitempty"`
	OriginalAIReceipt  *int     `json:"original_ai_receipt,omitempty"`
	OriginalAIRate     *float64 `json:"original_ai_rate,omitempty"`

	// BrandNotInCatalog is true when the matcher couldn't bind this row to any
	// tenant product — either match_confidence==0 from the start, or the row
	// was demoted by the 0.55 hard-floor REJECT. Flutter renders these in a
	// distinct "pick or skip" bucket so the user doesn't silently lose items.
	BrandNotInCatalog  bool                   `json:"brand_not_in_catalog,omitempty"`

	// SuggestedSale is the math-derived sale value (Opening + Receipt - Closing)
	// emitted ONLY when both Opening and Closing have field_confidence >= 0.9
	// AND it disagrees with the AI-extracted Sale. Flutter surfaces it as a
	// tap-to-accept chip on the Sale cell. Zero / unset = no suggestion.
	SuggestedSale int `json:"suggested_sale,omitempty"`

	// v1.0.157 — explicit stock-context fields the Flutter row UI consumes.
	//   SystemOpening    = current shop stock per the DB (= dbStock; previous
	//                       day's closing).
	//   EffectiveOpening = SystemOpening + (Receipt or 0). The cap that the
	//                       hard-block enforces: qty must be ≤ this number.
	//   PurchaseMissing  = true when AI saw a receipt column on the register
	//                       AND db_stock matches image_opening (without the
	//                       receipt). Means: shopkeeper took delivery but
	//                       hasn't entered Purchase. Flutter shows a yellow
	//                       "Purchase not added" chip so user knows to add it.
	SystemOpening    *int `json:"system_opening,omitempty"`
	EffectiveOpening *int `json:"effective_opening,omitempty"`
	PurchaseMissing  bool `json:"purchase_missing,omitempty"`

	// v1.0.183 Track C — per-row invariant doubts surfaced by the textract
	// math-gate. Each entry is one cell the extractor either auto-fixed
	// (AutoFixed=true; informational only) or flagged for the C2 doubt-popup
	// queue (AutoFixed=false; Flutter walks them one-by-one before the
	// review screen). Empty when every invariant rule passed.
	// Type definition: services/gemini_ocr_service.go.
	CellDoubts []CellDoubt `json:"cell_doubts,omitempty"`
}

// SmartSaleValidation represents overall validation results
type SmartSaleValidation struct {
	// Shop validation
	ShopNameMatch    bool   `json:"shop_name_match"`
	ExpectedShopName string `json:"expected_shop_name,omitempty"`
	DetectedShopName string `json:"detected_shop_name,omitempty"`

	// Size validation
	SizeMatch        bool   `json:"size_match"`
	ExpectedSize     string `json:"expected_size,omitempty"`
	ExpectedSizeML   int    `json:"expected_size_ml,omitempty"`
	DetectedSize     string `json:"detected_size,omitempty"`
	DetectedSizeML   int    `json:"detected_size_ml,omitempty"`

	// Date validation
	DateMatch      bool   `json:"date_match"`
	ExpectedDate   string `json:"expected_date,omitempty"`
	DetectedDate   string `json:"detected_date,omitempty"`

	// Cross-validation messages (explicit fields for Flutter)
	SizeMismatch        bool   `json:"size_mismatch,omitempty"`
	SizeMismatchMessage string `json:"size_mismatch_message,omitempty"`
	DateMismatch        bool   `json:"date_mismatch,omitempty"`
	DateMismatchMessage string `json:"date_mismatch_message,omitempty"`

	// Overall validation
	IsValid       bool     `json:"is_valid"`
	TotalItems    int      `json:"total_items"`
	ValidItems    int      `json:"valid_items"`
	Messages      []string `json:"messages"`
	Warnings      []string `json:"warnings"`       // Non-blocking warnings

	// Issue counts
	StockIssues          int `json:"stock_issues"`           // Insufficient stock
	StockDiscrepancies   int `json:"stock_discrepancies"`    // OCR opening != DB stock
	RateMismatches       int `json:"rate_mismatches"`
	AmountMismatches     int `json:"amount_mismatches"`      // Amount != Rate × Qty
	NotFoundItems        int `json:"not_found_items"`
	BrandNotInCatalogItems int `json:"brand_not_in_catalog_items"` // subset of not_found surfaced as "pick or skip" in Flutter
	NeedsReviewItems     int `json:"needs_review_items"`
	DuplicateMatchItems  int `json:"duplicate_match_items"`
	ZeroQuantityItems    int `json:"zero_quantity_items"`
	AmbiguousItems       int `json:"ambiguous_items"`
	LowConfidenceItems   int `json:"low_confidence_items"`
}

// SmartSaleProcessingDetails represents processing metrics
type SmartSaleProcessingDetails struct {
	OCRTimeMs        int     `json:"ocr_time_ms"`
	ValidationTimeMs int     `json:"validation_time_ms"`
	CreationTimeMs   int     `json:"creation_time_ms"`
	TotalTimeMs      int     `json:"total_time_ms"`
	ImagesProcessed  int     `json:"images_processed"`
	AIModel          string  `json:"ai_model"`
	AvgConfidence    float64 `json:"avg_confidence"`
}

// ProcessSmartSale processes images and creates daily sales entries
func (s *SmartSaleService) ProcessSmartSale(ctx context.Context, req *SmartSaleRequest, userID, tenantID uuid.UUID, userRole string) (*SmartSaleResult, error) {
	startTime := time.Now()

	result := &SmartSaleResult{
		Status:    "pending",
		ImageURLs: []string{},
		ProcessingDetails: &SmartSaleProcessingDetails{
			ImagesProcessed: len(req.ImageData),
			AIModel:         "Fomoa AI",
		},
	}

	s.logger.Infof("🚀 SmartSale: Processing %d images for shop %s", len(req.ImageData), req.ShopID)

	// Save receipt images to disk and collect URLs
	var savedImageURLs []string
	if len(req.ImageData) > 0 {
		tenantShort := tenantID.String()[:8]
		uploadDir := fmt.Sprintf("/app/uploads/daily_sales/%s", tenantShort)
		os.MkdirAll(uploadDir, 0755)

		for i, imgBytes := range req.ImageData {
			filename := fmt.Sprintf("smart_sale_%s_%d_%d.jpg", tenantShort, time.Now().UnixMilli(), i)
			fpath := fmt.Sprintf("%s/%s", uploadDir, filename)
			if err := os.WriteFile(fpath, imgBytes, 0644); err != nil {
				s.logger.Warnf("SmartSale: Failed to save image %d: %v", i, err)
				continue
			}
			imageURL := fmt.Sprintf("/uploads/daily_sales/%s/%s", tenantShort, filename)
			savedImageURLs = append(savedImageURLs, imageURL)
			s.logger.Infof("SmartSale: Saved image %d: %s", i+1, imageURL)
		}
		req.SavedImageURLs = savedImageURLs

		// Cache image URLs in Redis so ApplySmartSale can retrieve them
		// even if the client doesn't send them back
		cacheKey := fmt.Sprintf("smart_sale_images:%s:%s:%s:%s:%s",
			tenantID.String()[:8], req.ShopID.String(), req.SaleDate.Format("2006-01-02"), req.Category, req.Size)
		if err := s.cache.Set(ctx, cacheKey, savedImageURLs, 2*time.Hour); err != nil {
			s.logger.Warnf("SmartSale: Failed to cache image URLs: %v", err)
		} else {
			s.logger.Infof("SmartSale: Cached %d image URLs at key %s", len(savedImageURLs), cacheKey)
		}
	}

	// Validate shop exists and belongs to tenant
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		result.Status = "failed"
		result.Message = "Shop not found or access denied"
		result.ErrorDetails = err.Error()
		return result, nil
	}

	// Step 0: Pre-load ALL products (active + inactive) for matching
	// Smart Sale records from physical registers — shops may sell products marked inactive in app
	var scopedProducts []models.Product
	scopedQuery := s.db.Where("products.tenant_id = ?", tenantID).
		Preload("Brand")
	// v1.0.340 — SHOP-SCOPED MATCHING UNIVERSE (Bug 2 root-cause fix).
	// The sales matcher historically scoped only by tenant, so the AI could
	// match a Malsaii sale row to another shop's product (e.g. FM Tower /
	// Mahua Khera) whenever a same-name SKU existed there. The deduction then
	// landed on the wrong-owner product and the sale record displayed a
	// foreign SKU. This mirrors the purchase-path v365 isolation fix
	// (inventory smart_purchase_service.go loadProductsForMatching) and is the
	// single sufficient guard: the alias fast-path below only ever returns a
	// product that is present in this `scopedProducts` universe, so bounding
	// the universe transitively shop-scopes the alias path too.
	//
	// Restrict to products OWNED by this shop, or global-catalog products
	// (shop_id IS NULL) which any shop may legitimately sell. Kill-switch
	// SMART_SALE_SHOP_SCOPE=0 reverts to the old tenant-wide behaviour.
	shopScopeEnabled := os.Getenv("SMART_SALE_SHOP_SCOPE") != "0"
	if shopScopeEnabled && req.ShopID != uuid.Nil {
		scopedQuery = scopedQuery.Where("(products.shop_id = ? OR products.shop_id IS NULL)", req.ShopID)
	}
	if req.Size != "" {
		// Extract just the ML number from the size (e.g., "90ml (Nip)" -> 90, "750ML" -> 750)
		// Then match against products whose size contains the same ML number.
		//
		// v1.0.304 — was UPPER(size) = '90ML' (exact). Broke as soon as products
		// were stored in the canonical "90ml (Nip)" / "180ml (Quarter)" /
		// "375ml (Half)" / "750ml (Full)" form because UPPER("90ml (Nip)") =
		// "90ML (NIP)" ≠ "90ML". Inventory-scope returned 0, fell back to the
		// shop-less full-catalog branch, and the alias service matched a
		// completely different shop's product (Royal Stag 90ml at FM Tower
		// got picked for a sale at Mahua Khera → db_stock=0 → UI showed
		// "Opening 0 / -12 closing stock"). LIKE 'NNML%' prefix matches all
		// known size encodings ("90ML", "90ml (Nip)", "90ML (NIP)") without
		// pulling in unrelated sizes (190ML doesn't start with 90ML).
		sizeML := parseSizeToML(req.Size)
		if sizeML > 0 {
			sizePattern := fmt.Sprintf("%dML%%", sizeML)
			scopedQuery = scopedQuery.Where("UPPER(products.size) LIKE ?", sizePattern)
		} else {
			scopedQuery = scopedQuery.Where("UPPER(products.size) = UPPER(?)", req.Size)
		}
	}
	if req.Category == "beer" {
		scopedQuery = scopedQuery.Joins("JOIN categories ON categories.id = products.category_id").
			Where("LOWER(categories.name) IN ('beer', 'lager', 'ale', 'rtd')")
	} else if req.Category == "non_beer" {
		scopedQuery = scopedQuery.Joins("JOIN categories ON categories.id = products.category_id").
			Where("LOWER(categories.name) NOT IN ('beer', 'lager', 'ale', 'rtd')")
	}
	// v1.0.137 — INVENTORY-SCOPED MATCHING UNIVERSE.
	// You can't sell what you don't have. Restrict the AI's matching universe
	// to products with stock > 0 at THIS shop. This:
	//   • cuts the prompt size 30-70% (cheaper + faster + fewer hallucinations);
	//   • prevents fuzzy-matching to brands the shop doesn't carry (a major
	//     cause of "ghost rows" in the eval — AI sees similar handwriting and
	//     attaches it to the wrong master brand because all 53 candidates
	//     are in the prompt);
	//   • mirrors how the shopkeeper actually thinks: the register can only
	//     contain rows for things they have on the shelf.
	// Disable the strict mode by setting SMART_SALE_INVENTORY_SCOPE=0 (e.g.
	// for a brand-new shop with no stock_levels populated yet).
	useInventoryScope := os.Getenv("SMART_SALE_INVENTORY_SCOPE") != "0"
	if useInventoryScope && req.ShopID != uuid.Nil {
		// v1.0.174 — tightened inventory scope. The operator's TODAY sale can
		// only legitimately reference a product that:
		//   (a) currently has stock > 0 at this shop, OR
		//   (b) was purchased TODAY at this shop (just arrived, sold same day), OR
		//   (c) appears on a stock-setup recorded TODAY (start-of-day inventory)
		// The 14-day relaxation in v1.0.173 was too loose — it allowed re-tests
		// of historical records to match 0-stock products that are no longer
		// in inventory. Same-day-only is the operator-correct rule.
		//
		// `req.SaleDate` is the date of the sale being recorded; we use it as
		// the temporal anchor (not NOW()) so re-extracting a historical sale
		// scopes correctly to that day's inventory state.
		saleDateAnchor := req.SaleDate
		if saleDateAnchor.IsZero() {
			saleDateAnchor = time.Now()
		}
		dayStart := time.Date(saleDateAnchor.Year(), saleDateAnchor.Month(), saleDateAnchor.Day(), 0, 0, 0, 0, saleDateAnchor.Location())
		dayEnd := dayStart.Add(24 * time.Hour)
		scopedQuery = scopedQuery.
			Joins("LEFT JOIN stocks ON stocks.product_id = products.id AND stocks.shop_id = ? AND stocks.deleted_at IS NULL", req.ShopID).
			Where(`(
				stocks.quantity > 0
				OR EXISTS (
					SELECT 1 FROM stock_purchase_items spi
					JOIN stock_purchases sp ON sp.id = spi.purchase_id
					WHERE spi.product_id = products.id
					  AND sp.shop_id = ?
					  AND sp.purchase_date >= ? AND sp.purchase_date < ?
					  AND sp.status IN ('approved','received')
					  AND spi.deleted_at IS NULL AND sp.deleted_at IS NULL
				)
				OR EXISTS (
					SELECT 1 FROM stock_setup_items ssi
					JOIN stock_setup_records ssr ON ssr.id = ssi.stock_setup_record_id
					WHERE ssi.product_id = products.id
					  AND ssr.shop_id = ?
					  AND ssr.status = 'approved'
					  AND ssr.created_at >= ? AND ssr.created_at < ?
					  AND ssi.deleted_at IS NULL AND ssr.deleted_at IS NULL
				)
			)`, req.ShopID, dayStart, dayEnd, req.ShopID, dayStart, dayEnd)
	}
	scopedQuery.Find(&scopedProducts)
	if useInventoryScope && len(scopedProducts) == 0 {
		// Safety net: if a shop has zero in-stock products of this size+category
		// (e.g. fresh deployment, stock_levels not seeded), fall back to the
		// full scoped catalog so we don't extract an empty list.
		s.logger.Warnf("SmartSale: inventory-scope returned 0 products for shop=%s size=%s — falling back to full catalog", req.ShopID, req.Size)
		fallback := s.db.Where("products.tenant_id = ?", tenantID).Preload("Brand")
		// v1.0.340 — keep the shop-scope guard on the fallback too. This is the
		// path that previously leaked cross-shop matches the hardest (no stock
		// join at all → entire tenant catalog), e.g. a fresh shop matching
		// another shop's SKUs. Same kill-switch as the scoped branch.
		if shopScopeEnabled && req.ShopID != uuid.Nil {
			fallback = fallback.Where("(products.shop_id = ? OR products.shop_id IS NULL)", req.ShopID)
		}
		if req.Size != "" {
			// v1.0.304 — same prefix-LIKE fix as the inventory-scope branch
			// above; see that comment for the full rationale.
			sizeML := parseSizeToML(req.Size)
			if sizeML > 0 {
				fallback = fallback.Where("UPPER(products.size) LIKE ?", fmt.Sprintf("%dML%%", sizeML))
			} else {
				fallback = fallback.Where("UPPER(products.size) = UPPER(?)", req.Size)
			}
		}
		if req.Category == "beer" {
			fallback = fallback.Joins("JOIN categories ON categories.id = products.category_id").
				Where("LOWER(categories.name) IN ('beer', 'lager', 'ale', 'rtd')")
		} else if req.Category == "non_beer" {
			fallback = fallback.Joins("JOIN categories ON categories.id = products.category_id").
				Where("LOWER(categories.name) NOT IN ('beer', 'lager', 'ale', 'rtd')")
		}
		fallback.Find(&scopedProducts)
	}

	// Pass full product names to AI for matching (always use product Name, not Brand.Name)
	var productNames []string
	seen := map[string]bool{}
	for _, p := range scopedProducts {
		name := p.Name
		if !seen[name] {
			productNames = append(productNames, name)
			seen[name] = true
		}
	}
	s.logger.Infof("SmartSale: Loaded %d scoped products (size=%s, category=%s)", len(scopedProducts), req.Size, req.Category)

	// Load excise (master-catalog) metadata for any product that has a saas_brand_id.
	// Smart Sale previously matched register OCR ONLY against tenant product.Name — so
	// handwriting like "8 PM Gold" never scored against the authoritative master name
	// "8 PM Premium Black Superior Whisky". With this map, matching.Product gets the
	// authoritative name/display as additional text sources and the response surfaces
	// the excise label for the user to cross-check.
	exciseInfoMap := s.loadExciseInfoMap(scopedProducts)
	if len(exciseInfoMap) > 0 {
		s.logger.Infof("SmartSale: Loaded excise info for %d/%d products (master-aligned)", len(exciseInfoMap), len(scopedProducts))
	}

	// Step 1: Extract data from images using AI (product-aware).
	//
	// v1.0.138 — sheet-grid pipeline. When SMART_SALE_SHEET_GRID=1, prefer
	// the new architecture (CV /sheet + brand-by-row + 1 batched call per
	// page + math gate verify + Opus retry + image-hash cache). Falls back
	// to the legacy extractFromImages when (a) sheet-grid disabled, OR
	// (b) sheet-grid returns < 60% of CV non-blank rows (CV detected the
	// grid but extraction stalled — keep legacy behaviour as safety net).
	ocrStart := time.Now()
	var extractedItems []ExtractedReceiptItem
	var extractionResult *ReceiptExtractionResult
	var ocrCoverage []SaleCoverageEntry
	var err error
	usedSheetGrid := false
	usedTextract := false
	if textractPipelineEnabledForTenant(tenantID) {
		txItems, txResult, txErr := s.extractWithTextract(ctx, req, tenantID, req.ShopID)
		// v1.0.183 — per-size minimum row floor. The hard >=5 floor blocked
		// 90 ml registers (only 3 SKUs) from ever clearing Textract, forcing
		// every 90 ml job into the slow legacy sheet-grid path (~90s vs ~5s).
		// SMART_SALE_TEXTRACT_MIN_ROWS_BY_SIZE=90:1,750:3 (default 5).
		minRows := textractMinRowsForSize(req.Size)
		incomplete := ""
		// v1.0.215.12 — per-page completeness fallback. detectPageIncomplete
		// already infers an "expected" row count from each page's highest
		// RowNumber. Real-data audit on FM Tower (May 4-8) shows Textract
		// usually returns within 1-4 items of truth on clean camera photos;
		// the May 9 regression returned 10 of ~29 rows on page 1 (35%)
		// because the operator uploaded a photo-gallery screenshot instead
		// of the original camera shot. Threshold tuned to 50% AND
		// maxRowSeen >= 15 so it fires on May-9-style true regressions
		// without triggering on the routine 1-3 row gaps Textract owns
		// successfully. Above gate → fall through to Claude sheet-grid.
		type txCov struct {
			page   int
			got    int
			maxRow int
		}
		var pageCov []txCov
		if txErr == nil && len(txItems) > 0 {
			byPage := make(map[int][2]int)
			for _, it := range txItems {
				e := byPage[it.PageNumber]
				e[0]++
				if it.RowNumber > e[1] {
					e[1] = it.RowNumber
				}
				byPage[it.PageNumber] = e
			}
			pages := make([]int, 0, len(byPage))
			for p := range byPage {
				pages = append(pages, p)
			}
			sort.Ints(pages)
			for _, p := range pages {
				e := byPage[p]
				pageCov = append(pageCov, txCov{page: p, got: e[0], maxRow: e[1]})
				// v1.0.215.13 — maxRowSeen-based gate disabled. It counts ALL
				// register row positions Textract assigned, including blank rows
				// in sparse registers (operator only fills sold items). On a 28-
				// row printed register with 5 sold items, the metric reports
				// "5 of 28 = 82 % missing" which is wrong — it's actually
				// "5 of 5 = 100 % complete". Real signal for May-9-style bad-
				// image regressions needs CV row-detection (deferred to Phase 2)
				// or a field-confidence aggregate (Phase 3). For now Textract
				// accepts on the minRows floor alone; the line of defense
				// against screenshot/bad uploads is the frontend image-quality
				// preflight (v1.0.215.14+).
			}
		}
		switch {
		case txErr != nil:
			s.logger.Warnf("SmartSale: Textract extract failed: %v — falling back", txErr)
		case len(txItems) < minRows:
			s.logger.Warnf("SmartSale: Textract returned %d rows (size=%s floor=%d) — falling back", len(txItems), req.Size, minRows)
		case incomplete != "":
			s.logger.Warnf("SmartSale: Textract page-incomplete (%s) — falling back to sheet-grid", incomplete)
		default:
			extractedItems = txItems
			extractionResult = txResult
			usedTextract = true
			// v1.0.215.11 — populate coverage_summary for the Textract path
			// so downstream telemetry (eval pipeline, coverage banner) sees
			// the real numbers instead of 0/0/0/N.
			ocrCoverage = make([]SaleCoverageEntry, 0, len(pageCov))
			for _, e := range pageCov {
				missing := e.maxRow - e.got
				if missing < 0 {
					missing = 0
				}
				ocrCoverage = append(ocrCoverage, SaleCoverageEntry{
					PageNumber:    e.page,
					MainPassRows:  e.got,
					AfterVote:     e.got,
					AfterRecovery: e.got,
					Expected:      e.maxRow,
					StillMissing:  missing,
					Notes:         "textract",
				})
			}
			s.logger.Infof("SmartSale: Textract produced %d rows (size=%s floor=%d) — skipping legacy extract", len(txItems), req.Size, minRows)
		}
		// v1.0.306 — per-page collapse rescue. Even when Textract globally
		// clears the size-based floor, individual pages may have collapsed
		// (chhotu job b41913a8: 2-image 180ml → page 1 = 18 rows, page 2 =
		// 2 rows with garbage numeric brand cells from column-slip). This
		// detects pages dramatically below the median row count of sibling
		// pages and reruns ONLY those images through the existing fallback
		// OCR (Gemini / Claude), then merges rescued rows back keyed by
		// page_number. Skipped on single-image jobs (no median) and on
		// jobs where every page is sparse (no signal to rescue against).
		// Env: SMART_SALE_PER_PAGE_RESCUE (default ON).
		if usedTextract && perPageRescueEnabled() && len(req.ImageData) > 1 && txResult != nil && len(txResult.PerPageStats) > 0 {
			collapsedPages := detectCollapsedPages(txResult.PerPageStats)
			if len(collapsedPages) > 0 {
				s.logger.Warnf("SmartSale per-page rescue: %d page(s) appear collapsed: %v — trying Textract retry with image enhancement before AI fallback",
					len(collapsedPages), collapsedPages)

				// v1.0.308 — Phase A: Textract retry with image enhancement.
				// chhotu's quality-check reports brightness ~235/255 + low
				// contrast on every page, which collapses Textract's TABLE
				// detector on bottom-of-page rows. enhanceImageForTextract
				// applies a 5/95-percentile linear stretch + gamma=1.25 to
				// normalize exposure before re-calling Textract. ~3-5s total
				// vs ~30s for the Claude path — and keeps everything in AWS
				// (operator directive 2026-05-24).
				//
				// Phase B (Claude fallback) only fires if Phase A still
				// returns fewer rows than the original collapsed page.
				if txClient, cerr := newTextractClient(ctx); cerr == nil {
					// v1.0.310 — Phase A success threshold. A "real" Textract
					// recovery must hit at least max(8, median_raw_count * 0.5).
					// Without this, Phase A2 binarize on chhotu's page 2 returned
					// 5 rows (barely > the 4 from the first pass) and falsely
					// declared "success", blocking the Claude path that previously
					// recovered 12 rows. The threshold caps that false-positive.
					medianRaw := 0
					{
						counts := make([]int, 0, len(txResult.PerPageStats))
						for _, ps := range txResult.PerPageStats {
							if ps.RawRowCount > 0 {
								counts = append(counts, ps.RawRowCount)
							}
						}
						medianRaw = medianInt(counts)
					}
					goodEnough := func(n int) bool {
						floor := medianRaw / 2
						if floor < 8 {
							floor = 8
						}
						return n >= floor
					}

					stillCollapsed := make([]int, 0, len(collapsedPages))
					recoveredItems := make([]ExtractedReceiptItem, 0, 16)
					recoveredSet := make(map[int]bool, len(collapsedPages))
					for _, p := range collapsedPages {
						if p < 1 || p > len(req.ImageData) {
							continue
						}
						origRaw := req.ImageData[p-1]
						origCount := 0
						for _, ps := range txResult.PerPageStats {
							if ps.PageNumber == p {
								origCount = ps.RawRowCount
								break
							}
						}
						// Phase A1 — contrast stretch + TABLES + FORMS.
						items2, _, perr := s.runTextractPageEnhanced(ctx, txClient, origRaw, p)
						if perr == nil && goodEnough(len(items2)) {
							s.logger.Infof("SmartSale per-page rescue Phase A1: page %d Textract retry (contrast) rescued %d rows (was %d, threshold %d) — keeping AWS, skipping Claude",
								p, len(items2), origCount, medianRaw/2)
							recoveredItems = append(recoveredItems, items2...)
							recoveredSet[p] = true
							continue
						}
						s.logger.Warnf("SmartSale per-page rescue Phase A1 (contrast retry): page %d retry got %d rows (was %d, threshold %d) — trying binarized retry",
							p, len(items2), origCount, medianRaw/2)

						// v1.0.309 — Phase A2 — Otsu binarize + TABLES + FORMS.
						// Defeats faint-ink + uneven-exposure cases where the
						// contrast retry didn't lift Textract above the original
						// row count (chhotu's page 2 printed brand column is
						// very faint vs the handwritten rows below).
						items3, _, perr3 := s.runTextractPageBinarized(ctx, txClient, origRaw, p)
						if perr3 == nil && goodEnough(len(items3)) {
							s.logger.Infof("SmartSale per-page rescue Phase A2: page %d Textract retry (binarized) rescued %d rows (was %d, threshold %d) — keeping AWS, skipping Claude",
								p, len(items3), origCount, medianRaw/2)
							recoveredItems = append(recoveredItems, items3...)
							recoveredSet[p] = true
							continue
						}
						// v1.0.310 — Phase A2 fallback: even if not above the
						// quality bar, KEEP whichever retry got the most rows so
						// the Claude path has something to merge against in case
						// it also under-extracts. Track best so far per page.
						bestRetry := items2
						if len(items3) > len(bestRetry) {
							bestRetry = items3
						}
						s.logger.Warnf("SmartSale per-page rescue Phase A2 (binarized retry): page %d retry got %d rows (was %d, threshold %d) — best AWS-retry kept (%d rows), falling through to AI rescue",
							p, len(items3), origCount, medianRaw/2, len(bestRetry))
						_ = bestRetry
						stillCollapsed = append(stillCollapsed, p)
					}
					if len(recoveredItems) > 0 {
						kept := make([]ExtractedReceiptItem, 0, len(extractedItems)+len(recoveredItems))
						for _, it := range extractedItems {
							if !recoveredSet[it.PageNumber] {
								kept = append(kept, it)
							}
						}
						kept = append(kept, recoveredItems...)
						extractedItems = kept
						if extractionResult != nil {
							extractionResult.Items = kept
						}
					}
					// Reduce collapsedPages to only those still needing AI.
					collapsedPages = stillCollapsed
				} else {
					s.logger.Warnf("SmartSale per-page rescue Phase A: Textract client unavailable: %v — going straight to AI", cerr)
				}

				// Phase B (AI fallback) — only fires for pages Phase A couldn't
				// recover. If Phase A handled everything, len(collapsedPages)==0
				// and we skip this entire block, keeping the rescue 100% in AWS.
				if len(collapsedPages) > 0 {
				rescueReq := *req
				rescueReq.ImageData = make([][]byte, 0, len(collapsedPages))
				pageMap := make([]int, 0, len(collapsedPages))
				for _, p := range collapsedPages {
					if p >= 1 && p <= len(req.ImageData) {
						rescueReq.ImageData = append(rescueReq.ImageData, req.ImageData[p-1])
						pageMap = append(pageMap, p)
					}
				}
				rescueCtx := context.WithValue(ctx, SupplementalFallbackCtxKey, true)
				rescueItems, _, _, rescueErr := s.extractFromImages(rescueCtx, &rescueReq, productNames, tenantID)
				switch {
				case rescueErr != nil:
					s.logger.Warnf("SmartSale per-page rescue: extract failed: %v — keeping original Textract output", rescueErr)
				case len(rescueItems) == 0:
					s.logger.Warnf("SmartSale per-page rescue: fallback returned 0 rows — keeping original Textract output")
				default:
					// extractFromImages renumbered pages 1..N inside the
					// partial request; remap back to original page indices.
					for i := range rescueItems {
						idx := rescueItems[i].PageNumber - 1
						if idx >= 0 && idx < len(pageMap) {
							rescueItems[i].PageNumber = pageMap[idx]
						}
					}
					collapsedSet := make(map[int]bool, len(collapsedPages))
					for _, p := range collapsedPages {
						collapsedSet[p] = true
					}
					byPageBefore := map[int]int{}
					for _, it := range extractedItems {
						byPageBefore[it.PageNumber]++
					}
					kept := make([]ExtractedReceiptItem, 0, len(extractedItems)+len(rescueItems))
					for _, it := range extractedItems {
						if !collapsedSet[it.PageNumber] {
							kept = append(kept, it)
						}
					}
					kept = append(kept, rescueItems...)
					byPageAfter := map[int]int{}
					for _, it := range kept {
						byPageAfter[it.PageNumber]++
					}
					extractedItems = kept
					if extractionResult != nil {
						extractionResult.Items = kept
					}
					for _, p := range collapsedPages {
						s.logger.Infof("SmartSale per-page rescue: page %d %d→%d rows (rescued via fallback OCR)",
							p, byPageBefore[p], byPageAfter[p])
					}
				}
				} // close Phase B wrapper: if len(collapsedPages) > 0
			}
		}
	}
	if !usedTextract && SheetGridEnabled() {
		sgItems, sgResult, sgErr := s.tryExtractWithSheetGrid(ctx, req, tenantID, scopedProducts)
		if sgErr == nil && len(sgItems) > 0 {
			extractedItems = sgItems
			extractionResult = sgResult
			usedSheetGrid = true
			s.logger.Infof("SmartSale: sheet-grid produced %d rows — skipping legacy extract", len(sgItems))
		} else if sgErr != nil {
			s.logger.Warnf("SmartSale: sheet-grid extract failed: %v — falling back to legacy", sgErr)
		} else {
			s.logger.Warnf("SmartSale: sheet-grid returned 0 rows — falling back to legacy")
		}
	}
	if !usedTextract && !usedSheetGrid {
		extractedItems, extractionResult, ocrCoverage, err = s.extractFromImages(ctx, req, productNames, tenantID)
		if err != nil {
			s.logger.Errorf("SmartSale: Extraction failed: %v", err)
			result.Status = "failed"
			result.Message = "Failed to extract data from images"
			result.ErrorDetails = err.Error()
			return result, nil
		}
	}
	result.ProcessingDetails.OCRTimeMs = int(time.Since(ocrStart).Milliseconds())

	if len(extractedItems) == 0 {
		result.Status = "failed"
		result.Message = "No items could be extracted from the images"
		return result, nil
	}

	// v1.0.133-r9 — POST-EXTRACTION HALLUCINATION FILTER. Belt-and-braces
	// over P1's prompt instruction. The dominant failure mode on 90 ml
	// registers (92 % not_found in tonight's data) was Claude inventing
	// data into blank register rows + extracting the GRAND TOTAL row at
	// the bottom as a regular item. Even with the prompt rule in place,
	// the model occasionally returns ghost rows. This filter drops them
	// architecturally so downstream matching never sees them.
	//
	// Drop rules (a row is hallucinated when ALL of):
	//   1. Brand is empty/whitespace-only OR matches a TOTAL pattern.
	//   2. AND quantity == 0.
	//   3. AND amount <= 0.
	//   4. AND no opening / closing data either.
	// Also drop rows where the brand text is literally "TOTAL", "GRAND
	// TOTAL", "G.TOTAL", "GR TOTAL" or similar (case-insensitive, after
	// stripping non-alphanumerics) — these are the bottom-of-page sum rows.
	dropped := 0
	totalRowsDropped := 0
	filteredItems := extractedItems[:0]
	for _, it := range extractedItems {
		brandTrim := strings.TrimSpace(it.Brand)
		brandLower := strings.ToLower(brandTrim)
		// Total-row detection: strip non-alphanumerics, check for "total" / "grandtotal".
		var brandNorm strings.Builder
		for _, r := range brandLower {
			if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
				brandNorm.WriteRune(r)
			}
		}
		bn := brandNorm.String()
		isTotalRow := bn == "total" || bn == "grandtotal" || bn == "gtotal" || bn == "grtotal" ||
			strings.HasPrefix(bn, "grandtotal") || strings.HasSuffix(bn, "total")
		if isTotalRow && bn != "" {
			s.logger.Infof("SmartSale: dropped TOTAL-row hallucination — brand='%s' qty=%d amt=%.0f", brandTrim, it.Quantity, priceVal(it.Price))
			totalRowsDropped++
			continue
		}
		// Blank-row detection: empty brand AND all numerics zero.
		opening := 0
		if it.OpeningStock != nil {
			opening = *it.OpeningStock
		}
		closing := 0
		if it.ClosingStock != nil {
			closing = *it.ClosingStock
		}
		recpt := 0
		if it.Receipt != nil {
			recpt = *it.Receipt
		}
		if brandTrim == "" && it.Quantity == 0 && priceVal(it.Price) <= 0 && opening == 0 && closing == 0 && recpt == 0 {
			dropped++
			continue
		}
		// Pure ghost rows: brand is something like "row_number" or "raw_text"
		// (a schema-key leak from the AI) AND no real numeric data.
		if (brandLower == "row_number" || brandLower == "raw_text" || brandLower == "brand") &&
			it.Quantity == 0 && priceVal(it.Price) <= 0 {
			s.logger.Infof("SmartSale: dropped schema-key-leak ghost row — brand='%s'", brandTrim)
			dropped++
			continue
		}
		filteredItems = append(filteredItems, it)
	}
	if dropped > 0 || totalRowsDropped > 0 {
		s.logger.Infof("SmartSale: post-extraction filter dropped %d blank-row hallucinations + %d total-row hallucinations (kept %d of %d)",
			dropped, totalRowsDropped, len(filteredItems), len(extractedItems))
	}
	extractedItems = filteredItems
	if len(extractedItems) == 0 {
		// Edge case: AI returned only ghost rows. Fail rather than create
		// an empty sale.
		result.Status = "failed"
		result.Message = "No real data items extracted — register may be blank or unreadable"
		return result, nil
	}

	// v1.0.116 schema-key sanitizer: defang JSON-parse leaks where the AI
	// returns schema keys ("brand", "raw_text", "name", "size", "rate") as
	// brand VALUES. Job 016a1e0b had 5 such rows on the 750ML sale, including
	// row 22 with brand="raw_text" rate=940 qty=1. When detected, replace
	// Brand with RawText (the actual handwritten text) if available, else
	// mark with a sentinel that the rate-rescue path can route on.
	schemaKeyLeaks := map[string]bool{
		"brand": true, "raw_text": true, "name": true, "size": true,
		"size_text": true, "size_ml": true, "rate": true, "rate_per_unit": true,
		"price": true, "quantity": true, "amount": true, "total": true,
		"opening_stock": true, "closing_stock": true, "receipt": true,
		"row_number": true, "page_number": true, "confidence": true,
	}
	schemaLeakCount := 0
	for i := range extractedItems {
		brandLower := strings.ToLower(strings.TrimSpace(extractedItems[i].Brand))
		if schemaKeyLeaks[brandLower] {
			schemaLeakCount++
			original := extractedItems[i].Brand
			rawTextTrim := strings.TrimSpace(extractedItems[i].RawText)
			rawLower := strings.ToLower(rawTextTrim)
			if rawTextTrim != "" && !schemaKeyLeaks[rawLower] {
				extractedItems[i].Brand = rawTextTrim
				s.logger.Warnf("SmartSale: schema-key leak — brand=%q replaced with RawText=%q (row %d)",
					original, rawTextTrim, extractedItems[i].RowNumber)
			} else {
				// No RawText to recover. Empty brand so the matcher returns nothing
				// and the v1.0.116 rate-rescue path takes over (rate-exact lookup
				// against latest approved stock setup).
				extractedItems[i].Brand = ""
				s.logger.Warnf("SmartSale: schema-key leak — brand=%q cleared, will rely on rate-rescue (rate=%v, row %d)",
					original, extractedItems[i].RatePerUnit, extractedItems[i].RowNumber)
			}
		}
	}
	if schemaLeakCount > 0 {
		s.logger.Infof("SmartSale: sanitized %d schema-key-leak rows (AI returned schema keys as brand values)", schemaLeakCount)
	}

	// v1.0.131 — DEFER qty=0 filter to apply time. Pre-v1.0.131 this loop
	// dropped every zero-qty row before validation, page-rescue, handwritten
	// rescue, or matcher could see them. That was the root cause of chhotu's
	// FM Tower job 50ee29e7 silent loss: AI misread Page 2 handwritten
	// quantities as 0 (or never extracted them at all), the prefilter erased
	// them, no recovery defense ever ran on those rows.
	//
	// New policy:
	//   1. Annotate IsZeroQuantity=true so downstream surfaces can render a
	//      "AI may have missed qty — confirm" chip.
	//   2. Keep rows in the slice through validation/guards/rescue/matcher.
	//   3. Filter qty>0 only at apply time (ApplySmartSale already gates
	//      this — see "if item.Quantity <= 0 { continue }" near L797).
	//
	// The 31/39 not_found regression cited in the v1.0.115 comment was
	// driven by BrandNotInCatalog rows poisoning the matcher pool — that's
	// already prevented downstream by the BrandNotInCatalog flag, so the
	// blanket prefilter was over-broad.
	//
	// Env gate: SMART_SALE_PRESERVE_ZERO_QTY=0 reverts to legacy prefilter
	// behavior in case of regression. Default ON (1).
	preserveZero := os.Getenv("SMART_SALE_PRESERVE_ZERO_QTY") != "0"
	skippedZeroQty := 0
	if !preserveZero {
		preFilterCount := len(extractedItems)
		saleItems := make([]ExtractedReceiptItem, 0, len(extractedItems))
		for _, it := range extractedItems {
			if it.Quantity > 0 {
				saleItems = append(saleItems, it)
			} else {
				skippedZeroQty++
			}
		}
		extractedItems = saleItems
		if skippedZeroQty > 0 {
			s.logger.Infof("SmartSale: [legacy prefilter] dropped %d zero-quantity rows from %d extracted",
				skippedZeroQty, preFilterCount)
		}
		if len(extractedItems) == 0 {
			result.Status = "failed"
			result.Message = fmt.Sprintf("No sale items found — all %d extracted rows had zero quantity", skippedZeroQty)
			return result, nil
		}
	} else {
		zeroQtyCount := 0
		for i := range extractedItems {
			if extractedItems[i].Quantity <= 0 {
				extractedItems[i].IsZeroQuantity = true
				zeroQtyCount++
			}
		}
		if zeroQtyCount > 0 {
			s.logger.Infof("SmartSale: preserving %d zero-quantity rows through pipeline (annotated IsZeroQuantity=true; apply-time filter drops them at submit)", zeroQtyCount)
		}
		// Hard guard: if EVERY extracted row is qty=0 the AI almost certainly
		// failed catastrophically — surface as failed rather than persisting
		// an empty sale.
		nonZero := 0
		for _, it := range extractedItems {
			if it.Quantity > 0 {
				nonZero++
			}
		}
		if nonZero == 0 && len(extractedItems) > 0 {
			result.Status = "failed"
			result.Message = fmt.Sprintf("No sale items found — all %d extracted rows had zero quantity (AI may have failed to read the register)", len(extractedItems))
			return result, nil
		}
		if len(extractedItems) == 0 {
			result.Status = "failed"
			result.Message = "No sale items found — extraction returned empty result"
			return result, nil
		}
	}

	s.logger.Infof("SmartSale: Extracted %d items in %dms (qty=0 rows preserved for rescue/review)", len(extractedItems), result.ProcessingDetails.OCRTimeMs)

	// Step 2: Validate extracted data against inventory
	validationStart := time.Now()
	validatedItems, validation, err := s.validateExtractedData(ctx, req, extractedItems, extractionResult, tenantID, scopedProducts, exciseInfoMap)
	if err != nil {
		result.Status = "failed"
		result.Message = "Failed to validate extracted data"
		result.ErrorDetails = err.Error()
		return result, nil
	}
	result.ProcessingDetails.ValidationTimeMs = int(time.Since(validationStart).Milliseconds())

	// v1.0.134 Track E — tri-source consensus on sale_quantity. Cross-checks
	// the AI's S1 read against S2=opening+receipt-closing and S3=amount/rate.
	// 3-of-3 agree → boost confidence; 2-of-3 corroborate against AI → overwrite
	// with majority; pure disagreement → drop sale-cell confidence + warn.
	// Toggle off with SMART_SALE_QTY_CONSENSUS=0.
	var consensusStats SaleConsensusStats
	validatedItems, consensusStats = applySaleQtyConsensus(validatedItems)
	if consensusStats.Rows3of3 > 0 || consensusStats.Rows2of3 > 0 || consensusStats.RowsDisagree > 0 {
		s.logger.Infof("SmartSale: tri-source consensus — 3of3=%d 2of3=%d disagree=%d single=%d overwrites=%d backfill=%d",
			consensusStats.Rows3of3, consensusStats.Rows2of3, consensusStats.RowsDisagree,
			consensusStats.RowsSingleOnly, consensusStats.QtyOverwrites, consensusStats.BackfillDetected)
	}

	// Phase 3 deterministic guards (parity with Smart Stock Setup): rate-outlier
	// z-score, Sale × Rate ≈ Amount auto-correction, rate-monotonic check.
	// Auto-correction policy (user-confirmed): trust Sale and Rate (the more
	// legible columns), recompute Amount silently with a warning chip — fixes
	// the chhotu FM Tower bug class where AI's Amount was 80-93% off in 9 rows.
	// Run AFTER validation so per-field confidence is set up and AmountMismatches
	// counter from validation is already populated.
	ApplySaleAllGuards(validatedItems)
	tenantCatalogBrands := buildSaleCatalogBrandSet(scopedProducts)
	var phantomCount int
	validatedItems, phantomCount = ApplySalePhantomRowSuppressor(validatedItems, tenantCatalogBrands)
	if phantomCount > 0 {
		validation.Warnings = append(validation.Warnings,
			fmt.Sprintf("Suppressed %d preprinted-only rows (no quantity, brand not in catalog)", phantomCount))
	}

	// v1.0.115: Zero-qty rows already filtered upstream (before validation).
	// Surface count in validation warnings so the user knows the page had
	// non-sale rows that were skipped — visibility, not silence.
	if skippedZeroQty > 0 {
		validation.Warnings = append(validation.Warnings,
			fmt.Sprintf("Skipped %d zero-quantity rows (no sale today)", skippedZeroQty))
	}

	// Deduplicate: if two OCR items matched the same product, merge quantities
	dedupMap := map[string]int{} // product_id -> index in dedupedItems
	var dedupedItems []SmartSaleExtractedItem
	for _, item := range validatedItems {
		if item.ProductID == nil {
			dedupedItems = append(dedupedItems, item) // unmatched items pass through
			continue
		}
		pid := *item.ProductID
		if idx, exists := dedupMap[pid]; exists {
			// Merge: add quantity and amount to existing
			dedupedItems[idx].Quantity += item.Quantity
			dedupedItems[idx].Amount += item.Amount
			s.logger.Infof("SmartSale: Merged duplicate match '%s' (qty +%d) into existing entry", item.BrandName, item.Quantity)
		} else {
			dedupMap[pid] = len(dedupedItems)
			dedupedItems = append(dedupedItems, item)
		}
	}
	validatedItems = dedupedItems

	// v1.0.157 — post-dedup over-sell re-check. flagStockUnavailable runs
	// BEFORE the dedup loop above merges duplicate-matched rows into a single
	// entry. When 3 page-rows all matched product_id X (chhotu's 5005ab2a:
	// "M2 Remix Superior" sn=8 qty=23, sn=11 qty=12, sn=30 qty=32 all matched
	// the same SKU c51b847e), the dedup loop sums qty=23+12+32=67 vs system
	// stock=26 — well over the cap, but the original per-row check saw each
	// piece individually as ≤ stock and didn't flag any. Re-evaluating after
	// the merge catches this class.
	for i := range validatedItems {
		if validatedItems[i].ProductID == nil || *validatedItems[i].ProductID == "" {
			continue
		}
		if validatedItems[i].Quantity <= 0 {
			continue
		}
		// Prefer the explicit EffectiveOpening (set by flagStockUnavailable);
		// fall back to SystemOpening when receipt was zero.
		var cap int
		if validatedItems[i].EffectiveOpening != nil {
			cap = *validatedItems[i].EffectiveOpening
		} else if validatedItems[i].SystemOpening != nil {
			cap = *validatedItems[i].SystemOpening
		} else {
			continue // no stock context — first pass already handled the no-stock case
		}
		if validatedItems[i].Quantity > cap && !validatedItems[i].NoStockBlock {
			validatedItems[i].NoStockBlock = true
			validatedItems[i].NeedsReview = true
			validatedItems[i].Warnings = append(validatedItems[i].Warnings,
				fmt.Sprintf("Sale quantity (%d) exceeds available stock (%d) after duplicate-row merge. Cannot apply.",
					validatedItems[i].Quantity, cap))
			s.logger.Warnf("flagStockUnavailable post-dedup: brand=%q merged qty=%d > eff=%d (block)",
				validatedItems[i].BrandName, validatedItems[i].Quantity, cap)
		}
	}

	// v1.0.184 Track A4 — review-demotion. After every validator/guard has
	// had its turn flagging NeedsReview, walk the items once and DEMOTE rows
	// that meet the "clean" bar:
	//   - no warnings (no math-gate, no invariant, no rate-outlier, etc.)
	//   - no setup-rescue or rescue source (those want operator confirm)
	//   - no NoStockBlock (over-sell guard already fired)
	//   - match_conf  ≥ 0.80
	//   - sale field_conf ≥ 0.85 (or ≥ 0.85 for "quantity" alias)
	//   - no CellDoubts (invariant gate clean)
	//   - qty within effective_opening (defense in depth — already checked above)
	//
	// Demotion: NeedsReview=false. The row keeps confidence numbers intact
	// for the audit log, but Flutter's review chip + the doubt-popup queue
	// both gate on NeedsReview and CellDoubts respectively, so demoted rows
	// disappear from operator attention.
	//
	// Safety: gated by env SMART_SALE_REVIEW_DEMOTION (default ON). Disable
	// per-incident if a hidden bug surfaces.
	if reviewDemotionEnabled() {
		demotionFloor := reviewDemotionMatchFloor()
		fieldFloor := reviewDemotionFieldFloor()
		demoted := 0
		for i := range validatedItems {
			it := &validatedItems[i]
			if !it.NeedsReview {
				continue
			}
			if len(it.Warnings) > 0 {
				continue
			}
			if it.NoStockBlock {
				continue
			}
			if it.Source == "setup_rescue" || it.Source == "recovery_pass" {
				continue
			}
			if len(it.CellDoubts) > 0 {
				continue
			}
			if it.Confidence < demotionFloor {
				continue
			}
			fc := it.FieldConfidence
			saleConf := 0.0
			if fc != nil {
				if v, ok := fc["sale"]; ok {
					saleConf = v
				} else if v, ok := fc["quantity"]; ok {
					saleConf = v
				}
			}
			if saleConf < fieldFloor {
				continue
			}
			cap := -1
			if it.EffectiveOpening != nil {
				cap = *it.EffectiveOpening
			} else if it.SystemOpening != nil {
				cap = *it.SystemOpening
			}
			if cap >= 0 && it.Quantity > cap {
				continue
			}
			it.NeedsReview = false
			demoted++
		}
		if demoted > 0 {
			s.logger.Infof("SmartSale review-demotion: cleared NeedsReview on %d/%d clean rows (match_floor=%.2f field_floor=%.2f)",
				demoted, len(validatedItems), demotionFloor, fieldFloor)
		}
	}

	result.ExtractedItems = validatedItems
	result.Validation = validation

	// v1.0.118: surface coverage_summary so Flutter can render per-page recovery
	// telemetry (mirror of Stock Setup CoverageSummary). Augment ocrCoverage
	// with setup_rescue_rows count by summing items where Source="setup_rescue"
	// per page.
	if len(ocrCoverage) > 0 || true {
		setupRescueByPage := map[int]int{}
		for _, vi := range validatedItems {
			if vi.Source == "setup_rescue" {
				setupRescueByPage[vi.PageNumber]++
			}
		}
		// Add or merge setup-rescue counts into existing coverage entries.
		seen := make(map[int]int, len(ocrCoverage))
		for i, c := range ocrCoverage {
			seen[c.PageNumber] = i
		}
		for p, n := range setupRescueByPage {
			if idx, ok := seen[p]; ok {
				ocrCoverage[idx].SetupRescueRows = n
				if ocrCoverage[idx].Notes == "" {
					ocrCoverage[idx].Notes = fmt.Sprintf("setup rescued %d row(s) AI missed", n)
				} else {
					ocrCoverage[idx].Notes = ocrCoverage[idx].Notes + fmt.Sprintf("; setup rescued %d row(s)", n)
				}
			} else {
				ocrCoverage = append(ocrCoverage, SaleCoverageEntry{
					PageNumber:      p,
					SetupRescueRows: n,
					Notes:           fmt.Sprintf("setup rescued %d row(s) AI missed", n),
				})
			}
		}
		result.CoverageSummary = ocrCoverage
	}

	// Populate detected shop name and size from validation
	result.DetectedShopName = validation.DetectedShopName
	result.DetectedSize = validation.DetectedSize
	result.DetectedSizeML = validation.DetectedSizeML

	// Calculate totals
	var totalAmount float64
	var totalConfidence float64
	for _, item := range validatedItems {
		totalAmount += item.Amount
		totalConfidence += item.Confidence
	}
	result.TotalAmount = totalAmount
	if len(validatedItems) > 0 {
		result.ProcessingDetails.AvgConfidence = totalConfidence / float64(len(validatedItems))
	}

	// Step 3: Return extracted items for user review (no auto-create)
	// Three buckets surfaced to the user:
	//   matched         — validation_status == "matched" (high confidence, ready to save)
	//   needsReview     — low_confidence / ambiguous / inferred-from-delta (qty>0, conf≤0.6)
	//   notInCatalog    — BrandNotInCatalog == true (genuinely unknown brand or sub-floor match)
	matchedCount := 0
	needsReviewCount := 0
	notInCatalogCount := 0
	for _, item := range validatedItems {
		switch {
		case item.BrandNotInCatalog:
			notInCatalogCount++
		case item.ValidationStatus == "matched" && item.Confidence > 0.6:
			matchedCount++
		case item.ProductID != nil:
			needsReviewCount++
		}
	}

	result.ProcessingDetails.TotalTimeMs = int(time.Since(startTime).Milliseconds())

	result.ImageURLs = savedImageURLs

	if matchedCount+needsReviewCount > 0 {
		result.Status = "review"
		result.Message = fmt.Sprintf("Extracted %d items (%d matched, %d need review, %d not in catalog) — confirm before saving",
			len(validatedItems), matchedCount, needsReviewCount, notInCatalogCount)
	} else if notInCatalogCount > 0 {
		result.Status = "review"
		result.Message = fmt.Sprintf("Extracted %d items, %d not in catalog — pick from suggestions or skip",
			len(validatedItems), notInCatalogCount)
	} else {
		result.Status = "failed"
		result.Message = "No items could be matched from images to inventory products"
	}

	s.logger.Infof("SmartSale: Extracted in %dms - Status: %s, Items: %d matched of %d total",
		result.ProcessingDetails.TotalTimeMs, result.Status, matchedCount, len(validatedItems))

	// Save training data async
	saveSmartSaleTrainingData(tenantID.String(), req, result)

	return result, nil
}

// SmartSaleApplyRequest is the request body for confirming a smart sale after user review
type SmartSaleApplyRequest struct {
	ShopID    string   `json:"shop_id" binding:"required"`
	SaleDate  string   `json:"date" binding:"required"`     // YYYY-MM-DD
	Category  string   `json:"category"`                    // beer or non_beer
	Size      string   `json:"size"`                        // size filter
	Notes     string   `json:"notes"`
	ImageURLs []string `json:"image_urls"`                  // Receipt image URLs from ProcessSmartSale
	Items     []SmartSaleApplyItem `json:"items" binding:"required,min=1"`

	// Payment breakdown (record-level)
	CashAmount   float64 `json:"cash_amount"`
	UpiAmount    float64 `json:"upi_amount"`
	CardAmount   float64 `json:"card_amount"`
	CreditAmount float64 `json:"credit_amount"`

	// v1.0.124 — round-trip integrity. IdempotencyKey: stable UUID generated
	// once per submit attempt by Flutter; backend dedups via Redis (24h TTL)
	// so retries collapse to one record. ClientPayloadHash: SHA256 of the
	// canonical items[] JSON; persisted on the saved record so Flutter can
	// verify "what saved == what I submitted" on summary fetch.
	IdempotencyKey    string `json:"idempotency_key,omitempty"`
	ClientPayloadHash string `json:"client_payload_hash,omitempty"`

	// v1.0.184 Track B5 — setup_rescue drop learning. Flutter sends the
	// list of product IDs that were originally auto-injected as Source=
	// "setup_rescue" rows on the result screen. After apply, the backend
	// computes drops = (this set) − (apply payload product IDs) and bumps
	// smart_sale_rescue_drops so the next rescue ranking deprioritizes
	// chronically-dropped products. Empty / missing = no drop tracking
	// (backward compatible with older Flutter builds).
	OriginalRescueProductIDs []string `json:"original_rescue_product_ids,omitempty"`
}

// SmartSaleApplyItem is a single confirmed sale item from the user
type SmartSaleApplyItem struct {
	ProductID    string  `json:"product_id" binding:"required"`
	BrandName    string  `json:"brand_name"`
	Size         string  `json:"size"`
	Quantity     int     `json:"quantity" binding:"required,min=0"`
	Rate         float64 `json:"rate"`
	Amount       float64 `json:"amount"`
	OCRText      string  `json:"ocr_text"`       // original OCR text for alias learning
	WasCorrected bool    `json:"was_corrected"`   // true if user changed the product from AI suggestion
	// v1.0.115: Plumbing for picker-driven alias learning. When the user uses the
	// master-catalog swap picker, BrandName becomes the picked product's name and
	// OCRText is often empty (the swap UI doesn't carry original text forward).
	// OriginalAIBrand preserves the AI's first guess so LearnAlias has a
	// non-empty alias key. OriginalProductID lets us write a negative alias
	// against the rejected match, mirroring Stock Setup.
	OriginalAIBrand   string `json:"original_ai_brand,omitempty"`
	OriginalProductID string `json:"original_product_id,omitempty"`
	// v1.0.123: optional explicit MRP edit from the Smart Sale review screen.
	// When > 0 AND differs from the current product MRP, applyProductMRPUpdate
	// stamps the audit columns (last_mrp_change_at/by_id/by_name/previous) so
	// the tenant sees who changed the price for the next 7 days. Empty (0) =
	// user didn't touch MRP, no product update happens.
	MRP float64 `json:"mrp,omitempty"`

	// v1.0.124 — row provenance. Source is "main" / "recovery_pass" /
	// "setup_rescue" / "manual_add" — Flutter sets this so admin + audit
	// can see how each row got into the sale. ClientRowID is a UUID Flutter
	// assigns when the row first appears on review; survives draft restore.
	Source      string `json:"source,omitempty"`
	ClientRowID string `json:"client_row_id,omitempty"`

	// v1.0.157 — image-side stock context. Flutter has been sending these
	// for several iterations but the Go struct never modeled them, so they
	// were silently dropped. Now used by the apply gate to compute
	// effective_opening = dbStock + Receipt and refuse rows that exceed it.
	// Quantity field above is the CONFIRMED sale qty; these three are the
	// AI's reads of opening + receipt as captured at extraction time.
	OpeningStock *int `json:"opening_stock,omitempty"`
	Receipt      *int `json:"receipt,omitempty"`
	TotalStock   *int `json:"total_stock,omitempty"`

	// v1.0.140 — image-side coordinates Flutter echoes from the original
	// extraction so captureCellCropsForTraining can locate the row's CV
	// cells in the cached /sheet payload without needing to re-extract.
	// PageNumber: 1-based source-image index. RowNumber: in-page CV row idx.
	// Empty (0) when the row was operator-added manually post-extraction.
	PageNumber int `json:"page_number,omitempty"`
	RowNumber  int `json:"row_number,omitempty"`

	// v1.0.133 — Original-AI numeric values, echoed by the client BEFORE user
	// edits, so the apply path can compute (raw, corrected) pairs for the
	// per-shop digit-handwriting learning corpus. Each is a pointer so nil
	// distinguishes "client didn't echo" from "AI extracted 0".
	OriginalAIQuantity *int     `json:"original_ai_quantity,omitempty"`
	OriginalAIOpening  *int     `json:"original_ai_opening,omitempty"`
	OriginalAIReceipt  *int     `json:"original_ai_receipt,omitempty"`
	OriginalAISale     *int     `json:"original_ai_sale,omitempty"`
	OriginalAIClosing  *int     `json:"original_ai_closing,omitempty"`
	OriginalAIRate     *float64 `json:"original_ai_rate,omitempty"`
	OriginalAIAmount   *float64 `json:"original_ai_amount,omitempty"`

	// v1.0.160 — mandatory review enforcement. The client lists every blocking
	// warning the user has explicitly tapped/confirmed on the review screen.
	// On apply, the backend gate (validateWarningConfirmations) refuses to
	// persist any row that still has a blocking warning the user hasn't
	// confirmed. Backward-compatible: missing/empty = "nothing confirmed".
	// Set SMART_SALE_MANDATORY_REVIEW=0 to log-only (rollout escape hatch).
	UserConfirmedWarnings []string `json:"user_confirmed_warnings,omitempty"`
}

// ApplySmartSale creates daily sales entries from user-confirmed items
func (s *SmartSaleService) ApplySmartSale(ctx context.Context, req *SmartSaleApplyRequest, userID, tenantID uuid.UUID, userRole string) (*SmartSaleResult, error) {
	startTime := time.Now()

	result := &SmartSaleResult{
		Status:    "pending",
		ImageURLs: []string{},
		ProcessingDetails: &SmartSaleProcessingDetails{},
	}

	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		result.Status = "failed"
		result.Message = "Invalid shop ID"
		return result, nil
	}

	saleDate, err := time.Parse("2006-01-02", req.SaleDate)
	if err != nil {
		result.Status = "failed"
		result.Message = "Invalid date format (expected YYYY-MM-DD)"
		return result, nil
	}

	// v1.0.123: persist user-edited MRP (if any) BEFORE building daily sale
	// items so the sale's unit_price reflects the new MRP. Each item with
	// MRP > 1 that differs from current product.mrp triggers an audit write
	// (last_mrp_change_at/by_id/by_name/previous) — surfaced on Smart Sale
	// review + inventory cards for 7 days post-change. One transaction so
	// all writes succeed or roll back together.
	if mrpErr := s.db.Transaction(func(tx *gorm.DB) error {
		actorName := resolveActorName(tx, userID)
		for _, item := range req.Items {
			if item.MRP <= 1 || item.ProductID == "" {
				continue
			}
			pid, perr := uuid.Parse(item.ProductID)
			if perr != nil {
				continue
			}
			// v1.0.256 — make this txn TRULY atomic (the comment above already
			// claims it). Previously a per-item failure was swallowed → some
			// products got the new MRP, others silently kept the old price
			// for the same sale (Rockford 530→520 class). Return the error so
			// all MRP edits in this batch roll back together rather than
			// commit a partial, inconsistent set.
			if uErr := applyProductMRPUpdate(tx, pid, tenantID, item.MRP, userID, actorName); uErr != nil {
				s.logger.Errorf("SmartSale: MRP audit update failed for %s: %v — rolling back ALL MRP edits this batch", item.ProductID, uErr)
				return fmt.Errorf("MRP update failed for product %s: %w", item.ProductID, uErr)
			}
			s.logger.Infof("SmartSale: MRP edit by %s — product %s → ₹%.2f", actorName, item.ProductID, item.MRP)
		}
		return nil
	}); mrpErr != nil {
		// Sale itself already committed; MRP edits did NOT apply (atomic
		// rollback). Loud ERROR so it's visible in logs/monitoring.
		s.logger.Errorf("SmartSale: MRP audit txn rolled back — operator MRP edits NOT saved: %v", mrpErr)
	}

	// v1.0.131 — Apply-time stock gate. Build the shop stock map ONCE here so we
	// can refuse to record sales for products with zero shop stock. The user's
	// rule: "sale will only allowed for those who has stocks". The earlier
	// validation pass (flagStockUnavailable) flagged these rows with
	// NoStockBlock=true and surfaced them in the review UI; this is the hard
	// belt-and-braces gate that catches any row the user tried to push through
	// anyway. Returns a structured failure (apply.Status=blocked) listing which
	// products need stock; existing sale rows that DO have stock proceed normally.
	stockGate := os.Getenv("SMART_SALE_STOCK_GATE") != "0"
	var applyShopStock map[string]int
	if stockGate {
		applyShopStock = make(map[string]int)
		var stocks []models.Stock
		if err := s.db.Where("shop_id = ? AND tenant_id = ?", shopID, tenantID).Find(&stocks).Error; err != nil {
			s.logger.Warnf("SmartSale: apply-time stock-gate query failed (allowing sale to proceed without gate): %v", err)
			stockGate = false
		}
		for _, st := range stocks {
			applyShopStock[st.ProductID.String()] = st.Quantity
		}
	}

	// Convert apply items to SmartSaleExtractedItem format for createDailySalesEntries
	var validatedItems []SmartSaleExtractedItem
	var stockBlockedRows []string
	var blockedRowDetails []SmartSaleBlockedRow
	for _, item := range req.Items {
		if item.Quantity <= 0 {
			continue
		}
		// v1.0.131 — stock-gate hard block. Refuse rows where the shop has no
		// stock for this product. The user must either (a) swap the row to a
		// product that has stock, or (b) run AI Stock Setup / Purchase Entry
		// to bring stock in first.
		//
		// v1.0.157 — extended to refuse rows where qty > effective_opening
		// (= dbStock + AI receipt). chhotu's 0a54bcfe sale shipped 4 rows
		// with qty > stock (Officer's 94/55, Iconiq 33/23, M2 Pink 34/18,
		// Stag 25/20) because the previous gate only blocked dbStock<=0.
		// Per user's explicit rule "sale quantity not more than our system
		// stock for that product", this is now non-negotiable.
		//
		// v1.0.335 — split the two block reasons. The previous single message
		// told the operator to "run AI Stock Setup or Purchase Entry" even for
		// the OVER-SELL case (product HAS stock, qty just exceeds it) — wrong
		// advice that confused the Moonwalk 50-vs-11 report. We now emit a
		// distinct, accurate per-row reason + structured numbers so the review
		// screen renders an honest "sold 50 > stock 11" reconciliation card.
		if stockGate {
			name := strings.TrimSpace(item.BrandName)
			if name == "" {
				name = "(unnamed row)"
			}
			dbStock, hasStock := applyShopStock[item.ProductID]
			if !hasStock || dbStock <= 0 {
				msg := fmt.Sprintf("%s has no stock at this shop (sold %d, stock %d). Swap this row to a product that has stock, or run AI Stock Setup / Purchase Entry first.",
					name, item.Quantity, dbStock)
				stockBlockedRows = append(stockBlockedRows, fmt.Sprintf("%s (qty %d, shop stock %d)", name, item.Quantity, dbStock))
				blockedRowDetails = append(blockedRowDetails, SmartSaleBlockedRow{
					ProductID: item.ProductID, ProductName: name, Reason: "no_stock",
					Sold: item.Quantity, Available: 0, SystemStock: dbStock, Message: msg,
				})
				continue
			}
			imageReceipt := 0
			if item.Receipt != nil && *item.Receipt > 0 {
				imageReceipt = *item.Receipt
			}
			effectiveOpening := dbStock + imageReceipt
			if item.Quantity > effectiveOpening {
				msg := fmt.Sprintf("%s: register shows %d sold but only %d in stock (short %d). Check the sold quantity on the register — or correct the opening if stock is wrong.",
					name, item.Quantity, effectiveOpening, item.Quantity-effectiveOpening)
				stockBlockedRows = append(stockBlockedRows,
					fmt.Sprintf("%s (sold %d > available %d, system stock %d + receipt %d)",
						name, item.Quantity, effectiveOpening, dbStock, imageReceipt))
				blockedRowDetails = append(blockedRowDetails, SmartSaleBlockedRow{
					ProductID: item.ProductID, ProductName: name, Reason: "over_sell",
					Sold: item.Quantity, Available: effectiveOpening, SystemStock: dbStock,
					Receipt: imageReceipt, Short: item.Quantity - effectiveOpening, Message: msg,
				})
				continue
			}
		}
		amount := item.Amount
		if amount == 0 && item.Rate > 0 {
			amount = item.Rate * float64(item.Quantity)
		}
		productID := item.ProductID
		validatedItems = append(validatedItems, SmartSaleExtractedItem{
			ProductID:        &productID,
			BrandName:        item.BrandName,
			Size:             item.Size,
			Quantity:         item.Quantity,
			Rate:             item.Rate,
			Amount:           amount,
			ExpectedAmount:   item.Rate * float64(item.Quantity),
			IsValid:          true,
			ValidationStatus: "matched",
			Confidence:       1.0,
			// v1.0.124: carry row provenance through to daily_sales_items.
			Source:      item.Source,
			ClientRowID: item.ClientRowID,
			// v1.0.133-r6 — forward MRP + AI originals so createDailySalesEntries
			// can persist them on insert (Tushar's "edited Rockford 530 saved
			// as 520" + "ocr_total=0 in DB" bug class).
			MRP:                item.MRP,
			OriginalAIQuantity: item.OriginalAIQuantity,
			OriginalAIOpening:  item.OriginalAIOpening,
			OriginalAIReceipt:  item.OriginalAIReceipt,
			OriginalAIRate:     item.OriginalAIRate,
		})
	}
	if len(stockBlockedRows) > 0 {
		s.logger.Warnf("SmartSale: BLOCKED %d sale rows (over-sell / no stock): %s",
			len(stockBlockedRows), strings.Join(stockBlockedRows, "; "))
		// Hard fail: surface the blocked rows so Flutter can render them as
		// per-row reconciliation cards. Prevents partial saves where some
		// rows go through and others silently disappear.
		//
		// v1.0.335 — accurate top-line. Count the two reasons separately so the
		// message matches what the operator actually sees (an over-sell needs a
		// qty fix, not a stock-setup run).
		overSell, noStock := 0, 0
		for _, b := range blockedRowDetails {
			if b.Reason == "over_sell" {
				overSell++
			} else {
				noStock++
			}
		}
		result.Status = "blocked"
		result.BlockedRows = blockedRowDetails
		var parts []string
		if overSell > 0 {
			parts = append(parts, fmt.Sprintf("%d row(s) sell more than the stock on hand", overSell))
		}
		if noStock > 0 {
			parts = append(parts, fmt.Sprintf("%d row(s) reference products with no shop stock", noStock))
		}
		result.Message = fmt.Sprintf("Cannot save: %s. Fix each flagged row before submitting:\n• %s",
			strings.Join(parts, " and "), strings.Join(stockBlockedRows, "\n• "))
		// v1.0.132 — capture learning even when the sale was blocked. The
		// user's review-screen corrections (alias swaps, rate edits) are
		// valid signal regardless of whether the apply was rejected.
		s.captureApplyLearning(tenantID, userID, shopID, req.Items, "blocked_no_stock", req.OriginalRescueProductIDs...)
		s.captureCellCropsForTraining(tenantID, shopID, req, "apply_blocked")
		return result, nil
	}

	if len(validatedItems) == 0 {
		result.Status = "failed"
		result.Message = "No valid items to apply"
		return result, nil
	}

	// Retrieve cached image URLs if client didn't send them.
	//
	// v1.0.203 — do NOT delete the cache after the first read. Previously
	// the eager Delete ran on every Apply, which collided with double-submits:
	// first Apply read+deleted the cache, second Apply (a few seconds later)
	// got an empty list and persisted a record with 0 receipt_images.
	// Real-world hit: Trinken Beverage record d714d53a created 2.45s after
	// its sibling a0ab45c7 (same shop/date/category/size, near-identical
	// items) — the second submit lost all images. The 2h Redis TTL is
	// already short enough to expire naturally; we don't need eager cleanup.
	imageURLs := req.ImageURLs
	if len(imageURLs) == 0 {
		tenantShort := tenantID.String()[:8]
		cacheKey := fmt.Sprintf("smart_sale_images:%s:%s:%s:%s:%s",
			tenantShort, shopID.String(), req.SaleDate, req.Category, req.Size)
		var cachedURLs []string
		if err := s.cache.Get(ctx, cacheKey, &cachedURLs); err == nil && len(cachedURLs) > 0 {
			imageURLs = cachedURLs
			s.logger.Infof("SmartSale: Retrieved %d cached image URLs for apply", len(cachedURLs))
		}
	}

	// Build the internal request for createDailySalesEntries
	internalReq := &SmartSaleRequest{
		ShopID:            shopID,
		SaleDate:          saleDate,
		Category:          req.Category,
		Size:              req.Size,
		SavedImageURLs:    imageURLs,
		CashAmount:        req.CashAmount,
		UpiAmount:         req.UpiAmount,
		CardAmount:        req.CardAmount,
		CreditAmount:      req.CreditAmount,
		IdempotencyKey:    req.IdempotencyKey,
		ClientPayloadHash: req.ClientPayloadHash,
	}

	creationStart := time.Now()
	saleRecordID, err := s.createDailySalesEntries(ctx, internalReq, validatedItems, userID, tenantID, userRole)
	if err != nil {
		result.Status = "failed"
		result.Message = fmt.Sprintf("Failed to create sale: %v", err)
		result.ErrorDetails = err.Error()
		// v1.0.132 — capture learning even on apply failure. Same reasoning as
		// the Stock Setup path: review-screen edits are training signal
		// regardless of whether the SQL insert succeeded. Idempotent.
		s.captureApplyLearning(tenantID, userID, shopID, req.Items, "apply_failed", req.OriginalRescueProductIDs...)
		s.captureCellCropsForTraining(tenantID, shopID, req, "apply_failed")
		return result, nil
	}

	result.Status = "success"
	result.Message = fmt.Sprintf("Sale created with %d items", len(validatedItems))
	result.SaleRecordID = &saleRecordID
	result.ExtractedItems = validatedItems
	result.ProcessingDetails.CreationTimeMs = int(time.Since(creationStart).Milliseconds())
	result.ProcessingDetails.TotalTimeMs = int(time.Since(startTime).Milliseconds())

	// Calculate total
	var totalAmount float64
	for _, item := range validatedItems {
		totalAmount += item.Amount
	}
	result.TotalAmount = totalAmount

	s.logger.Infof("SmartSale: Applied %d items, total ₹%.2f in %dms",
		len(validatedItems), totalAmount, result.ProcessingDetails.TotalTimeMs)

	// v1.0.132 — single learning entrypoint. Always runs (alias upserts +
	// shop_product_rates upserts are all ON CONFLICT, safe to repeat).
	s.captureApplyLearning(tenantID, userID, shopID, req.Items, "applied", req.OriginalRescueProductIDs...)

	// v1.0.133 — per-shop digit-handwriting learning. NOTE: also fired from
	// the blocked + apply_failed paths inside captureApplyLearning (v1.0.193
	// W4 audit P1 fix) so digit corrections are captured even when the apply
	// itself didn't land. The success-path call here is harmless because
	// ocr_digit_corrections uses ON CONFLICT upserts and digit corrections
	// are idempotent.
	s.captureDigitCorrectionsFromApply(tenantID, shopID, req.Items)

	// v1.0.140 — cell-crop capture for the self-trained digit classifier.
	// Async + behind SMART_SALE_TRAIN_CAPTURE=1; no-op when disabled.
	s.captureCellCropsForTraining(tenantID, shopID, req, "apply_success")

	return result, nil
}

// captureDigitCorrectionsFromApply walks the apply payload and persists every
// (raw AI numeric → user-corrected) pair into ocr_digit_corrections so future
// extractions at this shop can include the most-frequent confusions as
// few-shot guidance.
func (s *SmartSaleService) captureDigitCorrectionsFromApply(
	tenantID, shopID uuid.UUID, items []SmartSaleApplyItem,
) {
	if shopID == uuid.Nil || len(items) == 0 {
		return
	}
	var pairs []digitCorrectionPair
	for _, item := range items {
		if !item.WasCorrected {
			continue
		}
		if p := digitCorrectionsFromIntPair("quantity", item.OriginalAIQuantity, item.Quantity); p != nil {
			pairs = append(pairs, *p)
		}
		if p := digitCorrectionsFromFloatPair("rate", item.OriginalAIRate, item.Rate); p != nil {
			pairs = append(pairs, *p)
		}
		if p := digitCorrectionsFromFloatPair("amount", item.OriginalAIAmount, item.Amount); p != nil {
			pairs = append(pairs, *p)
		}
	}
	captureDigitCorrections(s.db.DB, tenantID, shopID, "smart_sale", pairs)
}

// captureApplyLearning is the Smart Sale equivalent of
// SmartStockSetupService.captureApplyLearning — single async hook that runs
// on every apply outcome (applied / apply_failed / blocked) so the user's
// review-screen edits become training signal regardless of whether
// createDailySalesEntries succeeded. Pre-v1.0.132 these blocks were inline
// at the end of ApplySmartSale and only fired on success; that mirrored
// the Stock Setup gate that lost the May 1 90 ml signal.
//
// Idempotent: every callee uses ON CONFLICT upserts.
//
// applyOutcome is logged for telemetry — useful when post-hoc analyzing
// alias hits/misses by outcome bucket.
func (s *SmartSaleService) captureApplyLearning(
	tenantID uuid.UUID,
	userID uuid.UUID,
	shopID uuid.UUID,
	items []SmartSaleApplyItem,
	applyOutcome string,
	originalRescueProductIDs ...string,
) {
	if len(items) == 0 {
		return
	}

	// Alias learning — same three-tier fallback as Stock Setup.
	if s.aliasService != nil {
		go func() {
			defer func() {
				if r := recover(); r != nil {
					s.logger.Warnf("SmartSale: captureApplyLearning(alias) panic recovered: %v (outcome=%s)", r, applyOutcome)
				}
			}()
			aliasHits, negHits := 0, 0
			for _, applyItem := range items {
				// v1.0.163 — relax the "was_corrected" gate. Pre-fix the loop
				// only learned when the operator EXPLICITLY edited (qty / MRP
				// / picker swap). But chhotu's May 4 records had 396 review
				// rows where he just CONFIRMED the AI's flagged value — those
				// confirmations are equally valid signal that "this OCR text
				// IS this product". Now: also learn whenever the OCR text or
				// the AI's first guess differs from the final brand name,
				// regardless of WasCorrected. The hygiene guards in
				// LearnAliasScoped (jaccard, negative-table, length) still
				// reject noise.
				ocrKey := applyItem.OCRText
				if ocrKey == "" {
					ocrKey = applyItem.OriginalAIBrand
				}
				learnFromConfirmation := !applyItem.WasCorrected &&
					applyItem.ProductID != "" &&
					ocrKey != "" &&
					!strings.EqualFold(strings.TrimSpace(ocrKey), strings.TrimSpace(applyItem.BrandName))
				if !applyItem.WasCorrected && !learnFromConfirmation {
					continue
				}
				aliasKey := applyItem.OCRText
				if aliasKey == "" {
					aliasKey = applyItem.OriginalAIBrand
				}
				if aliasKey == "" {
					aliasKey = applyItem.BrandName
				}
				if aliasKey == "" {
					continue
				}

				if applyItem.OriginalProductID != "" && applyItem.OriginalProductID != applyItem.ProductID {
					if rejectedPID, perr := uuid.Parse(applyItem.OriginalProductID); perr == nil {
						// v1.0.160 — shop-scoped negative learn. The shop that
						// taught us "X is not Y" is the shop we warn against;
						// another shop in the same tenant may legitimately
						// mean Y by X.
						if naErr := s.aliasService.LearnNegativeAliasScoped(tenantID, shopID, aliasKey, rejectedPID); naErr == nil {
							negHits++
							s.logger.Infof("SmartSale learning(%s): NEG '%s' rejected -> %s (shop=%s)", applyOutcome, aliasKey, applyItem.OriginalProductID, shopID)
						}
					}
				}

				if applyItem.ProductID == "" {
					continue
				}
				pid, err := uuid.Parse(applyItem.ProductID)
				if err != nil {
					continue
				}
				var product models.Product
				if err := s.db.Select("name").Where("id = ?", pid).First(&product).Error; err == nil {
					// v1.0.160 — shop-scoped positive learn. Anchors the
					// lesson to the shop that did the correction.
					// v1.0.199 — DUAL-WRITE: also write tenant-wide so a
					// sibling shop in the same tenant inherits the alias
					// without re-teaching. LookupAliasCascade still tries
					// shop-exact first so shops can override differently.
					if laErr := s.aliasService.LearnAliasScoped(tenantID, shopID, aliasKey, product.Name, &pid, "user_correction"); laErr == nil {
						aliasHits++
						s.logger.Infof("SmartSale learning(%s): LEARNED '%s' -> '%s' (shop=%s)", applyOutcome, aliasKey, product.Name, shopID)
					}
					if shopID != uuid.Nil {
						if laErr := s.aliasService.LearnAliasScoped(tenantID, uuid.Nil, aliasKey, product.Name, &pid, "user_correction_tenant"); laErr == nil {
							s.logger.Infof("SmartSale learning(%s): LEARNED tenant-wide '%s' -> '%s'", applyOutcome, aliasKey, product.Name)
						}
					}
				}
			}
			s.logger.Infof("SmartSale: captureApplyLearning done — outcome=%s alias_hits=%d neg_hits=%d items=%d", applyOutcome, aliasHits, negHits, len(items))
		}()
	}

	// Per-shop rate learning — independent of alias capture, kept in its
	// own goroutine so a slow product lookup doesn't block alias writes.
	go func() {
		defer func() {
			if r := recover(); r != nil {
				s.logger.Warnf("SmartSale: captureApplyLearning(rate) panic recovered: %v (outcome=%s)", r, applyOutcome)
			}
		}()
		// v1.0.184 Track B4 — relax the rate-write gate from "WasCorrected only"
		// to "any confirmed non-MRP rate". Rationale: when chhotu approves a row
		// AS-IS where the AI extracted a rate the operator agrees with (and that
		// rate differs from MRP), the system should remember it as the shop's
		// effective rate. Pre-fix the loop only learned from edits — but an
		// "approved-as-is" rate is ALSO a confirmed signal that this is the rate
		// being used at this shop. The MRP-divergence guard (>₹0.5) keeps us
		// from re-learning the canonical price as a "shop" rate.
		// Distinguish corrections from confirmations in the source column so
		// downstream consumers can weight them differently.
		for _, applyItem := range items {
			if applyItem.ProductID == "" || applyItem.Rate <= 0 {
				continue
			}
			pid, err := uuid.Parse(applyItem.ProductID)
			if err != nil {
				continue
			}
			var product models.Product
			if err := s.db.Select("mrp").Where("id = ?", pid).First(&product).Error; err != nil {
				continue
			}
			if math.Abs(applyItem.Rate-product.MRP) <= 0.5 {
				continue
			}
			source := "smart_sale_confirmation"
			if applyItem.WasCorrected {
				source = "smart_sale_correction"
			}
			upsertSQL := `
				INSERT INTO shop_product_rates
					(tenant_id, shop_id, product_id, last_user_rate, last_corrected_at, last_corrected_by_id, occurrence_count, source)
				VALUES (?, ?, ?, ?, NOW(), ?, 1, ?)
				ON CONFLICT (tenant_id, shop_id, product_id) DO UPDATE
				SET last_user_rate = EXCLUDED.last_user_rate,
				    last_corrected_at = NOW(),
				    last_corrected_by_id = EXCLUDED.last_corrected_by_id,
				    occurrence_count = shop_product_rates.occurrence_count + 1,
				    source = EXCLUDED.source,
				    updated_at = NOW()
			`
			if err := s.db.Exec(upsertSQL, tenantID, shopID, pid, applyItem.Rate, userID, source).Error; err != nil {
				s.logger.Warnf("SmartSale: shop_product_rates upsert failed for product %s: %v", pid, err)
				continue
			}
			s.logger.Infof("SmartSale learning(%s): LEARNED shop rate %s @ shop %s = ₹%.2f (was MRP ₹%.2f, source=%s)", applyOutcome, pid, shopID, applyItem.Rate, product.MRP, source)
		}
	}()

	// v1.0.184 Track B2 — correction-outcome telemetry. Mirror of inventory
	// SmartStockSetupService.LogCorrectionOutcomes (smart_stock_setup_learning.go),
	// but written from the sales package against the same ai_correction_outcomes
	// table via raw SQL to avoid cross-package model coupling. Each row is one
	// (predicted, actual) pair the calibration / few-shot / distinguisher
	// pipelines feed off. WasCorrected is OR'd from explicit edits AND the
	// payload's was_corrected flag (catches alternative-pick swaps where the
	// brand string didn't change).
	go s.logCorrectionOutcomes(tenantID, shopID, items, applyOutcome)

	// v1.0.184 Track B5 — setup_rescue drop learning. Compute drops as
	// (originally-rescued PIDs) − (apply-payload PIDs). Each PID in the
	// drop set gets its dropped_count bumped per-shop so the next rescue
	// ranking can deprioritize chronically-dropped products. Backward
	// compatible: when Flutter doesn't send the original list, this is a
	// no-op.
	if len(originalRescueProductIDs) > 0 {
		go s.captureRescueDrops(tenantID, shopID, items, originalRescueProductIDs, applyOutcome)
	}

	// v1.0.193 W4-audit P1 fix — wire digit-correction capture into the
	// async hook so it fires on EVERY outcome (applied / blocked / failed),
	// not just success. The legacy success-path call site stayed at
	// ApplySmartSale L1484 to avoid removing a known-good code path; both
	// firing is fine because ocr_digit_corrections uses ON CONFLICT.
	go func() {
		defer func() {
			if r := recover(); r != nil {
				s.logger.Warnf("SmartSale: captureApplyLearning(digit) panic recovered: %v (outcome=%s)", r, applyOutcome)
			}
		}()
		s.captureDigitCorrectionsFromApply(tenantID, shopID, items)
	}()
}

// captureRescueDrops compares the original setup_rescue product set (sent by
// Flutter) to the apply payload to find products the operator deleted before
// applying. Each drop bumps smart_sale_rescue_drops so the next rescue
// ranking deprioritizes that product for this shop.
//
// v1.0.184 Track B5.
func (s *SmartSaleService) captureRescueDrops(
	tenantID uuid.UUID,
	shopID uuid.UUID,
	items []SmartSaleApplyItem,
	originalRescuePIDs []string,
	applyOutcome string,
) {
	defer func() {
		if r := recover(); r != nil {
			s.logger.Warnf("SmartSale: captureRescueDrops panic recovered: %v (outcome=%s)", r, applyOutcome)
		}
	}()
	if tenantID == uuid.Nil || shopID == uuid.Nil {
		return
	}
	applied := make(map[string]struct{}, len(items))
	for _, it := range items {
		if it.ProductID != "" {
			applied[it.ProductID] = struct{}{}
		}
	}
	dropped := make([]string, 0, len(originalRescuePIDs))
	for _, pid := range originalRescuePIDs {
		if pid == "" {
			continue
		}
		if _, kept := applied[pid]; kept {
			continue
		}
		dropped = append(dropped, pid)
	}
	if len(dropped) == 0 {
		s.logger.Infof("SmartSale: rescue-drops outcome=%s shop=%s — operator kept all %d rescue rows", applyOutcome, shopID, len(originalRescuePIDs))
		return
	}
	written := 0
	for _, pidStr := range dropped {
		pid, err := uuid.Parse(pidStr)
		if err != nil {
			continue
		}
		err = s.db.Exec(`
			INSERT INTO smart_sale_rescue_drops
			    (tenant_id, shop_id, product_id, dropped_count, last_dropped_at, first_dropped_at)
			VALUES (?, ?, ?, 1, NOW(), NOW())
			ON CONFLICT (tenant_id, shop_id, product_id) DO UPDATE
			SET dropped_count = smart_sale_rescue_drops.dropped_count + 1,
			    last_dropped_at = NOW()
		`, tenantID, shopID, pid).Error
		if err != nil {
			s.logger.Warnf("SmartSale: rescue-drop upsert failed for %s: %v", pid, err)
			continue
		}
		written++
	}
	s.logger.Infof("SmartSale: rescue-drops outcome=%s shop=%s captured=%d/%d original=%d", applyOutcome, shopID, written, len(dropped), len(originalRescuePIDs))
}

// loadShopRescueDropCounts returns a per-product drop count for this shop.
// Used by Track A5 ranking to push chronically-dropped products to the
// bottom of the rescue list (or out entirely under the cap).
//
// v1.0.184 Track B5.
func (s *SmartSaleService) loadShopRescueDropCounts(tenantID, shopID uuid.UUID) map[string]int {
	out := make(map[string]int)
	if shopID == uuid.Nil || tenantID == uuid.Nil {
		return out
	}
	type row struct {
		ProductID    uuid.UUID `gorm:"column:product_id"`
		DroppedCount int       `gorm:"column:dropped_count"`
	}
	var rows []row
	err := s.db.Raw(`
		SELECT product_id, dropped_count
		  FROM smart_sale_rescue_drops
		 WHERE tenant_id = ? AND shop_id = ?
		   AND last_dropped_at >= NOW() - interval '60 days'
	`, tenantID, shopID).Scan(&rows).Error
	if err != nil {
		s.logger.Warnf("SmartSale: loadShopRescueDropCounts failed: %v", err)
		return out
	}
	for _, r := range rows {
		out[r.ProductID.String()] = r.DroppedCount
	}
	return out
}

// logCorrectionOutcomes writes one ai_correction_outcomes row per apply item.
// Async + non-blocking — failures are logged but never affect the apply.
//
// v1.0.184 Track B2 — Smart Sale finally writes to the same audit table that
// has been live since Stock Setup added it. Backfills calibration data so the
// weekly Platt scaling job has Smart Sale samples too.
func (s *SmartSaleService) logCorrectionOutcomes(
	tenantID uuid.UUID,
	shopID uuid.UUID,
	items []SmartSaleApplyItem,
	applyOutcome string,
) {
	defer func() {
		if r := recover(); r != nil {
			s.logger.Warnf("SmartSale: logCorrectionOutcomes panic recovered: %v (outcome=%s)", r, applyOutcome)
		}
	}()
	if len(items) == 0 {
		return
	}

	now := time.Now()
	written := 0
	for _, it := range items {
		aiBrand := it.OriginalAIBrand
		if aiBrand == "" {
			aiBrand = it.OCRText
		}
		userBrand := it.BrandName

		aiRate := 0.0
		if it.OriginalAIRate != nil {
			aiRate = *it.OriginalAIRate
		}
		aiQty := 0
		if it.OriginalAIQuantity != nil {
			aiQty = *it.OriginalAIQuantity
		} else if it.OriginalAISale != nil {
			aiQty = *it.OriginalAISale
		}

		brandCorrected := userBrand != "" && aiBrand != "" &&
			!strings.EqualFold(strings.TrimSpace(aiBrand), strings.TrimSpace(userBrand))
		rateCorrected := aiRate > 0 && it.Rate > 0 && math.Abs(aiRate-it.Rate) > 0.01
		qtyCorrected := it.OriginalAIQuantity != nil && aiQty != it.Quantity

		wasCorrected := brandCorrected || rateCorrected || qtyCorrected || it.WasCorrected
		// Pure alternative-pick: payload says was_corrected but no field
		// difference detected — flag brand_corrected so the row is still
		// learnable signal (matches inventory's behaviour).
		if wasCorrected && !brandCorrected && !rateCorrected && !qtyCorrected {
			brandCorrected = true
		}

		correctionType := "approved_as_is"
		switch {
		case !wasCorrected:
			correctionType = "approved_as_is"
		case brandCorrected:
			correctionType = "name_edit"
		case rateCorrected:
			correctionType = "rate_edit"
		case qtyCorrected:
			correctionType = "qty_edit"
		default:
			correctionType = "other"
		}

		err := s.db.DB.Exec(`
			INSERT INTO ai_correction_outcomes
				(tenant_id, job_id, item_id, ai_brand, ai_rate, ai_qty, ai_confidence,
				 ai_matched_product, user_brand, user_rate, user_qty, user_matched_product,
				 was_corrected, brand_corrected, rate_corrected, qty_corrected,
				 correction_type, created_at)
			VALUES (?, NULL, NULL, ?, ?, ?, 0,
			        ?, ?, ?, ?, ?,
			        ?, ?, ?, ?,
			        ?, ?)
		`,
			tenantID,
			aiBrand, aiRate, aiQty,
			it.OriginalProductID, userBrand, it.Rate, it.Quantity, it.ProductID,
			wasCorrected, brandCorrected, rateCorrected, qtyCorrected,
			correctionType, now,
		).Error
		if err != nil {
			s.logger.Warnf("SmartSale: ai_correction_outcomes insert failed (shop=%s outcome=%s): %v", shopID, applyOutcome, err)
			continue
		}
		written++
	}
	s.logger.Infof("SmartSale: logCorrectionOutcomes outcome=%s wrote=%d/%d shop=%s", applyOutcome, written, len(items), shopID)
}

// imageExtractionResult holds the result from a single image extraction
type imageExtractionResult struct {
	Index  int
	Result *ReceiptExtractionResult
	Err    error
}

// tryExtractWithSheetGrid runs the v1.0.138 sheet-grid pipeline across all
// images of this request and returns the extracted items in the legacy
// ExtractedReceiptItem shape so the rest of ProcessSmartSale (validate,
// match, post-filter, persist) doesn't need to know the source.
//
// Caller decides fallback policy based on (items, error). Always succeeds
// best-effort — image-hash cache means re-runs are ₹0 even on retry.
func (s *SmartSaleService) tryExtractWithSheetGrid(
	ctx context.Context,
	req *SmartSaleRequest,
	tenantID uuid.UUID,
	scopedProducts []models.Product,
) ([]ExtractedReceiptItem, *ReceiptExtractionResult, error) {
	extractor := NewSaleSheetExtractor(s.db.DB, s.logger, s.cvSidecar, s.aliasService)
	sizeML := parseSizeToML(req.Size)
	printed, err := LoadShopPrintedBrandList(s.db.DB, tenantID, req.ShopID, sizeML, req.Category)
	if err != nil {
		return nil, nil, fmt.Errorf("load printed list: %w", err)
	}
	if len(printed) == 0 {
		// New shop with empty inventory — nothing to align brand-by-row against.
		return nil, nil, fmt.Errorf("no printed brand list for shop=%s size=%dml category=%s",
			req.ShopID, sizeML, req.Category)
	}
	out := make([]ExtractedReceiptItem, 0, 64)
	var totalCost float64
	var totalCalls int
	failedPages := []int{} // 1-based pages where sheet-grid gave us nothing usable
	// v1.0.146 — for SUPPLEMENTAL fallback we need to know which row indices
	// per page sheet-grid already covered, so the legacy merge avoids
	// duplicates while filling gaps.
	coveredRowsByPage := map[int]map[int]bool{} // page → set of row indices already extracted
	// v1.0.148 — track ExpectedRowCount per page so we can detect the
	// "CV under-detected the grid" failure mode (page 2 of 619ec745 had
	// 32 visible rows but CV only found 6 → coverage looked 100% but
	// 26 rows were silently lost).
	expectedRowsByPage := make(map[int]int, len(req.ImageData))
	pageRowsByPage := make(map[int]int, len(req.ImageData))

	// v1.0.150 — PARALLEL per-page extraction. The 4-min runtime on the
	// 30-Apr 375ml job was 100% sequential: page 1 (~110s) then page 2
	// (~95s). Now we fan out one goroutine per page, capped at 3 in-flight
	// to stay under Anthropic concurrency limits. Net wall-clock drops to
	// roughly the slowest page + a small overhead. Result merge keeps the
	// same per-page outputs the sequential loop produced.
	type pageOutcome struct {
		pi      int
		res     *SheetExtractionResult
		err     error
	}
	parallel := len(req.ImageData)
	if parallel > 3 {
		parallel = 3
	}
	if parallel < 1 {
		parallel = 1
	}
	sem := make(chan struct{}, parallel)
	resultsCh := make(chan pageOutcome, len(req.ImageData))
	var wg sync.WaitGroup
	for pi, imgBytes := range req.ImageData {
		wg.Add(1)
		sem <- struct{}{}
		go func(pi int, imgBytes []byte) {
			defer wg.Done()
			defer func() { <-sem }()
			defer func() {
				if r := recover(); r != nil {
					resultsCh <- pageOutcome{pi: pi, err: fmt.Errorf("panic: %v", r)}
				}
			}()
			// v1.0.160 — pass req.ShopID so alias-resolved-brand uses
			// shop-scoped cascade (shop → tenant → fuzzy).
			res, err := extractor.ExtractPage(ctx, imgBytes, pi+1, printed, tenantID, req.ShopID)
			resultsCh <- pageOutcome{pi: pi, res: res, err: err}
		}(pi, imgBytes)
	}
	wg.Wait()
	close(resultsCh)

	// Collect outcomes into a page-indexed slice so we can iterate in page
	// order (cheaper to debug; merge below assumes ascending order).
	pageOutcomes := make([]pageOutcome, len(req.ImageData))
	for o := range resultsCh {
		pageOutcomes[o.pi] = o
	}
	for _, o := range pageOutcomes {
		pi := o.pi
		if o.err != nil {
			s.logger.Warnf("SmartSale sheet-grid page %d failed: %v — marking for legacy fallback", pi+1, o.err)
			failedPages = append(failedPages, pi+1)
			continue
		}
		pageRes := o.res
		totalCost += pageRes.CostINR
		totalCalls += pageRes.CallsMade
		pageRows := 0
		coveredRowsByPage[pi+1] = map[int]bool{}
		for _, r := range pageRes.Rows {
			if r.SaleQty <= 0 {
				continue
			}
			pageRows++
			coveredRowsByPage[pi+1][r.RowIdx] = true
			ric := ExtractedReceiptItem{
				Brand:      r.BrandName,
				Quantity:   r.SaleQty,
				RowNumber:  r.RowIdx,
				PageNumber: pi + 1,
				Confidence: r.Confidence,
				Source:     r.Source,
				Warnings:   r.Warnings,
				FieldConfidence: map[string]float64{"sale": r.Confidence},
			}
			if r.MRP > 0 {
				mrp := r.MRP
				ric.RatePerUnit = &mrp
				amt := r.MRP * float64(r.SaleQty)
				ric.Price = &amt
			}
			ric.RawText = r.BrandName
			out = append(out, ric)
		}
		// v1.0.146 — UNDER-COVERAGE detection. Sheet-grid telling us
		// "page has ~N rows" via SheetExtractionResult while only emitting
		// k << N rows is a major signal that the AI missed multiple rows
		// (handwritten add-ons at bottom, low-contrast handwriting, etc).
		// Trigger fallback when extraction covers < 60% of expected rows
		// — not just 0%. Empirically this catches the dc676664 page 1
		// case (11 of 26 = 42%) where sheet-grid picked the easy printed
		// rows but missed half the page including add-ons. Legacy gets
		// MERGED with sheet-grid (deduped by row index), filling gaps.
		expectedRows := pageRes.ExpectedRowCount
		expectedRowsByPage[pi+1] = expectedRows
		pageRowsByPage[pi+1] = pageRows
		coverage := 1.0
		if expectedRows > 0 {
			coverage = float64(pageRows) / float64(expectedRows)
		}
		if pageRows == 0 {
			s.logger.Warnf("SmartSale sheet-grid page %d produced 0 rows — marking for legacy fallback", pi+1)
			failedPages = append(failedPages, pi+1)
		} else if expectedRows >= 6 && coverage < 0.60 {
			s.logger.Warnf("SmartSale sheet-grid page %d under-coverage: extracted=%d expected=%d (%.0f%%) — marking for SUPPLEMENTAL legacy fallback",
				pi+1, pageRows, expectedRows, coverage*100)
			failedPages = append(failedPages, pi+1)
		}
	}

	// v1.0.148 — CROSS-PAGE CV-under-detection fallback. Catches the silent
	// failure where CV grid-detection only found a few rows on a page that
	// actually has many (job 619ec745 page 2: CV expected=6, AI returned 6,
	// coverage=100%, but the page actually contains 32 register rows). The
	// per-page coverage gate above can't see this — it trusts CV. By comparing
	// each page's expected count against the MAX across all pages on the same
	// register, we flag a page as suspicious when its expected count is < 40%
	// of the largest sibling page (only when at least one sibling has ≥15 rows
	// to set a meaningful baseline).
	if len(expectedRowsByPage) > 1 {
		maxExpected := 0
		for _, c := range expectedRowsByPage {
			if c > maxExpected {
				maxExpected = c
			}
		}
		if maxExpected >= 15 {
			alreadyFailed := map[int]bool{}
			for _, p := range failedPages {
				alreadyFailed[p] = true
			}
			for page, expected := range expectedRowsByPage {
				if alreadyFailed[page] {
					continue
				}
				ratio := float64(expected) / float64(maxExpected)
				if ratio < 0.40 {
					s.logger.Warnf("SmartSale sheet-grid page %d cross-page-undercount: expected=%d (%.0f%% of largest sibling page=%d, extracted=%d) — CV likely missed grid lines, marking for SUPPLEMENTAL legacy fallback",
						page, expected, ratio*100, maxExpected, pageRowsByPage[page])
					failedPages = append(failedPages, page)
				}
			}
		}
	}

	// v1.0.144 + v1.0.146 — per-page legacy fallback w/ supplemental merge.
	// Triggers when sheet-grid produced 0 rows OR < 60% coverage. Legacy
	// rows from the same page are MERGED with sheet-grid rows: dedupe by
	// matching brand or row index, sheet-grid wins on overlap (its math
	// gates are stronger), legacy fills the gaps. This way the dc676664
	// 180ml case (page 1 sheet-grid = 11 rows, image has 26) gets the
	// missing 15 rows back from legacy without losing the 11 sheet-grid
	// already extracted with high confidence.
	if len(failedPages) > 0 {
		s.logger.Warnf("SmartSale sheet-grid: %d/%d pages need legacy fallback (zero or under-coverage)",
			len(failedPages), len(req.ImageData))
		fallbackReq := *req
		fallbackReq.ImageData = make([][]byte, 0, len(failedPages))
		pageMap := make([]int, 0, len(failedPages))
		for _, p := range failedPages {
			fallbackReq.ImageData = append(fallbackReq.ImageData, req.ImageData[p-1])
			pageMap = append(pageMap, p)
		}
		productNames := make([]string, 0, len(scopedProducts))
		for _, sp := range scopedProducts {
			productNames = append(productNames, sp.Name)
		}
		// v1.0.151 — flag this call as supplemental so extractFromImages skips
		// voting + Opus verifier (sheet-grid already produced the high-confidence
		// rows; supplemental just fills gaps). Cuts ~60-90s per page off runtime.
		fbCtx := context.WithValue(ctx, SupplementalFallbackCtxKey, true)
		fbItems, _, _, fbErr := s.extractFromImages(fbCtx, &fallbackReq, productNames, tenantID)
		if fbErr != nil {
			s.logger.Warnf("SmartSale sheet-grid fallback: legacy extract failed: %v", fbErr)
		} else {
			// Pre-build per-page brand-name set from the rows sheet-grid
			// already produced — merge skips legacy rows whose brand
			// matches a sheet-grid row on the same page (sheet-grid had
			// the math gate confirmation; legacy is supplemental).
			sgBrandsByPage := map[int]map[string]bool{}
			for _, r := range out {
				if sgBrandsByPage[r.PageNumber] == nil {
					sgBrandsByPage[r.PageNumber] = map[string]bool{}
				}
				sgBrandsByPage[r.PageNumber][normalizeBrandText(r.Brand)] = true
			}
			merged := 0
			for i := range fbItems {
				orig := pageMap[fbItems[i].PageNumber-1]
				if orig >= 1 {
					fbItems[i].PageNumber = orig
				}
				// Skip if a sheet-grid row already covers this brand+page
				// AND row index. Use brand fuzzy match because legacy + sheet-grid
				// may produce slightly different brand strings for the same
				// printed text. coveredRowsByPage gives a tighter row-index check.
				key := normalizeBrandText(fbItems[i].Brand)
				if sgBrands, ok := sgBrandsByPage[fbItems[i].PageNumber]; ok && sgBrands[key] {
					continue
				}
				if covered, ok := coveredRowsByPage[fbItems[i].PageNumber]; ok && covered[fbItems[i].RowNumber] && fbItems[i].RowNumber > 0 {
					continue
				}
				out = append(out, fbItems[i])
				merged++
			}
			s.logger.Infof("SmartSale sheet-grid fallback: legacy returned %d rows, %d merged into result (gaps filled), %d skipped as duplicates",
				len(fbItems), merged, len(fbItems)-merged)
		}
	}

	s.logger.Infof("SmartSale sheet-grid: %d images → %d rows, ai_calls=%d cost=₹%.2f failed_pages=%v",
		len(req.ImageData), len(out), totalCalls, totalCost, failedPages)
	result := &ReceiptExtractionResult{
		Items:          out,
		ProcessingTime: 0,
	}
	return out, result, nil
}

// extractFromImages uses AI (Claude / OpenAI / Gemini) to extract items from images (processes in parallel).
// v1.0.118: also returns per-image coverage entries (main vs after-vote vs after-recovery
// row counts) so the response can surface what recovered what — matches Stock Setup's
// CoverageSummary shape so the Flutter review can render a common banner.
// v1.0.119: Claude (matching Stock Setup) is the routed primary when SMART_SALE_PRIMARY=claude.
func (s *SmartSaleService) extractFromImages(ctx context.Context, req *SmartSaleRequest, productNames []string, tenantID uuid.UUID) ([]ExtractedReceiptItem, *ReceiptExtractionResult, []SaleCoverageEntry, error) {
	// Check which AI service is available
	switch {
	case s.useClaude && s.claudeService != nil:
		s.logger.Info("🧠 SmartSale: Using Claude Sonnet 4.6 for extraction (primary)")
	case s.useOpenAI && s.openaiService != nil:
		s.logger.Info("🧠 SmartSale: Using OpenAI GPT-4o for extraction")
	case s.geminiService != nil:
		s.logger.Info("🔮 SmartSale: Using Gemini for extraction")
	default:
		return nil, nil, nil, errors.New("no AI service available")
	}

	numImages := len(req.ImageData)
	s.logger.Infof("SmartSale: Starting parallel extraction of %d images", numImages)

	// v1.0.133 — inject per-shop digit-handwriting hints into the call
	// context so the Claude OCR system prompt picks them up. Empty string
	// when no learning yet (FormatDigitConfusionsForPrompt returns "").
	if req.ShopID != uuid.Nil {
		hint := FormatDigitConfusionsForPrompt(LoadTopDigitConfusions(s.db.DB, tenantID, req.ShopID, "smart_sale", 8))
		if hint != "" {
			ctx = context.WithValue(ctx, SaleDigitHintsCtxKey, hint)
			s.logger.Infof("SmartSale: digit-handwriting hint injected (%dch) for shop %s", len(hint), req.ShopID)
		}
		// v1.0.133-r5 — alias-few-shot priors. Pulls top-15 confident
		// (occurrence_count >= 3) tenant aliases. Closes the parity gap
		// with Stock Setup's FewShotPromptHint — Smart Sale was not
		// feeding its 31 captured aliases back into Claude on extraction.
		aliasHint := FormatAliasesForPrompt(LoadTopAliasesForTenant(s.db.DB, tenantID, 3, 15))
		if aliasHint != "" {
			ctx = context.WithValue(ctx, SaleAliasHintsCtxKey, aliasHint)
			s.logger.Infof("SmartSale: alias-few-shot hint injected (%dch) for tenant %s", len(aliasHint), tenantID)
		}
	}

	// Process all images in parallel
	resultChan := make(chan imageExtractionResult, numImages)

	for i, imageData := range req.ImageData {
		go func(index int, data []byte) {
			s.logger.Infof("SmartSale: Processing image %d/%d (size: %d bytes)", index+1, numImages, len(data))

			// Detect image type (default to jpeg)
			imageType := "jpeg"
			if len(data) > 8 && data[0] == 0x89 && data[1] == 0x50 {
				imageType = "png"
			}

			// v1.0.133-r10 — CV sidecar cross-check. Per-image (blank rows
			// vary across pages of a multi-page submission). Best-effort —
			// returns nil on any failure and Claude proceeds without the hint.
			//
			// v1.0.136 Phase 1+2 — when CV is enabled, we use /detect-grid
			// to get rows AND columns in one roundtrip. Rows go on
			// SaleCVRowsCtxKey (existing); columns go on SaleCVColsCtxKey
			// (new). Phase 2 cell-level all-fields uses both.
			imgCtx := ctx
			var cvGrid *CVSidecarGrid
			if s.cvSidecar != nil {
				cvGrid = s.cvSidecar.DetectGrid(ctx, data)
				if cvGrid != nil {
					// Build legacy cvSidecarResponse shape for BuildBlankRowHint.
					legacy := &cvSidecarResponse{
						PageSizePx: cvGrid.PageSizePx,
						Rows:       cvGrid.Rows,
						Diag:       cvGrid.Diag,
					}
					if cvHint := BuildBlankRowHint(legacy); cvHint != "" {
						imgCtx = context.WithValue(imgCtx, SaleCVHintsCtxKey, cvHint)
						s.logger.Infof("SmartSale: CV cross-check hint injected for image %d (%dch)", index+1, len(cvHint))
					}
					if len(cvGrid.Rows) > 0 {
						imgCtx = context.WithValue(imgCtx, SaleCVRowsCtxKey, cvGrid.Rows)
					}
					if cvGrid.Columns.Ok {
						cols := cvGrid.Columns
						imgCtx = context.WithValue(imgCtx, SaleCVColsCtxKey, &cols)
						s.logger.Infof("SmartSale: CV grid detected for image %d — rows=%d, cols=ok (brand %d→%d, sale %d→%d)",
							index+1, len(cvGrid.Rows), cols.XBrandStart, cols.XBrandEnd, cols.XSaleStart, cols.XRateStart)
					}
				} else if cvResp := s.cvSidecar.DetectBlankRows(ctx, data); cvResp != nil {
					// Fallback to row-only when /detect-grid is unavailable.
					if cvHint := BuildBlankRowHint(cvResp); cvHint != "" {
						imgCtx = context.WithValue(imgCtx, SaleCVHintsCtxKey, cvHint)
					}
					if len(cvResp.Rows) > 0 {
						imgCtx = context.WithValue(imgCtx, SaleCVRowsCtxKey, cvResp.Rows)
					}
				}
			}

			var result *ReceiptExtractionResult
			var err error

			// v1.0.119 dispatch: Claude (primary) → OpenAI (fallback) → Gemini (last resort).
			// Try the routed primary, then walk down the chain on failure so a transient
			// API error from one provider doesn't kill the extraction.
			switch {
			case s.useClaude && s.claudeService != nil:
				result, err = s.claudeService.ExtractFromImageWithProducts(imgCtx, data, imageType, productNames)
				if err != nil {
					s.logger.Warnf("Claude extraction failed for image %d, trying OpenAI: %v", index+1, err)
					if s.useOpenAI && s.openaiService != nil {
						result, err = s.openaiService.ExtractFromImageWithProducts(ctx, data, imageType, productNames)
					}
					if err != nil && s.geminiService != nil {
						s.logger.Warnf("OpenAI fallback also failed for image %d, trying Gemini: %v", index+1, err)
						result, err = s.geminiService.ExtractFromImage(ctx, data, imageType)
					}
				} else if result != nil && os.Getenv("SMART_SALE_OPUS_VERIFIER") != "0" && !IsSupplementalFallback(ctx) {
					// v1.0.131 — Opus 4.7 verifier on rows where Sonnet's per-row
					// confidence < 0.85. Sends a header strip + per-row Y-band crop
					// (max 5 rows / page) to Opus, overrides primary on disagreement,
					// bumps confidence to 0.92 on agreement. Best-effort: returns
					// primary unchanged on any error so a transient Opus failure can
					// never block the happy path. PARITY: Stock Setup verifier at
					// smart_stock_setup_claude.go:378-553. Set
					// SMART_SALE_OPUS_VERIFIER=0 to disable.
					verified, vErr := s.claudeService.VerifyLowConfRows(imgCtx, data, imageType, productNames, result.Items)
					if vErr != nil {
						s.logger.Warnf("SmartSale: Opus verifier failed for image %d (keeping primary): %v", index+1, vErr)
					} else {
						result.Items = verified
					}
				}
				// v1.0.135 Track G — column-drift detector. Computes qty*rate
				// vs amount per row; if ≥2 rows on this page disagree by >5 %,
				// the entire page is flagged drifted and Track F (cell-level
				// qty re-read) runs on every row of that page. Catches the
				// silent-misalignment class where consensus agrees on the wrong
				// column. No-op when SMART_SALE_CELL_LEVEL_QTY!=1.
				if result != nil && saleCellLevelEnabled() {
					threshold := saleColumnDriftThreshold()
					thisPageDrifted, driftedRows := detectColumnDriftOnImage(result.Items, threshold)
					if driftedRows > 0 {
						s.logger.Infof("SmartSale: Track G drift detector — image %d: %d drifted rows (threshold %.0f%%, page-flagged=%v)",
							index+1, driftedRows, threshold*100, thisPageDrifted)
					}
					// v1.0.135 Track F — cell-level qty micro-extraction.
					// Re-reads the Sale column for each suspect row using a
					// CV-derived crop. Only overwrites primary when the
					// cell-level result corroborates with at least one of
					// (open-close, amount/rate). Hallucination-safe.
					items2, st := s.claudeService.repairLowConfQtyCells(imgCtx, data, result.Items, index+1, thisPageDrifted)
					if st.Called > 0 {
						result.Items = items2
						s.logger.Infof("SmartSale: Track F — image %d: candidates=%d called=%d replaced=%d avg-conf=%.2f",
							index+1, st.Candidates, st.Called, st.Replaced, st.OverwriteConf)
					}
					// v1.0.136 Phase 2 — all-fields cell-level extraction.
					// When the page is drifted AND CV grid (rows + columns) is
					// available, re-extract EVERY field of EVERY row from
					// x-anchored crops. Replaces the primary's items wholesale
					// for this page when ≥80% of CV rows are accepted by the
					// cell-level math gate.
					if cellAllFieldsEnabled() {
						cvRows, _ := imgCtx.Value(SaleCVRowsCtxKey).([]cvSidecarRow)
						cvCols, _ := imgCtx.Value(SaleCVColsCtxKey).(*CVSidecarColumns)
						nonBlankCVRows := 0
						for _, r := range cvRows {
							if !r.IsBlank {
								nonBlankCVRows++
							}
						}
						shouldRun := thisPageDrifted ||
							(cvCols != nil && cvCols.Ok && nonBlankCVRows > 0 &&
								len(result.Items) < (nonBlankCVRows*9)/10)
						if shouldRun && cvCols != nil && cvCols.Ok && len(cvRows) > 0 {
							replacement, st2, ok := s.claudeService.extractAllFieldsCellLevel(imgCtx, data, cvRows, cvCols, index+1)
							// v1.0.136-fix2 — PER-ROW SELECTIVE MERGE.
							// Build a map of cell-level rows by RowNumber. For
							// each primary item, if a confident cell-level row
							// exists for the SAME RowNumber AND the cell-level
							// value disagrees with primary, prefer cell-level
							// (which is x-anchored, immune to column drift).
							// Math gate inside extractAllFieldsCellLevel has
							// already discounted confidence on rows that
							// fail open+recv-sale=close, so the high-conf
							// rows we keep are arithmetically self-consistent.
							if ok && len(replacement) > 0 {
								// v1.0.137 — ROW-REPLACEMENT mode on dense/drifted pages.
								// When ≥50% of non-blank CV rows produced a confident
								// (≥0.75) cell-level read, replace the entire page's
								// items with cell-level rows. This kills the brand↔row
								// misalignment class because every row's brand AND
								// numbers come from the same y-band (no fuzzy join).
								//
								// Below the 50% threshold we fall back to the per-row
								// merge so individual confident rows still help.
								confidentReplacement := make([]ExtractedReceiptItem, 0, len(replacement))
								for _, r := range replacement {
									if r.Confidence >= 0.75 && r.Quantity > 0 && len(strings.TrimSpace(r.Brand)) >= 3 {
										confidentReplacement = append(confidentReplacement, r)
									}
								}
								denseReplaceFloor := nonBlankCVRows / 2
								if denseReplaceFloor < 1 {
									denseReplaceFloor = 1
								}
								rowReplaced := false
								if (thisPageDrifted || cellAllFieldsForceReplace()) && len(confidentReplacement) >= denseReplaceFloor {
									s.logger.Infof("SmartSale: Phase 2 ROW-REPLACE — image %d: replacing %d primary items with %d cell-level rows (non-blank CV=%d, drifted=%v)",
										index+1, len(result.Items), len(confidentReplacement), nonBlankCVRows, thisPageDrifted)
									for i := range confidentReplacement {
										confidentReplacement[i].Source = "phase2-replace"
									}
									result.Items = confidentReplacement
									rowReplaced = true
								}
								if !rowReplaced {
								byRow := make(map[int]ExtractedReceiptItem, len(replacement))
								for _, r := range replacement {
									if r.Confidence >= 0.85 {
										byRow[r.RowNumber] = r
									}
								}
								merged := 0
								declined := 0
								for i := range result.Items {
									primary := &result.Items[i]
									cl, has := byRow[primary.RowNumber]
									if !has {
										continue
									}
									primaryQty := primary.Quantity
									if cl.Quantity <= 0 || cl.Quantity == primaryQty {
										continue
									}
									// v1.0.136-fix3 — internal consistency:
									// cell-level qty must satisfy
									// qty × rate ≈ amount within 25% using
									// cell-level's OWN rate and amount. This
									// catches the wrong-column hallucination
									// (e.g. cell-level reads opening as sale
									// → qty=70 but amount=240 doesn't match).
									if cl.RatePerUnit != nil && *cl.RatePerUnit > 0 &&
										cl.Price != nil && *cl.Price > 0 {
										expected := float64(cl.Quantity) * *cl.RatePerUnit
										delta := expected - *cl.Price
										if delta < 0 {
											delta = -delta
										}
										relDelta := delta / *cl.Price
										if relDelta > 0.25 {
											s.logger.Infof("SmartSale: Phase 2 row=%d declined merge — qty=%d × rate=%.0f = %.0f vs cell-level amount=%.0f (Δ %.0f%%)",
												primary.RowNumber, cl.Quantity, *cl.RatePerUnit, expected, *cl.Price, relDelta*100)
											declined++
											continue
										}
									}
									// Additional guard: cell-level qty must
									// also satisfy open − close ≈ qty within
									// ±2 using cell-level's OWN open + close.
									if cl.OpeningStock != nil && cl.ClosingStock != nil {
										s2 := *cl.OpeningStock - *cl.ClosingStock
										absDelta := s2 - cl.Quantity
										if absDelta < 0 {
											absDelta = -absDelta
										}
										if absDelta > 2 {
											s.logger.Infof("SmartSale: Phase 2 row=%d declined merge — qty=%d but cell-level open(%d)−close(%d)=%d (Δ %d)",
												primary.RowNumber, cl.Quantity, *cl.OpeningStock, *cl.ClosingStock, s2, absDelta)
											declined++
											continue
										}
									}
									// Passed all guards — apply correction.
									primary.Quantity = cl.Quantity
									if cl.RatePerUnit != nil {
										primary.RatePerUnit = cl.RatePerUnit
									}
									if cl.Price != nil {
										primary.Price = cl.Price
									}
									if cl.OpeningStock != nil {
										primary.OpeningStock = cl.OpeningStock
									}
									if cl.ClosingStock != nil {
										primary.ClosingStock = cl.ClosingStock
									}
									if primary.FieldConfidence == nil {
										primary.FieldConfidence = map[string]float64{}
									}
									primary.FieldConfidence["sale"] = cl.Confidence
									primary.Source = "phase2-merge"
									s.logger.Infof("SmartSale: Phase 2 row-merge — image %d row=%d qty %d → %d (cell-level conf %.2f, internal-consistent)",
										index+1, primary.RowNumber, primaryQty, cl.Quantity, cl.Confidence)
									merged++
								}
								s.logger.Infof("SmartSale: Phase 2 all-fields — image %d: %d/%d non-blank rows accepted, merged %d, declined %d on internal-consistency",
									index+1, st2.RowsAccepted, nonBlankCVRows, merged, declined)
								}
							}
						}
					}
				}
			case s.useOpenAI && s.openaiService != nil:
				result, err = s.openaiService.ExtractFromImageWithProducts(ctx, data, imageType, productNames)
				if err != nil {
					s.logger.Warnf("OpenAI extraction failed for image %d, trying Gemini: %v", index+1, err)
					if s.geminiService != nil {
						result, err = s.geminiService.ExtractFromImage(ctx, data, imageType)
					}
				}
			case s.geminiService != nil:
				result, err = s.geminiService.ExtractFromImage(ctx, data, imageType)
			}

			resultChan <- imageExtractionResult{Index: index, Result: result, Err: err}
		}(i, imageData)
	}

	// Collect results
	var allItems []ExtractedReceiptItem
	var lastResult *ReceiptExtractionResult
	successCount := 0

	// Collect per-image results first so we can run recovery-pass on images
	// that look incomplete before stamping PageNumber. Keeping a stable map
	// by index makes the recovery step straightforward.
	imageResults := make(map[int]*ReceiptExtractionResult, numImages)
	mainPassCounts := make(map[int]int, numImages) // for coverage_summary
	for i := 0; i < numImages; i++ {
		res := <-resultChan
		if res.Err != nil {
			s.logger.Warnf("SmartSale: Failed to extract from image %d: %v", res.Index+1, res.Err)
			continue
		}
		if res.Result != nil {
			imageResults[res.Index] = res.Result
			mainPassCounts[res.Index] = len(res.Result.Items)
			s.logger.Infof("SmartSale: Image %d main-pass extracted %d items", res.Index+1, len(res.Result.Items))
		}
	}

	// ── Self-consistency voting (v1.0.118) ────────────────────────────
	// When SMART_SALE_VOTE >= 2 (default 2 for size>=750 OR multi-image),
	// run a second extraction pass per image at slightly higher temperature
	// and merge new rows by row_number. Cheaper than full multi-pass voting
	// (we don't compare cell-level disagreements yet) but materially recovers
	// rows the first pass missed — same trigger logic as Stock Setup v1.0.103
	// SMART_STOCK_SETUP_VOTE knob. Single-image, smaller-size jobs stay on
	// single-pass to keep costs and latency tight.
	requestedSizeML := parseSizeToML(req.Size)
	// v1.0.136 Phase 3 — accuracy-first default: vote=2 ALWAYS unless
	// SMART_SALE_VOTE is explicitly set otherwise. Eliminates run-to-run
	// variance for ~70% of cells; the rest get escalated via Phase 2
	// cell-level all-fields when columns are drifted or primary missed
	// rows. Cost +50% on Anthropic spend, but accuracy is non-negotiable
	// per user request.
	voteDefault := 2
	_ = requestedSizeML // kept for potential per-size overrides later
	votePasses := voteDefault
	if v := strings.TrimSpace(os.Getenv("SMART_SALE_VOTE")); v != "" {
		if vp, err := strconv.Atoi(v); err == nil && vp >= 1 && vp <= 3 {
			votePasses = vp
		}
	}
	// v1.0.151 — supplemental fallback runs single-pass (sheet-grid already
	// covered the math-confirmed rows; we just need the gaps).
	if IsSupplementalFallback(ctx) {
		votePasses = 1
		s.logger.Infof("SmartSale: supplemental fallback — voting + Opus verifier disabled (single Sonnet pass)")
	}
	if votePasses >= 2 {
		s.logger.Infof("SmartSale: voting enabled (passes=%d, sizeML=%d, images=%d)", votePasses, requestedSizeML, numImages)
		voteCh := make(chan imageExtractionResult, numImages)
		for idx := range imageResults {
			if imageResults[idx] == nil {
				continue
			}
			go func(index int, data []byte) {
				imgType := "jpeg"
				if len(data) > 8 && data[0] == 0x89 && data[1] == 0x50 {
					imgType = "png"
				}
				var r *ReceiptExtractionResult
				var e error
				switch {
				case s.useClaude && s.claudeService != nil:
					r, e = s.claudeService.ExtractFromImageWithProducts(ctx, data, imgType, productNames)
				case s.useOpenAI && s.openaiService != nil:
					r, e = s.openaiService.ExtractFromImageWithProducts(ctx, data, imgType, productNames)
				case s.geminiService != nil:
					r, e = s.geminiService.ExtractFromImage(ctx, data, imgType)
				}
				voteCh <- imageExtractionResult{Index: index, Result: r, Err: e}
			}(idx, req.ImageData[idx])
		}
		// Collect & merge — second-pass rows fill row_number gaps in the first pass.
		expectedVotes := 0
		for idx := range imageResults {
			if imageResults[idx] != nil {
				expectedVotes++
			}
		}
		for v := 0; v < expectedVotes; v++ {
			r := <-voteCh
			if r.Err != nil || r.Result == nil {
				s.logger.Warnf("SmartSale: vote pass for image %d failed: %v", r.Index+1, r.Err)
				continue
			}
			main := imageResults[r.Index]
			if main == nil {
				continue
			}
			seen := make(map[int]struct{}, len(main.Items))
			rowIndex := make(map[int]int, len(main.Items))
			for i, it := range main.Items {
				seen[it.RowNumber] = struct{}{}
				rowIndex[it.RowNumber] = i
			}
			added := 0
			disagreeCount := 0
			// v1.0.131 cell-level voting (PARITY: smart_stock_setup_claude.go:226-349).
			// When the same row_number appears in BOTH passes, walk the cells
			// (Quantity, RatePerUnit, Price, OpeningStock, ClosingStock).
			// Agreement → boost field_confidence to 0.95. Disagreement → drop
			// field_confidence to 0.55, demote item.Confidence to 0.55, append
			// "voting_disagreement" warning. Pre-v1.0.131 vote merge silently
			// kept main-pass values without flagging — meaning if main pass
			// read Sale=12 and second pass read Sale=2, the 12 went through
			// unflagged.
			for _, it := range r.Result.Items {
				if idx, ok := rowIndex[it.RowNumber]; ok {
					// Both passes returned this row — vote per cell.
					existing := &main.Items[idx]
					if existing.FieldConfidence == nil {
						existing.FieldConfidence = make(map[string]float64)
					}
					compareInt := func(field string, a, b int) {
						if a == b {
							if existing.FieldConfidence[field] < 0.95 {
								existing.FieldConfidence[field] = 0.95
							}
						} else {
							existing.FieldConfidence[field] = 0.55
							disagreeCount++
						}
					}
					compareFloat := func(field string, a, b float64) {
						if absFloat(a-b) < 0.01 {
							if existing.FieldConfidence[field] < 0.95 {
								existing.FieldConfidence[field] = 0.95
							}
						} else {
							existing.FieldConfidence[field] = 0.55
							disagreeCount++
						}
					}
					compareIntPtr := func(field string, a, b *int) {
						av, bv := 0, 0
						if a != nil {
							av = *a
						}
						if b != nil {
							bv = *b
						}
						compareInt(field, av, bv)
					}
					compareFloatPtr := func(field string, a, b *float64) {
						av, bv := 0.0, 0.0
						if a != nil {
							av = *a
						}
						if b != nil {
							bv = *b
						}
						compareFloat(field, av, bv)
					}
					if !strings.EqualFold(strings.TrimSpace(existing.Brand), strings.TrimSpace(it.Brand)) {
						existing.FieldConfidence["brand"] = 0.55
						disagreeCount++
					} else if existing.FieldConfidence["brand"] < 0.95 {
						existing.FieldConfidence["brand"] = 0.95
					}
					compareInt("quantity", existing.Quantity, it.Quantity)
					compareFloatPtr("rate", existing.RatePerUnit, it.RatePerUnit)
					compareFloatPtr("amount", existing.Price, it.Price)
					compareIntPtr("opening", existing.OpeningStock, it.OpeningStock)
					compareIntPtr("closing", existing.ClosingStock, it.ClosingStock)
					continue
				}
				// New row not seen in main pass — append.
				main.Items = append(main.Items, it)
				seen[it.RowNumber] = struct{}{}
				rowIndex[it.RowNumber] = len(main.Items) - 1
				added++
			}
			if added > 0 || disagreeCount > 0 {
				s.logger.Infof("SmartSale: vote pass for image %d added %d new rows + %d cell disagreements (main had %d, total now %d)",
					r.Index+1, added, disagreeCount, len(main.Items)-added, len(main.Items))
			}
		}
	}
	// Snapshot post-vote counts for coverage_summary.
	afterVoteCounts := make(map[int]int, numImages)
	for idx, res := range imageResults {
		if res != nil {
			afterVoteCounts[idx] = len(res.Items)
		}
	}

	// ── Recovery pass ─────────────────────────────────────────────────
	// For each image whose main pass looks incomplete (returned fewer items
	// than the highest reported row_number, OR returned zero items on an
	// image the user bothered to upload), issue ONE extra OCR call with a
	// completeness-focused prompt that explicitly tells the model which gap
	// to close. Merge new rows by in-page row_number so we don't double-
	// count the main-pass rows.
	//
	// This directly addresses the user's "page 2 items missing" + "rows
	// 25/26/27 misaligned" complaints. Cost is bounded: at most one extra
	// call per image, only when the main pass looks short.
	// v1.0.157 Time-1 — skip the entire recovery pass on supplemental
	// fallbacks (sheet-grid already produced math-confirmed rows; this
	// pass is just gap-fill via brand-name dedup). Saves ~60-90s per
	// page in the supplemental case.
	skipRecoveryForSupplemental := IsSupplementalFallback(ctx)
	if skipRecoveryForSupplemental {
		s.logger.Infof("SmartSale: supplemental fallback — recovery pass disabled (skip)")
	}
	for idx, mainResult := range imageResults {
		if skipRecoveryForSupplemental {
			break
		}
		if mainResult == nil {
			continue
		}
		mainRows := len(mainResult.Items)
		maxRowSeen := 0
		for _, it := range mainResult.Items {
			if it.RowNumber > maxRowSeen {
				maxRowSeen = it.RowNumber
			}
		}
		// Trigger recovery if:
		//   (a) main pass returned zero items despite a successful call,
		//   (b) main pass returned fewer items than highest row_number - 2
		//       slack (the -2 absorbs one or two rows the AI legitimately
		//       skipped as blank-brand rows; larger gaps are real misses).
		needsRecovery := false
		switch {
		case mainRows == 0:
			needsRecovery = true
			s.logger.Warnf("SmartSale: image %d returned 0 items — triggering recovery pass", idx+1)
		case maxRowSeen > mainRows+2:
			needsRecovery = true
			s.logger.Warnf("SmartSale: image %d has max_row=%d but only %d items — triggering recovery pass (gap=%d)",
				idx+1, maxRowSeen, mainRows, maxRowSeen-mainRows)
		}
		if !needsRecovery {
			continue
		}
		// Detect image type from bytes (same 2-byte PNG sniff as main pass).
		imageType := "jpeg"
		if len(req.ImageData[idx]) > 8 && req.ImageData[idx][0] == 0x89 && req.ImageData[idx][1] == 0x50 {
			imageType = "png"
		}
		var recovery *ReceiptExtractionResult
		var rerr error
		switch {
		case s.useClaude && s.claudeService != nil:
			recovery, rerr = s.claudeService.ExtractRecoveryPass(ctx, req.ImageData[idx], imageType, productNames, mainRows, maxRowSeen)
			if rerr != nil && s.useOpenAI && s.openaiService != nil {
				s.logger.Warnf("SmartSale: Claude recovery failed for image %d (%v) — falling back to OpenAI", idx+1, rerr)
				recovery, rerr = s.openaiService.ExtractRecoveryPass(ctx, req.ImageData[idx], imageType, productNames, mainRows, maxRowSeen)
			}
			if rerr != nil && s.geminiService != nil {
				s.logger.Warnf("SmartSale: OpenAI recovery failed for image %d (%v) — falling back to Gemini", idx+1, rerr)
				recovery, rerr = s.geminiService.ExtractRecoveryPass(ctx, req.ImageData[idx], imageType, productNames, mainRows, maxRowSeen)
			}
		case s.useOpenAI && s.openaiService != nil:
			recovery, rerr = s.openaiService.ExtractRecoveryPass(ctx, req.ImageData[idx], imageType, productNames, mainRows, maxRowSeen)
			if rerr != nil && s.geminiService != nil {
				s.logger.Warnf("SmartSale: OpenAI recovery failed for image %d (%v) — falling back to Gemini", idx+1, rerr)
				recovery, rerr = s.geminiService.ExtractRecoveryPass(ctx, req.ImageData[idx], imageType, productNames, mainRows, maxRowSeen)
			}
		case s.geminiService != nil:
			recovery, rerr = s.geminiService.ExtractRecoveryPass(ctx, req.ImageData[idx], imageType, productNames, mainRows, maxRowSeen)
		}
		if rerr != nil || recovery == nil {
			s.logger.Warnf("SmartSale: recovery pass failed for image %d: %v (keeping main-pass rows)", idx+1, rerr)
			continue
		}
		// Merge: dedupe by in-page row_number. Main-pass row wins when both
		// passes hit the same row (main pass has had validation already; we
		// don't want the recovery pass to overwrite confident data).
		seen := make(map[int]struct{}, mainRows)
		for _, it := range mainResult.Items {
			seen[it.RowNumber] = struct{}{}
		}
		added := 0
		for _, it := range recovery.Items {
			if _, ok := seen[it.RowNumber]; ok {
				continue
			}
			mainResult.Items = append(mainResult.Items, it)
			seen[it.RowNumber] = struct{}{}
			added++
		}
		s.logger.Infof("SmartSale: recovery pass for image %d added %d rows (main had %d, total now %d)",
			idx+1, added, mainRows, len(mainResult.Items))
	}

	// ── Page-rescue gate (v1.0.131) ───────────────────────────────────
	// PARITY: smart_stock_setup_service.go:380-446. The recovery pass
	// above only fires when the AI's max_row exceeds extracted rows + 2.
	// On chhotu's job 50ee29e7 Page 2 the AI returned 6 rows with
	// max_row=6 — recovery never triggered, but the page actually had 38
	// rows. Page-rescue closes that gap by trusting the AI's
	// RowCountOnPage report (which it now emits per the v1.0.131 prompt
	// extension): when actual extracted < 70% of expected AND average
	// confidence is < 0.85 (sparse-and-uncertain, not sparse-but-clean),
	// re-OCR the full page via ExtractHandwrittenBand.
	//
	// Env gate: SMART_SALE_PAGE_RESCUE=0 disables. Default ON. Tenant-
	// scoped via SMART_SALE_HARDENING_TENANTS in NewSmartSaleService.
	pageRescueCounts := make(map[int]int, numImages)
	pageRescueTriggered := make(map[int]bool, numImages)
	pageActualBeforeRescue := make(map[int]int, numImages)
	// v1.0.157 Time-1 — page-rescue is the slowest pass (full handwritten-band
	// re-OCR, ~60s/page). Disabled on supplemental fallbacks since the
	// math-confirmed sheet-grid rows already cover the structured part and
	// supplemental is only meant to fill gaps via the cheap main pass.
	pageRescueDisabledSupplemental := IsSupplementalFallback(ctx)
	if os.Getenv("SMART_SALE_PAGE_RESCUE") != "0" && s.hardeningEnabledForTenant(tenantID) && !pageRescueDisabledSupplemental {
		for idx, mainResult := range imageResults {
			if mainResult == nil {
				continue
			}
			expected := mainResult.RowCountOnPage
			actual := len(mainResult.Items)
			pageActualBeforeRescue[idx] = actual
			if expected < 6 {
				continue
			}
			if float64(actual) >= 0.7*float64(expected) {
				continue
			}
			// Confidence guard: only rescue when extracted rows are uncertain.
			// A page with 5/8 high-confidence rows usually means the AI made a
			// honest count and the missing rows are the actually-blank ones at
			// the bottom of the page; rescuing would just hallucinate them.
			pageConf := 0.0
			for _, it := range mainResult.Items {
				pageConf += it.Confidence
			}
			avgConf := 0.0
			if actual > 0 {
				avgConf = pageConf / float64(actual)
			}
			if actual > 0 && avgConf >= 0.85 {
				s.logger.Infof("SmartSale: page-rescue SKIPPED for image %d — sparse but high-confidence (%d/%d=%.0f%%, avg conf %.2f)",
					idx+1, actual, expected, 100*float64(actual)/float64(expected), avgConf)
				continue
			}
			s.logger.Warnf("SmartSale: page-rescue TRIGGERED for image %d — expected %d rows, got %d (%.0f%%), avg conf %.2f",
				idx+1, expected, actual, 100*float64(actual)/float64(expected), avgConf)
			imageType := "jpeg"
			if len(req.ImageData[idx]) > 8 && req.ImageData[idx][0] == 0x89 && req.ImageData[idx][1] == 0x50 {
				imageType = "png"
			}
			var rescue *ReceiptExtractionResult
			var rerr error
			switch {
			case s.useClaude && s.claudeService != nil:
				rescue, rerr = s.claudeService.ExtractHandwrittenBand(ctx, req.ImageData[idx], imageType, productNames, 1, expected)
				if rerr != nil && s.useOpenAI && s.openaiService != nil {
					s.logger.Warnf("SmartSale: Claude page-rescue failed for image %d (%v) — falling back to OpenAI", idx+1, rerr)
					rescue, rerr = s.openaiService.ExtractHandwrittenBand(ctx, req.ImageData[idx], imageType, productNames, 1, expected)
				}
				if rerr != nil && s.geminiService != nil {
					s.logger.Warnf("SmartSale: OpenAI page-rescue failed for image %d (%v) — falling back to Gemini", idx+1, rerr)
					rescue, rerr = s.geminiService.ExtractHandwrittenBand(ctx, req.ImageData[idx], imageType, productNames, 1, expected)
				}
			case s.useOpenAI && s.openaiService != nil:
				rescue, rerr = s.openaiService.ExtractHandwrittenBand(ctx, req.ImageData[idx], imageType, productNames, 1, expected)
				if rerr != nil && s.geminiService != nil {
					rescue, rerr = s.geminiService.ExtractHandwrittenBand(ctx, req.ImageData[idx], imageType, productNames, 1, expected)
				}
			case s.geminiService != nil:
				rescue, rerr = s.geminiService.ExtractHandwrittenBand(ctx, req.ImageData[idx], imageType, productNames, 1, expected)
			}
			if rerr != nil || rescue == nil {
				s.logger.Warnf("SmartSale: page-rescue ALL providers failed for image %d: %v (keeping main-pass rows)", idx+1, rerr)
				continue
			}
			// Merge by row_number — main-pass wins on collision (validated rows
			// take precedence over re-extracted rows). Track which rows the
			// rescue actually added for the coverage summary.
			seen := make(map[int]struct{}, len(mainResult.Items))
			for _, it := range mainResult.Items {
				seen[it.RowNumber] = struct{}{}
			}
			added := 0
			for _, it := range rescue.Items {
				if _, ok := seen[it.RowNumber]; ok {
					continue
				}
				it.Source = "page_rescue"
				mainResult.Items = append(mainResult.Items, it)
				seen[it.RowNumber] = struct{}{}
				added++
			}
			pageRescueCounts[idx] = added
			pageRescueTriggered[idx] = true
			s.logger.Infof("SmartSale: page-rescue for image %d added %d rows (was %d, now %d, expected %d)",
				idx+1, added, actual, len(mainResult.Items), expected)
		}
	}

	// Concatenate with page-provenance stamping.
	for i := 0; i < numImages; i++ {
		res := imageResults[i]
		if res == nil {
			continue
		}
		successCount++
		lastResult = res
		s.logger.Infof("SmartSale: Image %d final count = %d items", i+1, len(res.Items))

		// Log if AI-detected size differs from user-selected size
		if req.Size != "" && res.PageSize != nil && *res.PageSize != "" {
			aiSizeNorm := normalizeSize(*res.PageSize)
			reqSizeNorm := normalizeSize(req.Size)
			if aiSizeNorm != reqSizeNorm {
				s.logger.Warnf("SmartSale: AI detected size %s but user selected %s — trusting user selection for matching", *res.PageSize, req.Size)
			}
		}

		// Stamp PageNumber (1-based) on every row before concatenating so
		// downstream per-page validators + the Flutter review UI can reason
		// about page provenance. Page identity goes on its own field;
		// row_number stays as the in-page position.
		pageNum := i + 1
		for _, item := range res.Items {
			item.PageNumber = pageNum
			allItems = append(allItems, item)
		}
	}

	s.logger.Infof("SmartSale: Parallel extraction complete - %d/%d images successful, %d total items", successCount, numImages, len(allItems))

	// Sort by (page, row) so the document's reading order survives the
	// parallel extraction. Items without an explicit PageNumber (legacy or
	// single-image flow) fall through to row-only sort.
	sort.Slice(allItems, func(i, j int) bool {
		if allItems[i].PageNumber != allItems[j].PageNumber {
			return allItems[i].PageNumber < allItems[j].PageNumber
		}
		return allItems[i].RowNumber < allItems[j].RowNumber
	})

	// v1.0.131: ALWAYS emit a coverage entry per page where the AI reported
	// RowCountOnPage > 0 OR where any rescue defense fired. Pre-v1.0.131 this
	// only emitted when vote/recovery changed counts, which hid the case
	// "page 2 expected 38, got 6, no rescue ran successfully" — the user saw
	// nothing when they should have seen a red banner. Now Flutter has the
	// full per-page state and can render still_missing=expected-after_rescue.
	var coverage []SaleCoverageEntry
	for i := 0; i < numImages; i++ {
		main := mainPassCounts[i]
		afterVote := afterVoteCounts[i]
		if afterVote == 0 {
			afterVote = main
		}
		afterRecovery := 0
		expected := 0
		if r, ok := imageResults[i]; ok && r != nil {
			afterRecovery = len(r.Items)
			expected = r.RowCountOnPage
		}
		stillMissing := 0
		if expected > afterRecovery {
			stillMissing = expected - afterRecovery
		}
		// Skip silent surface for the common-path "single page, AI got
		// everything cleanly" case.
		if afterVote == main && afterRecovery == main && expected <= afterRecovery && !pageRescueTriggered[i] {
			continue
		}
		notes := ""
		switch {
		case pageRescueTriggered[i] && pageRescueCounts[i] > 0:
			notes = fmt.Sprintf("page-rescue added %d rows", pageRescueCounts[i])
		case pageRescueTriggered[i] && pageRescueCounts[i] == 0:
			notes = fmt.Sprintf("page-rescue ran but recovered 0 new rows — verify against original photo")
		case afterVote > main && afterRecovery == afterVote:
			notes = fmt.Sprintf("vote pass added %d rows", afterVote-main)
		case afterRecovery > afterVote:
			notes = fmt.Sprintf("recovery pass added %d rows", afterRecovery-afterVote)
		case stillMissing > 0:
			notes = fmt.Sprintf("AI reported %d rows on this page but only %d extracted — please verify against original photo", expected, afterRecovery)
		}
		coverage = append(coverage, SaleCoverageEntry{
			PageNumber:    i + 1,
			MainPassRows:  main,
			AfterVote:     afterVote,
			AfterRecovery: afterRecovery,
			Expected:      expected,
			StillMissing:  stillMissing,
			Notes:         notes,
		})
	}

	// v1.0.157 L4 — math gate on legacy extraction path. Sheet-grid has
	// reconcileSale (sale_sheet_grid.go:395) that catches close-misread,
	// math-disagreement, and missing-anchor row classes. The legacy AI
	// extractor doesn't run any math gate, so when sheet-grid coverage
	// drops and we fall back here, every digit-confusion error came
	// through silently (chhotu's job dc676664 had 8 of 22 wrong qtys
	// because of this). Apply the same logic to legacy items now.
	allItems = applyLegacyMathGate(allItems, s.logger)

	return allItems, lastResult, coverage, nil
}

// applyLegacyMathGate re-evaluates each ExtractedReceiptItem against the
// open/receipt/close/total identity and adjusts Quantity / Confidence /
// Warnings when AI's read is inconsistent. Mirrors reconcileSale on
// sale_sheet_grid.go:395 but operates on the legacy struct shape.
//
// Logic (priority):
//
//	1. open + receipt − qty == close (±2) → math-confirmed, conf=0.99
//	2. close > open + receipt (impossible without restock) → close suspect,
//	   warn "close_misread_suspected", keep AI qty at conf=0.85
//	3. qty present but math fails any way → "ai-sale-math-disagree", warn,
//	   conf=0.78
//	4. qty=0 but open+close+receipt are present → derive qty=open+receipt-close,
//	   conf=0.93 (fills silently-missed sales)
//
// The Flutter math-fail chip (smart_sale_screen.dart) reads these warnings
// to surface the row to the operator for confirmation.
func applyLegacyMathGate(items []ExtractedReceiptItem, logger *logrus.Logger) []ExtractedReceiptItem {
	if len(items) == 0 {
		return items
	}
	abs := func(x int) int {
		if x < 0 {
			return -x
		}
		return x
	}
	corrections, mathFails, derived, closeSuspects := 0, 0, 0, 0
	for i := range items {
		item := &items[i]
		hasOpen := item.OpeningStock != nil
		hasClose := item.ClosingStock != nil
		hasReceipt := item.Receipt != nil
		recv := 0
		if hasReceipt {
			recv = *item.Receipt
		}
		// Path 4: qty=0 but anchors present — derive ONLY when both anchors
		// are non-zero AND closing < opening (sale happened). v1.0.158 hot-fix
		// from real-data smoke: original logic derived qty=57 for "100 STROKES
		// ROYAL" because AI returned close=0 (cell unread, not actual zero) so
		// derive computed open(57) - close(0) = 57. Truth was 10. The 0-close
		// case is the dominant unread signal. Tighten: require close > 0 AND
		// open > close (real sale shape).
		if item.Quantity == 0 && hasOpen && hasClose &&
			*item.OpeningStock > 0 && *item.ClosingStock > 0 &&
			*item.OpeningStock > *item.ClosingStock {
			derivedQty := *item.OpeningStock + recv - *item.ClosingStock
			if derivedQty > 0 && derivedQty <= 200 {
				item.Quantity = derivedQty
				item.Confidence = maxFloatLegacy(item.Confidence, 0.93)
				item.Source = strOr(item.Source, "math-derived")
				item.Warnings = append(item.Warnings, fmt.Sprintf("derived_from_math:open(%d)+recv(%d)-close(%d)=%d",
					*item.OpeningStock, recv, *item.ClosingStock, derivedQty))
				if item.FieldConfidence == nil {
					item.FieldConfidence = map[string]float64{}
				}
				item.FieldConfidence["sale"] = 0.93
				derived++
			}
			continue
		}
		// No qty AND no anchors — leave alone.
		if item.Quantity <= 0 {
			continue
		}
		if !hasOpen || !hasClose {
			continue
		}
		expected := *item.OpeningStock + recv - *item.ClosingStock
		diff := abs(expected - item.Quantity)
		if diff <= 2 {
			// Math-confirmed.
			item.Confidence = maxFloatLegacy(item.Confidence, 0.99)
			if item.FieldConfidence == nil {
				item.FieldConfidence = map[string]float64{}
			}
			item.FieldConfidence["sale"] = maxFloatLegacy(item.FieldConfidence["sale"], 0.99)
			corrections++
			continue
		}
		// Math FAILS. Two sub-cases.
		if expected < 0 {
			// Close > open + receipt = impossible without restock entry.
			// Trust AI's qty, mark close as the suspect cell.
			item.Source = strOr(item.Source, "ai-sale-close-suspect")
			item.Confidence = minFloat(item.Confidence, 0.85)
			item.Warnings = append(item.Warnings, fmt.Sprintf("close_misread_suspected:ai_sale=%d open(%d)+recv(%d)-close(%d)=%d",
				item.Quantity, *item.OpeningStock, recv, *item.ClosingStock, expected))
			if item.FieldConfidence == nil {
				item.FieldConfidence = map[string]float64{}
			}
			item.FieldConfidence["closing"] = 0.45
			closeSuspects++
			continue
		}
		// Generic math disagreement — qty doesn't match (open+recv-close).
		// Keep AI's qty (per reconcileSale doctrine — sale read is most
		// reliable) but lower confidence so the Flutter chip surfaces.
		item.Source = strOr(item.Source, "ai-sale-math-disagree")
		item.Confidence = minFloat(item.Confidence, 0.78)
		item.Warnings = append(item.Warnings, fmt.Sprintf("math_disagree:ai_sale=%d open(%d)+recv(%d)-close(%d)=%d",
			item.Quantity, *item.OpeningStock, recv, *item.ClosingStock, expected))
		if item.FieldConfidence == nil {
			item.FieldConfidence = map[string]float64{}
		}
		item.FieldConfidence["sale"] = minFloat(item.FieldConfidence["sale"], 0.78)
		mathFails++
	}
	if corrections+mathFails+derived+closeSuspects > 0 {
		logger.Infof("legacy-math-gate: items=%d math_ok=%d math_fail=%d close_suspect=%d derived=%d",
			len(items), corrections, mathFails, closeSuspects, derived)
	}
	return items
}

func maxFloatLegacy(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func minFloat(a, b float64) float64 {
	if a == 0 {
		return b
	}
	if a < b {
		return a
	}
	return b
}

func strOr(a, b string) string {
	if a != "" {
		return a
	}
	return b
}

// validateExtractedData validates items against inventory
func (s *SmartSaleService) validateExtractedData(
	ctx context.Context,
	req *SmartSaleRequest,
	items []ExtractedReceiptItem,
	extractionResult *ReceiptExtractionResult,
	tenantID uuid.UUID,
	products []models.Product,
	exciseInfoMap map[string]exciseInfo,
) ([]SmartSaleExtractedItem, *SmartSaleValidation, error) {

	validation := &SmartSaleValidation{
		TotalItems:       len(items),
		Messages:         []string{},
		Warnings:         []string{},
		ExpectedShopName: req.ShopName,
		ExpectedDate:     req.SaleDate.Format("2006-01-02"),
		ExpectedSize:     req.Size,
		ExpectedSizeML:   parseSizeToML(req.Size),
	}

	// Extract shop name from image header
	if extractionResult != nil {
		// Shop name - prefer ShopName field, fallback to VendorName
		if extractionResult.ShopName != nil && *extractionResult.ShopName != "" {
			validation.DetectedShopName = *extractionResult.ShopName
		} else if extractionResult.VendorName != nil && *extractionResult.VendorName != "" {
			validation.DetectedShopName = *extractionResult.VendorName
		}

		// Filter out generic non-shop-name strings (e.g., "SALE RECEIPT" when form header has no shop name)
		genericHeaders := []string{"sale receipt", "daily sale", "rept sale", "report", "register", "stock register"}
		if validation.DetectedShopName != "" {
			detectedLower := strings.ToLower(validation.DetectedShopName)
			for _, header := range genericHeaders {
				if strings.Contains(detectedLower, header) {
					s.logger.Infof("🏪 Detected shop name '%s' is a generic header — ignoring, using user-selected shop", validation.DetectedShopName)
					validation.DetectedShopName = "" // Clear — not a real shop name
					break
				}
			}
		}

		// Log detected shop name
		if validation.DetectedShopName != "" {
			s.logger.Infof("🏪 Detected Shop Name: %s (Expected: %s)", validation.DetectedShopName, req.ShopName)
		}

		// Validate shop name match
		if validation.DetectedShopName != "" {
			similarity := smartSaleStringSimilarity(strings.ToLower(req.ShopName), strings.ToLower(validation.DetectedShopName))
			validation.ShopNameMatch = similarity > 0.6
			if !validation.ShopNameMatch {
				validation.Warnings = append(validation.Warnings,
					fmt.Sprintf("⚠️ Shop name mismatch: Expected '%s', Image shows '%s'", req.ShopName, validation.DetectedShopName))
			}
		} else {
			validation.ShopNameMatch = true // No shop name detected — use user-selected shop
		}

		// Extract page size from image header
		if extractionResult.PageSize != nil && *extractionResult.PageSize != "" {
			validation.DetectedSize = *extractionResult.PageSize
		}
		if extractionResult.PageSizeML > 0 {
			validation.DetectedSizeML = extractionResult.PageSizeML
		}

		// Log detected size
		if validation.DetectedSize != "" || validation.DetectedSizeML > 0 {
			s.logger.Infof("📐 Detected Page Size: %s (%d ML) - Expected: %s (%d ML)",
				validation.DetectedSize, validation.DetectedSizeML, req.Size, validation.ExpectedSizeML)
		}

		// Validate size match (if user selected a size)
		if req.Size != "" && validation.DetectedSizeML > 0 {
			validation.SizeMatch = validation.ExpectedSizeML == validation.DetectedSizeML
			if !validation.SizeMatch {
				validation.SizeMismatch = true
				validation.SizeMismatchMessage = fmt.Sprintf(
					"Receipt shows %d ML but you selected %s. Please verify the correct size.",
					validation.DetectedSizeML, req.Size)
				validation.Warnings = append(validation.Warnings,
					fmt.Sprintf("⚠️ Size mismatch: Expected '%s', Image shows '%s'", req.Size, validation.DetectedSize))
			}
		} else {
			validation.SizeMatch = true // No size to validate or no size detected
		}
	} else {
		validation.ShopNameMatch = true // No extraction result to validate
		validation.SizeMatch = true
	}

	// Validate date if detected
	if extractionResult != nil && extractionResult.ReceiptDate != nil {
		detectedDate := *extractionResult.ReceiptDate
		validation.DetectedDate = detectedDate
		parsedDate, err := time.Parse("2006-01-02", detectedDate)
		if err == nil {
			validation.DateMatch = parsedDate.Format("2006-01-02") == req.SaleDate.Format("2006-01-02")
			if !validation.DateMatch {
				validation.DateMismatch = true
				validation.DateMismatchMessage = fmt.Sprintf(
					"Receipt date %s doesn't match your selected date %s. Please verify.",
					parsedDate.Format("02-Jan-2006"), req.SaleDate.Format("02-Jan-2006"))
				validation.Warnings = append(validation.Warnings,
					fmt.Sprintf("⚠️ Date mismatch: Expected '%s', Image shows '%s'",
						req.SaleDate.Format("2006-01-02"), detectedDate))
			}
		}
	} else {
		validation.DateMatch = true // No date to validate
	}

	// Products are pre-loaded and passed in (filtered by size/category)
	s.logger.Infof("SmartSale: Matching against %d products", len(products))

	// Preload ALL stock records for this shop to enable opening stock cross-validation.
	// The register's opening stock should match the DB stock — this is a powerful signal
	// to confirm or reject matches when product names are ambiguous.
	shopStockMap := make(map[string]int) // product_id -> stock quantity
	var shopStocks []models.Stock
	s.db.Where("shop_id = ? AND tenant_id = ?", req.ShopID, tenantID).Find(&shopStocks)
	for _, st := range shopStocks {
		shopStockMap[st.ProductID.String()] = st.Quantity
	}
	s.logger.Infof("SmartSale: Preloaded %d stock records for shop", len(shopStocks))

	// v1.0.328 — dedupe near-duplicate products at this shop BEFORE matching.
	// Concrete bug class (FM Tower 8PM Gold Scotch Tetra 2026-05-28): two LIVE
	// products with same effective SKU coexist because the names differ just
	// enough to escape unique constraints — e.g.
	//   ab40e44c "8PM Gold Scotch Tetra - 180ml" (size "180ML",   stock 26)
	//   8d20df01 "8pm Gold Scotch Whisky Tetra 180ml" (size "180ml (Quarter)", stock 94)
	// The matcher ranks 8d20df01 higher because OCR text includes "Whisky", so
	// the review screen shows stock 94 while the Inventory page shows 26. This
	// pass groups products by (shop, normalized_brand, sizeML), picks ONE
	// canonical entry per group, and removes losers from the candidate pool.
	// Canonical preference: (a) has stock > 0 over zero-stock twin, (b) higher
	// stock if both > 0, (c) canonical size string "Xml (Quarter|Half|Full)" over
	// raw "XML", (d) more recently updated. The losers also have their
	// shopStockMap entries zeroed so any path that still references their IDs
	// can't surface stale stock. Audit-logged for forensic visibility.
	products, dedupeStats := dedupeNearDuplicateProductsForShop(products, shopStockMap, s.db, req.ShopID)
	if dedupeStats.Removed > 0 {
		s.logger.Infof("SmartSale: dedupe collapsed %d near-duplicate product(s) into %d canonical (shop=%s) — examples: %v",
			dedupeStats.Removed, dedupeStats.Groups, req.ShopID, dedupeStats.Examples)
	}

	// v1.0.160 — load per-shop last-sold-days for shop-inventory bias. One small
	// query: products this shop has sold in the last 60 days (window > the
	// 30-day "recent" cutoff used by the matcher, so callers can adjust without
	// re-querying). Map[productID] = days_ago. Products absent from the map
	// have never been sold here (matcher treats LastSoldDaysAgo<0 as "never").
	shopLastSoldDays := s.loadShopLastSoldDays(tenantID, req.ShopID, 60)
	if len(shopLastSoldDays) > 0 {
		s.logger.Infof("SmartSale: Preloaded last-sold for %d products (window=60d)", len(shopLastSoldDays))
	}

	// v1.0.116: Pre-load the most-recent approved stock_setup as ground truth.
	// Used as a fast-path BEFORE fuzzy matching (rate exact + brand fuzzy >= 0.6
	// = instant match) and for completeness-gap detection (setup brands that
	// didn't appear in the sale extraction). Highest-confidence reference
	// because the user explicitly approved this setup recently.
	setupByRate, setupByName := s.loadLatestApprovedStockSetupMap(req.ShopID, validation.ExpectedSizeML, tenantID)
	matchedSetupProductIDs := make(map[string]struct{}, len(setupByName))

	// v1.0.125 — load per-shop learned rates so we can override selling-price
	// when the user has corrected the same product more than once. Mirrors
	// smart_stock_setup_service.go:loadShopLearnedRates. Keyed by product_id.
	shopLearnedRates := s.loadShopLearnedRates(tenantID, req.ShopID)

	// v1.0.172 — match-time exclusion of already-claimed products. Operator
	// rule: "if one item is added, no duplicacy allowed." Once a row has
	// been confidently matched to product X, no LATER row can claim X — the
	// matcher must skip X from its candidate pool. Without this, two rows
	// of the register that look textually similar (e.g. M2 Magic Moments
	// Remix variants) both claim the same product_id and one of them
	// silently saves the wrong record.
	//
	// claimedProducts is keyed by product_id; written when a row is matched
	// with score ≥ 0.85 OR via an exact-source alias hint. Lower-confidence
	// matches don't claim — they leave room for higher-confidence later rows
	// to take the product, and themselves get rerouted to the operator
	// picker when their target is already claimed.
	claimedProducts := make(map[string]struct{})

	// Validate each extracted item
	var validatedItems []SmartSaleExtractedItem
	for idx, item := range items {
		validated := SmartSaleExtractedItem{
			BrandName:        item.Brand,
			// v1.0.117: snapshot the AI's first-guess brand BEFORE the matcher
			// runs. The matcher (line ~1197) overwrites BrandName with the
			// matched product's name; the original AI text is otherwise lost
			// from the response. Plumbed through to Flutter and back on apply
			// so picker corrections seed ocr_brand_aliases.
			OriginalAIBrand:  item.Brand,
			Size:             item.SizeText,
			Category:         item.Category,
			Quantity:         item.Quantity,
			Rate:             s.getRate(item),
			Amount:           s.getAmount(item),
			OpeningStock:     item.OpeningStock,
			Receipt:          item.Receipt,
			Total:            item.Total,
			ClosingStock:     item.ClosingStock,
			Confidence:       item.Confidence,
			SerialNumber:     idx + 1,
			// Carry page + in-page row forward from extraction so Flutter can
			// group + validators can scope per-page. These mirror Stock Setup
			// where PageNumber drives the review UI's "Page 2 of 3" banner.
			PageNumber: item.PageNumber,
			RowNumber:  item.RowNumber,
			ValidationStatus: "not_found",
			Warnings:         append([]string{}, item.Warnings...),
			Errors:           []string{},
			// v1.0.131 — propagate per-cell field_confidence from extraction
			// (populated natively by Claude + by the cell-level voting pass)
			// so the Flutter amber-underline UI works on Smart Sale rows the
			// same way it does on Stock Setup. The field-confidence floor
			// gate in flagItemsForReview reads this map.
			//
			// v1.0.138 — also propagate per-row Warnings from the extractor.
			// Sheet-grid pipeline raises "ai-sale-math-disagree" /
			// "addon-unresolved" / "triple_disagreement" — Flutter renders
			// these as amber chips on the review row so the operator's
			// 1-tap fix flows back through alias-learning.
			FieldConfidence:  cloneFieldConfidence(item.FieldConfidence),
			Source:           item.Source,
			// v1.0.183 Track C — invariant doubts produced by the textract
			// math-gate. AutoFixed=true entries are informational; the row
			// already carries the corrected value. AutoFixed=false entries
			// are the C2 doubt-popup queue Flutter walks before the review
			// screen.
			CellDoubts:       append([]CellDoubt(nil), item.CellDoubts...),
		}

		// Set raw OCR text (preserved from AI extraction)
		validated.OCRText = item.RawText
		if validated.OCRText == "" {
			validated.OCRText = item.Brand
		}

		// Mark zero-quantity items
		if item.Quantity == 0 {
			validated.IsZeroQuantity = true
		}

		// Multi-candidate matching with price and stock awareness
		ocrRate := s.getRate(item)
		ocrOpeningStock := 0
		if item.OpeningStock != nil {
			ocrOpeningStock = *item.OpeningStock
		}
		// v1.0.172 — build per-row candidate pool excluding already-claimed
		// products. We pass `availableProducts` (a filtered view) to the
		// matcher so it never even considers claimed products. This is the
		// "match-time exclusion" the operator asked for — claimed products
		// can't even reach the matcher's score function, eliminating
		// the duplicacy-by-confident-tie class entirely.
		availableProducts := products
		if len(claimedProducts) > 0 {
			availableProducts = make([]models.Product, 0, len(products))
			for _, p := range products {
				if _, claimed := claimedProducts[p.ID.String()]; claimed {
					continue
				}
				availableProducts = append(availableProducts, p)
			}
			if len(availableProducts) < len(products) {
				s.logger.Debugf("SmartSale: row %d candidate pool excludes %d claimed product(s)",
					idx, len(products)-len(availableProducts))
			}
		}

		// v1.0.173 — META-KEYWORD pre-match. Walk the OCR text against
		// every available product's master meta_keywords (curated shop-floor
		// synonyms / abbreviations). When OCR contains a keyword as a
		// SUBSTRING (case-insensitive, after light normalization), the
		// match is operator-curated truth — score 0.95, claim immediately.
		// This is the deterministic name-first path that handles MCD →
		// Mc Dowells, OC → Officer's Choice, AD → After Dark, M.M → M2 Magic
		// Moments, Iconic → Iconiq, etc. before any fuzzy scorer runs.
		// Tie-broken by the row's opening stock + MRP corroboration so two
		// products sharing the same keyword (e.g. "blue") don't collide.
		var matches []saleProductMatch
		ocrLower := strings.ToLower(strings.TrimSpace(item.Brand))
		ocrRawLower := strings.ToLower(strings.TrimSpace(item.RawText))
		if ocrLower != "" || ocrRawLower != "" {
			type kwHit struct {
				prod  *models.Product
				kw    string
				score float64
			}
			var hits []kwHit
			for pi := range availableProducts {
				p := &availableProducts[pi]
				ei, hasInfo := exciseInfoMap[p.ID.String()]
				if !hasInfo || len(ei.MetaKeywords) == 0 {
					continue
				}
				for _, kw := range ei.MetaKeywords {
					kw = strings.ToLower(strings.TrimSpace(kw))
					if len(kw) < 2 {
						continue
					}
					hit := false
					if ocrLower != "" && (strings.Contains(ocrLower, kw) || strings.Contains(kw, ocrLower)) {
						hit = true
					}
					if !hit && ocrRawLower != "" && (strings.Contains(ocrRawLower, kw) || strings.Contains(kw, ocrRawLower)) {
						hit = true
					}
					if hit {
						// Score = keyword length / longest of (ocr, kw).
						// Ensures longer keywords dominate ("after dark blue rare"
						// beats just "ad" when OCR text is "After Dark Blue Rare Grain").
						maxLen := len(ocrLower)
						if len(kw) > maxLen {
							maxLen = len(kw)
						}
						sc := float64(len(kw)) / float64(maxLen)
						if sc > 1.0 {
							sc = 1.0
						}
						hits = append(hits, kwHit{prod: p, kw: kw, score: sc})
					}
				}
			}
			if len(hits) > 0 {
				// Tie-break by rate match (most discriminating cell-level signal),
				// then by opening match, then by raw keyword score.
				type scored struct {
					prod  *models.Product
					score float64
					tie   float64
				}
				ranked := make([]scored, 0, len(hits))
				for _, h := range hits {
					tie := h.score
					if ocrRate > 0 && h.prod.SellingPrice > 0 {
						pct := math.Abs(ocrRate - h.prod.SellingPrice) / h.prod.SellingPrice
						if pct <= 0.02 {
							tie += 0.20
						} else if pct <= 0.05 {
							tie += 0.10
						} else if pct >= 0.20 {
							tie -= 0.30
						}
					}
					if ocrOpeningStock > 0 {
						if dbStock, ok := shopStockMap[h.prod.ID.String()]; ok && dbStock > 0 {
							diff := ocrOpeningStock - dbStock
							if diff >= -2 && diff <= 2 {
								tie += 0.10
							}
						}
					}
					ranked = append(ranked, scored{prod: h.prod, score: h.score, tie: tie})
				}
				// pick highest tie-broken
				bestIdx := 0
				for i := 1; i < len(ranked); i++ {
					if ranked[i].tie > ranked[bestIdx].tie {
						bestIdx = i
					}
				}
				best := ranked[bestIdx]
				if best.tie >= 0.55 {
					matches = []saleProductMatch{{Product: best.prod, Score: 0.95, PriceMatch: true}}
					s.logger.Infof("SmartSale: META-KEYWORD HIT — '%s' → '%s' (tie_score=%.2f over %d candidates)",
						item.Brand, best.prod.Name, best.tie, len(ranked))
				}
			}
		}

		// v1.0.168 — honor MatchedProductIDHint set by the alias-cascade
		// pre-matcher in extractWithTextract. When the textract path
		// resolved a brand via an EXACT-source alias, we already know the
		// product_id with operator-confirmed certainty. Skip the matcher
		// entirely and assign that product. The pollution-guard at
		// findMatchingProductsWithStock would otherwise reject short alias
		// keys like "M.M" → M2 Magic Moments Jamun Spicymint.
		if len(matches) == 0 && item.MatchedProductIDHint != "" {
			if hintID, hErr := uuid.Parse(item.MatchedProductIDHint); hErr == nil {
				if _, alreadyClaimed := claimedProducts[item.MatchedProductIDHint]; !alreadyClaimed {
					for i := range products {
						if products[i].ID == hintID {
							matches = []saleProductMatch{{Product: &products[i], Score: 1.0, PriceMatch: true}}
							s.logger.Infof("SmartSale: matcher honored hint product=%s (source=%s) for ocr=%q",
								products[i].Name, item.MatchedProductIDHintSource, item.RawText)
							break
						}
					}
				} else {
					s.logger.Warnf("SmartSale: hint product %s already claimed by an earlier row — skipping hint, running matcher on remaining pool", item.MatchedProductIDHint)
				}
			}
		}
		// v1.0.133-r7 — pass raw OCR text so alias lookup tries the
		// register handwriting first, then falls back to AI's matched brand.
		// v1.0.160 — also pass shopLastSoldDays so the matcher can apply
		// shop-inventory bias (favour stocked / recently-sold products).
		// v1.0.172 — pass `availableProducts` (claimed-products excluded).
		if len(matches) == 0 {
			matches = s.findMatchingProductsWithStock(availableProducts, item.Brand, item.RawText, item.SizeText, item.Category, ocrRate, ocrOpeningStock, tenantID, req.ShopID, exciseInfoMap, shopStockMap, shopLastSoldDays)
		}
		// v1.0.172 — smart-search rescue. When the standard matcher returns
		// nothing (or only weak matches), run abbreviation+Levenshtein+
		// bigram+anchor scoring across the available pool. Catches the
		// "MCD → McDowell's" / "Iconic → Iconiq" / "OC Blue → Officer's
		// Choice Blue Superior" class a 5-year-old reader handles
		// effortlessly but jaccard misses. Only used as ADDITIVE signal —
		// never overrides a strong existing match.
		topExistingScore := 0.0
		if len(matches) > 0 {
			topExistingScore = matches[0].Score
		}
		if topExistingScore < 0.85 {
			smartSearchQueries := []string{}
			if t := strings.TrimSpace(item.Brand); t != "" {
				smartSearchQueries = append(smartSearchQueries, t)
			}
			if t := strings.TrimSpace(item.RawText); t != "" && t != item.Brand {
				smartSearchQueries = append(smartSearchQueries, t)
			}
			type scored struct {
				prod  *models.Product
				score float64
			}
			best := scored{score: 0}
			for pi := range availableProducts {
				p := &availableProducts[pi]
				for _, q := range smartSearchQueries {
					sc := smartSearchScore(q, p.Name)
					if p.DisplayName != "" {
						if d := smartSearchScore(q, p.DisplayName); d > sc {
							sc = d
						}
					}
					// v1.0.173 — score against master meta_keywords too. A
					// curated keyword like "mcd" or "iconic" or "after dark"
					// matches the OCR exactly, so smartSearchScore returns
					// near-1.0 (substring containment). Promotes meta-data
					// over pure jaccard token overlap.
					if exciseInfoMap != nil {
						if ei, ok := exciseInfoMap[p.ID.String()]; ok {
							for _, kw := range ei.MetaKeywords {
								if kw == "" {
									continue
								}
								if k := smartSearchScore(q, kw); k > sc {
									sc = k
								}
							}
						}
					}
					if sc > best.score {
						best.score = sc
						best.prod = p
					}
				}
			}
			// v1.0.172 — strict smart-search rescue floor. Set to 0.92 after
			// initial 0.65 pilot caused regressions (M.M → M2 Verve Cranberry,
			// After Dark → Imperial Blue) — abbreviation expansion + bigram
			// jaccard can hit 0.65-0.85 on coincidental token overlap. At
			// 0.92 we only rescue near-certain matches; weaker candidates
			// fall to operator picker (no auto-assigned wrong product).
			// ALSO require corroboration (rate or opening) for rescue
			// matches in [0.92, 1.00) — same logic as the main matcher gate.
			rescueFloor := 0.92
			if best.prod != nil && best.score > topExistingScore && best.score >= rescueFloor {
				rateOK := false
				openOK := false
				if ocrRate > 0 && best.prod.SellingPrice > 0 {
					if d := math.Abs(ocrRate - best.prod.SellingPrice); d/best.prod.SellingPrice <= 0.05 {
						rateOK = true
					}
				}
				if ocrOpeningStock > 0 {
					if dbStock, ok := shopStockMap[best.prod.ID.String()]; ok && dbStock > 0 {
						if abs := ocrOpeningStock - dbStock; abs >= -2 && abs <= 2 {
							openOK = true
						}
					}
				}
				if rateOK || openOK {
					s.logger.Infof("SmartSale: smart-search RESCUE — '%s' → '%s' (smart=%.2f, rateOK=%v, openOK=%v)",
						item.Brand, best.prod.Name, best.score, rateOK, openOK)
					rescued := saleProductMatch{Product: best.prod, Score: best.score, PriceMatch: rateOK}
					matches = append([]saleProductMatch{rescued}, matches...)
				} else {
					s.logger.Infof("SmartSale: smart-search rescue %s blocked — no corroboration (rate=%.0f mrp=%.0f, open=%d db=%d)",
						best.prod.Name, ocrRate, best.prod.SellingPrice, ocrOpeningStock, shopStockMap[best.prod.ID.String()])
				}
			}
		}

		// v1.0.116 stock-setup ground-truth rescue: when fuzzy matcher returns
		// nothing OR low-confidence and the OCR rate exactly matches a recently-
		// approved stock setup row, route there. This catches:
		//   - JSON-parse garbage (brand="raw_text" or "brand" — schema keys
		//     leaking as values, which the fuzzy matcher can't possibly match)
		//   - OCR brand misreads where rate is the cleaner signal (handwritten
		//     numerals are usually more legible than handwritten brand names)
		// Concretely fixes job 016a1e0b row 22 (raw_text ₹940 → Master Blenders
		// Signature). When multiple setup rows share the same rate, we only
		// rescue if exactly ONE candidate exists (no ambiguity).
		needsSetupRescue := len(matches) == 0 || (len(matches) > 0 && matches[0].Score < 0.55)
		if needsSetupRescue && ocrRate > 0 && len(setupByRate) > 0 {
			rateKey := int(ocrRate + 0.5)
			candidates := setupByRate[rateKey]
			// Also probe ±2 to absorb minor rate-write differences (e.g. 758 vs 760)
			if len(candidates) == 0 {
				for delta := 1; delta <= 2; delta++ {
					if c := setupByRate[rateKey+delta]; len(c) > 0 {
						candidates = c
						break
					}
					if c := setupByRate[rateKey-delta]; len(c) > 0 {
						candidates = c
						break
					}
				}
			}
			if len(candidates) == 1 {
				ref := candidates[0]
				// Find the corresponding tenant product in the candidate pool.
				// products is the size-scoped slice from request setup.
				for pi := range products {
					if products[pi].ID == ref.ProductID {
						s.logger.Infof("SmartSale: STOCK-SETUP RESCUE — '%s' rate=₹%.0f → '%s' (sole rate match in latest approved setup)",
							item.Brand, ocrRate, ref.ProductName)
						matches = []saleProductMatch{{Product: &products[pi], Score: 0.95, PriceMatch: true}}
						break
					}
				}
			} else if len(candidates) > 1 {
				// Multiple setup rows share this rate. Combine fuzzy brand match against
				// THIS smaller pool to disambiguate. Picks the highest-fuzzy candidate.
				bestIdx := -1
				bestSim := 0.0
				brandLower := strings.ToLower(strings.TrimSpace(item.Brand))
				for ci, c := range candidates {
					sim := smartSaleStringSimilarity(brandLower, strings.ToLower(c.ProductName))
					if sim > bestSim {
						bestSim = sim
						bestIdx = ci
					}
				}
				if bestIdx >= 0 && bestSim >= 0.30 {
					ref := candidates[bestIdx]
					for pi := range products {
						if products[pi].ID == ref.ProductID {
							s.logger.Infof("SmartSale: STOCK-SETUP RESCUE (rate-match + brand-fuzzy) — '%s' rate=₹%.0f → '%s' (brand_sim=%.2f, %d rate candidates)",
								item.Brand, ocrRate, ref.ProductName, bestSim, len(candidates))
							matches = []saleProductMatch{{Product: &products[pi], Score: 0.85, PriceMatch: true}}
							break
						}
					}
				}
			}
		}

		// Post-match price sanity check: if OCR rate is wildly different from the
		// matched product's MRP/selling price, the match is almost certainly wrong.
		// E.g., "Johnnie Walker Double Black" at ₹610 but MRP is ₹3770 — wrong product.
		if len(matches) > 0 && ocrRate > 0 {
			best := matches[0]
			productPrice := best.Product.SellingPrice
			if productPrice <= 0 {
				productPrice = best.Product.MRP
			}
			if productPrice > 0 {
				ratio := ocrRate / productPrice
				// If extracted rate is <40% or >250% of product price, reject this match
				if ratio < 0.40 || ratio > 2.50 {
					s.logger.Warnf("SmartSale: PRICE SANITY REJECT '%s' → '%s' (OCR rate=₹%.0f, product price=₹%.0f, ratio=%.2f)",
						item.Brand, best.Product.Name, ocrRate, productPrice, ratio)
					matches = nil // Force not_found path
				}
			}
		}

		// Hard floor: matches below 0.55 are noise — drop them so the row falls to
		// not_found, where the user gets a "pick or skip" UI instead of a silent
		// wrong match. FM Tower 750ml on 2026-04-28 had four such cases —
		// "MCD Double Oak Barrel" → "Mc Dowells No1 Original" @ 0.35,
		// "White And Blue Rare" → "BLACK & WHITE CELEBRATION" @ 0.25, etc.
		if len(matches) > 0 && matches[0].Score < 0.55 {
			s.logger.Warnf("SmartSale: LOW-SCORE REJECT '%s' → '%s' (score=%.2f < 0.55)",
				item.Brand, matches[0].Product.Name, matches[0].Score)
			matches = nil
		}

		// Size filter enforcement: if user selected a size filter, reject matches with different size
		if req.Size != "" && len(matches) > 0 {
			reqSizeML := parseSizeToML(req.Size)
			if reqSizeML > 0 {
				var sizeFiltered []saleProductMatch
				for _, m := range matches {
					productSizeML := parseSizeToML(m.Product.Size)
					if productSizeML == reqSizeML {
						sizeFiltered = append(sizeFiltered, m)
					} else {
						s.logger.Warnf("SmartSale: SIZE FILTER REJECT '%s' (%s=%dML) — filter is %s=%dML",
							m.Product.Name, m.Product.Size, productSizeML, req.Size, reqSizeML)
					}
				}
				if len(sizeFiltered) < len(matches) && len(sizeFiltered) > 0 {
					matches = sizeFiltered
				} else if len(sizeFiltered) == 0 {
					validated.Warnings = append(validated.Warnings,
						fmt.Sprintf("⚠️ All matches filtered out by size %s — check if correct size was selected", req.Size))
					matches = nil // Force not_found path
				}
			}
		}

		// v1.0.170 — confident-wrong floor. Pre-fix the matcher returned a top
		// candidate regardless of score and let the downstream validation
		// label it "Low confidence match" while still saving the wrong
		// product_id. Operator's eye sees a green checkmark and saves the
		// wrong sale. Catastrophic. Now: any score < 0.70 from a non-alias
		// path is REJECTED at this gate; the row's matched_brand_name stays
		// empty so the review screen shows "Product not found" + alternative
		// candidates picker instead of an auto-assigned wrong product.
		// Aliases (item.MatchedProductIDHint != "") have already been
		// validated by the alias-cascade and bypass this floor.
		// v1.0.170 — confident-match floor 0.70. Pre-fix the matcher returned
		// a top candidate regardless of score and let the downstream
		// validation label it "Low confidence match" while still saving the
		// wrong product_id.
		//
		// v1.0.171 — 3-way corroboration. Even at score >= 0.70, REQUIRE at
		// least one independent corroborator (opening_stock match within ±2
		// OR rate match within ±5%) when score < 0.85. The matcher's score
		// alone can be deceived by token-overlap accidents — opening + MRP
		// are independent signals from the OCR cells. Operator-confirmed
		// alias hints (item.MatchedProductIDHint) bypass this gate.
		const confidentMatchFloor = 0.70
		const trustWithoutCorroborationFloor = 0.85
		const openingTolerance = 2
		const ratePctTolerance = 0.05
		if len(matches) > 0 && item.MatchedProductIDHint == "" {
			best := matches[0]
			rejected := false
			rejectReason := ""
			// Floor 1: hard reject below 0.70
			if best.Score < confidentMatchFloor {
				rejected = true
				rejectReason = fmt.Sprintf("score %.2f < floor %.2f", best.Score, confidentMatchFloor)
			} else if best.Score < trustWithoutCorroborationFloor {
				// Floor 2: 0.70-0.85 zone requires explicit corroboration
				ocrRateLocal := s.getRate(item)
				ocrOpenLocal := 0
				if item.OpeningStock != nil {
					ocrOpenLocal = *item.OpeningStock
				}
				rateOK := ocrRateLocal > 0 && best.Product.SellingPrice > 0 &&
					math.Abs(ocrRateLocal-best.Product.SellingPrice)/best.Product.SellingPrice <= ratePctTolerance
				openOK := false
				if ocrOpenLocal > 0 {
					if dbStock, ok := shopStockMap[best.Product.ID.String()]; ok && dbStock > 0 {
						if abs := ocrOpenLocal - dbStock; abs >= -openingTolerance && abs <= openingTolerance {
							openOK = true
						}
					}
				}
				if !rateOK && !openOK {
					rejected = true
					rejectReason = fmt.Sprintf("corroboration FAIL (rate ocr=%.0f vs mrp=%.0f, open ocr=%d vs db=%d)",
						ocrRateLocal, best.Product.SellingPrice, ocrOpenLocal, shopStockMap[best.Product.ID.String()])
				} else {
					s.logger.Infof("SmartSale: corroboration PASS — '%s' → '%s' (score=%.2f, rateOK=%v, openOK=%v)",
						item.Brand, best.Product.Name, best.Score, rateOK, openOK)
				}
			}
			if rejected {
				s.logger.Warnf("SmartSale: REJECTED — '%s' would have matched '%s' (%s); routing to operator picker",
					item.Brand, best.Product.Name, rejectReason)
				alts := make([]SaleAlternativeMatch, 0, 3)
				for i := 0; i < len(matches) && i < 3; i++ {
					alts = append(alts, SaleAlternativeMatch{
						ProductID:    matches[i].Product.ID.String(),
						BrandName:    matches[i].Product.Name,
						SellingPrice: matches[i].Product.SellingPrice,
						Size:         matches[i].Product.Size,
						Confidence:   matches[i].Score,
					})
				}
				validated.AlternativeMatches = alts
				matches = nil
			}
		}

		if len(matches) > 0 {
			best := matches[0]
			matchedProduct := best.Product
			productID := matchedProduct.ID.String()
			matchedSetupProductIDs[productID] = struct{}{} // for completeness-gap detection
			// v1.0.172 — claim this product so subsequent rows can't pick it.
			// Claim only on confident assignments (score ≥ 0.85 OR alias hint).
			// Lower-confidence rows leave the product available so a later
			// high-confidence row can take it cleanly.
			if best.Score >= 0.85 || item.MatchedProductIDHint != "" {
				claimedProducts[productID] = struct{}{}
				s.logger.Debugf("SmartSale: row %d CLAIMED product %s (score=%.2f, hint=%v)",
					idx, matchedProduct.Name, best.Score, item.MatchedProductIDHint != "")
			}
			validated.ProductID = &productID
			validated.MatchedBrandName = matchedProduct.Name
			validated.BrandName = matchedProduct.Name // Override AI text with correct product name for Flutter display
			validated.MatchConfidence = best.Score
			// Surface master-catalog name so UI can show "UP Excise: 8 PM Premium Black" alongside
			// the tenant's local product name, and so future alias-learning captures the canonical form.
			if exciseInfoMap != nil {
				if ei, ok := exciseInfoMap[productID]; ok {
					validated.MatchedExciseBrandName = ei.BrandName
					validated.MatchedExciseDisplayName = ei.DisplayName
				}
			}

			// Override rate with inventory SellingPrice (OCR rate is only used for matching)
			if matchedProduct.SellingPrice > 0 {
				validated.Rate = matchedProduct.SellingPrice
				validated.Amount = matchedProduct.SellingPrice * float64(validated.Quantity)
			}

			// v1.0.125 — per-shop learned rate override. When the user has corrected
			// this same product's rate before at this shop, prefer that over the
			// global SellingPrice. Mirrors stock-setup learning: "fix it twice →
			// permanent at this shop." Trigger when learned rate diverges >5% from
			// current rate, to avoid noisy reapplies of trivially-different prices.
			if learnedRate, ok := shopLearnedRates[matchedProduct.ID.String()]; ok && learnedRate > 0 {
				baselineRate := validated.Rate
				if baselineRate <= 0 {
					baselineRate = matchedProduct.MRP
				}
				if baselineRate > 0 && math.Abs(learnedRate-baselineRate)/baselineRate > 0.05 {
					s.logger.Infof("SmartSale: LEARNED RATE OVERRIDE — '%s' shop=%s used ₹%.2f (was ₹%.2f from SellingPrice/AI; OCR=₹%.0f)",
						matchedProduct.Name, req.ShopID, learnedRate, baselineRate, ocrRate)
					validated.Rate = learnedRate
					validated.Amount = learnedRate * float64(validated.Quantity)
					validated.Warnings = append(validated.Warnings,
						fmt.Sprintf("ℹ️ Used your shop's learned rate ₹%.0f (different from current ₹%.0f) — verify before saving", learnedRate, baselineRate))
				}
			}

			// Status determination (matching Smart Stock Setup pattern)
			if best.Score >= 0.80 {
				validated.ValidationStatus = "matched"
			} else if len(matches) > 1 && (best.Score-matches[1].Score) < 0.10 {
				validated.ValidationStatus = "ambiguous"
			} else {
				validated.ValidationStatus = "low_confidence"
			}

			// v1.0.160 — shop-inventory bias surfaced ambiguity between two
			// stocked products (top two within AmbiguityNeedsReviewMargin).
			// Don't auto-pick: flag the row so Flutter shows the swap-row chip.
			if best.NeedsReview {
				validated.NeedsReview = true
				if validated.ReviewReason == "" {
					validated.ReviewReason = "two stocked products with near-tie scores — pick the right one"
				}
				if validated.ValidationStatus == "matched" {
					validated.ValidationStatus = "ambiguous"
				}
			}

			// Populate alternative matches (top 3 alternatives for user selection).
			//
			// v1.0.305 — filter alternatives by two rules to keep the
			// "Did you mean…" list sensible:
			//   (a) minimum score ≥ 0.75 so weak fuzzy matches don't show
			//       (real incident: a row matched OFFICER'S CHOICE ORIGINAL
			//       cleanly at ~0.95, but the matcher's #2 and #3 came back
			//       at 0.63 / 0.61 for "Mcd Original Why 180ml" and "100
			//       Strokes" — different brands that happen to share the
			//       word "Original" or be in the same shop pool. The operator
			//       saw them as nonsense suggestions).
			//   (b) alternative product has stock > 0 at this shop. There's
			//       no point offering a swap to something we can't sell.
			// shopStockMap is in scope here (built earlier in the same
			// function around line 3364) so the stock check is a cheap
			// map lookup, no extra query.
			for j := 1; j < len(matches) && j <= 3; j++ {
				alt := matches[j]
				if alt.Score < 0.75 {
					continue
				}
				if shopStockMap[alt.Product.ID.String()] <= 0 {
					continue
				}
				validated.AlternativeMatches = append(validated.AlternativeMatches, SaleAlternativeMatch{
					ProductID:    alt.Product.ID.String(),
					BrandName:    alt.Product.Name,
					Size:         alt.Product.Size,
					SellingPrice: alt.Product.SellingPrice,
					Confidence:   alt.Score,
				})
			}

			// Get current stock for this product and shop
			var stock models.Stock
			err := s.db.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				req.ShopID, matchedProduct.ID, tenantID).First(&stock).Error

			if err == nil {
				dbStock := stock.Quantity
				validated.DBStock = &dbStock

				if item.OpeningStock != nil && *item.OpeningStock > 0 {
					validated.OpeningStock = item.OpeningStock
				} else {
					validated.OpeningStock = &dbStock
				}

				if item.OpeningStock != nil && *item.OpeningStock != dbStock {
					discrepancy := *item.OpeningStock - dbStock
					validated.Warnings = append(validated.Warnings,
						fmt.Sprintf("⚠️ Stock discrepancy: Image shows opening=%d, DB has %d (diff: %+d)",
							*item.OpeningStock, dbStock, discrepancy))
					validation.StockDiscrepancies++
				}

				if item.ClosingStock != nil {
					validated.ClosingStock = item.ClosingStock
				} else {
					var baseStock int
					if item.Total != nil && *item.Total > 0 {
						baseStock = *item.Total
					} else if validated.OpeningStock != nil {
						baseStock = *validated.OpeningStock
					}
					if baseStock > 0 {
						closingStock := baseStock - item.Quantity
						validated.ClosingStock = &closingStock
					}
				}

				// v1.0.124 — qty math gate. When OCR provides opening + closing
				// AND the resulting delta disagrees with the OCR'd sale qty by
				// more than max(1, opening * 5%), flag the row for review and
				// drop the sale-cell confidence so Flutter renders amber. The
				// Royal Stag case in Chhotu's job (sale=11, opening=27,
				// closing=25, math says delta=2) would have been flagged here.
				// Warning-only; never blocks submit.
				if item.OpeningStock != nil && item.ClosingStock != nil && item.Quantity > 0 {
					opening := *item.OpeningStock
					closing := *item.ClosingStock
					receipt := 0
					if item.Receipt != nil {
						receipt = *item.Receipt
					}
					mathDelta := opening + receipt - closing
					tolerance := 1.0
					if float64(opening)*0.05 > tolerance {
						tolerance = float64(opening) * 0.05
					}
					if absFloat(float64(mathDelta-item.Quantity)) > tolerance {
						validated.Warnings = append(validated.Warnings,
							fmt.Sprintf("⚠️ Sale qty %d disagrees with stock math (open %d + recv %d − close %d = %d)",
								item.Quantity, opening, receipt, closing, mathDelta))
						validated.NeedsReview = true
						validation.StockDiscrepancies++
						if validated.FieldConfidence == nil {
							validated.FieldConfidence = map[string]float64{}
						}
						if cur, ok := validated.FieldConfidence["sale"]; !ok || cur > 0.6 {
							validated.FieldConfidence["sale"] = 0.5
						}
						s.logger.Warnf("SmartSale: math gate fired for '%s' — sale %d vs delta %d", item.Brand, item.Quantity, mathDelta)

						// v1.0.133 — high-confidence auto-suggest. When the AI
						// flagged Opening AND Closing as both >=0.9 confident,
						// the math-derived Sale is the canonical answer and the
						// extracted Sale is the suspect cell (handwriting
						// confusion). Surface the derived value to Flutter as
						// a tap-to-accept chip so users don't have to do the
						// math themselves.
						//
						// v1.0.133-r7 — when both opening and closing have
						// field_confidence >= 0.9 AND the math-derived sale
						// is plausible (within sane bounds — not negative,
						// not larger than opening, not 0 when AI said >0),
						// auto-APPLY the math-derived qty (overwriting the
						// AI's suspect Sale read). User still sees the chip
						// "math: N (was M)" so they can revert with one tap.
						// This is the column-confusion fix Tushar called out
						// (R-S Barrel qty 82 was actually closing, sale was
						// 12 — opening 94 + receipt 0 - closing 82 = 12).
						if mathDelta >= 0 && mathDelta != item.Quantity && item.FieldConfidence != nil {
							openConf, openOk := item.FieldConfidence["opening"]
							closeConf, closeOk := item.FieldConfidence["closing"]
							if openOk && closeOk && openConf >= 0.9 && closeConf >= 0.9 {
								validated.SuggestedSale = mathDelta
								// v1.0.133-r7 — auto-apply when math is also
								// inside sane bounds: non-negative, ≤ opening
								// (you can't sell more than you had), and the
								// AI's extracted Sale is suspiciously close to
								// either Opening or Closing (the column-drift
								// signature). When all three conditions hold,
								// overwrite the suspect AI read.
								mathSafe := mathDelta <= opening
								extractedSuspect := item.Quantity == opening || item.Quantity == closing || item.Quantity > opening
								if mathSafe && extractedSuspect {
									prevQty := item.Quantity
									validated.Quantity = mathDelta
									validated.Amount = float64(mathDelta) * validated.Rate
									validated.Warnings = append(validated.Warnings,
										fmt.Sprintf("✓ Auto-applied math sale = %d (was %d — looked like column drift). Tap row to revert.",
											mathDelta, prevQty))
									s.logger.Infof("SmartSale: auto-applied math sale for '%s' — %d → %d (column-drift signature; opening=%d closing=%d)",
										item.Brand, prevQty, mathDelta, opening, closing)
								} else {
									validated.Warnings = append(validated.Warnings,
										fmt.Sprintf("Math suggests sale = %d (open %d + recv %d − close %d) — opening/closing both look clear",
											mathDelta, opening, receipt, closing))
								}
							}
						}
					}
				}

				availableStock := dbStock
				imageReceipt := 0
				if item.Receipt != nil && *item.Receipt > 0 {
					imageReceipt = *item.Receipt
					availableStock = dbStock + imageReceipt
				}
				if item.Quantity > availableStock {
					// v1.0.335 — over-sell guard at extraction time. Selling more
					// than the shop physically holds is impossible — almost always
					// an OCR qty misread (Moonwalk: sale read 50 against stock 11)
					// or a wrong product bind. Previously this only logged a vague
					// "need X, have Y (sale already recorded)" note and let the row
					// reach the review screen showing a bare negative closing
					// (−39). Now we flag it for review, drop the sale-cell
					// confidence so Flutter underlines the suspect number, and —
					// when a closing read exists — surface the math-derived sale
					// (stock + receipt − closing) as a tap-to-accept suggestion.
					// The apply stock-gate remains the hard block; this just makes
					// the row arrive already explained instead of looking broken.
					validated.Warnings = append(validated.Warnings,
						fmt.Sprintf("⚠️ Sale qty %d is more than the stock on hand (%d). Likely a misread — check the register's sold column.",
							item.Quantity, availableStock))
					validated.NeedsReview = true
					validation.StockIssues++
					if validated.FieldConfidence == nil {
						validated.FieldConfidence = map[string]float64{}
					}
					if cur, ok := validated.FieldConfidence["sale"]; !ok || cur > 0.45 {
						validated.FieldConfidence["sale"] = 0.4
					}
					if validated.SuggestedSale == 0 && item.ClosingStock != nil {
						md := dbStock + imageReceipt - *item.ClosingStock
						if md >= 0 && md <= availableStock && md != item.Quantity {
							validated.SuggestedSale = md
						}
					}
					s.logger.Warnf("SmartSale: over-sell guard — '%s' sale %d > available %d (db %d + receipt %d)",
						item.Brand, item.Quantity, availableStock, dbStock, imageReceipt)
				}
			} else if errors.Is(err, gorm.ErrRecordNotFound) {
				// Product exists but has no stock record in this shop — set to 0
				zeroStock := 0
				validated.DBStock = &zeroStock
				if item.OpeningStock != nil && *item.OpeningStock > 0 {
					validated.OpeningStock = item.OpeningStock
				} else {
					validated.OpeningStock = &zeroStock
				}
				if item.ClosingStock != nil {
					validated.ClosingStock = item.ClosingStock
				}
				s.logger.Infof("SmartSale: No stock record for '%s' at shop — treating as 0", matchedProduct.Name)
			} else {
				s.logger.Warnf("Failed to get stock: %v", err)
			}

			// Check rate match
			if matchedProduct.SellingPrice > 0 {
				invRate := matchedProduct.SellingPrice
				validated.InventoryRate = &invRate
				if absFloat(invRate-validated.Rate) > 1.0 && validated.Rate > 0 {
					validated.Warnings = append(validated.Warnings,
						fmt.Sprintf("⚠️ Rate mismatch: Inventory ₹%.0f vs Image ₹%.0f", invRate, validated.Rate))
					validation.RateMismatches++
				}
			}
			// v1.0.123: surface MRP-change audit on the response so Flutter
			// can render the 7-day transparency banner ("Price changed by
			// Tushar 2 days ago: ₹720 → ₹620"). Empty when product has never
			// had its MRP changed OR the change was >7 days ago (we still
			// emit but Flutter renders only when within the 7-day window).
			if matchedProduct.LastMRPChangeAt != nil {
				validated.LastMRPChangeAt = matchedProduct.LastMRPChangeAt
				validated.LastMRPChangeByName = matchedProduct.LastMRPChangeByName
				if matchedProduct.LastMRPChangePrevious > 0 {
					prev := matchedProduct.LastMRPChangePrevious
					validated.LastMRPChangePrevious = &prev
				}
			}

			validated.ExpectedAmount = validated.Rate * float64(validated.Quantity)
			if validated.Amount > 0 && validated.ExpectedAmount > 0 {
				if absFloat(validated.Amount-validated.ExpectedAmount) > 1.0 {
					validated.Warnings = append(validated.Warnings,
						fmt.Sprintf("⚠️ Amount mismatch: Image ₹%.0f vs Expected ₹%.0f", validated.Amount, validated.ExpectedAmount))
					validation.AmountMismatches++
				}
			}

			validated.IsValid = (validated.ValidationStatus == "matched" || validated.ValidationStatus == "low_confidence") && len(validated.Errors) == 0
		} else {
			// Not found — use shared matcher with lower threshold for suggestions
			validated.Errors = append(validated.Errors, "Product not found in inventory")
			validation.NotFoundItems++
			// Tag for the "pick or skip" UI bucket. Both genuine zero-confidence
			// rows and rows demoted by the 0.55 hard-floor REJECT land here.
			validated.BrandNotInCatalog = true
			validation.BrandNotInCatalogItems++

			// Build suggestion list using shared matcher with relaxed settings
			suggestProducts := make([]matching.Product, len(products))
			suggestMap := make(map[string]*models.Product, len(products))
			for pi := range products {
				p := &products[pi]
				bName := p.Name
				if p.Brand != nil {
					bName = p.Brand.Name
				}
				sp := matching.Product{
					ID:           p.ID.String(),
					Name:         p.Name,
					BrandName:    bName,
					DisplayName:  p.DisplayName,
					Size:         p.Size,
					SizeML:       matching.ParseSizeML(p.Size),
					SellingPrice: p.SellingPrice,
				}
				if exciseInfoMap != nil {
					if ei, ok := exciseInfoMap[p.ID.String()]; ok {
						sp.ExciseBrandName = ei.BrandName
						sp.ExciseDisplayName = ei.DisplayName
					}
				}
				suggestProducts[pi] = sp
				suggestMap[p.ID.String()] = p
			}
			suggestPrepared := matching.PrepareProducts(suggestProducts)
			suggestConfig := matching.DefaultSaleConfig()
			suggestConfig.MinThreshold = 0.15          // Very low — show more options for user to pick
			suggestConfig.MinTextThreshold = 0.10      // Very low for suggestions — we want to show price-matched options
			suggestConfig.PriceExactBoost = 0.25       // Price-based suggestions for not-found items
			suggestConfig.PriceCloseBoost = 0.15
			suggestConfig.PriceFarPenalty = 0.05       // Mild penalty only
			suggestConfig.MaxResults = 5

			suggestResults := matching.MatchProducts(item.Brand, matching.ParseSizeML(item.SizeText), ocrRate, suggestPrepared, suggestConfig)
			for _, sr := range suggestResults {
				if sp, ok := suggestMap[sr.ProductID]; ok {
					validated.AlternativeMatches = append(validated.AlternativeMatches, SaleAlternativeMatch{
						ProductID:    sr.ProductID,
						BrandName:    sp.Name,
						Size:         sp.Size,
						SellingPrice: sp.SellingPrice,
						Confidence:   sr.Score,
					})
				}
			}
		}

		if validated.IsValid {
			validation.ValidItems++
		}

		// Log all items with their extracted values including Receipt, Total, Rate and Amount
		receiptVal := 0
		if validated.Receipt != nil {
			receiptVal = *validated.Receipt
		}
		totalVal := 0
		if validated.Total != nil {
			totalVal = *validated.Total
		}
		openVal := 0
		if validated.OpeningStock != nil {
			openVal = *validated.OpeningStock
		}
		closeVal := 0
		if validated.ClosingStock != nil {
			closeVal = *validated.ClosingStock
		}
		s.logger.Infof("📋 Item #%d: %s | Open: %d | Rcpt: %d | Total: %d | Qty: %d | Rate: ₹%.2f | Amt: ₹%.2f | Close: %d | %s",
			validated.SerialNumber, validated.BrandName, openVal, receiptVal, totalVal, validated.Quantity, validated.Rate, validated.Amount, closeVal, validated.ValidationStatus)

		validatedItems = append(validatedItems, validated)
	}

	// Opening stock cross-validation: verify matches using DB stock as ground truth.
	// If OCR opening stock matches DB stock for a product, that confirms the match.
	// If it doesn't match, check if an alternative product has matching stock.
	s.stockCrossValidate(validatedItems, shopStockMap, products, tenantID)

	// v1.0.131 — stock-gated sale enforcement. The user requested: "sale will
	// only allowed for those who has stocks". This pass flags any matched row
	// where the shop has zero stock for the product (NoStockBlock=true). The
	// apply path refuses to persist a row with NoStockBlock=true; the Flutter
	// review screen surfaces a red "no stock — swap or skip" chip on each
	// blocked row. Runs AFTER stockCrossValidate so any stock-driven product
	// swap has already happened.
	if blocked := s.flagStockUnavailable(validatedItems, shopStockMap); blocked > 0 {
		validation.Warnings = append(validation.Warnings,
			fmt.Sprintf("%d row(s) flagged: shop has no stock for these products. Run AI Stock Setup or Purchase Entry first, or swap to a product that has stock.", blocked))
	}

	// v1.0.312 — close the "garbled OCR matched to a zero-stock product" loop.
	// flagStockUnavailable already marked NoStockBlock=true; this drops the
	// productID binding for rows whose match is suspect (fuzzy / short
	// digit-letter-mix raw OCR / weak jaccard) so they fall into the existing
	// "could not be matched and were skipped" bucket instead of cluttering
	// the operator's review with red flags they must clear by hand.
	if demoted := s.dropGarbledZeroStockMatches(validatedItems); demoted > 0 {
		validation.Warnings = append(validation.Warnings,
			fmt.Sprintf("%d garbled-OCR row(s) had no matching shop stock — moved to the skipped bucket. Pick a product manually if needed.", demoted))
	}

	// Cross-validate: detect row-swap errors where AI assigned data to wrong product.
	s.crossValidateAndSwapItems(validatedItems, products)

	// Flag items needing user review
	s.flagItemsForReview(validatedItems)

	// Per-page completeness + row-drift validators. Ported from Smart Stock
	// Setup where the same checks catch page-2-missing-items / rows 25-27
	// misalignment before matching can compound the errors. Keeps each row's
	// NeedsReview flag + reason in sync with what the user actually sees
	// broken on the page.
	s.validatePageCompleteness(validatedItems, extractionResult)

	// Count review stats for validation summary
	for _, item := range validatedItems {
		if item.NeedsReview {
			validation.NeedsReviewItems++
		}
		if item.IsZeroQuantity {
			validation.ZeroQuantityItems++
		}
		if item.ValidationStatus == "ambiguous" {
			validation.AmbiguousItems++
		}
		if item.ValidationStatus == "low_confidence" {
			validation.LowConfidenceItems++
		}
	}

	// Overall validation
	validation.IsValid = validation.ValidItems > 0 &&
		(validation.ShopNameMatch || validation.DetectedShopName == "")

	// Bubble shop / date / size mismatches into per-item warnings + force review.
	// Without this the Flutter UI only sees a top-level banner; individual rows
	// look "matched" and the user clicks save without realising the entire
	// register might belong to a different shop or day. Per-item flags route
	// every row through the needs-review bucket so the user must explicitly
	// confirm before stock is deducted.
	headerMismatch := !validation.ShopNameMatch || validation.DateMismatch || validation.SizeMismatch
	if headerMismatch {
		var reasons []string
		if !validation.ShopNameMatch {
			reasons = append(reasons, fmt.Sprintf("shop=%s≠%s", validation.DetectedShopName, req.ShopName))
		}
		if validation.DateMismatch {
			reasons = append(reasons, fmt.Sprintf("date=%s≠%s", validation.DetectedDate, req.SaleDate.Format("2006-01-02")))
		}
		if validation.SizeMismatch {
			reasons = append(reasons, fmt.Sprintf("size=%s≠%s", validation.DetectedSize, req.Size))
		}
		why := strings.Join(reasons, ", ")
		warn := "⚠️ Header mismatch (" + why + ") — verify before saving"
		for i := range validatedItems {
			validatedItems[i].NeedsReview = true
			if validatedItems[i].ReviewReason == "" {
				validatedItems[i].ReviewReason = "header mismatch: " + why
			}
			validatedItems[i].Warnings = append(validatedItems[i].Warnings, warn)
		}
	}

	// v1.0.116 setup-completeness gap detection: surface stock-setup products
	// that didn't appear in the sale extraction. The AI may have missed a row
	// (e.g. 100 STROKES ROYAL WHISKY — present in approved setup at ₹720 but
	// never extracted from the sale image on job 016a1e0b). The user can then
	// manually add the missing row's quantity. Only emits when at least one
	// extraction match landed on a setup product (otherwise we don't have
	// evidence the sale and setup are related).
	//
	// v1.0.303 — gated OFF by default. Operator directive 2026-05-23: do not
	// auto-inject "AI may have missed this row" suggestions; they create
	// phantom duplicates when SKU variants share a name (Royal Stag 90ml
	// duplicate at chhotu's shop). Set SMART_SALE_SETUP_RESCUE_ENABLED=1
	// to re-enable. See setupRescueEnabled() in textract_pipeline.go.
	if setupRescueEnabled() && len(setupByName) > 0 && len(matchedSetupProductIDs) > 0 {
		var missingNames []string
		// v1.0.117: auto-inject missing setup rows as needs_review items.
		// Previously we only emitted a warning string ("Setup has N missing"),
		// but the user has to manually re-open the setup and remember each
		// brand. Injecting them as needs_review rows surfaces every potentially-
		// missed product on the review screen with rate pre-filled. User just
		// bumps qty if there was a sale, or leaves it 0 (in which case the row
		// drops at apply time via the same qty>0 gate). Concretely fixes the
		// 100 STROKES ROYAL WHISKY case where AI never extracted the row but
		// it's in the approved setup at ₹720.
		injectedNumber := len(validatedItems) + 1
		// v1.0.142 — pre-fetch CURRENT stocks.quantity for every product we
		// might rescue. The setup-snapshot's OpeningQty represents stock
		// AT SETUP TIME; if purchases / other sales / day-closings have
		// happened since, current stock differs. Showing the stale snapshot
		// in the "X in stock" chip lets operators apply sales for products
		// they no longer have (Iconiq 750ml at FM Tower: setup says 3 in
		// stock, stocks.quantity says 0).
		setupRescueStockNow := make(map[string]int, len(setupByName))
		{
			pids := make([]uuid.UUID, 0, len(setupByName))
			for _, ref := range setupByName {
				if _, hit := matchedSetupProductIDs[ref.ProductID.String()]; !hit {
					pids = append(pids, ref.ProductID)
				}
			}
			if len(pids) > 0 {
				type stockRow struct {
					ProductID uuid.UUID `gorm:"column:product_id"`
					Quantity  int       `gorm:"column:quantity"`
				}
				var sr []stockRow
				// v1.0.148 — was `Raw("... product_id = ANY(?)", req.ShopID, pids)`,
				// but GORM Raw doesn't expand a []uuid.UUID into the ANY array
				// argument and pq drops the binding silently → the map stayed
				// empty and every rescued row fell through to the STALE snapshot
				// OpeningQty (M2 Magic 47-phantom on FM Tower 30-Apr 375ml).
				// Use GORM's idiomatic IN expansion so the slice expands.
				if err := s.db.
					Table("stocks").
					Select("product_id, COALESCE(quantity, 0) AS quantity").
					Where("shop_id = ? AND deleted_at IS NULL AND product_id IN ?", req.ShopID, pids).
					Scan(&sr).Error; err != nil {
					s.logger.Warnf("SmartSale: setup-rescue stocks lookup failed (will fall back to snapshot): %v", err)
				}
				for _, r := range sr {
					setupRescueStockNow[r.ProductID.String()] = r.Quantity
				}
				s.logger.Infof("SmartSale: setup-rescue current-stock map = %d/%d products (the rest fall back to snapshot OpeningQty)", len(sr), len(pids))
			}
		}

		// v1.0.163 — last-7-day per-shop sale qty for setup-rescue carry-forward.
		// Pre-fix every rescued row arrived with Quantity=0 forcing the operator
		// to type a digit even when the previous day's sale was right next to
		// it on the register. Now we seed Quantity with the latest approved
		// sale qty from this shop within 7 days (Source-tagged as
		// "setup_rescue" so the row stays needs_review until the operator
		// confirms — the auto-seeded qty is a hint, not a commitment).
		setupRescueLastQty := s.loadShopRecentSaleQty(tenantID, req.ShopID, 7)

		// v1.0.184 Track A5 — cap rescue list to top-N historical sellers.
		// Pre-fix the rescue branch added EVERY unmatched setup product back
		// as needs_review, which on FM Tower 90ml meant 8+ rescue rows for
		// products chhotu had never sold in 30 days. Now: rank candidates by
		// last-30-day distinct-sale-day count and keep only the top
		// SMART_SALE_RESCUE_MAX_ROWS (default 5). Fallbacks: when there's a
		// tie or no history, last-7-day qty is the secondary key, then
		// product name for stable order.
		freq := s.loadShopRecentSaleFrequency(tenantID, req.ShopID, 30)
		rescueCap := setupRescueMaxRows()
		// v1.0.184 Track B5 — pull per-shop drop counts so candidates the
		// operator has dropped repeatedly fall to the bottom of the ranking.
		dropCounts := s.loadShopRescueDropCounts(tenantID, req.ShopID)
		// Build candidate list (only unmatched products with non-zero current stock).
		type rescueCandidate struct {
			ref          stockSetupRef
			currentStock int
			freq30d      int
			lastQty      int
			dropCount    int
		}
		candidates := make([]rescueCandidate, 0, len(setupByName))
		for _, ref := range setupByName {
			if _, hit := matchedSetupProductIDs[ref.ProductID.String()]; hit {
				continue
			}
			pidStr := ref.ProductID.String()
			currentStock, hasCurrent := setupRescueStockNow[pidStr]
			if !hasCurrent {
				currentStock = ref.OpeningQty
			}
			if currentStock <= 0 {
				continue
			}
			candidates = append(candidates, rescueCandidate{
				ref:          ref,
				currentStock: currentStock,
				freq30d:      freq[pidStr],
				lastQty:      setupRescueLastQty[pidStr],
				dropCount:    dropCounts[pidStr],
			})
		}
		// Sort: lowest drop count first (avoid chronic drops), then highest
		// frequency, then highest last-qty, then name. Drop count dominates so
		// even a high-frequency product that's been dropped 5+ times falls
		// behind a fresh candidate.
		sort.Slice(candidates, func(i, j int) bool {
			if candidates[i].dropCount != candidates[j].dropCount {
				return candidates[i].dropCount < candidates[j].dropCount
			}
			if candidates[i].freq30d != candidates[j].freq30d {
				return candidates[i].freq30d > candidates[j].freq30d
			}
			if candidates[i].lastQty != candidates[j].lastQty {
				return candidates[i].lastQty > candidates[j].lastQty
			}
			return candidates[i].ref.ProductName < candidates[j].ref.ProductName
		})
		if rescueCap > 0 && len(candidates) > rescueCap {
			s.logger.Infof("SmartSale: setup-rescue capping %d candidates → top %d (by 30d sale frequency)", len(candidates), rescueCap)
			candidates = candidates[:rescueCap]
		}

		for _, cand := range candidates {
			ref := cand.ref
			pidStr := ref.ProductID.String()
			rateVal := ref.Rate
			currentStock := cand.currentStock
			zeroStock := currentStock
			// v1.0.163 — carry-forward seed qty from last-7-day approved sale.
			// Capped at currentStock so we never propose a qty that exceeds
			// today's available stock (chhotu would have to back it down
			// otherwise; capping is the safe default).
			seedQty := 0
			if last, ok := setupRescueLastQty[pidStr]; ok && last > 0 {
				seedQty = last
				if seedQty > currentStock {
					seedQty = currentStock
				}
			}
			rescueReason := "AI may have missed this row — present in latest stock setup. Verify and enter sale quantity if sold."
			rescueWarning := "AI may have missed this row from the register — verify"
			if seedQty > 0 {
				rescueReason = fmt.Sprintf("AI may have missed this row — last sale here was %d. Tap to confirm or edit.", seedQty)
				rescueWarning = fmt.Sprintf("Setup rescue — last sale was %d, tap to confirm", seedQty)
			}
			injected := SmartSaleExtractedItem{
				ProductID:        &pidStr,
				BrandName:        ref.ProductName,
				MatchedBrandName: ref.ProductName,
				OriginalAIBrand:  "", // we don't have an AI guess — AI missed this row entirely
				Size:             req.Size,
				Category:         req.Category,
				Quantity:         seedQty,
				Rate:             rateVal,
				InventoryRate:    &rateVal,
				Amount:           rateVal * float64(seedQty),
				ExpectedAmount:   rateVal * float64(seedQty),
				IsValid:          false,
				ValidationStatus: "needs_review",
				NeedsReview:      true,
				ReviewReason:     rescueReason,
				IsZeroQuantity:   seedQty == 0,
				MatchConfidence:  0.95, // strong: came directly from approved setup
				OpeningStock:     &zeroStock,
				DBStock:          &zeroStock,
				Confidence:       0.95,
				SerialNumber:     injectedNumber,
				Source:           "setup_rescue",
				Warnings:         []string{rescueWarning},
				Errors:           []string{},
			}
			validatedItems = append(validatedItems, injected)
			missingNames = append(missingNames, fmt.Sprintf("%s (₹%.0f)", ref.ProductName, ref.Rate))
			injectedNumber++
		}
		if len(missingNames) > 0 {
			validation.Warnings = append(validation.Warnings,
				fmt.Sprintf("AI may have missed %d row(s) from the register — added for review: %s",
					len(missingNames), strings.Join(missingNames, "; ")))
			validation.NeedsReviewItems += len(missingNames)
			validation.TotalItems += len(missingNames)
			s.logger.Infof("SmartSale: rescued %d AI-missed rows from approved stock setup (auto-injected as needs_review)", len(missingNames))
		}
	}

	return validatedItems, validation, nil
}

// crossValidateAndSwapItems detects when AI assigned data to the wrong row.
// Example: Register shows Royal Stag (rate=90) and Blender Pride (rate=120, qty=43).
// AI puts qty=43/rate=120 on Royal Stag (wrong). This detects the mismatch and swaps.
func (s *SmartSaleService) crossValidateAndSwapItems(items []SmartSaleExtractedItem, products []models.Product) {
	if len(items) < 2 {
		return
	}

	// Build product price map from matched products
	productPriceMap := make(map[string]float64) // product_id -> selling_price
	for _, p := range products {
		productPriceMap[p.ID.String()] = p.SellingPrice
	}

	// Find items with rate mismatches
	for i := 0; i < len(items); i++ {
		itemA := &items[i]
		if itemA.ProductID == nil || itemA.Rate == 0 || itemA.Quantity == 0 {
			continue
		}

		productAPrice := productPriceMap[*itemA.ProductID]
		if productAPrice == 0 || absFloat(productAPrice-itemA.Rate) <= 1.0 {
			continue // rate matches, no issue
		}

		// Item A has a rate mismatch — look for another item whose product price matches A's rate
		for j := 0; j < len(items); j++ {
			if i == j {
				continue
			}
			itemB := &items[j]
			if itemB.ProductID == nil {
				continue
			}

			productBPrice := productPriceMap[*itemB.ProductID]

			// Check: A's rate matches B's product price, AND B has no data (zero qty/rate)
			// OR B's rate matches A's product price (mutual swap)
			aRateMatchesB := absFloat(itemA.Rate-productBPrice) <= 1.0
			bHasNoData := itemB.Quantity == 0 || itemB.Rate == 0
			bRateMatchesA := itemB.Rate > 0 && absFloat(itemB.Rate-productAPrice) <= 1.0

			if aRateMatchesB && (bHasNoData || bRateMatchesA) {
				s.logger.Warnf("🔄 Row swap detected: '%s' (rate=₹%.0f) has data that belongs to '%s' (price=₹%.0f). Swapping.",
					itemA.BrandName, itemA.Rate, itemB.BrandName, productBPrice)

				// Swap numerical data between items
				itemA.Quantity, itemB.Quantity = itemB.Quantity, itemA.Quantity
				itemA.Rate, itemB.Rate = itemB.Rate, itemA.Rate
				itemA.Amount, itemB.Amount = itemB.Amount, itemA.Amount
				itemA.OpeningStock, itemB.OpeningStock = itemB.OpeningStock, itemA.OpeningStock
				itemA.Receipt, itemB.Receipt = itemB.Receipt, itemA.Receipt
				itemA.Total, itemB.Total = itemB.Total, itemA.Total
				itemA.ClosingStock, itemB.ClosingStock = itemB.ClosingStock, itemA.ClosingStock
				itemA.IsZeroQuantity, itemB.IsZeroQuantity = itemB.IsZeroQuantity, itemA.IsZeroQuantity
				itemA.ExpectedAmount, itemB.ExpectedAmount = itemB.ExpectedAmount, itemA.ExpectedAmount
				itemA.DBStock, itemB.DBStock = itemB.DBStock, itemA.DBStock
				itemA.OCRText, itemB.OCRText = itemB.OCRText, itemA.OCRText

				// Clear old rate-mismatch warnings since swap fixed them
				itemA.Warnings = filterWarnings(itemA.Warnings, "Rate mismatch")
				itemB.Warnings = filterWarnings(itemB.Warnings, "Rate mismatch")

				// Recalculate validity
				itemA.IsValid = itemA.ProductID != nil && len(itemA.Errors) == 0
				itemB.IsValid = itemB.ProductID != nil && len(itemB.Errors) == 0

				s.logger.Infof("🔄 After swap: '%s' Qty=%d Rate=₹%.0f | '%s' Qty=%d Rate=₹%.0f",
					itemA.BrandName, itemA.Quantity, itemA.Rate, itemB.BrandName, itemB.Quantity, itemB.Rate)

				break // One swap per item
			}
		}
	}
}

// stockGateEnforced checks whether the SMART_SALE_STOCK_GATE rule is enabled.
// When ON, sales are not allowed for products with DB stock = 0 — the user
// must first run AI Stock Setup or Purchase Entry to bring stock into the
// shop before recording a sale. PARITY with user requirement (v1.0.131):
// "sale will only allowed for those who has stocks". Default ON; disable via
// SMART_SALE_STOCK_GATE=0 if a tenant explicitly wants to allow over-sells.
func (s *SmartSaleService) stockGateEnforced() bool {
	return os.Getenv("SMART_SALE_STOCK_GATE") != "0"
}

// flagStockUnavailable runs after stock cross-validation and BEFORE setup-rescue.
// For each matched item with quantity > 0, checks shop stock; if stock is 0
// (or quantity exceeds available stock), surfaces a hard NeedsReview warning
// AND sets a NoStockBlock flag the apply-time gate uses to refuse the sale.
// v1.0.131 — addresses the user's "sale only for products with stock" rule.
func (s *SmartSaleService) flagStockUnavailable(items []SmartSaleExtractedItem, shopStockMap map[string]int) (blockedCount int) {
	if !s.stockGateEnforced() {
		return 0
	}
	for i := range items {
		item := &items[i]
		if item.ProductID == nil || *item.ProductID == "" {
			continue // unmatched rows handled separately
		}
		if item.Quantity <= 0 {
			continue // zero-qty rows have no inventory effect; gate is qty>0 only
		}
		dbStock, hasStock := shopStockMap[*item.ProductID]
		if !hasStock {
			// No stock row at all = product was never set up at this shop.
			items[i].NeedsReview = true
			items[i].NoStockBlock = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Cannot record sale: %s has no stock at this shop. Run AI Stock Setup or Purchase Entry first.", item.BrandName))
			blockedCount++
			continue
		}
		if dbStock <= 0 {
			items[i].NeedsReview = true
			items[i].NoStockBlock = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Cannot record sale: %s shop stock is 0. Receive new stock before recording this sale.", item.BrandName))
			blockedCount++
			continue
		}
		// v1.0.157 — effective_opening = dbStock + image_receipt. If the AI saw
		// a receipt column on the register, the physical opening today is
		// (yesterday's closing in system) + (units received per the image).
		// This honors a shopkeeper who took delivery but hasn't entered it as
		// a Purchase yet. Without this we'd block real sales just because the
		// user is behind on purchase entries.
		imageReceipt := 0
		if item.Receipt != nil && *item.Receipt > 0 {
			imageReceipt = *item.Receipt
		}
		effectiveOpening := dbStock + imageReceipt
		// Stamp the stock-context fields so Flutter can render
		// system_opening as primary + chips for divergence + purchase-missing.
		sysOpen := dbStock
		eff := effectiveOpening
		items[i].SystemOpening = &sysOpen
		items[i].EffectiveOpening = &eff
		// "Purchase not added" — AI saw a receipt > 0 on the register, but
		// the system shows db_stock equal to image_opening (i.e. without the
		// receipt). That means the operator took delivery but hasn't entered
		// the Purchase. Use ±2 tolerance to absorb minor digit fuzz.
		if imageReceipt > 0 && item.OpeningStock != nil {
			diff := *item.OpeningStock - dbStock
			if diff < 0 {
				diff = -diff
			}
			if diff <= 2 {
				items[i].PurchaseMissing = true
			}
		}
		if item.Quantity > effectiveOpening {
			// v1.0.157 — HARD BLOCK. Per user's explicit rule "sale quantity
			// not more than our system stock for that product". Was previously
			// a soft warning that allowed the row to apply and take stock
			// negative; chhotu's 0a54bcfe sale shipped 4 such rows because
			// nothing stopped them. Now we set NoStockBlock=true so the
			// review row gets the red hard-stop chip and the apply path
			// refuses the sale.
			items[i].NeedsReview = true
			items[i].NoStockBlock = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Sale quantity (%d) exceeds available stock (%d). Cannot apply.",
					item.Quantity, effectiveOpening))
			blockedCount++
		}
	}
	return blockedCount
}

// stockCrossValidate uses DB stock quantities to confirm or correct product matches.
// The register's opening stock should equal the DB's current stock (previous day's closing).
// When OCR opening matches DB stock for a product, it confirms the match.
// When it doesn't match, we check if an alternative product has matching stock and switch if so.
func (s *SmartSaleService) stockCrossValidate(items []SmartSaleExtractedItem, shopStockMap map[string]int, products []models.Product, tenantID uuid.UUID) {
	if len(shopStockMap) == 0 {
		return // no stock data to validate against
	}

	for i := range items {
		item := &items[i]
		if item.OpeningStock == nil || *item.OpeningStock == 0 {
			continue // no opening stock to validate
		}
		if item.ProductID == nil {
			continue // not matched
		}

		ocrOpening := *item.OpeningStock
		dbStock := shopStockMap[*item.ProductID]

		// Check if opening stock matches DB stock (±2 tolerance for small discrepancies)
		if absInt(ocrOpening-dbStock) <= 2 {
			// Confirmed! Opening stock matches DB — this is likely the correct product
			s.logger.Infof("✅ Stock confirmed: '%s' opening=%d, DB stock=%d", item.BrandName, ocrOpening, dbStock)
			continue
		}

		// Opening stock doesn't match — check if any alternative product has matching stock
		if len(item.AlternativeMatches) == 0 {
			continue
		}

		for _, alt := range item.AlternativeMatches {
			altDBStock := shopStockMap[alt.ProductID]
			if absInt(ocrOpening-altDBStock) <= 2 && altDBStock > 0 {
				// Alternative's stock matches OCR opening.
				// SAFETY: Only swap if the alternative's text confidence is close to the primary.
				// If the primary was a strong text match (e.g., 0.90), don't override based on stock alone.
				scoreDiff := item.MatchConfidence - alt.Confidence
				if scoreDiff > 0.15 {
					s.logger.Infof("⚠️ Stock correction SKIPPED: '%s' (score=%.2f) would swap to '%s' (score=%.2f, DB=%d matches opening=%d) but text score gap is too large (%.2f)",
						item.BrandName, item.MatchConfidence, alt.BrandName, alt.Confidence, altDBStock, ocrOpening, scoreDiff)
					continue
				}

				s.logger.Warnf("🔄 Stock correction: '%s' opening=%d doesn't match '%s' (DB=%d), but matches '%s' (DB=%d). Switching.",
					item.OCRText, ocrOpening, item.BrandName, dbStock, alt.BrandName, altDBStock)

				// Switch to alternative product
				oldName := item.BrandName
				item.ProductID = &alt.ProductID
				item.MatchedBrandName = alt.BrandName
				item.BrandName = alt.BrandName
				item.MatchConfidence = alt.Confidence

				// Re-determine status
				if alt.Confidence >= 0.80 {
					item.ValidationStatus = "matched"
				} else {
					item.ValidationStatus = "low_confidence"
				}
				item.IsValid = len(item.Errors) == 0
				item.Warnings = append(item.Warnings,
					fmt.Sprintf("Stock-corrected: was '%s' (DB=%d), changed to '%s' (DB=%d, matches opening=%d)",
						oldName, dbStock, alt.BrandName, altDBStock, ocrOpening))

				// Update DB stock reference
				item.DBStock = &altDBStock
				break
			}
		}
	}
}

// filterWarnings removes warnings containing the given substring
func filterWarnings(warnings []string, substr string) []string {
	filtered := []string{}
	for _, w := range warnings {
		if !strings.Contains(w, substr) {
			filtered = append(filtered, w)
		}
	}
	return filtered
}

// smartSaleAliasConflictRatePct returns the percent-divergence threshold above
// which two AI rows binding to the same product_id are flagged as an
// alias-conflict (v1.0.327). Configurable via SMART_SALE_ALIAS_CONFLICT_RATE_PCT
// env. Default 5.0 (5%) — below this, two rows are treated as legitimate
// same-SKU duplicates and silently collapsed via the v1.0.171 keeper logic.
func smartSaleAliasConflictRatePct() float64 {
	if v := strings.TrimSpace(os.Getenv("SMART_SALE_ALIAS_CONFLICT_RATE_PCT")); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil && parsed > 0 {
			return parsed
		}
	}
	return 5.0
}

// findAliasConflictPartner scans items for any row OTHER than thisSerial that
// shares the given product_id AND whose AI rate diverges from this row's rate
// by more than ratePctThreshold. Returns the keeper serial (lowest serial in
// the conflict group, used as a stable display anchor) and the rate of the
// most-divergent partner. Treats either side's rate==0 as "unknown, assume
// divergent" so a row with no extracted rate still trips the guard against a
// row that has one. v1.0.327.
func findAliasConflictPartner(items []SmartSaleExtractedItem, pid string, thisSerial int, ratePctThreshold float64) (keeperSerial int, divergent bool, partnerRate float64) {
	keeperSerial = thisSerial
	for j := range items {
		if items[j].ProductID == nil || *items[j].ProductID != pid {
			continue
		}
		if items[j].SerialNumber == thisSerial {
			continue
		}
		var thisRate, otherRate float64
		for k := range items {
			if items[k].SerialNumber == thisSerial {
				thisRate = items[k].Rate
				break
			}
		}
		otherRate = items[j].Rate
		divergeHere := false
		switch {
		case thisRate <= 0 || otherRate <= 0:
			divergeHere = true
		default:
			denom := thisRate
			if otherRate > denom {
				denom = otherRate
			}
			pct := (thisRate - otherRate)
			if pct < 0 {
				pct = -pct
			}
			pct = pct / denom * 100.0
			if pct > ratePctThreshold {
				divergeHere = true
			}
		}
		if divergeHere {
			divergent = true
			partnerRate = otherRate
		}
		if items[j].SerialNumber < keeperSerial {
			keeperSerial = items[j].SerialNumber
		}
	}
	return keeperSerial, divergent, partnerRate
}

// flagItemsForReview marks items that need user attention
func (s *SmartSaleService) flagItemsForReview(items []SmartSaleExtractedItem) {
	// Track product_id usage for duplicate detection
	productUsage := make(map[string][]int) // product_id -> serial numbers
	for i := range items {
		if items[i].ProductID != nil {
			productUsage[*items[i].ProductID] = append(productUsage[*items[i].ProductID], items[i].SerialNumber)
		}
	}

	for i := range items {
		// Flag 1: Rate is ₹0 but quantity > 0
		if items[i].Rate == 0 && items[i].Quantity > 0 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Rate is ₹0 — please verify the correct selling price"
			}
		}

		// v1.0.131 Flag 1a: field-confidence floor gate (PARITY:
		// smart_stock_setup_service.go:1433-1448 WS-C-2). When voting or
		// per-cell extraction set FieldConfidence[k] to a low value, surface
		// it as a per-cell warning so the Flutter amber-underline UI can
		// pinpoint exactly which column the AI was unsure about. Threshold
		// 0.70 matches Stock Setup. Skip rows where the AI returned no
		// FieldConfidence map at all (Gemini fallback path).
		if items[i].Quantity > 0 && len(items[i].FieldConfidence) > 0 {
			gateFields := []string{"sale", "quantity", "rate", "amount", "opening"}
			lowFields := []string{}
			for _, f := range gateFields {
				if c, ok := items[i].FieldConfidence[f]; ok && c > 0 && c < 0.70 {
					lowFields = append(lowFields, f)
				}
			}
			if len(lowFields) > 0 {
				items[i].NeedsReview = true
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = "AI was unsure of: " + strings.Join(lowFields, ", ") + " — verify before saving"
				}
				items[i].Warnings = append(items[i].Warnings,
					"AI was unsure of: "+strings.Join(lowFields, ", "))
			}
		}

		// v1.0.131 Flag 1b: closing-arithmetic gate using Total when present
		// (PARITY: smart_stock_setup_service.go:1540-1548 WS-B-2). Pre-v1.0.131
		// Smart Sale's only math gate at L1752 used opening+receipt-closing.
		// This second gate fires whenever Total > 0 AND Closing != Total - Sale,
		// regardless of whether Closing was AI-extracted as 0 — catches the
		// "register math doesn't balance" case that the simpler gate misses
		// when Closing column is blurry but Total is legible.
		if items[i].Total != nil && *items[i].Total > 0 && *items[i].Total >= items[i].Quantity {
			totalVal := *items[i].Total
			expectedClose := totalVal - items[i].Quantity
			closeVal := 0
			if items[i].ClosingStock != nil {
				closeVal = *items[i].ClosingStock
			}
			if closeVal > 0 && closeVal != expectedClose {
				items[i].NeedsReview = true
				w := fmt.Sprintf("Closing(%d) ≠ Total(%d) - Sale(%d) = %d — register math doesn't balance",
					closeVal, totalVal, items[i].Quantity, expectedClose)
				items[i].Warnings = append(items[i].Warnings, w)
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = w
				}
			}
		}

		// Flag 2: Low confidence match (< 0.70)
		if items[i].MatchConfidence > 0 && items[i].MatchConfidence < 0.70 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Low confidence match — please verify brand name"
			}
		}

		// Flag 3: Not found
		if items[i].ValidationStatus == "not_found" {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Product not found — please select from suggestions or search"
			}
		}

		// Flag 4: Ambiguous (multiple close matches)
		if items[i].ValidationStatus == "ambiguous" {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Multiple products match — please select the correct one"
			}
		}

		// Flag 5: Duplicate product match — only flag the LOWER confidence duplicate
		// The highest confidence match keeps the product; others get flagged.
		//
		// v1.0.153 — multi-signal tie-break (chhotu's 30-Apr "Sov 1965 XXX Rum
		// matched to rows 1, 10, 11" class). Picking the keeper purely by
		// match_confidence let row-index drift on undercounted CV pages survive
		// as the keeper while the actually-correct row got rejected. New scoring
		// (descending priority): math_confirmed (open-close == ai_sale ±1),
		// match_confidence, then earliest serial_number. The math signal wins
		// because it's an internal-consistency check independent of the
		// matcher; if the row's own numbers add up, it's the real read.
		mathOK := func(it SmartSaleExtractedItem) bool {
			if it.OpeningStock == nil || it.ClosingStock == nil {
				return false
			}
			diff := *it.OpeningStock - *it.ClosingStock
			d := diff - it.Quantity
			if d < 0 {
				d = -d
			}
			return d <= 1 && diff >= 0
		}
		score := func(it SmartSaleExtractedItem) (mathBonus int, conf float64, sn int) {
			if mathOK(it) {
				mathBonus = 1
			}
			return mathBonus, it.MatchConfidence, it.SerialNumber
		}
		better := func(a, b SmartSaleExtractedItem) bool {
			am, ac, asn := score(a)
			bm, bc, bsn := score(b)
			if am != bm {
				return am > bm
			}
			if ac != bc {
				return ac > bc
			}
			return asn < bsn
		}
		if items[i].ProductID != nil {
			pid := *items[i].ProductID
			if indices, ok := productUsage[pid]; ok && len(indices) > 1 {
				// v1.0.327 — Alias-conflict detection. When two AI rows bind to
				// the SAME product_id but their OCR rates diverge meaningfully,
				// the matcher conflated two distinct SKUs (e.g. "8PM PET ₹130"
				// + "8PM Tetra ₹140" both matched to one '8 PM Gold Scotch'
				// product). Surface this as a BLOCKING per-row warning so the
				// operator MUST rebind one before submitting. The warning
				// substring "alias_conflict_row_" is listed in
				// smart_sale_review_gate.go blockingWarningSubstrings AND in
				// Flutter's blockingWarningSubstrings (smart_sale_screen.dart).
				ratePct := smartSaleAliasConflictRatePct() // env-configurable, default 5%
				keeperSerial, divergePartner, partnerRate := findAliasConflictPartner(items, pid, items[i].SerialNumber, ratePct)
				if divergePartner {
					// Tag THIS row (regardless of keeper status) with the
					// alias-conflict warning + NeedsReview. Both rows in the
					// pair end up tagged because flagItemsForReview iterates
					// every item. Do NOT clear ProductID here — operator
					// needs to see the binding to understand the conflict;
					// the review-gate + apply-time guard block submission.
					alias := fmt.Sprintf("alias_conflict_row_%d", keeperSerial)
					if !containsString(items[i].Warnings, alias) {
						items[i].Warnings = append(items[i].Warnings, alias)
					}
					items[i].NeedsReview = true
					if items[i].ReviewReason == "" {
						items[i].ReviewReason = fmt.Sprintf(
							"Same product as row #%d (AI rate ₹%.0f vs ₹%.0f) — rebind one row to the correct SKU before submitting",
							keeperSerial, items[i].Rate, partnerRate)
					}
					continue
				}

				// No rate divergence → legitimate same-SKU dup (or rates
				// agree closely enough that silent merge is safe). Fall back
				// to the v1.0.171 strict-clear behaviour: pick the keeper
				// via math/confidence/serial; non-keepers get product_id
				// cleared and fall to operator picker like a "not_found".
				isHighest := true
				for j := range items {
					if j == i || items[j].ProductID == nil || *items[j].ProductID != pid {
						continue
					}
					if better(items[j], items[i]) {
						isHighest = false
						break
					}
				}
				if !isHighest {
					reassigned := false
					if len(items[i].AlternativeMatches) > 0 {
						for _, alt := range items[i].AlternativeMatches {
							altUsed := false
							for k := range items {
								if k == i {
									continue
								}
								if items[k].ProductID != nil && *items[k].ProductID == alt.ProductID {
									altUsed = true
									break
								}
							}
							if !altUsed && alt.Confidence > 0.50 {
								items[i].ProductID = &alt.ProductID
								items[i].MatchedBrandName = alt.BrandName
								items[i].BrandName = alt.BrandName
								items[i].MatchConfidence = alt.Confidence
								items[i].NeedsReview = true
								items[i].ReviewReason = fmt.Sprintf("Auto-reassigned from duplicate (was rows %v) — please verify", indices)
								reassigned = true
								break
							}
						}
					}
					if !reassigned {
						// v1.0.171 strict no-duplicate enforcement preserved
						// for the rates-agree case — silent merge of two
						// rows with matching rates is safe to collapse, but
						// we still prefer to clear the loser so apply sees
						// a single row per product_id.
						items[i].ProductID = nil
						items[i].MatchedBrandName = ""
						items[i].MatchConfidence = 0
						items[i].ValidationStatus = "not_found"
						items[i].NeedsReview = true
						if items[i].ReviewReason == "" {
							items[i].ReviewReason = fmt.Sprintf("Duplicate of rows %v — pick a different product", indices)
						}
					}
				}
			}
		}

		// Flag 6: Rate mismatch > ₹20 with inventory
		if items[i].InventoryRate != nil && items[i].Rate > 0 {
			if absFloat(*items[i].InventoryRate-items[i].Rate) > 20.0 {
				items[i].NeedsReview = true
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = fmt.Sprintf("Rate mismatch: register ₹%.0f vs inventory ₹%.0f", items[i].Rate, *items[i].InventoryRate)
				}
			}
		}
	}

	// v1.0.131 Flag 11: Adjacent-row Opening drift (PARITY:
	// smart_stock_setup_service.go:1586-1614 WS-C-3). Two adjacent rows on
	// the same page almost never have identical Opening counts when both
	// reference different products. When they do AND both >0, the AI most
	// likely vertical-drifted (read row N-1's Opening twice instead of
	// reading row N's). Flag both rows and drop opening field-confidence so
	// the amber underline lights up. Adjacency is computed per-page in
	// (PageNumber, RowNumber) order — items[] arrives in arbitrary post-
	// match-shuffling order, so we walk a sorted index list.
	type pageRowIdx struct {
		page, row, idx int
	}
	indexed := make([]pageRowIdx, 0, len(items))
	for i := range items {
		indexed = append(indexed, pageRowIdx{items[i].PageNumber, items[i].RowNumber, i})
	}
	for a := 0; a < len(indexed); a++ {
		for b := a + 1; b < len(indexed); b++ {
			if indexed[a].page > indexed[b].page ||
				(indexed[a].page == indexed[b].page && indexed[a].row > indexed[b].row) {
				indexed[a], indexed[b] = indexed[b], indexed[a]
			}
		}
	}
	for k := 1; k < len(indexed); k++ {
		if indexed[k].page != indexed[k-1].page {
			continue // adjacency only meaningful within a page
		}
		if indexed[k].row != indexed[k-1].row+1 {
			continue // not directly adjacent (gap from skipped/voted-in rows)
		}
		prevIdx, curIdx := indexed[k-1].idx, indexed[k].idx
		prev := &items[prevIdx]
		cur := &items[curIdx]
		if prev.OpeningStock == nil || cur.OpeningStock == nil {
			continue
		}
		prevOp := *prev.OpeningStock
		curOp := *cur.OpeningStock
		if prevOp <= 0 || curOp != prevOp {
			continue
		}
		// Different products — vertical-drift signature. (Two rows pointing
		// at the SAME product is just a duplicate, handled by Flag 5.)
		if prev.ProductID != nil && cur.ProductID != nil && *prev.ProductID == *cur.ProductID {
			continue
		}
		if cur.FieldConfidence == nil {
			cur.FieldConfidence = map[string]float64{}
		}
		if prev.FieldConfidence == nil {
			prev.FieldConfidence = map[string]float64{}
		}
		cur.FieldConfidence["opening"] = 0.55
		prev.FieldConfidence["opening"] = 0.55
		cur.NeedsReview = true
		prev.NeedsReview = true
		warn := fmt.Sprintf("Opening(%d) matches previous row's opening — possible vertical drift, verify", curOp)
		cur.Warnings = append(cur.Warnings, warn)
		prev.Warnings = append(prev.Warnings, "Opening matches next row — possible vertical drift, verify")
		if cur.ReviewReason == "" {
			cur.ReviewReason = warn
		}
	}

	// v1.0.131 Flag 12: Page-level opening collapse (PARITY:
	// smart_stock_setup_service.go:1617-1663 WS-C-3b). Catches the worst
	// failure mode where AI emits the same opening for many rows because
	// it couldn't distinguish them (poor lighting, ditto-marks). Adjacent-
	// pair detector above catches stair-step drift but misses this global
	// collapse — N rows with identical opening, scattered through the page.
	// Threshold: any opening value appearing in ≥3 rows AND ≥30% of the
	// page's rows. All affected rows get field_confidence.opening=0.30
	// (re-extraction-grade low) + a page-level warning.
	pageRows := map[int][]int{}
	for i := range items {
		pageRows[items[i].PageNumber] = append(pageRows[items[i].PageNumber], i)
	}
	for page, idxs := range pageRows {
		if len(idxs) < 4 {
			continue
		}
		freq := map[int][]int{}
		for _, i := range idxs {
			if items[i].OpeningStock == nil {
				continue
			}
			op := *items[i].OpeningStock
			if op <= 0 {
				continue
			}
			freq[op] = append(freq[op], i)
		}
		pageRowCount := len(idxs)
		for op, hitIdxs := range freq {
			ratio := float64(len(hitIdxs)) / float64(pageRowCount)
			if len(hitIdxs) >= 3 && ratio >= 0.30 {
				warn := fmt.Sprintf("Page-level opening collapse: %d rows share opening=%d (%.0f%% of page %d) — re-extract this page",
					len(hitIdxs), op, ratio*100, page)
				for _, i := range hitIdxs {
					if items[i].FieldConfidence == nil {
						items[i].FieldConfidence = map[string]float64{}
					}
					items[i].FieldConfidence["opening"] = 0.30
					items[i].NeedsReview = true
					items[i].Warnings = append(items[i].Warnings, warn)
					if items[i].ReviewReason == "" {
						items[i].ReviewReason = warn
					}
				}
				s.logger.Warnf("SmartSale: %s", warn)
			}
		}
	}
}

// validatePageCompleteness runs per-page sanity checks on the extracted rows
// to catch three classes of accuracy bug before the user sees the result:
//
//   1. **Missing trailing rows on a page** — if the AI returns fewer rows
//      than the serial-number sequence implies, every item on that page is
//      flagged for review with a clear "Page N may be incomplete" reason.
//      This is the fix for "second page items are missing" — rather than
//      silently ship a short list, we surface the gap.
//
//   2. **Row-drift duplicates** — two consecutive rows on the same page
//      with identical opening/closing values are almost certainly AI row
//      confusion (it read the same row twice). Both rows get flagged.
//
//   3. **Per-page low-confidence gate** — if the average match confidence
//      for a page dips below the threshold, every item from that page gets
//      flagged so the user reviews the whole page rather than individual
//      rows. Matches Stock Setup's behaviour where a single bad page
//      blocks auto-apply until the user confirms.
//
// Why per-page, not global: Stock Setup learned the hard way that page 1
// can be pristine while page 2 is a row-drift disaster; global averages
// hide which page is broken. Flutter uses PageNumber on each item to
// group the review UI under "Page N" headers.
func (s *SmartSaleService) validatePageCompleteness(
	items []SmartSaleExtractedItem,
	extractionResult *ReceiptExtractionResult,
) {
	if len(items) == 0 {
		return
	}

	// Group indices by page so every check can scope itself to one page at a
	// time. Items without an explicit PageNumber (legacy single-image flow)
	// land in bucket 0; we still check them, just without per-page UX.
	byPage := make(map[int][]int)
	for i, it := range items {
		byPage[it.PageNumber] = append(byPage[it.PageNumber], i)
	}

	// Pages sorted ascending so log output is predictable and diagnosis is
	// easy ("page 2 had issues" is more useful than map-iteration order).
	pages := make([]int, 0, len(byPage))
	for p := range byPage {
		pages = append(pages, p)
	}
	sort.Ints(pages)

	// v1.0.306 — pre-filter check using PerPageStats. Detects the case
	// where Textract extracted rows on a page but EVERY row was later
	// dropped (qty=0 filter, hallucination filter, no-product-match) AND
	// per-page rescue either didn't fire or also returned 0 rows. The
	// existing Check 1 (post-filter maxRowSeen vs len(idxs)) can't catch
	// this because byPage[p] is empty → skipped entirely. The result is a
	// silent missing page that the user only notices by counting items.
	if extractionResult != nil && len(extractionResult.PerPageStats) > 0 {
		for _, ps := range extractionResult.PerPageStats {
			if ps.PageNumber <= 0 || ps.RawRowCount < 3 {
				continue
			}
			if len(byPage[ps.PageNumber]) > 0 {
				continue
			}
			// Whole page silently dropped — flag every surviving item on
			// adjacent pages so the operator sees the gap warning somewhere.
			// Picks the first page index with items as the carrier.
			carrier := -1
			for _, p := range pages {
				if len(byPage[p]) > 0 {
					carrier = p
					break
				}
			}
			if carrier < 0 {
				continue
			}
			warn := fmt.Sprintf(
				"Page %d appears empty — extraction returned %d rows but none survived filtering. Please re-capture or check this page before applying.",
				ps.PageNumber, ps.RawRowCount)
			for _, idx := range byPage[carrier] {
				items[idx].NeedsReview = true
				if items[idx].ReviewReason == "" {
					items[idx].ReviewReason = warn
				}
				if !containsString(items[idx].Warnings, fmt.Sprintf("page_disappeared:%d", ps.PageNumber)) {
					items[idx].Warnings = append(items[idx].Warnings,
						fmt.Sprintf("page_disappeared:%d:raw_rows:%d", ps.PageNumber, ps.RawRowCount))
				}
			}
			s.logger.Warnf("SmartSale: page %d disappeared from final items (raw=%d max_row=%d post_filter=%d) — surfaced as warning on page %d",
				ps.PageNumber, ps.RawRowCount, ps.MaxRowNumber, ps.PostFilterRowCount, carrier)
		}
	}

	const lowConfidenceThreshold = 0.65

	// ── Check 0: Structural row-scramble gate (v1.0.340, Bug 1 fix) ──────
	// The OCR pipeline already DETECTS when Textract returns rows out of
	// order (flagRowOrderInversions → "textract_row_order_inversion") or
	// binds a brand cell to the wrong row ("textract_cell_y_outlier:brand").
	// Historically those were warning-only: a row could still auto-save with
	// NeedsReview=false if its brand→product match confidence was high. But a
	// row-order inversion means the QUANTITY may belong to a DIFFERENT brand
	// than the one matched — match confidence (which only scores brand→SKU)
	// cannot see that. This is exactly how Malsaii d6f860d1 silently saved a
	// 3-row quantity rotation (8PM Gold/Moonwalk/Officer's Choice). Force
	// review on any structurally-suspect row so a human re-confirms the
	// quantity before it ever touches stock. Kill-switch
	// SMART_SALE_SCRAMBLE_GATE=0.
	if os.Getenv("SMART_SALE_SCRAMBLE_GATE") != "0" {
		scrambleFlagged := 0
		for i := range items {
			structural := false
			for _, w := range items[i].Warnings {
				if strings.HasPrefix(w, "textract_row_order_inversion") {
					structural = true
					break
				}
				// Severe brand-cell misbinding only (≥100% of a row out of
				// position) — the FM Tower "8 PM Gold PET vs Tetra" class.
				// Borderline geometry (the 60-75% handwriting jitter seen on
				// most rows) is intentionally NOT gated, to avoid red-flagging
				// every line and recreating the v1.0.319 UX regression.
				if strings.HasPrefix(w, "textract_cell_y_outlier:brand:delta_pct=") {
					if pct, err := strconv.Atoi(w[strings.LastIndex(w, "=")+1:]); err == nil && pct >= 100 {
						structural = true
						break
					}
				}
				// v1.0.341 — drifted SALE/quantity cell. This is the direct
				// cause of the wrong-quantity-on-right-brand scramble, so gate
				// it a touch more eagerly than the brand cell: ≥90% of a row out
				// of position means the digit almost certainly belongs to an
				// adjacent line. Below that is normal handwriting jitter.
				if strings.HasPrefix(w, "textract_cell_y_outlier:sale:delta_pct=") {
					if pct, err := strconv.Atoi(w[strings.LastIndex(w, "=")+1:]); err == nil && pct >= 90 {
						structural = true
						break
					}
				}
			}
			if structural && !items[i].NeedsReview {
				items[i].NeedsReview = true
				scrambleFlagged++
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = "The scanner read this page's rows out of order, so this row's sale quantity may belong to a different brand. Please re-check the quantity against the receipt before applying."
				}
			}
		}
		if scrambleFlagged > 0 {
			s.logger.Warnf("SmartSale: structural row-scramble gate forced review on %d row(s) (row-order inversion / severe brand-cell misbinding)", scrambleFlagged)
		}
	}

	for _, page := range pages {
		idxs := byPage[page]
		if len(idxs) == 0 {
			continue
		}

		// ── Check 1: Trailing-row gap detection ───────────────────────
		// If the highest row_number reported by the AI implies more rows
		// than we actually have, the AI dropped rows at the bottom. Flag
		// every item on the page with a clear reason so the user knows
		// to re-check the source image rather than trusting the partial
		// result.
		maxRowSeen := 0
		for _, idx := range idxs {
			if items[idx].RowNumber > maxRowSeen {
				maxRowSeen = items[idx].RowNumber
			}
		}
		if maxRowSeen > len(idxs)+1 {
			// The +1 slack absorbs a single handwritten row the AI gave a
			// non-sequential number; more than that is a real gap.
			missing := maxRowSeen - len(idxs)
			//
			// v1.0.319 — narrow the flag. The original blanket "every row
			// on this page needs review" was the single biggest UX
			// complaint on 2026-05-24: chhotu's 180ml job a7674aa9
			// returned 26 high-confidence matches but maxRowSeen=30 (4
			// printed-list rows that the operator legitimately didn't
			// fill that day). Check 1 fired and turned all 26 rows red,
			// forcing the operator to confirm-and-re-enter every line.
			// They submitted at positions 999xxx (manual-add slot) for
			// the entire page.
			//
			// New rule:
			//   - PAGE-level warning is preserved (logger + Warnings tag
			//     on every row) for telemetry and the Flutter top-of-page
			//     banner.
			//   - ROW-level NeedsReview only fires on rows that are
			//     themselves suspect — confidence < 0.85 OR no product_id
			//     bound OR an earlier check already flagged them. A row
			//     that the matcher resolved cleanly is left alone so the
			//     operator can submit it without manual confirmation.
			//
			// The "verify no item is missing" hint moves to the FIRST
			// already-flagged row on the page (if any) so the operator
			// still sees the message in context; if every row is clean,
			// the page-level Warnings tag is the only signal — Flutter
			// renders a single banner instead of red-flagging the list.
			const confidentMatchThreshold = 0.85
			firstFlaggedIdx := -1
			for _, idx := range idxs {
				if !containsString(items[idx].Warnings, "page_incomplete") {
					items[idx].Warnings = append(items[idx].Warnings, fmt.Sprintf("page_incomplete:%d:missing:%d", page, missing))
				}
				rowConfident := items[idx].MatchConfidence >= confidentMatchThreshold && items[idx].ProductID != nil && *items[idx].ProductID != ""
				if rowConfident && !items[idx].NeedsReview {
					// Leave clean matched rows alone — operator already
					// has trustworthy data here.
					continue
				}
				items[idx].NeedsReview = true
				if firstFlaggedIdx < 0 {
					firstFlaggedIdx = idx
				}
				if items[idx].ReviewReason == "" {
					items[idx].ReviewReason = fmt.Sprintf(
						"Page %d may be incomplete — AI returned %d rows but the page has ~%d. Please verify no item is missing before applying.",
						page, len(idxs), maxRowSeen)
				}
			}
			s.logger.Warnf("SmartSale: page %d likely incomplete — %d rows returned, highest row_number=%d (possible %d missing); flagged %d row(s) for review, left confident-match rows clean",
				page, len(idxs), maxRowSeen, missing, func() int {
					n := 0
					for _, idx := range idxs {
						if items[idx].NeedsReview {
							n++
						}
					}
					return n
				}())
		}

		// ── Check 2: Adjacent-row row-drift (duplicate opening/closing) ─
		// AI occasionally reads the same register row twice, especially
		// around handwritten additions. Two consecutive rows with
		// identical opening+closing that aren't both zero is a strong
		// row-drift signal. Flag both rows so user can see the confusion.
		for k := 1; k < len(idxs); k++ {
			a := &items[idxs[k-1]]
			b := &items[idxs[k]]
			// Skip zero-zero pairs — legitimate back-to-back no-sale rows
			// on an inactive product range.
			aOpen, aClose := derefIntOrZero(a.OpeningStock), derefIntOrZero(a.ClosingStock)
			bOpen, bClose := derefIntOrZero(b.OpeningStock), derefIntOrZero(b.ClosingStock)
			if aOpen == 0 && aClose == 0 {
				continue
			}
			if aOpen == bOpen && aClose == bClose {
				for _, idx := range []int{idxs[k-1], idxs[k]} {
					items[idx].NeedsReview = true
					if items[idx].ReviewReason == "" {
						items[idx].ReviewReason = fmt.Sprintf(
							"Adjacent rows %d and %d on page %d have identical opening/closing — possible row-drift, please verify",
							a.RowNumber, b.RowNumber, page)
					}
				}
			}
		}

		// ── Check 3: Per-page low-confidence gate ─────────────────────
		// Some rows have MatchConfidence=0 before product matching
		// succeeds; skip those from the average so we measure actual
		// quality, not "how many rows we've tried to match yet".
		var confSum float64
		var confCount int
		for _, idx := range idxs {
			if items[idx].MatchConfidence > 0 {
				confSum += items[idx].MatchConfidence
				confCount++
			}
		}
		if confCount >= 3 { // need enough samples to trust the average
			avg := confSum / float64(confCount)
			if avg < lowConfidenceThreshold {
				for _, idx := range idxs {
					items[idx].NeedsReview = true
					if items[idx].ReviewReason == "" {
						items[idx].ReviewReason = fmt.Sprintf(
							"Page %d has low average match confidence (%.2f) — please verify every item on this page before applying",
							page, avg)
					}
				}
				s.logger.Warnf("SmartSale: page %d low-confidence gate fired (avg=%.2f, threshold=%.2f, items=%d)",
					page, avg, lowConfidenceThreshold, confCount)
			}
		}
	}
}

// derefIntOrZero returns the pointee of a *int or 0 if nil. Avoids the
// repeated nil-check boilerplate in the row-drift comparison above.
func derefIntOrZero(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}

// containsString reports whether s contains the exact string v. Used to
// de-dupe warning tags without pulling strings.Contains (which does
// substring, not exact).
func containsString(s []string, v string) bool {
	for _, x := range s {
		if x == v {
			return true
		}
	}
	return false
}

// saleProductMatch is a candidate product match with score
type saleProductMatch struct {
	Product     *models.Product
	Score       float64
	PriceMatch  bool
	NeedsReview bool // v1.0.160 — narrow ambiguity between two stocked products
}

// exciseInfo is the authoritative brand name + display name from saas_brands (master catalog).
// Empty strings when a product has no saas_brand_id.
//
// v1.0.173 — MetaKeywords carries master-curated shop-floor synonyms / abbreviations
// (e.g. ["mcd","mc dowells","no1 original"] for Mc Dowells). Used by the matcher's
// name-token jaccard as an additional source of truth — a row whose OCR text matches
// a meta_keyword scores as if the OCR had said the canonical name.
type exciseInfo struct {
	BrandName    string
	DisplayName  string
	MetaKeywords []string
}

// loadExciseInfoMap fetches saas_brands.name + display_name for every product that has
// saas_brand_id set, returning a productID → exciseInfo map. Single query regardless of
// product count; missing rows are simply absent from the map.
func (s *SmartSaleService) loadExciseInfoMap(products []models.Product) map[string]exciseInfo {
	result := make(map[string]exciseInfo, len(products))
	if len(products) == 0 {
		return result
	}
	// Collect unique brand IDs (saas_brand_id) and a reverse index brand→[productIDs]
	brandToProducts := make(map[uuid.UUID][]string)
	for i := range products {
		p := &products[i]
		if p.SaaSBrandID == nil {
			continue
		}
		brandToProducts[*p.SaaSBrandID] = append(brandToProducts[*p.SaaSBrandID], p.ID.String())
	}
	if len(brandToProducts) == 0 {
		return result
	}
	brandIDs := make([]uuid.UUID, 0, len(brandToProducts))
	for id := range brandToProducts {
		brandIDs = append(brandIDs, id)
	}
	type row struct {
		ID              uuid.UUID
		Name            string
		DisplayName     string
		MetaKeywordsCSV string `gorm:"column:meta_keywords_csv"`
	}
	var rows []row
	if err := s.db.Raw(`
		SELECT id, name,
		       COALESCE(NULLIF(display_name, ''), '') AS display_name,
		       COALESCE(array_to_string(meta_keywords, '|'), '') AS meta_keywords_csv
		FROM saas_brands WHERE id IN (?) AND deleted_at IS NULL`, brandIDs).Scan(&rows).Error; err != nil {
		s.logger.Warnf("SmartSale: excise info fetch failed: %v", err)
		return result
	}
	totalKw := 0
	for _, r := range rows {
		var kws []string
		if r.MetaKeywordsCSV != "" {
			for _, k := range strings.Split(r.MetaKeywordsCSV, "|") {
				k = strings.TrimSpace(k)
				if k != "" {
					kws = append(kws, k)
				}
			}
		}
		info := exciseInfo{BrandName: r.Name, DisplayName: r.DisplayName, MetaKeywords: kws}
		totalKw += len(kws)
		for _, pid := range brandToProducts[r.ID] {
			result[pid] = info
		}
	}
	if totalKw > 0 {
		s.logger.Infof("SmartSale: loaded %d meta_keywords across %d master brands", totalKw, len(rows))
	}
	return result
}

// findMatchingProducts returns top candidates sorted by score (best first)
// Uses the unified matching engine from /pkg/shared/matching/
// shopStockMap is optional — pass nil to disable stock-aware matching.
//
// v1.0.160 — legacy caller compatibility shim. Defaults shopID to uuid.Nil
// (= tenant-wide alias lookup), preserving pre-shop-scope behaviour.
func (s *SmartSaleService) findMatchingProducts(products []models.Product, brandName, size, category string, ocrRate float64, tenantID uuid.UUID, shopStockMap ...map[string]int) []saleProductMatch {
	return s.findMatchingProductsWithStock(products, brandName, "", size, category, ocrRate, 0, tenantID, uuid.Nil, nil, shopStockMap...)
}

// loadShopRecentSaleFrequency returns a per-product count of distinct days
// the product was sold (qty>0) at this shop within the last `windowDays`.
// Used by Track A5 to rank setup_rescue candidates so the cap (top-N) goes
// to the products most likely to actually be sold today, not arbitrary
// alphabetical or insertion order. Returns empty map on error.
//
// v1.0.184 Track A5.
func (s *SmartSaleService) loadShopRecentSaleFrequency(tenantID, shopID uuid.UUID, windowDays int) map[string]int {
	out := make(map[string]int)
	if shopID == uuid.Nil || tenantID == uuid.Nil {
		return out
	}
	if windowDays <= 0 {
		windowDays = 30
	}
	type row struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		DayCount  int       `gorm:"column:day_count"`
	}
	var rows []row
	err := s.db.Raw(`
		SELECT dsi.product_id AS product_id,
		       COUNT(DISTINCT dsr.record_date) AS day_count
		  FROM daily_sales_items dsi
		  JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		 WHERE dsr.tenant_id = ?
		   AND dsr.shop_id  = ?
		   AND dsi.tenant_id = ?
		   AND dsr.status = 'approved'
		   AND dsr.deleted_at IS NULL
		   AND dsi.deleted_at IS NULL
		   AND dsr.record_date >= NOW() - (? || ' days')::interval
		   AND dsi.quantity > 0
		 GROUP BY dsi.product_id
	`, tenantID, shopID, tenantID, windowDays).Scan(&rows).Error
	if err != nil {
		s.logger.Warnf("SmartSale: loadShopRecentSaleFrequency failed: %v", err)
		return out
	}
	for _, r := range rows {
		out[r.ProductID.String()] = r.DayCount
	}
	return out
}

// loadShopRecentSaleQty returns a per-product "last sale qty within the last
// `windowDays` at this shop" map. Used by the setup-rescue branch to seed
// rescued rows with a sensible default qty rather than 0 (chhotu's burden:
// 23 rescue rows on May 4 all needed manual qty entry). The label is shown
// in Flutter as "rescued — last sale was N" so the operator can confirm
// with one tap. Tenant-scoped, shop-scoped — no cross-shop leakage.
//
// v1.0.163.
func (s *SmartSaleService) loadShopRecentSaleQty(tenantID, shopID uuid.UUID, windowDays int) map[string]int {
	out := make(map[string]int)
	if shopID == uuid.Nil || tenantID == uuid.Nil {
		return out
	}
	if windowDays <= 0 {
		windowDays = 7
	}
	type row struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		LastQty   int       `gorm:"column:last_qty"`
	}
	var rows []row
	// Pull the qty from the MOST-RECENT approved sale per product at this
	// (tenant, shop). Use DISTINCT ON to grab the freshest row only.
	err := s.db.Raw(`
		SELECT DISTINCT ON (dsi.product_id) dsi.product_id AS product_id,
		       dsi.quantity AS last_qty
		  FROM daily_sales_items dsi
		  JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		 WHERE dsr.tenant_id = ?
		   AND dsr.shop_id  = ?
		   AND dsi.tenant_id = ?
		   AND dsr.status = 'approved'
		   AND dsr.deleted_at IS NULL
		   AND dsi.deleted_at IS NULL
		   AND dsr.record_date >= NOW() - (? || ' days')::interval
		   AND dsi.quantity > 0
		 ORDER BY dsi.product_id, dsr.record_date DESC, dsr.created_at DESC
	`, tenantID, shopID, tenantID, windowDays).Scan(&rows).Error
	if err != nil {
		s.logger.Warnf("SmartSale: loadShopRecentSaleQty failed: %v", err)
		return out
	}
	for _, r := range rows {
		if r.LastQty > 0 {
			out[r.ProductID.String()] = r.LastQty
		}
	}
	return out
}

// loadShopLastSoldDays returns a per-product "days since last sale at this
// shop" map for shop-inventory bias. Window is in days (callers usually pass
// 60, slightly larger than the 30-day matcher cutoff so future tunes don't
// need a re-query). Products absent from the result have never been sold at
// this shop within the window (matcher treats those as "never sold here").
//
// Tenant-scoped, shop-scoped — no cross-shop leakage.
func (s *SmartSaleService) loadShopLastSoldDays(tenantID, shopID uuid.UUID, windowDays int) map[string]int {
	out := make(map[string]int)
	if shopID == uuid.Nil || tenantID == uuid.Nil {
		return out
	}
	if windowDays <= 0 {
		windowDays = 60
	}
	type row struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		DaysAgo   int       `gorm:"column:days_ago"`
	}
	var rows []row
	// Pull the most-recent approved daily_sales_records.record_date per product
	// for this (tenant, shop) within the window. We restrict on tenant_id +
	// shop_id on both sides of the join to keep multi-tenant isolation.
	err := s.db.Raw(`
		SELECT dsi.product_id AS product_id,
		       FLOOR(EXTRACT(EPOCH FROM (NOW() - MAX(dsr.record_date))) / 86400.0)::int AS days_ago
		  FROM daily_sales_items dsi
		  JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		 WHERE dsr.tenant_id = ?
		   AND dsr.shop_id  = ?
		   AND dsi.tenant_id = ?
		   AND dsr.record_date >= NOW() - (? || ' days')::interval
		   AND dsi.quantity > 0
		 GROUP BY dsi.product_id
	`, tenantID, shopID, tenantID, windowDays).Scan(&rows).Error
	if err != nil {
		s.logger.Warnf("SmartSale: loadShopLastSoldDays failed: %v", err)
		return out
	}
	for _, r := range rows {
		if r.DaysAgo < 0 {
			r.DaysAgo = 0
		}
		out[r.ProductID.String()] = r.DaysAgo
	}
	return out
}

// shopBiasFloorForTenant returns the SMART_SALE_MATCH_FLOOR threshold for
// the given tenant. Order: SMART_SALE_MATCH_FLOOR_TENANT_<id> > SMART_SALE_MATCH_FLOOR
// > the existing default (config.MinThreshold). Never lowers below the default.
func shopBiasFloorForTenant(tenantID uuid.UUID, defaultFloor float64) float64 {
	floor := defaultFloor
	if v := os.Getenv("SMART_SALE_MATCH_FLOOR"); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil && parsed > floor {
			floor = parsed
		}
	}
	if tenantID != uuid.Nil {
		key := "SMART_SALE_MATCH_FLOOR_TENANT_" + tenantID.String()
		if v := os.Getenv(key); v != "" {
			if parsed, err := strconv.ParseFloat(v, 64); err == nil && parsed > floor {
				floor = parsed
			}
		}
	}
	return floor
}

// shopInventoryBiasEnabled reads the SMART_SALE_SHOP_INVENTORY_BIAS feature
// flag. Default ON ("1"). Set "0" / "false" to disable.
func shopInventoryBiasEnabled() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv("SMART_SALE_SHOP_INVENTORY_BIAS")))
	if v == "" {
		return true
	}
	return v != "0" && v != "false" && v != "off" && v != "no"
}

// findMatchingProductsWithStock returns top candidates with stock-aware matching.
// exciseMap (may be nil) carries authoritative master-catalog names per product — when
// present, matching.Product gets ExciseBrandName + ExciseDisplayName populated so the
// matcher can score OCR text against official excise names, not just the tenant's
// local product.Name. This closes a big accuracy gap: tenant names are often misspelled
// or abbreviated, but the master-catalog name matches the UP Excise register exactly.
//
// v1.0.133-r7 — ocrText (raw register handwriting) is now first in alias-lookup
// order, then brandName falls back. Aliases are written keyed on ocr_text in
// captureApplyLearning, so looking them up by brandName (the matcher's post-fuzzy
// guess) misses the captured corpus. Real example: alias `very cranberry vodka
// → MOOOZ CRANBERRY VODKA` (occ 36) never fired because by the time we lookup
// the AI had already overwritten brandName to "Canvas Cranberry Vodka". Now the
// raw OCR text "Very Cranberry Vodka" is tried first → alias hit.
// v1.0.160 — added shopID so the alias cascade (shop → tenant → fuzzy) can
// route per-shop OCR aliases without leaking across shops at the same tenant.
// Pass uuid.Nil when the shop is not in scope; cascade then degrades to the
// pre-shop-scope tenant-wide behaviour.
func (s *SmartSaleService) findMatchingProductsWithStock(products []models.Product, brandName, ocrText, size, category string, ocrRate float64, ocrOpeningStock int, tenantID, shopID uuid.UUID, exciseMap map[string]exciseInfo, optionalMaps ...map[string]int) []saleProductMatch {
	sizeNorm := matching.NormalizeSize(strings.ToLower(strings.TrimSpace(size)))

	// Variadic positional arg unpacking:
	//   optionalMaps[0] = shopStockMap (productID → current quantity)
	//   optionalMaps[1] = shopLastSoldDaysMap (productID → days since last sale)
	// Both optional. nil slots are tolerated.
	var shopStockMapArg map[string]int
	var shopLastSoldDaysArg map[string]int
	if len(optionalMaps) > 0 {
		shopStockMapArg = optionalMaps[0]
	}
	if len(optionalMaps) > 1 {
		shopLastSoldDaysArg = optionalMaps[1]
	}

	// Fast path: check alias table for instant match (with negative alias awareness).
	// v1.0.124 — pollution guard: an alias instantly returning score 1.0 is a
	// HUGE blast radius if the alias is wrong (e.g. polluted entry like
	// "100 strokes royal" → "Royal Challenge Select Premium" found in prod
	// 2026-04-30). Apply a sanity check: when the OCR text and the matched
	// product name share NO distinctive token (length ≥ 4), refuse the alias
	// and fall through to fuzzy matching. Real user_correction aliases will
	// virtually always share at least one token (or the user fat-fingered).
	//
	// v1.0.133-r7 — try raw OCR text first, then brandName. Same pollution
	// guard applies to both lookups.
	if s.aliasService != nil {
		// Build a list of lookup keys in priority order — raw OCR first, then
		// post-match brandName as legacy fallback. De-duplicate when they're
		// identical (e.g. picker-swap rows where ocrText was never set).
		lookupKeys := []string{}
		ocrTrim := strings.TrimSpace(ocrText)
		if ocrTrim != "" {
			lookupKeys = append(lookupKeys, ocrTrim)
		}
		brandTrim := strings.TrimSpace(brandName)
		if brandTrim != "" && !strings.EqualFold(brandTrim, ocrTrim) {
			lookupKeys = append(lookupKeys, brandTrim)
		}
		var allRejectedIDs []uuid.UUID
		for _, key := range lookupKeys {
			// v1.0.160 — use the scoped lookup so shop-specific aliases are
			// preferred over tenant-wide ones; falls through to tenant on miss.
			// Negative-alias gating still applies at both scopes.
			//
			// v1.0.168 — also fetch the AliasSource so we can skip the
			// pollution-guard for EXACT alias matches. Exact hits were
			// either operator-confirmed (LearnAliasScoped from a manual
			// correction) or backfilled from approved history — both are
			// trustworthy by construction. The pollution guard exists to
			// catch fuzzy alias accidents; exact matches don't need it,
			// and rejecting them was blocking the M.M / VOV / OC class
			// of short-key aliases on chhotu's tenant.
			productID, _, aliasSrc, found, rejectedIDs := s.aliasService.LookupAliasWithNegativesScopedSource(context.Background(), tenantID, shopID, key)
			allRejectedIDs = append(allRejectedIDs, rejectedIDs...)
			if !found || productID == nil {
				continue
			}
			for i := range products {
				if products[i].ID != *productID {
					continue
				}
				productSize := matching.NormalizeSize(strings.ToLower(products[i].Size))
				if sizeNorm != "" && productSize != "" && sizeNorm != productSize {
					continue
				}
				exactSource := aliasSrc == alias.AliasSourceShopExact || aliasSrc == alias.AliasSourceTenantExact
				// v1.0.241 — packaging-token conflict guard. Applies BEFORE the
				// exact-source bypass because operator-confirmed aliases can still
				// be wrong: chhotu's FM Tower shop had "8 pm gold scotch whisky pet"
				// → a Tetra product pinned by user_correction, hit 13 times, every
				// preview silently routed PET rows to the Tetra duplicate. Two
				// products that differ only by packaging form (PET vs Tetra, etc.)
				// should never share an alias.
				if hasPackagingTokenConflict(key, products[i].Name) {
					if exactSource {
						// v1.0.241 — downgrade rather than block for exact-source.
						// The operator may have meant it (rare), so surface as
						// NeedsReview at Score 0.85 and let the review screen
						// force a re-confirmation. Preserves prior intent without
						// silently corrupting future previews.
						s.logger.Warnf("SmartSale: ALIAS PACKAGING-CONFLICT (exact-source) '%s' -> '%s' — source=%s, returning NeedsReview at 0.85",
							key, products[i].Name, aliasSrc)
						return []saleProductMatch{{Product: &products[i], Score: 0.85, PriceMatch: false, NeedsReview: true}}
					}
					s.logger.Warnf("SmartSale: ALIAS REJECTED (packaging-conflict) '%s' -> '%s' — source=%s, trying next key/falling through",
						key, products[i].Name, aliasSrc)
					continue
				}
				if exactSource || hasSharedDistinctiveToken(key, products[i].Name) {
					s.logger.Infof("SmartSale: ALIAS HIT '%s' -> '%s' (key=%s, source=%s, instant match)", key, products[i].Name, key, aliasSrc)
					return []saleProductMatch{{Product: &products[i], Score: 1.0, PriceMatch: true}}
				}
				s.logger.Warnf("SmartSale: ALIAS REJECTED (pollution guard) '%s' -> '%s' — no shared distinctive token, source=%s, trying next key/falling through",
					key, products[i].Name, aliasSrc)
			}
		}
		// Build rejected ID map for the matcher (combined from both lookups).
		_ = allRejectedIDs

		// v1.0.160 — very-short OCR strings ("MM", "OC", "VOV", "BD") have
		// no business going through fuzzy: jaccard / token overlap on a 2-3
		// char query inevitably picks an unrelated product. The alias table
		// (shop→tenant→global; only tenant-scoped today, but the cascade
		// shape is preserved by LookupAliasWithNegatives) has already been
		// consulted above. If it missed, return empty matches so the row
		// falls to not_found / needs_review rather than a confident-but-
		// wrong fuzzy guess.
		shortKey := ""
		if ocrTrim != "" {
			shortKey = ocrTrim
		} else if brandTrim != "" {
			shortKey = brandTrim
		}
		if shortRuneCount := len([]rune(shortKey)); shortRuneCount > 0 && shortRuneCount <= 4 {
			s.logger.Infof("SmartSale: SHORT-OCR (≤4 chars) alias miss for '%s' — skipping fuzzy fallback (forcing not_found)", shortKey)
			return nil
		}
	}

	// Build stock map from variadic arg
	stockMap := shopStockMapArg
	lastSoldMap := shopLastSoldDaysArg

	// Convert products to shared matching format (with stock data for stock-aware matching)
	matchProducts := make([]matching.Product, len(products))
	productMap := make(map[string]*models.Product, len(products))
	for i := range products {
		p := &products[i]
		brandName := p.Name
		if p.Brand != nil {
			brandName = p.Brand.Name
		}
		currentStock := 0
		if stockMap != nil {
			currentStock = stockMap[p.ID.String()]
		}
		// LastSoldDaysAgo defaults to -1 (= "never sold here / unknown") so the
		// matcher treats absence-from-map as a soft penalty, not a recent sale.
		lastSoldDays := -1
		if lastSoldMap != nil {
			if v, ok := lastSoldMap[p.ID.String()]; ok {
				lastSoldDays = v
			}
		}
		mp := matching.Product{
			ID:              p.ID.String(),
			Name:            p.Name,
			BrandName:       brandName,
			DisplayName:     p.DisplayName,
			Size:            p.Size,
			SizeML:          matching.ParseSizeML(p.Size),
			SellingPrice:    p.SellingPrice,
			CurrentStock:    currentStock,
			LastSoldDaysAgo: lastSoldDays,
			IsActive:        p.IsActive,
			CreatedAt:       p.CreatedAt,
		}
		if exciseMap != nil {
			if ei, ok := exciseMap[p.ID.String()]; ok {
				mp.ExciseBrandName = ei.BrandName
				mp.ExciseDisplayName = ei.DisplayName
			}
		}
		matchProducts[i] = mp
		productMap[p.ID.String()] = p
	}

	// Prepare products (precompute normalized names) and run matcher
	prepared := matching.PrepareProducts(matchProducts)
	config := matching.DefaultSaleConfig()
	ocrSizeML := matching.ParseSizeML(size)

	// If no stock map provided, disable stock filtering (backward compat for non-sale callers)
	if stockMap == nil {
		config.FilterZeroStock = false
		config.EnableStockMatching = false
	}

	// v1.0.160 — shop-inventory bias is opt-in via env (default ON).
	// Bias is a no-op when stockMap is nil (e.g. caller didn't have a shop) so
	// non-sale callers and tenant-scoped suggestion paths are unaffected.
	if shopInventoryBiasEnabled() && stockMap != nil {
		config.ShopInventoryBias = true
	}
	// Tenant-tunable match floor (never lowered below the default).
	config.MinThreshold = shopBiasFloorForTenant(tenantID, config.MinThreshold)

	results := matching.MatchProductsWithStock(brandName, ocrSizeML, ocrRate, ocrOpeningStock, prepared, config)

	// Convert back to saleProductMatch, with distinguisher guard
	// Reject matches where key distinguishing VARIANT words differ (prevents "Green Label" → "8 PM Rare")
	// Only applies to variant-level words that distinguish products within the same brand family.
	variantDistinguishers := []string{"green apple", "orange", "cranberry", "jamun", "lemon", "limon",
		"mango", "coffee", "spiced", "gold", "black", "blue", "barrel select", "double dark",
		"reserve collection", "legend", "matured", "premium black", "triple gold", "green label",
		"double black", "red label", "gold label", "royal green", "white"}
	brandLower := strings.ToLower(strings.TrimSpace(brandName))

	var candidates []saleProductMatch
	for _, r := range results {
		if p, ok := productMap[r.ProductID]; ok {
			// Guard: reject matches where variant distinguishing words differ.
			// Skip guard if the OCR text is contained in the product name or vice versa
			// (handles "Blenders Pride Blue Whisky" matching "Blenders Pride Blue Whisky - 750ML").
			matchedLower := strings.ToLower(p.Name)
			// Skip guard if one contains the other (near-exact match)
			skipGuard := strings.Contains(matchedLower, brandLower) || strings.Contains(brandLower, matchedLower)
			if !skipGuard {
				mismatch := false
				for _, d := range variantDistinguishers {
					inBrand := strings.Contains(brandLower, d)
					inMatched := strings.Contains(matchedLower, d)
					if inBrand != inMatched {
						mismatch = true
						break
					}
				}
				if mismatch {
					s.logger.Warnf("SmartSale: REJECTED match '%s' → '%s' (score=%.2f, variant word mismatch)", brandName, p.Name, r.Score)
					continue
				}
			}
			// Packaging-family guard for the FUZZY path (mirrors the alias-path
			// guard, v1.0.241). "8 PM Gold Scotch Whisky PET" must never bind to a
			// "...Tetra" product just because the shared brand prefix dominates the
			// fuzzy score — the catalog had no PET SKU, so the PET register row
			// silently grabbed the ₹130 Tetra and carried the wrong opening.
			// (Regression source: FM Tower record 2bc7c3c0.) Check raw OCR first,
			// then the post-match brandName.
			pkgKey := strings.TrimSpace(ocrText)
			if pkgKey == "" {
				pkgKey = strings.TrimSpace(brandName)
			}
			if pkgKey != "" && hasPackagingTokenConflict(pkgKey, p.Name) {
				s.logger.Warnf("SmartSale: REJECTED match '%s' → '%s' (score=%.2f, packaging-family conflict)", pkgKey, p.Name, r.Score)
				continue
			}
			candidates = append(candidates, saleProductMatch{
				Product:     p,
				Score:       r.Score,
				PriceMatch:  r.PriceMatch,
				NeedsReview: r.NeedsReview,
			})
		}
	}

	if len(candidates) > 0 {
		s.logger.Infof("SmartSale: MATCHED '%s %s' -> '%s' (score: %.2f, price_match: %v, candidates: %d)",
			brandName, size, candidates[0].Product.Name, candidates[0].Score, candidates[0].PriceMatch, len(candidates))
	} else {
		s.logger.Warnf("SmartSale: NO MATCH for '%s %s' (all scores < 0.40 or distinguisher mismatch)", brandName, size)
	}

	return candidates
}

// findMatchingProduct is a convenience wrapper returning the best match (backward compat)
func (s *SmartSaleService) findMatchingProduct(products []models.Product, brandName, size, category string, tenantID uuid.UUID) *models.Product {
	matches := s.findMatchingProducts(products, brandName, size, category, 0, tenantID)
	if len(matches) > 0 {
		return matches[0].Product
	}
	return nil
}

// stockSetupRef captures one row from the most-recent approved stock_setup_record
// at (shop, size). Used by Smart Sale as a ground-truth lookup table.
type stockSetupRef struct {
	ProductID   uuid.UUID
	ProductName string
	OpeningQty  int
	Rate        float64
}

// loadLatestApprovedStockSetupMap returns the latest approved stock_setup_record
// for (shop, size) as two lookup maps:
//   - byRate:  rate (rounded int) → []stockSetupRef
//   - byName:  lower-cased product.name → stockSetupRef
//
// v1.0.116 ground-truth integration: Smart Sale matches first against this table
// before the fuzzy scorer. When AI extracts a row whose brand text fails fuzzy
// matching but whose rate exactly matches a setup row, we route to that
// product. Concretely fixes job 016a1e0b row 22 (brand=\"raw_text\" rate=940 →
// Master Blenders Signature ₹940). Stock setup is the highest-confidence
// reference because the user just visually approved it 5 minutes ago.
// loadShopLearnedRates returns shop_product_rates keyed by product_id.
// v1.0.125 — Smart Sale parity with smart_stock_setup_service.go counterpart.
// Used by validateAndMatchItems to override SellingPrice when a row matches
// a product the user has corrected at this shop before.
func (s *SmartSaleService) loadShopLearnedRates(tenantID, shopID uuid.UUID) map[string]float64 {
	out := make(map[string]float64)
	if shopID == uuid.Nil || tenantID == uuid.Nil {
		return out
	}
	type row struct {
		ProductID    uuid.UUID `gorm:"column:product_id"`
		LastUserRate float64   `gorm:"column:last_user_rate"`
	}
	var rows []row
	if err := s.db.Raw(
		`SELECT product_id, last_user_rate
		   FROM shop_product_rates
		  WHERE tenant_id = ? AND shop_id = ?`,
		tenantID, shopID,
	).Scan(&rows).Error; err != nil {
		s.logger.Warnf("SmartSale: loadShopLearnedRates failed: %v", err)
		return out
	}
	for _, r := range rows {
		if r.LastUserRate > 0 {
			out[r.ProductID.String()] = r.LastUserRate
		}
	}
	if len(out) > 0 {
		s.logger.Infof("SmartSale: Preloaded %d shop_product_rates for shop %s", len(out), shopID)
	}
	return out
}

func (s *SmartSaleService) loadLatestApprovedStockSetupMap(shopID uuid.UUID, sizeML int, tenantID uuid.UUID) (byRate map[int][]stockSetupRef, byName map[string]stockSetupRef) {
	byRate = map[int][]stockSetupRef{}
	byName = map[string]stockSetupRef{}
	if shopID == uuid.Nil {
		return
	}
	type row struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		Name      string    `gorm:"column:name"`
		Quantity  int       `gorm:"column:quantity"`
		Rate      float64   `gorm:"column:rate"`
		Size      string    `gorm:"column:size"`
	}
	var rows []row
	q := s.db.
		Table("stock_setup_items AS ssi").
		Select("ssi.product_id, p.name, ssi.quantity, ssi.rate, p.size").
		Joins("JOIN stock_setup_records AS ssr ON ssr.id = ssi.stock_setup_record_id").
		Joins("JOIN products AS p ON p.id = ssi.product_id").
		Where("ssr.shop_id = ? AND ssr.status = ? AND ssr.tenant_id = ?", shopID, "approved", tenantID).
		Where("ssr.id IN (?)", s.db.
			Table("stock_setup_records").
			Select("id").
			Where("shop_id = ? AND status = ? AND tenant_id = ?", shopID, "approved", tenantID).
			Order("approved_at DESC").
			Limit(3))
	if err := q.Scan(&rows).Error; err != nil {
		s.logger.Warnf("SmartSale: failed to load stock setup map: %v", err)
		return
	}
	for _, r := range rows {
		// Optional size scoping: when sale is for a specific size, only include setup rows
		// at that size. Stock setups are usually scoped to one size each, so most setups
		// are already homogeneous, but a defensive filter keeps the map clean for
		// multi-size scenarios.
		if sizeML > 0 {
			rowSizeML := matching.ParseSizeML(r.Size)
			if rowSizeML > 0 && rowSizeML != sizeML {
				continue
			}
		}
		ref := stockSetupRef{ProductID: r.ProductID, ProductName: r.Name, OpeningQty: r.Quantity, Rate: r.Rate}
		rateKey := int(r.Rate + 0.5)
		byRate[rateKey] = append(byRate[rateKey], ref)
		byName[strings.ToLower(strings.TrimSpace(r.Name))] = ref
	}
	s.logger.Infof("SmartSale: stock-setup ground-truth loaded — %d rows by rate, %d unique names (shop=%s, sizeML=%d)",
		len(byRate), len(byName), shopID, sizeML)
	return
}

// findMostRecentApprovedStockSetupQty returns the quantity from the most-recent
// approved stock_setup record for (product, shop) approved STRICTLY before the sale's
// start-of-day. A setup approved AFTER the sale represents a later physical count
// and would underflow the opening — the sale's items have already been deducted by
// the time that setup was taken (closing-of-sale = stock_setup).
func (s *SmartSaleService) findMostRecentApprovedStockSetupQty(productID, shopID uuid.UUID, saleDate time.Time) (int, bool) {
	var qty int
	// saleDate is the record date; strip to start-of-day so a setup approved
	// earlier the same day (before the shopkeeper opened) still wins, but a
	// setup approved on a LATER calendar day does not.
	dayStart := time.Date(saleDate.Year(), saleDate.Month(), saleDate.Day(), 0, 0, 0, 0, saleDate.Location())
	err := s.db.
		Table("stock_setup_items AS ssi").
		Select("ssi.quantity").
		Joins("JOIN stock_setup_records AS ssr ON ssr.id = ssi.stock_setup_record_id").
		Where("ssi.product_id = ? AND ssr.shop_id = ? AND ssr.status = ? AND ssr.approved_at < ?",
			productID, shopID, "approved", dayStart).
		Order("ssr.approved_at DESC").
		Limit(1).
		Scan(&qty).Error
	if err != nil || qty == 0 {
		return 0, false
	}
	return qty, true
}

// createDailySalesEntries creates daily sales from validated items
func (s *SmartSaleService) createDailySalesEntries(
	ctx context.Context,
	req *SmartSaleRequest,
	items []SmartSaleExtractedItem,
	userID, tenantID uuid.UUID,
	userRole string,
) (string, error) {

	// Include ALL items that have a matched product.
	// Unmatched items are logged but NOT dropped — they remain in the response
	// for the Flutter UI to display (user can manually assign products).
	// Collapse duplicates by product_id so AI re-extracting the same row doesn't
	// produce duplicate DailySalesItem rows on the same record (Bug #11 source).
	var validItems []SmartSaleExtractedItem
	var unmatchedCount int
	seen := make(map[string]int)
	aliasMergePct := smartSaleAliasConflictRatePct()
	for _, item := range items {
		if item.ProductID != nil {
			if existingIdx, ok := seen[*item.ProductID]; ok {
				// v1.0.327 — belt-and-braces. Loud-log when two rows merging
				// here have rate divergence > threshold. The ValidateNoAliasConflicts
				// gate at the handler entrypoint should reject these before they
				// reach createDailySalesEntries; if we observe a divergent merge
				// here, either the gate was bypassed (SMART_SALE_ALIAS_CONFLICT_GUARD=0)
				// or this code path was reached from a non-gated caller. Either
				// way the operator deserves the log trail for forensic audit.
				existing := validItems[existingIdx]
				if existing.Rate > 0 && item.Rate > 0 {
					denom := existing.Rate
					if item.Rate > denom {
						denom = item.Rate
					}
					diff := existing.Rate - item.Rate
					if diff < 0 {
						diff = -diff
					}
					if diff/denom*100.0 > aliasMergePct {
						s.logger.Warnf(
							"SmartSale: ALIAS_CONFLICT_SILENT_MERGE product_id=%s name=%q existing_row(qty=%d,rate=%.2f) merging_row(qty=%d,rate=%.2f) — silently summed; v1.0.327 apply-gate may be disabled",
							*item.ProductID, item.BrandName,
							existing.Quantity, existing.Rate, item.Quantity, item.Rate)
					}
				} else {
					s.logger.Warnf(
						"SmartSale: ALIAS_CONFLICT_SILENT_MERGE_NORATE product_id=%s name=%q existing_row(qty=%d,rate=%.2f) merging_row(qty=%d,rate=%.2f) — at least one rate unknown",
						*item.ProductID, item.BrandName,
						existing.Quantity, existing.Rate, item.Quantity, item.Rate)
				}
				validItems[existingIdx].Quantity += item.Quantity
				validItems[existingIdx].Amount += item.Amount
				continue
			}
			seen[*item.ProductID] = len(validItems)
			validItems = append(validItems, item)
		} else {
			unmatchedCount++
			s.logger.Warnf("SmartSale: Unmatched item '%s' (qty: %d, rate: %.2f) — included in response for user review",
				item.BrandName, item.Quantity, item.Rate)
		}
	}

	if len(validItems) == 0 {
		return "", errors.New("no matched items to create sale")
	}

	if unmatchedCount > 0 {
		s.logger.Infof("SmartSale: %d items unmatched (in response for review), %d items will be saved", unmatchedCount, len(validItems))
	}

	// Determine auto-approval based on user role
	autoApprove := userRole == models.RoleAdmin ||
		userRole == models.RoleManager ||
		userRole == models.RoleAssistantManager

	initialStatus := models.StatusPending
	if autoApprove {
		initialStatus = models.StatusApproved
	}

	// v1.0.133-r6 — sum total using the same MRP-priority rule we apply
	// at insert (user MRP > Rate > 0). Pre-r6 summed `item.Amount` from
	// the payload which could mix old AI rate with edited MRP per row,
	// so record.TotalSalesAmount drifted from items_sum (Tushar record
	// 4e3675cf was 25500-vs-25550 with mixed edits). Now total is exactly
	// sum(unitPrice * qty) using the same unitPrice we'll write per item.
	var totalAmount float64
	for _, item := range validItems {
		rate := item.Rate
		if item.MRP > 0 {
			rate = item.MRP
		}
		totalAmount += rate * float64(item.Quantity)
	}

	// v1.0.203 — short-window dedup guard. The (shop_id, record_date,
	// salesman_id) unique index doesn't fire for Smart Sale because
	// salesman_id is NULL, and SQL treats NULL ≠ NULL. Without this
	// guard a double-tap on Submit creates two records (Trinken d714d53a
	// case: 2.45s after a0ab45c7 with near-identical items, second one
	// got 0 receipt_images because Redis cache was already evicted).
	//
	// Strategy: if a record exists for the same shop/date with the same
	// notes-tag ("Created via Smart Sale AI") created within the last
	// 60 seconds AND total_sales_amount within ±2% of this submit's
	// total, treat it as a duplicate and return its ID instead of
	// inserting again. Idempotency is the right long-term fix; this is
	// the defense-in-depth net for clients that don't (yet) send a key.
	if req.IdempotencyKey == "" {
		var existing models.DailySalesRecord
		dupErr := s.db.Where(
			"tenant_id = ? AND shop_id = ? AND record_date = ? AND notes = ? AND created_at >= ? AND deleted_at IS NULL",
			tenantID, req.ShopID, req.SaleDate, "Created via Smart Sale AI",
			time.Now().Add(-60*time.Second),
		).
			Order("created_at DESC").
			First(&existing).Error
		if dupErr == nil {
			tol := totalAmount * 0.02
			if tol < 1 {
				tol = 1
			}
			if math.Abs(existing.TotalSalesAmount-totalAmount) <= tol {
				s.logger.Warnf("SmartSale: dedup guard caught double-submit — returning existing record %s (created %.1fs ago, total ₹%.2f vs new ₹%.2f) for shop=%s date=%s",
					existing.ID, time.Since(existing.CreatedAt).Seconds(),
					existing.TotalSalesAmount, totalAmount,
					req.ShopID, req.SaleDate.Format("2006-01-02"))
				return existing.ID.String(), nil
			}
		}
	}

	// Start transaction
	var recordID uuid.UUID
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Payment breakdown: use provided values or default all to cash
		cashAmt := req.CashAmount
		upiAmt := req.UpiAmount
		cardAmt := req.CardAmount
		creditAmt := req.CreditAmount
		paymentProvided := (cashAmt + upiAmt + cardAmt + creditAmt) > 0
		if !paymentProvided {
			cashAmt = totalAmount // Default all to cash when no breakdown provided
		}

		// Create daily sales record
		record := &models.DailySalesRecord{
			TenantModel:       models.TenantModel{TenantID: &tenantID},
			RecordDate:        req.SaleDate,
			ShopID:            req.ShopID,
			TotalSalesAmount:  totalAmount,
			TotalCashAmount:   cashAmt,
			TotalUpiAmount:    upiAmt,
			TotalCardAmount:   cardAmt,
			TotalCreditAmount: creditAmt,
			Status:            initialStatus,
			CreatedByID:       userID,
			Notes:             "Created via Smart Sale AI",
			ReceiptImages:     models.JSONStringList(req.SavedImageURLs),
		}
		// v1.0.124 — round-trip integrity. IdempotencyKey gets the existing
		// unique-index protection so a retry with the same key fails at DB
		// level (no duplicate sale created). ClientPayloadHash persists the
		// exact bytes of the apply payload so the client can verify on
		// summary fetch that the saved data matches what was submitted.
		if req.IdempotencyKey != "" {
			ik := req.IdempotencyKey
			record.IdempotencyKey = &ik
		}
		if req.ClientPayloadHash != "" {
			ph := req.ClientPayloadHash
			record.ClientPayloadHash = &ph
		}

		if autoApprove {
			now := time.Now()
			record.ApprovedAt = &now
			record.ApprovedByID = &userID
		}

		if err := tx.Create(record).Error; err != nil {
			return fmt.Errorf("failed to create daily sales record: %w", err)
		}
		recordID = record.ID

		// Create items, update stock, and track alerts
		alertCount := 0
		for idx, item := range validItems {
			productID, err := uuid.Parse(*item.ProductID)
			if err != nil {
				continue
			}

			// Get product for price info
			var product models.Product
			if err := tx.Where("id = ?", productID).First(&product).Error; err != nil {
				s.logger.Warnf("SmartSale: Product not found: %s", *item.ProductID)
				continue
			}

			// v1.0.133-r6 — respect user-edited MRP. Pre-r6 the apply path
			// always used product.SellingPrice and dropped item.MRP / item.Rate
			// silently — Tushar's "Rockford 530 saved as 520" bug. Order of
			// preference: user-edited MRP > Rate from payload > product
			// inventory price > zero (which is filtered upstream). The user's
			// rate edit IS the audit-stamped MRP change and must win.
			unitPrice := product.SellingPrice
			if item.MRP > 0 {
				unitPrice = item.MRP
			} else if item.Rate > 0 {
				unitPrice = item.Rate
			} else if unitPrice <= 0 {
				unitPrice = item.Rate
			}

			// Create daily sales item (always saved with full quantity from register)
			totalAmount := unitPrice * float64(item.Quantity)
			saleItem := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: record.ID,
				ProductID:          productID,
				Quantity:           item.Quantity,
				QuantitySold:       item.Quantity, // Mirror so analytics/reports that read quantity_sold work correctly
				UnitPrice:          unitPrice,
				TotalAmount:        totalAmount,
				CashAmount:         totalAmount, // Default to cash — overridden below if payment breakdown provided
				// v1.0.124: row provenance for admin audit chip + diagnostic
				// queries. Empty string is fine — column is nullable.
				Source: item.Source,
				// v1.0.133-r6 — persist AI-extracted register values for audit
				// trail. Pre-r6 these columns existed in the table but the
				// struct never declared them so GORM wrote 0s. Now every saved
				// row carries what the AI saw at extraction time so post-mortem
				// queries can answer "did the user edit, or did AI guess
				// right?" without re-running OCR.
				OcrBrandName: item.BrandName,
				OcrTotal: func() int {
					if item.OriginalAIQuantity != nil {
						return *item.OriginalAIQuantity
					}
					return item.Quantity
				}(),
				OcrRate: func() float64 {
					if item.OriginalAIRate != nil {
						return *item.OriginalAIRate
					}
					return item.Rate
				}(),
				OcrReceipt: func() int {
					if item.OriginalAIReceipt != nil {
						return *item.OriginalAIReceipt
					}
					return 0
				}(),
				DBStockSnap: func() int {
					if item.OriginalAIOpening != nil {
						return *item.OriginalAIOpening
					}
					return 0
				}(),
				// v1.0.149 — initial display order = page*1000 + row_number, so
				// rows render in IMAGE order (apple-to-apple with the source
				// register) before the operator drag-reorders. Manual-add /
				// setup-rescue rows fall back to (max+1) so they sort last
				// instead of jumping to the top with position=0.
				Position: func() int {
					if item.PageNumber > 0 && item.RowNumber > 0 {
						return item.PageNumber*1000 + item.RowNumber
					}
					return 999000 + idx // idx is the loop counter — falls past all natural rows
				}(),
			}
			// v1.0.124 Tier C: persist client_row_id (UUID) so a single sale
			// row can be traced from Flutter UI through apply payload to
			// daily_sales_items. Parsing is best-effort — empty / invalid
			// strings just leave the column NULL.
			if item.ClientRowID != "" {
				if rowUUID, parseErr := uuid.Parse(item.ClientRowID); parseErr == nil {
					rid := rowUUID.String()
					saleItem.ClientRowID = &rid
				}
			}

			// Snapshot stock and deduct if auto-approved
			var stock models.Stock
			stockErr := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				req.ShopID, productID, tenantID).First(&stock).Error

			if stockErr == nil {
				// v1.0.144 — opening = CURRENT stocks.quantity, period.
				// Prior code preferred a historical stock_setup snapshot
				// "to avoid drift" but that backfired badly: when the user
				// made a stock setup at T=0 (open=154), then real sales
				// dropped current stock to 83 by T=N, and then submitted a
				// new sale, opening was stamped as 154 (from setup) while
				// current stock was 83. User saw "opening 154" on a sale
				// for stock they only had 83 of — totally confusing and
				// math-wrong vs the inventory page.
				//
				// Mirrors daily_sales_service.go CreateDailySalesRecord
				// (which always uses stock.Quantity). The "drift" concern
				// the original code worried about is illusory — current
				// stocks IS the truth at sale time.
				saleItem.OpeningStock = stock.Quantity

				if autoApprove {
					// v1.0.216 — snapshot BEFORE the tx.Update mutates
					// stock.Quantity in-place. Pre-fix the PreviousQuantity
					// field below read stock.Quantity AFTER GORM bumped it,
					// producing prev==new on every smart-sale audit row
					// (same class as chhotu's May 4 corruption on the
					// daily-sale path; the smart-sale branch was missed by
					// the v1.0.162 patch).
					beforeQty := stock.Quantity
					sShopRef, sProdRef := stock.ShopID, stock.ProductID
					if beforeQty >= item.Quantity {
						// Normal deduction - sufficient stock
						newQuantity := beforeQty - item.Quantity
						// v1.0.143 — closing in the AUDIT FIELD must use the
						// SAME basis as opening (setup snapshot), not the live
						// stock.Quantity. Pre-fix: opening=setup(7), closing=
						// stock(9)-sold(2)=7 → opening==closing whenever current
						// stock happened to drift by exactly the sale qty. The
						// inventory mutation (`Update("quantity", newQuantity)`
						// below) still uses live stock — that's the canonical
						// inventory write — but the audit snapshot in
						// daily_sales_items.closing_stock must satisfy
						// opening_stock - quantity_sold = closing_stock so the
						// review/summary screens render coherent values.
						auditClose := saleItem.OpeningStock - item.Quantity
						if auditClose < 0 {
							auditClose = 0
						}
						saleItem.ClosingStock = auditClose
						if err := tx.Model(&stock).Update("quantity", newQuantity).Error; err != nil {
							s.logger.Warnf("SmartSale: Failed to update stock: %v", err)
						}

						stockHistory := models.StockHistory{
							TenantModel:      models.TenantModel{TenantID: &tenantID},
							StockID:          stock.ID,
							ShopID:           &sShopRef,
							ProductID:        &sProdRef,
							MovementType:     "smart_sale",
							Quantity:         -item.Quantity,
							PreviousQuantity: beforeQty,
							NewQuantity:      newQuantity,
							UnitCost:         unitPrice,
							TotalCost:        totalAmount,
							Reference:        fmt.Sprintf("Smart Sale - Record %s", record.ID),
							ReferenceID:      &record.ID,
							CreatedByID:      userID,
							Notes:            fmt.Sprintf("Smart Sale AI entry for %s", product.Name),
						}
						tx.Create(&stockHistory)
					} else {
						// Insufficient stock - deduct to zero and set alert.
						// v1.0.143 — same audit-vs-inventory split as above.
						// The audit closing keeps the opening-basis math even
						// when actual stock fell short.
						shortage := item.Quantity - beforeQty
						deducted := beforeQty
						auditClose := saleItem.OpeningStock - item.Quantity
						if auditClose < 0 {
							auditClose = 0
						}
						saleItem.ClosingStock = auditClose
						if deducted > 0 {
							if err := tx.Model(&stock).Update("quantity", 0).Error; err != nil {
								s.logger.Warnf("SmartSale: Failed to update stock: %v", err)
							}

							stockHistory := models.StockHistory{
								TenantModel:      models.TenantModel{TenantID: &tenantID},
								StockID:          stock.ID,
								ShopID:           &sShopRef,
								ProductID:        &sProdRef,
								MovementType:     "smart_sale",
								Quantity:         -deducted,
								PreviousQuantity: beforeQty,
								NewQuantity:      0,
								UnitCost:         unitPrice,
								TotalCost:        float64(deducted) * unitPrice,
								Reference:        fmt.Sprintf("Smart Sale - Record %s (partial)", record.ID),
								ReferenceID:      &record.ID,
								CreatedByID:      userID,
								Notes:            fmt.Sprintf("Smart Sale AI entry for %s (deducted %d of %d, shortage %d)", product.Name, deducted, item.Quantity, shortage),
							}
							tx.Create(&stockHistory)
						}

						saleItem.StockAlert = fmt.Sprintf("Insufficient stock: had %d, sold %d, shortage %d", deducted, item.Quantity, shortage)
						saleItem.StockAlertQty = shortage
						alertCount++
						s.logger.Warnf("SmartSale: Stock alert for %s - had %d, sold %d, shortage %d (deducted to zero)", product.Name, deducted, item.Quantity, shortage)
					}
				} else {
					// v1.0.133-r6 — closing must use the SAME basis as opening,
					// not live stock.Quantity. Pre-r6: opening = setup snapshot
					// (e.g. 11) while closing = stock.Quantity - sold (e.g. 12-1=11),
					// so closing == opening for any row where current stock had
					// drifted by exactly the sale qty. Tushar's 726621c2 record
					// showed Sterling 11/1/11, Indri 1/1/1 — every row had
					// closing == opening because of this base mismatch. Now
					// computed deterministically as OpeningStock - Quantity.
					saleItem.ClosingStock = saleItem.OpeningStock - item.Quantity
					if saleItem.ClosingStock < 0 {
						saleItem.ClosingStock = 0
					}
				}
			} else {
				// No stock record found
				saleItem.OpeningStock = 0
				saleItem.ClosingStock = 0
				if autoApprove {
					saleItem.StockAlert = fmt.Sprintf("No stock record found: sold %d units", item.Quantity)
					saleItem.StockAlertQty = item.Quantity
					alertCount++
					s.logger.Warnf("SmartSale: Stock alert for %s - no stock record found (sold %d)", product.Name, item.Quantity)
				}
			}

			if err := tx.Create(&saleItem).Error; err != nil {
				return fmt.Errorf("failed to create daily sales item: %w", err)
			}
		}

		// Update record with alert info if any items had stock issues
		if alertCount > 0 {
			if err := tx.Model(record).Updates(map[string]interface{}{
				"has_alerts":  true,
				"alert_count": alertCount,
			}).Error; err != nil {
				s.logger.Warnf("SmartSale: Failed to update alert fields on record: %v", err)
			}
			s.logger.Infof("SmartSale: Record %s flagged with %d stock alerts", record.ID, alertCount)
		}

		return nil
	})

	if err != nil {
		return "", err
	}

	return recordID.String(), nil
}

// Helper functions

func (s *SmartSaleService) getRate(item ExtractedReceiptItem) float64 {
	if item.RatePerUnit != nil && *item.RatePerUnit > 0 {
		return *item.RatePerUnit
	}
	if item.Price != nil && item.Quantity > 0 {
		return *item.Price / float64(item.Quantity)
	}
	return 0
}

func (s *SmartSaleService) getAmount(item ExtractedReceiptItem) float64 {
	if item.Price != nil && *item.Price > 0 {
		return *item.Price
	}
	if item.RatePerUnit != nil && item.Quantity > 0 {
		return *item.RatePerUnit * float64(item.Quantity)
	}
	return 0
}

func normalizeSize(size string) string {
	// Remove spaces and convert to lowercase
	size = strings.ToLower(strings.TrimSpace(size))
	// Extract just the number
	re := regexp.MustCompile(`[^0-9]`)
	return re.ReplaceAllString(size, "")
}

// hasSharedDistinctiveToken returns true when ocr text and candidate product
// name share at least one token of length >= 4 that isn't a generic filler
// word (whisky/rum/vodka/etc.). Used as a pollution guard on alias hits:
// real user-correction aliases virtually always share at least one
// distinctive token; an alias that doesn't is almost certainly bad data
// (e.g. "100 strokes royal" → "Royal Challenge Select Premium" — only
// "royal" is shared, but it's a generic word, so this returns false).
// v1.0.124.
func hasSharedDistinctiveToken(ocr, candidate string) bool {
	generics := map[string]bool{
		"whisky": true, "whiskey": true, "rum": true, "vodka": true, "gin": true,
		"brandy": true, "wine": true, "beer": true, "scotch": true, "bourbon": true,
		"premium": true, "special": true, "rare": true, "reserve": true, "deluxe": true,
		"blended": true, "grain": true, "indian": true, "international": true,
		"flavoured": true, "flavored": true, "distilled": true, "original": true,
		"royal": true, "select": true, "fine": true, "old": true, "the": true,
	}
	tokenize := func(s string) map[string]bool {
		out := map[string]bool{}
		for _, t := range strings.Fields(strings.ToLower(s)) {
			if len(t) < 4 {
				continue
			}
			if generics[t] {
				continue
			}
			out[t] = true
		}
		return out
	}
	a := tokenize(ocr)
	b := tokenize(candidate)
	if len(a) == 0 || len(b) == 0 {
		// If either side has no distinctive tokens, can't judge — be permissive
		// (the matcher's other gates will catch any bad routing).
		return true
	}
	for t := range a {
		if b[t] {
			return true
		}
	}
	return false
}

// packagingTokens lists short variant words that distinguish two SKUs of the
// same brand by container/format. They are intentionally excluded from
// hasSharedDistinctiveToken's len(t) >= 4 filter because they are <4 chars
// (pet, tin, can, qtr) or appear inside generic words. v1.0.241 — added so
// the pollution-guard catches "8 PM Gold Scotch Whisky PET" → a Tetra product
// silent-corruption class of alias.
//
// Each entry is also paired with sibling tokens in packagingSiblings: a
// conflict is only raised when OCR has a token from one packaging family and
// the candidate has a token from a DIFFERENT family. Sharing the same family
// (or both being silent on packaging) is fine.
var packagingTokens = map[string]string{
	"pet":   "pet",
	"tetra": "tetra",
	"glass": "glass",
	"tin":   "tin",
	"can":   "tin", // tin / can collapse to the same family
	"pp":    "pp",
	"pvc":   "pvc",
	"qtr":   "qtr",
	"mini":  "mini",
}

// hasPackagingTokenConflict returns true when ocr text and candidate product
// name reference DIFFERENT packaging families. Example: ocr "8 pm gold scotch
// whisky pet" vs candidate "8pm Gold Scotch Whisky Tetra 180ml" — ocr says
// "pet" (family=pet), candidate says "tetra" (family=tetra), different
// families → conflict.
//
// Returns false when:
//   - neither side mentions any packaging token (most products)
//   - only one side mentions packaging (silence on the other side is not a
//     conflict — many catalog names omit packaging while the bill spells it
//     out, e.g. "8PM Gold Scotch" matches "8 PM Gold Scotch Pet" silently
//     when there's only ONE 8PM Gold Scotch in the shop)
//   - both sides mention the same packaging family
//
// Intentionally case-insensitive and whole-token-matched (not substring) so
// "petrol" or "qtrly" can't false-match.
func hasPackagingTokenConflict(ocr, candidate string) bool {
	familyOf := func(s string) string {
		for _, tok := range strings.Fields(strings.ToLower(s)) {
			// strip surrounding punctuation that survived NormalizeForMatch
			t := strings.Trim(tok, ".,;:()[]{}'\"-_/")
			if fam, ok := packagingTokens[t]; ok {
				return fam
			}
		}
		return ""
	}
	a := familyOf(ocr)
	b := familyOf(candidate)
	if a == "" || b == "" {
		return false
	}
	return a != b
}

// absFloat lives in smart_sale_review_gate.go in the same package; do not redeclare here.

// priceVal safely dereferences a *float64 (the OCR Price field on
// ExtractedReceiptItem may be nil when the AI couldn't read the cell).
func priceVal(p *float64) float64 {
	if p == nil {
		return 0
	}
	return *p
}

// ============================================================================
// Training data storage — save images + AI extraction for building custom models
// ============================================================================

func saveSmartSaleTrainingData(tenantID string, req *SmartSaleRequest, result *SmartSaleResult) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				// Don't crash on training data save failure
			}
		}()

		sessionID := uuid.New().String()[:12]
		tenantShort := tenantID
		if len(tenantShort) > 8 {
			tenantShort = tenantShort[:8]
		}

		baseDir := fmt.Sprintf("/app/ai-training/smart-sale/%s/%s", tenantShort, sessionID)
		if err := os.MkdirAll(baseDir, 0755); err != nil {
			return
		}

		// Save images
		for i, imgData := range req.ImageData {
			imgPath := fmt.Sprintf("%s/image_%d.jpg", baseDir, i+1)
			os.WriteFile(imgPath, imgData, 0644)
		}

		// Save metadata
		metadata := map[string]interface{}{
			"session_id":    sessionID,
			"tenant_id":     tenantID,
			"shop_id":       req.ShopID.String(),
			"sale_date":     req.SaleDate.Format("2006-01-02"),
			"category":      req.Category,
			"size":          req.Size,
			"image_count":   len(req.ImageData),
			"timestamp":     time.Now().Format(time.RFC3339),
		}
		if metaBytes, err := json.Marshal(metadata); err == nil {
			os.WriteFile(baseDir+"/metadata.json", metaBytes, 0644)
		}

		// Save extraction result
		if resultBytes, err := json.Marshal(result); err == nil {
			os.WriteFile(baseDir+"/extraction_result.json", resultBytes, 0644)
		}
	}()
}

// parseSizeToML extracts size in ML from size string (e.g., "375ML" -> 375)
func parseSizeToML(size string) int {
	if size == "" {
		return 0
	}
	size = strings.ToUpper(strings.TrimSpace(size))
	// Extract digits
	re := regexp.MustCompile(`[^0-9]`)
	numStr := re.ReplaceAllString(size, "")
	if numStr == "" {
		return 0
	}
	ml := 0
	fmt.Sscanf(numStr, "%d", &ml)
	return ml
}

func absInt(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// cloneFieldConfidence v1.0.131 — copies the per-cell confidence map from an
// ExtractedReceiptItem into a fresh map for the SmartSaleExtractedItem. We
// clone (rather than share) so downstream mutations on the validated item
// don't leak back into the extraction-result blob and corrupt the response
// shape.
func cloneFieldConfidence(src map[string]float64) map[string]float64 {
	if len(src) == 0 {
		return nil
	}
	out := make(map[string]float64, len(src))
	for k, v := range src {
		out[k] = v
	}
	return out
}

// smartSaleStringSimilarity computes Levenshtein-based similarity for brand matching
func smartSaleStringSimilarity(a, b string) float64 {
	if a == b {
		return 1.0
	}
	if len(a) == 0 || len(b) == 0 {
		return 0.0
	}

	longer := a
	shorter := b
	if len(a) < len(b) {
		longer = b
		shorter = a
	}

	longerLen := len(longer)
	if longerLen == 0 {
		return 1.0
	}

	distance := smartSaleLevenshtein(longer, shorter)
	return float64(longerLen-distance) / float64(longerLen)
}

func smartSaleLevenshtein(a, b string) int {
	if len(a) == 0 {
		return len(b)
	}
	if len(b) == 0 {
		return len(a)
	}

	matrix := make([][]int, len(a)+1)
	for i := range matrix {
		matrix[i] = make([]int, len(b)+1)
		matrix[i][0] = i
	}
	for j := range matrix[0] {
		matrix[0][j] = j
	}

	for i := 1; i <= len(a); i++ {
		for j := 1; j <= len(b); j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			matrix[i][j] = smartSaleMinInt(
				matrix[i-1][j]+1,
				matrix[i][j-1]+1,
				matrix[i-1][j-1]+cost,
			)
		}
	}

	return matrix[len(a)][len(b)]
}

func smartSaleMinInt(nums ...int) int {
	m := nums[0]
	for _, n := range nums[1:] {
		if n < m {
			m = n
		}
	}
	return m
}

// EncodeImageToBase64 converts image bytes to base64 string
func EncodeImageToBase64(data []byte) string {
	return base64.StdEncoding.EncodeToString(data)
}

// v1.0.133 — admin replay endpoint hook.
//
// ReplayApplyLearning re-runs the alias / negative-alias / shop-rate /
// LogCorrectionOutcomes pipelines against a job's review-screen state,
// without writing any sale rows. Mirrors Stock Setup's
// SmartStockSetupService.ReplayApplyLearning. Idempotent (the underlying
// upserts dedupe), so safe to call multiple times. Tagged "replayed" in
// telemetry so calibration / few-shot pipelines can weight the signal
// distinctly from genuine apply hits.
func (s *SmartSaleService) ReplayApplyLearning(
	tenantID uuid.UUID,
	userID uuid.UUID,
	shopID uuid.UUID,
	jobID string,
	items []SmartSaleApplyItem,
) {
	s.logger.Infof("SmartSale: replay-learning invoked — job=%s tenant=%s user=%s items=%d",
		jobID, tenantID, userID, len(items))
	s.captureApplyLearning(tenantID, userID, shopID, items, "replayed")
}

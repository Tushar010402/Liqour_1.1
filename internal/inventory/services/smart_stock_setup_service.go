package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/matching"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/datatypes"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// SmartStockSetupService orchestrates AI-powered stock setup from register images
type SmartStockSetupService struct {
	db              *database.DB
	ocr             *SmartPurchaseOCR
	purchaseService *SmartPurchaseService // for product matching (same package)
	stockService    *StockService         // for cache clearing
	aliasService    *alias.AliasService
	cvSidecar       *StockSetupCVClient // v1.0.134 — CV cross-check (parity with Sales r10)
}

// DB exposes the underlying *gorm.DB for handlers that need to run lean
// inline queries (e.g. calibration_handler) without rolling another service
// method per single-row read. Read-only callers should not mutate state.
func (s *SmartStockSetupService) DB() *gorm.DB { return s.db.DB }

// CVSidecar exposes the cv-sidecar HTTP client so the handler layer can run
// preflight quality checks without holding its own client. v1.0.178.
func (s *SmartStockSetupService) CVSidecar() *StockSetupCVClient {
	if s == nil {
		return nil
	}
	return s.cvSidecar
}

// NewSmartStockSetupService creates a new SmartStockSetupService.
// AutoMigrate's the learning schemas (correction outcomes, calibration stats,
// shop register templates) so they exist regardless of deploy order, and
// kicks off the background learning refresher in a goroutine.
func NewSmartStockSetupService(db *database.DB, ocr *SmartPurchaseOCR, stockService *StockService, purchaseService *SmartPurchaseService, aliasService *alias.AliasService) *SmartStockSetupService {
	s := &SmartStockSetupService{
		db:              db,
		ocr:             ocr,
		purchaseService: purchaseService,
		stockService:    stockService,
		aliasService:    aliasService,
		cvSidecar:       NewStockSetupCVClient(logrusLogger()),
	}
	if err := MigrateLearningSchemas(db.DB); err != nil {
		log.Printf("Smart Stock Setup: learning schema migrate failed (continuing without learning): %v", err)
	} else {
		s.StartLearningRefresher(context.Background())
		log.Println("Smart Stock Setup: learning pipelines initialized (template, distinguishers, calibration)")
	}
	return s
}

// ============================================================================
// Step 1: Extract — process register images and return matched data for review
// ============================================================================

// ProcessExtraction processes register page images and returns extracted stock data
func (s *SmartStockSetupService) ProcessExtraction(ctx context.Context, req SmartStockSetupRequest) (*SmartStockSetupResult, error) {
	totalStart := time.Now()

	if !s.ocr.IsAvailable() {
		return nil, fmt.Errorf("AI extraction not configured. Contact your administrator to enable Smart Stock Setup")
	}

	if len(req.Images) == 0 {
		return nil, fmt.Errorf("at least one register page image is required")
	}

	// Generate unique session ID for training data tracking
	sessionID := uuid.New().String()[:12]

	tenantID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant ID: %w", err)
	}

	// Save images async (for future AI training)
	SaveSessionImages(req.TenantID, sessionID, req.Images)

	// Save images to web-accessible uploads dir for approval review
	tenantShort := req.TenantID
	if len(tenantShort) > 8 {
		tenantShort = tenantShort[:8]
	}
	uploadDir := fmt.Sprintf("/app/uploads/stock_setup/%s", tenantShort)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		log.Printf("SmartStockSetup: Upload dir create failed for %s: %v — review screen will lack images", uploadDir, err)
	}

	var savedImageURLs []string
	for i, img := range req.Images {
		ext := ".jpg"
		if strings.Contains(strings.ToLower(img.ContentType), "png") {
			ext = ".png"
		}
		filename := fmt.Sprintf("stock_setup_%s_%d_%d%s", tenantShort, time.Now().UnixMilli(), i, ext)
		fpath := fmt.Sprintf("%s/%s", uploadDir, filename)
		writeErr := os.WriteFile(fpath, img.Data, 0644)
		if writeErr != nil && os.IsNotExist(writeErr) {
			// Parent dir might have been removed between the MkdirAll above and now; retry once.
			if mkErr := os.MkdirAll(uploadDir, 0755); mkErr == nil {
				writeErr = os.WriteFile(fpath, img.Data, 0644)
			}
		}
		if writeErr != nil {
			log.Printf("SmartStockSetup: Failed to save image %d to %s: %v", i, fpath, writeErr)
			continue
		}
		imageURL := fmt.Sprintf("/uploads/stock_setup/%s/%s", tenantShort, filename)
		savedImageURLs = append(savedImageURLs, imageURL)
	}
	log.Printf("SmartStockSetup: Saved %d/%d register images to uploads", len(savedImageURLs), len(req.Images))

	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		return nil, fmt.Errorf("invalid shop ID: %w", err)
	}

	// Validate stock_column: "total" (default), "closing", or "opening"
	stockColumn := req.StockColumn
	switch stockColumn {
	case "closing", "opening":
		// valid
	default:
		stockColumn = "total"
	}

	// Resolve optional category and size context
	var categoryName string
	var categoryUUID uuid.UUID
	var sizeML int

	if req.CategoryID != "" {
		categoryUUID, err = uuid.Parse(req.CategoryID)
		if err != nil {
			return nil, fmt.Errorf("invalid category ID: %w", err)
		}
		var cat struct{ Name string }
		if dbErr := s.db.Table("categories").Select("name").
			Where("id = ? AND tenant_id = ?", categoryUUID, tenantID).
			Scan(&cat).Error; dbErr == nil && cat.Name != "" {
			categoryName = cat.Name
		}
	}
	if req.Size != "" {
		sizeML = normalizeSizeText(req.Size)
	}

	// Pre-load products BEFORE OCR (needed for product-aware AI prompt)
	// Load ALL products for the given size (no category filter) because
	// the register page lists all spirits together (Whisky + Rum + Vodka + Brandy).
	var products []dbProduct
	if sizeML > 0 {
		products, err = s.purchaseService.loadProductsScoped(tenantID, &shopID, nil, sizeML)
	} else {
		products, err = s.purchaseService.loadProducts(tenantID, &shopID)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to load products: %w", err)
	}

	// Beer / non-beer hard divide. The user picks the category at upload
	// (Whisky, Vodka, Rum, Gin, Brandy, or Beer). Beer registers and non-beer
	// registers never share rows — a beer page never has a whisky entry and
	// vice versa. Within non-beer, sub-categories CAN cross-match (whisky page
	// can legitimately list a vodka row), so we don't hard-filter by sub-cat.
	// Without this filter, a beer-page upload could fuzzy-match into a whisky
	// product whose name happens to share tokens.
	isBeerSetup := strings.EqualFold(categoryName, "beer")
	if categoryName != "" && len(products) > 0 {
		// Resolve all "Beer" category UUIDs for this tenant (a tenant may have
		// renamed/duplicated the beer category). dbProduct only carries
		// CategoryID, not CategoryName, so we filter by ID set.
		var beerCatIDs []string
		if dbErr := s.db.Table("categories").
			Where("tenant_id = ? AND LOWER(name) = ?", tenantID, "beer").
			Pluck("id::text", &beerCatIDs).Error; dbErr != nil {
			log.Printf("Smart Stock Setup: beer-category lookup failed: %v (skipping beer/non-beer filter)", dbErr)
		} else {
			beerSet := make(map[string]bool, len(beerCatIDs))
			for _, id := range beerCatIDs {
				beerSet[id] = true
			}
			var keptProducts []dbProduct
			for _, p := range products {
				pIsBeer := beerSet[p.CategoryID]
				if pIsBeer == isBeerSetup {
					keptProducts = append(keptProducts, p)
				}
			}
			if len(keptProducts) < len(products) {
				log.Printf("Smart Stock Setup: beer/non-beer filter dropped %d products (%d → %d, isBeerSetup=%v, beerCatIDs=%d)",
					len(products)-len(keptProducts), len(products), len(keptProducts), isBeerSetup, len(beerCatIDs))
			}
			products = keptProducts
		}
	}

	// v1.0.247 — Build a full categoryID → name map so matchAndEnrich can run
	// the page-level category gate (whisky page must not match wine products).
	// Cheap: ~5-10 rows per tenant. We load it here rather than inside the
	// per-row matchAndEnrich call so the cost is amortised across all rows.
	categoryNameByID := make(map[string]string, 8)
	{
		var catRows []struct {
			ID   string `gorm:"column:id"`
			Name string `gorm:"column:name"`
		}
		if dbErr := s.db.Table("categories").
			Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
			Select("id::text AS id, name").
			Scan(&catRows).Error; dbErr != nil {
			log.Printf("Smart Stock Setup: category map lookup failed: %v (page-level category gate disabled this run)", dbErr)
		} else {
			for _, r := range catRows {
				categoryNameByID[r.ID] = r.Name
			}
		}
	}

	// Load master brands from UP Excise data for this size+state
	tenantState := s.getTenantState(tenantID)
	masterBrands := s.loadMasterBrands(sizeML, tenantState)
	log.Printf("Smart Stock Setup: Loaded %d master brands (%s, %dML)", len(masterBrands), tenantState, sizeML)

	// Enrich products whose saas_brand_id is NULL by inferring the excise linkage
	// from the master catalog via name+MRP. This makes `matched_excise_brand_name`
	// populated in the response even when the DB link is missing (which covers 60%+
	// of tenant products in the current state).
	s.enrichProductsWithInferredExcise(products, masterBrands)

	// Build product name list for AI prompt (tenant products).
	// We pass the FULL filtered set (capped at 500) for the selected size so the
	// AI is grounded in the actual catalog universe instead of falling back to
	// guesses from training data. Each line carries the display name AND the
	// excise/full name so the model can match either form (e.g. "M2 GREEN APPLE"
	// in the register vs the catalog's "M2 Magic Moments Remix Green Apple
	// Flavoured Vodka"). Size is included so the AI never confuses 750ML rows
	// with 180ML variants of the same brand.
	var productNames []string
	const maxProductsInPrompt = 500
	if len(products) > 0 {
		take := len(products)
		if take > maxProductsInPrompt {
			take = maxProductsInPrompt
		}
		productNames = make([]string, 0, take)
		for i := 0; i < take; i++ {
			p := products[i]
			display, full := resolveDisplayAndFullName(&p)
			if display == "" {
				display = p.BrandName
				if display == "" {
					display = p.Name
				}
			}
			line := display
			// The bold portion (if set in the catalog) is the SHORT essential
			// identifier the user himself flagged as the distinguishing piece —
			// surfacing it lets the AI prefer it for handwriting matches.
			if bold := extractBoldPortion(display, p.DisplayNameBoldStart, p.DisplayNameBoldLength); bold != "" {
				line += " | key: " + bold
			}
			// Append excise / full only when it actually adds info — same string
			// twice would just dilute the prompt.
			if p.ExciseDisplayName != "" && !strings.EqualFold(p.ExciseDisplayName, display) {
				line += " | excise: " + p.ExciseDisplayName
			} else if p.ExciseBrandName != "" && !strings.EqualFold(p.ExciseBrandName, display) {
				line += " | excise: " + p.ExciseBrandName
			} else if full != "" && !strings.EqualFold(full, display) {
				line += " | full: " + full
			}
			if p.Size != "" {
				line += " | " + p.Size
			}
			if p.MRP > 0 {
				line += fmt.Sprintf(" | MRP ₹%.0f", p.MRP)
			}
			productNames = append(productNames, line)
		}
		if len(products) > maxProductsInPrompt {
			log.Printf("Smart Stock Setup: capped product list at %d (have %d)", maxProductsInPrompt, len(products))
		}
	}

	// Build master brand list for AI prompt (official excise data). Include the
	// short display_name when distinct from the long excise name so the model
	// can recognise either form on the register (e.g. "M2 Cranberry" vs the
	// long "M2 MAGIC MOMENTS REMIX CRANBERRY FLAVOURED VODKA").
	var masterBrandNames []string
	for _, mb := range masterBrands {
		entry := mb.BrandName
		if mb.DisplayName != "" && !strings.EqualFold(mb.DisplayName, mb.BrandName) {
			entry = fmt.Sprintf("%s (display: %s)", mb.BrandName, mb.DisplayName)
		}
		if bold := extractBoldPortion(mb.DisplayName, mb.DisplayNameBoldStart, mb.DisplayNameBoldLength); bold != "" {
			entry += fmt.Sprintf(" (key: %s)", bold)
		}
		if mb.MRP > 0 {
			entry += fmt.Sprintf(" (MRP: ₹%.0f)", mb.MRP)
		}
		masterBrandNames = append(masterBrandNames, entry)
	}

	// Step 1: Extract from all images using AI (parallel for speed)
	ocrStart := time.Now()
	var allExtracted []ExtractedStockRegisterItem
	var detectedShopName string
	aiModel := "Fomoa AI"
	pageRowCounts := make([]int, len(req.Images)) // index by page-1 → row_count_on_page from AI

	// v1.0.184 Track S1 — AWS Textract Tables pipeline. Mirrors Smart Sale
	// (v1.0.183) and Smart Purchase (v1.0.169) — Textract reads the printed
	// register grid deterministically with per-cell digit confidence the
	// Sonnet vision LLM can't match on handwritten registers.
	//
	// Falls back to the legacy Sonnet path when:
	//   - kill switch (env STOCK_SETUP_PIPELINE=disabled or per-tenant)
	//   - Textract returns < per-size row floor (S2)
	//   - any error during extraction
	//
	// Trigger: chhotu Mahua Khera 2026-05-06 19:00 IST submissions had 50%
	// manual-correction rate on 180 ml and avg confidence 0.65 — the same
	// accuracy class Smart Sale was in pre-v1.0.183.
	if stockSetupTextractEnabledForTenant(tenantID) {
		txItems, txErr := extractStockRegisterWithTextract(ctxWithHintsTextract(ctx), req.Images, tenantID, shopID, stockColumn, sizeML)
		switch {
		case txErr != nil:
			log.Printf("Smart Stock Setup: Textract extract failed: %v — falling back to legacy Sonnet", txErr)
		case len(txItems) == 0:
			log.Printf("Smart Stock Setup: Textract returned 0 valid rows — falling back to legacy Sonnet")
		default:
			// Track S4 — silently apply confirmed (raw → corrected) digit
			// pairs operator has confirmed N+ times for this shop. Same
			// learning corpus Smart Sale uses; "ask once, learn forever".
			thresh := stockSetupAutoFixThreshold()
			if thresh > 0 {
				confirmed := LoadConfirmedDigitCorrectionsForStockSetup(s.db.DB, tenantID, shopID, thresh)
				autoFixed := 0
				for i := range txItems {
					autoFixed += applyConfirmedDigitCorrectionsStockSetup(&txItems[i], confirmed)
				}
				if autoFixed > 0 {
					log.Printf("Smart Stock Setup: Textract auto-fix applied %d confirmed digit corrections (threshold>=%d)", autoFixed, thresh)
				}
			}
			allExtracted = txItems
			aiModel = "AWS Textract"
			// Build per-page row-count summary from the rows we got back so
			// downstream UI banners match what was actually extracted.
			for _, it := range txItems {
				p := it.PageNumber - 1
				if p >= 0 && p < len(pageRowCounts) {
					pageRowCounts[p]++
				}
			}
			log.Printf("Smart Stock Setup: Textract produced %d rows — skipping legacy Sonnet extract", len(txItems))
		}
	}

	type imageResult struct {
		index    int
		result   *StockRegisterExtractionResult
		err      error
	}

	// Compute per-tenant prompt hints (template fingerprint + few-shot
	// examples) once and stash in context so each parallel OCR backend
	// reads the same string. Empty when learning thresholds aren't met yet.
	templateHint := s.ResolveTemplateHint(tenantID, shopID, sizeML)
	fewShotHint := s.FewShotPromptHint(tenantID)
	// v1.0.133 — per-shop digit-handwriting confusions. Prepended so Claude
	// sees the most-frequent (raw → corrected) pairs as few-shot guidance
	// before encountering the register image. Empty when no learning yet.
	digitHint := FormatDigitConfusionsForPrompt(LoadTopDigitConfusions(s.db.DB, tenantID, shopID, "stock_setup", 8))
	combinedHints := digitHint + templateHint + fewShotHint
	ctxWithHints := ctx
	if combinedHints != "" {
		ctxWithHints = context.WithValue(ctx, PromptHintsCtxKey, combinedHints)
		log.Printf("Smart Stock Setup: prompt hints injected (digit=%dch, template=%dch, few-shot=%dch)", len(digitHint), len(templateHint), len(fewShotHint))
	}
	// v1.0.246 — Pass the operator's stockColumn choice into the prompt so
	// the AI laser-focuses on that column for accuracy. Without this, the
	// AI splits attention across all 5 stock columns and the picked column
	// gets the same noisy read as the discarded ones — root cause of
	// chhotu's "zero opening" + "missing items" reports.
	ctxWithHints = context.WithValue(ctxWithHints, StockColumnCtxKey, stockColumn)

	// v1.0.184 Track S1 — skip the legacy parallel Sonnet loop entirely when
	// Textract already produced rows. The fallback (allExtracted == nil)
	// retains all the existing behaviour for tenants Textract was disabled on
	// and for layouts Textract couldn't grid.
	resultsCh := make(chan imageResult, len(req.Images))
	// v1.0.302 — declared at outer scope so the final-empty-result branch
	// below can build an honest user-facing message naming the real cause
	// when every extractor errored (vs the page being genuinely blank).
	var extractErrCount int
	var lastExtractErr error
	if len(allExtracted) == 0 {
	for i, img := range req.Images {
		go func(idx int, imgData []byte, contentType string) {
			// v1.0.134 — CV sidecar cross-check. Per-image (blank rows
			// vary across pages of a multi-page submission). Best-effort:
			// any failure returns nil and extraction proceeds without the
			// hint — sidecar NEVER blocks.
			imgCtx := ctxWithHints
			if s.cvSidecar != nil {
				if cvResp := s.cvSidecar.DetectBlankRows(ctxWithHints, imgData); cvResp != nil {
					if hint := BuildStockSetupBlankRowHint(cvResp); hint != "" {
						imgCtx = context.WithValue(imgCtx, StockSetupCVHintsCtxKey, hint)
						log.Printf("Smart Stock Setup: CV cross-check hint injected for image %d (%dch)", idx+1, len(hint))
					}
					if len(cvResp.Rows) > 0 {
						imgCtx = context.WithValue(imgCtx, StockSetupCVRowsCtxKey, cvResp.Rows)
					}
				}
			}
			res, err := s.ocr.ExtractStockRegister(imgCtx, imgData, contentType, categoryName, sizeML, productNames, masterBrandNames)
			resultsCh <- imageResult{index: idx, result: res, err: err}
		}(i, img.Data, img.ContentType)
	}

	// Collect results in order
	imageResults := make([]imageResult, len(req.Images))
	for range req.Images {
		r := <-resultsCh
		imageResults[r.index] = r
	}

	// v1.0.302 — track per-image extract errors so the user-facing message
	// can surface the real cause when every extractor fails (vars declared
	// at outer scope above so the final-empty-result branch can see them).
	// Real incident 2026-05-23: matched_product_id JSON-type bug blocked
	// Claude → Gemini → OpenAI in order; the OpenAI 429 was the final
	// visible error in the logs but the user saw "No product entries
	// found" and had no clue billing/parse was involved.
	for i, ir := range imageResults {
		if ir.err != nil {
			log.Printf("Smart Stock Setup: Failed to extract from image %d: %v", i+1, ir.err)
			extractErrCount++
			lastExtractErr = ir.err
			continue
		}
		result := ir.result

		// Use shop name from first image that has it
		if detectedShopName == "" && result.ShopName != "" {
			detectedShopName = result.ShopName
		}

		// Each page has a size from header — propagate to items.
		// Also stamp the 1-based PageNumber so downstream validators and the
		// Flutter review UI can tell which source image each row came from.
		pageNum := i + 1
		for j := range result.Items {
			if result.Items[j].SizeML == 0 && result.PageSizeML > 0 {
				result.Items[j].SizeML = result.PageSizeML
			}
			if result.Items[j].SizeText == "" && result.PageSize != "" {
				result.Items[j].SizeText = result.PageSize
			}
			result.Items[j].PageNumber = pageNum
			// Mark source so the two-pass handwritten re-extract can tell main-pass
			// rows from re-extracted ones for audit and Flutter badging.
			if result.Items[j].Source == "" {
				result.Items[j].Source = "main"
			}
		}
		// Page row-count fallback: if AI didn't return row_count_on_page, use
		// max(row_number) seen on the page as a best-effort estimate so the
		// review UI can still compute a Y-band for each row.
		rowCount := result.RowCountOnPage
		if rowCount == 0 {
			for _, it := range result.Items {
				if it.RowNumber > rowCount {
					rowCount = it.RowNumber
				}
			}
		}
		pageRowCounts[i] = rowCount

		allExtracted = append(allExtracted, result.Items...)

		aiModel = "Fomoa AI"
	}
	} // end Textract-fallback gate (v1.0.184 S1)
	ocrDuration := time.Since(ocrStart).Milliseconds()

	// Page-rescue (v1.0.114): for each page, compare extracted-row-count against
	// the OCR-claimed RowCountOnPage. If the gap is large (e.g. AI said page 2
	// had 23 rows but only 5 came through — the leading 18 handwritten rows
	// were silently dropped — see job 85e87033), trigger a full-page handwritten
	// re-extract before the trailing-band pass runs. detectHandwrittenBand only
	// finds trailing low-confidence runs in rows ALREADY present, so it can't
	// recover rows that never made it into allExtracted in the first place.
	pageRescueTriggered := make([]bool, len(req.Images))
	pageActualBeforeRescue := make([]int, len(req.Images))
	if os.Getenv("SMART_STOCK_SETUP_PAGE_RESCUE") != "0" {
		for i, img := range req.Images {
			pageNum := i + 1
			expected := pageRowCounts[i]
			actual := 0
			for _, ext := range allExtracted {
				if ext.PageNumber == pageNum {
					actual++
				}
			}
			pageActualBeforeRescue[i] = actual
			if expected < 6 {
				continue
			}
			// Compute page-level avg confidence up front — used by BOTH gates below.
			pageConf := 0.0
			if actual > 0 {
				sum := 0.0
				for _, ext := range allExtracted {
					if ext.PageNumber == pageNum {
						sum += ext.Confidence
					}
				}
				pageConf = sum / float64(actual)
			}
			underRowFloor := float64(actual) < 0.7*float64(expected)
			// v1.0.286 — low-confidence rescue gate. The original gate only
			// caught pages where the main pass DROPPED rows (actual < 70% of
			// expected). But chhotu's 2026-05-22 15:46 IST 180ml job hit a
			// failure mode the row gate misses: page 2 returned 11/13 rows
			// (85% — well above the row floor) BUT avg conf was 0.50 with
			// every page-2 row carrying "Price out of order — may be row
			// drift" warnings. Row count looked fine; the actual reads were
			// scrambled. Trigger rescue when EITHER the page is under-
			// extracted OR the page's main-pass reads are too uncertain to
			// trust (avg conf < 0.65). Override env var lets ops dial back
			// if the extra call cost shows up in bills.
			lowConfThreshold := 0.65
			if v := strings.TrimSpace(os.Getenv("SMART_STOCK_SETUP_PAGE_RESCUE_CONF")); v != "" {
				if f, err := strconv.ParseFloat(v, 64); err == nil && f >= 0 && f <= 1 {
					lowConfThreshold = f
				}
			}
			lowConfPage := actual > 0 && pageConf < lowConfThreshold
			if !underRowFloor && !lowConfPage {
				continue
			}
			// Confidence guard (legacy): a page where the rows we DID get are
			// high-confidence is probably just sparse (AI saw 28 row lines but
			// 10 are blank), not missing rows. Skip when avg conf is healthy
			// AND we only got here via the under-row-floor path — the low-conf
			// path has already ruled this out by definition.
			if !lowConfPage && actual > 0 && pageConf >= 0.85 {
				log.Printf("Smart Stock Setup: page-rescue skipped for page %d — sparse but high-confidence (avg %.2f)",
					pageNum, pageConf)
				continue
			}
			triggerReason := "under-row-floor"
			if lowConfPage && !underRowFloor {
				triggerReason = "low-confidence"
			} else if lowConfPage && underRowFloor {
				triggerReason = "both"
			}
			log.Printf("Smart Stock Setup: page-rescue triggered for page %d (%s) — expected %d rows, got %d (%.0f%%), avg conf %.2f",
				pageNum, triggerReason, expected, actual, 100*float64(actual)/float64(expected), pageConf)
			rRes, rErr := s.ocr.ExtractHandwrittenBand(ctx, img.Data, img.ContentType, categoryName, sizeML, productNames, masterBrandNames, 1, expected)
			if rErr != nil || rRes == nil {
				log.Printf("Smart Stock Setup: page-rescue failed for page %d: %v (keeping main-pass rows)", pageNum, rErr)
				continue
			}
			for j := range rRes.Items {
				rRes.Items[j].PageNumber = pageNum
				rRes.Items[j].Source = "page_rescue"
				if rRes.Items[j].SizeML == 0 && sizeML > 0 {
					rRes.Items[j].SizeML = sizeML
				}
			}
			allExtracted = mergeHandwrittenBand(allExtracted, rRes.Items, pageNum, 1, expected)
			pageRescueTriggered[i] = true
			rescued := 0
			for _, ext := range allExtracted {
				if ext.PageNumber == pageNum {
					rescued++
				}
			}
			log.Printf("Smart Stock Setup: page-rescue page %d merged — actual now %d/%d rows", pageNum, rescued, expected)
		}
	}

	// Handwritten-pass: for each page, detect a trailing band of handwritten /
	// low-confidence rows. If the band is substantial, issue a specialized AI
	// call focused on just that range and merge the result back in. Costs an
	// extra ~10s + 1 OpenAI call per page with a handwritten section, but
	// dramatically reduces brand/row drift in the hardest part of the register.
	handwrittenPassTriggered := false
	handwrittenPassPerPage := make([]bool, len(req.Images))
	for i, img := range req.Images {
		pageNum := i + 1
		fromRow, toRow, ok := detectHandwrittenBand(allExtracted, pageNum)
		if !ok {
			continue
		}
		log.Printf("Smart Stock Setup: handwritten-pass triggered for page %d rows %d-%d", pageNum, fromRow, toRow)
		hRes, hErr := s.ocr.ExtractHandwrittenBand(ctx, img.Data, img.ContentType, categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
		if hErr != nil || hRes == nil {
			log.Printf("Smart Stock Setup: handwritten-pass failed for page %d: %v (keeping main-pass rows)", pageNum, hErr)
			continue
		}
		// Mark source so Flutter can badge these and downstream debugging knows
		// which rows were re-extracted.
		for j := range hRes.Items {
			hRes.Items[j].PageNumber = pageNum
			hRes.Items[j].Source = "handwritten_pass"
			if hRes.Items[j].SizeML == 0 && sizeML > 0 {
				hRes.Items[j].SizeML = sizeML
			}
		}
		allExtracted = mergeHandwrittenBand(allExtracted, hRes.Items, pageNum, fromRow, toRow)
		handwrittenPassTriggered = true
		handwrittenPassPerPage[i] = true
	}
	if handwrittenPassTriggered {
		ocrDuration = time.Since(ocrStart).Milliseconds()
		log.Printf("Smart Stock Setup: handwritten-pass merged; total OCR time now %dms", ocrDuration)
	}

	// v1.0.120: dedupe duplicate (page, brand) extractions that the handwritten
	// pass + main pass occasionally produce. Without this, record c78bd84c
	// row 49 (100 STROKES @ ₹720, bled from row 48's M2 JAMUN) and row 50
	// (100 STROKES @ ₹620, correct master MRP) BOTH made it to Flutter — user
	// approved the matched 720 row, missed the duplicate 620 row in the
	// not-found tail. The dedupe keeps the rate that matches master MRP within
	// 5% (rate-bleed is recognizable that way), or falls back to highest
	// confidence. Pure backend fix — no schema change.
	beforeDedupe := len(allExtracted)
	allExtracted = dedupeSameBrandSamePage(allExtracted, masterBrands, sizeML)
	if dropped := beforeDedupe - len(allExtracted); dropped > 0 {
		log.Printf("Smart Stock Setup: brand-dedup dropped %d duplicate row(s) on the same page", dropped)
	}

	// v1.0.133-r9 — POST-EXTRACTION HALLUCINATION FILTER (parity with
	// Smart Sale). Drops Total/Grand-Total rows + completely-blank ghost
	// rows that survive past the extractor's prompt instructions. Stock
	// Setup's flow already has rule #11 in the prompt ("SKIP rows where
	// brand name is empty or is a total/subtotal/grand total row") but
	// belt-and-braces ensures it.
	beforeHallucinationFilter := len(allExtracted)
	cleaned := allExtracted[:0]
	totalDropped := 0
	blankDropped := 0
	for _, it := range allExtracted {
		brandTrim := strings.TrimSpace(it.Brand)
		brandLower := strings.ToLower(brandTrim)
		var brandNorm strings.Builder
		for _, r := range brandLower {
			if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
				brandNorm.WriteRune(r)
			}
		}
		bn := brandNorm.String()
		isTotalRow := bn == "total" || bn == "grandtotal" || bn == "gtotal" || bn == "grtotal" ||
			(strings.HasPrefix(bn, "grandtotal") && len(bn) <= 14) ||
			(strings.HasSuffix(bn, "total") && len(bn) <= 12)
		if isTotalRow && bn != "" {
			log.Printf("Smart Stock Setup: dropped TOTAL-row hallucination — brand='%s' opening=%d closing=%d", brandTrim, it.Opening, it.Closing)
			totalDropped++
			continue
		}
		// Blank-row detection: empty brand AND all numeric register cells zero.
		if brandTrim == "" && it.Opening == 0 && it.Receipt == 0 && it.Total == 0 && it.Sale == 0 && it.Closing == 0 && it.Rate == 0 {
			blankDropped++
			continue
		}
		// v1.0.265 — EMPTY-BRAND GHOST drop (deterministic, runs on the
		// Textract path that actually serves production). A row with NO
		// brand text is NOT a product — its numbers are Textract grid-bleed
		// (chhotu record 5693f4f6: job row 38 had brand="" opening=194 and
		// was matched to "NAUTILUS…/Teacher's 50", persisted with the
		// hallucinated 194 the operator could never fix). Previously such a
		// row survived because the blank filter above also required ALL
		// numeric cells == 0. An unbranded row must be dropped BEFORE the
		// matcher can attach a random master to it, regardless of its
		// (bled) numbers. Safe: no real catalog product is nameless.
		if len(bn) < 2 {
			log.Printf("Smart Stock Setup: dropped EMPTY-BRAND ghost row — brand='%s' opening=%d sale=%d rate=%.0f (v1.0.265, Textract grid-bleed)", brandTrim, it.Opening, it.Sale, it.Rate)
			blankDropped++
			continue
		}
		// v1.0.134 — schema-key-leak detection (parity with Smart Sale r9).
		// When the AI accidentally returns a JSON-schema field name as the
		// brand value (e.g. "row_number", "raw_text", "brand"), the row is
		// always a parse leak — drop it.
		if (brandLower == "row_number" || brandLower == "raw_text" || brandLower == "brand" ||
			brandLower == "opening" || brandLower == "closing" || brandLower == "rate") &&
			it.Opening == 0 && it.Receipt == 0 && it.Total == 0 && it.Sale == 0 && it.Closing == 0 && it.Rate == 0 {
			log.Printf("Smart Stock Setup: dropped schema-key-leak ghost row — brand='%s'", brandTrim)
			blankDropped++
			continue
		}
		// v1.0.262 — COLUMN-HEADER row drop (deterministic, prompt-independent).
		// On a pre-printed sale-receipt book the model sometimes emits the
		// column-title row ("Brand Name" + bled rate=290) as item #1, which
		// shifts every real brand down one and strips leading tokens (chhotu's
		// "8 PM Gold..." → "PM Gold..."). The schema-key-leak guard above misses
		// it because that requires ALL cells == 0 and the header carries bled
		// garbage. Exact-match on the alnum-normalised brand against known
		// column titles — no real liquor brand normalises to these, so this
		// never drops a genuine product regardless of its numbers.
		switch bn {
		case "brandname", "brand", "productname", "product", "particulars",
			"item", "itemname", "sno", "snno", "srno", "serialno",
			"serialnumber", "openin", "opening", "receipt", "sale", "rate",
			"amount", "closin", "closing", "qty", "quantity", "mrp", "size":
			log.Printf("Smart Stock Setup: dropped COLUMN-HEADER row — brand='%s' rate=%.0f (printed-form header, v1.0.262)", brandTrim, it.Rate)
			blankDropped++
			continue
		}
		// v1.0.263 — DETERMINISTIC rate-concat / arithmetic correction at the
		// SERVICE level (the parse-time ApplyAllGuards runs too early — a later
		// cell-retry/enrich sub-path re-introduces the doubled rate, e.g.
		// Officers Choice rate=130130 amount=4810 sale=37 → true rate 130).
		// This loop is the same prompt-independent place the v1.0.262
		// header-drop works, so it is guaranteed to see the FINAL item.
		if it.Rate > 5000 {
			orig := it.Rate
			var cand float64
			if it.Sale > 0 && it.Amount > 0 { // Amount = Sale × Rate is decisive
				r := it.Amount / float64(it.Sale)
				if r >= 30 && r <= 5000 && math.Abs(r-math.Round(r)) < 0.01 {
					cand = math.Round(r)
				}
			}
			if cand == 0 { // doubled-string pattern: "130130" → "130"
				s := strconv.FormatInt(int64(it.Rate), 10)
				if n := len(s); n >= 2 && n%2 == 0 && s[:n/2] == s[n/2:] {
					if h, err := strconv.ParseFloat(s[:n/2], 64); err == nil && h >= 30 && h <= 5000 {
						cand = h
					}
				}
			}
			if cand > 0 && cand != orig {
				log.Printf("Smart Stock Setup: rate-concat fixed row %d '%s': ₹%.0f → ₹%.0f (deterministic, v1.0.263)", it.RowNumber, brandTrim, orig, cand)
				it.Rate = cand
				if it.FieldConfidence == nil {
					it.FieldConfidence = map[string]float64{}
				}
				it.FieldConfidence["rate"] = 0.7
			}
		}
		cleaned = append(cleaned, it)
	}
	allExtracted = cleaned
	if totalDropped > 0 || blankDropped > 0 {
		log.Printf("Smart Stock Setup: post-extraction filter dropped %d total-row + %d blank-row hallucinations (kept %d of %d)",
			totalDropped, blankDropped, len(allExtracted), beforeHallucinationFilter)
	}

	// Save metadata and raw AI extraction for future training
	SaveSessionMetadata(req.TenantID, sessionID, StockSetupSessionMetadata{
		SessionID:    sessionID,
		TenantID:     req.TenantID,
		ShopID:       req.ShopID,
		UserID:       req.UserID,
		CategoryID:   req.CategoryID,
		CategoryName: categoryName,
		Size:         req.Size,
		SizeML:       sizeML,
		StockColumn:  stockColumn,
		ImageCount:   len(req.Images),
		AIModel:      aiModel,
		CreatedAt:    time.Now(),
	})
	SaveAIExtraction(req.TenantID, sessionID, allExtracted, detectedShopName)

	// v1.0.288 — Wrong-size pages: KEEP the rows, override size, warn the user.
	// Earlier (v1.0.287) we silently filtered rows whose detected size didn't match
	// the user-selected setup size. This had two failure modes in production:
	//   1. Tushar uploaded a real 375ml page-2 while setting up 180ml → 8 rows
	//      vanished and the user thought the app silently dropped photo 2.
	//   2. False-positive size reads from the AI (handwriting "180" misread as
	//      "375", or continuation pages with mismatched printed headers) also
	//      vanished — legitimate data lost without any user-visible signal.
	// Per user directive: trust the user's selection over the AI's read. Keep
	// the rows, tag them with the selected size, and surface a clear warning so
	// the user can verify those rows before applying. They know better than the
	// AI what they uploaded.
	type pageSkipAgg struct {
		count        int
		detectedSize string
		sizeML       int
	}
	pageSkipsByDetectedSize := make(map[int]map[int]*pageSkipAgg) // pageNumber -> detectedSizeML -> agg
	if sizeML > 0 && len(allExtracted) > 0 {
		overridden := 0
		for i := range allExtracted {
			item := &allExtracted[i]
			// Recover SizeML when AI omitted it but the brand/name string contains the size.
			if item.SizeML == 0 {
				item.SizeML = inferSizeMLFromName(item.Brand + " " + item.OfficialBrandName)
			}
			if item.SizeML > 0 && item.SizeML != sizeML {
				if item.PageNumber > 0 {
					if pageSkipsByDetectedSize[item.PageNumber] == nil {
						pageSkipsByDetectedSize[item.PageNumber] = make(map[int]*pageSkipAgg)
					}
					agg, ok := pageSkipsByDetectedSize[item.PageNumber][item.SizeML]
					if !ok {
						agg = &pageSkipAgg{sizeML: item.SizeML, detectedSize: item.SizeText}
						pageSkipsByDetectedSize[item.PageNumber][item.SizeML] = agg
					}
					agg.count++
					if agg.detectedSize == "" && item.SizeText != "" {
						agg.detectedSize = item.SizeText
					}
				}
				log.Printf("Smart Stock Setup: keeping '%s' but overriding detected size %dML → user-selected %dML (page %d)", item.Brand, item.SizeML, sizeML, item.PageNumber)
				item.SizeML = sizeML
				item.SizeText = ""
				overridden++
			}
		}
		if overridden > 0 {
			log.Printf("Smart Stock Setup: size override applied to %d items (kept, not dropped) — user will be warned to verify", overridden)
		}
	}
	// Materialise the per-page summary into the typed slice we surface on the
	// response. One entry per (page, detected-size) pair — usually one per page,
	// since a "wrong-size" page is almost always uniformly one size (the page
	// header dictates the size for every row on that page).
	var sizeMismatchSkippedPages []SizeMismatchSkippedPage
	if len(pageSkipsByDetectedSize) > 0 {
		pageNums := make([]int, 0, len(pageSkipsByDetectedSize))
		for p := range pageSkipsByDetectedSize {
			pageNums = append(pageNums, p)
		}
		sort.Ints(pageNums)
		for _, p := range pageNums {
			bySize := pageSkipsByDetectedSize[p]
			for _, agg := range bySize {
				sizeMismatchSkippedPages = append(sizeMismatchSkippedPages, SizeMismatchSkippedPage{
					PageNumber:     p,
					DetectedSizeML: agg.sizeML,
					DetectedSize:   agg.detectedSize,
					SkippedCount:   agg.count,
				})
			}
		}
	}

	// Phantom-row suppression: registers carry a preprinted brand list (~37 rows
	// at FM Tower) but only the rows the shopkeeper actually filled in have
	// handwritten quantities. The AI reads the printed names anyway and emits
	// rows for all of them, which the matcher then has to fight against. Drop
	// rows where every numeric field is zero AND the AI was uncertain AND the
	// brand isn't already in the tenant catalog (which would mean a legitimate
	// "zero stock today" entry). Surface the count in the result summary.
	unfilledRows := 0
	if len(allExtracted) > 0 {
		brandsInCatalog := make(map[string]bool, len(products))
		for _, p := range products {
			for _, name := range []string{p.Name, p.BrandName, p.DisplayName} {
				if name == "" {
					continue
				}
				if toks := distinctiveTokensFromText(name, 2); len(toks) > 0 {
					brandsInCatalog[strings.Join(toks, " ")] = true
				}
			}
		}
		var kept []ExtractedStockRegisterItem
		for _, item := range allExtracted {
			allZero := item.Opening == 0 && item.Receipt == 0 && item.Sale == 0 &&
				item.Total == 0 && item.Closing == 0 && item.Amount == 0
			if !allZero {
				kept = append(kept, item)
				continue
			}
			// All zeros — keep only if AI was confident OR the brand is already
			// in the tenant catalog (legitimate zero-stock entry).
			confident := item.Confidence >= 0.9
			brandKey := strings.Join(distinctiveTokensFromText(item.Brand+" "+item.OfficialBrandName, 2), " ")
			knownBrand := brandKey != "" && brandsInCatalog[brandKey]
			if confident || knownBrand {
				kept = append(kept, item)
				continue
			}
			unfilledRows++
			log.Printf("Smart Stock Setup: phantom row suppressed (page %d row %d): %q (conf=%.2f, all-zero, not in catalog)",
				item.PageNumber, item.RowNumber, item.Brand, item.Confidence)
		}
		if unfilledRows > 0 {
			log.Printf("Smart Stock Setup: suppressed %d phantom rows from preprinted brand list (%d → %d)",
				unfilledRows, len(allExtracted), len(kept))
		}
		allExtracted = kept
	}

	if len(allExtracted) == 0 {
		// v1.0.302 — honest message. If every image errored out of the
		// extractor, surface the actual underlying error so the operator
		// (or support) can act on the real cause instead of debugging a
		// "no products visible" complaint that's actually billing/parse/
		// network. Only fall back to the generic message when the
		// extractor returned successfully but the page was genuinely blank.
		msg := "No product entries found in the register page image(s)"
		if extractErrCount > 0 && extractErrCount == len(req.Images) && lastExtractErr != nil {
			msg = fmt.Sprintf("Could not read the register photo (%s). Please retry or contact support.", lastExtractErr.Error())
			if len(msg) > 400 {
				msg = msg[:400] + "…"
			}
		}
		return &SmartStockSetupResult{
			Status:      "failed",
			Message:     msg,
			StockColumn: stockColumn,
			ProcessingDetails: &SmartStockSetupProcessing{
				OCRTimeMs:       ocrDuration,
				TotalTimeMs:     time.Since(totalStart).Milliseconds(),
				ImagesProcessed: len(req.Images),
				AIModel:         aiModel,
			},
		}, nil
	}

	// Step 2: Match extracted items against known products
	// Philosophy: Stock Setup is often FIRST TIME setup. Show RAW text from image.
	// User reviews and corrects. On Apply → products created/matched + aliases learned.
	// This makes Smart Sale smarter for all future operations.
	matchStart := time.Now()

	stockMap, err := s.purchaseService.loadStockLevels(tenantID, shopID)
	if err != nil {
		log.Printf("Smart Stock Setup: Failed to load stock levels: %v", err)
		stockMap = map[string]int{}
	}

	var matchedItems []SmartStockSetupExtractedItem
	matchedCount, lowConfCount, notFoundCount, autoCreatedCount := 0, 0, 0, 0

	// Build the per-brand sibling-token index ONCE up front. This drives the
	// dynamic flavour/variant guard so we don't need a hardcoded list per brand.
	brandSiblings := buildBrandSiblingIndex(products)
	log.Printf("Smart Stock Setup: built sibling index for %d brand families", len(brandSiblings))

	// v1.0.125 — load this shop's learned rate corrections so matchAndEnrich
	// can prefer them over AI rates that diverge >5%. Powers "fix it twice
	// → permanent" — once user has corrected a rate, future extractions on
	// the same shop+product use the learned rate as ground truth.
	learnedRates := s.loadShopLearnedRates(tenantID, shopID)
	if len(learnedRates) > 0 {
		log.Printf("Smart Stock Setup: loaded %d learned shop rates for shop=%s", len(learnedRates), shopID)
	}

	// v1.0.187 — load master meta_keywords (synonyms) for every product
	// linked to a saas_brand. Mirrors Smart Sale's loadExciseInfoMap; gives
	// the fuzzy matcher additional name forms so "MCD" → "Mc Dowells",
	// "OC" → "Officer's Choice", "M.M" → "M2 Magic Moments" all match
	// without requiring per-row alias learning. Empty for tenants whose
	// products aren't linked to master.
	productSynonyms := s.loadProductSynonyms(tenantID, products)
	if len(productSynonyms) > 0 {
		total := 0
		for _, kws := range productSynonyms {
			total += len(kws)
		}
		log.Printf("Smart Stock Setup: loaded %d meta_keywords across %d master-linked products", total, len(productSynonyms))
	}

	// v1.0.199 — load tenant-inventory stats once per run. Feeds the matcher's
	// TenantInventoryBias term so a sibling shop's stock/sales history tilts
	// the score toward "what this tenant actually stocks". Empty map when no
	// products to score; safe to pass through.
	tenantStats := s.loadTenantInventoryStats(tenantID, products)
	if len(tenantStats) > 0 {
		log.Printf("Smart Stock Setup: loaded tenant-inventory stats for %d products", len(tenantStats))
	}

	for _, extracted := range allExtracted {
		item := s.matchAndEnrich(extracted, products, stockMap, stockColumn, tenantID, shopID, masterBrands, brandSiblings, learnedRates, productSynonyms, tenantStats, categoryName, categoryNameByID)
		matchedItems = append(matchedItems, item)

		switch item.Status {
		case "matched":
			matchedCount++
		case "low_confidence", "ambiguous":
			lowConfCount++
		case "not_found", "auto_create":
			notFoundCount++
		}
	}
	matchDuration := time.Since(matchStart).Milliseconds()

	// v1.0.185 Track S5 — append brand / match-related cell doubts produced
	// by the matcher (low confidence, ambiguous, MRP-vs-master mismatch).
	// Runs as a post-pass so matchAndEnrich's 5 early-return paths don't each
	// need to know about doubt emission. Doubts already produced by the
	// Textract pipeline (low_confidence on numeric cells, math_disagree,
	// rate_outlier) are preserved.
	for i := range matchedItems {
		appendMatchCellDoubts(&matchedItems[i])
	}

	// Step 3: For unmatched items, try cross-category search then mark as auto_create.
	// Every item MUST appear in the result — user decides what to do.
	// The broad catalog is loaded once and reused across all rescue attempts (was N+1).
	//
	// MASTER-DATA ALIGNMENT: before trusting the rescue candidate, verify it points to
	// the same saas_brand (excise master) that the OCR text resolves to. This prevents
	// the rescue from "saving" a variant-rejected item by re-matching it to the same
	// wrong product (e.g. "Bacardi Limon Rum" being rescued to "Rockford Classic Whisky").
	sizeStr := fmt.Sprintf("%dML", sizeML)
	var broadProducts []dbProduct
	var broadPrepared []matching.PreparedProduct
	broadLoaded := false
	for i := range matchedItems {
		// Skip rows that already matched cleanly
		if matchedItems[i].Status != "not_found" &&
			!((matchedItems[i].Status == "low_confidence" || matchedItems[i].Status == "ambiguous") &&
				matchedItems[i].MatchConfidence < 0.8) {
			continue
		}

		extracted := allExtracted[i]
		officialName := extracted.OfficialBrandName
		if officialName == "" {
			officialName = extracted.Brand
		}
		if officialName == "" {
			officialName = "Unknown Brand"
		}

		// Look up master brand for this item — authoritative source of truth.
		// We use it both for alignment-checking a rescue and for auto_create display name.
		itemMaster := s.findMasterBrand(officialName, extracted.SizeML, extracted.Rate, masterBrands)
		// v1.0.249 — Close the category-gate hole. v247 added sameSpiritFamily()
		// to matchAndEnrich's fuzzy-rejection block, but the rescue path here
		// could STILL bring in a wrong-family master brand. Chhotu's row 35:
		// AI raw "Indri" (single-malt whisky) → findMasterBrand returned
		// "I Heart Riesling" (wine) for a 750ml whisky-page upload, and conf=0.70
		// labelled it as "Will be added from excise master catalog". Now we
		// reject the master before it taints the row.
		if itemMaster != nil && categoryName != "" && itemMaster.Category != "" &&
			!sameSpiritFamily(categoryName, itemMaster.Category) {
			log.Printf("Smart Stock Setup: Master DROPPED for row %d (page=%s, master=%s, family mismatch): \"%s\" → \"%s\"",
				matchedItems[i].RowNumber, categoryName, itemMaster.Category, officialName, itemMaster.DisplayName)
			itemMaster = nil
		}
		// v1.0.257 — OCR-TEXT spirit gate. The v247/v249 gates compare the
		// UPLOAD category vs the master; they pass when the operator picked a
		// broad / non-spirit category (familyOf→"other" ⇒ sameSpiritFamily
		// returns true). But the register text itself usually names the spirit
		// ("PM Rare WHISKY Green"), so reject a master in a conflicting family
		// regardless of the upload category. This is exactly chhotu's job
		// 17f7a3e5 row 1: OCR-garbled "8 PM Special Rare Whisky" ("Whisky"
		// survived) was rescued to "Moonwalk Green Apple VODKA" and
		// auto-created. Better an unmatched row the operator fixes than a
		// confidently-wrong cross-spirit SKU.
		if itemMaster != nil {
			ocrSpiritText := strings.TrimSpace(extracted.Brand + " " + extracted.OfficialBrandName + " " + officialName)
			masterSpiritText := itemMaster.DisplayName + " " + itemMaster.BrandName + " " + itemMaster.Category
			if !sameSpiritFamily(ocrSpiritText, masterSpiritText) {
				log.Printf("Smart Stock Setup: Master DROPPED for row %d (OCR-spirit mismatch): \"%s\" → \"%s\" (%s)",
					matchedItems[i].RowNumber, ocrSpiritText, itemMaster.DisplayName, itemMaster.Category)
				itemMaster = nil
			}
		}
		// v1.0.257 — distinctive-token guard (catches the case the spirit gate
		// cannot: mis-categorised catalog data). Refuse a rescue master that
		// shares NO distinctive token with the raw register brand. The row
		// then stays unmatched for the operator — now fixable in one shot via
		// the photo-verify name correction (v1.0.257 Fix C) instead of being
		// silently auto-created as the wrong SKU (chhotu's "8 PM" → Moonwalk).
		if itemMaster != nil {
			ocrName := strings.TrimSpace(extracted.Brand) // RAW AI read only — OfficialBrandName is the AI's cleaned guess (may already be the WRONG canonical)
			if !sharesDistinctiveToken(ocrName, itemMaster.DisplayName+" "+itemMaster.BrandName) {
				log.Printf("Smart Stock Setup: Master DROPPED for row %d (no distinctive-token overlap): \"%s\" → \"%s\"",
					matchedItems[i].RowNumber, ocrName, itemMaster.DisplayName)
				itemMaster = nil
			}
		}
		masterName := officialName
		masterBrandID := ""
		if itemMaster != nil {
			if itemMaster.DisplayName != "" {
				masterName = itemMaster.DisplayName
			} else if itemMaster.BrandName != "" {
				masterName = itemMaster.BrandName
			}
			masterBrandID = itemMaster.BrandID
		}

		// Variant-rejected items skip rescue entirely — their rejection was deliberate.
		// Fall through to auto_create (with authoritative master name when available).
		if matchedItems[i].variantRejected {
			log.Printf("Smart Stock Setup: Rescue SKIPPED for row %d (variant_rejected): \"%s\"",
				matchedItems[i].RowNumber, officialName)
		} else {
			// Lazy-load the broad catalog on first rescue attempt (skip entirely if no rescues needed)
			if !broadLoaded {
				broadProducts, broadPrepared = s.buildBroadCatalog(tenantID, shopID)
				broadLoaded = true
				log.Printf("Smart Stock Setup: Broad catalog loaded for cross-category rescue (%d products)", len(broadProducts))
			}

			crossMatch := s.searchAllProductsForBrandSize(officialName, extracted.SizeML, broadProducts, broadPrepared)

			// Master-alignment check: if we know what excise brand this item is (via master),
			// the rescue candidate must link to the SAME excise brand. Otherwise reject
			// the rescue — it's a cross-brand collision, not a legitimate cross-category hit.
			if crossMatch != nil && masterBrandID != "" && crossMatch.SaasBrandID != masterBrandID {
				log.Printf("Smart Stock Setup: Rescue REJECTED row %d: candidate saas_brand %s ≠ master %s (\"%s\")",
					matchedItems[i].RowNumber, crossMatch.SaasBrandID, masterBrandID, masterName)
				crossMatch = nil
			}
			// v1.0.249 — Same category check for the rescued tenant product.
			// Even if the SaaS-brand aligns, the product itself could be in a
			// wrong-family catalog. Belt-and-braces with the page category.
			if crossMatch != nil && categoryName != "" && crossMatch.CategoryID != "" {
				prodCat := categoryNameByID[crossMatch.CategoryID]
				if prodCat != "" && !sameSpiritFamily(categoryName, prodCat) {
					log.Printf("Smart Stock Setup: Rescue REJECTED row %d (page=%s, product=%s family mismatch): \"%s\" → \"%s\"",
						matchedItems[i].RowNumber, categoryName, prodCat, officialName, crossMatch.Name)
					crossMatch = nil
				}
			}
			// v1.0.257 — OCR-TEXT spirit gate for the rescued tenant product
			// too (mirrors the master gate above; upload-category-config
			// independent). Stops "…Whisky…" register text linking to a
			// Vodka/Rum/Wine product just because a generic token ("Green")
			// plus shop-stock bias collided.
			if crossMatch != nil {
				ocrSpiritText := strings.TrimSpace(extracted.Brand + " " + extracted.OfficialBrandName + " " + officialName)
				if !sameSpiritFamily(ocrSpiritText, crossMatch.Name) {
					log.Printf("Smart Stock Setup: Rescue REJECTED row %d (OCR-spirit mismatch): \"%s\" → \"%s\"",
						matchedItems[i].RowNumber, ocrSpiritText, crossMatch.Name)
					crossMatch = nil
				}
			}
			// v1.0.257 — distinctive-token guard for the rescued tenant product
			// (mirrors the master guard; defeats mis-categorised catalog rows
			// the spirit gate cannot see).
			if crossMatch != nil {
				ocrName := strings.TrimSpace(extracted.Brand) // RAW AI read only — OfficialBrandName is the AI's cleaned guess (may already be the WRONG canonical)
				if !sharesDistinctiveToken(ocrName, crossMatch.Name) {
					log.Printf("Smart Stock Setup: Rescue REJECTED row %d (no distinctive-token overlap): \"%s\" → \"%s\"",
						matchedItems[i].RowNumber, ocrName, crossMatch.Name)
					crossMatch = nil
				}
			}

			if crossMatch != nil {
				display, full := resolveDisplayAndFullName(crossMatch)
				matchedItems[i].ProductID = &crossMatch.ID
				matchedItems[i].MatchedDisplayName = display
				matchedItems[i].MatchedDisplayNameBoldStart = crossMatch.DisplayNameBoldStart
				matchedItems[i].MatchedDisplayNameBoldLength = crossMatch.DisplayNameBoldLength
				matchedItems[i].MatchedFullName = full
				matchedItems[i].MatchedBrandName = display // backwards compat
				matchedItems[i].BrandName = display        // v1.0.258 — displayed brand = the rescued product, not the rejected primary candidate
				matchedItems[i].MatchedExciseBrandName = crossMatch.ExciseBrandName
				if crossMatch.ExciseDisplayName != "" {
					matchedItems[i].MatchedExciseDisplayName = crossMatch.ExciseDisplayName
				} else if crossMatch.ExciseBrandName != "" {
					matchedItems[i].MatchedExciseDisplayName = shortenForDisplay(crossMatch.ExciseBrandName)
				}
				matchedItems[i].MatchConfidence = 0.90
				matchedItems[i].Status = "matched"
				matchedItems[i].OfficialBrandName = officialName
				if stock, ok := stockMap[crossMatch.ID]; ok {
					matchedItems[i].CurrentStock = &stock
				}
				log.Printf("Smart Stock Setup: Cross-category rescue row %d: \"%s\" → \"%s\" (master-aligned)",
					matchedItems[i].RowNumber, officialName, display)
				notFoundCount--
				matchedCount++
				continue
			}
		}

		// Auto-match suppression for low-confidence trailing handwritten rows.
		// If the OCR confidence is low AND the row sits in the trailing part of
		// the page AND the AI didn't suggest any product, refuse to auto-create
		// — the AI's brand guess is likely a hallucination (see the v1.0.88 row
		// 43 "Smoke Lab Classic" case where a rate-isolated handwritten "Gold
		// Label" got a fabricated brand that would have become a real SKU).
		// The row stays as a needs_review entry with no product_id so the user
		// MUST explicitly pick a master brand or manually add the product.
		page := matchedItems[i].PageNumber
		rowN := matchedItems[i].RowNumber
		pageRowCount := 0
		if page > 0 && page-1 < len(pageRowCounts) {
			pageRowCount = pageRowCounts[page-1]
		}
		trailing := pageRowCount > 0 && rowN > 0 && float64(rowN) > 0.70*float64(pageRowCount)
		if extracted.Confidence > 0 && extracted.Confidence < 0.75 && trailing && extracted.MatchedProductIdx == 0 {
			matchedItems[i].Status = "needs_review"
			matchedItems[i].ProductID = nil
			matchedItems[i].AutoCreated = false
			matchedItems[i].CreationStatus = ""
			matchedItems[i].MatchConfidence = 0.0
			matchedItems[i].NeedsReview = true
			matchedItems[i].ReviewReason = "Low-confidence handwritten row — pick a master brand (AI's guess may be wrong)"
			// Clear OfficialBrandName so the apply path (line 3096 check) will
			// SKIP this row unless the user explicitly picks a master brand or
			// types a replacement. Without this, a hallucinated name like
			// "Smoke Lab Classic" would still get created on apply because
			// apply only checks whether OfficialBrandName or BrandName is set.
			// We keep MatchedExciseBrandName cleared and strip the matched
			// display name back to the raw OCR so the user sees exactly what
			// the AI read (not the auto-matched product name).
			matchedItems[i].OfficialBrandName = ""
			matchedItems[i].MatchedDisplayName = extracted.Brand
			matchedItems[i].MatchedFullName = ""
			matchedItems[i].MatchedBrandName = extracted.Brand
			matchedItems[i].BrandName = extracted.Brand // v1.0.258 — show the AI read, not a stale rejected match
			matchedItems[i].MatchedExciseBrandName = ""
			matchedItems[i].MatchedExciseDisplayName = ""
			// Still attach master-brand suggestions so the user has a dropdown
			// of likely matches to pick from, instead of having to type.
			matchedItems[i].MasterBrandSuggestions = s.findMasterBrandCandidates(
				extracted.Brand, extracted.SizeML, extracted.Rate, masterBrands, 5)
			matchedItems[i].Warnings = append(matchedItems[i].Warnings,
				fmt.Sprintf("Handwritten confidence %.2f — AI read '%s', please confirm or pick from master",
					extracted.Confidence, extracted.Brand))
			log.Printf("Smart Stock Setup: row %d/p%d auto-match SUPPRESSED (conf=%.2f, trailing=%.0f%%) — keeping as needs_review",
				rowN, page, extracted.Confidence, float64(rowN)/float64(pageRowCount)*100)
			continue
		}

		// Not found (or rescue rejected / skipped) — mark as auto_create with metadata
		// for deferred creation on Apply. Use master brand's authoritative display name
		// when available so the new product is created with the right name.
		creationName := masterName
		matchedItems[i].Status = "auto_create"
		matchedItems[i].ProductID = nil // No product_id — will be created on Apply
		matchedItems[i].AutoCreated = true
		matchedItems[i].OfficialBrandName = creationName
		// v1.0.258 — RESET the displayed brand. matchAndEnrich's primary fuzzy
		// attempt sets item.BrandName to the candidate it tried; when the
		// variant/spirit/distinctive guards (incl. v257 Fix B) reject that
		// candidate and the row drops to auto_create, BrandName was NEVER
		// reset — so the review screen kept showing the REJECTED product
		// (chhotu's "Moonwalk Green Apple" / "Royal Black Reserve" / "Mc
		// Dowells…" for 8 PM / MCD rows). The displayed name must be the
		// authoritative master/AI name (creationName), never a rejected
		// fuzzy hit. This also de-biases the photo-verify: Flutter sends
		// rawBrandName (= this brand_name) as the Gemini hint, so a correct
		// hint now stops the verifier from "confirming" the wrong brand.
		matchedItems[i].BrandName = creationName
		matchedItems[i].NeedsReview = true

		// v1.0.247 — Master-catalog auto-onboard: when itemMaster is non-nil,
		// we have a confident excise-master hit for the OCR'd brand. The apply
		// path will create a new shop product linked to this master (via
		// findOrCreateProduct's saas_brand_id propagation at lines 4800+).
		// Surface this confidence to the operator: bump match_confidence
		// 0.0 → 0.70 so the row reads as "we know what this is, just adding
		// it to your shop" instead of the alarming "match_confidence 0%". The
		// row still goes to NeedsReview so the operator sanity-checks size +
		// rate before approving — we're not auto-approving, just signaling
		// where the confidence actually lies. Solves chhotu's "Ballantines /
		// Jameson / Monkey Shoulder all showing as 0% auto_create" complaint.
		if itemMaster != nil {
			matchedItems[i].MatchConfidence = 0.70
		} else {
			matchedItems[i].MatchConfidence = 0.0
		}

		// Attach master-brand suggestions so Flutter can render a dropdown.
		// E.g. for "1965 Ram" this gives the user the 10 "1965 Spirit of Victory"
		// variants instead of forcing them to type the brand name from scratch.
		matchedItems[i].MasterBrandSuggestions = s.findMasterBrandCandidates(
			officialName, extracted.SizeML, extracted.Rate, masterBrands, 5)

		if itemMaster != nil {
			matchedItems[i].ReviewReason = fmt.Sprintf("Will be added to your shop from excise master catalog (%s) — verify size + MRP", masterName)
		} else if len(matchedItems[i].MasterBrandSuggestions) > 0 {
			matchedItems[i].ReviewReason = fmt.Sprintf("Partial excise match — pick from %d suggested brand(s) or add new",
				len(matchedItems[i].MasterBrandSuggestions))
		} else {
			matchedItems[i].ReviewReason = "Not recognized in excise master — verify spelling before adding"
		}
		matchedItems[i].MatchedDisplayName = creationName
		matchedItems[i].MatchedFullName = fmt.Sprintf("%s - %s", creationName, sizeStr)
		matchedItems[i].MatchedBrandName = matchedItems[i].MatchedFullName // backwards compat
		matchedItems[i].CreationStatus = "pending"

		// Surface excise name + bold range on auto_create too — when master brand
		// resolved, use its authoritative name/display so Flutter shows the official
		// excise alongside the AI's best guess and renders the bold portion.
		if itemMaster != nil {
			matchedItems[i].MatchedExciseBrandName = itemMaster.BrandName
			if itemMaster.DisplayName != "" {
				matchedItems[i].MatchedExciseDisplayName = itemMaster.DisplayName
			} else {
				matchedItems[i].MatchedExciseDisplayName = shortenForDisplay(itemMaster.BrandName)
			}
			matchedItems[i].MatchedDisplayNameBoldStart = itemMaster.DisplayNameBoldStart
			matchedItems[i].MatchedDisplayNameBoldLength = itemMaster.DisplayNameBoldLength
		}
		if extracted.Category != "" {
			matchedItems[i].Category = extracted.Category
		}

		autoCreatedCount++
		notFoundCount--
	}

	// Renumber items sequentially (1 to N)
	for i := range matchedItems {
		matchedItems[i].RowNumber = i + 1
	}

	// Auto-resolve duplicate matches — when multiple rows picked the same product,
	// keep the highest-confidence row and reassign the others to their best remaining
	// AlternativeMatch (if that alternative's score is reasonable). This prevents the
	// "two rows matched to the same product" duplicate situation from reaching the
	// review screen when a good alternative exists for the loser.
	s.autoResolveDuplicateMatches(matchedItems)

	// Flag items that need user review
	s.flagItemsForReview(matchedItems)

	// Suggested stock column
	suggestedColumn := ""
	if stockColumn == "total" {
		allReceiptZero := true
		hasOpening := false
		for _, item := range allExtracted {
			if item.Receipt != 0 {
				allReceiptZero = false
				break
			}
			if item.Opening > 0 {
				hasOpening = true
			}
		}
		if allReceiptZero && hasOpening {
			suggestedColumn = "opening"
		}
	}

	// Build response
	status := "success"
	var warnings []string
	if notFoundCount > 0 {
		status = "partial"
		warnings = append(warnings, fmt.Sprintf("%d item(s) not found in inventory", notFoundCount))
	}
	if lowConfCount > 0 {
		status = "partial"
		warnings = append(warnings, fmt.Sprintf("%d item(s) need confirmation", lowConfCount))
	}
	if autoCreatedCount > 0 {
		warnings = append(warnings, fmt.Sprintf("%d product(s) auto-created", autoCreatedCount))
	}
	// v1.0.288 — Size-mismatch warning (new "keep-and-warn" behavior, see filter
	// block above). When the AI read a different size header than the user selected,
	// we now KEEP the rows tagged with the user-selected size. Warn the user
	// prominently so they can verify those specific rows before saving — the AI
	// might be right (wrong page uploaded) or wrong (misread header on a valid
	// continuation page); the user can tell which.
	if len(sizeMismatchSkippedPages) > 0 {
		status = "partial"
		for _, sp := range sizeMismatchSkippedPages {
			label := fmt.Sprintf("%dML", sp.DetectedSizeML)
			if sp.DetectedSize != "" {
				label = sp.DetectedSize
			}
			warnings = append(warnings, fmt.Sprintf(
				"Photo %d header looked like %s but you selected %dML — %d row(s) kept with your selected size. Please verify those rows before saving.",
				sp.PageNumber, label, sizeML, sp.SkippedCount))
		}
	}
	// v1.0.288 — Zero-row page detection. After all OCR passes + page-rescue +
	// handwritten-pass have run, count rows per uploaded image. Any page that
	// produced ZERO rows in the final result almost always means the extraction
	// service failed (OpenAI 429 + Gemini truncated-JSON cascade we observed in
	// job 07ceace7), not that the user uploaded a blank page. Surface this so
	// they re-upload that specific photo rather than wondering why item counts
	// look wrong. Without this the failure is silent — the page silently
	// disappears and the user can't tell whether AI missed it or the photo was bad.
	if len(req.Images) > 1 {
		pageRowCountsFinal := make([]int, len(req.Images))
		for _, item := range matchedItems {
			if item.PageNumber >= 1 && item.PageNumber <= len(pageRowCountsFinal) {
				pageRowCountsFinal[item.PageNumber-1]++
			}
		}
		for i, c := range pageRowCountsFinal {
			if c == 0 {
				status = "partial"
				warnings = append(warnings, fmt.Sprintf(
					"Photo %d couldn't be read — the extraction service failed for this image. Please re-upload Photo %d on its own and try again.",
					i+1, i+1))
				log.Printf("Smart Stock Setup: zero-row page %d detected — extraction fallback chain exhausted", i+1)
			}
		}
	}

	// Compute extraction quality metrics per-image and overall
	firstSetup := len(products) == 0
	var avgConfidence float64
	var qualityWarning string
	var lowQualityImages []int

	if len(allExtracted) > 0 {
		totalConf := 0.0
		for _, ext := range allExtracted {
			totalConf += ext.Confidence
		}
		avgConfidence = totalConf / float64(len(allExtracted))

		// Per-page quality: compute avg confidence by indexing into allExtracted
		// via PageNumber (stamped at L346/L354 above). v1.0.114 replaces the
		// previous moving-cursor approach which was bug-prone — the cursor
		// silently skipped pages with empty results AND assumed
		// len(allExtracted) == Σ len(ir.result.Items), which breaks once
		// phantom-row suppression, size filtering, or page-rescue mutate
		// allExtracted between extraction and this gate.
		pageConfSum := make(map[int]float64, len(req.Images))
		pageConfCount := make(map[int]int, len(req.Images))
		for _, ext := range allExtracted {
			pageConfSum[ext.PageNumber] += ext.Confidence
			pageConfCount[ext.PageNumber]++
		}
		for p := 1; p <= len(req.Images); p++ {
			n := pageConfCount[p]
			if n == 0 {
				continue
			}
			if pageConfSum[p]/float64(n) < 0.65 {
				lowQualityImages = append(lowQualityImages, p)
			}
		}

		if avgConfidence > 0 && avgConfidence < 0.6 {
			qualityWarning = "Image quality is low — consider re-taking photos with full page visible and better lighting"
		} else if avgConfidence > 0 && avgConfidence < 0.7 {
			qualityWarning = "Some items may be inaccurately read — please review carefully"
		}
		if len(lowQualityImages) > 0 && qualityWarning == "" {
			qualityWarning = fmt.Sprintf("Image %v has low readability (heavy ink/cropped edges) — consider re-taking", lowQualityImages)
		}
	}

	// Gate auto_create on low-quality source pages. An illegible page is the most
	// common source of brand hallucinations ("Monkey Shoulder" → "Eden Blended Malt")
	// that would silently become new SKUs on apply. Demote such items to needs_review
	// so the user verifies before we create anything.
	if len(lowQualityImages) > 0 {
		lowQualPages := make(map[int]struct{}, len(lowQualityImages))
		for _, p := range lowQualityImages {
			lowQualPages[p] = struct{}{}
		}
		for i := range matchedItems {
			if matchedItems[i].Status == "auto_create" {
				if _, bad := lowQualPages[matchedItems[i].PageNumber]; bad {
					matchedItems[i].AutoCreated = false
					matchedItems[i].Status = "needs_review"
					matchedItems[i].CreationStatus = ""
					matchedItems[i].NeedsReview = true
					if matchedItems[i].ReviewReason == "" || strings.Contains(matchedItems[i].ReviewReason, "verify before adding") {
						matchedItems[i].ReviewReason = "Source image was low quality — verify brand name before creating as new product"
					}
				}
			}
		}
	}

	// v1.0.134 Track C — weak-signal auto_create demotion. When the AI proposes
	// a NEW product (auto_create) but the row has too little corroborating
	// signal, demote to needs_review so the operator confirms instead of
	// silently creating a SKU. "Weak signal" = brand <8 chars OR fewer than 2
	// of {opening, receipt, closing, rate} are non-zero. This kills the ghost
	// auto_create rows that were the dominant over-prediction class on
	// Trinken's 180/375/750 ml jobs.
	autoCreateDemoted := 0
	for i := range matchedItems {
		if matchedItems[i].Status != "auto_create" {
			continue
		}
		brandLen := len([]rune(strings.TrimSpace(matchedItems[i].BrandName)))
		nonZero := 0
		if matchedItems[i].Opening > 0 {
			nonZero++
		}
		if matchedItems[i].Receipt > 0 {
			nonZero++
		}
		if matchedItems[i].ClosingStock > 0 {
			nonZero++
		}
		if matchedItems[i].Rate > 0 {
			nonZero++
		}
		if brandLen < 8 || nonZero < 2 {
			matchedItems[i].AutoCreated = false
			matchedItems[i].Status = "needs_review"
			matchedItems[i].CreationStatus = ""
			matchedItems[i].NeedsReview = true
			matchedItems[i].ReviewReason = fmt.Sprintf(
				"Weak auto-create signal (brand=%dch, %d/4 non-zero) — confirm before adding as new product",
				brandLen, nonZero)
			autoCreateDemoted++
		}
	}
	if autoCreateDemoted > 0 {
		log.Printf("Smart Stock Setup: weak-signal gate demoted %d auto_create rows to needs_review", autoCreateDemoted)
	}

	// Recompute status counts from final matchedItems — the incremental counters
	// during rescue/auto-create passes can drift negative (e.g. a "low_confidence"
	// row that gets rescued decrements notFoundCount even though it was originally
	// counted in lowConfCount), producing nonsense values like "-3 not found" in
	// the client response. Single pass at the end is the source of truth.
	matchedCount, lowConfCount, notFoundCount, autoCreatedCount = 0, 0, 0, 0
	for _, mi := range matchedItems {
		switch mi.Status {
		case "matched":
			matchedCount++
		case "low_confidence", "ambiguous":
			lowConfCount++
		case "auto_create":
			autoCreatedCount++
		case "not_found", "needs_review":
			notFoundCount++
		}
	}

	message := fmt.Sprintf("Extracted %d items from register", len(matchedItems))
	if firstSetup {
		message = fmt.Sprintf("First-time setup: extracted %d items — all will be created as new products", len(matchedItems))
	} else if matchedCount < len(matchedItems) {
		message += fmt.Sprintf(" (%d matched, %d need review, %d not found)", matchedCount, lowConfCount, notFoundCount)
	}
	if autoCreatedCount > 0 {
		message += fmt.Sprintf(" [%d new products]", autoCreatedCount)
	}
	if qualityWarning != "" {
		warnings = append(warnings, qualityWarning)
	}

	// Populate MasterMRP / MasterVariantID on matched items so the review card
	// can show the authoritative catalog price next to the tenant MRP and offer
	// a one-tap "use master" correction. Key by (brand_id, uppercase size).
	//
	// Source of saas_brand_id: the matched tenant product (dbProduct.SaasBrandID).
	// When the tenant product isn't linked to master, we leave the fields empty
	// and the card renders unchanged.
	{
		prodByID := make(map[string]*dbProduct, len(products))
		for i := range products {
			prodByID[products[i].ID] = &products[i]
		}
		masterByKey := make(map[string]*models.MasterBrandInfo, len(masterBrands))
		for i := range masterBrands {
			mb := &masterBrands[i]
			k := mb.BrandID + "|" + strings.ToUpper(strings.TrimSpace(mb.Size))
			if _, dup := masterByKey[k]; !dup {
				masterByKey[k] = mb
			}
		}
		for i := range matchedItems {
			it := &matchedItems[i]
			if it.ProductID == nil || *it.ProductID == "" {
				continue
			}
			p := prodByID[*it.ProductID]
			if p == nil || p.SaasBrandID == "" {
				continue
			}
			sizeKey := strings.ToUpper(strings.TrimSpace(it.Size))
			if sizeKey == "" {
				sizeKey = strings.ToUpper(strings.TrimSpace(p.Size))
			}
			if mb := masterByKey[p.SaasBrandID+"|"+sizeKey]; mb != nil {
				it.MasterMRP = mb.MRP
				it.MasterVariantID = mb.VariantID
				// v1.0.120: master-MRP drift guard. When AI extracted a rate
				// that disagrees with the catalog master MRP by >10%, flag the
				// row for review. Catches the row 49 100 STROKES case where AI
				// bled ₹720 from the row above into a row whose true rate is
				// ₹620 (master MRP). The amber chip + warning forces the user
				// to verify the cell before approval.
				if it.Rate > 0 && mb.MRP > 0 {
					ratio := it.Rate / mb.MRP
					if ratio < 0.90 || ratio > 1.10 {
						warn := fmt.Sprintf("⚠️ Rate ₹%.0f differs from master MRP ₹%.0f by %.0f%% — verify (possible rate-bleed from adjacent row)",
							it.Rate, mb.MRP, abs(ratio-1.0)*100)
						it.Warnings = append(it.Warnings, warn)
						it.NeedsReview = true
						if it.ReviewReason == "" {
							it.ReviewReason = "Rate diverges from master MRP — verify"
						}
						if it.FieldConfidence == nil {
							it.FieldConfidence = map[string]float64{}
						}
						// Force "rate" cell into amber zone so Flutter renders the underline.
						if cur, ok := it.FieldConfidence["rate"]; !ok || cur > 0.6 {
							it.FieldConfidence["rate"] = 0.5
						}
					}
				}
			}
		}
	}

	// Only show what was extracted from the register image.
	// No separate products grid — keeps it clean for all tenants/shops.
	var allProducts []StockSetupProductInfo // empty — Flutter shows only extracted items

	// Build filter context
	var filterContext *StockSetupFilterContext
	if req.CategoryID != "" || req.Size != "" {
		filterContext = &StockSetupFilterContext{
			CategoryID:   req.CategoryID,
			CategoryName: categoryName,
			Size:         req.Size,
			SizeML:       sizeML,
			ProductCount: len(products),
		}
	}

	// Build per-page coverage summary (v1.0.114). Only emitted for pages where
	// either page-rescue or handwritten-pass actually ran, so 180/375ML success
	// jobs (the common case) carry an empty summary and Flutter renders no
	// banner. Counts are computed against the FINAL allExtracted so the user
	// sees the post-recovery row count.
	finalPageCount := make(map[int]int, len(req.Images))
	for _, ext := range allExtracted {
		finalPageCount[ext.PageNumber]++
	}
	var coverageSummary []PageCoverage
	for i := range req.Images {
		pageNum := i + 1
		if !pageRescueTriggered[i] && !handwrittenPassPerPage[i] {
			continue
		}
		recoveredVia := ""
		switch {
		case pageRescueTriggered[i] && handwrittenPassPerPage[i]:
			recoveredVia = "page_rescue+handwritten_pass"
		case pageRescueTriggered[i]:
			recoveredVia = "page_rescue"
		case handwrittenPassPerPage[i]:
			recoveredVia = "handwritten_pass"
		}
		coverageSummary = append(coverageSummary, PageCoverage{
			PageNumber:      pageNum,
			Expected:        pageRowCounts[i],
			ActualBefore:    pageActualBeforeRescue[i],
			ActualAfter:     finalPageCount[pageNum],
			RescueTriggered: pageRescueTriggered[i],
			RecoveredVia:    recoveredVia,
		})
	}

	result := &SmartStockSetupResult{
		SessionID:            sessionID,
		Status:               status,
		Message:              message,
		DetectedShopName:     detectedShopName,
		StockColumn:          stockColumn,
		SuggestedStockColumn: suggestedColumn,
		Items:                matchedItems,
		ProcessingDetails: &SmartStockSetupProcessing{
			OCRTimeMs:       ocrDuration,
			MatchingTimeMs:  matchDuration,
			TotalTimeMs:     time.Since(totalStart).Milliseconds(),
			ImagesProcessed: len(req.Images),
			AIModel:         aiModel,
		},
		Validation: &SmartStockSetupValidation{
			TotalItems:         len(matchedItems),
			MatchedItems:       matchedCount,
			LowConfidenceItems: lowConfCount,
			NotFoundItems:      notFoundCount,
			AutoCreatedItems:   autoCreatedCount,
			Warnings:           warnings,
			AverageConfidence:  avgConfidence,
			QualityWarning:     qualityWarning,
			LowQualityImages:   lowQualityImages,
			FirstSetup:         firstSetup,
		},
		FilterContext: filterContext,
		AllProducts:   allProducts,
		ImageURLs:    savedImageURLs,
		PageRowCounts: pageRowCounts,
		CoverageSummary: coverageSummary,
		Audit:         buildExtractionAudit(products, matchedItems, masterBrands, sizeML),
		SizeMismatchSkippedPages: sizeMismatchSkippedPages,
	}

	if result.Audit != nil {
		log.Printf("Smart Stock Setup: data-hygiene audit — %d orphan tenant products (no saas_brand_id), %d OCR brands missing from master catalog: %v",
			len(result.Audit.OrphanProducts), len(result.Audit.MissingMasterBrands), result.Audit.MissingMasterBrands)
	}

	// Save matched result for training data
	SaveMatchedResult(req.TenantID, sessionID, result)

	return result, nil
}

// flagItemsForReview marks items that need user attention in the Flutter UI.
// This runs AFTER all matching and auto-creation is complete.
// addMissingProducts detects known products that NO AI row matched and adds them
// as flagged items. This guarantees the user sees every product in the scoped
// category+size, even if the AI missed/skipped a register row.
func (s *SmartStockSetupService) addMissingProducts(items []SmartStockSetupExtractedItem, products []dbProduct, stockMap map[string]int, stockColumn string) []SmartStockSetupExtractedItem {
	if len(products) == 0 {
		return items
	}

	// Build set of product IDs already matched by AI rows
	matchedPIDs := make(map[string]bool)
	for _, item := range items {
		if item.ProductID != nil {
			matchedPIDs[*item.ProductID] = true
		}
	}

	// Find products NOT matched by any AI row
	nextRow := len(items) + 1
	missingCount := 0
	for _, p := range products {
		if matchedPIDs[p.ID] {
			continue
		}

		stock := 0
		if st, ok := stockMap[p.ID]; ok {
			stock = st
		}

		// Only add missing products that have existing stock > 0
		// Products with 0 stock that aren't in the register are noise
		if stock == 0 {
			continue
		}

		pid := p.ID
		display, full := resolveDisplayAndFullName(&p)
		missing := SmartStockSetupExtractedItem{
			RowNumber:          nextRow,
			BrandName:          p.BrandName,
			Size:               p.Size,
			SizeML:              normalizeSizeText(p.Size),
			Rate:               effectiveMRP(p),
			StockQuantity:      0, // user must fill in
			ProductID:          &pid,
			MatchedDisplayName: display,
			MatchedFullName:    full,
			MatchedBrandName:   display, // backwards compat
			MatchConfidence:    0,
			Status:             "missing",
			OfficialBrandName:  p.BrandName,
			CurrentStock:       &stock,
			NeedsReview:        true,
			ReviewReason:       "Not found in register image — enter stock if this product exists",
		}

		items = append(items, missing)
		nextRow++
		missingCount++
	}

	if missingCount > 0 {
		log.Printf("Smart Stock Setup: Added %d missing products for user review", missingCount)
	}

	return items
}

// autoResolveDuplicateMatches prevents two rows from pointing to the same product_id.
// For each product with multiple matched rows, the highest-confidence row keeps the
// match; the other rows fall back to their best AlternativeMatch that isn't already taken.
// If no usable alternative exists, the row is demoted to "not_found" so the user picks.
// The alternative_matches list is updated to drop the now-used product.
func (s *SmartStockSetupService) autoResolveDuplicateMatches(items []SmartStockSetupExtractedItem) {
	// Run multiple passes — reassigning an item may free a product that creates a new duplicate
	// elsewhere (unlikely but possible). Cap at N passes to guarantee termination.
	for pass := 0; pass < 3; pass++ {
		// Group matched rows by product_id
		groups := make(map[string][]int)
		for i := range items {
			if items[i].ProductID != nil && (items[i].Status == "matched" ||
				items[i].Status == "low_confidence" || items[i].Status == "ambiguous") {
				groups[*items[i].ProductID] = append(groups[*items[i].ProductID], i)
			}
		}

		changed := false
		// Reserved set of product_ids that are already claimed by some (kept) row
		reserved := make(map[string]bool)
		for pid, idxs := range groups {
			if len(idxs) <= 1 {
				reserved[pid] = true
				continue
			}
			// Sort by confidence descending, ties go to the lower row number (earlier row wins)
			best := idxs[0]
			for _, idx := range idxs[1:] {
				if items[idx].MatchConfidence > items[best].MatchConfidence ||
					(items[idx].MatchConfidence == items[best].MatchConfidence && items[idx].RowNumber < items[best].RowNumber) {
					best = idx
				}
			}
			reserved[pid] = true
			// Reassign all other rows in this group
			for _, idx := range idxs {
				if idx == best {
					continue
				}
				s.reassignToAlternative(&items[idx], reserved)
				changed = true
			}
		}
		if !changed {
			return
		}
	}
}

// reassignToAlternative picks the highest-scoring alternative whose product_id is not
// already taken. Falls back to "not_found" if nothing usable remains.
func (s *SmartStockSetupService) reassignToAlternative(item *SmartStockSetupExtractedItem, reserved map[string]bool) {
	// Re-apply the label-color + family-root guards on each alternative so the
	// reassignment can't silently reintroduce a cross-family misread that the
	// extraction-time guard would have rejected. Without this check, a duplicate
	// "Johnnie Walker Black Label" match would fall back to "8 PM Premium Black
	// Superior" (both contain "black" but different families) at score 0.50.
	sourceLower := strings.ToLower(item.BrandName + " " + item.OfficialBrandName)
	srcHasColor := labelColorIn(sourceLower) != ""
	var srcRoots map[string]struct{}
	if srcHasColor {
		srcRoots = familyRootTokens(sourceLower)
	}
	altBlocked := func(altName string) bool {
		candLower := strings.ToLower(altName)
		if hasLabelColorConflict(sourceLower, candLower) {
			return true
		}
		if srcHasColor && len(srcRoots) > 0 {
			candRoots := familyRootTokens(candLower)
			for t := range srcRoots {
				if _, ok := candRoots[t]; ok {
					return false
				}
			}
			return true // no shared family root with a same-family color src
		}
		// Flavor / variant distinguisher guard — same static list the
		// extraction-time fuzzy guard uses. Without this, autoResolve was
		// reassigning "M2 Orange" → "Magic Movement Jamun" (chhotu d982ade6
		// row 15) and "M2 Jamun Spicymint" → "M2 Cranberry Tease" (row 37)
		// because the alternatives carried mismatched flavor tokens that
		// the label-color/family check above ignores.
		distinguishers := []string{
			"green apple", "orange", "cranberry", "jamun", "lemon", "limon",
			"mango", "coffee", "spiced", "barrel select", "double dark",
			"reserve collection", "legend", "matured", "premium black", "triple gold",
			"100 strokes", "100 pipers", "old monk", "bacardi",
			"watermelon", "litchi", "verve", "pineapple", "chocolate", "cola",
			"spicymint", "m2", "remix",
		}
		for _, d := range distinguishers {
			if strings.Contains(sourceLower, d) != strings.Contains(candLower, d) {
				return true
			}
		}
		return false
	}

	var pickIdx = -1
	var pickScore float64
	for i, alt := range item.AlternativeMatches {
		if reserved[alt.ProductID] {
			continue
		}
		// Require reasonable score — don't replace a legitimate match with noise
		if alt.Confidence < 0.50 {
			continue
		}
		// Family-root / label-color guard — same check the extraction-time
		// matcher uses. Skips bad same-color-different-family alternatives.
		altFullName := alt.BrandName + " " + alt.DisplayName + " " + alt.FullName
		if altBlocked(altFullName) {
			log.Printf("SmartStockSetup: Reassign candidate '%s' REJECTED (label/family guard) for row %d",
				alt.BrandName, item.RowNumber)
			continue
		}
		if alt.Confidence > pickScore {
			pickScore = alt.Confidence
			pickIdx = i
		}
	}

	if pickIdx < 0 {
		// No good alternative — demote to not_found so user picks
		originalPid := ""
		if item.ProductID != nil {
			originalPid = *item.ProductID
		}
		item.ProductID = nil
		item.MatchedBrandName = ""
		item.MatchedDisplayName = ""
		item.MatchedDisplayNameBoldStart = nil
		item.MatchedDisplayNameBoldLength = nil
		item.MatchedFullName = ""
		item.MatchConfidence = 0
		item.Status = "not_found"
		item.Warnings = append(item.Warnings,
			"Duplicate match removed — another row matched the same product higher; please pick the correct one")
		log.Printf("SmartStockSetup: Reassign row %d: no alternative available (was product_id=%s)",
			item.RowNumber, originalPid)
		return
	}

	alt := item.AlternativeMatches[pickIdx]
	pid := alt.ProductID
	item.ProductID = &pid
	item.MatchedDisplayName = firstNonEmpty(alt.DisplayName, alt.BrandName)
	item.MatchedDisplayNameBoldStart = alt.DisplayNameBoldStart
	item.MatchedDisplayNameBoldLength = alt.DisplayNameBoldLength
	item.MatchedFullName = firstNonEmpty(alt.FullName, alt.BrandName)
	item.MatchedBrandName = item.MatchedDisplayName
	item.MatchConfidence = clampConfidence(alt.Confidence)
	reserved[pid] = true
	if alt.Confidence >= 0.8 {
		item.Status = "matched"
	} else {
		item.Status = "low_confidence"
	}
	// Remove the chosen alternative and any that are reserved
	filtered := item.AlternativeMatches[:0]
	for i, a := range item.AlternativeMatches {
		if i == pickIdx || reserved[a.ProductID] {
			continue
		}
		filtered = append(filtered, a)
	}
	item.AlternativeMatches = filtered
	log.Printf("SmartStockSetup: Reassign row %d → %s (score=%.2f) to avoid duplicate",
		item.RowNumber, item.MatchedDisplayName, alt.Confidence)
}

func (s *SmartStockSetupService) flagItemsForReview(items []SmartStockSetupExtractedItem) {
	// Track product_id usage to detect duplicates
	// SKIP auto_create and not_found items — their product_id is just a suggestion
	productUsage := make(map[string][]int) // product_id → list of item indices
	for i := range items {
		if items[i].ProductID != nil && items[i].Status == "matched" {
			pid := *items[i].ProductID
			productUsage[pid] = append(productUsage[pid], i)
		}
	}

	for i := range items {
		// Flag 0: Quantity sanity check — impossibly high values suggest column misalignment
		if items[i].StockQuantity > 500 {
			items[i].NeedsReview = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Unusually high quantity: %d bottles — likely a read error, please verify", items[i].StockQuantity))
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = fmt.Sprintf("Stock quantity %d is too high — please enter correct value", items[i].StockQuantity)
			}
		}
		if items[i].StockQuantity > 2000 {
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Quantity %d exceeds safe limit — resetting to 0", items[i].StockQuantity))
			items[i].StockQuantity = 0
		}

		// Flag 1: Rate is 0 — AI couldn't read the price column
		if items[i].Rate == 0 && items[i].StockQuantity > 0 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Rate/price is ₹0 — please enter the correct selling price"
			}
		}

		// Flag 2: Low confidence (< 0.7)
		if items[i].MatchConfidence > 0 && items[i].MatchConfidence < 0.7 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Low confidence match — please verify brand name"
			}
		}

		// Flag 2b (WS-C-2): OCR-confidence floor. The matcher's MatchConfidence
		// can be 0.95 even when the AI read the row's NUMBERS uncertainly —
		// matched-product confidence overrides original OCR uncertainty in
		// the gate above. Fix: independently check the row-level Confidence
		// AND the per-field confidence on critical numeric columns. If any
		// is below 0.7, force needs_review with a specific warning naming
		// the suspect column. This catches Tushar's 180ML pattern where
		// rows persisted with field_confidence 0.63-0.66 but unflagged.
		if items[i].FieldConfidence != nil {
			lowFields := []string{}
			for _, fk := range []string{"opening", "sale", "rate", "amount"} {
				if c, ok := items[i].FieldConfidence[fk]; ok && c > 0 && c < 0.7 {
					lowFields = append(lowFields, fk)
				}
			}
			if len(lowFields) > 0 {
				items[i].NeedsReview = true
				items[i].Warnings = append(items[i].Warnings,
					fmt.Sprintf("AI was unsure of: %s — verify before saving", strings.Join(lowFields, ", ")))
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = "Low per-field confidence on " + strings.Join(lowFields, "/")
				}
			}
		}

		// Flag 3: Status is not_found (no product matched, not auto-created)
		if items[i].Status == "not_found" {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Could not identify this product — please select or create"
			}
		}

		// Flag 4: Duplicate — multiple rows matched to the same product
		if items[i].ProductID != nil {
			pid := *items[i].ProductID
			if indices, ok := productUsage[pid]; ok && len(indices) > 1 {
				items[i].NeedsReview = true
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = fmt.Sprintf("Duplicate — another row also matched to this product (rows %v)", indices)
				}
			}
		}

		// Flag 5: All quantities are zero — possibly a blank/filler row
		if items[i].Opening == 0 && items[i].Total == 0 && items[i].ClosingStock == 0 && items[i].StockQuantity == 0 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "All quantities are zero — verify if this row has stock"
			}
		}

		// Flag 5b: Row bleed detection — only ONE column has a value, rest are 0.
		// This often means AI read an adjacent row's number into the wrong column.
		// E.g., empty row gets closing=40 from next row's opening=40.
		{
			vals := []int{items[i].Opening, items[i].Sale, items[i].ClosingStock}
			nonZero := 0
			for _, v := range vals {
				if v > 0 {
					nonZero++
				}
			}
			if nonZero == 1 && items[i].Receipt == 0 && items[i].Total == 0 {
				items[i].NeedsReview = true
				items[i].Warnings = append(items[i].Warnings,
					"Only one value found — may be misread from adjacent row")
			}
		}

		// Flag 6: Auto-created product — user should verify the brand name is correct
		if items[i].AutoCreated {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "New product — please verify brand name before creating"
			}
		}

		// Flag 7: Arithmetic mismatch — AI may have misread numbers
		if items[i].Sale > 0 && items[i].Rate > 0 && items[i].Amount > 0 {
			expected := float64(items[i].Sale) * items[i].Rate
			if absFloat64(expected-items[i].Amount) > 10.0 {
				items[i].NeedsReview = true
				items[i].Warnings = append(items[i].Warnings,
					fmt.Sprintf("Amount mismatch: Sale(%d) × Rate(₹%.0f) = ₹%.0f but shows ₹%.0f",
						items[i].Sale, items[i].Rate, expected, items[i].Amount))
			}
		}
		// v1.0.247 — Flag 7b: closing-stock impossibility. You cannot end the day
		// with MORE bottles than you started with, unless you received stock during
		// the day. Chhotu's job ff6d9c65 row 38 had opening=2, closing=21 (Indri →
		// I Heart Riesling — the matcher was wrong AND the close-stock impossible
		// math should have caught it independently). Hard gate: closing > opening
		// + receipt with no plausible math path → force needs_review.
		if items[i].Opening > 0 && items[i].ClosingStock > items[i].Opening+items[i].Receipt {
			items[i].NeedsReview = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Closing(%d) > Opening(%d) + Receipt(%d) — physically impossible without unrecorded stock-in",
					items[i].ClosingStock, items[i].Opening, items[i].Receipt))
			// Drop closing field confidence so the cell-doubt UI surfaces this prominently.
			if items[i].FieldConfidence == nil {
				items[i].FieldConfidence = map[string]float64{}
			}
			items[i].FieldConfidence["closing"] = 0.40
			items[i].FieldConfidence["opening"] = 0.40
		}
		if items[i].Total > 0 && items[i].Opening+items[i].Receipt != items[i].Total {
			// Promoted from warning-only to NeedsReview — arithmetic failures on
			// printed registers are almost always an OCR drift and should force
			// the user to confirm the numbers before they're committed as stock.
			items[i].NeedsReview = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Total(%d) ≠ Opening(%d) + Receipt(%d) — opening likely misread",
					items[i].Total, items[i].Opening, items[i].Receipt))
		}
		// WS-B-2: Closing arithmetic. Earlier gate `ClosingStock > 0` skipped
		// the check when AI returned closing=0 even though total/sale showed
		// a clear mismatch (Tushar's 180ML rows 29-33: total=51 sale=0 but
		// closing=0 → 51-0=51 ≠ 0 should flag). New rule: fire whenever
		// Total>0 AND Sale≥0 AND the math doesn't balance, regardless of
		// whether closing was AI-extracted or 0/missing. The discrepancy
		// itself is the signal.
		if items[i].Total > 0 && items[i].Total >= items[i].Sale {
			expectedClose := items[i].Total - items[i].Sale
			if items[i].ClosingStock != expectedClose {
				items[i].NeedsReview = true
				items[i].Warnings = append(items[i].Warnings,
					fmt.Sprintf("Closing(%d) ≠ Total(%d) - Sale(%d) = %d — register math doesn't balance",
						items[i].ClosingStock, items[i].Total, items[i].Sale, expectedClose))
			}
		}

		// v1.0.133 — sale-vs-math gate (Tushar's "use opening−closing as
		// canonical sale" ask). When OCR extracted Opening AND ClosingStock
		// AND Sale > 0, compute mathSale = Opening + Receipt - ClosingStock.
		// If it disagrees with extracted Sale by more than max(1, opening*5%):
		// flag for review, drop sale field-confidence to 0.5, append warning.
		// Mirrors the Smart Sale gate at smart_sale_service.go:2137.
		if items[i].Opening > 0 && items[i].ClosingStock >= 0 && items[i].Sale > 0 &&
			items[i].Opening >= items[i].ClosingStock {
			mathSale := items[i].Opening + items[i].Receipt - items[i].ClosingStock
			tolerance := 1.0
			if float64(items[i].Opening)*0.05 > tolerance {
				tolerance = float64(items[i].Opening) * 0.05
			}
			if absFloat64(float64(mathSale-items[i].Sale)) > tolerance {
				items[i].NeedsReview = true
				items[i].Warnings = append(items[i].Warnings,
					fmt.Sprintf("⚠️ Sale qty %d disagrees with stock math (open %d + recv %d − close %d = %d)",
						items[i].Sale, items[i].Opening, items[i].Receipt, items[i].ClosingStock, mathSale))
				if items[i].FieldConfidence == nil {
					items[i].FieldConfidence = map[string]float64{}
				}
				if cur, ok := items[i].FieldConfidence["sale"]; !ok || cur > 0.6 {
					items[i].FieldConfidence["sale"] = 0.5
				}

				// High-confidence auto-suggest: when BOTH opening and closing
				// have field_confidence >= 0.9, the math-derived sale is
				// almost certainly the right answer and the AI's Sale reading
				// is the suspect cell (handwriting confusion). Surface the
				// derived value to Flutter as a tap-to-accept chip. Threshold
				// chosen conservatively so we never overwrite a confident
				// AI sale with a wrong-but-plausible derived number.
				if mathSale >= 0 && mathSale != items[i].Sale {
					openConf, openOk := items[i].FieldConfidence["opening"]
					closeConf, closeOk := items[i].FieldConfidence["closing"]
					if openOk && closeOk && openConf >= 0.9 && closeConf >= 0.9 {
						items[i].SuggestedSale = mathSale
						items[i].Warnings = append(items[i].Warnings,
							fmt.Sprintf("Math suggests sale = %d (open %d + recv %d − close %d) — opening/closing both look clear",
								mathSale, items[i].Opening, items[i].Receipt, items[i].ClosingStock))
					}
				}
			}
		}

		// Flag 8: Duplicate values across adjacent rows — AI row confusion.
		// Extended from the original Opening+Closing-only check to the full
		// (Opening, Receipt, Sale, Closing) tuple with at least two non-zero
		// values. Catches the Indri/Longitude drift pattern (both rows emit
		// 1/0/0/1) that the two-column check missed.
		if i > 0 {
			prev, cur := items[i-1], items[i]
			if prev.Opening == cur.Opening && prev.Receipt == cur.Receipt &&
				prev.Sale == cur.Sale && prev.ClosingStock == cur.ClosingStock {
				nonZero := 0
				for _, v := range []int{cur.Opening, cur.Receipt, cur.Sale, cur.ClosingStock} {
					if v > 0 {
						nonZero++
					}
				}
				if nonZero >= 2 {
					items[i].NeedsReview = true
					items[i-1].NeedsReview = true
					warn := "Adjacent rows have identical values — likely row-drift, please verify"
					items[i].Warnings = append(items[i].Warnings, warn)
					items[i-1].Warnings = append(items[i-1].Warnings, warn)
					if items[i].ReviewReason == "" {
						items[i].ReviewReason = "Numbers look identical to previous row — please verify"
					}
					if items[i-1].ReviewReason == "" {
						items[i-1].ReviewReason = "Numbers look identical to next row — please verify"
					}
				}
			}
		}

		// Flag 9: Handwritten items (low AI confidence) — always flag for review
		if items[i].MatchConfidence > 0 {
			// Already handled by flag 2
		}

		// WS-C-3: Adjacent-row Opening drift. Catches the "stolen Opening from
		// previous row" pattern even when other columns differ. Two adjacent
		// rows almost never have identical Opening counts — when they do AND
		// both are >0, the AI likely vertical-drifted (read row N-1's Opening
		// twice). Flag both rows AND drop opening field-confidence so the
		// amber underline lights up. This complements Flag 8 above which
		// requires the FULL tuple to match.
		if i > 0 {
			prevOp := items[i-1].Opening
			curOp := items[i].Opening
			if prevOp > 0 && curOp == prevOp &&
				items[i-1].ProductID != nil && items[i].ProductID != nil &&
				*items[i-1].ProductID != *items[i].ProductID {
				// Different products, identical opening — vertical drift signature.
				if items[i].FieldConfidence == nil {
					items[i].FieldConfidence = map[string]float64{}
				}
				if items[i-1].FieldConfidence == nil {
					items[i-1].FieldConfidence = map[string]float64{}
				}
				items[i].FieldConfidence["opening"] = 0.55
				items[i-1].FieldConfidence["opening"] = 0.55
				items[i].NeedsReview = true
				items[i-1].NeedsReview = true
				warn := fmt.Sprintf("Opening(%d) matches previous row's opening — possible vertical drift, verify", curOp)
				items[i].Warnings = append(items[i].Warnings, warn)
				items[i-1].Warnings = append(items[i-1].Warnings, "Opening matches next row — possible vertical drift, verify")
			}
		}
	}

	// WS-C-3b: Page-level opening collapse. Catches the worst failure mode
	// where AI emits the same opening for many rows because it couldn't
	// distinguish them (poor lighting, blurred numbers, ditto-marks). The
	// adjacent-pair detector above catches stair-step drift but misses this
	// global collapse — N rows with identical opening, scattered through the
	// page. Threshold: any opening value appearing in ≥3 rows AND ≥30% of
	// the page's rows. All affected rows get field_confidence.opening=0.30
	// (re-extraction-grade low) + a page-level warning so the user re-shoots
	// instead of hand-fixing every row.
	{
		// Group rows by page.
		pageRows := map[int][]int{}
		for i := range items {
			pageRows[items[i].PageNumber] = append(pageRows[items[i].PageNumber], i)
		}
		for page, idxs := range pageRows {
			if len(idxs) < 4 {
				continue // very small pages (1-3 rows) — too small to disambiguate signal vs noise
			}
			// Count opening frequency on this page (ignore zero — empty rows).
			freq := map[int][]int{}
			for _, i := range idxs {
				op := items[i].Opening
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
					}
					log.Printf("Smart Stock Setup: %s", warn)
				}
			}
		}
	}

	// Flag 10: Duplicate product_id with meaningfully different rates — catches
	// "same brand emitted twice with a drifted number" (row 38+41 Black Label at
	// rates 3400 vs 3100 in the 2026-04-20 failure). Different rates on the same
	// product mean one of the OCR reads is wrong.
	type dupRowInfo struct {
		idx  int
		rate float64
	}
	byProduct := map[string][]dupRowInfo{}
	for i := range items {
		if items[i].ProductID != nil && (items[i].Status == "matched" || items[i].Status == "low_confidence") {
			pid := *items[i].ProductID
			byProduct[pid] = append(byProduct[pid], dupRowInfo{idx: i, rate: items[i].Rate})
		}
	}
	for _, rows := range byProduct {
		if len(rows) < 2 {
			continue
		}
		minR, maxR := rows[0].rate, rows[0].rate
		for _, r := range rows[1:] {
			if r.rate < minR {
				minR = r.rate
			}
			if r.rate > maxR {
				maxR = r.rate
			}
		}
		if maxR-minR > 10.0 {
			for _, r := range rows {
				items[r.idx].NeedsReview = true
				items[r.idx].Warnings = append(items[r.idx].Warnings,
					"Same item appears twice with different rates")
			}
		}
	}

	// Flag 11: Rate-ascent monotonicity + variance detection per page.
	// Printed registers list brands in ascending-rate order. Two triggers:
	//
	// (a) Drop threshold — any row where the rate drops ≥10% from the previous
	//     row. Catches obvious misreads like 3400→1680.
	// (b) Variance threshold — within a page, compute the median of adjacent
	//     rate deltas. Any delta that's >40% off from the median is anomalous
	//     even if the drop is small (catches the 950→940→1050→1020 drift
	//     pattern on printed rows 23-27 from 2026-04-20 where each drop is
	//     sub-10% but the rhythm is clearly broken). Scoped to rows with
	//     confidence ≥0.80 (printed-section heuristic) so handwritten wobble
	//     doesn't spam warnings.
	type pageRow struct {
		idx  int
		rate float64
	}
	byPage := map[int][]pageRow{}
	for i := range items {
		if items[i].Rate > 0 && items[i].PageNumber > 0 {
			byPage[items[i].PageNumber] = append(byPage[items[i].PageNumber], pageRow{idx: i, rate: items[i].Rate})
		}
	}
	for _, rows := range byPage {
		// (a) Drop threshold per adjacent pair.
		for j := 1; j < len(rows); j++ {
			prev := rows[j-1]
			cur := rows[j]
			if cur.rate < prev.rate*0.90 {
				items[prev.idx].NeedsReview = true
				items[cur.idx].NeedsReview = true
				warn := "Price out of order — may be row drift"
				items[prev.idx].Warnings = append(items[prev.idx].Warnings, warn)
				items[cur.idx].Warnings = append(items[cur.idx].Warnings, warn)
			}
		}
		// (b) Variance detection — only with ≥4 data points so the median is
		// stable. Computes deltas, finds median of POSITIVE deltas (ascending
		// baseline), then flags deltas that wander far from that baseline.
		if len(rows) < 4 {
			continue
		}
		deltas := make([]float64, 0, len(rows)-1)
		positiveDeltas := make([]float64, 0, len(rows)-1)
		for j := 1; j < len(rows); j++ {
			d := rows[j].rate - rows[j-1].rate
			deltas = append(deltas, d)
			if d > 0 {
				positiveDeltas = append(positiveDeltas, d)
			}
		}
		if len(positiveDeltas) < 2 {
			continue
		}
		sorted := append([]float64(nil), positiveDeltas...)
		sort.Float64s(sorted)
		median := sorted[len(sorted)/2]
		if median <= 0 {
			continue
		}
		for j, d := range deltas {
			// Skip when we're still within a ±40% band around median.
			off := d - median
			if off < 0 {
				off = -off
			}
			if off <= 0.40*median {
				continue
			}
			// Only complain when at least one of the two rows looks printed
			// (confidence ≥0.80 at extraction time — stored on the extracted
			// item but we only have the enriched item here). The backend has
			// already copied confidence into MatchConfidence for low_confidence
			// rows; use a loose heuristic: if both rows are matched/auto_create,
			// treat as printed section.
			prev := rows[j]
			cur := rows[j+1]
			prevPrinted := items[prev.idx].Status == "matched" || items[prev.idx].Status == "auto_create"
			curPrinted := items[cur.idx].Status == "matched" || items[cur.idx].Status == "auto_create"
			if !(prevPrinted && curPrinted) {
				continue
			}
			items[prev.idx].NeedsReview = true
			items[cur.idx].NeedsReview = true
			warn := fmt.Sprintf("Unusual price gap (₹%.0f vs typical ₹%.0f)", d, median)
			items[prev.idx].Warnings = append(items[prev.idx].Warnings, warn)
			items[cur.idx].Warnings = append(items[cur.idx].Warnings, warn)
		}
	}

	// Flag 11b: Adjacent-row value swap detector. When two adjacent confidently-
	// matched rows have values where ONE row has non-zero opening/closing/sale
	// and the NEXT row has all zeros, the numbers may have drifted between rows
	// (classic OCR row-shift on dense printed rows). Catches the Black Dog
	// Triple Gold case from 2026-04-20 where row 32 got row 33's 4/4 values.
	//
	// Threshold: only fire when both rows have high-confidence matches AND the
	// rate sequence is intact (N's rate < N+1's rate, monotonic). This avoids
	// false positives on legitimate empty rows in the middle of a register.
	{
		type rowRef struct {
			idx int
		}
		pageIdx := map[int][]rowRef{}
		for i := range items {
			if items[i].PageNumber > 0 {
				pageIdx[items[i].PageNumber] = append(pageIdx[items[i].PageNumber], rowRef{idx: i})
			}
		}
		for _, refs := range pageIdx {
			// Sort by row_number so "adjacent" means register-adjacent.
			sort.SliceStable(refs, func(a, b int) bool {
				return items[refs[a].idx].RowNumber < items[refs[b].idx].RowNumber
			})
			rowHasValues := func(it SmartStockSetupExtractedItem) bool {
				return it.Opening > 0 || it.Sale > 0 || it.ClosingStock > 0 || it.Receipt > 0
			}
			isAllZero := func(it SmartStockSetupExtractedItem) bool {
				return it.Opening == 0 && it.Sale == 0 && it.ClosingStock == 0 && it.Receipt == 0
			}
			confidentlyMatched := func(it SmartStockSetupExtractedItem) bool {
				return (it.Status == "matched" || it.Status == "auto_create") &&
					it.MatchConfidence >= 0.70 && it.Rate > 0
			}
			// suspectValueCrossover catches the Absolut/Ballantine pattern from
			// 2026-04-21 where the opening value drifted into the next row but the
			// second row still had legitimate sale/closing activity: row A has
			// opening alone, row B has no opening but real sale/closing movement.
			suspectValueCrossover := func(a, b SmartStockSetupExtractedItem) bool {
				aOnlyOpening := a.Opening > 0 && a.Sale == 0 && a.ClosingStock == 0 && a.Receipt == 0
				bHasMovement := b.Opening == 0 && (b.Sale > 0 || b.ClosingStock > 0 || b.Receipt > 0)
				if aOnlyOpening && bHasMovement {
					return true
				}
				bOnlyOpening := b.Opening > 0 && b.Sale == 0 && b.ClosingStock == 0 && b.Receipt == 0
				aHasMovement := a.Opening == 0 && (a.Sale > 0 || a.ClosingStock > 0 || a.Receipt > 0)
				return bOnlyOpening && aHasMovement
			}
			for j := 0; j < len(refs)-1; j++ {
				a := items[refs[j].idx]
				b := items[refs[j+1].idx]
				if !confidentlyMatched(a) || !confidentlyMatched(b) {
					continue
				}
				// Rates should be monotonic-ascending on printed sequences.
				if b.Rate < a.Rate {
					continue
				}
				fire := false
				// Existing "one row all-zeros" shape.
				if (rowHasValues(a) && isAllZero(b)) || (isAllZero(a) && rowHasValues(b)) {
					fire = true
				}
				// New opening-only crossover shape (Absolut/Ballantine).
				if !fire && suspectValueCrossover(a, b) {
					fire = true
				}
				if !fire {
					continue
				}
				warn := "Values may be swapped with next row"
				items[refs[j].idx].NeedsReview = true
				items[refs[j+1].idx].NeedsReview = true
				items[refs[j].idx].Warnings = append(items[refs[j].idx].Warnings, warn)
				items[refs[j+1].idx].Warnings = append(items[refs[j+1].idx].Warnings, warn)
				// Cross-link so the review UI can render a one-tap "Swap opening
				// with row N" action chip on both rows.
				items[refs[j].idx].SwapCandidateRow = b.RowNumber
				items[refs[j+1].idx].SwapCandidateRow = a.RowNumber
			}
		}
	}

	// Flag 13: Arithmetic sanity — opening + receipt - sale ≈ closing_stock.
	// ±1 tolerance for handwriting noise. Fires only when at least two of the
	// four values are non-zero so opening-only entries don't false-positive.
	for i := range items {
		it := items[i]
		nonZero := 0
		for _, v := range []int{it.Opening, it.Receipt, it.Sale, it.ClosingStock} {
			if v > 0 {
				nonZero++
			}
		}
		if nonZero < 2 {
			continue
		}
		expected := it.Opening + it.Receipt - it.Sale
		diff := expected - it.ClosingStock
		if diff < 0 {
			diff = -diff
		}
		if diff > 1 {
			items[i].NeedsReview = true
			items[i].Warnings = append(items[i].Warnings,
				fmt.Sprintf("Numbers don't balance (expected close %d, got %d)", expected, it.ClosingStock))
		}
	}

	// Flag 12: Cross-page same SKU. Identical (brand, sizeML, rate) across
	// different pages is almost certainly the same row extracted twice. Flag
	// both but don't auto-merge — user decides which to keep.
	type crossKey struct {
		brand  string
		sizeML int
		rate   float64
	}
	seenCross := map[crossKey][]int{}
	for i := range items {
		if items[i].OfficialBrandName == "" || items[i].Rate == 0 {
			continue
		}
		k := crossKey{
			brand:  strings.ToLower(strings.TrimSpace(items[i].OfficialBrandName)),
			sizeML: items[i].SizeML,
			rate:   items[i].Rate,
		}
		seenCross[k] = append(seenCross[k], i)
	}
	for _, idxs := range seenCross {
		if len(idxs) < 2 {
			continue
		}
		pages := map[int]struct{}{}
		for _, i := range idxs {
			pages[items[i].PageNumber] = struct{}{}
		}
		if len(pages) < 2 {
			continue
		}
		pageList := make([]int, 0, len(pages))
		for p := range pages {
			pageList = append(pageList, p)
		}
		sort.Ints(pageList)
		warn := fmt.Sprintf("Same brand+rate also appears on page %v — possibly duplicated across pages, please verify", pageList)
		for _, i := range idxs {
			items[i].NeedsReview = true
			items[i].Warnings = append(items[i].Warnings, warn)
		}
	}
}

// detectHandwrittenBand finds the trailing contiguous range of rows on a given
// page that look handwritten/low-confidence and are worth re-extracting with a
// specialized prompt. Returns fromRow, toRow (inclusive, 1-based row_numbers)
// and ok=true when the band is substantial (≥ 3 rows).
//
// Heuristics (a row is a "handwritten candidate" when any are true):
//   - AI confidence < 0.70 (it told us the row was uncertain)
//   - Brand text is short (<15 chars) AND contains no spaces (likely an abbreviation)
//   - Rate = 0 despite having opening or closing > 0 (handwritten sections often skip the printed rate column)
//   - MatchedProductIdx = 0 (AI couldn't resolve against the product list)
//
// The band must be TRAILING: we walk rows bottom-up and stop at the first
// non-candidate row. This avoids misfiring on a single mid-page fuzzy read.
func detectHandwrittenBand(items []ExtractedStockRegisterItem, pageNum int) (int, int, bool) {
	// Collect rows for this page, sorted by row_number
	pageItems := make([]ExtractedStockRegisterItem, 0, len(items)/2)
	for _, it := range items {
		if it.PageNumber == pageNum {
			pageItems = append(pageItems, it)
		}
	}
	if len(pageItems) < 3 {
		return 0, 0, false
	}
	sort.SliceStable(pageItems, func(i, j int) bool {
		return pageItems[i].RowNumber < pageItems[j].RowNumber
	})

	isCandidate := func(it ExtractedStockRegisterItem) bool {
		if it.Confidence > 0 && it.Confidence < 0.70 {
			return true
		}
		trimmed := strings.TrimSpace(it.Brand)
		if len(trimmed) > 0 && len(trimmed) < 15 && !strings.Contains(trimmed, " ") {
			return true
		}
		if it.Rate == 0 && (it.Opening > 0 || it.Closing > 0) {
			return true
		}
		if it.MatchedProductIdx == 0 && it.OfficialBrandName == "" && len(trimmed) > 0 {
			return true
		}
		return false
	}

	// Rate-isolation detector: a row whose rate differs from BOTH immediate
	// neighbors by >30% is almost certainly a misread (e.g. row 43 rate 2010
	// wedged between 4660 and 1680 in the 2026-04-20 failure). This widens the
	// trigger to include rows that don't look handwritten-style by themselves
	// but sit in a hotspot where the specialized prompt helps.
	isRateIsolated := func(i int) bool {
		if i <= 0 || i >= len(pageItems)-1 {
			return false
		}
		cur := pageItems[i].Rate
		prev := pageItems[i-1].Rate
		next := pageItems[i+1].Rate
		if cur <= 0 || prev <= 0 || next <= 0 {
			return false
		}
		// Both neighbors differ by > 30% from cur.
		diffPrev := cur / prev
		if diffPrev < 1 {
			diffPrev = 1 / diffPrev
		}
		diffNext := cur / next
		if diffNext < 1 {
			diffNext = 1 / diffNext
		}
		return diffPrev > 1.30 && diffNext > 1.30
	}

	// Walk bottom-up to find the trailing band.
	lastIdx := len(pageItems) - 1
	bandStart := lastIdx + 1
	for i := lastIdx; i >= 0; i-- {
		if isCandidate(pageItems[i]) {
			bandStart = i
		} else {
			break
		}
	}
	bandLen := (lastIdx - bandStart) + 1

	// Expand the band to include any rate-isolated rows upstream from bandStart
	// so a single anomaly like row 43's rate=2010 pulls itself (and its immediate
	// neighbors) into the re-extract range.
	for i := bandStart - 1; i >= 0; i-- {
		if isRateIsolated(i) {
			bandStart = i
		}
	}
	bandLen = (lastIdx - bandStart) + 1

	// Relaxed floor: 2 rows is enough to warrant the specialized prompt. Was 3
	// before — too strict for pages where the handwritten section was short.
	// Guard against runaway fallback (previous version re-extracted the entire
	// page when any 2 rows were unresolved — that dragged printed rows through
	// the looser handwritten prompt and sometimes made them WORSE). Only
	// return a non-trivial band, no full-page fallback.
	if bandLen < 2 {
		return 0, 0, false
	}
	return pageItems[bandStart].RowNumber, pageItems[lastIdx].RowNumber, true
}

// dedupeSameBrandSamePage handles a known v1.0.119 failure mode: the
// handwritten-pass and main-pass occasionally emit the SAME physical register
// row twice, with row_numbers that drift by 1-2 (e.g., row 49 and row 50 both
// labeled "100 STROKES ROYAL" on page 2). The duplicate readings can disagree
// on rate when one read is row-bled from an adjacent row (row 48 was
// "M2 MAGIC MOMENTS JAMUN" at ₹720, AI carried ₹720 down into row 49; row 50
// read the actual ₹620). Without this dedup, both rows reach Flutter and the
// matched/higher-confidence one wins approval — even when its rate is wrong.
//
// Strategy when same (page, normalized_brand) appears twice within ±3 rows:
//  1. If exactly one reading's rate matches a known master MRP within ±5%,
//     keep that one (rate-bleed is recognizable when AI's rate disagrees with
//     the master catalog).
//  2. Otherwise keep the higher-confidence reading.
//  3. The other reading is dropped silently (logged for audit).
//
// Called by ProcessExtraction after BOTH page-rescue and handwritten-pass merges.
// absFloatStockSetup is a local copy of math.Abs for float64 — keeps stock-
// setup helpers independent of the sales package. v1.0.123.
func absFloatStockSetup(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

// resolveActorNameStockSetup looks up a user's display name for the MRP audit
// columns. Best-effort — empty result if the lookup fails. v1.0.123.
func resolveActorNameStockSetup(tx *gorm.DB, actorID uuid.UUID) string {
	if actorID == uuid.Nil {
		return ""
	}
	var u models.User
	if err := tx.Select("first_name, last_name, username").Where("id = ?", actorID).First(&u).Error; err != nil {
		return ""
	}
	full := strings.TrimSpace(u.FirstName + " " + u.LastName)
	if full == "" {
		return u.Username
	}
	return full
}

func dedupeSameBrandSamePage(items []ExtractedStockRegisterItem, masterBrands []models.MasterBrandInfo, sizeML int) []ExtractedStockRegisterItem {
	if len(items) < 2 {
		return items
	}
	// Index master brands by normalized name for O(1) lookup of authoritative MRP.
	type masterEntry struct {
		mrp  float64
		name string
	}
	byName := make(map[string]masterEntry, len(masterBrands))
	for i := range masterBrands {
		key := strings.ToLower(strings.TrimSpace(masterBrands[i].BrandName))
		if key == "" {
			continue
		}
		// If a master brand has multiple variants (different sizes), keep the entry whose size matches sizeML.
		if existing, ok := byName[key]; ok {
			// Prefer the one matching the requested size when both are seen.
			if matching.ParseSizeML(masterBrands[i].Size) == sizeML {
				byName[key] = masterEntry{mrp: masterBrands[i].MRP, name: masterBrands[i].BrandName}
			} else if existing.mrp == 0 {
				byName[key] = masterEntry{mrp: masterBrands[i].MRP, name: masterBrands[i].BrandName}
			}
		} else {
			byName[key] = masterEntry{mrp: masterBrands[i].MRP, name: masterBrands[i].BrandName}
		}
	}

	// Group by (page, normalized brand). Brands that don't normalize cleanly
	// or are blank skip dedup (treat them as distinct).
	type bucketKey struct {
		page  int
		brand string
	}
	groups := make(map[bucketKey][]int, len(items))
	for i, it := range items {
		brandNorm := strings.ToLower(strings.TrimSpace(it.Brand))
		if brandNorm == "" || len(brandNorm) < 4 {
			continue
		}
		k := bucketKey{page: it.PageNumber, brand: brandNorm}
		groups[k] = append(groups[k], i)
	}

	dropIdx := make(map[int]bool)
	for k, idxs := range groups {
		if len(idxs) < 2 {
			continue
		}
		// Only dedup duplicates that are within ±3 rows of each other on the same
		// page — multi-shop registers can legitimately list the same brand twice
		// at very different positions (e.g., promo entries), and we don't want to
		// merge those.
		minRow, maxRow := items[idxs[0]].RowNumber, items[idxs[0]].RowNumber
		for _, i := range idxs[1:] {
			if items[i].RowNumber < minRow {
				minRow = items[i].RowNumber
			}
			if items[i].RowNumber > maxRow {
				maxRow = items[i].RowNumber
			}
		}
		if maxRow-minRow > 3 {
			continue
		}

		// Strategy 1: master-MRP rate match.
		var winner int = -1
		master, hasMaster := byName[k.brand]
		if hasMaster && master.mrp > 0 {
			tolerance := master.mrp * 0.05
			matches := []int{}
			for _, i := range idxs {
				if abs(items[i].Rate-master.mrp) <= tolerance {
					matches = append(matches, i)
				}
			}
			if len(matches) == 1 {
				winner = matches[0]
				log.Printf("Smart Stock Setup: brand-dedup — page=%d brand=%q kept row %d (rate=₹%.0f matches master MRP ₹%.0f), dropped %d duplicate(s) likely bled from adjacent row",
					k.page, items[winner].Brand, items[winner].RowNumber, items[winner].Rate, master.mrp, len(idxs)-1)
			}
		}

		// Strategy 2: highest confidence wins.
		if winner < 0 {
			winner = idxs[0]
			for _, i := range idxs[1:] {
				if items[i].Confidence > items[winner].Confidence {
					winner = i
				}
			}
			log.Printf("Smart Stock Setup: brand-dedup — page=%d brand=%q kept row %d (highest confidence %.2f), dropped %d duplicate(s)",
				k.page, items[winner].Brand, items[winner].RowNumber, items[winner].Confidence, len(idxs)-1)
		}

		for _, i := range idxs {
			if i != winner {
				dropIdx[i] = true
			}
		}
	}

	if len(dropIdx) == 0 {
		return items
	}
	out := make([]ExtractedStockRegisterItem, 0, len(items)-len(dropIdx))
	for i, it := range items {
		if dropIdx[i] {
			continue
		}
		out = append(out, it)
	}
	return out
}

// mergeHandwrittenBand replaces rows on the given page whose row_number falls
// inside [fromRow, toRow] with the re-extracted rows. Any re-extracted row
// with a row_number outside the requested band is dropped (defensive: the
// specialized prompt may occasionally emit stray rows). Rows from other pages
// are untouched.
func mergeHandwrittenBand(orig []ExtractedStockRegisterItem, reExtracted []ExtractedStockRegisterItem, pageNum, fromRow, toRow int) []ExtractedStockRegisterItem {
	// Partition orig into: (a) rows to keep (other pages or outside band on this page), (b) rows to replace.
	kept := make([]ExtractedStockRegisterItem, 0, len(orig))
	for _, it := range orig {
		if it.PageNumber == pageNum && it.RowNumber >= fromRow && it.RowNumber <= toRow {
			continue // drop — will be replaced
		}
		kept = append(kept, it)
	}
	// Append re-extracted rows that are within the band.
	for _, it := range reExtracted {
		if it.RowNumber < fromRow || it.RowNumber > toRow {
			continue
		}
		kept = append(kept, it)
	}
	// Sort so the downstream code sees a stable order.
	sort.SliceStable(kept, func(i, j int) bool {
		if kept[i].PageNumber != kept[j].PageNumber {
			return kept[i].PageNumber < kept[j].PageNumber
		}
		return kept[i].RowNumber < kept[j].RowNumber
	})
	return kept
}

// determineStockQuantity returns the stock value for the user-selected column.
// No fallback to other columns — if the selected column is 0, stock is 0.
// This prevents row-bleed errors where AI reads an adjacent row's number
// into the wrong column (e.g., closing=40 when opening should be 0).
func determineStockQuantity(extracted ExtractedStockRegisterItem, stockColumn string) int {
	switch stockColumn {
	case "closing":
		return extracted.Closing
	case "opening":
		return extracted.Opening
	default: // "total"
		if extracted.Total > 0 {
			return extracted.Total
		}
		// For "total" only, fall back to opening (registers often skip total column)
		return extracted.Opening
	}
}

// stockSetupGenericWords is the filler-word set used across the AI-index gate,
// findMasterBrand token-overlap, and same-brand-prefix alternative detection.
// Kept at package scope so all three call sites use an identical definition.
var stockSetupGenericWords = map[string]bool{
	"the": true, "a": true, "an": true, "of": true, "and": true, "for": true, "with": true,
	"whisky": true, "whiskey": true, "rum": true, "vodka": true, "gin": true, "brandy": true,
	"wine": true, "beer": true, "scotch": true, "bourbon": true, "liquor": true,
	"premium": true, "special": true, "rare": true, "reserve": true, "deluxe": true,
	"blended": true, "grain": true, "indian": true, "international": true, "triple": true,
	"flavoured": true, "flavored": true, "distilled": true, "original": true, "fine": true,
	"old": true, "very": true, "select": true, "choice": true, "finest": true,
	"superior": true, "exclusive": true,
}

// familyPrefixWords are brand "house" tokens that appear across multiple
// unrelated brand families and therefore don't disambiguate one family from
// another. Two products sharing only "royal" are NOT same-family ("Royal
// Green Reserve" vs "Royal Stag Superior" — chhotu d982ade6 row 18 picked
// these up as a 1.097 confidence match because both have "royal" + size +
// price match overlapped). Excluding these from the family-root comparison
// forces matches to share a token deeper than the prefix.
var familyPrefixWords = map[string]bool{
	"royal":     true,
	"the":       true,
	"master":    true,
	"all":       true,
	"seagrams":  true,
	"signature": true,
	"sterling":  true,
	"imperial":  true,
	"officer":   true,
	"officers":  true,
	"magic":     true,
	"moments":   true,
	"movement":  true,
}

// distinctiveTokenSet returns the brand-identifying tokens of text — distinctive
// (length ≥ 3, non-generic, non-color, non-family-prefix). Used by the
// cross-family conflict check.
func distinctiveTokenSet(text string) map[string]bool {
	out := map[string]bool{}
	for _, t := range strings.Fields(strings.ToLower(text)) {
		if len(t) < 3 {
			continue
		}
		if stockSetupGenericWords[t] {
			continue
		}
		if labelColorTokens[t] {
			continue
		}
		if familyPrefixWords[t] {
			continue
		}
		if t == "label" || t == "labels" {
			continue
		}
		out[t] = true
	}
	return out
}

// crossFamilyConflict returns true when src and cand share NO brand-identifying
// token (post-generic, post-prefix). This is a hard family-divergence signal —
// the source and the candidate name don't agree on any token deeper than a
// common house prefix or size/category filler.
//
// Returns false (no conflict) when either side is empty (can't decide; let
// other guards handle it). The fuzzy text-score primary and flavor guard run
// independently, so a false here just means this particular check abstains.
func crossFamilyConflict(src, cand string) bool {
	srcDist := distinctiveTokenSet(src)
	candDist := distinctiveTokenSet(cand)
	if len(srcDist) == 0 || len(candDist) == 0 {
		return false
	}
	for t := range srcDist {
		if candDist[t] {
			return false
		}
	}
	return true
}

// labelColorTokens are color words that appear as a *Label qualifier* on real
// brands (Johnnie Walker Red/Blue/Black/Gold/Blonde/Platinum Label, Dewars White
// Label, etc.) — swapping one for another yields a different real SKU, so the
// fuzzy/token matcher treating them as fungible is a silent-corruption bug.
// "green" is intentionally omitted — it appears mid-phrase in many legitimate
// products ("Royal Green Reserve") and would cause false positives.
// "double" is included because "Double Black" is a distinct JW SKU from "Black
// Label"; the helper treats it as a single label token via prefix scan.
var labelColorTokens = map[string]bool{
	"red": true, "blue": true, "black": true, "gold": true, "white": true,
	"silver": true, "yellow": true, "purple": true, "blonde": true, "platinum": true,
}

// labelColorIn returns the first label-color token found in the tokenised text,
// or "" if none. It also handles the "double black" compound — if "double"
// immediately precedes "black", we treat the pair as "double_black" so
// "Johnnie Walker Black Label" vs "Johnnie Walker Double Black" is a conflict
// (they are different SKUs) but "Johnnie Walker Double Black" vs itself is not.
func labelColorIn(text string) string {
	toks := strings.Fields(strings.ToLower(text))
	for i, t := range toks {
		if t == "double" && i+1 < len(toks) && toks[i+1] == "black" {
			return "double_black"
		}
		if labelColorTokens[t] {
			return t
		}
	}
	return ""
}

// familyRootTokens returns the distinctive (non-generic, non-label-color) tokens
// from text with length >= 4. These are the brand family roots like "walker",
// "dewars", "chivas" that identify a brand lineage across its Label variants.
func familyRootTokens(text string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, t := range strings.Fields(strings.ToLower(text)) {
		if len(t) < 4 {
			continue
		}
		if stockSetupGenericWords[t] {
			continue
		}
		if labelColorTokens[t] {
			continue
		}
		if t == "label" || t == "labels" {
			continue
		}
		out[t] = struct{}{}
	}
	return out
}

// hasLabelColorConflict returns true when src and cand each contain a DIFFERENT
// label-color token AND they share at least one family root (e.g. both mention
// "walker" or "dewars"). The family-root requirement prevents false positives
// on unrelated products that happen to mention different colors (e.g. "Royal
// Green Reserve" vs "8 PM Black" — no shared root, no conflict).
//
// Triggered cases from the 2026-04-20 failure:
//   src="Johnnie Walker Blue Label"  cand="Johnnie Walker Red Label"  → conflict (shared: walker)
//   src="Johnnie Walker Black Label" cand="Johnnie Walker Double Black" → conflict (black vs double_black, shared: walker)
//   src="Dewars White Label"         cand="Johnnie Walker Red Label"   → no conflict (no shared root)
//   src="Royal Green Reserve"        cand="8 PM Black"                 → no conflict (no shared root, "green" not in set)
func hasLabelColorConflict(src, cand string) bool {
	if src == "" || cand == "" {
		return false
	}
	srcColor := labelColorIn(src)
	candColor := labelColorIn(cand)
	if srcColor == "" || candColor == "" {
		return false
	}
	if srcColor == candColor {
		return false
	}
	srcRoots := familyRootTokens(src)
	if len(srcRoots) == 0 {
		return false
	}
	for t := range familyRootTokens(cand) {
		if _, ok := srcRoots[t]; ok {
			return true
		}
	}
	return false
}

// resolveDisplayAndFullName returns (display_name, full_name) for a product.
// display prefers DB display_name → brand_name → name. full is always the DB name.
func resolveDisplayAndFullName(p *dbProduct) (display, full string) {
	if p == nil {
		return "", ""
	}
	full = p.Name
	display = firstNonEmpty(p.DisplayName, p.BrandName, p.Name)
	return display, full
}

// findProductByID returns a pointer to the dbProduct with the given ID, or nil.
func findProductByID(products []dbProduct, id string) *dbProduct {
	for i := range products {
		if products[i].ID == id {
			return &products[i]
		}
	}
	return nil
}

// sameSpiritFamily reports whether two category names refer to the same
// product family (whisky / vodka / rum / gin / brandy / beer / wine).
// Case-insensitive, prefix-tolerant — "Whisky" / "WHISKY" / "Whiskey" all match,
// and "Indian Whisky"/"Scotch Whisky" match "Whisky".
// Returns true on empty inputs (treat unknown-category as "compatible") so
// pages without an explicit category pick don't over-reject.
//
// v1.0.247 — used by the page-level category gate in matchAndEnrich to block
// whisky→wine and similar cross-family matches that the keyword-based gate
// missed when neither the OCR text nor the product name carried a category
// word (chhotu's "Indri → I Heart Riesling" case).
// sharesDistinctiveToken reports whether a and b share at least one
// non-generic ("distinctive") word. Used only in the rescue path (already
// weak matches) to refuse an auto_create whose chosen master/product shares
// ONLY filler words (colours / qualifiers / spirit nouns / size) with the
// register text. v1.0.257: spirit-family gates are defeated when the catalog
// MIS-categorises a product — chhotu's tenant files "Moonwalk Green Apple"
// under category "Whisky", so an OCR-garbled "8 PM … Whisky Green" still
// rescued to it purely on the shared filler token "green" + shop-stock bias.
// Conservative: returns false ONLY when both sides have ≥1 distinctive token
// and they do not intersect (insufficient signal ⇒ true, never over-rejects).
func sharesDistinctiveToken(a, b string) bool {
	generic := map[string]bool{
		"green": true, "gold": true, "black": true, "blue": true, "red": true,
		"white": true, "silver": true, "premium": true, "rare": true,
		"reserve": true, "special": true, "classic": true, "original": true,
		"deluxe": true, "fine": true, "superior": true, "select": true,
		"smooth": true, "blend": true, "blended": true, "grain": true,
		"scotch": true, "whisky": true, "whiskey": true, "vodka": true,
		"rum": true, "gin": true, "brandy": true, "cognac": true, "wine": true,
		"beer": true, "lager": true, "ale": true, "the": true, "no": true,
		"ml": true, "pet": true, "tetra": true, "xo": true, "vsop": true,
		"dark": true, "old": true, "ltr": true,
	}
	toks := func(s string) map[string]bool {
		out := map[string]bool{}
		cur := make([]rune, 0, 16)
		flush := func() {
			if len(cur) == 0 {
				return
			}
			w := string(cur)
			cur = cur[:0]
			if len(w) < 2 || generic[w] {
				return
			}
			allDigit := true
			for _, r := range w {
				if r < '0' || r > '9' {
					allDigit = false
					break
				}
			}
			if allDigit {
				return
			}
			out[w] = true
		}
		for _, r := range strings.ToLower(s) {
			if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
				cur = append(cur, r)
			} else {
				flush()
			}
		}
		flush()
		return out
	}
	ta, tb := toks(a), toks(b)
	if len(ta) == 0 || len(tb) == 0 {
		return true // not enough signal — don't block
	}
	// Fuzzy, not exact: OCR garble must not over-reject a CORRECT rescue
	// ("Rockfrd Resrv" → "Rockford Reserve" shares no exact token but is
	// clearly the same brand). Accept an exact hit, a containment (len ≥ 4),
	// or a high character-similarity token pair. chhotu's distinctive "pm"
	// has no such partner in "Moonwalk Green Apple" ⇒ correctly blocked.
	for wa := range ta {
		for wb := range tb {
			if wa == wb {
				return true
			}
			if len(wa) >= 4 && len(wb) >= 4 &&
				(strings.Contains(wa, wb) || strings.Contains(wb, wa)) {
				return true
			}
			if matching.StringSimilarity(wa, wb) >= 0.80 {
				return true
			}
		}
	}
	return false
}

// shouldRejectUnreadableAutoCreate decides whether a deferred auto-create row
// has UNVERIFIABLE PROVENANCE and therefore must NOT become a permanent
// catalog brand+product.
//
// ROBUST CONTRACT (v1.0.283, hardened after the second instance). A row is
// rejected iff it is SIMULTANEOUSLY:
//   (a) NOT linked to any catalog master (no operator pick, no fuzzy master
//       sharing a distinctive token),
//   (b) NOT corrected / manually added by the operator (wasCorrected),
//   (c) has NO bottle photo, and
//   (d) NOT operator-authored (operator did not retype a distinct name).
//
// Such a brand string came purely from the extractor with ZERO corroboration.
// AI confidence is deliberately NOT a gate condition: the first instance was
// low-confidence OCR garble (chhotu's "Chonploopr", brand conf 0.35) but the
// second was a CONFIDENT HALLUCINATION ("Vin Green Label The Rich Blend
// Whisky · 375ml", a long plausible name the model was sure about). A model's
// confidence on out-of-distribution / hallucinated input is meaningless, so
// gating on it (the original ≤0.50 floor) let the confident-hallucination
// class straight through. Provenance — not confidence — is the safe invariant:
// if nothing (catalog / operator / photo) vouches for the name, creating a
// permanent product from it pollutes the tenant catalog forever, even on a
// never-approved record.
//
// CONSERVATIVE BY DESIGN — ANY single vouching signal keeps the row:
// catalog-linked, operator-corrected / manual add (Flutter's Add-Missing path
// sends was_corrected=true), photo-verified, operator-authored (retyped a
// distinct name), or operator-vouched-at-submit (v1.0.291: the row was
// visible on the review screen when the operator pressed Set Opening Stock).
// Confidence is logged at the call site for diagnostics only. Env kill-switch
// SMART_STOCK_SETUP_REJECT_UNREADABLE=0 disables instantly if it ever proves
// too strict in production.
//
// vouchedBySubmit is the v1.0.291 signal. Set true ONLY by Flutter when the
// row appeared in the review-screen list at the moment of submit. Re-extraction,
// admin auto-apply, and approve-of-deferred-row paths leave it false so the
// gate keeps protecting unattended creates. The approve path reads the flag
// from the persisted raw_ai_extraction JSON to honor the original submit vouch.
func shouldRejectUnreadableAutoCreate(
	masterLinked, wasCorrected, hasPhoto, vouchedBySubmit bool,
	editedName, brandName, officialName string,
) bool {
	if masterLinked || wasCorrected || hasPhoto || vouchedBySubmit {
		return false
	}
	// Operator typed a name distinct from the AI's guess → operator-authored;
	// treat as a deliberate manual add and never reject it.
	en := strings.TrimSpace(editedName)
	if en != "" &&
		!strings.EqualFold(en, strings.TrimSpace(brandName)) &&
		!strings.EqualFold(en, strings.TrimSpace(officialName)) {
		return false
	}
	return true
}

// joinUnverifiedBrands renders a short, capped, human-readable brand preview
// for the honest "N rows NOT saved: ..." operator message. Capped at 10 like
// the zero-skip preview so a huge reject list can't bloat the response.
func joinUnverifiedBrands(rows []UnverifiedRow) string {
	names := make([]string, 0, len(rows))
	for _, r := range rows {
		n := strings.TrimSpace(r.BrandName)
		if n == "" {
			n = "(unnamed row)"
		}
		names = append(names, n)
		if len(names) == 10 {
			names = append(names, fmt.Sprintf("… +%d more", len(rows)-10))
			break
		}
	}
	return strings.Join(names, ", ")
}

func sameSpiritFamily(a, b string) bool {
	if a == "" || b == "" {
		return true
	}
	familyOf := func(s string) string {
		s = strings.ToLower(strings.TrimSpace(s))
		switch {
		case strings.Contains(s, "whisk"), strings.Contains(s, "scotch"), strings.Contains(s, "bourbon"):
			return "whisky"
		case strings.Contains(s, "vodka"):
			return "vodka"
		case strings.Contains(s, "rum"):
			return "rum"
		case strings.Contains(s, "gin"):
			return "gin"
		case strings.Contains(s, "brandy"), strings.Contains(s, "cognac"):
			return "brandy"
		case strings.Contains(s, "wine"), strings.Contains(s, "riesling"),
			strings.Contains(s, "cabernet"), strings.Contains(s, "shiraz"),
			strings.Contains(s, "merlot"), strings.Contains(s, "sauvignon"),
			strings.Contains(s, "chardonnay"), strings.Contains(s, "pinot"):
			return "wine"
		case strings.Contains(s, "beer"), strings.Contains(s, "lager"), strings.Contains(s, "ale"):
			return "beer"
		}
		return "other"
	}
	fa, fb := familyOf(a), familyOf(b)
	if fa == "other" || fb == "other" {
		// One side is unrecognisable — don't reject, let the keyword-based
		// gate downstream make the call.
		return true
	}
	return fa == fb
}

// buildAlternatives constructs the AlternativeMatches list from fuzzy results plus
// source-anchored picks. Always pulls prices and names from the DB row (never
// from MatchResult.Price, which was previously bleeding the winner's price into
// every alternative row).
//
// `sourceText` is the OCR brand (raw + AI's official guess concatenated) — used
// to anchor Pass 2 so alternatives are genuinely "products similar to what the
// user wrote", not "siblings of whatever the wrong primary happened to be".
//
// `sourceRate` is the rate the shopkeeper wrote in the register; used to
// re-rank alternatives by MRP-distance via mrpProximityBonus so a row whose
// rate matches a ₹770 product never surfaces ₹800 products at the top.
func buildAlternatives(fuzzyResults []matching.MatchResult, primaryID string, products []dbProduct, maxAlts int, sourceText string, sourceRate float64) []AlternativeMatch {
	if maxAlts <= 0 {
		maxAlts = 5
	}
	alts := make([]AlternativeMatch, 0, maxAlts)
	seen := make(map[string]bool)
	seen[primaryID] = true

	appendIfNew := func(pid string, confidence float64) {
		if seen[pid] || len(alts) >= maxAlts {
			return
		}
		dbP := findProductByID(products, pid)
		if dbP == nil {
			return
		}
		display, full := resolveDisplayAndFullName(dbP)
		alts = append(alts, AlternativeMatch{
			ProductID:             pid,
			BrandName:             display, // backwards compat
			DisplayName:           display,
			DisplayNameBoldStart:  dbP.DisplayNameBoldStart,
			DisplayNameBoldLength: dbP.DisplayNameBoldLength,
			FullName:              full,
			ExciseBrandName:       dbP.ExciseBrandName,
			ExciseDisplayName:     dbP.ExciseDisplayName,
			Size:                  dbP.Size,
			CostPrice:             dbP.CostPrice, // from DB, NEVER from MatchResult.Price
			MRP:                   dbP.MRP,
			Confidence:            confidence,
		})
		seen[pid] = true
	}

	// Pass 1: fuzzy results (already scored + sized-filtered)
	for _, r := range fuzzyResults {
		appendIfNew(r.ProductID, r.Score)
	}

	// Pass 2: source-anchored picks. Use the OCR brand text's distinctive tokens
	// (and bold-key tokens of any product whose bold matches a source token) to
	// surface products similar to what the SHOPKEEPER WROTE — not similar to the
	// possibly-wrong primary. Eliminates "bullshit" alternatives where Jack
	// Daniels → Arthaus then alternatives are all "Arthaus *" variants.
	primary := findProductByID(products, primaryID)
	primarySize := ""
	if primary != nil {
		primarySize = primary.Size
	}
	sourceLower := strings.ToLower(sourceText)
	sourceTokens := distinctiveTokensFromText(sourceLower, 3)
	if len(sourceTokens) >= 1 && len(alts) < maxAlts {
		for i := range products {
			p := &products[i]
			if seen[p.ID] {
				continue
			}
			// Size match avoids suggesting a 180ML variant for a 750ML row
			if primarySize != "" && p.Size != primarySize {
				continue
			}
			// At least one source distinctive token must appear in the candidate
			// (anywhere in name/display/excise/bold). Stronger than primary-anchored
			// because it ties back to what the user actually wrote.
			hay := strings.ToLower(p.Name + " " + p.BrandName + " " + p.DisplayName + " " + p.ExciseBrandName + " " + p.ExciseDisplayName)
			if bold := extractBoldPortion(p.DisplayName, p.DisplayNameBoldStart, p.DisplayNameBoldLength); bold != "" {
				hay += " " + strings.ToLower(bold)
			}
			matches := 0
			for _, t := range sourceTokens {
				if strings.Contains(hay, t) {
					matches++
				}
			}
			if matches == 0 {
				continue
			}
			conf := 0.40 + 0.10*float64(matches)
			appendIfNew(p.ID, conf)
			if len(alts) >= maxAlts {
				break
			}
		}
	}

	// Apply tiered MRP-distance bonus + re-sort by adjusted confidence so the
	// closest-priced alternative surfaces first. Stable sort keeps original
	// fuzzy order as the tiebreaker when MRP-distance is identical.
	//
	// Bonus is added unbounded then clamped — without the clamp a strong
	// fuzzy hit (0.95) plus an exact MRP match could push past 1.0 and
	// cascade into MatchConfidence via autoResolveDuplicateMatches→alt.Confidence,
	// which is exactly what produced 1.035 / 1.097 confidences in chhotu's
	// d982ade6 job (rows 15, 18, 37).
	if sourceRate > 0 {
		for i := range alts {
			alts[i].Confidence = clampConfidence(alts[i].Confidence + mrpProximityBonus(sourceRate, alts[i].MRP))
		}
		sort.SliceStable(alts, func(i, j int) bool {
			return alts[i].Confidence > alts[j].Confidence
		})
	}

	return alts
}

// clampConfidence pins a score into [0, 1]. Single source of truth so any
// new boost path can't quietly produce values >1.0 and pollute the UI.
// Logs at warn level if the pre-clamp score exceeded 1.05 — that's the
// signature of stacked boosts and worth knowing about.
func clampConfidence(score float64) float64 {
	if score > 1.05 {
		log.Printf("Smart Stock Setup: confidence overflow (pre-clamp=%.4f) — boost stacking; clamping to 1.0", score)
	}
	if score > 1.0 {
		return 1.0
	}
	if score < 0 {
		return 0
	}
	return score
}

// shortenForDisplay turns a long all-caps / verbose excise brand name into a tidy
// short form with the first 4-5 significant tokens, title-cased. Used as a fallback
// when saas_brands.display_name is empty so Flutter never shows a blank excise label.
// Examples:
//   "JOHNNIE WALKER BLACK LABEL BLENDED SCOTCH WHISKY 12 Y" → "Johnnie Walker Black Label"
//   "8 PM Special Rare Whisky"                              → "8 PM Special Rare Whisky"
//   "M2 MAGIC MOMENTS REMIX GREEN APPLE FLAVOURED VODKA"    → "M2 Magic Moments Remix Green Apple"
func shortenForDisplay(s string) string {
	if s == "" {
		return ""
	}
	fields := strings.Fields(s)
	out := make([]string, 0, 6)
	// Drop trailing generic words ("WHISKY", "VODKA", etc.) and known noise words ("12 Y", "BLENDED").
	// Keep up to 5 content tokens total; always keep leading short tokens like "M2" / "8".
	for _, tok := range fields {
		lower := strings.ToLower(tok)
		if stockSetupGenericWords[lower] {
			// Skip unless we haven't accumulated anything yet (keep some descriptors)
			if len(out) >= 2 {
				continue
			}
		}
		// Title-case (handle "M2" → "M2", "8PM" → "8PM" stays, "BLACK" → "Black")
		if len(tok) > 1 && !hasAnyDigit(tok) {
			tok = strings.ToUpper(tok[:1]) + strings.ToLower(tok[1:])
		}
		out = append(out, tok)
		if len(out) >= 5 {
			break
		}
	}
	if len(out) == 0 {
		// Fallback: first 4 words title-cased, whatever they are
		for i := 0; i < len(fields) && i < 4; i++ {
			t := fields[i]
			if len(t) > 1 && !hasAnyDigit(t) {
				t = strings.ToUpper(t[:1]) + strings.ToLower(t[1:])
			}
			out = append(out, t)
		}
	}
	return strings.Join(out, " ")
}

func hasAnyDigit(s string) bool {
	for _, r := range s {
		if r >= '0' && r <= '9' {
			return true
		}
	}
	return false
}

// distinctiveTokensFromText returns up to n leading non-generic tokens (length >= 3).
// Used by the same-brand-prefix pass to find products in the same brand family.
func distinctiveTokensFromText(s string, n int) []string {
	tokens := strings.Fields(strings.ToLower(s))
	out := make([]string, 0, n)
	for _, t := range tokens {
		if stockSetupGenericWords[t] {
			continue
		}
		if len(t) < 3 {
			// Keep short brand fragments like "8" (common in "8 PM") by using prefix-like behaviour
			// Only accept if clearly a brand prefix (digit or digit+pm style)
			if len(t) < 1 {
				continue
			}
		}
		out = append(out, t)
		if len(out) >= n {
			break
		}
	}
	return out
}

// buildExtractionAudit summarises data-hygiene gaps so the Flutter Review
// screen can show the user (a) tenant products missing a saas_brand_id link
// and (b) OCR brand names that genuinely have no entry in the master catalog.
//
// orphan = tenant product whose saas_brand_id is empty AND whose size matches
//          the requested capacity (no point flagging products at other sizes).
// missing-master = OCR brand from a row that ended up in `auto_create` AND
//                  whose master suggestions list is empty (i.e. master scorer
//                  found no candidate at any threshold). Deduplicated.
//
// Returns nil when both lists are empty so we don't bloat the JSON response.
func buildExtractionAudit(products []dbProduct, items []SmartStockSetupExtractedItem, masterBrands []models.MasterBrandInfo, sizeML int) *StockSetupAudit {
	var orphans []OrphanTenantProduct
	for i := range products {
		p := &products[i]
		if p.SaasBrandID != "" {
			continue
		}
		// Skip products outside the chosen size — the audit should focus on
		// what's relevant to this extraction, not the entire tenant catalog.
		if sizeML > 0 {
			pSizeML := normalizeSizeText(p.Size)
			if pSizeML > 0 && pSizeML != sizeML {
				continue
			}
		}
		name := firstNonEmpty(p.DisplayName, p.BrandName, p.Name)
		orphans = append(orphans, OrphanTenantProduct{
			ProductID: p.ID,
			Name:      name,
			Size:      p.Size,
			MRP:       p.MRP,
		})
	}

	missingSeen := make(map[string]bool)
	var missing []string
	for i := range items {
		it := &items[i]
		if it.Status != "auto_create" {
			continue
		}
		if len(it.MasterBrandSuggestions) > 0 {
			// Master had a candidate — not truly missing, just unmatched.
			continue
		}
		key := strings.ToLower(strings.TrimSpace(firstNonEmpty(it.OfficialBrandName, it.BrandName)))
		if key == "" || missingSeen[key] {
			continue
		}
		missingSeen[key] = true
		missing = append(missing, firstNonEmpty(it.OfficialBrandName, it.BrandName))
	}

	if len(orphans) == 0 && len(missing) == 0 {
		return nil
	}
	return &StockSetupAudit{
		OrphanProducts:      orphans,
		MissingMasterBrands: missing,
	}
}

// findTenantProductByMasterRouting routes an OCR row through the master catalog:
//   1. Match the OCR text (raw + AI's official guess) against saas_brands via
//      findMasterBrand (the same scorer that uses bold-key + MRP + tokens).
//   2. If a master brand matches confidently, look up the tenant product whose
//      saas_brand_id == master.BrandID AND whose size matches.
//   3. Return that product so the caller can promote the row to "matched"
//      instead of falling back to auto_create / not_found.
//
// Rationale: a brand that's been onboarded by this tenant always has its
// products linked to saas_brands. So when tenant-name fuzzy fails on garbled
// OCR (e.g. "M2 Crn" → fuzzy can't reach "M2 Magic Moments Cranberry Vodka"),
// master matching can hop OCR→master→tenant via the link. This eliminates
// most spurious auto_create rows for brands the tenant already owns.
//
// Returns (nil, nil, "") when no confident master match or no tenant product
// links to that master entry.
func (s *SmartStockSetupService) findTenantProductByMasterRouting(extracted ExtractedStockRegisterItem, products []dbProduct, masterBrands []models.MasterBrandInfo) (*dbProduct, *models.MasterBrandInfo, string) {
	queryName := extracted.OfficialBrandName
	if queryName == "" {
		queryName = extracted.Brand
	}
	if queryName == "" {
		return nil, nil, ""
	}
	master := s.findMasterBrand(queryName, extracted.SizeML, extracted.Rate, masterBrands)
	if master == nil || master.BrandID == "" {
		return nil, nil, ""
	}
	// Find the tenant product linked to this master brand at the right size.
	// Size matching is loose — tenant size strings can differ in casing/format
	// (e.g. "750ML" vs "750 ml") so compare normalised mL when available.
	masterSizeML := normalizeSizeText(master.Size)
	for i := range products {
		p := &products[i]
		if p.SaasBrandID == "" || p.SaasBrandID != master.BrandID {
			continue
		}
		// Prefer exact-size match; if no products at this size, the tenant
		// just hasn't onboarded the size — fall through and try other sizes.
		if extracted.SizeML > 0 {
			pSizeML := normalizeSizeText(p.Size)
			if pSizeML > 0 && pSizeML != extracted.SizeML {
				continue
			}
		} else if masterSizeML > 0 {
			pSizeML := normalizeSizeText(p.Size)
			if pSizeML > 0 && pSizeML != masterSizeML {
				continue
			}
		}
		return p, master, "exact"
	}
	// Fallback: any size linked to the same master — only if no size info on the OCR.
	if extracted.SizeML == 0 {
		for i := range products {
			p := &products[i]
			if p.SaasBrandID != "" && p.SaasBrandID == master.BrandID {
				return p, master, "any_size"
			}
		}
	}
	return nil, master, ""
}

// mrpProximityBonus returns a tiered score adjustment based on how close the
// register's Rate column is to a candidate product's MRP. Single source of
// truth for MRP-distance scoring across alternatives + master suggestions.
//
// Tiers:
//   ±₹10  → +0.30 (the user's exact rate — strongest evidence we have)
//   ±₹30  → +0.20
//   ±₹60  → +0.10
//   ≤₹150 →  0.00 (neutral — common variance from outdated MRP)
//   >₹150 → -0.15 (heavy demote — likely the wrong product)
//
// Returns 0 when either side is missing so a missing rate never demotes a
// match (the fuzzy / token / bold scores still drive the decision).
func mrpProximityBonus(rate, mrp float64) float64 {
	if rate <= 0 || mrp <= 0 {
		return 0
	}
	diff := rate - mrp
	if diff < 0 {
		diff = -diff
	}
	switch {
	case diff <= 10:
		return 0.30
	case diff <= 30:
		return 0.20
	case diff <= 60:
		return 0.10
	case diff <= 150:
		return 0
	default:
		return -0.15
	}
}

// extractBoldPortion returns the substring of `name` defined by the optional
// (start, length) bold range. Used to surface the "essential identifier" of a
// brand to the AI — e.g. for "100 Strokes Royal Whisky" with start=0 length=11
// it returns "100 Strokes". Falls back to "" when the bounds are nil/invalid
// or when the range covers the whole string (no point repeating).
func extractBoldPortion(name string, start, length *int) string {
	if start == nil || length == nil || *length <= 0 || name == "" {
		return ""
	}
	runes := []rune(name)
	if *start < 0 || *start >= len(runes) {
		return ""
	}
	end := *start + *length
	if end > len(runes) {
		end = len(runes)
	}
	bold := strings.TrimSpace(string(runes[*start:end]))
	if bold == "" {
		return ""
	}
	if strings.EqualFold(strings.TrimSpace(name), bold) {
		// Bold == full string ⇒ no extra signal.
		return ""
	}
	return bold
}

// flavorMismatchToken returns ("token", true) when the source text (raw OCR
// brand + the AI's official guess) carries a flavour/variant token that none
// of the candidate name fields contain — or vice versa. Symmetric so both
// "M2 Cranberry" → "Magic Moments Vodka" and the reverse get rejected.
//
// Used by both the AI-index acceptance check and the fuzzy-match guard to keep
// flavored / sub-variant brands from collapsing into the plain base brand.
// The static distinguisher list catches the well-known cross-family bleeds
// (rum vs whisky tokens, premium tiers shared across many brands). For
// catalog-specific variants we ALSO call siblingDistinguisherMismatch which
// derives the discriminator set dynamically from the actual product universe.
func flavorMismatchToken(rawBrand, officialBrand, matchedBrand, matchedName, matchedDisplay string) (string, bool) {
	srcLower := strings.ToLower(rawBrand + " " + officialBrand)
	matchedLower := strings.ToLower(matchedBrand + " " + matchedName + " " + matchedDisplay)
	distinguishers := []string{"green apple", "orange", "cranberry", "jamun", "lemon", "limon",
		"mango", "coffee", "spiced", "gold", "black", "blue", "barrel select", "double dark",
		"reserve collection", "legend", "matured", "premium black", "triple gold",
		"100 strokes", "100 pipers", "old monk", "bacardi",
		"watermelon", "litchi", "verve", "pineapple", "chocolate", "cola", "spicymint",
		"m2", "remix"}
	for _, d := range distinguishers {
		if strings.Contains(srcLower, d) != strings.Contains(matchedLower, d) {
			return d, true
		}
	}
	return "", false
}

// brandSiblingIndex maps a brand-family key to the set of "discriminator
// tokens" — tokens that appear in some variants of that family but not all.
// E.g. for "American Pride" with variants {Whisky, Black, Reserve, Premium},
// the discriminator set is {black, reserve, premium}; "whisky" is shared so
// it doesn't discriminate.
//
// Family key: prefer SaasBrandID when available, otherwise fall back to the
// first 2 distinctive tokens of the product's display/name. The fallback
// covers products that aren't yet linked to the master catalog.
type brandSiblingIndex map[string]map[string]struct{}

func buildBrandSiblingIndex(products []dbProduct) brandSiblingIndex {
	// First pass: per-family token counts + variant counts.
	type counts struct {
		variants int
		tokens   map[string]int
	}
	per := make(map[string]*counts)
	keyOf := func(p *dbProduct) string {
		if p.SaasBrandID != "" {
			return "sb:" + p.SaasBrandID
		}
		tokens := distinctiveTokensFromText(firstNonEmpty(p.DisplayName, p.BrandName, p.Name), 2)
		if len(tokens) == 0 {
			return ""
		}
		return "fn:" + strings.Join(tokens, " ")
	}
	for i := range products {
		p := &products[i]
		k := keyOf(p)
		if k == "" {
			continue
		}
		c, ok := per[k]
		if !ok {
			c = &counts{tokens: map[string]int{}}
			per[k] = c
		}
		c.variants++
		seen := map[string]bool{}
		hay := strings.ToLower(p.Name + " " + p.DisplayName + " " + p.BrandName)
		for _, t := range strings.Fields(hay) {
			if len(t) < 3 || stockSetupGenericWords[t] {
				continue
			}
			if !seen[t] {
				c.tokens[t]++
				seen[t] = true
			}
		}
	}
	// Second pass: discriminator = present in ≥1 variant but NOT all.
	idx := make(brandSiblingIndex, len(per))
	for k, c := range per {
		if c.variants < 2 {
			// Single-variant family has no siblings — nothing to discriminate.
			continue
		}
		set := make(map[string]struct{})
		for tok, cnt := range c.tokens {
			if cnt > 0 && cnt < c.variants {
				set[tok] = struct{}{}
			}
		}
		if len(set) > 0 {
			idx[k] = set
		}
	}
	return idx
}

// siblingDistinguisherMismatch returns ("token", true) when the source carries
// a discriminator token from the matched product's family that the matched
// product itself does NOT have (or vice versa). Dynamic version of
// flavorMismatchToken — works for any brand family represented in the catalog,
// no hardcoded list required.
func siblingDistinguisherMismatch(rawBrand, officialBrand string, matched *dbProduct, idx brandSiblingIndex) (string, bool) {
	if matched == nil || idx == nil {
		return "", false
	}
	var key string
	if matched.SaasBrandID != "" {
		key = "sb:" + matched.SaasBrandID
	} else {
		tokens := distinctiveTokensFromText(firstNonEmpty(matched.DisplayName, matched.BrandName, matched.Name), 2)
		if len(tokens) == 0 {
			return "", false
		}
		key = "fn:" + strings.Join(tokens, " ")
	}
	siblings, ok := idx[key]
	if !ok || len(siblings) == 0 {
		return "", false
	}
	srcLower := strings.ToLower(rawBrand + " " + officialBrand)
	matchedLower := strings.ToLower(matched.Name + " " + matched.DisplayName + " " + matched.BrandName)
	srcTokens := strings.Fields(srcLower)
	for _, t := range srcTokens {
		if len(t) < 3 || stockSetupGenericWords[t] {
			continue
		}
		if _, isSibling := siblings[t]; !isSibling {
			continue
		}
		// Source carries a discriminator. Matched MUST also carry it.
		if !strings.Contains(matchedLower, t) {
			return t, true
		}
	}
	// Reverse: matched carries a sibling discriminator the source doesn't have.
	matchedTokens := strings.Fields(matchedLower)
	for _, t := range matchedTokens {
		if len(t) < 3 || stockSetupGenericWords[t] {
			continue
		}
		if _, isSibling := siblings[t]; !isSibling {
			continue
		}
		if !strings.Contains(srcLower, t) {
			return t, true
		}
	}
	return "", false
}

// productContainsAllTokens returns true if every token appears (case-insensitive) in
// any of Name / BrandName / DisplayName / ExciseBrandName / ExciseDisplayName.
func productContainsAllTokens(p *dbProduct, tokens []string) bool {
	hay := strings.ToLower(p.Name + " " + p.BrandName + " " + p.DisplayName + " " + p.ExciseBrandName + " " + p.ExciseDisplayName)
	for _, t := range tokens {
		if !strings.Contains(hay, t) {
			return false
		}
	}
	return true
}

// matchAndEnrich matches an extracted register row to a product and builds the response item
// loadShopLearnedRates returns a map of product_id (string) → last user-
// corrected rate for the given (tenant, shop). Empty map when no
// corrections exist yet. v1.0.125.
func (s *SmartStockSetupService) loadShopLearnedRates(tenantID, shopID uuid.UUID) map[string]float64 {
	out := map[string]float64{}
	if shopID == uuid.Nil {
		return out
	}
	type row struct {
		ProductID    uuid.UUID `gorm:"column:product_id"`
		LastUserRate float64   `gorm:"column:last_user_rate"`
	}
	var rows []row
	err := s.db.Table("shop_product_rates").
		Select("product_id, last_user_rate").
		Where("tenant_id = ? AND shop_id = ?", tenantID, shopID).
		Scan(&rows).Error
	if err != nil {
		log.Printf("Smart Stock Setup: failed to load shop learned rates: %v", err)
		return out
	}
	for _, r := range rows {
		out[r.ProductID.String()] = r.LastUserRate
	}
	return out
}

// v1.0.160 — added shopID so the alias-table fast-path uses the shop-scoped
// cascade. Pass uuid.Nil to fall back to tenant-wide lookup (legacy).
// v1.0.247 — added pageCategoryName + categoryNameByID to power the page-level
// category gate. pageCategoryName is what the operator picked at upload
// ("Whisky"/"Vodka"/"Rum"/"Gin"/"Brandy"/"Beer"); categoryNameByID resolves a
// product's category UUID → name so we can reject cross-family matches BEFORE
// OCR text contains an explicit category keyword (chhotu's "Bleck Labol" →
// "LA AMANTE CABERNET SHIRAZ" case where the wine product slipped past the
// keyword-based guard because neither side mentioned a category word).
func (s *SmartStockSetupService) matchAndEnrich(extracted ExtractedStockRegisterItem, products []dbProduct, stockMap map[string]int, stockColumn string, tenantID, shopID uuid.UUID, masterBrands []models.MasterBrandInfo, brandSiblings brandSiblingIndex, learnedRates map[string]float64, productSynonyms map[string][]string, tenantStats map[string]TenantInventoryStat, pageCategoryName string, categoryNameByID map[string]string) SmartStockSetupExtractedItem {
	stockQty := determineStockQuantity(extracted, stockColumn)

	// Use official_brand_name as the display name when available — it's the AI's
	// best guess at the correct brand name. The raw OCR text (extracted.Brand) is
	// kept in OfficialBrandName's pair. Flutter shows BrandName as editable default.
	displayName := extracted.Brand
	if extracted.OfficialBrandName != "" {
		displayName = extracted.OfficialBrandName
	}

	// Cross-validate against master brand data (UP Excise) using name + MRP
	masterMatch := s.findMasterBrand(displayName, extracted.SizeML, extracted.Rate, masterBrands)
	masterMRP := 0.0
	masterVariantID := ""
	if masterMatch != nil && masterMatch.BrandName != "" {
		// Use display name for user-facing result; fall back to official excise name
		if masterMatch.DisplayName != "" {
			displayName = masterMatch.DisplayName
		} else {
			displayName = masterMatch.BrandName
		}
		masterMRP = masterMatch.MRP
		masterVariantID = masterMatch.VariantID
	}

	// If AI couldn't read the rate, use master MRP (prevents ₹1.00 garbage)
	effectiveRate := extracted.Rate
	if effectiveRate <= 0 && masterMRP > 0 {
		effectiveRate = masterMRP
		log.Printf("Smart Stock Setup: Using master MRP ₹%.0f for '%s' (AI rate=0)", masterMRP, displayName)
	}

	item := SmartStockSetupExtractedItem{
		RowNumber:            extracted.RowNumber,
		PageNumber:           extracted.PageNumber,
		OriginalPrintedBrand: extracted.OriginalPrintedBrand,
		Source:               extracted.Source,
		BrandName:            displayName,
		// v1.0.117: capture AI's first-guess brand BEFORE displayName overwrites
		// happen (master match, brand auto-heal, name patches). Plumbed through
		// to Flutter so the review screen can preserve it across user mutations
		// and round-trip it on apply for alias learning.
		OriginalAIBrand: extracted.Brand,
		Size:                 extracted.SizeText,
		SizeML:               extracted.SizeML,
		Category:             extracted.Category,
		Opening:              extracted.Opening,
		Receipt:              extracted.Receipt,
		Total:                extracted.Total,
		Sale:                 extracted.Sale,
		Rate:                 effectiveRate,
		Amount:               extracted.Amount,
		ClosingStock:         extracted.Closing,
		StockQuantity:        stockQty,
		OfficialBrandName:    extracted.OfficialBrandName,
		MasterMRP:            masterMRP,
		MasterVariantID:      masterVariantID,
		FieldConfidence:      extracted.FieldConfidence,
	}

	// v1.0.185 Track S5 — doubt-popup queue. Emit per-cell doubts derived from
	// the Textract field-confidence map + arithmetic invariants. Flutter walks
	// the non-auto-fixed entries one-by-one BEFORE the review screen so the
	// operator confirms or corrects each ambiguous cell ONCE; the answer is
	// captured into ocr_digit_corrections and silently auto-fixed in every
	// future extraction at this shop ("ask once, learn forever").
	item.CellDoubts = emitTextractCellDoubts(extracted, extracted.FieldConfidence)

	// Even unmatched / auto_create rows must get MRP from master when available;
	// post-hoc loop only fills already-linked products, leaving zero rates on the rest.
	if item.Rate == 0 && masterMRP > 0 {
		item.Rate = masterMRP
	}

	if extracted.SizeML > 0 && item.Size == "" {
		item.Size = fmt.Sprintf("%dML", extracted.SizeML)
	}

	// Arithmetic cross-validation warnings
	if extracted.Opening+extracted.Receipt != extracted.Total && extracted.Total > 0 {
		item.Warnings = append(item.Warnings,
			fmt.Sprintf("Total (%d) ≠ Opening (%d) + Receipt (%d)", extracted.Total, extracted.Opening, extracted.Receipt))
	}
	if extracted.Total-extracted.Sale != extracted.Closing && extracted.Closing > 0 {
		item.Warnings = append(item.Warnings,
			fmt.Sprintf("Closing (%d) ≠ Total (%d) - Sale (%d)", extracted.Closing, extracted.Total, extracted.Sale))
	}

	// Build prepared product set ONCE at the top so every match path (alias, ai_index,
	// fuzzy) can generate rich alternatives via buildAlternatives. Previously the alias
	// and ai_index paths short-circuited before alternatives were computed — users saw
	// zero alternatives on those matches.
	matchProducts := make([]matching.Product, len(products))
	for pi, p := range products {
		brandName := p.BrandName
		if brandName == "" {
			brandName = p.Name
		}
		ts := tenantStats[p.ID]
		matchProducts[pi] = matching.Product{
			ID:                p.ID,
			Name:              p.Name,
			BrandName:         brandName,
			DisplayName:       p.DisplayName,
			ExciseBrandName:   p.ExciseBrandName,
			ExciseDisplayName: p.ExciseDisplayName,
			// v1.0.187 — feed master meta_keywords as synonyms so the
			// fuzzy matcher recognizes operator shorthand ("MCD" / "OC" /
			// "M.M" / "Iconic" etc.) at parity with Smart Sale.
			Synonyms:          productSynonyms[p.ID],
			Size:              p.Size,
			SizeML:            matching.ParseSizeML(p.Size),
			SellingPrice:      p.SellingPrice,
			CostPrice:         p.CostPrice,
			// v1.0.199 — tenant-inventory bias inputs.
			TenantTotalStockUnits: ts.TotalStockUnits,
			TenantSoldDaysAgo:     ts.SoldDaysAgo,
			TenantConfirmedAlias:  ts.HasConfirmedAlias,
		}
	}
	prepared := matching.PrepareProducts(matchProducts)
	// Closure: run fuzzy matcher for the given query text; used by every path that wants alternatives.
	altCfg := matching.DefaultStockSetupConfig()
	altCfg.MaxResults = 8 // widen pool so alternatives can show 8 PM family etc.
	if effectiveRate > 0 {
		altCfg.EnablePriceMatching = true
	}
	// v1.0.199 — turn tenant-inventory bias on by default; opt-out via env.
	if !envBoolOff("SMART_STOCK_SETUP_TENANT_BIAS") {
		altCfg.TenantInventoryBias = true
	}
	runFuzzy := func(query string) []matching.MatchResult {
		if query == "" {
			return nil
		}
		return matching.MatchProducts(query, extracted.SizeML, effectiveRate, prepared, altCfg)
	}

	// Fast path: check alias table for instant match.
	// Stock Setup differs from Smart Sale: the extractor schema returns ONLY
	// Brand (no separate raw OCR field), so unlike Smart Sale's matcher we
	// can't try raw OCR first. Aliases are looked up by extracted.Brand —
	// which is the same key captureApplyLearning uses for Stock Setup
	// (smart_stock_setup_learning.go writes aliases from item.OCRText, but
	// stock-setup OCR text on the apply payload comes from the same Brand
	// field at extraction time → keys are consistent for this flow).
	if s.aliasService != nil {
		// v1.0.160 — shop-scoped alias cascade. Shop-specific aliases fire
		// first; falls through to tenant-wide on miss; then to fuzzy. Negative
		// aliases at either scope block hits.
		productID, _, _, found := s.aliasService.LookupAliasCascade(context.Background(), tenantID, shopID, extracted.Brand, "")
		if found && productID != nil {
			pidStr := productID.String()
			for _, p := range products {
				if p.ID == pidStr {
					pp := p
					item.ProductID = &pp.ID
					display, full := resolveDisplayAndFullName(&pp)
					item.MatchedDisplayName = display
					item.MatchedDisplayNameBoldStart = pp.DisplayNameBoldStart
					item.MatchedDisplayNameBoldLength = pp.DisplayNameBoldLength
					item.MatchedFullName = full
					item.MatchedBrandName = display // backwards compat
					item.MatchedExciseBrandName = pp.ExciseBrandName
					item.MatchedExciseDisplayName = pp.ExciseDisplayName
					item.MatchConfidence = 1.0
					item.Status = "matched"
					if stock, ok := stockMap[pp.ID]; ok {
						item.CurrentStock = &stock
					}
					item.AlternativeMatches = buildAlternatives(runFuzzy(extracted.Brand), pp.ID, products, 5, extracted.Brand+" "+extracted.OfficialBrandName, extracted.Rate)
					log.Printf("Smart Stock Setup: ALIAS HIT '%s' -> product '%s' (display '%s')", extracted.Brand, pp.Name, display)
					s.logMatchOutcome(&item, extracted, "alias", "", 0)
					return item
				}
			}
		}
	}

	// AI-matched product (from product-aware prompt) — validate name before trusting.
	// "100 st" should NOT match "Royal Stag" just because AI picked wrong index.
	// The gate checks OCR brand against ALL three product name fields (brand, display, full)
	// using both Levenshtein similarity AND token overlap — OCR text is short, full name is
	// long, so Levenshtein alone scores low even when the match is actually correct
	// (e.g. "Iconiq - white" vs "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY - 750ML").
	if extracted.MatchedProductIdx > 0 && extracted.MatchedProductIdx <= len(products) {
		p := products[extracted.MatchedProductIdx-1] // 1-based → 0-based
		brandLower := strings.ToLower(extracted.Brand)
		brandTokens := strings.Fields(brandLower)

		// Generic/category words that don't prove a match by themselves.
		// Without this filter, Jaccard on {"old", "monk", "the", "legend", "rum"} vs
		// {"the", "rockford", "reserve", "fine", "rare"} would match on "the" and let
		// the wrong product through. Require at least one DISTINCTIVE token to match.
		genericWords := stockSetupGenericWords

		// Best-of-three over (brand_name, name, display_name) using Levenshtein + distinctive-token Jaccard
		bestSim := 0.0
		bestField := ""
		bestContains := false
		distinctiveMatchCount := 0 // count across all fields of distinctive tokens shared
		checkField := func(fieldName, fieldValue string) {
			if fieldValue == "" {
				return
			}
			f := strings.ToLower(fieldValue)
			sim := matching.StringSimilarity(brandLower, f)
			// Distinctive-token Jaccard: |A ∩ B over distinctive tokens| / |A ∪ B over distinctive tokens|
			ftokens := strings.Fields(f)
			if len(brandTokens) > 0 && len(ftokens) > 0 {
				inter := 0
				distinctiveInter := 0
				seen := make(map[string]bool)
				distinctiveInBrand := 0
				for _, bt := range brandTokens {
					if len(bt) < 2 {
						continue
					}
					isDistinctive := !genericWords[bt] && len(bt) >= 3
					if isDistinctive {
						distinctiveInBrand++
					}
					for _, pt := range ftokens {
						if bt == pt || (len(bt) >= 3 && (strings.HasPrefix(pt, bt) || strings.HasPrefix(bt, pt))) {
							if !seen[bt] {
								inter++
								if isDistinctive {
									distinctiveInter++
								}
								seen[bt] = true
							}
							break
						}
					}
				}
				if distinctiveInter > distinctiveMatchCount {
					distinctiveMatchCount = distinctiveInter
				}
				union := len(brandTokens) + len(ftokens) - inter
				if union > 0 {
					jaccard := float64(inter) / float64(union)
					if jaccard > sim {
						sim = jaccard
					}
				}
			}
			if sim > bestSim {
				bestSim = sim
				bestField = fieldName
			}
			if strings.Contains(f, brandLower) || strings.Contains(brandLower, f) {
				bestContains = true
			}
		}
		checkField("brand", p.BrandName)
		checkField("name", p.Name)
		checkField("display", p.DisplayName)

		// Accept AI's pick only if:
		//   (a) substring containment (very strong signal), OR
		//   (b) good similarity AND at least one distinctive token actually matched
		// This prevents "Old Monk The Legend Rum" → "The Rockford Reserve Fine & Rare"
		// where only "the" overlaps and Jaccard is misleading.
		if bestContains || (bestSim >= 0.50 && distinctiveMatchCount >= 1) {
			// Flavour guard: even if tokens overlap, reject when source carries a
			// flavour/variant token that the matched product doesn't (or vice versa).
			// Catches AI picking plain "Magic Moments Vodka" for "M2 Cranberry" rows.
			// Two layers: static cross-family list + dynamic per-family sibling set
			// derived from the actual catalog (covers American Pride / any future brand).
			staticWord, staticMismatch := flavorMismatchToken(extracted.Brand, extracted.OfficialBrandName, p.BrandName, p.Name, p.DisplayName)
			dynWord, dynMismatch := siblingDistinguisherMismatch(extracted.Brand, extracted.OfficialBrandName, &p, brandSiblings)
			// Label-color guard: within the same brand family (e.g. Johnnie Walker),
			// different Label colors are different SKUs. Reject cross-color matches
			// that the generic fuzzy/token guards miss (Red↔Blue↔Black↔Blonde etc.).
			candidateName := p.DisplayName
			if candidateName == "" {
				candidateName = p.BrandName
			}
			colorConflictSrc := extracted.Brand + " " + extracted.OfficialBrandName
			colorConflict := hasLabelColorConflict(colorConflictSrc, candidateName) ||
				hasLabelColorConflict(colorConflictSrc, p.Name)
			// Family-root gate — SAME color but DIFFERENT family. Catches the
			// "JW Black Label" → "Black & White Celebration" pattern that
			// color-conflict misses.
			familyConflict := false
			if !colorConflict && labelColorIn(strings.ToLower(colorConflictSrc)) != "" {
				srcRoots := familyRootTokens(strings.ToLower(colorConflictSrc))
				if len(srcRoots) > 0 {
					candRoots := familyRootTokens(strings.ToLower(candidateName + " " + p.Name))
					shared := false
					for t := range srcRoots {
						if _, ok := candRoots[t]; ok {
							shared = true
							break
						}
					}
					if !shared {
						familyConflict = true
					}
				}
			}
			if staticMismatch || dynMismatch || colorConflict || familyConflict {
				word := staticWord
				if dynMismatch {
					word = dynWord
				}
				if colorConflict && word == "" {
					word = "label-color"
				}
				if familyConflict && word == "" {
					word = "family-root"
				}
				log.Printf("Smart Stock Setup: AI index %d REJECTED on flavour/color/family guard — '%s' missing/extra '%s' vs '%s' (static=%v dyn=%v color=%v family=%v)",
					extracted.MatchedProductIdx, extracted.Brand, word, p.Name, staticMismatch, dynMismatch, colorConflict, familyConflict)
				if colorConflict || familyConflict {
					item.variantRejected = true
				}
			} else {
				// AI's match is plausible — trust it for product_id
				item.ProductID = &p.ID
				display, full := resolveDisplayAndFullName(&p)
				item.MatchedDisplayName = display
				item.MatchedDisplayNameBoldStart = p.DisplayNameBoldStart
				item.MatchedDisplayNameBoldLength = p.DisplayNameBoldLength
				item.MatchedFullName = full
				item.MatchedBrandName = display // backwards compat
				item.MatchedExciseBrandName = p.ExciseBrandName
				item.MatchedExciseDisplayName = p.ExciseDisplayName
				item.MatchConfidence = 0.95
				item.Status = "matched"
				if stock, ok := stockMap[p.ID]; ok {
					item.CurrentStock = &stock
				}
				// Populate alternatives from a fresh fuzzy run (reuses prepared products).
				item.AlternativeMatches = buildAlternatives(runFuzzy(extracted.Brand), p.ID, products, 5, extracted.Brand+" "+extracted.OfficialBrandName, extracted.Rate)
				s.logMatchOutcome(&item, extracted, "ai_index", "", 0)
				return item
			}
		}
		// AI's match doesn't match any of the product name fields — fall through to fuzzy matching
		log.Printf("Smart Stock Setup: AI index %d rejected — '%s' not similar (best=%s, score=%.2f, distinctive_match=%d)",
			extracted.MatchedProductIdx, extracted.Brand, bestField, bestSim, distinctiveMatchCount)
	}

	// Use unified matching engine with price awareness.
	// matchProducts/prepared/altCfg were already built at the top of this function.
	// Try raw brand first; fall back to AI's official name if the raw match was weak.
	results := runFuzzy(extracted.Brand)

	if extracted.OfficialBrandName != "" && (len(results) == 0 || (len(results) > 0 && results[0].Score < 0.8)) {
		officialResults := runFuzzy(extracted.OfficialBrandName)
		if len(officialResults) > 0 && (len(results) == 0 || officialResults[0].Score > results[0].Score) {
			results = officialResults
		}
	}

	if len(results) == 0 {
		// Tenant fuzzy returned nothing. Try master-routing — OCR → saas_brands
		// → tenant product with that saas_brand_id. Catches handwriting like
		// "M2 Crn" that fuzzy can't reach but findMasterBrand can hop through.
		if dbP, master, mode := s.findTenantProductByMasterRouting(extracted, products, masterBrands); dbP != nil {
			display, full := resolveDisplayAndFullName(dbP)
			item.ProductID = &dbP.ID
			item.MatchedDisplayName = display
			item.MatchedDisplayNameBoldStart = dbP.DisplayNameBoldStart
			item.MatchedDisplayNameBoldLength = dbP.DisplayNameBoldLength
			item.MatchedFullName = full
			item.MatchedBrandName = display
			if dbP.ExciseBrandName != "" {
				item.MatchedExciseBrandName = dbP.ExciseBrandName
			} else {
				item.MatchedExciseBrandName = master.BrandName
			}
			if dbP.ExciseDisplayName != "" {
				item.MatchedExciseDisplayName = dbP.ExciseDisplayName
			} else if master.DisplayName != "" {
				item.MatchedExciseDisplayName = master.DisplayName
			}
			item.MatchConfidence = 0.85
			item.Status = "matched"
			if stock, ok := stockMap[dbP.ID]; ok {
				item.CurrentStock = &stock
			}
			item.AlternativeMatches = buildAlternatives(runFuzzy(display), dbP.ID, products, 5, extracted.Brand+" "+extracted.OfficialBrandName, extracted.Rate)
			log.Printf("Smart Stock Setup: master-routing rescue row %d: \"%s\" → \"%s\" via master \"%s\" (%s)",
				extracted.RowNumber, extracted.Brand, display, master.BrandName, mode)
			s.logMatchOutcome(&item, extracted, "master_routing", "", 0)
			return item
		}
		// No tenant match AND no master link → real not_found. User picks via UI.
		item.Status = "not_found"
		item.MatchConfidence = 0
		s.logMatchOutcome(&item, extracted, "not_found", "", 0)
		return item
	}

	bestMatch := results[0]

	// Guard: variant/flavour/category mismatch. Applies to EVERY fuzzy match (not just
	// when OfficialBrandName is set) because the OCR brand text itself carries the variant
	// signal. Two kinds of mismatches:
	//   1. Variant/flavour: "Magic Moments Vodka" ≠ "M2 Magic Moments Jamun Spicymint"
	//   2. Spirit category: "Bacardi Limon Citrus Rum" ≠ "ROCKFORD CLASSIC ... WHISKY"
	// Run the variant guard ALWAYS, not only when score < 0.95. A high fuzzy
	// score happily aligns "M2 Cranberry" with "Magic Moments Vodka" because
	// brand tokens overlap heavily — the score doesn't penalise the dropped
	// flavour. The flavour guard is the only thing that catches it.
	{
		guardSource := extracted.OfficialBrandName
		if guardSource == "" {
			guardSource = extracted.Brand
		}
		sourceLower := strings.ToLower(guardSource)
		matchedLower := strings.ToLower(bestMatch.ProductName)
		matchedDisplayLower := ""
		if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
			matchedDisplayLower = strings.ToLower(firstNonEmpty(dbP.DisplayName, dbP.BrandName, dbP.Name))
		}
		// 1. Variant distinguishers — flavored vodkas, premium tiers, sub-brands.
		// Newly added: watermelon/litchi/verve/pineapple/chocolate/cola/spicymint
		// for the M2/Magic Moments Remix family the user is hitting.
		distinguishers := []string{"green apple", "orange", "cranberry", "jamun", "lemon", "limon",
			"mango", "coffee", "spiced", "gold", "black", "blue", "barrel select", "double dark",
			"reserve collection", "legend", "matured", "premium black", "triple gold",
			"100 strokes", "100 pipers", "old monk", "bacardi",
			"watermelon", "litchi", "verve", "pineapple", "chocolate", "cola", "spicymint",
			"m2", "remix"}
		mismatch := false
		mismatchWord := ""
		for _, d := range distinguishers {
			inSource := strings.Contains(sourceLower, d)
			inMatched := strings.Contains(matchedLower, d) || strings.Contains(matchedDisplayLower, d)
			if inSource != inMatched {
				mismatch = true
				mismatchWord = d
				break
			}
		}
		// WS-2.3: also consult ACTIVE-LEARNING distinguishers — tokens that
		// user corrections promoted via RefreshDistinguishers (runs every 15min,
		// requires 3+ correction hits to promote). Lets the matcher catch
		// catalog-specific flavor/variant tokens we never hand-listed. Only
		// applies when the static loop didn't already mismatch.
		if !mismatch {
			for _, t := range strings.Fields(sourceLower + " " + matchedLower + " " + matchedDisplayLower) {
				if !DerivedDistinguisher(t) {
					continue
				}
				inSource := strings.Contains(sourceLower, t)
				inMatched := strings.Contains(matchedLower, t) || strings.Contains(matchedDisplayLower, t)
				if inSource != inMatched {
					mismatch = true
					mismatchWord = "learned: " + t
					break
				}
			}
		}
		// Label-color guard: catches bidirectional Red↔Blue/Black↔Blonde swaps
		// within the same brand family that the one-way `distinguishers` list misses.
		// Requires shared family root so unrelated products aren't flagged.
		if !mismatch {
			candText := matchedLower + " " + matchedDisplayLower
			if hasLabelColorConflict(sourceLower, candText) {
				mismatch = true
				mismatchWord = "label-color"
			}
		}
		// Cross-family conflict (SHARED house prefix only, DIFFERENT identifier).
		// "Royal Green" vs "Royal Stag" both share "royal" but diverge on the
		// brand-identifying second token. chhotu d982ade6 row 18 was matching
		// these at 1.097 confidence. Always-on; complements the label-color
		// family check below.
		if !mismatch {
			cand := matchedLower + " " + matchedDisplayLower
			if crossFamilyConflict(sourceLower, cand) {
				mismatch = true
				mismatchWord = "cross-family"
			}
		}
		// Family-root gate (SAME color, DIFFERENT family). Catches "Johnnie
		// Walker Black Label" being fuzzy-matched to "Black & White Celebration"
		// — both contain "black" so the color-conflict check passes through,
		// but the families are unrelated (walker ≠ celebration). Only kicks in
		// when source carries a label-color token so normal searches stay
		// unaffected.
		if !mismatch && labelColorIn(sourceLower) != "" {
			srcRoots := familyRootTokens(sourceLower)
			if len(srcRoots) > 0 {
				candRoots := familyRootTokens(matchedLower + " " + matchedDisplayLower)
				shared := false
				for t := range srcRoots {
					if _, ok := candRoots[t]; ok {
						shared = true
						break
					}
				}
				if !shared {
					mismatch = true
					mismatchWord = "family-root"
				}
			}
		}
		// Dynamic per-family sibling guard. Catches catalog-specific variants
		// the static list doesn't know about (e.g. American Pride Black vs
		// American Pride Premium, or any future brand the user adds).
		if !mismatch {
			if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
				if word, dyn := siblingDistinguisherMismatch(extracted.Brand, extracted.OfficialBrandName, dbP, brandSiblings); dyn {
					mismatch = true
					mismatchWord = "sibling: " + word
				}
			}
		}
		// 2a. v1.0.247 — Page-level category gate. When the operator picks
		// "Whisky 750ml" at upload, every row on the register is in that family.
		// If the matched product's DB category belongs to a different spirit
		// family (e.g. wine), reject. This fires even when neither the OCR text
		// nor the matched-product name contains an explicit category word —
		// which is the failure mode for chhotu's "Indri → I Heart Riesling" and
		// "Bleck Labol → LA AMANTE CABERNET SHIRAZ" cases.
		if !mismatch && pageCategoryName != "" {
			if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil && dbP.CategoryID != "" {
				productCatName := categoryNameByID[dbP.CategoryID]
				if productCatName != "" && !sameSpiritFamily(pageCategoryName, productCatName) {
					mismatch = true
					mismatchWord = fmt.Sprintf("page=%s, product=%s", strings.ToLower(pageCategoryName), strings.ToLower(productCatName))
				}
			}
		}
		// 2. Spirit-category conflict: a "rum" OCR shouldn't pair with a "whisky" product
		if !mismatch {
			type catPair struct {
				self     []string
				conflict []string
			}
			categories := []catPair{
				{self: []string{"rum"}, conflict: []string{"whisky", "whiskey", "scotch", "bourbon", "vodka", "gin", "brandy", "wine", "riesling", "cabernet", "shiraz", "merlot", "sauvignon", "chardonnay"}},
				{self: []string{"vodka"}, conflict: []string{"whisky", "whiskey", "scotch", "bourbon", "rum", "gin", "brandy", "wine", "riesling", "cabernet", "shiraz", "merlot", "sauvignon", "chardonnay"}},
				{self: []string{"gin"}, conflict: []string{"whisky", "whiskey", "scotch", "bourbon", "rum", "vodka", "brandy", "wine", "riesling", "cabernet", "shiraz", "merlot", "sauvignon", "chardonnay"}},
				{self: []string{"brandy", "cognac"}, conflict: []string{"whisky", "whiskey", "scotch", "bourbon", "rum", "vodka", "gin", "wine", "riesling", "cabernet", "shiraz", "merlot", "sauvignon", "chardonnay"}},
				{self: []string{"whisky", "whiskey", "scotch", "bourbon"}, conflict: []string{"rum", "vodka", "gin", "brandy", "cognac", "wine", "riesling", "cabernet", "shiraz", "merlot", "sauvignon", "chardonnay"}},
				// v1.0.247 — wine is its own family. Chhotu's job had "Indri" (whisky) → "I Heart Riesling" (wine) and
				// "Bleck Labol" (whisky) → "LA AMANTE CABERNET SHIRAZ" (wine) cross-category matches.
				{self: []string{"wine", "riesling", "cabernet", "shiraz", "merlot", "sauvignon", "chardonnay", "pinot", "rose"}, conflict: []string{"whisky", "whiskey", "scotch", "bourbon", "rum", "vodka", "gin", "brandy", "cognac"}},
			}
			// Word-boundary containment: "rum" matches in "spiced rum" but not in "plum".
			// Cheaper than regex per call (called O(categories × words) per row).
			isWordChar := func(b byte) bool {
				return (b >= 'a' && b <= 'z') || (b >= '0' && b <= '9') || b == '_'
			}
			hasWord := func(s, w string) bool {
				i := 0
				for {
					idx := strings.Index(s[i:], w)
					if idx < 0 {
						return false
					}
					start := i + idx
					end := start + len(w)
					before := start == 0 || !isWordChar(s[start-1])
					after := end >= len(s) || !isWordChar(s[end])
					if before && after {
						return true
					}
					i = start + 1
					if i >= len(s) {
						return false
					}
				}
			}
			containsAny := func(s string, ws []string) (bool, string) {
				for _, w := range ws {
					if hasWord(s, w) {
						return true, w
					}
				}
				return false, ""
			}
			for _, cp := range categories {
				srcHas, srcWord := containsAny(sourceLower, cp.self)
				if !srcHas {
					continue
				}
				// OCR clearly says "rum" (for example). Check if the match says anything from conflict list
				// AND doesn't also say the expected self-category somewhere (because e.g. "rum" can appear in a whisky's name by accident).
				matchHasConflict, matchConflictWord := containsAny(matchedLower+" "+matchedDisplayLower, cp.conflict)
				matchHasSelf, _ := containsAny(matchedLower+" "+matchedDisplayLower, cp.self)
				if matchHasConflict && !matchHasSelf {
					mismatch = true
					mismatchWord = fmt.Sprintf("category %s→%s", srcWord, matchConflictWord)
					break
				}
			}
		}
		if mismatch {
			log.Printf("Smart Stock Setup: Fuzzy match REJECTED — '%s' ≠ '%s' (%s mismatch, score was %.2f)",
				guardSource, bestMatch.ProductName, mismatchWord, bestMatch.Score)
			// Before declaring not_found, try master-routing — the variant guard
			// rejected the wrong sibling, but the right one might be onboarded
			// under the same master brand. E.g. fuzzy hit plain "Magic Moments",
			// guard rejected on "cranberry", master can resolve "M2 Cranberry"
			// directly and the tenant product linked to that master id is the
			// real answer.
			if dbP, master, mode := s.findTenantProductByMasterRouting(extracted, products, masterBrands); dbP != nil && dbP.ID != bestMatch.ProductID {
				display, full := resolveDisplayAndFullName(dbP)
				item.ProductID = &dbP.ID
				item.MatchedDisplayName = display
				item.MatchedDisplayNameBoldStart = dbP.DisplayNameBoldStart
				item.MatchedDisplayNameBoldLength = dbP.DisplayNameBoldLength
				item.MatchedFullName = full
				item.MatchedBrandName = display
				if dbP.ExciseBrandName != "" {
					item.MatchedExciseBrandName = dbP.ExciseBrandName
				} else {
					item.MatchedExciseBrandName = master.BrandName
				}
				if dbP.ExciseDisplayName != "" {
					item.MatchedExciseDisplayName = dbP.ExciseDisplayName
				} else if master.DisplayName != "" {
					item.MatchedExciseDisplayName = master.DisplayName
				}
				item.MatchConfidence = 0.85
				item.Status = "matched"
				if stock, ok := stockMap[dbP.ID]; ok {
					item.CurrentStock = &stock
				}
				item.AlternativeMatches = buildAlternatives(runFuzzy(display), dbP.ID, products, 5, extracted.Brand+" "+extracted.OfficialBrandName, extracted.Rate)
				item.Warnings = nil // master-routing succeeded — the variant warning is moot
				log.Printf("Smart Stock Setup: master-routing rescued variant rejection row %d: \"%s\" → \"%s\" via master \"%s\" (%s)",
					extracted.RowNumber, extracted.Brand, display, master.BrandName, mode)
				s.logMatchOutcome(&item, extracted, "master_routing_after_variant_reject", "", 0)
				return item
			}
			item.Status = "not_found"
			item.MatchConfidence = 0
			item.variantRejected = true // skip cross-category rescue — this rejection is deliberate
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("'%s' is a different product from '%s' (differs on %s)",
					guardSource, bestMatch.ProductName, mismatchWord))
			s.logMatchOutcome(&item, extracted, "variant_rejected", "", 0)
			return item
		}
	}

	// PRICE-ONLY MATCH GATE — distinctive-token guard on the PRIMARY tenant
	// match. The v257 guard at :981/:1050 only protects the master/rescue
	// path; a garbled OCR brand that defeats every keyword/variant/category
	// guard above still reaches here and gets SILENTLY accepted as a
	// confident match driven by rate proximity + fuzzy noise — e.g.
	// "100 Step" (₹2260) → "Teacher's 50 Blended Scotch Whisky" (₹2260),
	// match_confidence 0, auto_create, persisted behind the operator's back.
	// If the register brand shares NO distinctive token with the chosen
	// product (sharesDistinctiveToken is fuzzy-aware: exact / containment≥4 /
	// similarity≥0.80, so legitimate OCR garble like "Rockfrd"→"Rockford"
	// still passes), this is brand-unsupported. Per the user's WYSIWYG
	// requirement we do NOT pre-attach it: hold the row as needs_review with
	// a visible reason and offer the candidate as a one-tap suggestion, so
	// the match is made transparently DURING review — never silently at
	// submit.
	{
		ocrGuard := strings.TrimSpace(extracted.Brand)
		if ocrGuard == "" {
			ocrGuard = strings.TrimSpace(extracted.OfficialBrandName)
		}
		bmName := bestMatch.ProductName
		if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
			bmName = firstNonEmpty(dbP.DisplayName, dbP.BrandName, dbP.Name, bestMatch.ProductName)
		}
		if ocrGuard != "" && !sharesDistinctiveToken(ocrGuard, bmName) {
			log.Printf("Smart Stock Setup: PRICE-ONLY match held for review row %d: \"%s\" ~ \"%s\" (no distinctive-token overlap, score %.2f)",
				extracted.RowNumber, ocrGuard, bmName, bestMatch.Score)
			item.Status = "needs_review"
			item.NeedsReview = true
			item.MatchConfidence = 0
			item.ReviewReason = fmt.Sprintf("Possible match \"%s\" by price only (₹%.0f) — brand unreadable, please verify or pick the correct product", bmName, extracted.Rate)
			item.Warnings = append(item.Warnings, item.ReviewReason)
			item.AlternativeMatches = buildAlternatives(results, "", products, 5, ocrGuard, extracted.Rate)
			s.logMatchOutcome(&item, extracted, "price_only_needs_review", "", 0)
			return item
		}
	}

	item.ProductID = &bestMatch.ProductID
	// Populate display + full + excise from DB with proper fallbacks
	if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
		display, full := resolveDisplayAndFullName(dbP)
		item.MatchedDisplayName = display
		item.MatchedDisplayNameBoldStart = dbP.DisplayNameBoldStart
		item.MatchedDisplayNameBoldLength = dbP.DisplayNameBoldLength
		item.MatchedFullName = full
		item.MatchedBrandName = display // backwards compat
		item.MatchedExciseBrandName = dbP.ExciseBrandName
		item.MatchedExciseDisplayName = dbP.ExciseDisplayName

		// Catalog-corruption guard — if the matched product's own name and
		// its linked brand name share almost no meaningful tokens, the
		// product record has a bad brand_id attached in the tenant
		// catalog. This catches the class of bugs seen on record
		// d4370fa3 row 11 where an OCR "Royal Stag" matched a product
		// named "Royal Stag Barrel Select" whose brand_id secretly
		// pointed to Magic Moments Verve.
		//
		// Strategy (v1.0.99 post-incident hardening): we don't just flag
		// anymore — we try to SILENTLY HEAL the product's brand_id by
		// searching the tenant brands for the best name-overlap match.
		// When a strong replacement exists (≥0.50 Jaccard), we update
		// product.brand_id in place and use the healed brand on this
		// item, so the salesman's review screen shows the correct brand
		// instead of the wrong one. If no confident replacement exists,
		// we fall back to the old behavior: warning + needs_review so a
		// human resolves it manually.
		if dbP.Name != "" && dbP.BrandName != "" && productBrandMismatch(dbP.Name, dbP.BrandName) {
			// bestMatch.ProductID comes from the matcher as a string; parse
			// to uuid for the heal helper. On parse failure we fall
			// through to the warning path.
			productUUID, perr := uuid.Parse(bestMatch.ProductID)
			healed := false
			healedName := ""
			if perr == nil {
				healedName, healed = s.tryAutoHealProductBrand(tenantID, productUUID, dbP.Name)
			}
			if healed {
				// Rewire the item to the corrected brand. item.BrandName
				// is checked later for display; keeping it aligned with
				// the healed brand avoids a stale reference anywhere.
				item.BrandName = healedName
				item.MatchedBrandName = healedName
			} else {
				item.Warnings = append(item.Warnings,
					"Suspect catalog link: product and brand disagree — verify before approving")
				item.NeedsReview = true
			}
		}
	} else {
		item.MatchedDisplayName = bestMatch.ProductName
		item.MatchedFullName = bestMatch.ProductName
		item.MatchedBrandName = bestMatch.ProductName
	}
	// Keep BrandName as displayName (AI official / master) — the fuzzy match tells us
	// WHICH product to link to, but the AI/master name is more accurate for display.
	// Only override if the fuzzy match name is significantly better (higher similarity to raw brand)
	fuzzyNameSim := matching.StringSimilarity(strings.ToLower(bestMatch.ProductName), strings.ToLower(extracted.Brand))
	displayNameSim := matching.StringSimilarity(strings.ToLower(item.BrandName), strings.ToLower(extracted.Brand))
	if fuzzyNameSim > displayNameSim+0.15 {
		// Fuzzy match name is clearly closer to what's in the register
		item.BrandName = item.MatchedDisplayName
	}
	item.MatchConfidence = clampConfidence(bestMatch.Score)

	// Current stock for comparison
	if stock, ok := stockMap[bestMatch.ProductID]; ok {
		item.CurrentStock = &stock
	}

	// MRP cross-validation. The shopkeeper's register Rate column is a strong
	// independent signal: a perfect-name fuzzy hit at the wrong price tier is
	// usually the wrong product (e.g. McDowell's No.1 Whisky 750ML vs the rare
	// No.1 Reserve). Push the match down when the rate diverges.
	mrpAgreement := 0 // -1 disagree, 0 unknown, +1 agree
	if extracted.Rate > 0 {
		matchedMRP := 0.0
		if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
			matchedMRP = dbP.MRP
		}
		if matchedMRP > 0 {
			diff := extracted.Rate - matchedMRP
			if diff < 0 {
				diff = -diff
			}
			switch {
			case diff <= 30:
				mrpAgreement = 1
			case diff > 60:
				mrpAgreement = -1
			}
		}
	}

	// v1.0.202 — Gemini disambiguation tiebreaker. Fires when the fuzzy
	// matcher landed in the ambiguous band (top-2 within 0.1) OR returned a
	// borderline best score (< 0.8). Sends a small TEXT-ONLY prompt to
	// gemini-2.5-flash with the OCR text + top-K candidate names; if Gemini
	// confidently picks one, we promote that to bestMatch and the status
	// short-circuits to "matched". No product image is uploaded; brand
	// identity is resolved from text alone — exactly the user requirement.
	//
	// Disabled by default to avoid surprising costs; opt-in via
	// GEMINI_DISAMBIG_ENABLED=1. Caller-side cap of 4 candidates keeps the
	// token count tiny (~150 in / ~30 out per row).
	if disambig := getGeminiBrandDisambiguator(); disambig != nil && len(results) >= 2 {
		ambiguousBand := results[0].Score-results[1].Score < 0.10
		borderline := bestMatch.Score < 0.80
		if ambiguousBand || borderline {
			topK := results
			if len(topK) > 4 {
				topK = topK[:4]
			}
			cands := make([]GeminiBrandCandidate, 0, len(topK))
			for _, r := range topK {
				cands = append(cands, GeminiBrandCandidate{
					ProductID:   r.ProductID,
					DisplayName: r.ProductName,
					Size:        r.Size,
					MRP:         r.Price,
				})
			}
			pickedID, conf := disambig.PickBrand(context.Background(), extracted.Brand, cands)
			if pickedID != "" && conf >= 0.6 {
				// Find the candidate matching the picked ID and promote it.
				for _, r := range results {
					if r.ProductID == pickedID {
						bestMatch = r
						item.MatchConfidence = clampConfidence(0.85) // Gemini-confirmed; mark as confident match.
						item.Warnings = append(item.Warnings,
							fmt.Sprintf("AI tiebreaker picked '%s' (%.0f%% confident)", r.ProductName, conf*100))
						item.Status = "matched"
						log.Printf("Smart Stock Setup: Gemini disambig promoted '%s' for OCR='%s' (conf=%.2f)", r.ProductName, extracted.Brand, conf)
						// Need to refresh display fields downstream — set them
						// here from the products slice so the rest of the
						// matchAndEnrich body keeps using bestMatch directly.
						if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
							display, full := resolveDisplayAndFullName(dbP)
							item.MatchedDisplayName = display
							item.MatchedDisplayNameBoldStart = dbP.DisplayNameBoldStart
							item.MatchedDisplayNameBoldLength = dbP.DisplayNameBoldLength
							item.MatchedFullName = full
							item.MatchedBrandName = display
							item.MatchedExciseBrandName = dbP.ExciseBrandName
							item.MatchedExciseDisplayName = dbP.ExciseDisplayName
							pid := dbP.ID
							item.ProductID = &pid
						}
						goto statusResolved
					}
				}
			}
		}
	}

	// Determine status
	if bestMatch.Score >= 0.8 {
		item.Status = "matched"
	} else if len(results) > 1 && results[0].Score-results[1].Score < 0.1 {
		item.Status = "ambiguous"
		item.Warnings = append(item.Warnings, "Multiple products match equally — please confirm")
	} else {
		item.Status = "low_confidence"
		item.Warnings = append(item.Warnings, "Low confidence match — please confirm")
	}
statusResolved:

	// Apply MRP modulation AFTER initial status: agreement upgrades a borderline
	// match to "matched"; disagreement demotes a confident match to low_confidence
	// so the user sees the alternatives + master suggestions.
	//
	// CRITICAL (FM Tower lesson): name match is primary, master MRP is a
	// tie-breaker only. A 0.70 name-score floor for the boost prevents the
	// "Royal Green 180ML @₹190" / "Xavior 180ML @₹190" merge — two different
	// brands at the same size+price must NOT collapse just because the price
	// aligns. Boost only when the name already matches reasonably well.
	if mrpAgreement == 1 && item.Status == "low_confidence" && bestMatch.Score >= 0.70 {
		item.Status = "matched"
		item.MatchConfidence = clampConfidence(bestMatch.Score + 0.05)
		log.Printf("Smart Stock Setup: MRP agreement (rate=%.0f, mrp matches) — promoted '%s' to matched", extracted.Rate, item.MatchedDisplayName)
	} else if mrpAgreement == -1 && item.Status == "matched" {
		item.Status = "low_confidence"
		item.Warnings = append(item.Warnings,
			fmt.Sprintf("Rate ₹%.0f doesn't match catalog MRP ₹%.0f — please verify",
				extracted.Rate, func() float64 {
					if dbP := findProductByID(products, bestMatch.ProductID); dbP != nil {
						return dbP.MRP
					}
					return 0
				}()))
		log.Printf("Smart Stock Setup: MRP disagreement (rate=%.0f vs matched MRP) — demoted '%s' to low_confidence",
			extracted.Rate, item.MatchedDisplayName)
	}

	// Populate alternatives via the shared helper — pulls correct prices from the DB row
	// and adds same-brand-prefix picks (e.g. 8 PM Gold when primary is 8 PM Special Rare).
	item.AlternativeMatches = buildAlternatives(results, bestMatch.ProductID, products, 5, extracted.Brand+" "+extracted.OfficialBrandName, extracted.Rate)

	// ALWAYS surface up to 5 master-catalog candidates for any item that isn't a
	// confident match. Covers situations like "M2 Cranberry" handwriting where
	// the tenant catalog has no Cranberry variant but the master catalog does,
	// AND the case where the fuzzy guess is wrong altogether (Jack Daniels →
	// Arthaus). User can pick the correct master entry from the picker.
	if item.Status != "matched" || item.MatchConfidence < 0.85 {
		queryName := extracted.OfficialBrandName
		if queryName == "" {
			queryName = extracted.Brand
		}
		item.MasterBrandSuggestions = s.findMasterBrandCandidates(
			queryName, extracted.SizeML, extracted.Rate, masterBrands, 5)
	}

	// Per-item decision log for fuzzy matches — include runner-up for ambiguous/low-conf
	runnerDisplay, runnerScore := "", 0.0
	if len(item.AlternativeMatches) > 0 {
		runnerDisplay = item.AlternativeMatches[0].DisplayName
		runnerScore = item.AlternativeMatches[0].Confidence
	}
	s.logMatchOutcome(&item, extracted, "fuzzy", runnerDisplay, runnerScore)

	// v1.0.125 — apply per-shop learned rate. When this product has a
	// previously-corrected rate for this shop AND the AI rate diverges by
	// more than 5% (or AI rate is 0), prefer the learned rate. Surfaces a
	// warning the user sees on review so the override is visible, never
	// silent. Implements the "fix it twice → permanent" loop the user
	// asked for.
	// v1.0.128 — when AI couldn't read the rate AND no master MRP existed
	// (covered above), fall back to the matched tenant product's effectiveMRP
	// (mrp → selling_price → cost_price). Without this, rows like row 29
	// "SEAGRAM'S ROYAL STAG BARREL SELECT WHISKY 750ML" rendered as "--"
	// despite the tenant product `b24f394e` having mrp=730. The user has to
	// manually type the rate every time, defeating the whole point of having
	// linked products.
	if item.ProductID != nil && *item.ProductID != "" && item.Rate <= 0 {
		for _, p := range products {
			if p.ID == *item.ProductID {
				if fallback := effectiveMRP(p); fallback > 0 {
					item.Rate = fallback
					log.Printf("Smart Stock Setup: TENANT MRP FALLBACK — product=%s rate=₹%.0f (AI rate=0, no master link)", p.ID, fallback)
				}
				break
			}
		}
	}

	if item.ProductID != nil && *item.ProductID != "" && len(learnedRates) > 0 {
		if learned, ok := learnedRates[*item.ProductID]; ok && learned > 1 {
			// Always surface the learned rate on the response so Flutter can
			// render "Your shop's rate last time: ₹X" even when the AI
			// happened to agree (so the user sees the system remembered).
			item.LearnedShopRate = learned
			ratio := 0.0
			if item.Rate > 0 {
				ratio = item.Rate / learned
			}
			if item.Rate <= 0 || ratio < 0.95 || ratio > 1.05 {
				oldRate := item.Rate
				item.Rate = learned
				item.NeedsReview = true
				if item.ReviewReason == "" {
					item.ReviewReason = fmt.Sprintf("Learned rate ₹%.0f used (your shop's last correction). AI read ₹%.0f from image.", learned, oldRate)
				}
				if item.FieldConfidence == nil {
					item.FieldConfidence = map[string]float64{}
				}
				if cur, ok := item.FieldConfidence["rate"]; !ok || cur > 0.6 {
					item.FieldConfidence["rate"] = 0.5
				}
				log.Printf("Smart Stock Setup: LEARNED RATE applied — product=%s ai_rate=₹%.0f → learned=₹%.0f (shop=%s)",
					*item.ProductID, oldRate, learned, "<from-context>")
			}
		}
	}

	return item
}

// logMatchOutcome writes a single-line per-item log showing the final matching decision.
// Source tag: "alias" (alias table hit), "ai_index" (AI product-aware prompt pick),
// "fuzzy" (shared matcher), "not_found" (no candidate), "variant_rejected" (fuzzy matched
// a different flavour/variant). Runner-up is shown when status is ambiguous or low_confidence.
func (s *SmartStockSetupService) logMatchOutcome(item *SmartStockSetupExtractedItem, extracted ExtractedStockRegisterItem, source string, runnerUpDisplay string, runnerUpScore float64) {
	display := item.MatchedDisplayName
	if display == "" {
		display = item.BrandName
	}
	log.Printf("SmartStockSetup: Item %d: \"%s\" %dML → %s \"%s\" (score=%.2f, src=%s)",
		extracted.RowNumber, extracted.Brand, extracted.SizeML, item.Status, display, item.MatchConfidence, source)
	if runnerUpDisplay != "" && (item.Status == "ambiguous" || item.Status == "low_confidence") {
		log.Printf("  runner-up: \"%s\" (score=%.2f)", runnerUpDisplay, runnerUpScore)
	}
}

// ============================================================================
// Auto-creation helpers
// ============================================================================

// resolveCategory maps an AI-detected category string to a tenant's category UUID.
// Auto-creates the category if it doesn't exist.
func (s *SmartStockSetupService) resolveCategory(tx *gorm.DB, tenantID uuid.UUID, categoryText string) (uuid.UUID, error) {
	// Map AI category names to standard DB names
	categoryMap := map[string]string{
		"whiskey":        "Whisky",
		"whisky":         "Whisky",
		"scotch":         "Whisky",
		"bourbon":        "Whisky",
		"rum":            "Rum",
		"vodka":          "Vodka",
		"beer":           "Beer",
		"lager":          "Beer",
		"ale":            "Beer",
		"brandy":         "Brandy",
		"cognac":         "Brandy",
		"gin":            "Gin",
		"wine":           "Wine",
		"country_liquor": "Country Liquor",
		"desi":           "Country Liquor",
		"spirits":        "IMFL",
		"rtd":            "RTD",
	}

	normalized := strings.ToLower(strings.TrimSpace(categoryText))
	canonicalName := "IMFL" // fallback
	if mapped, ok := categoryMap[normalized]; ok {
		canonicalName = mapped
	}

	// Look up in DB (case-insensitive)
	var cat struct {
		ID uuid.UUID
	}
	err := tx.Table("categories").
		Select("id").
		Where("LOWER(name) = LOWER(?) AND tenant_id = ?", canonicalName, tenantID).
		First(&cat).Error

	if err == nil {
		return cat.ID, nil
	}

	if err != gorm.ErrRecordNotFound {
		return uuid.Nil, err
	}

	// Auto-create the category
	newCatID := uuid.New()
	newCat := models.Category{
		TenantModel: models.TenantModel{TenantID: &tenantID},
		Name:        canonicalName,
		Description: "Auto-created during Smart Stock Setup",
		IsActive:    true,
	}
	newCat.ID = newCatID
	if createErr := tx.Create(&newCat).Error; createErr != nil {
		return uuid.Nil, fmt.Errorf("failed to create category %s: %w", canonicalName, createErr)
	}

	log.Printf("Smart Stock Setup: Auto-created category '%s' for tenant %s", canonicalName, tenantID)
	return newCatID, nil
}

// brandResolution holds the result of findOrCreateBrand
type brandResolution struct {
	BrandID    uuid.UUID
	BrandName  string
	WasCreated bool
}

// ResolveOrCreateBrandID is the exported wrapper around findOrCreateBrand, so the
// photo-verify handler can keep a product's tenant brand_id consistent with its
// (renamed) name without duplicating the 70%-fuzzy match/create logic. Returns the
// resolved tenant brand UUID. v1.0.355.
func (s *SmartStockSetupService) ResolveOrCreateBrandID(tx *gorm.DB, tenantID uuid.UUID, officialName string) (uuid.UUID, error) {
	res, err := s.findOrCreateBrand(tx, tenantID, officialName)
	if err != nil {
		return uuid.Nil, err
	}
	return res.BrandID, nil
}

// findOrCreateBrand finds an existing brand by fuzzy name match or creates a new one.
// Uses 70% similarity threshold to match existing brands and prevent duplicates.
func (s *SmartStockSetupService) findOrCreateBrand(tx *gorm.DB, tenantID uuid.UUID, officialName string) (*brandResolution, error) {
	// Load all tenant brands for matching
	type brandRow struct {
		ID   string
		Name string
	}
	var brands []brandRow
	tx.Table("brands").
		Select("id::text, name").
		Where("tenant_id = ? AND is_active = true AND deleted_at IS NULL", tenantID).
		Scan(&brands)

	normalizedInput := normalizeForMatch(officialName)

	// 1. Exact match first (normalized)
	for _, b := range brands {
		if normalizeForMatch(b.Name) == normalizedInput {
			id, _ := uuid.Parse(b.ID)
			return &brandResolution{BrandID: id, BrandName: b.Name}, nil
		}
	}

	// 2. Fuzzy match
	bestScore := 0.0
	var bestBrand *brandRow

	for i := range brands {
		normalizedDB := normalizeForMatch(brands[i].Name)
		score := stringSimilarity(normalizedInput, normalizedDB)

		// Boost for substring containment
		if strings.Contains(normalizedDB, normalizedInput) || strings.Contains(normalizedInput, normalizedDB) {
			if score < 0.8 {
				score = 0.8
			}
		}

		if score > bestScore {
			bestScore = score
			bestBrand = &brands[i]
		}
	}

	// 70%+ similarity → use existing brand (same brand, different spelling)
	if bestScore >= 0.70 && bestBrand != nil {
		id, _ := uuid.Parse(bestBrand.ID)
		log.Printf("Smart Stock Setup: Matched brand '%s' to existing '%s' (%.0f%% similarity)",
			officialName, bestBrand.Name, bestScore*100)
		return &brandResolution{BrandID: id, BrandName: bestBrand.Name}, nil
	}

	// 3. No match: create new brand
	newBrand := models.Brand{
		TenantModel: models.TenantModel{TenantID: &tenantID},
		Name:        officialName,
		IsActive:    true,
	}
	if err := tx.Create(&newBrand).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand '%s': %w", officialName, err)
	}

	log.Printf("Smart Stock Setup: Created new brand '%s' (no match above 70%%)", officialName)
	return &brandResolution{BrandID: newBrand.ID, BrandName: officialName, WasCreated: true}, nil
}

// findOrCreateProduct finds an existing product for brand+size or creates a new one.
// If shopID is non-nil, new products are scoped to that shop and existing-product
// lookups prefer a shop-scoped match over a tenant-wide one.
//
// Master catalog linkage: when saasBrandID is non-nil, the lookup ALSO checks for an
// existing tenant product with the same saas_variant_id (DB has UNIQUE INDEX on
// tenant_id + saas_variant_id) — this prevents duplicate products from emerging when
// the same master SKU is auto-created across multiple sessions. New products are
// created with SaasBrandID + SaaSVariantID populated so they align with the master
// catalog from day one.
// errDeferProductCreate — Unit 1 (2026-05-19) sentinel. Returned by
// findOrCreateProduct when deferCreate is set and ALL lookups missed: the
// caller (a PENDING submission) must NOT materialise a product at submit;
// ApproveStockSetup creates it (behind the same anti-phantom gate) only when
// a manager approves. Compared by identity (==) — never wrapped — because
// ApplyStockSetup shadows the stdlib `errors` package with a local slice, so
// errors.Is is unavailable in that scope.
var errDeferProductCreate = fmt.Errorf("stock setup: product create deferred to approval")

func (s *SmartStockSetupService) findOrCreateProduct(
	tx *gorm.DB, tenantID uuid.UUID, shopID *uuid.UUID, brandID uuid.UUID, brandName string,
	categoryID uuid.UUID, sizeStr string, sizeML int, rate float64,
	saasBrandID *uuid.UUID, saasVariantID *uuid.UUID, deferCreate bool,
) (uuid.UUID, bool, error) {
	if sizeStr == "" && sizeML > 0 {
		sizeStr = fmt.Sprintf("%dML", sizeML)
	}
	if sizeStr == "" {
		sizeStr = "Unknown"
	}

	// Lookup 0 (highest priority): by saas_variant_id — honors the DB's UNIQUE INDEX
	// on (tenant_id, saas_variant_id WHERE NOT NULL) and guarantees single source of
	// truth for master-aligned products.
	if saasVariantID != nil {
		// CRITICAL: match the unique index EXACTLY. idx_products_tenant_saas_
		// variant_unique is ON (tenant_id, saas_variant_id) WHERE
		// saas_variant_id IS NOT NULL — it does NOT exclude soft-deleted rows.
		// The old lookup added `deleted_at IS NULL`, so a SOFT-DELETED product
		// with the same (tenant, saas_variant) was missed → fell through to
		// CREATE → the INSERT collided with the index → SQLSTATE 23505 and the
		// row failed ("Saved 0 of 29" after the operator rejected old records,
		// which soft-deleted those products). Look up WITHOUT the deleted_at
		// filter (mirroring the constraint); if the match is soft-deleted,
		// RESTORE it (the operator is onboarding stock for that SKU again) and
		// reuse it — single source of truth, no duplicate, no 23505.
		var existingByVariant struct {
			ID        string
			DeletedAt *time.Time `gorm:"column:deleted_at"`
		}
		vErr := tx.Table("products").
			Select("id::text, deleted_at").
			Where("tenant_id = ? AND saas_variant_id = ?",
				tenantID, *saasVariantID).
			First(&existingByVariant).Error
		if vErr == nil {
			id, _ := uuid.Parse(existingByVariant.ID)
			if existingByVariant.DeletedAt != nil {
				// The check constraint chk_products_shop_id_required is
				// `CHECK (deleted_at IS NOT NULL OR shop_id IS NOT NULL)` —
				// soft-deleted rows may have NULL shop_id, but the moment we
				// clear deleted_at the row MUST have a shop_id or it violates
				// the check (SQLSTATE 23514). 42 soft-deleted variant products
				// for this tenant have NULL shop_id. So the restore MUST also
				// set shop_id to the shop being onboarded. (For Stock Setup
				// apply shopID is always the record's shop.) If we somehow
				// have no shop to assign, do NOT restore into an invalid state
				// — surface a clear error instead of the opaque 23514.
				if shopID == nil {
					return uuid.Nil, false, fmt.Errorf("cannot restore soft-deleted product %s: no shop_id available (chk_products_shop_id_required)", id)
				}
				restore := map[string]interface{}{
					"deleted_at": nil,
					"updated_at": time.Now(),
					"shop_id":    *shopID,
				}
				if rErr := tx.Table("products").
					Where("id = ? AND tenant_id = ?", id, tenantID).
					Updates(restore).Error; rErr != nil {
					return uuid.Nil, false, fmt.Errorf("restore soft-deleted product %s: %w", id, rErr)
				}
				log.Printf("Smart Stock Setup: RESTORED soft-deleted product by saas_variant_id + reattached shop_id (was rejected earlier; reusing — avoids 23505 dup + 23514 shop-required)")
			} else {
				log.Printf("Smart Stock Setup: Reusing product by saas_variant_id (master-aligned, avoiding duplicate)")
			}
			return id, false, nil
		}
		if vErr != gorm.ErrRecordNotFound {
			return uuid.Nil, false, vErr
		}
	}

	// Lookup 0.5: by saas_brand_id + size + shop. Catches the case where a prior
	// session created the product without a variant_id (or with a different one),
	// but the same master brand. Without this, every stock setup creates a fresh
	// tenant product for the same Royal Green / XCLAMATION (Tushar saw 3 Royal
	// Green products in shop 36d55d78 with the same saas_brand_id but different
	// product_id). Prefer products with stock so we don't reactivate a zombie.
	if saasBrandID != nil {
		// v1.0.281 — SIZE-STRING NORMALIZATION (safe dedupe).
		// Was: `UPPER(p.size) = UPPER(?)` exact-string — so the SAME SKU
		// stored as "750ML" by one run and "750ml (Full)" by the next did
		// NOT match → a fresh duplicate product every Stock Setup run (the
		// dominant duplicate generator proven in stocksetup_dupe_audit.sh).
		// Now: fetch this shop's rows for THIS saas_brand_id and match on
		// normalizeSizeText (the canonical Go ML normaliser used everywhere
		// else). saas_brand_id is per-flavour (green apple ≠ orange ≠ pink —
		// verified on live data), so this can NEVER merge different SKUs; it
		// only collapses size-string variants of the SAME flavour. brand_id
		// is COARSE and is deliberately NOT used here for that reason.
		targetML := normalizeSizeText(sizeStr)
		var cands []struct {
			ID   string
			Size string
		}
		bq := tx.Table("products AS p").
			Select("p.id::text AS id, p.size AS size").
			Joins("LEFT JOIN stocks s ON s.product_id = p.id AND s.tenant_id = p.tenant_id").
			Where("p.tenant_id = ? AND p.saas_brand_id = ? AND p.deleted_at IS NULL",
				tenantID, *saasBrandID)
		if shopID != nil {
			// v1.0.241 — strict shop scope. Orphan tenant-wide products (shop_id IS NULL)
			// were removed in the v1.0.241 migration. The matcher must NEVER reconsider
			// them — every product belongs to a single shop now.
			bq = bq.Where("p.shop_id = ?", *shopID)
		}
		// Preserve the prior preference order: most stock first, then oldest.
		if bErr := bq.Group("p.id, p.size").
			Order("MAX(s.quantity) DESC NULLS LAST, p.created_at ASC").
			Find(&cands).Error; bErr != nil {
			return uuid.Nil, false, bErr
		}
		pick := ""
		// 1) exact size-string is the strongest signal (unchanged behaviour).
		for _, c := range cands {
			if strings.EqualFold(strings.TrimSpace(c.Size), strings.TrimSpace(sizeStr)) {
				pick = c.ID
				break
			}
		}
		// 2) else any row with the SAME normalised ML (750ML ≡ 750ml (Full)).
		if pick == "" && targetML > 0 {
			for _, c := range cands {
				if normalizeSizeText(c.Size) == targetML {
					pick = c.ID
					break
				}
			}
		}
		if pick != "" {
			id, _ := uuid.Parse(pick)
			log.Printf("Smart Stock Setup: Reusing product by saas_brand_id+normalized-size (no size-string duplicate)")
			// Backfill saas_variant_id if we now have a more specific variant link.
			if saasVariantID != nil {
				_ = tx.Table("products").
					Where("id = ? AND tenant_id = ? AND saas_variant_id IS NULL", id, tenantID).
					Updates(map[string]interface{}{"saas_variant_id": *saasVariantID}).Error
			}
			return id, false, nil
		}
	}

	// Lookup 1 (size-robust, variant-independent) — reuse an existing product
	// for this brand+shop matched on NORMALISED size, not the exact size
	// string.
	//
	// 2026-05-18 — ROOT FIX for the dominant duplicate generator proven on
	// live data (Morpheus: "375ML" from a May-14 run vs "375ml (Half)" from
	// a May-16 run, SAME tenant+shop+saas_brand_id, two product rows, stock
	// split 5/4 → inventory showed an inflated group of 9 and the photo
	// landed on the wrong row). Lookup 0 (saas_variant_id) missed it (older
	// row had NULL variant); Lookup 0.5 is gated `saasBrandID != nil` and
	// the May-16 run had NULL saas linkage at create time (backfilled
	// later); and THIS lookup used an exact `UPPER(size)` string so
	// "375ML" != "375ML (HALF)" → a fresh duplicate every run.
	//
	// Now: (1) exact size-string is still the strongest signal; (2) else
	// reuse the SINGLE candidate whose normalizeSizeText matches. Strictly
	// single-candidate: if two rows share the coarse brand_id + the same
	// normalised size (genuinely different flavours that happen to share a
	// brand_id) it is AMBIGUOUS and we fall through to the name lookup /
	// create exactly as before — we never merge two distinct SKUs.
	{
		targetML := normalizeSizeText(sizeStr)
		var bcands []struct {
			ID   string
			Size string
		}
		bq := tx.Table("products").
			Select("id::text AS id, size").
			Where("brand_id = ? AND tenant_id = ? AND deleted_at IS NULL",
				brandID, tenantID)
		if shopID != nil {
			// v1.0.241 — strict shop scope: one product belongs to one shop.
			bq = bq.Where("shop_id = ?", *shopID)
		}
		if bErr := bq.Find(&bcands).Error; bErr != nil {
			return uuid.Nil, false, bErr
		}
		pick := ""
		for _, c := range bcands { // exact size string — strongest, unchanged
			if strings.EqualFold(strings.TrimSpace(c.Size), strings.TrimSpace(sizeStr)) {
				pick = c.ID
				break
			}
		}
		if pick == "" && targetML > 0 { // else: single normalised-size match only
			matchN := 0
			for _, c := range bcands {
				if normalizeSizeText(c.Size) == targetML {
					matchN++
					pick = c.ID
				}
			}
			if matchN != 1 {
				pick = "" // 0 = none, >1 = ambiguous → do NOT merge
			}
		}
		if pick != "" {
			id, _ := uuid.Parse(pick)
			// Opportunistic master-linkage backfill (unchanged behaviour).
			if saasBrandID != nil {
				updates := map[string]interface{}{"saas_brand_id": *saasBrandID}
				if saasVariantID != nil {
					updates["saas_variant_id"] = *saasVariantID
				}
				if upErr := tx.Table("products").
					Where("id = ? AND tenant_id = ? AND saas_brand_id IS NULL", id, tenantID).
					Updates(updates).Error; upErr == nil {
					log.Printf("Smart Stock Setup: Backfilled master linkage on existing product %s", id)
				}
			}
			log.Printf("Smart Stock Setup: Reusing product by brand+shop+normalized-size — no size-string duplicate (%s)", id)
			return id, false, nil
		}
	}

	// Also search by name+size across ALL brands (prevents duplicates across sessions).
	//
	// 2026-05-17 — mirror the v1.0.272 saas_variant restore for the NAME path.
	// The broken uq_products_tenant_shop_brand_size index was replaced by
	// uq_products_tenant_shop_name_size (UNIQUE on tenant, shop, lower(name),
	// size WHERE deleted_at IS NULL AND saas_brand_id IS NULL) for the
	// uncatalogued case. To stay idempotent across reject→re-run cycles (and
	// never 23505 on that new index), look up WITHOUT the deleted_at filter
	// (matching the partial index's key) and RESTORE a soft-deleted match
	// instead of leaving it dead and piling up a fresh duplicate row each
	// submit — exactly the v272 pattern, applied to the name slot.
	var existingByName struct {
		ID        string
		DeletedAt *time.Time `gorm:"column:deleted_at"`
	}
	productName := fmt.Sprintf("%s - %s", brandName, sizeStr)
	nameQ := tx.Table("products").
		Select("id::text, deleted_at").
		Where("LOWER(name) = LOWER(?) AND tenant_id = ?",
			productName, tenantID)
	if shopID != nil {
		nameQ = nameQ.Where("(shop_id = ? OR shop_id IS NULL)", *shopID)
	}
	// Prefer a live row; only fall back to a soft-deleted one to restore it.
	nameErr := nameQ.Order("deleted_at NULLS FIRST").First(&existingByName).Error
	if nameErr == nil {
		id, _ := uuid.Parse(existingByName.ID)
		if existingByName.DeletedAt != nil {
			// Same chk_products_shop_id_required constraint as v272: clearing
			// deleted_at requires a shop_id. Restore + reattach the shop.
			if shopID == nil {
				return uuid.Nil, false, fmt.Errorf("cannot restore soft-deleted product %s by name: no shop_id available (chk_products_shop_id_required)", id)
			}
			restore := map[string]interface{}{
				"deleted_at": nil,
				"updated_at": time.Now(),
				"shop_id":    *shopID,
			}
			if rErr := tx.Table("products").
				Where("id = ? AND tenant_id = ?", id, tenantID).
				Updates(restore).Error; rErr != nil {
				return uuid.Nil, false, fmt.Errorf("restore soft-deleted product %s by name: %w", id, rErr)
			}
			log.Printf("Smart Stock Setup: RESTORED soft-deleted product by name '%s' + reattached shop_id (reject→re-run; reuse, no duplicate row)", productName)
		} else {
			log.Printf("Smart Stock Setup: Found existing product by name '%s' (avoiding duplicate)", productName)
		}
		if saasBrandID != nil {
			updates := map[string]interface{}{"saas_brand_id": *saasBrandID}
			if saasVariantID != nil {
				updates["saas_variant_id"] = *saasVariantID
			}
			_ = tx.Table("products").
				Where("id = ? AND tenant_id = ? AND saas_brand_id IS NULL", id, tenantID).
				Updates(updates).Error
		}
		return id, false, nil
	}

	// v1.0.328 — normalized-name dedupe guard. Catches the "ab40e44c vs
	// 8d20df01" class: two LIVE products at the same shop with names that
	// NORMALIZE to the same key but differ in raw form
	// (e.g. "8PM Gold Scotch Tetra - 180ml" size "180ML" vs "8pm Gold
	// Scotch Whisky Tetra 180ml" size "180ml (Quarter)"). The exact-name
	// lookup at line 5274 missed because the strings aren't byte-equal;
	// this normalized-key + parsed-sizeML lookup reuses the existing
	// product_id instead of materialising a new near-duplicate row.
	//
	// Trade-off: query is shop-scoped + tenant-scoped + size-filtered, so
	// false positives are bounded to cases where two products share the
	// same normalized brand text at the same size at the same shop —
	// which is the exact bug class we want to prevent.
	{
		normNew := matching.NormalizeForMatch(productName)
		sizeMLNew := matching.ParseSizeML(sizeStr)
		if normNew != "" && sizeMLNew > 0 {
			var candidates []struct {
				ID   string
				Name string
				Size string
			}
			candQ := tx.Table("products").
				Select("id::text, name, size").
				Where("tenant_id = ? AND deleted_at IS NULL", tenantID)
			if shopID != nil {
				candQ = candQ.Where("(shop_id = ? OR shop_id IS NULL)", *shopID)
			}
			_ = candQ.Find(&candidates).Error
			for _, c := range candidates {
				if matching.ParseSizeML(c.Size) != sizeMLNew {
					continue
				}
				if matching.NormalizeForMatch(c.Name) != normNew {
					continue
				}
				id, _ := uuid.Parse(c.ID)
				log.Printf("Smart Stock Setup: NORMALIZED-NAME DEDUPE — reusing existing product %s (%q size=%q) instead of creating duplicate %q size=%q at shop=%v (v1.0.328)",
					id, c.Name, c.Size, productName, sizeStr, shopID)
				if saasBrandID != nil {
					updates := map[string]interface{}{"saas_brand_id": *saasBrandID}
					if saasVariantID != nil {
						updates["saas_variant_id"] = *saasVariantID
					}
					_ = tx.Table("products").
						Where("id = ? AND tenant_id = ? AND saas_brand_id IS NULL", id, tenantID).
						Updates(updates).Error
				}
				return id, false, nil
			}
		}
	}

	// Unit 1 (2026-05-19) — defer create to approval. Every lookup above
	// missed (no existing/catalog/name match) and the caller is a PENDING
	// submission with STOCK_SETUP_DEFER_CREATE on: do NOT materialise a
	// product at submit. Reused / catalog-matched products returned above
	// are unaffected — ONLY brand-new creates wait for a manager's approval,
	// so nothing unvouched ever enters inventory from a mere request.
	if deferCreate {
		return uuid.Nil, false, errDeferProductCreate
	}

	// Create new product
	// Pricing: cost = selling = MRP = rate (user will update cost via Smart Purchase later)
	mrp := rate
	if mrp <= 0 {
		mrp = 1.0 // minimum to satisfy validation
	}

	sku := fmt.Sprintf("AUTO-%s-%s", tenantID.String()[:8], uuid.New().String()[:8])

	product := models.Product{
		TenantModel:   models.TenantModel{TenantID: &tenantID},
		ShopID:        shopID, // nil = legacy tenant-wide; non-nil = shop-scoped
		SaaSBrandID:   saasBrandID,   // master catalog brand linkage (may be nil)
		SaaSVariantID: saasVariantID, // master catalog variant linkage (may be nil)
		Name:          productName,
		CategoryID:    categoryID,
		BrandID:       brandID,
		Size:          sizeStr,
		CostPrice:     mrp,
		SellingPrice:  mrp,
		MRP:           mrp,
		SKU:           sku,
		IsActive:      true,
		// A master-linked auto-create carries a trustworthy catalog name.
		// An UNLINKED create is raw, unverified Stock-Setup text and must be
		// confirmed by a bottle photo before it can be purchased.
		NameVerified: saasBrandID != nil,
		// 2026-05-18 — provenance for the AI-Purchase image gate. A
		// Stock-Setup product with no photo blocks purchase until one is
		// attached. See migration 20260518_products_created_via.sql.
		CreatedVia: "stock_setup",
	}

	if createErr := tx.Create(&product).Error; createErr != nil {
		return uuid.Nil, false, fmt.Errorf("failed to create product '%s': %w", productName, createErr)
	}

	scopeNote := "tenant-wide"
	if shopID != nil {
		scopeNote = fmt.Sprintf("shop %s", shopID.String()[:8])
	}
	masterNote := "unlinked"
	if saasBrandID != nil {
		masterNote = fmt.Sprintf("master=%s", saasBrandID.String()[:8])
	}
	log.Printf("Smart Stock Setup: Created product '%s' (MRP: ₹%.2f, SKU: %s, scope: %s, %s)", productName, mrp, sku, scopeNote, masterNote)
	return product.ID, true, nil
}

// findOrCreateProductBare — 2026-05-17 NEVER-DROP last resort.
//
// Operator directive: a row the operator can read MUST be saved — "100
// whatever it is, do the submit, never skip one". If the primary
// findOrCreateProduct fails for ANY reason (category/brand resolution
// races, an unforeseen constraint, etc.) we must NOT drop the row. This
// guarantees the verbatim name lands as a real shop product, flagged
// name_verified=false so it surfaces for a trusted-photo name fix before
// it can be purchased. It cannot itself fail to land: it reuses/restores
// an existing same-name product, and if a fresh insert still collides it
// retries once with a row-disambiguated name so something always persists.
func (s *SmartStockSetupService) findOrCreateProductBare(
	tx *gorm.DB, tenantID uuid.UUID, shopID *uuid.UUID, brandID uuid.UUID,
	brandName string, categoryID uuid.UUID, sizeStr string, rate float64, rowNumber int,
) (uuid.UUID, error) {
	if strings.TrimSpace(sizeStr) == "" {
		sizeStr = "Unknown"
	}
	if strings.TrimSpace(brandName) == "" {
		brandName = "Unnamed item"
	}
	productName := fmt.Sprintf("%s - %s", strings.TrimSpace(brandName), sizeStr)

	// Reuse/restore an existing same-name product (mirror the v273 name path)
	// so a reject→re-run never piles up duplicates here either.
	var ex struct {
		ID        string
		DeletedAt *time.Time `gorm:"column:deleted_at"`
	}
	q := tx.Table("products").
		Select("id::text, deleted_at").
		Where("LOWER(name) = LOWER(?) AND tenant_id = ?", productName, tenantID)
	if shopID != nil {
		q = q.Where("(shop_id = ? OR shop_id IS NULL)", *shopID)
	}
	if q.Order("deleted_at NULLS FIRST").First(&ex).Error == nil {
		id, _ := uuid.Parse(ex.ID)
		if ex.DeletedAt == nil {
			// Live row — safe reuse, no write, cannot poison.
			log.Printf("Smart Stock Setup Apply: NEVER-DROP fallback reused LIVE product '%s' (row %d)", productName, rowNumber)
			return id, nil
		}
		if shopID == nil {
			// Soft-deleted but no shop to attach — reuse id as-is (no write).
			return id, nil
		}
		// Soft-deleted: restoring it (clearing deleted_at) re-enters the
		// partial unique index uq_products_tenant_shop_name_size and can
		// FAIL (a live same-name row from a prior run). The OLD code did
		// `_ = ...Updates(...).Error` then `return id, nil` — swallowing the
		// failure and returning SUCCESS with a POISONED transaction, so
		// every later row's category lookup + the final idempotency lookup
		// cascaded 25P02 → "Saved 0 of N". Savepoint-guard it: on failure
		// roll back and FALL THROUGH to a fresh disambiguated insert (which
		// cannot collide), never a poisoned success.
		sp := fmt.Sprintf("spr_%d_%s", rowNumber, strings.ReplaceAll(uuid.New().String()[:8], "-", ""))
		if e := tx.SavePoint(sp).Error; e != nil {
			// Cannot even set a savepoint → tx already aborted upstream.
			// Surface a real error so the savepoint-wrapped caller rolls back.
			return uuid.Nil, fmt.Errorf("bare restore savepoint failed (tx already aborted): %w", e)
		}
		rErr := tx.Table("products").
			Where("id = ? AND tenant_id = ?", id, tenantID).
			Updates(map[string]interface{}{"deleted_at": nil, "updated_at": time.Now(), "shop_id": *shopID}).Error
		if rErr == nil {
			log.Printf("Smart Stock Setup Apply: NEVER-DROP fallback RESTORED soft-deleted product '%s' (row %d)", productName, rowNumber)
			return id, nil
		}
		tx.RollbackTo(sp) // un-poison; fall through to a fresh insert below
		log.Printf("Smart Stock Setup Apply: NEVER-DROP restore failed for '%s' (%v) — creating fresh disambiguated product instead", productName, rErr)
	}

	mrp := rate
	if mrp <= 0 {
		mrp = 1.0
	}
	insert := func(name string) (uuid.UUID, error) {
		// CRITICAL: wrap every Create in its OWN savepoint. A failed INSERT
		// inside a Postgres tx poisons the WHOLE transaction (SQLSTATE
		// 25P02 — "current transaction is aborted, commands ignored"), so
		// without this the first failed attempt poisons the tx, the retry
		// runs on a dead tx, and every SUBSEQUENT row's category lookup then
		// fails 25P02 → "Saved 0 of N". RollbackTo un-poisons so the tx
		// stays usable for the retry and the rest of the apply.
		sp := fmt.Sprintf("spb_%d_%s", rowNumber, strings.ReplaceAll(uuid.New().String()[:8], "-", ""))
		if e := tx.SavePoint(sp).Error; e != nil {
			return uuid.Nil, e
		}
		p := models.Product{
			TenantModel:  models.TenantModel{TenantID: &tenantID},
			ShopID:       shopID,
			Name:         name,
			CategoryID:   categoryID,
			BrandID:      brandID,
			Size:         sizeStr,
			CostPrice:    mrp,
			SellingPrice: mrp,
			MRP:          mrp,
			SKU:          fmt.Sprintf("AUTO-%s-%s", tenantID.String()[:8], uuid.New().String()[:8]),
			IsActive:     true,
			NameVerified: false, // raw text — must be photo-verified before purchase
			CreatedVia:   "stock_setup", // 2026-05-18 — AI-Purchase image gate
		}
		if e := tx.Create(&p).Error; e != nil {
			tx.RollbackTo(sp) // un-poison the tx so the retry / rest of apply survive
			return uuid.Nil, e
		}
		return p.ID, nil
	}

	id, err := insert(productName)
	if err == nil {
		log.Printf("Smart Stock Setup Apply: NEVER-DROP fallback created product '%s' (row %d, name_verified=false)", productName, rowNumber)
		return id, nil
	}
	// Last-ditch: disambiguate the name by row so it cannot collide, then it
	// is guaranteed to land. Operator fixes the real name by photo later.
	id, err2 := insert(fmt.Sprintf("%s (row %d)", productName, rowNumber))
	if err2 != nil {
		return uuid.Nil, fmt.Errorf("bare create failed twice (%v / %v)", err, err2)
	}
	log.Printf("Smart Stock Setup Apply: NEVER-DROP fallback created disambiguated product '%s (row %d)' (name_verified=false)", productName, rowNumber)
	return id, nil
}

// demoteCrossShopProduct enforces the "each shop owns its own items only"
// invariant. Given a product_id, if that product belongs to a DIFFERENT shop
// than shopID (the cross-shop-link bug class that trg_block_crossshop_stock
// rejects at stock-write time — and which poisons the whole approve tx), it
// resolves-or-creates a shop-OWNED equivalent and returns the new id.
//
// How a cross-shop link gets in: the AI matcher itself is shop-scoped, but the
// product picker on the review screen (and the web-admin Swap dialog) historically
// called GET /products tenant-wide, so an operator could pick another shop's
// identically-named row — easy to do when a tenant has near-duplicate shops
// ("Malsaii" vs "T-Malsaii"). Legacy pre-v397 records carry the same links.
//
// Reuses the tx-safe onboard core: ResolveOrCreateShopProductFromMaster when the
// foreign product is master-linked (preserves the catalogue brand, drops the
// tenant-unique saas_variant link), else ResolveOrCreateShopProductNew. Both are
// idempotent, so repeated calls reuse the shop's product.
//
// Returns (productID, false, nil) — caller keeps its id — when the product is
// already shop-owned, tenant-wide (shop_id NULL), missing, or unparseable.
func (s *SmartStockSetupService) demoteCrossShopProduct(tx *gorm.DB, tenantID, shopID uuid.UUID, productID string) (string, bool, error) {
	pid, err := uuid.Parse(productID)
	if err != nil || pid == uuid.Nil {
		return productID, false, nil
	}
	var p models.Product
	if e := tx.Select("id, shop_id, saas_brand_id, name, size, category_id, mrp, cost_price").
		Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", pid, tenantID).
		First(&p).Error; e != nil {
		return productID, false, nil // unknown product — leave the caller's id untouched
	}
	if p.ShopID == nil || *p.ShopID == shopID {
		return productID, false, nil // already correct scope (shop-owned or tenant-wide)
	}
	sizeML := extractML(p.Size)
	if sizeML <= 0 {
		return productID, false, fmt.Errorf("cross-shop demote: cannot parse size %q for product %s", p.Size, pid)
	}
	catName := ""
	if p.CategoryID != uuid.Nil {
		var c struct{ Name string }
		tx.Table("categories").Select("name").Where("id = ?", p.CategoryID).Scan(&c)
		catName = c.Name
	}
	var res *OnboardCoreResult
	if p.SaaSBrandID != nil && *p.SaaSBrandID != uuid.Nil {
		res, err = ResolveOrCreateShopProductFromMaster(tx, tenantID, shopID, *p.SaaSBrandID, sizeML, p.CostPrice, p.MRP, catName)
	} else {
		res, err = ResolveOrCreateShopProductNew(tx, tenantID, shopID, p.Name, sizeML, catName, p.MRP, p.CostPrice)
	}
	if err != nil {
		return productID, false, fmt.Errorf("cross-shop demote for product %s → shop %s: %w", pid, shopID, err)
	}
	log.Printf("Stock Setup: cross-shop demote — product %s (owner shop %s) → shop-owned %s for shop %s",
		pid, *p.ShopID, res.ProductID, shopID)
	return res.ProductID.String(), true, nil
}

// ============================================================================
// Step 2: Apply — bulk-set stock in a single transaction
// ============================================================================

// ApplyStockSetup bulk-sets stock for all confirmed items in a single transaction.
// For salesman role: creates a pending StockSetupRecord requiring manager/admin approval.
// For admin/manager: creates an auto-approved record and applies stock immediately.
func (s *SmartStockSetupService) ApplyStockSetup(ctx context.Context, req SmartStockSetupApplyRequest, tenantID, userID uuid.UUID, userRole ...string) (*SmartStockSetupApplyResult, error) {
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		return nil, fmt.Errorf("invalid shop ID: %w", err)
	}

	if len(req.Items) == 0 {
		return nil, fmt.Errorf("at least one item is required")
	}

	// v1.0.243 + v1.0.244 + v1.0.248 — Brand-image verification AUDIT.
	// Through v247 this was a HARD gate that rejected the apply when any row
	// lacked Front+Back photos. Chhotu's real-world flow surfaced two cases the
	// hard gate handled badly:
	//   1. Manual "Add Missing Brands" entries don't have photo chips, so the
	//      gate could never be satisfied — operator was deadlocked.
	//   2. Operators want to take photos LATER from the inventory product
	//      page (post-apply), not all at once during Stock Setup.
	// v248 makes this a SOFT gate: collect the unverified rows, log them,
	// surface them on the response under PhotoAuditMissing, and let the apply
	// proceed. Operator follows up on each missing-photo product from the
	// inventory edit screen (see PendingPhotoVerifications API in v248).
	//
	// Hard-rejection can still be re-enabled with SMART_STOCK_SETUP_REQUIRE_IMAGE=1
	// for tenants that need strict enforcement; default behaviour is now soft.
	var photoAuditMissing []UnverifiedRow
	for i, it := range req.Items {
		frontOK := it.VerifiedViaImageFront || it.VerifiedViaImage
		backOK := it.VerifiedViaImageBack
		if frontOK && backOK {
			continue
		}
		missing := "both"
		switch {
		case !frontOK && backOK:
			missing = "front"
		case frontOK && !backOK:
			missing = "back"
		}
		row := UnverifiedRow{
			RowNumber: it.RowNumber,
			BrandName: it.BrandName,
			Size:      it.Size,
			Reason:    "missing_photo_verification",
			Face:      missing,
		}
		if row.RowNumber == 0 {
			row.RowNumber = i + 1
		}
		photoAuditMissing = append(photoAuditMissing, row)
	}
	if len(photoAuditMissing) > 0 {
		log.Printf("Smart Stock Setup Apply: %d row(s) lack photo verification (shop=%s, total=%d) — soft-warn, apply will proceed",
			len(photoAuditMissing), req.ShopID, len(req.Items))
		// Opt-in strict mode: when explicitly required, still reject. Default OFF.
		if os.Getenv("SMART_STOCK_SETUP_REQUIRE_IMAGE") == "1" {
			return nil, &UnverifiedRowsError{
				UnverifiedCount: len(photoAuditMissing),
				RejectedRows:    photoAuditMissing,
			}
		}
	}

	notes := req.Notes
	if notes == "" {
		notes = "Opening stock set from register image"
	}

	// Add size context to notes for better audit trail
	if req.Size != "" {
		notes = fmt.Sprintf("Set via AI Stock Setup - %d products (%s)", len(req.Items), req.Size)
		if req.CategoryID != "" {
			var catName struct{ Name string }
			if catErr := s.db.Table("categories").Select("name").
				Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).
				Scan(&catName).Error; catErr == nil && catName.Name != "" {
				notes = fmt.Sprintf("Set via AI Stock Setup - %d products (%s · %s)", len(req.Items), catName.Name, req.Size)
			}
		}
	}

	// Determine user role for approval flow.
	// Only admin and manager can apply stock directly; executive and salesman must
	// stage as pending and wait for approval (was previously salesman-only, which let
	// executives bypass approval entirely).
	role := ""
	if len(userRole) > 0 {
		role = userRole[0]
	}
	needsApproval := role != "" && role != models.RoleAdmin && role != models.RoleManager
	log.Printf("Smart Stock Setup Apply: %d items received (session: %s, size: %s, role: %s, needs_approval: %v)", len(req.Items), req.SessionID, req.Size, role, needsApproval)

	// Unit 1 (2026-05-19) — opt-in: when a PENDING submission can't match an
	// existing/catalog product, PARK the row and create the product at
	// APPROVAL instead of at submit, so a mere request never adds an
	// unvouched product to inventory. Default OFF (must be exactly "1") so
	// the change ships dormant and is switched on per the rollout plan;
	// clearing the env var instantly restores submit-time create, no
	// redeploy. Only the pending flow is affected (admin/manager direct
	// apply still creates immediately — they ARE the approver).
	deferProductCreate := needsApproval && os.Getenv("STOCK_SETUP_DEFER_CREATE") == "1"
	if deferProductCreate {
		log.Printf("Smart Stock Setup Apply: STOCK_SETUP_DEFER_CREATE=1 — unmatched NEW products will be created at APPROVAL (pending flow), not at submit")
	}

	// Submission audit — list each item's brand + qty on submission so any
	// "row missing" complaint can be triangulated against the extraction logs
	// (e.g. user reports B7 absent → grep brand_name='B7' in this log; if
	// present here, the gap is in the apply path or the user dropped it).
	{
		rowNums := make([]string, 0, len(req.Items))
		zeroActivity := 0
		for _, it := range req.Items {
			rowNums = append(rowNums, fmt.Sprintf("'%s'(qty=%d,sale=%d,opening=%d)", it.BrandName, it.Quantity, it.Sale, it.OpeningStock))
			if it.Quantity == 0 && it.Sale == 0 && it.OpeningStock == 0 {
				zeroActivity++
			}
		}
		log.Printf("Smart Stock Setup Apply: submitted rows (%d, zero_activity=%d): %s",
			len(req.Items), zeroActivity, strings.Join(rowNums, " | "))
	}

	applied := 0
	failed := 0
	var errors []string
	// v1.0.266 — FULL ACCOUNTING. Every received item must end up counted as
	// applied, failed, OR skipped — never invisibly dropped. The zero-activity
	// branch previously did a bare `continue` with no counter, so
	// ItemsApplied+ItemsFailed < ItemsReceived and the operator had no signal
	// that N items vanished (chhotu record 5693f4f6: 29 received, 16 saved, 13
	// silently gone). These make the loss VISIBLE and the arithmetic balance.
	zeroSkipped := 0
	var zeroSkippedBrands []string
	// v1.0.283 — anti-phantom: rows rejected as unreadable OCR garbage (no
	// catalog match + low confidence + no photo + operator never touched).
	// Counted as an explicit, reported skip — NOT a failure — so the
	// accounting balances received == applied + failed + zeroSkipped +
	// rejectedUnreadable and the operator is told exactly what to re-capture.
	rejectedUnreadable := 0
	var rejectedUnreadableRows []UnverifiedRow
	var setupRecordID uuid.UUID
	// Unit 1 — count of rows parked for approval-time create (diagnostic;
	// these still become stock_setup_items so the received==applied+failed+
	// zeroSkipped+rejectedUnreadable accounting is unchanged — they are
	// "applied" in the pending sense, just without a product yet).
	deferredCreate := 0

	err = s.db.Transaction(func(tx *gorm.DB) error {
		// ========================================
		// Pass 1: Resolve product IDs (deferred creation)
		// ========================================
		type resolvedItem struct {
			ProductID uuid.UUID
			Item      *SmartStockSetupApplyItem
			PrevStock int // DB stock before this apply
		}
		var resolved []resolvedItem

		for idx := range req.Items {
			item := &req.Items[idx]

			log.Printf("Smart Stock Setup Apply item[%d]: product_id=%s brand_name='%s' edited_name='%s' size='%s' qty=%d mrp=%.2f", idx, item.ProductID, item.BrandName, item.EditedName, item.Size, item.Quantity, item.MRP)

			// 2026-05-22 — STRICT zero-stock filter. Operator directive after
			// record 310beab1 surfaced rows 5 (1965 Spirit of Victory) + 13
			// (Magic Moments Orange) with opening=0, closing=0, quantity=0 but
			// a phantom AI sale value (-5, -7) being persisted as setup items.
			// These rows represent no real inventory state to set and were
			// cluttering the approved record. Now ALWAYS skipped — regardless
			// of name, master pick, or sale/receipt value — because:
			//   * opening=0 + closing=0 means the row contributes nothing to
			//     stock after apply.
			//   * Any sale/receipt value on such a row is arithmetically
			//     impossible (can't sell what you don't have), so it's AI noise.
			//   * Unit 2 reversible-replace handles the "operator omitted real
			//     product from register" case anyway — it soft-deactivates
			//     out-of-scope products with restorable snapshots.
			// Supersedes the 2026-05-17 "NEVER-SKIP named zero rows" directive
			// (which was about preserving legitimate qty>0 rows, not 0/0 phantoms).
			if item.OpeningStock == 0 && item.ClosingStock == 0 && item.Quantity == 0 {
				nm := strings.TrimSpace(item.EditedName)
				if nm == "" {
					nm = strings.TrimSpace(item.OfficialBrandName)
				}
				if nm == "" {
					nm = strings.TrimSpace(item.BrandName)
				}
				if nm == "" {
					nm = "(unnamed empty row)"
				}
				zeroSkipped++
				zeroSkippedBrands = append(zeroSkippedBrands, nm)
				log.Printf("Smart Stock Setup Apply: SKIPPED 0-stock row '%s' (open=0, close=0, qty=0; sale=%d, recv=%d) — operator directive 2026-05-22",
					nm, item.Sale, item.Receipt)
				continue
			}

			// Per-shop ownership guard (v1.0.397): the client may send a product_id
			// that belongs to ANOTHER shop — most often when the AI review screen's
			// product picker listed a tenant-wide match for a brand this shop hasn't
			// stocked yet. Writing this shop's stock against another shop's product
			// is rejected by trg_block_crossshop_stock at approve (and poisons the
			// tx → "N items failed to write stock"). Convert it to a shop-owned
			// equivalent NOW so every persisted item is owned by req.ShopID.
			if item.ProductID != "" {
				newPID, changed, dErr := s.demoteCrossShopProduct(tx, tenantID, shopID, item.ProductID)
				if dErr != nil {
					return fmt.Errorf("stock setup apply item[%d]: %w", idx, dErr)
				}
				if changed {
					log.Printf("Smart Stock Setup Apply item[%d]: cross-shop product %s demoted to shop-owned %s", idx, item.ProductID, newPID)
					item.ProductID = newPID
					item.SaasVariantID = "" // shop-owned copy carries no master variant link
				}
			}

			// Edit-name re-resolve safety net (v1.0.112): if the client sent an
			// existing product_id BUT the user clearly edited the name to something
			// else AND didn't pick a master, fuzzy-resolve the EditedName to a
			// master brand. If that returns a different master than the matched
			// product is linked to, drop the product_id so the deferred-creation
			// block below re-routes the row to the correct master via
			// findOrCreateProduct (which honors v1.0.110's saas_brand_id+size
			// dedup). Without this, the apply path on line 4271 would simply
			// rename the WRONG tenant product to the new text — Tushar's BACARDI/
			// XCLAMATION class. Mirror of the Flutter row-edit auto_create flip,
			// kept on the backend so older clients / direct API callers get the
			// same safety.
			if item.ProductID != "" && item.EditedName != "" && item.SaasBrandID == "" {
				var matched struct {
					Name        string
					SaasBrandID *uuid.UUID
				}
				if mErr := tx.Table("products").
					Select("name, saas_brand_id").
					Where("id = ? AND tenant_id = ?", item.ProductID, tenantID).
					Scan(&matched).Error; mErr == nil && matched.Name != "" {
					if !strings.EqualFold(strings.TrimSpace(matched.Name), strings.TrimSpace(item.EditedName)) {
						sizeForLookup := item.Size
						if sizeForLookup == "" {
							sizeForLookup = req.Size
						}
						sizeML := normalizeSizeText(sizeForLookup)
						rateForLookup := item.MRP
						if rateForLookup <= 0 {
							rateForLookup = item.Rate
						}
						tState := s.getTenantState(tenantID)
						mBrands := s.loadMasterBrands(sizeML, tState)
						if mb := s.findMasterBrand(item.EditedName, sizeML, rateForLookup, mBrands); mb != nil {
							currentSB := ""
							if matched.SaasBrandID != nil {
								currentSB = matched.SaasBrandID.String()
							}
							if !strings.EqualFold(mb.BrandID, currentSB) {
								log.Printf("Smart Stock Setup Apply: edit-name re-resolve — row '%s' edited from '%s' to '%s' → re-routing to master %s (was %s)",
									item.BrandName, matched.Name, item.EditedName, mb.BrandID, currentSB)
								item.SaasBrandID = mb.BrandID
								item.SaasVariantID = mb.VariantID
								item.OriginalProductID = item.ProductID
								item.ProductID = ""
								if item.OfficialBrandName == "" {
									item.OfficialBrandName = item.EditedName
								}
							}
						}
					}
				}
			}

			// Deferred creation: if no product_id, create the product now.
			// brandName precedence: EditedName > OfficialBrandName > BrandName.
			// Flutter sends a STALE OfficialBrandName when the user edits the
			// row name without using the catalog picker — only `name` (and thus
			// `edited_name`) gets updated, while `officialBrandName` keeps the
			// AI's original guess. v1.0.113 root cause: record 57aee835 row 27
			// had official_brand_name='BACARDI...' but edited_name='SEAGRAM'S
			// XCLAMATION ...' — backend used the stale official and created a
			// BACARDI product. Treat EditedName as the user's authoritative
			// intent.
			if item.ProductID == "" && (item.EditedName != "" || item.OfficialBrandName != "" || item.BrandName != "") {
				brandName := item.EditedName
				if brandName == "" {
					brandName = item.OfficialBrandName
				}
				if brandName == "" {
					brandName = item.BrandName
				}

				// v1.0.132 — per-row savepoint guards the auto-create branch.
				// The auto-create path writes brands + products + (saas_brand_id
				// backfill) in this transaction. If any of those fail (the
				// May 1 incident: products.last_m_rpchange_at SQLSTATE 42703),
				// PostgreSQL marks the whole txn as aborted and every later
				// statement returns 25P02 — the stock_setup_records insert
				// disappears, the user sees "200 OK" but no record. Wrapping
				// in a savepoint lets us roll back ONLY this row's writes and
				// keep the rest of the apply alive.
				spName := fmt.Sprintf("sp_autocreate_%d", idx)
				if spErr := tx.SavePoint(spName).Error; spErr != nil {
					failed++
					errors = append(errors, fmt.Sprintf("savepoint failed for %s: %v", brandName, spErr))
					continue
				}

				var catID uuid.UUID
				if item.CategoryName != "" {
					var catErr error
					catID, catErr = s.resolveCategory(tx, tenantID, item.CategoryName)
					if catErr != nil {
						tx.RollbackTo(spName)
						failed++
						errors = append(errors, fmt.Sprintf("Failed to resolve category for %s: %v", brandName, catErr))
						continue
					}
				} else if req.CategoryID != "" {
					parsedCatID, parseErr := uuid.Parse(req.CategoryID)
					if parseErr == nil {
						catID = parsedCatID
					}
				}
				if catID == uuid.Nil {
					var catErr error
					catID, catErr = s.resolveCategory(tx, tenantID, "spirits")
					if catErr != nil {
						tx.RollbackTo(spName)
						failed++
						errors = append(errors, fmt.Sprintf("Failed to resolve category for %s: %v", brandName, catErr))
						continue
					}
				}

				brandRes, brandErr := s.findOrCreateBrand(tx, tenantID, brandName)
				if brandErr != nil {
					tx.RollbackTo(spName)
					failed++
					errors = append(errors, fmt.Sprintf("Failed to create brand %s: %v", brandName, brandErr))
					continue
				}

				sizeStr := item.Size
				if sizeStr == "" {
					sizeStr = req.Size
				}
				if sizeStr == "" {
					sizeStr = "Unknown"
				}
				sizeML := normalizeSizeText(sizeStr)

				rate := item.MRP
				if rate <= 0 {
					rate = item.Rate
				}

				// Resolve master brand + variant ONCE — used both for MRP backfill and
				// for propagating saas_brand_id / saas_variant_id onto the new product.
				// This is the key hook that keeps auto-created products aligned with the
				// master catalog; previously every auto-create left these columns NULL.
				//
				// If the client sent saas_brand_id (inline catalog picker on the Add-
				// Missing UI), trust it verbatim and skip the fuzzy resolver — the user
				// already chose the master, so guessing again would risk overriding their
				// pick with a worse fuzzy match.
				var masterBrandIDPtr *uuid.UUID
				var masterVariantIDPtr *uuid.UUID
				if item.SaasBrandID != "" {
					if mbID, perr := uuid.Parse(item.SaasBrandID); perr == nil {
						masterBrandIDPtr = &mbID
					}
					if item.SaasVariantID != "" {
						if vID, perr := uuid.Parse(item.SaasVariantID); perr == nil {
							masterVariantIDPtr = &vID
						}
					}
					log.Printf("Smart Stock Setup Apply: Using client-provided master link saas_brand_id=%s saas_variant_id=%s for '%s'",
						item.SaasBrandID, item.SaasVariantID, brandName)
				} else {
					tenantStateApply := s.getTenantState(tenantID)
					masterBrandsApply := s.loadMasterBrands(sizeML, tenantStateApply)
					if mb := s.findMasterBrand(brandName, sizeML, rate, masterBrandsApply); mb != nil {
						// WYSIWYG-AT-APPLY GUARD. The operator did NOT pick a
						// master (item.SaasBrandID == "") and the extractor
						// (Fix 2) deliberately left this row unbound for them
						// to choose. findMasterBrand here is a fuzzy+RATE
						// resolver — on a garbled brand it returns a product
						// purely by price proximity ("100 Stop" ₹2260 →
						// "Teacher's 50 Blended Scotch Whisky" ₹2260), and
						// findOrCreateProduct then DEDUPES the row onto that
						// wrong existing product. That is the exact "I saved
						// '100 Stop' but the record shows Teacher's 50, behind
						// my back" bug. Only accept this auto-resolved master
						// if it shares a distinctive token with what the
						// operator actually saw (sharesDistinctiveToken is
						// fuzzy-aware so legit OCR garble like
						// "Rockfrd"→"Rockford" still links). Otherwise DROP the
						// master link → findOrCreateProduct creates a NEW
						// standalone product named exactly as reviewed
						// ("100 Stop"), never a divergent rate twin.
						mbName := strings.TrimSpace(mb.DisplayName + " " + mb.BrandName)
						if sharesDistinctiveToken(brandName, mbName) {
							if mbID, perr := uuid.Parse(mb.BrandID); perr == nil {
								masterBrandIDPtr = &mbID
							}
							if mb.VariantID != "" {
								if vID, perr := uuid.Parse(mb.VariantID); perr == nil {
									masterVariantIDPtr = &vID
								}
							}
							if rate <= 1 && mb.MRP > 0 {
								rate = mb.MRP
								log.Printf("Smart Stock Setup Apply: Using master MRP ₹%.0f for '%s' (item MRP was ₹%.0f)", mb.MRP, brandName, item.MRP)
							}
						} else {
							log.Printf("Smart Stock Setup Apply: WYSIWYG guard — DROPPED rate-only master '%s' for un-picked row '%s' (no distinctive-token overlap); creating standalone product as reviewed", mbName, brandName)
						}
					}
				}

				// v1.0.283 — ANTI-PHANTOM GATE (hardened). Two production
				// instances of the same class: chhotu's low-confidence OCR
				// garble "Chonploopr - 180ml" (brand conf 0.35) AND the
				// confident hallucination "Vin Green Label The Rich Blend
				// Whisky · 375ml". Both auto-created a permanent brand+product
				// here, polluting inventory even though the record stays
				// pending forever. The safe invariant is PROVENANCE, not
				// confidence (a model is unreliably confident on hallucinated
				// input): if this row resolved to NO catalog master, the
				// operator never corrected/picked it, it has NO bottle photo,
				// and the operator did not retype a distinct name, nothing
				// vouches for it — roll back THIS row's brand/category create,
				// never make the product, report it honestly (no silent drop
				// — v1.0.279). brand_conf is logged for diagnostics only.
				//
				// 2026-05-22 (v1.0.290) — ALWAYS-ON at submit too. Was env-
				// kill-switchable; record 310beab1 incident showed the flag
				// being silently set to 0 in prod .env, letting 5 garbled
				// phantoms (imjum / SM19Jum / M6002Jum / 100 Step / Jamson)
				// ride into the catalog on the manager/admin direct-submit
				// path (which has no separate approve step to catch them).
				// Approve-time gate has always been ignored env since v1.0.289;
				// closing the same loophole here means a phantom can never
				// ride in via env tampering on ANY path.
				{
					brandConf := item.FieldConfidence["brand"] // diagnostic only — NOT a gate
					hasPhoto := item.VerifiedViaImage || item.VerifiedViaImageFront ||
						item.VerifiedViaImageBack || item.FrontImageURL != "" ||
						item.VerifiedImageURL != ""
					// v1.0.291 — 5th vouching signal. When Flutter's review screen
					// is the entry point, every row in the apply payload carries
					// operator_vouched_at_submit=true; that gesture IS the vouch.
					// Re-extraction / admin auto-apply paths leave it false so the
					// gate still protects unattended creates.
					if shouldRejectUnreadableAutoCreate(
						masterBrandIDPtr != nil, item.WasCorrected, hasPhoto, item.OperatorVouchedAtSubmit,
						item.EditedName, item.BrandName, item.OfficialBrandName,
					) {
						// Savepoint spName wraps from before resolveCategory +
						// findOrCreateBrand, so this undoes BOTH for this row.
						// A rollback failure means the tx is unrecoverable —
						// bail this row exactly like the prodErr never-drop path.
						if rbErr := tx.RollbackTo(spName).Error; rbErr != nil {
							failed++
							errors = append(errors, fmt.Sprintf("rollback failed for unverified row %s (tx unrecoverable): %v", brandName, rbErr))
							continue
						}
						rr := UnverifiedRow{
							RowNumber: item.RowNumber,
							BrandName: brandName,
							Size:      sizeStr,
							Reason:    "unverified_no_catalog_match",
						}
						if rr.RowNumber == 0 {
							rr.RowNumber = idx + 1
						}
						rejectedUnreadable++
						rejectedUnreadableRows = append(rejectedUnreadableRows, rr)
						log.Printf("Smart Stock Setup Apply: REJECTED unverified-provenance row '%s' (brand_conf=%.2f [not gated], no master, no photo, not corrected, not operator-authored, not operator-vouched-at-submit) — product NOT created; reported for re-capture/catalog-pick", brandName, brandConf)
						continue
					}
				}

				pid, _, prodErr := s.findOrCreateProduct(tx, tenantID, &shopID, brandRes.BrandID, brandRes.BrandName, catID, sizeStr, sizeML, rate, masterBrandIDPtr, masterVariantIDPtr, deferProductCreate)
				if prodErr == errDeferProductCreate {
					// Unit 1 — pending submit, no existing/catalog match.
					// Roll back THIS row's brand/category create (spName wraps
					// from before resolveCategory + findOrCreateBrand) so a
					// mere request leaves NOTHING behind, then park the item
					// with the zero-UUID sentinel (stock_setup_items.product_id
					// is NOT NULL but has NO FK to products — the zero UUID is
					// a safe "not created yet" marker). RawAIExtraction
					// (ai_brand / ai_rate / picked_saas_* / edited_name /
					// official_brand_name / was_corrected) + record.Size /
					// record.Category carry everything ApproveStockSetup needs
					// to create it then, behind the SAME anti-phantom gate.
					// Pending records write no stock (early-return below), so a
					// zero product_id is inert until approval.
					if rbErr := tx.RollbackTo(spName).Error; rbErr != nil {
						failed++
						errors = append(errors, fmt.Sprintf("rollback failed for deferred row %s (tx unrecoverable): %v", brandName, rbErr))
						continue
					}
					item.ProductID = uuid.Nil.String()
					deferredCreate++
					log.Printf("Smart Stock Setup Apply: DEFERRED create for '%s - %s' to approval (pending; STOCK_SETUP_DEFER_CREATE=1)", brandName, sizeStr)
				} else {
					if prodErr != nil {
					// NEVER-DROP: do not skip a readable row. Roll back the
					// failed attempt, then guarantee the verbatim name lands
					// via the bare fallback (flagged name_verified=false so it
					// is image-verified before any purchase). The row is only
					// counted failed if even the fallback cannot persist —
					// which it is built to never do.
					if rbErr := tx.RollbackTo(spName).Error; rbErr != nil {
						// The per-item savepoint is gone / tx unrecoverable.
						// Bail this row cleanly rather than cascade 25P02.
						failed++
						errors = append(errors, fmt.Sprintf("rollback failed for %s (tx unrecoverable): %v", brandName, rbErr))
						continue
					}
					log.Printf("Smart Stock Setup Apply: primary create failed for '%s' (%v) — engaging never-drop fallback", brandName, prodErr)
					// Wrap the ENTIRE fallback in its own savepoint so that
					// ANY failure inside it (including a swallowed/unexpected
					// poison) can be fully rolled back, guaranteeing a CLEAN
					// transaction for every subsequent item. This is the
					// belt-and-suspenders that makes "0 of N" structurally
					// impossible from this path.
					spBare := fmt.Sprintf("sp_bare_%d", idx)
					if spe := tx.SavePoint(spBare).Error; spe != nil {
						failed++
						errors = append(errors, fmt.Sprintf("bare savepoint failed for %s (tx unrecoverable): %v", brandName, spe))
						continue
					}
					barePID, bareErr := s.findOrCreateProductBare(tx, tenantID, &shopID, brandRes.BrandID, brandRes.BrandName, catID, sizeStr, rate, item.RowNumber)
					if bareErr != nil {
						tx.RollbackTo(spBare) // guarantee a clean tx for the next item
						failed++
						errors = append(errors, fmt.Sprintf("Could not save %s even via never-drop fallback: %v", brandName, bareErr))
						continue
					}
					pid = barePID
				}
				item.ProductID = pid.String()
				log.Printf("Smart Stock Setup Apply: Created product '%s - %s' (category: %s) on user confirm", brandRes.BrandName, sizeStr, catID)

				// Backfill saas_brand_id when the row went through custom-create (no client master link
				// AND no prior tenant-state match). Without this, custom rows stay orphaned and the next
				// size of the same brand can't dedupe against the master catalog.
				if masterBrandIDPtr == nil {
					tenantStateApply := s.getTenantState(tenantID)
					masterBrandsApply := s.loadMasterBrands(sizeML, tenantStateApply)
					searchName := brandName
					if item.EditedName != "" {
						searchName = item.EditedName
					}
					if mb := s.findMasterBrand(searchName, sizeML, rate, masterBrandsApply); mb != nil {
						updates := map[string]interface{}{}
						if mbID, perr := uuid.Parse(mb.BrandID); perr == nil {
							updates["saas_brand_id"] = mbID
						}
						if mb.VariantID != "" {
							if vID, perr := uuid.Parse(mb.VariantID); perr == nil {
								updates["saas_variant_id"] = vID
							}
						}
						if len(updates) > 0 {
							// ROOT-CAUSE FIX (2026-05-17, the real "Saved 0 of 29"):
							// idx_products_tenant_saas_variant_unique is
							// (tenant_id, saas_variant_id). If ANOTHER product in
							// this tenant already owns this variant, this backfill
							// UPDATE raises 23505 — and UNGUARDED (error ignored,
							// no savepoint) it POISONS the whole apply transaction,
							// cascading 25P02 into every later row's stock lookup,
							// savepoint create, category resolve AND the final
							// idempotency lookup → nothing saves. This is a
							// BEST-EFFORT link: on conflict the product simply
							// stays unlinked (still fully saved), the tx stays
							// clean, and the remaining rows apply normally.
							spBackfill := fmt.Sprintf("sp_vbackfill_%d", idx)
							if spe := tx.SavePoint(spBackfill).Error; spe == nil {
								if upErr := tx.Model(&models.Product{}).
									Where("id = ? AND tenant_id = ? AND saas_brand_id IS NULL", pid, tenantID).
									Updates(updates).Error; upErr != nil {
									tx.RollbackTo(spBackfill)
									log.Printf("Smart Stock Setup Apply: saas_variant backfill skipped for product %s (non-fatal, stays unlinked): %v", pid, upErr)
								}
							}
						}
					}
				}
				} // end else (Unit 1: non-deferred create path)
			}

			productID, parseErr := uuid.Parse(item.ProductID)
			if parseErr != nil {
				failed++
				errors = append(errors, fmt.Sprintf("Invalid product ID: %s", item.ProductID))
				continue
			}
			if item.Quantity < 0 {
				failed++
				errors = append(errors, fmt.Sprintf("Negative quantity for %s: %d", item.BrandName, item.Quantity))
				continue
			}

			// Get current DB stock for record
			var prevQty int
			var existingStock models.Stock
			if stockErr := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", shopID, productID, tenantID).
				First(&existingStock).Error; stockErr == nil {
				prevQty = existingStock.Quantity
			}

			// v1.0.250 — Persist Front/Back photos onto the linked PRODUCT so
			// the same photo appears everywhere the product is shown (inventory
			// list, Manual Purchase picker, product detail, edit screen).
			// Before v250 photos lived only on stock_setup_items, so chhotu had
			// to re-upload for each new flow. The fields on the products table
			// were already migrated in v249; this is the write-side that uses
			// them. Idempotent: re-applying the same Stock Setup row just
			// overwrites with the same URL.
			if item.FrontImageURL != "" || item.BackImageURL != "" || item.BackImageMRP > 0 {
				productPhotoUpdates := map[string]interface{}{}
				if item.FrontImageURL != "" {
					productPhotoUpdates["front_image_url"] = item.FrontImageURL
				}
				if item.BackImageURL != "" {
					productPhotoUpdates["back_image_url"] = item.BackImageURL
				}
				if item.VerifiedViaImageFront || item.VerifiedViaImage {
					productPhotoUpdates["verified_via_image_front"] = true
				}
				if item.VerifiedViaImageBack {
					productPhotoUpdates["verified_via_image_back"] = true
				}
				if item.BackImageMRP > 0 {
					productPhotoUpdates["back_image_mrp"] = item.BackImageMRP
				}
				if len(productPhotoUpdates) > 0 {
					productPhotoUpdates["photo_verified_at"] = time.Now()
					// Same class as the saas_variant backfill above: this is a
					// non-fatal best-effort write, so it MUST NOT be able to
					// poison the apply transaction. Savepoint-guard it — on any
					// failure roll back just this UPDATE and continue; photos
					// still live on stock_setup_items.
					spPhoto := fmt.Sprintf("sp_photo_%d", idx)
					if spe := tx.SavePoint(spPhoto).Error; spe == nil {
						if upErr := tx.Model(&models.Product{}).
							Where("id = ? AND tenant_id = ?", productID, tenantID).
							Updates(productPhotoUpdates).Error; upErr != nil {
							tx.RollbackTo(spPhoto)
							log.Printf("Smart Stock Setup Apply: photo persist on product %s skipped (non-fatal, photos still on stock_setup_items): %v", productID, upErr)
						}
					}
				}
			}

			resolved = append(resolved, resolvedItem{ProductID: productID, Item: item, PrevStock: prevQty})
		}

		// v1.0.256 — fail loud on an empty apply. Previously only the
		// (resolved==0 && failed>0) case errored; (resolved==0 && failed==0)
		// fell through and created a 0-item record (or none) while returning
		// HTTP 200 "success" — the operator's reviewed setup silently
		// vanished. No resolved items ⇒ nothing to record; surface it.
		if len(resolved) == 0 {
			return fmt.Errorf("no items to apply (resolved 0, failed %d) — nothing was saved; please retry", failed)
		}

		// ========================================
		// Create StockSetupRecord for approval tracking
		// ========================================
		// v1.0.129 — totalVal must use the SAME effectiveItemRate as the per-row
		// Amount (L4596-4609): when user edited MRP, MRP wins over the raw AI
		// rate. Pre-v1.0.129 totalVal summed `r.Item.Rate * Qty` while per-row
		// Amount used `effectiveItemRate * Qty`, so the summary card "Total
		// Value" diverged from the table-footer sum on any record with MRP
		// edits. Real case: record `43140443` summary said ₹2,66,700 vs footer
		// ₹2,67,780 (off by ₹1,080).
		totalQty := 0
		totalVal := 0.0
		for _, r := range resolved {
			totalQty += r.Item.Quantity
			rowRate := r.Item.Rate
			if r.Item.MRP > 1 && r.Item.MRP != r.Item.Rate {
				rowRate = r.Item.MRP
			}
			totalVal += rowRate * float64(r.Item.Quantity)
		}

		recordStatus := "approved"
		if needsApproval {
			recordStatus = "pending"
		}

		// Parse receipt images from request
		var receiptImages models.JSONStringList
		for _, url := range req.ImageURLs {
			receiptImages = append(receiptImages, url)
		}

		now := time.Now()
		// v1.0.216 — idempotency: if the same session_id already produced a
		// stock-setup record (Apply replay after a flaky network), return that
		// one instead of inserting a duplicate. The (tenant_id, session_id)
		// partial unique index is the final defense — even concurrent retries
		// can't both succeed.
		var sessionPtr *string
		if req.SessionID != "" {
			sid := req.SessionID
			sessionPtr = &sid
			var existing models.StockSetupRecord
			lookupErr := tx.Where("tenant_id = ? AND session_id = ? AND deleted_at IS NULL", tenantID, sid).
				First(&existing).Error
			if lookupErr == nil {
				log.Printf("Smart Stock Setup Apply: idempotent replay detected — session=%s already produced record %s (status=%s); returning existing", sid, existing.ID, existing.Status)
				setupRecordID = existing.ID
				// Re-derive counts from the existing record so the response
				// matches the original Apply. Banking-grade: replay returns
				// the same numbers, never re-bumps stocks.quantity.
				var itemCount int64
				tx.Model(&models.StockSetupItem{}).
					Where("stock_setup_record_id = ?", existing.ID).
					Count(&itemCount)
				applied = int(itemCount)
				failed = 0
				return nil
			} else if lookupErr != gorm.ErrRecordNotFound {
				return fmt.Errorf("idempotency lookup failed: %w", lookupErr)
			}
		}

		setupRecord := models.StockSetupRecord{
			TenantModel:   models.TenantModel{TenantID: &tenantID},
			ShopID:        shopID,
			Category:      req.CategoryID,
			Size:          req.Size,
			TotalItems:    len(resolved),
			TotalQuantity: totalQty,
			TotalValue:    totalVal,
			Status:        recordStatus,
			CreatedByID:   userID,
			Notes:         notes,
			ReceiptImages: receiptImages,
			AIModel:       "Fomoa AI",
			SessionID:     sessionPtr,
		}
		if !needsApproval {
			setupRecord.ApprovedAt = &now
			setupRecord.ApprovedByID = &userID
		}

		// v1.0.256 — FAIL LOUD on record-create failure (was the v1.0.132
		// silent-loss class, still live for the parent record). Previously a
		// failed Create was logged as a Warning + RollbackTo, then fell
		// through returning nil → HTTP 200 "success" with NO record while
		// Pass-2 could still move stock. Return the error so the whole txn
		// aborts and the operator sees a real failure (and the session_id
		// idempotency lets them safely retry) instead of a false success.
		if createErr := tx.Create(&setupRecord).Error; createErr != nil {
			log.Printf("ERROR: stock setup record create failed (aborting txn, no partial apply): %v", createErr)
			return fmt.Errorf("failed to create stock setup record: %w", createErr)
		} else {
			setupRecordID = setupRecord.ID

			// Create StockSetupItem entries — preserve register audit columns (opening/receipt/sale)
			// sent by the client so the historical record reflects what was actually in the register.
			// Fallback: if the client didn't send OpeningStock but the selected stock column was
			// "opening" (meaning Quantity IS the opening value), use Quantity as OpeningStock.
			selectedColumn := strings.ToLower(strings.TrimSpace(req.StockColumn))
			// v1.0.255 — prefetch resilient photo candidates once so an
			// APPROVED item permanently carries its Front/Back URLs even when
			// the submit payload + v252 app-key both failed (stale app).
			// Window anchored at now() — operator photographs then submits.
			applyCands := s.loadAuditCands(tenantID, shopID, time.Now())
			applyRowCount := map[int]int{}
			for _, rr := range resolved {
				if rr.Item.RowNumber > 0 {
					applyRowCount[rr.Item.RowNumber]++
				}
			}
			for _, r := range resolved {
				openingStock := r.Item.OpeningStock
				if openingStock == 0 && selectedColumn == "opening" {
					openingStock = r.Item.Quantity
				}
				// v1.0.125 — effective rate. When Flutter sent both rate and mrp,
				// MRP is the user-edited price (row-edit Save handler at L6256).
				// Use whichever > 1; mrp wins on conflict so user edits persist.
				// Without this fix, ssi.rate stayed at AI value even when user
				// edited MRP — admin portal renders ssi.rate, so user's edit
				// "looked lost" (record edbbe25d 2026-04-30: 8 user_corrected
				// rows with saved=ai_rate identical).
				effectiveItemRate := r.Item.Rate
				if r.Item.MRP > 1 && r.Item.MRP != r.Item.Rate {
					effectiveItemRate = r.Item.MRP
				}
				// v1.0.249 — back-photo MRP rescue. Chhotu's row 34: JW Black
				// Label, AI extracted rate=₹1 (empty/smudged cell), back photo
				// Gemini correctly read ₹3110. Before this fix the row was
				// applied with rate=₹1 — looked "rubbish" to chhotu.
				// Trust the back-photo MRP when:
				//   - AI rate is clearly broken (≤1 = missed cell), OR
				//   - AI rate is < 30% of back-photo MRP (huge mismatch,
				//     almost always AI digit drop e.g. ₹311 read as ₹31).
				// Conservative: never override a sane AI rate with back-MRP
				// even if they differ — operator's edit (r.Item.MRP) still
				// wins ahead of this rule, so manual corrections are safe.
				if r.Item.BackImageMRP > 0 && r.Item.VerifiedViaImageBack {
					backMRP := r.Item.BackImageMRP
					if effectiveItemRate <= 1 ||
						(effectiveItemRate > 1 && r.Item.MRP <= 1 && backMRP > effectiveItemRate*3) {
						log.Printf("Smart Stock Setup: back-photo MRP rescue row %d: ai_rate=%.0f → back_photo=%.0f",
							r.Item.RowNumber, effectiveItemRate, backMRP)
						effectiveItemRate = backMRP
					}
				}
				setupItem := models.StockSetupItem{
					TenantModel:        models.TenantModel{TenantID: &tenantID},
					StockSetupRecordID: setupRecord.ID,
					ProductID:          r.ProductID,
					Quantity:           r.Item.Quantity,
					OpeningStock:       openingStock,
					Receipt:            r.Item.Receipt,
					Sale:               r.Item.Sale,
					Rate:               effectiveItemRate,
					Amount:             effectiveItemRate * float64(r.Item.Quantity),
					PreviousDBStock:    r.PrevStock,
					UserCorrected:      r.Item.WasCorrected,
					// v1.0.246 — Persist Front/Back verification photos onto
					// the record so admin's StockSetupDetail page can render
					// thumbnails per row. Photo URLs are durable paths under
					// /uploads/stock_setup/verifications/{tenant}/{shop}/.
					// Before v246 these fields were on the apply payload but
					// dropped at write time, leaving admin blind to what the
					// operator actually photographed.
					FrontImageURL:          r.Item.FrontImageURL,
					BackImageURL:           r.Item.BackImageURL,
					VerifiedViaImageFront:  r.Item.VerifiedViaImageFront,
					VerifiedViaImageBack:   r.Item.VerifiedViaImageBack,
					BackImageMRP:           r.Item.BackImageMRP,
					// Legacy single-photo carrier (v243); falls back to Front.
					VerifiedImageURL: firstNonEmptyStr(r.Item.FrontImageURL, r.Item.VerifiedImageURL),
					VerifiedViaImage: r.Item.VerifiedViaImage || r.Item.VerifiedViaImageFront,
					GeminiAgreed:     r.Item.GeminiAgreed,
				}
				// GeminiConfidence is *float64 on the model (nullable) but float64
				// on the apply payload (defaulting to 0 when unknown). Only set
				// when the caller actually sent a value.
				if r.Item.GeminiConfidence > 0 {
					gc := r.Item.GeminiConfidence
					setupItem.GeminiConfidence = &gc
				}
				// WS-2.4: persist the raw AI extraction blob so post-mortem audits
				// can answer "what did the AI actually see?" weeks later. Powers
				// future few-shot training by pairing predicted-vs-approved.
				// Includes ALL register columns the client sent (opening/receipt/
				// sale/closing) plus picker linkage, so we can debug collapse
				// patterns ("all opening=0") and master-pick failures ("user
				// picked XCLAMATION but row linked to BACARDI") without hoping
				// the AI logs are still around.
				if rawJSON, mErr := json.Marshal(map[string]interface{}{
					"ocr_text":              r.Item.OCRText,
					"ai_brand":              r.Item.BrandName,
					"ai_qty":                r.Item.Quantity,
					"ai_rate":               r.Item.Rate,
					"ai_opening":            r.Item.OpeningStock,
					"ai_receipt":            r.Item.Receipt,
					"ai_sale":               r.Item.Sale,
					"ai_closing":            r.Item.ClosingStock,
					"ai_field_confidence":   r.Item.FieldConfidence,
					"ai_row_number":         r.Item.RowNumber,
					"ai_page_number":        r.Item.PageNumber,
					"original_product_id":   r.Item.OriginalProductID,
					"was_corrected":         r.Item.WasCorrected,
					"picked_saas_brand_id":  r.Item.SaasBrandID,
					"picked_saas_variant_id": r.Item.SaasVariantID,
					"official_brand_name":   r.Item.OfficialBrandName,
					"edited_name":           r.Item.EditedName,
					"extractor_model":       setupRecord.AIModel,
					// v1.0.291 — persist the submit-time vouching flag so the
					// approve-time anti-phantom gate (~line 7596) can honor the
					// operator's original vouch when the row was deferred. Without
					// this, approve would re-reject what submit already accepted.
					"operator_vouched_at_submit": r.Item.OperatorVouchedAtSubmit,
				}); mErr == nil {
					setupItem.RawAIExtraction = datatypes.JSON(rawJSON)
				}
				// v1.0.255 — fill-only-empty tiered backfill (exact keys only,
				// app-version-independent; ambiguous row → skip).
				if len(applyCands) > 0 {
					ps := pickItemPhotos(applyCands, r.ProductID.String(),
						r.Item.RowNumber, r.Item.PageNumber, req.SessionID,
						applyRowCount[r.Item.RowNumber] > 1)
					if setupItem.FrontImageURL == "" && ps.Front != "" {
						setupItem.FrontImageURL = ps.Front
						setupItem.VerifiedViaImageFront = true
						setupItem.VerifiedViaImage = true
						if setupItem.VerifiedImageURL == "" {
							setupItem.VerifiedImageURL = ps.Front
						}
					}
					if setupItem.BackImageURL == "" && ps.Back != "" {
						setupItem.BackImageURL = ps.Back
						setupItem.VerifiedViaImageBack = true
					}
					if setupItem.BackImageMRP == 0 && ps.BackMRP > 0 {
						setupItem.BackImageMRP = ps.BackMRP
					}
				}
				// 2026-05-18 — make v255-rescued photo URLs visible to the
				// instant product-photo persistence below (and on approval)
				// even when the submit payload never carried them (stale-app
				// class — Fix A). r.Item is a pointer, so this is seen by the
				// decoupled photo/name pass before the pending early-return.
				if r.Item.FrontImageURL == "" && setupItem.FrontImageURL != "" {
					r.Item.FrontImageURL = setupItem.FrontImageURL
					r.Item.VerifiedViaImageFront = true
					r.Item.VerifiedViaImage = true
				}
				if r.Item.BackImageURL == "" && setupItem.BackImageURL != "" {
					r.Item.BackImageURL = setupItem.BackImageURL
					r.Item.VerifiedViaImageBack = true
				}
				if r.Item.BackImageMRP == 0 && setupItem.BackImageMRP > 0 {
					r.Item.BackImageMRP = setupItem.BackImageMRP
				}
				if itemErr := tx.Create(&setupItem).Error; itemErr != nil {
					// Past silent-bug: when AutoMigrate skipped a new column the
					// item insert errored, was logged, but GORM marked the tx
					// errored anyway and rolled back the parent record. Result:
					// salesman submitted, admin saw nothing, no error surfaced.
					// Now we ABORT the transaction explicitly so the apply
					// handler returns 500 and the salesman retries — NEVER
					// silently swallow item-create errors.
					log.Printf("ERROR: failed to create stock setup item for product %s: %v — aborting transaction so the salesman can retry instead of getting a silent partial-record",
						r.ProductID, itemErr)
					return fmt.Errorf("stock setup item create failed: %w", itemErr)
				}
			}
			log.Printf("Smart Stock Setup: Created record %s (status: %s, items: %d)", setupRecord.ID, recordStatus, len(resolved))
		}

		// v1.0.125 — per-shop rate learning. For every user-corrected row,
		// upsert (shop_id, product_id) → user's rate into shop_product_rates.
		// Future extractions on the same shop+product consult this table
		// during cross-validation; if the AI rate diverges from the learned
		// rate by >5%, prefer the learned rate and warn the user. This makes
		// "fix it twice → permanent" automatic — the bug class where Tushar
		// reuploaded the same image and got the same wrong rate is fixed at
		// the system level.
		for _, r := range resolved {
			if !r.Item.WasCorrected {
				continue
			}
			rateForLearn := r.Item.MRP
			if rateForLearn <= 1 && r.Item.Rate > 1 {
				rateForLearn = r.Item.Rate
			}
			if rateForLearn <= 1 {
				continue
			}
			// v1.0.193 W4-audit P1 fix — write to s.db (NOT tx) so the rate
			// write SURVIVES txn rollback. Pre-fix: this upsert was inside
			// the apply transaction; an item-insert failure rolled back the
			// rate-write too, silently dropping the operator's correction
			// signal. Same bug-class as the May-1 alias-loss that
			// motivated v1.0.132.
			//
			// Safe to write outside the txn because shop_product_rates uses
			// ON CONFLICT upserts — re-running the apply on a retry just
			// bumps occurrence_count again, which is the desired behaviour.
			if upsertErr := s.db.Exec(`
				INSERT INTO shop_product_rates
					(tenant_id, shop_id, product_id, last_user_rate, last_corrected_at,
					 last_corrected_by_id, occurrence_count, source, created_at, updated_at)
				VALUES (?, ?, ?, ?, NOW(), ?, 1, 'stock_setup', NOW(), NOW())
				ON CONFLICT (tenant_id, shop_id, product_id) DO UPDATE SET
					last_user_rate = EXCLUDED.last_user_rate,
					last_corrected_at = NOW(),
					last_corrected_by_id = EXCLUDED.last_corrected_by_id,
					occurrence_count = shop_product_rates.occurrence_count + 1,
					source = EXCLUDED.source,
					updated_at = NOW()
			`, tenantID, shopID, r.ProductID, rateForLearn, userID).Error; upsertErr != nil {
				log.Printf("Smart Stock Setup: shop_product_rates upsert failed for %s: %v", r.ProductID, upsertErr)
			} else {
				log.Printf("Smart Stock Setup: LEARNED shop rate — shop=%s product=%s rate=₹%.2f (user_correction)",
					shopID, r.ProductID, rateForLearn)
			}
		}

		// ========================================
		// 2026-05-18 — Decouple photo + verified name from the stock-
		// approval gate (Option A). A product's bottle photo and its
		// operator-confirmed / photo-verified NAME are CORRECTIONS, not
		// stock movements: they must reflect instantly everywhere the
		// product is shown even when the record is pending manager
		// approval (executive/salesman). The stock QUANTITY + MRP still
		// wait for approval (Pass 2 below). Runs for BOTH paths — for
		// admin/manager it's idempotent against v250/Pass-2 (same values);
		// for pending it's the only place these land before approval.
		// Savepoint-guarded + non-fatal per the v132/v250 poisoning
		// lessons: a bad per-row write must never abort the apply txn.
		// ========================================
		for pnIdx, r := range resolved {
			item := r.Item
			pu := map[string]interface{}{}
			if item.FrontImageURL != "" {
				pu["front_image_url"] = item.FrontImageURL
			}
			if item.BackImageURL != "" {
				pu["back_image_url"] = item.BackImageURL
			}
			if item.VerifiedViaImageFront || item.VerifiedViaImage {
				pu["verified_via_image_front"] = true
			}
			if item.VerifiedViaImageBack {
				pu["verified_via_image_back"] = true
			}
			if item.BackImageMRP > 0 {
				pu["back_image_mrp"] = item.BackImageMRP
			}
			if len(pu) > 0 {
				pu["photo_verified_at"] = time.Now()
			}
			// Operator's authoritative name edit reflects on the product
			// row immediately (mirrors Pass-2's `name = EditedName`). When
			// the row was photo-verified, also flag name_verified=true so
			// the inventory chip + purchase / AI-Purchase image gates stop
			// treating it as raw OCR. MRP is intentionally NOT set here —
			// it rides the approval gate with stock (Pass 2).
			if strings.TrimSpace(item.EditedName) != "" {
				pu["name"] = strings.TrimSpace(item.EditedName)
			}
			if item.VerifiedViaImageFront || item.VerifiedViaImageBack || item.VerifiedViaImage {
				pu["name_verified"] = true
			}
			if len(pu) == 0 {
				continue
			}
			spPN := fmt.Sprintf("sp_pn_%d", pnIdx)
			if spe := tx.SavePoint(spPN).Error; spe != nil {
				continue
			}
			if upErr := tx.Model(&models.Product{}).
				Where("id = ? AND tenant_id = ?", r.ProductID, tenantID).
				Updates(pu).Error; upErr != nil {
				tx.RollbackTo(spPN)
				log.Printf("Smart Stock Setup Apply: instant photo/name persist on product %s skipped (non-fatal, record still records it): %v", r.ProductID, upErr)
			}
		}

		// ========================================
		// If salesman: stop here — stock will be applied on approval
		// ========================================
		if needsApproval {
			applied = len(resolved)
			return nil
		}

		// ========================================
		// Pass 2: Apply stock (admin/manager — auto-approved)
		// ========================================

		// SNAPSHOT RESET: zero out stock for products at the same (shop, size,
		// beer/non-beer bucket) that are NOT in this apply set. The setup is
		// treated as a complete snapshot — any stale stock for products absent
		// from the register is cleared (clamped to reserved_quantity to preserve
		// pending orders).
		if req.Size != "" {
			bucket := ""
			if req.CategoryID != "" {
				var catName struct{ Name string }
				if catErr := tx.Table("categories").Select("name").
					Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).
					Scan(&catName).Error; catErr == nil && catName.Name != "" {
					if strings.EqualFold(catName.Name, "beer") {
						bucket = "beer"
					} else {
						bucket = "non_beer"
					}
				}
			}
			applyIDs := make(map[string]bool, len(resolved))
			setupIDs := make([]string, 0, len(resolved))
			for _, r := range resolved {
				id := r.ProductID.String()
				applyIDs[id] = true
				setupIDs = append(setupIDs, id)
			}
			// v1.0.218 — canonical-brand expansion (see ApproveStockSetup comment).
			if added := s.expandApplyIDsByCanonicalBrand(tx, tenantID, req.Size, applyIDs, setupIDs); added > 0 {
				log.Printf("ApplyStockSetup auto-apply: canonical-brand expansion added %d sibling product_ids", added)
			}
			ref := fmt.Sprintf("Smart Stock Setup (auto-apply): record %s — cleared not in setup", setupRecordID)
			if cleared, clearErr := s.clearStaleStockOutsideSetup(tx, tenantID, shopID, setupRecordID, req.Size, bucket, applyIDs, ref, userID); clearErr != nil {
				log.Printf("ApplyStockSetup auto-apply: clearStaleStockOutsideSetup error: %v", clearErr)
			} else if cleared > 0 {
				log.Printf("ApplyStockSetup auto-apply: cleared %d stale stocks at shop %s (size=%s, bucket=%s)",
					cleared, shopID, req.Size, bucket)
			}
		}

		for idx, r := range resolved {
			item := r.Item

			// v1.0.132 — per-row savepoint for Pass 2 (stock + product MRP +
			// history). Same reasoning as the Pass 1 wrapper: any future
			// schema-mismatch on a per-row write must not abort the whole
			// apply. A failed row gets rolled back to this savepoint, the
			// remainder of the loop continues, and the caller still gets a
			// `partial` result with explicit errors instead of "200 OK,
			// nothing applied".
			spApply := fmt.Sprintf("sp_apply_%d", idx)
			if spErr := tx.SavePoint(spApply).Error; spErr != nil {
				failed++
				errors = append(errors, fmt.Sprintf("savepoint failed for %s: %v", item.BrandName, spErr))
				continue
			}

			// Get or create stock record with row-level locking.
			//
			// v1.0.297 — prefer the LIVE row when both live + soft-deleted exist.
			// Without the explicit Order, GORM's First() returns the lexically-
			// smallest UUID, which can be the soft-deleted ghost. The v1.0.295
			// revive path then clears its DeletedAt and Save() trips the
			// idx_stocks_unique_live_tenant_shop_product partial unique index
			// because another live row already holds that key. Real failure
			// observed on chhotu's 750ml approve for product def6e8a1: ghost
			// 99928b30 (soft-deleted 2026-05-14) sorted before live a533e837;
			// SELECT picked the ghost, Save → 23505, whole approve tx poisoned.
			// ORDER BY deleted_at NULLS FIRST puts live rows first; we only
			// reach the revive branch when no live row exists.
			var stock models.Stock
			stockErr := tx.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?", shopID, r.ProductID, tenantID).
				Order("deleted_at NULLS FIRST, id ASC").
				First(&stock).Error

			if stockErr != nil {
				if stockErr == gorm.ErrRecordNotFound {
					stock = models.Stock{
						TenantModel:   models.TenantModel{TenantID: &tenantID},
						ShopID:        shopID,
						ProductID:     r.ProductID,
						Quantity:      0,
						CostingMethod: "fifo",
					}
					if createErr := tx.Create(&stock).Error; createErr != nil {
						tx.RollbackTo(spApply)
						failed++
						errors = append(errors, fmt.Sprintf("Failed to create stock for %s: %v", item.BrandName, createErr))
						continue
					}
				} else {
					tx.RollbackTo(spApply)
					failed++
					errors = append(errors, fmt.Sprintf("Failed to query stock for %s: %v", item.BrandName, stockErr))
					continue
				}
			} else if stock.DeletedAt.Valid {
				// Revive a soft-deleted row instead of creating a duplicate.
				stock.DeletedAt = gorm.DeletedAt{}
			}

			previousQuantity := stock.Quantity

			if item.Quantity < stock.ReservedQuantity {
				tx.RollbackTo(spApply)
				failed++
				errors = append(errors, fmt.Sprintf("Cannot set %s to %d (reserved: %d)", item.BrandName, item.Quantity, stock.ReservedQuantity))
				continue
			}

			stock.Quantity = item.Quantity
			// v1.0.295 — Unscoped().Save so reviving a soft-deleted row actually
			// clears deleted_at on the UPDATE; without it GORM's auto deleted_at
			// IS NULL filter on the UPDATE WHERE skips ghost rows.
			if saveErr := tx.Unscoped().Save(&stock).Error; saveErr != nil {
				tx.RollbackTo(spApply)
				failed++
				errors = append(errors, fmt.Sprintf("Failed to update stock for %s: %v", item.BrandName, saveErr))
				continue
			}

			// Update product name and/or MRP if user edited them.
			// v1.0.122: when Flutter omits item.MRP, fall back to item.Rate.
			// AI Stock Setup's review screen shows ONE rate column the user
			// edits — that value rides on `rate` in the apply payload, not
			// `mrp`. Without this fallback, ChhoTu's price changes during
			// review (record 600a7332: 12 rows where shop sells ₹10–₹730
			// below master MRP) only get persisted on approve, leaving the
			// admin's pending-review screen showing stale catalog MRPs.
			// Persisting at apply-time means admin's pending view = the
			// price actually about to be applied.
			productUpdates := map[string]interface{}{}
			effectiveMRP := item.MRP
			if effectiveMRP <= 1 && item.Rate > 1 {
				effectiveMRP = item.Rate
			}
			if effectiveMRP > 0 && effectiveMRP <= 1 {
				sizeML := normalizeSizeText(item.Size)
				if sizeML == 0 {
					sizeML = normalizeSizeText(req.Size)
				}
				tState := s.getTenantState(tenantID)
				mBrands := s.loadMasterBrands(sizeML, tState)
				brandForLookup := item.EditedName
				if brandForLookup == "" {
					brandForLookup = item.BrandName
				}
				if mb := s.findMasterBrand(brandForLookup, sizeML, 0, mBrands); mb != nil && mb.MRP > 0 {
					effectiveMRP = mb.MRP
				}
			}
			// v1.0.123: stamp MRP audit on every change so the 7-day
			// transparency banner can render. Pull current MRP first so we can
			// detect a real change (helper short-circuits on no-op).
			if effectiveMRP > 1 {
				var current models.Product
				if cErr := tx.Select("mrp").Where("id = ? AND tenant_id = ?", r.ProductID, tenantID).First(&current).Error; cErr == nil {
					if absFloatStockSetup(current.MRP-effectiveMRP) >= 0.5 {
						actorName := resolveActorNameStockSetup(tx, userID)
						now := time.Now()
						productUpdates["mrp"] = effectiveMRP
						productUpdates["selling_price"] = effectiveMRP
						productUpdates["last_mrp_change_at"] = now
						productUpdates["last_mrp_change_previous"] = current.MRP
						productUpdates["last_mrp_change_by_id"] = userID
						productUpdates["last_mrp_change_by_name"] = actorName
					} else {
						// MRP unchanged → still set selling_price (idempotent), no audit.
						productUpdates["mrp"] = effectiveMRP
						productUpdates["selling_price"] = effectiveMRP
					}
				} else {
					productUpdates["mrp"] = effectiveMRP
					productUpdates["selling_price"] = effectiveMRP
				}
			}
			if item.EditedName != "" {
				productUpdates["name"] = item.EditedName
			}
			if len(productUpdates) > 0 {
				// v1.0.132 — check the error and roll back the row's savepoint
				// instead of silently swallowing it. Pre-fix this Updates was
				// the ground-zero call for the May 1 incident: it produced
				// `column "last_m_rpchange_at" does not exist` (SQLSTATE 42703),
				// which poisoned the wrapping txn. Even though the column tag
				// fix in pkg/shared/models/inventory.go closes that specific
				// hole, future product columns added to productUpdates can hit
				// the same class of failure, so we must surface the error here.
				if updErr := tx.Model(&models.Product{}).Where("id = ? AND tenant_id = ?", r.ProductID, tenantID).Updates(productUpdates).Error; updErr != nil {
					tx.RollbackTo(spApply)
					failed++
					errors = append(errors, fmt.Sprintf("Failed to update product for %s: %v", item.BrandName, updErr))
					log.Printf("ApplyStockSetup: product update failed for %s: %v (updates=%v) — rolled back row savepoint", r.ProductID, updErr, productUpdates)
					continue
				}
				log.Printf("ApplyStockSetup: persisted product updates for %s: %v (item.MRP=%.2f, item.Rate=%.2f, effectiveMRP=%.2f)",
					r.ProductID, productUpdates, item.MRP, item.Rate, effectiveMRP)
			}

			// Create stock history entry. Quantity is the SIGNED DELTA so the
			// v1.0.216 math-gate trigger (new = prev + qty) passes; setting it
			// to item.Quantity directly would fail whenever previousQuantity > 0.
			ssShopRef, ssProdRef := stock.ShopID, stock.ProductID
			history := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: &tenantID},
				StockID:          stock.ID,
				ShopID:           &ssShopRef,
				ProductID:        &ssProdRef,
				MovementType:     "opening_stock_setup",
				Quantity:         item.Quantity - previousQuantity,
				PreviousQuantity: previousQuantity,
				NewQuantity:      item.Quantity,
				Reference:        fmt.Sprintf("Smart Stock Setup: %s %s", item.BrandName, item.Size),
				Notes:            notes,
				CreatedByID:      userID,
			}
			if histErr := tx.Create(&history).Error; histErr != nil {
				tx.RollbackTo(spApply)
				failed++
				errors = append(errors, fmt.Sprintf("Failed to create history for %s: %v", item.BrandName, histErr))
				continue
			}

			applied++
		}

		// If ALL items failed, rollback
		if applied == 0 && failed > 0 {
			return fmt.Errorf("all items failed to apply")
		}

		return nil
	})

	// v1.0.132 — capture learning signal regardless of txn outcome.
	// The alias corpus is the model's memory; losing user review-screen
	// edits because the SQL aborted (May 1 2026 incident: products column
	// mismatch killed the wrapping txn → "200 OK, no record" → user
	// corrections vanished from training data) gives the AI another shot
	// at the same wrong guess. captureApplyLearning is idempotent
	// (LearnAlias / LearnNegativeAlias upsert) and async (non-blocking),
	// so it's safe to call before the error gate. Only the alias-corpus
	// updates and the LogCorrectionOutcomes telemetry depend on
	// req.Items + payload flags — they don't need a successful apply.
	applyOutcome := "applied"
	if err != nil {
		applyOutcome = "apply_failed"
	} else if needsApproval {
		applyOutcome = "pending_approval"
	}
	s.captureApplyLearning(tenantID, userID, req, setupRecordID, applyOutcome)

	// v1.0.133 — per-shop digit-handwriting learning. For every numeric cell
	// where the client echoed an OriginalAI value AND the final value differs,
	// record (raw → corrected) so the extractor's next call to this shop can
	// inject the most-frequent confusions as few-shot guidance. Async,
	// idempotent, never blocks the apply response.
	if shopID != uuid.Nil && len(req.Items) > 0 {
		var pairs []digitCorrectionPair
		for _, item := range req.Items {
			if !item.WasCorrected {
				continue
			}
			if p := digitCorrectionsFromIntPair("quantity", item.OriginalAIQuantity, item.Quantity); p != nil {
				pairs = append(pairs, *p)
			}
			if p := digitCorrectionsFromIntPair("opening", item.OriginalAIOpening, item.OpeningStock); p != nil {
				pairs = append(pairs, *p)
			}
			if p := digitCorrectionsFromIntPair("receipt", item.OriginalAIReceipt, item.Receipt); p != nil {
				pairs = append(pairs, *p)
			}
			if p := digitCorrectionsFromIntPair("sale", item.OriginalAISale, item.Sale); p != nil {
				pairs = append(pairs, *p)
			}
			if p := digitCorrectionsFromIntPair("closing", item.OriginalAIClosing, item.ClosingStock); p != nil {
				pairs = append(pairs, *p)
			}
			rateForCapture := item.MRP
			if rateForCapture <= 0 {
				rateForCapture = item.Rate
			}
			if p := digitCorrectionsFromFloatPair("rate", item.OriginalAIRate, rateForCapture); p != nil {
				pairs = append(pairs, *p)
			}
		}
		captureDigitCorrections(s.db.DB, tenantID, shopID, "stock_setup", pairs)
	}

	if err != nil {
		return &SmartStockSetupApplyResult{
			Status:        "failed",
			Message:       fmt.Sprintf("Failed to apply stock setup: %v", err),
			ItemsApplied:  0,
			ItemsFailed:   len(req.Items),
			ItemsReceived: len(req.Items),
			Errors:        errors,
		}, nil
	}

	// v1.0.396 — apply-time COVERAGE CHECK. Surface scan items (opening>0,
	// same size) that never made it into this submission so a quietly-omitted
	// row (the Malsaii "8 PM Black 375" case) is visible, not lost. Best-effort,
	// never blocks the apply. Computed once; attached to both return paths.
	coverageMissing := s.computeCoverageMissing(ctx, tenantID, req)
	if len(coverageMissing) > 0 {
		brands := make([]string, 0, len(coverageMissing))
		for _, r := range coverageMissing {
			brands = append(brands, r.BrandName)
		}
		log.Printf("Smart Stock Setup Apply: COVERAGE WARNING — %d scan item(s) (opening>0, size %s) NOT in submission for session %s: %s",
			len(coverageMissing), req.Size, req.SessionID, strings.Join(brands, ", "))
	}

	// For pending records (salesman), return early without clearing cache or applying
	if needsApproval {
		status := "pending_approval"
		message := fmt.Sprintf("Stock setup submitted for %d products — awaiting manager/admin approval", applied)
		// v1.0.283 — unreadable rows were NOT saved; tell the operator loudly
		// and list them (no silent drop — v1.0.279). This is chhotu's exact
		// path (executive role → pending), so it MUST be surfaced here too.
		if rejectedUnreadable > 0 {
			message = fmt.Sprintf("%s — %d row(s) NOT saved: unverified brand (no catalog match, no photo, not confirmed); re-photograph or pick from catalog", message, rejectedUnreadable)
			errors = append(errors, fmt.Sprintf("%d unverified item(s) skipped (not saved): %s", rejectedUnreadable, joinUnverifiedBrands(rejectedUnreadableRows)))
			log.Printf("Smart Stock Setup Apply: ACCOUNTING (pending) — received=%d applied=%d failed=%d zeroSkipped=%d rejectedUnreadable=%d (balanced=%v)",
				len(req.Items), applied, failed, zeroSkipped, rejectedUnreadable,
				len(req.Items) == applied+failed+zeroSkipped+rejectedUnreadable)
		}
		result := &SmartStockSetupApplyResult{
			Status:        status,
			Message:       message,
			ItemsApplied:  applied,
			ItemsFailed:   failed,
			ItemsReceived: len(req.Items),
			Errors:        errors,
		}
		if setupRecordID != uuid.Nil {
			rid := setupRecordID.String()
			result.RecordID = &rid
		}
		// v1.0.248 — surface the unverified-photo audit list so Flutter can
		// render a "follow up in inventory" CTA after submit.
		result.PhotoAuditMissing = photoAuditMissing
		result.RejectedUnreadable = rejectedUnreadableRows
		return result, nil
	}

	// Clear stock cache for this shop (only for auto-approved)
	s.stockService.ClearShopStockCache(ctx, tenantID, shopID)

	status := "success"
	message := fmt.Sprintf("Stock set for %d products", applied)
	if failed > 0 {
		status = "partial"
		message = fmt.Sprintf("Stock set for %d products (%d failed)", applied, failed)
	}
	// v1.0.266 — surface zero-activity skips LOUDLY so they are never a silent
	// loss. The operator/app now sees the exact count + brand list and the
	// returned arithmetic balances: received == applied + failed + zeroSkipped.
	if zeroSkipped > 0 {
		if status == "success" {
			status = "partial"
		}
		message = fmt.Sprintf("%s — %d zero-stock row(s) NOT saved (enable 'Include zero-activity' to keep them)", message, zeroSkipped)
		preview := zeroSkippedBrands
		if len(preview) > 10 {
			preview = preview[:10]
		}
		errors = append(errors, fmt.Sprintf("%d zero-activity item(s) skipped (not saved): %s", zeroSkipped, strings.Join(preview, ", ")))
		log.Printf("Smart Stock Setup Apply: ACCOUNTING — received=%d applied=%d failed=%d zeroSkipped=%d (balanced=%v)",
			len(req.Items), applied, failed, zeroSkipped, len(req.Items) == applied+failed+zeroSkipped)
	}
	// v1.0.283 — unreadable rows surfaced LOUDLY, same contract as zero-skip:
	// explicit count + brand list, status downgraded so the client never
	// reads it as a clean success, accounting balances received == applied +
	// failed + zeroSkipped + rejectedUnreadable.
	if rejectedUnreadable > 0 {
		if status == "success" {
			status = "partial"
		}
		message = fmt.Sprintf("%s — %d unreadable row(s) NOT saved (no catalog match, low confidence, no photo); re-photograph or pick from catalog", message, rejectedUnreadable)
		errors = append(errors, fmt.Sprintf("%d unreadable item(s) skipped (not saved): %s", rejectedUnreadable, joinUnverifiedBrands(rejectedUnreadableRows)))
		log.Printf("Smart Stock Setup Apply: ACCOUNTING — received=%d applied=%d failed=%d zeroSkipped=%d rejectedUnreadable=%d (balanced=%v)",
			len(req.Items), applied, failed, zeroSkipped, rejectedUnreadable,
			len(req.Items) == applied+failed+zeroSkipped+rejectedUnreadable)
	}

	// Save user-confirmed data as training ground truth
	if req.SessionID != "" && applied > 0 {
		SaveAppliedCorrections(tenantID.String(), req.SessionID, StockSetupTrainingRecord{
			SessionID:  req.SessionID,
			AppliedAt:  time.Now(),
			Items:      req.Items,
			ItemCount:  applied,
			CleanedUp:  0,
			CategoryID: req.CategoryID,
			Size:       req.Size,
		})
	}

	// Alias learning + LogCorrectionOutcomes already captured above via
	// captureApplyLearning, regardless of txn outcome (v1.0.132).

	result := &SmartStockSetupApplyResult{
		Status:        status,
		Message:       message,
		ItemsApplied:  applied,
		ItemsFailed:   failed,
		ItemsReceived: len(req.Items),
		CleanedUp:     0,
		Errors:        errors,
	}
	if setupRecordID != uuid.Nil {
		rid := setupRecordID.String()
		result.RecordID = &rid
	}
	// v1.0.248 — surface the unverified-photo audit list so Flutter can
	// render a "follow up in inventory" CTA after submit.
	result.PhotoAuditMissing = photoAuditMissing
	result.RejectedUnreadable = rejectedUnreadableRows
	result.CoverageMissing = coverageMissing
	return result, nil
}

// ============================================================================
// v1.0.396 — apply-time coverage check (no silent drop of scan rows)
// ============================================================================

// coverageStr / coverageInt coerce a JSONB-decoded value (interface{}) into a
// string / int. JSON numbers decode to float64 inside a map[string]interface{}.
func coverageStr(v interface{}) string {
	if s, ok := v.(string); ok {
		return strings.TrimSpace(s)
	}
	return ""
}

func coverageInt(v interface{}) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	case string:
		i, _ := strconv.Atoi(strings.TrimSpace(n))
		return i
	}
	return 0
}

// coverageMissingItems is the PURE comparison: scan rows the extraction
// produced (opening>0, same size as the apply) that the operator never
// submitted. No DB access → unit-testable. Matching is by normalized brand
// key, the same normalizer the matcher uses, so an edited name still counts as
// "submitted". v1.0.396.
func coverageMissingItems(jobItems []interface{}, req SmartStockSetupApplyRequest) []UnverifiedRow {
	submitted := make(map[string]bool)
	add := func(s string) {
		if k := normalizeForMatch(s); k != "" {
			submitted[k] = true
		}
	}
	for _, it := range req.Items {
		add(it.BrandName)
		add(it.EditedName)
		add(it.OfficialBrandName)
	}
	reqML := matching.ParseSizeML(req.Size)
	var missing []UnverifiedRow
	seen := make(map[string]bool)
	for _, ri := range jobItems {
		m, ok := ri.(map[string]interface{})
		if !ok {
			continue
		}
		brand := coverageStr(m["brand_name"])
		if brand == "" {
			brand = coverageStr(m["brand"])
		}
		opening := coverageInt(m["opening"])
		if brand == "" || opening <= 0 {
			continue
		}
		// Only flag rows of the size being applied (apply is per-size). When the
		// scan didn't tag a size_ml, don't exclude on size.
		if sizeML := coverageInt(m["size_ml"]); reqML > 0 && sizeML > 0 && sizeML != reqML {
			continue
		}
		key := normalizeForMatch(brand)
		if key == "" || submitted[key] || seen[key] {
			continue
		}
		seen[key] = true
		missing = append(missing, UnverifiedRow{
			RowNumber: coverageInt(m["row_number"]),
			BrandName: brand,
			Size:      coverageStr(m["size"]),
			Reason:    "extracted_but_not_submitted",
		})
	}
	return missing
}

// computeCoverageMissing loads the session's extraction job and runs the pure
// coverage comparison. Best-effort: any failure returns nil and never blocks
// the apply. v1.0.396.
func (s *SmartStockSetupService) computeCoverageMissing(ctx context.Context, tenantID uuid.UUID, req SmartStockSetupApplyRequest) []UnverifiedRow {
	if req.SessionID == "" {
		return nil
	}
	var job models.SmartStockSetupJob
	if err := s.db.DB.WithContext(ctx).
		Where("tenant_id = ? AND session_id = ? AND deleted_at IS NULL", tenantID, req.SessionID).
		Order("created_at DESC").First(&job).Error; err != nil {
		return nil
	}
	itemsRaw, ok := job.Result["items"].([]interface{})
	if !ok {
		return nil
	}
	return coverageMissingItems(itemsRaw, req)
}

// ============================================================================
// Step 3: Approval Flow — list, get, approve, reject stock setup records
// ============================================================================

// StockSetupRecordResponse is the API response for a stock setup record
type StockSetupRecordResponse struct {
	ID            string                      `json:"id"`
	ShopID        string                      `json:"shop_id"`
	ShopName      string                      `json:"shop_name"`
	Category      string                      `json:"category"`
	CategoryName  string                      `json:"category_name"`
	Size          string                      `json:"size"`
	TotalItems    int                         `json:"total_items"`
	TotalQuantity int                         `json:"total_quantity"`
	TotalValue    float64                     `json:"total_value"`
	Status        string                      `json:"status"`
	ApprovedAt    *time.Time                  `json:"approved_at,omitempty"`
	ApprovedBy    string                      `json:"approved_by,omitempty"`
	RejectionReason string                    `json:"rejection_reason,omitempty"`
	CreatedByID     string                    `json:"created_by_id"`
	CreatedByName   string                    `json:"created_by_name"`
	// v1.0.203 — operator's phone surfaced on the admin record list so a
	// manager reviewing chhotu's submission can tap to call the operator
	// directly when something looks wrong (low-conf rows, manual additions
	// that need clarification, etc). Empty when the operator has no phone
	// recorded on their user profile.
	CreatedByMobile string                    `json:"created_by_mobile"`
	Notes           string                    `json:"notes"`
	ReceiptImages []string                    `json:"receipt_images"`
	AIModel       string                      `json:"ai_model"`
	Items         []StockSetupItemResponse    `json:"items,omitempty"`
	CreatedAt     time.Time                   `json:"created_at"`
	UpdatedAt     time.Time                   `json:"updated_at"`
	// v1.0.290 — surface rows the always-on anti-phantom gate dropped at
	// APPROVE (deferred-create resolver, ~line 7562). Without this the
	// operator just sees the final approved count and can't tell that 5
	// parked rows were silently rejected (record 310beab1 incident: imjum /
	// SM19Jum / M6002Jum / 100 Step / Jamson all rejected at approve, but
	// the operator couldn't see why their app showed N rows but inventory
	// has N-5). Populated only on the approve response; empty otherwise.
	RejectedAtApproveCount int             `json:"rejected_at_approve_count,omitempty"`
	RejectedAtApproveRows  []UnverifiedRow `json:"rejected_at_approve_rows,omitempty"`
}

// StockSetupItemResponse is the API response for a stock setup item.
//
// DisplayName + bold indices come from the linked Product and let the web +
// Flutter review UIs render the admin-chosen "distinctive identifier in bold,
// rest in light weight" treatment that mirrors the search-match UX.
//
// SuspectCatalogLink + Warnings are computed at response-build time (not
// persisted) so managers see catalog-corruption flags the moment they open a
// record — even for records submitted before this check shipped. The flag
// fires when the linked product's display name shares <30% meaningful tokens
// with its brand name (e.g. product "Royal Stag Barrel Select" linked to
// brand "M2 Magic Moments Verve Cranberry"). That's almost always a bad
// brand_id attachment in the tenant catalog, not an AI matching miss — but
// the downstream effect is the same: the manager needs to swap the row to
// the right product before approving.
type StockSetupItemResponse struct {
	ID                    string   `json:"id"`
	ProductID             string   `json:"product_id"`
	ProductName           string   `json:"product_name"`
	BrandName             string   `json:"brand_name"`
	DisplayName           string   `json:"display_name,omitempty"`
	DisplayNameBoldStart  *int     `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int     `json:"display_name_bold_length,omitempty"`
	Size                  string   `json:"size"`
	Quantity              int      `json:"quantity"`
	OpeningStock          int      `json:"opening_stock"`
	Receipt               int      `json:"receipt"`
	Sale                  int      `json:"sale"`
	Rate                  float64  `json:"rate"`
	Amount                float64  `json:"amount"`
	PreviousDBStock       int      `json:"previous_db_stock"`
	// SaaSVariantID is echoed so the Add-Missing picker on the web admin
	// can exclude master-catalog variants that are already on the current
	// record (preventing duplicate rows for the same bottle/size).
	SaaSVariantID         string   `json:"saas_variant_id,omitempty"`
	SuspectCatalogLink    bool     `json:"suspect_catalog_link,omitempty"`
	Warnings              []string `json:"warnings,omitempty"`
	// v1.0.246 — Verification photos echoed so the web admin can render
	// per-row thumbnails. Empty strings when no photo was captured (legacy
	// pre-v243 records).
	FrontImageURL          string   `json:"front_image_url,omitempty"`
	BackImageURL           string   `json:"back_image_url,omitempty"`
	VerifiedViaImageFront  bool     `json:"verified_via_image_front,omitempty"`
	VerifiedViaImageBack   bool     `json:"verified_via_image_back,omitempty"`
	BackImageMRP           float64  `json:"back_image_mrp,omitempty"`
}

// ListStockSetupRecords returns paginated stock setup records for a tenant.
// category / size are optional scope filters so the Flutter AI-stock-setup
// picker can surface pending submissions that match what the user is about to
// set up — e.g. "Whisky 750ML pending approval" appears inline on the size
// picker so two users don't redo the same work.
func (s *SmartStockSetupService) ListStockSetupRecords(ctx context.Context, tenantID uuid.UUID, shopID, status, category, size string, page, pageSize int) (map[string]interface{}, error) {
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 20
	}

	query := s.db.Model(&models.StockSetupRecord{}).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

	if shopID != "" {
		query = query.Where("shop_id = ?", shopID)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if category != "" {
		query = query.Where("category = ?", category)
	}
	if size != "" {
		query = query.Where("size = ?", size)
	}

	var total int64
	query.Count(&total)

	var records []models.StockSetupRecord
	query.Preload("Shop").Preload("Items", orderItemsByRegisterRow).
		Order("created_at DESC").
		Offset((page - 1) * pageSize).Limit(pageSize).
		Find(&records)

	// Build response
	var results []StockSetupRecordResponse
	for _, rec := range records {
		resp := s.buildRecordResponse(rec)
		results = append(results, resp)
	}

	return map[string]interface{}{
		"records":    results,
		"total":      total,
		"page":       page,
		"page_size":  pageSize,
		"total_pages": (total + int64(pageSize) - 1) / int64(pageSize),
	}, nil
}

// PendingCount returns the number of stock_setup_records in 'pending' status
// for the caller's tenant + optional shop scope. Drives the admin sidebar
// badge ("AI Stock Setup ⓷"). Cheap — single COUNT query with a WHERE on
// indexed columns (tenant_id + status + deleted_at IS NULL).
//
// v1.0.203.
func (s *SmartStockSetupService) PendingCount(ctx context.Context, tenantID uuid.UUID, shopID string) (int64, error) {
	q := s.db.Model(&models.StockSetupRecord{}).
		Where("tenant_id = ? AND status = ? AND deleted_at IS NULL", tenantID, "pending")
	if shopID != "" {
		q = q.Where("shop_id = ?", shopID)
	}
	var count int64
	if err := q.Count(&count).Error; err != nil {
		return 0, fmt.Errorf("pending count failed: %w", err)
	}
	return count, nil
}

// orderItemsByRegisterRow is the canonical sort for stock_setup_items —
// register page+row order from the AI extraction (ai_page_number /
// ai_row_number, persisted into the raw_ai_extraction JSONB blob), with
// items missing a row number (manual adds, late captures) pushed to the
// bottom via NULLS LAST. Falls back to created_at + id for ties.
//
// v1.0.296 (2026-05-23) — added because Preload("Items") with no Order
// clause returned rows in PostgreSQL physical order, which shifts every
// time a row is UPDATEd (HOT update may rewrite tuple to a different
// page). chhotu reported items "getting disturbed after sometimes of
// approval" on record 4e90dd7a — exactly that pattern: after approve
// touched a few items, their physical positions shuffled and the web
// admin's items table reordered itself.
//
// Used by every Preload("Items") call in this file.
func orderItemsByRegisterRow(db *gorm.DB) *gorm.DB {
	return db.Order(
		"NULLIF(COALESCE((raw_ai_extraction->>'ai_page_number')::int, 0), 0) ASC NULLS LAST, " +
			"NULLIF(COALESCE((raw_ai_extraction->>'ai_row_number')::int, 0), 0) ASC NULLS LAST, " +
			"created_at ASC, " +
			"id ASC")
}

// GetStockSetupRecordByID returns a single stock setup record with items
func (s *SmartStockSetupService) GetStockSetupRecordByID(ctx context.Context, recordID, tenantID uuid.UUID) (*StockSetupRecordResponse, error) {
	var record models.StockSetupRecord
	err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
		Preload("Shop").
		Preload("Items", orderItemsByRegisterRow).
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		First(&record).Error
	if err != nil {
		return nil, fmt.Errorf("stock setup record not found: %w", err)
	}

	resp := s.buildRecordResponse(record)
	return &resp, nil
}

// expandApplyIDsByCanonicalBrand widens the "do not clear" set so that every
// products row representing the SAME canonical brand at the same shop+size as
// any setup item is preserved — not just the one product_id the matcher
// happened to pick for the setup. Without this, a pending Smart Sale that
// matched the same brand to a duplicate products row gets its stock zeroed at
// Stock Setup approve (root-cause of FM Tower Mahua Khera 2026-05-11 P0:
// pending sale 319389bb's Black & White Celebration product was wiped from
// 18 → 0 because the setup picked a different products row for the same SKU).
//
// Expansion strategy (union):
//   - For every setup product with a non-NULL saas_brand_id, find sibling
//     products in the tenant sharing that saas_brand_id at the same size.
//   - Fallback for setup products with NULL saas_brand_id: expand by
//     normalized lower(trim(name)) at the same size, so unlinked tenant
//     duplicates are also covered.
//
// Returns the number of new IDs added (for logging). Caller continues even on
// error — expansion is best-effort hardening.
func (s *SmartStockSetupService) expandApplyIDsByCanonicalBrand(
	tx *gorm.DB,
	tenantID uuid.UUID,
	sizeText string,
	applyIDs map[string]bool,
	setupProductIDs []string,
) int {
	sizeML := normalizeSizeText(sizeText)
	if sizeML == 0 || len(setupProductIDs) == 0 {
		return 0
	}
	type pRow struct {
		ID          string  `gorm:"column:id"`
		Name        string  `gorm:"column:name"`
		Size        string  `gorm:"column:size"`
		SaasBrandID *string `gorm:"column:saas_brand_id"`
	}
	var setupRows []pRow
	if err := tx.Table("products").
		Select("id::text AS id, name, size, saas_brand_id::text AS saas_brand_id").
		Where("tenant_id = ? AND id IN ? AND deleted_at IS NULL", tenantID, setupProductIDs).
		Scan(&setupRows).Error; err != nil {
		log.Printf("expandApplyIDsByCanonicalBrand: setup-row lookup failed: %v", err)
		return 0
	}

	saasBrandIDs := make([]string, 0, len(setupRows))
	normalizedNames := make([]string, 0, len(setupRows))
	for _, r := range setupRows {
		if r.SaasBrandID != nil && *r.SaasBrandID != "" {
			saasBrandIDs = append(saasBrandIDs, *r.SaasBrandID)
		} else {
			n := strings.ToLower(strings.TrimSpace(r.Name))
			if n != "" {
				normalizedNames = append(normalizedNames, n)
			}
		}
	}

	added := 0
	addCandidate := func(rows []pRow) {
		for _, r := range rows {
			if normalizeSizeText(r.Size) != sizeML {
				continue
			}
			if applyIDs[r.ID] {
				continue
			}
			applyIDs[r.ID] = true
			added++
		}
	}

	if len(saasBrandIDs) > 0 {
		var rows []pRow
		if err := tx.Table("products").
			Select("id::text AS id, name, size, saas_brand_id::text AS saas_brand_id").
			Where("tenant_id = ? AND saas_brand_id IN ? AND deleted_at IS NULL", tenantID, saasBrandIDs).
			Scan(&rows).Error; err != nil {
			log.Printf("expandApplyIDsByCanonicalBrand: saas_brand_id expansion failed: %v", err)
		} else {
			addCandidate(rows)
		}
	}
	if len(normalizedNames) > 0 {
		var rows []pRow
		if err := tx.Table("products").
			Select("id::text AS id, name, size, saas_brand_id::text AS saas_brand_id").
			Where("tenant_id = ? AND LOWER(TRIM(name)) IN ? AND deleted_at IS NULL", tenantID, normalizedNames).
			Scan(&rows).Error; err != nil {
			log.Printf("expandApplyIDsByCanonicalBrand: name-fallback expansion failed: %v", err)
		} else {
			addCandidate(rows)
		}
	}
	return added
}

// clearStaleStockOutsideSetup zeros out stock for products at the same
// (shop, size, beer/non-beer bucket) that are NOT in the setup's apply set.
// This makes a stock-setup approval a complete snapshot for that scope:
// items absent from the register are treated as "no longer in stock" and
// cleared. Reserved quantities are preserved (clamped to reserved). Stocks
// already at or below the reserved level are skipped.
//
// bucket = "beer" | "non_beer" | "" (empty disables the beer/non-beer filter
// and clears across both buckets at that size — used as a fallback when the
// caller can't determine the bucket).
func (s *SmartStockSetupService) clearStaleStockOutsideSetup(
	tx *gorm.DB,
	tenantID, shopID uuid.UUID,
	recordID uuid.UUID,
	sizeText string,
	bucket string,
	applyProductIDs map[string]bool,
	movementRef string,
	createdByID uuid.UUID,
) (int, error) {
	if sizeText == "" {
		return 0, nil
	}
	sizeML := normalizeSizeText(sizeText)
	if sizeML == 0 {
		return 0, nil
	}
	sizeStr := fmt.Sprintf("%dML", sizeML)

	beerCatIDs := map[string]bool{}
	if bucket != "" {
		var ids []string
		if err := tx.Table("categories").
			Where("tenant_id = ? AND LOWER(name) = ?", tenantID, "beer").
			Pluck("id::text", &ids).Error; err != nil {
			log.Printf("clearStaleStockOutsideSetup: beer-category lookup failed: %v (skipping bucket filter)", err)
		} else {
			for _, id := range ids {
				beerCatIDs[id] = true
			}
		}
	}
	wantBeer := strings.EqualFold(bucket, "beer")

	type staleStock struct {
		StockID     string `gorm:"column:stock_id"`
		ProductID   string `gorm:"column:product_id"`
		CategoryID  string `gorm:"column:category_id"`
		ProductName string `gorm:"column:name"`
		ProductSize string `gorm:"column:size"`
		Quantity    int    `gorm:"column:quantity"`
		Reserved    int    `gorm:"column:reserved_quantity"`
	}
	var rows []staleStock
	// Load all stocks at the shop with quantity > 0; filter by normalized size
	// in Go because product.size may be stored in many forms ("180ML",
	// "180ml (Quarter)", "180ml") and a SQL-side equality misses variants.
	if err := tx.Raw(`
		SELECT s.id::text AS stock_id,
		       s.product_id::text AS product_id,
		       p.category_id::text AS category_id,
		       p.name AS name,
		       p.size AS size,
		       s.quantity AS quantity,
		       s.reserved_quantity AS reserved_quantity
		FROM stocks s
		JOIN products p ON p.id = s.product_id
		WHERE s.shop_id = ? AND s.tenant_id = ? AND s.deleted_at IS NULL
		  AND p.deleted_at IS NULL AND s.quantity > 0
	`, shopID, tenantID).Scan(&rows).Error; err != nil {
		return 0, fmt.Errorf("clearStaleStockOutsideSetup: query stale stocks failed: %w", err)
	}

	cleared := 0
	skippedPending := 0
	for _, r := range rows {
		if applyProductIDs[r.ProductID] {
			continue
		}
		if normalizeSizeText(r.ProductSize) != sizeML {
			continue
		}
		if len(beerCatIDs) > 0 {
			pIsBeer := beerCatIDs[r.CategoryID]
			if pIsBeer != wantBeer {
				continue
			}
		}
		newQty := 0
		if r.Reserved > 0 {
			newQty = r.Reserved
		}
		if newQty >= r.Quantity {
			continue
		}

		// v1.0.218 — pending-sale/purchase guard. Mirror v1.0.132 reject-baseline
		// pattern (project-liquorpro-v132-reject-baseline-fix.md): never zero
		// stock for a product that a pending DailySalesRecord (or active
		// StockPurchase) still references — the operator would be locked out
		// of approving that sale. Belt-and-suspenders for cases where
		// expandApplyIDsByCanonicalBrand missed a sibling (NULL saas_brand_id +
		// name mismatch).
		// v1.0.280 — ROOT CAUSE of "commit unexpectedly resulted in rollback"
		// on ApproveStockSetup. Two flat bugs + the systemic class:
		//   (1) wrong table: daily_sales_record_items does not exist → it is
		//       daily_sales_items (42P01).
		//   (2) wrong join column: the FK is dsi.daily_sales_record_id, not
		//       dsi.record_id.
		//   (3) THE CLASS: these checks are BEST-EFFORT ("never block clears on
		//       a query error") — but a failed statement poisons the WHOLE
		//       Postgres tx, so the old bare `if err != nil { log }` was a lie:
		//       it aborted the entire approve tx and Commit() then returned
		//       "commit unexpectedly resulted in rollback" (HTTP 400, nothing
		//       saved). Wrap both checks in ONE savepoint so a failure is
		//       genuinely non-fatal and the approve tx stays clean — same
		//       discipline as the v1.0.277 apply-path guards.
		var pendingSale, pendingPurchase int64
		spPend := "sp_pendchk_" + strings.ReplaceAll(uuid.New().String(), "-", "")[:12]
		if spe := tx.SavePoint(spPend).Error; spe == nil {
			pendErr := tx.Table("daily_sales_items dsi").
				Joins("JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id").
				Where("dsr.shop_id = ? AND dsr.tenant_id = ? AND dsr.status = ? AND dsi.product_id = ?",
					shopID, tenantID, "pending", r.ProductID).
				Count(&pendingSale).Error
			if pendErr == nil {
				pendErr = tx.Table("stock_purchases").
					Where("shop_id = ? AND tenant_id = ? AND product_id = ? AND status IN ?",
						shopID, tenantID, r.ProductID, []string{"pending", "partial_received"}).
					Count(&pendingPurchase).Error
			}
			if pendErr != nil {
				tx.RollbackTo(spPend)
				pendingSale, pendingPurchase = 0, 0
				log.Printf("clearStaleStockOutsideSetup: pending checks skipped for product %s (non-fatal, tx kept clean): %v", r.ProductID, pendErr)
			}
		}
		if pendingSale > 0 || pendingPurchase > 0 {
			stockUUID, parseErr := uuid.Parse(r.StockID)
			if parseErr == nil {
				skShopRef := shopID
				prodUUID, prodErr := uuid.Parse(r.ProductID)
				skipHist := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stockUUID,
					ShopID:           &skShopRef,
					MovementType:     "opening_stock_setup_clear_skipped",
					Quantity:         0,
					PreviousQuantity: r.Quantity,
					NewQuantity:      r.Quantity,
					Reference:        movementRef,
					Notes: fmt.Sprintf("Skipped clear — pending sale=%d purchase=%d for product '%s' (shop=%s, size=%s, bucket=%s)",
						pendingSale, pendingPurchase, r.ProductName, shopID, sizeStr, bucket),
					CreatedByID: createdByID,
				}
				if prodErr == nil {
					skipHist.ProductID = &prodUUID
				}
				_ = tx.Create(&skipHist).Error
			}
			skippedPending++
			log.Printf("clearStaleStockOutsideSetup: skipped clear for product %s ('%s') — pending sale=%d purchase=%d (qty preserved at %d)",
				r.ProductID, r.ProductName, pendingSale, pendingPurchase, r.Quantity)
			continue
		}

		stockUUID, parseErr := uuid.Parse(r.StockID)
		if parseErr != nil {
			continue
		}
		var stock models.Stock
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ? AND tenant_id = ?", stockUUID, tenantID).
			First(&stock).Error; err != nil {
			log.Printf("clearStaleStockOutsideSetup: failed to lock stock %s: %v", r.StockID, err)
			continue
		}
		previousQuantity := stock.Quantity
		stock.Quantity = newQty
		if err := tx.Save(&stock).Error; err != nil {
			log.Printf("clearStaleStockOutsideSetup: failed to update stock %s: %v", r.StockID, err)
			continue
		}

		clShopRef, clProdRef := stock.ShopID, stock.ProductID
		hist := models.StockHistory{
			TenantModel:      models.TenantModel{TenantID: &tenantID},
			StockID:          stock.ID,
			ShopID:           &clShopRef,
			ProductID:        &clProdRef,
			MovementType:     "opening_stock_setup_clear",
			Quantity:         stock.Quantity - previousQuantity,
			PreviousQuantity: previousQuantity,
			NewQuantity:      stock.Quantity,
			Reference:        movementRef,
			Notes:            fmt.Sprintf("Cleared stale stock — product '%s' not in setup (shop=%s, size=%s, bucket=%s)", r.ProductName, shopID, sizeStr, bucket),
			CreatedByID:      createdByID,
		}
		_ = tx.Create(&hist).Error

		// 2026-05-19 — REVERSIBLE SNAPSHOT-REPLACE. The stock was zeroed
		// above (legacy behaviour). When the clear is COMPLETE (newQty == 0
		// — nothing reserved/pending remains) ALSO soft-deactivate the
		// product so the just-approved register is the WHOLE truth for this
		// (shop,size,bucket): stale / duplicate / phantom rows disappear
		// from inventory instead of merely showing 0. Every removal is
		// persisted to stock_setup_replace_snapshots FIRST, so the entire
		// replace is reversible (RestoreStockSetupReplace) if the approved
		// register turns out to have silently dropped a real item — that is
		// what makes this destructive-looking replace safe: nothing is ever
		// hard-deleted. Kill-switch STOCK_SETUP_REPLACE_DEACTIVATE=0
		// instantly reverts to zero-only legacy behaviour with no redeploy.
		if newQty == 0 && recordID != uuid.Nil &&
			os.Getenv("STOCK_SETUP_REPLACE_DEACTIVATE") != "0" {
			if prodUUID, puErr := uuid.Parse(r.ProductID); puErr == nil {
				var prior struct {
					DeletedAt *time.Time `gorm:"column:deleted_at"`
					IsActive  bool       `gorm:"column:is_active"`
				}
				_ = tx.Table("products").
					Select("deleted_at, is_active").
					Where("id = ? AND tenant_id = ?", prodUUID, tenantID).
					Scan(&prior).Error
				// Only deactivate a row that is still live. An already
				// soft-deleted product needs no change AND must not have its
				// original deleted_at overwritten — otherwise restore would
				// resurrect a row the operator had themselves removed.
				if prior.DeletedAt == nil {
					// v1.0.311 — CROSS-SHOP GUARD. After v1.0.297's cross-
					// shop dedup pass, a single product row can be referenced
					// by stocks rows at MULTIPLE shops in the same tenant.
					// (Real incident 2026-05-23: chhotu had 45 units of
					// Master Blenders 36801036 at shop c5cf581d while the
					// product was OWNED BY shop 36d55d78 / FM Tower.) When
					// FM Tower's approve fired this snapshot-replace, the
					// product was soft-deleted — and chhotu's 45 units
					// silently disappeared from his inventory view because
					// GORM auto-filters deleted_at IS NULL on every JOIN.
					// Operator directive 2026-05-24: snapshot-replace must
					// be SHOP-ONLY and never disturb a sibling shop's data.
					// Guard: skip the soft-delete (still zero THIS shop's
					// stock + log) when ANY sibling shop in the same tenant
					// has live stocks > 0 referencing this product. Snapshot
					// is also skipped because there's nothing to "restore"
					// — the product never got hidden.
					var siblingStock int64
					_ = tx.Table("stocks").
						Where("product_id = ? AND tenant_id = ? AND shop_id != ? AND deleted_at IS NULL AND quantity > 0",
							prodUUID, tenantID, shopID).
						Select("COALESCE(SUM(quantity), 0)").Row().Scan(&siblingStock)
					if siblingStock > 0 {
						log.Printf("clearStaleStockOutsideSetup: SKIPPED soft-delete for product %s ('%s') — sibling shops hold %d live units (shop-only directive, v1.0.311)",
							r.ProductID, r.ProductName, siblingStock)
						cleared++
						continue
					}

					// Snapshot-write + soft-delete wrapped in ONE savepoint.
					// On ANY failure roll back BOTH: the product stays live
					// (stock already cleared to 0 — exactly today's safe
					// behaviour). We NEVER hide a product without first
					// persisting a restorable snapshot, and a failure here
					// can never poison the approve tx (the documented
					// unguarded-write-in-tx incident class).
					spSnap := "sp_ssrs_" + strings.ReplaceAll(uuid.New().String(), "-", "")[:12]
					if spe := tx.SavePoint(spSnap).Error; spe == nil {
						stockRef := stock.ID
						snap := models.StockSetupReplaceSnapshot{
							TenantID:             &tenantID,
							StockSetupRecordID:   recordID,
							ProductID:            prodUUID,
							ShopID:               shopID,
							StockID:              &stockRef,
							PrevStockQuantity:    previousQuantity,
							PrevProductDeletedAt: nil, // prior.DeletedAt == nil → was live
							PrevIsActive:         prior.IsActive,
							Action:               "deactivated",
							CreatedByID:          &createdByID,
							Notes: fmt.Sprintf("Snapshot-replace: product '%s' not in approved setup (shop=%s, size=%s, bucket=%s)",
								r.ProductName, shopID, sizeStr, bucket),
						}
						snapErr := tx.Create(&snap).Error
						if snapErr == nil {
							snapErr = tx.Table("products").
								Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", prodUUID, tenantID).
								Updates(map[string]interface{}{
									"deleted_at": time.Now(),
									"updated_at": time.Now(),
								}).Error
						}
						if snapErr != nil {
							tx.RollbackTo(spSnap)
							log.Printf("clearStaleStockOutsideSetup: snapshot/deactivate skipped for product %s (non-fatal, stays live + zeroed): %v", r.ProductID, snapErr)
						} else {
							log.Printf("clearStaleStockOutsideSetup: REVERSIBLE-DEACTIVATED product %s ('%s') — snapshot saved (record %s, prev_qty=%d)",
								r.ProductID, r.ProductName, recordID, previousQuantity)
						}
					}
				}
			}
		}

		cleared++
		log.Printf("clearStaleStockOutsideSetup: cleared product %s ('%s') %d → %d (reserved=%d, size=%s, bucket=%s)",
			r.ProductID, r.ProductName, previousQuantity, stock.Quantity, r.Reserved, sizeStr, bucket)
	}
	if skippedPending > 0 {
		log.Printf("clearStaleStockOutsideSetup: skipped %d clears (pending sale/purchase guard) at shop=%s size=%s bucket=%s",
			skippedPending, shopID, sizeStr, bucket)
	}
	return cleared, nil
}

// ApproveStockSetup approves a pending stock setup record and applies stock.
// approverRole guards against executive/salesman approving their own (or anyone's)
// pending records — only admin and manager may approve.
func (s *SmartStockSetupService) ApproveStockSetup(ctx context.Context, recordID, tenantID, approvedByID uuid.UUID, approverRole string) (*StockSetupRecordResponse, error) {
	if approverRole != models.RoleAdmin && approverRole != models.RoleManager {
		return nil, fmt.Errorf("only admin or manager can approve stock setup records")
	}
	var record models.StockSetupRecord
	err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
		Preload("Items", orderItemsByRegisterRow).
		First(&record).Error
	if err != nil {
		return nil, fmt.Errorf("stock setup record not found: %w", err)
	}

	if record.Status != "pending" {
		return nil, fmt.Errorf("record is already %s", record.Status)
	}

	// v1.0.290 — track rows the always-on anti-phantom gate drops at approve
	// (deferred-create resolver). Slice lives OUTSIDE the tx so a tx
	// rollback/retry doesn't double-count or lose entries; populated only
	// from the gate site (~line 7562), surfaced on the final response so
	// the approving manager sees "5 rows skipped at approve: …" instead of
	// silently getting N-5 items applied with no explanation.
	var rejectedAtApprove []UnverifiedRow

	// v1.0.301 — DUP-PRODUCT-ID GUARD. If two or more items in the same
	// record point to the same product, the per-item delta math stacks:
	// item A applies (qtyA - prevA), item B applies (qtyB - prevB) on top,
	// and unless qtyA == qtyB they partially cancel. Real incident
	// 2026-05-23 record bbf99742 (FM Tower 180ml): AI matched two
	// "8PM Gold Scotch Tetra" rows (₹130 row 1 qty=94 + ₹140 row 4 qty=26)
	// to the same product → stock ended at 65 instead of 94 OR 26 OR 120.
	//
	// Root cause is upstream (matcher ignores AI rate); this is the
	// approve-time backstop so silent data loss can't happen again even
	// if the matcher mis-matches. We refuse to commit and tell the
	// approver exactly which rows collide so they can swap one in the
	// review screen and re-approve.
	//
	// Only checks items with a resolved product_id (non-nil, non-zero).
	// Deferred-create items (product_id == uuid.Nil) are exempt because
	// the resolver below creates a fresh product per row.
	zeroUUID := uuid.UUID{}
	type dupGroup struct {
		Rows        []int
		ProductName string
	}
	dupByProduct := map[uuid.UUID]*dupGroup{}
	for _, item := range record.Items {
		if item.ProductID == uuid.Nil || item.ProductID == zeroUUID {
			continue
		}
		if dupByProduct[item.ProductID] == nil {
			dupByProduct[item.ProductID] = &dupGroup{}
		}
		// Use ai_row_number from raw extraction if present; fall back to
		// item index order (best-effort — the goal is to give the operator
		// a stable identifier they can recognise in the review screen).
		row := 0
		if item.RawAIExtraction != nil {
			var rb struct {
				AIRowNumber int `json:"ai_row_number"`
			}
			_ = json.Unmarshal(item.RawAIExtraction, &rb)
			row = rb.AIRowNumber
		}
		dupByProduct[item.ProductID].Rows = append(dupByProduct[item.ProductID].Rows, row)
	}
	var collisions []string
	for pid, g := range dupByProduct {
		if len(g.Rows) < 2 {
			continue
		}
		// Look up product name for a friendly message. Best-effort; if
		// the lookup fails we still surface the row numbers + UUID.
		var p models.Product
		name := pid.String()
		if err := s.db.Select("name").Where("id = ?", pid).First(&p).Error; err == nil && p.Name != "" {
			name = p.Name
		}
		collisions = append(collisions,
			fmt.Sprintf("rows %v all match product %q — please reassign all but one in the review screen before re-approving", g.Rows, name))
	}
	if len(collisions) > 0 {
		return nil, fmt.Errorf("approve blocked: %d duplicate-product collision(s) detected — %s",
			len(collisions), strings.Join(collisions, "; "))
	}

	// Apply stock in a transaction
	err = s.db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		record.Status = "approved"
		record.ApprovedAt = &now
		record.ApprovedByID = &approvedByID
		if err := tx.Save(&record).Error; err != nil {
			return err
		}

		// v1.0.256 — track per-item stock-write failures. Previously the
		// record was flipped to "approved" (saved above) and per-item
		// failures just log+continue → manager sees "approved" while some
		// products' stock was never written (salesman's opening stock
		// silently lost). Any failure now aborts the whole approve txn.
		stockFailures := 0

		// Apply stock for each item
		for idx := range record.Items {
			item := &record.Items[idx]

			// Unit 1 (2026-05-19) — DEFERRED-CREATE RESOLUTION. A pending
			// submit under STOCK_SETUP_DEFER_CREATE parked this row with the
			// zero-UUID sentinel instead of creating a product at submit. A
			// manager is now approving: create the product NOW, behind the
			// SAME anti-phantom gate as submit, before any stock is written.
			// All inputs survive on the item — RawAIExtraction (ai_brand /
			// ai_rate / picked_saas_* / edited_name / official_brand_name) +
			// the photo columns + record.Size/record.Category. If the gate
			// rejects it the row is skipped & reported (never a phantom, never
			// a silent drop); approval continues for the good rows. Robust to
			// the env being toggled off after parking — presence of the
			// zero-UUID sentinel alone drives this.
			if item.ProductID == uuid.Nil {
				var b struct {
					AIBrand                 string  `json:"ai_brand"`
					AIRate                  float64 `json:"ai_rate"`
					PickedSB                string  `json:"picked_saas_brand_id"`
					PickedSV                string  `json:"picked_saas_variant_id"`
					EditedName              string  `json:"edited_name"`
					OfficialName            string  `json:"official_brand_name"`
					OperatorVouchedAtSubmit bool    `json:"operator_vouched_at_submit"` // v1.0.291
				}
				if item.RawAIExtraction != nil {
					_ = json.Unmarshal(item.RawAIExtraction, &b)
				}
				displayBrand := firstNonEmptyStr(
					firstNonEmptyStr(strings.TrimSpace(b.EditedName), strings.TrimSpace(b.OfficialName)),
					strings.TrimSpace(b.AIBrand))
				sizeStr := record.Size
				sizeML := normalizeSizeText(sizeStr)
				rate := b.AIRate
				if rate <= 0 {
					rate = item.Rate
				}
				hasPhoto := item.FrontImageURL != "" || item.BackImageURL != "" ||
					item.VerifiedViaImageFront || item.VerifiedViaImageBack ||
					item.VerifiedViaImage || item.VerifiedImageURL != ""

				// Master resolution — trust an operator pick verbatim; else
				// fuzzy+rate resolve with the SAME WYSIWYG distinctive-token
				// guard as Pass 1 (never bind a garbled row to a rate twin).
				var masterBrandIDPtr, masterVariantIDPtr *uuid.UUID
				if b.PickedSB != "" {
					if id, e := uuid.Parse(b.PickedSB); e == nil {
						masterBrandIDPtr = &id
					}
					if b.PickedSV != "" {
						if id, e := uuid.Parse(b.PickedSV); e == nil {
							masterVariantIDPtr = &id
						}
					}
				} else if displayBrand != "" {
					tState := s.getTenantState(tenantID)
					mBrands := s.loadMasterBrands(sizeML, tState)
					if mb := s.findMasterBrand(displayBrand, sizeML, rate, mBrands); mb != nil {
						if sharesDistinctiveToken(displayBrand, strings.TrimSpace(mb.DisplayName+" "+mb.BrandName)) {
							if id, e := uuid.Parse(mb.BrandID); e == nil {
								masterBrandIDPtr = &id
							}
							if mb.VariantID != "" {
								if id, e := uuid.Parse(mb.VariantID); e == nil {
									masterVariantIDPtr = &id
								}
							}
							if rate <= 1 && mb.MRP > 0 {
								rate = mb.MRP
							}
						}
					}
				}

				// 2026-05-22 — ALWAYS-ON anti-phantom gate at approve. The
				// env kill-switch SMART_STOCK_SETUP_REJECT_UNREADABLE that
				// covers the submit-time path is DELIBERATELY ignored here:
				// approve is the last line of defense before a phantom OCR
				// brand becomes a permanent catalog product. Record 310beab1
				// (5 garbled rows imjum / SM19Jum / M6002Jum / 100 Step /
				// Jamson + "VERY OLD VATTED OLD MONK" with no master link)
				// shipped while the env flag was silently set to 0. Even if
				// the flag flips off again, the gate still fires here:
				// unvouched (no master + not corrected + no photo + not
				// operator-authored + not operator-vouched-at-submit) deferred
				// rows are dropped at approve.
				//
				// v1.0.291 — read the operator_vouched_at_submit flag persisted
				// at submit time. If the operator saw this row on the review
				// screen and pressed Set Opening Stock, the row was vouched —
				// honor that decision instead of re-rejecting at approve.
				if shouldRejectUnreadableAutoCreate(masterBrandIDPtr != nil, item.UserCorrected, hasPhoto, b.OperatorVouchedAtSubmit,
					b.EditedName, displayBrand, b.OfficialName) {
					log.Printf("ApproveStockSetup: DEFERRED row '%s' REJECTED by always-on anti-phantom gate (no master, not corrected, no photo, not authored, not operator-vouched-at-submit) — product NOT created, row skipped", displayBrand)
					nm := displayBrand
					if nm == "" {
						nm = "(unnamed parked row)"
					}
					rejectedAtApprove = append(rejectedAtApprove, UnverifiedRow{
						BrandName: nm,
						Size:      record.Size,
						Reason:    "unverified_no_provenance_at_approve",
					})
					continue
				}
				if displayBrand == "" {
					log.Printf("ApproveStockSetup: DEFERRED row has no usable brand name (item %s) — skipped", item.ID)
					continue
				}

				catID, _ := s.resolveCategory(tx, tenantID, record.Category)
				if catID == uuid.Nil {
					catID, _ = s.resolveCategory(tx, tenantID, "spirits")
				}
				spDef := "sp_defcreate_" + strings.ReplaceAll(uuid.New().String(), "-", "")[:12]
				if spe := tx.SavePoint(spDef).Error; spe != nil {
					log.Printf("ApproveStockSetup: deferred-create savepoint failed for '%s': %v", displayBrand, spe)
					stockFailures++
					continue
				}
				brandRes, brandErr := s.findOrCreateBrand(tx, tenantID, displayBrand)
				if brandErr != nil {
					tx.RollbackTo(spDef)
					log.Printf("ApproveStockSetup: deferred-create brand resolve failed for '%s': %v", displayBrand, brandErr)
					stockFailures++
					continue
				}
				newPID, _, fcErr := s.findOrCreateProduct(tx, tenantID, &record.ShopID, brandRes.BrandID, brandRes.BrandName, catID, sizeStr, sizeML, rate, masterBrandIDPtr, masterVariantIDPtr, false)
				if fcErr != nil {
					tx.RollbackTo(spDef)
					log.Printf("ApproveStockSetup: deferred-create failed for '%s': %v", displayBrand, fcErr)
					stockFailures++
					continue
				}
				item.ProductID = newPID
				if upErr := tx.Model(&models.StockSetupItem{}).
					Where("id = ?", item.ID).
					Update("product_id", newPID).Error; upErr != nil {
					log.Printf("ApproveStockSetup: deferred-create product_id persist failed for item %s: %v", item.ID, upErr)
				}
				// Snapshot-set: previous = the product's CURRENT stock now (it
				// may have been freshly created at 0, or a lookup inside
				// findOrCreateProduct may have reused an existing row). The
				// delta logic below then drives stock TO item.Quantity exactly.
				var curStk models.Stock
				if e := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", record.ShopID, newPID, tenantID).First(&curStk).Error; e == nil {
					item.PreviousDBStock = curStk.Quantity
				} else {
					item.PreviousDBStock = 0
				}
				log.Printf("ApproveStockSetup: DEFERRED-CREATED product %s for '%s - %s' at approval (master=%v, prev_stock=%d)",
					newPID, displayBrand, sizeStr, masterBrandIDPtr != nil, item.PreviousDBStock)
			}

			// Edit-name re-resolve at approve time (v1.0.112). For records that were
			// SUBMITTED on a pre-v1.0.112 build, the apply-time re-resolve never
			// ran, so item.ProductID may still point at the wrong tenant product
			// (e.g. BACARDI when the user edited to XCLAMATION). Read the audit
			// blob, fuzzy-match the edited_name, and if it resolves to a different
			// master, re-route the item before we write stock. Without this, the
			// "edited but inventory still shows old info" bug class persists for
			// every still-pending record submitted before today.
			//
			// ANTI-PHANTOM INVARIANT (v1.0.283 audit): this is the ONLY other
			// findOrCreateBrand/findOrCreateProduct call site outside the
			// ApplyStockSetup deferred-create. It is NOT a phantom vector and
			// deliberately carries NO anti-phantom gate — it fires only when the
			// operator EDITED the name AND that edit FUZZY-RESOLVES TO A REAL
			// CATALOG MASTER (mb != nil below) AND a manager is actively
			// approving: the created product is operator-authored + catalog-
			// linked + approver-vouched, the exact opposite of the unvouched
			// "Chonploopr / Vin Green Label" class. If mb == nil the block is
			// skipped and nothing is created. The unvouched-create class is
			// fully contained by the single ApplyStockSetup gate
			// (shouldRejectUnreadableAutoCreate), which runs before any item
			// gets a stock_setup_item — so by approve time every item has
			// already passed it. DO NOT add an unguarded create here.
			if item.RawAIExtraction != nil {
				var blob struct {
					EditedName  string `json:"edited_name"`
					OCRText     string `json:"ocr_text"`
					PickedSB    string `json:"picked_saas_brand_id"`
				}
				_ = json.Unmarshal(item.RawAIExtraction, &blob)
				edited := strings.TrimSpace(blob.EditedName)
				if edited != "" && blob.PickedSB == "" {
					var current struct {
						Name        string
						SaasBrandID *uuid.UUID
						Size        string
					}
					if cErr := tx.Table("products").
						Select("name, saas_brand_id, size").
						Where("id = ? AND tenant_id = ?", item.ProductID, tenantID).
						Scan(&current).Error; cErr == nil && current.Name != "" {
						if !strings.EqualFold(strings.TrimSpace(current.Name), edited) {
							sizeML := normalizeSizeText(current.Size)
							if sizeML == 0 {
								sizeML = normalizeSizeText(record.Size)
							}
							rateForLookup := item.Rate
							if rateForLookup <= 0 {
								rateForLookup = float64(item.OpeningStock) // best-effort; rate is the typical signal
							}
							tState := s.getTenantState(tenantID)
							mBrands := s.loadMasterBrands(sizeML, tState)
							if mb := s.findMasterBrand(edited, sizeML, item.Rate, mBrands); mb != nil {
								currentSB := ""
								if current.SaasBrandID != nil {
									currentSB = current.SaasBrandID.String()
								}
								if !strings.EqualFold(mb.BrandID, currentSB) {
									// Resolve / create the right tenant product under the picked master.
									brandRes, brandErr := s.findOrCreateBrand(tx, tenantID, edited)
									if brandErr == nil {
										catID, _ := s.resolveCategory(tx, tenantID, record.Category)
										if catID == uuid.Nil {
											catID, _ = s.resolveCategory(tx, tenantID, "spirits")
										}
										sizeStr := current.Size
										if sizeStr == "" {
											sizeStr = record.Size
										}
										masterBrandIDPtr := (*uuid.UUID)(nil)
										masterVariantIDPtr := (*uuid.UUID)(nil)
										if mbID, perr := uuid.Parse(mb.BrandID); perr == nil {
											masterBrandIDPtr = &mbID
										}
										if mb.VariantID != "" {
											if vID, perr := uuid.Parse(mb.VariantID); perr == nil {
												masterVariantIDPtr = &vID
											}
										}
										if newPID, _, fcErr := s.findOrCreateProduct(tx, tenantID, &record.ShopID, brandRes.BrandID, brandRes.BrandName, catID, sizeStr, sizeML, item.Rate, masterBrandIDPtr, masterVariantIDPtr, false); fcErr == nil {
											log.Printf("ApproveStockSetup: edit-name re-resolve — item %s '%s' → '%s' (was product %s, now %s, master %s)",
												item.ID, current.Name, edited, item.ProductID, newPID, mb.BrandID)
											item.ProductID = newPID
											// Persist the corrected product_id back to stock_setup_items so
											// future re-runs/audits see the right linkage.
											tx.Model(&models.StockSetupItem{}).Where("id = ?", item.ID).Update("product_id", newPID)
											// Reset previous DB stock to 0 since we are writing to a different
											// product than the one the snapshot was taken on.
											item.PreviousDBStock = 0
										}
									}
								}
							}
						}
					}
				}
			}

			// Per-shop ownership self-heal (v1.0.397). Heal any item still pointing
			// at ANOTHER shop's product — legacy pre-v397 records, or links that
			// slipped past the apply-time guard — BEFORE we touch stock, so
			// trg_block_crossshop_stock never fires and the approve tx is never
			// poisoned (the "N items failed to write stock — nothing applied" bug:
			// one cross-shop item's P0001 used to cascade 25P02 onto every sibling).
			// Resolve-or-create a shop-owned equivalent and repoint the item.
			// Wrapped in its own savepoint so a heal failure isolates to this item.
			if item.ProductID != uuid.Nil {
				spXshop := fmt.Sprintf("sp_xshop_%d", idx)
				if spe := tx.SavePoint(spXshop).Error; spe != nil {
					log.Printf("ApproveStockSetup: cross-shop savepoint failed for item %s: %v", item.ID, spe)
					stockFailures++
					continue
				}
				newPID, changed, dErr := s.demoteCrossShopProduct(tx, tenantID, record.ShopID, item.ProductID.String())
				if dErr != nil {
					tx.RollbackTo(spXshop)
					log.Printf("ApproveStockSetup: cross-shop self-heal failed for item %s (product %s): %v", item.ID, item.ProductID, dErr)
					stockFailures++
					continue
				}
				if changed {
					if np, perr := uuid.Parse(newPID); perr == nil {
						tx.Model(&models.StockSetupItem{}).Where("id = ?", item.ID).Update("product_id", np)
						log.Printf("ApproveStockSetup: cross-shop self-heal — item %s product %s → shop-owned %s", item.ID, item.ProductID, np)
						item.ProductID = np
						item.PreviousDBStock = 0 // new product → snapshot baseline is 0
					}
				}
			}

			// v1.0.295 — Unscoped() so we find any soft-deleted row and revive
			// it instead of creating a duplicate (tenant_id, shop_id, product_id)
			// pair. See ApplyStockSetup site above for full rationale.
			// v1.0.297 — prefer LIVE row when both live + soft-deleted coexist
			// (chhotu's 750ml approve hit this — see ApplyStockSetup comment).
			var stock models.Stock
			stockErr := tx.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?", record.ShopID, item.ProductID, tenantID).
				Order("deleted_at NULLS FIRST, id ASC").
				First(&stock).Error

			if stockErr != nil {
				if stockErr == gorm.ErrRecordNotFound {
					stock = models.Stock{
						TenantModel:   models.TenantModel{TenantID: &tenantID},
						ShopID:        record.ShopID,
						ProductID:     item.ProductID,
						Quantity:      0,
						CostingMethod: "fifo",
					}
					// v1.0.397 — savepoint the bare create. Pre-fix this was the ONE
					// stock write in the approve loop NOT wrapped (the v1.0.329
					// savepoint only guarded the Save/update path below), so a
					// constraint rejection here poisoned the whole tx and took every
					// sibling item down with it. RollbackTo keeps the failure local.
					spCreate := fmt.Sprintf("sp_approve_create_%d", idx)
					if spe := tx.SavePoint(spCreate).Error; spe != nil {
						log.Printf("ApproveStockSetup: create-savepoint failed for product %s: %v", item.ProductID, spe)
						stockFailures++
						continue
					}
					if createErr := tx.Create(&stock).Error; createErr != nil {
						tx.RollbackTo(spCreate)
						log.Printf("ApproveStockSetup: failed to create stock for product %s: %v", item.ProductID, createErr)
						stockFailures++
						continue
					}
				} else {
					log.Printf("ApproveStockSetup: failed to query stock for product %s: %v", item.ProductID, stockErr)
					stockFailures++
					continue
				}
			} else if stock.DeletedAt.Valid {
				stock.DeletedAt = gorm.DeletedAt{}
			}

			// Delta-based application: avoids overwriting sales that occurred between submission and approval
			delta := item.Quantity - item.PreviousDBStock
			previousQuantity := stock.Quantity
			stock.Quantity = stock.Quantity + delta
			if stock.Quantity < 0 {
				log.Printf("ApproveStockSetup: delta application would go negative for product %s (prev=%d, delta=%d), clamping to 0",
					item.ProductID, previousQuantity, delta)
				stock.Quantity = 0
			}
			// v1.0.329 — wrap the stock write + product edits + audit row for THIS
			// item in a savepoint so they commit (or roll back) as a unit. Pre-fix
			// the stock Save below committed even when the audit Create at the end
			// silently failed, leaving stocks.quantity changed with NO stock_history
			// row — the un-laddered drift the nightly audit_heal_v1 sweep kept
			// papering over (root cause of FM Tower 8d20df01 going 94→26).
			spStock := fmt.Sprintf("sp_approve_stock_%d", idx)
			if spErr := tx.SavePoint(spStock).Error; spErr != nil {
				log.Printf("ApproveStockSetup: savepoint failed for product %s (tx unrecoverable): %v", item.ProductID, spErr)
				stockFailures++
				continue
			}

			if saveErr := tx.Unscoped().Save(&stock).Error; saveErr != nil {
				log.Printf("ApproveStockSetup: failed to update stock for product %s: %v", item.ProductID, saveErr)
				tx.RollbackTo(spStock)
				stockFailures++
				continue
			}

			log.Printf("ApproveStockSetup: delta application for product %s: prev_db_stock=%d, setup_qty=%d, delta=%d, stock %d → %d",
				item.ProductID, item.PreviousDBStock, item.Quantity, delta, previousQuantity, stock.Quantity)

			// Persist user MRP / name edits to the product on approve (v1.0.113).
			// Without this, pending records that came through with a user-edited
			// MRP would silently drop the edit at approve time — only stock got
			// applied, the product kept its old price. Mirror of ApplyStockSetup
			// behavior at line 4271-4297 so submit-and-approve has the same
			// outcome as direct apply.
			if item.Rate > 1 || item.RawAIExtraction != nil {
				productUpdates := map[string]interface{}{}
				if item.Rate > 1 {
					// v1.0.123: stamp MRP audit on Approve path too. The fields
					// flow into the same products columns Smart Sale + Apply
					// write, so the banner sources are unified.
					var current models.Product
					if cErr := tx.Select("mrp").Where("id = ? AND tenant_id = ?", item.ProductID, tenantID).First(&current).Error; cErr == nil {
						if absFloatStockSetup(current.MRP-item.Rate) >= 0.5 {
							actorName := resolveActorNameStockSetup(tx, approvedByID)
							productUpdates["mrp"] = item.Rate
							productUpdates["selling_price"] = item.Rate
							productUpdates["last_mrp_change_at"] = time.Now()
							productUpdates["last_mrp_change_previous"] = current.MRP
							productUpdates["last_mrp_change_by_id"] = approvedByID
							productUpdates["last_mrp_change_by_name"] = actorName
						} else {
							productUpdates["mrp"] = item.Rate
							productUpdates["selling_price"] = item.Rate
						}
					} else {
						productUpdates["mrp"] = item.Rate
						productUpdates["selling_price"] = item.Rate
					}
				}
				if item.RawAIExtraction != nil {
					var blob struct {
						EditedName string `json:"edited_name"`
					}
					_ = json.Unmarshal(item.RawAIExtraction, &blob)
					if edited := strings.TrimSpace(blob.EditedName); edited != "" {
						productUpdates["name"] = edited
					}
				}
				if len(productUpdates) > 0 {
					if updErr := tx.Model(&models.Product{}).
						Where("id = ? AND tenant_id = ?", item.ProductID, tenantID).
						Updates(productUpdates).Error; updErr != nil {
						log.Printf("ApproveStockSetup: failed to apply product updates for %s: %v", item.ProductID, updErr)
					} else if len(productUpdates) > 0 {
						log.Printf("ApproveStockSetup: applied product updates for %s: %v", item.ProductID, productUpdates)
					}
				}
			}

			// Stock history. Quantity is the ACTUAL applied delta (post-clamp)
			// so the v1.0.216 math-gate trigger (new = prev + qty) passes even
			// when the requested delta would have driven stock below zero and
			// got clamped at 0 above.
			apShopRef, apProdRef := stock.ShopID, stock.ProductID
			actualDelta := stock.Quantity - previousQuantity
			history := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: &tenantID},
				StockID:          stock.ID,
				ShopID:           &apShopRef,
				ProductID:        &apProdRef,
				MovementType:     "opening_stock_setup",
				Quantity:         actualDelta,
				PreviousQuantity: previousQuantity,
				NewQuantity:      stock.Quantity,
				Reference:        fmt.Sprintf("Smart Stock Setup (approved, requested_delta=%d, applied_delta=%d): record %s", delta, actualDelta, recordID),
				ReferenceID:      &recordID,
				Notes:            record.Notes,
				CreatedByID:      approvedByID,
			}
			if histErr := tx.Create(&history).Error; histErr != nil {
				// FAIL LOUD + atomic (v1.0.329). A failed audit insert must NOT
				// leave the stock change behind — roll this item's stock + product
				// writes back so stock and ledger stay in lockstep, then count it
				// as a failure (same fail-closed posture as the daily-sale paths).
				log.Printf("ApproveStockSetup: stock_history create FAILED for product %s — rolling back this item's stock change: %v", item.ProductID, histErr)
				tx.RollbackTo(spStock)
				stockFailures++
				continue
			}
		}

		// Snapshot semantics: any product at the same (shop, size, beer/non-beer
		// bucket) NOT in this record's items had its stock cleared. The setup is
		// the user's complete count for that scope; absent items mean "no longer
		// stocked", not "the OCR missed it". Reserved quantities are preserved.
		applyIDs := make(map[string]bool, len(record.Items))
		setupIDs := make([]string, 0, len(record.Items))
		for _, item := range record.Items {
			id := item.ProductID.String()
			applyIDs[id] = true
			setupIDs = append(setupIDs, id)
		}
		// v1.0.218 — expand the apply set by canonical brand (saas_brand_id, then
		// normalized name) so duplicate products rows representing the same SKU
		// at this size are also preserved. Prevents the FM Tower Mahua Khera
		// "Sale approve insufficient stock" bug class (Black & White Celebration
		// was wiped to 0 because the setup picked a different products row).
		if added := s.expandApplyIDsByCanonicalBrand(tx, tenantID, record.Size, applyIDs, setupIDs); added > 0 {
			log.Printf("ApproveStockSetup: canonical-brand expansion added %d sibling product_ids to apply set", added)
		}
		ref := fmt.Sprintf("Smart Stock Setup (approved): record %s — cleared not in setup", recordID)
		if cleared, clearErr := s.clearStaleStockOutsideSetup(tx, tenantID, record.ShopID, recordID, record.Size, record.Category, applyIDs, ref, approvedByID); clearErr != nil {
			log.Printf("ApproveStockSetup: clearStaleStockOutsideSetup error: %v", clearErr)
		} else if cleared > 0 {
			log.Printf("ApproveStockSetup: cleared %d stale stocks at shop %s (size=%s, category=%s)",
				cleared, record.ShopID, record.Size, record.Category)
		}

		// v1.0.256 — abort the whole approve if ANY item's stock write
		// failed: better the manager retries than the record shows
		// "approved" with some products' opening stock silently never written.
		if stockFailures > 0 {
			return fmt.Errorf("approve aborted: %d item(s) failed to write stock — nothing applied, please retry", stockFailures)
		}

		// v1.0.298 — auto-reject other pending records for the same
		// (shop, canonical-size) at this moment. Operator directive
		// 2026-05-23: approving record A invalidates concurrent pending
		// scans of the same shelf — they're stale snapshots. Stays inside
		// the approve tx so it rolls back together with the approve if
		// anything below fails. Size match uses the same normalization the
		// products unique index uses (lower + strip non-alphanumeric) so
		// "750ml (Full)" / "750ML" / "750ml" all match each other.
		// Approved/rejected records are never touched, only "pending".
		// New records submitted AFTER this commit are allowed (the rule
		// only fires once, here).
		var autoRejected int64
		autoRejectRes := tx.Model(&models.StockSetupRecord{}).
			Where("tenant_id = ? AND shop_id = ? AND status = ? AND id <> ? AND deleted_at IS NULL",
				tenantID, record.ShopID, "pending", record.ID).
			Where("regexp_replace(lower(COALESCE(size, '')), '[^0-9a-z]', '', 'g') = regexp_replace(lower(?), '[^0-9a-z]', '', 'g')",
				record.Size).
			Updates(map[string]interface{}{
				"status":     "rejected",
				"updated_at": time.Now(),
			})
		if autoRejectRes.Error != nil {
			return fmt.Errorf("auto-reject pending duplicates failed: %w", autoRejectRes.Error)
		}
		autoRejected = autoRejectRes.RowsAffected
		if autoRejected > 0 {
			log.Printf("ApproveStockSetup: auto-rejected %d other pending record(s) at same (shop=%s, size=%s)",
				autoRejected, record.ShopID, record.Size)
		}

		return nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to approve stock setup: %w", err)
	}

	// Clear stock cache
	s.stockService.ClearShopStockCache(ctx, tenantID, record.ShopID)

	// Capture (predicted, ground_truth) outcomes + learn aliases for the
	// executive→admin-approve flow. ApplyStockSetup runs these on auto-apply,
	// but the early-return for needsApproval means salesman/executive
	// submissions never reached the capture path. Replay them here from the
	// per-item raw_ai_extraction JSONB + the final approved record values so
	// the learning pipelines (alias, correction outcomes, few-shot,
	// distinguisher, calibration) ALL see executive-submitted corrections too.
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("ApproveStockSetup: post-approve learning panic recovered: %v", r)
			}
		}()
		var items []models.StockSetupItem
		if err := s.db.Preload("Product").Where("stock_setup_record_id = ?", recordID).Find(&items).Error; err != nil || len(items) == 0 {
			return
		}
		samples := make([]apiCorrectionInput, 0, len(items))
		for _, it := range items {
			var ai struct {
				AIBrand           string  `json:"ai_brand"`
				AIRate            float64 `json:"ai_rate"`
				AIQty             int     `json:"ai_qty"`
				AIConfidence      float64 `json:"ai_confidence"`
				OCRText           string  `json:"ocr_text"`
				WasCorrected      bool    `json:"was_corrected"`
				OriginalProductID string  `json:"original_product_id"`
			}
			if len(it.RawAIExtraction) > 0 {
				_ = json.Unmarshal(it.RawAIExtraction, &ai)
			}
			finalName := ""
			if it.Product != nil {
				finalName = it.Product.Name
			}
			samples = append(samples, apiCorrectionInput{
				AIBrand:             ai.AIBrand,
				AIRate:              ai.AIRate,
				AIQty:               ai.AIQty,
				AIConfidence:        ai.AIConfidence,
				AIMatchedProduct:    ai.OriginalProductID,
				UserBrand:           finalName,
				UserRate:            it.Rate,
				UserQty:             it.Quantity,
				UserMatchedProduct:  finalName,
				PayloadWasCorrected: it.UserCorrected || ai.WasCorrected,
			})

			// Alias learning. v1.0.160: shop-scoped so the lesson is anchored
			// to record.ShopID (the shop whose register this approval covered).
			// v1.0.175: relax the gate — pre-fix only fired on UserCorrected
			// approvals; now also fires when ocr_text differs from final
			// product name. Operator's first-time AI Stock Setup is the
			// moment when they confirm "this OCR text IS this product" via
			// the picker — every such approval is a TENANT shortcut we should
			// learn for future Smart Sale extractions, even if the operator
			// didn't explicitly correct (the AI may have already guessed it
			// right). Source tag distinguishes confirmed-without-edit from
			// edited so the alias graph remembers the lineage.
			if s.aliasService != nil && ai.OCRText != "" && finalName != "" &&
				!strings.EqualFold(strings.TrimSpace(ai.OCRText), strings.TrimSpace(finalName)) {
				pid := it.ProductID
				source := "stock_setup_approved"
				if it.UserCorrected || ai.WasCorrected {
					source = "user_correction"
				}
				s.aliasService.LearnAliasScoped(tenantID, record.ShopID, ai.OCRText, finalName, &pid, source)
				log.Printf("ApproveStockSetup: LEARNED %s '%s' -> '%s' (shop=%s)", source, ai.OCRText, finalName, record.ShopID)
				// v1.0.199 — DUAL-WRITE tenant-wide so a sibling shop benefits
				// from the same OCR→product mapping without re-teaching.
				// Lookup cascade keeps shop-scoped exact match as the priority
				// override path, so a shop can still differ.
				if record.ShopID != uuid.Nil {
					s.aliasService.LearnAliasScoped(tenantID, uuid.Nil, ai.OCRText, finalName, &pid, source+"_tenant")
					log.Printf("ApproveStockSetup: LEARNED tenant-wide '%s' -> '%s'", ai.OCRText, finalName)
				}
				if ai.OriginalProductID != "" && ai.OriginalProductID != pid.String() {
					if rejectedPID, perr := uuid.Parse(ai.OriginalProductID); perr == nil {
						s.aliasService.LearnNegativeAliasScoped(tenantID, record.ShopID, ai.OCRText, rejectedPID)
					}
				}
			}

			// v1.0.307 — also learn ai.AIBrand. Real-data audit on chhotu's
			// approved stock-setup history: 244 of 985 approved items have
			// EMPTY ocr_text but populated ai_brand (Textract pipeline doesn't
			// fill ocr_text the way the legacy pipeline does), so the OCRText
			// guard above silently skipped them. The ai_brand text is the AI's
			// model-side interpretation of the printed label — equally valid
			// as a Smart Sale lookup key. Source `stock_setup_ai_brand` keeps
			// the lineage separate from `stock_setup_approved` for telemetry;
			// confidence map (alias_service.go) ranks both at 90. Same dual-
			// write + negative-alias side-effects as the OCRText path.
			if s.aliasService != nil && ai.AIBrand != "" && finalName != "" &&
				!strings.EqualFold(strings.TrimSpace(ai.AIBrand), strings.TrimSpace(finalName)) &&
				!strings.EqualFold(strings.TrimSpace(ai.AIBrand), strings.TrimSpace(ai.OCRText)) {
				pid := it.ProductID
				source := "stock_setup_ai_brand"
				if it.UserCorrected || ai.WasCorrected {
					source = "user_correction"
				}
				s.aliasService.LearnAliasScoped(tenantID, record.ShopID, ai.AIBrand, finalName, &pid, source)
				log.Printf("ApproveStockSetup: LEARNED %s (ai_brand) '%s' -> '%s' (shop=%s)", source, ai.AIBrand, finalName, record.ShopID)
				if record.ShopID != uuid.Nil {
					s.aliasService.LearnAliasScoped(tenantID, uuid.Nil, ai.AIBrand, finalName, &pid, source+"_tenant")
				}
			}
		}
		s.LogCorrectionOutcomes(tenantID, recordID.String(), samples)
	}()

	// Phase 4 (WS-2.1): contribute this approved record to the per-shop
	// register-template fingerprint. After 5+ approvals at the same (shop,
	// size), the cached layout becomes a prompt hint on future extractions
	// for this shop. Async + idempotent + panic-safe in the helper.
	go func() {
		var sizeML int
		if record.Size != "" {
			sizeML = normalizeSizeText(record.Size)
		}
		// Reload items so we can pass the per-row data to the template.
		var items []models.StockSetupItem
		if err := s.db.Where("stock_setup_record_id = ?", recordID).Find(&items).Error; err == nil && sizeML > 0 {
			extracted := make([]SmartStockSetupExtractedItem, 0, len(items))
			for i := range items {
				it := &items[i]
				name := ""
				if it.Product != nil {
					name = it.Product.Name
				}
				extracted = append(extracted, SmartStockSetupExtractedItem{
					BrandName:          name,
					MatchedDisplayName: name,
					MatchConfidence:    func() float64 { if it.AIConfidence != nil { return *it.AIConfidence }; return 0.95 }(),
					Status:             "matched",
					Opening:            it.OpeningStock,
					Receipt:            it.Receipt,
					Sale:               it.Sale,
					Rate:               it.Rate,
					Amount:             it.Amount,
					RowNumber:          i + 1,
				})
			}
			tID := uuid.Nil
			if record.TenantID != nil {
				tID = *record.TenantID
			}
			s.RecordTemplateContribution(tID, record.ShopID, sizeML, recordID.String(), extracted)
		}
	}()

	// Reload and return — attach in-flight approve-time rejections so the
	// operator sees exactly which parked rows the anti-phantom gate dropped
	// (v1.0.290). GetStockSetupRecordByID reads from DB and has no knowledge
	// of these (they were never persisted as items), so we attach here.
	resp, gErr := s.GetStockSetupRecordByID(ctx, recordID, tenantID)
	if gErr != nil {
		return resp, gErr
	}
	if len(rejectedAtApprove) > 0 && resp != nil {
		resp.RejectedAtApproveRows = rejectedAtApprove
		resp.RejectedAtApproveCount = len(rejectedAtApprove)
		log.Printf("ApproveStockSetup: returning %d rejected-at-approve rows on response (record %s)", len(rejectedAtApprove), recordID)
	}
	return resp, nil
}

// ReapplyStockSetup re-applies an already-approved stock setup record's
// quantities to current stock. Useful when a shop wants to "reset to the
// approved baseline" after a few days of activity (typo'd sales, manual
// adjustments that need undoing, etc.). Gated to within 7 days of the
// original approval so older records can't be silently overwritten.
//
// Behaviour: SETS each item's stock to record.Items[i].Quantity (not delta-
// applied — the user's intent is "snap stock back to this approved
// snapshot"). Writes a stock_history audit row per change tagged
// "stock_setup_reapply". Updates record.notes with a "Reapplied at X by Y"
// breadcrumb. Status stays "approved" (idempotent — calling it twice is a
// no-op for stock that hasn't moved).
// --- Reversible snapshot-replace (2026-05-19) -----------------------------
//
// ApproveStockSetup → clearStaleStockOutsideSetup now soft-deactivates every
// in-scope product NOT in the approved register and records each removal in
// stock_setup_replace_snapshots. These two helpers make that safe:
//   PreviewStockSetupReplace  — read-only dry-run: exactly which products an
//                               approval WOULD deactivate (no mutation).
//   RestoreStockSetupReplace  — full reversal: un-deactivate the products and
//                               restore their prior stock, keyed to the
//                               record's snapshot rows.
// Nothing is ever hard-deleted, so a register that silently dropped a real
// item is always recoverable.

type StockSetupReplacePreviewItem struct {
	ProductID string `json:"product_id"`
	Name      string `json:"name"`
	Size      string `json:"size"`
	Quantity  int    `json:"quantity"`
}

type StockSetupReplacePreview struct {
	RecordID             string                         `json:"record_id"`
	Status               string                         `json:"status"`
	Scope                string                         `json:"scope"`
	ApprovedProductCount int                            `json:"approved_product_count"`
	WouldDeactivate      []StockSetupReplacePreviewItem `json:"would_deactivate"`
	WouldDeactivateCount int                            `json:"would_deactivate_count"`
	Message              string                         `json:"message"`
}

// PreviewStockSetupReplace returns, WITHOUT mutating anything, the exact set
// of in-scope products that approving this record would deactivate. Mirrors
// the scope filters of clearStaleStockOutsideSetup (same shop + normalized
// size + beer/non-beer bucket, minus the approved set and its canonical
// siblings) — deliberately a read-only re-implementation so the battle-tested
// clear path is not refactored.
func (s *SmartStockSetupService) PreviewStockSetupReplace(
	ctx context.Context, recordID, tenantID uuid.UUID,
) (*StockSetupReplacePreview, error) {
	var record models.StockSetupRecord
	if err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
		Preload("Items", orderItemsByRegisterRow).First(&record).Error; err != nil {
		return nil, fmt.Errorf("stock setup record not found: %w", err)
	}
	sizeML := normalizeSizeText(record.Size)
	out := &StockSetupReplacePreview{
		RecordID: recordID.String(),
		Status:   record.Status,
		Scope:    fmt.Sprintf("shop=%s size=%s(%dML) bucket=%q", record.ShopID.String()[:8], record.Size, sizeML, record.Category),
	}
	applyIDs := make(map[string]bool, len(record.Items))
	setupIDs := make([]string, 0, len(record.Items))
	for _, it := range record.Items {
		id := it.ProductID.String()
		applyIDs[id] = true
		setupIDs = append(setupIDs, id)
	}
	out.ApprovedProductCount = len(applyIDs)
	if sizeML == 0 {
		out.Message = "record size is not normalizable — approval would deactivate nothing"
		return out, nil
	}
	// Read-only canonical expansion (same keep-set widening as approve).
	_ = s.expandApplyIDsByCanonicalBrand(s.db.DB, tenantID, record.Size, applyIDs, setupIDs)

	beerCatIDs := map[string]bool{}
	if record.Category != "" {
		var ids []string
		_ = s.db.Table("categories").
			Where("tenant_id = ? AND LOWER(name) = ?", tenantID, "beer").
			Pluck("id::text", &ids).Error
		for _, id := range ids {
			beerCatIDs[id] = true
		}
	}
	wantBeer := strings.EqualFold(record.Category, "beer")

	type prow struct {
		ProductID  string `gorm:"column:product_id"`
		CategoryID string `gorm:"column:category_id"`
		Name       string `gorm:"column:name"`
		Size       string `gorm:"column:size"`
		Quantity   int    `gorm:"column:quantity"`
	}
	var rows []prow
	if err := s.db.Raw(`
		SELECT s.product_id::text AS product_id, p.category_id::text AS category_id,
		       p.name AS name, p.size AS size, s.quantity AS quantity
		FROM stocks s JOIN products p ON p.id = s.product_id
		WHERE s.shop_id = ? AND s.tenant_id = ? AND s.deleted_at IS NULL
		  AND p.deleted_at IS NULL AND s.quantity > 0
	`, record.ShopID, tenantID).Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("preview query failed: %w", err)
	}
	for _, r := range rows {
		if applyIDs[r.ProductID] {
			continue
		}
		if normalizeSizeText(r.Size) != sizeML {
			continue
		}
		if len(beerCatIDs) > 0 && beerCatIDs[r.CategoryID] != wantBeer {
			continue
		}
		out.WouldDeactivate = append(out.WouldDeactivate, StockSetupReplacePreviewItem{
			ProductID: r.ProductID, Name: r.Name, Size: r.Size, Quantity: r.Quantity,
		})
	}
	out.WouldDeactivateCount = len(out.WouldDeactivate)
	out.Message = fmt.Sprintf("approving this record would deactivate %d in-scope product(s) not in the approved set — fully reversible via restore-replace", out.WouldDeactivateCount)
	return out, nil
}

type StockSetupReplaceRestoreResult struct {
	RecordID         string `json:"record_id"`
	ProductsRestored int    `json:"products_restored"`
	StockRestored    int    `json:"stock_restored"`
	Skipped          int    `json:"skipped"`
	NothingToRestore bool   `json:"nothing_to_restore"`
	Message          string `json:"message"`
}

// RestoreStockSetupReplace fully reverses the snapshot-replace caused by one
// record's approval: every product it deactivated is un-deactivated, and any
// stock still sitting in the cleared (0) state is restored to its pre-replace
// quantity. Stock that has legitimately changed since (a newer setup / sale /
// purchase) is left as-is — only the product visibility + the still-zeroed
// rows are reverted, never clobbering newer truth. Admin/manager only.
func (s *SmartStockSetupService) RestoreStockSetupReplace(
	ctx context.Context, recordID, tenantID, byID uuid.UUID, role string,
) (*StockSetupReplaceRestoreResult, error) {
	if role != models.RoleAdmin && role != models.RoleManager {
		return nil, fmt.Errorf("only admin or manager can restore a stock setup replace")
	}
	var snaps []models.StockSetupReplaceSnapshot
	if err := s.db.Where("tenant_id = ? AND stock_setup_record_id = ? AND restored = ?",
		tenantID, recordID, false).Find(&snaps).Error; err != nil {
		return nil, fmt.Errorf("load replace snapshots: %w", err)
	}
	res := &StockSetupReplaceRestoreResult{RecordID: recordID.String()}
	if len(snaps) == 0 {
		res.NothingToRestore = true
		res.Message = "nothing to restore — this record has no un-restored replace snapshots"
		return res, nil
	}
	shopForCache := snaps[0].ShopID
	err := s.db.Transaction(func(tx *gorm.DB) error {
		now := time.Now()
		for i := range snaps {
			sn := &snaps[i]
			// 1) Un-deactivate the product. tx.Table (not Model) so GORM's
			//    soft-delete scope does not hide the row we must un-delete.
			restore := map[string]interface{}{"updated_at": now}
			if sn.PrevProductDeletedAt == nil {
				restore["deleted_at"] = gorm.Expr("NULL")
			} else {
				restore["deleted_at"] = *sn.PrevProductDeletedAt
			}
			if upErr := tx.Table("products").
				Where("id = ? AND tenant_id = ?", sn.ProductID, tenantID).
				Updates(restore).Error; upErr != nil {
				log.Printf("RestoreStockSetupReplace: product %s un-delete failed (skipped): %v", sn.ProductID, upErr)
				res.Skipped++
				continue
			}
			res.ProductsRestored++

			// 2) Restore prior stock ONLY if still in the cleared state (0).
			//    If stock changed since the replace, newer truth wins.
			var st models.Stock
			if stErr := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?", sn.ShopID, sn.ProductID, tenantID).
				First(&st).Error; stErr == nil {
				if st.Quantity == 0 && sn.PrevStockQuantity > 0 {
					st.Quantity = sn.PrevStockQuantity
					if svErr := tx.Save(&st).Error; svErr == nil {
						res.StockRestored++
						sShop, sProd := st.ShopID, st.ProductID
						_ = tx.Create(&models.StockHistory{
							TenantModel:      models.TenantModel{TenantID: &tenantID},
							StockID:          st.ID,
							ShopID:           &sShop,
							ProductID:        &sProd,
							MovementType:     "stock_setup_replace_restore",
							Quantity:         sn.PrevStockQuantity,
							PreviousQuantity: 0,
							NewQuantity:      sn.PrevStockQuantity,
							Reference:        fmt.Sprintf("Stock Setup replace RESTORED: record %s", recordID),
							ReferenceID:      &recordID,
							Notes:            "Reversed snapshot-replace deactivation",
							CreatedByID:      byID,
						}).Error
					}
				}
			}

			// 3) Mark snapshot restored (idempotent — re-running is a no-op).
			if mErr := tx.Model(&models.StockSetupReplaceSnapshot{}).
				Where("id = ?", sn.ID).
				Updates(map[string]interface{}{
					"restored":       true,
					"restored_at":    now,
					"restored_by_id": byID,
					"updated_at":     now,
				}).Error; mErr != nil {
				return fmt.Errorf("mark snapshot %s restored: %w", sn.ID, mErr)
			}
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("restore failed: %w", err)
	}
	s.stockService.ClearShopStockCache(ctx, tenantID, shopForCache)
	res.Message = fmt.Sprintf("restored %d product(s), %d stock row(s), %d skipped",
		res.ProductsRestored, res.StockRestored, res.Skipped)
	return res, nil
}

func (s *SmartStockSetupService) ReapplyStockSetup(
	ctx context.Context,
	recordID, tenantID, reappliedByID uuid.UUID,
	approverRole string,
) (*StockSetupRecordResponse, error) {
	if approverRole != models.RoleAdmin && approverRole != models.RoleManager {
		return nil, fmt.Errorf("only admin or manager can reapply stock setup records")
	}
	var record models.StockSetupRecord
	if err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
		Preload("Items", orderItemsByRegisterRow).First(&record).Error; err != nil {
		return nil, fmt.Errorf("stock setup record not found: %w", err)
	}
	if record.Status != "approved" {
		return nil, fmt.Errorf("only approved records can be reapplied (record is %s)", record.Status)
	}
	if record.ApprovedAt == nil {
		return nil, fmt.Errorf("record has no approval timestamp")
	}
	// 7-day window. Beyond this, the record's snapshot is stale enough that a
	// blind reapply would erase legitimate stock changes from sales / receipts
	// since approval; user should run a fresh AI Stock Setup instead.
	if time.Since(*record.ApprovedAt) > 7*24*time.Hour {
		return nil, fmt.Errorf("reapply window expired — this record was approved more than 7 days ago. Run a fresh AI Stock Setup for the latest counts")
	}

	applied := 0
	skipped := 0
	err := s.db.Transaction(func(tx *gorm.DB) error {
		for idx := range record.Items {
			item := &record.Items[idx]

			// v1.0.295 — Unscoped() so we find any soft-deleted row and revive
			// it instead of creating a duplicate. See ApplyStockSetup site for
			// full rationale.
			// v1.0.297 — prefer LIVE row when both states coexist (chhotu 750ml).
			var stock models.Stock
			stockErr := tx.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?", record.ShopID, item.ProductID, tenantID).
				Order("deleted_at NULLS FIRST, id ASC").
				First(&stock).Error
			if stockErr != nil {
				if stockErr == gorm.ErrRecordNotFound {
					stock = models.Stock{
						TenantModel:   models.TenantModel{TenantID: &tenantID},
						ShopID:        record.ShopID,
						ProductID:     item.ProductID,
						Quantity:      0,
						CostingMethod: "fifo",
					}
					if cErr := tx.Create(&stock).Error; cErr != nil {
						log.Printf("ReapplyStockSetup: failed to create stock for product %s: %v", item.ProductID, cErr)
						skipped++
						continue
					}
				} else {
					log.Printf("ReapplyStockSetup: failed to query stock for product %s: %v", item.ProductID, stockErr)
					skipped++
					continue
				}
			} else if stock.DeletedAt.Valid {
				stock.DeletedAt = gorm.DeletedAt{}
			}

			previousQuantity := stock.Quantity
			if previousQuantity == item.Quantity {
				continue // already at target
			}
			if item.Quantity < stock.ReservedQuantity {
				log.Printf("ReapplyStockSetup: cannot reapply for product %s — target qty %d < reserved %d, skipping",
					item.ProductID, item.Quantity, stock.ReservedQuantity)
				skipped++
				continue
			}
			stock.Quantity = item.Quantity
			if saveErr := tx.Unscoped().Save(&stock).Error; saveErr != nil {
				log.Printf("ReapplyStockSetup: failed to update stock for product %s: %v", item.ProductID, saveErr)
				skipped++
				continue
			}

			// Audit row — distinct movement_type so reports can split reapplies
			// from initial approvals.
			raShopRef, raProdRef := stock.ShopID, stock.ProductID
			audit := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: &tenantID},
				StockID:          stock.ID,
				ShopID:           &raShopRef,
				ProductID:        &raProdRef,
				MovementType:     "stock_setup_reapply",
				Quantity:         item.Quantity - previousQuantity,
				PreviousQuantity: previousQuantity,
				NewQuantity:      item.Quantity,
				Reference:        fmt.Sprintf("Stock Setup record %s reapplied", record.ID),
				ReferenceID:      &record.ID,
				Notes:            fmt.Sprintf("Reapplied approved baseline (orig approved %s, within 7-day window)", record.ApprovedAt.Format(time.RFC3339)),
				CreatedByID:      reappliedByID,
			}
			if hErr := tx.Create(&audit).Error; hErr != nil {
				log.Printf("ReapplyStockSetup: failed to write stock_history for product %s: %v", item.ProductID, hErr)
			}

			applied++
			log.Printf("ReapplyStockSetup: product %s stock %d → %d (record=%s)",
				item.ProductID, previousQuantity, item.Quantity, record.ID)
		}

		// Stamp a breadcrumb on the record's notes so the web UI can show
		// "last reapplied" without a separate column.
		now := time.Now()
		newNote := fmt.Sprintf("%s\nReapplied %d / %d items at %s by %s",
			record.Notes, applied, len(record.Items), now.Format(time.RFC3339), reappliedByID)
		return tx.Model(&record).Updates(map[string]interface{}{
			"notes":      newNote,
			"updated_at": now,
		}).Error
	})
	if err != nil {
		return nil, fmt.Errorf("reapply failed: %w", err)
	}

	s.stockService.ClearShopStockCache(ctx, tenantID, record.ShopID)
	log.Printf("ReapplyStockSetup: record=%s applied=%d skipped=%d total=%d",
		record.ID, applied, skipped, len(record.Items))

	return s.GetStockSetupRecordByID(ctx, recordID, tenantID)
}

// RejectStockSetup rejects a pending stock setup record
func (s *SmartStockSetupService) RejectStockSetup(ctx context.Context, recordID, tenantID, rejectedByID uuid.UUID, reason string) error {
	result := s.db.Model(&models.StockSetupRecord{}).
		Where("id = ? AND tenant_id = ? AND status = 'pending' AND deleted_at IS NULL", recordID, tenantID).
		Updates(map[string]interface{}{
			"status":           "rejected",
			"rejection_reason": reason,
			"approved_by_id":   rejectedByID,
			"approved_at":      time.Now(),
		})

	if result.Error != nil {
		return fmt.Errorf("failed to reject stock setup: %w", result.Error)
	}
	if result.RowsAffected == 0 {
		return fmt.Errorf("record not found or already processed")
	}
	return nil
}

// UpdateStockSetupItemRequest is one row in the PATCH payload. ID is empty for
// newly-added rows; for existing rows it must match an item_id already on the
// record so we can locate + update (rather than recreate) it and preserve
// previous_db_stock for the delta-safe apply-on-approve math.
type UpdateStockSetupItemRequest struct {
	ID              string  `json:"id,omitempty"`
	ProductID       string  `json:"product_id" binding:"required"`
	Quantity        int     `json:"quantity"`
	OpeningStock    int     `json:"opening_stock"`
	Receipt         int     `json:"receipt"`
	Sale            int     `json:"sale"`
	Rate            float64 `json:"rate"`
	Amount          float64 `json:"amount"`
	PreviousDBStock *int    `json:"previous_db_stock,omitempty"`
}

// UpdateStockSetupRecordRequest is the PATCH body. Items replaces the full
// items list; anything not in the payload is deleted. Notes is optional
// (empty string leaves the existing value untouched to avoid accidentally
// clearing it — callers that want to clear notes can send a single space).
type UpdateStockSetupRecordRequest struct {
	Items []UpdateStockSetupItemRequest `json:"items" binding:"required"`
	Notes *string                       `json:"notes,omitempty"`
}

// UpdateStockSetupRecord applies manager edits to a pending record. Used by
// the web admin review UI when an AI-extracted row matched the wrong product
// (row drift) or when the manager needs to add a missing brand / delete a
// phantom row before approving. Only allowed when status=pending.
//
// Strategy: reconcile items in a single transaction — update rows whose id
// appears in the payload, create new rows for payload entries without id,
// delete existing rows whose id isn't referenced. PreviousDBStock is
// preserved on update (so the delta math on approve stays correct), but
// fetched fresh for new rows added by the manager.
func (s *SmartStockSetupService) UpdateStockSetupRecord(ctx context.Context, recordID, tenantID, actorID uuid.UUID, req UpdateStockSetupRecordRequest) (*StockSetupRecordResponse, error) {
	var record models.StockSetupRecord
	if err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
		Preload("Items", orderItemsByRegisterRow).First(&record).Error; err != nil {
		return nil, fmt.Errorf("stock setup record not found: %w", err)
	}
	if record.Status != "pending" {
		return nil, fmt.Errorf("record is %s, only pending records can be edited", record.Status)
	}
	if len(req.Items) == 0 {
		return nil, fmt.Errorf("items[] must contain at least one row — delete the record instead if you want to remove all rows")
	}

	// Index existing items by id so we can tell update vs delete in one pass.
	existing := make(map[string]*models.StockSetupItem, len(record.Items))
	for i := range record.Items {
		existing[record.Items[i].ID.String()] = &record.Items[i]
	}

	keepIDs := make(map[string]struct{}, len(req.Items))
	var totalQty int
	var totalVal float64

	err := s.db.Transaction(func(tx *gorm.DB) error {
		for _, row := range req.Items {
			productUUID, perr := uuid.Parse(row.ProductID)
			if perr != nil {
				return fmt.Errorf("invalid product_id %q: %w", row.ProductID, perr)
			}
			// Verify product belongs to this tenant — a sanity check so a bad
			// admin UI can't stash a cross-tenant product id in here.
			var prodCount int64
			if err := tx.Model(&models.Product{}).
				Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", productUUID, tenantID).
				Count(&prodCount).Error; err != nil {
				return fmt.Errorf("verify product %s: %w", row.ProductID, err)
			}
			if prodCount == 0 {
				return fmt.Errorf("product %s not found in this tenant", row.ProductID)
			}

			// Per-shop ownership guard (v1.0.397): the web-admin Swap picker can
			// surface another shop's identically-named product. Convert any
			// cross-shop pick to a shop-owned equivalent so the edit can never
			// persist a link that trg_block_crossshop_stock would reject at
			// approve. No-op when the pick already belongs to the record's shop.
			if newPID, changed, dErr := s.demoteCrossShopProduct(tx, tenantID, record.ShopID, productUUID.String()); dErr != nil {
				return fmt.Errorf("edit item product %s: %w", row.ProductID, dErr)
			} else if changed {
				if np, perr := uuid.Parse(newPID); perr == nil {
					log.Printf("UpdateStockSetupRecord: cross-shop pick %s demoted to shop-owned %s (record %s shop %s)", productUUID, np, record.ID, record.ShopID)
					productUUID = np
				}
			}

			amount := row.Amount
			if amount == 0 && row.Rate > 0 {
				amount = row.Rate * float64(row.Quantity)
			}

			if row.ID != "" {
				// Update path — preserve previous_db_stock unless the caller
				// explicitly set it.
				item, ok := existing[row.ID]
				if !ok {
					return fmt.Errorf("item %s does not belong to record", row.ID)
				}
				item.ProductID = productUUID
				item.Quantity = row.Quantity
				item.OpeningStock = row.OpeningStock
				item.Receipt = row.Receipt
				item.Sale = row.Sale
				item.Rate = row.Rate
				item.Amount = amount
				if row.PreviousDBStock != nil {
					item.PreviousDBStock = *row.PreviousDBStock
				}
				if err := tx.Save(item).Error; err != nil {
					return fmt.Errorf("update item %s: %w", row.ID, err)
				}
				keepIDs[row.ID] = struct{}{}
			} else {
				// Create path — fetch current DB stock so the delta math on
				// approve works for the newly-added row.
				var prevStock int
				var st models.Stock
				if serr := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?", record.ShopID, productUUID, tenantID).
					First(&st).Error; serr == nil {
					prevStock = st.Quantity
				}
				if row.PreviousDBStock != nil {
					prevStock = *row.PreviousDBStock
				}
				newItem := models.StockSetupItem{
					TenantModel:        models.TenantModel{TenantID: &tenantID},
					StockSetupRecordID: record.ID,
					ProductID:          productUUID,
					Quantity:           row.Quantity,
					OpeningStock:       row.OpeningStock,
					Receipt:            row.Receipt,
					Sale:               row.Sale,
					Rate:               row.Rate,
					Amount:             amount,
					PreviousDBStock:    prevStock,
				}
				if err := tx.Create(&newItem).Error; err != nil {
					return fmt.Errorf("create new item: %w", err)
				}
				keepIDs[newItem.ID.String()] = struct{}{}
			}
			totalQty += row.Quantity
			totalVal += amount
		}

		// Delete items no longer present.
		var deleteIDs []uuid.UUID
		for id, item := range existing {
			if _, keep := keepIDs[id]; !keep {
				deleteIDs = append(deleteIDs, item.ID)
			}
		}
		if len(deleteIDs) > 0 {
			if err := tx.Where("id IN ? AND stock_setup_record_id = ?", deleteIDs, record.ID).
				Delete(&models.StockSetupItem{}).Error; err != nil {
				return fmt.Errorf("delete removed items: %w", err)
			}
		}

		// Update record totals + notes.
		updates := map[string]interface{}{
			"total_items":    len(req.Items),
			"total_quantity": totalQty,
			"total_value":    totalVal,
			"updated_at":     time.Now(),
		}
		if req.Notes != nil {
			updates["notes"] = *req.Notes
		}
		if err := tx.Model(&models.StockSetupRecord{}).
			Where("id = ? AND tenant_id = ?", record.ID, tenantID).
			Updates(updates).Error; err != nil {
			return fmt.Errorf("update record totals: %w", err)
		}

		added := 0
		for _, row := range req.Items {
			if row.ID == "" {
				added++
			}
		}
		log.Printf("UpdateStockSetupRecord: record=%s actor=%s updated=%d added=%d deleted=%d totals(qty=%d val=%.2f)",
			recordID, actorID, len(req.Items)-added, added, len(deleteIDs), totalQty, totalVal)
		return nil
	})
	if err != nil {
		return nil, err
	}

	return s.GetStockSetupRecordByID(ctx, recordID, tenantID)
}

// AutoFixBrandLinksResult is the response shape for the auto-heal endpoint:
// which rows were fixed and which still need human review.
type AutoFixBrandLinksResult struct {
	TotalFlagged int                      `json:"total_flagged"`
	Fixed        []AutoFixedBrandLink     `json:"fixed"`
	NeedsReview  []AutoFixNeedsReview     `json:"needs_review"`
}

type AutoFixedBrandLink struct {
	ProductID   string `json:"product_id"`
	ProductName string `json:"product_name"`
	OldBrand    string `json:"old_brand"`
	NewBrand    string `json:"new_brand"`
	Score       float64 `json:"score"`
}

type AutoFixNeedsReview struct {
	ProductID   string `json:"product_id"`
	ProductName string `json:"product_name"`
	CurrentBrand string `json:"current_brand"`
	Reason      string `json:"reason"`
}

// AutoFixBrandLinks scans a pending record's items, finds rows where the
// product's own name disagrees with its linked brand's name (the "suspect
// catalog link" flag), and auto-repairs the product's brand_id by searching
// the tenant's brands table for the best name match. Only fires the update
// when the match is strong (Jaccard ≥ 0.50 over meaningful tokens) — rows
// that can't be repaired with confidence are returned as needs_review so
// the manager can swap them manually via Edit mode.
//
// Why this helps: the user's record d4370fa3 row 11 had
// product "Royal Stag Barrel Select" linked to brand "M2 Magic Moments
// Verve Cranberry". There ARE three tenant brands named "ROYAL STAG BARREL
// SELECT …" — the heuristic finds the best of them by name overlap and
// rewires the product's brand_id to the right one, so future responses
// show the correct brand without any manual intervention.
func (s *SmartStockSetupService) AutoFixBrandLinks(ctx context.Context, recordID, tenantID uuid.UUID) (*AutoFixBrandLinksResult, error) {
	var record models.StockSetupRecord
	if err := s.db.Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
		Preload("Items", orderItemsByRegisterRow).
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		First(&record).Error; err != nil {
		return nil, fmt.Errorf("stock setup record not found: %w", err)
	}
	if record.Status != "pending" {
		return nil, fmt.Errorf("record is %s, only pending records can be auto-fixed", record.Status)
	}

	// Preload all tenant brands once — we'll score every flagged product
	// against all of them. Scales fine; a tenant typically has <5k brands.
	var allBrands []models.Brand
	if err := s.db.Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
		Find(&allBrands).Error; err != nil {
		return nil, fmt.Errorf("load brands: %w", err)
	}

	result := &AutoFixBrandLinksResult{
		Fixed:       []AutoFixedBrandLink{},
		NeedsReview: []AutoFixNeedsReview{},
	}

	// Track products we've already processed so multiple items sharing the
	// same product (rare but possible) don't double-fix.
	processed := make(map[uuid.UUID]struct{})

	for _, item := range record.Items {
		if item.Product == nil || item.Product.Brand == nil {
			continue
		}
		productName := item.Product.Name
		brandName := item.Product.Brand.Name
		if !productBrandMismatch(productName, brandName) {
			continue
		}
		result.TotalFlagged++
		if _, seen := processed[item.ProductID]; seen {
			continue
		}
		processed[item.ProductID] = struct{}{}

		// Find best brand candidate by name overlap against product.name.
		bestBrandID := uuid.Nil
		bestBrandName := ""
		bestScore := 0.0
		for _, b := range allBrands {
			if b.ID == item.Product.BrandID {
				continue // skip the already-linked (wrong) brand
			}
			score := nameOverlapJaccard(productName, b.Name)
			if score > bestScore {
				bestScore = score
				bestBrandID = b.ID
				bestBrandName = b.Name
			}
		}

		// Strong-match threshold. 0.5 means at least half the meaningful
		// tokens overlap (e.g. "Royal Stag Barrel Select" vs "SEAGRAM'S
		// ROYAL STAG BARREL SELECT WHISKY" scores ~0.67 after strip —
		// stopwords like SEAGRAMS/WHISKY drop out). Below this we flag
		// as needs_review instead of guessing.
		if bestBrandID == uuid.Nil || bestScore < 0.5 {
			result.NeedsReview = append(result.NeedsReview, AutoFixNeedsReview{
				ProductID:    item.ProductID.String(),
				ProductName:  productName,
				CurrentBrand: brandName,
				Reason:       "No tenant brand matched strongly (best score " + fmt.Sprintf("%.2f", bestScore) + ")",
			})
			continue
		}

		// Update the product's brand_id in place. Also CLEAR display_name and
		// its bold range — leaving them set would render the OLD brand label
		// on the inventory list (Tushar saw "XCLAMATION 63" on a row whose
		// name was already "Royal Green" because display_name was stale from
		// the original create). The Flutter list prefers display_name over
		// name; clearing it lets the bold-fallback util recompute from the
		// current brand on next render.
		if err := s.db.Model(&models.Product{}).
			Where("id = ? AND tenant_id = ?", item.ProductID, tenantID).
			Updates(map[string]interface{}{
				"brand_id":                 bestBrandID,
				"display_name":             "",
				"display_name_bold_start":  nil,
				"display_name_bold_length": nil,
			}).Error; err != nil {
			result.NeedsReview = append(result.NeedsReview, AutoFixNeedsReview{
				ProductID:    item.ProductID.String(),
				ProductName:  productName,
				CurrentBrand: brandName,
				Reason:       "Update failed: " + err.Error(),
			})
			continue
		}
		log.Printf("AutoFixBrandLinks: record=%s product=%s '%s': brand_id %s → %s (score %.2f)",
			recordID, item.ProductID, productName, item.Product.BrandID, bestBrandID, bestScore)
		result.Fixed = append(result.Fixed, AutoFixedBrandLink{
			ProductID:   item.ProductID.String(),
			ProductName: productName,
			OldBrand:    brandName,
			NewBrand:    bestBrandName,
			Score:       bestScore,
		})
	}

	return result, nil
}

// tryAutoHealProductBrand repairs a single product's brand_id attachment
// at match time, returning (newBrandName, true) when a confident replacement
// was found and written. Called from the matching path: when we detect
// product.Name ↔ brand.Name divergence (catalog corruption), we search the
// tenant brands for the best name overlap against product.Name, and if the
// top scorer clears the threshold (≥0.50 Jaccard) we UPDATE products.brand_id
// in place. The next time this product is loaded the brand will be correct,
// and downstream callers on the current request get the healed brand name
// via the return value.
//
// Threshold notes: 0.50 is intentionally conservative. It means at least
// half the meaningful tokens of product.Name appear in brand.Name (after
// stopwords like WHISKY / PREMIUM / BLENDED are removed). For the row-11
// case the scorer picks "SEAGRAM'S ROYAL STAG BARREL SELECT WHISKY" at
// ~0.67 — a clean win over all other tenant brands.
//
// This method is cheap in practice (one SELECT all brands + one UPDATE
// product) and we don't cache the brands list at the caller because
// catalog corruption is rare. When it's not rare, the caller-level audit
// (AutoFixBrandLinks) is the right bulk tool.
func (s *SmartStockSetupService) tryAutoHealProductBrand(tenantID, productID uuid.UUID, productName string) (string, bool) {
	var brands []models.Brand
	if err := s.db.Where("tenant_id = ? AND deleted_at IS NULL", tenantID).Find(&brands).Error; err != nil {
		return "", false
	}
	bestID := uuid.Nil
	bestName := ""
	bestScore := 0.0
	for _, b := range brands {
		score := nameOverlapJaccard(productName, b.Name)
		if score > bestScore {
			bestScore = score
			bestID = b.ID
			bestName = b.Name
		}
	}
	if bestID == uuid.Nil || bestScore < 0.50 {
		return "", false
	}
	// Same display_name reset as AutoFixBrandLinks — see note there.
	if err := s.db.Model(&models.Product{}).
		Where("id = ? AND tenant_id = ?", productID, tenantID).
		Updates(map[string]interface{}{
			"brand_id":                 bestID,
			"display_name":             "",
			"display_name_bold_start":  nil,
			"display_name_bold_length": nil,
		}).Error; err != nil {
		return "", false
	}
	log.Printf("tryAutoHealProductBrand: product=%s (%s) → brand %s (%s) score=%.2f",
		productID, productName, bestID, bestName, bestScore)
	return bestName, true
}

// nameOverlapJaccard returns Jaccard similarity between two names after
// dropping stopwords/size-markers (using meaningfulTokens). Same helper
// productBrandMismatch uses — extracted here so the auto-heal can rank
// positively (higher = better match) while the mismatch detector reads
// the same score negatively (lower = bad).
func nameOverlapJaccard(a, b string) float64 {
	at := meaningfulTokens(a)
	bt := meaningfulTokens(b)
	if len(at) == 0 || len(bt) == 0 {
		return 0
	}
	aset := make(map[string]struct{}, len(at))
	for _, t := range at {
		aset[t] = struct{}{}
	}
	inter := 0
	for _, t := range bt {
		if _, ok := aset[t]; ok {
			inter++
		}
	}
	union := len(aset)
	for _, t := range bt {
		if _, ok := aset[t]; !ok {
			union++
		}
	}
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

// v1.0.252 — auditPhotoSet is the latest Front/Back photo + back-MRP captured
// for one physical register row, recovered from stock_setup_image_verifications.
type auditPhotoSet struct {
	Front   string
	Back    string
	BackMRP float64
}

// v1.0.255 — Resilient, app-version-independent photo recovery.
//
// v252's key (session_id/row_number/page_number) requires an updated app and
// is NULL on 100% of prod audit rows (operator on a stale APK). But the
// Flutter row_id (= _ReviewProduct.id) is a REQUIRED verify-row field on
// EVERY app version since v243, and is embedded in image_url as
// `…/{rowID}-{face}-{ts}.jpg`. So the binding key already exists in legacy
// data. resolveRecordAuditPhotos binds photos→items by EXACT key, tiered:
//   T1 rid == item.product_id            (matched rows; rid is the product uuid)
//   T2 v252 session+row(+page)           (authoritative once apps update)
//   T3 auto_<rownum>_ rid → ai_row_number (auto-create rows; exact row pos)
// Ambiguous (a key → >1 item in the record) ⇒ bind none: never the wrong
// bottle. No fuzzy brand matching anywhere.

type rcand struct {
	rid     string
	face    string
	rowNum  int
	pageNum int
	session string
	url     string
	mrp     float64
}

var ridFromURLRe = regexp.MustCompile(`/([^/]+)-(front|back)-[0-9]+\.[A-Za-z0-9]+$`)
var autoRowRe = regexp.MustCompile(`^auto_([0-9]+)_`)

// loadAuditCands pulls every verify-row photo for this shop within a bounded
// window around the record (operators photograph then submit; the window only
// disambiguates between multiple same-shop setups — rid/rownum is the real
// key). Derives rid/face/rowNum from the row_id column when present, else from
// the image_url filename (works for ALL legacy app versions).
func (s *SmartStockSetupService) loadAuditCands(tenantID, shopID uuid.UUID, recAt time.Time) []rcand {
	var rows []struct {
		RowIDCol   string  `gorm:"column:row_id"`
		SessionID  string  `gorm:"column:session_id"`
		RowNumCol  int     `gorm:"column:row_number"`
		PageNumCol int     `gorm:"column:page_number"`
		Face       string  `gorm:"column:face"`
		ImageURL   string  `gorm:"column:image_url"`
		MRP        float64 `gorm:"column:extracted_mrp"`
	}
	if err := s.db.Raw(`
		SELECT COALESCE(row_id,'')        AS row_id,
		       COALESCE(session_id,'')    AS session_id,
		       COALESCE(row_number,0)     AS row_number,
		       COALESCE(page_number,0)    AS page_number,
		       face,
		       image_url,
		       COALESCE(extracted_mrp,0)  AS extracted_mrp
		FROM stock_setup_image_verifications
		WHERE tenant_id = ? AND shop_id = ? AND image_url <> ''
		  AND created_at BETWEEN ? AND ?
		ORDER BY created_at DESC
	`, tenantID, shopID, recAt.Add(-12*time.Hour), recAt.Add(2*time.Hour)).Scan(&rows).Error; err != nil {
		log.Printf("Stock Setup: audit-photo candidate load failed (shop=%s): %v — rows may show 'no photo'", shopID, err)
		return nil
	}
	out := make([]rcand, 0, len(rows))
	for _, r := range rows {
		c := rcand{
			rid: strings.TrimSpace(r.RowIDCol), face: strings.ToLower(strings.TrimSpace(r.Face)),
			rowNum: r.RowNumCol, pageNum: r.PageNumCol,
			session: strings.TrimSpace(r.SessionID), url: r.ImageURL, mrp: r.MRP,
		}
		if m := ridFromURLRe.FindStringSubmatch(r.ImageURL); m != nil {
			if c.rid == "" {
				c.rid = m[1]
			}
			if c.face != "front" && c.face != "back" {
				c.face = m[2]
			}
		}
		if c.rowNum <= 0 {
			if am := autoRowRe.FindStringSubmatch(c.rid); am != nil {
				if n, e := strconv.Atoi(am[1]); e == nil {
					c.rowNum = n
				}
			}
		}
		if c.face == "front" || c.face == "back" {
			out = append(out, c)
		}
	}
	return out
}

// pickItemPhotos applies the tiers for ONE item. cands are createdAt DESC, so
// the first match per face is the latest. rowAmbiguous disables T3 for items
// whose ai_row_number is shared by >1 item in the record.
func pickItemPhotos(cands []rcand, productID string, aiRow, aiPage int, recSession string, rowAmbiguous bool) auditPhotoSet {
	productID = strings.TrimSpace(productID)
	recSession = strings.TrimSpace(recSession)
	tierMatch := func(c rcand, tier int) bool {
		switch tier {
		case 1:
			return productID != "" && c.rid == productID
		case 2:
			return recSession != "" && c.session != "" && c.session == recSession &&
				c.rowNum > 0 && c.rowNum == aiRow &&
				(c.pageNum == aiPage || c.pageNum == 0 || aiPage == 0)
		case 3:
			return !rowAmbiguous && aiRow > 0 && c.rowNum > 0 && c.rowNum == aiRow
		}
		return false
	}
	var ps auditPhotoSet
	for _, face := range []string{"front", "back"} {
		for tier := 1; tier <= 3; tier++ {
			hit := false
			for _, c := range cands {
				if c.face != face || !tierMatch(c, tier) {
					continue
				}
				if face == "front" {
					ps.Front = c.url
				} else {
					ps.Back = c.url
					if c.mrp > 0 {
						ps.BackMRP = c.mrp
					}
				}
				hit = true
				break
			}
			if hit {
				break
			}
		}
	}
	return ps
}

// aiRowPage parses ai_row_number/ai_page_number from a RawAIExtraction blob.
// Returns row<=0 when missing/unparseable so the caller keeps "no photo"
// rather than guessing (defensive — silent-drop/dead-code lessons).
func aiRowPage(raw datatypes.JSON) (row, page int) {
	if len(raw) == 0 {
		return 0, 0
	}
	var m map[string]interface{}
	if err := json.Unmarshal(raw, &m); err != nil {
		return 0, 0
	}
	toInt := func(v interface{}) int {
		switch n := v.(type) {
		case float64:
			return int(n)
		case int:
			return n
		case string:
			if x, err := strconv.Atoi(strings.TrimSpace(n)); err == nil {
				return x
			}
		}
		return 0
	}
	return toInt(m["ai_row_number"]), toInt(m["ai_page_number"])
}

// buildRecordResponse converts a model to API response
func (s *SmartStockSetupService) buildRecordResponse(rec models.StockSetupRecord) StockSetupRecordResponse {
	resp := StockSetupRecordResponse{
		ID:            rec.ID.String(),
		ShopID:        rec.ShopID.String(),
		Category:      rec.Category,
		Size:          rec.Size,
		TotalItems:    rec.TotalItems,
		TotalQuantity: rec.TotalQuantity,
		TotalValue:    rec.TotalValue,
		Status:        rec.Status,
		ApprovedAt:    rec.ApprovedAt,
		RejectionReason: rec.RejectionReason,
		CreatedByID:   rec.CreatedByID.String(),
		Notes:         rec.Notes,
		ReceiptImages: []string(rec.ReceiptImages),
		AIModel:       rec.AIModel,
		CreatedAt:     rec.CreatedAt,
		UpdatedAt:     rec.UpdatedAt,
	}

	if resp.ReceiptImages == nil {
		resp.ReceiptImages = []string{}
	}

	if rec.Shop != nil {
		resp.ShopName = rec.Shop.Name
	}

	// Look up category name
	if rec.Category != "" {
		var catName struct{ Name string }
		if err := s.db.Table("categories").Select("name").
			Where("id = ? AND tenant_id = ?", rec.Category, rec.TenantID).
			Scan(&catName).Error; err == nil && catName.Name != "" {
			resp.CategoryName = catName.Name
		}
	}

	// Look up creator name + phone. v1.0.203 — phone surfaced on the admin
	// list so managers can tap-to-call the operator directly.
	var creator struct {
		FirstName string `gorm:"column:first_name"`
		LastName  string `gorm:"column:last_name"`
		Phone     string `gorm:"column:phone"`
	}
	if err := s.db.Table("users").Select("first_name, last_name, phone").
		Where("id = ?", rec.CreatedByID).Scan(&creator).Error; err == nil {
		resp.CreatedByName = strings.TrimSpace(creator.FirstName + " " + creator.LastName)
		resp.CreatedByMobile = strings.TrimSpace(creator.Phone)
	}

	// Look up approver name
	if rec.ApprovedByID != nil {
		var approver struct {
			FirstName string `gorm:"column:first_name"`
			LastName  string `gorm:"column:last_name"`
		}
		if err := s.db.Table("users").Select("first_name, last_name").
			Where("id = ?", rec.ApprovedByID).Scan(&approver).Error; err == nil {
			resp.ApprovedBy = strings.TrimSpace(approver.FirstName + " " + approver.LastName)
		}
	}

	// Batch-load saas_brand display_name + bold indices for every item's
	// saas_brand_id. Many tenant product rows have display_name populated
	// but bold_start/bold_length are NULL — because the master-catalog
	// sync copies the string but never copied the bold config at the time
	// the product was created. We use the saas_brand as the fallback so
	// the bold treatment configured at master data flows through even
	// when the tenant copy is incomplete. One query per record, keyed by
	// saas_brand_id.
	type saasBrandDN struct {
		ID          string
		Name        string
		DisplayName string
		BoldStart   *int
		BoldLength  *int
	}
	saasBrandByID := map[string]saasBrandDN{}
	{
		seen := map[string]struct{}{}
		var ids []string
		for _, it := range rec.Items {
			if it.Product != nil && it.Product.SaaSBrandID != nil {
				id := it.Product.SaaSBrandID.String()
				if _, ok := seen[id]; !ok {
					seen[id] = struct{}{}
					ids = append(ids, id)
				}
			}
		}
		if len(ids) > 0 {
			var rows []struct {
				ID          string `gorm:"column:id"`
				Name        string `gorm:"column:name"`
				DisplayName string `gorm:"column:display_name"`
				BoldStart   *int   `gorm:"column:display_name_bold_start"`
				BoldLength  *int   `gorm:"column:display_name_bold_length"`
			}
			if err := s.db.Table("saas_brands").
				Select("id, name, display_name, display_name_bold_start, display_name_bold_length").
				Where("id IN ?", ids).
				Scan(&rows).Error; err == nil {
				for _, r := range rows {
					saasBrandByID[r.ID] = saasBrandDN{
						ID: r.ID, Name: r.Name, DisplayName: r.DisplayName,
						BoldStart: r.BoldStart, BoldLength: r.BoldLength,
					}
				}
			}
		}
	}

	// v1.0.255 — resilient photo backfill (app-version-independent). Photos
	// are written to stock_setup_image_verifications on every capture but the
	// volatile submit payload + v252 app-key both fail on stale apps. Recover
	// by exact key derived from data ALL app versions already produce (row_id
	// in the filename). Fill-only-empty below — never overwrite, never fuzzy.
	var auditCands []rcand
	aiRowCount := map[int]int{}
	{
		var tid uuid.UUID
		if rec.TenantID != nil {
			tid = *rec.TenantID
		}
		auditCands = s.loadAuditCands(tid, rec.ShopID, rec.CreatedAt)
		for _, it := range rec.Items {
			if r, _ := aiRowPage(it.RawAIExtraction); r > 0 {
				aiRowCount[r]++
			}
		}
	}
	recSession := ""
	if rec.SessionID != nil {
		recSession = *rec.SessionID
	}

	// Build items
	for _, item := range rec.Items {
		itemResp := StockSetupItemResponse{
			ID:              item.ID.String(),
			ProductID:       item.ProductID.String(),
			Quantity:        item.Quantity,
			OpeningStock:    item.OpeningStock,
			Receipt:         item.Receipt,
			Sale:            item.Sale,
			Rate:            item.Rate,
			Amount:          item.Amount,
			PreviousDBStock: item.PreviousDBStock,
			// v1.0.246 — Verification photos. Empty when no photo captured.
			FrontImageURL:         item.FrontImageURL,
			BackImageURL:          item.BackImageURL,
			VerifiedViaImageFront: item.VerifiedViaImageFront,
			VerifiedViaImageBack:  item.VerifiedViaImageBack,
			BackImageMRP:          item.BackImageMRP,
		}
		// v1.0.255 — fill-only-empty tiered backfill (T1 product_id / T2 v252
		// key / T3 auto-row), exact keys only, ambiguous→skip.
		if len(auditCands) > 0 {
			aiR, aiP := aiRowPage(item.RawAIExtraction)
			ps := pickItemPhotos(auditCands, item.ProductID.String(), aiR, aiP, recSession, aiRowCount[aiR] > 1)
			if itemResp.FrontImageURL == "" && ps.Front != "" {
				itemResp.FrontImageURL = ps.Front
				itemResp.VerifiedViaImageFront = true
			}
			if itemResp.BackImageURL == "" && ps.Back != "" {
				itemResp.BackImageURL = ps.Back
				itemResp.VerifiedViaImageBack = true
			}
			if itemResp.BackImageMRP == 0 && ps.BackMRP > 0 {
				itemResp.BackImageMRP = ps.BackMRP
			}
		}
		if item.Product != nil {
			itemResp.Size = item.Product.Size
			if item.Product.SaaSVariantID != nil {
				itemResp.SaaSVariantID = item.Product.SaaSVariantID.String()
			}

			// Master-or-tenant sourcing for the three display fields.
			//
			// When the tenant product is linked to a master saas_brand
			// (saas_brand_id set AND the batch-load resolved the row),
			// the master catalog is the single source of truth: bold line
			// (display_name), small line (brand_name) and product name
			// all come from there. This keeps the row self-consistent
			// even when the tenant's own brand_id / display_name fields
			// have drifted out of sync with the master — the exact
			// "M2 Magic Moments Superior Vodka" bold next to "M2 Magic
			// Moments JAMUN SPICYMINT" small-line bug on record d4370fa3
			// row 2.
			//
			// Tenant product.Name, product.Brand.Name, product.DisplayName
			// are kept as fallbacks for two cases:
			//   (a) unlinked custom products (saas_brand_id IS NULL), and
			//   (b) linked products whose master row got deleted / wasn't
			//       loaded (keep something rendering rather than blank).
			//
			// IMPORTANT: the productBrandMismatch detector below still
			// compares the RAW tenant strings (product.Name vs Brand.Name)
			// so the amber "Suspect catalog link" badge keeps surfacing
			// rows with corrupted brand_id even after this display-layer
			// shield makes the UI look clean. The data-side heal path
			// (AutoFixBrandLinks) remains the actual fix.
			tenantProdName := item.Product.Name
			tenantBrandName := ""
			if item.Product.Brand != nil {
				tenantBrandName = item.Product.Brand.Name
			}

			var master *saasBrandDN
			if item.Product.SaaSBrandID != nil {
				if sb, ok := saasBrandByID[item.Product.SaaSBrandID.String()]; ok {
					master = &sb
				}
			}

			if master != nil && strings.TrimSpace(master.Name) != "" {
				itemResp.ProductName = master.Name
				itemResp.BrandName = master.Name
				// display_name priority within master-sourced path:
				//   master.DisplayName (the consumer-facing label) →
				//   master.Name (fall back to official name if no
				//   display_name is configured on the master row).
				if strings.TrimSpace(master.DisplayName) != "" {
					itemResp.DisplayName = master.DisplayName
				} else {
					itemResp.DisplayName = master.Name
				}
				itemResp.DisplayNameBoldStart = master.BoldStart
				itemResp.DisplayNameBoldLength = master.BoldLength
			} else {
				// Unlinked / master-missing — keep tenant fields.
				itemResp.ProductName = tenantProdName
				if tenantBrandName != "" {
					itemResp.BrandName = tenantBrandName
				} else {
					itemResp.BrandName = tenantProdName
				}
				if strings.TrimSpace(item.Product.DisplayName) != "" {
					itemResp.DisplayName = item.Product.DisplayName
					itemResp.DisplayNameBoldStart = item.Product.DisplayNameBoldStart
					itemResp.DisplayNameBoldLength = item.Product.DisplayNameBoldLength
				}
			}

			// Catalog-corruption check — surfaces the amber "Brand mismatch"
			// badge when a tenant product's name and its linked brand share
			// almost no meaningful tokens (Jaccard < 0.30). Useful for
			// detecting legacy data corruption, BUT only when the legacy
			// brand_id is the actual source of truth.
			//
			// v1.0.130 — gate on saas_brand_id IS NULL. When the tenant
			// product is linked to a master saas_brand, the master catalog
			// IS the authoritative brand source (the display layer at L6239
			// already overrides tenant fields with master.Name). A wrong
			// legacy brand_id is invisible to the user and irrelevant to
			// downstream features. Showing the badge anyway just nags the
			// user about a problem they already resolved by picking from
			// the master picker. Real case: row 22 of record `43140443`
			// (SEAGRAMS BLENDERS PRIDE RESERVE COLLECTION EXCLUSIVE 375ml)
			// resolved to product 3355a36f via master pick — saas_brand_id
			// set, but legacy brand_id still pointed at "Blender Pride Blue
			// Collection" → badge fired despite the user's confirmation.
			//
			// Custom user-created products with no saas link still surface
			// the badge — there the legacy brand_id IS the only signal, so
			// a real mismatch is actionable via Edit-mode swap or the
			// "Auto-fix brand links" button.
			if tenantProdName != "" && tenantBrandName != "" && item.Product.SaaSBrandID == nil {
				if productBrandMismatch(tenantProdName, tenantBrandName) {
					itemResp.SuspectCatalogLink = true
					itemResp.Warnings = append(itemResp.Warnings,
						"Suspect catalog link: product name and linked brand disagree")
				}
			}
		} else {
			// 2026-05-19 — Unit 1: a deferred-create row has NO product yet
			// (parked with the zero-UUID sentinel until a manager approves).
			// Without this it renders as a blank, un-reviewable row. Source
			// the operator-facing name from the persisted AI extraction blob
			// (the SAME fields ApproveStockSetup rebuilds the product from) +
			// the record-level size, so the reviewer sees exactly what they
			// are approving. Pure display shaping — no logic/stock effect;
			// also repairs any legacy product-less item.
			if item.RawAIExtraction != nil {
				var bN struct {
					AIBrand      string `json:"ai_brand"`
					EditedName   string `json:"edited_name"`
					OfficialName string `json:"official_brand_name"`
				}
				_ = json.Unmarshal(item.RawAIExtraction, &bN)
				nm := firstNonEmptyStr(
					firstNonEmptyStr(strings.TrimSpace(bN.EditedName), strings.TrimSpace(bN.OfficialName)),
					strings.TrimSpace(bN.AIBrand))
				itemResp.ProductName = nm
				itemResp.BrandName = nm
				itemResp.DisplayName = nm
			}
			if itemResp.Size == "" {
				itemResp.Size = rec.Size
			}
		}
		resp.Items = append(resp.Items, itemResp)
	}
	if resp.Items == nil {
		resp.Items = []StockSetupItemResponse{}
	}

	return resp
}

// productBrandMismatch returns true when the product name and brand name
// don't share enough meaningful tokens to plausibly be the same thing.
// Strategy: tokenize both on whitespace, lowercase, drop stopwords / numeric
// size markers, then compute Jaccard overlap. Threshold chosen empirically
// at 0.30 — below that virtually every real case is catalog corruption
// (confirmed by hand on tenant record d4370fa3's row 11 Royal Stag →
// Magic Moments Verve Cranberry, and row 16 Rockford Reserve Fine & Rare →
// Rockford Classic Finest, both of which land at <0.20 overlap).
func productBrandMismatch(productName, brandName string) bool {
	pt := meaningfulTokens(productName)
	bt := meaningfulTokens(brandName)
	if len(pt) == 0 || len(bt) == 0 {
		return false
	}
	// Intersection size.
	pset := make(map[string]struct{}, len(pt))
	for _, t := range pt {
		pset[t] = struct{}{}
	}
	overlap := 0
	for _, t := range bt {
		if _, ok := pset[t]; ok {
			overlap++
		}
	}
	// Jaccard — union - intersection in denominator keeps tiny-name cases
	// from tripping the check (e.g. a 3-word product against a 3-word brand
	// with one shared word scores 1/5 = 0.20, flagged; 2/4 = 0.50, clean).
	union := len(pset)
	for _, t := range bt {
		if _, ok := pset[t]; !ok {
			union++
		}
	}
	if union == 0 {
		return false
	}
	jaccard := float64(overlap) / float64(union)
	return jaccard < 0.30
}

// meaningfulTokens lowercases a name, strips size markers (750ml, 180ml…),
// drops stopwords that every liquor brand name carries (whisky, vodka, rum,
// premium, blended, rare, scotch, indian, fine, etc.), and returns the rest.
// Keeping stopwords would make every two whiskies look similar and mute the
// signal we actually want.
func meaningfulTokens(s string) []string {
	stop := map[string]struct{}{
		"whisky": {}, "whiskey": {}, "vodka": {}, "rum": {}, "gin": {}, "beer": {},
		"wine": {}, "brandy": {}, "scotch": {}, "blended": {}, "indian": {},
		"premium": {}, "superior": {}, "special": {}, "rare": {}, "fine": {},
		"finest": {}, "select": {}, "reserve": {}, "deluxe": {}, "classic": {},
		"original": {}, "grain": {}, "malt": {}, "single": {}, "double": {},
		"aged": {}, "old": {}, "year": {}, "years": {}, "the": {}, "and": {},
		"&": {}, "with": {}, "of": {}, "flavoured": {}, "flavored": {},
		"edition": {}, "collection": {}, "heritage": {}, "reserve.": {},
		"ml": {}, "l": {}, "full": {},
	}
	out := make([]string, 0, 8)
	for _, raw := range strings.Fields(strings.ToLower(s)) {
		tok := strings.Trim(raw, ".,()[]'\"-/")
		if tok == "" {
			continue
		}
		// Strip standalone size markers like "750ml" / "180" / "90ml".
		if len(tok) <= 6 {
			// If token ends in "ml" and the rest is digits, drop it.
			if strings.HasSuffix(tok, "ml") {
				digits := strings.TrimSuffix(tok, "ml")
				if digits != "" && allDigits(digits) {
					continue
				}
			}
			if allDigits(tok) {
				continue
			}
		}
		if _, isStop := stop[tok]; isStop {
			continue
		}
		out = append(out, tok)
	}
	return out
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// cleanupUnusedProducts deactivates products in the same category+size that weren't
// part of the apply and have 0 or no stock. This keeps the product list clean —
// only products the shop actually stocks remain active.
func (s *SmartStockSetupService) cleanupUnusedProducts(tenantID, shopID uuid.UUID, req SmartStockSetupApplyRequest) int {
	categoryID, err := uuid.Parse(req.CategoryID)
	if err != nil {
		return 0
	}
	sizeML := normalizeSizeText(req.Size)
	if sizeML == 0 {
		return 0
	}
	sizeStr := fmt.Sprintf("%dML", sizeML)

	// Build set of product IDs that were applied
	appliedIDs := make(map[string]bool)
	for _, item := range req.Items {
		appliedIDs[item.ProductID] = true
	}

	// Find all products in this category+size
	type scopedProduct struct {
		ID string
	}
	var products []scopedProduct
	s.db.Table("products").
		Select("id::text").
		Where("tenant_id = ? AND category_id = ? AND UPPER(size) = UPPER(?) AND is_active = true AND deleted_at IS NULL",
			tenantID, categoryID, sizeStr).
		Scan(&products)

	// For each product NOT in the applied set, check if it has stock > 0
	var toDeactivate []string
	for _, p := range products {
		if appliedIDs[p.ID] {
			continue // was part of the apply, keep it
		}

		// Check stock for this shop
		var stock struct {
			Quantity int
		}
		err := s.db.Table("stocks").
			Select("quantity").
			Where("product_id = ? AND shop_id = ? AND tenant_id = ? AND deleted_at IS NULL",
				p.ID, shopID, tenantID).
			First(&stock).Error

		if err != nil || stock.Quantity <= 0 {
			toDeactivate = append(toDeactivate, p.ID)
		}
	}

	if len(toDeactivate) == 0 {
		return 0
	}

	// Soft-delete unused products
	result := s.db.Table("products").
		Where("id IN ? AND tenant_id = ?", toDeactivate, tenantID).
		Updates(map[string]interface{}{
			"deleted_at": time.Now(),
			"is_active":  false,
		})

	if result.Error != nil {
		log.Printf("Smart Stock Setup: Failed to cleanup unused products: %v", result.Error)
		return 0
	}

	count := int(result.RowsAffected)
	log.Printf("Smart Stock Setup: Cleaned up %d unused products in %s %s (kept %d applied)",
		count, req.CategoryID[:8], sizeStr, len(appliedIDs))
	return count
}

// effectiveMRP returns MRP with fallback to SellingPrice when MRP is 0.
func absFloat64(x float64) float64 {
	if x < 0 {
		return -x
	}
	return x
}

func effectiveMRP(p dbProduct) float64 {
	if p.MRP > 0 {
		return p.MRP
	}
	if p.SellingPrice > 0 {
		return p.SellingPrice
	}
	return p.CostPrice
}

// mapToCanonical maps an AI category string to its canonical DB form.
func mapToCanonical(category string) string {
	categoryMap := map[string]string{
		"whiskey": "Whisky", "whisky": "Whisky", "scotch": "Whisky", "bourbon": "Whisky",
		"rum": "Rum", "vodka": "Vodka", "beer": "Beer", "lager": "Beer", "ale": "Beer",
		"brandy": "Brandy", "cognac": "Brandy", "gin": "Gin", "wine": "Wine",
		"country_liquor": "Country Liquor", "desi": "Country Liquor",
		"spirits": "IMFL", "rtd": "RTD",
	}
	if mapped, ok := categoryMap[strings.ToLower(strings.TrimSpace(category))]; ok {
		return mapped
	}
	return ""
}

// validateBrandForCategory checks if a brand name contains a category keyword
// that conflicts with the scoped category. Returns (isConflict, detectedCategory).
func validateBrandForCategory(brandName string, scopedCategoryName string) (bool, string) {
	normalizedBrand := strings.ToLower(brandName)
	normalizedScope := strings.ToLower(scopedCategoryName)

	categoryKeywords := map[string][]string{
		"whisky": {"whisky", "whiskey", "scotch", "bourbon"},
		"rum":    {"rum"},
		"vodka":  {"vodka"},
		"beer":   {"beer", "lager", "ale"},
		"brandy": {"brandy", "cognac"},
		"gin":    {"gin"},
		"wine":   {"wine"},
	}

	// Find which category the scope belongs to
	scopeKey := ""
	for key, keywords := range categoryKeywords {
		for _, kw := range keywords {
			if strings.Contains(normalizedScope, kw) {
				scopeKey = key
				break
			}
		}
		if scopeKey != "" {
			break
		}
	}

	// Check if brand name contains a DIFFERENT category's keyword (word boundary match)
	for key, keywords := range categoryKeywords {
		if key == scopeKey {
			continue
		}
		for _, kw := range keywords {
			idx := strings.Index(normalizedBrand, kw)
			if idx < 0 {
				continue
			}
			before := idx == 0 || !unicode.IsLetter(rune(normalizedBrand[idx-1]))
			after := idx+len(kw) >= len(normalizedBrand) || !unicode.IsLetter(rune(normalizedBrand[idx+len(kw)]))
			if before && after {
				return true, key
			}
		}
	}
	return false, ""
}

// searchAllProductsForBrandSize searches across ALL categories for a matching product.
// Used during auto-creation to find existing products in a different category than the scoped one.
// Caller must pre-load the broad catalog ONCE and pass both the dbProduct slice and its prepared
// form — this function runs in a loop over unmatched items, so the heavy load+prepare work
// must live outside to avoid N+1 query + CPU work per row.
func (s *SmartStockSetupService) searchAllProductsForBrandSize(brandName string, sizeML int, allProducts []dbProduct, prepared []matching.PreparedProduct) *dbProduct {
	if len(prepared) == 0 || brandName == "" {
		return nil
	}
	config := matching.DefaultPurchaseConfig()
	results := matching.MatchProducts(brandName, sizeML, 0, prepared, config)
	if len(results) > 0 && results[0].Score >= 0.80 {
		for i := range allProducts {
			if allProducts[i].ID == results[0].ProductID {
				return &allProducts[i]
			}
		}
	}
	return nil
}

// buildBroadCatalog loads all tenant products and prepares them for cross-category matching.
// Hoisted out of the rescue loop to eliminate the per-item N+1 pattern.
// shopID filters to products scoped to the shop (or shared via shop_id IS NULL).
func (s *SmartStockSetupService) buildBroadCatalog(tenantID, shopID uuid.UUID) ([]dbProduct, []matching.PreparedProduct) {
	allProducts, err := s.purchaseService.loadProducts(tenantID, &shopID)
	if err != nil {
		log.Printf("Smart Stock Setup: Failed to load all products for cross-category search: %v", err)
		return nil, nil
	}
	matchProducts := make([]matching.Product, len(allProducts))
	for i, p := range allProducts {
		bn := p.BrandName
		if bn == "" {
			bn = p.Name
		}
		matchProducts[i] = matching.Product{
			ID:                p.ID,
			Name:              p.Name,
			BrandName:         bn,
			DisplayName:       p.DisplayName,
			ExciseBrandName:   p.ExciseBrandName,
			ExciseDisplayName: p.ExciseDisplayName,
			Size:              p.Size,
			SizeML:            matching.ParseSizeML(p.Size),
		}
	}
	prepared := matching.PrepareProducts(matchProducts)
	return allProducts, prepared
}

// ============================================================================
// Master Brand Data (UP Excise / State Excise)
// ============================================================================

// loadMasterBrands loads official brand+MRP reference data for a given size and state
func (s *SmartStockSetupService) loadMasterBrands(sizeML int, state string) []models.MasterBrandInfo {
	if state == "" {
		state = "UP"
	}

	// sizeML=0 is the "all sizes" path — used by OrphansAutofix and any caller
	// that needs to cross-size match (e.g. linking 180ML orphans to their
	// 750ML master variants). Previously this returned nil unconditionally,
	// which silently broke the bulk autofix — 65 orphans, 0 links.
	var brands []models.MasterBrandInfo
	var err error
	if sizeML == 0 {
		err = s.db.Raw(`
			SELECT bv.id::text as variant_id, sb.id::text as brand_id, sb.name as brand_name,
				COALESCE(NULLIF(sb.display_name, ''), sb.name) as display_name,
				sb.display_name_bold_start as display_name_bold_start,
				sb.display_name_bold_length as display_name_bold_length,
				bv.size, bv.mrp, COALESCE(bc.name, '') as category,
				COALESCE(bv.category_id::text, '') as category_id,
				COALESCE(bc.sub_type, '') as sub_type,
				COALESCE(bv.state, 'UP') as state,
				COALESCE(array_to_string(sb.meta_keywords, '|'), '') as meta_keywords_csv
			FROM brand_variants bv
			JOIN saas_brands sb ON bv.brand_id = sb.id
			LEFT JOIN brand_categories bc ON bv.category_id = bc.id
			WHERE bv.deleted_at IS NULL AND sb.deleted_at IS NULL
			  AND COALESCE(bv.state, 'UP') = ?
			ORDER BY sb.name ASC
		`, state).Scan(&brands).Error
		if err == nil {
			return brands
		}
		log.Printf("Smart Stock Setup: Failed to load all-sizes master brands: %v", err)
		return nil
	}

	sizeStr := fmt.Sprintf("%dML", sizeML)

	err = s.db.Raw(`
		SELECT bv.id::text as variant_id, sb.id::text as brand_id, sb.name as brand_name,
			COALESCE(NULLIF(sb.display_name, ''), sb.name) as display_name,
			sb.display_name_bold_start as display_name_bold_start,
			sb.display_name_bold_length as display_name_bold_length,
			bv.size, bv.mrp, COALESCE(bc.name, '') as category,
			COALESCE(bv.category_id::text, '') as category_id,
			COALESCE(bc.sub_type, '') as sub_type,
			COALESCE(bv.state, 'UP') as state
		FROM brand_variants bv
		JOIN saas_brands sb ON bv.brand_id = sb.id
		LEFT JOIN brand_categories bc ON bv.category_id = bc.id
		WHERE bv.deleted_at IS NULL AND sb.deleted_at IS NULL
		  AND UPPER(bv.size) = UPPER(?)
		  AND COALESCE(bv.state, 'UP') = ?
		ORDER BY sb.name ASC
	`, sizeStr, state).Scan(&brands).Error

	if err != nil {
		log.Printf("Smart Stock Setup: Failed to load master brands: %v", err)
		return nil
	}
	return brands
}

// getTenantState returns the state code for a tenant (defaults to "UP")
func (s *SmartStockSetupService) getTenantState(tenantID uuid.UUID) string {
	var state struct{ State string }
	err := s.db.Table("tenants").Select("COALESCE(state, 'UP') as state").
		Where("id = ?", tenantID).Scan(&state).Error
	if err != nil || state.State == "" {
		return "UP"
	}
	return state.State
}

// scoreMasterBrand computes a match score between OCR text and a master brand record.
// Uses the max of Levenshtein (brand and display) and distinctive-token Jaccard,
// plus an MRP-proximity boost. Returns (score, hasDistinctiveTokenMatch).
//
// Rationale: Levenshtein alone misses cases like "1965 Ram" vs "1965 SPIRIT OF VICTORY
// PREMIUM XXX RUM" (~0.28 sim), even though "1965" is a strong distinctive token.
// Token-overlap with the stockSetupGenericWords filter catches it.
// initialsMatchScore handles the common Indian-liquor-register shorthand
// where shopkeepers write a brand name as its word-initials plus one or two
// distinctive tokens. Examples that previously failed:
//
//	"M M jun"   → "M2 Magic Moments Jamun"        (MM → Magic Moments, jun ≈ jamun)
//	"r s berri" → "Royal Stag Barrel Select ..."  (RS → Royal Stag, berri ≈ barrel)
//	"j d black" → "Jack Daniel's No.7 Tennessee"  (JD → Jack Daniel's, black context)
//	"8 pm rare" → "8 PM Special Rare Whisky"      (8 PM → 8 PM, rare → rare)
//
// Why the main scorer misses these: it filters out tokens <4 chars as
// "generic" and whole-string Levenshtein between "m m jun" and "m2 magic
// moments jamun" is too low. This helper rescues that case by building an
// abbreviation from the ≤2-char OCR tokens (M, M, …) and checking whether
// that abbreviation is a prefix of the master brand's word-initials
// (M from Magic, M from Moments, J from Jamun → MMJ; "MM" is a prefix of MMJ).
//
// Returns a score in [0, 1]:
//   - 0.85 when abbreviation matches AND every long OCR token prefix-matches
//     some master token (the "jun"→"jamun" case) — strong evidence.
//   - 0.55 when abbreviation matches but long-token check is weak — enough
//     to clear the 0.55 acceptance threshold but still tentative.
//   - 0.0 when abbreviation can't be identified or doesn't match.
func initialsMatchScore(ocrLower string, mb *models.MasterBrandInfo) float64 {
	ocrTokens := strings.Fields(ocrLower)
	if len(ocrTokens) < 2 {
		return 0
	}

	// Bucket OCR tokens by length. Short tokens (≤2 runes) are treated as
	// first-letter abbreviations; longer ones still need to match the
	// corresponding master token directly.
	// Period-joined initials ("R.S Barrel", "M.M. Jun") get split on periods
	// first — each dotted segment becomes its own first-letter abbreviation.
	// Without this, "r.s" stays as a 3-char token and falls into the long
	// bucket where it won't Levenshtein-match any real master token.
	var abbrev []byte
	var longTokens []string
	for _, t := range ocrTokens {
		// If the token contains an embedded period like "r.s" or "m.m.",
		// split by period and treat each dotted segment as its own piece.
		parts := strings.Split(t, ".")
		for _, p := range parts {
			trimmed := strings.Trim(p, ".,;:-/")
			if trimmed == "" {
				continue
			}
			if len(trimmed) <= 2 {
				abbrev = append(abbrev, trimmed[0])
			} else {
				longTokens = append(longTokens, trimmed)
			}
		}
	}
	// Need at least 2 abbreviated letters — otherwise this isn't an
	// initials-style OCR (a single letter is too ambiguous: "M whisky"
	// would match every whisky brand starting with M).
	if len(abbrev) < 2 {
		return 0
	}

	// Try to align abbrev against each candidate master-name form. We test
	// multiple forms so a master with a bold-key shorter than the full name
	// still has a chance (e.g., display="Blenders Pride" vs full name
	// "SEAGRAM'S BLENDERS PRIDE RARE PREMIUM WHISKY").
	candidates := []string{mb.BrandName}
	if mb.DisplayName != "" {
		candidates = append(candidates, mb.DisplayName)
	}
	if bold := extractBoldPortion(mb.DisplayName, mb.DisplayNameBoldStart, mb.DisplayNameBoldLength); bold != "" {
		candidates = append(candidates, bold)
	}

	bestAbbrevScore := 0.0
	bestLongHit := 0
	bestLongNeed := len(longTokens)
	for _, form := range candidates {
		master := strings.Fields(strings.ToLower(form))
		if len(master) == 0 {
			continue
		}
		// Build the master's initials — one byte per word. "M2 Magic Moments
		// Jamun" → "mmmj" (keeping the "m" from "m2" because users often
		// drop the digit when abbreviating).
		masterInits := make([]byte, 0, len(master))
		for _, mt := range master {
			if mt == "" || stockSetupGenericWords[mt] {
				continue
			}
			masterInits = append(masterInits, mt[0])
		}
		if len(masterInits) < len(abbrev) {
			continue
		}
		// Abbrev must appear as a contiguous run of initials — typically at
		// the start of the non-generic initials, but allow anywhere so e.g.
		// "RS Barrel" → "royal stag barrel" matches RS in positions 0,1.
		found := false
		for start := 0; start+len(abbrev) <= len(masterInits); start++ {
			match := true
			for i := range abbrev {
				if masterInits[start+i] != abbrev[i] {
					match = false
					break
				}
			}
			if match {
				found = true
				break
			}
		}
		if !found {
			continue
		}

		// Abbreviation aligns. Now check long tokens: each long OCR token
		// should map to some master token via a loose similarity — not a
		// strict prefix because real shorthand like "berri" → "barrel" and
		// "jun" → "jamun" aren't prefixes of anything. The heuristic:
		// same first letter AND Levenshtein similarity ≥ 0.4.
		longHit := 0
		for _, lt := range longTokens {
			if len(lt) == 0 {
				continue
			}
			for _, mt := range master {
				if len(mt) == 0 || mt[0] != lt[0] {
					continue
				}
				// Prefix match first (cheap) — handles clean shorthand like
				// "mag" → "magic" or "royal" → "royal".
				if strings.HasPrefix(mt, lt) || strings.HasPrefix(lt, mt) {
					longHit++
					break
				}
				// Fallback: loose Levenshtein similarity. ≥0.4 accepts
				// "berri"↔"barrel" (0.5) and "jun"↔"jamun" (0.4) while
				// rejecting unrelated same-initial tokens like "rum"↔"red".
				if matching.StringSimilarity(lt, mt) >= 0.4 {
					longHit++
					break
				}
			}
		}
		if longHit > bestLongHit {
			bestLongHit = longHit
			bestAbbrevScore = 0.55
			if longHit == len(longTokens) && len(longTokens) > 0 {
				bestAbbrevScore = 0.85
			}
		} else if bestAbbrevScore == 0 {
			// First alignment with zero long tokens — still score it
			// conservatively so initials-only matches like pure "MM"
			// (no long context) can be considered, but cap at 0.50 so
			// they don't outscore genuine distinctive-token matches.
			if len(longTokens) == 0 {
				bestAbbrevScore = 0.50
			}
		}
	}
	_ = bestLongNeed // kept for future tuning; currently unused beyond the ratio above
	return bestAbbrevScore
}

// brandKeyTokens lowercases, splits on non-alphanumerics, and JOINS a short
// digit token with an immediately-following short alpha token so register
// brand keys survive tokenisation: "8 pm" → "8pm", "1 965" → "1965". Without
// this, scoreMasterBrand's distinctive-token loop (which skips tokens < 4
// chars) silently drops the single most distinctive Indian brand key — "8 PM"
// — so "8 PM Black Whisky" got no brand signal and lost to "Royal Black
// Reserve" purely on an exact MRP-proximity tie (chhotu job 28e26d08 row 6,
// 2026-05-16). The correct master "8 PM Premium Black Superior Whisky" WAS in
// the candidate set, just mis-ranked. v1.0.259.
func brandKeyTokens(s string) []string {
	raw := strings.FieldsFunc(strings.ToLower(s), func(r rune) bool {
		return !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'))
	})
	isDigits := func(w string) bool {
		if w == "" {
			return false
		}
		for _, r := range w {
			if r < '0' || r > '9' {
				return false
			}
		}
		return true
	}
	// Units we must NOT fuse onto a number — "750"+"ml" must stay a size, not
	// become a fake distinctive key "750ml".
	unit := map[string]bool{"ml": true, "l": true, "ltr": true, "cl": true,
		"g": true, "kg": true, "oz": true, "btl": true, "pc": true, "pcs": true}
	out := make([]string, 0, len(raw))
	for i := 0; i < len(raw); i++ {
		w := raw[i]
		// digit head (1-4) + short alpha tail (≤3, e.g. "pm","yo") → one key.
		if len(w) <= 4 && isDigits(w) && i+1 < len(raw) {
			nx := raw[i+1]
			if len(nx) <= 3 && !isDigits(nx) && !unit[nx] {
				out = append(out, w+nx)
				i++
				continue
			}
		}
		out = append(out, w)
	}
	return out
}

// isAlnumMix: contains BOTH a letter and a digit (e.g. "8pm", "b7"). A
// short token only counts as a distinctive brand key when it's such a mix —
// pure-digit tokens ("750", "250", "1965") are sizes/prices/years, never
// brand identity, so they must NOT drive a match.
func isAlnumMix(w string) bool {
	hasD, hasL := false, false
	for _, r := range w {
		switch {
		case r >= '0' && r <= '9':
			hasD = true
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z':
			hasL = true
		}
	}
	return hasD && hasL
}

func scoreMasterBrand(ocrLower string, mb *models.MasterBrandInfo, rate float64) (float64, bool) {
	// Levenshtein: prefer the best of brand_name vs display_name (display often cleaner).
	// The BOLD KEY (catalog admin's chosen short identifier) is the strongest signal
	// because handwritten registers usually carry the short form, not the full name.
	// If the OCR is "bomb sofy" and the catalog has display "Bombay Sapphire Gin"
	// with bold "Bombay Sapphire", scoring "bomb sofy" against the bold portion
	// produces a much stronger match than against the full name.
	lev := matching.StringSimilarity(ocrLower, strings.ToLower(mb.BrandName))
	if mb.DisplayName != "" {
		if d := matching.StringSimilarity(ocrLower, strings.ToLower(mb.DisplayName)); d > lev {
			lev = d
		}
	}
	if bold := extractBoldPortion(mb.DisplayName, mb.DisplayNameBoldStart, mb.DisplayNameBoldLength); bold != "" {
		if b := matching.StringSimilarity(ocrLower, strings.ToLower(bold)); b > lev {
			lev = b
		}
	}

	// v1.0.202 — meta_keywords / synonyms scoring. Each keyword is treated as
	// an alternative name form: the score is the BEST of (a) Levenshtein vs
	// the keyword, (b) substring containment either way. Empty when the
	// brand has no meta_keywords. Concrete win: typing "MCD" against "Mc
	// Dowells" levenshteins low (0.20) but the meta_keywords list contains
	// "MCD" → score = 1.0 here, promoted to top of the search dropdown.
	hasKeywordHit := false
	if mb.MetaKeywordsCSV != "" {
		for _, kw := range strings.Split(mb.MetaKeywordsCSV, "|") {
			kw = strings.TrimSpace(strings.ToLower(kw))
			if len(kw) < 2 {
				continue
			}
			ks := matching.StringSimilarity(ocrLower, kw)
			if ks > lev {
				lev = ks
			}
			// Substring containment — "MCD" inside "MCD ORIGINAL" or vice versa.
			if strings.Contains(ocrLower, kw) || strings.Contains(kw, ocrLower) {
				if 0.85 > lev {
					lev = 0.85
				}
				hasKeywordHit = true
			}
			if ks >= 0.85 {
				hasKeywordHit = true
			}
		}
	}

	// Distinctive-token overlap. Only tokens of length >= 4 that aren't generic count.
	// Include the bold-key portion so its tokens get a fair shot in token overlap too.
	// v1.0.259 — brandKeyTokens (not strings.Fields) so "8 pm" → "8pm" on
	// BOTH sides, and digit-bearing short keys (8pm, b7, 100, 1965) count as
	// distinctive. Pure short alpha noise ("pm","no","co") is still skipped.
	ocrTokens := brandKeyTokens(ocrLower)
	mbText := strings.ToLower(mb.BrandName)
	if mb.DisplayName != "" {
		mbText += " " + strings.ToLower(mb.DisplayName)
	}
	if bold := extractBoldPortion(mb.DisplayName, mb.DisplayNameBoldStart, mb.DisplayNameBoldLength); bold != "" {
		mbText += " " + strings.ToLower(bold)
	}
	mbTokens := brandKeyTokens(mbText)

	distinctiveInOCR := 0
	distinctiveMatched := 0
	hasDistinctiveMatch := false
	seen := make(map[string]bool)
	for _, ot := range ocrTokens {
		if stockSetupGenericWords[ot] || (len(ot) < 4 && !isAlnumMix(ot)) {
			continue
		}
		if seen[ot] {
			continue
		}
		seen[ot] = true
		distinctiveInOCR++
		for _, mt := range mbTokens {
			if ot == mt || (len(ot) >= 4 && (strings.HasPrefix(mt, ot) || strings.HasPrefix(ot, mt))) {
				distinctiveMatched++
				hasDistinctiveMatch = true
				break
			}
		}
	}
	tokenScore := 0.0
	if distinctiveInOCR > 0 {
		tokenScore = float64(distinctiveMatched) / float64(distinctiveInOCR)
	}

	score := lev
	if tokenScore > score {
		score = tokenScore
	}

	// Initials-shorthand rescue — raises the score (and flips
	// hasDistinctiveMatch to true) when the OCR looks like "M M jun" and the
	// master's word-initials line up. Covers a large class of Indian
	// register shorthand the levenshtein/token path can't reach.
	initScore := initialsMatchScore(ocrLower, mb)
	if initScore > score {
		score = initScore
		hasDistinctiveMatch = true
	}
	// Period-heavy abbreviation boost — when the OCR query looks like
	// "R.S Barrel" / "M.M. Jun" (period-separated initials) AND the
	// initials path scored ≥ 0.55 against this master, add a small bonus
	// to the overall score. Without the bonus, a generic token-only hit
	// ("barrel" → matches 20 unrelated products at tokenScore=1.0) would
	// tie or beat the correct initials-matched answer. The bonus is scoped
	// to dotted queries only so it doesn't distort normal searches.
	if initScore >= 0.55 && strings.Contains(ocrLower, ".") {
		score += 0.25
		hasDistinctiveMatch = true
	}

	// Tiered MRP proximity adjustment — single source of truth shared with
	// buildAlternatives so master and DB candidates rank consistently.
	score += mrpProximityBonus(rate, mb.MRP)

	// Label-color guard — cap the score below the acceptance threshold when
	// source and master carry different label colors within the same brand
	// family. Without this, master-routing would silently rescue a Red↔Blue
	// swap and reintroduce the same bug the AI-index gate rejected.
	masterText := mb.BrandName
	if mb.DisplayName != "" {
		masterText += " " + mb.DisplayName
	}
	if hasLabelColorConflict(ocrLower, masterText) {
		if score > 0.3 {
			score = 0.3
		}
		hasDistinctiveMatch = false
	}

	// Family-root gate — when the OCR source carries BOTH a label-color token
	// AND a family-root token (e.g. "Johnnie Walker Black Label" has color
	// "black" + root "walker"/"johnnie"), require the candidate to share at
	// least one family root. Fixes the "JW Black Label" → "Black & White
	// Celebration" case where both contain "black" (same color, so the
	// label-color guard above doesn't trigger) but the families are unrelated
	// (walker ≠ celebration). Activates only when source carries a color token
	// so normal non-label-series searches aren't affected.
	if labelColorIn(ocrLower) != "" {
		srcRoots := familyRootTokens(ocrLower)
		if len(srcRoots) > 0 {
			candRoots := familyRootTokens(masterText)
			shared := false
			for t := range srcRoots {
				if _, ok := candRoots[t]; ok {
					shared = true
					break
				}
			}
			if !shared {
				if score > 0.30 {
					score = 0.30
				}
				hasDistinctiveMatch = false
			}
		}
	}

	// v1.0.202 — a meta_keywords hit (synonym match) counts as a distinctive
	// match, so the dropdown can surface synonym-only matches above the
	// 0.55 Levenshtein-only threshold. Without this, "MCD" → "Mc Dowells"
	// would still need a strong levenshtein hit to clear the gate, even
	// though the synonym match is unambiguous.
	if hasKeywordHit {
		hasDistinctiveMatch = true
	}

	return score, hasDistinctiveMatch
}

// sizeMLRegex captures e.g. "750 ml", "180ML", "180 ML (Quarter)" — the leading word boundary
// avoids false positives like "ML" appearing inside other tokens.
var sizeMLRegex = regexp.MustCompile(`(?i)\b(\d{2,4})\s*ml\b`)

// inferSizeMLFromName recovers a missing SizeML when the AI omitted the structured field
// but the brand/name string still contains the size literal.
func inferSizeMLFromName(name string) int {
	m := sizeMLRegex.FindStringSubmatch(name)
	if len(m) == 2 {
		v, _ := strconv.Atoi(m[1])
		return v
	}
	return 0
}

// findMasterBrand finds the best matching master brand for a given name, size, and rate.
// Accepts when Levenshtein OR distinctive-token match produces score >= 0.55.
// For token-only wins, requires at least one distinctive token (len >= 4) to match —
// prevents garbage matches on common short words.
func (s *SmartStockSetupService) findMasterBrand(name string, sizeML int, rate float64, masterBrands []models.MasterBrandInfo) *models.MasterBrandInfo {
	if len(masterBrands) == 0 || name == "" {
		return nil
	}

	nameLower := strings.ToLower(name)
	var bestMatch *models.MasterBrandInfo
	bestScore := 0.0
	bestHasDistinctive := false

	for i := range masterBrands {
		mb := &masterBrands[i]
		score, hasDist := scoreMasterBrand(nameLower, mb, rate)

		// Prefer matches with a distinctive-token hit when scores are close;
		// when scores are equal, prefer the shorter display name (cleaner).
		better := score > bestScore+0.01
		if !better && score >= bestScore-0.01 && hasDist && !bestHasDistinctive {
			better = true
		}
		if !better && score == bestScore && bestMatch != nil {
			// Tie-break: shorter display_name wins
			curLen := len(mb.DisplayName)
			if curLen == 0 {
				curLen = len(mb.BrandName)
			}
			bestLen := len(bestMatch.DisplayName)
			if bestLen == 0 {
				bestLen = len(bestMatch.BrandName)
			}
			if curLen > 0 && curLen < bestLen {
				better = true
			}
		}
		if better {
			bestScore = score
			bestMatch = mb
			bestHasDistinctive = hasDist
		}
	}

	if bestMatch == nil {
		return nil
	}
	// Accept: Levenshtein/combined score >= 0.55 OR distinctive-token match at >= 0.50
	if bestScore >= 0.55 || (bestHasDistinctive && bestScore >= 0.50) {
		return bestMatch
	}
	return nil
}

// enrichProductsWithInferredExcise mutates the products slice in-place to fill
// ExciseBrandName / ExciseDisplayName for any product whose saas_brand_id is empty.
// We fuzzy-match the product's name/display against the master catalog and copy
// the master's name + display when the match is confident (score >= 0.75 AND a
// distinctive token match). Also fills in ExciseDisplayName from shortenForDisplay
// when the DB has a long excise name but empty display_name.
//
// Called once per extraction after loadProducts. O(products × masters) in the worst
// case; acceptable since products ≈ 100 and masters ≈ 1000 for a single size.
func (s *SmartStockSetupService) enrichProductsWithInferredExcise(products []dbProduct, masterBrands []models.MasterBrandInfo) {
	if len(products) == 0 || len(masterBrands) == 0 {
		return
	}
	inferred, shortened := 0, 0
	for i := range products {
		p := &products[i]
		// Case 1: excise name is already linked — just ensure display is populated
		if p.ExciseBrandName != "" {
			if p.ExciseDisplayName == "" {
				p.ExciseDisplayName = shortenForDisplay(p.ExciseBrandName)
				shortened++
			}
			continue
		}
		// Case 2: no linkage — try to infer
		searchText := firstNonEmpty(p.DisplayName, p.BrandName, p.Name)
		if searchText == "" {
			continue
		}
		// Use the strict scoreMasterBrand directly (bypasses the ≥0.50 / ≥0.55 thresholds
		// in findMasterBrand) so we can require a tighter 0.75 for inference.
		var bestMatch *models.MasterBrandInfo
		bestScore := 0.0
		bestHasDistinctive := false
		searchLower := strings.ToLower(searchText)
		for j := range masterBrands {
			mb := &masterBrands[j]
			score, hasDist := scoreMasterBrand(searchLower, mb, p.MRP)
			if score > bestScore {
				bestScore = score
				bestMatch = mb
				bestHasDistinctive = hasDist
			}
		}
		if bestMatch != nil && bestScore >= 0.75 && bestHasDistinctive {
			p.ExciseBrandName = bestMatch.BrandName
			if bestMatch.DisplayName != "" {
				p.ExciseDisplayName = bestMatch.DisplayName
			} else {
				p.ExciseDisplayName = shortenForDisplay(bestMatch.BrandName)
			}
			inferred++
		}
	}
	if inferred > 0 || shortened > 0 {
		log.Printf("Smart Stock Setup: Enriched excise data — inferred %d, shortened %d (of %d products)",
			inferred, shortened, len(products))
	}
}

// findMasterBrandCandidates returns up to topN best-scoring master brand matches,
// used to populate MasterBrandSuggestions on auto_create items. Scoring is the same
// as findMasterBrand; the threshold is relaxed to 0.35 to show more options.
func (s *SmartStockSetupService) findMasterBrandCandidates(name string, sizeML int, rate float64, masterBrands []models.MasterBrandInfo, topN int) []MasterBrandSuggestion {
	if len(masterBrands) == 0 || name == "" || topN <= 0 {
		return nil
	}
	nameLower := strings.ToLower(name)

	type scored struct {
		mb       *models.MasterBrandInfo
		score    float64
		hasToken bool
	}
	candidates := make([]scored, 0, len(masterBrands))
	for i := range masterBrands {
		mb := &masterBrands[i]
		score, hasDist := scoreMasterBrand(nameLower, mb, rate)
		if score < 0.35 {
			continue
		}
		if !hasDist && score < 0.55 {
			// Levenshtein-only picks need a higher threshold to avoid noise
			continue
		}
		candidates = append(candidates, scored{mb: mb, score: score, hasToken: hasDist})
	}
	// Sort desc by score
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].score != candidates[j].score {
			return candidates[i].score > candidates[j].score
		}
		// Tie-break: shorter display name
		li := len(candidates[i].mb.DisplayName)
		if li == 0 {
			li = len(candidates[i].mb.BrandName)
		}
		lj := len(candidates[j].mb.DisplayName)
		if lj == 0 {
			lj = len(candidates[j].mb.BrandName)
		}
		return li < lj
	})
	if len(candidates) > topN {
		candidates = candidates[:topN]
	}
	out := make([]MasterBrandSuggestion, 0, len(candidates))
	for _, c := range candidates {
		dn := c.mb.DisplayName
		if dn == "" {
			dn = c.mb.BrandName
		}
		out = append(out, MasterBrandSuggestion{
			BrandID:               c.mb.BrandID,
			VariantID:             c.mb.VariantID,
			BrandName:             c.mb.BrandName,
			DisplayName:           dn,
			DisplayNameBoldStart:  c.mb.DisplayNameBoldStart,
			DisplayNameBoldLength: c.mb.DisplayNameBoldLength,
			Size:                  c.mb.Size,
			MRP:                   c.mb.MRP,
			Confidence:            c.score,
		})
	}
	return out
}

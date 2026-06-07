package services

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// ============================================================================
// AI Extraction Types (parsed from OpenAI/Gemini response for stock registers)
// ============================================================================

// StockRegisterExtractionResult is the raw AI extraction from register page images
type StockRegisterExtractionResult struct {
	ShopName   string                       `json:"shop_name"`
	PageSize   string                       `json:"page_size"`
	PageSizeML int                          `json:"page_size_ml"`
	Items      []ExtractedStockRegisterItem `json:"items"`
	// RowCountOnPage is the total visible rows on the source image (including
	// blank ones). Lets the Flutter review UI compute a Y-band for a given row
	// so "verify from image" can scroll the image to roughly that band.
	RowCountOnPage int `json:"row_count_on_page,omitempty"`
}

// UnmarshalJSON tolerates AI responses where matched_product_id arrives as
// a string ("0") instead of a number (0). Real incident 2026-05-23:
// chhotu 90ml (Nip) Stock Setup, Claude+Gemini+OpenAI all returned
// matched_product_id as a JSON string, default int parser rejected all 3,
// extractor returned 0 items, user saw misleading "No product entries
// found". Every other field uses default decoding via the alias-embed trick
// (no field-by-field copying — keeps additions to the struct working
// without further edits here).
func (e *ExtractedStockRegisterItem) UnmarshalJSON(b []byte) error {
	type alias ExtractedStockRegisterItem
	var aux struct {
		*alias
		MatchedProductIdx json.RawMessage `json:"matched_product_id"`
	}
	aux.alias = (*alias)(e)
	if err := json.Unmarshal(b, &aux); err != nil {
		return err
	}
	if len(aux.MatchedProductIdx) == 0 {
		return nil
	}
	s := strings.TrimSpace(string(aux.MatchedProductIdx))
	if s == "" || s == "null" {
		e.MatchedProductIdx = 0
		return nil
	}
	if len(s) >= 2 && s[0] == '"' && s[len(s)-1] == '"' {
		s = strings.TrimSpace(s[1 : len(s)-1])
	}
	if s == "" {
		e.MatchedProductIdx = 0
		return nil
	}
	if n, err := strconv.Atoi(s); err == nil {
		e.MatchedProductIdx = n
		return nil
	}
	if fv, err := strconv.ParseFloat(s, 64); err == nil {
		e.MatchedProductIdx = int(fv)
		return nil
	}
	// Unknown shape — treat as no-match rather than failing the whole row.
	e.MatchedProductIdx = 0
	return nil
}

// ExtractedStockRegisterItem is a single row extracted from a stock register
type ExtractedStockRegisterItem struct {
	RowNumber         int     `json:"row_number"`
	Brand             string  `json:"brand"`
	OfficialBrandName string  `json:"official_brand_name"` // AI-identified canonical name
	Category          string  `json:"category"`
	SizeText          string  `json:"size_text"`
	SizeML            int     `json:"size_ml"`
	Opening           int     `json:"opening"`
	Receipt           int     `json:"receipt"`
	Total             int     `json:"total"`
	Sale              int     `json:"sale"`
	Rate              float64 `json:"rate"`
	Amount            float64 `json:"amount"`
	Closing           int     `json:"closing"`
	Confidence        float64 `json:"confidence"`
	// FieldConfidence is per-field confidence (brand, opening, receipt, total,
	// sale, rate, amount). Returned natively by Claude; for Gemini/OpenAI we
	// spread the single Confidence value across fields. The Flutter review
	// screen highlights cells with confidence < 0.7 in amber so the user
	// knows exactly which value to verify.
	FieldConfidence   map[string]float64 `json:"field_confidence,omitempty"`
	MatchedProductIdx int                `json:"matched_product_id"` // 1-based index into product list (0 = no match)
	// PageNumber is the 1-based source image index. Set server-side in the image loop
	// (not from AI output) so validators can scope checks per-page and the Flutter review
	// UI can group rows under page headers and link back to the source image.
	PageNumber int `json:"page_number,omitempty"`
	// OriginalPrintedBrand is the preprinted brand name on a row where the shop
	// owner wrote over it with a different product (handwritten-wins rule). The
	// live `Brand` field holds the handwritten text; this field preserves what
	// the printed register said so the review UI can show "was: Monkey Shoulder"
	// and the user can spot register reassignments at a glance.
	OriginalPrintedBrand string `json:"original_printed_brand,omitempty"`
	// Source distinguishes rows extracted by the main pass from rows re-extracted
	// by the specialized handwritten pass ("main" | "handwritten_pass"). Not sent
	// to Flutter directly — surfaced via Source on SmartStockSetupExtractedItem.
	Source string `json:"source,omitempty"`
}

// ============================================================================
// Smart Stock Setup Response Types (returned to Flutter)
// ============================================================================

// SmartStockSetupResult is the top-level extraction response
type SmartStockSetupResult struct {
	SessionID        string                         `json:"session_id,omitempty"` // unique ID for this extraction session (links images, AI response, apply data)
	Status           string                         `json:"status"`              // success, partial, failed
	Message          string                         `json:"message"`
	DetectedShopName string                         `json:"detected_shop_name,omitempty"`
	StockColumn          string                         `json:"stock_column"`                        // "total", "closing", or "opening"
	SuggestedStockColumn string                         `json:"suggested_stock_column,omitempty"`
	Items            []SmartStockSetupExtractedItem `json:"items"`
	ProcessingDetails *SmartStockSetupProcessing    `json:"processing_details"`
	Validation       *SmartStockSetupValidation     `json:"validation"`
	FilterContext    *StockSetupFilterContext        `json:"filter_context,omitempty"`
	AllProducts      []StockSetupProductInfo         `json:"all_products,omitempty"`
	ImageURLs        []string                        `json:"image_urls,omitempty"`                 // saved register image URLs for approval review
	// PageRowCounts is the per-page row count (indexed by PageNumber-1). Lets the
	// Flutter review UI compute a Y-band for a given row so tapping a "verify"
	// button can scroll to roughly that area of the source image.
	PageRowCounts []int `json:"page_row_counts,omitempty"`
	// CoverageSummary (v1.0.114) reports per-page rescue activity so Flutter can
	// render banners like "Page 2: 18 of 23 rows recovered via re-scan — verify".
	// Empty when no pages needed rescue (the common 180/375ML case).
	CoverageSummary []PageCoverage `json:"coverage_summary,omitempty"`
	// Audit so the user can validate data hygiene without leaving the app:
	//  - OrphanProducts: tenant products with NULL saas_brand_id at the chosen
	//    size; these render as `Catalog:` instead of `Excise:` and benefit from
	//    a one-shot "link to master" action in Flutter.
	//  - MissingMasterBrands: OCR brands that didn't match anything in the
	//    master catalog at all — likely brands the regulator catalog doesn't
	//    yet contain. User can validate against their own list and request
	//    additions to master upstream.
	Audit *StockSetupAudit `json:"audit,omitempty"`
	// SizeMismatchSkippedPages reports photos whose detected page-size header
	// did not match the user-selected size — the rows from those photos were
	// dropped by the wrong-size filter. The Flutter review UI uses this to
	// render a clear banner (e.g. "Photo 2 was a 375ML register — re-upload
	// it as a 375ML setup") so users don't think the second photo failed to
	// scan. Empty when every uploaded photo matched the selected size.
	SizeMismatchSkippedPages []SizeMismatchSkippedPage `json:"size_mismatch_skipped_pages,omitempty"`
}

// SizeMismatchSkippedPage records a photo whose contents were the wrong size
// for this setup. PageNumber is 1-based and matches the upload order.
type SizeMismatchSkippedPage struct {
	PageNumber     int    `json:"page_number"`
	DetectedSizeML int    `json:"detected_size_ml"`
	DetectedSize   string `json:"detected_size,omitempty"`
	SkippedCount   int    `json:"skipped_count"`
}

// StockSetupAudit summarises data-hygiene gaps surfaced during extraction.
type StockSetupAudit struct {
	OrphanProducts      []OrphanTenantProduct `json:"orphan_products,omitempty"`
	MissingMasterBrands []string              `json:"missing_master_brands,omitempty"`
}

// OrphanTenantProduct identifies a tenant product whose saas_brand_id is NULL.
type OrphanTenantProduct struct {
	ProductID string  `json:"product_id"`
	Name      string  `json:"name"`
	Size      string  `json:"size,omitempty"`
	MRP       float64 `json:"mrp,omitempty"`
}

// StockSetupFilterContext describes the category+size scope used for extraction
type StockSetupFilterContext struct {
	CategoryID   string `json:"category_id,omitempty"`
	CategoryName string `json:"category_name,omitempty"`
	Size         string `json:"size,omitempty"`
	SizeML       int    `json:"size_ml,omitempty"`
	ProductCount int    `json:"product_count"`
}

// StockSetupProductInfo is a product in the scoped category+size for the frontend grid
type StockSetupProductInfo struct {
	ProductID    string  `json:"product_id"`
	Name         string  `json:"name"`
	BrandName    string  `json:"brand_name"`
	Size         string  `json:"size"`
	SizeML       int     `json:"size_ml"`
	MRP          float64 `json:"mrp"`
	SellingPrice float64 `json:"selling_price"`
	CurrentStock int     `json:"current_stock"`
}

// SmartStockSetupExtractedItem is an extracted register row enriched with product matching
type SmartStockSetupExtractedItem struct {
	// OCR-extracted values
	RowNumber int    `json:"row_number"`
	BrandName string `json:"brand_name"`
	// OriginalAIBrand is the AI's FIRST-GUESS brand text BEFORE matchAndEnrich
	// overwrote BrandName with the master display name. Flutter preserves this
	// across user edits + master picker swaps and sends it back on apply as
	// original_ai_brand so the alias-learning pipeline has a non-empty key
	// even when the user uses the catalog picker. Closes the v1.0.114 gap
	// where 4 master-pick rows on record c78bd84c produced 0 aliases.
	OriginalAIBrand string `json:"original_ai_brand,omitempty"`
	Size      string `json:"size"`
	SizeML    int    `json:"size_ml"`
	Category  string `json:"category"`
	// PageNumber is the 1-based source image index — surfaced so Flutter can group
	// the review list under "Page 1" / "Page 2" headers and link each header back
	// to its source image for visual verification.
	PageNumber int `json:"page_number,omitempty"`
	// OriginalPrintedBrand carries the preprinted name of a row whose brand was
	// handwritten-overwritten by the shop owner (handwritten-wins rule). The
	// live BrandName is the handwritten replacement; this field lets Flutter
	// render "was: <printed>" so the user can confirm the overwrite was intended.
	OriginalPrintedBrand string `json:"original_printed_brand,omitempty"`
	// Source tags how the row was extracted ("main" or "handwritten_pass"). Helps
	// the review UI show a small "re-extracted" badge and aids post-mortem audits.
	Source string `json:"source,omitempty"`

	// All register columns (for context in Flutter UI)
	Opening      int     `json:"opening"`
	Receipt      int     `json:"receipt"`
	Total        int     `json:"total"`
	Sale         int     `json:"sale"`
	Rate         float64 `json:"rate"`
	Amount       float64 `json:"amount"`
	ClosingStock int     `json:"closing_stock"`

	// FieldConfidence is the per-column extraction confidence from Claude
	// (or spread from overall confidence for Gemini/OpenAI). Flutter
	// highlights specific cells with confidence < 0.7 in amber.
	FieldConfidence map[string]float64 `json:"field_confidence,omitempty"`

	// SuggestedSale is the math-derived sale value (Opening + Receipt - ClosingStock)
	// emitted ONLY when both Opening and ClosingStock have field_confidence >= 0.9
	// and the derived value disagrees with the AI-extracted Sale. The Flutter
	// review row surfaces this as a tap-to-accept chip on the Sale cell so the
	// user can override AI's reading with the arithmetic-validated number when
	// the columns match the register footer. Zero / unset = no suggestion.
	SuggestedSale int `json:"suggested_sale,omitempty"`

	// The quantity that will be set as stock (based on stock_column choice)
	StockQuantity int `json:"stock_quantity"`

	// Product matching result
	ProductID                *string `json:"product_id,omitempty"`
	MatchedBrandName              string  `json:"matched_brand_name,omitempty"`                 // Kept for backwards compat — equals MatchedDisplayName
	MatchedDisplayName            string  `json:"matched_display_name,omitempty"`               // Short clean name (e.g. "Magic Moments Vodka")
	MatchedDisplayNameBoldStart   *int    `json:"matched_display_name_bold_start,omitempty"`    // 0-indexed start of bold range inside MatchedDisplayName
	MatchedDisplayNameBoldLength  *int    `json:"matched_display_name_bold_length,omitempty"`   // length of bold range — Flutter uses these to render the catalog admin's chosen distinctive identifier in bold
	MatchedFullName               string  `json:"matched_full_name,omitempty"`                  // Full DB name (e.g. "M2 Magic Moments Superior Vodka - 180ml")
	MatchedExciseBrandName        string  `json:"matched_excise_brand_name,omitempty"`          // Authoritative name from saas_brands (excise master catalog)
	MatchedExciseDisplayName      string  `json:"matched_excise_display_name,omitempty"`        // Authoritative short-form excise name
	MatchConfidence               float64 `json:"match_confidence"`
	Status                        string  `json:"status"` // matched, low_confidence, ambiguous, not_found

	// MasterMRP / MasterVariantID — the authoritative price+variant from the
	// master catalog at the item's size. Surfaced so the review UI can show
	// "master ₹X" alongside the tenant MRP and offer a one-tap "use master"
	// correction. Empty when no master variant exists at this size.
	MasterMRP       float64 `json:"master_mrp,omitempty"`
	MasterVariantID string  `json:"master_variant_id,omitempty"`

	// SwapCandidateRow points to the register row this one likely swapped values
	// with (set by Flag 11b row-drift detector). Non-zero RowNumber means the
	// review UI should render a "Swap opening with row N" action chip.
	SwapCandidateRow int `json:"swap_candidate_row,omitempty"`

	// AI-identified brand name (canonical)
	OfficialBrandName string `json:"official_brand_name,omitempty"`

	// Auto-creation fields
	AutoCreated      bool    `json:"auto_created"`
	CreatedBrandID   *string `json:"created_brand_id,omitempty"`
	CreatedProductID *string `json:"created_product_id,omitempty"`
	CreationStatus   string  `json:"creation_status,omitempty"` // "created", "existing_brand_new_product", ""

	// Current stock in DB (for comparison: "Current: 48 → Will set to: 60")
	CurrentStock *int `json:"current_stock,omitempty"`

	// For ambiguous matches — Flutter shows picker popup
	AlternativeMatches []AlternativeMatch `json:"alternative_matches,omitempty"`
	BrandCandidates    []BrandCandidate   `json:"brand_candidates,omitempty"`

	// For auto_create items — dropdown of master-catalog suggestions the user can pick from
	// instead of typing the brand name. Populated when the OCR text partially resolves to
	// one or more entries in saas_brands (e.g. "1965 Ram" → 10 "1965 Spirit of Victory" variants).
	MasterBrandSuggestions []MasterBrandSuggestion `json:"master_brand_suggestions,omitempty"`

	// Review flags — Flutter shows popup for user to confirm/edit
	NeedsReview  bool   `json:"needs_review"`            // true = show review popup in Flutter
	ReviewReason string `json:"review_reason,omitempty"` // why this item needs review

	Warnings []string `json:"warnings,omitempty"`

	// v1.0.125 — per-shop learned rate hint. When the user has corrected this
	// product's rate before at this shop (in shop_product_rates), surface the
	// last-corrected value + correction count so the Flutter review row can
	// render "Your shop's rate last time: ₹X (corrected N times)" beside the
	// rate cell. Helps the user spot when the AI re-extracted a wrong rate
	// they've already fixed previously, without forcing them to remember the
	// learned rate from prior sessions.
	LearnedShopRate            float64 `json:"learned_shop_rate,omitempty"`
	LearnedShopRateOccurrences int     `json:"learned_shop_rate_occurrences,omitempty"`

	// variantRejected is an internal flag (not serialized) set when matchAndEnrich
	// rejected a fuzzy match via the variant/distinguisher guard. The cross-category
	// rescue loop reads this to skip items that were *deliberately* rejected, so it
	// doesn't re-match them to the same wrong product.
	variantRejected bool `json:"-"`

	// CellDoubts (v1.0.185 Track S5) — per-cell doubts the extractor has on this
	// row. Each entry is one cell where confidence is below the auto-trust floor
	// or arithmetic disagrees. Drives the Flutter doubt-popup walker
	// (StockSetupDoubtModal) before the review screen so the operator confirms
	// or corrects each one ONCE, then it's captured into ocr_digit_corrections
	// (and the alias / shop-rate corpora) and silently auto-fixed in every
	// future extraction at this shop. Mirror of Smart Sale's CellDoubts.
	CellDoubts []StockSetupCellDoubt `json:"cell_doubts,omitempty"`
}

// StockSetupCellDoubt — v1.0.185 Track S5. One cell-level doubt produced by
// the Stock Setup invariant gate or low-confidence detector.
type StockSetupCellDoubt struct {
	// Field: which cell triggered the doubt — "brand" | "opening" | "receipt"
	// | "total" | "closing" | "rate" | "amount" | "name".
	Field string `json:"field"`
	// Rule: which detector fired — "low_confidence" | "math_disagree" |
	// "brand_no_match" | "ambiguous_match" | "rate_outlier" | "mrp_doubt".
	Rule string `json:"rule"`
	// AIValueInt / AIValueFloat / AIValueText — what the extractor read.
	// One of the three is set based on the field type; the others stay zero.
	AIValueInt   *int     `json:"ai_value_int,omitempty"`
	AIValueFloat *float64 `json:"ai_value_float,omitempty"`
	AIValueText  string   `json:"ai_value_text,omitempty"`
	// SuggestedInt / SuggestedFloat / SuggestedText — the system's best guess
	// the operator can one-tap accept. Nil when no clean suggestion is
	// available (operator must type).
	SuggestedInt   *int     `json:"suggested_int,omitempty"`
	SuggestedFloat *float64 `json:"suggested_float,omitempty"`
	SuggestedText  string   `json:"suggested_text,omitempty"`
	// Confidence in [Suggested*] (0-1). Below STOCK_SETUP_INVARIANT_AUTOFIX_CONF
	// (default 0.85) the doubt goes to the popup queue; at/above that floor
	// the backend already auto-fixed (and emits the entry as informational
	// with AutoFixed=true).
	Confidence float64 `json:"confidence"`
	// HumanText — operator-facing one-liner: "Brand 'Royal Stag Premium': we
	// found 2 matches with similar names. Tap to confirm which one."
	HumanText string `json:"human_text"`
	// AutoFixed — true when the backend already wrote the suggestion to the
	// row; informational only (popup queue skips these).
	AutoFixed bool `json:"auto_fixed,omitempty"`
}

// BrandCandidate is a potential brand match for review
type BrandCandidate struct {
	BrandID    string  `json:"brand_id"`
	BrandName  string  `json:"brand_name"`
	Similarity float64 `json:"similarity"`
}

// MasterBrandSuggestion is a pick-list entry from the UP Excise master catalog
// offered to the user when no tenant product matches. Lets Flutter render a
// dropdown of authoritative brand names instead of forcing free-text entry.
type MasterBrandSuggestion struct {
	BrandID               string  `json:"brand_id"`
	VariantID             string  `json:"variant_id,omitempty"`               // Master variant id at the searched size — lets the picker submit a saas_variant_id linkage
	BrandName             string  `json:"brand_name"`                         // Official excise name (e.g. "OLD MONK THE LEGEND RUM VERY OLD Vatted")
	DisplayName           string  `json:"display_name"`                       // Short form (e.g. "Old Monk The Legend Rum")
	DisplayNameBoldStart  *int    `json:"display_name_bold_start,omitempty"`  // 0-indexed start of bold range inside DisplayName
	DisplayNameBoldLength *int    `json:"display_name_bold_length,omitempty"` // length of bold range
	Size                  string  `json:"size,omitempty"`                     // Master variant size (echoes the requested size when filter matched)
	MRP                   float64 `json:"mrp,omitempty"`
	Confidence            float64 `json:"confidence"` // 0-1 — how closely the OCR text matched this entry
}

// PageCoverage (v1.0.114) describes per-page extraction recovery. Emitted only
// when at least one page needed rescue, so Flutter can show the user where the
// AI struggled and what got recovered.
type PageCoverage struct {
	PageNumber       int    `json:"page_number"`
	Expected         int    `json:"expected"`           // OCR-claimed RowCountOnPage (or max(row_number) fallback)
	ActualBefore     int    `json:"actual_before"`      // rows before page-rescue ran
	ActualAfter      int    `json:"actual_after"`       // rows after page-rescue + handwritten-pass
	RescueTriggered  bool   `json:"rescue_triggered"`
	RecoveredVia     string `json:"recovered_via,omitempty"` // "page_rescue", "handwritten_pass", or both
}

// SmartStockSetupProcessing holds timing metrics
type SmartStockSetupProcessing struct {
	OCRTimeMs       int64  `json:"ocr_time_ms"`
	MatchingTimeMs  int64  `json:"matching_time_ms"`
	TotalTimeMs     int64  `json:"total_time_ms"`
	ImagesProcessed int    `json:"images_processed"`
	AIModel         string `json:"ai_model"`
}

// SmartStockSetupValidation summarizes extraction quality
type SmartStockSetupValidation struct {
	TotalItems         int      `json:"total_items"`
	MatchedItems       int      `json:"matched_items"`
	LowConfidenceItems int      `json:"low_confidence_items"`
	NotFoundItems      int      `json:"not_found_items"`
	AutoCreatedItems   int      `json:"auto_created_items"`
	Warnings           []string `json:"warnings"`
	AverageConfidence  float64  `json:"average_confidence"`
	QualityWarning     string   `json:"quality_warning,omitempty"`
	LowQualityImages   []int   `json:"low_quality_images,omitempty"`
	FirstSetup         bool     `json:"first_setup,omitempty"`
}

// ============================================================================
// Apply (confirm) types
// ============================================================================

// SmartStockSetupApplyRequest is the JSON body for the apply endpoint
type SmartStockSetupApplyRequest struct {
	SessionID   string                     `json:"session_id"`  // links to extraction session for training data
	ShopID      string                     `json:"shop_id" binding:"required"`
	Items       []SmartStockSetupApplyItem `json:"items" binding:"required,min=1"`
	Notes       string                     `json:"notes"`
	CategoryID  string                     `json:"category_id"`  // optional: cleanup unused products in this scope
	Size        string                     `json:"size"`         // optional: cleanup unused products in this scope
	ImageURLs   []string                   `json:"image_urls"`   // register images for approval review
	StockColumn string                     `json:"stock_column"` // which register column the quantity came from: "opening", "closing", "total"
}

// SmartStockSetupApplyItem is a single product to set stock for
type SmartStockSetupApplyItem struct {
	ProductID string `json:"product_id"` // empty for auto_create items (deferred creation)
	Quantity  int    `json:"quantity"`
	BrandName string `json:"brand_name"` // for audit trail
	Size      string `json:"size"`       // for audit trail
	// Deferred creation metadata (for items without product_id)
	OfficialBrandName string  `json:"official_brand_name,omitempty"`
	CategoryName      string  `json:"category_name,omitempty"`
	Rate              float64 `json:"rate,omitempty"`
	MRP               float64 `json:"mrp,omitempty"`               // User-edited MRP to update on product
	EditedName        string  `json:"edited_name,omitempty"`       // User-edited product name to update
	// Audit trail — original register column values, preserved for historical records.
	// If the client doesn't send these, they default to 0 (legacy behaviour).
	OpeningStock int `json:"opening_stock,omitempty"`
	Receipt      int `json:"receipt,omitempty"`
	Sale         int `json:"sale,omitempty"`
	ClosingStock int `json:"closing_stock,omitempty"`
	// Alias learning fields
	OCRText           string  `json:"ocr_text,omitempty"`          // original OCR text for alias learning
	WasCorrected      bool    `json:"was_corrected,omitempty"`     // true if user changed the product from AI suggestion
	OriginalProductID string  `json:"original_product_id,omitempty"` // AI's original suggestion before user correction
	// v1.0.115: AI's first-guess brand text BEFORE the user used the master picker.
	// Picker swap overwrites BrandName with the picked master's name, so without
	// this, alias learning has no key to attach to (ocr_text is also empty for
	// picker rows because the swap UI doesn't carry the AI text forward). The
	// 4 master-pick rows on record c78bd84c (JOHNNIE WALKER GOLD LABEL et al)
	// produced zero aliases because of this gap.
	OriginalAIBrand string `json:"original_ai_brand,omitempty"`
	// Master-catalog linkage when the client KNOWS which master the item is — set
	// by the inline catalog picker on the Add-Missing UI. When non-empty, the
	// apply pipeline trusts these IDs verbatim and skips its own fuzzy resolution
	// for this item, so manually-picked items always come out linked correctly.
	SaasBrandID   string `json:"saas_brand_id,omitempty"`
	SaasVariantID string `json:"saas_variant_id,omitempty"`
	// AI telemetry echoed back by the client so the audit blob captures what
	// the extractor actually thought of each cell. The extractor side already
	// produces these on SmartStockSetupExtractedItem; the client just relays
	// them here unchanged. Empty = legacy client.
	FieldConfidence map[string]float64 `json:"field_confidence,omitempty"`
	RowNumber       int                `json:"row_number,omitempty"`
	PageNumber      int                `json:"page_number,omitempty"`

	// v1.0.133 — Original-AI numeric values, echoed by the client BEFORE user
	// edits, so the apply path can compute (raw, corrected) pairs for the
	// per-shop digit-handwriting learning corpus. Each is a string so "" /
	// nil distinguishes "client didn't echo" from "AI extracted 0". Stock
	// Setup writes these into ocr_digit_corrections via captureDigitCorrections.
	OriginalAIQuantity     *int     `json:"original_ai_quantity,omitempty"`
	OriginalAIOpening      *int     `json:"original_ai_opening,omitempty"`
	OriginalAIReceipt      *int     `json:"original_ai_receipt,omitempty"`
	OriginalAISale         *int     `json:"original_ai_sale,omitempty"`
	OriginalAIClosing      *int     `json:"original_ai_closing,omitempty"`
	OriginalAIRate         *float64 `json:"original_ai_rate,omitempty"`
	OriginalAIAmount       *float64 `json:"original_ai_amount,omitempty"`

	// v1.0.243 — Brand-image verification carriers. Each row must be
	// photo-verified before apply (unless SMART_STOCK_SETUP_REQUIRE_IMAGE=0).
	// Populated by Flutter from /stocks/smart-setup/verify-row response.
	VerifiedImageURL string  `json:"verified_image_url,omitempty"`
	GeminiConfidence float64 `json:"gemini_confidence,omitempty"`
	GeminiAgreed     *bool   `json:"gemini_agreed,omitempty"`
	VerifiedViaImage bool    `json:"verified_via_image,omitempty"`

	// v1.0.244 — Two-photo verification (Front + Back). Apply gate now
	// requires BOTH faces to be verified (unless legacy single-photo
	// VerifiedViaImage is set — backward compat with v1.0.243 clients).
	// Back-face Gemini call extracts MRP from the back label; operator can
	// tap a chip in the Edit sheet to apply that MRP. Never auto-applies.
	FrontImageURL         string  `json:"front_image_url,omitempty"`
	BackImageURL          string  `json:"back_image_url,omitempty"`
	VerifiedViaImageFront bool    `json:"verified_via_image_front,omitempty"`
	VerifiedViaImageBack  bool    `json:"verified_via_image_back,omitempty"`
	BackImageMRP          float64 `json:"back_image_mrp,omitempty"`

	// v1.0.291 — Set to true by Flutter ONLY when the row was visible on the
	// AI Stock Setup review screen at the moment the operator tapped "Set
	// Opening Stock". That act IS the vouching gesture: the operator looked
	// at this row (even if the AI's brand name is garbled OCR) and chose to
	// save it. Counted as a 5th vouching signal by shouldRejectUnreadableAutoCreate
	// alongside master_link / user_corrected / has_photo / operator-authored.
	//
	// Re-extraction, admin-direct auto-apply, and any other path that does
	// NOT pass through the review screen must leave this false (omitempty
	// drops it) so the anti-phantom gate keeps protecting unattended paths.
	//
	// Persisted into raw_ai_extraction so the approve-time gate (deferred
	// product creation, ApproveStockSetup) honors the same vouch.
	OperatorVouchedAtSubmit bool `json:"operator_vouched_at_submit,omitempty"`
}

// UnverifiedRowsError is returned by ApplyStockSetup when one or more
// rows lack photo verification AND SMART_STOCK_SETUP_REQUIRE_IMAGE != "0".
// The handler converts this into a 422 with a structured envelope so
// Flutter can scroll the operator to the offending rows.
type UnverifiedRowsError struct {
	UnverifiedCount int
	RejectedRows    []UnverifiedRow
}

type UnverifiedRow struct {
	RowNumber int    `json:"row_number"`
	BrandName string `json:"brand_name"`
	Size      string `json:"size,omitempty"`
	Reason    string `json:"reason"`
	// v1.0.244 — which face is missing: "front", "back", or "both".
	Face string `json:"face,omitempty"`
}

func (e *UnverifiedRowsError) Error() string {
	return fmt.Sprintf("%d row(s) still need photo verification", e.UnverifiedCount)
}

// SmartStockSetupApplyResult is the response after applying stock
type SmartStockSetupApplyResult struct {
	Status        string   `json:"status"` // success, partial, failed, pending_approval
	Message       string   `json:"message"`
	ItemsApplied  int      `json:"items_applied"`
	ItemsFailed   int      `json:"items_failed"`
	ItemsReceived int      `json:"items_received"` // how many items Flutter sent (for traceability)
	CleanedUp     int      `json:"cleaned_up"`     // unused products deactivated
	RecordID      *string  `json:"record_id,omitempty"` // stock setup record ID for approval tracking
	Errors        []string `json:"errors,omitempty"`
	// v1.0.248 — Soft photo-audit. When rows were applied without front/back
	// verification, this lists them so Flutter can surface a CTA: "5 products
	// still need photos — go to inventory to add them". The apply still
	// succeeds; this is informational so the operator knows to follow up.
	PhotoAuditMissing []UnverifiedRow `json:"photo_audit_missing,omitempty"`
	// v1.0.283 — rows the anti-phantom gate refused to auto-create because
	// they were unreadable OCR garbage (no catalog match + low AI confidence
	// + no photo + operator never touched). NOT saved as products; listed
	// here so the operator knows exactly what to re-photograph or pick from
	// the catalog (honest contract — no silent drop, v1.0.279).
	RejectedUnreadable []UnverifiedRow `json:"rejected_unreadable,omitempty"`
	// v1.0.396 — apply-time COVERAGE CHECK. Items the original scan extracted
	// (opening > 0, same size) that never appeared in this submission — i.e.
	// they were silently left out of the apply request (operator overlooked a
	// low-qty row, or a client display collapsed it). Mirrors the "no silent
	// drop" contract: surfaced, never lost. Root-caused from the Malsaii
	// "8 PM Black 375 (opening 2) quietly missing" incident (2026-06-06).
	CoverageMissing []UnverifiedRow `json:"coverage_missing,omitempty"`
}

// SmartStockSetupRequest is the parsed request from the extract handler
type SmartStockSetupRequest struct {
	TenantID    string
	UserID      string
	ShopID      string
	StockColumn string // "total", "closing", or "opening"
	CategoryID  string // optional: scope matching to this category
	Size        string // optional: scope matching to this size (e.g. "750ML")
	Images      []SmartPurchaseImage // reuse existing image type
}

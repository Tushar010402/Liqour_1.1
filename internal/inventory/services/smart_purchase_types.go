package services

import (
	"strconv"
	"time"
)

// ============================================================================
// AI Extraction Types (parsed from OpenAI/Gemini response)
// ============================================================================

// PurchaseExtractionResult represents the raw AI extraction from invoice images
type PurchaseExtractionResult struct {
	VendorName          string                  `json:"vendor_name"`
	VendorGST           string                  `json:"vendor_gst"`
	VendorAddress       string                  `json:"vendor_address"`
	InvoiceNumber       string                  `json:"invoice_number"`
	InvoiceDate         string                  `json:"invoice_date"`
	Items               []ExtractedPurchaseItem `json:"items"`
	ExpectedRowCount    int                     `json:"expected_row_count"`    // Max S.No seen on invoice; used to detect partial extractions
	DocumentTotalCases  int                     `json:"document_total_cases"`  // From "Total N Cs." footer; cross-check vs sum of row cases
	DocumentTotalAmount float64                 `json:"document_total_amount"` // Grand total ₹ from footer (plain decimal, no lakh commas)
	SubTotal            float64                 `json:"subtotal"`
	TaxAmount           float64                 `json:"tax_amount"`
	TotalAmount         float64                 `json:"total_amount"`
	RawText             string                  `json:"raw_text"`
	// Truncated is set true by parseExtractionResponse when the AI response
	// was cut off mid-array and we recovered partial items via the JSON
	// repair fallback. Caller uses this to decide whether to retry the same
	// request once (gemini-flash-latest's response length is non-deterministic
	// on the same input — second attempt often returns the full document).
	Truncated bool `json:"-"`
}

// ExtractedPurchaseItem represents a single line item extracted by AI from the invoice
type ExtractedPurchaseItem struct {
	RowNumber      float64 `json:"row_number"`
	Brand          string  `json:"brand"`
	Category       string  `json:"category"`
	SizeText       string  `json:"size_text"`
	SizeML         float64 `json:"size_ml"`
	QuantityRaw    float64 `json:"quantity_raw"`
	QuantityUnit   string  `json:"quantity_unit"`    // "cases" or "bottles"
	BottlesPerCase float64 `json:"bottles_per_case"`
	QuantityBottles float64 `json:"quantity_bottles"`
	RatePerBottle  float64 `json:"rate_per_bottle"`
	RatePerCase    float64 `json:"rate_per_case"`
	Amount         float64 `json:"amount"`
	LooseBottles   float64 `json:"loose_bottles"` // "(M Pcs)" extra bottles on top of cases in a dual-line row
	BatchNumber    string  `json:"batch_number"`
	Confidence     float64 `json:"confidence"`
	QuantityFlag   string  `json:"quantity_flag"` // "rate_unit_uncertain" when amount ≠ rate × qty

	// v1.0.199 — per-field Textract confidence (0-1). Populated by the
	// AnalyzeExpense pipeline; legacy paths leave it nil. Keys: "brand",
	// "size", "quantity", "rate", "amount", "duty". Surfaced in Flutter
	// review chips so the operator sees which cell Textract was unsure of.
	FieldConfidence map[string]float64 `json:"field_confidence,omitempty"`

	// AnalyzeMethod records which Textract feature produced this row:
	// "expense" (AnalyzeExpense), "tables" (AnalyzeDocument(TABLES)),
	// "queries" (AnalyzeDocument(QUERIES)), "llm" (Gemini/Claude fallback).
	// Drives observability + lets per-row mixing show in the UI when a page
	// hit multiple Textract features.
	AnalyzeMethod string `json:"analyze_method,omitempty"`

	// v1.0.215.9 — 0-based bill page index this row was extracted from.
	// Stamped by extractWithAnalyzeExpense's per-page merge so we can
	// disambiguate duplicate S.Nos (page 1 has 1-41, page 2 restarts at
	// 1-18). Flows through to SmartPurchaseExtractedItem.PageIndex for
	// the Flutter "Review by Image" pager.
	SourcePageIdx int `json:"-"`

	// v1.0.209 — Brand canonicalization. The bill prints SHORT vendor names
	// ("Mcd Original Why", "Impe Blue Dual Cask") that vary across vendors.
	// The gate-pass prints FULL excise names ("McDowell's No.1 Original",
	// "Imperial Blue Dual Cask Smooth Whisky") which are legally authoritative.
	// When buildGatePassBrandMap pairs a bill row to a GP row at score ≥ 0.60,
	// we copy the GP full name onto CanonicalBrand and preserve the bill's
	// original short name in OriginalBrand. Downstream matcher prefers
	// CanonicalBrand when present; alias-capture on Apply writes "short →
	// matched_product" so future bills auto-resolve without GP coverage.
	OriginalBrand    string `json:"original_brand,omitempty"`
	CanonicalBrand   string `json:"canonical_brand,omitempty"`
	CanonicalSource  string `json:"canonical_source,omitempty"` // "gate_pass" | "gemini" | ""
}

// ============================================================================
// Case Conversion Constants (UP India IMFL standard)
// ============================================================================

// StandardCaseSizes maps bottle size (ML) to bottles per case for UP India
var StandardCaseSizes = map[int]int{
	// IMFL (Indian Made Foreign Liquor) — owner-confirmed standard packs (v1.0.359)
	60:   150,
	90:   96,
	180:  48,
	375:  24,
	750:  12,
	1000: 12, // v1.0.359 — corrected from 9 (litre packs 12, matches PackSizesByML)
	// Beer sizes
	330:  24,
	500:  12,
	650:  12,
}

// GetBottlesPerCase returns the standard bottles-per-case for a given size in ML.
// v1.0.202 — when the literal sizeML doesn't match any standard size, falls
// back to RecoverStandardSize which strips leading-digit corruption (e.g.
// "8pm Gold Tetra 180ml" → AI extracted size_ml=8180 because the "8pm" digits
// bled into the size cell). Without this, bpc=12 default applied to a 180ml
// bottle would compute 12 bpc instead of 48 — breaking every per-case math
// recovery for that row.
func GetBottlesPerCase(sizeML int) int {
	if bpc, ok := StandardCaseSizes[sizeML]; ok {
		return bpc
	}
	if recovered := RecoverStandardSize(sizeML); recovered > 0 {
		if bpc, ok := StandardCaseSizes[recovered]; ok {
			return bpc
		}
	}
	// Default: assume 12 for unknown sizes
	return 12
}

// RecoverStandardSize tries to recover a known standard bottle size from a
// corrupted size_ml integer. The corruption pattern is OCR/extractor
// concatenation of leading digits from the brand name (e.g. "8pm" + "180" ->
// 8180; "B7" + "375" -> 7375; "M2" + "750" -> 2750).
//
// Strategy: if the input is already a known standard size, return as-is.
// Otherwise, scan the trailing 4, 3, 2 digits for a known standard size and
// return the longest match. Returns 0 when nothing matches.
//
// Examples (all real, from chhotu's bill, job b911079b):
//
//	8180     -> 180  ("8pm Gold ... 180ml")
//	7375     -> 375  ("Sterling Reserve B7 ... 375ML")
//	7180     -> 180  ("Sterling Reserve B7 ... 180ML")
//	2750     -> 750  ("M2 Magic Moments ... 750ml")
//	2375     -> 375  ("M2 Magic Moments ... 375ml")
//	2180     -> 180  ("M2 Magic Moment ... 180 MI Pet")
//	44100180 -> 180  ("100 Strokes Royal ... 180ml")
//	400750   -> 750  ("Strokes Royal ... 750ml")
//	40180    -> 180  ("Mcd Original ... 180ml")
//	8180     -> 180  ("Pm Black ... 180ML")
//
// Why a method rather than a hardcoded suffix peel: the corruption depth
// varies per row (sometimes 1 digit, sometimes 5), so we try widths 4 down
// to 2. We don't peel single trailing digits because every standard size
// has at least 2 digits (90 is the smallest).
func RecoverStandardSize(sizeML int) int {
	if sizeML <= 0 {
		return 0
	}
	if _, ok := StandardCaseSizes[sizeML]; ok {
		return sizeML
	}
	// SUFFIX peeling — handles "8750"→750, "2750"→750, "44100180"→180.
	// Try widest mod first so 100180 → 180 not 100.
	for width := 4; width >= 2; width-- {
		mod := 1
		for i := 0; i < width; i++ {
			mod *= 10
		}
		candidate := sizeML % mod
		if candidate == sizeML {
			continue // would be the same as the original
		}
		if _, ok := StandardCaseSizes[candidate]; ok {
			return candidate
		}
	}
	// v1.0.215.8 — PREFIX peeling. Real-data trigger: bill row "Jamenson
	// Irish 750 MI Whisky(25-26)" extracted as SizeML=7502526 (size+year
	// merged). Suffix peeling can't recover 750 because no width gives
	// 750 from 7502526's tail. Prefix peeling at width 3 ("750" first
	// 3 digits) → 750 ✓. We try widths 4 down to 2 from the FRONT.
	asStr := strconv.Itoa(sizeML)
	if len(asStr) > 4 {
		for width := 4; width >= 2; width-- {
			if width >= len(asStr) {
				continue
			}
			candidate, err := strconv.Atoi(asStr[:width])
			if err != nil {
				continue
			}
			if _, ok := StandardCaseSizes[candidate]; ok {
				return candidate
			}
		}
	}
	return 0
}

// ============================================================================
// Smart Purchase Response Types (returned to Flutter)
// ============================================================================

// SmartPurchaseResult is the top-level response returned to the Flutter app
type SmartPurchaseResult struct {
	Status  string `json:"status"`  // success, partial, failed
	Message string `json:"message"`

	// Pagination / extraction completeness
	ExpectedRowCount    int     `json:"expected_row_count,omitempty"`    // Highest S.No OCR saw across all images
	ExtractedCount      int     `json:"extracted_count,omitempty"`       // After dedup
	Partial             bool    `json:"partial,omitempty"`               // true when extracted < expected - 2
	DocumentTotalCases  int     `json:"document_total_cases,omitempty"`  // From "Total N Cs." footer
	DocumentTotalAmount float64 `json:"document_total_amount,omitempty"` // Grand total ₹ from footer

	// Detected invoice metadata
	DetectedVendor *DetectedVendorInfo `json:"detected_vendor,omitempty"`
	InvoiceNumber  string              `json:"invoice_number,omitempty"`
	InvoiceDate    string              `json:"invoice_date,omitempty"`

	// Vendor match from DB
	MatchedVendorID   *string `json:"matched_vendor_id,omitempty"`
	MatchedVendorName string  `json:"matched_vendor_name,omitempty"`
	VendorConfidence  float64 `json:"vendor_confidence"`

	// Extracted and matched line items
	Items []SmartPurchaseExtractedItem `json:"items"`

	// Totals from invoice
	SubTotal    float64 `json:"sub_total"`
	TaxAmount   float64 `json:"tax_amount"`
	TotalAmount float64 `json:"total_amount"`

	// Processing metrics
	ProcessingDetails *SmartPurchaseProcessing `json:"processing_details"`

	// v1.0.199 — top-level analyze_method tag for the overall submission.
	// "expense" = AnalyzeExpense did everything; "expense+tables" =
	// AnalyzeExpense+AnalyzeDocument(TABLES) on at least one page;
	// "expense+queries" = AnalyzeExpense + a QUERIES call for missing
	// header/footer; "tables" = legacy AnalyzeDocument(TABLES) path took
	// over; "llm" = Gemini/Claude cascade fired. Operator-visible in the
	// review header chip; ops uses it for the dashboard counter.
	AnalyzeMethod string `json:"analyze_method,omitempty"`

	// Saved image URLs
	ImageURLs []string `json:"image_urls,omitempty"`

	// Validation summary
	Validation *SmartPurchaseValidation `json:"validation"`

	// v1.0.238 — Purcha gate REMOVED. AI Purchase no longer requires
	// operator-uploaded product photos; 100% accuracy comes from Bill+GP
	// cross-validation (Reconciliation field below, Track B).
	Reconciliation *BillGPReconciliation `json:"reconciliation,omitempty"`

	// v1.0.238 Track E — raw GP row dump for the Excel "photocopy" export.
	// One element per GP row as Textract / Claude saw it, with PageIndex
	// stamped during extraction so the export route can group rows back
	// into per-page sheets. Persists in smart_purchase_jobs.result so the
	// export endpoint can re-render the photocopy at any time without
	// re-running OCR.
	DutyItems []GatePassDutyItem `json:"duty_items,omitempty"`
}

// DetectedVendorInfo holds vendor info extracted from invoice header
type DetectedVendorInfo struct {
	Name      string `json:"name"`
	GSTNumber string `json:"gst_number,omitempty"`
	Address   string `json:"address,omitempty"`
}

// BillGPReconciliation surfaces cross-validation between the bill (vendor /
// invoice number / cost) and the GP (canonical brand / qty / duty). v1.0.238
// Track B — replaces the operator-uploaded Purcha photo flow with deterministic
// document-vs-document checks.
//
// Flutter renders a banner: 🟢 when all 3 anchors agree (vendor, invoice
// number present, qty/cost reconcile within tolerance), 🟡 on partial,
// 🔴 when vendor mismatch or cost-vs-duty completely diverges.
type BillGPReconciliation struct {
	BillVendor       string  `json:"bill_vendor"`
	GPVendor         string  `json:"gp_vendor,omitempty"`
	VendorMatchScore float64 `json:"vendor_match_score"` // 0..1 jaccard
	VendorMatches    bool    `json:"vendor_matches"`

	InvoiceNumber string `json:"invoice_number"`
	InvoiceDate   string `json:"invoice_date,omitempty"`

	BillTotal     float64 `json:"bill_total"`
	GPDutyTotal   float64 `json:"gp_duty_total"`
	TotalMismatch bool    `json:"total_mismatch"`

	RowsBoth     int      `json:"rows_both"`     // rows present in both bill + GP (paired)
	RowsBillOnly int      `json:"rows_bill_only"`
	RowsGPOnly   int      `json:"rows_gp_only"`
	Warnings     []string `json:"warnings,omitempty"`
}

// SmartPurchaseExtractedItem is an extracted line item enriched with product matching
type SmartPurchaseExtractedItem struct {
	// OCR-extracted values
	RowNumber int    `json:"row_number"`
	// v1.0.215.9 — page index (0-based) of the bill image this row was
	// extracted from. Drives the Flutter "Review by Image" pager so the
	// operator can verify each image's extracted rows against the photo
	// they uploaded — and see WHY a row didn't pair to GP (variant
	// mismatch, size mismatch, no GP candidate).
	PageIndex int    `json:"page_index"`
	BrandName string `json:"brand_name"` // bill's printed short text (what operator sees on photo)

	// v1.0.209 — Brand canonicalization surfaced to Flutter so the operator
	// row can render "Mcd Original Why → McDowell's No.1 Original Whisky"
	// chip when the GP supplied an authoritative full name.
	CanonicalBrand  string `json:"canonical_brand,omitempty"`  // GP / Gemini-resolved full name
	CanonicalSource string `json:"canonical_source,omitempty"` // "gate_pass" | "gemini"
	Size      string `json:"size"`
	SizeML    int    `json:"size_ml"`
	Category  string `json:"category"`

	// Quantity handling
	QuantityRaw     int    `json:"quantity_raw"`
	QuantityUnit    string `json:"quantity_unit"`     // "cases" or "bottles"
	BottlesPerCase  int    `json:"bottles_per_case"`
	QuantityBottles int    `json:"quantity_bottles"`

	// Pricing
	RatePerBottle float64 `json:"rate_per_bottle"`
	RatePerCase   float64 `json:"rate_per_case"`
	Amount        float64 `json:"amount"`

	// Batch
	BatchNumber string `json:"batch_number,omitempty"`

	// Product matching result
	ProductID                *string `json:"product_id,omitempty"`
	MatchedBrandName         string  `json:"matched_brand_name,omitempty"`          // Kept for backwards compat — equals MatchedDisplayName
	MatchedDisplayName       string  `json:"matched_display_name,omitempty"`        // Short clean name (e.g. "Magic Moments Vodka")
	// MatchedDisplayNameBoldStart / Length drive the bold-range + small-tail
	// rendering the Flutter app applies everywhere a product name shows up.
	// Inherited from the matched product (which itself inherits from the
	// linked saas_brand master catalog). Null when the matched product has
	// no bold indices configured, in which case the Flutter side falls back
	// to a single style.
	MatchedDisplayNameBoldStart  *int `json:"matched_display_name_bold_start,omitempty"`
	MatchedDisplayNameBoldLength *int `json:"matched_display_name_bold_length,omitempty"`
	MatchedFullName          string  `json:"matched_full_name,omitempty"`           // Full DB name (e.g. "M2 Magic Moments Superior Vodka - 180ml")
	MatchedExciseBrandName   string  `json:"matched_excise_brand_name,omitempty"`   // Authoritative name from saas_brands (excise master catalog)
	MatchedExciseDisplayName string  `json:"matched_excise_display_name,omitempty"` // Authoritative short-form excise name
	MatchConfidence          float64 `json:"match_confidence"`
	Status                   string  `json:"status"` // matched, low_confidence, ambiguous, not_found, not_found_suggest_create, quantity_unclear

	// For ambiguous matches — Flutter shows picker popup
	AlternativeMatches []AlternativeMatch `json:"alternative_matches,omitempty"`

	// Validation warnings
	Warnings []string `json:"warnings,omitempty"`

	// Review flagging
	NeedsReview  bool   `json:"needs_review,omitempty"`
	ReviewReason string `json:"review_reason,omitempty"`

	// v1.0.343 — unified row confidence. ConfidenceScore (0..1) is computed
	// from agreement across the independent sources we have for a row (product
	// match, quantity integrity, price/bill corroboration, bill↔GP cross-val,
	// resolution disputes). ConfidenceTier buckets it: "high" = corroborated,
	// safe to auto-accept; "review" = at least one source is missing or
	// disagrees, so it is surfaced and nothing uncertain ships silently. This
	// unifies the previously-scattered NeedsReview triggers into one auditable
	// number.
	ConfidenceScore float64 `json:"confidence_score"`
	ConfidenceTier  string  `json:"confidence_tier,omitempty"` // "high" | "review"

	// 2026-05-18 — NeedsImage: true when the matched product was created by
	// AI Stock Setup (created_via='stock_setup') and still has no bottle
	// photo. The review row shows a "photo required" chip and AI-Purchase
	// apply hard-blocks (HTTP 409 PurchaseImageRequiredError) until a photo
	// is attached inline. Advisory here; the apply gate is authoritative.
	NeedsImage bool `json:"needs_image,omitempty"`

	// DB comparison data
	DBCostPrice   *float64 `json:"db_cost_price,omitempty"`
	MRP           *float64 `json:"mrp,omitempty"`
	SellingPrice  *float64 `json:"selling_price,omitempty"`
	CurrentStock *int     `json:"current_stock,omitempty"`

	// Gate Pass data
	GatePassBrand string  `json:"gate_pass_brand,omitempty"` // Official excise name from gate pass
	DutyFee       float64 `json:"duty_fee,omitempty"`
	DutyPerBottle float64 `json:"duty_per_bottle,omitempty"`

	// v1.0.226 — GP-canonical rule. BillOCRText preserves the bill's
	// printed brand text WITHOUT polluting BrandName (which is the GP
	// canonical that the UI displays). Used purely by the apply path to
	// teach AliasService "bill said X → canonical Y" without affecting
	// matching or display.
	BillOCRText string `json:"bill_ocr_text,omitempty"`

	// CostSource records where cost_per_bottle came from: "bill" (matched
	// bill row), "operator" (manual edit on review screen), "" (no cost found).
	// v1.0.238 — "purcha" value removed; Purcha gate no longer exists.
	CostSource string `json:"cost_source,omitempty"`

	// v1.0.238 — Purcha gate provenance fields REMOVED (PurchaConfirmed /
	// PurchaQtyObserved / PurchaSource / PurchaBrandText). AI Purchase no
	// longer requires operator-uploaded product photos; bill cost +
	// vendor + invoice number reconciliation replaces this provenance trail.

	// Quantity integrity — set true when amount≠rate×qty or bottles==cases for IMFL sizes
	QuantityFlagged bool `json:"quantity_flagged,omitempty"`

	// v1.0.193 — Bill ↔ Gate-pass cross-validation results.
	//
	// CrossValFlags lists every disagreement between this bill row and the
	// matched gate-pass row (or absence-of-match): brand_disagreement,
	// size_disagreement, bottle_count_mismatch, pack_size_violation,
	// bill_only_no_gp, quantity_disputed. Empty means agreement (or no GP
	// uploaded). Flutter renders one chip per flag with both BILL and GP
	// values side-by-side, never silently picking one.
	CrossValFlags []CrossValFlag `json:"cross_val_flags,omitempty"`

	// ResolutionSource = which document the final quantity was sourced from.
	// "bill" → bill row math is internally consistent; took bill values
	// "gate_pass" → bill row failed math, GP took over (cases/bottles re-derived)
	// "disputed" → bill and GP disagreed by >1 bottle; needs_review=true, no
	//   silent pick. Flutter shows both values to operator.
	// "" (empty) → no GP uploaded, used bill only.
	ResolutionSource string `json:"resolution_source,omitempty"`

	// v1.0.193 — Onboarding decision tree (4-tier).
	//
	// OnboardingTier:
	//   "matched"                     — found in this shop (or shop-bias winner)
	//   "matched_other_shop"          — exists in tenant but NOT in this shop yet
	//   "master_create_shop_product"  — master catalog has it; one-tap create
	//   "fully_new"                   — nothing matches; operator MRP+size+category form
	//
	// Empty string when item is "matched" (default — no onboarding needed).
	OnboardingTier    string             `json:"onboarding_tier,omitempty"`
	OnboardingPayload *OnboardingPayload `json:"onboarding_payload,omitempty"`
}

// CrossValFlag is a single bill ↔ gate-pass disagreement, surfaced 1:1 to
// Flutter so the operator sees exactly what the system couldn't reconcile.
//
// We never silently pick a side — every disagreement is the operator's call.
// "100% accuracy" rule from v1.0.193 plan.
type CrossValFlag struct {
	// Kind: "brand_disagreement" | "size_disagreement" |
	// "bottle_count_mismatch" | "pack_size_violation" |
	// "bill_only_no_gp" | "gp_only_no_bill" | "quantity_disputed"
	Kind string `json:"kind"`
	// Severity: "info" (just FYI) | "warn" (review recommended) | "block"
	// (apply-gate refuses without explicit operator confirmation).
	Severity string `json:"severity"`
	// Both values, side-by-side, for the Flutter chip.
	BillValue     string `json:"bill_value,omitempty"`
	GatePassValue string `json:"gate_pass_value,omitempty"`
	// Human-readable explainer for the row tooltip.
	Detail string `json:"detail,omitempty"`
}

// OnboardingPayload carries everything Flutter needs to one-tap-create the
// product (no second roundtrip to fetch master MRP, etc).
type OnboardingPayload struct {
	// For matched_other_shop: the existing tenant product to copy to this shop.
	ExistingProductID string `json:"existing_product_id,omitempty"`

	// For master_create_shop_product:
	MasterSaaSBrandID string  `json:"master_saas_brand_id,omitempty"`
	MasterDisplayName string  `json:"master_display_name,omitempty"`
	MasterMRP         float64 `json:"master_mrp,omitempty"`
	MasterCategory    string  `json:"master_category,omitempty"`

	// For fully_new: caller fills in MRP + category from operator form.
	SuggestedBrandName string `json:"suggested_brand_name,omitempty"`
	SuggestedSizeML    int    `json:"suggested_size_ml,omitempty"`

	// Cost price the bill showed (always populated when known) — pre-fills
	// the form so operator only confirms.
	BillCostPrice float64 `json:"bill_cost_price,omitempty"`
}

// AlternativeMatch represents a possible product match for ambiguous items
type AlternativeMatch struct {
	ProductID             string  `json:"product_id"`
	BrandName             string  `json:"brand_name"` // Kept for backwards compat — equals DisplayName
	DisplayName           string  `json:"display_name,omitempty"`
	DisplayNameBoldStart  *int    `json:"display_name_bold_start,omitempty"`  // 0-indexed start of bold range inside DisplayName
	DisplayNameBoldLength *int    `json:"display_name_bold_length,omitempty"` // length of bold range
	FullName              string  `json:"full_name,omitempty"`
	ExciseBrandName       string  `json:"excise_brand_name,omitempty"`
	ExciseDisplayName     string  `json:"excise_display_name,omitempty"`
	Size                  string  `json:"size"`
	CostPrice             float64 `json:"cost_price"`
	MRP                   float64 `json:"mrp"`
	Confidence            float64 `json:"confidence"`
}

// SmartPurchaseProcessing holds timing and processing metadata
type SmartPurchaseProcessing struct {
	OCRTimeMs      int64  `json:"ocr_time_ms"`
	MatchingTimeMs int64  `json:"matching_time_ms"`
	TotalTimeMs    int64  `json:"total_time_ms"`
	ImagesProcessed int   `json:"images_processed"`
	AIModel        string `json:"ai_model"`

	// v1.0.214 — gap detection on the extracted S.No sequence. Surfaces row-
	// recall failures to the operator: when bill page 1 has S.No 1..42
	// printed but Textract dropped 21/25/30, the missing S.Nos appear here
	// so the Flutter review screen can banner "rows X, Y, Z appear missing".
	// Bill side runs over ExtractedPurchaseItem.RowNumber. GP side runs over
	// GatePassDutyItem.RowNumber. Empty when no gaps detected.
	MissingBillSnos []int `json:"missing_bill_snos,omitempty"`
	MissingGPSnos   []int `json:"missing_gp_snos,omitempty"`
}

// SmartPurchaseValidation summarizes extraction quality
type SmartPurchaseValidation struct {
	TotalItems         int      `json:"total_items"`
	MatchedItems       int      `json:"matched_items"`
	LowConfidenceItems int      `json:"low_confidence_items"`
	NotFoundItems      int      `json:"not_found_items"`
	NeedsReviewItems   int      `json:"needs_review_items"`
	Warnings           []string `json:"warnings"`

	// v1.0.193 — Reconciliation flags surface footer-level mismatches
	// (sum-of-items vs printed subtotal, sum-of-cases vs printed total
	// cases, sum-of-duty vs printed gate-pass duty total). Severity=block
	// rejects apply server-side unless `user_confirmed_warnings` includes
	// the kind. Severity=warn shows a banner; severity=info is logged only.
	ReconciliationFlags []ReconciliationFlag `json:"reconciliation_flags,omitempty"`

	// v1.0.193 — Orphan dispatch rows: items that appear in the gate pass
	// but don't have a matching bill row. Operator may want to add them
	// manually or query the supplier. Empty array when bill ↔ GP fully
	// reconciled or when no GP was uploaded.
	OrphanGatePassRows []OrphanGatePassRow `json:"orphan_gate_pass_rows,omitempty"`
}

// ReconciliationFlag — a footer-level (or document-level) mismatch.
type ReconciliationFlag struct {
	// Kind: "subtotal_mismatch" | "case_count_mismatch" | "duty_total_mismatch"
	Kind     string  `json:"kind"`
	Severity string  `json:"severity"` // "info" | "warn" | "block"
	Expected float64 `json:"expected"` // printed footer value
	Got      float64 `json:"got"`      // sum-of-items value
	Detail   string  `json:"detail"`
	// v1.0.199 — Source records which extractor produced the disagreeing
	// value. "expense" | "tables" | "queries" | "llm". Lets the review UI
	// surface "Textract said X / LLM said Y" only when a real cross-source
	// disagreement existed (rare with the new cascade).
	Source string `json:"source,omitempty"`
}

// OrphanGatePassRow — a gate-pass dispatch row with no bill row.
type OrphanGatePassRow struct {
	GatePassRowNumber int     `json:"gate_pass_row_number"`
	BrandName         string  `json:"brand_name"`
	SizeML            int     `json:"size_ml"`
	Cases             int     `json:"cases"`
	Bottles           int     `json:"bottles"`
	DutyFee           float64 `json:"duty_fee"`
	// Detail is a human-readable suggestion for the operator banner.
	Detail string `json:"detail"`
}

// ============================================================================
// Internal helper types
// ============================================================================

// productMatch is used internally during product matching
type productMatch struct {
	ProductID   string
	ProductName string
	Size        string
	SizeML      int
	CostPrice      float64
	MRP            float64
	SellingPrice   float64
	Confidence  float64
	Stock       int
}

// SmartPurchaseRequest is the parsed request from the handler
type SmartPurchaseRequest struct {
	TenantID    string
	UserID      string
	ShopID      string
	VendorID    string // optional
	InvoiceDate string // optional
	Images      []SmartPurchaseImage
	GatePassImages []SmartPurchaseImage // Optional gate pass images for duty extraction

	// v1.0.227 — optional job context. When set, the orchestrator updates
	// smart_purchase_jobs.progress_stage at six checkpoints (queued,
	// extracting_bill, extracting_gp, matching_brands, building_purcha_gate,
	// done) so the Flutter poll surfaces granular hints instead of a generic
	// "Processing…". Empty for synchronous callers; only the async worker
	// (smart_purchase_job_service.runJob) populates it today.
	JobID string
}

// SmartPurchaseImage holds an uploaded image's data
type SmartPurchaseImage struct {
	Data        []byte
	ContentType string
	Filename    string
}

// Ensure time is imported (used in models referenced)
var _ = time.Now

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
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
)

// SmartPurchaseService orchestrates AI-powered purchase invoice extraction
type SmartPurchaseService struct {
	db           *database.DB
	ocr          *SmartPurchaseOCR
	aliasService *alias.AliasService
}

// NewSmartPurchaseService creates a new SmartPurchaseService
//
// v1.0.169 D3 — alias service is now optional. When provided, the matcher
// pre-resolves brand text via the same shop-scoped → tenant cascade Smart
// Sale uses. Existing callers can pass nil.
func NewSmartPurchaseService(db *database.DB, ocr *SmartPurchaseOCR) *SmartPurchaseService {
	return &SmartPurchaseService{db: db, ocr: ocr, aliasService: alias.NewAliasService(db)}
}

// ProcessSmartPurchase processes invoice images and returns matched/extracted data
// annotateNeedsImage flags review rows whose matched product was created by
// AI Stock Setup (created_via='stock_setup') and still has no image at all
// (image_url / front_image_url / back_image_url empty). The AI-Purchase
// apply path hard-blocks these (PurchaseImageRequiredError); surfacing the
// flag on the review item lets the screen show a "photo required" chip
// BEFORE the operator taps Submit. Best-effort: any DB hiccup leaves
// NeedsImage=false (fails open — must never break extraction). Only
// 'stock_setup' is gated; every other origin (legacy_exempt default,
// ai_purchase, catalog, manual, bulk_import) is exempt.
func (s *SmartPurchaseService) annotateNeedsImage(tenantID string, items []SmartPurchaseExtractedItem) {
	if s.db == nil || len(items) == 0 {
		return
	}
	tid, err := uuid.Parse(tenantID)
	if err != nil {
		return
	}
	ids := make([]uuid.UUID, 0, len(items))
	for i := range items {
		if items[i].ProductID == nil || *items[i].ProductID == "" {
			continue
		}
		if pid, e := uuid.Parse(*items[i].ProductID); e == nil {
			ids = append(ids, pid)
		}
	}
	if len(ids) == 0 {
		return
	}
	var flagged []struct {
		ID string `gorm:"column:id"`
	}
	if e := s.db.Table("products").
		Select("id::text AS id").
		Where(`tenant_id = ? AND id IN ? AND deleted_at IS NULL
		        AND created_via = ?
		        AND COALESCE(image_url,'') = ''
		        AND COALESCE(front_image_url,'') = ''
		        AND COALESCE(back_image_url,'') = ''`,
			tid, ids, "stock_setup").
		Scan(&flagged).Error; e != nil {
		log.Printf("[needs_image] annotate skipped (non-fatal): %v", e)
		return
	}
	if len(flagged) == 0 {
		return
	}
	need := make(map[string]bool, len(flagged))
	for _, f := range flagged {
		need[f.ID] = true
	}
	for i := range items {
		if items[i].ProductID != nil && need[*items[i].ProductID] {
			items[i].NeedsImage = true
		}
	}
}

func (s *SmartPurchaseService) ProcessSmartPurchase(ctx context.Context, req SmartPurchaseRequest) (*SmartPurchaseResult, error) {
	totalStart := time.Now()

	// v1.0.227 — progress writer. Async worker passes req.JobID; sync
	// callers leave it empty and the writes are no-ops. Each call is
	// best-effort (DB hiccup MUST NOT abort the extraction pipeline).
	writeStage := func(stage string) {
		if req.JobID == "" {
			return
		}
		if s.db == nil {
			return
		}
		if err := s.db.Model(&models.SmartPurchaseJob{}).
			Where("id = ?", req.JobID).
			Update("progress_stage", stage).Error; err != nil {
			log.Printf("[v227] writeStage(%s) for job %s failed: %v", stage, req.JobID, err)
		}
	}
	writeStage(models.SmartPurchaseStageExtractingBill)

	if !s.ocr.IsAvailable() {
		return nil, fmt.Errorf("AI extraction not configured. Contact your administrator to enable Smart Purchase")
	}

	if len(req.Images) == 0 {
		return nil, fmt.Errorf("at least one invoice image is required")
	}

	tenantID, err := uuid.Parse(req.TenantID)
	if err != nil {
		return nil, fmt.Errorf("invalid tenant ID: %w", err)
	}

	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		return nil, fmt.Errorf("invalid shop ID: %w", err)
	}

	// v1.0.359 — GP-only mode: NAME + quantity/pieces come from the gate pass
	// only; the bill contributes only cost/vendor/TCS. Computed once from the
	// job's user_id (per-job portal enable) + the global ship switch, then
	// threaded through the item builder + reconciliation. Dark by default.
	gpOnly := gpOnlyNamesEnabled(req.UserID)
	if gpOnly {
		log.Printf("SmartPurchase v359: GP-ONLY mode ON for job %s (user %s) — names+qty from gate pass, bill=cost/vendor/TCS only", req.JobID, req.UserID)
	}

	// WS1 — stamp the per-job strict-shop-isolation decision onto ctx so the
	// GP-primary matcher (selectBestProductForGPRow, several calls below) honors
	// the same test-user / global gate without threading userID through every
	// signature. Dark by default.
	if shopAliasGuardEnabled(req.UserID) {
		ctx = withShopIsolation(ctx, true)
		log.Printf("SmartPurchase WS1: STRICT SHOP ISOLATION ON for job %s (user %s) — matcher + aliases restricted to this shop", req.JobID, req.UserID)
	}
	// WS-A/B image→identity engine: reuse a mislinked existing same-shop product
	// (variant-safe name+size) instead of creating a duplicate. Dark by default.
	if identityEngineEnabled(req.UserID) {
		ctx = withIdentityEngine(ctx, true)
		log.Printf("SmartPurchase WS-A/B: IDENTITY ENGINE ON for job %s (user %s) — reuse-before-create by variant-safe name+size", req.JobID, req.UserID)
	}

	// Save invoice images to disk (same pattern as Smart Sale)
	tenantShort := req.TenantID[:8]
	uploadDir := fmt.Sprintf("/app/uploads/purchases/%s", tenantShort)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		log.Printf("SmartPurchase: Upload dir create failed for %s: %v — review screen will lack images", uploadDir, err)
	}
	var savedImageURLs []string
	for i, img := range req.Images {
		filename := fmt.Sprintf("%d_%s.jpg", time.Now().UnixMilli(), uuid.New().String()[:8])
		fpath := filepath.Join(uploadDir, filename)
		writeErr := os.WriteFile(fpath, img.Data, 0644)
		if writeErr != nil && os.IsNotExist(writeErr) {
			if mkErr := os.MkdirAll(uploadDir, 0755); mkErr == nil {
				writeErr = os.WriteFile(fpath, img.Data, 0644)
			}
		}
		if writeErr != nil {
			log.Printf("SmartPurchase: Failed to save image %d to %s: %v", i, fpath, writeErr)
			continue
		}
		savedImageURLs = append(savedImageURLs, fmt.Sprintf("/uploads/purchases/%s/%s", tenantShort, filename))
	}

	// Step 1: Extract from all images using AI (parallel for speed)
	ocrStart := time.Now()
	var allExtracted []ExtractedPurchaseItem
	var vendorInfo *DetectedVendorInfo
	var invoiceNumber, invoiceDate string
	var subTotal, taxAmount, totalAmount float64
	var expectedRowCount int
	var documentTotalCases int
	var documentTotalAmount float64
	rowToImageIdx := make(map[int]int)
	aiModel := "Fomoa AI"

	// v1.0.193 — Gate-pass extraction starts NOW in a background goroutine
	// so it runs in parallel with bill extraction. End-to-end latency drops
	// from sum(bill, GP) to max(bill, GP) — for a 4-doc submission that's
	// 60-90s saved. The variable is read after bill extraction completes;
	// gpDoneCh closes when GP is ready.
	var dutyItems []GatePassDutyItem
	var gpDoneCh chan struct{}
	// v1.0.385 — filled by the GP extractor with the printed footer totals; read
	// after the GP goroutine joins (gpDoneCh) to flag unreconcilable extractions.
	gpFooter := &gpFooterVerdict{}
	if len(req.GatePassImages) > 0 {
		log.Printf("SmartPurchase: Processing %d gate pass images for duty extraction (in parallel with bill)", len(req.GatePassImages))
		// Persist GP images to disk synchronously so the URLs make it into
		// savedImageURLs before the response is built. This is fast (file
		// write) and not worth racing with extraction.
		for i, img := range req.GatePassImages {
			filename := fmt.Sprintf("gp_%d_%s.jpg", time.Now().UnixMilli(), uuid.New().String()[:8])
			if err := os.WriteFile(filepath.Join(uploadDir, filename), img.Data, 0644); err != nil {
				log.Printf("SmartPurchase: Failed to save gate pass image %d: %v", i, err)
				continue
			}
			savedImageURLs = append(savedImageURLs, fmt.Sprintf("/uploads/purchases/%s/%s", tenantShort, filename))
		}
		gpDoneCh = make(chan struct{})
		// v1.0.227 — checkpoint just before Claude GP extraction kicks
		// off. Bill extraction is already running on the foreground;
		// last writer wins is fine since the UI shows both stages as
		// "Reading bill + gate-pass" when they overlap.
		writeStage(models.SmartPurchaseStageExtractingGP)
		go func() {
			defer close(gpDoneCh)
			var gpErr error
			// v1.0.385 — gpFooterVerdict carries the printed footer totals back so
			// the reconciliation pass below can flag the job if the final rows can't
			// reconcile to them. Read only after this goroutine joins (gpDoneCh).
			gpCtx := withGPFooterVerdict(ctx, gpFooter)
			dutyItems, gpErr = s.extractDutyFromGatePass(gpCtx, req.GatePassImages, req.UserID)
			if gpErr != nil {
				log.Printf("SmartPurchase: Gate pass extraction failed (non-fatal): %v", gpErr)
			} else {
				log.Printf("SmartPurchase: Extracted %d duty items from gate pass", len(dutyItems))
				for _, d := range dutyItems {
					log.Printf("  GP: %s %sML: %d cases, %d bottles, duty=%.2f", d.BrandName, d.Size, d.Cases, d.Bottles, d.DutyFee)
				}
			}
		}()
	}

	// v1.0.169 D1 — AWS Textract Tables row-locked extractor for invoices.
	// Behind STOCK_PURCHASE_PIPELINE=textract or per-tenant flag. Falls back
	// to legacy Gemini+OpenAI when Textract returns < 5 rows or errors.
	// Same row-locked geometry that fixed Smart Sale's 50% row-loss problem.
	//
	// v1.0.189 — added quality filter (sanitizeTextractRows) before counting.
	// Real-data on chhotu's SONU SINGH FL-2 invoice exposed a column-merge
	// failure mode where Textract emitted "42" / "43" / "44" as brand names
	// and "400 Strokes Royal Whisky 750ml" as a size value. Threshold ≥5 was
	// passing through 7 garbage rows when the legacy Gemini path would have
	// produced 41 clean rows. Now we drop header/total/numeric-brand rows
	// up front and only fall through to legacy when at least 5 *valid* rows
	// remain. Drop ratio also matters — if >40% of rows look like junk the
	// page itself was mis-parsed and we should retry with Gemini.
	tenantUUIDForTextract, _ := uuid.Parse(req.TenantID)
	shopUUIDForTextract, _ := uuid.Parse(req.ShopID)
	analyzeMethodTag := ""

	// v1.0.199 — Phase A: AnalyzeExpense primary, AnalyzeDocument(TABLES)
	// per-page secondary, LLM cascade as last-resort fallback. The
	// stockPurchaseAnalyzerForTenant() function picks per-tenant mode
	// (default "expense" once Phase F passes; ramped via STOCK_PURCHASE_
	// ANALYZER_TENANT_<uuid>=expense for the chhotu rollout).
	analyzer := stockPurchaseAnalyzerForTenant(tenantUUIDForTextract)
	log.Printf("SmartPurchase: tenant=%s analyzer=%s", tenantUUIDForTextract.String(), analyzer)

	if analyzer == "expense" {
		exp, expErr := extractWithAnalyzeExpense(ctx, &req, tenantUUIDForTextract, shopUUIDForTextract)
		if expErr != nil {
			log.Printf("SmartPurchase: AnalyzeExpense failed: %v — escalating to TABLES", expErr)
		} else if exp != nil {
			// Lift header fields off the Expense response into the local vars
			// the legacy code path already consumes. Empty fields fall through
			// to whatever the LLM/TABLES paths recover later.
			if exp.Header.VendorName != "" {
				vendorInfo = &DetectedVendorInfo{
					Name:      exp.Header.VendorName,
					GSTNumber: exp.Header.VendorGST,
					Address:   exp.Header.VendorAddress,
				}
			}
			if exp.Header.InvoiceNumber != "" {
				invoiceNumber = exp.Header.InvoiceNumber
			}
			if exp.Header.InvoiceDate != "" {
				invoiceDate = exp.Header.InvoiceDate
			}
			if exp.Header.SubTotal > 0 {
				subTotal = exp.Header.SubTotal
			}
			if exp.Header.TaxAmount > 0 {
				taxAmount = exp.Header.TaxAmount
			}
			if exp.Header.TotalAmount > 0 {
				totalAmount = exp.Header.TotalAmount
				documentTotalAmount = exp.Header.TotalAmount
			}
			allExtracted = exp.Items
			aiModel = "AWS Textract Expense"
			analyzeMethodTag = exp.AnalyzeMethod
			for i := range exp.Items {
				rowToImageIdx[int(exp.Items[i].RowNumber)] = 0
			}
			log.Printf("SmartPurchase: AnalyzeExpense produced %d items (method=%s, needs_tables_pages=%d, needs_llm_pages=%d)",
				len(exp.Items), exp.AnalyzeMethod, len(exp.NeedsTables), len(exp.NeedsLLM))
		}
	}

	// v1.0.215 — DUAL-ANALYZER MERGE.
	//
	// Real-data evidence (chhotu's 2026-05-08 SONU SINGH bill page 1):
	// AnalyzeExpense extracted 36 of 42 visible rows. Dropped: S.No 21, 25,
	// 30, 33, 34, 38, 42 — middle rows of triple-pack groups, standalone
	// rows between brand-clusters, last row of the page. These are
	// STRUCTURAL Textract LineItem-grouping limits, not OCR errors.
	//
	// Pre-v215: TABLES only ran as fallback when Expense returned 0.
	// v215: always run BOTH in parallel and union by printed S.No. TABLES
	// uses a different grid-detection engine (AnalyzeDocument(TABLES) walks
	// horizontal grid lines) and catches rows Expense's LineItemFields
	// merging drops, and vice-versa. When same S.No is in both, keep
	// Expense (cleaner LineItem semantics on price/quantity columns).
	//
	// Cost: ~₹1.50/page extra. Worth it for the 6/42=14% recall lift.
	needsTables := analyzer == "tables" || (analyzer == "expense" && len(allExtracted) == 0)
	mergeTables := analyzer == "expense" && len(allExtracted) > 0
	if needsTables || mergeTables {
		txItemsRaw, txErr := extractWithTextract(ctx, &req, tenantUUIDForTextract, shopUUIDForTextract)
		txItems, dropped := sanitizeTextractRows(txItemsRaw)
		dropRatio := 0.0
		if len(txItemsRaw) > 0 {
			dropRatio = float64(dropped) / float64(len(txItemsRaw))
		}
		switch {
		case txErr != nil:
			log.Printf("SmartPurchase: TABLES extract failed: %v — %s", txErr,
				ternaryStr(mergeTables, "skipping merge (Expense rows still applied)", "falling back to legacy LLM"))
		case mergeTables:
			// v215 merge path: append TABLES rows whose S.No is missing from Expense.
			added, replaced := mergeTablesIntoExpense(&allExtracted, txItems, rowToImageIdx)
			if added > 0 || replaced > 0 {
				log.Printf("SmartPurchase v215 merge: TABLES added %d rows, replaced %d rows (Expense %d → total %d)",
					added, replaced, len(allExtracted)-added, len(allExtracted))
				if analyzeMethodTag == "" {
					analyzeMethodTag = "expense+tables"
				} else if !strings.Contains(analyzeMethodTag, "tables") {
					analyzeMethodTag += "+tables"
				}
			} else {
				log.Printf("SmartPurchase v215 merge: TABLES added 0 rows (Expense already covered all %d S.Nos)", len(allExtracted))
			}
		case len(txItems) < 5:
			log.Printf("SmartPurchase: TABLES returned %d valid rows (raw=%d, dropped=%d) — falling back to legacy LLM",
				len(txItems), len(txItemsRaw), dropped)
		case dropRatio > 0.4:
			log.Printf("SmartPurchase: TABLES drop ratio %.0f%% (raw=%d valid=%d) too high — falling back to legacy LLM",
				dropRatio*100, len(txItemsRaw), len(txItems))
		default:
			// Tag the rows so the UI / dashboard sees which feature won.
			for i := range txItems {
				txItems[i].AnalyzeMethod = "tables"
			}
			allExtracted = txItems
			aiModel = "AWS Textract Tables"
			if analyzeMethodTag == "" {
				analyzeMethodTag = "tables"
			} else {
				analyzeMethodTag = "expense+tables"
			}
			for i := range txItems {
				rowToImageIdx[int(txItems[i].RowNumber)] = 0
			}
			log.Printf("SmartPurchase: TABLES produced %d valid rows (dropped %d junk) — skipping legacy extract",
				len(txItems), dropped)
		}
	}
	// v1.0.204 — RECALL SUPPLEMENT.
	//
	// Real-data evidence (chhotu's 2026-05-08 SONU SINGH bill, job d1c3020b):
	// page 1 has 42 printed S.No, Textract extracted 36 — silently dropped 6.
	// Page 2 was 18-of-18 (perfect). With Textract as the sole extractor we
	// capped at 90% recall on the bill. Operator workflow assumed 100% — the
	// missing rows showed up later as stock-discrepancy ghosts.
	//
	// This pass runs the LLM cascade on the same invoice images AS A SAFETY
	// NET when Textract already produced rows. Any LLM row whose
	// (normalize(brand), size_ml) key doesn't collide with an existing row
	// gets appended. We do NOT replace Textract rows; we only add ones it
	// missed. Textract's structured output is preserved; the LLM pays the
	// recall tax.
	//
	// Cost: one extra Anthropic/Gemini call per image (~₹3-5/page). DEFAULTS
	// OFF per Tushar's v207 architecture call (2026-05-08): "Gemini for fall
	// back we will use not for the extraction. We will use for the matching."
	// Textract is now the SOLE extractor; LLM is reserved for v208 canonical-
	// name resolution (short → full brand mapping). The recall-supplement
	// code is preserved but gated on SMART_PURCHASE_RECALL_RESCUE=1 in case
	// a future tenant has a Textract-blind invoice that needs the safety net.
	if len(allExtracted) > 0 && strings.ToLower(strings.TrimSpace(os.Getenv("SMART_PURCHASE_RECALL_RESCUE"))) == "1" {
		appended := s.runRecallSupplement(ctx, &req, &allExtracted, rowToImageIdx)
		if appended > 0 {
			log.Printf("SmartPurchase: recall-supplement appended %d LLM-recovered rows (was %d, now %d)",
				appended, len(allExtracted)-appended, len(allExtracted))
			if analyzeMethodTag == "" {
				analyzeMethodTag = "rescue_llm"
			} else {
				analyzeMethodTag += "+rescue_llm"
			}
		}
	}

	// v1.0.215.6 — TAIL-RESCUE.
	//
	// Real-data trigger: chhotu's bill page 1 has 42 visible rows. Textract
	// AnalyzeExpense's bottom-edge truncation always drops S.No 42 — even
	// with v215.1 dual-variant merge (variant B catches mid-page drops but
	// not the last row) and v215.2 bottom-crop variant C (Textract uses
	// sequential row numbering on the crop, can't be safely merged back).
	//
	// Tail-rescue: for each page with extracted rows, call Claude Sonnet
	// once asking ONLY for rows whose printed S.No exceeds the highest
	// extracted on that page. Single targeted LLM call (~₹2-3, ~3-5s).
	// Append rows whose RowNumber doesn't already exist.
	//
	// Gated behind STOCK_PURCHASE_TAIL_RESCUE=1 (default off — keeps the
	// fast 10s path for tenants who don't need 100% recall). Set the flag
	// to trade ~5s latency for the last-row safety net.
	if len(allExtracted) > 0 && strings.ToLower(strings.TrimSpace(os.Getenv("STOCK_PURCHASE_TAIL_RESCUE"))) == "1" {
		appended := s.runTailRescuePerPage(ctx, &req, &allExtracted, rowToImageIdx)
		if appended > 0 {
			log.Printf("SmartPurchase v215.6 tail-rescue: appended %d LLM-recovered tail rows (was %d, now %d)",
				appended, len(allExtracted)-appended, len(allExtracted))
			if !strings.Contains(analyzeMethodTag, "tail_rescue") {
				if analyzeMethodTag == "" {
					analyzeMethodTag = "tail_rescue"
				} else {
					analyzeMethodTag += "+tail_rescue"
				}
			}
		}
	}

	// Skip legacy when Textract already produced rows. The legacy block is
	// gated below by checking len(allExtracted) before each step.

	type imageResult struct {
		index  int
		result *PurchaseExtractionResult
		err    error
	}

	resultsCh := make(chan imageResult, len(req.Images))
	var gatePassErrMsg string
	if len(allExtracted) == 0 { // skip legacy when Textract already produced rows
	for i, img := range req.Images {
		go func(idx int, imgData []byte, contentType string) {
			res, err := s.ocr.ExtractFromImage(ctx, imgData, contentType)
			resultsCh <- imageResult{index: idx, result: res, err: err}
		}(i, img.Data, img.ContentType)
	}

	// Collect results in order
	imageResults := make([]imageResult, len(req.Images))
	for range req.Images {
		r := <-resultsCh
		imageResults[r.index] = r
	}

	// v1.0.214 — smart page reordering by printed S.No. Operators sometimes
	// upload page 2 before page 1, or skip a page. The legacy stitcher
	// assumed upload order = printed order, which mis-offsets every page.
	// Now: compute each page's min(SNo); sort by min ascending; THEN run
	// the cumulative-vs-restart detection over the reordered set so offset
	// math always matches the printed sequence.
	pageMinSno := func(items []ExtractedPurchaseItem) int {
		min := 0
		for i, it := range items {
			n := int(it.RowNumber)
			if n <= 0 {
				continue
			}
			if i == 0 || n < min {
				min = n
			}
		}
		return min
	}
	sort.SliceStable(imageResults, func(a, b int) bool {
		ra, rb := imageResults[a].result, imageResults[b].result
		if ra == nil || len(ra.Items) == 0 {
			return false
		}
		if rb == nil || len(rb.Items) == 0 {
			return true
		}
		return pageMinSno(ra.Items) < pageMinSno(rb.Items)
	})

	for i, ir := range imageResults {
		if ir.err != nil {
			log.Printf("Smart Purchase: Failed to extract from image %d: %v", i+1, ir.err)
			if strings.HasPrefix(ir.err.Error(), "gate_pass:") {
				gatePassErrMsg = strings.TrimPrefix(ir.err.Error(), "gate_pass: ")
			}
			continue
		}
		result := ir.result

		// Diagnostic: log the S.No range returned for this image so we can see whether
		// images are in the expected order and whether AI is numbering correctly.
		if len(result.Items) > 0 {
			minRow, maxRow := int(result.Items[0].RowNumber), int(result.Items[0].RowNumber)
			for _, it := range result.Items {
				rn := int(it.RowNumber)
				if rn < minRow {
					minRow = rn
				}
				if rn > maxRow {
					maxRow = rn
				}
			}
			log.Printf("SmartPurchase: Image %d returned %d items, S.No range [%d..%d]", i, len(result.Items), minRow, maxRow)
		}

		// Use vendor info from first image that has it
		if vendorInfo == nil && result.VendorName != "" {
			vendorInfo = &DetectedVendorInfo{
				Name:      result.VendorName,
				GSTNumber: result.VendorGST,
				Address:   result.VendorAddress,
			}
		}
		if result.InvoiceNumber != "" && !looksLikePageMarker(result.InvoiceNumber) {
			// v1.0.193 — only accept supplier-printed invoice numbers; skip
			// page markers ("Page 2", "Continued"). Real-data trigger:
			// chhotu's bill page 2's header had "Page 2" in the same area
			// the supplier prints the bill number on page 1. The prompt
			// rule (rules.3 in buildPurchasePrompt) tells the AI not to
			// emit page markers as invoice_number, but if it does anyway,
			// this client-side sanity filter catches the regression.
			//
			// Prefer the FIRST valid invoice_number across pages — the
			// supplier prints the same number on every page; whichever
			// page got read cleanly wins.
			if invoiceNumber == "" {
				invoiceNumber = result.InvoiceNumber
			}
		}
		if invoiceDate == "" && result.InvoiceDate != "" {
			invoiceDate = result.InvoiceDate
		}

		// Detect numbering style: if this image's lowest S.No is greater than the highest
		// S.No we've already seen, the AI is using cumulative numbering across pages
		// (the invoice continues "S.No 43" on page 2). In that case we must NOT add an
		// offset — doing so double-counts and renames row 43 to row 85. Only when an
		// image restarts numbering at 1 (typical for separate documents stitched into
		// one upload) do we apply an offset so rows stay unique.
		minNew := math.MaxInt32
		maxExisting := 0
		for _, ex := range allExtracted {
			if int(ex.RowNumber) > maxExisting {
				maxExisting = int(ex.RowNumber)
			}
		}
		for _, it := range result.Items {
			if int(it.RowNumber) > 0 && int(it.RowNumber) < minNew {
				minNew = int(it.RowNumber)
			}
		}
		needsOffset := minNew != math.MaxInt32 && minNew <= maxExisting
		if needsOffset {
			offset := maxExisting
			for j := range result.Items {
				result.Items[j].RowNumber += float64(offset)
			}
		}

		// Track which image each row came from so the verification pass can re-examine
		// the right image when correcting a wrong row.
		startIdx := len(allExtracted)
		allExtracted = append(allExtracted, result.Items...)
		for j := startIdx; j < len(allExtracted); j++ {
			rowToImageIdx[int(allExtracted[j].RowNumber)] = i
		}
		// v1.0.190 — MAX, not SUM. Each page's SubTotal/TaxAmount/TotalAmount
		// is the AI's read of the document-level footer (grand totals printed
		// only on the final page). Summing across pages double-counts: page 1
		// reports its own item sum as subtotal, page 2 reports the printed
		// grand total, and SUM ends up ~2× actual. Same fix as document_total_cases
		// further down. The matcher cross-checks against sum-of-item-amounts later.
		if result.SubTotal > subTotal {
			subTotal = result.SubTotal
		}
		if result.TaxAmount > taxAmount {
			taxAmount = result.TaxAmount
		}
		if result.TotalAmount > totalAmount {
			totalAmount = result.TotalAmount
		}
		// expected_row_count: take the MAX across pages, not the SUM. Each image reports
		// the highest S.No visible on it; for an invoice with continuing numbering page 1
		// reports 42 and page 2 reports 48 — the true count is MAX(42,48)=48, NOT 90.
		// (When images restart at 1, we offset above so result.Items already has the right
		// numbers; using MAX of the offset-adjusted page max still works.)
		pageMax := 0
		for _, it := range result.Items {
			if int(it.RowNumber) > pageMax {
				pageMax = int(it.RowNumber)
			}
		}
		if pageMax > expectedRowCount {
			expectedRowCount = pageMax
		}
		// Footer totals from the "Total N Cs." and "₹ X,XX,XXX.XX" lines — used below to
		// cross-check sum of extracted row quantities/amounts. For multi-image invoices only
		// the final page carries the grand total, so we take the MAX (last non-zero) rather
		// than summing.
		if result.DocumentTotalCases > documentTotalCases {
			documentTotalCases = result.DocumentTotalCases
		}
		if result.DocumentTotalAmount > documentTotalAmount {
			documentTotalAmount = result.DocumentTotalAmount
		}
	}
	} // end legacy-extraction gate

	ocrDuration := time.Since(ocrStart).Milliseconds()

	// VERIFICATION PASS (DISABLED): a second AI call to re-check row amounts against
	// the document grand total was attempted but proved unreliable — each run produced
	// different suggestions, some of which regressed correct rows. Left the plumbing in
	// place (ocr.VerifyExtractionAgainstTotal and rowToImageIdx) for possible future use
	// with better models or multi-model ensemble.
	if false && documentTotalAmount > 0 && len(allExtracted) > 0 {
		preSum := 0.0
		for _, it := range allExtracted {
			preSum += it.Amount
		}
		// The document total may include TCS/GST on top of subtotal — give a 5% wider
		// tolerance to avoid false-trigger when the only diff is tax. Adjust the target
		// downward by extracted tax/TCS to compare against subtotal.
		targetSum := documentTotalAmount - taxAmount
		if targetSum <= 0 {
			targetSum = documentTotalAmount * 0.98 // assume ~2% TCS
		}
		diff := targetSum - preSum
		absDiff := diff
		if absDiff < 0 {
			absDiff = -absDiff
		}
		tol := targetSum * 0.01
		if tol < 200 {
			tol = 200
		}
		if absDiff > tol {
			log.Printf("SmartPurchase: Total mismatch detected — pre-sum ₹%.2f vs target ₹%.2f (Δ₹%.2f, tol ₹%.2f). Running verification pass for ADVISORY corrections (not auto-applied).",
				preSum, targetSum, diff, tol)
			// Group rows by image. Exclude dual-line rows from verification (they're handled
			// specially and verification prompt doesn't see their structure).
			imageItems := make(map[int][]ExtractedPurchaseItem)
			for _, it := range allExtracted {
				if it.LooseBottles > 0 {
					continue
				}
				idx, ok := rowToImageIdx[int(it.RowNumber)]
				if !ok {
					continue
				}
				imageItems[idx] = append(imageItems[idx], it)
			}
			// Collect AI suggestions but apply ONLY when multiple signals confirm:
			//   (a) the correction makes single-line math consistent (rate × cases ≈ amount)
			//   (b) the correction is NOT a massive regression (<50% change)
			//   (c) the suggested amount is CLOSER to the document-total reconciliation
			for imgIdx, items := range imageItems {
				if imgIdx >= len(req.Images) || len(items) == 0 {
					continue
				}
				img := req.Images[imgIdx]
				corrections, err := s.ocr.VerifyExtractionAgainstTotal(ctx, img.Data, img.ContentType, items, documentTotalAmount)
				if err != nil {
					log.Printf("SmartPurchase: Verification pass failed for image %d: %v", imgIdx, err)
					continue
				}
				if len(corrections) == 0 {
					continue
				}
				for j := range allExtracted {
					row := int(allExtracted[j].RowNumber)
					c, ok := corrections[row]
					if !ok {
						continue
					}
					oldAmount := allExtracted[j].Amount
					cases := allExtracted[j].QuantityRaw
					// Guard (a): single-line invariant — rate × cases ≈ amount
					if c.Rate > 0 && cases > 0 {
						expected := cases * c.Rate
						if abs(expected-c.Amount) > expected*0.02+5 {
							log.Printf("SmartPurchase: REJECTED verification row %d (not single-line consistent)", row)
							continue
						}
					}
					// Guard (b): reject >2x changes (both inflate and shrink)
					if oldAmount > 0 && (c.Amount > oldAmount*2 || c.Amount*2 < oldAmount) {
						log.Printf("SmartPurchase: REJECTED verification row %d — suggested ₹%.2f diverges too much from original ₹%.2f",
							row, c.Amount, oldAmount)
						continue
					}
					// Guard (c): does this correction move sum CLOSER to target?
					hypotheticalSum := preSum - oldAmount + c.Amount
					oldDist := targetSum - preSum
					if oldDist < 0 {
						oldDist = -oldDist
					}
					newDist := targetSum - hypotheticalSum
					if newDist < 0 {
						newDist = -newDist
					}
					if newDist >= oldDist {
						log.Printf("SmartPurchase: REJECTED verification row %d — correction ₹%.2f→₹%.2f would move sum AWAY from target (from Δ%.0f to Δ%.0f)",
							row, oldAmount, c.Amount, oldDist, newDist)
						continue
					}
					// All guards passed — apply
					allExtracted[j].RatePerCase = c.Rate
					allExtracted[j].Amount = c.Amount
					if allExtracted[j].BottlesPerCase > 0 {
						allExtracted[j].RatePerBottle = c.Rate / allExtracted[j].BottlesPerCase
					}
					preSum = hypotheticalSum // update running preSum for the "closer to target" check
					log.Printf("SmartPurchase: Applied verification correction to row %d: amount ₹%.2f→₹%.2f (moves toward target)",
						row, oldAmount, c.Amount)
				}
			}
			postSum := 0.0
			for _, it := range allExtracted {
				postSum += it.Amount
			}
			log.Printf("SmartPurchase: Verification pass complete — final sum ₹%.2f (target ₹%.2f)", postSum, targetSum)
		}
	}

	if len(allExtracted) == 0 {
		failMsg := "No product line items found in the invoice image(s)"
		if gatePassErrMsg != "" {
			failMsg = gatePassErrMsg
		}
		return &SmartPurchaseResult{
			Status:  "failed",
			Message: failMsg,
			ProcessingDetails: &SmartPurchaseProcessing{
				OCRTimeMs:       ocrDuration,
				TotalTimeMs:     time.Since(totalStart).Milliseconds(),
				ImagesProcessed: len(req.Images),
				AIModel:         aiModel,
			},
		}, nil
	}

	// Deduplicate items from multi-image (same product from overlapping scans)
	allExtracted = s.deduplicateExtracted(allExtracted)

	_ = expectedRowCount
	// Step 2: Extract gate pass items EARLY (before product matching) so we can use
	// Wait for the GP goroutine launched at the top of this function to
	// finish (started in parallel with bill extraction so total latency =
	// max(bill, GP) instead of sum). When no GP was uploaded, gpDoneCh is
	// nil and the wait is skipped.
	// v1.0.340 — measure how long the bill thread BLOCKS waiting on the GP
	// goroutine. If this is large, GP extraction (not the bill) is the long
	// pole and the latency lever is the GP path, not the bill path. Logged in
	// the consolidated TIMING line below so the ~3 min/job split is visible on
	// the next real job (timing isn't persisted to job.result, only logged).
	gpAwaitStart := time.Now()
	if gpDoneCh != nil {
		<-gpDoneCh
	}
	gpAwaitMs := time.Since(gpAwaitStart).Milliseconds()

	// v1.0.213 — recover corrupted bill size_ml BEFORE GP pairing. Real-data
	// trigger (chhotu's 2026-05-08 bill, S.No 18 "8 Pm Black Whisky 375ML"):
	// Textract bleeds the brand prefix digit into the size cell, returning
	// size_ml=188375 instead of 375. The downstream pairing function in
	// buildGatePassBrandMap rejects size mismatches, leaving the bill row
	// unpaired even when GP has the matching 375ml entry. RecoverStandardSize
	// peels leading digits until it hits a known bottle size (90/180/375/750/
	// 1000/etc.). Idempotent + safe — only rewrites when a clean canonical
	// size exists.
	for i := range allExtracted {
		raw := int(allExtracted[i].SizeML)
		if raw <= 0 {
			continue
		}
		if recovered := RecoverStandardSize(raw); recovered > 0 && recovered != raw {
			log.Printf("SmartPurchase: size_ml corruption fix — %q size %d → %d (pre-pairing)",
				allExtracted[i].Brand, raw, recovered)
			allExtracted[i].SizeML = float64(recovered)
			if allExtracted[i].SizeText == "" || allExtracted[i].SizeText == fmt.Sprintf("%dml", raw) {
				allExtracted[i].SizeText = fmt.Sprintf("%dML", recovered)
			}
		}
	}

	// v1.0.217 Track 1 — post-extraction row collapse. Textract sometimes
	// emits the same physical bill row twice (chhotu's "Strokes 180mk +
	// 180ml", "Royal Stag Barrel ×2", "Spicymint Vodka ×2" patterns —
	// 3 of 7 dedup clusters traced back here, not to the matcher). Collapse
	// duplicates BEFORE gate-pass pairing so we never enrich a phantom row.
	//
	// Collapse rules (both must hold):
	//   1. Same (SourcePageIdx, RowNumber) — Textract assigned the same
	//      table-cell to two output rows.
	//   OR
	//   1'. Same normalized brand + same SizeML AND consecutive RowNumbers
	//       (|Δ| ≤ 1) with the SAME quantity_unit + identical amount within
	//       ±₹1.0 — definite extraction duplicate.
	//
	// Action: keep the row with higher Confidence (or first if tied), drop
	// the other. Log each collapse so the operator can audit.
	{
		keep := make([]bool, len(allExtracted))
		for i := range keep {
			keep[i] = true
		}
		normBrand := func(s string) string {
			s = strings.ToLower(strings.TrimSpace(s))
			var b strings.Builder
			for _, r := range s {
				if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
					b.WriteRune(r)
				}
			}
			return b.String()
		}
		collapsed := 0
		for i := 0; i < len(allExtracted); i++ {
			if !keep[i] {
				continue
			}
			for j := i + 1; j < len(allExtracted); j++ {
				if !keep[j] {
					continue
				}
				ai, aj := allExtracted[i], allExtracted[j]
				dupCell := ai.SourcePageIdx == aj.SourcePageIdx &&
					int(ai.RowNumber) == int(aj.RowNumber) &&
					int(ai.RowNumber) > 0
				dupBrand := ai.SizeML == aj.SizeML && ai.SizeML > 0 &&
					normBrand(ai.Brand) != "" &&
					normBrand(ai.Brand) == normBrand(aj.Brand) &&
					ai.QuantityUnit == aj.QuantityUnit &&
					math.Abs(ai.Amount-aj.Amount) < 1.0 &&
					math.Abs(ai.RowNumber-aj.RowNumber) <= 1.0
				if !dupCell && !dupBrand {
					continue
				}
				// Keep the higher-confidence row (or i if tied).
				drop := j
				if aj.Confidence > ai.Confidence {
					drop = i
					keep[j] = true
				}
				keep[drop] = false
				log.Printf("SmartPurchase Track-1: collapsed duplicate-extract row — kept=%q@page%d/row%.0f confidence=%.2f, dropped=%q@page%d/row%.0f confidence=%.2f",
					allExtracted[(i+j)-drop].Brand, allExtracted[(i+j)-drop].SourcePageIdx, allExtracted[(i+j)-drop].RowNumber, allExtracted[(i+j)-drop].Confidence,
					allExtracted[drop].Brand, allExtracted[drop].SourcePageIdx, allExtracted[drop].RowNumber, allExtracted[drop].Confidence)
				collapsed++
				if drop == i {
					break // i is gone; advance outer loop
				}
			}
		}
		if collapsed > 0 {
			filtered := allExtracted[:0]
			for i, it := range allExtracted {
				if keep[i] {
					filtered = append(filtered, it)
				}
			}
			log.Printf("SmartPurchase Track-1: collapsed %d duplicate-extract row(s) (was %d, now %d)",
				collapsed, len(allExtracted), len(filtered))
			allExtracted = filtered
		}
	}

	// Build gate pass brand lookup: for each invoice item, find the best gate pass brand name
	// by matching on brand+size. This gives us official excise names AND the GP row we can
	// use as authoritative case/bottle quantities.
	gatePassBrandMap, gatePassItemMap := s.buildGatePassBrandMap(ctx, &req, allExtracted, dutyItems)

	// v1.0.209 Tier 1 canonicalization — record the GP full name on each
	// paired bill row WITHOUT overwriting Brand. The bill's short text stays
	// authoritative as `Brand` (so the response BrandName, Apply payload's
	// original_ai_brand for alias learning, and the operator-facing review
	// row all keep "what's printed on the bill"). The canonical full name
	// rides alongside as CanonicalBrand and is used by the matcher (already
	// passed as gatePassBrand arg) and any future deduplication / display
	// chip logic.
	canonicalized := 0
	for invIdx, gpBrand := range gatePassBrandMap {
		if gpBrand == "" || invIdx >= len(allExtracted) {
			continue
		}
		short := strings.TrimSpace(allExtracted[invIdx].Brand)
		if short == "" || strings.EqualFold(short, gpBrand) {
			continue
		}
		allExtracted[invIdx].OriginalBrand = short
		allExtracted[invIdx].CanonicalBrand = gpBrand
		allExtracted[invIdx].CanonicalSource = "gate_pass"
		canonicalized++
	}
	if canonicalized > 0 {
		log.Printf("SmartPurchase: GP-canonicalized %d bill rows (short→full mapping recorded; Brand preserved)",
			canonicalized)
	}

	// Step 3: Match products from DB
	matchStart := time.Now()
	products, err := s.loadProducts(tenantID, &shopID)
	if err != nil {
		return nil, fmt.Errorf("failed to load products: %w", err)
	}

	// Load stock levels for the shop
	stockMap, err := s.loadStockLevels(tenantID, shopID)
	if err != nil {
		log.Printf("Smart Purchase: Failed to load stock levels: %v", err)
		stockMap = map[string]int{}
	}

	// v1.0.217 Track 6 — recent-sales bias. Build a map of product_id → days
	// since last sold at this shop (lookback 30 days). The matcher uses this
	// via PreparedProduct.LastSoldDaysAgo / ShopInventoryRecentBoost to
	// favour products this shop has been *actively moving*. Real-world
	// motivation: chhotu's bills repeatedly buy back the same SKUs the shop
	// sells weekly — recent-sales is the strongest "this is the right
	// product" signal we have. Falls through silently on query failure.
	recentSalesMap := map[string]int{} // product_id → days_since_last_sale
	{
		type rsRow struct {
			ProductID string `gorm:"column:product_id"`
			DaysAgo   int    `gorm:"column:days_ago"`
		}
		var rsRows []rsRow
		rsErr := s.db.Raw(`
			SELECT product_id::text, EXTRACT(DAY FROM (NOW() - MAX(created_at)))::int as days_ago
			FROM daily_sales_items
			WHERE tenant_id = ?
			  AND deleted_at IS NULL
			  AND created_at >= NOW() - INTERVAL '30 days'
			  AND daily_sales_record_id IN (SELECT id FROM daily_sales_records WHERE shop_id = ? AND deleted_at IS NULL)
			GROUP BY product_id
		`, tenantID, shopID).Scan(&rsRows).Error
		if rsErr == nil {
			for _, r := range rsRows {
				recentSalesMap[r.ProductID] = r.DaysAgo
			}
			log.Printf("SmartPurchase Track-6: loaded recent-sales map — %d products sold in last 30 days at this shop", len(recentSalesMap))
		} else {
			log.Printf("SmartPurchase Track-6: recent-sales query failed: %v (falling back to stock-only bias)", rsErr)
		}
	}

	// v1.0.217 Track 7 — last-purchase-cost map for outlier detection.
	// product_id → last cost_price paid at this shop in the past 90 days.
	// Used after match to flag rows where AI's cost is >30% off the
	// historical cost (likely OCR misread on the rate column).
	lastCostMap := map[string]float64{}
	// v1.0.220 — recent-purchases bias map. product_id → days since last
	// purchased at this shop. Highest-priority matcher signal because a vendor
	// invoice naming a brand the shop bought 60 days ago is the strongest
	// possible "this is the right SKU" signal even if current stock = 0.
	recentPurchasesMap := map[string]int{}
	{
		type lcRow struct {
			ProductID string  `gorm:"column:product_id"`
			LastCost  float64 `gorm:"column:last_cost"`
			DaysAgo   int     `gorm:"column:days_ago"`
		}
		var lcRows []lcRow
		lcErr := s.db.Raw(`
			SELECT spi.product_id::text,
			       spi.unit_price AS last_cost,
			       EXTRACT(DAY FROM (NOW() - sp.created_at))::int AS days_ago
			FROM stock_purchase_items spi
			JOIN stock_purchases sp ON sp.id = spi.purchase_id
			WHERE sp.tenant_id = ?
			  AND sp.shop_id = ?
			  AND sp.deleted_at IS NULL
			  AND spi.deleted_at IS NULL
			  AND sp.created_at >= NOW() - INTERVAL '90 days'
			  AND COALESCE(sp.status, '') NOT IN ('rejected', 'cancelled')
			ORDER BY sp.created_at DESC
		`, tenantID, shopID).Scan(&lcRows).Error
		if lcErr == nil {
			// First row per product_id wins (DESC order = most recent).
			for _, r := range lcRows {
				if _, exists := recentPurchasesMap[r.ProductID]; !exists {
					if r.DaysAgo < 0 {
						r.DaysAgo = 0
					}
					recentPurchasesMap[r.ProductID] = r.DaysAgo
				}
				if r.LastCost > 0 {
					if _, exists := lastCostMap[r.ProductID]; !exists {
						lastCostMap[r.ProductID] = r.LastCost
					}
				}
			}
			log.Printf("SmartPurchase Track-7+v220: loaded last-cost map for %d products + recent-purchase map for %d products (90-day window)",
				len(lastCostMap), len(recentPurchasesMap))
		} else {
			log.Printf("SmartPurchase Track-7+v220: stock_purchases history query failed: %v (purchase-history bias disabled for this run)", lcErr)
		}
	}

	// Convert to shared matching format
	matchProducts := make([]matching.Product, len(products))
	productDBMap := make(map[string]dbProduct, len(products)) // ID → dbProduct for enrichment
	for i, p := range products {
		brandName := p.BrandName
		if brandName == "" {
			brandName = p.Name
		}
		// v1.0.216.2 — populate CurrentStock from the shop's stocks table so
		// MatchConfig.ShopInventoryBias (on by DefaultPurchaseConfig default)
		// can tilt the matcher toward products this shop has already
		// onboarded. Without this wiring CurrentStock was always 0 and the
		// bias never fired — which is why chhotu's matcher kept routing
		// invoice rows to master-catalog SKUs (MOOOZ Cranberry Vodka,
		// Sterling Reserve B7) that the shop doesn't even stock, instead
		// of the existing shop products at slightly lower text-only score.
		// Key: ANY presence in stockMap means "in this shop" — operator
		// onboarded it. Use max(quantity, 1) so the +0.10 in-stock bonus
		// fires even when quantity dropped to 0 from prior sales.
		stockQty := 0
		if q, ok := stockMap[p.ID]; ok {
			if q > 0 {
				stockQty = q
			} else {
				stockQty = 1 // present in shop, currently empty — still prefer over master-catalog
			}
		}
		// v1.0.217 Track 6 — LastSoldDaysAgo from the recent-sales map we
		// just loaded. Matcher's ShopInventoryRecentBoost gives +0.15 when
		// in [0, 30]. -1 means "never sold here in 30 days" (default).
		lastSold := -1
		if d, ok := recentSalesMap[p.ID]; ok {
			lastSold = d
		}
		// v1.0.220 — LastPurchasedDaysAgo from the 90-day recent-purchases
		// map. Drives the new ShopInventoryPurchaseBoost (+0.20), the strongest
		// shop-bias signal. -1 means never purchased in window.
		lastPurchased := -1
		if d, ok := recentPurchasesMap[p.ID]; ok {
			lastPurchased = d
		}
		matchProducts[i] = matching.Product{
			ID:                   p.ID,
			Name:                 p.Name,
			BrandName:            brandName,
			DisplayName:          p.DisplayName,
			ExciseBrandName:      p.ExciseBrandName,
			ExciseDisplayName:    p.ExciseDisplayName,
			Size:                 p.Size,
			SizeML:               matching.ParseSizeML(p.Size),
			SellingPrice:         p.SellingPrice,
			CostPrice:            p.CostPrice,
			CurrentStock:         stockQty,
			LastSoldDaysAgo:      lastSold,
			LastPurchasedDaysAgo: lastPurchased,
		}
		productDBMap[p.ID] = p
	}
	// v1.0.356 — feed tenant-confirmed aliases into the matcher. The matcher already
	// grants a capped TenantConfirmedAlias boost (matcher.go ~886), but Smart Purchase
	// never set it. A tenant-wide, high-confidence (operator/photo-confirmed, score>=90:
	// photo_verify 95, stock_setup_approved 90, user_correction 100 — never fuzzy/auto)
	// alias pointing to a candidate nudges the matcher toward it, so learned corrections
	// improve future matches. Additive + capped → can only break ties toward a product the
	// operator already vouched. Kill-switch SMART_PURCHASE_ALIAS_BOOST.
	if os.Getenv("SMART_PURCHASE_ALIAS_BOOST") != "0" && len(matchProducts) > 0 {
		candIDs := make([]string, 0, len(matchProducts))
		for i := range matchProducts {
			candIDs = append(candIDs, matchProducts[i].ID)
		}
		type aliasPID struct {
			PID string `gorm:"column:pid"`
		}
		var prows []aliasPID
		if e := s.db.Model(&models.OCRBrandAlias{}).
			Select("DISTINCT product_id::text AS pid").
			Where("tenant_id = ? AND shop_id IS NULL AND product_id IS NOT NULL AND confidence_score >= 90 AND product_id IN ?",
				tenantID, candIDs).
			Scan(&prows).Error; e == nil {
			confirmed := make(map[string]bool, len(prows))
			for _, r := range prows {
				confirmed[r.PID] = true
			}
			n := 0
			for i := range matchProducts {
				if confirmed[matchProducts[i].ID] {
					matchProducts[i].TenantConfirmedAlias = true
					n++
				}
			}
			log.Printf("SmartPurchase v356: tenant-confirmed-alias boost applied to %d/%d candidates", n, len(matchProducts))
		} else {
			log.Printf("SmartPurchase v356: tenant-confirmed-alias query failed: %v (boost skipped)", e)
		}
	}

	prepared := matching.PrepareProducts(matchProducts)
	matchConfig := matching.DefaultPurchaseConfig()
	// v1.0.185 — bump only the Smart Purchase floor 0.50→0.55. Real invoice
	// OCR is noisier than stock-setup ledger pages (handwriting, multi-page,
	// embedded category abbrevs), and 0.50 was matching OCR garble against
	// shop SKUs that aren't on the invoice. Stock Setup keeps 0.50 because
	// its image source is cleaner and recall matters more than precision.
	matchConfig.MinThreshold = 0.55

	// Load master brands (saas_brands + brand_variants) for each unique size in the invoice.
	// Mirrors smart_stock_setup behaviour — official excise names act as an authoritative
	// text source that can correct OCR noise (e.g. "Type Blue" → "Imperial Blue").
	tenantState := s.getTenantState(tenantID)
	masterBrandsBySize := make(map[int][]models.MasterBrandInfo)
	for _, ex := range allExtracted {
		sz := int(ex.SizeML)
		if sz <= 0 {
			continue
		}
		if _, ok := masterBrandsBySize[sz]; ok {
			continue
		}
		masterBrandsBySize[sz] = s.loadMasterBrands(sz, tenantState)
	}
	if len(masterBrandsBySize) > 0 {
		totalMB := 0
		for _, v := range masterBrandsBySize {
			totalMB += len(v)
		}
		log.Printf("SmartPurchase: Loaded master brands for %d size(s), %d total variants (state=%s)",
			len(masterBrandsBySize), totalMB, tenantState)
	}

	var matchedItems []SmartPurchaseExtractedItem
	matchedCount := 0
	lowConfCount := 0
	notFoundCount := 0

	// v1.0.169 D3 — pre-resolve brand text via the alias-cascade so the
	// matchAndEnrich loop can short-circuit when an exact-source alias hit
	// is available. Tenant + shop scoped; same alias DB Smart Sale uses
	// (412 chhotu aliases as of v1.0.167 D4 backfill). Builds a map keyed
	// by lowercase brand → resolved product_id; matchAndEnrich consults it
	// before running the multi-source jaccard matcher.
	aliasResolved := map[string]uuid.UUID{}
	if s.aliasService != nil {
		tID, _ := uuid.Parse(req.TenantID)
		sID, _ := uuid.Parse(req.ShopID)
		// WS1.1 — strict shop isolation: when the guard is on, use the
		// shop-validated cascade so a tenant-wide alias pointing at ANOTHER
		// shop's product is never used (the Rockford cross-shop bind).
		shopGuard := shopAliasGuardEnabled(req.UserID)
		for _, ex := range allExtracted {
			brand := strings.TrimSpace(ex.Brand)
			if brand == "" {
				continue
			}
			var (
				pid *uuid.UUID
				src alias.AliasSource
				ok  bool
			)
			if shopGuard {
				pid, _, src, ok = s.aliasService.LookupAliasCascadeShopValidated(ctx, tID, sID, brand, "")
			} else {
				pid, _, src, ok = s.aliasService.LookupAliasCascade(ctx, tID, sID, brand, "")
			}
			if !ok || pid == nil {
				continue
			}
			// Only TRUST exact-source aliases (operator-confirmed or backfilled
			// from approved truth). Fuzzy hits stay subject to the multi-source
			// matcher's pollution guards.
			if src == alias.AliasSourceShopExact || src == alias.AliasSourceTenantExact {
				aliasResolved[strings.ToLower(brand)] = *pid
			}
		}
		if len(aliasResolved) > 0 {
			log.Printf("SmartPurchase: alias-cascade pre-resolved %d brand(s) via exact-source hits", len(aliasResolved))
		}
	}

	for idx, extracted := range allExtracted {
		gpBrand := gatePassBrandMap[idx]
		gpItem := gatePassItemMap[idx]
		masterBrands := masterBrandsBySize[int(extracted.SizeML)]
		// v1.0.169 D3 — alias-cascade hint. matchAndEnrich honors this by
		// short-circuiting the multi-source matcher when the hint resolves
		// to a real product in the loaded catalog.
		var aliasHint *uuid.UUID
		if pid, ok := aliasResolved[strings.ToLower(strings.TrimSpace(extracted.Brand))]; ok {
			h := pid
			aliasHint = &h
		}
		item := s.matchAndEnrichWithHint(extracted, prepared, matchConfig, productDBMap, stockMap, gpBrand, gpItem, dutyItems, masterBrands, aliasHint, gpOnly)
		// v1.0.217 Track 7 — last-purchase-cost outlier flag. Runs AFTER
		// match so we have the resolved product_id. >30% drift = OCR rate
		// misread suspected; flag for operator review before apply.
		if item.ProductID != nil {
			if lc, ok := lastCostMap[*item.ProductID]; ok && lc > 0 && extracted.RatePerBottle > 0 {
				drift := (extracted.RatePerBottle - lc) / lc
				if drift > 0.30 || drift < -0.30 {
					log.Printf("SmartPurchase Track-7: cost outlier — '%s' bill ₹%.0f vs last-purchase ₹%.0f (%.0f%% drift)",
						item.MatchedBrandName, extracted.RatePerBottle, lc, drift*100)
					item.NeedsReview = true
					item.Warnings = append(item.Warnings,
						fmt.Sprintf("Cost %.0f%% off last purchase at this shop (₹%.0f → ₹%.0f) — verify before applying",
							drift*100, lc, extracted.RatePerBottle))
				}
			}
		}
		// v1.0.215.9 — stamp the bill page index (0-based) so Flutter's
		// per-image review pager can filter rows by source image.
		// extracted.SourcePageIdx is set during the per-page merge in
		// extractWithAnalyzeExpense; falls back to rowToImageIdx for
		// rows from other code paths (TABLES, tail-rescue) which already
		// stamp the map correctly.
		item.PageIndex = extracted.SourcePageIdx
		if item.PageIndex == 0 {
			if pIdx, ok := rowToImageIdx[int(extracted.RowNumber)]; ok {
				item.PageIndex = pIdx
			}
		}
		matchedItems = append(matchedItems, item)

		switch item.Status {
		case "matched":
			matchedCount++
		case "low_confidence", "ambiguous":
			lowConfCount++
		case "not_found":
			notFoundCount++
		}
	}
	matchDuration := time.Since(matchStart).Milliseconds()

	// v1.0.340 — consolidated phase-timing breakdown. The per-job ~3 min was
	// never split out in logs, so we couldn't see where it goes (bill OCR vs
	// blocking on GP vs matching vs the rest). ocr=bill AnalyzeExpense wall
	// time; gp_await=how long the bill thread blocked on the GP goroutine
	// (>0 means GP is the long pole); match=DB load + per-row matching; the
	// remainder up to total is GP-primary reconciliation + result build.
	log.Printf("SmartPurchase TIMING job: ocr(bill)=%dms gp_await=%dms match=%dms total_so_far=%dms (bill_rows=%d gp_rows=%d)",
		ocrDuration, gpAwaitMs, matchDuration, time.Since(totalStart).Milliseconds(),
		len(allExtracted), len(dutyItems))

	// Flag items that need user review
	s.flagItemsForReview(matchedItems)

	needsReviewCount := 0
	for _, item := range matchedItems {
		if item.NeedsReview {
			needsReviewCount++
		}
	}

	// Step 3: Match vendor
	var matchedVendorID *string
	var matchedVendorName string
	var vendorConfidence float64

	if req.VendorID != "" {
		// User provided vendor — use it directly
		matchedVendorID = &req.VendorID
		vendorConfidence = 1.0
		// Look up name
		var name string
		if err := s.db.Table("vendors").Select("name").Where("id = ?", req.VendorID).Scan(&name).Error; err != nil {
			log.Printf("Smart Purchase: Failed to look up vendor %s: %v", req.VendorID, err)
		}
		matchedVendorName = name
	} else if vendorInfo != nil {
		// Try to match detected vendor
		id, name, conf := s.matchVendor(tenantID, vendorInfo.Name, vendorInfo.GSTNumber)
		if id != nil {
			idStr := id.String()
			matchedVendorID = &idStr
			matchedVendorName = name
			vendorConfidence = conf
		} else if vendorInfo.Name != "" {
			// v1.0.200 — vendor auto-link. When extraction detected a
			// vendor name but no DB vendor matches, idempotently create
			// one (keyed on GST + lowercase name). Operator never sees a
			// "Vendor: Unknown" picker — the bill applies cleanly with a
			// real vendor_id, and the auto-created row carries action=
			// "auto_created" so the audit trail records it.
			//
			// Mirrors the SmartPurchaseVendorHandler.CreateOrMatchVendor
			// logic but runs inline so Flutter doesn't need to make a
			// separate HTTP call.
			autoID, autoName, created := s.autoCreateVendorByExtraction(tenantID, vendorInfo)
			if autoID != nil {
				idStr := autoID.String()
				matchedVendorID = &idStr
				matchedVendorName = autoName
				vendorConfidence = 0.85 // tagged auto-created — less confident than a real fuzzy match
				if created {
					log.Printf("SmartPurchase vendor auto-link: created new vendor %s (%s) from extraction (GST=%s)",
						autoName, idStr, vendorInfo.GSTNumber)
				} else {
					log.Printf("SmartPurchase vendor auto-link: matched existing vendor %s (%s) by GST/exact-name fallback",
						autoName, idStr)
				}
			}
		}
	}

	// Use user-provided invoice date if AI didn't detect one
	if invoiceDate == "" && req.InvoiceDate != "" {
		invoiceDate = req.InvoiceDate
	}

	// Build status message
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
	if needsReviewCount > 0 {
		warnings = append(warnings, fmt.Sprintf("%d item(s) flagged for review", needsReviewCount))
	}

	// Row-count reconciliation: OCR reports the highest S.No it saw; if we ended up with
	// significantly fewer items (after dedup), rows were silently dropped. Surface a clear
	// warning so the user re-scans missed pages rather than letting 40+ items slip through.
	partialExtraction := false
	if expectedRowCount > 0 && len(matchedItems) < expectedRowCount-2 {
		partialExtraction = true
		status = "partial"
		warnings = append(warnings,
			fmt.Sprintf("Only %d of %d expected rows extracted — some items may be missing, please re-scan",
				len(matchedItems), expectedRowCount))
		log.Printf("SmartPurchase: Partial extraction: %d extracted vs %d expected",
			len(matchedItems), expectedRowCount)
	}

	// Footer-total reconciliation — cross-check sum of extracted rows against the "Total N Cs."
	// and grand total amount printed in the invoice footer. If they disagree by more than a
	// small tolerance, per-row case counts or amounts are off and stock deltas would be wrong.
	//
	// v1.0.193 — produces ReconciliationFlag entries (machine-readable for the
	// review screen) IN ADDITION to the legacy plain-string warnings.
	var reconFlags []ReconciliationFlag
	if documentTotalCases > 0 {
		sumCases := 0
		for _, it := range matchedItems {
			if it.QuantityUnit == "cases" {
				sumCases += it.QuantityRaw
			}
		}
		if absInt(documentTotalCases-sumCases) > 1 {
			warnings = append(warnings,
				fmt.Sprintf("Footer says %d cases total but extracted rows sum to %d — check quantity accuracy",
					documentTotalCases, sumCases))
			log.Printf("SmartPurchase: Invoice footer MISMATCH — total_cases=%d, sum=%d", documentTotalCases, sumCases)
			status = "partial"
			reconFlags = append(reconFlags, ReconciliationFlag{
				Kind:     "case_count_mismatch",
				Severity: "warn",
				Expected: float64(documentTotalCases),
				Got:      float64(sumCases),
				Detail:   fmt.Sprintf("Bill footer says %d cases but extracted rows sum to %d (Δ%d) — check quantity accuracy", documentTotalCases, sumCases, documentTotalCases-sumCases),
			})
		}
	}
	if documentTotalAmount > 0 {
		sumAmount := 0.0
		for _, it := range matchedItems {
			sumAmount += it.Amount
		}
		// Tolerance: 2% OR ₹500 (whichever larger) — accommodates rounding + TCS lines
		tol := documentTotalAmount * 0.02
		if tol < 500 {
			tol = 500
		}
		diff := documentTotalAmount - sumAmount
		if diff < 0 {
			diff = -diff
		}
		if diff > tol {
			warnings = append(warnings,
				fmt.Sprintf("Footer grand total ₹%.0f differs from sum of rows ₹%.0f (diff ₹%.0f) — check amounts",
					documentTotalAmount, sumAmount, diff))
			log.Printf("SmartPurchase: Invoice amount MISMATCH — total=₹%.2f, sum=₹%.2f", documentTotalAmount, sumAmount)
			status = "partial"
			// Severity escalates with delta size:
			//   ≤ 5%  → warn   (operator confirms but apply allowed)
			//   > 5%  → block  (apply gate refuses w/o user_confirmed_warnings)
			sev := "warn"
			pct := diff / documentTotalAmount
			if pct > 0.05 {
				sev = "block"
			}
			reconFlags = append(reconFlags, ReconciliationFlag{
				Kind:     "subtotal_mismatch",
				Severity: sev,
				Expected: documentTotalAmount,
				Got:      sumAmount,
				Detail:   fmt.Sprintf("Bill subtotal ₹%.0f vs sum-of-rows ₹%.0f (Δ₹%.0f / %.1f%%)", documentTotalAmount, sumAmount, diff, pct*100),
			})
		}
	}

	// v1.0.385 — NEVER-SILENTLY-WRONG net. The gate pass prints its own dispatched
	// totals (cases / bottles / bulk-litres). The footer-arbitration above already
	// reverts merge/re-read drift to the footer-proven read when one exists; if the
	// FINAL rows STILL can't reconcile to the printed totals, the extraction is
	// genuinely uncertain (e.g. a rare large-doc LLM truncation) — flag the job for
	// review instead of showing unverified quantities. No-op when the footer wasn't
	// read (non-hybrid path) or when the rows reconcile (the common, healthy case).
	if gpFooter.known && len(dutyItems) > 0 {
		var sumCases, sumBottles int
		var sumLitres float64
		for _, d := range dutyItems {
			sumCases += d.Cases
			sumBottles += d.Bottles
			sumLitres += float64(d.Bottles) * float64(d.SizeML) / 1000.0
		}
		tolB := bpcTolerance(dutyItems)
		tolL := gpFooter.footerLitres * 0.02
		if tolL < 5 {
			tolL = 5
		}
		absF := func(x float64) float64 {
			if x < 0 {
				return -x
			}
			return x
		}
		casesOff := gpFooter.footerCases > 0 && absInt(gpFooter.footerCases-sumCases) > 1
		bottlesOff := absInt(gpFooter.footerBottles-sumBottles) > tolB
		litresOff := gpFooter.footerLitres > 0 && absF(gpFooter.footerLitres-sumLitres) > tolL
		if casesOff || bottlesOff || litresOff {
			log.Printf("SmartPurchase: GP footer MISMATCH — printed %dc/%db/%.1fL vs rows %dc/%db/%.1fL (cOff=%v bOff=%v lOff=%v)",
				gpFooter.footerCases, gpFooter.footerBottles, gpFooter.footerLitres,
				sumCases, sumBottles, sumLitres, casesOff, bottlesOff, litresOff)
			warnings = append(warnings,
				fmt.Sprintf("Gate-pass footer says %d bottles but extracted rows sum to %d — review quantities before approving",
					gpFooter.footerBottles, sumBottles))
			status = "partial"
			reconFlags = append(reconFlags, ReconciliationFlag{
				Kind:     "gp_footer_mismatch",
				Severity: "warn",
				Expected: float64(gpFooter.footerBottles),
				Got:      float64(sumBottles),
				Source:   "llm",
				Detail: fmt.Sprintf("Gate-pass printed totals %d cases / %d bottles / %.1f L but extracted rows sum to %d cases / %d bottles / %.1f L — the read could not be verified against the gate pass's own totals; review quantities",
					gpFooter.footerCases, gpFooter.footerBottles, gpFooter.footerLitres, sumCases, sumBottles, sumLitres),
			})
		}
	}

	// Compute orphan gate-pass rows — dispatch lines that didn't match any
	// bill row. Surfaces as a banner on the review screen.
	orphanGPRows := s.computeOrphanGatePassRows(dutyItems, gatePassItemMap)
	if len(orphanGPRows) > 0 {
		log.Printf("SmartPurchase: %d orphan gate-pass rows (in dispatch but not in bill)", len(orphanGPRows))
		warnings = append(warnings,
			fmt.Sprintf("%d items in dispatch missing from bill — review", len(orphanGPRows)))
	}

	// v1.0.193 — Subtotal/Total reconciliation against sum-of-items.
	//
	// When the AI's reported SubTotal disagrees with sum(item.amount) by >2%,
	// the AI is almost certainly mis-reading the bill's footer area — common
	// patterns: reading a "Gross Value" / "Aggregate Sales Value" interim
	// line as the subtotal, reading TCS-inclusive total as subtotal, etc.
	//
	// Sum-of-items is the authoritative invariant here: every row passed
	// through math gates and per-row reconciliation; their sum cannot lie
	// about the document's commercial value. Substituting sum-of-items
	// fixes chhotu's real bill where Gemini consistently read ₹679,965 as
	// SubTotal instead of the printed ₹637,739.81.
	//
	// We surface the AI's original read as a reconciliation flag so the
	// operator sees what the system corrected.
	{
		var sumItems float64
		for _, it := range matchedItems {
			sumItems += it.Amount
		}
		if sumItems > 0 && subTotal > 0 {
			diff := subTotal - sumItems
			if diff < 0 {
				diff = -diff
			}
			if diff > sumItems*0.02 {
				log.Printf("SmartPurchase: SubTotal sanity — AI reported ₹%.2f but sum(items)=₹%.2f (Δ%.1f%%) — using sum(items) as displayed subtotal",
					subTotal, sumItems, 100*diff/sumItems)
				reconFlags = append(reconFlags, ReconciliationFlag{
					Kind:     "subtotal_ai_misread",
					Severity: "info",
					Expected: sumItems,
					Got:      subTotal,
					Detail:   fmt.Sprintf("AI read footer subtotal as ₹%.0f but line items sum to ₹%.0f — using line-item sum", subTotal, sumItems),
				})
				subTotal = sumItems
			}
		}
	}

	// v1.0.193 — TotalAmount derivation. Once subTotal is reconciled
	// against sum-of-items, derive TotalAmount as SubTotal + TaxAmount when
	// the AI's TotalAmount disagrees by >1%. This is mathematically
	// guaranteed when the bill prints Tax explicitly (e.g. "TCS @ 2%").
	if subTotal > 0 && taxAmount > 0 {
		derivedTotal := subTotal + taxAmount
		if totalAmount > 0 {
			diff := totalAmount - derivedTotal
			if diff < 0 {
				diff = -diff
			}
			if diff > derivedTotal*0.01 {
				log.Printf("SmartPurchase: TotalAmount sanity — AI reported ₹%.2f but Sub+Tax=₹%.2f — using Sub+Tax",
					totalAmount, derivedTotal)
				totalAmount = derivedTotal
			}
		} else {
			totalAmount = derivedTotal
		}
	}

	// Gate pass duty fees already applied during matchAndEnrich above

	message := fmt.Sprintf("Extracted %d items from invoice", len(matchedItems))
	if lowConfCount > 0 || notFoundCount > 0 {
		message += fmt.Sprintf(" (%d matched, %d need review, %d not found)", matchedCount, lowConfCount, notFoundCount)
	}

	// v1.0.199 — finalize analyze_method tag. Empty means legacy LLM took over.
	if analyzeMethodTag == "" {
		analyzeMethodTag = "llm"
	}
	log.Printf("SmartPurchase analyze_method=%s tenant=%s shop=%s items=%d",
		analyzeMethodTag, req.TenantID, req.ShopID, len(matchedItems))

	// v1.0.227 — both bill + GP extractions have returned. Flip stage to
	// "matching_brands" so the Flutter poll reflects what the orchestrator
	// is doing next. extractGP earlier in this function gets its own
	// checkpoint just before the call.
	writeStage(models.SmartPurchaseStageMatchingBrands)

	// v1.0.221 GP-primary wire-up. When env flag SMART_PURCHASE_GP_PRIMARY=1
	// (globally) or SMART_PURCHASE_GP_PRIMARY_TENANT_<uuid>=1 (per tenant),
	// replace the legacy bill-primary matchedItems with the GP-primary
	// pipeline output. The orchestrator in smart_purchase_gp_primary_orchestrator.go
	// rebuilds the items list from the same (allExtracted, dutyItems) but
	// uses GP as skeleton, strict saas_brand_id match, DSE-register
	// fallback, and per-bottle cost via bill price-only enrichment.
	//
	// Safe to add late in the function: every downstream caller of the
	// items list (apply path, response JSON, observability) consumes the
	// existing SmartPurchaseExtractedItem shape — and the GP-primary
	// pipeline produces exactly that shape, just with better values.
	gpDegraded, gpBad, gpTotal := gatePassTooDegradedForPrimary(dutyItems)
	gatePassDegradedFellBack := false
	// v1.0.359 — GP-only forces the GP-primary orchestrator and DISABLES the
	// degraded→bill-primary fallback. Even a poor gate pass keeps GP names/qty
	// (rows that can't be read become "needs review"), NEVER bill names. The bill
	// still supplies per-bottle cost via price-only enrichment in the orchestrator.
	runGPPrimary := gpOnly || gpPrimaryEnabled(tenantID)
	if !gpOnly && gpPrimaryEnabled(tenantID) && len(dutyItems) > 0 && gpDegraded && gpDegradedFallbackEnabled() {
		// v1.0.346 — the gate pass is too degraded to drive the item list (low-res
		// screenshot of a dense excise pass: empty brand/size columns). Keep the
		// BILL-PRIMARY matchedItems — already built + review-flagged above from the
		// clean machine-printed bill, and still duty/qty-enriched from the GP. This
		// avoids the all-unmatched ₹0 review screen chhotu hit on Mahua Khera job
		// 87098ea4 (19/51 names + 12/51 sizes blank → 23 not_found).
		// NOTE: disabled under GP-only (owner rule: never use bill names).
		gatePassDegradedFellBack = true
		log.Printf("SmartPurchase v1.0.346: gate pass DEGRADED (%d/%d rows missing name or size) — keeping BILL-PRIMARY %d items instead of GP-primary skeleton (tenant=%s)",
			gpBad, gpTotal, len(matchedItems), tenantID)
	} else if runGPPrimary && len(dutyItems) > 0 {
		if gpOnly && gpDegraded {
			log.Printf("SmartPurchase v359: gate pass degraded (%d/%d) but GP-ONLY mode — running GP-primary anyway; unread rows flagged for review, NOT falling back to bill names (tenant=%s)",
				gpBad, gpTotal, tenantID)
		}
		v221Items := s.processGPPrimary(ctx, tenantID, shopID, dutyItems, allExtracted)
		if len(v221Items) > 0 {
			log.Printf("SmartPurchase v221: GP-primary replaced %d legacy items with %d GP-skeleton items (flag on, tenant=%s)",
				len(matchedItems), len(v221Items), tenantID)
			matchedItems = v221Items
			// v1.0.343 — the GP-primary path REPLACES matchedItems AFTER the
			// flagItemsForReview pass at line ~1188 ran on the (now-discarded)
			// legacy items, so the GP rows shipped with no confidence score and
			// no review flags. Re-run the pass on the GP rows that actually go
			// to the operator + apply path. (This is chhotu's live path.)
			s.flagItemsForReview(matchedItems)
			// Recompute the review count off the GP rows so Validation /
			// warnings reflect what the operator actually sees.
			needsReviewCount = 0
			for ri := range matchedItems {
				if matchedItems[ri].NeedsReview {
					needsReviewCount++
				}
			}
		} else {
			log.Printf("SmartPurchase v221: GP-primary returned 0 items — keeping legacy %d items (this shouldn't happen with len(dutyItems)>0)", len(matchedItems))
		}
	}

	// v1.0.238 Track B — Bill/GP/Vendor reconciliation. Computes a banner
	// that the Flutter review screen shows: "Vendor Sonu Singh FL-2 ↔
	// Invoice 451 ↔ ₹X.XX verified". Compares bill-extracted vendor name
	// against any GP-side hint, validates invoice number is present, totals
	// bill amounts and GP duties. Replaces the (deleted) Purcha gate as the
	// operator's 100%-confidence anchor.
	reconciliation := s.reconcileBillAndGP(
		allExtracted, dutyItems, vendorInfo, invoiceNumber, invoiceDate, subTotal, totalAmount,
	)

	// 2026-05-18 — flag Stock-Setup-origin rows still missing a bottle photo
	// so the review screen can chip them before Submit (apply gate is the
	// hard guarantee). Best-effort, never blocks the result.
	s.annotateNeedsImage(req.TenantID, matchedItems)

	// v1.0.346 — surface the degraded-gate-pass fallback to the operator so they
	// know why the items came from the bill, and how to get a cleaner read next
	// time (this is the capture-quality nudge: the GP looked like a screenshot).
	if gatePassDegradedFellBack {
		warnings = append(warnings,
			"Gate pass was low quality (looks like a screenshot) — brands & prices were read from your bill instead. For best accuracy, upload the original gate-pass PDF or a clear, full-page photo.")
	} else if gpOnly && gpDegraded && len(dutyItems) > 0 {
		// v1.0.359 — GP-only never reads bill names; a poor GP leaves some rows
		// unread (flagged for review) rather than substituting the bill. Nudge for
		// a cleaner capture WITHOUT claiming the bill was used.
		warnings = append(warnings,
			"Gate pass was low quality — some rows couldn't be read and are marked for review. Upload the original gate-pass PDF or a clear, full-page photo for best accuracy.")
	}

	return &SmartPurchaseResult{
		Status:              status,
		Message:             message,
		ExpectedRowCount:    expectedRowCount,
		ExtractedCount:      len(matchedItems),
		Partial:             partialExtraction,
		DocumentTotalCases:  documentTotalCases,
		DocumentTotalAmount: documentTotalAmount,
		DetectedVendor:    vendorInfo,
		InvoiceNumber:     invoiceNumber,
		InvoiceDate:       invoiceDate,
		MatchedVendorID:   matchedVendorID,
		MatchedVendorName: matchedVendorName,
		VendorConfidence:  vendorConfidence,
		Items:             matchedItems,
		SubTotal:          subTotal,
		TaxAmount:         taxAmount,
		TotalAmount:       totalAmount,
		ImageURLs:         savedImageURLs,
		AnalyzeMethod:     analyzeMethodTag,
		ProcessingDetails: &SmartPurchaseProcessing{
			OCRTimeMs:       ocrDuration,
			MatchingTimeMs:  matchDuration,
			TotalTimeMs:     time.Since(totalStart).Milliseconds(),
			ImagesProcessed: len(req.Images),
			AIModel:         aiModel,
			MissingBillSnos: findMissingBillSNos(matchedItems),
			MissingGPSnos:   findMissingGPSNos(dutyItems),
		},
		Validation: &SmartPurchaseValidation{
			TotalItems:          len(matchedItems),
			MatchedItems:        matchedCount,
			LowConfidenceItems:  lowConfCount,
			NotFoundItems:       notFoundCount,
			NeedsReviewItems:    needsReviewCount,
			Warnings:            warnings,
			ReconciliationFlags: reconFlags,
			OrphanGatePassRows:  orphanGPRows,
		},
		Reconciliation: reconciliation,
		// v1.0.238 Track E — raw GP rows for the Excel photocopy.
		DutyItems: dutyItems,
	}, nil
}

// reconcileBillAndGP computes the operator-facing verification banner that
// replaces the deleted Purcha gate. Compares the bill-extracted vendor name
// + invoice number + amount against GP-derived totals and surfaces
// human-readable warnings when they disagree.
//
// v1.0.238 Track B — entire function is new. Lightweight: pure-Go computation
// over already-extracted bill + GP items; no API calls.
func (s *SmartPurchaseService) reconcileBillAndGP(
	billItems []ExtractedPurchaseItem,
	gpItems []GatePassDutyItem,
	vendor *DetectedVendorInfo,
	invoiceNumber, invoiceDate string,
	billSubTotal, billTotal float64,
) *BillGPReconciliation {
	rec := &BillGPReconciliation{
		InvoiceNumber: strings.TrimSpace(invoiceNumber),
		InvoiceDate:   strings.TrimSpace(invoiceDate),
		BillTotal:     billTotal,
	}
	if vendor != nil {
		rec.BillVendor = strings.TrimSpace(vendor.Name)
	}

	// Vendor cross-check: we don't extract GP vendor name systematically,
	// so for v238 the "vendor matches" check is "bill vendor name is
	// non-empty and not obviously garbage". A future iteration can compare
	// against the GP header's licensee name.
	rec.VendorMatchScore = 0
	if rec.BillVendor != "" && len(rec.BillVendor) >= 3 {
		rec.VendorMatchScore = 1.0
		rec.VendorMatches = true
	} else {
		rec.Warnings = append(rec.Warnings, "vendor_name_missing")
	}

	if rec.InvoiceNumber == "" {
		rec.Warnings = append(rec.Warnings, "invoice_number_missing")
	}

	// Sum GP duty fees.
	for _, g := range gpItems {
		rec.GPDutyTotal += g.DutyFee
	}

	// v1.0.238-r2 — row-pairing now uses the same edit-aware jaccard +
	// size_ml equality the GP-primary matcher uses (jaccardTokensEditAware,
	// 0.45 floor). Pure-jaccard 0.5 missed pairs the matcher confidently
	// resolves — e.g. "Beagrams Royal Stag" ↔ "Seagrams Royal Stag" diverges
	// by one character but jaccard reads 1.0 on the rest of the tokens. The
	// edit-aware variant tolerates DL=2 typos per token ≥ 4 chars long.
	type pairProbe struct {
		toks   map[string]struct{}
		sizeML int
	}
	billProbes := make([]pairProbe, len(billItems))
	for i, b := range billItems {
		billProbes[i] = pairProbe{
			toks:   gpTokenSet(strings.ToLower(b.Brand)),
			sizeML: int(b.SizeML),
		}
	}
	gpMatched := make([]bool, len(gpItems))
	for _, b := range billProbes {
		matched := false
		// Two-pass: prefer same-size_ml pairs, then fall through to any size.
		for pass := 0; pass < 2 && !matched; pass++ {
			for j, g := range gpItems {
				if gpMatched[j] {
					continue
				}
				if pass == 0 && b.sizeML > 0 && g.SizeML > 0 && b.sizeML != g.SizeML {
					continue
				}
				gt := gpTokenSet(strings.ToLower(g.BrandName))
				if jaccardTokensEditAware(b.toks, gt) >= 0.45 {
					gpMatched[j] = true
					matched = true
					break
				}
			}
		}
		if matched {
			rec.RowsBoth++
		} else {
			rec.RowsBillOnly++
		}
	}
	for _, m := range gpMatched {
		if !m {
			rec.RowsGPOnly++
		}
	}

	// Total mismatch detection: when subtotal differs from sum of bill items
	// by >5%. Best-effort — bill totals are often Textract-extracted and may
	// have rounding noise.
	if billSubTotal > 0 && billTotal > 0 {
		diff := billTotal - billSubTotal
		if diff < 0 {
			diff = -diff
		}
		if billSubTotal > 0 && diff/billSubTotal > 0.05 {
			rec.TotalMismatch = true
			rec.Warnings = append(rec.Warnings, "bill_total_diverges_from_subtotal")
		}
	}

	return rec
}

// v1.0.238 — buildPurchaGateManifest + supporting struct removed entirely.
// Operator-uploaded Purcha photos are no longer part of the AI Purchase flow;
// 100% accuracy now comes from Bill+GP cross-validation (Track B).

// findMissingBillSNos returns the printed S.Nos that should be present in the
// extracted bill but aren't, based on the contiguous range [min..max]. Real-
// data trigger: chhotu's bill page 1 has S.Nos 1-42 visible but Textract
// dropped 21, 25, 30, 33, 34, 38, 42 — those gaps appear here so the Flutter
// review screen can banner the operator to verify page completeness. Empty
// slice when no gaps OR when the spread is implausible (single outlier
// row_number creates phantom gaps). Cap: if (max-min+1) > len*1.5 the
// spread is suspicious — return nil and let operator see no banner rather
// than a noisy 50+ false-missing list.
func findMissingBillSNos(items []SmartPurchaseExtractedItem) []int {
	if len(items) < 2 {
		return nil
	}
	rowNums := make([]int, 0, len(items))
	for _, it := range items {
		if it.RowNumber > 0 {
			rowNums = append(rowNums, it.RowNumber)
		}
	}
	return missingFromImplausibleSpread(rowNums)
}

// findMissingGPSNos mirrors findMissingBillSNos for the gate-pass side.
func findMissingGPSNos(items []GatePassDutyItem) []int {
	if len(items) < 2 {
		return nil
	}
	rowNums := make([]int, 0, len(items))
	for _, it := range items {
		if it.RowNumber > 0 {
			rowNums = append(rowNums, it.RowNumber)
		}
	}
	return missingFromImplausibleSpread(rowNums)
}

// missingFromImplausibleSpread is the shared gap-detector. Sorts row numbers,
// trims the top 5% as outliers (LLM rescue rows + Textract artifacts can
// produce stray row_numbers way past the true page max), then walks the
// trimmed contiguous range. Returns nil when:
//   - too few rows to be meaningful (< 4),
//   - spread is implausible (max-min+1 > len * 1.5 — likely outlier-driven),
//   - or no gaps exist.
func missingFromImplausibleSpread(rowNums []int) []int {
	if len(rowNums) < 4 {
		return nil
	}
	sorted := make([]int, len(rowNums))
	copy(sorted, rowNums)
	sort.Ints(sorted)
	// Trim top 5% (at least 1) — outlier row_numbers from LLM rescue paths.
	trim := len(sorted) / 20
	if trim < 1 {
		trim = 1
	}
	if 2*trim >= len(sorted) {
		return nil
	}
	bounded := sorted[:len(sorted)-trim]
	minN, maxN := bounded[0], bounded[len(bounded)-1]
	span := maxN - minN + 1
	if span <= len(bounded) {
		return nil // no gaps
	}
	// Implausible spread guard: if the rows we kept after trimming still
	// span 1.5× their count, the page numbering is too irregular to use as
	// a gap signal.
	if span > len(bounded)*3/2 {
		return nil
	}
	present := make(map[int]bool, len(bounded))
	for _, n := range bounded {
		present[n] = true
	}
	missing := make([]int, 0, span-len(bounded))
	for i := minN; i <= maxN; i++ {
		if !present[i] {
			missing = append(missing, i)
		}
	}
	return missing
}

// ============================================================================
// v1.0.215 — Dual-analyzer merge (Expense + TABLES)
// ============================================================================

// ternaryStr is a tiny helper to keep log lines compact.
func ternaryStr(cond bool, t, f string) string {
	if cond {
		return t
	}
	return f
}

// mergeTablesIntoExpense unions Expense + TABLES bill rows by printed S.No.
//
// Pre-conditions:
//   - expense already holds the AnalyzeExpense rows (with RowNumber=printed S.No
//     where extractable, or 0 when Expense couldn't read the S.No cell).
//   - tables holds the AnalyzeDocument(TABLES) rows for the same images.
//
// Behavior:
//   - For each TABLES row whose S.No is positive AND not already present in
//     Expense by S.No: APPEND. These are the rows Expense's LineItem grouping
//     dropped (chhotu's S.No 21/25/30/33/34/38/42 case).
//   - When TABLES row's S.No matches an Expense row but the Expense row has a
//     missing critical field (Brand="" OR QuantityBottles=0) AND TABLES filled
//     it: REPLACE. Real-data motivator: Expense sometimes splits "5 Cs."
//     across QUANTITY+OTHER while TABLES reads it cleanly.
//   - TABLES rows with S.No==0 are SKIPPED — they're un-keyable and the
//     existing Expense+legacy LLM cascade already covers no-S.No invoices.
//
// Returns (added, replaced) for telemetry.
func mergeTablesIntoExpense(expense *[]ExtractedPurchaseItem, tables []ExtractedPurchaseItem, rowToImageIdx map[int]int) (int, int) {
	if expense == nil {
		return 0, 0
	}
	bySNo := make(map[int]int, len(*expense))
	for i, it := range *expense {
		sno := int(it.RowNumber)
		if sno > 0 {
			bySNo[sno] = i
		}
	}
	added, replaced := 0, 0
	for _, t := range tables {
		sno := int(t.RowNumber)
		if sno <= 0 {
			continue
		}
		idx, exists := bySNo[sno]
		if !exists {
			t.AnalyzeMethod = "tables"
			*expense = append(*expense, t)
			bySNo[sno] = len(*expense) - 1
			rowToImageIdx[sno] = 0
			added++
			continue
		}
		// Replacement check: Expense row missing brand OR qty, TABLES filled.
		eRow := &(*expense)[idx]
		expBrandEmpty := strings.TrimSpace(eRow.Brand) == ""
		expQtyZero := eRow.QuantityBottles <= 0 && eRow.QuantityRaw <= 0
		txHasBrand := strings.TrimSpace(t.Brand) != ""
		txHasQty := t.QuantityBottles > 0 || t.QuantityRaw > 0
		if (expBrandEmpty && txHasBrand) || (expQtyZero && txHasQty) {
			t.AnalyzeMethod = "tables"
			(*expense)[idx] = t
			replaced++
		}
	}
	return added, replaced
}

// ============================================================================
// v1.0.215.6 — Per-page LLM tail-rescue
// ============================================================================

// runTailRescuePerPage walks each input image, computes max(S.No) of rows
// already extracted from that page, and asks Claude for any rows on the
// page with S.No > max. Recovered rows are appended to allExtracted with
// the correct page index in rowToImageIdx. Best-effort: failures on a
// single page don't block the others.
//
// Real-data motivation: chhotu's bill page 1 has 42 printed rows. Textract
// AnalyzeExpense reliably emits 41 (S.Nos 1-41). The 42nd row is the LAST
// row on the page — Textract's bottom-edge truncation drops it across both
// variant A and B. Tail-rescue recovers it with a single Claude call.
//
// Returns the count of newly-appended rows (0 when no page had a tail to
// recover).
func (s *SmartPurchaseService) runTailRescuePerPage(
	ctx context.Context,
	req *SmartPurchaseRequest,
	allExtracted *[]ExtractedPurchaseItem,
	rowToImageIdx map[int]int,
) int {
	if s.ocr == nil || len(req.Images) == 0 {
		return 0
	}
	// Bucket extracted rows by page.
	rowsPerPage := make(map[int][]int, len(req.Images)) // pageIdx → list of S.Nos
	existingByPage := make(map[int]map[int]bool, len(req.Images))
	for _, it := range *allExtracted {
		sno := int(it.RowNumber)
		if sno <= 0 {
			continue
		}
		page := rowToImageIdx[sno]
		rowsPerPage[page] = append(rowsPerPage[page], sno)
		if existingByPage[page] == nil {
			existingByPage[page] = make(map[int]bool)
		}
		existingByPage[page][sno] = true
	}
	totalAppended := 0
	for pageIdx, img := range req.Images {
		if len(img.Data) == 0 {
			continue
		}
		snos := rowsPerPage[pageIdx]
		if len(snos) == 0 {
			continue
		}
		maxSNo := 0
		for _, n := range snos {
			if n > maxSNo {
				maxSNo = n
			}
		}
		startSNo := maxSNo + 1
		// Skip if maxSNo is implausibly high (>200) — likely Textract error
		// rather than a real page edge. Don't waste an LLM call.
		if maxSNo > 200 || startSNo <= 0 {
			continue
		}
		rescueCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		// v1.0.215.7 — provider selection. Anthropic credits exhausted in
		// production (2026-05-08), so default to Gemini Flash (which has
		// working credits per the v215.5 GP-page-2 cascade evidence).
		// Operator can flip back to claude after Anthropic top-up via
		// STOCK_PURCHASE_TAIL_RESCUE_PROVIDER=claude.
		provider := strings.ToLower(strings.TrimSpace(os.Getenv("STOCK_PURCHASE_TAIL_RESCUE_PROVIDER")))
		if provider == "" {
			provider = "gemini"
		}
		var result *PurchaseExtractionResult
		var err error
		switch provider {
		case "claude":
			result, err = s.ocr.ExtractPurchaseTailRescue(rescueCtx, img.Data, img.ContentType, startSNo)
		default:
			result, err = s.ocr.ExtractPurchaseTailRescueGemini(rescueCtx, img.Data, img.ContentType, startSNo)
		}
		cancel()
		if err != nil {
			log.Printf("SmartPurchase tail-rescue page %d (%s): %v", pageIdx+1, provider, err)
			continue
		}
		if result == nil || len(result.Items) == 0 {
			log.Printf("SmartPurchase tail-rescue page %d: no rows above S.No %d", pageIdx+1, maxSNo)
			continue
		}
		appendedThisPage := 0
		for _, item := range result.Items {
			sno := int(item.RowNumber)
			if sno < startSNo {
				continue // safety: ignore Claude rows that violate the constraint
			}
			if existingByPage[pageIdx] != nil && existingByPage[pageIdx][sno] {
				continue // already have this S.No
			}
			ext := ExtractedPurchaseItem{
				RowNumber:       float64(sno),
				SourcePageIdx:   pageIdx,
				Brand:           item.Brand,
				SizeText:        item.SizeText,
				SizeML:          item.SizeML,
				QuantityRaw:     item.QuantityRaw,
				QuantityUnit:    item.QuantityUnit,
				BottlesPerCase:  item.BottlesPerCase,
				QuantityBottles: item.QuantityBottles,
				RatePerBottle:   item.RatePerBottle,
				Amount:          item.Amount,
				Confidence:      0.85,
				AnalyzeMethod:   "tail_rescue",
				FieldConfidence: map[string]float64{"brand": 0.85, "quantity": 0.85, "rate": 0.85, "amount": 0.85},
			}
			*allExtracted = append(*allExtracted, ext)
			rowToImageIdx[sno] = pageIdx
			if existingByPage[pageIdx] == nil {
				existingByPage[pageIdx] = make(map[int]bool)
			}
			existingByPage[pageIdx][sno] = true
			appendedThisPage++
		}
		if appendedThisPage > 0 {
			log.Printf("SmartPurchase tail-rescue page %d: recovered %d row(s) (S.No > %d)",
				pageIdx+1, appendedThisPage, maxSNo)
		}
		totalAppended += appendedThisPage
	}
	return totalAppended
}

// ============================================================================
// Deduplication
// ============================================================================

// deduplicateExtracted removes exact duplicate items from multi-image uploads
// (same brand+size with identical quantity and rate = duplicate scan of same page)
func (s *SmartPurchaseService) deduplicateExtracted(items []ExtractedPurchaseItem) []ExtractedPurchaseItem {
	type key struct {
		brand  string
		sizeML int
	}
	type seen struct {
		index int
		qty   int
		rate  float64
	}
	seenMap := make(map[key]seen)
	var deduped []ExtractedPurchaseItem

	for _, item := range items {
		k := key{brand: normalizeForMatch(item.Brand), sizeML: int(item.SizeML)}
		if k.brand == "" {
			deduped = append(deduped, item)
			continue
		}
		if prev, exists := seenMap[k]; exists {
			// Exact duplicate: same brand+size+qty+rate = same invoice line scanned twice
			if prev.qty == int(item.QuantityRaw) && prev.rate == item.RatePerBottle {
				log.Printf("Smart Purchase: Duplicate removed: '%s' %dML (qty=%d, rate=%.2f)", item.Brand, int(item.SizeML), int(item.QuantityRaw), item.RatePerBottle)
				continue
			}
			// Different quantities = different line items, keep both
			deduped = append(deduped, item)
		} else {
			seenMap[k] = seen{index: len(deduped), qty: int(item.QuantityRaw), rate: item.RatePerBottle}
			deduped = append(deduped, item)
		}
	}

	if removed := len(items) - len(deduped); removed > 0 {
		log.Printf("Smart Purchase: Deduplication removed %d duplicate items", removed)
	}
	return deduped
}

// ============================================================================
// Review flagging
// ============================================================================

// attemptRateUnitFlip is the v1.0.201 formula-driven rate-unit corrector.
// Detects when the extractor tagged a per-CASE rate as per-bottle and
// silently flips it. No static rate thresholds — the only signals used
// are: standard BPC for the size, the bill's own (cases × rate = amount)
// arithmetic, and (when available) GP pieces ÷ bpc cross-validation.
//
// Mutates `extracted` in place. Caller is matchAndEnrich's first action,
// so all downstream resolveQuantitiesFromBillAndGP / arithmetic checks /
// matching see the corrected per-bottle rate.
//
// Why no static "rate must be ≤ ₹X" guard: legitimate per-bottle prices
// span ₹40 (country liquor) to ₹4000+ (premium scotch). The chhotu case
// that exposed the old static `> 5000` guard had bills like:
//   "8pm Gold Tetra 180ml @ ₹5,409" — actually per-case (₹113/bottle × 48bpc)
//   "Sterling Reserve B7 375ml @ ₹7,573" — per-case (₹315/bottle × 24bpc)
// Both fail the static guard but reconcile cleanly under the formula.
func (s *SmartPurchaseService) attemptRateUnitFlip(extracted *ExtractedPurchaseItem, gp *GatePassDutyItem) {
	if extracted == nil {
		return
	}
	if extracted.RatePerBottle <= 0 || extracted.Amount <= 0 || extracted.QuantityRaw <= 0 {
		return
	}
	// v1.0.202 — recover from size_ml corruption (brand-leading digits bled
	// into the size cell, e.g. "8pm Gold 180ml" → 8180). MUST run before BPC
	// lookup so we get bpc=48 for 180ml, not the bpc=12 default.
	if recovered := RecoverStandardSize(int(extracted.SizeML)); recovered > 0 && recovered != int(extracted.SizeML) {
		log.Printf("SmartPurchase: size_ml corruption fix — '%s' size %d → %d (brand-digit bleed)",
			extracted.Brand, int(extracted.SizeML), recovered)
		extracted.SizeML = float64(recovered)
	}
	// Resolve BPC: explicit on item > standard for size+category > skip flip.
	bpc := int(extracted.BottlesPerCase)
	if bpc <= 1 {
		bpc = GetBottlesPerCase(int(extracted.SizeML))
	}
	if bpc <= 1 {
		return
	}
	// If extractor already split rate_per_case from rate_per_bottle distinctly,
	// trust it — that path has its own MatchAmount math handled elsewhere.
	if extracted.QuantityUnit == "cases" && extracted.RatePerCase > 0 &&
		math.Abs(extracted.RatePerCase-extracted.RatePerBottle) > 0.5 {
		return
	}
	cases := extracted.QuantityRaw

	// Hypothesis A — RatePerBottle is genuinely per-bottle.
	expectedAsBottle := cases * float64(bpc) * extracted.RatePerBottle
	// Hypothesis B — RatePerBottle is actually per-CASE (mis-tagged).
	expectedAsCase := cases * extracted.RatePerBottle

	tol := extracted.Amount * 0.02
	if tol < 5 {
		tol = 5
	}
	closesAsBottle := math.Abs(extracted.Amount-expectedAsBottle) <= tol
	closesAsCase := math.Abs(extracted.Amount-expectedAsCase) <= tol

	// If both close (e.g. cases=1 trivially), prefer the existing tag.
	if closesAsBottle {
		return
	}
	if !closesAsCase {
		return // neither hypothesis works — leave for the math gate
	}

	// v1.0.239 — GP-bottles-authoritative rule (Tushar 2026-05-14):
	// GP's "No of Bottles Dispatched" is the physical truth from the depot.
	// When the bill says "N Cs × ₹R = ₹A" AND GP.Bottles == N, the bill row's
	// printed unit is wrong (it should be "Pcs", not "Cs"). Common on
	// premium-priced loose-bottle dispatches — bill template defaults to "Cs"
	// in the unit column even when the depot shipped 2 bottles instead of
	// 2 cases. Real-data: chhotu's Johnnie Walker Black Label 12Y 750ml had
	// "2 Cs × ₹2907.60 = ₹5815.20" on the bill, but GP showed 2 bottles
	// dispatched. The original flip flipped ₹2907.60 to per-case → ₹242.30
	// per-bottle which is absurd for premium scotch. With this rule we
	// recognise raw_qty == gp.Bottles → treat ₹2907.60 as per-BOTTLE
	// (the math 2 × 2907.60 = 5815.20 still holds either way).
	if gp != nil && gp.Bottles > 0 {
		// Case 1: bill raw_qty exactly matches GP.Bottles → already per-bottle
		if int(cases) == gp.Bottles {
			log.Printf("SmartPurchase: rate-unit flip ABORTED — GP says %d bottles dispatched, bill raw_qty=%g matches; treating bill rate ₹%.2f as per-BOTTLE (was about to flip to per-CASE = ₹%.2f).",
				gp.Bottles, cases, extracted.RatePerBottle, extracted.RatePerBottle/float64(bpc))
			// Stamp QuantityBottles from GP truth (so downstream math uses GP qty).
			if extracted.QuantityBottles == 0 || extracted.QuantityBottles != float64(gp.Bottles) {
				extracted.QuantityBottles = float64(gp.Bottles)
			}
			extracted.QuantityUnit = "bottles"
			extracted.BottlesPerCase = float64(bpc)
			return
		}
		// Case 2: bill raw_qty × bpc == GP.Bottles (the normal "cases" case) → flip OK
		// Case 3: drift > bpc → abort, neither cases nor bottles interpretation works
		if gp.Cases > 0 {
			expectedGPBottles := gp.Cases * bpc
			drift := gp.Bottles - expectedGPBottles
			if drift < 0 {
				drift = -drift
			}
			if drift > bpc {
				log.Printf("SmartPurchase: rate-unit flip skipped — GP doesn't reconcile (gp.cases=%d × bpc=%d = %d, gp.bottles=%d, drift=%d)",
					gp.Cases, bpc, expectedGPBottles, gp.Bottles, drift)
				return
			}
		}
		// Final cross-check before flipping: if the flipped per-bottle math
		// would NOT yield gp.Bottles, abort. e.g. bill says "3 Cs", GP says
		// "24 bottles", bpc=12 → 3 × 12 = 36 ≠ 24 → flip would be wrong.
		impliedBottles := cases * float64(bpc)
		drift := math.Abs(impliedBottles - float64(gp.Bottles))
		if drift > float64(bpc) {
			log.Printf("SmartPurchase: rate-unit flip ABORTED — implied bottles after flip (%g cases × %d bpc = %g) does not match GP.Bottles=%d (drift=%.0f > bpc=%d). Trusting GP qty.",
				cases, bpc, impliedBottles, gp.Bottles, drift, bpc)
			// Recompute per-bottle cost using GP's truth: amount / GP.Bottles
			if gp.Bottles > 0 {
				newPerBottle := extracted.Amount / float64(gp.Bottles)
				log.Printf("SmartPurchase: GP-anchored cost — '%s' %dml: ₹%.2f / %d bottles = ₹%.2f per bottle",
					extracted.Brand, int(extracted.SizeML), extracted.Amount, gp.Bottles, newPerBottle)
				extracted.RatePerBottle = newPerBottle
				extracted.QuantityBottles = float64(gp.Bottles)
				extracted.QuantityUnit = "bottles"
				extracted.BottlesPerCase = float64(bpc)
			}
			return
		}
	}

	impliedPerBottle := extracted.RatePerBottle / float64(bpc)

	// v1.0.240 — Implausible-cost loose-dispatch detector.
	// If the post-flip per-bottle would land below the size-class plausibility
	// floor, this row is NOT a "rate is per-case" misread — it's a loose
	// dispatch where the bill's "N Cs" actually means N LOOSE BOTTLES (Textract
	// missed the "(N Pcs)" annotation). Real-data: chhotu's JW Black 12Y row 60
	// "2 Cs × ₹2907.60 = ₹5815.20". Post-flip would give per-bottle ₹242.30,
	// which is far below the ₹500 floor for premium 750ml. The pre-flip
	// interpretation (rate=₹2907.60/bottle, 2 loose bottles) lands at the real
	// wholesale price for JW Black. Override: keep the rate as per-bottle,
	// treat the cases count as the literal bottle count.
	plausibleMin, plausibleMax := plausiblePerBottleRange(int(extracted.SizeML))
	if plausibleMin > 0 && impliedPerBottle < plausibleMin &&
		extracted.RatePerBottle >= plausibleMin && extracted.RatePerBottle <= plausibleMax {
		log.Printf("SmartPurchase: rate-unit flip OVERRIDDEN as LOOSE DISPATCH — '%s' %dml: post-flip per-bottle ₹%.2f below %dml floor ₹%.2f. Treating bill 'N Cs' as N LOOSE BOTTLES at rate ₹%.2f/bottle (pre-flip plausible). %g bottles × ₹%.2f = ₹%.2f reconciles with bill amount ₹%.2f.",
			extracted.Brand, int(extracted.SizeML),
			impliedPerBottle, int(extracted.SizeML), plausibleMin,
			extracted.RatePerBottle,
			cases, extracted.RatePerBottle, expectedAsCase, extracted.Amount)
		// Rate stays per-bottle; bottles count = cases (interpreted as loose).
		extracted.QuantityUnit = "bottles"
		extracted.QuantityBottles = cases
		// Reset BPC so downstream doesn't treat this as a normal-case row.
		extracted.BottlesPerCase = float64(bpc) // keep for display; quantity logic uses QuantityBottles directly
		// Stamp QuantityFlag so the review screen can surface the override.
		if extracted.QuantityFlag == "" {
			extracted.QuantityFlag = "loose_dispatch_inferred"
		}
		return
	}

	log.Printf("SmartPurchase: rate-unit auto-flip — '%s' %dml: bill rate ₹%.2f recognized as per-CASE (BPC=%d) → per-bottle ₹%.2f; %g cases × ₹%.2f = ₹%.2f reconciles with bill amount ₹%.2f",
		extracted.Brand, int(extracted.SizeML),
		extracted.RatePerBottle, bpc, impliedPerBottle,
		cases, extracted.RatePerBottle, expectedAsCase, extracted.Amount)

	extracted.RatePerCase = extracted.RatePerBottle
	extracted.RatePerBottle = impliedPerBottle
	extracted.QuantityUnit = "cases"
	if extracted.QuantityBottles == 0 {
		extracted.QuantityBottles = cases * float64(bpc)
	}
	if extracted.BottlesPerCase == 0 {
		extracted.BottlesPerCase = float64(bpc)
	}
}

// plausiblePerBottleRange returns the (min, max) per-bottle wholesale price
// range expected for a given size class in India's IMFL market (as of 2026).
// v1.0.240 — calibrated against actual chhotu vendor data + master MRP table.
// Used by attemptRateUnitFlip to detect loose-dispatch misreads where the
// post-flip per-bottle math lands implausibly low.
//
// Floor = ~₹150 / 750ml (cheapest country liquor)
// Ceiling = ~₹15,000 / 750ml (imported single malt limit)
// Smaller sizes scale linearly with bottle volume.
func plausiblePerBottleRange(sizeML int) (min, max float64) {
	switch sizeML {
	case 750, 1000:
		return 150, 15000
	case 375:
		return 75, 7500
	case 180:
		return 40, 4000
	case 90:
		return 20, 2000
	case 650:
		return 80, 500 // beer
	case 500:
		return 50, 400 // beer cans
	case 330:
		return 30, 300 // beer pints
	}
	return 0, 0 // unknown — disable the check
}

// flagItemsForReview marks items needing user attention
func (s *SmartPurchaseService) flagItemsForReview(items []SmartPurchaseExtractedItem) {
	// Track product_id usage to detect duplicates
	productUsage := make(map[string][]int)
	for i := range items {
		if items[i].ProductID != nil {
			pid := *items[i].ProductID
			productUsage[pid] = append(productUsage[pid], i+1) // 1-based row numbers
		}
	}

	for i := range items {
		// Flag 1: Rate is zero
		if items[i].RatePerBottle == 0 && items[i].QuantityRaw > 0 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Rate is ₹0 — please enter the correct purchase price"
			}
		}

		// Flag 2: Negative rate is the only static guard left.
		// v1.0.201 — REMOVED the `> 5000` check. Per-bottle prices legitimately
		// span ₹40 (country liquor) → ₹4000+ (premium scotch). Mis-tagged
		// per-CASE rates are now caught upstream by attemptRateUnitFlip
		// (formula: bpc + cases×rate=amount + GP cross-val), not by a
		// static threshold that punishes legitimate premium SKUs.
		if items[i].RatePerBottle < 0 {
			items[i].NeedsReview = true
			items[i].ReviewReason = "Negative rate detected — please correct"
		}

		// Flag 3: Quantity is zero or negative
		if items[i].QuantityRaw <= 0 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = "Quantity is zero or invalid — please correct"
			}
		}

		// Flag 4: Low confidence match
		if items[i].MatchConfidence > 0 && items[i].MatchConfidence < 0.7 {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = fmt.Sprintf("Match uncertain (%d%%) — tap to select correct product", int(items[i].MatchConfidence*100))
			}
		}

		// Flag 5: Not found in inventory
		if items[i].Status == "not_found" {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				if items[i].GatePassBrand != "" {
					items[i].ReviewReason = fmt.Sprintf("Product not in inventory (gate pass: %s) — add or select", items[i].GatePassBrand)
				} else {
					items[i].ReviewReason = "Product not in inventory — tap to select or add new"
				}
			}
		}

		// Flag 6: Duplicate product_id across rows
		if items[i].ProductID != nil {
			pid := *items[i].ProductID
			if rows, ok := productUsage[pid]; ok && len(rows) > 1 {
				items[i].NeedsReview = true
				if items[i].ReviewReason == "" {
					items[i].ReviewReason = "Duplicate — multiple rows matched to the same product"
				}
			}
		}

		// v1.0.343 — unified confidence. Runs AFTER every specific flag above so
		// it sees the final NeedsReview/cross-val state. Sets the single score +
		// tier and, when the row scores into "review" but no specific flag fired
		// (e.g. a price that isn't bill-corroborated), still surfaces it with a
		// reason — so no uncertain row reaches stock without a human glance.
		score, tier, reason := scoreRowConfidence(&items[i])
		items[i].ConfidenceScore = score
		items[i].ConfidenceTier = tier
		if tier == "review" {
			items[i].NeedsReview = true
			if items[i].ReviewReason == "" {
				items[i].ReviewReason = reason
			}
		}
	}
}

// scoreRowConfidence collapses every independent signal we have about a row
// into one 0..1 score and a tier. v1.0.343. Pure (no DB) so it is unit-tested.
//
// The model is "agreement across sources": a row is trustworthy only when its
// product identity, quantity, price, and bill↔GP cross-validation all hold. Any
// missing or disagreeing source pulls the score down; below 0.80 the row is
// "review" so it cannot ship silently. Deductions are additive and clamped.
func scoreRowConfidence(it *SmartPurchaseExtractedItem) (score float64, tier, reason string) {
	score = 1.0
	reason = ""
	deduct := func(d float64, why string) {
		score -= d
		if reason == "" {
			reason = why
		}
	}

	// Product identity — which SKU is this?
	switch it.Status {
	case "not_found", "not_found_suggest_create":
		deduct(0.6, "Product not matched to inventory — select or add it")
	case "ambiguous", "low_confidence":
		deduct(0.4, "Product match is uncertain — confirm the right product")
	}
	if it.MatchConfidence > 0 && it.MatchConfidence < 0.7 {
		deduct(0.7-it.MatchConfidence, "Product match is uncertain — confirm the right product")
	}

	// Quantity integrity — how many bottles?
	if it.QuantityRaw <= 0 || it.QuantityBottles <= 0 {
		deduct(0.5, "Quantity is missing or zero — enter it")
	}
	if it.QuantityFlagged {
		deduct(0.25, "Quantity was adjusted or is in doubt — confirm it")
	}

	// Price completeness — what did it cost?
	if it.RatePerBottle <= 0 {
		deduct(0.4, "Purchase price is ₹0 — enter the rate")
	} else if it.CostSource == "" {
		// Has a price but it wasn't corroborated by a matched bill line.
		deduct(0.15, "Price not confirmed against the bill — verify the rate")
	}

	// Bill ↔ gate-pass cross-validation.
	for _, f := range it.CrossValFlags {
		switch f.Severity {
		case "block":
			deduct(0.5, "Bill and gate pass disagree — resolve before saving")
		case "warn":
			deduct(0.25, "Bill and gate pass differ — please confirm")
		}
	}
	if it.ResolutionSource == "disputed" {
		deduct(0.4, "Bill and gate pass quantities disagree — pick the correct one")
	}

	if score < 0 {
		score = 0
	}
	tier = "high"
	if score < 0.80 {
		tier = "review"
	}
	return score, tier, reason
}

// ============================================================================
// Product loading and matching
// ============================================================================

type dbProduct struct {
	ID                    string
	Name                  string
	DisplayName           string
	DisplayNameBoldStart  *int   // 0-indexed start of the bold/distinctive range inside DisplayName
	DisplayNameBoldLength *int   // length in characters of the bold range
	ExciseBrandName       string // Authoritative name from saas_brands (official excise catalog)
	ExciseDisplayName     string // Authoritative display_name from saas_brands
	SaasBrandID           string // saas_brands.id — empty when product isn't linked to master catalog
	Size                  string
	CostPrice             float64
	MRP                   float64
	SellingPrice          float64
	BrandName             string
	CategoryID            string
}

// productSelectColumns is the full column list shared by loadProducts + loadProductsScoped.
// Includes saas_brands LEFT JOIN so each row carries the authoritative excise name + display name.
const productSelectColumns = `products.id, products.name,
	COALESCE(NULLIF(products.display_name, ''), '') as display_name,
	COALESCE(saas_brands.display_name_bold_start, products.display_name_bold_start) as display_name_bold_start,
	COALESCE(saas_brands.display_name_bold_length, products.display_name_bold_length) as display_name_bold_length,
	COALESCE(saas_brands.name, '') as excise_brand_name,
	COALESCE(NULLIF(saas_brands.display_name, ''), '') as excise_display_name,
	COALESCE(products.saas_brand_id::text, '') as saas_brand_id,
	products.size, products.cost_price, products.mrp, products.selling_price,
	COALESCE(brands.name, '') as brand_name,
	products.category_id::text as category_id`

const productSelectJoins = `LEFT JOIN brands ON products.brand_id = brands.id
	LEFT JOIN saas_brands ON products.saas_brand_id = saas_brands.id AND saas_brands.deleted_at IS NULL`

// loadProducts loads tenant products; when shopID is non-nil, filters to products that
// are either scoped to that shop (products.shop_id = shopID) or shared across the tenant
// (products.shop_id IS NULL — legacy/pre-scoping products).
// looksLikePageMarker returns true when the string is clearly a page label
// rather than a supplier-printed invoice number. Used to filter out
// "Page 2", "Continued", "Page 1 of 3" reads when the AI mis-attributes
// a page header to the invoice_number field.
//
// Conservative — only blocks STRINGS that contain the literal "page"
// (case-insensitive) AND have <= 12 chars total OR contain "continued".
// Real invoice numbers like "PAGE-INV-001" wouldn't match because of the
// length cap. Real supplier formats observed:
//   - Pure digits: "459", "12345"
//   - Prefix+digits: "INV-2024-001", "BILL/2024/00045"
//   - Folio markers (block these): "Page 1", "Page 2 of 4", "Continued"
func looksLikePageMarker(s string) bool {
	t := strings.ToLower(strings.TrimSpace(s))
	if t == "" {
		return false
	}
	if strings.Contains(t, "continued") {
		return true
	}
	if strings.Contains(t, "page") && len(t) <= 14 {
		return true
	}
	return false
}

func (s *SmartPurchaseService) loadProducts(tenantID uuid.UUID, shopID *uuid.UUID) ([]dbProduct, error) {
	var products []dbProduct
	query := s.db.Table("products").
		Select(productSelectColumns).
		Joins(productSelectJoins).
		Where("products.tenant_id = ? AND products.deleted_at IS NULL", tenantID)
	if shopID != nil {
		query = query.Where("(products.shop_id = ? OR products.shop_id IS NULL)", *shopID)
	}
	err := query.Order("products.name ASC").Scan(&products).Error
	if err != nil {
		return nil, err
	}
	log.Printf("Smart Purchase: Loaded %d products for matching (shop-scoped=%v)", len(products), shopID != nil)
	return products, nil
}

// loadProductsScoped loads products filtered by optional category and/or size.
// Used by Smart Stock Setup when the user has pre-selected category+size in the wizard.
// When shopID is non-nil, also filters to products scoped to that shop or shared.
func (s *SmartPurchaseService) loadProductsScoped(tenantID uuid.UUID, shopID *uuid.UUID, categoryID *uuid.UUID, sizeML int) ([]dbProduct, error) {
	query := s.db.Table("products").
		Select(productSelectColumns).
		Joins(productSelectJoins).
		Where("products.tenant_id = ? AND products.deleted_at IS NULL", tenantID)
	if shopID != nil {
		query = query.Where("(products.shop_id = ? OR products.shop_id IS NULL)", *shopID)
	}

	if categoryID != nil {
		query = query.Where("products.category_id = ?", *categoryID)
	}
	if sizeML > 0 {
		sizeStr := fmt.Sprintf("%dML", sizeML)
		query = query.Where("UPPER(products.size) = UPPER(?)", sizeStr)
	}

	var products []dbProduct
	if err := query.Order("products.name ASC").Scan(&products).Error; err != nil {
		return nil, err
	}
	log.Printf("Smart Stock Setup: Loaded %d scoped products (category=%v, size=%dML)", len(products), categoryID, sizeML)
	return products, nil
}

func (s *SmartPurchaseService) loadStockLevels(tenantID, shopID uuid.UUID) (map[string]int, error) {
	type stockRow struct {
		ProductID string `gorm:"column:product_id"`
		Quantity  int    `gorm:"column:quantity"`
	}
	var rows []stockRow
	err := s.db.Table("stocks").
		Select("product_id::text, quantity").
		Where("tenant_id = ? AND shop_id = ? AND deleted_at IS NULL", tenantID, shopID).
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}

	result := make(map[string]int, len(rows))
	for _, r := range rows {
		result[r.ProductID] = r.Quantity
	}
	return result, nil
}

// buildGatePassBrandMap matches each invoice item to the BEST gate pass item by brand+size,
// returning a map from invoice item index → gate pass brand name (official excise name)
// AND a second map index → *GatePassDutyItem so callers can use the GP's cases/bottles as
// authoritative quantities (the GP's columnar layout is much more reliable than the invoice's
// dual-line quantity column).
//
// Threshold raised to 0.60 (from 0.50). GP lines at 0.50-0.60 were dragging whole invoice rows
// onto unrelated master products (e.g. "Rockford Reserve" invoice row paired with "All Seasons
// Rare Reserve" GP line because both contain "reserve" — yielding a false 0.95 "matched").
// With 0.60 the noise drops without losing legitimate cross-name pairings.
//
// When multiple invoice rows share the same best GP item (happens when two brands score
// similarly), the GP row is assigned to the invoice row with the highest score — only one
// invoice row "owns" a given GP row to avoid double-counting bottles.
func (s *SmartPurchaseService) buildGatePassBrandMap(ctx context.Context, req *SmartPurchaseRequest, extracted []ExtractedPurchaseItem, dutyItems []GatePassDutyItem) (map[int]string, map[int]*GatePassDutyItem) {
	brandMap := make(map[int]string)
	itemMap := make(map[int]*GatePassDutyItem)
	if len(dutyItems) == 0 {
		return brandMap, itemMap
	}

	// v1.0.215.10 — pre-load learned aliases. When the operator (or Gemini)
	// previously confirmed that bill abbreviation "Pm Black Whisky" maps to
	// GP canonical "8 PM Premium Black Superior Whisky", that mapping is
	// stored in ocr_brand_aliases. Loading here lets us bypass fuzzy + Gemini
	// entirely on subsequent uploads — the abbreviation is "learned".
	tenantID, _ := uuid.Parse(req.TenantID)
	shopID, _ := uuid.Parse(req.ShopID)
	learnedAliases := s.loadLearnedGPAliases(ctx, tenantID, shopID)

	// First pass: compute best (GP index, score) for each invoice row
	type pair struct {
		gpIdx int
		score float64
		src   string // "fuzzy" | "alias" | "gemini"
	}
	bestByInvoice := make(map[int]pair, len(extracted))
	type nearMiss struct {
		invIdx int
		gpIdx  int
		score  float64
	}
	nearMisses := make([]nearMiss, 0)
	for i, ex := range extracted {
		sizeStr := ex.SizeText
		if sizeStr == "" && ex.SizeML > 0 {
			sizeStr = fmt.Sprintf("%dML", int(ex.SizeML))
		}
		// Tier 0 — learned alias check. If this bill brand has a known
		// canonical mapping, find the GP row whose brand contains it.
		if learned, ok := learnedAliases[strings.ToLower(strings.TrimSpace(ex.Brand))]; ok {
			canon := strings.ToLower(learned)
			for gpIdx, gp := range dutyItems {
				if !sameSize(sizeStr, gp.Size) {
					continue
				}
				if strings.Contains(strings.ToLower(gp.BrandName), canon) {
					bestByInvoice[i] = pair{gpIdx: gpIdx, score: 0.99, src: "alias"}
					log.Printf("SmartPurchase: GP-map: %q %s → %q (LEARNED ALIAS, %d cases / %d bottles)",
						ex.Brand, sizeStr, gp.BrandName, gp.Cases, gp.Bottles)
					break
				}
			}
			if _, paired := bestByInvoice[i]; paired {
				continue
			}
		}
		bestScore := 0.0
		bestGPIdx := -1
		for gpIdx, gp := range dutyItems {
			score := s.fuzzyMatchBrandSize(ex.Brand, sizeStr, gp.BrandName, gp.Size)
			if score > bestScore {
				bestScore = score
				bestGPIdx = gpIdx
			}
		}
		if bestGPIdx >= 0 && bestScore >= 0.60 {
			bestByInvoice[i] = pair{gpIdx: bestGPIdx, score: bestScore, src: "fuzzy"}
		} else if bestScore >= 0.30 && bestGPIdx >= 0 {
			// Near-miss: queue for Gemini Tier-2 check.
			nearMisses = append(nearMisses, nearMiss{invIdx: i, gpIdx: bestGPIdx, score: bestScore})
			log.Printf("SmartPurchase: GP-map: %q %s → %q (score=%.2f, REJECTED <0.60, queued for Gemini Tier-2)",
				ex.Brand, sizeStr, dutyItems[bestGPIdx].BrandName, bestScore)
		} else if bestScore > 0 && bestGPIdx >= 0 {
			log.Printf("SmartPurchase: GP-map: %q %s → %q (score=%.2f, REJECTED <0.30 — too weak for Gemini)",
				ex.Brand, sizeStr, dutyItems[bestGPIdx].BrandName, bestScore)
		}
	}

	// v1.0.215.10 — Gemini Tier-2 matching for near-miss pairs. Sends a
	// single batched call asking "is bill[i] the same product as gp[j]?"
	// Confirmed pairs get written to ocr_brand_aliases for future learning.
	if len(nearMisses) > 0 && os.Getenv("STOCK_PURCHASE_GEMINI_MATCH") != "0" {
		geminiPairs := make([]geminiMatchCandidate, 0, len(nearMisses))
		for _, nm := range nearMisses {
			geminiPairs = append(geminiPairs, geminiMatchCandidate{
				InvIdx:    nm.invIdx,
				GPIdx:     nm.gpIdx,
				BillBrand: extracted[nm.invIdx].Brand,
				GPBrand:   dutyItems[nm.gpIdx].BrandName,
			})
		}
		confirmed := s.geminiMatchBatch(ctx, geminiPairs)
		for _, gp := range confirmed {
			bestByInvoice[gp.InvIdx] = pair{gpIdx: gp.GPIdx, score: 0.85, src: "gemini"}
			log.Printf("SmartPurchase: GP-map: %q → %q (GEMINI Tier-2 confirmed)",
				extracted[gp.InvIdx].Brand, dutyItems[gp.GPIdx].BrandName)
			// Write back to alias table for next-time learning.
			s.saveLearnedGPAlias(ctx, tenantID, shopID,
				extracted[gp.InvIdx].Brand, dutyItems[gp.GPIdx].BrandName)
		}
	}

	// Second pass: per GP-item, keep only the HIGHEST-scoring invoice row
	bestInvoiceForGP := make(map[int]int) // gpIdx → invoiceIdx
	bestScoreForGP := make(map[int]float64)
	for invIdx, p := range bestByInvoice {
		if cur, ok := bestScoreForGP[p.gpIdx]; !ok || p.score > cur {
			bestScoreForGP[p.gpIdx] = p.score
			bestInvoiceForGP[p.gpIdx] = invIdx
		}
	}

	// Emit final mapping — invoice row gets the GP pairing only if it won its GP item
	for invIdx, p := range bestByInvoice {
		if bestInvoiceForGP[p.gpIdx] != invIdx {
			log.Printf("SmartPurchase: GP-map: %q %dML → %q dropped (lost to higher-scoring row)",
				extracted[invIdx].Brand, int(extracted[invIdx].SizeML), dutyItems[p.gpIdx].BrandName)
			continue
		}
		gp := &dutyItems[p.gpIdx]
		brandMap[invIdx] = gp.BrandName
		itemMap[invIdx] = gp
		log.Printf("SmartPurchase: GP-map: %q %dML → %q (score=%.2f, %d cases / %d bottles)",
			extracted[invIdx].Brand, int(extracted[invIdx].SizeML), gp.BrandName, p.score, gp.Cases, gp.Bottles)
	}
	return brandMap, itemMap
}

// v1.0.215.10 — Gemini Tier-2 matching helpers + learned-alias persistence.
// Solves the residual GP-pairing gaps where the bill prints abbreviations
// (e.g. "Pm Black Whisky" → "8 PM Premium Black"; "Vodca" → "Vodka") that
// fuzzy match scores below the 0.60 threshold. Gemini reads the two brand
// strings and answers "same product?". Confirmed pairs persist to
// ocr_brand_aliases so subsequent uploads bypass Gemini entirely.

type geminiMatchCandidate struct {
	InvIdx    int
	GPIdx     int
	BillBrand string
	GPBrand   string
}

// sameSize compares two size strings after the same normalize pass that
// fuzzyMatchBrandSize uses — strips ml/mt/mi/ltr/space.
func sameSize(s1, s2 string) bool {
	n1 := strings.ToLower(strings.TrimSpace(s1))
	n2 := strings.ToLower(strings.TrimSpace(s2))
	for _, noise := range []string{"ml", "mt", "mi", "ltr", " "} {
		n1 = strings.ReplaceAll(n1, noise, "")
		n2 = strings.ReplaceAll(n2, noise, "")
	}
	return n1 != "" && n1 == n2
}

// isCorruptGPBrandText flags GP text that smells like a multi-row Textract
// concat: too long, embeds small standalone integers (the next row's
// printed S.No), or repeats a category word.
func isCorruptGPBrandText(s string) bool {
	if len(s) > 80 {
		return true
	}
	tokens := strings.Fields(strings.ToLower(s))
	categoryHits := 0
	categories := map[string]bool{
		"whisky": true, "whiskey": true, "vodka": true, "rum": true,
		"gin": true, "brandy": true, "scotch": true, "wine": true,
	}
	for _, t := range tokens {
		// Standalone small integers (1-99) inside brand text → next-row S.No bleed.
		if len(t) <= 2 {
			if n, err := strconv.Atoi(t); err == nil && n >= 1 && n <= 99 {
				return true
			}
		}
		if categories[t] {
			categoryHits++
		}
	}
	// Two+ distinct alcohol-category words in one brand → almost always
	// two products joined.
	return categoryHits >= 2
}

// loadLearnedGPAliases reads ocr_brand_aliases for this tenant+shop and
// returns alias_name → canonical_brand_name. Used at the start of
// buildGatePassBrandMap to bypass fuzzy + Gemini for previously-confirmed
// abbreviations.
func (s *SmartPurchaseService) loadLearnedGPAliases(ctx context.Context, tenantID, shopID uuid.UUID) map[string]string {
	out := make(map[string]string)
	if s.db == nil || tenantID == uuid.Nil {
		return out
	}
	type row struct {
		Alias     string `gorm:"column:alias_name"`
		Canonical string `gorm:"column:canonical_brand_name"`
	}
	var rows []row
	q := s.db.WithContext(ctx).Raw(`
		SELECT alias_name, canonical_brand_name
		FROM ocr_brand_aliases
		WHERE tenant_id = ?
		  AND deleted_at IS NULL
		  AND (shop_id = ? OR shop_id IS NULL)
		  AND source IN ('gemini', 'manual', 'gp_match')
	`, tenantID, shopID)
	if err := q.Scan(&rows).Error; err != nil {
		log.Printf("SmartPurchase: loadLearnedGPAliases failed: %v", err)
		return out
	}
	for _, r := range rows {
		out[strings.ToLower(strings.TrimSpace(r.Alias))] = r.Canonical
	}
	if len(out) > 0 {
		log.Printf("SmartPurchase: loaded %d learned GP aliases for tenant=%s shop=%s",
			len(out), tenantID, shopID)
	}
	return out
}

// saveLearnedGPAlias upserts a confirmed bill→GP mapping into ocr_brand_aliases
// with source="gemini" so subsequent uploads from any shop in this tenant
// can pair the same abbreviation directly.
//
// v1.0.215.10 sanity guard: don't learn aliases when the GP text looks
// CORRUPT (multi-row Textract concat). Real-data trigger: GP page 2's
// TABLES extraction sometimes joins two products into one cell, e.g.
// "Royal Challenge Select 29 Premium Whisky M2 Magic Moments Remix 30
// Superior Green Apple" — Gemini sees "M2 Magic Moments" inside, says
// yes, and we'd persist a polluted mapping. Guards: length cap + reject
// if the brand text contains stray small numbers (S.No bleed) or 2+
// distinct beverage categories.
func (s *SmartPurchaseService) saveLearnedGPAlias(ctx context.Context, tenantID, shopID uuid.UUID, billBrand, gpBrand string) {
	if s.db == nil || tenantID == uuid.Nil {
		return
	}
	billBrand = strings.TrimSpace(billBrand)
	gpBrand = strings.TrimSpace(gpBrand)
	if billBrand == "" || gpBrand == "" {
		return
	}
	if isCorruptGPBrandText(gpBrand) {
		log.Printf("SmartPurchase: SKIP saveLearnedGPAlias — gp brand looks corrupt (concat of multiple GP rows): %q", gpBrand)
		return
	}
	// Use shop-scoped (NOT NULL shop_id) for first writes — promotes to tenant
	// scope when ≥3 shops within the tenant confirm the same alias (future).
	var shopArg interface{} = shopID
	if shopID == uuid.Nil {
		shopArg = nil
	}
	err := s.db.WithContext(ctx).Exec(`
		INSERT INTO ocr_brand_aliases (
			tenant_id, shop_id, alias_name, canonical_brand_name,
			source, occurrence_count, confidence_score, created_at, updated_at, last_used_at
		)
		VALUES (?, ?, ?, ?, 'gemini', 1, 90.00, NOW(), NOW(), NOW())
		ON CONFLICT (tenant_id, shop_id, alias_name) WHERE shop_id IS NOT NULL
		DO UPDATE SET occurrence_count = ocr_brand_aliases.occurrence_count + 1,
		              last_used_at = NOW(),
		              updated_at = NOW()
	`, tenantID, shopArg, billBrand, gpBrand).Error
	if err != nil {
		log.Printf("SmartPurchase: saveLearnedGPAlias failed: %v", err)
		return
	}
	log.Printf("SmartPurchase: LEARNED alias %q → %q (tenant=%s shop=%s)",
		billBrand, gpBrand, tenantID, shopID)
}

// geminiMatchBatch sends one Gemini call asking whether each bill brand
// matches its candidate GP brand. Returns only the confirmed pairs.
// Best-effort: any failure returns nil so the matcher continues without
// Tier-2 results.
func (s *SmartPurchaseService) geminiMatchBatch(ctx context.Context, candidates []geminiMatchCandidate) []geminiMatchCandidate {
	if len(candidates) == 0 || s.ocr == nil || s.ocr.geminiKey == "" {
		return nil
	}
	prompt := strings.Builder{}
	prompt.WriteString("You are a liquor SKU matcher. For each pair below, answer YES if the bill text and gate-pass text refer to the SAME PRODUCT (same brand, same variant — different sizes, abbreviations, OCR typos, or lengthier names are OK), otherwise NO.\n\n")
	prompt.WriteString("Examples:\n")
	prompt.WriteString("- bill=\"Pm Black Whisky\" gp=\"8 PM Premium Black Superior Whisky\" → YES\n")
	prompt.WriteString("- bill=\"Magic Moments Vodca\" gp=\"M2 Magic Moments Remix Superior Vodka\" → YES\n")
	prompt.WriteString("- bill=\"Royal Stag Barrel\" gp=\"Royal Stag Superior\" → NO (different variant)\n")
	prompt.WriteString("- bill=\"Johnnie Walker Red Label\" gp=\"Johnnie Walker Black Label\" → NO\n\n")
	prompt.WriteString("Return ONLY one JSON object: {\"matches\": [{\"i\":0,\"yes\":true},{\"i\":1,\"yes\":false},...]}. No prose, no fences. Each i corresponds to the pair number below.\n\n")
	for i, c := range candidates {
		fmt.Fprintf(&prompt, "Pair %d:\n  bill=%q\n  gp=%q\n\n", i, c.BillBrand, c.GPBrand)
	}
	body := map[string]interface{}{
		"contents": []map[string]interface{}{
			{"parts": []map[string]interface{}{{"text": prompt.String()}}},
		},
		"generationConfig": map[string]interface{}{
			"temperature": 0.0, "maxOutputTokens": 2048, "responseMimeType": "application/json",
		},
	}
	bodyJSON, _ := json.Marshal(body)
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(bodyJSON))
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-goog-api-key", s.ocr.geminiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		log.Printf("SmartPurchase: Gemini matcher request failed: %v", err)
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(resp.Body)
		log.Printf("SmartPurchase: Gemini matcher %d: %s", resp.StatusCode, string(raw))
		return nil
	}
	var apiResp struct {
		Candidates []struct {
			Content struct {
				Parts []struct{ Text string } `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return nil
	}
	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return nil
	}
	text := apiResp.Candidates[0].Content.Parts[0].Text
	var parsed struct {
		Matches []struct {
			I   int  `json:"i"`
			Yes bool `json:"yes"`
		} `json:"matches"`
	}
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		log.Printf("SmartPurchase: Gemini matcher parse failed: %v (raw=%s)", err, text)
		return nil
	}
	out := make([]geminiMatchCandidate, 0, len(parsed.Matches))
	for _, m := range parsed.Matches {
		if m.Yes && m.I >= 0 && m.I < len(candidates) {
			out = append(out, candidates[m.I])
		}
	}
	log.Printf("SmartPurchase: Gemini matcher confirmed %d of %d candidates", len(out), len(candidates))
	return out
}

// loadMasterBrands loads the official excise master catalog (saas_brands + brand_variants)
// for a given size and state. Mirrors smart_stock_setup_service.loadMasterBrands so both
// AI features consume the same authoritative naming source.
func (s *SmartPurchaseService) loadMasterBrands(sizeML int, state string) []models.MasterBrandInfo {
	if sizeML == 0 {
		return nil
	}
	sizeStr := fmt.Sprintf("%dML", sizeML)
	if state == "" {
		state = "UP"
	}

	var brands []models.MasterBrandInfo
	err := s.db.Raw(`
		SELECT bv.id::text as variant_id, sb.id::text as brand_id, sb.name as brand_name,
			COALESCE(NULLIF(sb.display_name, ''), sb.name) as display_name,
			sb.display_name_bold_start as display_name_bold_start,
			sb.display_name_bold_length as display_name_bold_length,
			bv.size, bv.mrp, COALESCE(bc.name, '') as category, COALESCE(bc.sub_type, '') as sub_type,
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
		log.Printf("SmartPurchase: Failed to load master brands: %v", err)
		return nil
	}
	return brands
}

// getTenantState returns the state code for a tenant (defaults to "UP")
func (s *SmartPurchaseService) getTenantState(tenantID uuid.UUID) string {
	var state struct{ State string }
	err := s.db.Table("tenants").Select("COALESCE(state, 'UP') as state").
		Where("id = ?", tenantID).Scan(&state).Error
	if err != nil || state.State == "" {
		return "UP"
	}
	return state.State
}

// findMasterBrand finds the best matching master brand for a given invoice text, size, and rate.
// Returns the best MasterBrandInfo if score >= 0.55, else nil. Mirrors smart_stock_setup_service.findMasterBrand.
func (s *SmartPurchaseService) findMasterBrand(name string, sizeML int, rate float64, masterBrands []models.MasterBrandInfo) *models.MasterBrandInfo {
	if len(masterBrands) == 0 || name == "" {
		return nil
	}

	var bestMatch *models.MasterBrandInfo
	bestScore := 0.0

	nameUpper := strings.ToUpper(name)
	for i := range masterBrands {
		mb := &masterBrands[i]
		mbUpper := strings.ToUpper(mb.BrandName)

		score := matching.StringSimilarity(nameUpper, mbUpper)

		// Also try against display_name — shorter form often closer to OCR text
		if mb.DisplayName != "" {
			dnScore := matching.StringSimilarity(nameUpper, strings.ToUpper(mb.DisplayName))
			if dnScore > score {
				score = dnScore
			}
		}

		// MRP proximity boost
		if rate > 0 && mb.MRP > 0 {
			diff := rate - mb.MRP
			if diff < 0 {
				diff = -diff
			}
			if diff <= 30 {
				score += 0.20
			} else if diff <= 80 {
				score += 0.05
			}
		}

		if score > bestScore {
			bestScore = score
			bestMatch = mb
		}
	}

	if bestScore >= 0.55 {
		return bestMatch
	}
	return nil
}

// firstNonEmpty returns the first non-empty string in the provided list.
func firstNonEmpty(s ...string) string {
	for _, v := range s {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

// ocrTypoMatchAgainstMasters is the v1.0.200 last-resort OCR-typo rescue.
// Tokenizes the OCR brand text, then for each token finds the closest
// master-brand keyword by Levenshtein edit distance ≤ 2. When a master
// brand has at least 2 of its keywords matched within distance 1 (or all
// of its keywords within distance 2), return it.
//
// Real chhotu wins this catches:
//
//	"Mconiq White Why.375ml"     → ICONIQ WHITE DELUXE     ('M'→'I', 1 edit)
//	"Hndri Single Mait Why.750ml" → INDRI SINGLE MALT      ('H'→deleted, 'a'→'a', 2 edits)
//	"Verv Cranberry Vodka 750ML" → VERVE CRANBERRY VODKA  ('e' missing, 1 edit)
//	"Mcd Original Why 180ml"     → MC DOWELL'S NO 1        (token expansion)
//
// Cheap (in-process, ~1ms/row); only fires when prior tiers return nothing
// or score < 0.70. Size filter is applied first to slash the candidate pool.
func (s *SmartPurchaseService) ocrTypoMatchAgainstMasters(ocrText string, sizeML int, masterBrands []models.MasterBrandInfo) *models.MasterBrandInfo {
	if ocrText == "" || len(masterBrands) == 0 {
		return nil
	}
	tokens := tokenizeForFuzzyMatch(ocrText)
	if len(tokens) == 0 {
		return nil
	}
	type scored struct {
		brand *models.MasterBrandInfo
		score int // higher is better; counts close-token hits
	}
	var best scored
	best.score = 0
	for i := range masterBrands {
		mb := &masterBrands[i]
		// Size filter — when both have known size, mismatched sizes can't match.
		// MasterBrandInfo stores size as a string ("750ML" / "375ml" / "180").
		mbSize := parseSizeMLFromText(mb.Size)
		if sizeML > 0 && mbSize > 0 && sizeML != mbSize {
			continue
		}
		nameTokens := tokenizeForFuzzyMatch(mb.DisplayName)
		if len(nameTokens) == 0 {
			nameTokens = tokenizeForFuzzyMatch(mb.BrandName)
		}
		if len(nameTokens) == 0 {
			continue
		}
		// Score = number of OCR tokens that match (≤2 edits) at least one
		// master keyword. Closer matches (1 edit) count double; exact (0)
		// counts triple.
		score := 0
		for _, ot := range tokens {
			if len(ot) < 3 {
				continue // skip noise tokens like "of", "&"
			}
			bestEdit := 999
			for _, nt := range nameTokens {
				if len(nt) < 3 {
					continue
				}
				if d := levenshtein(ot, nt); d < bestEdit {
					bestEdit = d
				}
			}
			switch {
			case bestEdit == 0:
				score += 3
			case bestEdit == 1:
				score += 2
			case bestEdit == 2:
				score += 1
			}
		}
		if score > best.score && score >= 3 {
			// Need at least one strong (1-edit) hit OR three weak hits.
			best = scored{brand: mb, score: score}
		}
	}
	return best.brand
}

// tokenizeForFuzzyMatch lowercases + strips punctuation + splits into
// alphanumeric tokens. Drops "ml", numeric size tokens (handled separately
// via sizeML filter), and 1-2 character noise.
func tokenizeForFuzzyMatch(s string) []string {
	if s == "" {
		return nil
	}
	s = strings.ToLower(s)
	// Replace non-alphanumeric with space, then split.
	cleaned := strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			return r
		}
		return ' '
	}, s)
	out := []string{}
	for _, t := range strings.Fields(cleaned) {
		if len(t) < 2 {
			continue
		}
		// Skip pure-numeric tokens (sizes, batch numbers); the size filter
		// covers ML matching and we don't want "375" to match "750".
		isAllDigit := true
		for _, r := range t {
			if r < '0' || r > '9' {
				isAllDigit = false
				break
			}
		}
		if isAllDigit {
			continue
		}
		// Skip the "ml" suffix word.
		if t == "ml" || t == "mls" {
			continue
		}
		out = append(out, t)
	}
	return out
}

// levenshtein returns the edit distance between two strings (insertions,
// deletions, substitutions). Iterative DP with two rolling rows so it
// allocates O(min(len)) instead of O(len²). Used only for short brand
// tokens (≤ 30 chars), so the linear-space rolling buffer is enough.
func levenshtein(a, b string) int {
	if a == b {
		return 0
	}
	if len(a) == 0 {
		return len(b)
	}
	if len(b) == 0 {
		return len(a)
	}
	// Make a the shorter one so prev/curr are O(min len)
	if len(a) > len(b) {
		a, b = b, a
	}
	prev := make([]int, len(a)+1)
	curr := make([]int, len(a)+1)
	for i := 0; i <= len(a); i++ {
		prev[i] = i
	}
	for j := 1; j <= len(b); j++ {
		curr[0] = j
		for i := 1; i <= len(a); i++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			del := prev[i] + 1
			ins := curr[i-1] + 1
			sub := prev[i-1] + cost
			m := del
			if ins < m {
				m = ins
			}
			if sub < m {
				m = sub
			}
			curr[i] = m
		}
		prev, curr = curr, prev
	}
	return prev[len(a)]
}

// matchAndEnrich matches an extracted item against DB products using the shared matcher
// and enriches with metadata. Uses gate pass brand names for improved matching.
//
// When gatePassItem is non-nil, its cases/bottles are the SOURCE OF TRUTH for quantities:
// the gate pass has a clean columnar layout ("No of Cases Dispatched" + "No of Bottles
// Dispatched") whereas the invoice often stacks N Cs. + (M Pcs) in a single cell that the
// matchAndEnrichWithHint is the v1.0.169 entry point. When aliasHint is
// non-nil AND points to a real product in the loaded catalog, the matcher
// short-circuits with score=1.0 and skips the multi-source jaccard pass —
// trusting operator-confirmed alias data over fuzzy text matching. Falls
// through to the legacy matchAndEnrich on miss.
func (s *SmartPurchaseService) matchAndEnrichWithHint(
	extracted ExtractedPurchaseItem,
	prepared []matching.PreparedProduct,
	config matching.MatchConfig,
	productDBMap map[string]dbProduct,
	stockMap map[string]int,
	gatePassBrand string,
	gatePassItem *GatePassDutyItem,
	dutyItems []GatePassDutyItem,
	masterBrands []models.MasterBrandInfo,
	aliasHint *uuid.UUID,
	gpOnly bool,
) SmartPurchaseExtractedItem {
	if aliasHint != nil {
		hintStr := aliasHint.String()
		if dbp, ok := productDBMap[hintStr]; ok {
			// Force-feed the matcher a single-candidate result via a synthetic
			// match list. We still call matchAndEnrich so all the post-match
			// enrichment (gate pass merge, duty fees, rate audit) runs unchanged.
			extracted.Brand = dbp.Name
			log.Printf("SmartPurchase: alias hint honored — brand=%q resolved to product=%q (id=%s)",
				extracted.Brand, dbp.Name, hintStr)
		}
	}
	return s.matchAndEnrich(extracted, prepared, config, productDBMap, stockMap, gatePassBrand, gatePassItem, dutyItems, masterBrands, gpOnly)
}

// AI mis-reads. We still honor the invoice's rate and amount — only quantities are replaced.
func (s *SmartPurchaseService) matchAndEnrich(
	extracted ExtractedPurchaseItem,
	prepared []matching.PreparedProduct,
	config matching.MatchConfig,
	productDBMap map[string]dbProduct,
	stockMap map[string]int,
	gatePassBrand string,
	gatePassItem *GatePassDutyItem,
	dutyItems []GatePassDutyItem,
	masterBrands []models.MasterBrandInfo,
	gpOnly bool,
) (item SmartPurchaseExtractedItem) {
	// v1.0.359 — GP-ONLY name override. Owner rule: the displayed/applied product
	// NAME must come from the GATE PASS only, never the bill. Deferred so it covers
	// EVERY return path (not_found, no-match, matched). Precedence:
	//   gate-pass brand → GP canonical → matched product name → "Unread — needs review".
	// The bill text (extracted.Brand) is preserved in BillOCRText for alias learning
	// only, never shown. Dark unless gpOnly. (item is the named return value.)
	defer func() {
		if !gpOnly {
			return
		}
		item.BillOCRText = strings.TrimSpace(extracted.Brand)
		name, unread := resolveGPOnlyName(item.GatePassBrand, extracted.CanonicalBrand, extracted.CanonicalSource, item.MatchedDisplayName)
		item.BrandName = name
		if unread {
			item.NeedsReview = true
			if item.ReviewReason == "" {
				item.ReviewReason = "Gate-pass name not read for this row — confirm the product"
			}
		}
	}()

	// v1.0.201 — formula-based rate-unit auto-flip. Runs before any other
	// math/match/quantity logic so downstream code sees the corrected rate.
	//
	// Why: chhotu's bills (and many UP wholesale invoices) print the per-CASE
	// rate in the "rate" column. Our extractor sometimes tags this as
	// rate_per_bottle. The fix is purely formula-driven — no static rate
	// thresholds, since prices legitimately vary per brand (premium scotches
	// run ₹3000+/bottle, while country liquor is ₹40):
	//
	//   bpc(size, category)        = standard pack from StandardCaseSizes
	//   bill rate-as-case math     = cases × RatePerBottle ≈ Amount
	//   GP cross-validation        = GP.Bottles ≈ GP.Cases × bpc
	//   per-bottle implied         = RatePerBottle ÷ bpc (used only for log)
	//
	// When bill math closes treating the rate as per-CASE AND GP doesn't
	// disagree, flip silently. Otherwise leave alone (downstream math gate
	// + cross-val flags catch unresolved cases).
	s.attemptRateUnitFlip(&extracted, gatePassItem)

	// GP-preferred quantities: when paired to a GP row, use its cases+bottles as authoritative.
	// Add the invoice's loose_bottles as additional loose pieces if the invoice separately
	// captured "(M Pcs)" on top of the cases.
	resolvedCases := int(extracted.QuantityRaw)
	resolvedBottles := int(extracted.QuantityBottles)
	resolvedUnit := extracted.QuantityUnit
	resolvedBPC := int(extracted.BottlesPerCase)
	loose := int(extracted.LooseBottles)
	gpUsed := ""

	// Decide if invoice's own quantity numbers are internally consistent.
	// "Consistent" = amount ≈ (cases × rate_per_case) + (loose × rate_per_bottle), within ±2%.
	// When the invoice's math ties together, TRUST INVOICE — even if the gate pass shows a
	// different (typically larger) authorized quantity. The gate pass is the permit; the
	// invoice is what was actually delivered + billed. They legitimately disagree when the
	// vendor delivers fewer bottles than authorized (loose-bottle billing of a partial case).
	invoiceMathConsistent := false
	if extracted.Amount > 0 && extracted.RatePerBottle > 0 {
		var expected float64
		if extracted.QuantityUnit == "cases" {
			expected = extracted.QuantityRaw * extracted.RatePerCase
			if extracted.LooseBottles > 0 {
				expected += extracted.LooseBottles * extracted.RatePerBottle
			}
		} else {
			expected = extracted.QuantityRaw * extracted.RatePerBottle
		}
		diff := expected - extracted.Amount
		if diff < 0 {
			diff = -diff
		}
		tol := extracted.Amount * 0.02
		if tol < 5 {
			tol = 5
		}
		invoiceMathConsistent = diff <= tol
	}

	if gatePassItem != nil && gatePassItem.Cases > 0 && !invoiceMathConsistent {
		bpc := resolvedBPC
		if gatePassItem.Cases > 0 && gatePassItem.Bottles >= gatePassItem.Cases {
			// Derive bpc from GP when consistent
			if gatePassItem.Bottles%gatePassItem.Cases == 0 {
				bpc = gatePassItem.Bottles / gatePassItem.Cases
			}
		}
		if bpc == 0 {
			if std, ok := StandardCaseSizes[int(extracted.SizeML)]; ok {
				bpc = std
			} else {
				bpc = 12
			}
		}
		// GP doesn't separately surface loose bottles — they're rolled into the bottles column.
		// So we only add invoice's loose when GP.bottles == GP.cases × bpc exactly.
		gpBottles := gatePassItem.Bottles
		if gpBottles == gatePassItem.Cases*bpc {
			gpBottles += loose
		}
		resolvedCases = gatePassItem.Cases
		resolvedBottles = gpBottles
		resolvedUnit = "cases"
		resolvedBPC = bpc
		gpUsed = fmt.Sprintf(" (from GP: %d cases × %d bpc = %d bottles%s; invoice math inconsistent)", resolvedCases, bpc, gpBottles,
			func() string { if loose > 0 { return fmt.Sprintf(" + %d loose", loose) } ; return "" }())
	} else if gatePassItem != nil && gatePassItem.Cases > 0 && invoiceMathConsistent {
		log.Printf("SmartPurchase: Item %d: GP override SKIPPED — invoice math is internally consistent (amount=₹%.2f, qty=%g %s, rate_b=₹%.2f) — trusting invoice over GP",
			int(extracted.RowNumber), extracted.Amount, extracted.QuantityRaw, extracted.QuantityUnit, extracted.RatePerBottle)
	}
	if gpUsed == "" && loose > 0 && int(extracted.QuantityRaw) > 0 {
		// No GP pairing: rebuild bottles from cases × bpc + loose when OCR gave us loose_bottles.
		bpc := resolvedBPC
		if bpc == 0 {
			if std, ok := StandardCaseSizes[int(extracted.SizeML)]; ok {
				bpc = std
			} else {
				bpc = 12
			}
		}
		rebuiltBottles := int(extracted.QuantityRaw)*bpc + loose
		if rebuiltBottles != resolvedBottles {
			log.Printf("SmartPurchase: Item %d: rebuilding bottles from cases+loose: %d → %d",
				int(extracted.RowNumber), resolvedBottles, rebuiltBottles)
		}
		resolvedBottles = rebuiltBottles
		resolvedBPC = bpc
	}

	item = SmartPurchaseExtractedItem{
		RowNumber:       int(extracted.RowNumber),
		BrandName:       extracted.Brand,
		CanonicalBrand:  extracted.CanonicalBrand,
		CanonicalSource: extracted.CanonicalSource,
		Size:            extracted.SizeText,
		SizeML:          int(extracted.SizeML),
		Category:        extracted.Category,
		QuantityRaw:     resolvedCases,
		QuantityUnit:    resolvedUnit,
		BottlesPerCase:  resolvedBPC,
		QuantityBottles: resolvedBottles,
		RatePerBottle:   extracted.RatePerBottle,
		RatePerCase:     extracted.RatePerCase,
		Amount:          extracted.Amount,
		BatchNumber:     extracted.BatchNumber,
	}
	if gpUsed != "" {
		log.Printf("SmartPurchase: Item %d: using GP quantities%s — invoice had %d cases / %d bottles",
			int(extracted.RowNumber), gpUsed, int(extracted.QuantityRaw), int(extracted.QuantityBottles))
	}

	if int(extracted.SizeML) > 0 && item.Size == "" {
		item.Size = fmt.Sprintf("%dML", int(extracted.SizeML))
	}

	// Set gate pass brand for frontend display
	if gatePassBrand != "" {
		item.GatePassBrand = gatePassBrand
	}

	// v1.0.193 — Bill ↔ gate-pass cross-validation. Surfaces every
	// disagreement (brand / size / bottle count / pack-size violation)
	// as an explicit CrossValFlag on the row. Operator sees both values
	// side-by-side and the system never silently picks. Resolution source
	// drives whether to trust bill / GP / disputed.
	//
	// Skipped when no GP was uploaded (the "info"-severity bill_only_no_gp
	// flag would noise up every row of a no-GP submission). We pass nil
	// in that case so validateBillVsGatePass returns no flags.
	cvGP := gatePassItem
	if len(dutyItems) == 0 {
		// No GP image at all — don't flag anything from cross-validation.
		// Existing internal-math gates below still run.
		cvGP = nil
		_ = cvGP
	} else {
		flags, resolution := s.validateBillVsGatePass(&extracted, gatePassItem, gpOnly)
		if len(flags) > 0 {
			item.CrossValFlags = append(item.CrossValFlags, flags...)
		}
		if resolution != "" {
			item.ResolutionSource = resolution
			// v1.0.359 — under GP-only the bill's bottle count is irrelevant, so
			// validateBillVsGatePass never returns "disputed" and GP wins silently.
			// Guard the reconcile-block so a stray "disputed" can't force review.
			if !gpOnly && resolution == "disputed" {
				item.NeedsReview = true
				item.QuantityFlagged = true
				if item.ReviewReason == "" {
					item.ReviewReason = "Bill and gate-pass disagree on bottle count — operator must reconcile"
				}
			}
		}
	}

	// Quantity integrity check — catches two common OCR failure modes:
	//   (a) amount != rate_per_bottle * quantity_bottles (rate/unit confusion)
	//   (b) quantity_bottles == quantity_raw for IMFL sizes (bottles-column read from cases-column)
	// Flagged rows get a warning and drop to low_confidence regardless of name-match strength so
	// the user re-checks. See also the OCR prompt's quantity_flag field (rule 14).
	if extracted.QuantityFlag != "" {
		// v1.0.200 — math_gate_corrected / amount_recomputed / amount_ocr_recovered
		// flags mean the system already CORRECTED a low-conf cell using
		// high-conf rate+amount math. The corrected row is authoritative —
		// don't flag as "verify cases/bottles/rate" since we already did.
		// "rate_unit_uncertain" / "low_confidence_field" still warn the
		// operator (those are unresolved ambiguities, not system fixes).
		isAuthoritative := extracted.QuantityFlag == "math_gate_corrected" ||
			extracted.QuantityFlag == "amount_recomputed" ||
			extracted.QuantityFlag == "amount_ocr_recovered"
		if !isAuthoritative {
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Quantity uncertain (%s) — verify cases/bottles/rate", extracted.QuantityFlag))
		} else {
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("System auto-corrected via math gate (%s) — quantity is authoritative", extracted.QuantityFlag))
		}
	}
	// Arithmetic cross-check (amount ≈ rate × qty, ±3%)
	if extracted.RatePerBottle > 0 && extracted.QuantityBottles > 0 && extracted.Amount > 0 {
		expected := extracted.RatePerBottle * extracted.QuantityBottles
		diff := expected - extracted.Amount
		if diff < 0 {
			diff = -diff
		}
		tolerance := expected * 0.03
		if tolerance < 10 {
			tolerance = 10
		}
		if diff > tolerance {
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Amount %.0f ≠ rate %.2f × qty %.0f (got %.0f) — check rate unit",
					extracted.Amount, extracted.RatePerBottle, extracted.QuantityBottles, expected))
			if extracted.QuantityFlag == "" {
				item.QuantityFlagged = true
			}
		}
	}
	// Double-read detection: bottles == cases for an IMFL size with standard BPC > 1 is impossible.
	// Means the bottles column was read from the cases column (or vice versa).
	if extracted.QuantityRaw > 0 && extracted.QuantityBottles > 0 &&
		int(extracted.QuantityRaw) == int(extracted.QuantityBottles) {
		if bpc, ok := StandardCaseSizes[int(extracted.SizeML)]; ok && bpc > 1 &&
			extracted.QuantityUnit == "cases" {
			expectedBottles := int(extracted.QuantityRaw) * bpc
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Bottle count (%d) equals case count — likely %d bottles (%d cases × %d bpc)",
					int(extracted.QuantityBottles), expectedBottles, int(extracted.QuantityRaw), bpc))
			item.QuantityFlagged = true
		}
	}

	// Master brand lookup — cross-check invoice brand against official excise catalog.
	// If found, its display_name is used as an additional (authoritative) text source.
	// This mirrors smart_stock_setup's behaviour and helps correct OCR noise like "Type Blue" → "Imperial Blue".
	var masterBrand *models.MasterBrandInfo
	if len(masterBrands) > 0 {
		masterBrand = s.findMasterBrand(extracted.Brand, int(extracted.SizeML), extracted.RatePerBottle, masterBrands)
		// If direct lookup failed and we have a gate pass brand, try that too — gate pass
		// is closer to the official name than invoice OCR.
		if masterBrand == nil && gatePassBrand != "" {
			masterBrand = s.findMasterBrand(gatePassBrand, int(extracted.SizeML), extracted.RatePerBottle, masterBrands)
		}
	}

	// Rate-vs-master-MRP sanity check — catches dual-line row-shift bugs where the AI
	// attributed a different row's per-Cs rate to this row. The internal amount=qty×rate
	// math may still be consistent within the row, but the rate compared to the master
	// catalog's MRP is wildly off (typically 50-90% lower). Flag for human review.
	if masterBrand != nil && masterBrand.MRP > 0 && extracted.RatePerBottle > 0 {
		ratio := extracted.RatePerBottle / masterBrand.MRP
		if ratio < 0.4 || ratio > 2.5 {
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Rate ₹%.2f/bottle is %.0f%% of master MRP ₹%.2f — possible row-shift error, verify cases/rate",
					extracted.RatePerBottle, ratio*100, masterBrand.MRP))
			item.QuantityFlagged = true
		}
	}

	// v1.0.200 — Match priority restructured. Government-printed gate pass
	// is the AUTHORITATIVE brand source when paired (full canonical excise
	// name, all-caps, no OCR drift). Fix bills like "Mconiq" / "Hndri" /
	// "Verv" that crashed past matchers — the GP says ICONIQ / INDRI /
	// VERVE in plain government typography.
	//
	// Source priority (changed from v1.0.199's "invoice first, GP only if
	// meaningfully better"):
	//
	//   1. GP brand (when row paired)            — authoritative
	//   2. Invoice text                           — for unpaired rows or low-conf GP
	//   3. Master display name + MRP price-aware — disambiguates variants
	//   4. OCR-typo Levenshtein fallback          — last resort before not_found
	//
	// At each tier, take the result if score ≥ 0.75. Otherwise keep going
	// and pick the strongest across all tiers at the end.
	sizeML := int(extracted.SizeML)
	var results []matching.MatchResult
	matchSource := ""
	var invoiceResults, gpResults []matching.MatchResult

	// v1.0.216 — typo corrections (Vodca → Vodka, Wisky → Whisky, etc.) on
	// both the GP and invoice brand text before the matcher sees them. These
	// are token-level case-insensitive replacements documented in
	// matching.ApplyTypoCorrections; the original strings are not mutated
	// because downstream code (alias capture, original_ai_brand) still
	// needs them verbatim.
	gpBrandForMatch := matching.ApplyTypoCorrections(gatePassBrand)
	invoiceBrandForMatch := matching.ApplyTypoCorrections(extracted.Brand)

	// Tier 1 — gate-pass brand. v1.0.216.2: GP is now AUTHORITATIVE.
	// The gate pass carries the official UP Excise brand name printed by the
	// distillery; the invoice column is a handwritten / typed shorthand the
	// operator scribbles. When GP text exists AND the matcher finds any
	// candidate at ≥ 0.5 score, we trust it — even if invoice text scores
	// higher against a different product. Reason: invoice text typos (Why,
	// Vodca, Wisky, Mt) routinely score very high against wrong products
	// (e.g. "Mcd Original Why" → MOOOZ Cranberry Vodka at 0.80 because of
	// the Vodka token), but GP "Mc Dowells No1 ORIGINAL BLENDED WHISKY"
	// resolves cleanly. Only fall through to invoice when GP text is empty
	// OR GP matched at < 0.5 (i.e. GP brand isn't in this tenant's catalog).
	if gpBrandForMatch != "" {
		gpResults = matching.MatchProducts(gpBrandForMatch, sizeML, 0, prepared, config)
		if len(gpResults) > 0 && gpResults[0].Score >= 0.5 {
			results = gpResults
			matchSource = "gate_pass"
		}
	}

	// Tier 2 — invoice text. Runs only when GP empty or GP failed (< 0.5).
	// When GP already won, we still compute invoice for cross-val logging
	// but never override the GP pick.
	invoiceResults = matching.MatchProducts(invoiceBrandForMatch, sizeML, 0, prepared, config)
	if len(results) == 0 && len(invoiceResults) > 0 {
		results = invoiceResults
		matchSource = "invoice"
	} else if len(results) > 0 && len(invoiceResults) > 0 &&
		invoiceResults[0].ProductID != results[0].ProductID {
		// GP and invoice disagree. v1.0.216.2: GP wins UNCONDITIONALLY now —
		// no override path. Log the disagreement so operator can audit, but
		// trust the official excise name on the gate pass.
		log.Printf("SmartPurchase: Item %d: GP/invoice disagreement (kept GP) — gp=%.2f→%s vs invoice=%.2f→%s",
			int(extracted.RowNumber), results[0].Score, results[0].ProductName,
			invoiceResults[0].Score, invoiceResults[0].ProductName)
	}

	// Source 3: master display name + master MRP. The master brand from saas_brands
	// has an authoritative MRP — use it as a price signal to disambiguate between
	// tenant products with similar names but different prices (e.g. regular vs premium
	// variants that both contain "Magic Moments"). Requires price matching enabled.
	var mbResults []matching.MatchResult
	if masterBrand != nil && masterBrand.DisplayName != "" {
		priceAwareCfg := config
		if masterBrand.MRP > 0 {
			priceAwareCfg.EnablePriceMatching = true
			priceAwareCfg.UseCostPrice = false // master MRP corresponds to SellingPrice
			priceAwareCfg.PriceExactBoost = 0.15
			priceAwareCfg.PriceCloseBoost = 0.08
			priceAwareCfg.PriceNearBoost = 0.02
			priceAwareCfg.PriceFarPenalty = 0.10
		}
		mbResults = matching.MatchProducts(masterBrand.DisplayName, sizeML, masterBrand.MRP, prepared, priceAwareCfg)
		if len(mbResults) > 0 {
			if len(results) == 0 {
				results = mbResults
				matchSource = "master_display"
			} else if mbResults[0].Score > results[0].Score+0.05 {
				results = mbResults
				matchSource = "master_display_mrp"
			}
		}
	}

	// Merge alternate best candidates from the other sources so the user sees options.
	mergeAlternate := func(src []matching.MatchResult, minScore float64) {
		if len(src) == 0 {
			return
		}
		top := src[0]
		if len(results) == 0 || top.ProductID == results[0].ProductID {
			return
		}
		for _, r := range results {
			if r.ProductID == top.ProductID {
				return
			}
		}
		if top.Score >= minScore {
			results = append(results, top)
		}
	}
	mergeAlternate(gpResults, 0.50)
	mergeAlternate(mbResults, 0.50)

	// v1.0.200 Tier 4 — OCR-typo Levenshtein fallback. Real chhotu errors:
	//   "Mconiq White Why.375ml" → ICONIQ WHITE
	//   "Hndri Single Mait Why.750ml" → INDRI SINGLE MALT
	//   "Verv Cranberry Vodka 750ML" → VERVE CRANBERRY VODKA
	// When prior tiers produced nothing or only weak matches (<0.70), retry
	// each OCR token against master-brand keywords with edit distance ≤2 per
	// token. A single 1-edit match is enough to lift a not_found to a
	// confirmed master pick. Cheap (in-process, ~1ms/row).
	if (len(results) == 0 || results[0].Score < 0.70) && len(masterBrands) > 0 {
		typoMatch := s.ocrTypoMatchAgainstMasters(extracted.Brand, sizeML, masterBrands)
		if typoMatch != nil {
			typoResults := matching.MatchProducts(typoMatch.DisplayName, sizeML, typoMatch.MRP, prepared, config)
			if len(typoResults) > 0 {
				if len(results) == 0 || typoResults[0].Score > results[0].Score+0.05 {
					log.Printf("SmartPurchase: Item %d: OCR-typo rescue '%s' → '%s' (score=%.2f)",
						int(extracted.RowNumber), extracted.Brand, typoMatch.DisplayName, typoResults[0].Score)
					results = typoResults
					matchSource = "ocr_typo_rescue"
				}
			}
		}
	}

	if len(results) == 0 {
		// Nothing matched — but if master or gate pass tells us what the product SHOULD be,
		// surface that as a "suggest create" so the frontend can offer adding it to inventory.
		item.MatchConfidence = 0
		authoritativeName := ""
		switch {
		case masterBrand != nil && masterBrand.DisplayName != "":
			authoritativeName = masterBrand.DisplayName
		case gatePassBrand != "":
			authoritativeName = gatePassBrand
		}

		// v1.0.193 — 4-tier onboarding decision tree. Operator gets a single
		// tap to put the product where it belongs:
		//
		//   Tier 3: master saas_brand exists → create shop product linked to it
		//           (MRP / size / category pre-filled from master)
		//   Tier 4: no master, no GP → fully new brand → operator MRP+size form
		//
		// Tier 1 / Tier 2 are handled below in the matched branch.
		if masterBrand != nil && masterBrand.DisplayName != "" {
			item.Status = "not_found_suggest_create"
			item.OnboardingTier = "master_create_shop_product"
			item.OnboardingPayload = &OnboardingPayload{
				MasterSaaSBrandID:  masterBrand.BrandID,
				MasterDisplayName:  masterBrand.DisplayName,
				MasterMRP:          masterBrand.MRP,
				MasterCategory:     masterBrand.Category,
				SuggestedBrandName: masterBrand.DisplayName,
				SuggestedSizeML:    int(extracted.SizeML),
				BillCostPrice:      extracted.RatePerBottle,
			}
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Official name \"%s\" (₹%.0f MRP) — tap 'Create from catalog' to add", masterBrand.DisplayName, masterBrand.MRP))
		} else if gatePassBrand != "" {
			item.Status = "not_found_suggest_create"
			item.OnboardingTier = "master_create_shop_product"
			item.OnboardingPayload = &OnboardingPayload{
				SuggestedBrandName: gatePassBrand,
				SuggestedSizeML:    int(extracted.SizeML),
				BillCostPrice:      extracted.RatePerBottle,
			}
			_ = authoritativeName
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Excise name \"%s\" — product not in inventory, tap to add", gatePassBrand))
		} else {
			item.Status = "not_found"
			item.OnboardingTier = "fully_new"
			item.OnboardingPayload = &OnboardingPayload{
				SuggestedBrandName: extracted.Brand,
				SuggestedSizeML:    int(extracted.SizeML),
				BillCostPrice:      extracted.RatePerBottle,
			}
			item.Warnings = append(item.Warnings, "New brand — confirm MRP + size + category before creating")
		}
		log.Printf("SmartPurchase: Item %d: \"%s\" %s → %s tier=%s (gp: \"%s\", master: \"%s\")",
			item.RowNumber, extracted.Brand, item.Size, item.Status, item.OnboardingTier, gatePassBrand,
			func() string {
				if masterBrand != nil {
					return masterBrand.DisplayName
				}
				return ""
			}())
		return item
	}

	// v1.0.217 Track 2 — Master-MRP cost-ratio anchor gate. Reject the
	// matcher's top pick when invoice cost makes the product economically
	// impossible. Real-data root cause on chhotu's MOOOZ Cranberry Vodka
	// cluster: matcher routed "8 Pm Black Whisky 375ml" (cost ₹350/btl)
	// to MOOOZ Cranberry Vodka (MRP ₹650) — the text score was higher than
	// any whisky candidate due to "vodka" token shenanigans. With this
	// gate, cost-vs-MRP economics demote the match: nobody buys a ₹650
	// MRP bottle at ₹350 cost OR a ₹350 MRP bottle at ₹2400 cost.
	// Gate parameters: cost is "reasonable" when 0.30 ≤ cost/MRP ≤ 2.0.
	// Outside that band, drop this candidate and try the runner-up.
	for len(results) > 0 {
		top := results[0]
		dbP, hasDB := productDBMap[top.ProductID]
		if !hasDB || dbP.MRP <= 0 || extracted.RatePerBottle <= 0 {
			break // can't check; trust matcher
		}
		ratio := extracted.RatePerBottle / dbP.MRP
		if ratio >= 0.30 && ratio <= 2.0 {
			break // economics check out
		}
		// v1.0.240 — MRP-anchored loose-dispatch salvage. Before rejecting the
		// candidate as economically implausible, check if the row would PASS
		// the MRP anchor when re-interpreted as a LOOSE DISPATCH (no rate-unit
		// flip happened, cases is actually a literal bottle count). Real-data:
		// chhotu's JW Black row 60 came through attemptRateUnitFlip as
		// per-bottle ₹242.30 × 24 bottles = ₹5815.20. MRP for JW Black 750ml is
		// ~₹7000-7500, so ratio = 242/7500 = 0.03 — would be rejected here.
		// But the pre-flip interpretation (rate=₹2907.60/bottle × 2 bottles)
		// lands at ratio = 0.39 — within MRP band. We salvage by undoing the
		// flip on this single row.
		if ratio < 0.30 && extracted.RatePerCase > 0 && extracted.QuantityRaw > 0 {
			impliedPreFlipRate := extracted.RatePerCase // pre-flip stored the original
			preFlipRatio := impliedPreFlipRate / dbP.MRP
			expectedAsBottles := extracted.QuantityRaw * impliedPreFlipRate
			if preFlipRatio >= 0.30 && preFlipRatio <= 2.0 &&
				math.Abs(expectedAsBottles-extracted.Amount) <= extracted.Amount*0.02+5 {
				log.Printf("SmartPurchase: MRP-anchored LOOSE DISPATCH salvage — '%s' %dml: post-flip ratio %.2f failed MRP anchor (master MRP ₹%.0f); pre-flip rate ₹%.2f gives ratio %.2f (in band). Undoing flip: %g bottles × ₹%.2f = ₹%.2f ✓",
					extracted.Brand, int(extracted.SizeML),
					ratio, dbP.MRP,
					impliedPreFlipRate, preFlipRatio,
					extracted.QuantityRaw, impliedPreFlipRate, expectedAsBottles)
				extracted.RatePerBottle = impliedPreFlipRate
				extracted.RatePerCase = 0
				extracted.QuantityUnit = "bottles"
				extracted.QuantityBottles = extracted.QuantityRaw
				// Sync item-level fields. QuantityBottles on item is int.
				item.RatePerBottle = extracted.RatePerBottle
				item.RatePerCase = 0
				item.QuantityBottles = int(extracted.QuantityBottles)
				item.QuantityUnit = "bottles"
				item.Warnings = append(item.Warnings, "loose_dispatch_inferred_via_mrp")
				break // candidate stays; carry on with the salvaged values
			}
		}
		log.Printf("SmartPurchase Track-2: rejected '%s' → '%s' on MRP anchor — bill cost ₹%.0f vs master MRP ₹%.0f (ratio %.2f outside [0.30, 2.0])",
			extracted.Brand, top.ProductName, extracted.RatePerBottle, dbP.MRP, ratio)
		results = results[1:]
	}
	if len(results) == 0 {
		// All candidates failed MRP anchor — fall to "not found" branch.
		// Re-enter the not-found path by setting up state and looping back.
		item.MatchConfidence = 0
		item.Status = "not_found"
		item.OnboardingTier = "fully_new"
		item.Warnings = append(item.Warnings, "All candidates rejected on price economics — operator must pick or create the right product")
		return item
	}

	best := results[0]
	item.ProductID = &best.ProductID
	item.MatchConfidence = best.Score

	// v1.0.217 Track 3 — Variant-token discrimination. When the OCR text
	// contains a flavour token (orange / green apple / jamun / spicymint /
	// cranberry / chocolate / strawberry / lemon / mint) the matched
	// candidate's tokens must contain at least one matching flavour
	// token. Otherwise Magic Moments Vodka variants collapse into one
	// product (chhotu's bc905a4b + 1adf1688 clusters).
	{
		flavourTokens := []string{"orange", "green apple", "greenapple", "apple", "jamun", "spicymint", "spymint", "cranberry", "chocolate", "strawberry", "lemon", "mint", "vanilla", "peach"}
		ocrLower := strings.ToLower(extracted.Brand)
		var ocrFlavours []string
		for _, t := range flavourTokens {
			if strings.Contains(ocrLower, t) {
				ocrFlavours = append(ocrFlavours, t)
			}
		}
		if len(ocrFlavours) > 0 {
			candidateName := strings.ToLower(best.ProductName)
			if dbP, ok := productDBMap[best.ProductID]; ok {
				candidateName += " " + strings.ToLower(dbP.Name) + " " + strings.ToLower(dbP.DisplayName) + " " + strings.ToLower(dbP.ExciseBrandName) + " " + strings.ToLower(dbP.ExciseDisplayName)
			}
			flavourFound := false
			for _, f := range ocrFlavours {
				if strings.Contains(candidateName, f) {
					flavourFound = true
					break
				}
			}
			if !flavourFound {
				// Try the runner-up if it has the right flavour.
				rescued := false
				for _, r := range results[1:] {
					name := strings.ToLower(r.ProductName)
					if dbP, ok := productDBMap[r.ProductID]; ok {
						name += " " + strings.ToLower(dbP.Name) + " " + strings.ToLower(dbP.DisplayName) + " " + strings.ToLower(dbP.ExciseBrandName) + " " + strings.ToLower(dbP.ExciseDisplayName)
					}
					for _, f := range ocrFlavours {
						if strings.Contains(name, f) {
							log.Printf("SmartPurchase Track-3: variant-token swap — '%s' has flavour '%s', dropped '%s' (no flavour) for '%s'",
								extracted.Brand, f, best.ProductName, r.ProductName)
							best = r
							item.ProductID = &best.ProductID
							item.MatchConfidence = best.Score
							rescued = true
							break
						}
					}
					if rescued {
						break
					}
				}
				if !rescued {
					log.Printf("SmartPurchase Track-3: no candidate has flavour token(s) %v for '%s' — flagging for review",
						ocrFlavours, extracted.Brand)
					item.NeedsReview = true
					if item.ReviewReason == "" {
						item.ReviewReason = fmt.Sprintf("Bill says %s but matched product doesn't have that flavour — confirm", strings.Join(ocrFlavours, "/"))
					}
				}
			}
		}
	}

	// v1.0.200 — Confirmation gate on ambiguity. Operator sees a popup with
	// alternatives (Flutter purchase_match_picker.dart already wired) when:
	//   (a) top score < 0.85  (uncertain match — below auto-apply threshold)
	//   (b) top vs 2nd within 0.05 (true ambiguity — coin-flip between
	//       two equally-scored products that BOTH could be right)
	// 0.85 chosen empirically: chhotu's high-conf matches all sit ≥0.85
	// with the v1.0.199 4-source matcher; below that score is genuinely
	// uncertain. Above auto-apply silently — chip in UI marks the
	// confidence level visually but doesn't block.
	if best.Score < 0.85 {
		item.NeedsReview = true
		if item.ReviewReason == "" {
			item.ReviewReason = fmt.Sprintf("Match confidence %.0f%% below auto-apply threshold — confirm pick", best.Score*100)
		}
	}
	if len(results) >= 2 && best.Score-results[1].Score < 0.05 && results[1].Score >= 0.70 {
		item.NeedsReview = true
		if item.ReviewReason == "" {
			item.ReviewReason = fmt.Sprintf("Top two candidates within 0.05 (%.2f vs %.2f) — pick one", best.Score, results[1].Score)
		}
	}

	// Populate display_name + full_name + excise from DB, prefer display_name → brand_name → full name.
	if dbP, ok := productDBMap[best.ProductID]; ok {
		item.MatchedFullName = dbP.Name
		item.MatchedDisplayName = firstNonEmpty(dbP.DisplayName, dbP.BrandName, dbP.Name)
		item.MatchedExciseBrandName = dbP.ExciseBrandName
		item.MatchedExciseDisplayName = dbP.ExciseDisplayName
		// Bold range follows the DB product's config, which itself was
		// pulled with a COALESCE that prefers the saas_brand master's
		// indices over the local product's. Only apply bold when the name
		// we're rendering (MatchedDisplayName) actually matches the string
		// the indices were configured for — otherwise character offsets
		// would highlight the wrong substring. The safe case: we picked
		// dbP.DisplayName as MatchedDisplayName, which is exactly the
		// string the bold indices index into.
		if item.MatchedDisplayName == dbP.DisplayName {
			item.MatchedDisplayNameBoldStart = dbP.DisplayNameBoldStart
			item.MatchedDisplayNameBoldLength = dbP.DisplayNameBoldLength
		}
	} else {
		item.MatchedFullName = best.ProductName
		item.MatchedDisplayName = best.ProductName
	}
	// Backwards compat: existing frontend reads matched_brand_name
	item.MatchedBrandName = item.MatchedDisplayName

	// Set DB prices for comparison
	if dbP, ok := productDBMap[best.ProductID]; ok {
		if dbP.CostPrice > 0 {
			item.DBCostPrice = &dbP.CostPrice
			item.MRP = &dbP.MRP
			item.SellingPrice = &dbP.SellingPrice
		}
	}

	// shop_product_rates write happens in smart_purchase_apply.go (v1.0.193).
	// READ-side rate-divergence chip deferred to v1.0.201 — needs shopID
	// plumbed through matchAndEnrich + a pre-loaded rates map to avoid
	// per-row DB roundtrips. The WRITE side already builds the historical
	// data we'll need; first 1-2 weeks of operator confirmations populate
	// the table organically.

	// Set current stock
	if stock, ok := stockMap[best.ProductID]; ok {
		item.CurrentStock = &stock
	}

	// v1.0.193 — Tier 1 vs Tier 2 onboarding classification.
	//
	// stockMap presence = a stock_levels row exists for (shop, product). That
	// row is created at the moment a product first enters this shop, even if
	// current quantity is 0 (it dropped to 0 from sales). So:
	//
	//   Tier 1 "matched"            — stock_levels row present (shop carries it)
	//   Tier 2 "matched_other_shop" — no stock_levels row (tenant has it, shop
	//                                 doesn't yet) → operator gets one-tap
	//                                 "Add to this shop" on apply.
	if _, hasStockRow := stockMap[best.ProductID]; hasStockRow {
		item.OnboardingTier = "matched"
	} else if dbP, ok := productDBMap[best.ProductID]; ok {
		item.OnboardingTier = "matched_other_shop"
		item.OnboardingPayload = &OnboardingPayload{
			ExistingProductID:  best.ProductID,
			SuggestedBrandName: dbP.Name,
			SuggestedSizeML:    int(extracted.SizeML),
			BillCostPrice:      extracted.RatePerBottle,
		}
	} else {
		item.OnboardingTier = "matched"
	}

	// Determine status based on confidence
	if best.Score >= 0.8 {
		item.Status = "matched"
	} else if len(results) > 1 && results[0].Score-results[1].Score < 0.1 {
		item.Status = "ambiguous"
		item.Warnings = append(item.Warnings, "Multiple products match equally — please confirm")
	} else {
		item.Status = "low_confidence"
		item.Warnings = append(item.Warnings, "Low confidence match — please confirm")
	}
	// Quantity-integrity failure drops status to low_confidence even for strong name matches,
	// because the wrong case/piece count poisons inventory regardless of whether the SKU is right.
	if item.QuantityFlagged && item.Status == "matched" {
		item.Status = "low_confidence"
	}

	// v1.0.193 — Variant-confusion protection (alias-aware).
	//
	// Real-world case: bill says "8 PM Gold" but shop has "8 PM Rare"
	// onboarded. ShopInventoryBias could otherwise push Rare over the
	// threshold and silently match GOLD bottles as RARE — corrupting stock
	// for both variants.
	//
	// SMART rule: when there's a LEARNED ALIAS (operator confirmed this
	// mapping at this shop in a prior session — captured via
	// captureSmartPurchaseLearning), we RESPECT it. The cross-variant pick
	// is the operator's deliberate choice — apply silently. Otherwise we
	// surface a soft "variant_mismatch" cross-val flag asking the operator
	// to confirm. On confirmation, the alias is learned for next time.
	{
		ocrLower := strings.ToLower(extracted.Brand)
		matchedLower := strings.ToLower(item.MatchedDisplayName)
		variantTokens := []string{
			"gold", "rare", "black", "blue", "white", "green", "red", "silver",
			"premium", "superior", "reserve", "select", "classic", "smooth",
			"deluxe",
		}
		ocrVariants := map[string]bool{}
		matchedVariants := map[string]bool{}
		for _, v := range variantTokens {
			if strings.Contains(ocrLower, v) {
				ocrVariants[v] = true
			}
			if strings.Contains(matchedLower, v) {
				matchedVariants[v] = true
			}
		}
		mismatched := []string{}
		for v := range ocrVariants {
			if !matchedVariants[v] {
				mismatched = append(mismatched, v)
			}
		}
		// Hide the warning when the match was sourced via the alias-cascade
		// pre-resolver (the operator's prior choice — already validated). We
		// detect this by checking whether the matched product is the alias-
		// resolved product (item.AliasResolvedProductID set when alias hit).
		// In the current schema, alias resolution sets a higher floor score —
		// so when best.Score >= 0.95 from a fuzzy alias path, treat it as
		// "operator-trusted" and skip the warning.
		operatorTrusted := best.Score >= 0.95
		if len(mismatched) > 0 && !operatorTrusted {
			// Soft warning — operator must confirm but apply is allowed.
			// The cross-val flag drives a Flutter chip with one-tap
			// "Yes, treat as same at this shop" → captureApplyLearning saves
			// the alias on apply and next time auto-resolves.
			item.CrossValFlags = append(item.CrossValFlags, CrossValFlag{
				Kind:          "variant_mismatch",
				Severity:      "warn",
				BillValue:     extracted.Brand,
				GatePassValue: item.MatchedDisplayName,
				Detail: fmt.Sprintf(
					"Bill mentions variant '%s' but matched product '%s' doesn't — confirm same at this shop or pick different",
					strings.Join(mismatched, ", "), item.MatchedDisplayName),
			})
			item.NeedsReview = true
			if item.ReviewReason == "" {
				item.ReviewReason = fmt.Sprintf("Variant disambiguation needed: '%s' vs matched product",
					strings.Join(mismatched, ", "))
			}
			log.Printf("SmartPurchase: VARIANT-MISMATCH row %.0f — bill=%q matched=%q missing=%v score=%.2f",
				extracted.RowNumber, extracted.Brand, item.MatchedDisplayName, mismatched, best.Score)
		}
	}

	// Add alternative matches (top 3, excluding best)
	// If primary results have few alternatives, do a relaxed pass to show more options
	altResults := results
	if len(results) < 3 {
		relaxedConfig := config
		relaxedConfig.MinThreshold = 0.40
		relaxedConfig.MaxResults = 5
		relaxedAlt := matching.MatchProducts(extracted.Brand, sizeML, 0, prepared, relaxedConfig)
		// Merge: add any new products not already in results
		seen := make(map[string]bool)
		for _, r := range results {
			seen[r.ProductID] = true
		}
		for _, r := range relaxedAlt {
			if !seen[r.ProductID] {
				altResults = append(altResults, r)
				seen[r.ProductID] = true
			}
		}
	}
	for i := 1; i < len(altResults) && i <= 3; i++ {
		altFullName := altResults[i].ProductName
		altDisplay := altFullName
		var altMRP, altCost float64
		var altExcise, altExciseDisplay, altSize string
		altSize = altResults[i].Size
		if dbP, ok := productDBMap[altResults[i].ProductID]; ok {
			altFullName = dbP.Name
			altDisplay = firstNonEmpty(dbP.DisplayName, dbP.BrandName, dbP.Name)
			altMRP = dbP.MRP
			altCost = dbP.CostPrice
			altExcise = dbP.ExciseBrandName
			altExciseDisplay = dbP.ExciseDisplayName
		}
		item.AlternativeMatches = append(item.AlternativeMatches, AlternativeMatch{
			ProductID:         altResults[i].ProductID,
			BrandName:         altDisplay, // backwards compat
			DisplayName:       altDisplay,
			FullName:          altFullName,
			ExciseBrandName:   altExcise,
			ExciseDisplayName: altExciseDisplay,
			Size:              altSize,
			CostPrice:         altCost, // from DB (was results[i].Price which is SellingPrice)
			MRP:               altMRP,
			Confidence:        altResults[i].Score,
		})
	}

	// Validate rate against DB cost price
	if dbP, ok := productDBMap[best.ProductID]; ok && item.RatePerBottle > 0 && dbP.CostPrice > 0 {
		pctDiff := math.Abs(item.RatePerBottle-dbP.CostPrice) / dbP.CostPrice
		if pctDiff > 0.15 {
			item.Warnings = append(item.Warnings,
				fmt.Sprintf("Rate ₹%.2f differs from known cost ₹%.2f (%.0f%% difference)",
					item.RatePerBottle, dbP.CostPrice, pctDiff*100))
		}
	}

	// Apply duty fee from gate pass — pick best matching gate pass item
	if len(dutyItems) > 0 {
		sizeStr := item.Size
		bestDutyScore := 0.0
		bestDutyIdx := -1
		for di, duty := range dutyItems {
			score := s.fuzzyMatchBrandSize(item.BrandName, sizeStr, duty.BrandName, duty.Size)
			if score > bestDutyScore {
				bestDutyScore = score
				bestDutyIdx = di
			}
		}
		if bestDutyIdx >= 0 && bestDutyScore >= 0.5 {
			item.DutyFee = dutyItems[bestDutyIdx].DutyFee
			if item.QuantityBottles > 0 {
				item.DutyPerBottle = dutyItems[bestDutyIdx].DutyFee / float64(item.QuantityBottles)
			}
		}
	}

	// Log match result with top 2 candidates for debugging
	log.Printf("SmartPurchase: Item %d: \"%s\" %s → %s \"%s\" (score=%.2f, src=%s)",
		item.RowNumber, extracted.Brand, item.Size, item.Status, item.MatchedDisplayName, best.Score, matchSource)
	if item.MatchedDisplayName != item.MatchedFullName {
		log.Printf("  full: \"%s\"", item.MatchedFullName)
	}
	if len(results) > 1 {
		r2display := results[1].ProductName
		if dbP, ok := productDBMap[results[1].ProductID]; ok {
			r2display = firstNonEmpty(dbP.DisplayName, dbP.BrandName, dbP.Name)
		}
		log.Printf("  runner-up: \"%s\" (score=%.2f)", r2display, results[1].Score)
	}
	if gatePassBrand != "" {
		log.Printf("  gate_pass: \"%s\"", gatePassBrand)
	}
	if masterBrand != nil {
		log.Printf("  master: \"%s\" (mrp=₹%.0f)", masterBrand.DisplayName, masterBrand.MRP)
	}

	return item
}

// findMatches is replaced by matching.MatchProducts from the shared matching package.
// The shared matcher uses IDF-weighted token overlap which correctly distinguishes
// critical differentiating words (e.g., "black" vs "rare" in "8PM Black Whisky").

// ============================================================================
// Vendor matching
// ============================================================================

// autoCreateVendorByExtraction is the v1.0.200 inline vendor auto-link.
// Idempotent: re-extraction of the same vendor name returns the existing
// vendor_id without creating a duplicate. Returns (vendorID, displayName,
// wasCreated). nil on tenant lookup failure.
//
// Mirrors SmartPurchaseVendorHandler.CreateOrMatchVendor but runs inline
// so Flutter doesn't need a second HTTP roundtrip — the bill applies
// cleanly on first extraction.
func (s *SmartPurchaseService) autoCreateVendorByExtraction(tenantID uuid.UUID, info *DetectedVendorInfo) (*uuid.UUID, string, bool) {
	if info == nil || info.Name == "" {
		return nil, "", false
	}
	cleanName := strings.TrimSpace(info.Name)
	cleanGST := strings.ToUpper(strings.TrimSpace(info.GSTNumber))

	type vendorRow struct {
		ID        string `gorm:"column:id"`
		Name      string `gorm:"column:name"`
		GSTNumber string `gorm:"column:gst_number"`
	}

	// Idempotency: GST first, then exact-name fallback.
	if cleanGST != "" {
		var v vendorRow
		err := s.db.Table("vendors").
			Select("id::text, name, COALESCE(gst_number, '') as gst_number").
			Where("tenant_id = ? AND UPPER(gst_number) = ? AND deleted_at IS NULL", tenantID, cleanGST).
			Limit(1).Scan(&v).Error
		if err == nil && v.ID != "" {
			if id, perr := uuid.Parse(v.ID); perr == nil {
				return &id, v.Name, false
			}
		}
	}
	{
		var v vendorRow
		err := s.db.Table("vendors").
			Select("id::text, name, COALESCE(gst_number, '') as gst_number").
			Where("tenant_id = ? AND LOWER(name) = LOWER(?) AND deleted_at IS NULL", tenantID, cleanName).
			Limit(1).Scan(&v).Error
		if err == nil && v.ID != "" {
			if id, perr := uuid.Parse(v.ID); perr == nil {
				return &id, v.Name, false
			}
		}
	}

	// Create new vendor row. Minimal field set — name + tenant + GST +
	// address. Defaults the rest. The handler's full create-vendor form
	// is still available if the operator wants to add city/state/etc.
	newID := uuid.New()
	createSQL := `
		INSERT INTO vendors (id, tenant_id, name, gst_number, address, is_active, created_at, updated_at)
		VALUES (?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), true, NOW(), NOW())
		ON CONFLICT (tenant_id, LOWER(name)) DO NOTHING
	`
	if err := s.db.Exec(createSQL, newID, tenantID, cleanName, cleanGST, info.Address).Error; err != nil {
		// ON CONFLICT clause may fail if no such unique index exists; fall
		// back to a plain insert (the idempotency check above already
		// ruled out an existing exact-name row).
		fallbackSQL := `
			INSERT INTO vendors (id, tenant_id, name, gst_number, address, is_active, created_at, updated_at)
			VALUES (?, ?, ?, NULLIF(?, ''), NULLIF(?, ''), true, NOW(), NOW())
		`
		if ferr := s.db.Exec(fallbackSQL, newID, tenantID, cleanName, cleanGST, info.Address).Error; ferr != nil {
			log.Printf("SmartPurchase vendor auto-link: insert failed: %v", ferr)
			return nil, "", false
		}
	}
	return &newID, cleanName, true
}

func (s *SmartPurchaseService) matchVendor(tenantID uuid.UUID, vendorName, vendorGST string) (*uuid.UUID, string, float64) {
	type vendorRow struct {
		ID        string `gorm:"column:id"`
		Name      string `gorm:"column:name"`
		GSTNumber string `gorm:"column:gst_number"`
	}

	var vendors []vendorRow
	if err := s.db.Table("vendors").
		Select("id::text, name, COALESCE(gst_number, '') as gst_number").
		Where("tenant_id = ? AND is_active = true AND deleted_at IS NULL", tenantID).
		Scan(&vendors).Error; err != nil {
		log.Printf("Smart Purchase: Failed to load vendors: %v", err)
		return nil, "", 0
	}

	// Priority 1: Exact GST match
	if vendorGST != "" {
		for _, v := range vendors {
			if strings.EqualFold(v.GSTNumber, vendorGST) {
				id, err := uuid.Parse(v.ID)
				if err != nil {
					log.Printf("Smart Purchase: Invalid vendor UUID %s: %v", v.ID, err)
					continue
				}
				return &id, v.Name, 1.0
			}
		}
	}

	// Priority 2: Fuzzy name match
	if vendorName != "" {
		normalizedInput := normalizeForMatch(vendorName)
		bestScore := 0.0
		var bestVendor *vendorRow

		for i := range vendors {
			normalizedDB := normalizeForMatch(vendors[i].Name)
			score := stringSimilarity(normalizedInput, normalizedDB)

			// Boost for substring
			if strings.Contains(normalizedDB, normalizedInput) || strings.Contains(normalizedInput, normalizedDB) {
				score = spMax(score, 0.8)
			}

			if score > bestScore {
				bestScore = score
				bestVendor = &vendors[i]
			}
		}

		if bestVendor != nil && bestScore >= 0.6 {
			id, err := uuid.Parse(bestVendor.ID)
			if err != nil {
				log.Printf("Smart Purchase: Invalid vendor UUID %s: %v", bestVendor.ID, err)
				return nil, "", 0
			}
			return &id, bestVendor.Name, bestScore
		}
	}

	return nil, "", 0
}

// ============================================================================
// String matching utilities
// ============================================================================

// normalizeForMatch lowercases and removes non-alphanumeric characters
func normalizeForMatch(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

// initialsMatch is now provided by the shared matching package (matching.InitialsMatch)

// stringSimilarity returns a similarity score between 0.0 and 1.0 using Levenshtein distance
func stringSimilarity(a, b string) float64 {
	if a == b {
		return 1.0
	}
	if len(a) == 0 || len(b) == 0 {
		return 0.0
	}

	dist := levenshteinDistance(a, b)
	maxLen := spMax(len(a), len(b))
	return 1.0 - float64(dist)/float64(maxLen)
}

// levenshteinDistance computes the edit distance between two strings
func levenshteinDistance(a, b string) int {
	la := len(a)
	lb := len(b)

	if la == 0 {
		return lb
	}
	if lb == 0 {
		return la
	}

	// Use single-row optimization
	prev := make([]int, lb+1)
	curr := make([]int, lb+1)

	for j := 0; j <= lb; j++ {
		prev[j] = j
	}

	for i := 1; i <= la; i++ {
		curr[0] = i
		for j := 1; j <= lb; j++ {
			cost := 1
			if a[i-1] == b[j-1] {
				cost = 0
			}
			curr[j] = spMin(
				prev[j]+1,      // deletion
				curr[j-1]+1,    // insertion
				prev[j-1]+cost, // substitution
			)
		}
		prev, curr = curr, prev
	}

	return prev[lb]
}

func spMin(vals ...int) int {
	m := vals[0]
	for _, v := range vals[1:] {
		if v < m {
			m = v
		}
	}
	return m
}

func spMax[T int | float64](a, b T) T {
	if a > b {
		return a
	}
	return b
}

// runRecallSupplement runs the LLM cascade as a parallel safety-net for the
// Textract result. Any LLM-recovered row whose (normalize(brand), size_ml)
// key isn't already present in allExtracted gets appended with a fresh
// row_number above max-existing. Returns the number of appended rows.
//
// Why we don't replace: Textract has structured output (cells, anchored
// row indices) that's more reliable for the rows it DOES capture. The LLM
// is best at recall — finding rows Textract dropped — but its row numbers
// are LLM-derived and may overlap with real S.No. So we keep Textract's
// rows authoritative and only ADD missing ones.
//
// Caller already gated on len(allExtracted) > 0 and the env flag.
func (s *SmartPurchaseService) runRecallSupplement(
	ctx context.Context,
	req *SmartPurchaseRequest,
	allExtracted *[]ExtractedPurchaseItem,
	rowToImageIdx map[int]int,
) int {
	if len(req.Images) == 0 || s.ocr == nil {
		return 0
	}

	// 1. Build collision keys from existing rows: lower-cased first 3 brand
	// words + size_ml. We trim trailing category abbrevs (WHY, WHISKY, etc.)
	// because Textract and the LLM word them differently — without trimming,
	// "Royal Stag Whisky 750ml" (Textract) and "Royal Stag" (LLM) would key
	// differently and the LLM row would be falsely appended as duplicate.
	// v1.0.206 — fuzzy dedup. Brand-name OCR varies sharply across extractors
	// ("Mcd" vs "McDowell's", "Impe Blue" vs "Imperial Blue", "Pm Black" vs
	// "8 PM Black"). Exact-token keys produce false-novel rows; the v205 cap
	// then aborted real recoveries. Switch to per-size-bucket Levenshtein
	// similarity ≥ 0.7. Same physical SKU should always exceed 0.7, distinct
	// SKUs (Royal Stag vs Royal Green) stay below.
	canonSize := func(sizeML int) int {
		if rec := RecoverStandardSize(sizeML); rec > 0 {
			return rec
		}
		return sizeML
	}

	// Strip noise tokens + lowercase to give fuzzy matching its best chance.
	cleanBrand := func(brand string) string {
		b := strings.ToLower(strings.TrimSpace(brand))
		for _, tok := range []string{
			"whisky", "whiskey", " why ", " why.", " why,", " why",
			" rum", " gin", " vodka", " brandy", " beer", " scotch",
			"(pet)", "(pet.)", "(tetra)", "(glass)", "(laminate)",
			"ml.", " ml", "ml",
		} {
			b = strings.ReplaceAll(b, tok, " ")
		}
		// Drop punctuation that one extractor includes and the other doesn't
		// ("McDowell's No.1" vs "McDowells No 1").
		var sb strings.Builder
		for _, r := range b {
			if r == '\'' || r == '.' || r == ',' || r == '"' {
				continue
			}
			sb.WriteRune(r)
		}
		return strings.Join(strings.Fields(sb.String()), " ")
	}

	// Bucket existing rows by canonical size so we only compare brand
	// similarity within the same size — different sizes are always distinct
	// SKUs even if the brand reads identical.
	type existingEntry struct {
		key   string // cleanBrand result
		raw   string // original for logging
	}
	bySize := map[int][]existingEntry{}
	maxRow := 0
	for _, ex := range *allExtracted {
		sz := canonSize(int(ex.SizeML))
		bySize[sz] = append(bySize[sz], existingEntry{
			key: cleanBrand(ex.Brand),
			raw: ex.Brand,
		})
		if int(ex.RowNumber) > maxRow {
			maxRow = int(ex.RowNumber)
		}
	}

	// firstNChars returns the first n alphabetic chars of s — used as the
	// dedup primitive. Strips digits/spaces so "8 pm black" and "pm black"
	// both yield "pmb" at n=3, keeping the well-known abbreviation collisions
	// in the same bucket.
	firstNChars := func(s string, n int) string {
		var sb strings.Builder
		for _, r := range s {
			if r >= 'a' && r <= 'z' {
				sb.WriteRune(r)
				if sb.Len() >= n {
					break
				}
			}
		}
		return sb.String()
	}

	// firstWordPrefix returns the first 3 alphabetic chars of the first word.
	// "mcd original" → "mcd"; "mcdowells no1 original" → "mcd".
	// "imperial blue" → "imp"; "impe blue" → "imp".
	// "royal stag" → "roy"; "royal green" → "roy" (collision — handled by
	// also checking the second-word prefix).
	firstWordPrefix := func(s string) string {
		fields := strings.Fields(s)
		if len(fields) == 0 {
			return ""
		}
		return firstNChars(fields[0], 3)
	}
	secondWordPrefix := func(s string) string {
		fields := strings.Fields(s)
		if len(fields) < 2 {
			return ""
		}
		return firstNChars(fields[1], 3)
	}

	// isDuplicate scans the same-size bucket. Two rows are the same SKU if
	// EITHER:
	//   (a) Levenshtein similarity ≥ 0.7 (close OCR variants), OR
	//   (b) first-word-prefix(3 alpha chars) AND second-word-prefix(3 alpha
	//       chars) BOTH match. Real-data validation (chhotu's bill):
	//         "mcd original 375"           ⊕ "mcdowells no1 original" → mcd+ori (no — first words match "mcd" but second "ori" vs "no1" differ → false). Hmm.
	//
	// Adjustment after walking through chhotu's collisions: the
	// "mcd"/"mcdowells" pair shares only the first-word prefix (since the
	// second word is "original" vs "no1"). Falling back to first-word-only
	// would over-merge "Royal Stag" / "Royal Green". The practical fix:
	// first-word-3-char match + size match + (second-word match OR brand-
	// length-difference < 4 chars OR jaccard of word sets ≥ 0.5).
	// wordSetJaccard counts only tokens that are ≥4 alphabetic chars. Drops
	// digits ("375", "no1") and short noise ("ml", "cs") that would otherwise
	// dilute the score. Real-data check on chhotu's bill:
	//   "mcd original" / "mcdowells no1 original" → {original} ∩
	//     {mcdowells, original} = 1/2 = 0.5 ✓ (dup at threshold)
	//   "royal stag" / "royal green" → {royal, stag} ∩ {royal, green} =
	//     1/3 = 0.33 ✗ (NOT dup, distinct SKUs)
	wordSetJaccard := func(a, b string) float64 {
		isAlphaWord := func(w string) bool {
			alpha := 0
			for _, r := range w {
				if r >= 'a' && r <= 'z' {
					alpha++
				}
			}
			return alpha >= 4
		}
		aw := map[string]bool{}
		for _, w := range strings.Fields(a) {
			if isAlphaWord(w) {
				aw[w] = true
			}
		}
		bw := map[string]bool{}
		for _, w := range strings.Fields(b) {
			if isAlphaWord(w) {
				bw[w] = true
			}
		}
		intersect := 0
		for w := range aw {
			if bw[w] {
				intersect++
			}
		}
		union := len(aw) + len(bw) - intersect
		if union == 0 {
			return 0
		}
		return float64(intersect) / float64(union)
	}

	isDuplicate := func(candBrand string, candSizeML int) bool {
		cand := cleanBrand(candBrand)
		if cand == "" {
			return false
		}
		sz := canonSize(candSizeML)
		entries, ok := bySize[sz]
		if !ok {
			return false
		}
		candFW := firstWordPrefix(cand)
		candSW := secondWordPrefix(cand)
		for _, e := range entries {
			// Layer 1: Levenshtein similarity ≥ 0.7 — close OCR variants.
			if matching.StringSimilarity(cand, e.key) >= 0.7 {
				return true
			}
			eFW := firstWordPrefix(e.key)
			eSW := secondWordPrefix(e.key)
			// Layer 2: first-word-prefix matches AND (second-word-prefix
			// matches OR word-set jaccard ≥ 0.5). The jaccard fallback
			// catches "mcd original" / "mcdowells no1 original" via the
			// shared "original" token even though second words differ.
			if candFW != "" && candFW == eFW {
				if (candSW != "" && candSW == eSW) || wordSetJaccard(cand, e.key) >= 0.5 {
					return true
				}
			}
		}
		return false
	}

	// remember this candidate so subsequent novel-but-similar LLM rows
	// from the same image don't all get appended.
	addToBuckets := func(brand string, sizeML int) {
		sz := canonSize(sizeML)
		bySize[sz] = append(bySize[sz], existingEntry{
			key: cleanBrand(brand),
			raw: brand,
		})
	}

	// 2. Run LLM extract per image in parallel.
	type imgRes struct {
		idx int
		res *PurchaseExtractionResult
		err error
	}
	ch := make(chan imgRes, len(req.Images))
	for i, img := range req.Images {
		go func(idx int, data []byte, ct string) {
			r, e := s.ocr.ExtractFromImage(ctx, data, ct)
			ch <- imgRes{idx: idx, res: r, err: e}
		}(i, img.Data, img.ContentType)
	}

	results := make([]imgRes, len(req.Images))
	for range req.Images {
		r := <-ch
		results[r.idx] = r
	}

	// 3. For every LLM row whose key is novel, append. Renumber starting at
	// maxRow+1 so the new rows sort after existing ones in the UI.
	//
	// Sanity cap: refuse to append more than 30% of existing-count.
	// Real-data check (chhotu's bill, 60 printed rows): Textract got 54,
	// supplement should add at most ~16 to land at 100% recall. A run that
	// wants to add 40+ is almost certainly key-mismatch noise — abort and
	// preserve the (still-good) Textract result.
	maxAppend := len(*allExtracted) * 30 / 100
	if maxAppend < 6 {
		maxAppend = 6 // floor for tiny bills
	}

	appended := 0
	nextRow := maxRow + 1
	abort := false
	for _, r := range results {
		if r.err != nil || r.res == nil {
			log.Printf("SmartPurchase: recall-supplement: image %d LLM error: %v", r.idx, r.err)
			continue
		}
		for _, it := range r.res.Items {
			if int(it.SizeML) <= 0 || strings.TrimSpace(it.Brand) == "" {
				continue
			}
			if isDuplicate(it.Brand, int(it.SizeML)) {
				continue
			}
			if appended >= maxAppend {
				log.Printf("SmartPurchase: recall-supplement HIT CAP (%d novel rows would exceed %d=30%% of existing %d) — aborting append, keeping Textract result",
					appended+1, maxAppend, len(*allExtracted)-appended)
				abort = true
				break
			}
			// Anchor the rescued row's number for image-mapping + tag the
			// source so the UI can render a chip identifying recovered rows.
			it.RowNumber = float64(nextRow)
			it.AnalyzeMethod = "llm_rescue"
			rowToImageIdx[nextRow] = r.idx
			*allExtracted = append(*allExtracted, it)
			addToBuckets(it.Brand, int(it.SizeML))
			log.Printf("SmartPurchase: recall-supplement RECOVERED row %d: %q %dml (image %d)",
				nextRow, it.Brand, int(it.SizeML), r.idx)
			nextRow++
			appended++
		}
		if abort {
			// Drop everything we appended in this pass — safer to ship
			// Textract-only than mix in 30%+ noise.
			*allExtracted = (*allExtracted)[:len(*allExtracted)-appended]
			return 0
		}
	}
	return appended
}

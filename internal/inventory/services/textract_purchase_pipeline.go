package services

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
	"github.com/google/uuid"
)

// textractPurchasePipelineEnabledForTenant decides whether the v1.0.169 D1
// Textract Tables pipeline runs for Stock Purchase invoices on this tenant.
// Mirrors textractPipelineEnabledForTenant in
// /var/www/liquorpro/internal/sales/services/textract_pipeline.go (v1.0.165).
//
// **v1.0.193 — DEFAULT FLIPPED.** Textract is now the primary extractor on
// every tenant (opt-out instead of opt-in) because:
//   - It's deterministic. Same input → same output. Critical for the "100%
//     accuracy" bar — LLMs (Gemini in particular) showed non-deterministic
//     row counts on chhotu's 41-row dense bill: 41 / 10 / 6 across three runs
//     of the same image (real production data, 2026-05-06).
//   - It's cheaper. ~₹1.25/page vs Claude ~₹4-5/page or Gemini's
//     retry-storms (~₹1.50-7.50/page when truncation kicks in).
//   - Bills are 100% printed tables. Textract's AnalyzeDocument(TABLES)
//     returns explicit cell geometry; LLMs synthesize JSON from a vision
//     prompt and can hallucinate / drop / merge cells.
//
// Order of checks:
//   - STOCK_PURCHASE_PIPELINE=disabled                        → revert globally to LLM
//   - STOCK_PURCHASE_PIPELINE=gemini|openai|claude            → revert globally to LLM (any non-textract value)
//   - STOCK_PURCHASE_PIPELINE_TENANT_<uuid>=disabled|gemini|… → that tenant only opts out
//   - otherwise                                                → Textract (default)
//
// Per-tenant disable still works (ops can flip a single tenant back to LLM if
// Textract has a regression on their layout) but the global default is on.
func textractPurchasePipelineEnabledForTenant(tenantID uuid.UUID) bool {
	global := strings.ToLower(strings.TrimSpace(os.Getenv("STOCK_PURCHASE_PIPELINE")))
	switch global {
	case "disabled", "off", "false", "0", "gemini", "openai", "claude", "llm":
		return false
	}
	per := strings.ToLower(strings.TrimSpace(os.Getenv("STOCK_PURCHASE_PIPELINE_TENANT_" + tenantID.String())))
	switch per {
	case "disabled", "off", "false", "0", "gemini", "openai", "claude", "llm":
		return false
	}
	return true
}

// cachedTextractPurchaseClient holds the lazily-built AWS Textract client.
// One client per process is enough — AWS SDK v2 clients are concurrency-safe
// and reuse the underlying http.Client + credentials cache. Naming is scoped
// (`Purchase`) to avoid colliding with the sales package's identical pattern
// once both binaries link in the same go module.
var cachedTextractPurchaseClient *textract.Client

func newTextractPurchaseClient(ctx context.Context) (*textract.Client, error) {
	if cachedTextractPurchaseClient != nil {
		return cachedTextractPurchaseClient, nil
	}
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "ap-south-1"
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("textract purchase: load aws config: %w", err)
	}
	cachedTextractPurchaseClient = textract.NewFromConfig(cfg)
	return cachedTextractPurchaseClient, nil
}

// chhotu's UP-state IMFL purchase invoices have a fixed 9-column layout (the
// last column is sometimes absent — Duty/Tax is optional on intra-state runs).
// Textract returns ColumnIndex 1-based; the constants below are how we route
// each CELL block into the right ExtractedPurchaseItem field. Diverges from
// the sales register in /var/www/liquorpro/internal/sales/services/textract_pipeline.go:
//
//	Sales:    SerialNo | Brand | Open | Recv | Total | Sale | Rate | Amount | Close
//	Purchase: SerialNo | Brand | Size | Cases | BPC   | Total| Rate | Amount | Duty
//
// The shape is similar enough that 90% of the row-walk + math-gate logic ports
// directly; only the column meanings change.
const (
	purColSerialNo = 1
	purColBrand    = 2
	purColSize     = 3
	purColCases    = 4
	purColBPC      = 5
	purColTotalBot = 6
	purColRate     = 7
	purColAmount   = 8
	purColDuty     = 9
)

// extractWithTextract runs Textract AnalyzeDocument over each invoice image
// and returns the flat ExtractedPurchaseItem list. Caller (smart_purchase_service)
// merges this output with the matcher / vendor pipeline identical to the
// existing legacy path — the only contract difference is the source of the
// rows.
//
// Why standalone function instead of method? SmartPurchaseService has no
// logger field today (it uses log.Printf throughout); making this a function
// keeps the surface narrow and avoids a service-struct refactor on the same
// commit. Tenant + shop IDs are passed explicitly so a future alias-cascade
// pre-matcher (D2) can plug in without changing this signature.
func extractWithTextract(
	ctx context.Context,
	req *SmartPurchaseRequest,
	tenantID, shopID uuid.UUID,
) ([]ExtractedPurchaseItem, error) {

	_ = shopID // reserved for D2 alias-cascade pre-matcher; signature stable now

	client, err := newTextractPurchaseClient(ctx)
	if err != nil {
		return nil, err
	}

	startedAt := time.Now()
	out := make([]ExtractedPurchaseItem, 0, 64)
	totalRowSeen := 0

	// v1.0.193 — Two pre-processing steps before Textract:
	//   1) Local 2× upscale for small phone images. Chhotu's 720×1280 JPEGs
	//      yielded ~17 px/row on a 41-row invoice — below Textract's
	//      reliable row-detection threshold. Upscaling to 1440×2560 doubles
	//      that to ~34 px/row, enough for the table model to lock on.
	//   2) cv-sidecar /deskew for tilt correction. Phone shots routinely
	//      have 3-5° rotation that collapses table detection.
	// Both are best-effort — failure passes through the original bytes.
	deskew := newDeskewClient()

	for pageIdx, img := range req.Images {
		if len(img.Data) == 0 {
			continue
		}
		// (1) Upscale small images locally — golang.org/x/image/draw is
		// fast (~150ms for 720×1280) and stays in-process.
		preprocessed := prepareTextractImage(img.Data)
		if len(preprocessed) != len(img.Data) {
			log.Printf("SmartPurchase textract: page %d upscaled (%d → %d bytes)", pageIdx+1, len(img.Data), len(preprocessed))
		}
		// (2) Deskew via cv-sidecar — runs after upscale so the sidecar
		// gets the higher-resolution image to detect rotation against.
		dctx, dcancel := context.WithTimeout(ctx, 3*time.Second)
		desk := deskew.Deskew(dctx, preprocessed)
		dcancel()
		if len(desk) > 0 && len(desk) != len(preprocessed) {
			log.Printf("SmartPurchase textract: page %d deskewed (%d → %d bytes)", pageIdx+1, len(preprocessed), len(desk))
			preprocessed = desk
		}
		page, perr := runTextractInvoicePage(ctx, client, preprocessed, pageIdx+1)
		if perr != nil {
			log.Printf("SmartPurchase textract: page %d failed: %v — skipping page", pageIdx+1, perr)
			continue
		}
		if len(page) == 0 {
			log.Printf("SmartPurchase textract: page %d produced 0 rows", pageIdx+1)
			continue
		}
		log.Printf("SmartPurchase textract: page %d → %d rows", pageIdx+1, len(page))

		// v1.0.169 D1 — math-gate qty correction. Port of the v1.0.166/167
		// 2-of-3 consensus pattern in sales/services/textract_pipeline.go,
		// adapted to the purchase invoice's two independent identities:
		//
		//   M1 = cases × bpc                  (pack-math identity)
		//   M2 = amount ÷ rate                (revenue identity)
		//
		// When BOTH identities corroborate within ±1 AND the corroboration
		// disagrees with Textract's "total bottles" cell, replace with the
		// consensus. Pure arithmetic — no model call, no extra latency.
		// Stamps FieldConfidence is not on ExtractedPurchaseItem, so the
		// QuantityFlag field is used as the surfacing channel instead
		// (matches the existing legacy semantics — "rate_unit_uncertain"
		// is the closest pre-existing label; we'll add a dedicated label
		// in D2 once the matcher consumes it).
		mathFixed := 0
		for i := range page {
			row := &page[i]
			cases := int(row.QuantityRaw + 0.5)
			bpc := int(row.BottlesPerCase + 0.5)
			total := int(row.QuantityBottles + 0.5)
			rate := row.RatePerBottle
			amount := row.Amount

			candidates := []int{}
			// M1: cases × bpc, only when both legs are sane.
			if cases > 0 && bpc > 0 && bpc <= 96 {
				v := cases * bpc
				if v > 0 && v <= 2000 {
					candidates = append(candidates, v)
				}
			}
			// M2: amount ÷ rate, only when both legs are sane.
			// Rate floor of 30 keeps "duty per case" cells (₹2-15) from
			// being mistaken for a bottle rate; UP IMFL bottle rates start
			// at ~₹50 (90ml country liquor) and ceiling at ~₹6000 (premium 750ml).
			if rate >= 30 && rate <= 6000 && amount > 0 {
				v := int((amount / rate) + 0.5)
				if v > 0 && v <= 2000 {
					candidates = append(candidates, v)
				}
			}
			if len(candidates) < 2 {
				continue
			}
			// Find a value that ≥2 candidates agree on within ±1.
			consensus := -1
			for a := 0; a < len(candidates); a++ {
				agree := 1
				for b := 0; b < len(candidates); b++ {
					if a == b {
						continue
					}
					diff := candidates[a] - candidates[b]
					if diff < 0 {
						diff = -diff
					}
					if diff <= 1 {
						agree++
					}
				}
				if agree >= 2 {
					consensus = candidates[a]
					break
				}
			}
			if consensus < 0 || total == consensus {
				continue
			}
			log.Printf("SmartPurchase textract math-gate: page %d row %.0f total_bottles %d → %d (corroborators=%v)",
				pageIdx+1, row.RowNumber, total, consensus, candidates)
			row.QuantityBottles = float64(consensus)
			// Confidence ceiling for math-gate-corrected rows mirrors the
			// 0.97 sales analog at lines 213-214 of textract_pipeline.go.
			row.Confidence = 0.97
			mathFixed++
		}
		if mathFixed > 0 {
			log.Printf("SmartPurchase textract math-gate: page %d corrected %d total_bottles cells via row arithmetic (2-of-2 consensus)", pageIdx+1, mathFixed)
		}

		totalRowSeen += len(page)
		out = append(out, page...)
	}

	if len(out) == 0 {
		return nil, fmt.Errorf("textract returned no rows on any page")
	}

	log.Printf("SmartPurchase textract: tenant=%s %d total rows in %dms (~$%.2f est)",
		tenantID.String(), totalRowSeen, int(time.Since(startedAt).Milliseconds()),
		0.015*float64(len(req.Images)))
	return out, nil
}

// runTextractInvoicePage submits one page image to AnalyzeDocument and converts
// the Tables response into ExtractedPurchaseItem rows. Picks the largest TABLE
// block on the page — invoices always have one dominant grid; smaller blocks
// are usually header/total captures Textract over-segmented.
//
// Mirrors the structure of runTextractPage in
// /var/www/liquorpro/internal/sales/services/textract_pipeline.go:347-544;
// only the column→field mapping and row-filter heuristics differ.
func runTextractInvoicePage(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
) ([]ExtractedPurchaseItem, error) {

	pctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(pctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: raw},
		FeatureTypes: []ttypes.FeatureType{ttypes.FeatureTypeTables},
	})
	if err != nil {
		return nil, fmt.Errorf("AnalyzeDocument: %w", err)
	}

	// v1.0.193 — Drop handwritten WORD blocks before they reach the row builder.
	//
	// Both the bill and the gate-pass are 100% machine-printed by the supplier.
	// Any handwritten ink (margin notes, ticks, asterisks, "OK" stamps,
	// hand-tallied subtotals, pen strikes through brand names) is operator-
	// personal noise and must never be extracted into any field.
	//
	// Textract emits TextType=HANDWRITING on every handwritten WORD block.
	// Filtering at the blockByID stage is the cleanest knife: any CELL whose
	// child Word IDs were skipped will simply concatenate the remaining
	// printed words. Empty cells (operator wrote a tick over an otherwise
	// empty box) drop out via the existing 4-guard row filter below.
	blockByID := map[string]ttypes.Block{}
	skippedHandwriting := 0
	for _, b := range resp.Blocks {
		if b.Id == nil {
			continue
		}
		if b.BlockType == ttypes.BlockTypeWord && b.TextType == ttypes.TextTypeHandwriting {
			skippedHandwriting++
			continue
		}
		blockByID[*b.Id] = b
	}
	if skippedHandwriting > 0 {
		log.Printf("SmartPurchase textract: page %d dropped %d handwritten word blocks (operator pen-marks, not extracted)", pageNumber, skippedHandwriting)
	}

	// Find the largest TABLE block by cell count.
	var bestTable *ttypes.Block
	bestCellCount := 0
	for i, b := range resp.Blocks {
		if b.BlockType != ttypes.BlockTypeTable {
			continue
		}
		cells := 0
		for _, rel := range b.Relationships {
			if rel.Type == ttypes.RelationshipTypeChild {
				cells += len(rel.Ids)
			}
		}
		if cells > bestCellCount {
			bestCellCount = cells
			bestTable = &resp.Blocks[i]
		}
	}
	if bestTable == nil {
		return nil, nil
	}

	// rowsByIdx[r][c] is the CELL block at Textract (row r, col c).
	rowsByIdx := map[int32]map[int32]ttypes.Block{}
	for _, rel := range bestTable.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, cid := range rel.Ids {
			cell, ok := blockByID[cid]
			if !ok || cell.BlockType != ttypes.BlockTypeCell || cell.RowIndex == nil || cell.ColumnIndex == nil {
				continue
			}
			row := *cell.RowIndex
			col := *cell.ColumnIndex
			if rowsByIdx[row] == nil {
				rowsByIdx[row] = map[int32]ttypes.Block{}
			}
			rowsByIdx[row][col] = cell
		}
	}

	out := make([]ExtractedPurchaseItem, 0, len(rowsByIdx))
	rowIDs := make([]int32, 0, len(rowsByIdx))
	for r := range rowsByIdx {
		rowIDs = append(rowIDs, r)
	}
	sortInt32Asc(rowIDs)

	for _, r := range rowIDs {
		cells := rowsByIdx[r]

		// Skip the header row: detect by checking the Brand/Item column.
		if r == 1 {
			brandHdr := strings.ToUpper(strings.TrimSpace(joinCellText(cells[purColBrand], blockByID)))
			if strings.Contains(brandHdr, "BRAND") ||
				strings.Contains(brandHdr, "ITEM") ||
				strings.Contains(brandHdr, "PARTICULAR") ||
				strings.Contains(brandHdr, "DESCRIPTION") {
				continue
			}
		}

		brandText := strings.TrimSpace(joinCellText(cells[purColBrand], blockByID))
		serialText := strings.TrimSpace(joinCellText(cells[purColSerialNo], blockByID))
		sizeText := strings.TrimSpace(joinCellText(cells[purColSize], blockByID))
		cases, _ := parseIntPurchaseCell(cells[purColCases], blockByID)
		bpc, _ := parseIntPurchaseCell(cells[purColBPC], blockByID)
		totalBottles, _ := parseIntPurchaseCell(cells[purColTotalBot], blockByID)
		rate, _ := parseFloatPurchaseCell(cells[purColRate], blockByID)
		amount, _ := parseFloatPurchaseCell(cells[purColAmount], blockByID)
		duty, _ := parseFloatPurchaseCell(cells[purColDuty], blockByID)

		// v1.0.169 D1 — same 4-guard row filter as v1.0.165 sales (lines
		// 435-465). Each guard kills a class of garbage Textract leaks
		// through to the matcher:

		// Guard 1: completely empty brand AND zero quantity → blank row.
		if brandText == "" && cases == 0 && totalBottles == 0 {
			continue
		}
		// Guard 2: serial column says "Total"/"Grand"/"Sub" → footer row.
		uS := strings.ToUpper(serialText)
		if strings.Contains(uS, "TOTAL") || strings.Contains(uS, "GRAND") || strings.Contains(uS, "SUB") {
			continue
		}
		uB := strings.ToUpper(brandText)
		if strings.HasPrefix(uB, "TOTAL") || strings.HasPrefix(uB, "GRAND") || strings.HasPrefix(uB, "SUB") {
			continue
		}
		// Guard 3: implausibly-high total bottles (>2000). Real per-row
		// invoice qty maxes out around 500-800 bottles even on bulk runs;
		// >2000 is almost always Textract reading the Amount column as a
		// bottle count due to grid-detection slip.
		if totalBottles > 2000 {
			continue
		}
		// Guard 4: brand text too short or pure punctuation. Real brand
		// names on these invoices are >= 3 chars (even acronyms like
		// "8PM" are exactly 3).
		if len(brandText) < 3 && cases == 0 && totalBottles == 0 {
			continue
		}

		serialNum, _ := parseIntPurchaseCell(cells[purColSerialNo], blockByID)
		sizeML := parseSizeMLFromText(sizeText)

		// Row-level confidence = average of available cell confidences
		// (0-1 scale). Textract's per-cell confidence on the Hindi-script
		// columns runs 80-95% on chhotu's photos; this aggregate gives the
		// Flutter review screen a useful "is this row trustworthy" signal.
		confSum := 0.0
		confCount := 0
		for _, k := range []int32{purColBrand, purColSize, purColCases, purColBPC, purColTotalBot, purColRate, purColAmount} {
			if c, ok := cells[k]; ok && c.Confidence != nil {
				confSum += float64(*c.Confidence) / 100.0
				confCount++
			}
		}
		rowConf := 0.0
		if confCount > 0 {
			rowConf = confSum / float64(confCount)
		}

		// QuantityUnit follows the legacy contract: if the Cases column
		// is populated we treat the row as case-denominated; otherwise
		// fall back to "bottles". Rare bottle-only rows show on the very
		// last "loose" line of some invoices.
		qtyUnit := "cases"
		qtyRaw := float64(cases)
		if cases == 0 && totalBottles > 0 {
			qtyUnit = "bottles"
			qtyRaw = float64(totalBottles)
		}

		// rate_per_case derivation matches the GeminiOCR convention used
		// elsewhere in this package: bpc × per-bottle rate when both are
		// known. Keeps downstream consumers (matcher + UI) identical
		// whether the row came from Textract or Gemini.
		ratePerCase := 0.0
		if rate > 0 && bpc > 0 {
			ratePerCase = rate * float64(bpc)
		}

		item := ExtractedPurchaseItem{
			RowNumber:       float64(serialNum),
			Brand:           brandText,
			SizeText:        sizeText,
			SizeML:          float64(sizeML),
			QuantityRaw:     qtyRaw,
			QuantityUnit:    qtyUnit,
			BottlesPerCase:  float64(bpc),
			QuantityBottles: float64(totalBottles),
			RatePerBottle:   rate,
			RatePerCase:     ratePerCase,
			Amount:          amount,
			Confidence:      rowConf,
		}
		// Duty stays zeroed unless the optional col 9 was present and
		// parsed; downstream gate-pass merge rewrites this anyway when
		// gate-pass images are uploaded.
		_ = duty
		_ = pageNumber // ExtractedPurchaseItem has no PageNumber field; carried via append order

		// If pack-math fails the row is still emitted (legacy path tolerates
		// it) but flagged so the review UI surfaces it. Mirrors the existing
		// quantity_flag="rate_unit_uncertain" semantics in smart_purchase_types.go.
		if cases > 0 && bpc > 0 && totalBottles > 0 && cases*bpc != totalBottles {
			item.QuantityFlag = "rate_unit_uncertain"
		}
		if rate > 0 && totalBottles > 0 && amount > 0 {
			expected := rate * float64(totalBottles)
			diff := expected - amount
			if diff < 0 {
				diff = -diff
			}
			if diff > 0.01*amount && item.QuantityFlag == "" {
				item.QuantityFlag = "rate_unit_uncertain"
			}
		}

		out = append(out, item)
	}
	return out, nil
}

// joinCellText concatenates the WORD children of a CELL block into a single
// space-separated string. Direct port of cellText() at line 547 of the sales
// pipeline; renamed to avoid collision once both packages link in the same
// binary (the constant naming convention here is `purchase`-scoped).
func joinCellText(cell ttypes.Block, byID map[string]ttypes.Block) string {
	if cell.BlockType == "" {
		return ""
	}
	var parts []string
	for _, rel := range cell.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, id := range rel.Ids {
			child, ok := byID[id]
			if !ok {
				continue
			}
			if child.BlockType == ttypes.BlockTypeWord && child.Text != nil {
				parts = append(parts, *child.Text)
			}
		}
	}
	return strings.Join(parts, " ")
}

// parseIntPurchaseCell tolerates leading/trailing whitespace, commas, and the
// stray "₹" / "Rs" that Textract sometimes attaches to numeric cells. Returns
// (value, ok). Renamed from parseIntCell to avoid colliding with the sales
// package's identically-shaped helper.
func parseIntPurchaseCell(cell ttypes.Block, byID map[string]ttypes.Block) (int, bool) {
	t := strings.TrimSpace(joinCellText(cell, byID))
	if t == "" {
		return 0, false
	}
	t = strings.ReplaceAll(t, ",", "")
	clean := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		if r == '-' {
			return r
		}
		return -1
	}, t)
	if clean == "" {
		return 0, false
	}
	v, err := strconv.Atoi(clean)
	if err != nil {
		return 0, false
	}
	return v, true
}

func parseFloatPurchaseCell(cell ttypes.Block, byID map[string]ttypes.Block) (float64, bool) {
	t := strings.TrimSpace(joinCellText(cell, byID))
	if t == "" {
		return 0, false
	}
	t = strings.ReplaceAll(t, ",", "")
	t = strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		if r == '.' || r == '-' {
			return r
		}
		return -1
	}, t)
	if t == "" {
		return 0, false
	}
	v, err := strconv.ParseFloat(t, 64)
	if err != nil {
		return 0, false
	}
	return v, true
}

// parseSizeMLFromText pulls the integer ML value out of strings like "180ML",
// "180 ml", "375mL", "750". Falls back to 0 when nothing parses; downstream
// matcher will then key on bottles-per-case alone (UP IMFL invoices encode
// size redundantly across cols 3 and 5).
func parseSizeMLFromText(s string) int {
	if s == "" {
		return 0
	}
	digits := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, s)
	if digits == "" {
		return 0
	}
	v, err := strconv.Atoi(digits)
	if err != nil {
		return 0
	}
	return v
}

// sortInt32Asc — in-place ascending insertion sort. Cheap (rows-per-page is
// always < 60); avoids importing "sort" + the sort.Slice closure allocation.
// Renamed from sortInt32 for the same package-coexistence reason as the rest.
func sortInt32Asc(a []int32) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j-1] > a[j]; j-- {
			a[j-1], a[j] = a[j], a[j-1]
		}
	}
}

// sanitizeTextractRows drops obviously-junk rows that Textract emits when the
// invoice's column geometry confuses its table model. Returns the cleaned
// slice + the count of rows dropped (callers use the drop ratio as a signal
// to fall back to the Gemini legacy path).
//
// Real-data calibration: chhotu's 2026-05-03 SONU SINGH FL-2 invoice produced
// these junk patterns from Textract:
//   - Brand column reading the row number ("42", "43", "44") because the size
//     cell visually overlapped with the brand cell on a slightly tilted scan.
//   - Brand column reading the table header ("SI No.", "Description of Goods")
//     because the header row was indistinguishable from a data row.
//   - Brand column reading the footer ("Total", "TC S ON SALE") which has
//     numeric values in the columns aligned exactly like a data row.
//   - SizeML reading concatenated header + size text ("400 Strokes Royal
//     Whisky 750ml" → 400750) because two cells got merged.
//   - QuantityRaw reading the case×price product or scaled amount (671232)
//     because the qty cell was empty and the next cell got pulled in.
//
// Anything matching these patterns is filtered out so we don't pass it to the
// matcher (where it produces 7 garbage not_found rows that overwrite a clean
// 41-row Gemini extraction).
func sanitizeTextractRows(items []ExtractedPurchaseItem) ([]ExtractedPurchaseItem, int) {
	if len(items) == 0 {
		return items, 0
	}
	headerLikeRe := strings.NewReplacer(".", "", " ", "", "\t", "")
	junkBrands := map[string]struct{}{
		"sino": {}, "slno": {}, "sl": {}, "no": {}, "sn": {},
		"description": {}, "descriptionofgoods": {},
		"total": {}, "subtotal": {}, "grandtotal": {},
		"tcs": {}, "tcsonsale": {}, "tax": {}, "amount": {},
		"continued": {}, "page": {}, "page2": {}, "page3": {},
	}
	out := make([]ExtractedPurchaseItem, 0, len(items))
	dropped := 0
	for _, it := range items {
		brand := strings.TrimSpace(it.Brand)
		// 1. Empty brand AND no usable size = nothing to match.
		if brand == "" && it.SizeML <= 0 {
			dropped++
			continue
		}
		// 2. Brand is purely a row number ("42") or a header label.
		key := strings.ToLower(headerLikeRe.Replace(brand))
		if _, ok := junkBrands[key]; ok {
			dropped++
			continue
		}
		if isAllDigitsBrand(brand) {
			dropped++
			continue
		}
		// 3. Size is impossible (>2000 ml or smashed-together cells).
		// Real liquor sizes top out at 1000ml in this market; the standard
		// case sizes are 90/180/375/750/1000. Anything > 2000 is column merge.
		if it.SizeML > 2000 {
			dropped++
			continue
		}
		// 4. Quantity is impossible — no real invoice row has > 5000 cases.
		// chhotu's largest single-row qty was 192. Anything > 10000 is the
		// rate or amount cell being read into qty_raw.
		if it.QuantityRaw > 10000 {
			dropped++
			continue
		}
		// 5. Brand text contains a digit-stretch typical of a price merge.
		// e.g. "Royal Stag 7,213.44" — a real brand never has a 4+ digit run.
		if hasLongDigitRun(brand, 4) {
			dropped++
			continue
		}
		out = append(out, it)
	}
	return out, dropped
}

// isAllDigitsBrand returns true when the brand cell is entirely numeric (with
// optional whitespace + commas + dots) — it's almost certainly a row number,
// quantity, or amount that got mis-mapped into the brand column.
func isAllDigitsBrand(s string) bool {
	stripped := strings.TrimSpace(s)
	if stripped == "" {
		return false
	}
	hasDigit := false
	for _, r := range stripped {
		switch {
		case r >= '0' && r <= '9':
			hasDigit = true
		case r == '.' || r == ',' || r == ' ' || r == '-':
			// allowed punctuation
		default:
			return false
		}
	}
	return hasDigit
}

// hasLongDigitRun returns true when the string contains a contiguous run of
// digits of length >= n. Used to catch price/amount text that got merged into
// the brand cell (real brand names never carry a 4-digit number).
func hasLongDigitRun(s string, n int) bool {
	run := 0
	for _, r := range s {
		if r >= '0' && r <= '9' {
			run++
			if run >= n {
				return true
			}
		} else {
			run = 0
		}
	}
	return false
}

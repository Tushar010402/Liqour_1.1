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

// ============================================================================
// v1.0.184 Track S1 — AWS Textract Tables pipeline for AI Stock Setup.
//
// Mirrors the architecture that drove Smart Sale (v1.0.183) and Smart Purchase
// (v1.0.169) accuracy from ~65% to ~95+%: AWS Textract reads the printed
// register grid deterministically, returning per-cell geometry + confidence.
// The legacy Sonnet-vision path remains as fallback for layouts Textract
// can't grid (rare).
//
// Why this matters for chhotu's Mahua Khera 19:00 IST submission:
//   - 180ml: 14/19 matched, avg_conf 0.65, 12 of 24 rows manually corrected
//   - 375ml: 22/32 matched, avg_conf 0.63, 5 of 22 rows corrected
//   - 750ml: 23/35 matched, avg_conf 0.68, low_quality_image[2] flagged
// All four jobs ran the Sonnet vision LLM on handwritten register photos.
// Textract is purpose-built for this exact task and gives per-cell digit
// confidence Sonnet can't.
//
// Layout — chhotu's stock-setup register uses the SAME 9-column grid as the
// sales register (he uses the same notebook for both):
//
//	SerialNo | Brand | Opening | Receipt | Total | Sale | Rate | Amount | Closing
//
// Stock Setup operator only fills the column they're setting (req.StockColumn:
// "total" | "opening" | "closing"). The pipeline reads ALL columns Textract
// finds; downstream code uses StockColumn to pick the canonical value.
// ============================================================================

const (
	stkColSerialNo = 1
	stkColBrand    = 2
	stkColOpening  = 3
	stkColReceipt  = 4
	stkColTotal    = 5
	stkColSale     = 6
	stkColRate     = 7
	stkColAmount   = 8
	stkColClosing  = 9
)

// stockSetupTextractEnabledForTenant — kill switch + per-tenant override.
// Default ON for every tenant (chhotu's accuracy crisis is the trigger). Set
// STOCK_SETUP_PIPELINE=disabled (or =claude / =sonnet / =legacy) globally to
// fall back to the Sonnet vision path. Per-tenant override:
// STOCK_SETUP_PIPELINE_TENANT_<uuid>=disabled.
func stockSetupTextractEnabledForTenant(tenantID uuid.UUID) bool {
	global := strings.ToLower(strings.TrimSpace(os.Getenv("STOCK_SETUP_PIPELINE")))
	switch global {
	case "disabled", "off", "false", "0", "claude", "sonnet", "llm", "legacy":
		return false
	}
	per := strings.ToLower(strings.TrimSpace(os.Getenv("STOCK_SETUP_PIPELINE_TENANT_" + tenantID.String())))
	switch per {
	case "disabled", "off", "false", "0", "claude", "sonnet", "llm", "legacy":
		return false
	}
	return true
}

// cachedStockSetupTextractClient — lazy-built, process-singleton AWS client.
// Concurrency-safe per AWS SDK v2 docs; one is enough.
var cachedStockSetupTextractClient *textract.Client

func newStockSetupTextractClient(ctx context.Context) (*textract.Client, error) {
	if cachedStockSetupTextractClient != nil {
		return cachedStockSetupTextractClient, nil
	}
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "ap-south-1"
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("stock-setup textract: load aws config: %w", err)
	}
	cachedStockSetupTextractClient = textract.NewFromConfig(cfg)
	return cachedStockSetupTextractClient, nil
}

// stockSetupTextractMinRowsBySize — Track S2. Per-size minimum row floor that
// Textract output must clear before we trust it. Same structure as Smart Sale
// SMART_SALE_TEXTRACT_MIN_ROWS_BY_SIZE: comma-separated `<sizeML>:<minRows>`
// entries. Sizes not listed fall back to the default floor (5).
//
// Default `90:1,750:3` reflects chhotu's reality:
//   - 90 ml registers list ~3 SKUs (the default >=5 floor would force every
//     90 ml job to legacy Sonnet)
//   - 750 ml premium-spirit pages have ~3-4 high-MRP rows
//   - 180 / 375 ml are the dense pages (≥10 rows) so default floor applies.
func stockSetupTextractMinRowsForSize(sizeML int) int {
	const def = 5
	v := strings.TrimSpace(os.Getenv("STOCK_SETUP_TEXTRACT_MIN_ROWS_BY_SIZE"))
	if v == "" {
		// Sensible defaults baked in so the env var is optional.
		switch sizeML {
		case 90:
			return 1
		case 750:
			return 3
		}
		return def
	}
	for _, kv := range strings.Split(v, ",") {
		parts := strings.SplitN(strings.TrimSpace(kv), ":", 2)
		if len(parts) != 2 {
			continue
		}
		sz, err1 := strconv.Atoi(strings.TrimSpace(parts[0]))
		rows, err2 := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err1 != nil || err2 != nil {
			continue
		}
		if sz == sizeML {
			return rows
		}
	}
	return def
}

// extractStockRegisterWithTextract runs AWS Textract over every register page
// image and returns the flattened ExtractedStockRegisterItem list (page +
// row provenance preserved). Caller hooks this BEFORE the legacy Sonnet
// extractor; on error or under-floor row count, falls back to Sonnet.
//
// Returns (items, error). Empty `items` with nil error means Textract ran
// cleanly but produced 0 valid rows (e.g. blank page) — caller should NOT
// fall back in that case (the page genuinely has no data).
func extractStockRegisterWithTextract(
	ctx context.Context,
	images []SmartPurchaseImage,
	tenantID uuid.UUID,
	shopID uuid.UUID,
	stockColumn string,
	sizeML int,
) ([]ExtractedStockRegisterItem, error) {
	_ = shopID // reserved for shop-specific row-filter heuristics

	if len(images) == 0 {
		return nil, fmt.Errorf("no images")
	}
	client, err := newStockSetupTextractClient(ctx)
	if err != nil {
		return nil, err
	}

	startedAt := time.Now()
	out := make([]ExtractedStockRegisterItem, 0, 64)
	pageRowCounts := make([]int, 0, len(images))

	for pageIdx, img := range images {
		if len(img.Data) == 0 {
			pageRowCounts = append(pageRowCounts, 0)
			continue
		}
		page, perr := runTextractStockSetupPage(ctx, client, img.Data, pageIdx+1, stockColumn)
		if perr != nil {
			log.Printf("StockSetup textract: page %d failed: %v — caller will fall back", pageIdx+1, perr)
			return nil, perr
		}
		pageRowCounts = append(pageRowCounts, len(page))
		if len(page) == 0 {
			log.Printf("StockSetup textract: page %d produced 0 rows", pageIdx+1)
			continue
		}
		log.Printf("StockSetup textract: page %d → %d rows (sizeML=%d, stock_column=%s)", pageIdx+1, len(page), sizeML, stockColumn)
		out = append(out, page...)
	}

	// Per-size row floor. If the largest single page is below the size floor,
	// caller should fall back to Sonnet — Textract didn't see the grid we
	// expected. Don't sum across pages: a 2-page job with 8 rows on page 1 and
	// 0 on page 2 should NOT be considered "above floor" because the floor is
	// a per-page sanity check.
	maxPageRows := 0
	for _, c := range pageRowCounts {
		if c > maxPageRows {
			maxPageRows = c
		}
	}
	floor := stockSetupTextractMinRowsForSize(sizeML)
	if maxPageRows < floor {
		log.Printf("StockSetup textract: largest page only %d rows < floor %d for size %dml — caller falls back",
			maxPageRows, floor, sizeML)
		return nil, fmt.Errorf("textract under floor: max page rows %d < %d", maxPageRows, floor)
	}

	log.Printf("StockSetup textract: tenant=%s rows=%d in %dms across %d pages",
		tenantID.String(), len(out), int(time.Since(startedAt).Milliseconds()), len(images))
	return out, nil
}

// runTextractStockSetupPage submits one page image to AnalyzeDocument(TABLES)
// and converts the response into ExtractedStockRegisterItem rows.
//
// Lifts column→field mapping + row-filter guards directly from
// /var/www/liquorpro/internal/sales/services/textract_pipeline.go (v1.0.165
// runTextractPage); only the output struct and the StockColumn-aware
// canonical-value pick differ.
func runTextractStockSetupPage(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	pageNumber int,
	stockColumn string,
) ([]ExtractedStockRegisterItem, error) {

	pctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(pctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: raw},
		FeatureTypes: []ttypes.FeatureType{ttypes.FeatureTypeTables},
	})
	if err != nil {
		return nil, fmt.Errorf("AnalyzeDocument: %w", err)
	}

	blockByID := map[string]ttypes.Block{}
	for _, b := range resp.Blocks {
		if b.Id == nil {
			continue
		}
		blockByID[*b.Id] = b
	}

	// Find the largest TABLE block by cell count — registers always have one
	// dominant grid; other tables are usually header / total-line strips.
	var bestTable *ttypes.Block
	bestCells := 0
	for i, b := range resp.Blocks {
		if b.BlockType != ttypes.BlockTypeTable {
			continue
		}
		c := 0
		for _, rel := range b.Relationships {
			if rel.Type == ttypes.RelationshipTypeChild {
				c += len(rel.Ids)
			}
		}
		if c > bestCells {
			bestCells = c
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

	out := make([]ExtractedStockRegisterItem, 0, len(rowsByIdx))
	rowIDs := make([]int32, 0, len(rowsByIdx))
	for r := range rowsByIdx {
		rowIDs = append(rowIDs, r)
	}
	sortInt32StockSetup(rowIDs)

	rowOrdinal := 0 // 1-based ordinal among non-header data rows on this page
	for _, r := range rowIDs {
		cells := rowsByIdx[r]

		// Skip header row (Textract row 1 is usually the header).
		if r == 1 {
			brandHdr := strings.ToUpper(strings.TrimSpace(joinCellText(cells[stkColBrand], blockByID)))
			if strings.Contains(brandHdr, "BRAND") || strings.Contains(brandHdr, "ITEM") || strings.Contains(brandHdr, "PARTICULAR") {
				continue
			}
		}

		brandText := strings.TrimSpace(joinCellText(cells[stkColBrand], blockByID))
		serialText := strings.TrimSpace(joinCellText(cells[stkColSerialNo], blockByID))
		opening, _ := parseIntPurchaseCell(cells[stkColOpening], blockByID)
		receipt, _ := parseIntPurchaseCell(cells[stkColReceipt], blockByID)
		total, _ := parseIntPurchaseCell(cells[stkColTotal], blockByID)
		sale, _ := parseIntPurchaseCell(cells[stkColSale], blockByID)
		closing, _ := parseIntPurchaseCell(cells[stkColClosing], blockByID)
		rate, _ := parseFloatPurchaseCell(cells[stkColRate], blockByID)
		amount, _ := parseFloatPurchaseCell(cells[stkColAmount], blockByID)

		// Same 4-guard row filter pattern as Smart Sale + Smart Purchase
		// Textract pipelines (v1.0.165 / v1.0.169). Each guard kills a class
		// of garbage Textract leaks through.

		// Guard 1: empty brand AND zero numeric content → blank row.
		if brandText == "" && opening == 0 && receipt == 0 && total == 0 && sale == 0 && closing == 0 {
			continue
		}
		// Guard 2: serial column says Total/Grand/Sub → footer row.
		uS := strings.ToUpper(serialText)
		if strings.Contains(uS, "TOTAL") || strings.Contains(uS, "GRAND") || strings.Contains(uS, "SUB") {
			continue
		}
		uB := strings.ToUpper(brandText)
		if strings.HasPrefix(uB, "TOTAL") || strings.HasPrefix(uB, "GRAND") || strings.HasPrefix(uB, "SUB") {
			continue
		}
		// Guard 3: implausibly-high stock counts. Real per-row stock caps
		// at ~1500 (officer's choice 332 case noted on chhotu's 180ml). The
		// 5000+ values are Textract reading the Amount column as a stock
		// count due to grid-detection slip.
		if opening > 5000 || total > 5000 || closing > 5000 {
			continue
		}
		// Guard 4: brand text < 3 chars and no numeric content → corner cell.
		if len(brandText) < 3 && opening == 0 && total == 0 && closing == 0 {
			continue
		}
		// Guard 5 (v1.0.187): drop rows whose Opening, Receipt, Total, AND
		// Closing cells are ALL empty — even when the printed Brand column
		// has text. These are pre-printed register rows the operator simply
		// hasn't filled in (the shop doesn't carry that SKU at this time).
		// Mirror of the Smart Sale post-extraction filter that drops rows
		// with no sale data; keeps the review screen clean of "0 stock"
		// noise the operator would have to manually delete one-by-one.
		//
		// We do NOT include `sale` in this gate — Stock Setup never sets
		// sale, and including it would reject every row by definition.
		// Rate is allowed to be non-zero (printed register prices) — those
		// are still informational.
		if opening == 0 && receipt == 0 && total == 0 && closing == 0 {
			continue
		}

		// Per-cell confidence comes directly from Textract's CELL block.
		fc := map[string]float64{}
		setConf := func(k string, c ttypes.Block) {
			if c.Confidence != nil {
				fc[k] = float64(*c.Confidence) / 100.0
			}
		}
		setConf("brand", cells[stkColBrand])
		setConf("opening", cells[stkColOpening])
		setConf("receipt", cells[stkColReceipt])
		setConf("total", cells[stkColTotal])
		setConf("sale", cells[stkColSale])
		setConf("rate", cells[stkColRate])
		setConf("amount", cells[stkColAmount])
		setConf("closing", cells[stkColClosing])

		// v1.0.187 — Track 100% numeric accuracy. When Textract returns
		// NON-numeric text in a numeric column (e.g. "no" / "or" / "as" /
		// "+" / "-" / "/-"), the parser quietly returned 0 above but the
		// cell IS NOT actually empty — it had handwriting Textract
		// mis-classified as text instead of a digit. We force the cell's
		// field_confidence to 0 so the doubt-popup gate (Track S5) fires
		// and asks the operator. Without this, the row would silently
		// apply with 0 stock for a brand the operator clearly wrote a
		// number for. Real example: chhotu's FM Tower 180 ml Royal Stag
		// 21 → "or"; Sterling Reserve B7 sale 2 → "no".
		forceLowConfIfNonNumeric := func(field string, parsedI int, parsedF float64, raw string) {
			raw = strings.TrimSpace(raw)
			if raw == "" {
				return
			}
			// Did the parser succeed? If yes, leave confidence alone.
			if parsedI != 0 || parsedF != 0 {
				return
			}
			// Parser returned 0 AND the cell isn't blank → garbage text
			// in a numeric cell. Force confidence to 0.
			fc[field] = 0
		}
		forceLowConfIfNonNumeric("opening", opening, 0, joinCellText(cells[stkColOpening], blockByID))
		forceLowConfIfNonNumeric("receipt", receipt, 0, joinCellText(cells[stkColReceipt], blockByID))
		forceLowConfIfNonNumeric("total", total, 0, joinCellText(cells[stkColTotal], blockByID))
		forceLowConfIfNonNumeric("sale", sale, 0, joinCellText(cells[stkColSale], blockByID))
		forceLowConfIfNonNumeric("closing", closing, 0, joinCellText(cells[stkColClosing], blockByID))
		forceLowConfIfNonNumeric("rate", 0, rate, joinCellText(cells[stkColRate], blockByID))
		forceLowConfIfNonNumeric("amount", 0, amount, joinCellText(cells[stkColAmount], blockByID))

		rowConf := 0.0
		if len(fc) > 0 {
			sum := 0.0
			for _, v := range fc {
				sum += v
			}
			rowConf = sum / float64(len(fc))
		}

		rowOrdinal++

		// Pick the canonical stock value from the StockColumn the operator
		// said they were filling. Default "total" matches the legacy
		// req.StockColumn default in ProcessExtraction.
		canonical := total
		switch strings.ToLower(stockColumn) {
		case "opening":
			canonical = opening
			if canonical == 0 && total > 0 {
				canonical = total
			}
		case "closing":
			canonical = closing
			if canonical == 0 && total > 0 {
				canonical = total
			}
		default:
			// "total" — sum of opening + receipt when total is empty but those
			// two are filled (closing-stock setups often only have opening +
			// receipt).
			if canonical == 0 && opening > 0 {
				canonical = opening + receipt
			}
		}

		item := ExtractedStockRegisterItem{
			RowNumber:       rowOrdinal,
			Brand:           brandText,
			Opening:         opening,
			Receipt:         receipt,
			Total:           total,
			Sale:            sale,
			Closing:         closing,
			Rate:            rate,
			Amount:          amount,
			Confidence:      rowConf,
			FieldConfidence: fc,
			PageNumber:      pageNumber,
			Source:          "textract",
		}
		// Track S3 — math gate. When two of (Opening, Receipt, Total) are
		// non-zero AND the arithmetic doesn't agree, surface it via field
		// confidence so the review screen highlights the cell. This is the
		// same 2-of-3-consensus pattern as Smart Sale's textract_pipeline.go
		// math-gate (v1.0.166/167). Pure arithmetic, no model call.
		if opening > 0 && receipt > 0 && total > 0 && opening+receipt != total {
			// Arithmetic disagrees — drop confidence on the Total cell so
			// review highlights it. Pick the lower of the three current confs
			// so we don't accidentally raise it.
			if fc["total"] > 0.5 {
				fc["total"] = 0.5
			}
			item.FieldConfidence = fc
		}
		// Set the canonical value via existing Total field for downstream
		// matchers that expect it (canonical resolution happens in the apply
		// path; this is just a hint).
		_ = canonical

		out = append(out, item)
	}
	return out, nil
}

// sortInt32StockSetup — local int32-slice sort to keep the package
// self-contained (purchase pipeline has the same helper named differently).
func sortInt32StockSetup(a []int32) {
	for i := 1; i < len(a); i++ {
		for j := i; j > 0 && a[j-1] > a[j]; j-- {
			a[j-1], a[j] = a[j], a[j-1]
		}
	}
}

// ctxWithHintsTextract is a thin pass-through so the Textract path mirrors
// the Sonnet path's signature; Textract doesn't consume the prompt-hints
// context value (deterministic OCR), but having it documented keeps future
// authors from accidentally adding a model call that does.
func ctxWithHintsTextract(parent context.Context) context.Context {
	return parent
}

// stockSetupAutoFixThreshold — Track S4. Min occurrence_count required to
// silently apply a confirmed (raw → corrected) digit pair. Default 3 (the
// same threshold Smart Sale uses). Set to 0 to disable auto-fix entirely.
// Tunable via STOCK_SETUP_AUTO_FIX_THRESHOLD.
func stockSetupAutoFixThreshold() int {
	const def = 3
	v := strings.TrimSpace(os.Getenv("STOCK_SETUP_AUTO_FIX_THRESHOLD"))
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 0 {
		return def
	}
	return n
}

// stockSetupCellDoubtFloor — Track S5 / v1.0.187. Per-cell confidence floor
// below which the extractor emits a doubt for the operator to confirm.
//
// Default split (v1.0.187 — 100% numeric accuracy push):
//   - Numeric cells (opening / receipt / total / closing / sale / rate / amount)
//     use the AGGRESSIVE floor: 0.95 by default. Anything below 95% certainty
//     goes to the popup queue. The user explicitly asked for 100% numeric
//     accuracy and the popup queue is the path that gets us there — every
//     uncertain digit becomes a one-tap operator confirmation that ALSO
//     teaches the system (raw → corrected) for future shop-shop runs.
//   - Brand / name cells use the LOOSE floor: 0.65. Brand text is
//     usually printed (high Textract confidence) and false positives on
//     low-conf brand cells would flood the popup queue.
//
// Tunable via STOCK_SETUP_CELL_DOUBT_FLOOR (numeric) and
// STOCK_SETUP_BRAND_DOUBT_FLOOR (brand/name).
func stockSetupCellDoubtFloor() float64 {
	const def = 0.95 // AGGRESSIVE — was 0.65 before the 100% numeric push.
	v := strings.TrimSpace(os.Getenv("STOCK_SETUP_CELL_DOUBT_FLOOR"))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f <= 0 || f > 1 {
		return def
	}
	return f
}

// stockSetupBrandDoubtFloor — separate, looser floor for non-numeric brand
// / name cells. v1.0.187. Defaults to 0.65 (the legacy floor); set
// STOCK_SETUP_BRAND_DOUBT_FLOOR to override.
func stockSetupBrandDoubtFloor() float64 {
	const def = 0.65
	v := strings.TrimSpace(os.Getenv("STOCK_SETUP_BRAND_DOUBT_FLOOR"))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f <= 0 || f > 1 {
		return def
	}
	return f
}

// stockSetupDoubtAutoFixConf — Track S5. Confidence floor above which the
// system silently auto-fixes (emitting the doubt only as informational
// AutoFixed=true) instead of asking the operator. Mirrors Smart Sale's
// SMART_SALE_INVARIANT_AUTOFIX_CONF. Default 0.85.
func stockSetupDoubtAutoFixConf() float64 {
	const def = 0.85
	v := strings.TrimSpace(os.Getenv("STOCK_SETUP_DOUBT_AUTOFIX_CONF"))
	if v == "" {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil || f <= 0 || f > 1 {
		return def
	}
	return f
}

// emitTextractCellDoubts walks one extracted row and produces zero or more
// StockSetupCellDoubt entries based on per-cell confidence + arithmetic
// invariants. The caller attaches the doubts to the SmartStockSetupExtractedItem
// for Flutter to walk. Pure server-side logic — no model calls.
//
// Rules:
//
//	R1 low_confidence: any non-empty cell with field_confidence < FLOOR.
//	R2 math_disagree:  Opening + Receipt != Total (when all three filled).
//	R3 rate_outlier:   Rate > 0 but < 30 OR > 6000 (typo-class detection).
//
// The brand_no_match / ambiguous_match / mrp_doubt rules fire later in
// matchAndEnrich (they need the catalog match to compare against).
//
// Track S5 — Stock Setup doubt-popup queue parity.
func emitTextractCellDoubts(row ExtractedStockRegisterItem, fc map[string]float64) []StockSetupCellDoubt {
	if len(fc) == 0 {
		return nil
	}
	floor := stockSetupCellDoubtFloor()
	out := make([]StockSetupCellDoubt, 0, 4)

	// R1 — per-cell low confidence on numeric cells that have content.
	type numCell struct {
		field string
		valI  int
		valF  float64
		isInt bool
	}
	cells := []numCell{
		{"opening", row.Opening, 0, true},
		{"receipt", row.Receipt, 0, true},
		{"total", row.Total, 0, true},
		{"closing", row.Closing, 0, true},
		{"sale", row.Sale, 0, true},
		{"rate", 0, row.Rate, false},
		{"amount", 0, row.Amount, false},
	}
	for _, c := range cells {
		conf, ok := fc[c.field]
		if !ok {
			continue
		}
		nonZero := (c.isInt && c.valI != 0) || (!c.isInt && c.valF != 0)
		if !nonZero {
			continue
		}
		if conf >= floor {
			continue
		}
		d := StockSetupCellDoubt{
			Field:      c.field,
			Rule:       "low_confidence",
			Confidence: conf,
		}
		if c.isInt {
			ai := c.valI
			d.AIValueInt = &ai
			d.HumanText = fmt.Sprintf("Brand %q: we read %s = %d but our confidence is %.0f%%. Please verify.",
				row.Brand, niceFieldLabel(c.field), c.valI, conf*100)
		} else {
			ai := c.valF
			d.AIValueFloat = &ai
			d.HumanText = fmt.Sprintf("Brand %q: we read %s = %.0f but our confidence is %.0f%%. Please verify.",
				row.Brand, niceFieldLabel(c.field), c.valF, conf*100)
		}
		out = append(out, d)
	}

	// R2 — Opening + Receipt != Total when all three are non-zero. Suggest
	// the arithmetic answer for Total. High confidence (0.95) when the user
	// confirms the math is right.
	if row.Opening > 0 && row.Receipt > 0 && row.Total > 0 && row.Opening+row.Receipt != row.Total {
		expected := row.Opening + row.Receipt
		ai := row.Total
		s := expected
		out = append(out, StockSetupCellDoubt{
			Field:        "total",
			Rule:         "math_disagree",
			AIValueInt:   &ai,
			SuggestedInt: &s,
			Confidence:   0.90,
			HumanText: fmt.Sprintf("Brand %q: Opening + Receipt = %d + %d = %d, but we read Total = %d. Tap to use %d.",
				row.Brand, row.Opening, row.Receipt, expected, row.Total, expected),
		})
	}

	// R3 — Rate outlier. Real per-bottle MRPs at chhotu's tenant range
	// ₹50-6000 (90 ml country liquor floor / premium 750 ml ceiling). Anything
	// outside is almost always an OCR slip (column misread, decimal drop).
	if row.Rate > 0 && (row.Rate < 30 || row.Rate > 6000) {
		ai := row.Rate
		out = append(out, StockSetupCellDoubt{
			Field:        "rate",
			Rule:         "rate_outlier",
			AIValueFloat: &ai,
			Confidence:   0,
			HumanText: fmt.Sprintf("Brand %q: we read MRP = ₹%.0f which looks unusual. Please correct.",
				row.Brand, row.Rate),
		})
	}

	return out
}

// appendMatchCellDoubts adds brand / match / MRP-related doubts to an
// already-matched SmartStockSetupExtractedItem. Idempotent — won't re-emit
// duplicates if called twice on the same row.
//
// Rules:
//
//	M1 brand_no_match:    Status == "not_found" or "auto_create" — operator
//	                      should confirm the AI brand text or pick from
//	                      master_brand_suggestions.
//	M2 ambiguous_match:   len(AlternativeMatches) ≥ 2 with top-two within
//	                      0.10 confidence — operator picks one.
//	M3 mrp_doubt:         Master MRP differs from Rate by >₹10 — possibly
//	                      mis-routed match (right brand text, wrong product).
//	M4 low_match:         MatchConfidence < 0.55 (very weak match).
//
// All have AutoFixed=false (operator MUST confirm).
//
// v1.0.185 Track S5.
func appendMatchCellDoubts(item *SmartStockSetupExtractedItem) {
	if item == nil {
		return
	}
	// De-dupe shield: if we've already emitted a brand or name rule on this
	// row, don't add another (could happen if the post-pass re-runs).
	for _, d := range item.CellDoubts {
		if d.Field == "brand" || d.Field == "name" || d.Rule == "mrp_doubt" {
			return
		}
	}

	// M1 — Status is not_found OR auto_create.
	if item.Status == "not_found" || item.Status == "auto_create" {
		ai := item.OriginalAIBrand
		if ai == "" {
			ai = item.BrandName
		}
		item.CellDoubts = append(item.CellDoubts, StockSetupCellDoubt{
			Field:       "brand",
			Rule:        "brand_no_match",
			AIValueText: ai,
			Confidence:  0,
			HumanText: fmt.Sprintf("Brand %q didn't match any product in your catalog. Please pick the correct one or confirm to add as new.",
				ai),
		})
		return
	}

	// M2 — top-2 alternatives within 0.10 of each other (genuine ambiguity).
	if len(item.AlternativeMatches) >= 2 {
		// AlternativeMatches is sorted by confidence DESC by buildAlternatives.
		top := item.AlternativeMatches[0].Confidence
		runnerUp := item.AlternativeMatches[1].Confidence
		if top-runnerUp < 0.10 && top < 0.95 {
			item.CellDoubts = append(item.CellDoubts, StockSetupCellDoubt{
				Field:        "name",
				Rule:         "ambiguous_match",
				AIValueText:  item.MatchedDisplayName,
				SuggestedText: item.MatchedDisplayName,
				Confidence:   top,
				HumanText: fmt.Sprintf("Multiple products match this brand. We picked %q (%.0f%%); other matches within %.0f%%. Tap to confirm or swap.",
					item.MatchedDisplayName, top*100, (top-runnerUp)*100),
			})
			return
		}
	}

	// M3 — MRP doubt: master MRP differs from extracted rate by >₹10. The
	// row probably mis-routed (right brand text → wrong product).
	if item.MasterMRP > 0 && item.Rate > 0 {
		diff := item.Rate - item.MasterMRP
		if diff < 0 {
			diff = -diff
		}
		if diff > 10 {
			ai := item.Rate
			s := item.MasterMRP
			item.CellDoubts = append(item.CellDoubts, StockSetupCellDoubt{
				Field:          "rate",
				Rule:           "mrp_doubt",
				AIValueFloat:   &ai,
				SuggestedFloat: &s,
				Confidence:     0.85,
				HumanText: fmt.Sprintf("Brand %q: we read MRP = ₹%.0f but the master catalog says ₹%.0f. Tap to use ₹%.0f.",
					item.BrandName, item.Rate, item.MasterMRP, item.MasterMRP),
			})
			return
		}
	}

	// M4 — generic low match confidence.
	if item.MatchConfidence > 0 && item.MatchConfidence < 0.55 {
		item.CellDoubts = append(item.CellDoubts, StockSetupCellDoubt{
			Field:       "name",
			Rule:        "low_match",
			AIValueText: item.MatchedDisplayName,
			Confidence:  item.MatchConfidence,
			HumanText: fmt.Sprintf("Brand %q matched %q but only at %.0f%% confidence. Please verify.",
				item.OriginalAIBrand, item.MatchedDisplayName, item.MatchConfidence*100),
		})
	}
}

// loadProductSynonyms returns productID → []meta_keywords for every product
// linked to a saas_brand. Empty map when no products are linked. Mirrors
// Smart Sale's loadExciseInfoMap; the result feeds matching.Product.Synonyms
// so the shared fuzzy matcher recognises shop-floor abbreviations
// ("MCD" → "Mc Dowells", "OC" → "Officer's Choice", "M.M" → "M2 Magic
// Moments", etc.) at parity with Smart Sale.
//
// v1.0.187 Track meta-keyword parity.
func (s *SmartStockSetupService) loadProductSynonyms(tenantID uuid.UUID, products []dbProduct) map[string][]string {
	out := make(map[string][]string, len(products))
	if len(products) == 0 {
		return out
	}
	// Collect unique saas_brand IDs and build reverse index brand→[productIDs].
	brandToProducts := make(map[string][]string)
	for i := range products {
		p := &products[i]
		if p.SaasBrandID == "" {
			continue
		}
		brandToProducts[p.SaasBrandID] = append(brandToProducts[p.SaasBrandID], p.ID)
	}
	if len(brandToProducts) == 0 {
		return out
	}
	brandIDs := make([]string, 0, len(brandToProducts))
	for id := range brandToProducts {
		brandIDs = append(brandIDs, id)
	}
	type row struct {
		ID              string
		MetaKeywordsCSV string `gorm:"column:meta_keywords_csv"`
	}
	var rows []row
	if err := s.db.Raw(`
		SELECT id::text AS id,
		       COALESCE(array_to_string(meta_keywords, '|'), '') AS meta_keywords_csv
		FROM saas_brands
		WHERE id::text IN (?) AND deleted_at IS NULL
	`, brandIDs).Scan(&rows).Error; err != nil {
		log.Printf("Smart Stock Setup: loadProductSynonyms failed: %v", err)
		return out
	}
	for _, r := range rows {
		if r.MetaKeywordsCSV == "" {
			continue
		}
		var kws []string
		for _, k := range strings.Split(r.MetaKeywordsCSV, "|") {
			k = strings.TrimSpace(k)
			if k != "" {
				kws = append(kws, k)
			}
		}
		if len(kws) == 0 {
			continue
		}
		for _, pid := range brandToProducts[r.ID] {
			out[pid] = kws
		}
	}
	_ = tenantID // reserved for future per-tenant synonym overrides
	return out
}

// TenantInventoryStat carries the tenant-wide signals the matcher's
// TenantInventoryBias scoring uses. Built once per Stock Setup run by
// loadTenantInventoryStats; passed through matchAndEnrich to populate
// matching.Product fields.
//
// v1.0.199 — Track 3.
type TenantInventoryStat struct {
	// TotalStockUnits = sum of stock across all shops in this tenant.
	// Useful when the matcher needs to know "this product is stocked SOMEWHERE
	// in the tenant" even if not at the current shop.
	TotalStockUnits int
	// SoldDaysAgo = MIN(days_since_last_sale) across any shop in the tenant.
	// -1 means never sold by any shop in the tenant.
	SoldDaysAgo int
	// HasConfirmedAlias = true when ocr_brand_aliases has a tenant-wide row
	// (shop_id IS NULL) pointing to this product. Strong signal that operators
	// somewhere in the tenant have already disambiguated this brand.
	HasConfirmedAlias bool
}

// loadTenantInventoryStats builds productID → TenantInventoryStat for every
// product in the tenant's catalog passed in. Three queries:
//   1. SUM(current_stock) per product across stocks rows (any shop in tenant).
//   2. MIN(now - last_sale_date) per product from daily_sales_items.
//   3. EXISTS check for tenant-wide ocr_brand_aliases (shop_id IS NULL).
//
// All queries are scoped to the tenant; product IDs are inserted via the
// product list to avoid scanning unrelated tenants.
//
// v1.0.199 — Track 3.
func (s *SmartStockSetupService) loadTenantInventoryStats(tenantID uuid.UUID, products []dbProduct) map[string]TenantInventoryStat {
	out := make(map[string]TenantInventoryStat, len(products))
	if len(products) == 0 {
		return out
	}
	pids := make([]string, 0, len(products))
	for i := range products {
		if products[i].ID != "" {
			pids = append(pids, products[i].ID)
		}
		// Initialize default: never sold (-1) so SoldDaysAgo doesn't accidentally
		// look "sold today" when the product has zero history.
		out[products[i].ID] = TenantInventoryStat{SoldDaysAgo: -1}
	}
	if len(pids) == 0 {
		return out
	}

	// Query 1 — tenant-wide stock totals. The stocks table is per-shop; sum
	// across shops in the tenant.
	type stockRow struct {
		ProductID string `gorm:"column:product_id"`
		Total     int    `gorm:"column:total"`
	}
	var stockRows []stockRow
	if err := s.db.Raw(`
		SELECT product_id::text AS product_id, COALESCE(SUM(quantity),0) AS total
		FROM stocks
		WHERE tenant_id = ? AND product_id::text IN (?) AND deleted_at IS NULL
		GROUP BY product_id
	`, tenantID, pids).Scan(&stockRows).Error; err == nil {
		for _, r := range stockRows {
			st := out[r.ProductID]
			st.TotalStockUnits = r.Total
			out[r.ProductID] = st
		}
	} else {
		log.Printf("Smart Stock Setup: loadTenantInventoryStats stocks query failed: %v", err)
	}

	// Query 2 — most-recent sale across any shop in the tenant.
	type saleRow struct {
		ProductID  string `gorm:"column:product_id"`
		MinDaysAgo int    `gorm:"column:min_days_ago"`
	}
	var saleRows []saleRow
	if err := s.db.Raw(`
		SELECT i.product_id::text AS product_id,
		       EXTRACT(DAY FROM (NOW() - MAX(r.created_at)))::int AS min_days_ago
		FROM daily_sales_items i
		JOIN daily_sales_records r ON r.id = i.daily_sales_record_id
		WHERE r.tenant_id = ? AND i.product_id::text IN (?)
		  AND r.deleted_at IS NULL AND i.deleted_at IS NULL
		  AND r.created_at >= NOW() - INTERVAL '90 days'
		GROUP BY i.product_id
	`, tenantID, pids).Scan(&saleRows).Error; err == nil {
		for _, r := range saleRows {
			st := out[r.ProductID]
			st.SoldDaysAgo = r.MinDaysAgo
			out[r.ProductID] = st
		}
	} else {
		log.Printf("Smart Stock Setup: loadTenantInventoryStats sales query failed: %v", err)
	}

	// Query 3 — tenant-wide alias rows (shop_id IS NULL).
	type aliasRow struct {
		ProductID string `gorm:"column:product_id"`
	}
	var aliasRows []aliasRow
	if err := s.db.Raw(`
		SELECT DISTINCT product_id::text AS product_id
		FROM ocr_brand_aliases
		WHERE tenant_id = ? AND shop_id IS NULL AND deleted_at IS NULL
		  AND product_id::text IN (?)
	`, tenantID, pids).Scan(&aliasRows).Error; err == nil {
		for _, r := range aliasRows {
			st := out[r.ProductID]
			st.HasConfirmedAlias = true
			out[r.ProductID] = st
		}
	} else {
		log.Printf("Smart Stock Setup: loadTenantInventoryStats alias query failed: %v", err)
	}

	return out
}

// envBoolOff returns true when the env var is set to a falsy value
// ("0","false","no","off"). Used as an OPT-OUT switch — feature defaults to ON
// unless explicitly disabled. Any other value (including unset) → returns false
// (i.e. the feature stays on).
//
// v1.0.199 — Track 3.
func envBoolOff(name string) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(name)))
	switch v {
	case "0", "false", "no", "off":
		return true
	}
	return false
}

func niceFieldLabel(field string) string {
	switch field {
	case "opening":
		return "Opening"
	case "receipt":
		return "Receipt"
	case "total":
		return "Total"
	case "closing":
		return "Closing"
	case "sale":
		return "Sale"
	case "rate":
		return "MRP"
	case "amount":
		return "Amount"
	case "brand":
		return "Brand"
	}
	return field
}

package services

// v1.0.138 Sheet-Grid pipeline.
//
// User-confirmed design: convert the printed register photo to a structured
// 2D sheet (rows × columns) deterministically via CV, then read ONLY the
// non-blank Sale cells with one batched AI call. Brand for each printed
// row is resolved by row-index lookup against the shop's MRP-ordered
// inventory (no AI fuzzy matching, no brand↔row misalignment possible).
// Math gate (open − sale = close ±2) catches misreads; one cell-level
// retry on math failure; remaining failures surface as warnings to the
// operator (option C).
//
// This file is the standalone implementation. Integration into the
// production extract-pipeline is gated by env SMART_SALE_SHEET_GRID=1.

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

// SheetCell is one element of the CV sheet — pixel bounds + ink/has_writing.
type SheetCell struct {
	RowIdx          int     `json:"row_idx"`
	ColName         string  `json:"col_name"`
	XLeft           int     `json:"x_left"`
	XRight          int     `json:"x_right"`
	YTop            int     `json:"y_top"`
	YBot            int     `json:"y_bot"`
	InkRatio        float64 `json:"ink_ratio"`
	HasWriting      bool    `json:"has_writing"`
	StrokesEstimate int     `json:"strokes_estimate"`
}

// SheetRow / SheetCol mirror /sheet response.
type SheetRow struct {
	Idx  int `json:"idx"`
	YTop int `json:"y_top"`
	YBot int `json:"y_bot"`
}
type SheetCol struct {
	Name   string `json:"name"`
	XLeft  int    `json:"x_left"`
	XRight int    `json:"x_right"`
}
type SheetResponse struct {
	OK         bool        `json:"ok"`
	PageSizePx []int       `json:"page_size_px"`
	DeskewDeg  float64     `json:"deskew_deg"`
	RowCount   int         `json:"row_count"`
	ColCount   int         `json:"col_count"`
	Rows       []SheetRow  `json:"rows"`
	Cols       []SheetCol  `json:"cols"`
	Cells      []SheetCell `json:"cells"`
	Diag       map[string]any `json:"diag"`
}

// PrintedBrand — one row of the shop's MRP-ordered inventory list. The
// printed register's row N corresponds to PrintedBrand[N-1].
type PrintedBrand struct {
	ProductID  uuid.UUID
	BrandName  string
	MRP        float64
	StockQty   int
}

// SheetSaleRow is the per-row outcome the pipeline returns to the caller.
type SheetSaleRow struct {
	RowIdx       int        // 1-indexed printed-row number on the page
	ProductID    *uuid.UUID // nil for handwritten add-on rows the matcher couldn't resolve
	BrandName    string
	MRP          float64
	OpeningStock int
	SaleQty      int
	ClosingStock int
	Source       string  // "blank", "skipped-zero-stock", "ai-digit", "ai-retry", "math-warn", "addon"
	Confidence   float64
	Warnings     []string
}

// SheetExtractionResult is the page-level extraction output.
type SheetExtractionResult struct {
	PageIndex        int
	ImageSHA256      string
	Rows             []SheetSaleRow
	CostINR          float64 // estimated cost in INR for telemetry
	CallsMade        int
	Warnings         []string
	// v1.0.146 — count of CV-detected non-blank data rows on the page.
	// Caller compares to len(Rows with SaleQty>0) to detect under-coverage
	// and trigger supplemental legacy fallback when AI missed many rows.
	ExpectedRowCount int
}

// SaleSheetExtractor orchestrates the v1.0.138 sheet-grid pipeline.
type SaleSheetExtractor struct {
	db           *gorm.DB
	logger       *logrus.Logger
	cvSidecar    *CVSidecarClient
	aliasService *alias.AliasService // optional; nil → no learned-alias resolution
	claudeAPIKey string
	httpClient   *http.Client
}

// NewSaleSheetExtractor constructs the extractor. Anthropic API key is read
// from env ANTHROPIC_API_KEY; cv-sidecar URL from existing CVSidecarClient.
// aliasService may be nil — when supplied, handwritten add-on rows are first
// looked up against learned tenant aliases (operator-confirmed mappings),
// dramatically improving brand resolution on cursive abbreviations like
// "M.M" → M2 Magic Moments Pink.
func NewSaleSheetExtractor(db *gorm.DB, logger *logrus.Logger, cv *CVSidecarClient, aliasSvc *alias.AliasService) *SaleSheetExtractor {
	return &SaleSheetExtractor{
		db:           db,
		logger:       logger,
		cvSidecar:    cv,
		aliasService: aliasSvc,
		claudeAPIKey: os.Getenv("ANTHROPIC_API_KEY"),
		httpClient:   &http.Client{Timeout: 60 * time.Second},
	}
}

// SheetGridEnabled — env-gated rollout knob.
func SheetGridEnabled() bool {
	return os.Getenv("SMART_SALE_SHEET_GRID") == "1"
}

const SheetGridPipelineVersion = "sheet-v1.0.160"

// CachedExtraction is the persisted shape (image-bytes-only, brand-agnostic).
type CachedExtraction struct {
	Rows      []SheetSaleRow `json:"rows"`
	CallsMade int            `json:"calls_made"`
	CostINR   float64        `json:"cost_inr"`
	Warnings  []string       `json:"warnings"`
}

// loadFromCache returns a cached extraction by SHA-256 if present + bumps hit_count.
func (e *SaleSheetExtractor) loadFromCache(ctx context.Context, sha string) *CachedExtraction {
	if e.db == nil {
		return nil
	}
	var raw []byte
	row := e.db.WithContext(ctx).Raw(`
		UPDATE sale_image_extraction_cache
		   SET hit_count = hit_count + 1, last_hit_at = NOW()
		 WHERE image_sha256 = ? AND pipeline_version = ?
		 RETURNING result_jsonb
	`, sha, SheetGridPipelineVersion).Row()
	if err := row.Scan(&raw); err != nil {
		return nil
	}
	var c CachedExtraction
	if err := json.Unmarshal(raw, &c); err != nil {
		return nil
	}
	return &c
}

// saveToCache persists an extraction; ignores duplicate-key (concurrent writers).
func (e *SaleSheetExtractor) saveToCache(ctx context.Context, sha string, c CachedExtraction, sheetRaw []byte) {
	if e.db == nil {
		return
	}
	body, _ := json.Marshal(c)
	e.db.WithContext(ctx).Exec(`
		INSERT INTO sale_image_extraction_cache (image_sha256, pipeline_version, result_jsonb, cv_sheet_jsonb)
		VALUES (?, ?, ?::jsonb, ?::jsonb)
		ON CONFLICT (image_sha256, pipeline_version) DO NOTHING
	`, sha, SheetGridPipelineVersion, string(body), string(sheetRaw))
}

// imageHash returns the lowercase hex SHA-256 of the image bytes.
func imageHash(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

// fetchSheetFromCV calls the cv-sidecar /sheet endpoint and parses the JSON.
func (e *SaleSheetExtractor) fetchSheetFromCV(ctx context.Context, imgBytes []byte) (*SheetResponse, error) {
	if e.cvSidecar == nil || !e.cvSidecar.enabled {
		return nil, fmt.Errorf("cv sidecar not enabled")
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "register.jpg")
	if err != nil {
		return nil, err
	}
	if _, err := part.Write(imgBytes); err != nil {
		return nil, err
	}
	w.Close()
	req, err := http.NewRequestWithContext(ctx, "POST", e.cvSidecar.url+"/sheet", body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := e.cvSidecar.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		raw, _ := io.ReadAll(io.LimitReader(resp.Body, 400))
		return nil, fmt.Errorf("cv /sheet non-200 (%d): %s", resp.StatusCode, string(raw))
	}
	var out SheetResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("cv /sheet decode: %w", err)
	}
	if !out.OK {
		return nil, fmt.Errorf("cv /sheet returned ok=false (rows=%d, cols=%d)",
			out.RowCount, out.ColCount)
	}
	return &out, nil
}

// LoadShopPrintedBrandList returns the shop's inventory in the same order
// the printed register PDF generates: MRP ASC, name ASC, restricted to the
// requested size and beer/non-beer category. Used to bind brand by row index.
//
// We INCLUDE products with stock_qty == 0 because the printed register the
// salesman scanned may have been generated weeks ago when those products
// had stock. The "skip rows with zero stock" rule from the user applies at
// EXTRACTION time per-row (we don't ask AI to read empty rows), not at
// brand-list-build time.
func LoadShopPrintedBrandList(db *gorm.DB, tenantID, shopID uuid.UUID, sizeML int, category string) ([]PrintedBrand, error) {
	type row struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		Name      string    `gorm:"column:name"`
		MRP       float64   `gorm:"column:mrp"`
		StockQty  int       `gorm:"column:stock_qty"`
	}
	var rows []row
	sizePattern := fmt.Sprintf("%dML", sizeML)
	q := db.Raw(`
		SELECT p.id AS product_id,
		       p.name,
		       COALESCE(p.mrp, p.selling_price, 0) AS mrp,
		       COALESCE(st.quantity, 0) AS stock_qty
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN stocks st ON st.product_id = p.id AND st.shop_id = ? AND st.deleted_at IS NULL
		WHERE p.tenant_id = ?
		  AND p.deleted_at IS NULL
		  AND UPPER(p.size) = ?
		  AND (
		    (? = 'beer'     AND LOWER(COALESCE(c.name,'')) IN ('beer','lager','ale','rtd'))
		    OR
		    (? = 'non_beer' AND LOWER(COALESCE(c.name,'')) NOT IN ('beer','lager','ale','rtd'))
		    OR
		    (? = '')
		  )
		ORDER BY COALESCE(p.mrp, p.selling_price, 0) ASC, p.name ASC
	`, shopID, tenantID, sizePattern, category, category, category)
	if err := q.Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("load printed brand list: %w", err)
	}
	out := make([]PrintedBrand, 0, len(rows))
	for _, r := range rows {
		out = append(out, PrintedBrand{
			ProductID: r.ProductID,
			BrandName: r.Name,
			MRP:       r.MRP,
			StockQty:  r.StockQty,
		})
	}
	return out, nil
}

// normalizeBrandText lower-cases, strips punctuation, collapses whitespace.
func normalizeBrandText(s string) string {
	out := strings.Builder{}
	for _, r := range strings.ToLower(s) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			out.WriteRune(r)
		case r == ' ' || r == '\t' || r == '-' || r == '_' || r == '.' || r == ',' || r == '/' || r == '\\' || r == '\'' || r == '`' || r == '"':
			out.WriteByte(' ')
		}
	}
	// collapse spaces
	parts := strings.Fields(out.String())
	return strings.Join(parts, " ")
}

// tokenSet returns the set of word tokens in normalized form.
func tokenSet(s string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, t := range strings.Fields(normalizeBrandText(s)) {
		out[t] = struct{}{}
	}
	return out
}

// jaccard computes |A ∩ B| / |A ∪ B|.
func jaccard(a, b map[string]struct{}) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	inter := 0
	for k := range a {
		if _, ok := b[k]; ok {
			inter++
		}
	}
	union := len(a) + len(b) - inter
	if union == 0 {
		return 0
	}
	return float64(inter) / float64(union)
}

// matchPrintedBrand returns the best printed-list match for a brand text
// read from the image, or nil if no candidate scores above the floor.
// Floor is adaptive: 0.45 for normal printed text, 0.30 for short
// handwritten abbreviations (e.g. "M.M" → "M2 Magic Moments Pink").
// Used to align CV row → product_id without trusting MRP-sort assumptions.
func matchPrintedBrand(text string, printed []PrintedBrand) *PrintedBrand {
	if text == "" || len(printed) == 0 {
		return nil
	}
	normText := normalizeBrandText(text)
	textSet := tokenSet(text)
	if len(textSet) == 0 {
		return nil
	}
	floor := 0.45
	// Short abbreviation (≤6 chars after normalization) → relax floor and
	// also try substring containment for cases like "smirn" inside
	// "smirnoff orange triple distilled".
	if len(normText) <= 6 {
		floor = 0.30
	}
	best := -1
	bestScore := floor
	for i := range printed {
		pn := normalizeBrandText(printed[i].BrandName)
		score := jaccard(textSet, tokenSet(printed[i].BrandName))
		// Substring boost: short OCR text contained in a printed brand
		// is a strong signal (e.g. "smirn" in "smirnoff").
		if len(normText) >= 3 && len(normText) <= 8 && strings.Contains(pn, normText) {
			score += 0.25
		}
		if score > bestScore {
			bestScore = score
			best = i
		}
	}
	if best < 0 {
		return nil
	}
	return &printed[best]
}

// reconcileSale runs the math gate over the AI's read of (open, sale, close, total).
// Returns (final_qty, source_label, confidence, warnings).
//
// CRITICAL DESIGN — derived from real-world data on c8fc33fa:
// The AI's direct Sale read is the MOST RELIABLE single signal because (a)
// the Sale column is what the salesman wrote with the most care (it's
// what they're paid on), and (b) Open/Close cells often have larger 2-3
// digit numbers more prone to misread. So we use math as VERIFICATION
// (boost confidence when it agrees) but NEVER as override.
//
// Strategy:
//
//	1. If sale present + open and close also present + math holds (±1) → conf 0.99 (gold standard).
//	2. If sale present + math doesn't hold OR no anchor → keep sale, conf 0.85, warn.
//	3. If sale ABSENT but open+close present → derive sale = open-close, conf 0.93.
//	4. If sale ABSENT but total+close present → derive sale = total-close, conf 0.90.
//	5. Empty everywhere → 0, conf 1.0.
//
// This way a misread of open or close NEVER corrupts a correct sale read.
func reconcileSale(rd SaleRowRead) (int, string, float64, []string) {
	warns := []string{}
	get := func(p *int) (int, bool) {
		if p == nil {
			return 0, false
		}
		return *p, true
	}
	sale, hasSale := get(rd.SaleQty)
	open, hasOpen := get(rd.OpenQty)
	close_, hasClose := get(rd.CloseQty)
	total, hasTotal := get(rd.TotalQty)

	abs := func(x int) int {
		if x < 0 {
			return -x
		}
		return x
	}
	cap_ := func(q int) (int, bool) {
		if q < 0 || q > 200 {
			return 0, false
		}
		return q, true
	}

	// Path 1+2: AI gave us a Sale read. Trust it. Math is verification only.
	if hasSale {
		v, ok := cap_(sale)
		if !ok {
			warns = append(warns, fmt.Sprintf("ai_sale_out_of_range:%d", sale))
			// fall through to derive paths
		} else {
			// Verify with open-close.
			if hasOpen && hasClose {
				expected := open - close_
				if abs(expected-v) <= 1 {
					return v, "ai-sale+math-confirmed", 0.99, warns
				}
				if hasTotal {
					expectedT := total - close_
					if abs(expectedT-v) <= 1 {
						return v, "ai-sale+total-confirmed", 0.97, warns
					}
				}
				// v1.0.153 — when the math is internally impossible (close > open
				// without a stock receipt — which sheet-grid doesn't model), the
				// closing-stock cell was misread, not the sale qty. Trust AI's
				// sale value at higher confidence and tag the closing as the
				// suspect cell so review UI guides the operator to it. Avoids
				// the "every math-disagree row is full needs_review" pattern
				// that buried chhotu's 30-Apr 375ml in 29/29 flagged items.
				if expected < 0 {
					warns = append(warns, fmt.Sprintf("close_misread_suspected:ai_sale=%d open(%d)-close(%d)", v, open, close_))
					return v, "ai-sale-close-suspect", 0.85, warns
				}
				warns = append(warns, fmt.Sprintf("math_disagree:ai_sale=%d open(%d)-close(%d)=%d", v, open, close_, expected))
				return v, "ai-sale-math-disagree", 0.78, warns
			}
			if hasTotal && hasClose {
				expectedT := total - close_
				if abs(expectedT-v) <= 1 {
					return v, "ai-sale+total-confirmed", 0.96, warns
				}
				warns = append(warns, fmt.Sprintf("total_disagree:ai_sale=%d total(%d)-close(%d)=%d", v, total, close_, expectedT))
				return v, "ai-sale-total-disagree", 0.78, warns
			}
			// v1.0.141 — anti-hallucination guard: when AI gives us a sale
			// number with NO math anchor (open or close missing/unreadable),
			// the value is effectively unverified. Empirically (FM Tower
			// 750ml job 9435754d) this path produced 4 phantom sales out
			// of 5 firings ("Jack Daniels qty=2", "Brand Name qty=16",
			// etc.) because AI was reading bleed-through ink or simply
			// inventing values. Refuse the row and let the operator add
			// it manually if it's actually a sale.
			warns = append(warns, "no_math_anchor_dropped")
			return 0, "no-math-anchor-dropped", 0.0, warns
		}
	}
	// v1.0.141 — small-sale recovery RESTORED (tightened range [1-3] only).
	// Killing it entirely lost the Sterling B7 sale=1 capture without
	// fixing the Old Monk qty=3 phantom (AI reads close=24 vs truth=27 →
	// the close cell is genuinely a digit-recognition cliff case, NOT
	// solvable by guard tightening). Net-neutral, so keep the guard
	// since it does help recover ~1 row per page on average.
	if hasOpen && hasClose && open >= 5 && close_ >= 5 {
		expected := open - close_
		if expected >= 1 && expected <= 3 {
			warns = append(warns, fmt.Sprintf("derived_from_open_close:%d-%d=%d (small-sale recovery)", open, close_, expected))
			return expected, "open-close-small-sale", 0.78, warns
		}
	}
	if hasTotal && hasClose && total >= 5 && close_ >= 5 {
		expected := total - close_
		if expected >= 1 && expected <= 3 {
			warns = append(warns, fmt.Sprintf("derived_from_total_close:%d-%d=%d (small-sale recovery)", total, close_, expected))
			return expected, "total-close-small-sale", 0.76, warns
		}
	}
	return 0, "blank", 1.0, warns
}

// isLikelyGrandTotalText catches the printed footer brand-cell content
// (variants of "Grand Total" / "Total" / blank-with-numbers-only).
func isLikelyGrandTotalText(s string) bool {
	n := normalizeBrandText(s)
	if n == "" {
		return false
	}
	for _, m := range []string{"grand total", "grand totale", "totalsale", "totalsales", "total sale", "total sales"} {
		if n == m || strings.Contains(n, "grand total") {
			return true
		}
	}
	return false
}

// isLikelyHeaderRowText catches the column-header strip ("S.N | Brand Name
// | Openin | Receipt | Total | Sale | Rate | Amount | Closin") that
// sometimes leaks into CV's row detection on multi-page registers where
// page 2 starts with a header band.
func isLikelyHeaderRowText(s string) bool {
	n := normalizeBrandText(s)
	if n == "" {
		return false
	}
	for _, h := range []string{"brand name", "brand", "s n brand", "openin receipt"} {
		if n == h || (len(n) <= 12 && strings.Contains(n, h)) {
			return true
		}
	}
	return false
}

// dataRowCellsByCol indexes the sheet's cells by (row_idx, col_name) for fast lookup.
func indexCells(cells []SheetCell) map[int]map[string]SheetCell {
	out := make(map[int]map[string]SheetCell, 64)
	for _, c := range cells {
		if out[c.RowIdx] == nil {
			out[c.RowIdx] = map[string]SheetCell{}
		}
		out[c.RowIdx][c.ColName] = c
	}
	return out
}

// inferDataRows returns row indices that look like data rows (not header,
// not grand-total).
//
//	- skip the first row (header: S.No / Brand Name / Open / ...)
//	- any row whose Sale cell has writing OR Open cell has writing is
//	  a candidate. Rows entirely blank in numeric columns are skipped.
//	- v1.0.138-r3 — drop the GRAND TOTAL footer: signature is
//	  brand_cell.ink_ratio < 0.04 (effectively blank — printed footer
//	  spans columns under the brand) AND >= 2 numeric cells with writing,
//	  AND the row is in the bottom 25% of the page.
func inferDataRows(rows []SheetRow, byRow map[int]map[string]SheetCell) []int {
	if len(rows) == 0 {
		return nil
	}
	maxIdx := 0
	for _, r := range rows {
		if r.Idx > maxIdx {
			maxIdx = r.Idx
		}
	}
	bottomCutoff := maxIdx - (maxIdx / 4)
	out := make([]int, 0, len(rows))
	for i, r := range rows {
		if i == 0 {
			continue // header
		}
		cells := byRow[r.Idx]
		if cells == nil {
			continue
		}
		// Grand-total signature.
		brandCell, hasBrand := cells["brand"]
		numericCount := 0
		for _, col := range []string{"open", "sale", "amount", "closing", "total"} {
			if c, ok := cells[col]; ok && c.HasWriting {
				numericCount++
			}
		}
		if r.Idx >= bottomCutoff && hasBrand && brandCell.InkRatio < 0.04 && numericCount >= 2 {
			// Looks like grand-total footer — skip silently.
			continue
		}
		anyDataInk := false
		for _, col := range []string{"open", "sale", "amount", "closing"} {
			if c, ok := cells[col]; ok && c.HasWriting {
				anyDataInk = true
				break
			}
		}
		if anyDataInk {
			out = append(out, r.Idx)
			continue
		}
		if hasBrand && brandCell.HasWriting {
			out = append(out, r.Idx)
		}
	}
	return out
}

// cropCellPNG extracts a single cell's pixel rectangle from the source image
// and JPEG-encodes it. Used to attach individual cell crops to the AI prompt.
func cropCellJPEG(src image.Image, cell SheetCell, padding int) ([]byte, error) {
	b := src.Bounds()
	x0 := cell.XLeft - padding
	y0 := cell.YTop - padding
	x1 := cell.XRight + padding
	y1 := cell.YBot + padding
	if x0 < b.Min.X {
		x0 = b.Min.X
	}
	if y0 < b.Min.Y {
		y0 = b.Min.Y
	}
	if x1 > b.Max.X {
		x1 = b.Max.X
	}
	if y1 > b.Max.Y {
		y1 = b.Max.Y
	}
	if x1-x0 < 4 || y1-y0 < 4 {
		return nil, fmt.Errorf("cell crop too small: %dx%d", x1-x0, y1-y0)
	}
	type subImager interface {
		SubImage(image.Rectangle) image.Image
	}
	si, ok := src.(subImager)
	if !ok {
		return nil, fmt.Errorf("source image does not support SubImage")
	}
	sub := si.SubImage(image.Rect(x0, y0, x1, y1))
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, sub, &jpeg.Options{Quality: 92}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// SaleRowRead — one row as read by the AI in a single batched call.
// We read 4 cells per row so the math gate (open−close=sale, total−close=sale)
// can self-correct digit misreads without ANY additional API spend.
type SaleRowRead struct {
	BrandText string  `json:"brand_text"`
	OpenQty   *int    `json:"-"`
	SaleQty   *int    `json:"-"`
	CloseQty  *int    `json:"-"`
	TotalQty  *int    `json:"-"`
	// Raw inbound values so UnmarshalJSON can tolerate strings like "Closing"
	// or stray words the AI sometimes puts in numeric cells. v1.0.154-r3 —
	// without this guard a single `"close_qty": "Closing"` from Anthropic
	// crashes decode for the ENTIRE page batch (chhotu's 30-Apr 375ml p2).
	RawOpenQty  any `json:"open_qty"`
	RawSaleQty  any `json:"sale_qty"`
	RawCloseQty any `json:"close_qty"`
	RawTotalQty any `json:"total_qty,omitempty"`
}

// coerceQty turns Anthropic's any-typed value into *int. Accepts: int, float64
// (json.Number), nil. Rejects strings (non-empty), bools, arrays, maps —
// returns nil. v1.0.154-r3 — the model occasionally responds with the column
// header text ("Closing", "—", "*") in numeric fields when a cell is unclear.
// Permissive decode keeps the rest of the page extractable.
func coerceQty(v any) *int {
	if v == nil {
		return nil
	}
	switch t := v.(type) {
	case float64:
		i := int(t)
		return &i
	case int:
		i := t
		return &i
	case json.Number:
		if i64, err := t.Int64(); err == nil {
			i := int(i64)
			return &i
		}
		if f, err := t.Float64(); err == nil {
			i := int(f)
			return &i
		}
	}
	return nil
}

// finalizeQtys runs after json.Unmarshal to populate the typed *int fields
// from the raw any values.
func (r *SaleRowRead) finalizeQtys() {
	r.OpenQty = coerceQty(r.RawOpenQty)
	r.SaleQty = coerceQty(r.RawSaleQty)
	r.CloseQty = coerceQty(r.RawCloseQty)
	r.TotalQty = coerceQty(r.RawTotalQty)
}

// cropCellJPEGPadded — like cropCellJPEG but with explicit horizontal /
// vertical padding factors of the cell width/height (e.g. 0.20 = +20% on
// each side). Wider crops keep leading digits intact when handwriting
// overflows the column rule.
func cropCellJPEGPadded(src image.Image, cell SheetCell, padXFrac, padYFrac float64) ([]byte, error) {
	w := cell.XRight - cell.XLeft
	h := cell.YBot - cell.YTop
	padX := int(float64(w)*padXFrac + 0.5)
	padY := int(float64(h)*padYFrac + 0.5)
	if padX < 2 {
		padX = 2
	}
	if padY < 2 {
		padY = 2
	}
	c2 := cell
	c2.XLeft -= padX
	c2.XRight += padX
	c2.YTop -= padY
	c2.YBot += padY
	return cropCellJPEG(src, c2, 0)
}

// readSaleAndBrandBatched — single Anthropic call per page. For each CV row
// with writing, sends 4 cell crops (Brand printed + Open handwritten +
// Sale handwritten + Close handwritten) plus Total when present. Returns
// per-row {brand_text, open, sale, close, total}. The math gate downstream
// uses open−close=sale and total−close=sale to self-verify digit reads.
func (e *SaleSheetExtractor) readSaleAndBrandBatched(
	ctx context.Context,
	srcImg image.Image,
	rows []SheetRow,
	byRow map[int]map[string]SheetCell,
	pageIdx int,
	printedRowCount int, // v1.0.139: rows 1..printedRowCount get NO brand crop (brand from row-index lookup)
	paddleBrands map[int]BrandRead, // v1.0.157 Phase 2: skip brand crop on rows where Paddle is high-conf
) (map[int]SaleRowRead, float64, error) {
	if e.claudeAPIKey == "" {
		return nil, 0, fmt.Errorf("ANTHROPIC_API_KEY not set")
	}
	type contentBlock map[string]any
	contents := []contentBlock{}
	rowOrder := []int{}
	addonRows := []int{} // 1-based positions in rowOrder that NEED brand text in the response
	addCrop := func(name string, c SheetCell, padX float64) {
		crop, err := cropCellJPEGPadded(srcImg, c, padX, 0.10)
		if err != nil {
			return
		}
		contents = append(contents, contentBlock{"type": "text", "text": name + ":"})
		contents = append(contents, contentBlock{"type": "image",
			"source": map[string]any{"type": "base64", "media_type": "image/jpeg",
				"data": base64.StdEncoding.EncodeToString(crop)}})
	}
	for _, r := range rows {
		cells := byRow[r.Idx]
		if cells == nil {
			continue
		}
		saleCell, hasSale := cells["sale"]
		brandCell, hasBrand := cells["brand"]
		openCell, hasOpen := cells["open"]
		closeCell, hasClose := cells["closing"]
		// v1.0.154-r2 — broader signal gate REVERTED. Tightening only the
		// dedup path proved to be the win; broadening anySignal sent rows
		// to AI that AI then dropped at the math gate, NET reducing real
		// extraction (8/30 vs 11/30 on chhotu's 30-Apr p1). Keep the
		// stricter pre-filter; let CV's has_writing flag decide which rows
		// are worth Anthropic spend.
		anySignal := (hasSale && saleCell.HasWriting) ||
			(hasOpen && openCell.HasWriting && hasClose && closeCell.HasWriting)
		if !anySignal {
			continue
		}
		if !hasBrand {
			continue
		}
		// v1.0.139-r2: brand-skip optimization REVERTED — printed register
		// row ordering doesn't reliably match DB MRP-sort (header rows
		// shift indices, deactivated inventory leaves gaps), so position-
		// based brand binding lost 60% accuracy. Keep brand reading via AI
		// — it's what makes the alias+fuzzy matcher work.
		_ = printedRowCount
		_ = addonRows
		// v1.0.157 Phase 2 — skip brand crop when PaddleOCR already read the
		// brand at high confidence. Pre-fills happen post-call from the same
		// map. Saves ~30-40% input tokens for those rows since the brand cell
		// is the widest column. Sonnet is told `brand_text=null` for these
		// rows so it doesn't try to read what wasn't sent.
		_, hasPaddle := paddleBrands[r.Idx]
		contents = append(contents, contentBlock{"type": "text",
			"text": fmt.Sprintf("--- Row #%d ---", len(rowOrder)+1)})
		if !hasPaddle {
			addCrop("Brand", brandCell, 0.05)
		}
		if hasOpen {
			addCrop("Open", openCell, 0.25)
		}
		if hasSale {
			addCrop("Sale", saleCell, 0.25)
		}
		if hasClose {
			addCrop("Close", closeCell, 0.25)
		}
		// Total cell intentionally dropped: nearly always blank in real
		// shop registers; Open-Sale=Close math identity already covers it.
		// Saves ~3-5% input tokens per row with no accuracy impact.
		rowOrder = append(rowOrder, r.Idx)
		if hasPaddle {
			addonRows = append(addonRows, len(rowOrder)) // 1-based: rows where brand_text was NOT in the crop set
		}
	}
	if len(rowOrder) == 0 {
		return map[int]SaleRowRead{}, 0, nil
	}
	// v1.0.157 Phase 2 — when PaddleOCR already read the brand at high
	// confidence, the brand crop is omitted from those rows entirely.
	// Sonnet should return brand_text=null for those rows (we'll fill
	// from Paddle post-call). The list of "no-brand-crop" row indices is
	// included verbatim in the prompt.
	noBrandList := ""
	if len(addonRows) > 0 {
		parts := make([]string, 0, len(addonRows))
		for _, n := range addonRows {
			parts = append(parts, strconv.Itoa(n))
		}
		noBrandList = strings.Join(parts, ", ")
	}
	prompt := strings.Join([]string{
		"Above are " + strconv.Itoa(len(rowOrder)) + " row blocks from a daily-sales register.",
		"Most blocks have a Brand cell (machine-printed brand name OR handwritten add-on),",
		"and the handwritten Open / Sale / Close cells.",
		"",
		"Return ONLY this JSON, no prose, no markdown fences:",
		"{ \"rows\": [{\"brand_text\":\"...\", \"open_qty\":<int|null>, \"sale_qty\":<int|null>, \"close_qty\":<int|null>}, ...] }",
		"",
		"Rules:",
		"- The 'rows' array MUST have exactly " + strconv.Itoa(len(rowOrder)) + " entries in the order shown.",
		"- For rows that include a Brand crop, 'brand_text' is the FULL brand name (printed text OR handwritten add-on like 'M.M', '100 St', 'Sirsoun').",
		"- For rows where no Brand crop was provided, return brand_text=null (do not invent).",
		(func() string {
			if noBrandList == "" {
				return ""
			}
			return "- These row numbers (1-based) have NO brand crop — return brand_text=null for them: " + noBrandList + "."
		})(),
		"- All quantity fields: integer when clearly written; '-' or blank or unreadable → null.",
		"- Read every digit. A '30' is two digits, never just '0'. A '19' is two digits, never just '9'.",
		"  Look at the FULL crop width before answering — leading digits often sit close to the column rule.",
		"- The math identity is: open_qty − sale_qty = close_qty.  Use it as a self-check.",
		"  If your read of (open, sale, close) doesn't satisfy that within ±2, lower confidence by returning null on the LEAST clearly-written cell rather than guessing.",
		"- If a row appears to be the GRAND TOTAL footer, return brand_text='__GRAND_TOTAL__' and qty fields null.",
		"- Sales >200 in a single cell are extremely rare; if you read >200, return null.",
	}, "\n")
	contents = append(contents, contentBlock{
		"type": "text", "text": prompt,
		// Anthropic prompt-cache breakpoint: the trailing instruction prompt
		// is identical across all pages within an eval run AND across runs.
		// Caching it for 5 minutes saves ~70-90% of input-token cost on
		// repeat calls within the cache window (cv-sidecar tail latency
		// + page-2 of multi-page jobs).
		"cache_control": map[string]any{"type": "ephemeral"},
	})

	body := map[string]any{
		"model":      "claude-sonnet-4-6",
		"max_tokens": 2400,
		"messages":   []map[string]any{{"role": "user", "content": contents}},
	}
	bodyJSON, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, "POST",
		"https://api.anthropic.com/v1/messages", bytes.NewReader(bodyJSON))
	req.Header.Set("x-api-key", e.claudeAPIKey)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("content-type", "application/json")
	resp, err := e.httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("anthropic /messages %d: %s", resp.StatusCode, string(raw))
	}
	var apiResp struct {
		Content []struct{ Text string } `json:"content"`
		Usage   struct {
			InputTokens              int `json:"input_tokens"`
			OutputTokens             int `json:"output_tokens"`
			CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
			CacheReadInputTokens     int `json:"cache_read_input_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(raw, &apiResp); err != nil {
		return nil, 0, err
	}
	if len(apiResp.Content) == 0 {
		return nil, 0, fmt.Errorf("anthropic empty content")
	}
	text := strings.TrimSpace(apiResp.Content[0].Text)
	// Robust JSON extraction: find the first '{' and the matching closing '}'.
	// Tolerates "Here is the JSON:" prose prefixes and ```json fences.
	jsonStart := strings.Index(text, "{")
	jsonEnd := strings.LastIndex(text, "}")
	if jsonStart < 0 || jsonEnd <= jsonStart {
		return nil, 0, fmt.Errorf("no JSON object in response: %s", text)
	}
	text = text[jsonStart : jsonEnd+1]
	var parsed struct {
		Rows []SaleRowRead `json:"rows"`
	}
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		return nil, 0, fmt.Errorf("decode rows json (%s): %w", text, err)
	}
	if len(parsed.Rows) != len(rowOrder) {
		return nil, 0, fmt.Errorf("row count mismatch: got %d expected %d", len(parsed.Rows), len(rowOrder))
	}
	out := make(map[int]SaleRowRead, len(rowOrder))
	for i, ri := range rowOrder {
		out[ri] = parsed.Rows[i]
	}
	// v1.0.154 — duplicate-brand-text rejection. The chhotu 30-Apr 375ml job
	// returned the same brand_text ("Sov 1965 XXX Rum") for 4 distinct row
	// crops, cascading into duplicate product matches downstream. When the
	// same brand_text appears on N>1 rows of a single page, keep ONLY the
	// row with the strongest signal (lowest math residual when open+sale+
	// close are all present; otherwise the earliest row); blank the brand
	// on the others so they fall through to row-index/printed mapping or
	// the legacy fallback. Empty brand_text and __GRAND_TOTAL__ are
	// excluded from the dedup count.
	type sig struct {
		ri          int
		residualAbs int
		hasMath     bool
	}
	bucket := map[string][]sig{}
	for ri, rd := range out {
		bt := strings.ToLower(strings.TrimSpace(rd.BrandText))
		if bt == "" || bt == "__grand_total__" {
			continue
		}
		s := sig{ri: ri}
		if rd.OpenQty != nil && rd.SaleQty != nil && rd.CloseQty != nil {
			s.hasMath = true
			r := *rd.OpenQty - *rd.SaleQty - *rd.CloseQty
			if r < 0 {
				r = -r
			}
			s.residualAbs = r
		} else {
			s.residualAbs = 99
		}
		bucket[bt] = append(bucket[bt], s)
	}
	for bt, sigs := range bucket {
		if len(sigs) < 2 {
			continue
		}
		// Pick winner: prefer hasMath && lowest residual; tiebreak by lowest ri.
		winner := sigs[0]
		for _, s := range sigs[1:] {
			if s.hasMath != winner.hasMath {
				if s.hasMath {
					winner = s
				}
				continue
			}
			if s.residualAbs < winner.residualAbs ||
				(s.residualAbs == winner.residualAbs && s.ri < winner.ri) {
				winner = s
			}
		}
		for _, s := range sigs {
			if s.ri == winner.ri {
				continue
			}
			rd := out[s.ri]
			rd.BrandText = ""
			out[s.ri] = rd
			e.logger.Infof("sheet-grid: dedup'd brand_text=%q on row=%d (winner row=%d residual=%d)", bt, s.ri, winner.ri, winner.residualAbs)
		}
	}
	// Anthropic pricing for Sonnet 4.6 (per 1M tokens, USD):
	//   input:                $3.00
	//   cache write (5min):   $3.75 (25% premium)
	//   cache read:           $0.30 (90% discount)
	//   output:               $15.00
	in := apiResp.Usage.InputTokens
	cw := apiResp.Usage.CacheCreationInputTokens
	cr := apiResp.Usage.CacheReadInputTokens
	costUSD := float64(in)*3e-6 + float64(cw)*3.75e-6 + float64(cr)*0.3e-6 + float64(apiResp.Usage.OutputTokens)*15e-6
	costINR := costUSD * 83.0
	cacheNote := ""
	if cw > 0 || cr > 0 {
		cacheNote = fmt.Sprintf(" cache_write=%d cache_read=%d", cw, cr)
	}
	e.logger.Infof("sheet-grid page=%d: batched %d rows, in=%d out=%d%s cost=₹%.3f",
		pageIdx, len(rowOrder), in, apiResp.Usage.OutputTokens, cacheNote, costINR)
	return out, costINR, nil
}

// readSaleDigitsBatched (legacy, kept for cache-shape compat) — see readSaleAndBrandBatched.
func (e *SaleSheetExtractor) readSaleDigitsBatched(
	ctx context.Context,
	srcImg image.Image,
	saleCells []SheetCell,
	pageIdx int,
) (map[int]*int, float64, error) {
	if len(saleCells) == 0 {
		return map[int]*int{}, 0, nil
	}
	if e.claudeAPIKey == "" {
		return nil, 0, fmt.Errorf("ANTHROPIC_API_KEY not set")
	}
	type contentBlock map[string]any
	contents := []contentBlock{}
	rowOrder := []int{}
	for _, c := range saleCells {
		if !c.HasWriting {
			continue
		}
		crop, err := cropCellJPEG(srcImg, c, 4)
		if err != nil {
			e.logger.Warnf("sheet-grid: cell crop failed row=%d: %v", c.RowIdx, err)
			continue
		}
		contents = append(contents, contentBlock{"type": "text", "text": fmt.Sprintf("Cell #%d (printed row %d):", len(rowOrder)+1, c.RowIdx)})
		contents = append(contents, contentBlock{
			"type": "image",
			"source": map[string]any{
				"type":       "base64",
				"media_type": "image/jpeg",
				"data":       base64.StdEncoding.EncodeToString(crop),
			},
		})
		rowOrder = append(rowOrder, c.RowIdx)
	}
	if len(rowOrder) == 0 {
		return map[int]*int{}, 0, nil
	}

	prompt := strings.Join([]string{
		"Each image above is one cell crop from the SALE QUANTITY column of a daily-sales register.",
		"Each cell contains either:",
		"  • a handwritten integer (1-3 digits, typically 1-99 for daily sales of a single SKU), OR",
		"  • a dash '-' meaning no sale (return null), OR",
		"  • a blank cell (return null)",
		"",
		"Return ONLY this JSON, no prose, no markdown fences:",
		"{ \"values\": [<integer or null>, <integer or null>, ...] }",
		"",
		"Rules:",
		"- The array MUST have exactly " + strconv.Itoa(len(rowOrder)) + " entries, one per cell in the order shown.",
		"- A clearly written digit → integer. A dash, blank, or unreadable mark → null.",
		"- Sales >200 in a single cell are extremely rare; if you read >200, return null and let the math gate decide.",
		"- Be confident on legible digits. Do NOT invent values to be helpful.",
	}, "\n")
	contents = append(contents, contentBlock{"type": "text", "text": prompt})

	body := map[string]any{
		"model":      "claude-sonnet-4-6",
		"max_tokens": 800,
		"messages":   []map[string]any{{"role": "user", "content": contents}},
	}
	bodyJSON, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, "POST",
		"https://api.anthropic.com/v1/messages", bytes.NewReader(bodyJSON))
	req.Header.Set("x-api-key", e.claudeAPIKey)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("content-type", "application/json")
	resp, err := e.httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("anthropic /messages %d: %s", resp.StatusCode, string(raw))
	}
	var apiResp struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
		Usage struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(raw, &apiResp); err != nil {
		return nil, 0, err
	}
	if len(apiResp.Content) == 0 {
		return nil, 0, fmt.Errorf("anthropic empty content")
	}
	text := apiResp.Content[0].Text
	// Strip any accidental ```json fences
	text = strings.TrimSpace(text)
	if strings.HasPrefix(text, "```") {
		// remove first line + trailing fence
		lines := strings.SplitN(text, "\n", 2)
		if len(lines) == 2 {
			text = strings.TrimSuffix(strings.TrimSpace(lines[1]), "```")
		}
	}
	var parsed struct {
		Values []*int `json:"values"`
	}
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		return nil, 0, fmt.Errorf("decode digits json (%s): %w", text, err)
	}
	if len(parsed.Values) != len(rowOrder) {
		return nil, 0, fmt.Errorf("digit count mismatch: got %d expected %d", len(parsed.Values), len(rowOrder))
	}
	out := make(map[int]*int, len(rowOrder))
	for i, ri := range rowOrder {
		out[ri] = parsed.Values[i]
	}
	// Cost estimate: Sonnet 4.6 input ~$3/Mtok, output ~$15/Mtok. INR ~83/USD.
	costUSD := float64(apiResp.Usage.InputTokens)*3e-6 + float64(apiResp.Usage.OutputTokens)*15e-6
	costINR := costUSD * 83.0
	e.logger.Infof("sheet-grid page=%d: batched %d sale cells, in_tok=%d out_tok=%d cost=₹%.3f",
		pageIdx, len(rowOrder), apiResp.Usage.InputTokens, apiResp.Usage.OutputTokens, costINR)
	return out, costINR, nil
}

// readNumberCell is the option-C retry: when the math gate fails for a row,
// re-read just that one cell. Used for any single column (open/sale/closing).
// Returns nil if the model can't read it confidently.
func (e *SaleSheetExtractor) readNumberCell(ctx context.Context, srcImg image.Image, cell SheetCell, label string) (*int, float64, error) {
	if e.claudeAPIKey == "" {
		return nil, 0, fmt.Errorf("ANTHROPIC_API_KEY not set")
	}
	crop, err := cropCellJPEG(srcImg, cell, 6)
	if err != nil {
		return nil, 0, err
	}
	prompt := fmt.Sprintf(
		"This image is a single %s cell from a daily-sales register. "+
			"It contains either a handwritten integer (typically 0-200), "+
			"a dash '-', or is blank. Return ONLY this JSON: "+
			"{ \"value\": <integer or null> }. "+
			"Dash or blank → null. Be confident on legible digits.", label)
	body := map[string]any{
		"model":      "claude-opus-4-7",
		"max_tokens": 100,
		"messages": []map[string]any{{
			"role": "user",
			"content": []map[string]any{
				{"type": "image", "source": map[string]any{
					"type":       "base64",
					"media_type": "image/jpeg",
					"data":       base64.StdEncoding.EncodeToString(crop),
				}},
				{"type": "text", "text": prompt},
			},
		}},
	}
	bodyJSON, _ := json.Marshal(body)
	req, _ := http.NewRequestWithContext(ctx, "POST",
		"https://api.anthropic.com/v1/messages", bytes.NewReader(bodyJSON))
	req.Header.Set("x-api-key", e.claudeAPIKey)
	req.Header.Set("anthropic-version", "2023-06-01")
	req.Header.Set("content-type", "application/json")
	resp, err := e.httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, 0, fmt.Errorf("anthropic %d: %s", resp.StatusCode, string(raw))
	}
	var apiResp struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
		Usage struct {
			InputTokens  int `json:"input_tokens"`
			OutputTokens int `json:"output_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(raw, &apiResp); err != nil {
		return nil, 0, err
	}
	if len(apiResp.Content) == 0 {
		return nil, 0, fmt.Errorf("empty content")
	}
	text := strings.TrimSpace(apiResp.Content[0].Text)
	if strings.HasPrefix(text, "```") {
		lines := strings.SplitN(text, "\n", 2)
		if len(lines) == 2 {
			text = strings.TrimSuffix(strings.TrimSpace(lines[1]), "```")
		}
	}
	var parsed struct {
		Value *int `json:"value"`
	}
	if err := json.Unmarshal([]byte(text), &parsed); err != nil {
		return nil, 0, fmt.Errorf("decode (%s): %w", text, err)
	}
	// Opus pricing: in $15/Mtok, out $75/Mtok.
	costUSD := float64(apiResp.Usage.InputTokens)*15e-6 + float64(apiResp.Usage.OutputTokens)*75e-6
	return parsed.Value, costUSD * 83.0, nil
}

// bindByPrintedListPosition assigns brand_text on each row by position
// when the CV row count matches the printed-list count within ±2 (after
// header-row skipping). When `reads[i]` already has a high-confidence
// PaddleOCR brand text that token-jaccard-matches the position-bound
// printed brand by ≥0.4, we KEEP the read (it's confirmed). When
// disagreement is severe (jaccard <0.2), we OVERWRITE the read with
// the printed name — the text was probably mis-read.
//
// Catches the failure mode where row 1 was misread as "Blend" and row 4
// as "Tetra" when truth was the reverse — pure brand-cell misread.
//
// Header-row skip: if dataRowIdxs[0]'s Paddle text contains "SALE" or
// "STARTING STOCK" or matches /^[A-Z\s]+$/ and is short, offset by 1.
// Limit offset to 0..2.
func bindByPrintedListPosition(reads map[int]SaleRowRead, dataRowIdxs []int, printed []PrintedBrand, paddleBrands map[int]BrandRead) (overrides int) {
	if len(dataRowIdxs) == 0 || len(printed) == 0 {
		return 0
	}
	// Determine header-row offset (0..2). A row whose Paddle text is short
	// and looks like a column header ("SALE", "STARTING STOCK", or pure
	// upper-case) is treated as a header and skipped before alignment.
	isHeader := func(txt string) bool {
		t := strings.TrimSpace(txt)
		if t == "" {
			return false
		}
		upper := strings.ToUpper(t)
		if strings.Contains(upper, "SALE") || strings.Contains(upper, "STARTING STOCK") {
			return true
		}
		if len(t) > 24 {
			return false
		}
		// Pure [A-Z\s]+ check.
		allUpperOrSpace := true
		hasLetter := false
		for _, r := range t {
			switch {
			case r >= 'A' && r <= 'Z':
				hasLetter = true
			case r == ' ' || r == '\t':
				// allowed
			default:
				allUpperOrSpace = false
			}
		}
		return allUpperOrSpace && hasLetter
	}
	offset := 0
	for offset < 2 && offset < len(dataRowIdxs) {
		ri := dataRowIdxs[offset]
		pb, ok := paddleBrands[ri]
		if !ok || !isHeader(pb.BrandText) {
			break
		}
		offset++
	}

	dataRowsAfterSkip := len(dataRowIdxs) - offset
	// Count alignment guard: ±2 between effective CV data rows and printed list.
	diff := dataRowsAfterSkip - len(printed)
	if diff < 0 {
		diff = -diff
	}
	if diff > 2 {
		return 0
	}

	for i := offset; i < len(dataRowIdxs); i++ {
		k := i - offset
		if k >= len(printed) {
			break
		}
		ri := dataRowIdxs[i]
		printedName := printed[k].BrandName
		rd := reads[ri]
		existing := strings.TrimSpace(rd.BrandText)
		// No existing read → fill from printed list.
		if existing == "" {
			rd.BrandText = printedName
			reads[ri] = rd
			overrides++
			continue
		}
		// Decide based on token-jaccard between existing read and printed name.
		score := jaccard(tokenSet(existing), tokenSet(printedName))
		if score >= 0.4 {
			// Confirmed by Paddle/Sonnet read — keep it.
			continue
		}
		if score < 0.2 {
			// Severe disagreement → overwrite with printed name.
			rd.BrandText = printedName
			reads[ri] = rd
			overrides++
		}
		// 0.2 ≤ score < 0.4 → ambiguous, leave existing read alone.
	}
	return overrides
}

// ExtractPage is the entry point: image bytes → fully-resolved page rows.
// Idempotent + cache-aware: re-runs against the same image bytes pay $0.
// ExtractPage runs the v1.0.138 sheet-grid pipeline on a single image.
//
// v1.0.160 — accepts a `shopID` so the alias-resolved-brand step uses the
// shop-scoped lookup cascade. uuid.Nil falls back to tenant-wide alias
// matching (legacy behaviour). Backward-compat callers can use
// ExtractPageLegacy below.
func (e *SaleSheetExtractor) ExtractPage(
	ctx context.Context,
	imgBytes []byte,
	pageIdx int,
	printed []PrintedBrand,
	tenantID uuid.UUID,
	shopID uuid.UUID,
) (*SheetExtractionResult, error) {
	hash := imageHash(imgBytes)
	res := &SheetExtractionResult{
		PageIndex:   pageIdx,
		ImageSHA256: hash,
	}
	// Cache hit → zero AI cost. We still re-resolve printed brands per call
	// because brands are tenant-specific and may have changed since cache.
	if cached := e.loadFromCache(ctx, hash); cached != nil {
		e.logger.Infof("sheet-grid page=%d: CACHE HIT sha256=%s rows=%d", pageIdx, hash[:12], len(cached.Rows))
		res.Rows = cached.Rows
		res.CallsMade = 0
		res.CostINR = 0
		res.Warnings = append(res.Warnings, "cache_hit")
		// Re-bind brand_id from current printed list using row position.
		dataRows := []int{}
		for _, r := range res.Rows {
			dataRows = append(dataRows, r.RowIdx)
		}
		sort.Ints(dataRows)
		for i := range res.Rows {
			k := -1
			for idx, ri := range dataRows {
				if ri == res.Rows[i].RowIdx {
					k = idx
					break
				}
			}
			if k >= 0 && k < len(printed) {
				pid := printed[k].ProductID
				res.Rows[i].ProductID = &pid
				res.Rows[i].BrandName = printed[k].BrandName
				res.Rows[i].MRP = printed[k].MRP
			}
		}
		return res, nil
	}

	// v1.0.177 — passive page-quality telemetry. Logs blur/contrast/skew
	// metrics for every page so we can correlate accuracy vs image quality
	// on real traffic before flipping any hard quality gate. Best-effort —
	// nil on disabled / error / unreachable.
	if q := e.cvSidecar.QualityCheck(ctx, imgBytes); q != nil {
		if q.Advisory {
			e.logger.Warnf("sheet-grid page=%d: image-quality advisory issues=%v blur=%.1f contrast=%.1f bright=%.1f skew=%.1f°",
				pageIdx, q.Issues, q.Blur, q.Contrast, q.Brightness, q.SkewDeg)
			res.Warnings = append(res.Warnings, fmt.Sprintf("image_quality:%v", q.Issues))
		} else {
			e.logger.Infof("sheet-grid page=%d: image-quality OK blur=%.1f contrast=%.1f bright=%.1f skew=%.1f°",
				pageIdx, q.Blur, q.Contrast, q.Brightness, q.SkewDeg)
		}
	}

	sheet, err := e.fetchSheetFromCV(ctx, imgBytes)
	if err != nil {
		return nil, fmt.Errorf("cv sheet: %w", err)
	}
	sheetRaw, _ := json.Marshal(sheet)

	srcImg, _, err := image.Decode(bytes.NewReader(imgBytes))
	if err != nil {
		return nil, fmt.Errorf("decode image: %w", err)
	}

	byRow := indexCells(sheet.Cells)
	dataRowIdxs := inferDataRows(sheet.Rows, byRow)
	// v1.0.146 — ExpectedRowCount = CV-detected non-blank data rows. The
	// caller compares this to len(out rows with SaleQty>0) to detect
	// under-coverage (e.g. AI returned 11 of 26 visible rows) and trigger
	// supplemental legacy fallback.
	res.ExpectedRowCount = len(dataRowIdxs)
	if len(dataRowIdxs) == 0 {
		return res, nil
	}

	// Single batched call — reads BOTH the printed brand text AND the
	// handwritten sale digit per row. Skips cells with no writing.
	dataRows := make([]SheetRow, 0, len(dataRowIdxs))
	for _, ri := range dataRowIdxs {
		for _, r := range sheet.Rows {
			if r.Idx == ri {
				dataRows = append(dataRows, r)
				break
			}
		}
	}
	// v1.0.140 — shadow-mode local digit prediction. When
	// SMART_SALE_LOCAL_DIGIT_MODEL=shadow we ALSO call cv-sidecar
	// /predict-cells in parallel with the AI batched call and log per-cell
	// agreement (no behavior change — AI result still wins). This gives us
	// the data needed to gate the promotion to mode=1 (model-primary).
	mode := os.Getenv("SMART_SALE_LOCAL_DIGIT_MODEL")
	var localPreds map[string]CellPrediction // keyed by "rowIdx|colName"
	var localModelVersion string
	if (mode == "shadow" || mode == "1") && e.cvSidecar != nil {
		// Build the cell list for /predict-cells: every Sale cell that has writing.
		var cellsForLocal []SheetCell
		for _, ri := range dataRowIdxs {
			cells := byRow[ri]
			if c, ok := cells["sale"]; ok && c.HasWriting {
				cellsForLocal = append(cellsForLocal, c)
			}
		}
		if len(cellsForLocal) > 0 {
			preds, mv, perr := e.cvSidecar.PredictCells(ctx, imgBytes, cellsForLocal)
			if perr == nil && len(preds) > 0 {
				localModelVersion = mv
				localPreds = make(map[string]CellPrediction, len(preds))
				for _, p := range preds {
					localPreds[fmt.Sprintf("%d|%s", p.RowIdx, p.ColName)] = p
				}
				e.logger.Infof("sheet-grid local-model: page=%d cells=%d model=%s", pageIdx, len(preds), mv)
			} else if perr != nil {
				e.logger.Warnf("sheet-grid local-model: page=%d failed: %v", pageIdx, perr)
			}
		}
	}

	// v1.0.157 Phase 2 — pull brand text deterministically from PaddleOCR
	// BEFORE the AI call. PaddleOCR runs on CPU at ₹0/page and reads printed
	// brand columns at ~95% accuracy; we only fall back to Sonnet's brand
	// read for low-confidence rows. Map keyed by row_idx so overlay below
	// is a constant-time lookup. Best-effort — paddle errors get logged
	// and we fall through to the existing Sonnet path.
	paddleBrands := map[int]BrandRead{}
	if e.cvSidecar != nil {
		if pb, perr := e.cvSidecar.ExtractBrands(ctx, imgBytes); perr != nil {
			e.logger.Warnf("sheet-grid page=%d paddleocr brand call failed: %v (falling back to AI brand)", pageIdx, perr)
		} else {
			high := 0
			for _, b := range pb {
				if b.Confidence >= 0.85 && strings.TrimSpace(b.BrandText) != "" {
					paddleBrands[b.RowIdx] = b
					high++
				}
			}
			e.logger.Infof("sheet-grid page=%d paddleocr-brand: total=%d high_conf=%d (cost=₹0)", pageIdx, len(pb), high)
		}
	}

	// v1.0.139: pass printed-list size so the batched call skips Brand crops
	// for the first N rows (already known by index lookup). Saves ~20% input tokens.
	// v1.0.157 Phase 2: pass paddleBrands so the batched call SKIPS the
	// brand crop entirely for rows with high-conf Paddle reads — saves
	// 30-40% input tokens on those rows since the brand cell is the widest.
	reads, cost, err := e.readSaleAndBrandBatched(ctx, srcImg, dataRows, byRow, pageIdx, len(printed), paddleBrands)
	if err != nil {
		return nil, fmt.Errorf("batched brand+sale read: %w", err)
	}
	res.CostINR += cost
	res.CallsMade++

	// v1.0.157 Phase 2 — fill brand_text from PaddleOCR. For rows where the
	// Sonnet call had no brand crop, brand_text comes back null and we fill
	// it from Paddle here. For rows that DID get a brand crop (low-conf
	// Paddle), Paddle's read still wins when present — Paddle is much less
	// likely to hallucinate the same text on multiple rows than Sonnet.
	filled, overrides := 0, 0
	for ri, rd := range reads {
		pb, ok := paddleBrands[ri]
		if !ok {
			continue
		}
		if rd.BrandText == "" {
			rd.BrandText = pb.BrandText
			reads[ri] = rd
			filled++
		} else if rd.BrandText != pb.BrandText {
			rd.BrandText = pb.BrandText
			reads[ri] = rd
			overrides++
		}
	}
	if filled+overrides > 0 {
		e.logger.Infof("sheet-grid page=%d paddleocr-brand: filled=%d overrode=%d (of %d total reads)", pageIdx, filled, overrides, len(reads))
	}

	// Position-anchored brand binding: when CV row count matches the
	// printed-list size within ±2 (after header-row skipping), trust the
	// MRP-ordered shop inventory as the row→brand truth source. Catches
	// the row 1 ↔ row 4 brand swap class where Paddle/Sonnet correctly
	// read the cells but assigned them to the wrong rows.
	//
	// v1.0.158 — gated OFF by default. On the 30-Apr smoke this was
	// over-binding correct AI reads with wrong positional binds because
	// the printed-list shop ordering didn't always match the actual page
	// row order. Set SMART_SALE_POSITION_ANCHOR=1 to opt-in.
	if os.Getenv("SMART_SALE_POSITION_ANCHOR") == "1" {
		// Recompute offset for the log line (mirror of helper's logic).
		offset := 0
		for offset < 2 && offset < len(dataRowIdxs) {
			ri := dataRowIdxs[offset]
			pb, ok := paddleBrands[ri]
			if !ok {
				break
			}
			t := strings.TrimSpace(pb.BrandText)
			upper := strings.ToUpper(t)
			isHdr := strings.Contains(upper, "SALE") || strings.Contains(upper, "STARTING STOCK")
			if !isHdr && len(t) > 0 && len(t) <= 24 {
				allUpperOrSpace := true
				hasLetter := false
				for _, r := range t {
					switch {
					case r >= 'A' && r <= 'Z':
						hasLetter = true
					case r == ' ' || r == '\t':
					default:
						allUpperOrSpace = false
					}
				}
				if allUpperOrSpace && hasLetter {
					isHdr = true
				}
			}
			if !isHdr {
				break
			}
			offset++
		}
		posOverrides := bindByPrintedListPosition(reads, dataRowIdxs, printed, paddleBrands)
		e.logger.Infof("sheet-grid page=%d position-anchored: rows=%d printed=%d offset=%d overrides=%d",
			pageIdx, len(dataRowIdxs), len(printed), offset, posOverrides)
	}

	// v1.0.154 — duplicate-brand-text detection. Sheet-grid hits a failure
	// mode where Sonnet returns the SAME brand text for many adjacent rows
	// (often the most-visible brand on the page). On chhotu's 30-Apr 375ml
	// "Sov 1965 XXX Rum" came back for rows 1, 10, and 11. Suppress the
	// brand text on rows where the same text appeared 3+ times across the
	// page — those rows fall through to brand_unresolved and let the
	// operator fix manually instead of silently mis-routing the sale.
	{
		brandCounts := make(map[string]int)
		for _, rd := range reads {
			t := strings.ToLower(strings.TrimSpace(rd.BrandText))
			if t == "" || t == "__grand_total__" {
				continue
			}
			brandCounts[t]++
		}
		for ri, rd := range reads {
			t := strings.ToLower(strings.TrimSpace(rd.BrandText))
			if t == "" {
				continue
			}
			if brandCounts[t] >= 3 {
				rd.BrandText = ""
				reads[ri] = rd
				e.logger.Infof("sheet-grid page=%d row=%d: dropped brand text (appeared %d times on page — likely hallucination)",
					pageIdx, ri, brandCounts[t])
			}
		}
	}

	// Shadow-mode telemetry. Logs one line per Sale cell where local model
	// returned a non-empty prediction. Aggregator (later) parses these to
	// produce the agreement-rate report that gates rollout.
	if mode == "shadow" && localPreds != nil {
		for ri, rd := range reads {
			lp, ok := localPreds[fmt.Sprintf("%d|sale", ri)]
			if !ok || lp.Digit == "" {
				continue
			}
			aiVal := ""
			if rd.SaleQty != nil {
				aiVal = strconv.Itoa(*rd.SaleQty)
			}
			e.logger.Infof("sheet-grid-shadow page=%d row=%d col=sale model=%s ai=%s conf=%.2f model_version=%s",
				pageIdx, ri, lp.Digit, aiVal, lp.Confidence, localModelVersion)
		}
	}

	for _, ri := range dataRowIdxs {
		row := SheetSaleRow{RowIdx: ri}
		brandText := ""
		var rd SaleRowRead
		if r, ok := reads[ri]; ok {
			rd = r
			brandText = strings.TrimSpace(rd.BrandText)
		}
		if brandText == "__GRAND_TOTAL__" || isLikelyGrandTotalText(brandText) || isLikelyHeaderRowText(brandText) {
			continue
		}
		if brandText != "" {
			resolved := false
			if e.aliasService != nil {
				// v1.0.160 — shop-scoped cascade. Shop-specific OCR aliases
				// fire first; falls through to tenant-wide on miss; then to
				// jaccard fuzzy. Negative-alias gating still applies.
				pid, canonical, _, found := e.aliasService.LookupAliasCascade(ctx, tenantID, shopID, brandText, "")
				if found && pid != nil {
					row.ProductID = pid
					row.BrandName = canonical
					for _, pb := range printed {
						if pb.ProductID == *pid {
							row.MRP = pb.MRP
							break
						}
					}
					row.Source = "alias-resolved"
					resolved = true
				}
			}
			if !resolved {
				if pb := matchPrintedBrand(brandText, printed); pb != nil {
					pid := pb.ProductID
					row.ProductID = &pid
					row.BrandName = pb.BrandName
					row.MRP = pb.MRP
					resolved = true
				}
			}
			if !resolved {
				row.BrandName = brandText
				row.Source = "addon-unresolved"
				row.Warnings = append(row.Warnings, "brand_unresolved:"+brandText)
			}
		}

		// Anti-hallucination guard: when the Sale CELL is visibly blank
		// (CV reports has_writing=false on the Sale column), trust that
		// "no writing = no sale". DO NOT math-derive a phantom sale from
		// open-close in that case. This is the dominant hallucination
		// source on registers where the salesman wrote a dash for "no
		// sale today" — open and close are filled (carried forward) but
		// sale was zero.
		saleCell, hasSaleCell := byRow[ri]["sale"]
		saleCellBlank := !hasSaleCell || !saleCell.HasWriting
		var qty int
		var source string
		var conf float64
		var warns []string
		if saleCellBlank {
			qty = 0
			source = "blank-sale-cell"
			conf = 1.0
		} else {
			// Math gate — open-close=sale or total-close=sale verification.
			// Cost: ZERO additional API calls (all 4 cells in the batched call).
			qty, source, conf, warns = reconcileSale(rd)
		}
		row.SaleQty = qty
		row.Source = source
		row.Confidence = conf
		row.Warnings = append(row.Warnings, warns...)

		// v1.0.141 — Drop rows that reconcile flagged as
		// "no-math-anchor-dropped". These are the AI hallucinations
		// (Brand Name=16, Jack Daniels=2, JOHNNIE WALKER=2 with no
		// open-close anchor). Better to miss than create phantom sales
		// the operator has to manually delete.
		if source == "no-math-anchor-dropped" {
			continue
		}

		// Skip rule: zero stock + zero sale + no add-on brand → drop entirely.
		if qty == 0 && row.ProductID != nil {
			zeroStock := false
			for _, pb := range printed {
				if pb.ProductID == *row.ProductID && pb.StockQty == 0 {
					zeroStock = true
					break
				}
			}
			if zeroStock {
				continue
			}
		}
		res.Rows = append(res.Rows, row)
	}

	// Cell-level Opus retry on math-disagree rows. The math gate flagged
	// these cells as "AI sale doesn't match open-close" — the only path
	// that can break the disagreement is a stronger model re-reading
	// JUST that cell with no surrounding distraction. Cost: ~₹0.04 per
	// retried row. Capped to 6 retries per page so worst-case cost is
	// ₹0.25/page extra. Disabled by SMART_SALE_SHEET_GRID_RETRY=0.
	retryEnabled := os.Getenv("SMART_SALE_SHEET_GRID_RETRY") != "0"
	if retryEnabled {
		retried := 0
		const maxRetries = 6
		for i := range res.Rows {
			if retried >= maxRetries {
				break
			}
			r := &res.Rows[i]
			if r.Source != "ai-sale-math-disagree" && r.Source != "ai-sale-total-disagree" {
				continue
			}
			cell, ok := byRow[r.RowIdx]["sale"]
			if !ok || !cell.HasWriting {
				continue
			}
			v, cost, err := e.readNumberCell(ctx, srcImg, cell, "Sale")
			res.CostINR += cost
			res.CallsMade++
			retried++
			if err != nil {
				e.logger.Warnf("sheet-grid retry row=%d failed: %v", r.RowIdx, err)
				continue
			}
			if v == nil {
				r.Warnings = append(r.Warnings, "opus_retry_returned_null")
				continue
			}
			// Decision matrix (derived from real-world data on c8fc33fa):
			//   • Sonnet+Opus AGREE  → that value is the gold standard
			//     (two independent model families converging is more
			//     reliable than math derivation, which compounds open
			//     AND close cell errors). Confidence 0.97.
			//   • Sonnet+Opus DISAGREE → use math derivation as the
			//     tiebreaker:
			//       - if math matches Opus → take Opus, conf 0.96
			//       - if math matches Sonnet → keep Sonnet, conf 0.95
			//       - if math matches NEITHER → keep Sonnet (the original
			//         direct read of the dedicated Sale-cell crop) and
			//         flag for operator review. NEVER take math when
			//         both models disagree with it — math has compound
			//         error from two reads.
			rd := reads[r.RowIdx]
			oldQty := r.SaleQty
			abs := func(x int) int {
				if x < 0 {
					return -x
				}
				return x
			}
			expectedOC, expectedTC := 0, 0
			hasOC, hasTC := false, false
			if rd.OpenQty != nil && rd.CloseQty != nil {
				expectedOC = *rd.OpenQty - *rd.CloseQty
				if expectedOC >= 0 && expectedOC <= 200 {
					hasOC = true
				}
			}
			if rd.TotalQty != nil && rd.CloseQty != nil {
				expectedTC = *rd.TotalQty - *rd.CloseQty
				if expectedTC >= 0 && expectedTC <= 200 {
					hasTC = true
				}
			}
			matchesMath := func(x int) bool {
				if hasOC && abs(expectedOC-x) <= 1 {
					return true
				}
				if hasTC && abs(expectedTC-x) <= 1 {
					return true
				}
				return false
			}
			if abs(*v-oldQty) <= 1 {
				// Dual-model agreement — strongest signal.
				r.SaleQty = *v
				if matchesMath(*v) {
					r.Source = "dual-model+math-confirmed"
					r.Confidence = 0.99
				} else {
					r.Source = "dual-model-confirmed"
					r.Confidence = 0.97
				}
				e.logger.Infof("sheet-grid retry row=%d page=%d: sonnet=%d opus=%d agree → %d (%s)",
					r.RowIdx, pageIdx, oldQty, *v, r.SaleQty, r.Source)
			} else if matchesMath(*v) {
				// Models disagree, but Opus matches math → take Opus.
				r.SaleQty = *v
				r.Source = "opus-retry+math-confirmed"
				r.Confidence = 0.96
				e.logger.Infof("sheet-grid retry row=%d page=%d: sonnet=%d opus=%d → take opus=%d (math agrees)",
					r.RowIdx, pageIdx, oldQty, *v, *v)
			} else if matchesMath(oldQty) {
				// Models disagree, Sonnet matches math → keep Sonnet.
				r.Source = "ai-sale+math-confirmed"
				r.Confidence = 0.95
				e.logger.Infof("sheet-grid retry row=%d page=%d: sonnet=%d opus=%d → keep sonnet=%d (math agrees)",
					r.RowIdx, pageIdx, oldQty, *v, oldQty)
			} else {
				// Triple disagreement. Math is unreliable (no anchor agreed),
				// so we have to choose between Sonnet and Opus. Heuristic
				// derived from real data: when math is wildly implausible
				// (negative, or > Sonnet * 5), the open OR close cell was
				// misread; Opus is a stronger model and more often correct
				// when it actively changed Sonnet's answer.
				mathImplausible := !hasOC || expectedOC < 0 || expectedOC > 200
				if mathImplausible {
					r.SaleQty = *v
					r.Source = "opus-retry-trusted"
					r.Confidence = 0.78
					r.Warnings = append(r.Warnings, fmt.Sprintf("opus_overrode_sonnet:sonnet=%d opus=%d math_implausible=%d", oldQty, *v, expectedOC))
					e.logger.Infof("sheet-grid retry row=%d page=%d: math implausible (%d) → take opus=%d over sonnet=%d",
						r.RowIdx, pageIdx, expectedOC, *v, oldQty)
				} else {
					r.Warnings = append(r.Warnings, fmt.Sprintf("triple_disagreement:sonnet=%d opus=%d math_oc=%d math_tc=%d", oldQty, *v, expectedOC, expectedTC))
					r.Confidence = 0.70
					e.logger.Infof("sheet-grid retry row=%d page=%d: triple disagreement sonnet=%d opus=%d math=%d → keep sonnet (review needed)",
						r.RowIdx, pageIdx, oldQty, *v, expectedOC)
				}
			}
		}
	}

	// Sort by row index to keep the output stable.
	sort.Slice(res.Rows, func(i, j int) bool { return res.Rows[i].RowIdx < res.Rows[j].RowIdx })

	// Cache the result (brand-agnostic shape) for future re-runs.
	e.saveToCache(ctx, hash, CachedExtraction{
		Rows: func() []SheetSaleRow {
			// Strip per-tenant brand resolution for the cache (will be re-bound on hit).
			out := make([]SheetSaleRow, len(res.Rows))
			copy(out, res.Rows)
			for i := range out {
				out[i].ProductID = nil
				out[i].BrandName = ""
				out[i].MRP = 0
			}
			return out
		}(),
		CallsMade: res.CallsMade,
		CostINR:   res.CostINR,
		Warnings:  res.Warnings,
	}, sheetRaw)

	return res, nil
}

package services

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"log"
	"math"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
	"github.com/disintegration/imaging"
)

// GP TARGETED SIZE RE-READ (v1.0.374)
//
// THE GAP THIS CLOSES (job 4f2b33cf row 8 "Verve Cranberry"):
// repairGPSizeBleed can deterministically fix an adjacent Size+Packaging SWAP
// (the packaging-concatenation fingerprint), but a STANDALONE size misread —
// where Textract reads a coherent 180/48 and the LLM a coherent 375/24 for the
// SAME row — is data-indistinguishable from a correct row (row 6 vs row 8 carry
// byte-identical extracted data yet opposite truths). The safety net can only
// FLAG those, never auto-pick, because trusting either engine globally would
// corrupt the other case.
//
// The ONLY signal that separates them is the row's own pixels. This re-reads
// exactly that: for each flagged row, it crops the single physical row from the
// (deskewed) page using Textract's per-row geometry — anchored on the cleanly-read
// DUTY value, which is unique per row and immune to the column bleed — and asks
// the vision-LLM to read JUST that isolated row. An isolated single-row crop has
// no neighbour to bleed from, so the size/cases/bottles read is clean.
//
// SAFETY RAILS (never a blunder):
//   - Only rows already flagged SizeBleedSuspect && !corrected && SizeAltML>0.
//   - The re-read size is ACCEPTED only if it equals one of the two known
//     candidates (the Textract size or the LLM alternative) AND is a standard
//     size. A third value ⇒ keep the flag (re-read inconclusive).
//   - Counts are taken from the re-read only when they form a coherent full-case
//     pack under the accepted size; otherwise derived by pack-math.
// Dark by default; auto-on for the tester / SMART_PURCHASE_GP_SIZE_REREAD=1.

type gpSizeReReadCtxKey struct{}

func withGPSizeReRead(ctx context.Context, on bool) context.Context {
	return context.WithValue(ctx, gpSizeReReadCtxKey{}, on)
}

func gpSizeReReadEnabled(userID string) bool {
	if test := strings.TrimSpace(os.Getenv("SMART_PURCHASE_TEST_USER_ID")); test != "" {
		if strings.EqualFold(strings.TrimSpace(userID), test) {
			return true
		}
	}
	v := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_SIZE_REREAD"))
	return v == "1" || strings.EqualFold(v, "true")
}

func gpSizeReReadFromCtx(ctx context.Context) bool {
	if v, ok := ctx.Value(gpSizeReReadCtxKey{}).(bool); ok {
		return v
	}
	g := strings.TrimSpace(os.Getenv("SMART_PURCHASE_GP_SIZE_REREAD"))
	return g == "1" || strings.EqualFold(g, "true")
}

// gpRowBand is a row's vertical extent on the page, in pixels.
type gpRowBand struct{ top, bottom int }

// reReadFlaggedGPSizes re-reads the isolated pixels of every still-uncertain
// size-bleed row and auto-corrects the ones it can read confidently. Returns the
// number of rows corrected. merged is mutated in place.
func (s *SmartPurchaseService) reReadFlaggedGPSizes(ctx context.Context, images []SmartPurchaseImage, merged []GatePassDutyItem) int {
	// Which rows still need a decision?
	byPage := map[int][]int{}
	for i := range merged {
		m := &merged[i]
		if m.SizeBleedSuspect && !m.SizeBleedCorrected && m.SizeAltML > 0 && m.DutyFee > 0 {
			p := m.PageIndex
			if p <= 0 {
				p = 1
			}
			byPage[p] = append(byPage[p], i)
		}
	}
	if len(byPage) == 0 {
		return 0
	}

	client, err := newTextractPurchaseClient(ctx)
	if err != nil {
		log.Printf("SmartPurchase GP re-read: textract client init failed: %v — keeping flags", err)
		return 0
	}
	deskew := newDeskewClient()
	fixed := 0

	for page, idxs := range byPage {
		if page-1 < 0 || page-1 >= len(images) || len(images[page-1].Data) == 0 {
			continue
		}
		// Deskew so Textract geometry lines up with the bytes we crop from.
		pre := prepareTextractImageVariant(images[page-1].Data, 0)
		dctx, dcancel := context.WithTimeout(ctx, 3*time.Second)
		if d := deskew.Deskew(dctx, pre); len(d) > 0 && len(d) != len(pre) {
			pre = d
		}
		dcancel()

		srcImg, _, derr := image.Decode(bytes.NewReader(pre))
		if derr != nil {
			log.Printf("SmartPurchase GP re-read: page %d decode failed: %v", page, derr)
			continue
		}
		imgH := srcImg.Bounds().Dy()

		// Targets = the flagged rows' duty values (unique, cleanly-read keys).
		targets := make([]float64, 0, len(idxs))
		for _, i := range idxs {
			targets = append(targets, merged[i].DutyFee)
		}
		bands := gpRowBandsForDuties(ctx, client, pre, targets, imgH)
		if len(bands) == 0 {
			log.Printf("SmartPurchase GP re-read: page %d — no duty-anchored row bands found, keeping flags", page)
			continue
		}

		for _, i := range idxs {
			band, ok := bands[dutyKey(merged[i].DutyFee)]
			if !ok {
				continue
			}
			cropBytes, ok := cropRowBandJPEG(srcImg, band, imgH)
			if !ok {
				continue
			}
			sz, cs, bt, ok := s.readSingleGPRow(ctx, cropBytes, merged[i].BrandName)
			if !ok {
				continue
			}
			// SAFETY: accept only one of the two known candidates, and only a
			// standard size. Anything else ⇒ re-read inconclusive, keep the flag.
			cand1, cand2 := merged[i].SizeML, merged[i].SizeAltML
			if sz != cand1 && sz != cand2 {
				log.Printf("  GP re-read: row %d %q read %dML — not in candidates {%d,%d}, keeping flag",
					merged[i].RowNumber, truncBrand(merged[i].BrandName), sz, cand1, cand2)
				continue
			}
			std, okStd := StandardCaseSizes[sz]
			if !okStd {
				continue
			}
			// Counts: trust the re-read pair when coherent, else pack-math.
			newCases, newBottles := cs, bt
			if newCases <= 0 || newBottles != newCases*std {
				if newCases > 0 {
					newBottles = newCases * std
				} else if merged[i].Cases > 0 {
					newCases, newBottles = merged[i].Cases, merged[i].Cases*std
				} else {
					newBottles = std
					newCases = 1
				}
			}
			log.Printf("  GP re-read CORRECT: row %d %q size %dML→%dML, dispatch %d×%d=%d (isolated single-row crop, brand-anchored)",
				merged[i].RowNumber, truncBrand(merged[i].BrandName), cand1, sz, newCases, std, newBottles)
			merged[i].SizeML = sz
			merged[i].Size = fmt.Sprintf("%dML", sz)
			merged[i].Cases = newCases
			merged[i].Bottles = newBottles
			merged[i].SizeBleedCorrected = true
			merged[i].SizeAltML = 0
			fixed++
		}
	}
	if fixed > 0 {
		log.Printf("SmartPurchase GP re-read: auto-corrected %d flagged size(s) via isolated re-read", fixed)
	}
	return fixed
}

// dutyKey rounds a duty fee to paise so float reads match exactly.
func dutyKey(d float64) int64 { return int64(math.Round(d * 100)) }

// gpRowBandsForDuties runs one Textract TABLES pass on the full page and returns,
// for each target duty value, the vertical pixel band of the table row that
// carries it (union of that row's cells, so the band spans the whole sheared row).
func gpRowBandsForDuties(ctx context.Context, client *textract.Client, img []byte, targets []float64, imgH int) map[int64]gpRowBand {
	out := map[int64]gpRowBand{}
	want := map[int64]bool{}
	for _, t := range targets {
		want[dutyKey(t)] = true
	}

	// Detached from the caller's (possibly near-expired) extraction deadline — the
	// re-read is a best-effort enhancement with its own bound.
	pctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(pctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: img},
		FeatureTypes: []ttypes.FeatureType{ttypes.FeatureTypeTables},
	})
	if err != nil {
		log.Printf("SmartPurchase GP re-read: AnalyzeDocument failed: %v", err)
		return out
	}

	blockByID := map[string]ttypes.Block{}
	for _, b := range resp.Blocks {
		if b.Id != nil {
			blockByID[*b.Id] = b
		}
	}
	// Largest table.
	var best *ttypes.Block
	bestN := 0
	for i, b := range resp.Blocks {
		if b.BlockType != ttypes.BlockTypeTable {
			continue
		}
		n := 0
		for _, rel := range b.Relationships {
			if rel.Type == ttypes.RelationshipTypeChild {
				n += len(rel.Ids)
			}
		}
		if n > bestN {
			bestN, best = n, &resp.Blocks[i]
		}
	}
	if best == nil {
		return out
	}
	// rowIdx -> cells.
	rows := map[int32][]ttypes.Block{}
	for _, rel := range best.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, cid := range rel.Ids {
			cell, ok := blockByID[cid]
			if !ok || cell.BlockType != ttypes.BlockTypeCell || cell.RowIndex == nil {
				continue
			}
			rows[*cell.RowIndex] = append(rows[*cell.RowIndex], cell)
		}
	}
	for _, cells := range rows {
		// Does this row carry one of the target duties (any cell text matches)?
		var matchKey int64 = -1
		for _, c := range cells {
			txt := strings.TrimSpace(joinCellText(c, blockByID))
			if txt == "" {
				continue
			}
			v, perr := strconv.ParseFloat(strings.ReplaceAll(txt, ",", ""), 64)
			if perr != nil {
				continue
			}
			if want[dutyKey(v)] {
				matchKey = dutyKey(v)
				break
			}
		}
		if matchKey < 0 {
			continue
		}
		// Union vertical extent of this row's cells (covers the sheared row).
		top, bottom := 1.0, 0.0
		for _, c := range cells {
			if c.Geometry == nil || c.Geometry.BoundingBox == nil {
				continue
			}
			bb := c.Geometry.BoundingBox
			t := float64(bb.Top)
			b := float64(bb.Top + bb.Height)
			if t < top {
				top = t
			}
			if b > bottom {
				bottom = b
			}
		}
		if bottom <= top {
			continue
		}
		out[matchKey] = gpRowBand{top: int(top * float64(imgH)), bottom: int(bottom * float64(imgH))}
	}
	return out
}

// cropRowBandJPEG crops the full image width at the row band's vertical extent,
// padded by ~60% of the row height on each side so the whole (sheared) row is
// captured even if the duty cell sat slightly off from the size cell.
func cropRowBandJPEG(src image.Image, band gpRowBand, imgH int) ([]byte, bool) {
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	b := src.Bounds()
	h := band.bottom - band.top
	if h <= 0 {
		return nil, false
	}
	pad := int(float64(h) * 0.6)
	y0 := band.top - pad
	y1 := band.bottom + pad
	if y0 < b.Min.Y {
		y0 = b.Min.Y
	}
	if y1 > b.Max.Y {
		y1 = b.Max.Y
	}
	si, ok := src.(subImager)
	if !ok {
		rgba := image.NewRGBA(b)
		for y := b.Min.Y; y < b.Max.Y; y++ {
			for x := b.Min.X; x < b.Max.X; x++ {
				rgba.Set(x, y, src.At(x, y))
			}
		}
		si = rgba
	}
	crop := si.SubImage(image.Rect(b.Min.X, y0, b.Max.X, y1))
	// Downscale wide crops — a full-page-width band on a deskewed (often upscaled)
	// image can be large enough to make the vision-LLM call slow / time out. Cap the
	// width at 1100px; a single row stays legible well below that.
	var out image.Image = crop
	if crop.Bounds().Dx() > 1100 {
		out = imaging.Resize(crop, 1100, 0, imaging.Lanczos)
	}
	log.Printf("  GP re-read: row crop %dx%d (band y=%d..%d pad source)", out.Bounds().Dx(), out.Bounds().Dy(), y0, y1)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: 85}); err != nil {
		return nil, false
	}
	return buf.Bytes(), true
}

// readSingleGPRow asks the vision-LLM to read one isolated row crop for a known
// brand. Returns (sizeML, cases, bottles, ok).
func (s *SmartPurchaseService) readSingleGPRow(ctx context.Context, cropJPEG []byte, brand string) (int, int, int, bool) {
	prompt := fmt.Sprintf(`You are reading ONE row cropped from a UP (Uttar Pradesh) Excise gate pass / transport permit table.
This crop contains a single data row for the brand: %q (plus possibly a thin sliver of the rows above/below — ignore those).

Read ONLY the row for %q. The columns, left to right, include: Brand, Liquor Type, Sub Type, Description, Packaging Size (ml: one of 90/180/375/750/1000), Packaging Type, Cases Requested, Bottles Requested, No. of Cases Dispatched, No. of Bottles Dispatched, Duty Fee.

Rules:
- Ignore ALL handwriting; read only the printed table digits.
- Packaging Size is the printed ml value for THIS brand's row.
- Use the DISPATCHED cases and bottles (the right-hand pair), not Requested.
- Read each printed digit literally; do not infer.

Return ONLY this JSON (no prose):
{"items":[{"row_number":1,"brand_name":%q,"size_ml":<int>,"cases":<int>,"bottles":<int>}]}`, brand, brand, brand)

	// Fast mode: a single-row crop yields exactly ONE item, which the cascade's
	// looksTruncated heuristic would mistake for an under-extraction and escalate
	// gemini→claude→openai (slow; the openai leg timed out in v374 testing). Fast
	// mode accepts the first backend (Gemini) that parses.
	// Detached + fast mode: own deadline (not the caller's near-expired one), and
	// accept the first backend that parses (a 1-item crop must not trigger the
	// truncation escalation through claude/openai).
	ctctx, cancel := context.WithTimeout(withGPFastLLM(context.Background()), 50*time.Second)
	defer cancel()
	res, err := s.ocr.extractGatePassWithAI(ctctx, cropJPEG, "image/jpeg", prompt)
	if err != nil || res == nil || len(res.Items) == 0 {
		if err != nil {
			log.Printf("SmartPurchase GP re-read: single-row LLM read failed for %q: %v", truncBrand(brand), err)
		}
		return 0, 0, 0, false
	}
	// Pick the item whose brand best matches; default to the first.
	pick := res.Items[0]
	bnorm := normBrandKey(brand)
	for _, it := range res.Items {
		if normBrandKey(it.BrandName) == bnorm {
			pick = it
			break
		}
	}
	if pick.SizeML <= 0 {
		return 0, 0, 0, false
	}
	return pick.SizeML, pick.Cases, pick.Bottles, true
}

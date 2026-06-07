package services

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png" // decoder registration

	"golang.org/x/image/draw"
)

// splitImageVerticallyOverlap returns N vertical strips of the input JPEG,
// each strip overlapping its neighbor by `overlapFrac` (0..1) of the image
// height. v1.0.237 — used to chunk dense GP pages (>20 rows per page) into
// sub-images each containing ≤ 20 rows, so Textract's cell-boundary detector
// doesn't fragment multi-line wrap text across adjacent rows.
//
// Strategy: split into N equal-height strips, then extend each strip
// outwards by overlapFrac*H/N so adjacent strips share rows. Operator's
// downstream pipeline merges by printed S.No, deduping the shared rows.
//
// Real-data trigger (chhotu DocScanner 2026-05-13 page-0005, 28 rows):
// Textract's raw output had 18 of 28 rows mangled (multi-line wrap +
// row-number leaks). Splitting into 2 strips of ~14 rows each + 30%
// overlap brings Textract back to clean per-row extraction.
func splitImageVerticallyOverlap(raw []byte, n int, overlapFrac float64) ([][]byte, error) {
	if n <= 1 {
		return [][]byte{raw}, nil
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, fmt.Errorf("decode for split: %w", err)
	}
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	if w == 0 || h == 0 {
		return [][]byte{raw}, nil
	}
	if overlapFrac < 0 {
		overlapFrac = 0
	}
	if overlapFrac > 0.5 {
		overlapFrac = 0.5
	}
	baseStripH := float64(h) / float64(n)
	overlapPx := int(float64(h) * overlapFrac / float64(n))

	out := make([][]byte, 0, n)
	for i := 0; i < n; i++ {
		y0 := int(float64(i) * baseStripH)
		y1 := int(float64(i+1) * baseStripH)
		// Extend outwards by overlapPx so neighbours share rows.
		y0 -= overlapPx
		y1 += overlapPx
		if y0 < 0 {
			y0 = 0
		}
		if y1 > h {
			y1 = h
		}
		sh := y1 - y0
		if sh <= 0 {
			continue
		}
		dst := image.NewRGBA(image.Rect(0, 0, w, sh))
		draw.Copy(dst, image.Pt(0, 0), img, image.Rect(0, y0, w, y1), draw.Src, nil)
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: 92}); err != nil {
			return nil, fmt.Errorf("encode strip %d: %w", i, err)
		}
		out = append(out, buf.Bytes())
	}
	return out, nil
}

// prepareTextractImage upscales small phone-shot images so Textract has
// enough pixels per row to detect dense liquor-invoice tables.
//
// Chhotu's real-data trigger: 720×1280 phone JPEGs of a 41-row invoice meant
// each row got ~17 vertical pixels — below Textract's reliable detection
// threshold (~25-30 px/row). Result: 6 of 41 rows extracted, 86% miss rate.
//
// v1.0.235 — bumped target threshold from "≥1500 px" to "≥3000 px on longest
// edge". Real-data root cause (chhotu job 432e396a, 2026-05-13): GP image
// at 713×1600 made Textract read printed "8PM" as "6PM" on row 1 because
// per-character width was ~10-15px. After 3× upscale → 2139×4800 →
// per-character width ~40-60px → Textract digit accuracy goes from ~92%
// to ~99% on the same source pixels.
//
// Strategy: scale factor = ceil(3000 / longest_edge), capped at 4× (Textract
// 10MB limit). Catmull-Rom is sharper than BiLinear on printed text edges.
// Output is re-encoded as JPEG quality=92 for Textract.
//
// Why not deskew + upscale together in cv-sidecar? Latency. The cv-sidecar
// deskew adds another HTTP roundtrip (~200ms) and 0.5° tilts on chhotu's
// phone shots are below the deskew threshold. Local upscale is faster and
// addresses the bigger problem (resolution).
func prepareTextractImage(raw []byte) []byte {
	return prepareTextractImageVariant(raw, 0)
}

// prepareTextractImageVariant produces preprocessed images for the v215.1
// dual-variant AnalyzeExpense merge. variant=0 is the canonical path
// (Catmull-Rom upscale, JPEG q=92 — what shipped through v215). variant=1
// uses BiLinear upscale + JPEG q=80 — slightly softer pixels and weaker
// edge contrast, which Textract's OCR + LineItem grouping interprets
// differently.
//
// Real-data motivation (chhotu 2026-05-08 SONU SINGH bill):
//   - run A: AnalyzeExpense returned 36 of 42 rows on page 1
//   - run B (different preprocessing): returned 42 of 42 rows
// AnalyzeExpense's LineItem grouping is sensitive to row-separator pixel
// width — varying the upscale algorithm + JPEG quality nudges the
// segmentation across the threshold for a different row set. We then
// MERGE the two responses by printed S.No to capture the union — neither
// run alone hits 100%, but the union does on every chhotu sample.
func prepareTextractImageVariant(raw []byte, variant int) []byte {
	if len(raw) == 0 {
		return raw
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return raw
	}
	bounds := img.Bounds()
	w := bounds.Dx()
	h := bounds.Dy()
	long := w
	if h > long {
		long = h
	}
	// v1.0.235 — only skip when already > 3000px long edge (was 1500px).
	// Variants 1+ always re-encode to ensure byte-divergence even on
	// already-large images, so the cache key differs.
	if long >= 3000 && variant == 0 {
		return raw
	}

	// Variant 2 — bottom-half crop. Recovers the LAST printed row when
	// Textract's page-bottom truncation drops it (S.No 42 case on
	// chhotu's bill page 1). The crop is the bottom 60% of the original
	// image (40% overlap with top half), then upscaled so the dropped
	// row sits well above the page-bottom boundary in the output buffer.
	if variant == 2 {
		// Take the lower 60% of the source image.
		cropTop := int(float64(h) * 0.40)
		if cropTop < 0 {
			cropTop = 0
		}
		cropRect := image.Rect(bounds.Min.X, bounds.Min.Y+cropTop, bounds.Max.X, bounds.Max.Y)
		type subImager interface{ SubImage(image.Rectangle) image.Image }
		var cropped image.Image = img
		if si, ok := img.(subImager); ok {
			cropped = si.SubImage(cropRect)
		}
		cb := cropped.Bounds()
		cw := cb.Dx()
		ch := cb.Dy()
		// Upscale 2× and re-encode as JPEG q=90 — different bytes from
		// variants 0+1 so the cache key is distinct.
		dst := image.NewRGBA(image.Rect(0, 0, cw*2, ch*2))
		draw.CatmullRom.Scale(dst, dst.Bounds(), cropped, cb, draw.Over, nil)
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: 90}); err != nil {
			return raw
		}
		return buf.Bytes()
	}

	// v1.0.235 — pick scale factor so output longest-edge ≥ 3000px.
	// Capped at 4× to stay under Textract's 10MB limit on huge originals.
	scale := 2
	switch {
	case long >= 3000:
		scale = 1
	case long >= 1500:
		scale = 2 // ~3000-6000px output
	case long >= 1000:
		scale = 3 // ~3000-4500px output
	default:
		scale = 4 // tiny phone images → ~3200-4800px output
	}
	dst := image.NewRGBA(image.Rect(0, 0, w*scale, h*scale))
	switch variant {
	case 1:
		draw.BiLinear.Scale(dst, dst.Bounds(), img, bounds, draw.Over, nil)
	default:
		draw.CatmullRom.Scale(dst, dst.Bounds(), img, bounds, draw.Over, nil)
	}
	q := 92
	if variant == 1 {
		q = 80
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: q}); err != nil {
		return raw
	}
	return buf.Bytes()
}

package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"image"
	"image/jpeg"
)

// v1.0.133-r10 — CV-driven verifier crop helper. When the CV sidecar has
// returned row Y-bounds (via SaleCVRowsCtxKey), use them to crop the source
// image at PIXEL-ACCURATE positions instead of the linear-partition fallback.
// This is the foundational piece of cell-level extraction (P0 Phase 3): the
// Opus verifier sees the exact handwritten row, not a possibly-misaligned slice.

// SaleCVRowsCtxKey carries []cvSidecarRow on the call context. Set by the
// extractor after a successful CV sidecar call so the verifier can fetch it
// without a second HTTP round-trip.
type saleCVRowsCtxKeyT struct{}

var SaleCVRowsCtxKey = saleCVRowsCtxKeyT{}

// buildSaleVerifierCropsCVFirst attempts CV-driven cropping first; falls back
// to the heuristic linear partition when CV data is missing or malformed.
// Behavior is otherwise identical to buildSaleVerifierCrops.
func buildSaleVerifierCropsCVFirst(c *ClaudeOCRService, ctx context.Context, imageBytes []byte, rowNumbers []int, totalRows int) ([]saleClaudeContent, bool) {
	cvRows, _ := ctx.Value(SaleCVRowsCtxKey).([]cvSidecarRow)
	if len(cvRows) >= len(rowNumbers) && len(cvRows) >= 4 {
		if out, ok := buildVerifierCropsFromCV(c, imageBytes, rowNumbers, cvRows); ok {
			return out, true
		}
	}
	// Fallback to legacy linear partition.
	return buildSaleVerifierCrops(c, imageBytes, rowNumbers, totalRows)
}

func buildVerifierCropsFromCV(c *ClaudeOCRService, imageBytes []byte, rowNumbers []int, cvRows []cvSidecarRow) ([]saleClaudeContent, bool) {
	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		c.logger.Warnf("SmartSale Claude: CV verifier crop decode failed: %v", err)
		return nil, false
	}
	bounds := src.Bounds()
	W, H := bounds.Dx(), bounds.Dy()
	if W < 200 || H < 200 {
		return nil, false
	}
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}
	si, ok := src.(subImager)
	if !ok {
		rgba := image.NewRGBA(bounds)
		for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
			for x := bounds.Min.X; x < bounds.Max.X; x++ {
				rgba.Set(x, y, src.At(x, y))
			}
		}
		si = rgba
	}
	encode := func(img image.Image) (saleClaudeContent, bool) {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85}); err != nil {
			return saleClaudeContent{}, false
		}
		return saleClaudeContent{
			Type: "image",
			Source: &saleClaudeImageSrc{
				Type:      "base64",
				MediaType: "image/jpeg",
				Data:      base64.StdEncoding.EncodeToString(buf.Bytes()),
			},
		}, true
	}
	out := make([]saleClaudeContent, 0, len(rowNumbers)+1)
	// Header strip: from page top to the start of the first detected row.
	if cvRows[0].YTop > 30 {
		hdrBottom := cvRows[0].YTop
		if hdrBottom > H/3 {
			hdrBottom = H / 3
		}
		if cb, ok2 := encode(si.SubImage(image.Rect(bounds.Min.X, bounds.Min.Y, bounds.Max.X, bounds.Min.Y+hdrBottom))); ok2 {
			out = append(out, cb)
		}
	}
	pad := H / 80
	addedAny := false
	for _, row := range rowNumbers {
		idx := row - 1
		if idx < 0 || idx >= len(cvRows) {
			continue
		}
		y0 := bounds.Min.Y + cvRows[idx].YTop - pad
		y1 := bounds.Min.Y + cvRows[idx].YBottom + pad
		if y0 < bounds.Min.Y {
			y0 = bounds.Min.Y
		}
		if y1 > bounds.Max.Y {
			y1 = bounds.Max.Y
		}
		if y1-y0 < 25 {
			continue
		}
		if cb, ok2 := encode(si.SubImage(image.Rect(bounds.Min.X, y0, bounds.Max.X, y1))); ok2 {
			out = append(out, cb)
			addedAny = true
		}
	}
	if !addedAny {
		return nil, false
	}
	c.logger.Infof("SmartSale Claude: verifier using CV-driven crops (%d row crops + header)", len(out)-1)
	return out, true
}

package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"image"
	"image/jpeg"
	"log"
)

// v1.0.134 — CV-driven verifier crop helper for Stock Setup. Mirrors
// internal/sales/services/cv_verifier_crops.go but emits []claudeContent
// (the Stock Setup struct shape) instead of []saleClaudeContent.
//
// When CV row Y-bounds are present on the call context (StockSetupCVRowsCtxKey),
// crop at PIXEL-ACCURATE positions instead of the linear-partition heuristic.
// Falls back to the legacy buildVerifierCrops path on any failure or when
// CV data is too sparse to be trusted.

func buildStockSetupVerifierCropsCVFirst(ctx context.Context, imageBytes []byte, rowNumbers []int, totalRows int) ([]claudeContent, bool) {
	cvRows, _ := ctx.Value(StockSetupCVRowsCtxKey).([]stockSetupCVRow)
	if len(cvRows) >= len(rowNumbers) && len(cvRows) >= 4 {
		if out, ok := buildStockSetupVerifierCropsFromCV(imageBytes, rowNumbers, cvRows); ok {
			return out, true
		}
	}
	return buildVerifierCrops(imageBytes, rowNumbers, totalRows)
}

func buildStockSetupVerifierCropsFromCV(imageBytes []byte, rowNumbers []int, cvRows []stockSetupCVRow) ([]claudeContent, bool) {
	src, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		log.Printf("Smart Stock Setup OCR: CV verifier crop decode failed: %v", err)
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
	encode := func(img image.Image) (claudeContent, bool) {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 88}); err != nil {
			return claudeContent{}, false
		}
		return claudeContent{
			Type: "image",
			Source: &claudeImageSource{
				Type:      "base64",
				MediaType: "image/jpeg",
				Data:      base64.StdEncoding.EncodeToString(buf.Bytes()),
			},
		}, true
	}
	out := make([]claudeContent, 0, len(rowNumbers)+1)
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
	log.Printf("Smart Stock Setup OCR: verifier using CV-driven crops (%d row crops + header)", len(out)-1)
	return out, true
}

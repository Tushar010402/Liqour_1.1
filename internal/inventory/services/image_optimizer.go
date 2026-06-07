package services

import (
	"bytes"
	"image"
	"image/jpeg"
	_ "image/png"
	"os"
	"strconv"

	"github.com/disintegration/imaging"
)

// v1.0.134 — pre-send image optimizer for Stock Setup. Mirrors Smart Sale's
// optimizeImageForClaude (sales/services/image_optimizer.go) but reads its
// own env knobs so the two pipelines can be tuned independently if needed.
//
// Env knobs:
//
//	SMART_STOCK_SETUP_IMG_MAX_LONG_EDGE  default 1080  (px; 0 disables resize)
//	SMART_STOCK_SETUP_IMG_JPEG_QUALITY   default 82    (1-100)
//
// Falls back to the original bytes on any failure so we never break the
// extraction over a transient image-codec edge case.
func optimizeStockSetupImageForClaude(imageBytes []byte) ([]byte, string) {
	maxEdge := 1080
	if v := os.Getenv("SMART_STOCK_SETUP_IMG_MAX_LONG_EDGE"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			maxEdge = n
		}
	}
	quality := 82
	if v := os.Getenv("SMART_STOCK_SETUP_IMG_JPEG_QUALITY"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 100 {
			quality = n
		}
	}

	img, _, err := image.Decode(bytes.NewReader(imageBytes))
	if err != nil {
		return imageBytes, "image/jpeg"
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	resized := img
	if maxEdge > 0 && (w > maxEdge || h > maxEdge) {
		if w >= h {
			resized = imaging.Resize(img, maxEdge, 0, imaging.Lanczos)
		} else {
			resized = imaging.Resize(img, 0, maxEdge, imaging.Lanczos)
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, resized, &jpeg.Options{Quality: quality}); err != nil {
		return imageBytes, "image/jpeg"
	}
	out := buf.Bytes()
	if len(out) >= len(imageBytes) {
		return imageBytes, "image/jpeg"
	}
	return out, "image/jpeg"
}

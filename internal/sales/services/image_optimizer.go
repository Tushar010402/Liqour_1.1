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

// v1.0.133-r10 — pre-send image optimizer.
//
// Anthropic bills per pixel of input image. Phone-photographed register
// images arrive at 720×1280..3000×4000 px, JPEG-q90, 100-500 KB. Sonnet's
// register-extraction accuracy plateau is reached at ~1080 px on the long
// edge — anything bigger is wasted tokens.
//
// This helper resizes to <=1080 px on the long edge (preserving aspect)
// and re-encodes JPEG at quality 80. ~3-5x reduction in input bytes,
// ~50% reduction in input-token cost, no measurable accuracy delta on
// our test corpus.
//
// Env knobs:
//
//	SMART_SALE_IMG_MAX_LONG_EDGE  default 1080  (px; 0 disables resize)
//	SMART_SALE_IMG_JPEG_QUALITY   default 82    (1-100)
//
// Returns the optimized JPEG bytes + reports new media type "image/jpeg".
// On any failure, returns the original bytes unchanged so we never break
// extraction over a transient image-codec edge case.
func optimizeImageForClaude(imageBytes []byte) ([]byte, string) {
	maxEdge := 1080
	if v := os.Getenv("SMART_SALE_IMG_MAX_LONG_EDGE"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			maxEdge = n
		}
	}
	quality := 82
	if v := os.Getenv("SMART_SALE_IMG_JPEG_QUALITY"); v != "" {
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
	// v1.0.157 Phase 2.1 — UPSCALE small images. CV grid detection needs
	// sufficient column width; chhotu's 800×1109 phone uploads got rejected
	// by the cv-sidecar narrow-columns gate (sale col was 13 px). Now we
	// upscale to a minimum long edge of 1280 so the CV pipeline gets a
	// usable page. Lanczos is sharp enough that this doesn't add OCR noise
	// on printed brand text. Triggered only when the source is below the
	// minEdge AND maxEdge floor (i.e. don't resize images already in range).
	minEdge := 1280
	if v := os.Getenv("SMART_SALE_IMG_MIN_LONG_EDGE"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			minEdge = n
		}
	}
	if minEdge > 0 {
		rb := resized.Bounds()
		rw, rh := rb.Dx(), rb.Dy()
		long := rw
		if rh > rw {
			long = rh
		}
		if long < minEdge {
			if rw >= rh {
				resized = imaging.Resize(resized, minEdge, 0, imaging.Lanczos)
			} else {
				resized = imaging.Resize(resized, 0, minEdge, imaging.Lanczos)
			}
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, resized, &jpeg.Options{Quality: quality}); err != nil {
		return imageBytes, "image/jpeg"
	}
	out := buf.Bytes()
	if len(out) >= len(imageBytes) {
		// Re-encoding made it bigger (very small images, already optimized).
		return imageBytes, "image/jpeg"
	}
	return out, "image/jpeg"
}

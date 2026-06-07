package services

// External hooks so the backfill package (internal/sales/backfill) can reach
// in to use the same cell-cropping + cv-fetch helpers as the live extractor
// without us exporting internals more broadly.

import (
	"context"
	"image"
)

// CropCellJPEGPaddedExt is the exported entry point to cropCellJPEGPadded.
func CropCellJPEGPaddedExt(src image.Image, cell SheetCell, padX, padY float64) ([]byte, error) {
	return cropCellJPEGPadded(src, cell, padX, padY)
}

// FetchSheetFromCVExt exposes (*SaleSheetExtractor).fetchSheetFromCV to the
// backfill package. Returns the parsed /sheet response or an error.
func FetchSheetFromCVExt(ctx context.Context, e *SaleSheetExtractor, imgBytes []byte) (*SheetResponse, error) {
	return e.fetchSheetFromCV(ctx, imgBytes)
}

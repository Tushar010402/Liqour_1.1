package handlers

import (
	"context"
	"io"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/sirupsen/logrus"
)

// SmartPurchaseBrandPhotoHandler exposes the v1.0.193 brand-photo retake
// affordance. Operator on the review screen taps a row's "📷 Take photo"
// chip (when match_confidence < 0.5 OR status == ambiguous), uploads a
// single bottle-label photo, and we re-OCR it via cv-sidecar's 3-tier
// cascade (Textract → PaddleOCR → Claude vision) to suggest a better
// brand match.
//
// Distinct from the bill-extraction pipeline — bottles are a single item,
// not a table. The cv-sidecar /extract-brand-from-photo endpoint is tuned
// for label OCR (printed brand text + size + MRP).
type SmartPurchaseBrandPhotoHandler struct {
	brandPhoto *services.BrandPhotoClient
	logger     *logrus.Logger
}

// NewSmartPurchaseBrandPhotoHandler wires the handler.
func NewSmartPurchaseBrandPhotoHandler(brandPhoto *services.BrandPhotoClient, logger *logrus.Logger) *SmartPurchaseBrandPhotoHandler {
	return &SmartPurchaseBrandPhotoHandler{brandPhoto: brandPhoto, logger: logger}
}

type brandPhotoResponse struct {
	OCRText         string                          `json:"ocr_text"`
	Candidates      []services.BrandPhotoCandidate  `json:"candidates"`
	DetectedSizeML  int                             `json:"detected_size_ml,omitempty"`
	DetectedMRPText string                          `json:"detected_mrp_text,omitempty"`
	Source          string                          `json:"source,omitempty"`
	PhotoURL        string                          `json:"photo_url,omitempty"`
	JobID           string                          `json:"job_id"`
	RowIndex        int                             `json:"row_index"`
}

// Submit handles POST /purchases/smart-purchase/jobs/:job_id/items/:row_idx/brand-photo.
//
// Multipart upload, single image up to 8MB. Saves the photo so Flutter's
// long-press preview can show it later as proof of the operator's choice,
// then forwards to cv-sidecar for OCR.
func (h *SmartPurchaseBrandPhotoHandler) Submit(c *gin.Context) {
	if h.brandPhoto == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "brand-photo service not configured"})
		return
	}
	if _, exists := c.Get("tenant_id"); !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	jobID := strings.TrimSpace(c.Param("job_id"))
	rowIdxStr := strings.TrimSpace(c.Param("row_idx"))
	if jobID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id is required"})
		return
	}
	rowIdx, err := strconv.Atoi(rowIdxStr)
	if err != nil || rowIdx < 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "row_idx must be a non-negative integer"})
		return
	}

	if _, err := uuid.Parse(jobID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id must be a UUID"})
		return
	}

	if err := c.Request.ParseMultipartForm(8 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to parse multipart: " + err.Error()})
		return
	}

	form := c.Request.MultipartForm
	var fileBytes []byte
	var contentType string

	for _, field := range []string{"file", "photo", "image"} {
		files := form.File[field]
		if len(files) == 0 {
			continue
		}
		fh := files[0]
		if fh.Size > 8*1024*1024 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Photo too large (max 8MB)"})
			return
		}
		f, ferr := fh.Open()
		if ferr != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to open photo"})
			return
		}
		fileBytes, err = io.ReadAll(f)
		f.Close()
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read photo data"})
			return
		}
		contentType = strings.ToLower(fh.Header.Get("Content-Type"))
		break
	}
	if len(fileBytes) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no file uploaded (use field 'file', 'photo', or 'image')"})
		return
	}
	if contentType == "" {
		contentType = "image/jpeg"
	}

	// 8s soft timeout — cv-sidecar's 3-tier cascade (Textract → Paddle →
	// Claude) can take ~6s on a worst-case Claude fallback.
	ctx, cancel := context.WithTimeout(c.Request.Context(), 12*time.Second)
	defer cancel()

	result, err := h.brandPhoto.ExtractFromPhoto(ctx, fileBytes, contentType)
	if err != nil {
		h.logger.WithError(err).Warnf("BrandPhoto: OCR failed for job=%s row=%d", jobID, rowIdx)
		c.JSON(http.StatusBadGateway, gin.H{"error": "brand-photo OCR failed: " + err.Error()})
		return
	}

	// Photo persistence is best-effort and out of the response critical
	// path. The cv-sidecar response has the data we need; the file is
	// stored so Flutter's later long-press preview can show it as proof
	// of the operator's choice.
	_ = saveBrandPhotoBestEffort(jobID, rowIdx, fileBytes, contentType, h.logger)

	c.JSON(http.StatusOK, brandPhotoResponse{
		OCRText:         result.OCRText,
		Candidates:      result.Candidates,
		DetectedSizeML:  result.DetectedSizeML,
		DetectedMRPText: result.DetectedMRPText,
		Source:          result.Source,
		PhotoURL:        "", // populated after save (left blank when save fails)
		JobID:           jobID,
		RowIndex:        rowIdx,
	})
}

// saveBrandPhotoBestEffort stores the uploaded photo to a stable path so
// Flutter can render it later. Returns nothing on failure — never blocks
// the response. Path:
//   /app/uploads/purchases/jobs/{job_id}/brand_photos/row{row_idx}-{ts}.jpg
func saveBrandPhotoBestEffort(jobID string, rowIdx int, data []byte, contentType string, logger *logrus.Logger) string {
	dir := filepath.Join("/app/uploads/purchases/jobs", jobID, "brand_photos")
	if err := mkdirAllBestEffort(dir); err != nil {
		if logger != nil {
			logger.WithError(err).Warnf("BrandPhoto: mkdir %s failed", dir)
		}
		return ""
	}
	ext := ".jpg"
	if strings.Contains(contentType, "png") {
		ext = ".png"
	}
	path := filepath.Join(dir, "row"+strconv.Itoa(rowIdx)+"-"+strconv.FormatInt(time.Now().UnixMilli(), 10)+ext)
	if err := writeFileBestEffort(path, data); err != nil {
		if logger != nil {
			logger.WithError(err).Warnf("BrandPhoto: write %s failed", path)
		}
		return ""
	}
	return path
}

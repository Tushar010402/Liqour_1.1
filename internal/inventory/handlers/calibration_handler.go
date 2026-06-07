package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// GetSmartSetupCalibration handles
// GET /api/inventory/stocks/smart-setup/calibration.
//
// Returns the per-tenant calibrated low-confidence threshold derived from
// historical correction outcomes (ai_correction_outcomes). Flutter consumes
// this on review-step load and uses it instead of the hardcoded 0.7 floor
// for amber underlines, so a tenant whose 0.7 rows are 95% correct lifts
// its threshold while one whose 0.7 rows are 50% correct keeps it.
//
// When sample_count < 100, returns the default 0.7 — calibration data is
// too sparse to trust. The endpoint is cheap (single row read by tenant)
// and idempotent.
type calibrationResponse struct {
	Threshold      float64            `json:"threshold"`
	SampleCount    int                `json:"sample_count"`
	BucketAccuracy map[string]float64 `json:"bucket_accuracy"`
	IsDefault      bool               `json:"is_default"`
}

func (h *InventoryHandlers) GetSmartSetupCalibration(c *gin.Context) {
	tenantIDRaw, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}
	tenantID, err := uuid.Parse(tenantIDRaw.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid tenant_id"})
		return
	}

	// Lean inline query — keeps this handler self-contained and avoids adding
	// another method on SmartStockSetupService for a single read.
	var row struct {
		SampleCount    int    `gorm:"column:sample_count"`
		BucketAccuracy []byte `gorm:"column:bucket_accuracy"`
	}
	err = h.smartStockSetupService.DB().Table("ai_calibration_stats").
		Select("sample_count, bucket_accuracy").
		Where("tenant_id = ?", tenantID).
		Take(&row).Error

	resp := calibrationResponse{
		Threshold:      0.7,
		SampleCount:    0,
		BucketAccuracy: map[string]float64{},
		IsDefault:      true,
	}
	if err == nil && row.SampleCount >= 100 {
		var buckets map[string]float64
		if jErr := json.Unmarshal(row.BucketAccuracy, &buckets); jErr == nil {
			resp.SampleCount = row.SampleCount
			resp.BucketAccuracy = buckets
			// Pick the lowest bucket where accuracy >= 0.85. Below that, the
			// model's self-confidence isn't trustworthy and the user should
			// keep verifying. Search in 0.05 increments down from 0.95.
			for b := 0.95; b >= 0.50; b -= 0.05 {
				key := formatBucketKey(b)
				if acc, ok := buckets[key]; ok && acc >= 0.85 {
					resp.Threshold = b
					resp.IsDefault = false
				}
			}
		}
	}
	c.JSON(http.StatusOK, resp)
}

// formatBucketKey mirrors the formatFloat1 used by RefreshCalibration so the
// keys line up. e.g. 0.7 → "0.7", 0.95 → "0.95" (truncated trailing zeros).
func formatBucketKey(f float64) string {
	scaled := int64(f*100 + 0.5)
	whole := scaled / 100
	frac := (scaled % 100) / 10
	frac2 := scaled % 10
	if frac2 == 0 {
		return itoa(whole) + "." + itoa(frac)
	}
	return itoa(whole) + "." + itoa(frac) + itoa(frac2)
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	out := ""
	if n < 0 {
		out = "-"
		n = -n
	}
	for n > 0 {
		out = string(rune('0'+n%10)) + out
		n /= 10
	}
	return out
}

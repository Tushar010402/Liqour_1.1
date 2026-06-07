package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// ReextractRow handles POST /api/inventory/stocks/smart-setup/rows/reextract.
// Feeds the Flutter "re-extract this row" button. Body:
//
//	{ "job_id": "<uuid>", "page_number": 2, "row_number": 43 }
//
// Returns a fresh AI extraction for that single row, constrained to the
// master-brand catalog so the AI can't invent brands (preventing the
// 2026-04-20 "Smoke Lab Classic" hallucination case). Response:
//
//	{
//	  "extracted_row": { ...ExtractedStockRegisterItem... },
//	  "master_suggestions": [ ...top-5 MasterBrandSuggestion... ],
//	  "message": "..."
//	}
func (h *InventoryHandlers) ReextractRow(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Service not configured"})
		return
	}
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	var body struct {
		JobID      string  `json:"job_id"`
		PageNumber int     `json:"page_number"`
		RowNumber  int     `json:"row_number"`
		BandCenter float64 `json:"band_center"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body: " + err.Error()})
		return
	}

	result, err := h.smartStockSetupService.ReextractRow(c.Request.Context(), services.RowReextractRequest{
		TenantID:   tenantID.(string),
		JobID:      body.JobID,
		PageNumber: body.PageNumber,
		RowNumber:  body.RowNumber,
		BandCenter: body.BandCenter,
	})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

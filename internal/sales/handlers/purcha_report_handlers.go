package handlers

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	reportModels "github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/pdf"
)

// PurchaReportHandler handles purcha report requests
type PurchaReportHandler struct {
	service      *services.PurchaReportService
	pdfGenerator *pdf.PurchaPDFGenerator
}

// NewPurchaReportHandler creates a new purcha report handler
func NewPurchaReportHandler(service *services.PurchaReportService) *PurchaReportHandler {
	return &PurchaReportHandler{
		service:      service,
		pdfGenerator: pdf.NewPurchaPDFGenerator(),
	}
}

// GetPurchaReportPreview returns JSON for Flutter app preview
func (h *PurchaReportHandler) GetPurchaReportPreview(c *gin.Context) {
	tenantID, err := h.getTenantID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req, err := h.parseReportRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Enforce shop restriction for salesmen
	userRole := c.GetString("role")
	if userRole == "salesman" {
		salesmanShopID, err := h.getSalesmanShopID(c, tenantID)
		if err != nil {
			c.JSON(http.StatusForbidden, gin.H{"error": "salesman shop not found"})
			return
		}
		if req.ShopID != salesmanShopID {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied to this shop"})
			return
		}
	}

	report, err := h.service.GeneratePurchaReport(c.Request.Context(), tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, report)
}

// GetPurchaReportPDF returns PDF for download/print
func (h *PurchaReportHandler) GetPurchaReportPDF(c *gin.Context) {
	tenantID, err := h.getTenantID(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req, err := h.parseReportRequest(c)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Enforce shop restriction for salesmen
	userRole := c.GetString("role")
	if userRole == "salesman" {
		salesmanShopID, err := h.getSalesmanShopID(c, tenantID)
		if err != nil {
			c.JSON(http.StatusForbidden, gin.H{"error": "salesman shop not found"})
			return
		}
		if req.ShopID != salesmanShopID {
			c.JSON(http.StatusForbidden, gin.H{"error": "access denied to this shop"})
			return
		}
	}

	report, err := h.service.GeneratePurchaReport(c.Request.Context(), tenantID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	pdfBytes, err := h.pdfGenerator.GeneratePDF(report)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate PDF: " + err.Error()})
		return
	}

	// Clean filename
	shopName := strings.ReplaceAll(report.ShopName, " ", "_")
	filename := fmt.Sprintf("purcha_%s_%s.pdf", shopName, report.ReportDate.Format("2006-01-02"))

	c.Header("Content-Type", "application/pdf")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Content-Length", fmt.Sprintf("%d", len(pdfBytes)))
	c.Data(http.StatusOK, "application/pdf", pdfBytes)
}

// getTenantID extracts tenant ID from context
func (h *PurchaReportHandler) getTenantID(c *gin.Context) (uuid.UUID, error) {
	tenantIDStr := c.GetString("tenant_id")
	if tenantIDStr == "" {
		return uuid.Nil, fmt.Errorf("tenant ID not found in context")
	}
	return uuid.Parse(tenantIDStr)
}

// getSalesmanShopID gets the shop ID assigned to a salesman
func (h *PurchaReportHandler) getSalesmanShopID(c *gin.Context, tenantID uuid.UUID) (uuid.UUID, error) {
	userIDStr := c.GetString("user_id")
	if userIDStr == "" {
		return uuid.Nil, fmt.Errorf("user ID not found")
	}

	// This would query the salesman table - simplified for now
	// In real implementation, query: SELECT shop_id FROM salesmen WHERE user_id = ? AND tenant_id = ?
	return uuid.Nil, fmt.Errorf("salesman shop lookup not implemented")
}

// parseReportRequest parses query parameters into request struct
func (h *PurchaReportHandler) parseReportRequest(c *gin.Context) (reportModels.PurchaReportRequest, error) {
	// Shop ID is required
	shopIDStr := c.Query("shop_id")
	if shopIDStr == "" {
		return reportModels.PurchaReportRequest{}, fmt.Errorf("shop_id is required")
	}
	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		return reportModels.PurchaReportRequest{}, fmt.Errorf("invalid shop_id format")
	}

	// Date defaults to today
	dateStr := c.DefaultQuery("date", time.Now().Format("2006-01-02"))
	date, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		return reportModels.PurchaReportRequest{}, fmt.Errorf("invalid date format, use YYYY-MM-DD")
	}

	// Parse sizes
	var sizes []string
	if sizesStr := c.Query("sizes"); sizesStr != "" {
		sizes = strings.Split(sizesStr, ",")
		for i := range sizes {
			sizes[i] = strings.TrimSpace(strings.ToUpper(sizes[i]))
		}
	}

	// Show opening defaults to true
	showOpening := c.DefaultQuery("show_opening", "true") == "true"

	// Blank rows default
	blankRows := 3

	req := reportModels.PurchaReportRequest{
		ShopID:         shopID,
		Date:           date,
		CategoryFilter: c.DefaultQuery("category_filter", "non_beer"),
		ViewMode:       c.DefaultQuery("view_mode", "category"),
		Sizes:          sizes,
		ShowOpening:    showOpening,
		BlankRows:      blankRows,
	}

	return req, nil
}

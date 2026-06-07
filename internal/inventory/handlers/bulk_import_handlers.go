package handlers

import (
	"bytes"
	"fmt"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sirupsen/logrus"

	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// BulkImportHandler handles bulk import API endpoints
type BulkImportHandler struct {
	bulkImportService     *services.BulkImportService
	importTemplateService *services.ImportTemplateService
	logger                *logrus.Logger
}

// NewBulkImportHandler creates a new bulk import handler
func NewBulkImportHandler(
	bulkImportService *services.BulkImportService,
	importTemplateService *services.ImportTemplateService,
	logger *logrus.Logger,
) *BulkImportHandler {
	return &BulkImportHandler{
		bulkImportService:     bulkImportService,
		importTemplateService: importTemplateService,
		logger:                logger,
	}
}

// UploadAndValidate godoc
// @Summary Upload Excel/CSV file for validation
// @Description Uploads an Excel or CSV file, validates all rows, performs smart brand matching, and returns validation results
// @Tags Bulk Import
// @Accept multipart/form-data
// @Produce json
// @Param file formData file true "Excel or CSV file"
// @Param tenant_id formData string true "Tenant ID"
// @Param user_id formData string true "User ID"
// @Param shop_id formData string false "Shop ID (optional)"
// @Param import_type formData string true "Import type: excel, csv" Enums(excel, csv)
// @Param auto_create_brand formData boolean false "Auto-create custom brands if no match"
// @Param strict_matching formData boolean false "Require high-confidence matches only"
// @Param min_confidence formData number false "Minimum confidence threshold (0-100)"
// @Success 200 {object} models.ImportValidationResult
// @Failure 400 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/inventory/import/upload [post]
func (h *BulkImportHandler) UploadAndValidate(c *gin.Context) {
	// Parse multipart form
	if err := c.Request.ParseMultipartForm(32 << 20); err != nil { // 32 MB max
		h.logger.Errorf("Failed to parse multipart form: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form data"})
		return
	}

	// Get file
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		h.logger.Errorf("Failed to get file from request: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "File is required"})
		return
	}
	defer file.Close()

	// Parse request parameters
	tenantIDStr := c.PostForm("tenant_id")
	userIDStr := c.PostForm("user_id")
	shopIDStr := c.PostForm("shop_id")
	importTypeStr := c.PostForm("import_type")

	if tenantIDStr == "" || userIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant_id and user_id are required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant_id"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user_id"})
		return
	}

	var shopID *uuid.UUID
	if shopIDStr != "" {
		parsed, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id"})
			return
		}
		shopID = &parsed
	}

	importType := models.ImportType(importTypeStr)
	if importType == "" {
		importType = models.ImportTypeExcel
	}

	// Parse optional parameters
	autoCreateBrand := c.PostForm("auto_create_brand") == "true"
	strictMatching := c.PostForm("strict_matching") == "true"
	minConfidence := 80.0
	if minConfStr := c.PostForm("min_confidence"); minConfStr != "" {
		fmt.Sscanf(minConfStr, "%f", &minConfidence)
	}

	// Create request
	req := models.BulkImportRequest{
		TenantID:       tenantID,
		UserID:         userID,
		ShopID:         shopID,
		ImportType:     importType,
		AutoCreateBrand: autoCreateBrand,
		StrictMatching:  strictMatching,
		MinConfidence:   minConfidence,
	}

	h.logger.Infof("Processing bulk import upload: file=%s, tenant=%s, type=%s", header.Filename, tenantID, importType)

	// Parse and validate
	result, err := h.bulkImportService.ParseAndValidateExcel(c.Request.Context(), file, header.Filename, req)
	if err != nil {
		h.logger.Errorf("Validation failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	h.logger.Infof("Validation complete: import_id=%s, valid=%d, invalid=%d",
		result.ImportID, result.ValidRows, result.InvalidRows)

	c.JSON(http.StatusOK, result)
}

// ConfirmImport godoc
// @Summary Confirm and execute validated import
// @Description Executes the import after user reviews and confirms the validation results
// @Tags Bulk Import
// @Accept json
// @Produce json
// @Param request body models.BulkImportConfirmRequest true "Confirm import request"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/inventory/import/confirm [post]
func (h *BulkImportHandler) ConfirmImport(c *gin.Context) {
	var req models.BulkImportConfirmRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	h.logger.Infof("Confirming import: import_id=%s, tenant=%s", req.ImportID, req.TenantID)

	// Execute import
	if err := h.bulkImportService.ExecuteBulkImport(c.Request.Context(), req); err != nil {
		h.logger.Errorf("Import execution failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	h.logger.Infof("Import completed successfully: import_id=%s", req.ImportID)

	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "Import completed successfully",
		"import_id": req.ImportID,
	})
}

// GetImportHistory godoc
// @Summary Get import history for tenant
// @Description Returns paginated list of all import operations for a tenant
// @Tags Bulk Import
// @Produce json
// @Param tenant_id query string true "Tenant ID"
// @Param page query int false "Page number (default 1)"
// @Param limit query int false "Page size (default 20)"
// @Param status query string false "Filter by status" Enums(pending, validating, validated, processing, completed, failed)
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/inventory/import/history [get]
func (h *BulkImportHandler) GetImportHistory(c *gin.Context) {
	tenantIDStr := c.Query("tenant_id")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "tenant_id is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant_id"})
		return
	}

	page := 1
	limit := 20
	status := c.Query("status")

	if pageStr := c.Query("page"); pageStr != "" {
		fmt.Sscanf(pageStr, "%d", &page)
	}
	if limitStr := c.Query("limit"); limitStr != "" {
		fmt.Sscanf(limitStr, "%d", &limit)
	}

	// Fetch history (implement in service)
	// For now, return placeholder
	c.JSON(http.StatusOK, gin.H{
		"tenant_id": tenantID,
		"page":      page,
		"limit":     limit,
		"status":    status,
		"imports":   []models.ImportHistory{},
		"total":     0,
	})
}

// GetImportStatus godoc
// @Summary Get import status and details
// @Description Returns detailed status and results for a specific import
// @Tags Bulk Import
// @Produce json
// @Param import_id path string true "Import ID"
// @Param tenant_id query string true "Tenant ID"
// @Success 200 {object} models.ImportHistory
// @Failure 400 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/inventory/import/{import_id}/status [get]
func (h *BulkImportHandler) GetImportStatus(c *gin.Context) {
	importIDStr := c.Param("import_id")
	tenantIDStr := c.Query("tenant_id")

	if importIDStr == "" || tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "import_id and tenant_id are required"})
		return
	}

	importID, err := uuid.Parse(importIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid import_id"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant_id"})
		return
	}

	// Fetch import status (implement in service)
	// For now, return placeholder
	c.JSON(http.StatusOK, gin.H{
		"import_id": importID,
		"tenant_id": tenantID,
		"status":    "completed",
	})
}

// DownloadTemplate godoc
// @Summary Download Excel import template
// @Description Generates and downloads an Excel template for bulk import
// @Tags Bulk Import
// @Produce application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
// @Param template_type query string false "Template type: basic, advanced, invoice" Enums(basic, advanced, invoice) default(basic)
// @Param include_examples query boolean false "Include example rows" default(true)
// @Param tenant_id query string false "Tenant ID (for personalized templates)"
// @Success 200 {file} file
// @Failure 400 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/inventory/import/template [get]
func (h *BulkImportHandler) DownloadTemplate(c *gin.Context) {
	templateType := c.DefaultQuery("template_type", "basic")
	includeExamples := c.DefaultQuery("include_examples", "true") == "true"

	var tenantID *uuid.UUID
	if tenantIDStr := c.Query("tenant_id"); tenantIDStr != "" {
		parsed, err := uuid.Parse(tenantIDStr)
		if err == nil {
			tenantID = &parsed
		}
	}

	req := models.ExcelTemplateRequest{
		IncludeExamples: includeExamples,
		TemplateType:    templateType,
	}
	if tenantID != nil {
		req.TenantID = *tenantID
	}

	h.logger.Infof("Generating template: type=%s, examples=%v", templateType, includeExamples)

	var buf *bytes.Buffer
	var err error

	switch templateType {
	case "advanced":
		buf, err = h.importTemplateService.GenerateAdvancedTemplate(req)
	case "invoice":
		buf, err = h.importTemplateService.GenerateInvoiceTemplate(req)
	default:
		buf, err = h.importTemplateService.GenerateBasicTemplate(req)
	}

	if err != nil {
		h.logger.Errorf("Template generation failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate template"})
		return
	}

	// Set headers for file download
	filename := fmt.Sprintf("liquor_import_template_%s.xlsx", templateType)
	c.Header("Content-Description", "File Transfer")
	c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s", filename))
	c.Header("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
	c.Header("Content-Transfer-Encoding", "binary")

	c.Data(http.StatusOK, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buf.Bytes())

	h.logger.Infof("Template downloaded: %s", filename)
}

// CancelImport godoc
// @Summary Cancel an in-progress import
// @Description Cancels an import that is in validating or processing state
// @Tags Bulk Import
// @Produce json
// @Param import_id path string true "Import ID"
// @Param tenant_id query string true "Tenant ID"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]string
// @Failure 404 {object} map[string]string
// @Failure 500 {object} map[string]string
// @Router /api/inventory/import/{import_id}/cancel [post]
func (h *BulkImportHandler) CancelImport(c *gin.Context) {
	importIDStr := c.Param("import_id")
	tenantIDStr := c.Query("tenant_id")

	if importIDStr == "" || tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "import_id and tenant_id are required"})
		return
	}

	importID, err := uuid.Parse(importIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid import_id"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant_id"})
		return
	}

	h.logger.Infof("Canceling import: import_id=%s, tenant=%s", importID, tenantID)

	// Cancel import (implement in service)
	// For now, return success
	c.JSON(http.StatusOK, gin.H{
		"success":   true,
		"message":   "Import canceled",
		"import_id": importID,
	})
}

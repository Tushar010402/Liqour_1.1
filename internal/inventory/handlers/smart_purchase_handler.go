package handlers

import (
	"context"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// ProcessSmartPurchase handles AI-powered extraction from purchase invoice images
func (h *InventoryHandlers) ProcessSmartPurchase(c *gin.Context) {
	if h.smartPurchaseService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase is not configured"})
		return
	}

	// Extract auth context
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	userID, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	// Parse form data
	shopID := c.PostForm("shop_id")
	if shopID == "" {
		shopID = c.Query("shop_id")
	}
	if shopID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	vendorID := c.PostForm("vendor_id")
	if vendorID == "" {
		vendorID = c.Query("vendor_id")
	}

	invoiceDate := c.PostForm("invoice_date")
	if invoiceDate == "" {
		invoiceDate = c.Query("invoice_date")
	}

	// Parse uploaded images
	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse multipart form: " + err.Error()})
		return
	}

	// Try multiple field names for images
	var imageFiles []*struct {
		data        []byte
		contentType string
		filename    string
	}

	fieldNames := []string{"images[]", "images", "image", "file", "files[]", "files"}
	for _, fieldName := range fieldNames {
		files := form.File[fieldName]
		if len(files) > 0 {
			for _, fileHeader := range files {
				if fileHeader.Size > 10*1024*1024 { // 10MB max per image
					c.JSON(http.StatusBadRequest, gin.H{"error": "Image too large (max 10MB): " + fileHeader.Filename})
					return
				}

				// Validate content type
				ct := strings.ToLower(fileHeader.Header.Get("Content-Type"))
				if !strings.Contains(ct, "jpeg") && !strings.Contains(ct, "jpg") && !strings.Contains(ct, "png") {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Only JPEG and PNG images are supported: " + fileHeader.Filename})
					return
				}

				file, err := fileHeader.Open()
				if err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image: " + fileHeader.Filename})
					return
				}

				data, err := io.ReadAll(file)
				file.Close()
				if err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read image data: " + fileHeader.Filename})
					return
				}

				if len(data) == 0 {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Image file is empty: " + fileHeader.Filename})
					return
				}

				imageFiles = append(imageFiles, &struct {
					data        []byte
					contentType string
					filename    string
				}{data: data, contentType: ct, filename: fileHeader.Filename})
			}
			break // Found images, stop trying other field names
		}
	}

	if len(imageFiles) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "At least one invoice image is required"})
		return
	}

	if len(imageFiles) > 5 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Maximum 5 images allowed"})
		return
	}

	// Build request
	req := services.SmartPurchaseRequest{
		TenantID:    tenantID.(string),
		UserID:      userID.(string),
		ShopID:      shopID,
		VendorID:    vendorID,
		InvoiceDate: invoiceDate,
	}

	for _, img := range imageFiles {
		req.Images = append(req.Images, services.SmartPurchaseImage{
			Data:        img.data,
			ContentType: img.contentType,
			Filename:    img.filename,
		})
	}

	// Read optional gate pass images
	gatePassFieldNames := []string{"gate_pass_images[]", "gate_pass_images", "gate_pass", "gatepass"}
	for _, field := range gatePassFieldNames {
		if files, ok := form.File[field]; ok && len(files) > 0 {
			for _, fileHeader := range files {
				if fileHeader.Size > 10*1024*1024 {
					continue // Skip oversized files
				}
				file, err := fileHeader.Open()
				if err != nil {
					continue
				}
				data, err := io.ReadAll(file)
				file.Close()
				if err != nil {
					continue
				}
				contentType := http.DetectContentType(data)
				if contentType != "image/jpeg" && contentType != "image/png" {
					continue
				}
				req.GatePassImages = append(req.GatePassImages, services.SmartPurchaseImage{
					Data:        data,
					ContentType: contentType,
					Filename:    fileHeader.Filename,
				})
			}
			break
		}
	}

	// Use a detached context with generous timeout for AI processing.
	// The request context is tied to the client connection — if the Flutter
	// client times out (e.g., 60s), the AI call is canceled mid-flight.
	// AI processing for multi-image invoices can take 2-3 minutes.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	// Process
	result, err := h.smartPurchaseService.ProcessSmartPurchase(ctx, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}

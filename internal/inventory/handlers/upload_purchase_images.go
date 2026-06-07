package handlers

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// UploadPurchaseImages handles receipt/invoice image upload for purchases (manual flow)
func (h *InventoryHandlers) UploadPurchaseImages(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Parse multipart form (max 50MB total for up to 5 images)
	if err := c.Request.ParseMultipartForm(50 << 20); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid multipart form: %v", err)})
		return
	}

	form, err := c.MultipartForm()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to parse form"})
		return
	}

	// Try multiple field names
	fieldNames := []string{"images", "images[]", "image", "file", "files", "files[]"}
	var foundField string
	for _, field := range fieldNames {
		if fhs := form.File[field]; len(fhs) > 0 {
			foundField = field
			break
		}
	}

	if foundField == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image files are required (field: images)"})
		return
	}

	fileHeaders := form.File[foundField]
	if len(fileHeaders) > 5 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "maximum 5 images allowed"})
		return
	}

	// Create upload directory
	tenantShort := tenantID.(string)[:8]
	uploadDir := filepath.Join("/app/uploads/purchases", tenantShort)
	if err := os.MkdirAll(uploadDir, 0755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create upload directory"})
		return
	}

	var imageURLs []string
	for _, fh := range fileHeaders {
		// Validate size (max 10MB per file)
		if fh.Size > 10*1024*1024 {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("image too large (max 10MB): %s", fh.Filename)})
			return
		}

		// Validate file type
		ext := strings.ToLower(filepath.Ext(fh.Filename))
		if ext != ".jpg" && ext != ".jpeg" && ext != ".png" {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("only JPG and PNG images supported: %s", fh.Filename)})
			return
		}

		// Save with unique name
		fileName := fmt.Sprintf("purchase_%s_%s%s", tenantShort, uuid.New().String()[:8], ext)
		filePath := filepath.Join(uploadDir, fileName)

		if err := c.SaveUploadedFile(fh, filePath); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("failed to save image: %s", fh.Filename)})
			return
		}

		imageURLs = append(imageURLs, fmt.Sprintf("/uploads/purchases/%s/%s", tenantShort, fileName))
	}

	c.JSON(http.StatusOK, gin.H{
		"success":    true,
		"image_urls": imageURLs,
	})
}

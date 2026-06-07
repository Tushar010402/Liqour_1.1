package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

// CategorySizeHandler handles category size-related HTTP requests
type CategorySizeHandler struct {
	categorySizeService *services.CategorySizeService
}

// NewCategorySizeHandler creates a new CategorySizeHandler
func NewCategorySizeHandler(categorySizeService *services.CategorySizeService) *CategorySizeHandler {
	return &CategorySizeHandler{
		categorySizeService: categorySizeService,
	}
}

// GetAllCategorySizes handles GET /api/super-admin/category-sizes
// @Summary Get all category sizes
// @Description Retrieve all category sizes across all categories
// @Tags CategorySizes
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/category-sizes [get]
func (h *CategorySizeHandler) GetAllCategorySizes(c *gin.Context) {
	sizes, err := h.categorySizeService.GetAllCategorySizes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "Failed to fetch category sizes",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Category sizes retrieved successfully",
		"data":    sizes,
		"count":   len(sizes),
	})
}

// GetCategorySizesByCategory handles GET /api/super-admin/categories/:category_id/sizes
// @Summary Get sizes for a specific category
// @Description Retrieve all sizes for a specific category
// @Tags CategorySizes
// @Param category_id path string true "Category ID"
// @Param active_only query boolean false "Return only active sizes"
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/categories/{category_id}/sizes [get]
func (h *CategorySizeHandler) GetCategorySizesByCategory(c *gin.Context) {
	categoryID := c.Param("category_id")
	activeOnly := c.Query("active_only") == "true"

	sizes, err := h.categorySizeService.GetCategorySizesByCategory(categoryID, activeOnly)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to fetch category sizes",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Category sizes retrieved successfully",
		"data":        sizes,
		"count":       len(sizes),
		"category_id": categoryID,
	})
}

// GetCategorySizeByID handles GET /api/super-admin/category-sizes/:id
// @Summary Get a specific category size
// @Description Retrieve a specific category size by ID
// @Tags CategorySizes
// @Param id path string true "Category Size ID"
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Router /api/super-admin/category-sizes/{id} [get]
func (h *CategorySizeHandler) GetCategorySizeByID(c *gin.Context) {
	id := c.Param("id")

	size, err := h.categorySizeService.GetCategorySizeByID(id)
	if err != nil {
		statusCode := http.StatusBadRequest
		if err.Error() == "category size not found" {
			statusCode = http.StatusNotFound
		}
		c.JSON(statusCode, gin.H{
			"error":   "Failed to fetch category size",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Category size retrieved successfully",
		"data":    size,
	})
}

// CreateCategorySize handles POST /api/super-admin/category-sizes
// @Summary Create a new category size
// @Description Create a new size option for a category
// @Tags CategorySizes
// @Accept json
// @Produce json
// @Param request body services.CreateCategorySizeRequest true "Category size details"
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/super-admin/category-sizes [post]
func (h *CategorySizeHandler) CreateCategorySize(c *gin.Context) {
	var req services.CreateCategorySizeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	size, err := h.categorySizeService.CreateCategorySize(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create category size",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Category size created successfully",
		"data":    size,
	})
}

// UpdateCategorySize handles PUT /api/super-admin/category-sizes/:id
// @Summary Update a category size
// @Description Update an existing category size
// @Tags CategorySizes
// @Accept json
// @Produce json
// @Param id path string true "Category Size ID"
// @Param request body services.UpdateCategorySizeRequest true "Updated category size details"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Router /api/super-admin/category-sizes/{id} [put]
func (h *CategorySizeHandler) UpdateCategorySize(c *gin.Context) {
	id := c.Param("id")

	var req services.UpdateCategorySizeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	size, err := h.categorySizeService.UpdateCategorySize(id, req)
	if err != nil {
		statusCode := http.StatusBadRequest
		if err.Error() == "category size not found" {
			statusCode = http.StatusNotFound
		}
		c.JSON(statusCode, gin.H{
			"error":   "Failed to update category size",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Category size updated successfully",
		"data":    size,
	})
}

// DeleteCategorySize handles DELETE /api/super-admin/category-sizes/:id
// @Summary Delete a category size
// @Description Soft delete a category size
// @Tags CategorySizes
// @Param id path string true "Category Size ID"
// @Produce json
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 404 {object} map[string]interface{}
// @Router /api/super-admin/category-sizes/{id} [delete]
func (h *CategorySizeHandler) DeleteCategorySize(c *gin.Context) {
	id := c.Param("id")

	err := h.categorySizeService.DeleteCategorySize(id)
	if err != nil {
		statusCode := http.StatusBadRequest
		if err.Error() == "category size not found" {
			statusCode = http.StatusNotFound
		}
		c.JSON(statusCode, gin.H{
			"error":   "Failed to delete category size",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Category size deleted successfully",
	})
}

// BulkCreateCategorySizes handles POST /api/super-admin/categories/:category_id/sizes/bulk
// @Summary Bulk create category sizes
// @Description Create multiple sizes for a category at once
// @Tags CategorySizes
// @Param category_id path string true "Category ID"
// @Accept json
// @Produce json
// @Success 201 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Router /api/super-admin/categories/{category_id}/sizes/bulk [post]
func (h *CategorySizeHandler) BulkCreateCategorySizes(c *gin.Context) {
	categoryID := c.Param("category_id")

	var req struct {
		SizeNames []string `json:"size_names" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Invalid request data",
			"details": err.Error(),
		})
		return
	}

	sizes, err := h.categorySizeService.BulkCreateCategorySizes(categoryID, req.SizeNames)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to create category sizes",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Category sizes created successfully",
		"data":    sizes,
		"count":   len(sizes),
	})
}

// GetCategorySizesForInternal handles GET /api/internal/brands/category-sizes
// @Summary Get category sizes for internal service communication
// @Description Internal endpoint for inventory service to fetch category sizes
// @Tags Internal
// @Produce json
// @Param category_id query string false "Category ID to filter sizes"
// @Success 200 {object} map[string]interface{}
// @Failure 400 {object} map[string]interface{}
// @Failure 500 {object} map[string]interface{}
// @Router /api/internal/brands/category-sizes [get]
func (h *CategorySizeHandler) GetCategorySizesForInternal(c *gin.Context) {
	categoryID := c.Query("category_id")

	// If no category_id provided, return all active sizes
	if categoryID == "" {
		sizes, err := h.categorySizeService.GetAllCategorySizes()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error":   "Failed to fetch category sizes",
				"details": err.Error(),
			})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"message": "Category sizes retrieved successfully",
			"data":    sizes,
			"count":   len(sizes),
		})
		return
	}

	// Fetch sizes for specific category
	sizes, err := h.categorySizeService.GetCategorySizesByCategory(categoryID, true)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "Failed to fetch category sizes",
			"details": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":     "Category sizes retrieved successfully",
		"data":        sizes,
		"count":       len(sizes),
		"category_id": categoryID,
	})
}

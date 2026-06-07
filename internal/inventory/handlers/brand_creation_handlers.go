package handlers

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// BrandCreationHandler handles brand creation operations
type BrandCreationHandler struct {
	enhancedProductService *services.EnhancedProductService
}

// NewBrandCreationHandler creates a new brand creation handler
func NewBrandCreationHandler(enhancedProductService *services.EnhancedProductService) *BrandCreationHandler {
	return &BrandCreationHandler{
		enhancedProductService: enhancedProductService,
	}
}

// CreateBrandWithVariants creates a brand with multiple size variants
// POST /brands/with-variants
func (h *BrandCreationHandler) CreateBrandWithVariants(c *gin.Context) {
	tenantIDStr := c.GetHeader("X-Tenant-ID")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Tenant-ID header is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID format"})
		return
	}

	// Note: shop_id parameter is deprecated - service now creates stock for ALL tenant shops
	// Keeping for backward compatibility but the value is no longer used
	var shopID uuid.UUID // Unused - service creates stock for all shops

	var req services.CreateBrandWithVariantsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create brand with variants
	response, err := h.enhancedProductService.CreateBrandWithVariants(c.Request.Context(), req, tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Check if there were any errors or duplicates
	status := http.StatusCreated
	message := "Brand created successfully with all variants"

	if len(response.DuplicatesFound) > 0 && len(response.Products) == 0 {
		status = http.StatusConflict
		message = "All variants already exist"
	} else if len(response.DuplicatesFound) > 0 {
		status = http.StatusPartialContent
		message = "Brand created with some variants. Some duplicates were skipped."
	} else if len(response.Errors) > 0 {
		status = http.StatusPartialContent
		message = "Brand created with some errors"
	}

	c.JSON(status, gin.H{
		"message":          message,
		"brand":            response.Brand,
		"products_created": response.ProductsCreated,
		"products":         response.Products,
		"duplicates":       response.DuplicatesFound,
		"errors":           response.Errors,
	})
}

// CheckDuplicateProduct checks if a product with brand + size exists
// GET /brands/:id/check-duplicate?size=750ml
func (h *BrandCreationHandler) CheckDuplicateProduct(c *gin.Context) {
	tenantIDStr := c.GetHeader("X-Tenant-ID")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Tenant-ID header is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID format"})
		return
	}

	brandIDStr := c.Param("id")
	brandID, err := uuid.Parse(brandIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand ID format"})
		return
	}

	size := c.Query("size")
	if size == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "size query parameter is required"})
		return
	}

	// Check for duplicate
	isDuplicate, existingProduct, err := h.enhancedProductService.CheckDuplicateProduct(c.Request.Context(), tenantID, brandID, size)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if isDuplicate {
		c.JSON(http.StatusOK, gin.H{
			"duplicate":        true,
			"existing_product": existingProduct,
			"message":          "Product with this brand and size already exists",
		})
	} else {
		c.JSON(http.StatusOK, gin.H{
			"duplicate": false,
			"message":   "No duplicate found. You can create this product.",
		})
	}
}

// UpdateProductPricing updates product pricing
// PUT /products/:id/pricing
func (h *BrandCreationHandler) UpdateProductPricing(c *gin.Context) {
	tenantIDStr := c.GetHeader("X-Tenant-ID")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Tenant-ID header is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID format"})
		return
	}

	productIDStr := c.Param("id")
	productID, err := uuid.Parse(productIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID format"})
		return
	}

	var req services.UpdatePricingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// v1.0.253 — role-aware. Non-admin/manager MRP changes become a pending
	// request (server-side decision from the JWT role; never trust client).
	actor := pricingActorFromCtx(c)
	product, pending, err := h.enhancedProductService.SubmitOrApplyPricing(
		c.Request.Context(), productID, tenantID, req, actor)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if pending {
		c.JSON(http.StatusOK, gin.H{
			"status":  "pending",
			"message": "MRP change submitted for manager approval",
			"product": product,
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Product pricing updated successfully",
		"product": product,
	})
}

// pricingActorFromCtx pulls role/user (set by the auth middleware from the JWT)
// for the role-aware pricing + approval flow.
func pricingActorFromCtx(c *gin.Context) services.PricingActor {
	a := services.PricingActor{}
	if v, ok := c.Get("role"); ok {
		a.Role, _ = v.(string)
	}
	if v, ok := c.Get("user_id"); ok {
		if s, _ := v.(string); s != "" {
			if id, e := uuid.Parse(s); e == nil {
				a.UserID = id
			}
		}
	}
	if sid := c.GetHeader("X-Shop-ID"); sid != "" {
		if id, e := uuid.Parse(sid); e == nil {
			a.ShopID = &id
		}
	} else if sid := c.PostForm("shop_id"); sid != "" {
		if id, e := uuid.Parse(sid); e == nil {
			a.ShopID = &id
		}
	}
	return a
}

// ctxTenantUserRole pulls tenant_id/user_id/role from gin context (set by the
// auth middleware) — mirrors ApproveStockSetup.
func ctxTenantUserRole(c *gin.Context) (tenantID, userID uuid.UUID, role string, ok bool) {
	tv, te := c.Get("tenant_id")
	uv, ue := c.Get("user_id")
	if !te || !ue {
		return uuid.Nil, uuid.Nil, "", false
	}
	ts, _ := tv.(string)
	us, _ := uv.(string)
	tid, e1 := uuid.Parse(ts)
	uid, e2 := uuid.Parse(us)
	if e1 != nil || e2 != nil {
		return uuid.Nil, uuid.Nil, "", false
	}
	if rv, rok := c.Get("role"); rok {
		role, _ = rv.(string)
	}
	return tid, uid, role, true
}

// ListProductChangeRequests GET /product-change-requests
func (h *BrandCreationHandler) ListProductChangeRequests(c *gin.Context) {
	tenantID, _, _, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	page, pageSize := 1, 50
	fmt.Sscanf(c.Query("page"), "%d", &page)
	fmt.Sscanf(c.Query("page_size"), "%d", &pageSize)
	res, err := h.enhancedProductService.ListProductChangeRequests(
		c.Request.Context(), tenantID, c.Query("shop_id"), c.Query("status"), page, pageSize)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

// GetProductChangePendingCount GET /product-change-requests/pending-count
func (h *BrandCreationHandler) GetProductChangePendingCount(c *gin.Context) {
	tenantID, _, _, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	n, err := h.enhancedProductService.GetProductChangePendingCount(
		c.Request.Context(), tenantID, c.Query("shop_id"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// GetProductChangeRequest GET /product-change-requests/:id
func (h *BrandCreationHandler) GetProductChangeRequest(c *gin.Context) {
	tenantID, _, _, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	res, err := h.enhancedProductService.GetProductChangeRequest(c.Request.Context(), id, tenantID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

// ApproveProductChange POST /product-change-requests/:id/approve
func (h *BrandCreationHandler) ApproveProductChange(c *gin.Context) {
	tenantID, userID, role, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	res, err := h.enhancedProductService.ApproveProductChange(c.Request.Context(), id, tenantID, userID, role)
	if err != nil {
		if strings.Contains(err.Error(), "only admin or manager") {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

// RejectProductChange POST /product-change-requests/:id/reject
func (h *BrandCreationHandler) RejectProductChange(c *gin.Context) {
	tenantID, userID, role, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	if role != models.RoleAdmin && role != models.RoleManager {
		c.JSON(http.StatusForbidden, gin.H{"error": "only admin or manager can reject product changes"})
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if err := h.enhancedProductService.RejectProductChange(c.Request.Context(), id, tenantID, userID, body.Reason); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Product change request rejected"})
}

// v1.0.344 — combined photo/name/MRP requests (grouped by capture-session
// batch_id). One batch = one reviewable request on the web admin portal.

// ListPhotoChangeBatches GET /product-change-requests/batches?shop_id=&status=
func (h *BrandCreationHandler) ListPhotoChangeBatches(c *gin.Context) {
	tenantID, _, _, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	batches, err := h.enhancedProductService.ListPhotoChangeBatches(
		c.Request.Context(), tenantID, c.Query("shop_id"), c.Query("status"))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"batches": batches})
}

// ApproveBatch POST /product-change-requests/batches/:batchId/approve
func (h *BrandCreationHandler) ApproveBatch(c *gin.Context) {
	tenantID, userID, role, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	batchID, err := uuid.Parse(c.Param("batchId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid batch id"})
		return
	}
	n, err := h.enhancedProductService.ApproveBatch(c.Request.Context(), batchID, tenantID, userID, role)
	if err != nil {
		if strings.Contains(err.Error(), "only admin or manager") {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Combined request approved", "approved": n})
}

// RejectBatch POST /product-change-requests/batches/:batchId/reject
func (h *BrandCreationHandler) RejectBatch(c *gin.Context) {
	tenantID, userID, role, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	batchID, err := uuid.Parse(c.Param("batchId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid batch id"})
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	_ = c.ShouldBindJSON(&body)
	n, err := h.enhancedProductService.RejectBatch(c.Request.Context(), batchID, tenantID, userID, role, body.Reason)
	if err != nil {
		if strings.Contains(err.Error(), "only admin or manager") {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": "Combined request rejected", "rejected": n})
}

// RevertProductChange POST /product-change-requests/:id/revert — undo an
// auto-applied change (restore the snapshotted name/MRP).
func (h *BrandCreationHandler) RevertProductChange(c *gin.Context) {
	tenantID, userID, role, ok := ctxTenantUserRole(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth context missing"})
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	res, err := h.enhancedProductService.RevertProductChange(c.Request.Context(), id, tenantID, userID, role)
	if err != nil {
		if strings.Contains(err.Error(), "only admin or manager") {
			c.JSON(http.StatusForbidden, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

// GetProductsByBrand gets all products for a specific brand
// GET /brands/:id/products
func (h *BrandCreationHandler) GetProductsByBrand(c *gin.Context) {
	tenantIDStr := c.GetHeader("X-Tenant-ID")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Tenant-ID header is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID format"})
		return
	}

	brandIDStr := c.Param("id")
	brandID, err := uuid.Parse(brandIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand ID format"})
		return
	}

	// Get products
	products, err := h.enhancedProductService.GetProductsByBrand(c.Request.Context(), tenantID, brandID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Products retrieved successfully",
		"count":   len(products),
		"data":    products,
	})
}

// GetProductsGroupedByBrand gets products grouped by brand
// GET /brands/products/grouped
func (h *BrandCreationHandler) GetProductsGroupedByBrand(c *gin.Context) {
	tenantIDStr := c.GetHeader("X-Tenant-ID")
	if tenantIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "X-Tenant-ID header is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID format"})
		return
	}

	// Get products grouped by brand
	grouped, err := h.enhancedProductService.GetProductsGroupedByBrand(c.Request.Context(), tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Calculate statistics
	totalBrands := len(grouped)
	totalProducts := 0
	for _, products := range grouped {
		totalProducts += len(products)
	}

	c.JSON(http.StatusOK, gin.H{
		"message":        "Products grouped by brand retrieved successfully",
		"total_brands":   totalBrands,
		"total_products": totalProducts,
		"data":           grouped,
	})
}

// CalculateUPDuty calculates Uttar Pradesh government duty for a product
// POST /pricing/calculate-up-duty
func (h *BrandCreationHandler) CalculateUPDuty(c *gin.Context) {
	var req struct {
		Size           string  `json:"size" binding:"required"`
		AlcoholContent float64 `json:"alcohol_content"`
		CostPrice      float64 `json:"cost_price" binding:"required,gt=0"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create temp service instance to access duty calculation
	// In real scenario, this would be exposed through the service
	duty := calculateUPDutyHelper(req.Size, req.AlcoholContent, req.CostPrice)
	totalCost := req.CostPrice + duty

	c.JSON(http.StatusOK, gin.H{
		"message":       "Duty calculated successfully",
		"size":          req.Size,
		"cost_price":    req.CostPrice,
		"government_duty": duty,
		"total_cost":    totalCost,
		"calculation_rule": getDutyRuleDescription(req.Size),
	})
}

// Helper function to calculate UP duty (duplicated from service for API exposure)
func calculateUPDutyHelper(size string, alcoholContent float64, costPrice float64) float64 {
	sizeLower := size
	if len(size) > 0 {
		sizeLower = size
	}

	var dutyRate float64
	var minimumDuty float64

	// Determine duty rate and minimum based on size
	if contains(sizeLower, "180") || contains(sizeLower, "200") {
		dutyRate = 0.25
		minimumDuty = 50.0
	} else if contains(sizeLower, "350") || contains(sizeLower, "375") {
		dutyRate = 0.30
		minimumDuty = 100.0
	} else if contains(sizeLower, "750") {
		dutyRate = 0.35
		minimumDuty = 200.0
	} else if contains(sizeLower, "1l") || contains(sizeLower, "1L") || contains(sizeLower, "1000") {
		dutyRate = 0.40
		minimumDuty = 300.0
	} else {
		dutyRate = 0.30
		minimumDuty = 100.0
	}

	calculatedDuty := costPrice * dutyRate
	if calculatedDuty < minimumDuty {
		return minimumDuty
	}

	return calculatedDuty
}

// Helper function to check if string contains substring (case-insensitive)
func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > len(substr) &&
		(s[:len(substr)] == substr || s[len(s)-len(substr):] == substr))
}

// Helper function to get duty rule description
func getDutyRuleDescription(size string) string {
	if contains(size, "180") || contains(size, "200") {
		return "180ml/200ml: 25% of cost price (minimum ₹50)"
	} else if contains(size, "350") || contains(size, "375") {
		return "350ml/375ml: 30% of cost price (minimum ₹100)"
	} else if contains(size, "750") {
		return "750ml: 35% of cost price (minimum ₹200)"
	} else if contains(size, "1l") || contains(size, "1L") || contains(size, "1000") {
		return "1L/1000ml: 40% of cost price (minimum ₹300)"
	}
	return "Unknown size: 30% of cost price (minimum ₹100)"
}

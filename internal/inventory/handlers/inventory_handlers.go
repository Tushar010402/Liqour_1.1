package handlers

import (
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

type InventoryHandlers struct {
	productService         *services.ProductService
	stockService           *services.StockService
	purchaseService        *services.PurchaseService
	categoryService        *services.CategoryService
	tenantBrandService     *services.TenantBrandService
	brandOnboardingHandler *BrandOnboardingHandler
	brandCreationHandler   *BrandCreationHandler
	bulkImportHandler      *BulkImportHandler
	smartPurchaseService   *services.SmartPurchaseService
	smartStockSetupService *services.SmartStockSetupService
	smartStockJobService   *services.SmartStockJobService
}

func NewInventoryHandlers(
	productService *services.ProductService,
	stockService *services.StockService,
	purchaseService *services.PurchaseService,
	categoryService *services.CategoryService,
	tenantBrandService *services.TenantBrandService,
	brandOnboardingHandler *BrandOnboardingHandler,
	brandCreationHandler *BrandCreationHandler,
	bulkImportHandler *BulkImportHandler,
	smartPurchaseService *services.SmartPurchaseService,
	smartStockSetupService *services.SmartStockSetupService,
	smartStockJobService *services.SmartStockJobService,
) *InventoryHandlers {
	return &InventoryHandlers{
		productService:         productService,
		stockService:           stockService,
		purchaseService:        purchaseService,
		categoryService:        categoryService,
		tenantBrandService:     tenantBrandService,
		brandOnboardingHandler: brandOnboardingHandler,
		brandCreationHandler:   brandCreationHandler,
		bulkImportHandler:      bulkImportHandler,
		smartPurchaseService:   smartPurchaseService,
		smartStockSetupService: smartStockSetupService,
		smartStockJobService:   smartStockJobService,
	}
}

// Health check
func (h *InventoryHandlers) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"service": "inventory",
	})
}

// Product handlers
func (h *InventoryHandlers) CreateProduct(c *gin.Context) {
	var req services.ProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	_, err = uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	product, err := h.productService.CreateProduct(c.Request.Context(), req, tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, product)
}

// GetProductSizes returns distinct product sizes with counts
// Supports both single category_id and multiple category_ids (comma-separated)
func (h *InventoryHandlers) GetProductSizes(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Parse category_ids (comma-separated, takes priority) or single category_id
	var categoryIDs []uuid.UUID
	if idsStr := c.Query("category_ids"); idsStr != "" {
		for _, idStr := range strings.Split(idsStr, ",") {
			idStr = strings.TrimSpace(idStr)
			if parsed, err := uuid.Parse(idStr); err == nil {
				categoryIDs = append(categoryIDs, parsed)
			}
		}
	} else if catStr := c.Query("category_id"); catStr != "" {
		if parsed, err := uuid.Parse(catStr); err == nil {
			categoryIDs = append(categoryIDs, parsed)
		}
	}

	// Parse shop_id for shop-scoped size counts
	var shopIDArg []uuid.UUID
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopIDArg = append(shopIDArg, parsed)
		}
	}

	sizes, err := h.productService.GetProductSizes(c.Request.Context(), tenantUUID, categoryIDs, shopIDArg...)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch product sizes"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"sizes":   sizes,
	})
}

func (h *InventoryHandlers) GetProducts(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Parse query parameters
	categoryIDStr := c.Query("category_id")
	categoryIDsStr := c.Query("category_ids")
	brandIDStr := c.Query("brand_id")
	search := c.Query("search")
	sizeFilter := c.Query("size")
	includeInactive := c.Query("include_inactive") == "true"

	limitStr := c.DefaultQuery("limit", "50")
	offsetStr := c.DefaultQuery("offset", "0")

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 || limit > 500 {
		limit = 50
	}

	offset, err := strconv.Atoi(offsetStr)
	if err != nil || offset < 0 {
		offset = 0
	}

	var categoryID, brandID *uuid.UUID
	var categoryIDs []uuid.UUID

	// Parse category_ids (comma-separated, takes priority over single category_id)
	if categoryIDsStr != "" {
		for _, idStr := range strings.Split(categoryIDsStr, ",") {
			idStr = strings.TrimSpace(idStr)
			if parsed, err := uuid.Parse(idStr); err == nil {
				categoryIDs = append(categoryIDs, parsed)
			}
		}
	}

	if categoryIDStr != "" {
		if parsed, err := uuid.Parse(categoryIDStr); err == nil {
			categoryID = &parsed
		}
	}
	if brandIDStr != "" {
		if parsed, err := uuid.Parse(brandIDStr); err == nil {
			brandID = &parsed
		}
	}

	// Parse shop_id for shop-scoped product filtering
	shopIDStr := c.Query("shop_id")
	var shopID *uuid.UUID
	if shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &parsed
		}
	}

	// Parse owner_shop_id — ownership-scoped picker (products this shop owns,
	// regardless of stock). Used by the Stock Setup Swap dialog so managers
	// can only pick the record-shop's own SKUs (prevents cross-shop links).
	ownerShopIDStr := c.Query("owner_shop_id")
	var ownerShopID *uuid.UUID
	if ownerShopIDStr != "" {
		if parsed, err := uuid.Parse(ownerShopIDStr); err == nil {
			ownerShopID = &parsed
		}
	}

	filters := services.ProductFilters{
		Search:      search,
		Size:        sizeFilter,
		CategoryIDs: categoryIDs,
		Page:        offset/limit + 1,
		PageSize:    limit,
	}
	if categoryID != nil {
		filters.CategoryID = *categoryID
	}
	if brandID != nil {
		filters.BrandID = *brandID
	}
	if shopID != nil {
		filters.ShopID = *shopID
	}
	if ownerShopID != nil {
		filters.OwnerShopID = *ownerShopID
	}
	if !includeInactive {
		active := true
		filters.IsActive = &active
	}
	// Admin escape hatch to see zero-stock duplicates (off by default — see
	// ProductFilters.IncludeZeroStock comment for rationale).
	if v := strings.ToLower(c.Query("include_zero_stock")); v == "true" || v == "1" || v == "yes" {
		filters.IncludeZeroStock = true
	}
	// Smart-picker mode: rank products by recent-purchase / in-stock tiers
	// instead of hiding the catalog. Only meaningful with shop_id.
	if v := strings.ToLower(c.Query("purchase_priority")); v == "true" || v == "1" || v == "yes" {
		filters.PurchasePriority = true
	}

	response, err := h.productService.GetProducts(c.Request.Context(), tenantUUID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"products": response.Products,
		"total":    response.TotalCount,
		"limit":    limit,
		"offset":   offset,
		// v1.0.299 — SUM(stocks.quantity) over the full filtered set at this
		// shop, independent of pagination. Flutter Inventory header reads
		// this so the visible "X pcs" matches the approved record total
		// regardless of which page is loaded. Service computes it in a
		// single SQL aggregate (see product_service.go).
		"total_stock": response.TotalStock,
	})
}

func (h *InventoryHandlers) GetProductByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	product, err := h.productService.GetProductByID(c.Request.Context(), id, tenantUUID)
	if err != nil {
		if err.Error() == "product not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, product)
}

func (h *InventoryHandlers) UpdateProduct(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	var req services.ProductRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	_, err = uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	product, err := h.productService.UpdateProduct(c.Request.Context(), id, tenantUUID, req)
	if err != nil {
		if err.Error() == "product not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, product)
}

func (h *InventoryHandlers) DeleteProduct(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid product ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	err = h.productService.DeleteProduct(c.Request.Context(), id, tenantUUID)
	if err != nil {
		if err.Error() == "product not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// Stock handlers
func (h *InventoryHandlers) GetStocks(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	shopIDStr := c.Query("shop_id")
	var shopID *uuid.UUID
	if shopIDStr != "" {
		if parsed, err := uuid.Parse(shopIDStr); err == nil {
			shopID = &parsed
		} else {
			c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
			return
		}
	}

	lowStock := c.Query("low_stock") == "true"

	var stocks []*services.StockResponse

	if lowStock {
		// Get low stock items, optionally filtered by shop
		stocks, err = h.stockService.GetLowStockItems(c.Request.Context(), tenantUUID, shopID)
	} else {
		// Get all stocks, optionally filtered by shop
		filters := services.StockFilters{}
		stocks, err = h.stockService.GetAllStocks(c.Request.Context(), tenantUUID, shopID, filters)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stocks": stocks,
		"total":  len(stocks),
	})
}

func (h *InventoryHandlers) GetStockMovements(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	_, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	limitStr := c.DefaultQuery("limit", "50")
	offsetStr := c.DefaultQuery("offset", "0")

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 || limit > 500 {
		limit = 50
	}

	offset, err := strconv.Atoi(offsetStr)
	if err != nil || offset < 0 {
		offset = 0
	}

	// For simplicity, return empty movements as this requires complex query implementation
	movements := []*services.StockHistoryResponse{}
	total := int64(0)

	c.JSON(http.StatusOK, gin.H{
		"movements": movements,
		"total":     total,
		"limit":     limit,
		"offset":    offset,
	})
}

func (h *InventoryHandlers) AdjustStock(c *gin.Context) {
	var req services.StockAdjustmentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	stock, err := h.stockService.AdjustStock(c.Request.Context(), req, tenantUUID, userUUID)
	if err != nil {
		errMsg := err.Error()
		// Check if it's a SHOP_NOT_FOUND error
		if len(errMsg) >= 14 && errMsg[:14] == "SHOP_NOT_FOUND" {
			c.JSON(http.StatusNotFound, gin.H{
				"error": errMsg[16:], // Skip "SHOP_NOT_FOUND: " prefix
				"code":  "SHOP_NOT_FOUND",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Stock adjusted successfully",
		"stock":   stock,
	})
}

// UpdateStockByBrand updates stock for an existing brand identified by brand name and size
// This endpoint is specifically for OCR flows where we need to update stock for existing brands
func (h *InventoryHandlers) UpdateStockByBrand(c *gin.Context) {
	var req services.BrandStockUpdateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get tenant ID from header
	tenantIDStr := c.GetHeader("X-Tenant-ID")
	if tenantIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "X-Tenant-ID header is required"})
		return
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID format"})
		return
	}

	// Get user ID from header
	userIDStr := c.GetHeader("X-User-ID")
	if userIDStr == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "X-User-ID header is required"})
		return
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID format"})
		return
	}

	stock, err := h.stockService.UpdateStockByBrandAndSize(c.Request.Context(), req, tenantID, userID)
	if err != nil {
		// Check if product was not found
		errMsg := err.Error()
		if len(errMsg) >= len("product not found") && errMsg[:len("product not found")] == "product not found" {
			c.JSON(http.StatusNotFound, gin.H{
				"error": errMsg,
				"code":  "PRODUCT_NOT_FOUND",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": errMsg})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": fmt.Sprintf("Stock updated successfully for %s %s", req.BrandName, req.Size),
		"stock":   stock,
	})
}

func (h *InventoryHandlers) TransferStock(c *gin.Context) {
	var req services.StockTransferRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	err = h.stockService.CreateStockTransfer(c.Request.Context(), req, tenantUUID, userUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Stock transferred successfully"})
}

// Purchase handlers
func (h *InventoryHandlers) CreatePurchase(c *gin.Context) {
	var req services.PurchaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	purchase, err := h.purchaseService.CreatePurchase(c.Request.Context(), req, tenantUUID, userUUID)
	if err != nil {
		// Purchase name gate: products with unverified raw names must be
		// photo-verified first. 409 + structured list so the app can route
		// the operator straight to the inventory photo-verify step.
		if unvErr, ok := err.(*services.PurchaseNameUnverifiedError); ok {
			c.JSON(http.StatusConflict, gin.H{
				"error":               unvErr.Error(),
				"code":                "name_unverified",
				"unverified_products": unvErr.Products,
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, purchase)
}

func (h *InventoryHandlers) GetPurchases(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	status := c.Query("status")

	filter := services.PurchaseListFilter{
		Status:      status,
		HasShortage: c.Query("has_shortage") == "1" || c.Query("has_shortage") == "true",
	}
	if v := c.Query("shop_id"); v != "" {
		if parsed, err := uuid.Parse(v); err == nil {
			filter.ShopID = &parsed
		}
	}
	if v := c.Query("vendor_id"); v != "" {
		if parsed, err := uuid.Parse(v); err == nil {
			filter.VendorID = &parsed
		}
	}
	// from/to accept YYYY-MM-DD (date) — the service makes `to` inclusive.
	if v := c.Query("from"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			filter.From = &t
		}
	}
	if v := c.Query("to"); v != "" {
		if t, err := time.Parse("2006-01-02", v); err == nil {
			filter.To = &t
		}
	}

	limitStr := c.DefaultQuery("limit", "50")
	offsetStr := c.DefaultQuery("offset", "0")

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit <= 0 || limit > 1000 {
		limit = 50
	}

	offset, err := strconv.Atoi(offsetStr)
	if err != nil || offset < 0 {
		offset = 0
	}

	purchases, total, err := h.purchaseService.GetPurchases(c.Request.Context(), tenantUUID, filter, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Aggregate over the FULL filtered set so the list header is accurate even
	// when the current page is a slice of many purchases. Non-fatal on error.
	summary, sErr := h.purchaseService.GetPurchasesSummaryData(c.Request.Context(), tenantUUID, filter)
	if sErr != nil {
		summary = services.PurchasesSummary{Count: total}
	}

	c.JSON(http.StatusOK, gin.H{
		"purchases": purchases,
		"total":     total,
		"limit":     limit,
		"offset":    offset,
		"summary":   summary,
	})
}

func (h *InventoryHandlers) GetPurchasesSummary(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Get today's purchases summary
	today := time.Now().Truncate(24 * time.Hour)

	var result struct {
		TotalAmount float64 `json:"total_amount"`
		Count       int64   `json:"count"`
	}

	h.purchaseService.DB().Model(&models.StockPurchase{}).
		Where("tenant_id = ? AND created_at >= ?", tenantUUID, today).
		Select("COALESCE(SUM(total_amount), 0) as total_amount, COUNT(*) as count").
		Scan(&result)

	c.JSON(http.StatusOK, gin.H{
		"total_amount": result.TotalAmount,
		"count":        result.Count,
	})
}

func (h *InventoryHandlers) GetPurchaseByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid purchase ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	purchase, err := h.purchaseService.GetPurchaseByID(c.Request.Context(), id, tenantUUID)
	if err != nil {
		if err.Error() == "purchase not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, purchase)
}

func (h *InventoryHandlers) ReceivePurchase(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid purchase ID"})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	err = h.purchaseService.ReceivePurchase(c.Request.Context(), id, tenantUUID, userUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Purchase received successfully"})
}

// Category handlers
func (h *InventoryHandlers) CreateCategory(c *gin.Context) {
	var req services.CategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	category, err := h.categoryService.CreateCategory(c.Request.Context(), req, tenantUUID, userUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, category)
}

func (h *InventoryHandlers) GetCategories(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	includeInactive := c.Query("include_inactive") == "true"

	categories, err := h.categoryService.GetCategories(c.Request.Context(), tenantUUID, includeInactive)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"categories": categories})
}

func (h *InventoryHandlers) GetCategoryByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid category ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	category, err := h.categoryService.GetCategoryByID(c.Request.Context(), id, tenantUUID)
	if err != nil {
		if err.Error() == "category not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, category)
}

func (h *InventoryHandlers) UpdateCategory(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid category ID"})
		return
	}

	var req services.CategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	category, err := h.categoryService.UpdateCategory(c.Request.Context(), id, req, tenantUUID, userUUID)
	if err != nil {
		if err.Error() == "category not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, category)
}

func (h *InventoryHandlers) DeleteCategory(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid category ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	err = h.categoryService.DeleteCategory(c.Request.Context(), id, tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// Brand handlers
func (h *InventoryHandlers) CreateBrand(c *gin.Context) {
	var req services.BrandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	brand, err := h.categoryService.CreateBrand(c.Request.Context(), req, tenantUUID, userUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, brand)
}

func (h *InventoryHandlers) GetBrands(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	includeInactive := c.Query("include_inactive") == "true"

	brands, err := h.categoryService.GetBrands(c.Request.Context(), tenantUUID, includeInactive)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"brands": brands})
}

func (h *InventoryHandlers) GetBrandByID(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	brand, err := h.categoryService.GetBrandByID(c.Request.Context(), id, tenantUUID)
	if err != nil {
		if err.Error() == "brand not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, brand)
}

func (h *InventoryHandlers) UpdateBrand(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand ID"})
		return
	}

	var req services.BrandRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

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

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	userUUID, err := uuid.Parse(userID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user ID"})
		return
	}

	brand, err := h.categoryService.UpdateBrand(c.Request.Context(), id, req, tenantUUID, userUUID)
	if err != nil {
		if err.Error() == "brand not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, brand)
}

func (h *InventoryHandlers) DeleteBrand(c *gin.Context) {
	idStr := c.Param("id")
	id, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid brand ID"})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	err = h.categoryService.DeleteBrand(c.Request.Context(), id, tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// Advanced Inventory Reports
func (h *InventoryHandlers) GetInventoryValuationReport(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Parse query parameters
	valueMethod := c.DefaultQuery("method", "average_cost") // average_cost, fifo, lifo

	report, err := h.stockService.GetInventoryValuationReport(c.Request.Context(), tenantUUID, valueMethod)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":       report,
		"method":       valueMethod,
		"generated_at": "2024-01-01T00:00:00Z",
	})
}

func (h *InventoryHandlers) GetStockTurnoverReport(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Parse query parameters
	periodStr := c.DefaultQuery("period", "12") // months
	period, err := strconv.Atoi(periodStr)
	if err != nil || period <= 0 {
		period = 12
	}

	report, err := h.stockService.GetStockTurnoverReport(c.Request.Context(), tenantUUID, period)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":        report,
		"period_months": period,
		"generated_at":  "2024-01-01T00:00:00Z",
	})
}

func (h *InventoryHandlers) GetStockAgingReport(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	report, err := h.stockService.GetStockAgingReport(c.Request.Context(), tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"report":       report,
		"generated_at": "2024-01-01T00:00:00Z",
	})
}

// Product Template endpoints
func (h *InventoryHandlers) GetProductTemplates(c *gin.Context) {
	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Get query parameters for filtering
	categoryID := c.Query("category_id")
	subcategoryID := c.Query("subcategory_id")
	brandID := c.Query("brand_id")
	search := c.Query("search")

	templates, err := h.productService.GetProductTemplates(c.Request.Context(), tenantUUID, categoryID, subcategoryID, brandID, search)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"templates": templates,
		"count":     len(templates),
	})
}

func (h *InventoryHandlers) GetProductTemplate(c *gin.Context) {
	// This endpoint is not implemented yet
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Endpoint not implemented"})
}

// Subcategory endpoints
func (h *InventoryHandlers) GetSubcategories(c *gin.Context) {
	// Get tenant ID
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	categoryIDStr := c.Query("category_id")
	if categoryIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "category_id is required"})
		return
	}

	categoryID, err := uuid.Parse(categoryIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid category ID"})
		return
	}

	subcategories, err := h.productService.GetSubcategories(c.Request.Context(), tenantUUID, categoryID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"subcategories": subcategories,
	})
}

func (h *InventoryHandlers) CreateSubcategory(c *gin.Context) {
	var req struct {
		Name        string `json:"name" binding:"required"`
		CategoryID  string `json:"category_id" binding:"required"`
		PriceRange  string `json:"price_range"`
		Description string `json:"description"`
		SortOrder   int    `json:"sort_order"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// This endpoint is not implemented yet
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Endpoint not implemented"})
}

// Product creation from template
func (h *InventoryHandlers) CreateProductFromTemplate(c *gin.Context) {
	// This endpoint is not implemented yet
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Endpoint not implemented"})
}

// Bulk stock creation from templates
func (h *InventoryHandlers) BulkCreateStock(c *gin.Context) {
	// This endpoint is not implemented yet
	c.JSON(http.StatusNotImplemented, gin.H{"error": "Endpoint not implemented"})
}

// Brand management handlers for SaaS integration
func (h *InventoryHandlers) GetAvailableBrands(c *gin.Context) {
	brands, err := h.tenantBrandService.GetAvailableBrands()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Available brands retrieved successfully",
		"brands":  brands,
	})
}

func (h *InventoryHandlers) GetTenantBrands(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	brands, err := h.tenantBrandService.GetTenantBrands(tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Tenant brands retrieved successfully",
		"brands":  brands,
	})
}

func (h *InventoryHandlers) CreateProductFromBrand(c *gin.Context) {
	var req struct {
		VariantID uuid.UUID `json:"variant_id" binding:"required"`
		ShopID    uuid.UUID `json:"shop_id" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	product, err := h.tenantBrandService.CreateProductFromBrandVariant(tenantUUID, req.VariantID, req.ShopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Product created from brand variant successfully",
		"product": product,
	})
}

func (h *InventoryHandlers) GetProductsFromBrands(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	products, err := h.tenantBrandService.GetProductsFromBrandVariants(tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":  "Products from brands retrieved successfully",
		"products": products,
	})
}

func (h *InventoryHandlers) SyncBrandPricing(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	err = h.tenantBrandService.SyncBrandVariantPricing(tenantUUID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Brand variant pricing synced successfully",
	})
}

// SelectBrandsFromCatalogRequest represents request for selecting brands from SaaS catalog
type SelectBrandsFromCatalogRequest struct {
	BrandIDs []string `json:"brand_ids" binding:"required"`
}

// CustomizeBrandVariantRequest represents request for customizing brand variant
type CustomizeBrandVariantRequest struct {
	VariantID          string   `json:"variant_id" binding:"required"`
	CustomBuyingPrice  *float64 `json:"custom_buying_price"`
	CustomSellingPrice *float64 `json:"custom_selling_price"`
	CustomMRP          *float64 `json:"custom_mrp"`
	CustomName         *string  `json:"custom_name"`
}

// ImportBrandsAsProductsRequest represents request for importing brands as products
type ImportBrandsAsProductsRequest struct {
	Imports []BrandImportItem `json:"imports" binding:"required"`
	ShopID  string            `json:"shop_id" binding:"required"`
}

// BrandImportItem represents a single brand variant import
type BrandImportItem struct {
	VariantID    string   `json:"variant_id" binding:"required"`
	InitialStock int      `json:"initial_stock"`
	BuyingPrice  *float64 `json:"buying_price"`
	SellingPrice *float64 `json:"selling_price"`
	MRP          *float64 `json:"mrp"`
}

// SelectBrandsFromCatalog allows tenants to select brands from SaaS catalog
func (h *InventoryHandlers) SelectBrandsFromCatalog(c *gin.Context) {
	var req SelectBrandsFromCatalogRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// Convert string brand IDs to UUIDs
	brandUUIDs := make([]uuid.UUID, len(req.BrandIDs))
	for i, brandIDStr := range req.BrandIDs {
		brandUUID, err := uuid.Parse(brandIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("Invalid brand ID: %s", brandIDStr)})
			return
		}
		brandUUIDs[i] = brandUUID
	}

	// Call the tenant brand service to persist the selection to SaaS service
	err = h.tenantBrandService.SelectBrandsForTenant(tenantUUID, brandUUIDs)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": fmt.Sprintf("Failed to select brands: %s", err.Error())})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   fmt.Sprintf("Successfully selected %d brands for tenant", len(req.BrandIDs)),
		"brand_ids": req.BrandIDs,
		"tenant_id": tenantUUID,
	})
}

// CustomizeBrandVariant allows tenants to customize brand variant pricing and details
func (h *InventoryHandlers) CustomizeBrandVariant(c *gin.Context) {
	var req CustomizeBrandVariantRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	// For now, just return success - full implementation would store customizations
	c.JSON(http.StatusOK, gin.H{
		"message":        "Brand variant customized successfully",
		"variant_id":     req.VariantID,
		"tenant_id":      tenantUUID,
		"customizations": req,
	})
}

// ImportBrandsAsProducts imports selected brand variants as products with initial stock using bulk operations
func (h *InventoryHandlers) ImportBrandsAsProducts(c *gin.Context) {
	var req ImportBrandsAsProductsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	_, exists = c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "User ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	shopUUID, err := uuid.Parse(req.ShopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
		return
	}

	// Prepare imports using the correct BrandVariantImport structure
	imports := make([]services.BrandVariantImport, len(req.Imports))

	for i, item := range req.Imports {
		variantUUID, err := uuid.Parse(item.VariantID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": fmt.Sprintf("Invalid variant ID %s: %v", item.VariantID, err),
			})
			return
		}

		imports[i] = services.BrandVariantImport{
			VariantID:          variantUUID,
			InitialStock:       item.InitialStock,
			CustomBuyingPrice:  item.BuyingPrice,
			CustomSellingPrice: item.SellingPrice,
			CustomMRP:          item.MRP,
		}
	}

	// Use the TenantBrandService BulkImportBrandVariants method for efficient bulk import
	importedProducts, err := h.tenantBrandService.BulkImportBrandVariants(tenantUUID, shopUUID, imports)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": fmt.Sprintf("Failed to bulk import brand variants: %v", err),
		})
		return
	}

	// Build response with imported product details
	importResponse := []map[string]interface{}{}
	for i, product := range importedProducts {
		// Get the corresponding import config
		importConfig := req.Imports[i]

		importResponse = append(importResponse, map[string]interface{}{
			"product_id":      product.ID,
			"name":            product.Name,
			"variant_id":      importConfig.VariantID,
			"initial_stock":   importConfig.InitialStock,
			"cost_price":      product.CostPrice,
			"selling_price":   product.SellingPrice,
			"mrp":             product.MRP,
			"size":            product.Size,
			"alcohol_content": product.AlcoholContent,
			"category_id":     product.CategoryID,
			"brand_id":        product.BrandID,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"message":           fmt.Sprintf("Successfully imported %d products from brand variants", len(importedProducts)),
		"imported_products": importResponse,
		"shop_id":           shopUUID,
		"tenant_id":         tenantUUID,
		"total_imported":    len(importedProducts),
	})
}

// Brand Onboarding delegation methods (delegate to brandOnboardingHandler)

func (h *InventoryHandlers) GetAvailableBrandTemplates(c *gin.Context) {
	h.brandOnboardingHandler.GetAvailableBrandTemplates(c)
}

func (h *InventoryHandlers) OnboardBrands(c *gin.Context) {
	h.brandOnboardingHandler.OnboardBrands(c)
}

func (h *InventoryHandlers) GetOnboardedBrands(c *gin.Context) {
	h.brandOnboardingHandler.GetOnboardedBrands(c)
}

func (h *InventoryHandlers) UpdateOnboardedBrand(c *gin.Context) {
	h.brandOnboardingHandler.UpdateOnboardedBrand(c)
}

func (h *InventoryHandlers) GetCustomBrands(c *gin.Context) {
	h.brandOnboardingHandler.GetCustomBrands(c)
}

func (h *InventoryHandlers) GetBrandCategories(c *gin.Context) {
	h.brandOnboardingHandler.GetBrandCategories(c)
}

func (h *InventoryHandlers) GetBrandsByCategory(c *gin.Context) {
	h.brandOnboardingHandler.GetBrandsByCategory(c)
}

func (h *InventoryHandlers) GetBrandMetadata(c *gin.Context) {
	h.brandOnboardingHandler.GetBrandMetadata(c)
}

func (h *InventoryHandlers) GetSubcategoriesByCategory(c *gin.Context) {
	h.brandOnboardingHandler.GetSubcategoriesByCategory(c)
}

func (h *InventoryHandlers) GetSaaSBrandCategories(c *gin.Context) {
	h.brandOnboardingHandler.GetSaaSBrandCategories(c)
}

func (h *InventoryHandlers) GetSaaSBrandSubcategories(c *gin.Context) {
	h.brandOnboardingHandler.GetSaaSBrandSubcategories(c)
}

func (h *InventoryHandlers) GetSaaSCategorySizes(c *gin.Context) {
	h.brandOnboardingHandler.GetSaaSCategorySizes(c)
}

// Brand Creation delegation methods (delegate to brandCreationHandler)

func (h *InventoryHandlers) CreateBrandWithVariants(c *gin.Context) {
	h.brandCreationHandler.CreateBrandWithVariants(c)
}

func (h *InventoryHandlers) CheckDuplicateProduct(c *gin.Context) {
	h.brandCreationHandler.CheckDuplicateProduct(c)
}

func (h *InventoryHandlers) UpdateProductPricing(c *gin.Context) {
	h.brandCreationHandler.UpdateProductPricing(c)
}

// v1.0.253 — Product photo+MRP change-request approval (delegated, mirrors
// the Stock Setup approve/reject pattern).
func (h *InventoryHandlers) ListProductChangeRequests(c *gin.Context) {
	h.brandCreationHandler.ListProductChangeRequests(c)
}

func (h *InventoryHandlers) GetProductChangePendingCount(c *gin.Context) {
	h.brandCreationHandler.GetProductChangePendingCount(c)
}

func (h *InventoryHandlers) GetProductChangeRequest(c *gin.Context) {
	h.brandCreationHandler.GetProductChangeRequest(c)
}

func (h *InventoryHandlers) ApproveProductChange(c *gin.Context) {
	h.brandCreationHandler.ApproveProductChange(c)
}

func (h *InventoryHandlers) RejectProductChange(c *gin.Context) {
	h.brandCreationHandler.RejectProductChange(c)
}

// v1.0.344 — combined photo/name/MRP requests (grouped by batch_id).
func (h *InventoryHandlers) ListPhotoChangeBatches(c *gin.Context) {
	h.brandCreationHandler.ListPhotoChangeBatches(c)
}

func (h *InventoryHandlers) ApproveBatch(c *gin.Context) {
	h.brandCreationHandler.ApproveBatch(c)
}

func (h *InventoryHandlers) RejectBatch(c *gin.Context) {
	h.brandCreationHandler.RejectBatch(c)
}

func (h *InventoryHandlers) RevertProductChange(c *gin.Context) {
	h.brandCreationHandler.RevertProductChange(c)
}

func (h *InventoryHandlers) GetProductsByBrand(c *gin.Context) {
	h.brandCreationHandler.GetProductsByBrand(c)
}

func (h *InventoryHandlers) GetProductsGroupedByBrand(c *gin.Context) {
	h.brandCreationHandler.GetProductsGroupedByBrand(c)
}

func (h *InventoryHandlers) CalculateUPDuty(c *gin.Context) {
	h.brandCreationHandler.CalculateUPDuty(c)
}

// Bulk Import delegation methods (delegate to bulkImportHandler)

func (h *InventoryHandlers) DownloadImportTemplate(c *gin.Context) {
	h.bulkImportHandler.DownloadTemplate(c)
}

func (h *InventoryHandlers) UploadAndValidateImport(c *gin.Context) {
	h.bulkImportHandler.UploadAndValidate(c)
}

func (h *InventoryHandlers) ConfirmImport(c *gin.Context) {
	h.bulkImportHandler.ConfirmImport(c)
}

func (h *InventoryHandlers) GetImportHistory(c *gin.Context) {
	h.bulkImportHandler.GetImportHistory(c)
}

func (h *InventoryHandlers) GetImportStatus(c *gin.Context) {
	h.bulkImportHandler.GetImportStatus(c)
}

func (h *InventoryHandlers) CancelImport(c *gin.Context) {
	h.bulkImportHandler.CancelImport(c)
}

// OCR Auto-onboarding delegation methods (would delegate to autoOnboardHandler if we had it)
// For now, these return not implemented

func (h *InventoryHandlers) AutoOnboardFromOCR(c *gin.Context) {
	// This would delegate to autoOnboardHandler once we integrate it
	c.JSON(http.StatusNotImplemented, gin.H{
		"error": "OCR auto-onboarding endpoint not yet integrated",
		"message": "Please use manual brand onboarding for now",
	})
}

func (h *InventoryHandlers) GetOCROnboardingSummary(c *gin.Context) {
	// This would delegate to autoOnboardHandler once we integrate it
	c.JSON(http.StatusNotImplemented, gin.H{
		"error": "OCR onboarding summary endpoint not yet integrated",
		"message": "Please use manual brand onboarding for now",
	})
}

// Custom brand creation delegation method
func (h *InventoryHandlers) CreateCustomBrand(c *gin.Context) {
	h.brandOnboardingHandler.CreateCustomBrand(c)
}

// GetPurchaReportPreview returns a purchase report preview for a shop on a given date
func (h *InventoryHandlers) GetPurchaReportPreview(c *gin.Context) {
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	tenantUUID, err := uuid.Parse(tenantID.(string))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid tenant ID"})
		return
	}

	shopIDStr := c.Query("shop_id")
	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	shopUUID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop ID"})
		return
	}

	dateStr := c.Query("date")
	if dateStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "date is required"})
		return
	}

	viewMode := c.DefaultQuery("view_mode", "flat")
	categoryFilter := c.DefaultQuery("category_filter", "all")
	showOpening := c.DefaultQuery("show_opening", "false") == "true"

	report, err := h.purchaseService.GetPurchaReportPreview(
		c.Request.Context(), tenantUUID, shopUUID, dateStr, viewMode, categoryFilter, showOpening,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, report)
}

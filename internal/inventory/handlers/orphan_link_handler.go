package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/inventory/services"
)

// LinkProductToMaster handles POST /api/inventory/products/:id/link-master.
// Body: {"saas_brand_id": "<uuid>"} — optional. When omitted, the service
// auto-picks the best master using the same scorer that the extraction
// pipeline uses (so the picker + extractor agree on the best match).
func (h *InventoryHandlers) LinkProductToMaster(c *gin.Context) {
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
		SaasBrandID string `json:"saas_brand_id"`
	}
	// Body is optional — a bare POST triggers auto-pick.
	_ = c.ShouldBindJSON(&body)

	productID := c.Param("id")
	if productID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "product id is required"})
		return
	}

	result, err := h.smartStockSetupService.LinkOrphanToMaster(services.LinkOrphanToMasterRequest{
		ProductID:   productID,
		TenantID:    tenantID.(string),
		SaasBrandID: body.SaasBrandID,
	})
	if err != nil {
		// 409 when the product is already linked (client can refresh); 400 for
		// invalid ids or auto-pick failures where the user can retry manually.
		status := http.StatusBadRequest
		if err.Error() == "product is already linked to a master brand; cannot re-link via this endpoint" ||
			err.Error() == "product was linked concurrently; retry after refresh" {
			status = http.StatusConflict
		}
		c.JSON(status, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

// SearchMasterBrands handles GET /api/inventory/master-brands/search?q=&size=&limit=.
// Feeds the Flutter link-master picker. Ranked by the same scorer as the
// extraction flow so "what the picker shows first" matches "what the
// extractor would have picked first".
func (h *InventoryHandlers) SearchMasterBrands(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Service not configured"})
		return
	}
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Empty `q` is allowed — triggers browse mode in the service layer, which
	// returns the alphabetical top-N for the given size+category. The picker
	// uses this to show suggestions the moment the user taps the field, with
	// no typing required.
	q := c.Query("q")

	size := c.Query("size")
	categoryID := c.Query("category_id")
	limit := 0
	if s := c.Query("limit"); s != "" {
		// Parse defensively — service clamps to [1,20] so we pass 0 on parse failure.
		for _, r := range s {
			if r < '0' || r > '9' {
				limit = 0
				break
			}
			limit = limit*10 + int(r-'0')
			if limit > 20 {
				limit = 20
				break
			}
		}
	}

	results, err := h.smartStockSetupService.SearchMasterBrands(services.SearchMasterBrandsRequest{
		TenantID:   tenantID.(string),
		Query:      q,
		Size:       size,
		CategoryID: categoryID,
		Limit:      limit,
	})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"results": results})
}

// GetStockSetupAudit handles GET /api/inventory/stocks/smart-setup/audit?category_id=&size=.
// Returns the live audit (orphan tenant products) so the Flutter review screen
// can refresh its Data Hygiene banner after an apply or manual link without
// re-running the full extraction. Missing master brands are not re-computed
// here (they require the OCR items from the extraction step).
func (h *InventoryHandlers) GetStockSetupAudit(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Service not configured"})
		return
	}
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	audit, err := h.smartStockSetupService.GetStockSetupAudit(services.GetStockSetupAuditRequest{
		TenantID:   tenantID.(string),
		CategoryID: c.Query("category_id"),
		Size:       c.Query("size"),
	})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"audit": audit})
}

// OrphansAutofix handles POST /api/inventory/orphans/autofix?dry_run=true|false.
//
// Safety contract:
//   - Defaults to dry_run=true. Mutation ONLY happens when the query param is
//     the exact string "false". Any other value (including "0", empty, garbage)
//     leaves the endpoint in dry-run mode.
//   - Dry-run returns a full preview response so the caller can inspect
//     exactly what would be deleted / renamed / linked before flipping the flag.
//   - Per-tenant scope — cross-tenant writes are impossible (service layer
//     loads orphans WHERE tenant_id = caller's tenant and writes with the
//     same predicate).
func (h *InventoryHandlers) OrphansAutofix(c *gin.Context) {
	if h.smartStockSetupService == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Service not configured"})
		return
	}
	tenantID, exists := c.Get("tenant_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Default: dry-run. Only the literal "false" opts in to mutation.
	dryRun := c.Query("dry_run") != "false"

	result, err := h.smartStockSetupService.OrphansAutofix(services.OrphanAutofixRequest{
		TenantID: tenantID.(string),
		DryRun:   dryRun,
	})
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, result)
}

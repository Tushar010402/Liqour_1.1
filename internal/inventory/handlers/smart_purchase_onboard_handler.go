package handlers

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

// SmartPurchaseOnboardHandler exposes the v1.0.193 product-onboarding
// endpoints used by Flutter's review screen onboarding chips.
//
// Two endpoints — Tier 3 and Tier 4 of the OnboardingTier decision tree:
//
//   POST /purchases/smart-purchase/onboard-from-master  (Tier 3)
//     Creates a shop product linked to an existing master saas_brand.
//     Auto-fills MRP / size / category from the master record.
//
//   POST /purchases/smart-purchase/onboard-new           (Tier 4)
//     Creates a fully new product (no master link). Operator supplies
//     brand_name + size + category + MRP + cost.
//
// Both endpoints are idempotent on (tenant_id, shop_id, brand_name, size):
// re-submitting the same payload returns the existing product_id with
// `action: "matched_existing"`. This protects against the operator
// double-tapping the chip on a slow network.
type SmartPurchaseOnboardHandler struct {
	db     *database.DB
	logger *logrus.Logger
}

// NewSmartPurchaseOnboardHandler wires the handler.
func NewSmartPurchaseOnboardHandler(db *database.DB, logger *logrus.Logger) *SmartPurchaseOnboardHandler {
	return &SmartPurchaseOnboardHandler{db: db, logger: logger}
}

type onboardFromMasterRequest struct {
	SaaSBrandID string  `json:"saas_brand_id" binding:"required"`
	SizeML      int     `json:"size_ml" binding:"required"`
	ShopID      string  `json:"shop_id" binding:"required"`
	CostPrice   float64 `json:"cost_price"` // optional; defaults to master MRP × 0.6 if unset
}

type onboardNewRequest struct {
	BrandName string  `json:"brand_name" binding:"required"`
	SizeML    int     `json:"size_ml" binding:"required"`
	Category  string  `json:"category"` // optional; defaults to "Whisky" if unset
	MRP       float64 `json:"mrp" binding:"required"`
	CostPrice float64 `json:"cost_price"`
	ShopID    string  `json:"shop_id" binding:"required"`
}

type onboardResponse struct {
	ProductID   string `json:"product_id"`
	ProductName string `json:"product_name"`
	Action      string `json:"action"` // "created" | "matched_existing"
}

// OnboardFromMaster handles POST /purchases/smart-purchase/onboard-from-master.
//
// Looks up the master saas_brands row, creates a tenant Product linked to it
// (saas_brand_id + saas_variant_id wired so future onboarding sees this is
// already taken), and creates a stock_levels-equivalent Stock row with qty=0.
// The actual quantity comes from the apply-purchase step that follows.
func (h *SmartPurchaseOnboardHandler) OnboardFromMaster(c *gin.Context) {
	tenantID, userID, ok := h.requireAuth(c)
	if !ok {
		return
	}

	var req onboardFromMasterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	saasBrandID, err := uuid.Parse(req.SaaSBrandID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid saas_brand_id"})
		return
	}
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
		return
	}

	// v1.0.386 — delegate to the shared tx-safe core (single create-product code
	// path with the apply auto-onboard). h.db.DB is the autocommit *gorm.DB, so
	// behaviour matches the old per-step writes.
	res, err := services.ResolveOrCreateShopProductFromMaster(h.db.DB, tenantID, shopID, saasBrandID, req.SizeML, req.CostPrice, 0, "")
	if err != nil {
		h.logger.WithError(err).Error("OnboardFromMaster: core failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "onboard failed"})
		return
	}
	h.logger.Infof("OnboardFromMaster: %s product %s tenant=%s shop=%s saas_brand=%s (user=%s)",
		map[bool]string{true: "created", false: "matched"}[res.Created], res.ProductID, tenantID, shopID, saasBrandID, userID)

	status, action := http.StatusCreated, "created"
	if !res.Created {
		status, action = http.StatusOK, "matched_existing"
	}
	c.JSON(status, onboardResponse{
		ProductID:   res.ProductID.String(),
		ProductName: res.Name,
		Action:      action,
	})
}

// OnboardNew handles POST /purchases/smart-purchase/onboard-new.
//
// Tier 4 path — operator filled out the new-product form because no master
// match existed. Creates Brand + Category + Product + Stock from scratch,
// no saas_brand_id linkage (the brand isn't in the SaaS catalog).
func (h *SmartPurchaseOnboardHandler) OnboardNew(c *gin.Context) {
	tenantID, userID, ok := h.requireAuth(c)
	if !ok {
		return
	}

	var req onboardNewRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.BrandName = strings.TrimSpace(req.BrandName)
	if req.BrandName == "" || req.SizeML <= 0 || req.MRP <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "brand_name, size_ml > 0, mrp > 0 are required"})
		return
	}
	shopID, err := uuid.Parse(req.ShopID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
		return
	}
	if req.Category == "" {
		req.Category = "Whisky"
	}

	// v1.0.386 — delegate to the shared tx-safe core (single create path).
	res, err := services.ResolveOrCreateShopProductNew(h.db.DB, tenantID, shopID, req.BrandName, req.SizeML, req.Category, req.MRP, req.CostPrice)
	if err != nil {
		h.logger.WithError(err).Error("OnboardNew: core failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "onboard failed"})
		return
	}
	h.logger.Infof("OnboardNew: %s product %s tenant=%s shop=%s name=%q (user=%s)",
		map[bool]string{true: "created", false: "matched"}[res.Created], res.ProductID, tenantID, shopID, res.Name, userID)

	status, action := http.StatusCreated, "created"
	if !res.Created {
		status, action = http.StatusOK, "matched_existing"
	}
	c.JSON(status, onboardResponse{
		ProductID:   res.ProductID.String(),
		ProductName: res.Name,
		Action:      action,
	})
}

// requireAuth pulls tenant + user from the gateway-injected context and
// returns ok=false (with a 401 already written) when either is missing.
func (h *SmartPurchaseOnboardHandler) requireAuth(c *gin.Context) (uuid.UUID, uuid.UUID, bool) {
	// REGRESSION FIX (chhotu's "Create from catalog → Invalid tenant or user ID"):
	// the gateway/middleware stores tenant_id / user_id in the gin context as
	// STRINGS (from the X-Tenant-ID / X-User-ID headers). The old code here
	// asserted `.(uuid.UUID)`, which ALWAYS failed → uuid.Nil → 500. The v1.0.231
	// fix migrated apply/vendor/replay to the shared string-parsing helpers but
	// MISSED this onboard handler. Use the canonical helpers (see
	// smart_purchase_context.go) so onboard-from-master / onboard-new work.
	tenantID, terr := tenantUUIDFromContext(c)
	if terr != nil {
		c.JSON(terr.status, gin.H{"error": terr.msg})
		return uuid.Nil, uuid.Nil, false
	}
	userID, uerr := userUUIDFromContext(c)
	if uerr != nil {
		c.JSON(uerr.status, gin.H{"error": uerr.msg})
		return uuid.Nil, uuid.Nil, false
	}
	return tenantID, userID, true
}

// resolveOrCreateCategory returns a category_id for the given (tenant, name).
// Creates a new category row when no case-insensitive match exists. Used by
// both onboarding paths so we don't silently fail on a missing category.
func (h *SmartPurchaseOnboardHandler) resolveOrCreateCategory(tenantID uuid.UUID, name string) (uuid.UUID, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		name = "Whisky"
	}
	var existing models.Category
	err := h.db.
		Where("tenant_id = ? AND deleted_at IS NULL AND LOWER(name) = LOWER(?)", tenantID, name).
		First(&existing).Error
	if err == nil {
		return existing.ID, nil
	}
	if err != gorm.ErrRecordNotFound {
		return uuid.Nil, err
	}
	cat := models.Category{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		Name:     name,
		IsActive: true,
	}
	if err := h.db.Create(&cat).Error; err != nil {
		return uuid.Nil, err
	}
	return cat.ID, nil
}

// resolveOrCreateBrand returns a brand_id for the given (tenant, name).
// Same idempotency pattern as category resolution.
func (h *SmartPurchaseOnboardHandler) resolveOrCreateBrand(tenantID uuid.UUID, name string) (uuid.UUID, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return uuid.Nil, gorm.ErrInvalidData
	}
	var existing models.Brand
	err := h.db.
		Where("tenant_id = ? AND deleted_at IS NULL AND LOWER(name) = LOWER(?)", tenantID, name).
		First(&existing).Error
	if err == nil {
		return existing.ID, nil
	}
	if err != gorm.ErrRecordNotFound {
		return uuid.Nil, err
	}
	br := models.Brand{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		Name:     name,
		IsActive: true,
	}
	if err := h.db.Create(&br).Error; err != nil {
		return uuid.Nil, err
	}
	return br.ID, nil
}

// ensureStockRow upserts a (shop, product) Stock row with quantity 0 if the
// row didn't already exist. Best-effort — failure is logged but not
// surfaced because the apply-purchase step that follows will create the
// row if needed via its own stock-write logic.
func (h *SmartPurchaseOnboardHandler) ensureStockRow(tenantID, shopID, productID uuid.UUID) {
	var count int64
	h.db.Model(&models.Stock{}).
		Where("tenant_id = ? AND shop_id = ? AND product_id = ? AND deleted_at IS NULL", tenantID, shopID, productID).
		Count(&count)
	if count > 0 {
		return
	}
	stock := models.Stock{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		ShopID:    shopID,
		ProductID: productID,
		Quantity:  0,
	}
	if err := h.db.Create(&stock).Error; err != nil {
		h.logger.WithError(err).Warnf("OnboardHandler: stock-row upsert failed for product=%s shop=%s", productID, shopID)
	}
}

// sizeMLString formats an int ML count as the bare "180ML" / "750ML" string.
// DEPRECATED for product.size writes — use canonicalSizeLabel so onboarded
// products match the rest of the catalog. Retained for any legacy callers.
func sizeMLString(ml int) string {
	return strconv.Itoa(ml) + "ML"
}

// mlFromSizeString extracts the ML count from ANY free-text products.size value
// ("375ml (Half)", "375ML", "375", "1L"). Mirrors services.extractML so the
// onboard idempotency check matches a stored product regardless of which size
// format wrote it. Without this, "Create from catalog" compared "375ML" against
// the tenant's canonical "375ml (Half)", never matched, and created malformed
// duplicate SKUs with no stock linkage (chhotu: "create from catalog not working").
func mlFromSizeString(size string) int {
	up := strings.ToUpper(strings.TrimSpace(size))
	digits := make([]rune, 0, len(up))
	for _, c := range up {
		if c >= '0' && c <= '9' {
			digits = append(digits, c)
		}
	}
	n := 0
	if len(digits) > 0 {
		n, _ = strconv.Atoi(string(digits))
	}
	// "1L" / "1 L" (no ML) → 1000ml.
	if strings.Contains(up, "L") && !strings.Contains(up, "ML") && n < 100 {
		return n * 1000
	}
	return n
}

// canonicalSizeLabel maps an ML count to the tenant's canonical size label
// ("90ml (Nip)", "180ml (Quarter)", "375ml (Half)", "750ml (Full)", "1L+ (Large)"
// — beer uses its own buckets). New onboarded products MUST use this so the
// matcher, size filter and grouping (which all key on the label) line up with
// the existing catalog instead of an odd "375ML" row that groups with nothing.
// Mirrors the buckets in services.nonBeerSizeRanges / beerSizeRanges.
func canonicalSizeLabel(ml int, category string) string {
	if strings.Contains(strings.ToLower(category), "beer") {
		switch {
		case ml <= 400:
			return "330ml & Below"
		case ml <= 550:
			return "500ml"
		case ml <= 999:
			return "650ml"
		default:
			return "Keg/Bulk"
		}
	}
	switch {
	case ml <= 100:
		return "90ml (Nip)"
	case ml <= 250:
		return "180ml (Quarter)"
	case ml <= 400:
		return "375ml (Half)"
	case ml <= 999:
		return "750ml (Full)"
	default:
		return "1L+ (Large)"
	}
}

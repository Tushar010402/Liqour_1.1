package services

import (
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// smart_purchase_onboard_core.go — v1.0.386
//
// Transaction-safe product onboarding shared by BOTH the HTTP onboard handlers
// (Flutter's "Create from catalog" chips) AND the apply path (authoritative
// auto-onboard so NOTHING is ever dropped — chhotu's 30→27 bug). Previously the
// only create-product logic lived in handlers.SmartPurchaseOnboardHandler using
// the non-tx h.db, so the apply transaction could not create a product for an
// item that matched the master catalog but had no shop SKU yet — it skipped the
// row ("no_product") and the purchase silently saved 27/30.
//
// These functions take an explicit *gorm.DB so they run INSIDE the apply tx
// (atomic with the stock_purchase_items insert), and the handlers call them with
// the autocommit h.db.DB — one code path, identical idempotency.

// OnboardCoreResult is the outcome of resolving-or-creating a shop product.
type OnboardCoreResult struct {
	ProductID uuid.UUID
	Name      string
	Created   bool // false = idempotent hit (product already existed)
}

// ResolveOrCreateShopProductFromMaster resolves (or creates) the shop's product
// for a master saas_brand + size. Idempotent on (tenant, shop, saas_brand,
// size_ml) — size matched by extracted ML so canonical "375ml (Half)" and legacy
// "375ML" rows both hit. Covers the master_create_shop_product onboarding tier.
// Runs entirely on tx. costPrice<=0 falls back to master MRP*0.6.
//
// mrpHint / categoryHint let the caller supply the SIZE-specific MRP + category
// (the apply path passes the onboarding payload's values, which the orchestrator
// already resolved from brand_variants). When a hint is empty the core fetches
// it from brand_variants itself — NOTE saas_brands carries only name/display_name
// (no mrp/category columns), so MRP/category MUST come from brand_variants.
func ResolveOrCreateShopProductFromMaster(tx *gorm.DB, tenantID, shopID, saasBrandID uuid.UUID, sizeML int, costPrice, mrpHint float64, categoryHint string) (*OnboardCoreResult, error) {
	if sizeML <= 0 {
		return nil, fmt.Errorf("onboard-from-master: size_ml required")
	}

	// 1. Load the master name from saas_brands (the only identity columns it has).
	var master struct {
		Name        string
		DisplayName string
		MRP         float64
		Category    string
	}
	row := tx.Raw(`
		SELECT name, COALESCE(NULLIF(display_name, ''), name) AS display_name
		FROM saas_brands
		WHERE id = ? AND deleted_at IS NULL
		LIMIT 1
	`, saasBrandID).Row()
	if err := row.Scan(&master.Name, &master.DisplayName); err != nil {
		return nil, fmt.Errorf("onboard-from-master: saas_brand %s not found: %w", saasBrandID, err)
	}
	// Size-specific MRP + category: caller hints first, else brand_variants.
	master.MRP, master.Category = mrpHint, categoryHint
	if master.MRP <= 0 || master.Category == "" {
		fm, fc := fetchMasterVariantMRPCategoryTx(tx, saasBrandID, sizeML)
		if master.MRP <= 0 {
			master.MRP = fm
		}
		if master.Category == "" {
			master.Category = fc
		}
	}
	if master.Category == "" {
		master.Category = "Whisky"
	}

	// 2. Idempotency — match an existing shop product for this saas_brand whose
	// size (normalised to ML) equals sizeML. v1.0.241 strict shop scope.
	var candidates []models.Product
	if err := tx.Where("tenant_id = ? AND deleted_at IS NULL AND saas_brand_id = ? AND shop_id = ?",
		tenantID, saasBrandID, shopID).Find(&candidates).Error; err != nil {
		return nil, fmt.Errorf("onboard-from-master: existing-product lookup: %w", err)
	}
	for i := range candidates {
		if extractML(candidates[i].Size) == sizeML {
			ensureStockRowTx(tx, tenantID, shopID, candidates[i].ID)
			return &OnboardCoreResult{ProductID: candidates[i].ID, Name: candidates[i].Name, Created: false}, nil
		}
	}

	// 3. Resolve category + brand (Product demands non-null category_id + brand_id).
	categoryID, err := resolveOrCreateCategoryTx(tx, tenantID, master.Category)
	if err != nil {
		return nil, fmt.Errorf("onboard-from-master: category resolve: %w", err)
	}
	brandID, err := resolveOrCreateBrandTx(tx, tenantID, master.Name)
	if err != nil {
		return nil, fmt.Errorf("onboard-from-master: brand resolve: %w", err)
	}

	// 4. Cost defaults to MRP*0.6 (UP IMFL wholesale margin) when unset.
	if costPrice <= 0 && master.MRP > 0 {
		costPrice = master.MRP * 0.6
	}

	// 5. Create the product linked to the master saas_brand.
	product := models.Product{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		ShopID:       &shopID,
		Name:         master.Name,
		CategoryID:   categoryID,
		BrandID:      brandID,
		SaaSBrandID:  &saasBrandID,
		Size:         canonicalSizeLabel(sizeML, master.Category),
		IsActive:     true,
		CostPrice:    costPrice,
		SellingPrice: master.MRP,
		MRP:          master.MRP,
		DisplayName:  master.DisplayName,
	}
	if err := tx.Create(&product).Error; err != nil {
		return nil, fmt.Errorf("onboard-from-master: product create: %w", err)
	}

	// 6. Stock row qty=0 placeholder (apply writes the actual bottles after).
	ensureStockRowTx(tx, tenantID, shopID, product.ID)

	return &OnboardCoreResult{ProductID: product.ID, Name: product.Name, Created: true}, nil
}

// ResolveOrCreateShopProductNew resolves (or creates) a fully-new shop product
// (no master saas_brand link). Idempotent on (tenant, shop, LOWER(name),
// size_ml). Covers the fully_new onboarding tier. mrp<=0 falls back to a
// cost-derived MRP so a missing master MRP never blocks the save; costPrice<=0
// falls back to mrp*0.6. Runs entirely on tx.
func ResolveOrCreateShopProductNew(tx *gorm.DB, tenantID, shopID uuid.UUID, name string, sizeML int, category string, mrp, costPrice float64) (*OnboardCoreResult, error) {
	name = strings.TrimSpace(name)
	if name == "" || sizeML <= 0 {
		return nil, fmt.Errorf("onboard-new: name + size_ml required")
	}
	if strings.TrimSpace(category) == "" {
		category = "Whisky"
	}

	// Idempotency — same name+shop, size normalised to ML.
	var candidates []models.Product
	if err := tx.Where("tenant_id = ? AND deleted_at IS NULL AND LOWER(name) = LOWER(?) AND shop_id = ?",
		tenantID, name, shopID).Find(&candidates).Error; err != nil {
		return nil, fmt.Errorf("onboard-new: existing-product lookup: %w", err)
	}
	for i := range candidates {
		if extractML(candidates[i].Size) == sizeML {
			ensureStockRowTx(tx, tenantID, shopID, candidates[i].ID)
			return &OnboardCoreResult{ProductID: candidates[i].ID, Name: candidates[i].Name, Created: false}, nil
		}
	}

	categoryID, err := resolveOrCreateCategoryTx(tx, tenantID, category)
	if err != nil {
		return nil, fmt.Errorf("onboard-new: category resolve: %w", err)
	}
	brandID, err := resolveOrCreateBrandTx(tx, tenantID, name)
	if err != nil {
		return nil, fmt.Errorf("onboard-new: brand resolve: %w", err)
	}

	// Never block on a missing MRP — derive a placeholder from cost so the row
	// still saves (honours "nothing dropped"). Operator can correct MRP later.
	if mrp <= 0 {
		if costPrice > 0 {
			mrp = costPrice / 0.6
		}
	}
	if costPrice <= 0 && mrp > 0 {
		costPrice = mrp * 0.6
	}

	product := models.Product{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		ShopID:       &shopID,
		Name:         name,
		CategoryID:   categoryID,
		BrandID:      brandID,
		Size:         canonicalSizeLabel(sizeML, category),
		IsActive:     true,
		CostPrice:    costPrice,
		SellingPrice: mrp,
		MRP:          mrp,
		DisplayName:  name,
	}
	if err := tx.Create(&product).Error; err != nil {
		return nil, fmt.Errorf("onboard-new: product create: %w", err)
	}
	ensureStockRowTx(tx, tenantID, shopID, product.ID)

	return &OnboardCoreResult{ProductID: product.ID, Name: product.Name, Created: true}, nil
}

// fetchMasterVariantMRPCategoryTx returns the size-specific MRP + category name
// from the master catalog's brand_variants (joined to brand_categories), keyed
// by saas_brand_id + "<ml>ML". Package-level tx twin of the orchestrator's
// fetchMasterVariantMRPCategory so the onboard core can reach it. Returns (0,"")
// when the variant isn't catalogued — callers default safely.
func fetchMasterVariantMRPCategoryTx(tx *gorm.DB, saasBrandID uuid.UUID, sizeML int) (float64, string) {
	if saasBrandID == uuid.Nil || sizeML <= 0 {
		return 0, ""
	}
	var r struct {
		MRP      float64 `gorm:"column:mrp"`
		Category string  `gorm:"column:category"`
	}
	err := tx.Raw(`
		SELECT bv.mrp AS mrp, COALESCE(bc.name, '') AS category
		FROM brand_variants bv
		LEFT JOIN brand_categories bc ON bv.category_id = bc.id
		WHERE bv.deleted_at IS NULL
		  AND bv.brand_id = ?
		  AND UPPER(bv.size) = UPPER(?)
		LIMIT 1
	`, saasBrandID, fmt.Sprintf("%dML", sizeML)).Scan(&r).Error
	if err != nil {
		return 0, ""
	}
	return r.MRP, r.Category
}

// resolveOrCreateCategoryTx returns a category_id for (tenant, name), creating
// it on case-insensitive miss. tx-safe twin of the handler's resolver.
func resolveOrCreateCategoryTx(tx *gorm.DB, tenantID uuid.UUID, name string) (uuid.UUID, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		name = "Whisky"
	}
	var existing models.Category
	err := tx.Where("tenant_id = ? AND deleted_at IS NULL AND LOWER(name) = LOWER(?)", tenantID, name).
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
	if err := tx.Create(&cat).Error; err != nil {
		return uuid.Nil, err
	}
	return cat.ID, nil
}

// resolveOrCreateBrandTx returns a brand_id for (tenant, name) by exact
// (normalised) match, creating it on miss. tx-safe twin of the handler's
// resolver — exact match (not fuzzy) to keep idempotency parity with products
// the HTTP onboard endpoints already created.
func resolveOrCreateBrandTx(tx *gorm.DB, tenantID uuid.UUID, name string) (uuid.UUID, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return uuid.Nil, gorm.ErrInvalidData
	}
	var existing models.Brand
	err := tx.Where("tenant_id = ? AND deleted_at IS NULL AND LOWER(name) = LOWER(?)", tenantID, name).
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
	if err := tx.Create(&br).Error; err != nil {
		return uuid.Nil, err
	}
	return br.ID, nil
}

// ensureStockRowTx upserts a (shop, product) Stock row with qty 0 when absent.
// Best-effort — failure is swallowed (the apply stock-write that follows creates
// the row if needed). tx-safe twin of the handler's ensureStockRow.
func ensureStockRowTx(tx *gorm.DB, tenantID, shopID, productID uuid.UUID) {
	var count int64
	tx.Model(&models.Stock{}).
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
	_ = tx.Create(&stock).Error
}

// canonicalSizeLabel maps an ML count to the tenant's canonical size label so
// onboarded products group/filter with the rest of the catalog (services twin
// of the handler's canonicalSizeLabel — kept in sync). Mirrors the buckets in
// nonBeerSizeRanges / beerSizeRanges.
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

package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/sizing"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

// ProductService handles product management operations
type ProductService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewProductService creates a new product service
func NewProductService(db *database.DB, cache *cache.Cache) *ProductService {
	return &ProductService{
		db:    db,
		cache: cache,
	}
}

// ProductRequest represents product creation/update request
type ProductRequest struct {
	Name           string    `json:"name" binding:"required"`
	DisplayName    string    `json:"display_name"`
	// DisplayNameBoldStart + DisplayNameBoldLength jointly define the bold
	// range [start, start+length) inside DisplayName. Start defaults to 0
	// (prefix); length 0/NULL = no styling.
	DisplayNameBoldStart  *int      `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int      `json:"display_name_bold_length,omitempty"`
	CategoryID     uuid.UUID `json:"category_id" binding:"required"`
	BrandID        uuid.UUID `json:"brand_id" binding:"required"`
	Size           string    `json:"size" binding:"required"`
	AlcoholContent float64   `json:"alcohol_content"`
	Description    string    `json:"description"`
	Barcode        string    `json:"barcode"`
	SKU            string    `json:"sku"`
	CostPrice      float64   `json:"cost_price" binding:"required,gt=0"`
	SellingPrice   float64   `json:"selling_price" binding:"required,gt=0"`
	MRP            float64   `json:"mrp" binding:"required,gt=0"`
	IsActive       bool      `json:"is_active"`
}

// ProductResponse represents product in responses
type ProductResponse struct {
	ID             uuid.UUID `json:"id"`
	Name           string    `json:"name"`
	CategoryID     uuid.UUID `json:"category_id"`
	CategoryName   string    `json:"category_name"`
	BrandID        uuid.UUID `json:"brand_id"`
	BrandName      string    `json:"brand_name"`
	Size           string    `json:"size"`
	AlcoholContent float64   `json:"alcohol_content"`
	Description    string    `json:"description"`
	Barcode        string    `json:"barcode"`
	SKU            string    `json:"sku"`
	CostPrice      float64   `json:"cost_price"`
	SellingPrice   float64   `json:"selling_price"`
	MRP            float64   `json:"mrp"`
	Price          float64   `json:"price"`
	DisplayName    string    `json:"display_name"`
	DisplayNameBoldStart  *int `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int `json:"display_name_bold_length,omitempty"`
	IsActive       bool      `json:"is_active"`
	CurrentStock   int       `json:"current_stock"`
	SaasBrandID    *uuid.UUID `json:"saas_brand_id,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
	// Purchase-priority enrichments (only populated when ProductFilters.PurchasePriority=true).
	// PurchasePriority: 1=bought in last 90d, 2=currently in stock, 3=ever bought, 4=master only.
	// LastPurchasedAt is the most recent purchase_date for this product in this shop, or nil.
	PurchasePriority *int       `json:"purchase_priority,omitempty"`
	LastPurchasedAt  *time.Time `json:"last_purchased_at,omitempty"`
	// v1.0.250 — Front/Back photo verification fields surfaced so the same
	// images appear everywhere the product is shown (inventory list, Manual
	// Purchase picker, edit screen). When verified=true the URL is durable
	// (/uploads/stock_setup/verifications/... served via nginx).
	FrontImageURL         string     `json:"front_image_url,omitempty"`
	BackImageURL          string     `json:"back_image_url,omitempty"`
	BackImageMRP          float64    `json:"back_image_mrp,omitempty"`
	VerifiedViaImageFront bool       `json:"verified_via_image_front,omitempty"`
	VerifiedViaImageBack  bool       `json:"verified_via_image_back,omitempty"`
	PhotoVerifiedAt       *time.Time `json:"photo_verified_at,omitempty"`
}

// BrandPricingRequest represents brand pricing request
type BrandPricingRequest struct {
	BrandID      uuid.UUID `json:"brand_id" binding:"required"`
	Size         string    `json:"size" binding:"required"`
	CostPrice    float64   `json:"cost_price" binding:"required,gt=0"`
	SellingPrice float64   `json:"selling_price" binding:"required,gt=0"`
	MRP          float64   `json:"mrp" binding:"required,gt=0"`
}

// CreateProduct creates a new product
func (s *ProductService) CreateProduct(ctx context.Context, req ProductRequest, tenantID uuid.UUID) (*ProductResponse, error) {
	// Verify category exists
	var category models.Category
	if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
		return nil, errors.New("category not found")
	}

	// Verify brand exists
	var brand models.Brand
	if err := s.db.Where("id = ? AND tenant_id = ?", req.BrandID, tenantID).First(&brand).Error; err != nil {
		return nil, errors.New("brand not found")
	}

	// v1.0.219 — canonicalise size at the write boundary so garbage like
	// "180ML1" or "8375" never lands in products.size. Rejecting at the API
	// keeps the chip strips honest in every downstream screen.
	if req.Size != "" {
		canonical, _, _, ok := sizing.Canonicalize(req.Size, sizing.CategoryIsBeer(category.Name))
		if !ok {
			return nil, fmt.Errorf("invalid size '%s' — must be one of: 90ml, 180ml, 375ml, 750ml, 1000ml (or 330ml/500ml/650ml for beer)", req.Size)
		}
		req.Size = canonical
	}

	// Check for duplicate SKU if provided
	if req.SKU != "" {
		var existing models.Product
		if err := s.db.Where("sku = ? AND tenant_id = ?", req.SKU, tenantID).First(&existing).Error; err == nil {
			return nil, errors.New("product with this SKU already exists")
		}
	} else {
		// Generate SKU if not provided
		req.SKU = s.generateSKU(brand.Name, req.Size)
	}

	// Auto-set display_name from brand name if not provided
	displayName := req.DisplayName
	if displayName == "" {
		displayName = brand.Name
	}

	// Auto-link to master catalog if a confident match exists (saas_brands + brand_variants).
	// Keeps manually-created products in sync with the authoritative excise catalog, which
	// future AI matching, reporting, and duplicate prevention rely on.
	saasBrandID, saasVariantID := s.findMasterLinkage(tenantID, req.Name, brand.Name, req.Size, req.MRP)

	// Normalize bold range (start, length) so it never exceeds display_name bounds.
	boldStart, boldLen := sanitizeBoldRange(req.DisplayNameBoldStart, req.DisplayNameBoldLength, displayName)

	// Create product
	product := models.Product{
		TenantModel:           models.TenantModel{TenantID: &tenantID},
		Name:                  req.Name,
		DisplayName:           displayName,
		DisplayNameBoldStart:  boldStart,
		DisplayNameBoldLength: boldLen,
		CategoryID:     req.CategoryID,
		BrandID:        req.BrandID,
		SaaSBrandID:    saasBrandID,
		SaaSVariantID:  saasVariantID,
		Size:           req.Size,
		AlcoholContent: req.AlcoholContent,
		Description:    req.Description,
		Barcode:        req.Barcode,
		SKU:            req.SKU,
		CostPrice:      req.CostPrice,
		SellingPrice:   req.SellingPrice,
		MRP:            req.MRP,
		IsActive:       req.IsActive,
		CreatedVia:     "manual", // 2026-05-18 — provenance (exempt from AI-Purchase image gate)
		Category:       &category,
		Brand:          &brand,
	}

	if err := s.db.Create(&product).Error; err != nil {
		return nil, fmt.Errorf("failed to create product: %w", err)
	}
	if saasBrandID != nil {
		// Log when linkage is established so we can track adoption from logs without
		// querying the DB.
		fmt.Printf("ProductService: Created product '%s' linked to master saas_brand_id=%s\n", req.Name, saasBrandID.String()[:8])
	}

	// Clear cache
	s.clearProductCache(ctx, tenantID)

	return s.mapProductToResponse(&product, 0), nil
}

// GetProducts returns paginated list of products
func (s *ProductService) GetProducts(ctx context.Context, tenantID uuid.UUID, filters ProductFilters) (*ProductListResponse, error) {
	var products []models.Product
	var totalCount int64

	query := s.db.Model(&models.Product{}).
		Where("tenant_id = ?", tenantID).
		Preload("Category").
		Preload("Brand")

	// Apply filters
	// Priority: CategoryIDs (multiple) > CategoryID (single)
	if len(filters.CategoryIDs) > 0 {
		query = query.Where("category_id IN ?", filters.CategoryIDs)
	} else if filters.CategoryID != uuid.Nil {
		query = query.Where("category_id = ?", filters.CategoryID)
	}
	if filters.BrandID != uuid.Nil {
		query = query.Where("brand_id = ?", filters.BrandID)
	}
	// Ownership filter: restrict to products this shop OWNS, regardless of
	// stock presence. Unlike ShopID (stock-presence), this is the correct
	// scope for a per-shop picker — a manager setting up a shop's shelf must
	// only see/pick that shop's own SKUs, so we never re-introduce a link to
	// another shop's product (which trg_block_crossshop_stock rejects at
	// approve). Applied to the COUNT, the list, and the TotalStock subquery
	// because they all derive from this same `query`.
	if filters.OwnerShopID != uuid.Nil {
		query = query.Where("products.shop_id = ?", filters.OwnerShopID)
	}
	if filters.Size != "" {
		// Check if this is a range label (contains parenthesis or "Below" or "Bulk")
		isRange := false
		var minML, maxML int
		allRanges := append(beerSizeRanges, nonBeerSizeRanges...)
		for _, rng := range allRanges {
			if strings.EqualFold(rng.Label, filters.Size) {
				isRange = true
				minML = rng.MinML
				maxML = rng.MaxML
				break
			}
		}
		if isRange {
			// Range-based filter: find products whose size in ml falls within range
			// Build list of matching sizes from existing products
			var matchingSizes []string
			s.db.WithContext(ctx).Table("products").
				Select("DISTINCT UPPER(size)").
				Where("tenant_id = ? AND deleted_at IS NULL AND is_active = true AND size IS NOT NULL AND size != ''", tenantID).
				Scan(&matchingSizes)
			var filteredSizes []string
			for _, sz := range matchingSizes {
				ml := extractML(sz)
				if ml >= minML && ml <= maxML {
					filteredSizes = append(filteredSizes, sz)
				}
			}
			if len(filteredSizes) > 0 {
				query = query.Where("UPPER(size) IN ?", filteredSizes)
			} else {
				query = query.Where("1 = 0") // no matching sizes
			}
		} else {
			// Exact size match (backward compatible)
			query = query.Where("UPPER(size) = UPPER(?)", filters.Size)
		}
	}
	if filters.IsActive != nil {
		query = query.Where("is_active = ?", *filters.IsActive)
	}
	if filters.Search != "" {
		// Tokenized AND search across the fields the user actually sees
		// in the picker: tenant name/sku/barcode, the tenant's display_name
		// override, and the master saas_brand name (which is what falls
		// back into the picker label when display_name is empty). Each
		// whitespace-separated token must hit at least one of those fields.
		//
		// Why not a single "%<query>%" substring: real catalog names
		// interleave brand + line + variant + size ("M2 Magic Moments
		// Jamun Spicymint Flavoured Vodka"), so a user typing
		// "m2 jamun" gets zero hits from plain ILIKE. Tokenizing fixes
		// that without needing pg_trgm.
		//
		// Why EXISTS instead of JOIN on saas_brands: several column names
		// (name, size, is_active, deleted_at) are also present on
		// saas_brands, and the unqualified Where clauses earlier in this
		// function would become ambiguous under a JOIN.
		rawTokens := strings.Fields(strings.ToLower(filters.Search))
		tokens := make([]string, 0, len(rawTokens))
		for _, t := range rawTokens {
			if len(t) < 2 {
				continue
			}
			tokens = append(tokens, t)
			if len(tokens) >= 8 {
				break
			}
		}
		for _, tok := range tokens {
			pattern := "%" + tok + "%"
			query = query.Where(
				"products.name ILIKE ? OR products.sku ILIKE ? OR products.barcode ILIKE ? OR products.display_name ILIKE ? OR EXISTS (SELECT 1 FROM saas_brands sb WHERE sb.id = products.saas_brand_id AND sb.deleted_at IS NULL AND sb.name ILIKE ?)",
				pattern, pattern, pattern, pattern, pattern,
			)
		}
	}
	// Shop filter: only return products that have a stock record in the specified shop.
	// PurchasePriority intentionally bypasses both the in-shop filter AND the zero-stock
	// filter so the entire master catalog is available — the picker sorts master items
	// to the bottom rather than hiding them. The operator can still purchase a brand-new
	// SKU on a one-off basis without admins having to seed inventory first.
	if filters.ShopID != uuid.Nil && !filters.PurchasePriority {
		query = query.Where("products.id IN (SELECT product_id FROM stocks WHERE shop_id = ? AND deleted_at IS NULL)", filters.ShopID)

		// Hide products with zero stock in this shop by default — the inventory
		// list should show what you HAVE, not every SKU you've ever stocked.
		// Tushar's Mahua Khera shop accumulated 22 zero-stock SKUs from prior
		// stock-setup runs that overwrote rows to 0 (manual entries, swap-pick
		// failures, sold-out items). Showing them as noisy 0-rows obscures the
		// real inventory. Admins pass ?include_zero_stock=true to see everything
		// (e.g. for cleanup, re-stocking decisions).
		if !filters.IncludeZeroStock {
			query = query.Where(
				`COALESCE((SELECT SUM(quantity) FROM stocks WHERE product_id = products.id AND shop_id = ? AND deleted_at IS NULL), 0) > 0`,
				filters.ShopID,
			)
		}
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count products: %w", err)
	}

	// v1.0.299 — TotalStock: SUM of stocks.quantity over the full filtered
	// set at this shop, independent of pagination. The Flutter inventory-list
	// header shows this so the visible "X pcs" matches the approved record
	// total regardless of which page is loaded. Previously the header summed
	// only the current page (kProductPageSize=30 in Flutter) — chhotu's 180ml
	// record had 31 products with the 31st on page 2 carrying 141 units, so
	// the header read 2770 instead of 2911. With this field the header is
	// always SUM(stocks.quantity) across every product matching the same
	// filters as TotalCount, computed in a single SQL aggregate.
	//
	// Only computed when a shop is filtered (stock is per-shop). When no
	// shop is in scope (admin tenant-wide list), totalStock stays 0 and the
	// Flutter side falls back to its previous per-page sum.
	var totalStock int64
	if filters.ShopID != uuid.Nil && !filters.PurchasePriority {
		// Reuse the exact same query (already carries WHERE-clause filters
		// for tenant, category, size, search, is_active, shop in-stock, etc.)
		// but project the stock SUM and reset pagination/order so Count's
		// LIMIT/OFFSET don't apply. GORM's .Session(&gorm.Session{}) gives
		// us a fresh statement built from the same WHERE tree.
		stockSubq := s.db.WithContext(ctx).
			Table("(?) AS p_filtered", query.Session(&gorm.Session{}).Select("products.id")).
			Select("COALESCE(SUM(stocks.quantity), 0)").
			Joins("JOIN stocks ON stocks.product_id = p_filtered.id AND stocks.shop_id = ? AND stocks.deleted_at IS NULL", filters.ShopID)
		if err := stockSubq.Row().Scan(&totalStock); err != nil {
			// Non-fatal: the page list still works, header falls back.
			log.Printf("GetProducts: total_stock SUM failed (non-fatal): %v", err)
			totalStock = 0
		}
	}

	// Pagination: in PurchasePriority mode we fetch the entire matching set
	// (no SQL offset/limit) so the Go-side priority sort sees every row, then
	// apply the limit/offset in memory. Master catalogs cap at ~2000 rows for
	// liquor SKUs, well under any concerning memory footprint.
	dbQuery := query
	if !filters.PurchasePriority {
		offset := (filters.Page - 1) * filters.PageSize
		dbQuery = dbQuery.Offset(offset).Limit(filters.PageSize).Order("name ASC")
	} else {
		dbQuery = dbQuery.Order("LOWER(products.name) ASC")
	}
	if err := dbQuery.Find(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to get products: %w", err)
	}

	// Convert to response format
	// NOTE: We don't include stock here because stock is shop-specific
	// and products are tenant-wide. Stock should be fetched separately
	// via the /api/inventory/stock endpoint with shop_id parameter.
	responses := make([]*ProductResponse, len(products))
	for i, product := range products {
		responses[i] = s.mapProductToResponse(&product, 0)
	}

	// Backfill display_name_bold_* from the linked master saas_brand when the
	// product row doesn't have its own bold range configured. Only 15/209
	// products have bold configured locally; most inherit from the master
	// catalog (1600+ rows), so without this fallback the Flutter app + web
	// admin render everything as a flat un-emphasized line and the
	// "bold distinctive identifier" UX the master catalog was designed for
	// never fires on Inventory / Daily Sales Entry rows.
	s.applyDisplayBoldFallback(responses, products)

	// Purchase-priority enrichment: tag each product with a tier (1-4) based on
	// recent purchase history + current stock for the requested shop, then sort
	// so "what the operator actually buys" floats to the top. Saves the user
	// scrolling through hundreds of master-catalog SKUs they will never order.
	if filters.PurchasePriority && filters.ShopID != uuid.Nil && len(responses) > 0 {
		s.enrichWithPurchasePriority(ctx, responses, filters.ShopID)

		// Apply offset/limit in Go after the priority sort so the frontend
		// still sees pagination semantics.
		offset := (filters.Page - 1) * filters.PageSize
		if offset > len(responses) {
			offset = len(responses)
		}
		end := offset + filters.PageSize
		if end > len(responses) {
			end = len(responses)
		}
		totalCount = int64(len(responses))
		responses = responses[offset:end]
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &ProductListResponse{
		Products:   responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
		TotalStock: totalStock,
	}, nil
}

// enrichWithPurchasePriority adds purchase_priority + last_purchased_at + current_stock
// to each ProductResponse and re-sorts the slice so tier-1 (recently purchased) products
// float to the top. Two batched queries: one MAX(purchase_date) per product_id from
// stock_purchases joined to stock_purchase_items in this shop, one SUM(stock.quantity)
// per product_id in this shop. Single sweep through responses to assign tiers.
func (s *ProductService) enrichWithPurchasePriority(ctx context.Context, responses []*ProductResponse, shopID uuid.UUID) {
	if len(responses) == 0 {
		return
	}
	productIDs := make([]uuid.UUID, len(responses))
	for i, r := range responses {
		productIDs[i] = r.ID
	}

	type purchaseRow struct {
		ProductID       uuid.UUID `gorm:"column:product_id"`
		LastPurchasedAt time.Time `gorm:"column:last_purchased_at"`
	}
	var purchaseRows []purchaseRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT spi.product_id AS product_id, MAX(sp.purchase_date) AS last_purchased_at
		FROM stock_purchase_items spi
		JOIN stock_purchases sp ON sp.id = spi.purchase_id
		WHERE sp.shop_id = ? AND spi.product_id IN ? AND sp.deleted_at IS NULL AND spi.deleted_at IS NULL
		GROUP BY spi.product_id
	`, shopID, productIDs).Scan(&purchaseRows).Error; err != nil {
		// Soft failure: enrichment is advisory; on error fall back to all-tier-4.
		purchaseRows = nil
	}
	lastPurchase := make(map[uuid.UUID]time.Time, len(purchaseRows))
	for _, r := range purchaseRows {
		lastPurchase[r.ProductID] = r.LastPurchasedAt
	}

	type stockRow struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		Qty       int       `gorm:"column:qty"`
	}
	var stockRows []stockRow
	if err := s.db.WithContext(ctx).Raw(`
		SELECT product_id, COALESCE(SUM(quantity), 0) AS qty
		FROM stocks
		WHERE shop_id = ? AND product_id IN ? AND deleted_at IS NULL
		GROUP BY product_id
	`, shopID, productIDs).Scan(&stockRows).Error; err != nil {
		stockRows = nil
	}
	currentStock := make(map[uuid.UUID]int, len(stockRows))
	for _, r := range stockRows {
		currentStock[r.ProductID] = r.Qty
	}

	ninetyDaysAgo := time.Now().Add(-90 * 24 * time.Hour)
	for _, resp := range responses {
		if t, ok := lastPurchase[resp.ID]; ok {
			tCopy := t
			resp.LastPurchasedAt = &tCopy
		}
		if qty, ok := currentStock[resp.ID]; ok && qty > 0 {
			resp.CurrentStock = qty
		}
		var tier int
		switch {
		case resp.LastPurchasedAt != nil && resp.LastPurchasedAt.After(ninetyDaysAgo):
			tier = 1
		case resp.CurrentStock > 0:
			tier = 2
		case resp.LastPurchasedAt != nil:
			tier = 3
		default:
			tier = 4
		}
		t := tier
		resp.PurchasePriority = &t
	}

	// Stable sort: tier asc, then last_purchased_at desc within tier (most
	// recent re-orders show first), then name asc as a final tiebreak.
	sort.SliceStable(responses, func(i, j int) bool {
		ti, tj := 4, 4
		if responses[i].PurchasePriority != nil {
			ti = *responses[i].PurchasePriority
		}
		if responses[j].PurchasePriority != nil {
			tj = *responses[j].PurchasePriority
		}
		if ti != tj {
			return ti < tj
		}
		li, lj := responses[i].LastPurchasedAt, responses[j].LastPurchasedAt
		if li != nil && lj != nil && !li.Equal(*lj) {
			return li.After(*lj)
		}
		if li != nil && lj == nil {
			return true
		}
		if li == nil && lj != nil {
			return false
		}
		return strings.ToLower(responses[i].Name) < strings.ToLower(responses[j].Name)
	})
}

// GetProductByID returns product by ID
func (s *ProductService) GetProductByID(ctx context.Context, productID, tenantID uuid.UUID) (*ProductResponse, error) {
	var product models.Product

	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).
		Preload("Category").
		Preload("Brand").
		First(&product).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("product not found")
		}
		return nil, fmt.Errorf("failed to get product: %w", err)
	}

	// NOTE: We don't include stock here because stock is shop-specific
	// and products are tenant-wide. Stock should be fetched separately
	// via the /api/inventory/stock endpoint with shop_id parameter.
	resp := s.mapProductToResponse(&product, 0)
	s.applyDisplayBoldFallback([]*ProductResponse{resp}, []models.Product{product})
	return resp, nil
}

// UpdateProduct updates product information
func (s *ProductService) UpdateProduct(ctx context.Context, productID, tenantID uuid.UUID, req ProductRequest) (*ProductResponse, error) {
	var product models.Product

	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("product not found")
		}
		return nil, fmt.Errorf("failed to find product: %w", err)
	}

	// Verify category if changed
	if req.CategoryID != product.CategoryID {
		var category models.Category
		if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
			return nil, errors.New("category not found")
		}
	}

	// Verify brand if changed
	if req.BrandID != product.BrandID {
		var brand models.Brand
		if err := s.db.Where("id = ? AND tenant_id = ?", req.BrandID, tenantID).First(&brand).Error; err != nil {
			return nil, errors.New("brand not found")
		}
	}

	// Check SKU uniqueness if changed
	if req.SKU != "" && req.SKU != product.SKU {
		var existing models.Product
		if err := s.db.Where("sku = ? AND tenant_id = ? AND id != ?", req.SKU, tenantID, productID).First(&existing).Error; err == nil {
			return nil, errors.New("product with this SKU already exists")
		}
	}

	// v1.0.219 — canonicalise size on update too. Look up the new category
	// (or fall back to the existing one) so beer vs non-beer routing is
	// correct when the operator hasn't changed the category.
	if req.Size != "" {
		catName := ""
		if req.CategoryID != uuid.Nil {
			var cat models.Category
			if err := s.db.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&cat).Error; err == nil {
				catName = cat.Name
			}
		}
		if catName == "" && product.Category != nil {
			catName = product.Category.Name
		}
		canonical, _, _, ok := sizing.Canonicalize(req.Size, sizing.CategoryIsBeer(catName))
		if !ok {
			return nil, fmt.Errorf("invalid size '%s' — must be one of: 90ml, 180ml, 375ml, 750ml, 1000ml (or 330ml/500ml/650ml for beer)", req.Size)
		}
		req.Size = canonical
	}

	// Update product
	// display_name + display_name_bold_length are updatable from the admin portal.
	// When the caller provides a new DisplayName we save it and clamp the bold length
	// to its new bounds; when they clear DisplayName we clear the bold length too so
	// the row stays internally consistent.
	displayName := req.DisplayName
	if displayName == "" {
		displayName = product.DisplayName
	}
	boldStart, boldLen := sanitizeBoldRange(req.DisplayNameBoldStart, req.DisplayNameBoldLength, displayName)

	updates := map[string]interface{}{
		"name":                      req.Name,
		"category_id":               req.CategoryID,
		"brand_id":                  req.BrandID,
		"size":                      req.Size,
		"alcohol_content":           req.AlcoholContent,
		"description":               req.Description,
		"barcode":                   req.Barcode,
		"sku":                       req.SKU,
		"cost_price":                req.CostPrice,
		"selling_price":             req.SellingPrice,
		"mrp":                       req.MRP,
		"is_active":                 req.IsActive,
		"display_name":              displayName,
		"display_name_bold_start":   boldStart,
		"display_name_bold_length":  boldLen,
	}

	if err := s.db.Model(&product).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update product: %w", err)
	}

	// Clear cache
	s.clearProductCache(ctx, tenantID)

	// Get updated product
	return s.GetProductByID(ctx, productID, tenantID)
}

// DeleteProduct soft deletes a product
func (s *ProductService) DeleteProduct(ctx context.Context, productID, tenantID uuid.UUID) error {
	var product models.Product

	err := s.db.Where("id = ? AND tenant_id = ?", productID, tenantID).First(&product).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("product not found")
		}
		return fmt.Errorf("failed to find product: %w", err)
	}

	// Check if product has stock
	var stockCount int64
	s.db.Model(&models.Stock{}).
		Where("product_id = ? AND quantity > 0", productID).
		Count(&stockCount)

	if stockCount > 0 {
		return errors.New("cannot delete product with existing stock")
	}

	// Soft delete product
	if err := s.db.Delete(&product).Error; err != nil {
		return fmt.Errorf("failed to delete product: %w", err)
	}

	// Clear cache
	s.clearProductCache(ctx, tenantID)

	return nil
}

// Brand Management

// CreateBrand creates a new brand
func (s *ProductService) CreateBrand(ctx context.Context, req BrandRequest, tenantID uuid.UUID) (*BrandResponse, error) {
	// Check for duplicate name
	var existing models.Brand
	if err := s.db.Where("name = ? AND tenant_id = ?", req.Name, tenantID).First(&existing).Error; err == nil {
		return nil, errors.New("brand with this name already exists")
	}

	// Create brand
	isActive := true
	if req.IsActive != nil {
		isActive = *req.IsActive
	}

	brand := models.Brand{
		TenantModel: models.TenantModel{TenantID: &tenantID},
		Name:        req.Name,
		Description: req.Description,
		IsActive:    isActive,
	}

	if err := s.db.Create(&brand).Error; err != nil {
		return nil, fmt.Errorf("failed to create brand: %w", err)
	}

	// Clear cache
	s.clearBrandCache(ctx, tenantID)

	return s.mapBrandToResponse(&brand, 0), nil
}

// GetBrands returns all brands
func (s *ProductService) GetBrands(ctx context.Context, tenantID uuid.UUID) ([]*BrandResponse, error) {
	var brands []models.Brand

	err := s.db.Where("tenant_id = ?", tenantID).
		Order("name ASC").
		Find(&brands).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get brands: %w", err)
	}

	// Get product counts for each brand
	var brandCounts []struct {
		BrandID uuid.UUID
		Count   int
	}
	s.db.Model(&models.Product{}).
		Select("brand_id, COUNT(*) as count").
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
		Group("brand_id").
		Scan(&brandCounts)

	countMap := make(map[uuid.UUID]int)
	for _, bc := range brandCounts {
		countMap[bc.BrandID] = bc.Count
	}

	// Convert to response format
	responses := make([]*BrandResponse, len(brands))
	for i, brand := range brands {
		responses[i] = s.mapBrandToResponse(&brand, countMap[brand.ID])
	}

	return responses, nil
}

// GetBrandByID returns brand by ID
func (s *ProductService) GetBrandByID(ctx context.Context, brandID, tenantID uuid.UUID) (*BrandResponse, error) {
	var brand models.Brand

	err := s.db.Where("id = ? AND tenant_id = ?", brandID, tenantID).First(&brand).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("brand not found")
		}
		return nil, fmt.Errorf("failed to get brand: %w", err)
	}

	// Get product count
	var productCount int64
	s.db.Model(&models.Product{}).
		Where("brand_id = ? AND tenant_id = ? AND deleted_at IS NULL", brandID, tenantID).
		Count(&productCount)

	return s.mapBrandToResponse(&brand, int(productCount)), nil
}

// UpdateBrand updates brand information
func (s *ProductService) UpdateBrand(ctx context.Context, brandID, tenantID uuid.UUID, req BrandRequest) (*BrandResponse, error) {
	var brand models.Brand

	err := s.db.Where("id = ? AND tenant_id = ?", brandID, tenantID).First(&brand).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("brand not found")
		}
		return nil, fmt.Errorf("failed to find brand: %w", err)
	}

	// Check name uniqueness if changed
	if req.Name != brand.Name {
		var existing models.Brand
		if err := s.db.Where("name = ? AND tenant_id = ? AND id != ?", req.Name, tenantID, brandID).First(&existing).Error; err == nil {
			return nil, errors.New("brand with this name already exists")
		}
	}

	// Update brand
	updates := map[string]interface{}{
		"name":        req.Name,
		"description": req.Description,
		"is_active":   req.IsActive,
	}

	if err := s.db.Model(&brand).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update brand: %w", err)
	}

	// Clear cache
	s.clearBrandCache(ctx, tenantID)

	// Get updated brand
	return s.GetBrandByID(ctx, brandID, tenantID)
}

// DeleteBrand soft deletes a brand
func (s *ProductService) DeleteBrand(ctx context.Context, brandID, tenantID uuid.UUID) error {
	var brand models.Brand

	err := s.db.Where("id = ? AND tenant_id = ?", brandID, tenantID).First(&brand).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("brand not found")
		}
		return fmt.Errorf("failed to find brand: %w", err)
	}

	// Check if brand has products
	var productCount int64
	s.db.Model(&models.Product{}).
		Where("brand_id = ? AND deleted_at IS NULL", brandID).
		Count(&productCount)

	if productCount > 0 {
		return errors.New("cannot delete brand with existing products")
	}

	// Soft delete brand
	if err := s.db.Delete(&brand).Error; err != nil {
		return fmt.Errorf("failed to delete brand: %w", err)
	}

	// Clear cache
	s.clearBrandCache(ctx, tenantID)

	return nil
}

// Brand Pricing Management

// CreateBrandPricing creates brand-size pricing
func (s *ProductService) CreateBrandPricing(ctx context.Context, req BrandPricingRequest, tenantID uuid.UUID) error {
	// Verify brand exists
	var brand models.Brand
	if err := s.db.Where("id = ? AND tenant_id = ?", req.BrandID, tenantID).First(&brand).Error; err != nil {
		return errors.New("brand not found")
	}

	// Check for duplicate
	var existing models.BrandPricing
	if err := s.db.Where("brand_id = ? AND size = ? AND tenant_id = ?",
		req.BrandID, req.Size, tenantID).First(&existing).Error; err == nil {
		// Update existing
		updates := map[string]interface{}{
			"cost_price":    req.CostPrice,
			"selling_price": req.SellingPrice,
			"mrp":           req.MRP,
		}
		return s.db.Model(&existing).Updates(updates).Error
	}

	// Create new pricing
	pricing := models.BrandPricing{
		TenantModel:  models.TenantModel{TenantID: &tenantID},
		BrandID:      req.BrandID,
		Size:         req.Size,
		CostPrice:    req.CostPrice,
		SellingPrice: req.SellingPrice,
		MRP:          req.MRP,
	}

	if err := s.db.Create(&pricing).Error; err != nil {
		return fmt.Errorf("failed to create brand pricing: %w", err)
	}

	// Update all products with this brand and size
	if err := s.db.Model(&models.Product{}).
		Where("brand_id = ? AND size = ? AND tenant_id = ?", req.BrandID, req.Size, tenantID).
		Updates(map[string]interface{}{
			"cost_price":    req.CostPrice,
			"selling_price": req.SellingPrice,
			"mrp":           req.MRP,
		}).Error; err != nil {
		return fmt.Errorf("failed to update product pricing: %w", err)
	}

	return nil
}

// Helper types and functions

// ProductFilters represents filters for products
type ProductFilters struct {
	CategoryIDs []uuid.UUID // Multiple category IDs for combined filters
	Size        string      // Size filter (e.g. "90ML")
	ShopID     uuid.UUID `form:"shop_id"` // Filter products that have stock in this shop
	// OwnerShopID filters to products this shop OWNS (products.shop_id = ?),
	// independent of whether any stock row exists yet. Distinct from ShopID
	// (which is stock-presence based and hides a shop's own zero-stock SKUs).
	// Used by per-shop pickers — e.g. the Stock Setup "Swap" dialog — so a
	// manager can only ever pick a product that belongs to the record's shop,
	// never another shop's identically-named row (the cross-shop-link bug class
	// blocked by trg_block_crossshop_stock at approve).
	OwnerShopID uuid.UUID `form:"owner_shop_id"`
	CategoryID  uuid.UUID `form:"category_id"`
	BrandID    uuid.UUID `form:"brand_id"`
	IsActive   *bool     `form:"is_active"`
	Search     string    `form:"search"`
	Page       int       `form:"page"`
	PageSize   int       `form:"page_size"`
	// When false (default) and ShopID is set, hide zero-stock products that
	// are duplicates of a populated SKU (same saas_brand_id + size). Surfaces
	// the right one to the user without nuking legitimately-empty SKUs.
	// Admins can pass ?include_zero_stock=true to see all zombies for cleanup.
	IncludeZeroStock bool `form:"include_zero_stock"`
	// PurchasePriority switches the picker to "smart" mode: instead of hiding
	// products this shop has no stock for, return the entire master catalog
	// but ranked into 4 tiers so the operator sees what they actually buy at
	// the top. Requires ShopID. Disables the standard zero-stock + in-shop
	// filters when true. Tier 1 = bought in last 90d, Tier 2 = current stock,
	// Tier 3 = ever bought, Tier 4 = master only.
	PurchasePriority bool `form:"purchase_priority"`
}

// ProductListResponse represents paginated product response
type ProductListResponse struct {
	Products   []*ProductResponse `json:"products"`
	TotalCount int64              `json:"total_count"`
	Page       int                `json:"page"`
	PageSize   int                `json:"page_size"`
	TotalPages int                `json:"total_pages"`
	// v1.0.299 — TotalStock is SUM(stocks.quantity) across the FULL filtered
	// set (every product matching the same WHERE clauses as TotalCount),
	// independent of pagination. The Flutter inventory-list header reads this
	// directly so the visible "X pcs" matches what was approved, regardless
	// of which page of products is loaded. Computed at shop-scope; 0 when no
	// shop filter is applied (the per-product COALESCE subquery only makes
	// sense within a shop).
	TotalStock int64 `json:"total_stock"`
}

// applyDisplayBoldFallback wraps the shared utils.ApplyDisplayBoldFallback
// so a page of products whose own bold indices are NULL can inherit them
// from the linked master saas_brand. See utils/display_bold.go for details.
func (s *ProductService) applyDisplayBoldFallback(responses []*ProductResponse, products []models.Product) {
	if len(responses) == 0 {
		return
	}
	targets := make([]utils.DisplayBoldTarget, len(responses))
	for i, p := range products {
		targets[i] = utils.DisplayBoldTarget{
			SaasBrandID: p.SaaSBrandID,
			DisplayName: responses[i].DisplayName,
			BoldStart:   responses[i].DisplayNameBoldStart,
			BoldLength:  responses[i].DisplayNameBoldLength,
		}
	}
	utils.ApplyDisplayBoldFallback(s.db.DB, targets, func(i int, dn string, bs, bl *int) {
		responses[i].DisplayName = dn
		responses[i].DisplayNameBoldStart = bs
		responses[i].DisplayNameBoldLength = bl
	})
}

// mapProductToResponse converts model to response format
func (s *ProductService) mapProductToResponse(product *models.Product, currentStock int) *ProductResponse {
	response := &ProductResponse{
		ID:             product.ID,
		Name:           product.Name,
		CategoryID:     product.CategoryID,
		BrandID:        product.BrandID,
		Size:           product.Size,
		AlcoholContent: product.AlcoholContent,
		Description:    product.Description,
		Barcode:        product.Barcode,
		SKU:            product.SKU,
		CostPrice:      product.CostPrice,
		SellingPrice:   product.SellingPrice,
		MRP:            product.MRP,
		Price:                 product.SellingPrice,
		DisplayName:           product.DisplayName,
		DisplayNameBoldStart:  product.DisplayNameBoldStart,
		DisplayNameBoldLength: product.DisplayNameBoldLength,
		IsActive:       product.IsActive,
		CurrentStock:   currentStock,
		SaasBrandID:    product.SaaSBrandID,
		CreatedAt:      product.CreatedAt,
		UpdatedAt:      product.UpdatedAt,
		// v1.0.250 — Front/Back photo verification fields. When set, Flutter
		// renders thumbnails on inventory list / Manual Purchase picker / etc.
		FrontImageURL:         product.FrontImageURL,
		BackImageURL:          product.BackImageURL,
		BackImageMRP:          product.BackImageMRP,
		VerifiedViaImageFront: product.VerifiedViaImageFront,
		VerifiedViaImageBack:  product.VerifiedViaImageBack,
		PhotoVerifiedAt:       product.PhotoVerifiedAt,
	}

	// Price = selling price, fall back to MRP if not set
	if response.Price == 0 {
		response.Price = product.MRP
	}

	if product.Category != nil {
		response.CategoryName = product.Category.Name
	}

	if product.Brand != nil {
		response.BrandName = product.Brand.Name
	}

	return response
}

// mapBrandToResponse converts model to response format
func (s *ProductService) mapBrandToResponse(brand *models.Brand, productCount int) *BrandResponse {
	return &BrandResponse{
		ID:           brand.ID,
		Name:         brand.Name,
		Description:  brand.Description,
		IsActive:     brand.IsActive,
		ProductCount: int64(productCount),
	}
}

// generateSKU generates SKU for product
func (s *ProductService) generateSKU(brandName, size string) string {
	timestamp := time.Now().Format("060102")
	random, _ := utils.GenerateRandomString(4)
	brandCode := brandName[:3]
	if len(brandName) < 3 {
		brandCode = brandName
	}
	return fmt.Sprintf("%s-%s-%s-%s", brandCode, size, timestamp, random)
}

// getStockLevels gets stock levels for products
func (s *ProductService) getStockLevels(tenantID uuid.UUID, products []models.Product) map[uuid.UUID]int {
	stockMap := make(map[uuid.UUID]int)

	if len(products) == 0 {
		return stockMap
	}

	productIDs := make([]uuid.UUID, len(products))
	for i, p := range products {
		productIDs[i] = p.ID
	}

	var stockLevels []struct {
		ProductID uuid.UUID
		Total     int
	}

	s.db.Model(&models.Stock{}).
		Select("product_id, COALESCE(SUM(quantity), 0) as total").
		Where("product_id IN ? AND tenant_id = ?", productIDs, tenantID).
		Group("product_id").
		Scan(&stockLevels)

	for _, sl := range stockLevels {
		stockMap[sl.ProductID] = sl.Total
	}

	return stockMap
}

// clearProductCache clears product-related cache
func (s *ProductService) clearProductCache(ctx context.Context, tenantID uuid.UUID) {
	cacheKey := fmt.Sprintf("products:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)
}

// clearBrandCache clears brand-related cache
func (s *ProductService) clearBrandCache(ctx context.Context, tenantID uuid.UUID) {
	cacheKey := fmt.Sprintf("brands:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)
}

// Product Template Management

// GetProductTemplates returns filtered product templates for the catalog
func (s *ProductService) GetProductTemplates(ctx context.Context, tenantID uuid.UUID, categoryID, subcategoryID, brandID, search string) ([]*models.ProductTemplate, error) {
	query := s.db.Model(&models.ProductTemplate{})

	// Filter by tenant through category relationship
	query = query.Joins("JOIN categories ON product_templates.category_id = categories.id").
		Where("categories.tenant_id = ?", tenantID)

	// Apply filters
	if categoryID != "" {
		if catUUID, err := uuid.Parse(categoryID); err == nil {
			query = query.Where("product_templates.category_id = ?", catUUID)
		}
	}

	if subcategoryID != "" {
		if subUUID, err := uuid.Parse(subcategoryID); err == nil {
			query = query.Where("product_templates.subcategory_id = ?", subUUID)
		}
	}

	if brandID != "" {
		if brandUUID, err := uuid.Parse(brandID); err == nil {
			query = query.Where("product_templates.brand_id = ?", brandUUID)
		}
	}

	if search != "" {
		query = query.Where("product_templates.name ILIKE ?", "%"+search+"%")
	}

	// Only active templates
	query = query.Where("product_templates.is_active = ?", true)

	// Include relationships
	query = query.Preload("Category").Preload("Subcategory").Preload("Brand")

	// Order by sort order and name
	query = query.Order("product_templates.sort_order ASC, product_templates.name ASC")

	var templates []*models.ProductTemplate
	if err := query.Find(&templates).Error; err != nil {
		return nil, fmt.Errorf("failed to get product templates: %w", err)
	}

	return templates, nil
}

// GetSubcategories returns subcategories for a category
func (s *ProductService) GetSubcategories(ctx context.Context, tenantID, categoryID uuid.UUID) ([]*models.Subcategory, error) {
	var subcategories []*models.Subcategory

	err := s.db.Where("tenant_id = ? AND category_id = ? AND is_active = ?", tenantID, categoryID, true).
		Order("sort_order ASC, name ASC").
		Find(&subcategories).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get subcategories: %w", err)
	}

	return subcategories, nil
}

// SizeWithCount represents a product size and the number of products with that size
type SizeWithCount struct {
	Size         string `json:"SIZE"`
	ProductCount int64  `json:"PRODUCT_COUNT"`
}

// GetProductSizes returns distinct product sizes with counts
// Supports multiple category IDs (comma-separated category_ids param) for combined filters like English = Whisky+Rum+Vodka
// Falls back to predefined standard sizes when no products exist yet (new tenant/shop setup)
// SizeRangeConfig defines a size range bucket
type SizeRangeConfig struct {
	Label string
	MinML int
	MaxML int
	Sort  int
}

var beerSizeRanges = []SizeRangeConfig{
	{Label: "330ml & Below", MinML: 0, MaxML: 400, Sort: 1},
	{Label: "500ml", MinML: 401, MaxML: 550, Sort: 2},
	{Label: "650ml", MinML: 551, MaxML: 999, Sort: 3},
	{Label: "Keg/Bulk", MinML: 1000, MaxML: 999999, Sort: 4},
}

var nonBeerSizeRanges = []SizeRangeConfig{
	{Label: "90ml (Nip)", MinML: 0, MaxML: 100, Sort: 1},
	{Label: "180ml (Quarter)", MinML: 101, MaxML: 250, Sort: 2},
	{Label: "375ml (Half)", MinML: 251, MaxML: 400, Sort: 3},
	{Label: "750ml (Full)", MinML: 401, MaxML: 999, Sort: 4},
	{Label: "1L+ (Large)", MinML: 1000, MaxML: 999999, Sort: 5},
}

func extractML(size string) int {
	size = strings.ToUpper(strings.TrimSpace(size))
	numStr := ""
	for _, c := range size {
		if c >= '0' && c <= '9' {
			numStr += string(c)
		}
	}
	num := 0
	if numStr != "" {
		if n, err := strconv.Atoi(numStr); err == nil {
			num = n
		}
	}
	// Handle "1L" = 1000ml
	if strings.Contains(size, "L") && !strings.Contains(size, "ML") && num < 100 {
		return num * 1000
	}
	return num
}

func (s *ProductService) GetProductSizes(ctx context.Context, tenantID uuid.UUID, categoryIDs []uuid.UUID, shopID ...uuid.UUID) ([]SizeWithCount, error) {
	// First get individual sizes
	var rawResults []SizeWithCount

	query := s.db.WithContext(ctx).
		Table("products").
		Select("UPPER(products.size) as size, COUNT(*) as product_count").
		Where("products.tenant_id = ? AND products.deleted_at IS NULL AND products.is_active = ? AND products.size IS NOT NULL AND products.size != ''", tenantID, true).
		Group("UPPER(products.size)").
		Order("product_count DESC")

	// Shop filter: only count products that have stock in the specified shop
	if len(shopID) > 0 && shopID[0] != uuid.Nil {
		query = query.Where("products.id IN (SELECT product_id FROM stocks WHERE shop_id = ? AND deleted_at IS NULL)", shopID[0])
	}

	if len(categoryIDs) == 1 {
		query = query.Where("products.category_id = ?", categoryIDs[0])
	} else if len(categoryIDs) > 1 {
		query = query.Where("products.category_id IN ?", categoryIDs)
	}

	if err := query.Find(&rawResults).Error; err != nil {
		return nil, fmt.Errorf("failed to get product sizes: %w", err)
	}

	// Determine if this is beer category
	isBeer := false
	if len(categoryIDs) > 0 {
		var catName string
		s.db.WithContext(ctx).Table("categories").Select("LOWER(name)").Where("id = ?", categoryIDs[0]).Scan(&catName)
		isBeer = strings.Contains(catName, "beer")
	}

	// Group individual sizes into ranges
	ranges := nonBeerSizeRanges
	if isBeer {
		ranges = beerSizeRanges
	}

	rangeMap := make(map[string]int64) // label -> total product count
	for _, r := range rawResults {
		ml := extractML(r.Size)
		for _, rng := range ranges {
			if ml >= rng.MinML && ml <= rng.MaxML {
				rangeMap[rng.Label] += r.ProductCount
				break
			}
		}
	}

	// Build result in sort order, only include ranges with products
	var results []SizeWithCount
	for _, rng := range ranges {
		if count, ok := rangeMap[rng.Label]; ok && count > 0 {
			results = append(results, SizeWithCount{Size: rng.Label, ProductCount: count})
		}
	}

	// Fallback: if no products, return standard ranges
	if len(results) == 0 && len(categoryIDs) > 0 {
		for _, rng := range ranges {
			results = append(results, SizeWithCount{Size: rng.Label, ProductCount: 0})
		}
	}

	return results, nil
}

// getStandardSizesForCategories returns predefined sizes based on category name
func (s *ProductService) getStandardSizesForCategories(ctx context.Context, categoryIDs []uuid.UUID) []SizeWithCount {
	// Look up category name to determine which standard sizes to return
	var categoryName string
	if err := s.db.WithContext(ctx).Table("categories").Select("LOWER(name)").Where("id = ?", categoryIDs[0]).Scan(&categoryName).Error; err != nil {
		return nil
	}

	var sizes []string
	if categoryName == "beer" {
		sizes = []string{"330ML", "500ML", "650ML"}
	} else {
		// Spirits: Whisky, Rum, Vodka, Brandy, etc.
		sizes = []string{"90ML", "180ML", "375ML", "750ML", "1L"}
	}

	results := make([]SizeWithCount, len(sizes))
	for i, size := range sizes {
		results[i] = SizeWithCount{Size: size, ProductCount: 0}
	}
	return results
}

// findMasterLinkage looks up the master catalog (saas_brands + brand_variants) for a
// product being created manually and returns (saas_brand_id, saas_variant_id) pointers
// when a confident match exists. Returns (nil, nil) when no good match is found —
// product will be created unlinked and can be linked later via Smart Stock Setup.
//
// Strategy: normalize the user's name + brand, look up brand_variants of the same
// normalized size in the tenant's state, score each candidate's saas_brands.name vs.
// the user input using simple token overlap. Accept only when ≥2 distinctive tokens
// (≥4 chars, non-generic) overlap — avoids false positives like "Whisky" matching
// every whisky in the catalog. The goal is precision, not recall; when in doubt, skip.
func (s *ProductService) findMasterLinkage(tenantID uuid.UUID, productName, brandName, size string, mrp float64) (*uuid.UUID, *uuid.UUID) {
	nameForMatch := strings.TrimSpace(productName)
	if nameForMatch == "" {
		nameForMatch = strings.TrimSpace(brandName)
	}
	if nameForMatch == "" || size == "" {
		return nil, nil
	}
	sizeUpper := strings.ToUpper(strings.TrimSpace(size))
	if !strings.HasSuffix(sizeUpper, "ML") && !strings.HasSuffix(sizeUpper, "L") {
		sizeUpper = sizeUpper + "ML"
	}

	// Resolve tenant state (defaults to UP for historical reasons)
	var st struct{ State string }
	_ = s.db.Raw(`SELECT COALESCE(state, 'UP') AS state FROM tenants WHERE id = ?`, tenantID).Scan(&st).Error
	state := st.State
	if state == "" {
		state = "UP"
	}

	type row struct {
		VariantID uuid.UUID `gorm:"column:variant_id"`
		BrandID   uuid.UUID `gorm:"column:brand_id"`
		Name      string    `gorm:"column:name"`
		MRP       float64   `gorm:"column:mrp"`
	}
	var rows []row
	if err := s.db.Raw(`
		SELECT bv.id AS variant_id, sb.id AS brand_id, sb.name AS name, bv.mrp AS mrp
		FROM brand_variants bv
		JOIN saas_brands sb ON bv.brand_id = sb.id AND sb.deleted_at IS NULL
		WHERE bv.deleted_at IS NULL
		  AND UPPER(bv.size) = UPPER(?)
		  AND COALESCE(bv.state, 'UP') = ?
	`, sizeUpper, state).Scan(&rows).Error; err != nil || len(rows) == 0 {
		return nil, nil
	}

	// Distinctive-token scoring
	generic := map[string]bool{
		"whisky": true, "whiskey": true, "vodka": true, "rum": true, "gin": true, "brandy": true,
		"wine": true, "premium": true, "reserve": true, "rare": true, "superior": true,
		"deluxe": true, "select": true, "blend": true, "blended": true, "grain": true,
		"spirits": true, "scotch": true, "bourbon": true, "indian": true, "international": true,
	}
	tokenize := func(s string) []string {
		lower := strings.ToLower(s)
		fields := strings.FieldsFunc(lower, func(r rune) bool {
			return !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'))
		})
		out := make([]string, 0, len(fields))
		for _, f := range fields {
			if len(f) >= 4 && !generic[f] {
				out = append(out, f)
			}
		}
		return out
	}
	userTokens := tokenize(nameForMatch + " " + brandName)
	if len(userTokens) == 0 {
		return nil, nil
	}

	bestMatches := 0
	bestMRPDiff := 1e18
	var bestBrandID, bestVariantID *uuid.UUID
	for i := range rows {
		r := &rows[i]
		masterTokens := tokenize(r.Name)
		overlap := 0
		for _, ut := range userTokens {
			for _, mt := range masterTokens {
				if ut == mt || strings.HasPrefix(mt, ut) || strings.HasPrefix(ut, mt) {
					overlap++
					break
				}
			}
		}
		if overlap < 2 {
			continue
		}
		diff := 1e18
		if mrp > 0 && r.MRP > 0 {
			diff = mrp - r.MRP
			if diff < 0 {
				diff = -diff
			}
		}
		if overlap > bestMatches || (overlap == bestMatches && diff < bestMRPDiff) {
			bestMatches = overlap
			bestMRPDiff = diff
			bid := r.BrandID
			vid := r.VariantID
			bestBrandID = &bid
			bestVariantID = &vid
		}
	}
	return bestBrandID, bestVariantID
}

// sanitizeBoldLength clamps an incoming display_name_bold_length value so it
// never exceeds the characters available in displayName. Returns nil when the
// input is nil or out of range — the column is nullable and NULL means "no
// special styling" (the whole display name renders in the default style).
func sanitizeBoldLength(raw *int, displayName string) *int {
	if raw == nil {
		return nil
	}
	n := *raw
	runeLen := len([]rune(displayName))
	if n <= 0 || runeLen == 0 {
		return nil
	}
	if n > runeLen {
		n = runeLen
	}
	return &n
}

// sanitizeBoldRange clamps the incoming (start, length) pair so the bold range
// stays inside displayName: 0 ≤ start ≤ runeLen, 1 ≤ length ≤ runeLen-start.
// Returns (nil, nil) when length is invalid; (nil, length) when only length is
// valid (preserves the legacy prefix-bold behaviour where Start is implicit 0).
func sanitizeBoldRange(rawStart, rawLength *int, displayName string) (*int, *int) {
	length := sanitizeBoldLength(rawLength, displayName)
	if length == nil {
		return nil, nil
	}
	runeLen := len([]rune(displayName))
	start := 0
	if rawStart != nil && *rawStart > 0 {
		start = *rawStart
	}
	if start >= runeLen {
		// Whole range is out of bounds → drop styling rather than rendering nothing.
		return nil, nil
	}
	// Clamp length so start+length never exceeds runeLen.
	if start+*length > runeLen {
		newLen := runeLen - start
		length = &newLen
	}
	if start == 0 {
		return nil, length
	}
	return &start, length
}

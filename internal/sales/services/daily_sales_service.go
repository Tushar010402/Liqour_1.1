package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// DailySalesService handles daily sales operations - the critical bulk entry workflow
type DailySalesService struct {
	db    *database.DB
	cache *cache.Cache
}

// propagateMRPFromDailySale stamps products.mrp / audit columns AND upserts
// shop_product_rates whenever the operator enters a unit_price on the DSE form
// that differs from the current product MRP by ≥ ₹0.5. Mirrors what Smart Sale
// apply does at v1.0.123 / v1.0.125 — DSE flow had been silently dropping
// these edits since v1.0.86 (chhotu's 8 PM Rare 460→470 case on May 2 2026).
//
// Best-effort: a failure here logs but never fails the sale write. Called
// AFTER the daily_sales_items have been persisted. v1.0.161.
func (s *DailySalesService) propagateMRPFromDailySale(tenantID, shopID, actorID uuid.UUID, items []DailySalesItemRequest) {
	if len(items) == 0 {
		return
	}
	actorName := resolveActorName(s.db.DB, actorID)
	for _, it := range items {
		if it.UnitPrice <= 1 || it.ProductID == uuid.Nil {
			continue
		}
		var current models.Product
		if err := s.db.Select("id, mrp").
			Where("id = ? AND tenant_id = ?", it.ProductID, tenantID).
			First(&current).Error; err != nil {
			continue
		}
		if utils.AbsFloat(current.MRP-it.UnitPrice) < 0.5 {
			continue
		}
		if err := applyProductMRPUpdate(s.db.DB, it.ProductID, tenantID, it.UnitPrice, actorID, actorName); err != nil {
			log.Printf("⚠️ [DailySales] MRP audit update failed for product %s: %v", it.ProductID, err)
		} else {
			log.Printf("💸 [DailySales] MRP edit by %s — product %s: ₹%.2f → ₹%.2f", actorName, it.ProductID, current.MRP, it.UnitPrice)
		}
		upsertSQL := `
			INSERT INTO shop_product_rates
				(tenant_id, shop_id, product_id, last_user_rate, last_corrected_at, last_corrected_by_id, occurrence_count, source)
			VALUES (?, ?, ?, ?, NOW(), ?, 1, 'dse_correction')
			ON CONFLICT (tenant_id, shop_id, product_id) DO UPDATE
			SET last_user_rate = EXCLUDED.last_user_rate,
			    last_corrected_at = NOW(),
			    last_corrected_by_id = EXCLUDED.last_corrected_by_id,
			    occurrence_count = shop_product_rates.occurrence_count + 1,
			    source = 'dse_correction',
			    updated_at = NOW()
		`
		if err := s.db.Exec(upsertSQL, tenantID, shopID, it.ProductID, it.UnitPrice, actorID).Error; err != nil {
			log.Printf("⚠️ [DailySales] shop_product_rates upsert failed for product %s: %v", it.ProductID, err)
		}
	}
}

// NewDailySalesService creates a new daily sales service
func NewDailySalesService(db *database.DB, cache *cache.Cache) *DailySalesService {
	return &DailySalesService{
		db:    db,
		cache: cache,
	}
}

// DailySalesRecordRequest represents daily sales record creation/update request
type DailySalesRecordRequest struct {
	RecordDate        time.Time               `json:"record_date" binding:"required"`
	ShopID            uuid.UUID               `json:"shop_id" binding:"required"`
	SalesmanID        *uuid.UUID              `json:"salesman_id"`
	TotalSalesAmount  float64                 `json:"total_sales_amount" binding:"required,gt=0"`
	TotalCashAmount   float64                 `json:"total_cash_amount"`
	TotalCardAmount   float64                 `json:"total_card_amount"`
	TotalUpiAmount    float64                 `json:"total_upi_amount"`
	TotalCreditAmount float64                 `json:"total_credit_amount"`
	Notes             string                  `json:"notes"`
	ReceiptImages     []string                `json:"receipt_images"`
	ImageURLs         []string                `json:"image_urls"`        // Flutter app sends this field name
	IdempotencyKey    *string                 `json:"idempotency_key"`   // Prevent duplicate submissions
	Items             []DailySalesItemRequest `json:"items" binding:"required,min=1"`
}

// GetReceiptImages returns receipt images from either field (web sends receipt_images, Flutter sends image_urls)
func (r *DailySalesRecordRequest) GetReceiptImages() []string {
	if len(r.ReceiptImages) > 0 {
		return r.ReceiptImages
	}
	return r.ImageURLs
}

// DailySalesItemRequest represents individual product sales within daily record
type DailySalesItemRequest struct {
	ProductID    uuid.UUID `json:"product_id" binding:"required"`
	Quantity     int       `json:"quantity" binding:"required,gt=0"`
	UnitPrice    float64   `json:"unit_price" binding:"required,gt=0"`
	TotalAmount  float64   `json:"total_amount" binding:"required,gt=0"`
	CashAmount   float64   `json:"cash_amount"`
	CardAmount   float64   `json:"card_amount"`
	UpiAmount    float64   `json:"upi_amount"`
	CreditAmount float64   `json:"credit_amount"`
}

// DailySalesRecordResponse represents daily sales record in responses
type DailySalesRecordResponse struct {
	ID                uuid.UUID                `json:"id"`
	RecordDate        time.Time                `json:"record_date"`
	ShopID            uuid.UUID                `json:"shop_id"`
	ShopName          string                   `json:"shop_name"`
	SalesmanID        *uuid.UUID               `json:"salesman_id"`
	SalesmanName      string                   `json:"salesman_name"`
	TotalSalesAmount  float64                  `json:"total_sales_amount"`
	TotalCashAmount   float64                  `json:"total_cash_amount"`
	TotalCardAmount   float64                  `json:"total_card_amount"`
	TotalUpiAmount    float64                  `json:"total_upi_amount"`
	TotalCreditAmount float64                  `json:"total_credit_amount"`
	Status            string                   `json:"status"`
	ApprovedAt        *time.Time               `json:"approved_at"`
	ApprovedByName    string                   `json:"approved_by_name"`
	CreatedByName     string                   `json:"created_by_name"`
	Notes             string                   `json:"notes"`
	HasAlerts         bool                     `json:"has_alerts,omitempty"`
	AlertCount        int                      `json:"alert_count,omitempty"`
	ReceiptImages     []string                 `json:"receipt_images,omitempty"`
	// v1.0.157 — duplicate the receipt images under image_urls because
	// the Flutter receipt-image viewer parses image_urls only. Without
	// this, tapping the attached image on Sales Summary shows "Failed
	// to load image".
	ImageURLs         []string                 `json:"image_urls,omitempty"`
	CreatedAt         time.Time                `json:"created_at"`
	UpdatedAt         time.Time                `json:"updated_at"`
	Items             []DailySalesItemResponse `json:"items"`
	TotalItems        int                      `json:"total_items"`
}

// DailySalesItemResponse represents daily sales item in responses.
// DisplayName + bold indices flow through so the web admin renders the
// admin-configured bold + small treatment on the daily sales detail view
// (which is the highest-traffic list after the sales list itself).
type DailySalesItemResponse struct {
	ID                    uuid.UUID `json:"id"`
	ProductID             uuid.UUID `json:"product_id"`
	ProductName           string    `json:"product_name"`
	BrandName             string    `json:"brand_name"`
	DisplayName           string    `json:"display_name,omitempty"`
	DisplayNameBoldStart  *int      `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int      `json:"display_name_bold_length,omitempty"`
	CategoryName          string    `json:"category_name"`
	Size                  string    `json:"size"`
	Quantity              int       `json:"quantity"`
	UnitPrice             float64   `json:"unit_price"`
	TotalAmount           float64   `json:"total_amount"`
	CashAmount            float64   `json:"cash_amount"`
	CardAmount            float64   `json:"card_amount"`
	UpiAmount             float64   `json:"upi_amount"`
	CreditAmount          float64   `json:"credit_amount"`
	OpeningStock          int       `json:"opening_stock"`
	ClosingStock          int       `json:"closing_stock"`
	StockAlert            string    `json:"stock_alert,omitempty"`
	StockAlertQty         int       `json:"stock_alert_qty,omitempty"`
	// v1.0.156 — current product MRP + audit. Sales summary view must show
	// the live shop MRP alongside the historical applied unit_price so the
	// operator can see whether the sold rate diverges from the current
	// price (chhotu's M2 Cranberry case: applied at ₹770 but products.mrp
	// is ₹760 — both numbers should be visible on the same row).
	ProductMRP              float64    `json:"product_mrp"`
	LastMRPChangeAt         *time.Time `json:"last_mrp_change_at,omitempty"`
	LastMRPChangeByName     string     `json:"last_mrp_change_by_name,omitempty"`
	LastMRPChangePrevious   float64    `json:"last_mrp_change_previous,omitempty"`
}

// rebuildRegisterChain re-derives daily_sales_items.opening_stock/closing_stock
// from the authoritative `daily_sale` stock_histories rows for the given (shop,
// product) set, so the per-day register always chains (open[d] == close[d-1])
// regardless of back-dating or multiple records per day. The stock ledger is the
// single source of truth; the register is a DERIVED projection of it — this
// replaces the old create-time live-snapshot capture that broke when several
// back-dated records were submitted together (all captured the same live
// balance). Pure register fix: never touches stocks.quantity or writes history.
// Idempotent (only divergent rows updated). Best-effort — a failure here must
// never block a sale, so we log and continue. v1.0.389.
func (s *DailySalesService) rebuildRegisterChain(tx *gorm.DB, tenantID, shopID uuid.UUID, productIDs []uuid.UUID) {
	if len(productIDs) == 0 {
		return
	}
	if err := tx.Exec(`
		WITH moved AS (
		  SELECT DISTINCT ON (sh.reference_id, sh.product_id)
		         sh.reference_id AS rec, sh.product_id AS pid,
		         sh.previous_quantity AS topen, sh.new_quantity AS tclose
		  FROM stock_histories sh
		  JOIN daily_sales_records r ON r.id = sh.reference_id AND r.deleted_at IS NULL AND r.status <> 'rejected'
		  WHERE sh.movement_type = 'daily_sale' AND sh.tenant_id = ? AND sh.shop_id = ?
		    AND sh.product_id IN ? AND sh.deleted_at IS NULL
		  ORDER BY sh.reference_id, sh.product_id, sh.created_at DESC)
		UPDATE daily_sales_items i SET opening_stock = m.topen, closing_stock = m.tclose, updated_at = NOW()
		FROM moved m
		WHERE m.rec = i.daily_sales_record_id AND m.pid = i.product_id AND i.deleted_at IS NULL
		  AND (i.opening_stock <> m.topen OR i.closing_stock <> m.tclose)
	`, tenantID, shopID, productIDs).Error; err != nil {
		log.Printf("⚠️ [DailySales] rebuildRegisterChain (shop=%s, %d products): %v — non-fatal", shopID, len(productIDs), err)
	}
}

// CreateDailySalesRecord creates a new daily sales record with bulk items
func (s *DailySalesService) CreateDailySalesRecord(ctx context.Context, req DailySalesRecordRequest, tenantID, createdByID uuid.UUID, createdByRole string) (*DailySalesRecordResponse, error) {
	// Validate payment amounts sum up correctly
	totalPaymentAmount := req.TotalCashAmount + req.TotalCardAmount + req.TotalUpiAmount + req.TotalCreditAmount
	if utils.AbsFloat(totalPaymentAmount-req.TotalSalesAmount) > 0.01 {
		return nil, errors.New("total payment amounts do not match total sales amount")
	}

	// Validate record date — must not be in the future or more than 7 days in the past (IST)
	recordDate := utils.StartOfDayIST(req.RecordDate)
	todayIST := utils.StartOfDayIST(utils.NowIST())
	if recordDate.After(todayIST) {
		return nil, errors.New("record date cannot be in the future")
	}
	maxPastDate := todayIST.AddDate(0, 0, -7)
	if recordDate.Before(maxPastDate) {
		return nil, fmt.Errorf("record date cannot be more than 7 days in the past (earliest: %s)", maxPastDate.Format("2006-01-02"))
	}

	// Verify shop exists and belongs to tenant FIRST (before checking duplicates)
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		log.Printf("❌ [DailySales] Shop not found: shop_id=%s, tenant_id=%s, error=%v", req.ShopID, tenantID, err)
		return nil, fmt.Errorf("shop not found or doesn't belong to this tenant (shop_id: %s)", req.ShopID)
	}
	log.Printf("✅ [DailySales] Shop verified: %s (ID: %s)", shop.Name, shop.ID)

	// Allow multiple daily sales records for the same date and shop
	// This enables corrections, adjustments, and multiple entries per day
	checkDate := utils.StartOfDayIST(req.RecordDate)
	log.Printf("📅 [DailySales] Processing record for date=%v, shop_id=%s, tenant_id=%s", checkDate, req.ShopID, tenantID)
	log.Printf("✅ [DailySales] Multiple entries allowed for same date/shop - proceeding with creation")

	// Check idempotency key to prevent duplicate submissions
	if req.IdempotencyKey != nil && *req.IdempotencyKey != "" {
		var existing models.DailySalesRecord
		if err := s.db.Where("idempotency_key = ? AND tenant_id = ? AND deleted_at IS NULL",
			*req.IdempotencyKey, tenantID).First(&existing).Error; err == nil {
			log.Printf("⚠️ [DailySales] Idempotency key already used: %s (existing record %s)", *req.IdempotencyKey, existing.ID)
			// Return the existing record instead of creating a duplicate
			return s.GetDailySalesRecordByID(ctx, existing.ID, tenantID)
		}
	}

	// Verify salesman if provided
	if req.SalesmanID != nil {
		var salesman models.Salesman
		if err := s.db.Where("id = ? AND tenant_id = ? AND shop_id = ?",
			*req.SalesmanID, tenantID, req.ShopID).First(&salesman).Error; err != nil {
			return nil, errors.New("salesman not found or doesn't belong to this shop")
		}
	}

	// ✅ UPFRONT STOCK VALIDATION - Check stock availability for ALL users
	// This ensures immediate feedback without deducting stock for pending records
	log.Printf("🔍 [DailySales] Validating stock availability for %d items...", len(req.Items))
	if err := s.validateStockAvailability(tenantID, req.ShopID, req.Items); err != nil {
		log.Printf("❌ [DailySales] Stock validation failed: %v", err)
		return nil, err
	}
	log.Printf("✅ [DailySales] Stock validation passed - all items available")

	// Determine if auto-approval based on user role
	// Roles that can auto-approve: admin, manager, assistant_manager
	autoApprove := createdByRole == models.RoleAdmin ||
		createdByRole == models.RoleManager ||
		createdByRole == models.RoleAssistantManager

	initialStatus := models.StatusPending
	if autoApprove {
		initialStatus = models.StatusApproved
		log.Printf("✅ [DailySales] Auto-approving record for privileged user (role=%s)", createdByRole)
	} else {
		log.Printf("⏳ [DailySales] Creating pending record for user (role=%s) - requires approval", createdByRole)
	}

	// Start transaction for atomic creation
	var record *models.DailySalesRecord
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Create daily sales record
		record = &models.DailySalesRecord{
			TenantModel:       models.TenantModel{TenantID: &tenantID},
			RecordDate:        utils.StartOfDayIST(req.RecordDate),
			ShopID:            req.ShopID,
			SalesmanID:        req.SalesmanID,
			TotalSalesAmount:  req.TotalSalesAmount,
			TotalCashAmount:   req.TotalCashAmount,
			TotalCardAmount:   req.TotalCardAmount,
			TotalUpiAmount:    req.TotalUpiAmount,
			TotalCreditAmount: req.TotalCreditAmount,
			Status:            initialStatus,
			CreatedByID:       createdByID,
			Notes:             req.Notes,
			ReceiptImages:     models.JSONStringList(req.GetReceiptImages()),
			IdempotencyKey:    req.IdempotencyKey,
		}

		// If auto-approved, set approval metadata
		if autoApprove {
			now := time.Now()
			record.ApprovedAt = &now
			record.ApprovedByID = &createdByID
		}

		if err := tx.Create(&record).Error; err != nil {
			return fmt.Errorf("failed to create daily sales record: %w", err)
		}

		// Create daily sales items
		totalItemsAmount := 0.0
		for _, itemReq := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			// Validate item payment amounts
			itemPaymentTotal := itemReq.CashAmount + itemReq.CardAmount + itemReq.UpiAmount + itemReq.CreditAmount
			if utils.AbsFloat(itemPaymentTotal-itemReq.TotalAmount) > 0.01 {
				return fmt.Errorf("payment amounts for product %s do not match total amount", product.Name)
			}

			// ✅ ALWAYS DEDUCT STOCK at creation time (for both pending and auto-approved).
			// Opening/closing stock is captured and locked in the item.
			// If rejected later, stock will be restored.
			var stock models.Stock
			err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				req.ShopID, itemReq.ProductID, tenantID).First(&stock).Error

			openingStock := 0
			closingStock := 0
			if err == nil {
				openingStock = stock.Quantity
				newQuantity := stock.Quantity - itemReq.Quantity
				if newQuantity < 0 {
					return fmt.Errorf("insufficient stock for %s: available %d, requested %d",
						product.Name, stock.Quantity, itemReq.Quantity)
				}
				closingStock = newQuantity

				// Deduct stock
				if err := tx.Model(&stock).Update("quantity", newQuantity).Error; err != nil {
					return fmt.Errorf("failed to update stock for product %s: %w", product.Name, err)
				}

				// Create stock history for audit trail
				approvalNote := "auto-approved"
				if !autoApprove {
					approvalNote = "pending"
				}
				// v1.0.162 — use the pre-update `openingStock` snapshot. After
				// `tx.Model(&stock).Update(...)`, GORM mutates `stock.Quantity`
				// to `newQuantity` in-place; reading it here would record
				// PreviousQuantity == NewQuantity (the corruption pattern that
				// silently broke chhotu's May 4 audit trail on 97 rows).
				shopRef, prodRef := stock.ShopID, stock.ProductID
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					ShopID:           &shopRef,
					ProductID:        &prodRef,
					MovementType:     "daily_sale",
					Quantity:         -itemReq.Quantity,
					PreviousQuantity: openingStock,
					NewQuantity:      newQuantity,
					UnitCost:         itemReq.UnitPrice,
					TotalCost:        itemReq.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Record %s", record.ID),
					ReferenceID:      &record.ID,
					CreatedByID:      createdByID,
					Notes:            fmt.Sprintf("Daily sales entry for %s (%s)", product.Name, approvalNote),
				}

				// v1.0.256 — FAIL LOUD (atomic stock+audit). Was swallowed →
				// FM Tower 1133-missing-rows class (breaks reject-baseline/heal).
				if err := tx.Create(&stockHistory).Error; err != nil {
					log.Printf("ERROR: stock history create failed — rolling back sale: %v", err)
					return fmt.Errorf("failed to record stock history (sale not saved, please retry): %w", err)
				}

				log.Printf("✅ [DailySales] Stock deducted for %s: %d → %d (-%d) [%s]",
					product.Name, openingStock, newQuantity, itemReq.Quantity, approvalNote)
			} else if !errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("failed to get stock for product %s: %w", product.Name, err)
			}

			// Create item with locked opening/closing stock
			item := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: record.ID,
				ProductID:          itemReq.ProductID,
				Quantity:           itemReq.Quantity,
				QuantitySold:       itemReq.Quantity,
				UnitPrice:          itemReq.UnitPrice,
				TotalAmount:        itemReq.TotalAmount,
				CashAmount:         itemReq.CashAmount,
				CardAmount:         itemReq.CardAmount,
				UpiAmount:          itemReq.UpiAmount,
				CreditAmount:       itemReq.CreditAmount,
				OpeningStock:       openingStock,
				ClosingStock:       closingStock,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create daily sales item: %w", err)
			}

			totalItemsAmount += itemReq.TotalAmount
		}

		// Verify total items amount matches record total
		if utils.AbsFloat(totalItemsAmount-req.TotalSalesAmount) > 0.01 {
			return errors.New("total items amount does not match record total sales amount")
		}

		// v1.0.389 — keep the per-day register a clean projection of the ledger
		// (chains across this + any prior back-dated records for these products).
		regProducts := make([]uuid.UUID, 0, len(req.Items))
		for _, it := range req.Items {
			regProducts = append(regProducts, it.ProductID)
		}
		s.rebuildRegisterChain(tx, tenantID, req.ShopID, regProducts)

		return nil
	})

	if err != nil {
		return nil, err
	}

	// v1.0.161 — propagate operator-edited MRPs to products + shop_product_rates.
	// DSE form lets the user override unit_price per row; before this hook those
	// edits stayed locked inside daily_sales_items (Chhotu's 8 PM Rare 460→470
	// on FM Tower May 2). Best-effort, async-safe, ₹0.5 no-op gate.
	go s.propagateMRPFromDailySale(tenantID, req.ShopID, createdByID, req.Items)

	// ═══════════════════════════════════════════════════════════════════════════
	// 💵 AUTO CASH TRACKING - Update user's cash holding
	// ═══════════════════════════════════════════════════════════════════════════
	// For approved records with cash payments, automatically update cash holdings
	if autoApprove && record.TotalCashAmount > 0 {
		// Create cash service instance (lightweight, no external deps)
		cashService := &CashServiceAdapter{db: s.db}

		err := cashService.UpdateCashBalance(
			ctx,
			createdByID,      // User who created the sale has the cash
			req.ShopID,       // Cash is at this shop
			tenantID,         // Tenant
			record.TotalCashAmount, // Cash amount to add
			"sale",           // Transaction type
			fmt.Sprintf("Daily sales - Record ID: %s, Date: %s", record.ID, record.RecordDate.Format("2006-01-02")),
			"daily_sales",    // Related entity type
			&record.ID,       // Related entity ID
			createdByID,      // Created by
		)

		if err != nil {
			// ⚠️ Don't fail the sale - just log the error
			// The sale succeeded, cash tracking is secondary
			log.Printf("⚠️ [DailySales] Failed to update cash holding (non-critical): %v", err)
		} else {
			log.Printf("✅ [DailySales] Cash holding updated: +%.2f for user %s at shop %s",
				record.TotalCashAmount, createdByID, req.ShopID)
		}
	}

	// Clear cache for pending sales
	s.clearDailySalesCache(ctx, tenantID, req.ShopID)

	// Load and return complete record
	return s.GetDailySalesRecordByID(ctx, record.ID, tenantID)
}

// GetDailySalesRecords returns paginated list of daily sales records
func (s *DailySalesService) GetDailySalesRecords(ctx context.Context, tenantID uuid.UUID, filters DailySalesFilters) (*DailySalesListResponse, error) {
	var records []models.DailySalesRecord
	var totalCount int64

	query := s.db.Model(&models.DailySalesRecord{}).
		Where("tenant_id = ?", tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items", func(db *gorm.DB) *gorm.DB {
			// v1.0.149 — every list view sorts by operator-defined position so
			// the IMAGE order (set on Smart Sale apply) and any subsequent
			// drag-reorder propagate to web admin, Sales Summary, daily entry.
			return db.Order("position ASC").Order("unit_price ASC")
		}).
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	// BASE filters = everything EXCEPT size/category (shop, salesman, status,
	// date, alerts). Size/category are applied separately so each breakdown can
	// ignore its own facet (selecting a size still shows every size; selecting a
	// category still shows every category).
	applyBaseFilters := func(q *gorm.DB) *gorm.DB {
		if filters.ShopID != "" {
			if shopUUID, err := uuid.Parse(filters.ShopID); err == nil {
				q = q.Where("shop_id = ?", shopUUID)
			}
		}
		if filters.SalesmanID != "" {
			if salesmanUUID, err := uuid.Parse(filters.SalesmanID); err == nil {
				q = q.Where("salesman_id = ?", salesmanUUID)
			}
		}
		if filters.Status != "" {
			q = q.Where("status = ?", filters.Status)
		}
		if !filters.StartDate.IsZero() {
			q = q.Where("record_date >= ?", filters.StartDate)
		}
		if !filters.EndDate.IsZero() {
			q = q.Where("record_date < ?", filters.EndDate)
		}
		if filters.HasAlerts != nil {
			q = q.Where("has_alerts = ?", *filters.HasAlerts)
		}
		return q
	}

	// Item-level facet predicates — operate on a query that aliased the items as
	// `i`, with products `p` and categories `c` joined.
	sz := strings.ToLower(strings.TrimSpace(filters.Size))
	cat := strings.TrimSpace(filters.Category)
	itemSizeWhere := func(q *gorm.DB) *gorm.DB {
		if sz == "" {
			return q
		}
		if sz == "beer" {
			return q.Where("LOWER(COALESCE(c.name,'')) LIKE ?", "%beer%")
		}
		like := sz + "%"
		return q.Where(
			"LOWER(REGEXP_REPLACE(COALESCE(p.size,''), '[^0-9a-zA-Z]', '', 'g')) LIKE ? OR "+
				"LOWER(REGEXP_REPLACE(COALESCE(i.ocr_size,''), '[^0-9a-zA-Z]', '', 'g')) LIKE ?",
			like, like)
	}
	itemCatWhere := func(q *gorm.DB) *gorm.DB {
		if cat == "" {
			return q
		}
		return q.Where("LOWER(c.name) = LOWER(?)", cat)
	}

	// Record-level facet: keep records that contain at least one item matching
	// BOTH the size AND the category (so a 375ml-vodka + 180ml-whisky day is not a
	// false match for size=375 & category=whisky).
	applyRecordFacets := func(q *gorm.DB) *gorm.DB {
		if sz == "" && cat == "" {
			return q
		}
		sub := s.db.Table("daily_sales_items AS i").
			Select("i.daily_sales_record_id").
			Joins("JOIN products p ON p.id = i.product_id").
			Joins("LEFT JOIN categories c ON c.id = p.category_id").
			Where("i.deleted_at IS NULL")
		sub = itemCatWhere(itemSizeWhere(sub))
		return q.Where("id IN (?)", sub)
	}

	query = applyRecordFacets(applyBaseFilters(query))

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count daily sales records: %w", err)
	}

	// v1.0.392 — FACETED summary over the FULL filtered set (independent of
	// pagination). Record-level totals reflect ALL active filters; per-category /
	// per-size breakdowns each IGNORE their own facet so the other options stay
	// visible; FilteredQty/Amount is the exact item-level total for the active
	// size+category so the cards reconcile with the table.
	summary := &DailySalesSummary{}
	applyRecordFacets(applyBaseFilters(s.db.Model(&models.DailySalesRecord{}).Where("tenant_id = ?", tenantID))).
		Select("COUNT(*) AS total_records, COALESCE(SUM(total_sales_amount),0) AS total_amount, " +
			"COUNT(*) FILTER (WHERE status = 'pending') AS pending, " +
			"COUNT(*) FILTER (WHERE status = 'approved') AS approved").
		Scan(summary)

	baseIDs := applyBaseFilters(s.db.Model(&models.DailySalesRecord{}).Where("tenant_id = ?", tenantID)).Select("id")
	baseItems := func() *gorm.DB {
		return s.db.Table("daily_sales_items AS i").
			Joins("JOIN products p ON p.id = i.product_id").
			Joins("LEFT JOIN categories c ON c.id = p.category_id").
			Where("i.daily_sales_record_id IN (?)", baseIDs).
			Where("i.deleted_at IS NULL")
	}
	// By category — apply the SIZE facet, group all categories.
	itemSizeWhere(baseItems()).
		Select("COALESCE(NULLIF(c.name,''),'Uncategorized') AS label, COALESCE(SUM(i.quantity),0) AS qty, COALESCE(SUM(i.total_amount),0) AS amount").
		Group("label").Order("amount DESC").Scan(&summary.ByCategory)
	// By size — apply the CATEGORY facet, group all sizes.
	itemCatWhere(baseItems()).
		Select("CASE WHEN LOWER(COALESCE(c.name,'')) LIKE '%beer%' THEN 'Beer' ELSE COALESCE(NULLIF(REGEXP_REPLACE(COALESCE(p.size,''), '[^0-9]', '', 'g'), ''), 'Other') END AS label, COALESCE(SUM(i.quantity),0) AS qty, COALESCE(SUM(i.total_amount),0) AS amount").
		Group("label").Order("qty DESC").Scan(&summary.BySize)
	// Exact item-level total for the ACTIVE size+category (cards reconcile w/ table).
	var ft struct {
		Qty    int64
		Amount float64
	}
	itemCatWhere(itemSizeWhere(baseItems())).
		Select("COALESCE(SUM(i.quantity),0) AS qty, COALESCE(SUM(i.total_amount),0) AS amount").
		Scan(&ft)
	summary.FilteredQty = ft.Qty
	summary.FilteredAmount = ft.Amount
	baseItems().Select("COALESCE(SUM(i.quantity),0)").Scan(&summary.TotalQty)

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("record_date DESC, created_at DESC").
		Find(&records).Error; err != nil {
		return nil, fmt.Errorf("failed to get daily sales records: %w", err)
	}

	// Convert to response format.
	//
	// Each response also gets run through enrichItemsWithStock so the
	// opening/closing values captured at sale-creation time surface to the
	// client. mapDailySalesRecordToResponse deliberately leaves those
	// fields unset (kept separate so the legacy StockHistory fallback can
	// fill them for old rows), so calling the enricher here is required —
	// otherwise the list endpoint returns 0/0 even when the underlying row
	// has locked values, and the Flutter summary renders "0 in stock,
	// 0 closing" on every line. Matches the pattern GetDailySalesRecordByID
	// already uses at line ~466.
	responses := make([]*DailySalesRecordResponse, len(records))
	for i, record := range records {
		responses[i] = s.mapDailySalesRecordToResponse(&record)
		s.enrichItemsWithStock(responses[i], &record, tenantID)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &DailySalesListResponse{
		Records:    responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
		Summary:    summary,
	}, nil
}

// GetDailySalesRecordByID returns daily sales record by ID
func (s *DailySalesService) GetDailySalesRecordByID(ctx context.Context, recordID, tenantID uuid.UUID) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("Items", func(db *gorm.DB) *gorm.DB {
			// v1.0.149 — every list view sorts by operator-defined position so
			// the IMAGE order (set on Smart Sale apply) and any subsequent
			// drag-reorder propagate to web admin, Sales Summary, daily entry.
			return db.Order("position ASC").Order("unit_price ASC")
		}).
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category").
		First(&record).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to get daily sales record: %w", err)
	}

	response := s.mapDailySalesRecordToResponse(&record)

	// Enrich items with opening/closing stock
	s.enrichItemsWithStock(response, &record, tenantID)

	return response, nil
}

// UpdateDailySalesRecordDate is a date-only PATCH for the sales list. Lighter
// than UpdateDailySalesRecord (which deletes + recreates items) so the admin
// can fix a wrong sale date inline without restock churn. Validates the same
// not-future / max-7-days-past window as create. Allowed for pending AND
// approved records — admin needs to correct attribution mistakes that may
// only surface after approval. v1.0.121.
func (s *DailySalesService) UpdateDailySalesRecordDate(ctx context.Context, recordID, tenantID uuid.UUID, newDate time.Time) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord
	if err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	candidate := utils.StartOfDayIST(newDate)
	todayIST := utils.StartOfDayIST(utils.NowIST())
	if candidate.After(todayIST) {
		return nil, errors.New("record date cannot be in the future")
	}
	maxPastDate := todayIST.AddDate(0, 0, -7)
	if candidate.Before(maxPastDate) {
		return nil, fmt.Errorf("record date cannot be more than 7 days in the past (earliest: %s)", maxPastDate.Format("2006-01-02"))
	}
	existingDate := utils.StartOfDayIST(record.RecordDate)
	if candidate.Equal(existingDate) {
		// No-op — return current state without touching the row.
		return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
	}

	if err := s.db.Model(&record).Update("record_date", candidate).Error; err != nil {
		return nil, fmt.Errorf("failed to update record date: %w", err)
	}
	log.Printf("📅 [DailySales] Date updated: record %s %s → %s",
		recordID, existingDate.Format("2006-01-02"), candidate.Format("2006-01-02"))

	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// UpdateDailySalesRecord updates existing daily sales record
func (s *DailySalesService) UpdateDailySalesRecord(ctx context.Context, recordID, tenantID uuid.UUID, req DailySalesRecordRequest) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items", func(db *gorm.DB) *gorm.DB {
			return db.Order("position ASC").Order("unit_price ASC")
		}).
		First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only pending records can be updated
	if record.Status != models.StatusPending {
		return nil, errors.New("only pending records can be updated")
	}

	// Validate payment amounts
	totalPaymentAmount := req.TotalCashAmount + req.TotalCardAmount + req.TotalUpiAmount + req.TotalCreditAmount
	if utils.AbsFloat(totalPaymentAmount-req.TotalSalesAmount) > 0.01 {
		return nil, errors.New("total payment amounts do not match total sales amount")
	}

	// v1.0.121: allow admin/manager to fix the record_date when shopkeeper
	// recorded a sale on the wrong day. Same constraints as create — not in
	// the future, not more than 7 days in the past. Empty req.RecordDate
	// means the client didn't send a date and we keep the existing value.
	var newRecordDate *time.Time
	if !req.RecordDate.IsZero() {
		candidate := utils.StartOfDayIST(req.RecordDate)
		todayIST := utils.StartOfDayIST(utils.NowIST())
		if candidate.After(todayIST) {
			return nil, errors.New("record date cannot be in the future")
		}
		maxPastDate := todayIST.AddDate(0, 0, -7)
		if candidate.Before(maxPastDate) {
			return nil, fmt.Errorf("record date cannot be more than 7 days in the past (earliest: %s)", maxPastDate.Format("2006-01-02"))
		}
		// Only stage the update when the date actually changed — avoids audit
		// noise on no-op edits.
		existingDate := utils.StartOfDayIST(record.RecordDate)
		if !candidate.Equal(existingDate) {
			newRecordDate = &candidate
			log.Printf("📅 [DailySales] Date change requested: record %s %s → %s",
				recordID, existingDate.Format("2006-01-02"), candidate.Format("2006-01-02"))
		}
	}

	// Start transaction for atomic update
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Step 1: Restore stock for old items (if stock was deducted at creation)
		for _, oldItem := range record.Items {
			if oldItem.OpeningStock > 0 || oldItem.ClosingStock != 0 {
				var stock models.Stock
				if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
					record.ShopID, oldItem.ProductID, tenantID).First(&stock).Error; err == nil {
					prevQty := stock.Quantity
					newQty := prevQty + oldItem.Quantity
					tx.Model(&stock).Update("quantity", newQty)

					// v1.0.216 — every stock-balance change must leave an audit
					// row. Pre-fix this restore was silent: stocks.quantity
					// bumped without a stock_histories entry, contributing to
					// the FM Tower-style audit drift class.
					rsShopRef, rsProdRef := stock.ShopID, stock.ProductID
					restoreHist := models.StockHistory{
						TenantModel:      models.TenantModel{TenantID: &tenantID},
						StockID:          stock.ID,
						ShopID:           &rsShopRef,
						ProductID:        &rsProdRef,
						MovementType:     "daily_sale_edit_restore",
						Quantity:         oldItem.Quantity,
						PreviousQuantity: prevQty,
						NewQuantity:      newQty,
						UnitCost:         oldItem.UnitPrice,
						TotalCost:        oldItem.TotalAmount,
						Reference:        fmt.Sprintf("Daily Sales Record %s (edit restore)", record.ID),
						ReferenceID:      &record.ID,
						CreatedByID:      record.CreatedByID,
						Notes:            fmt.Sprintf("Restored %d units of %s on record edit", oldItem.Quantity, oldItem.ProductID),
					}
					tx.Create(&restoreHist)

					log.Printf("🔄 [DailySales] Update: restored %d units of product %s (stock %d → %d)",
						oldItem.Quantity, oldItem.ProductID, prevQty, newQty)
				}
			}
		}

		// Step 2: Delete existing items
		if err := tx.Where("daily_sales_record_id = ?", recordID).Delete(&models.DailySalesItem{}).Error; err != nil {
			return fmt.Errorf("failed to delete existing items: %w", err)
		}

		// Delete old StockHistory entries for this record
		tx.Where("reference_id = ? AND movement_type = ?", recordID, "daily_sale").Delete(&models.StockHistory{})

		// Update record
		// Preserve receipt images on updates
		receiptImages := req.GetReceiptImages()
		if len(receiptImages) == 0 {
			receiptImages = []string(record.ReceiptImages)
		}

		updates := map[string]interface{}{
			"total_sales_amount":  req.TotalSalesAmount,
			"total_cash_amount":   req.TotalCashAmount,
			"total_card_amount":   req.TotalCardAmount,
			"total_upi_amount":    req.TotalUpiAmount,
			"total_credit_amount": req.TotalCreditAmount,
			"notes":               req.Notes,
			"receipt_images":      models.JSONStringList(receiptImages),
		}
		// v1.0.121: persist record_date update only when caller actually changed it.
		// Stock-deduct logic above runs against current stocks regardless of date,
		// so changing the date doesn't require re-running stock math — it's purely
		// an attribution change for reports + dashboards.
		if newRecordDate != nil {
			updates["record_date"] = *newRecordDate
		}

		if err := tx.Model(&record).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to update daily sales record: %w", err)
		}

		// Step 3: Create new items with fresh stock deduction
		totalItemsAmount := 0.0
		for _, itemReq := range req.Items {
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			itemPaymentTotal := itemReq.CashAmount + itemReq.CardAmount + itemReq.UpiAmount + itemReq.CreditAmount
			if utils.AbsFloat(itemPaymentTotal-itemReq.TotalAmount) > 0.01 {
				return fmt.Errorf("payment amounts for product %s do not match total amount", product.Name)
			}

			// Deduct stock and capture opening/closing
			openingStock := 0
			closingStock := 0
			var stock models.Stock
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				record.ShopID, itemReq.ProductID, tenantID).First(&stock).Error; err == nil {
				openingStock = stock.Quantity
				closingStock = stock.Quantity - itemReq.Quantity
				if closingStock < 0 {
					return fmt.Errorf("insufficient stock for %s: available %d, requested %d",
						product.Name, stock.Quantity, itemReq.Quantity)
				}
				tx.Model(&stock).Update("quantity", closingStock)

				// v1.0.162 — use `openingStock` snapshot, not `stock.Quantity`,
				// to avoid GORM in-place mutation poisoning the audit trail.
				shopRef, prodRef := stock.ShopID, stock.ProductID
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					ShopID:           &shopRef,
					ProductID:        &prodRef,
					MovementType:     "daily_sale",
					Quantity:         -itemReq.Quantity,
					PreviousQuantity: openingStock,
					NewQuantity:      closingStock,
					UnitCost:         itemReq.UnitPrice,
					TotalCost:        itemReq.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Record %s (updated)", record.ID),
					ReferenceID:      &record.ID,
					CreatedByID:      record.CreatedByID,
					Notes:            fmt.Sprintf("Updated sale entry for %s", product.Name),
				}
				// v1.0.256 — FAIL LOUD (atomic stock+audit). Was a bare
				// ignored Create → update moved stock with no audit row.
				if err := tx.Create(&stockHistory).Error; err != nil {
					log.Printf("ERROR: stock history create failed — rolling back update: %v", err)
					return fmt.Errorf("failed to record stock history (update not saved, please retry): %w", err)
				}

				log.Printf("✅ [DailySales] Update: deducted %d units of %s (stock %d → %d)",
					itemReq.Quantity, product.Name, openingStock, closingStock)
			}

			item := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: recordID,
				ProductID:          itemReq.ProductID,
				Quantity:           itemReq.Quantity,
				QuantitySold:       itemReq.Quantity,
				UnitPrice:          itemReq.UnitPrice,
				TotalAmount:        itemReq.TotalAmount,
				CashAmount:         itemReq.CashAmount,
				CardAmount:         itemReq.CardAmount,
				UpiAmount:          itemReq.UpiAmount,
				CreditAmount:       itemReq.CreditAmount,
				OpeningStock:       openingStock,
				ClosingStock:       closingStock,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create daily sales item: %w", err)
			}

			totalItemsAmount += itemReq.TotalAmount
		}

		if utils.AbsFloat(totalItemsAmount-req.TotalSalesAmount) > 0.01 {
			return errors.New("total items amount does not match record total sales amount")
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// v1.0.161 — same MRP propagation as Create. Edits made on the update form
	// must reach products + shop_product_rates too.
	go s.propagateMRPFromDailySale(tenantID, record.ShopID, record.CreatedByID, req.Items)

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// ApproveDailySalesRecord approves a daily sales record
func (s *DailySalesService) ApproveDailySalesRecord(ctx context.Context, recordID, tenantID, approvedByID uuid.UUID) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items", func(db *gorm.DB) *gorm.DB {
			return db.Order("position ASC").Order("unit_price ASC")
		}).
		Preload("Items.Product").
		First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only pending records can be approved
	if record.Status != models.StatusPending {
		return nil, errors.New("only pending records can be approved")
	}

	// Start transaction to update status AND deduct stock
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Update record status
		now := time.Now()
		updates := map[string]interface{}{
			"status":         models.StatusApproved,
			"approved_at":    now,
			"approved_by_id": approvedByID,
		}

		if err := tx.Model(&record).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to approve daily sales record: %w", err)
		}

		log.Printf("✅ [DailySales] Approving record %s with %d items", recordID, len(record.Items))

		// v1.0.133-r4 — verify deduction via stock_histories, NOT via the
		// item's opening/closing values. Pre-fix this gate trusted that
		// (item.OpeningStock > 0 || item.ClosingStock != 0) meant "stock was
		// already moved at create time" — but Smart Sale records opening/
		// closing as AI-extracted INFORMATION, not as a marker of an actual
		// stock movement. Result: every Smart-Sale-approved record skipped
		// stock deduction and inventory drifted upward over time. The 5
		// records reverted on 2026-05-01 (e2f650c5, 5799f9a6, 712fcdf5,
		// e4f436c9, 96820225) all hit this bug.
		//
		// Correct check: scan stock_histories for any movement_type='daily_sale'
		// with reference_id = this record. If present → already deducted at
		// create-time path. If absent → deduct now on approve.
		var existingMovements int64
		if cErr := tx.Table("stock_histories").
			Where("reference_id = ? AND movement_type = ?", record.ID, "daily_sale").
			Count(&existingMovements).Error; cErr != nil {
			log.Printf("⚠️ [DailySales] stock_histories check failed for record %s: %v — proceeding with deduction", recordID, cErr)
		}
		stockAlreadyDeducted := existingMovements > 0

		if stockAlreadyDeducted {
			log.Printf("✅ [DailySales] Stock already deducted at creation for record %s (%d audit rows) — skipping deduction", recordID, existingMovements)
		} else {
			// Standard path: deduct stock now on approve. This is the right
			// behaviour for both v1.0.120+ Smart Sale records (which DO carry
			// opening/closing AI values but never wrote a daily_sale history
			// row) and legacy records.
			log.Printf("📉 [DailySales] Approving record %s — deducting stock now", recordID)

			// v1.0.335 — over-sell pre-flight. Before mutating ANY stock row, walk
			// every item and collect those whose sale qty exceeds the available
			// balance (honoring the operator-vouched opening exactly as the
			// deduction loop does). Previously the first such row threw a mid-loop
			// "insufficient stock" error that rolled the WHOLE transaction back —
			// so one bad row (e.g. Moonwalk sold 50 vs stock 11) silently sank the
			// operator's other 26 products with a cryptic message. Now we fail
			// fast and clean, listing EVERY offending row up front, before any
			// write. Read-only; skips the zero-stock case so the in-loop self-heal
			// rescue (which can restore an unintended clear) is left untouched.
			{
				var overSell []string
				for _, item := range record.Items {
					if item.Quantity <= 0 {
						continue
					}
					var ps models.Stock
					if err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
						record.ShopID, item.ProductID, tenantID).First(&ps).Error; err != nil {
						continue // missing-stock handled by the deduction loop below
					}
					// v1.0.336 — mirror the sales-aware deduction basis exactly so the
					// pre-flight ceiling can never under-block (which would let a row
					// through here only to fail mid-loop and roll the whole tx back,
					// the cryptic-rollback class v1.0.335 fixed).
					avail := ps.Quantity
					if item.OpeningStock > 0 && item.OpeningStock != ps.Quantity {
						salesAware := driftReconcileSalesAware()
						salesSince := 0
						if salesAware {
							var s int64
							if qErr := tx.Table("stock_histories").
								Where("shop_id = ? AND product_id = ? AND tenant_id = ? AND movement_type = ? AND created_at > ?",
									record.ShopID, item.ProductID, tenantID, "daily_sale", record.CreatedAt).
								Select("COALESCE(SUM(ABS(quantity)), 0)").
								Scan(&s).Error; qErr != nil {
								return fmt.Errorf("failed to verify drift for %s (approval not saved, please retry): %w", item.Product.Name, qErr)
							}
							salesSince = int(s)
						}
						_, avail = decideDriftReconcile(item.OpeningStock, ps.Quantity, salesSince, salesAware)
					}
					// Only flag a genuine over-sell against real stock. avail<=0 falls
					// through to the rescue path; never pre-block it here.
					if avail > 0 && item.Quantity > avail {
						overSell = append(overSell, fmt.Sprintf("%s (sold %d, available %d, short %d)",
							item.Product.Name, item.Quantity, avail, item.Quantity-avail))
					}
				}
				if len(overSell) > 0 {
					log.Printf("⛔ [DailySales] approve blocked for record %s — %d over-sell row(s): %s",
						recordID, len(overSell), strings.Join(overSell, "; "))
					return fmt.Errorf("Cannot approve: %d row(s) sell more than the stock on hand. Fix the sold quantity (or opening) on each, then re-approve:\n• %s",
						len(overSell), strings.Join(overSell, "\n• "))
				}
			}

			for _, item := range record.Items {
				var stock models.Stock
				err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
					record.ShopID, item.ProductID, tenantID).First(&stock).Error

				if err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						return fmt.Errorf("stock not found for product %s in this shop", item.Product.Name)
					}
					return fmt.Errorf("failed to get stock for product %s: %w", item.Product.Name, err)
				}

				// v1.0.218 — self-heal rescue. If stock is zero, look for a recent
				// opening_stock_setup_clear on this product (within 14 days) that
				// has not been re-set by a subsequent legitimate setup. If found,
				// reverse the clear and proceed. This recovers from the FM Tower
				// Mahua Khera bug class where Stock Setup approve zeroed the
				// Sale's product because the matcher picked a sibling row for
				// the same brand. Strictly bounded: fires only when stock is
				// exactly 0 AND we have direct evidence of an unintended clear
				// AND no legitimate later setup has touched the product.
				if stock.Quantity == 0 && item.Quantity > 0 {
					type clearRow struct {
						ID               uuid.UUID `gorm:"column:id"`
						PreviousQuantity int       `gorm:"column:previous_quantity"`
						CreatedAt        time.Time `gorm:"column:created_at"`
						ReferenceID      *uuid.UUID `gorm:"column:reference_id"`
					}
					var clr clearRow
					clrErr := tx.Table("stock_histories").
						Select("id, previous_quantity, created_at, reference_id").
						Where("shop_id = ? AND product_id = ? AND tenant_id = ? AND movement_type = ? AND created_at > ?",
							record.ShopID, item.ProductID, tenantID, "opening_stock_setup_clear", time.Now().Add(-14*24*time.Hour)).
						Order("created_at DESC").Limit(1).
						Scan(&clr).Error
					if clrErr == nil && clr.PreviousQuantity > 0 {
						// Is there a LATER legitimate setup row for this product?
						// (opening_stock_setup or another _clear) — if yes, do not reverse.
						var laterCount int64
						_ = tx.Table("stock_histories").
							Where("shop_id = ? AND product_id = ? AND tenant_id = ? AND movement_type IN ? AND created_at > ?",
								record.ShopID, item.ProductID, tenantID,
								[]string{"opening_stock_setup", "opening_stock_setup_clear"},
								clr.CreatedAt).
							Count(&laterCount).Error
						if laterCount == 0 {
							restored := clr.PreviousQuantity
							if err := tx.Model(&stock).Update("quantity", restored).Error; err != nil {
								log.Printf("⚠️ [DailySales] rescue restore failed for product %s: %v", item.Product.Name, err)
							} else {
								stock.Quantity = restored
								revShopRef, revProdRef := stock.ShopID, stock.ProductID
								rev := models.StockHistory{
									TenantModel:      models.TenantModel{TenantID: &tenantID},
									StockID:          stock.ID,
									ShopID:           &revShopRef,
									ProductID:        &revProdRef,
									MovementType:     "opening_stock_setup_clear_reverse",
									Quantity:         restored,
									PreviousQuantity: 0,
									NewQuantity:      restored,
									Reference:        fmt.Sprintf("Auto-restored before approving Daily Sales Record %s — clear was unintended (pending sale referenced product)", record.ID),
									ReferenceID:      &record.ID,
									Notes:            fmt.Sprintf("Reversed opening_stock_setup_clear from %s (clear=%s) so the pending sale could approve", clr.CreatedAt.Format(time.RFC3339), clr.ID),
									CreatedByID:      approvedByID,
								}
								_ = tx.Create(&rev).Error
								log.Printf("✅ [DailySales] Auto-restored stock for product %s (0 → %d, reversing clear %s) before approving record %s",
									item.Product.Name, restored, clr.ID, record.ID)
							}
						} else {
							log.Printf("[DailySales] rescue skipped for product %s — %d later setup row(s) found after clear %s",
								item.Product.Name, laterCount, clr.ID)
						}
					}
				}

				// v1.0.162 — root-cause fix for chhotu's May 4 corruption (97
				// items, 7 records). GORM's tx.Model(&stock).Update(...) mutates
				// stock.Quantity in-place to newQuantity. The previous code read
				// stock.Quantity AFTER that call to populate opening_stock and
				// PreviousQuantity, recording the post-deduction value for both
				// — so opening==closing on every row and the audit history was
				// useless. Snapshot first, then deduct.
				beforeQty := stock.Quantity

				// Apple-to-apple opening-drift guard (Bug 3 defensive). The operator
				// vouched for item.OpeningStock on the review screen at submit, and at
				// that moment it WAS the live balance (both create paths stamp
				// opening = stocks.quantity). If the live balance has since drifted out
				// from under us — e.g. an un-laddered AI Stock Setup / cross-shop
				// consolidation write, the root of FM Tower record 2bc7c3c0 where 94
				// silently became 26 — reconcile the gap with its OWN explicit ledger
				// row so the audit trail stays banking-grade.
				//
				// v1.0.336 — SALES-AWARE. The legacy guard snapped live fully UP to
				// the vouched opening on ANY mismatch. That cancels prior legitimate
				// sales when a backlog of records is batch-approved (every record
				// carries the same submit-time opening, so each approval snaps back up
				// and erases the previous record's daily_sale — Mahua Khera 2026-06-02,
				// 60 products / 1035 bottles overstated). We now decompose the gap: the
				// portion explained by daily_sale movements recorded AFTER this record
				// was submitted is LEGITIMATE and left intact; only the residual
				// non-sale drift is reconciled. See decideDriftReconcile.
				deductBasis := beforeQty
				if item.OpeningStock > 0 && item.OpeningStock != beforeQty {
					salesAware := driftReconcileSalesAware()
					salesSince := 0
					if salesAware {
						var s int64
						if qErr := tx.Table("stock_histories").
							Where("shop_id = ? AND product_id = ? AND tenant_id = ? AND movement_type = ? AND created_at > ?",
								record.ShopID, item.ProductID, tenantID, "daily_sale", record.CreatedAt).
							Select("COALESCE(SUM(ABS(quantity)), 0)").
							Scan(&s).Error; qErr != nil {
							// FAIL LOUD: if we can't prove how much of the drift is
							// sale-attributable, do NOT silently reconcile (that is the
							// cancellation bug) and do NOT silently trust live (that
							// re-opens FM Tower). Roll the approval back.
							log.Printf("ERROR: sales-aware drift query failed for %s record %s — rolling back approval: %v",
								item.Product.Name, record.ID, qErr)
							return fmt.Errorf("failed to verify drift for %s (approval not saved, please retry): %w", item.Product.Name, qErr)
						}
						salesSince = int(s)
					}

					illegitGap, basis := decideDriftReconcile(item.OpeningStock, beforeQty, salesSince, salesAware)
					deductBasis = basis

					if illegitGap != 0 {
						log.Printf("⚠️ [DailySales] OPENING DRIFT for %s in record %s: live=%d vouched=%d salesSince=%d → reconciling non-sale residual %+d (deduct from %d)",
							item.Product.Name, record.ID, beforeQty, item.OpeningStock, salesSince, illegitGap, deductBasis)
						recShop, recProd := stock.ShopID, stock.ProductID
						recon := models.StockHistory{
							TenantModel:      models.TenantModel{TenantID: &tenantID},
							StockID:          stock.ID,
							ShopID:           &recShop,
							ProductID:        &recProd,
							MovementType:     "opening_drift_reconcile",
							Quantity:         illegitGap,
							PreviousQuantity: beforeQty,
							NewQuantity:      beforeQty + illegitGap,
							Reference:        fmt.Sprintf("Daily Sales Record %s (approved)", record.ID),
							ReferenceID:      &record.ID,
							CreatedByID:      approvedByID,
							Notes:            fmt.Sprintf("Live stock %d drifted from operator-vouched opening %d for %s (gap %+d, %d already sold since submit); reconciled the %+d non-sale residual before applying the sale.", beforeQty, item.OpeningStock, item.Product.Name, item.OpeningStock-beforeQty, salesSince, illegitGap),
						}
						if err := tx.Create(&recon).Error; err != nil {
							log.Printf("ERROR: drift reconcile history create failed — rolling back approval: %v", err)
							return fmt.Errorf("failed to record drift reconciliation (approval not saved, please retry): %w", err)
						}
					} else {
						log.Printf("✅ [DailySales] drift for %s record %s fully sale-attributable (live=%d vouched=%d salesSince=%d) — deducting from live, no reconcile",
							item.Product.Name, record.ID, beforeQty, item.OpeningStock, salesSince)
					}
				}

				if deductBasis < item.Quantity {
					return fmt.Errorf("insufficient stock for product %s: available %d, requested %d (after rescue attempt)",
						item.Product.Name, deductBasis, item.Quantity)
				}

				newQuantity := deductBasis - item.Quantity
				if err := tx.Model(&stock).Update("quantity", newQuantity).Error; err != nil {
					return fmt.Errorf("failed to update stock for product %s: %w", item.Product.Name, err)
				}

				// Apple-to-apple: the operator already vouched for opening/closing
				// at submit, so those are authoritative — NEVER re-derive them from
				// the live balance here. (Regression source: FM Tower record
				// 2bc7c3c0 — a silently-drifted live stock of 26 overwrote the
				// operator-submitted opening of 94, flipping closing 77→9.) Only
				// backfill when the row never carried opening/closing at all
				// (legacy/manual rows where opening_stock was left unset).
				if item.OpeningStock == 0 && item.ClosingStock == 0 {
					tx.Model(&item).Updates(map[string]interface{}{
						"opening_stock": beforeQty,
						"closing_stock": newQuantity,
					})
				}

				shopRef, prodRef := stock.ShopID, stock.ProductID
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					ShopID:           &shopRef,
					ProductID:        &prodRef,
					MovementType:     "daily_sale",
					Quantity:         -item.Quantity,
					PreviousQuantity: deductBasis,
					NewQuantity:      newQuantity,
					UnitCost:         item.UnitPrice,
					TotalCost:        item.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Record %s (approved)", record.ID),
					ReferenceID:      &record.ID,
					CreatedByID:      approvedByID,
					Notes:            fmt.Sprintf("Daily sales entry for %s (legacy approval)", item.Product.Name),
				}

				// v1.0.256 — FAIL LOUD (atomic stock+audit) on approve.
				if err := tx.Create(&stockHistory).Error; err != nil {
					log.Printf("ERROR: stock history create failed — rolling back approval: %v", err)
					return fmt.Errorf("failed to record stock history (approval not saved, please retry): %w", err)
				}

				log.Printf("✅ [DailySales] Legacy deduction for %s: %d → %d (-%d)", item.Product.Name, deductBasis, newQuantity, item.Quantity)
			}
		}

		// v1.0.389 — re-chain the per-day register for the products this record
		// touched (self-heals back-dated / multi-record-per-day ordering).
		regProducts := make([]uuid.UUID, 0, len(record.Items))
		for _, it := range record.Items {
			regProducts = append(regProducts, it.ProductID)
		}
		s.rebuildRegisterChain(tx, tenantID, record.ShopID, regProducts)

		return nil
	})

	if err != nil {
		return nil, err
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// 💵 AUTO CASH TRACKING - Update cash holding after approval
	// ═══════════════════════════════════════════════════════════════════════════
	// For approved records with cash payments, automatically update cash holdings
	if record.TotalCashAmount > 0 {
		// Create cash service instance
		cashService := &CashServiceAdapter{db: s.db}

		// Determine who gets the cash (the salesman who created the record)
		cashRecipientID := record.CreatedByID
		if record.SalesmanID != nil && *record.SalesmanID != uuid.Nil {
			cashRecipientID = *record.SalesmanID
		}

		err := cashService.UpdateCashBalance(
			ctx,
			cashRecipientID,            // User who created/made the sale has the cash
			record.ShopID,              // Cash is at this shop
			tenantID,                   // Tenant
			record.TotalCashAmount,     // Cash amount to add
			"sale",                     // Transaction type
			fmt.Sprintf("Daily sales - Record ID: %s, Date: %s (approved)", record.ID, record.RecordDate.Format("2006-01-02")),
			"daily_sales",              // Related entity type
			&record.ID,                 // Related entity ID
			approvedByID,               // Approved by (for audit)
		)

		if err != nil {
			// ⚠️ Don't fail the approval - just log the error
			// The approval succeeded, cash tracking is secondary
			log.Printf("⚠️ [DailySales] Failed to update cash holding after approval (non-critical): %v", err)
		} else {
			log.Printf("✅ [DailySales] Cash holding updated after approval: +%.2f for user %s at shop %s",
				record.TotalCashAmount, cashRecipientID, record.ShopID)
		}
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// v1.0.187 — propagate any operator-edited unit_price up to products.mrp
	// + shop_product_rates on approval too. Pre-fix the propagation only fired
	// from CreateDailySalesRecord/UpdateDailySalesRecord, so a sale that was
	// approved AFTER edit (or where the edit happened on a draft record before
	// approval) silently dropped the MRP change. Concretely: chhotu's FM Tower
	// 2026-05-05 Red Label sales went in at unit_price ₹1910, the goroutine
	// here didn't run on the approval path, products.mrp stayed at ₹1810,
	// inventory cards rendered the stale value. Healed manually 2026-05-07;
	// this hook prevents recurrence.
	itemRequests := make([]DailySalesItemRequest, 0, len(record.Items))
	for _, it := range record.Items {
		itemRequests = append(itemRequests, DailySalesItemRequest{
			ProductID: it.ProductID,
			UnitPrice: it.UnitPrice,
			Quantity:  it.Quantity,
		})
	}
	go s.propagateMRPFromDailySale(tenantID, record.ShopID, approvedByID, itemRequests)

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// RejectDailySalesRecord rejects a daily sales record and restores stock
func (s *DailySalesService) RejectDailySalesRecord(ctx context.Context, recordID, tenantID, rejectedByID uuid.UUID, reason string) error {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items", func(db *gorm.DB) *gorm.DB {
			return db.Order("position ASC").Order("unit_price ASC")
		}).
		Preload("Items.Product").
		First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("daily sales record not found")
		}
		return fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only pending records can be rejected
	if record.Status != models.StatusPending {
		return errors.New("only pending records can be rejected")
	}

	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Update record status
		now := time.Now()
		updates := map[string]interface{}{
			"status":         models.StatusRejected,
			"approved_at":    now,
			"approved_by_id": rejectedByID,
			"notes":          record.Notes + " | Rejection reason: " + reason,
		}

		if err := tx.Model(&record).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to reject daily sales record: %w", err)
		}

		// v1.0.216 phase 3 — authoritative "did this record actually deduct
		// stock?" check, gated on stock_histories audit rows for the record.
		// FM Tower 90ML May 6 opening was inflated by exactly this class: a
		// duplicate of May 5's sale (d714d53a) was created pre-v1.0.203 dedup,
		// never approved (so never debited), then rejected on May 7. The reject
		// path's old gate (item.OpeningStock > 0 || ClosingStock != 0) returned
		// true on every record since OpeningStock is captured at create time,
		// so it "restored" ~38 units that were never debited — the next day's
		// Smart-Sale opening locked in the phantom inflation.
		var deductRows int64
		tx.Table("stock_histories").
			Where("reference_id = ? AND movement_type IN ('daily_sale','smart_sale') AND deleted_at IS NULL",
				recordID).
			Count(&deductRows)
		stockWasDeducted := deductRows > 0
		if !stockWasDeducted {
			log.Printf("🛑 [DailySales] Reject of %s — no daily_sale audit row exists; record never deducted, skipping restore (FM Tower May 6 class fix). Items=%d", recordID, len(record.Items))
		}

		if stockWasDeducted {
			log.Printf("🔄 [DailySales] Rejecting record %s — restoring stock for %d items", recordID, len(record.Items))
			for _, item := range record.Items {
				var stock models.Stock
				err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
					record.ShopID, item.ProductID, tenantID).First(&stock).Error

				if err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						log.Printf("⚠️ [DailySales] Stock record not found for product %s — skipping restore", item.ProductID)
						continue
					}
					return fmt.Errorf("failed to get stock for restore: %w", err)
				}

				// Baseline-reset guard: if opening stock has been re-set on this stock
				// row AFTER this sale was created (via Smart Stock Setup approve), the
				// new opening stock already represents the real count — adding the
				// rejected qty back would double-count and inflate inventory. Real
				// case: rejected daily-sale record 95647dc0 created 00:58 → three
				// stock setups overwrote opening stock before reject at 20:02 →
				// previous restore code pushed stock from 137 to 161.
				var resetCount int64
				if cErr := tx.Table("stock_histories").
					Where("stock_id = ? AND movement_type = ? AND created_at > ?",
						stock.ID, "opening_stock_setup", record.CreatedAt).
					Count(&resetCount).Error; cErr != nil {
					log.Printf("⚠️ [DailySales] baseline-reset check failed for stock %s: %v — proceeding with restore", stock.ID, cErr)
				}

				prevQty := stock.Quantity
				productName := fmt.Sprintf("%s", item.ProductID)
				if item.Product != nil {
					productName = item.Product.Name
				}

				if resetCount > 0 {
					// Opening stock was reset since the sale — skip the +qty
					// restoration but still audit the rejection so the trail is
					// complete. This prevents the silent double-count without
					// hiding the operator's reject action.
					shopRef, prodRef := stock.ShopID, stock.ProductID
					stockHistory := models.StockHistory{
						TenantModel:      models.TenantModel{TenantID: &tenantID},
						StockID:          stock.ID,
						ShopID:           &shopRef,
						ProductID:        &prodRef,
						MovementType:     "daily_sale_rejected_no_restore",
						Quantity:         0,
						PreviousQuantity: prevQty,
						NewQuantity:      prevQty,
						UnitCost:         item.UnitPrice,
						TotalCost:        item.TotalAmount,
						Reference:        fmt.Sprintf("Daily Sales Record %s (rejected, baseline reset)", record.ID),
						ReferenceID:      &record.ID,
						CreatedByID:      rejectedByID,
						Notes:            fmt.Sprintf("Reject of %s skipped stock restore — opening stock was reset by Smart Stock Setup after this sale; restore would double-count. Reason: %s", productName, reason),
					}
					// v1.0.256 — FAIL LOUD: this row is the only record of WHY
					// restore was skipped; losing it makes the reject look
					// like a bug. Atomic with the reject txn.
					if err := tx.Create(&stockHistory).Error; err != nil {
						log.Printf("ERROR: no-restore audit row create failed — rolling back reject: %v", err)
						return fmt.Errorf("failed to record no-restore audit (reject not saved, please retry): %w", err)
					}
					log.Printf("🛑 [DailySales] Skipping stock restore for %s (stock=%d) — opening stock was reset %d time(s) after sale was created", productName, prevQty, resetCount)
					continue
				}

				// Normal restore path — opening stock has NOT been reset since.
				newQuantity := prevQty + item.Quantity
				if err := tx.Model(&stock).Update("quantity", newQuantity).Error; err != nil {
					return fmt.Errorf("failed to restore stock for product %s: %w", item.ProductID, err)
				}

				shopRef2, prodRef2 := stock.ShopID, stock.ProductID
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					ShopID:           &shopRef2,
					ProductID:        &prodRef2,
					MovementType:     "daily_sale_rejected",
					Quantity:         item.Quantity,
					PreviousQuantity: prevQty,
					NewQuantity:      newQuantity,
					UnitCost:         item.UnitPrice,
					TotalCost:        item.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Record %s (rejected)", record.ID),
					ReferenceID:      &record.ID,
					CreatedByID:      rejectedByID,
					Notes:            fmt.Sprintf("Stock restored for %s — sale rejected: %s", productName, reason),
				}

				// v1.0.256 — FAIL LOUD (atomic stock-restore + audit) on reject.
				if err := tx.Create(&stockHistory).Error; err != nil {
					log.Printf("ERROR: stock history create failed — rolling back reject: %v", err)
					return fmt.Errorf("failed to record stock history (reject not saved, please retry): %w", err)
				}

				log.Printf("🔄 [DailySales] Stock restored for %s: %d → %d (+%d)", productName, prevQty, newQuantity, item.Quantity)
			}
		} else {
			log.Printf("⚠️ [DailySales] Legacy record %s — no stock to restore", recordID)
		}

		return nil
	})

	if err != nil {
		return err
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	return nil
}

// Helper functions

// DailySalesFilters represents filters for daily sales records
type DailySalesFilters struct {
	ShopID     string `form:"shop_id"`
	SalesmanID string `form:"salesman_id"`
	Status     string `form:"status"`
	HasAlerts  *bool  `form:"has_alerts"`
	// Size filter: bucket records by any contained item whose product.size or
	// ocr_size starts with the requested numeric prefix (e.g. "180", "375",
	// "750"). Empty = no size filter. "beer" matches Beer / non-numeric sizes.
	Size      string    `form:"size"`
	// Category filter (v1.0.391): keep records that contain at least one item
	// whose product category name matches (case-insensitive). Mirrors Size.
	Category  string    `form:"category"`
	StartDate time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate   time.Time `form:"end_date" time_format:"2006-01-02"`
	Page      int       `form:"page"`
	PageSize  int       `form:"page_size"`
}

// SalesBucket is one (size or category) breakdown row in the list summary.
type SalesBucket struct {
	Label  string  `json:"label" gorm:"column:label"`
	Qty    int64   `json:"qty" gorm:"column:qty"`
	Amount float64 `json:"amount" gorm:"column:amount"`
}

// DailySalesSummary aggregates the FULL filtered set (not just the current page)
// so the web admin can show totals + per-category + per-size breakdowns. v1.0.391.
type DailySalesSummary struct {
	TotalRecords int64 `json:"total_records" gorm:"column:total_records"`
	TotalAmount  float64 `json:"total_amount" gorm:"column:total_amount"`
	Pending      int64 `json:"pending" gorm:"column:pending"`
	Approved     int64 `json:"approved" gorm:"column:approved"`
	// TotalQty = all bottles in the base (date/shop/status) set, ignoring the
	// size/category selection. FilteredQty/Amount = the exact item-level total for
	// the ACTIVE size+category, so the cards reconcile with the table + breakdowns.
	TotalQty       int64         `json:"total_qty" gorm:"-"`
	FilteredQty    int64         `json:"filtered_qty" gorm:"-"`
	FilteredAmount float64       `json:"filtered_amount" gorm:"-"`
	// Each breakdown IGNORES its own facet (by_category applies the size filter
	// but groups all categories; by_size applies the category filter but groups
	// all sizes) so the other options never disappear when one is selected.
	ByCategory []SalesBucket `json:"by_category" gorm:"-"`
	BySize     []SalesBucket `json:"by_size" gorm:"-"`
}

// DailySalesListResponse represents paginated daily sales response
type DailySalesListResponse struct {
	Records    []*DailySalesRecordResponse `json:"records"`
	TotalCount int64                       `json:"total_count"`
	Page       int                         `json:"page"`
	PageSize   int                         `json:"page_size"`
	TotalPages int                         `json:"total_pages"`
	Summary    *DailySalesSummary          `json:"summary,omitempty"`
}

// enrichItemsWithStock populates opening/closing stock for each item in the response.
// New system: opening/closing are stored in the DailySalesItem at creation time (locked values).
// Legacy fallback: for old records without stored values, uses StockHistory or current stock.
func (s *DailySalesService) enrichItemsWithStock(response *DailySalesRecordResponse, record *models.DailySalesRecord, tenantID uuid.UUID) {
	if len(response.Items) == 0 {
		return
	}

	// Check if items already have stored opening/closing from the new system
	hasStoredStock := false
	for _, item := range record.Items {
		if item.OpeningStock > 0 || item.ClosingStock != 0 {
			hasStoredStock = true
			break
		}
	}

	if hasStoredStock {
		// New system: use the locked values stored in each item at creation time
		log.Printf("[StockCalc] Record %s (%s, %s): using stored opening/closing from creation",
			record.ID, record.Status, record.RecordDate.Format("2006-01-02"))

		// Build a map from the model items (which have the stored values)
		storedMap := make(map[uuid.UUID]*models.DailySalesItem)
		for i := range record.Items {
			storedMap[record.Items[i].ProductID] = &record.Items[i]
		}

		for i, item := range response.Items {
			if stored, ok := storedMap[item.ProductID]; ok {
				response.Items[i].OpeningStock = stored.OpeningStock
				response.Items[i].ClosingStock = stored.ClosingStock
				log.Printf("[StockCalc]   %s: opening=%d, closing=%d (locked)",
					item.ProductName, stored.OpeningStock, stored.ClosingStock)
			}
		}
		return
	}

	// Legacy fallback for old records without stored stock values
	log.Printf("[StockCalc] Record %s (%s, %s): legacy mode — no stored stock, computing from DB",
		record.ID, record.Status, record.RecordDate.Format("2006-01-02"))

	if record.Status == "approved" {
		// For approved legacy records, use StockHistory snapshots
		var histories []models.StockHistory
		s.db.Where("reference_id = ? AND movement_type = ?", record.ID, "daily_sale").
			Preload("Stock").
			Find(&histories)

		historyMap := make(map[uuid.UUID]*models.StockHistory)
		for i := range histories {
			if histories[i].Stock != nil {
				historyMap[histories[i].Stock.ProductID] = &histories[i]
			}
		}

		for i, item := range response.Items {
			if h, ok := historyMap[item.ProductID]; ok {
				response.Items[i].OpeningStock = h.PreviousQuantity
				response.Items[i].ClosingStock = h.NewQuantity
			}
		}
	} else {
		// For legacy pending/rejected, use current stock
		productIDs := make([]uuid.UUID, len(response.Items))
		for i, item := range response.Items {
			productIDs[i] = item.ProductID
		}

		var stocks []models.Stock
		s.db.Where("shop_id = ? AND product_id IN ? AND tenant_id = ?", record.ShopID, productIDs, tenantID).
			Find(&stocks)

		currentStockMap := make(map[uuid.UUID]int)
		for _, st := range stocks {
			currentStockMap[st.ProductID] = st.Quantity
		}

		for i, item := range response.Items {
			currentStock := currentStockMap[item.ProductID]
			response.Items[i].OpeningStock = currentStock
			if record.Status == "pending" {
				response.Items[i].ClosingStock = currentStock - item.Quantity
			} else {
				response.Items[i].ClosingStock = currentStock
			}
		}
	}
}

// mapDailySalesRecordToResponse converts model to response format
func (s *DailySalesService) mapDailySalesRecordToResponse(record *models.DailySalesRecord) *DailySalesRecordResponse {
	response := &DailySalesRecordResponse{
		ID:                record.ID,
		RecordDate:        record.RecordDate,
		ShopID:            record.ShopID,
		SalesmanID:        record.SalesmanID,
		TotalSalesAmount:  record.TotalSalesAmount,
		TotalCashAmount:   record.TotalCashAmount,
		TotalCardAmount:   record.TotalCardAmount,
		TotalUpiAmount:    record.TotalUpiAmount,
		TotalCreditAmount: record.TotalCreditAmount,
		Status:            record.Status,
		ApprovedAt:        record.ApprovedAt,
		Notes:             record.Notes,
		ReceiptImages:     []string(record.ReceiptImages),
		// v1.0.157 — Flutter parses `image_urls` (not `receipt_images`) from
		// the response, so without this assignment the receipt-image viewer
		// always sees an empty list and shows "Failed to load image".
		// Backend supports BOTH on the request side for legacy reasons; we
		// now ship both on the response too. Web admin still reads
		// receipt_images.
		ImageURLs:         []string(record.ReceiptImages),
		HasAlerts:         record.HasAlerts,
		AlertCount:        record.AlertCount,
		CreatedAt:         record.CreatedAt,
		UpdatedAt:         record.UpdatedAt,
		TotalItems:        len(record.Items),
	}

	// Add shop info
	if record.Shop != nil {
		response.ShopName = record.Shop.Name
	}

	// Add salesman info
	if record.Salesman != nil {
		response.SalesmanName = record.Salesman.Name
	}

	// Add created by info
	if record.CreatedBy != nil {
		response.CreatedByName = record.CreatedBy.FirstName + " " + record.CreatedBy.LastName
	}

	// Add approved by info
	if record.ApprovedBy != nil {
		response.ApprovedByName = record.ApprovedBy.FirstName + " " + record.ApprovedBy.LastName
	}

	// Add items
	if len(record.Items) > 0 {
		response.Items = make([]DailySalesItemResponse, len(record.Items))
		targets := make([]utils.DisplayBoldTarget, len(record.Items))
		for i, item := range record.Items {
			response.Items[i] = DailySalesItemResponse{
				ID:            item.ID,
				ProductID:     item.ProductID,
				Quantity:      item.Quantity,
				UnitPrice:     item.UnitPrice,
				TotalAmount:   item.TotalAmount,
				CashAmount:    item.CashAmount,
				CardAmount:    item.CardAmount,
				UpiAmount:     item.UpiAmount,
				CreditAmount:  item.CreditAmount,
				StockAlert:    item.StockAlert,
				StockAlertQty: item.StockAlertQty,
				// v1.0.156 — opening + closing stock were previously
				// dropped on the floor here (defaulted to 0) which left
				// the daily sales detail screen with no opening info to
				// render. Carry them through.
				OpeningStock:  item.OpeningStock,
				ClosingStock:  item.ClosingStock,
			}

			// Add product info
			if item.Product != nil {
				response.Items[i].ProductName = item.Product.Name
				response.Items[i].Size = item.Product.Size
				// Carry display_name through so daily-sales detail uses the
				// same bold + small treatment as Brands / Products pages.
				response.Items[i].DisplayName = item.Product.DisplayName
				response.Items[i].DisplayNameBoldStart = item.Product.DisplayNameBoldStart
				response.Items[i].DisplayNameBoldLength = item.Product.DisplayNameBoldLength
				// v1.0.156 — current product MRP + last-change audit.
				// Sales summary view renders both the applied unit_price
				// and product_mrp so the operator can spot divergence at
				// a glance (the chhotu M2 Cranberry case: ₹770 sold at
				// vs ₹760 current MRP).
				response.Items[i].ProductMRP = item.Product.MRP
				response.Items[i].LastMRPChangeAt = item.Product.LastMRPChangeAt
				response.Items[i].LastMRPChangeByName = item.Product.LastMRPChangeByName
				response.Items[i].LastMRPChangePrevious = item.Product.LastMRPChangePrevious

				if item.Product.Brand != nil {
					response.Items[i].BrandName = item.Product.Brand.Name
				}

				if item.Product.Category != nil {
					response.Items[i].CategoryName = item.Product.Category.Name
				}
				targets[i] = utils.DisplayBoldTarget{
					SaasBrandID: item.Product.SaaSBrandID,
					DisplayName: response.Items[i].DisplayName,
					BoldStart:   response.Items[i].DisplayNameBoldStart,
					BoldLength:  response.Items[i].DisplayNameBoldLength,
				}
			}
		}

		// Bold fallback: DSE items whose product row has NULL bold indices
		// still inherit the master saas_brand's bold range. Matches the
		// inventory /products and purchase item responses so the Flutter
		// review/edit screens render the same bold+small treatment.
		utils.ApplyDisplayBoldFallback(s.db.DB, targets, func(i int, dn string, bs, bl *int) {
			response.Items[i].DisplayName = dn
			response.Items[i].DisplayNameBoldStart = bs
			response.Items[i].DisplayNameBoldLength = bl
		})
	}

	return response
}

// validateStockAvailability checks if sufficient stock is available for all items
// This validation happens BEFORE creating the record to provide immediate feedback
func (s *DailySalesService) validateStockAvailability(tenantID, shopID uuid.UUID, items []DailySalesItemRequest) error {
	for _, itemReq := range items {
		// Get product details first for better error messages
		var product models.Product
		if err := s.db.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("product not found: %s", itemReq.ProductID)
			}
			return fmt.Errorf("failed to verify product: %w", err)
		}

		// Check stock availability
		var stock models.Stock
		err := s.db.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
			shopID, itemReq.ProductID, tenantID).First(&stock).Error

		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return fmt.Errorf("no stock record found for '%s' in this shop - please add initial stock first", product.Name)
			}
			return fmt.Errorf("failed to check stock for '%s': %w", product.Name, err)
		}

		// Validate sufficient quantity available
		if stock.Quantity < itemReq.Quantity {
			return fmt.Errorf("insufficient stock for '%s': available %d, requested %d - please reduce quantity",
				product.Name, stock.Quantity, itemReq.Quantity)
		}

		log.Printf("   ✓ Stock OK for %s: Available=%d, Requested=%d", product.Name, stock.Quantity, itemReq.Quantity)
	}

	return nil
}

// clearDailySalesCache clears related cache entries (non-critical — logs errors instead of failing)
func (s *DailySalesService) clearDailySalesCache(ctx context.Context, tenantID, shopID uuid.UUID) {
	// Clear various cache patterns
	cacheKeys := []string{
		fmt.Sprintf(cache.DailySalesKey, shopID.String(), time.Now().Format("2006-01-02")),
		fmt.Sprintf(cache.PendingApprovalsKey, tenantID.String()),
	}

	for _, key := range cacheKeys {
		if err := s.cache.Delete(ctx, key); err != nil {
			log.Printf("[DailySales] Cache clear failed for key %s (non-critical): %v", key, err)
		}
	}
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Service Adapter - Lightweight adapter to access finance module
// ═══════════════════════════════════════════════════════════════════════════

// CashServiceAdapter provides access to cash management operations
type CashServiceAdapter struct {
	db *database.DB
}

// UpdateCashBalance updates cash holding and creates audit trail
func (a *CashServiceAdapter) UpdateCashBalance(
	ctx context.Context,
	userID, shopID, tenantID uuid.UUID,
	amount float64,
	transactionType, description string,
	relatedEntityType string,
	relatedEntityID *uuid.UUID,
	createdByID uuid.UUID,
) error {
	return a.db.Transaction(func(tx *gorm.DB) error {
		// Get or create cash holding with proper conflict handling
		var holding models.CashHolding
		err := tx.WithContext(ctx).
			Where("user_id = ? AND shop_id = ? AND tenant_id = ?", userID, shopID, tenantID).
			First(&holding).Error

		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				// Look up user's role for the cash holding
				var user models.User
				userRole := "salesman"
				if lookupErr := tx.WithContext(ctx).Select("role").Where("id = ?", userID).First(&user).Error; lookupErr == nil {
					userRole = user.Role
				}

				// Create new cash holding
				holding = models.CashHolding{
					TenantModel: models.TenantModel{
						TenantID: &tenantID,
					},
					UserID:         userID,
					ShopID:         &shopID,
					Role:           userRole,
					CurrentBalance: 0,
					LastUpdatedAt:  time.Now(),
				}

				if err = tx.WithContext(ctx).Create(&holding).Error; err != nil {
					return fmt.Errorf("failed to create cash holding: %w", err)
				}
			} else {
				return fmt.Errorf("failed to get cash holding: %w", err)
			}
		}

		previousBalance := holding.CurrentBalance
		newBalance := previousBalance + amount

		if newBalance < 0 {
			return errors.New("insufficient cash balance")
		}

		// Update balance
		holding.CurrentBalance = newBalance
		holding.LastUpdatedAt = time.Now()
		if err := tx.Save(&holding).Error; err != nil {
			return fmt.Errorf("failed to update cash balance: %w", err)
		}

		// Create audit trail
		transaction := &models.CashTransaction{
			TenantModel: models.TenantModel{
				TenantID: &tenantID,
			},
			UserID:            userID,
			ShopID:            &shopID,
			TransactionType:   transactionType,
			Amount:            amount,
			PreviousBalance:   previousBalance,
			NewBalance:        newBalance,
			RelatedEntityType: relatedEntityType,
			RelatedEntityID:   relatedEntityID,
			Description:       description,
			TransactionDate:   time.Now(),
			CreatedByID:       createdByID,
		}

		if err := tx.Create(transaction).Error; err != nil {
			return fmt.Errorf("failed to create cash transaction: %w", err)
		}

		return nil
	})
}

// HealthCheck validates database connectivity for health endpoint
func (s *DailySalesService) HealthCheck(ctx context.Context) error {
	if s.db == nil {
		return errors.New("database not initialized")
	}

	// Use GORM's built-in SQL ping with context
	sqlDB, err := s.db.DB.DB()
	if err != nil {
		return fmt.Errorf("failed to get database connection: %w", err)
	}

	// Ping with timeout from context
	if err := sqlDB.PingContext(ctx); err != nil {
		return fmt.Errorf("database ping failed: %w", err)
	}

	return nil
}

// ReapplyDailySalesRecord re-applies an approved daily-sale record's stock
// effects within 7 days of approval. SETS each product's stock to the
// item's recorded closing_stock (the value stock SHOULD have right after
// this sale was applied), so any drift since approval — manual edit, an
// older sale being rejected after a fresh stock setup, etc — is undone.
//
// Idempotent: if stock already equals closing_stock, the row is a no-op.
// Audited as movement_type='daily_sale_reapply'. Returns 410-style error
// past the 7-day window so the user runs a fresh sale entry instead.
func (s *DailySalesService) ReapplyDailySalesRecord(ctx context.Context, recordID, tenantID, reappliedByID uuid.UUID) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord
	if err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items", func(db *gorm.DB) *gorm.DB {
			return db.Order("position ASC").Order("unit_price ASC")
		}).
		Preload("Items.Product").First(&record).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}
	if record.Status != models.StatusApproved {
		return nil, fmt.Errorf("only approved records can be reapplied (record is %s)", record.Status)
	}
	if record.ApprovedAt == nil {
		return nil, errors.New("record has no approval timestamp")
	}
	if time.Since(*record.ApprovedAt) > 7*24*time.Hour {
		return nil, errors.New("reapply window expired — this sale was approved more than 7 days ago. Create a fresh adjustment instead")
	}

	applied := 0
	skipped := 0
	err := s.db.Transaction(func(tx *gorm.DB) error {
		for _, item := range record.Items {
			// closing_stock captured at apply/approve time IS the canonical
			// "what stock should be after this sale" value. SET stock to it
			// so any drift since is undone.
			target := item.ClosingStock
			if target < 0 {
				skipped++
				continue
			}

			var stock models.Stock
			stockErr := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("shop_id = ? AND product_id = ? AND tenant_id = ?", record.ShopID, item.ProductID, tenantID).
				First(&stock).Error
			if stockErr != nil {
				if errors.Is(stockErr, gorm.ErrRecordNotFound) {
					log.Printf("⚠️ [DailySales] reapply: stock missing for product %s — skipping", item.ProductID)
					skipped++
					continue
				}
				return fmt.Errorf("failed to get stock for reapply: %w", stockErr)
			}

			if stock.Quantity == target {
				continue // already at target, no-op
			}
			if target < stock.ReservedQuantity {
				log.Printf("⚠️ [DailySales] reapply: product %s target %d < reserved %d, skipping", item.ProductID, target, stock.ReservedQuantity)
				skipped++
				continue
			}

			previousQty := stock.Quantity
			if err := tx.Model(&stock).Update("quantity", target).Error; err != nil {
				return fmt.Errorf("failed to reapply stock for product %s: %w", item.ProductID, err)
			}

			productName := fmt.Sprintf("%s", item.ProductID)
			if item.Product != nil {
				productName = item.Product.Name
			}
			shopRef, prodRef := stock.ShopID, stock.ProductID
			audit := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: &tenantID},
				StockID:          stock.ID,
				ShopID:           &shopRef,
				ProductID:        &prodRef,
				MovementType:     "daily_sale_reapply",
				Quantity:         target - previousQty,
				PreviousQuantity: previousQty,
				NewQuantity:      target,
				UnitCost:         item.UnitPrice,
				TotalCost:        item.TotalAmount,
				Reference:        fmt.Sprintf("Daily Sales Record %s reapplied", record.ID),
				ReferenceID:      &record.ID,
				CreatedByID:      reappliedByID,
				Notes:            fmt.Sprintf("Reapplied to closing_stock=%d for %s (within 7-day window of approval %s)", target, productName, record.ApprovedAt.Format(time.RFC3339)),
			}
			if hErr := tx.Create(&audit).Error; hErr != nil {
				log.Printf("Warning: failed to create stock_history for reapply: %v", hErr)
			}
			applied++
			log.Printf("🔁 [DailySales] reapply: product %s stock %d → %d (record=%s)", productName, previousQty, target, record.ID)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	s.clearDailySalesCache(ctx, tenantID, record.ShopID)
	log.Printf("🔁 [DailySales] reapply complete — record=%s applied=%d skipped=%d total=%d", record.ID, applied, skipped, len(record.Items))

	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// CacheHealthCheck validates Redis cache connectivity for health endpoint
func (s *DailySalesService) CacheHealthCheck(ctx context.Context) error {
	if s.cache == nil {
		return errors.New("cache not initialized")
	}

	// Try a simple ping operation
	if err := s.cache.Ping(ctx); err != nil {
		return fmt.Errorf("cache ping failed: %w", err)
	}

	return nil
}

// ItemPosition is a single (item, new-position) pair in a bulk reorder.
type ItemPosition struct {
	ID       uuid.UUID
	Position int
}

// ReorderItems bulk-updates daily_sales_items.position for a single record.
// All updates run inside one transaction so the order change is atomic and
// list endpoints never read a partial reorder. Tenant-scoped: rejects items
// that belong to other tenants or to a different record.
//
// v1.0.149.
func (s *DailySalesService) ReorderItems(ctx context.Context, recordID, tenantID uuid.UUID, pairs []ItemPosition) error {
	if len(pairs) == 0 {
		return nil
	}
	return s.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Verify the record belongs to this tenant before any write.
		var owned int64
		if err := tx.Model(&models.DailySalesRecord{}).
			Where("id = ? AND tenant_id = ?", recordID, tenantID).
			Count(&owned).Error; err != nil {
			return fmt.Errorf("verify record: %w", err)
		}
		if owned == 0 {
			return fmt.Errorf("record not found")
		}
		for _, p := range pairs {
			res := tx.Model(&models.DailySalesItem{}).
				Where("id = ? AND daily_sales_record_id = ? AND tenant_id = ?", p.ID, recordID, tenantID).
				Update("position", p.Position)
			if res.Error != nil {
				return fmt.Errorf("update item %s: %w", p.ID, res.Error)
			}
		}
		return nil
	})
}

// HealApproveCorruptionResult is the structured return for the
// /admin/heal-approve-corruption endpoint.
//
// v1.0.162.
type HealApproveCorruptionResult struct {
	DryRun         bool                       `json:"dry_run"`
	RecordsScanned int                        `json:"records_scanned"`
	ItemsScanned   int                        `json:"items_scanned"`
	ItemsHealed    int                        `json:"items_healed"`
	HistoriesFixed int                        `json:"histories_fixed"`
	PerRecord      []HealApproveRecordSummary `json:"per_record"`
}

type HealApproveRecordSummary struct {
	RecordID     uuid.UUID `json:"record_id"`
	RecordDate   string    `json:"record_date"`
	ItemsScanned int       `json:"items_scanned"`
	ItemsHealed  int       `json:"items_healed"`
}

type healPlan struct {
	itemID       uuid.UUID
	productID    uuid.UUID
	stockID      uuid.UUID
	beforeOpen   int
	beforeClose  int
	qtySold      int
	openExpected int
	closeExpected int
}

// HealApproveCorruption walks the stock_histories chain for each shop+product
// pair on the given records and reconstructs the true pre-sale stock to fix
// daily_sales_items.opening_stock / closing_stock and stock_histories
// previous_quantity / new_quantity that were corrupted by the v1.0.133-r4
// approval-time GORM-mutation bug. Cosmetic-only — stocks.quantity is already
// correct. v1.0.162.
func (s *DailySalesService) HealApproveCorruption(
	ctx context.Context,
	tenantID uuid.UUID,
	recordIDs []uuid.UUID,
	dryRun bool,
) (*HealApproveCorruptionResult, error) {
	if len(recordIDs) == 0 {
		return nil, errors.New("record_ids required")
	}
	if len(recordIDs) > 200 {
		return nil, errors.New("too many records (max 200 per call)")
	}
	out := &HealApproveCorruptionResult{DryRun: dryRun, PerRecord: []HealApproveRecordSummary{}}

	for _, recordID := range recordIDs {
		var record models.DailySalesRecord
		if err := s.db.Preload("Items").
			Where("id = ? AND tenant_id = ? AND deleted_at IS NULL", recordID, tenantID).
			First(&record).Error; err != nil {
			log.Printf("⚠️ [HealApproveCorruption] record %s skipped: %v", recordID, err)
			continue
		}
		out.RecordsScanned++

		summary := HealApproveRecordSummary{
			RecordID:   record.ID,
			RecordDate: record.RecordDate.Format("2006-01-02"),
		}
		var plans []healPlan

		for _, it := range record.Items {
			out.ItemsScanned++
			summary.ItemsScanned++
			// Only heal rows where opening==closing AND something was sold.
			// Otherwise it's a legitimate zero-qty row.
			if it.OpeningStock != it.ClosingStock || it.Quantity == 0 {
				continue
			}
			// Reconstruct true opening from stock_histories deltas. Walk every
			// history row for this (shop, product) ordered by created_at, sum
			// the `quantity` deltas BEFORE this record's deduction event, and
			// add back current stocks.quantity. The `quantity` column is
			// reliable (the column-mutation bug only affected prev/new).
			var stock models.Stock
			if err := s.db.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				record.ShopID, it.ProductID, tenantID).First(&stock).Error; err != nil {
				log.Printf("⚠️ [HealApproveCorruption] stock not found for product %s: %v", it.ProductID, err)
				continue
			}
			// Sum deltas of all histories CREATED AFTER this record's deduction
			// (so that "rewinding" them lands us at the open value).
			var deltasAfter int64
			s.db.Table("stock_histories").
				Where("stock_id = ? AND tenant_id = ? AND deleted_at IS NULL", stock.ID, tenantID).
				Where("reference_id = ? OR created_at > (SELECT MAX(created_at) FROM stock_histories WHERE reference_id = ? AND stock_id = ?)",
					record.ID, record.ID, stock.ID).
				Select("COALESCE(SUM(quantity), 0)").
				Row().Scan(&deltasAfter)
			// Open = current stock - deltasAfter (deltasAfter is negative for
			// sales, positive for purchases). Equivalent to "what was the stock
			// just before this record's deduction landed".
			beforeOpen := stock.Quantity - int(deltasAfter)
			closeExpected := beforeOpen - it.Quantity
			if closeExpected < 0 {
				closeExpected = 0
			}
			// If reconstructed open equals current closing (i.e. nothing to
			// fix), skip.
			if beforeOpen == it.OpeningStock && closeExpected == it.ClosingStock {
				continue
			}
			plans = append(plans, healPlan{
				itemID:        it.ID,
				productID:     it.ProductID,
				stockID:       stock.ID,
				beforeOpen:    it.OpeningStock,
				beforeClose:   it.ClosingStock,
				qtySold:       it.Quantity,
				openExpected:  beforeOpen,
				closeExpected: closeExpected,
			})
		}

		if dryRun {
			summary.ItemsHealed = len(plans)
			out.ItemsHealed += len(plans)
			out.PerRecord = append(out.PerRecord, summary)
			continue
		}

		// Live: one transaction per record so a partial failure leaves the
		// record untouched.
		err := s.db.Transaction(func(tx *gorm.DB) error {
			for _, p := range plans {
				if err := tx.Model(&models.DailySalesItem{}).
					Where("id = ? AND tenant_id = ?", p.itemID, tenantID).
					Updates(map[string]interface{}{
						"opening_stock": p.openExpected,
						"closing_stock": p.closeExpected,
					}).Error; err != nil {
					return fmt.Errorf("heal item %s: %w", p.itemID, err)
				}
				summary.ItemsHealed++
				out.ItemsHealed++

				// Patch the matching stock_history row(s) for this record+stock.
				if err := tx.Model(&models.StockHistory{}).
					Where("reference_id = ? AND stock_id = ? AND tenant_id = ? AND quantity = ?",
						record.ID, p.stockID, tenantID, -p.qtySold).
					Updates(map[string]interface{}{
						"previous_quantity": p.openExpected,
						"new_quantity":      p.closeExpected,
					}).Error; err != nil {
					log.Printf("⚠️ [HealApproveCorruption] history patch failed for record %s product %s: %v", record.ID, p.productID, err)
				} else {
					out.HistoriesFixed++
				}
			}
			return nil
		})
		if err != nil {
			log.Printf("⚠️ [HealApproveCorruption] record %s heal aborted: %v", record.ID, err)
		}

		out.PerRecord = append(out.PerRecord, summary)
	}

	log.Printf("🩺 [HealApproveCorruption] tenant=%s records=%d items_scanned=%d items_healed=%d histories_fixed=%d dry_run=%v",
		tenantID, out.RecordsScanned, out.ItemsScanned, out.ItemsHealed, out.HistoriesFixed, dryRun)
	return out, nil
}

// driftReconcileSalesAware gates the v1.0.336 sales-aware opening-drift
// reconcile (see decideDriftReconcile). Default ON. Set
// SMART_SALE_DRIFT_RECONCILE_SALES_AWARE=0 to revert to the legacy behavior
// that snapped live stock fully UP to the operator-vouched opening before
// deducting (the source of the Mahua Khera batch-approval cancellation bug).
func driftReconcileSalesAware() bool {
	return os.Getenv("SMART_SALE_DRIFT_RECONCILE_SALES_AWARE") != "0"
}

// decideDriftReconcile decides, at approve time, how to handle the gap between
// the operator-vouched opening (vouchedOpening) and the current live balance
// (liveBefore) for one product, given salesSince = the total units already sold
// for this product (Σ|daily_sale|) AFTER this record was submitted.
//
// It returns:
//   - illegitGap: the signed quantity to record as an opening_drift_reconcile
//     ledger row (0 means write no reconcile row), and
//   - deductBasis: the balance the sale should be deducted FROM.
//
// Rationale — the legacy reconcile (v1.0.329, FM Tower record 2bc7c3c0) assumed
// ANY drift below the vouched opening was an illegitimate non-sale clobber and
// snapped live UP to the vouched opening. That is WRONG when a backlog of
// records is batch-approved: every record carries the SAME submit-time opening,
// so snapping up to it cancels the PRIOR record's legitimate daily_sale (Mahua
// Khera 2026-06-02: 60 products, 1035 bottles overstated). The fix decomposes
// the gap — the portion explained by sales recorded after this record was
// submitted is LEGITIMATE (the lower balance is correct) and is left intact;
// only the residual non-sale drift is reconciled.
//
// salesAware=false reproduces the legacy full-snap behavior exactly, so the
// SMART_SALE_DRIFT_RECONCILE_SALES_AWARE kill-switch is a true revert.
func decideDriftReconcile(vouchedOpening, liveBefore, salesSince int, salesAware bool) (illegitGap, deductBasis int) {
	// Guard not met (no vouched opening, or no drift) → deduct from live, no row.
	if vouchedOpening <= 0 || vouchedOpening == liveBefore {
		return 0, liveBefore
	}
	gap := vouchedOpening - liveBefore
	if !salesAware {
		// Legacy: snap fully to the vouched opening.
		return gap, vouchedOpening
	}
	// Sales-aware: only the non-sale-attributable residual is illegitimate.
	raw := gap - salesSince
	if raw > 0 {
		return raw, liveBefore + raw
	}
	// Gap fully explained by intervening sales (or live is higher, e.g. an
	// intervening purchase) → live is authoritative; deduct from it, no row.
	return 0, liveBefore
}

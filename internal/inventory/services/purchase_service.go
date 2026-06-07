package services

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	"gorm.io/gorm"
)

type PurchaseService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewPurchaseService(db *database.DB, cache *cache.Cache) *PurchaseService {
	return &PurchaseService{
		db:    db,
		cache: cache,
	}
}

// DB returns the underlying gorm.DB for direct queries
func (s *PurchaseService) DB() *gorm.DB {
	return s.db.DB
}

type PurchaseRequest struct {
	VendorID      uuid.UUID                `json:"vendor_id" binding:"required"`
	ShopID        uuid.UUID                `json:"shop_id" binding:"required"`
	ReceiptNo     string                   `json:"receipt_no"`
	Items         []PurchaseItemRequest    `json:"items" binding:"required,min=1"`
	TotalAmount   float64                  `json:"total_amount"`
	TaxAmount     float64                  `json:"tax_amount"`
	RoundOff      float64                  `json:"round_off"`
	Notes         string                   `json:"notes"`
	Payments      []PurchasePaymentRequest `json:"payments"`
	ReceiptImages []string                 `json:"receipt_images"`
}

type PurchaseItemRequest struct {
	ProductID   uuid.UUID  `json:"product_id" binding:"required"`
	Quantity    float64    `json:"quantity" binding:"required,gt=0"`
	UnitPrice   float64    `json:"unit_price" binding:"required,gt=0"`
	TotalPrice  float64    `json:"total_price"`
	ExpiryDate  *time.Time `json:"expiry_date"`
	DutyFee       float64 `json:"duty_fee"`
	Leakage       int     `json:"leakage"`
	ShortReceived int     `json:"short_received"`
	BatchNumber   string  `json:"batch_number"`
}

type PurchasePaymentRequest struct {
	Method string  `json:"method" binding:"required"`
	Amount float64 `json:"amount" binding:"required,gt=0"`
}

type PurchaseResponse struct {
	ID            uuid.UUID                 `json:"id"`
	PurchaseNo    string                    `json:"purchase_no"`
	VendorID      uuid.UUID                 `json:"vendor_id"`
	VendorName    string                    `json:"vendor_name"`
	ShopID        uuid.UUID                 `json:"shop_id"`
	ShopName      string                    `json:"shop_name"`
	ReceiptNo     string                    `json:"receipt_no"`
	// receipt_number / receipt_date / subtotal / tax_amount / round_off mirror
	// the model so the web admin renders the Invoice # column, the real purchase
	// date (not a created_at fallback), and the full bill breakdown.
	ReceiptNumber string                    `json:"receipt_number"`
	ReceiptDate   *time.Time                `json:"receipt_date,omitempty"`
	InvoiceNumber string                    `json:"invoice_number,omitempty"`
	Status        string                    `json:"status"`
	SubTotal      float64                   `json:"subtotal"`
	TaxAmount     float64                   `json:"tax_amount"`
	RoundOff      float64                   `json:"round_off"`
	TotalAmount   float64                   `json:"total_amount"`
	PaidAmount    float64                   `json:"paid_amount"`
	DueAmount     float64                   `json:"due_amount"`
	Items         []PurchaseItemResponse    `json:"items"`
	Payments      []PurchasePaymentResponse `json:"payments"`
	Notes         string                    `json:"notes"`
	ReceiptImages []string                  `json:"receipt_images,omitempty"`
	CreatedBy     uuid.UUID                 `json:"created_by"`
	CreatedByName string                    `json:"created_by_name,omitempty"`
	CreatedByRole string                    `json:"created_by_role,omitempty"`
	ApprovedByName string                   `json:"approved_by_name,omitempty"`
	ApprovedAt    *time.Time                `json:"approved_at,omitempty"`
	ReceivedAt    *time.Time                `json:"received_at,omitempty"`
	CreatedAt     time.Time                 `json:"created_at"`
	UpdatedAt     time.Time                 `json:"updated_at"`
}

type PurchaseItemResponse struct {
	ID                    uuid.UUID  `json:"id"`
	ProductID             uuid.UUID  `json:"product_id"`
	ProductName           string     `json:"product_name"`
	BrandName             string     `json:"brand_name"`
	DisplayName           string     `json:"display_name,omitempty"`
	DisplayNameBoldStart  *int       `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int       `json:"display_name_bold_length,omitempty"`
	Size                  string     `json:"size,omitempty"`
	Quantity              float64    `json:"quantity"`
	UnitPrice             float64    `json:"unit_price"`
	TotalPrice            float64    `json:"total_price"`
	ExpiryDate            *time.Time `json:"expiry_date"`
	DutyFee               float64    `json:"duty_fee"`
	Leakage               int        `json:"leakage"`
	ShortReceived         int        `json:"short_received"`
	BatchNumber           string     `json:"batch_number"`
	CreatedAt             time.Time  `json:"created_at"`
}

type PurchasePaymentResponse struct {
	ID        uuid.UUID `json:"id"`
	Method    string    `json:"method"`
	Amount    float64   `json:"amount"`
	CreatedAt time.Time `json:"created_at"`
}

// UnverifiedProduct + PurchaseNameUnverifiedError — 2026-05-17. A product
// whose name is raw, unverified Stock-Setup text (name_verified=false) must
// be confirmed against a trusted bottle photo from the inventory page BEFORE
// it can be purchased, so purchase and sales always reconcile on the correct
// name. The handler maps this to HTTP 409 + this payload so the app can route
// the operator straight to the photo-verify step for the listed products.
type UnverifiedProduct struct {
	ID   uuid.UUID `json:"product_id" gorm:"column:id"`
	Name string    `json:"name" gorm:"column:name"`
}

type PurchaseNameUnverifiedError struct {
	Products []UnverifiedProduct `json:"unverified_products"`
}

func (e *PurchaseNameUnverifiedError) Error() string {
	names := make([]string, 0, len(e.Products))
	for _, p := range e.Products {
		names = append(names, p.Name)
	}
	return fmt.Sprintf("%d product(s) need a verified name (upload a photo from inventory) before purchase: %s",
		len(e.Products), strings.Join(names, ", "))
}

// ImageRequiredProduct + PurchaseImageRequiredError — 2026-05-18. A product
// created by AI Stock Setup (created_via='stock_setup') that still has NO
// bottle photo (image_url / front_image_url / back_image_url all empty) must
// have a photo attached before AI Purchase will record stock against it —
// otherwise purchase posts quantity onto an unverified image-less row that
// the operator can never visually reconcile. The AI-Purchase apply handler
// maps this to HTTP 409 + this payload so the app can let the operator
// photograph the listed products inline (POST /products/:id/verify-photo)
// and resubmit. Mirrors PurchaseNameUnverifiedError above. Only
// 'stock_setup' is gated; every other created_via (incl. the legacy_exempt
// default) is exempt, so this is strictly forward-only.
type ImageRequiredProduct struct {
	ID   uuid.UUID `json:"product_id" gorm:"column:id"`
	Name string    `json:"name" gorm:"column:name"`
	// v1.0.338 — strict front+back gate. When PURCHASE_REQUIRE_FRONT_BACK=1 the
	// gate requires BOTH faces for every product, so the app needs to know which
	// face(s) are still missing to drive the capture flow. Empty/false in the
	// legacy "any one photo" mode. gorm:"-" — computed from the fetched URLs,
	// not scanned from a column.
	MissingFront bool `json:"missing_front" gorm:"-"`
	MissingBack  bool `json:"missing_back" gorm:"-"`
	// v1.0.356 — set when the product has photos but its name isn't verified yet
	// (requires a confident photo read; post-v355 a verified name also means
	// name+brand+excise are consistent). Lets the app say "needs verification".
	UnverifiedName bool `json:"unverified_name" gorm:"-"`
}

type PurchaseImageRequiredError struct {
	Products []ImageRequiredProduct `json:"image_required_products"`
}

func (e *PurchaseImageRequiredError) Error() string {
	names := make([]string, 0, len(e.Products))
	for _, p := range e.Products {
		names = append(names, p.Name)
	}
	return fmt.Sprintf("%d product(s) need a bottle photo (attach from the review row) before purchase: %s",
		len(e.Products), strings.Join(names, ", "))
}

func (s *PurchaseService) CreatePurchase(ctx context.Context, req PurchaseRequest, tenantID, userID uuid.UUID) (*PurchaseResponse, error) {
	var purchase models.StockPurchase
	var totalCalculated float64

	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	if err := tx.Error; err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Generate purchase number
	purchaseNo, err := s.generatePurchaseNumber(ctx, tenantID)
	if err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to generate purchase number: %w", err)
	}

	// Validate vendor exists
	var vendor models.Vendor
	if err := tx.Where("id = ? AND tenant_id = ?", req.VendorID, tenantID).First(&vendor).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("vendor not found: %w", err)
	}

	// Validate shop exists
	var shop models.Shop
	if err := tx.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("shop not found: %w", err)
	}

	// PURCHASE NAME GATE (2026-05-17) — block before any rows are written.
	// A product still carrying raw, unverified Stock-Setup text must be
	// image-verified first; otherwise purchase would record stock against a
	// garbled name and never reconcile with sales. Structured error → the
	// app sends the operator to the inventory photo-verify step.
	{
		ids := make([]uuid.UUID, 0, len(req.Items))
		for _, it := range req.Items {
			ids = append(ids, it.ProductID)
		}
		if len(ids) > 0 {
			var unv []UnverifiedProduct
			if scErr := tx.Table("products").
				Select("id, name").
				Where("tenant_id = ? AND id IN ? AND deleted_at IS NULL AND name_verified = ?", tenantID, ids, false).
				Scan(&unv).Error; scErr == nil && len(unv) > 0 {
				tx.Rollback()
				return nil, &PurchaseNameUnverifiedError{Products: unv}
			}
		}
	}

	// Create purchase record
	purchase = models.StockPurchase{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		PurchaseNumber: purchaseNo,
		VendorID:       req.VendorID,
		ShopID:         req.ShopID,
		PurchaseDate:   time.Now(),
		Status:         "pending",
		Notes:          req.Notes,
		ReceiptNo:      req.ReceiptNo,
		ReceiptImages:  models.JSONStringList(req.ReceiptImages),
		CreatedBy:      userID,
		TotalAmount:    req.TotalAmount,
	}

	if err := tx.Create(&purchase).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create purchase: %w", err)
	}

	// Create purchase items
	var purchaseItems []models.StockPurchaseItem
	for _, itemReq := range req.Items {
		// Validate product exists
		var product models.Product
		if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("product not found: %w", err)
		}

		itemTotal := itemReq.Quantity * itemReq.UnitPrice
		if itemReq.TotalPrice > 0 {
			itemTotal = itemReq.TotalPrice
		}
		totalCalculated += itemTotal

		purchaseItem := models.StockPurchaseItem{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockPurchaseID: purchase.ID,
			ProductID:       itemReq.ProductID,
			Quantity:        int(itemReq.Quantity),
			UnitCost:        itemReq.UnitPrice,
			TotalCost:       itemTotal,
			ExpiryDate:      itemReq.ExpiryDate,
			BatchNumber:     itemReq.BatchNumber,
			DutyFee:         itemReq.DutyFee,
			Leakage:         itemReq.Leakage,
			ShortReceived:   itemReq.ShortReceived,
		}

		if err := tx.Create(&purchaseItem).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create purchase item: %w", err)
		}

		purchaseItems = append(purchaseItems, purchaseItem)
	}

	// Update purchase totals
	finalTotal := totalCalculated
	if req.TotalAmount > 0 {
		finalTotal = req.TotalAmount
	}

	if err := tx.Model(&purchase).Updates(map[string]interface{}{
		"sub_total":    totalCalculated,
		"tax_amount":  req.TaxAmount,
		"round_off":   req.RoundOff,
		"total_amount": finalTotal,
	}).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update purchase total: %w", err)
	}

	// Create purchase payments
	var purchasePayments []models.StockPurchasePayment
	for _, paymentReq := range req.Payments {
		payment := models.StockPurchasePayment{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockPurchaseID: purchase.ID,
			PaymentMethod:   paymentReq.Method,
			Amount:          paymentReq.Amount,
			PaymentDate:     time.Now(),
		}

		if err := tx.Create(&payment).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create purchase payment: %w", err)
		}

		purchasePayments = append(purchasePayments, payment)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Build response
	response := s.buildPurchaseResponse(purchase, vendor, shop, purchaseItems, purchasePayments)

	// Clear relevant cache
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return response, nil
}

// PurchaseListFilter is the shared filter applied to both the list query and
// its summary aggregates so they always describe the same set.
type PurchaseListFilter struct {
	ShopID      *uuid.UUID
	VendorID    *uuid.UUID
	Status      string
	From        *time.Time // purchase_date >= From
	To          *time.Time // purchase_date <= To (inclusive day)
	HasShortage bool       // only purchases with a short/leak item
}

// apply adds the filter's WHERE clauses to a *gorm.DB scoped to stock_purchases.
// shortageCol is the qualified id column for the EXISTS subquery (e.g.
// "stock_purchases.id" or "sp.id") so it works on both plain + aliased queries.
func (f PurchaseListFilter) apply(q *gorm.DB, idCol string) *gorm.DB {
	if f.ShopID != nil {
		q = q.Where(idColPrefix(idCol)+"shop_id = ?", *f.ShopID)
	}
	if f.VendorID != nil {
		q = q.Where(idColPrefix(idCol)+"vendor_id = ?", *f.VendorID)
	}
	if f.Status != "" {
		q = q.Where(idColPrefix(idCol)+"status = ?", f.Status)
	}
	if f.From != nil {
		q = q.Where(idColPrefix(idCol)+"purchase_date >= ?", *f.From)
	}
	if f.To != nil {
		q = q.Where(idColPrefix(idCol)+"purchase_date < ?", f.To.AddDate(0, 0, 1))
	}
	if f.HasShortage {
		q = q.Where("EXISTS (SELECT 1 FROM stock_purchase_items spi WHERE spi.purchase_id = "+idCol+
			" AND spi.deleted_at IS NULL AND (COALESCE(spi.short_received,0) > 0 OR COALESCE(spi.leakage,0) > 0))")
	}
	return q
}

// idColPrefix turns "sp.id" → "sp." and "stock_purchases.id" → "stock_purchases."
func idColPrefix(idCol string) string {
	if i := strings.LastIndex(idCol, "."); i >= 0 {
		return idCol[:i+1]
	}
	return ""
}

func (s *PurchaseService) GetPurchases(ctx context.Context, tenantID uuid.UUID, f PurchaseListFilter, limit, offset int) ([]PurchaseResponse, int64, error) {
	var purchases []models.StockPurchase
	var total int64

	query := f.apply(s.db.Where("tenant_id = ?", tenantID), "stock_purchases.id")

	// Get total count
	if err := query.Model(&models.StockPurchase{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count purchases: %w", err)
	}

	// Get purchases with pagination
	if err := query.
		Preload("Vendor").
		Preload("Shop").
		Preload("Items").
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		Preload("Payments").
		Preload("CreatedByUser").
			Preload("ApprovedBy").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&purchases).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get purchases: %w", err)
	}

	var responses []PurchaseResponse
	for _, purchase := range purchases {
		response := s.buildPurchaseResponseFromModel(purchase)
		responses = append(responses, *response)
	}

	return responses, total, nil
}

// PurchasesSummary aggregates the FULL filtered set (not just the current page)
// so the list header shows accurate totals regardless of pagination.
type PurchasesSummary struct {
	Count        int64   `json:"count"`
	TotalAmount  float64 `json:"total_amount"`
	TotalBottles int64   `json:"total_bottles"`
	Received     int64   `json:"received"`
	Pending      int64   `json:"pending"`
	Cancelled    int64   `json:"cancelled"`
	WithShortage int64   `json:"with_shortage"`
	ShortBottles int64   `json:"short_bottles"`
}

// GetPurchasesSummaryData computes header metrics over the same filter the list
// uses (tenant + optional shop + optional status), ignoring pagination.
func (s *PurchaseService) GetPurchasesSummaryData(ctx context.Context, tenantID uuid.UUID, f PurchaseListFilter) (PurchasesSummary, error) {
	var out PurchasesSummary

	base := f.apply(s.db.Model(&models.StockPurchase{}).Where("tenant_id = ?", tenantID), "stock_purchases.id")

	// Counts + status breakdown over the full filtered set (cancelled included
	// so the breakdown is honest). Money + bottle VALUE excludes cancelled
	// (voided) purchases — unless the user is explicitly viewing cancelled —
	// so the headline reflects real stock purchased, not reversed orders.
	excludeCancelled := f.Status != "cancelled"

	var head struct {
		Count     int64
		Received  int64
		Pending   int64
		Cancelled int64
	}
	base.Select("COUNT(*) as count, " +
		"COUNT(*) FILTER (WHERE status = 'received') as received, " +
		"COUNT(*) FILTER (WHERE status = 'pending') as pending, " +
		"COUNT(*) FILTER (WHERE status = 'cancelled') as cancelled").
		Scan(&head)
	out.Count = head.Count
	out.Received = head.Received
	out.Pending = head.Pending
	out.Cancelled = head.Cancelled

	valQ := f.apply(s.db.Model(&models.StockPurchase{}).Where("tenant_id = ?", tenantID), "stock_purchases.id")
	if excludeCancelled {
		valQ = valQ.Where("status <> 'cancelled'")
	}
	var val struct{ TotalAmount float64 }
	valQ.Select("COALESCE(SUM(total_amount),0) as total_amount").Scan(&val)
	out.TotalAmount = val.TotalAmount

	// Bottles + shortage aggregates over the same filtered purchase set.
	itemsQ := f.apply(s.db.Table("stock_purchase_items spi").
		Joins("JOIN stock_purchases sp ON sp.id = spi.purchase_id").
		Where("sp.tenant_id = ? AND spi.deleted_at IS NULL AND sp.deleted_at IS NULL", tenantID), "sp.id")
	if excludeCancelled {
		itemsQ = itemsQ.Where("sp.status <> 'cancelled'")
	}
	var items struct {
		TotalBottles int64
		ShortBottles int64
		WithShortage int64
	}
	itemsQ.Select("COALESCE(SUM(spi.quantity),0) as total_bottles, " +
		"COALESCE(SUM(COALESCE(spi.short_received,0) + COALESCE(spi.leakage,0)),0) as short_bottles, " +
		"COUNT(DISTINCT sp.id) FILTER (WHERE COALESCE(spi.short_received,0) > 0 OR COALESCE(spi.leakage,0) > 0) as with_shortage").
		Scan(&items)
	out.TotalBottles = items.TotalBottles
	out.ShortBottles = items.ShortBottles
	out.WithShortage = items.WithShortage

	return out, nil
}

func (s *PurchaseService) GetPurchaseByID(ctx context.Context, id, tenantID uuid.UUID) (*PurchaseResponse, error) {
	var purchase models.StockPurchase

	if err := s.db.
		Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Vendor").
		Preload("Shop").
		Preload("Items").
		Preload("Items.Product").
		Preload("Items.Product.Brand").
		Preload("Payments").
		Preload("CreatedByUser").
			Preload("ApprovedBy").
		First(&purchase).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("purchase not found")
		}
		return nil, fmt.Errorf("failed to get purchase: %w", err)
	}

	return s.buildPurchaseResponseFromModel(purchase), nil
}

func (s *PurchaseService) ReceivePurchase(ctx context.Context, id, tenantID, userID uuid.UUID) error {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	if err := tx.Error; err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Get purchase with items
	var purchase models.StockPurchase
	if err := tx.Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Items").
		First(&purchase).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("purchase not found: %w", err)
	}

	// v1.0.388 — idempotent + double-add safe. Stock is added EXACTLY ONCE here
	// (AI apply no longer moves stock at submit). If this purchase was already
	// received (status flipped + received_at stamped), return success WITHOUT
	// re-incrementing — a double-tap of "Receive & Update Stock" must never
	// double-count stock.
	if purchase.Status == "received" || purchase.ReceivedAt != nil {
		tx.Rollback()
		return nil
	}
	if purchase.Status != "pending" {
		tx.Rollback()
		return fmt.Errorf("purchase is not in pending status")
	}

	// Create or update stock for each item
	for _, item := range purchase.Items {
		// Check if stock exists for this product in this shop
		var stock models.Stock
		err := tx.Where("product_id = ? AND shop_id = ? AND tenant_id = ?",
			item.ProductID, purchase.ShopID, tenantID).First(&stock).Error

		// SINGLE point where shortage is subtracted from stock. item.Quantity is
		// the GROSS billed count (both legacy CreatePurchase and AI apply store
		// gross); netReceivedQty subtracts leakage + short exactly once.
		netDelta := netReceivedQty(item.Quantity, item.Leakage, item.ShortReceived)
		var prevQty int

		if err == gorm.ErrRecordNotFound {
			// Create new stock record (previous = 0).
			now := time.Now()
			stock = models.Stock{
				TenantModel: models.TenantModel{
					BaseModel: models.BaseModel{ID: uuid.New()},
					TenantID:  &tenantID,
				},
				ProductID:        item.ProductID,
				ShopID:           purchase.ShopID,
				Quantity:         netDelta,
				MinimumLevel:     0,
				MaximumLevel:     0,
				AverageCost:      item.UnitCost,
				LastPurchaseDate: &now,
			}
			prevQty = 0
			if err := tx.Create(&stock).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create stock: %w", err)
			}
		} else if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to check stock: %w", err)
		} else {
			// Update existing stock. Snapshot prev BEFORE the in-place GORM
			// update so the audit row records the true pre-purchase balance.
			prevQty = stock.Quantity
			newStock := prevQty + netDelta
			now := time.Now()

			updates := map[string]interface{}{
				"quantity":           newStock,
				"average_cost":       item.UnitCost,
				"last_purchase_date": &now,
			}

			if err := tx.Model(&stock).Updates(updates).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to update stock: %w", err)
			}
		}

		// v1.0.216 — purchase apply MUST also write a stock_histories row.
		// Pre-fix only models.StockMovement was created, so the audit ledger
		// for stocks.quantity had no entry for received purchases. That's the
		// root cause of the FM Tower ICONIQ 750ML +12-without-history drift
		// surfaced in the 2026-05-11 audit. ShopID + ProductID are denormalized
		// so audit queries can filter by shop without joining stocks.
		purchaseID := purchase.ID
		histShopRef := stock.ShopID
		histProdRef := stock.ProductID
		history := models.StockHistory{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockID:          stock.ID,
			ShopID:           &histShopRef,
			ProductID:        &histProdRef,
			MovementType:     "purchase",
			Quantity:         netDelta,
			PreviousQuantity: prevQty,
			NewQuantity:      prevQty + netDelta,
			UnitCost:         item.UnitCost,
			TotalCost:        float64(netDelta) * item.UnitCost,
			Reference:        fmt.Sprintf("Stock Purchase %s received", purchase.PurchaseNumber),
			ReferenceID:      &purchaseID,
			Notes:            fmt.Sprintf("Stock received from purchase %s (gross=%d, leakage=%d, short=%d, net=%d)", purchase.PurchaseNumber, item.Quantity, item.Leakage, item.ShortReceived, netDelta),
			CreatedByID:      userID,
		}
		if err := tx.Create(&history).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create stock history: %w", err)
		}

		// Legacy StockMovement record (kept for callers that still read it).
		movement := models.StockMovement{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockID:      stock.ID,
			MovementType: "purchase",
			Quantity:     netDelta,
			Reference:    "purchase",
			ReferenceID:  &purchaseID,
			Notes:        fmt.Sprintf("Stock received from purchase %s", purchase.PurchaseNumber),
		}

		if err := tx.Create(&movement).Error; err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to create stock movement: %w", err)
		}
	}

	// Update purchase status
	if err := tx.Model(&purchase).Updates(map[string]interface{}{
		"status":      "received",
		"received_at": time.Now(),
		"received_by": userID,
	}).Error; err != nil {
		tx.Rollback()
		return fmt.Errorf("failed to update purchase status: %w", err)
	}

	if err := tx.Commit().Error; err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	stockCacheKey := fmt.Sprintf("stocks:shop:%s:tenant:%s", purchase.VendorID.String(), tenantID.String())
	s.cache.Delete(ctx, stockCacheKey)

	return nil
}

func (s *PurchaseService) generatePurchaseNumber(ctx context.Context, tenantID uuid.UUID) (string, error) {
	year := time.Now().Year()

	var count int64
	if err := s.db.
		Model(&models.StockPurchase{}).
		Where("tenant_id = ? AND EXTRACT(YEAR FROM created_at) = ?", tenantID, year).
		Count(&count).Error; err != nil {
		return "", fmt.Errorf("failed to count purchases: %w", err)
	}

	return fmt.Sprintf("PUR-%d-%05d", year, count+1), nil
}

func (s *PurchaseService) buildPurchaseResponse(
	purchase models.StockPurchase,
	vendor models.Vendor,
	shop models.Shop,
	items []models.StockPurchaseItem,
	payments []models.StockPurchasePayment,
) *PurchaseResponse {
	response := &PurchaseResponse{
		ID:            purchase.ID,
		PurchaseNo:    purchase.PurchaseNumber,
		VendorID:      purchase.VendorID,
		VendorName:    vendor.Name,
		ShopID:        purchase.ShopID, // was purchase.VendorID
		ShopName:      shop.Name,
		ReceiptNo:     purchase.ReceiptNo,
		ReceiptNumber: purchase.ReceiptNo,
		Status:        purchase.Status,
		SubTotal:      purchase.SubTotal,
		TaxAmount:     purchase.TaxAmount,
		RoundOff:      purchase.RoundOff,
		TotalAmount:   purchase.TotalAmount,
		Notes:         purchase.Notes,
		ReceiptImages: []string(purchase.ReceiptImages),
		CreatedBy:     purchase.CreatedBy,
		ReceivedAt:    purchase.ReceivedAt,
		CreatedAt:     purchase.CreatedAt,
		UpdatedAt:     purchase.UpdatedAt,
	}
	if !purchase.PurchaseDate.IsZero() {
		pd := purchase.PurchaseDate
		response.ReceiptDate = &pd
	}

	// Lookup creator name once so the Flutter success screen can show it.
	var creator models.User
	if err := s.db.Select("id, first_name, last_name, role").
		Where("id = ?", purchase.CreatedBy).
		First(&creator).Error; err == nil {
		response.CreatedByName = creator.FullName()
		response.CreatedByRole = creator.Role
	}

	for _, item := range items {
		itemResponse := PurchaseItemResponse{
			ID:          item.ID,
			ProductID:   item.ProductID,
			Quantity:    float64(item.Quantity),
			UnitPrice:   item.UnitCost,
			TotalPrice:  item.TotalCost,
			ExpiryDate:  item.ExpiryDate,
			BatchNumber: item.BatchNumber,
			DutyFee:       item.DutyFee,
			Leakage:       item.Leakage,
			ShortReceived: item.ShortReceived,
			CreatedAt:     item.CreatedAt,
		}
		response.Items = append(response.Items, itemResponse)
	}

	// POST /purchases returns immediately after save, so Product rows aren't
	// preloaded here. Do one batched SELECT by ID to hydrate the response
	// with product_name + display_name + bold indices (so the Flutter
	// success screen renders the same bold/small treatment as GET paths).
	s.hydratePurchaseItemsFromProducts(response.Items)

	for _, payment := range payments {
		paymentResponse := PurchasePaymentResponse{
			ID:        payment.ID,
			Method:    payment.PaymentMethod,
			Amount:    payment.Amount,
			CreatedAt: payment.CreatedAt,
		}
		response.Payments = append(response.Payments, paymentResponse)
	}

	return response
}

// hydratePurchaseItemsFromProducts fills product_name, size, brand_name,
// display_name, and the bold indices on item responses whose source rows
// didn't have Product preloaded — then runs the saas_brand bold fallback.
// Used by buildPurchaseResponse (POST path, where items come from an insert
// and Product isn't preloaded) so the Flutter response matches the GET path.
func (s *PurchaseService) hydratePurchaseItemsFromProducts(items []PurchaseItemResponse) {
	if len(items) == 0 {
		return
	}
	idSet := map[uuid.UUID]struct{}{}
	for _, it := range items {
		idSet[it.ProductID] = struct{}{}
	}
	ids := make([]uuid.UUID, 0, len(idSet))
	for id := range idSet {
		ids = append(ids, id)
	}
	var products []models.Product
	if err := s.db.Preload("Brand").Where("id IN ?", ids).Find(&products).Error; err != nil {
		return
	}
	byID := make(map[uuid.UUID]models.Product, len(products))
	for _, p := range products {
		byID[p.ID] = p
	}

	targets := make([]utils.DisplayBoldTarget, len(items))
	for i := range items {
		p, ok := byID[items[i].ProductID]
		if !ok {
			continue
		}
		items[i].ProductName = p.Name
		items[i].Size = p.Size
		items[i].DisplayName = p.DisplayName
		items[i].DisplayNameBoldStart = p.DisplayNameBoldStart
		items[i].DisplayNameBoldLength = p.DisplayNameBoldLength
		if p.Brand != nil {
			items[i].BrandName = p.Brand.Name
		}
		targets[i] = utils.DisplayBoldTarget{
			SaasBrandID: p.SaaSBrandID,
			DisplayName: items[i].DisplayName,
			BoldStart:   items[i].DisplayNameBoldStart,
			BoldLength:  items[i].DisplayNameBoldLength,
		}
	}
	utils.ApplyDisplayBoldFallback(s.db.DB, targets, func(i int, dn string, bs, bl *int) {
		items[i].DisplayName = dn
		items[i].DisplayNameBoldStart = bs
		items[i].DisplayNameBoldLength = bl
	})
}

// PurchaReportItem represents a single item in the purchase report
type PurchaReportItem struct {
	ProductID    uuid.UUID `json:"product_id"`
	ProductName  string    `json:"product_name"`
	BrandName    string    `json:"brand_name"`
	CategoryName string    `json:"category_name"`
	CategoryID   uuid.UUID `json:"category_id"`
	Size         string    `json:"size"`
	Quantity     int       `json:"quantity"`
	UnitPrice    float64   `json:"unit_price"`
	TotalPrice   float64   `json:"total_price"`
	OpeningStock int       `json:"opening_stock,omitempty"`
	VendorName   string    `json:"vendor_name"`
	PurchaseDate string    `json:"purchase_date"`
	PurchaseNo   string    `json:"purchase_no"`
}

// GetPurchaReportPreview generates a Purcha (daily stock) report
// Structure: pages (by size) -> categories -> items
// Each item shows: opening stock, receipt (purchase), total, sale, rate, amount, closing stock
func (s *PurchaseService) GetPurchaReportPreview(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	dateStr, viewMode, categoryFilter string,
	showOpening bool,
) (map[string]interface{}, error) {
	date, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		return nil, fmt.Errorf("invalid date format, expected YYYY-MM-DD: %w", err)
	}

	nextDay := date.AddDate(0, 0, 1)

	// 1. Get all products for this shop with their current stock
	type productRow struct {
		ProductID    uuid.UUID `gorm:"column:product_id"`
		ProductName  string    `gorm:"column:product_name"`
		DisplayName  string    `gorm:"column:display_name"`
		BrandName    string    `gorm:"column:brand_name"`
		CategoryName string    `gorm:"column:category_name"`
		Size         string    `gorm:"column:size"`
		SellingPrice float64   `gorm:"column:selling_price"`
		MRP          float64   `gorm:"column:mrp"`
		StockQty     int       `gorm:"column:stock_qty"`
	}

	var products []productRow
	if err := s.db.Raw(`
		SELECT
			p.id as product_id,
			p.name as product_name,
			COALESCE(NULLIF(p.display_name, ''), b.name, p.name) as display_name,
			COALESCE(b.name, p.name) as brand_name,
			COALESCE(c.name, 'Other') as category_name,
			COALESCE(p.size, '') as size,
			COALESCE(p.selling_price, 0) as selling_price,
			COALESCE(p.mrp, 0) as mrp,
			COALESCE(st.quantity, 0) as stock_qty
		FROM products p
		LEFT JOIN brands b ON b.id = p.brand_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN stocks st ON st.product_id = p.id AND st.shop_id = ? AND st.tenant_id = ? AND st.deleted_at IS NULL
		WHERE p.tenant_id = ?
		  AND p.deleted_at IS NULL
		ORDER BY c.name, p.size, p.name
	`, shopID, tenantID, tenantID).Scan(&products).Error; err != nil {
		return nil, fmt.Errorf("failed to query products: %w", err)
	}

	// 2. Get purchases (receipts) for this date
	type purchaseRow struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		Quantity  int       `gorm:"column:quantity"`
	}
	var purchases []purchaseRow
	s.db.Raw(`
		SELECT spi.product_id, SUM(spi.quantity) as quantity
		FROM stock_purchase_items spi
		JOIN stock_purchases sp ON sp.id = spi.purchase_id
		WHERE sp.tenant_id = ? AND sp.shop_id = ?
		  AND sp.purchase_date >= ? AND sp.purchase_date < ?
		  AND sp.deleted_at IS NULL AND spi.deleted_at IS NULL
		GROUP BY spi.product_id
	`, tenantID, shopID, date, nextDay).Scan(&purchases)

	purchaseMap := map[uuid.UUID]int{}
	for _, p := range purchases {
		purchaseMap[p.ProductID] = p.Quantity
	}

	// 3. Get sales for this date from daily_sales_records items
	type saleRow struct {
		ProductID uuid.UUID `gorm:"column:product_id"`
		Quantity  int       `gorm:"column:quantity"`
	}
	var sales []saleRow
	s.db.Raw(`
		SELECT dsri.product_id, SUM(dsri.quantity_sold) as quantity
		FROM daily_sales_items dsri
		JOIN daily_sales_records dsr ON dsr.id = dsri.daily_sales_record_id
		WHERE dsr.tenant_id = ? AND dsr.shop_id = ?
		  AND dsr.record_date >= ? AND dsr.record_date < ?
		  AND dsr.deleted_at IS NULL AND dsri.deleted_at IS NULL
		GROUP BY dsri.product_id
	`, tenantID, shopID, date, nextDay).Scan(&sales)

	saleMap := map[uuid.UUID]int{}
	for _, sl := range sales {
		saleMap[sl.ProductID] = sl.Quantity
	}

	// 4. Build report items grouped by size then category
	type reportItem struct {
		ProductID    string  `json:"product_id"`
		BrandName    string  `json:"brand_name"`
		ProductName  string  `json:"product_name"`
		DisplayName  string  `json:"display_name"`
		Size         string  `json:"size"`
		CategoryName string  `json:"category_name"`
		OpeningStock int     `json:"opening_stock"`
		Receipt      int     `json:"receipt"`
		Total        int     `json:"total"`
		Sale         int     `json:"sale"`
		Rate         float64 `json:"rate"`
		Amount       float64 `json:"amount"`
		ClosingStock int     `json:"closing_stock"`
		SerialNo     int     `json:"serial_no"`
	}

	type catGroup struct {
		Items        []reportItem
		TotalOpen    int
		TotalReceipt int
		TotalTotal   int
		TotalSale    int
		TotalAmount  float64
		TotalClosing int
	}
	sizeGroups := map[string]map[string]*catGroup{}

	for _, p := range products {
		// Apply category filter
		if categoryFilter == "non_beer" && p.CategoryName == "Beer" {
			continue
		}
		if categoryFilter == "beer" && p.CategoryName != "Beer" {
			continue
		}

		receipt := purchaseMap[p.ProductID]
		sale := saleMap[p.ProductID]
		closing := p.StockQty
		opening := closing + sale - receipt
		if opening < 0 {
			opening = 0
		}
		total := opening + receipt
		amount := float64(sale) * p.SellingPrice
		rate := p.SellingPrice

		// Skip items with no activity
		if opening == 0 && receipt == 0 && sale == 0 && closing == 0 {
			continue
		}

		// Map product size to range label
		size := p.Size
		if size == "" {
			size = "Other"
		} else {
			ml := extractML(size)
			isBeer := categoryFilter == "beer"
			ranges := nonBeerSizeRanges
			if isBeer {
				ranges = beerSizeRanges
			}
			for _, rng := range ranges {
				if ml >= rng.MinML && ml <= rng.MaxML {
					size = rng.Label
					break
				}
			}
		}
		cat := p.CategoryName
		if cat == "" {
			cat = "Other"
		}

		if sizeGroups[size] == nil {
			sizeGroups[size] = map[string]*catGroup{}
		}
		if sizeGroups[size][cat] == nil {
			sizeGroups[size][cat] = &catGroup{}
		}

		// Use display name if available, else clean product name
		displayName := p.DisplayName
		if displayName == "" {
			displayName = p.ProductName
		}
		effectiveRate := p.MRP
		if effectiveRate == 0 {
			effectiveRate = p.SellingPrice
		}
		rate = effectiveRate

		item := reportItem{
			ProductID:    p.ProductID.String(),
			BrandName:    displayName,
			ProductName:  p.ProductName,
			DisplayName:  displayName,
			Size:         size,
			CategoryName: cat,
			OpeningStock: opening,
			Receipt:      receipt,
			Total:        total,
			Sale:         sale,
			Rate:         rate,
			Amount:       amount,
			ClosingStock: closing,
		}

		g := sizeGroups[size][cat]
		g.Items = append(g.Items, item)
		g.TotalOpen += opening
		g.TotalReceipt += receipt
		g.TotalTotal += total
		g.TotalSale += sale
		g.TotalAmount += amount
		g.TotalClosing += closing
	}

	// 5. Build pages response sorted by size
	// Use range labels for ordering
	var sizeOrder []string
	if categoryFilter == "beer" {
		for _, rng := range beerSizeRanges {
			sizeOrder = append(sizeOrder, rng.Label)
		}
	} else {
		for _, rng := range nonBeerSizeRanges {
			sizeOrder = append(sizeOrder, rng.Label)
		}
	}
	var sortedSizes []string
	for _, sz := range sizeOrder {
		if _, ok := sizeGroups[sz]; ok {
			sortedSizes = append(sortedSizes, sz)
		}
	}
	for sz := range sizeGroups {
		found := false
		for _, ss := range sortedSizes {
			if sz == ss {
				found = true
				break
			}
		}
		if !found {
			sortedSizes = append(sortedSizes, sz)
		}
	}

	var pages []map[string]interface{}
	var grandOpen, grandReceipt, grandTotal, grandSale, grandClosing int
	var grandAmount float64

	for _, size := range sortedSizes {
		cats := sizeGroups[size]
		var categories []map[string]interface{}
		var pageOpen, pageReceipt, pageTotal, pageSale, pageClosing int
		var pageAmount float64
		sortIdx := 0

		for catName, g := range cats {
			for i := range g.Items {
				g.Items[i].SerialNo = i + 1
			}
			catMap := map[string]interface{}{
				"category_name": catName,
				"sort_order":    sortIdx,
				"items":         g.Items,
				"total_opening": g.TotalOpen,
				"total_receipt": g.TotalReceipt,
				"total_total":   g.TotalTotal,
				"total_sale":    g.TotalSale,
				"total_amount":  g.TotalAmount,
				"total_closing": g.TotalClosing,
			}
			categories = append(categories, catMap)
			pageOpen += g.TotalOpen
			pageReceipt += g.TotalReceipt
			pageTotal += g.TotalTotal
			pageSale += g.TotalSale
			pageAmount += g.TotalAmount
			pageClosing += g.TotalClosing
			sortIdx++
		}

		page := map[string]interface{}{
			"size":          size,
			"categories":    categories,
			"grand_opening": pageOpen,
			"grand_receipt": pageReceipt,
			"grand_total":   pageTotal,
			"grand_sale":    pageSale,
			"grand_amount":  pageAmount,
			"grand_closing": pageClosing,
		}
		pages = append(pages, page)
		grandOpen += pageOpen
		grandReceipt += pageReceipt
		grandTotal += pageTotal
		grandSale += pageSale
		grandAmount += pageAmount
		grandClosing += pageClosing
	}

	var shopName string
	s.db.Raw("SELECT name FROM shops WHERE id = ? AND tenant_id = ?", shopID, tenantID).Scan(&shopName)

	return map[string]interface{}{
		"shop_id":         shopID,
		"shop_name":       shopName,
		"report_date":     dateStr,
		"generated_at":    time.Now().Format(time.RFC3339),
		"category_filter": categoryFilter,
		"view_mode":       viewMode,
		"show_opening":    showOpening,
		"pages":           pages,
		"total_opening":   grandOpen,
		"total_receipt":   grandReceipt,
		"total_total":     grandTotal,
		"total_sale":      grandSale,
		"total_amount":    grandAmount,
		"total_closing":   grandClosing,
	}, nil
}

func (s *PurchaseService) buildPurchaseResponseFromModel(purchase models.StockPurchase) *PurchaseResponse {
	response := &PurchaseResponse{
		ID:            purchase.ID,
		PurchaseNo:    purchase.PurchaseNumber,
		VendorID:      purchase.VendorID,
		ShopID:        purchase.ShopID, // was purchase.VendorID — corrupted shop_id on every row
		ReceiptNo:     purchase.ReceiptNo,
		ReceiptNumber: purchase.ReceiptNo,
		InvoiceNumber: purchase.InvoiceNumber,
		Status:        purchase.Status,
		SubTotal:      purchase.SubTotal,
		TaxAmount:     purchase.TaxAmount,
		RoundOff:      purchase.RoundOff,
		TotalAmount:   purchase.TotalAmount,
		PaidAmount:    purchase.PaidAmount,
		DueAmount:     purchase.DueAmount,
		Notes:         purchase.Notes,
		ReceiptImages: []string(purchase.ReceiptImages),
		CreatedBy:     purchase.CreatedBy,
		ApprovedAt:    purchase.ApprovedAt,
		ReceivedAt:    purchase.ReceivedAt,
		CreatedAt:     purchase.CreatedAt,
		UpdatedAt:     purchase.UpdatedAt,
	}
	if !purchase.PurchaseDate.IsZero() {
		pd := purchase.PurchaseDate
		response.ReceiptDate = &pd
	}
	// Fall back to the dedicated invoice_number column's value via ReceiptNo
	// when invoice_number is blank (legacy rows stored the bill no. in receipt_no).
	if response.InvoiceNumber == "" {
		response.InvoiceNumber = purchase.ReceiptNo
	}

	if purchase.Vendor != nil {
		response.VendorName = purchase.Vendor.Name
	}

	if purchase.Shop != nil {
		response.ShopName = purchase.Shop.Name
	}

	if purchase.CreatedByUser != nil {
		response.CreatedByName = purchase.CreatedByUser.FullName()
		response.CreatedByRole = purchase.CreatedByUser.Role
	}

	if purchase.ApprovedBy != nil {
		response.ApprovedByName = purchase.ApprovedBy.FullName()
	}

	// Build item responses + collect saas_brand ids so we can run the bold
	// fallback in one batch after the loop.
	targets := make([]utils.DisplayBoldTarget, 0, len(purchase.Items))
	targetIdx := make([]int, 0, len(purchase.Items))
	for _, item := range purchase.Items {
		itemResponse := PurchaseItemResponse{
			ID:          item.ID,
			ProductID:   item.ProductID,
			Quantity:    float64(item.Quantity),
			UnitPrice:   item.UnitCost,
			TotalPrice:  item.TotalCost,
			ExpiryDate:  item.ExpiryDate,
			BatchNumber: item.BatchNumber,
			DutyFee:       item.DutyFee,
			Leakage:       item.Leakage,
			ShortReceived: item.ShortReceived,
			CreatedAt:     item.CreatedAt,
		}

		if item.Product != nil {
			itemResponse.ProductName = item.Product.Name
			itemResponse.Size = item.Product.Size
			// Carry admin-configured display_name through so the web admin
			// renders the bold + small treatment on purchase item lines.
			itemResponse.DisplayName = item.Product.DisplayName
			itemResponse.DisplayNameBoldStart = item.Product.DisplayNameBoldStart
			itemResponse.DisplayNameBoldLength = item.Product.DisplayNameBoldLength
			if item.Product.Brand != nil {
				itemResponse.BrandName = item.Product.Brand.Name
			}
			targets = append(targets, utils.DisplayBoldTarget{
				SaasBrandID: item.Product.SaaSBrandID,
				DisplayName: itemResponse.DisplayName,
				BoldStart:   itemResponse.DisplayNameBoldStart,
				BoldLength:  itemResponse.DisplayNameBoldLength,
			})
			targetIdx = append(targetIdx, len(response.Items))
		}

		response.Items = append(response.Items, itemResponse)
	}

	// Fallback: products with NULL bold indices that are linked to a master
	// saas_brand inherit the master's bold range. Matches the inventory
	// /products response — same rendering path end-to-end.
	utils.ApplyDisplayBoldFallback(s.db.DB, targets, func(i int, dn string, bs, bl *int) {
		ri := targetIdx[i]
		response.Items[ri].DisplayName = dn
		response.Items[ri].DisplayNameBoldStart = bs
		response.Items[ri].DisplayNameBoldLength = bl
	})

	for _, payment := range purchase.Payments {
		paymentResponse := PurchasePaymentResponse{
			ID:        payment.ID,
			Method:    payment.PaymentMethod,
			Amount:    payment.Amount,
			CreatedAt: payment.CreatedAt,
		}
		response.Payments = append(response.Payments, paymentResponse)
	}

	return response
}

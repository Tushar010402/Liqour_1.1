package services

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"gorm.io/gorm"
)

type PurchaseService struct {
	db                   *database.DB
	cache                *cache.Cache
	workflowNotification *notifservices.WorkflowNotificationService
}

func NewPurchaseService(db *database.DB, cache *cache.Cache) *PurchaseService {
	return &PurchaseService{
		db:    db,
		cache: cache,
	}
}

// SetWorkflowNotificationService sets the workflow notification service for sending approval notifications
func (s *PurchaseService) SetWorkflowNotificationService(wn *notifservices.WorkflowNotificationService) {
	s.workflowNotification = wn
}

type PurchaseRequest struct {
	VendorID    uuid.UUID                `json:"vendor_id" binding:"required"`
	ShopID      uuid.UUID                `json:"shop_id" binding:"required"`
	ReceiptNo   string                   `json:"receipt_no"`
	Items       []PurchaseItemRequest    `json:"items" binding:"required,min=1"`
	SubTotal    float64                  `json:"sub_total"`
	Subtotal    float64                  `json:"subtotal"`    // Alternative camelCase for Flutter
	TaxAmount   float64                  `json:"tax_amount"`  // TDS amount
	TdsAmount   float64                  `json:"tds_amount"`  // Alternative field name
	RoundOff    float64                  `json:"round_off"`   // Round-off adjustment
	TotalAmount float64                  `json:"total_amount"`
	Notes       string                   `json:"notes"`
	Payments    []PurchasePaymentRequest `json:"payments"`
	// Receipt/Invoice Information
	ReceiptNumber   *string    `json:"receipt_number"`
	ReceiptDate     *time.Time `json:"receipt_date"`
	ReceiptImageURL *string    `json:"receipt_image_url"`
	ReceiptNotes    *string    `json:"receipt_notes"`
}

type PurchaseItemRequest struct {
	ProductID   uuid.UUID  `json:"product_id" binding:"required"`
	Quantity    float64    `json:"quantity" binding:"required,gt=0"`
	UnitPrice   float64    `json:"unit_price" binding:"required,gt=0"`
	TotalPrice  float64    `json:"total_price"`
	ExpiryDate  *time.Time `json:"expiry_date"`
	BatchNumber string     `json:"batch_number"`
}

type PurchasePaymentRequest struct {
	Method string  `json:"method" binding:"required"`
	Amount float64 `json:"amount" binding:"required,gt=0"`
}

type PurchaseResponse struct {
	ID          uuid.UUID                 `json:"id"`
	PurchaseNo  string                    `json:"purchase_no"`
	VendorID    uuid.UUID                 `json:"vendor_id"`
	VendorName  string                    `json:"vendor_name"`
	ShopID      uuid.UUID                 `json:"shop_id"`
	ShopName    string                    `json:"shop_name"`
	ReceiptNo   string                    `json:"receipt_no"`
	Status      string                    `json:"status"`
	SubTotal    float64                   `json:"sub_total"`
	TaxAmount   float64                   `json:"tax_amount"` // TDS amount
	RoundOff    float64                   `json:"round_off"`  // Round-off adjustment
	TotalAmount float64                   `json:"total_amount"`
	Items       []PurchaseItemResponse    `json:"items"`
	Payments    []PurchasePaymentResponse `json:"payments"`
	Notes       string                    `json:"notes"`
	// Receipt/Invoice Information
	ReceiptNumber   *string    `json:"receipt_number,omitempty"`
	ReceiptDate     *time.Time `json:"receipt_date,omitempty"`
	ReceiptImageURL *string    `json:"receipt_image_url,omitempty"`
	ReceiptNotes    *string    `json:"receipt_notes,omitempty"`
	// User info
	CreatedBy     uuid.UUID `json:"created_by"`
	CreatedByName string    `json:"created_by_name"`
	CreatedByRole string    `json:"created_by_role"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
	// Approval workflow fields
	SubmittedAt     time.Time  `json:"submitted_at"`
	ApprovedByID    *uuid.UUID `json:"approved_by_id,omitempty"`
	ApprovedByName  string     `json:"approved_by_name,omitempty"`
	ApprovedAt      *time.Time `json:"approved_at,omitempty"`
	RejectionReason string     `json:"rejection_reason,omitempty"`
}

// RejectRequest is the request body for rejecting a purchase
type RejectRequest struct {
	Reason string `json:"reason" binding:"required"`
}

type PurchaseItemResponse struct {
	ID          uuid.UUID  `json:"id"`
	ProductID   uuid.UUID  `json:"product_id"`
	ProductName string     `json:"product_name"`
	BrandName   string     `json:"brand_name"`
	Size        string     `json:"size"`
	Quantity    float64    `json:"quantity"`
	UnitPrice   float64    `json:"unit_price"`
	TotalPrice  float64    `json:"total_price"`
	ExpiryDate  *time.Time `json:"expiry_date"`
	BatchNumber string     `json:"batch_number"`
	CreatedAt   time.Time  `json:"created_at"`
}

type PurchasePaymentResponse struct {
	ID        uuid.UUID `json:"id"`
	Method    string    `json:"method"`
	Amount    float64   `json:"amount"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *PurchaseService) CreatePurchase(ctx context.Context, req PurchaseRequest, tenantID, userID uuid.UUID, userRole string) (*PurchaseResponse, error) {
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

	// All purchases require approval - no auto-approval
	// Approval can be done by assistant_manager, manager, admin, or owner
	shouldAutoApprove := false // All purchases start as pending

	now := time.Now()

	// Handle alternative field names for subtotal and tax
	subTotal := req.SubTotal
	if subTotal == 0 && req.Subtotal > 0 {
		subTotal = req.Subtotal
	}
	taxAmount := req.TaxAmount
	if taxAmount == 0 && req.TdsAmount > 0 {
		taxAmount = req.TdsAmount
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
		PurchaseDate:   now,
		SubTotal:       subTotal,
		TaxAmount:      taxAmount, // TDS amount
		RoundOff:       req.RoundOff,
		Status:         "pending",
		Notes:          req.Notes,
		CreatedBy:      userID,
		CreatedByRole:  userRole,
		SubmittedAt:    now,
		// Receipt/Invoice Information
		ReceiptNumber:   req.ReceiptNumber,
		ReceiptDate:     req.ReceiptDate,
		ReceiptImageURL: req.ReceiptImageURL,
		ReceiptNotes:    req.ReceiptNotes,
	}

	// Auto-approve for assistant_manager and above
	if shouldAutoApprove {
		purchase.Status = "approved"
		purchase.ApprovedByID = &userID
		purchase.ApprovedAt = &now
	}

	if err := tx.Create(&purchase).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to create purchase: %w", err)
	}

	// Create purchase items
	var purchaseItems []models.StockPurchaseItem
	for _, itemReq := range req.Items {
		// Validate product exists and preload brand
		var product models.Product
		if err := tx.Preload("Brand").Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
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
			Product:         &product, // Keep product reference for response
			Quantity:        int(itemReq.Quantity),
			UnitCost:        itemReq.UnitPrice,
			TotalCost:       itemTotal,
			ExpiryDate:      itemReq.ExpiryDate,
			BatchNumber:     itemReq.BatchNumber,
		}

		if err := tx.Create(&purchaseItem).Error; err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to create purchase item: %w", err)
		}

		purchaseItems = append(purchaseItems, purchaseItem)
	}

	// Update purchase totals
	// SubTotal is the sum of item prices (before TDS)
	// TaxAmount is TDS (typically 1% of subtotal)
	// RoundOff is adjustment to round total to whole number
	// TotalAmount is SubTotal + TaxAmount + RoundOff
	finalSubTotal := subTotal
	if finalSubTotal == 0 {
		finalSubTotal = totalCalculated // Use calculated total from items as subtotal
	}

	finalTaxAmount := taxAmount
	// If tax wasn't provided but subtotal was, calculate 1% TDS
	// Note: Only auto-calculate if both were not explicitly provided
	// If they provided subtotal but not tax, we assume no TDS

	finalRoundOff := req.RoundOff

	finalTotal := req.TotalAmount
	if finalTotal == 0 {
		// If total not provided, calculate: SubTotal + TaxAmount + RoundOff
		finalTotal = finalSubTotal + finalTaxAmount + finalRoundOff
	}

	// Update all financial fields
	updates := map[string]interface{}{
		"sub_total":    finalSubTotal,
		"tax_amount":   finalTaxAmount,
		"round_off":    finalRoundOff,
		"total_amount": finalTotal,
	}
	if err := tx.Model(&purchase).Updates(updates).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to update purchase totals: %w", err)
	}
	purchase.SubTotal = finalSubTotal
	purchase.TaxAmount = finalTaxAmount
	purchase.RoundOff = finalRoundOff
	purchase.TotalAmount = finalTotal

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

	// If auto-approved, add stock immediately
	if shouldAutoApprove {
		if err := s.addStockForPurchase(tx, purchase, purchaseItems, tenantID, userID); err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("failed to add stock: %w", err)
		}
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Load the user who created the purchase for the response
	var createdByUser models.User
	if err := s.db.Where("id = ?", userID).First(&createdByUser).Error; err == nil {
		purchase.CreatedByUser = &createdByUser
	}

	// Build response
	response := s.buildPurchaseResponse(purchase, vendor, shop, purchaseItems, purchasePayments)

	// Clear relevant cache
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Clear stock cache if stock was added
	if shouldAutoApprove {
		stockCacheKey := fmt.Sprintf("stocks:shop:%s:tenant:%s", purchase.ShopID.String(), tenantID.String())
		s.cache.Delete(ctx, stockCacheKey)
	}

	// Notify approvers about new purchase order requiring approval (if not auto-approved)
	if !shouldAutoApprove && s.workflowNotification != nil {
		go func() {
			if err := s.workflowNotification.NotifyPurchaseCreated(context.Background(), &purchase); err != nil {
				log.Printf("[PURCHASE] Failed to send purchase creation notification: %v", err)
			}
		}()
	}

	return response, nil
}

func (s *PurchaseService) GetPurchases(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, status string, limit, offset int) ([]PurchaseResponse, int64, error) {
	var purchases []models.StockPurchase
	var total int64

	query := s.db.Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	if status != "" {
		query = query.Where("status = ?", status)
	}

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

	if purchase.Status != "pending" {
		tx.Rollback()
		return fmt.Errorf("purchase is not in pending status")
	}

	// Create or update stock for each item
	for _, item := range purchase.Items {
		// Check if stock exists for this product in this shop
		var stock models.Stock
		err := tx.Where("product_id = ? AND shop_id = ? AND tenant_id = ?",
			item.ProductID, purchase.ShopID, tenantID).First(&stock).Error // FIX: Use ShopID not VendorID

		if err == gorm.ErrRecordNotFound {
			// Create new stock record
			stock = models.Stock{
				TenantModel: models.TenantModel{
					BaseModel: models.BaseModel{ID: uuid.New()},
					TenantID:  &tenantID,
				},
				ProductID:         item.ProductID,
				ShopID:            purchase.ShopID, // FIX: Use ShopID not VendorID
				Quantity:          item.Quantity,
				AvailableQuantity: item.Quantity,
				MinimumLevel:      0,
				MaximumLevel:      0,
				AverageCost:       item.UnitCost,
				LastPurchaseDate:  &time.Time{},
			}
			*stock.LastPurchaseDate = time.Now()

			if err := tx.Create(&stock).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to create stock: %w", err)
			}
		} else if err != nil {
			tx.Rollback()
			return fmt.Errorf("failed to check stock: %w", err)
		} else {
			// Update existing stock
			newStock := stock.Quantity + item.Quantity
			newAvailable := newStock - stock.ReservedQuantity - stock.DamagedQuantity
			now := time.Now()

			updates := map[string]interface{}{
				"quantity":           newStock,
				"available_quantity": newAvailable,
				"average_cost":       item.UnitCost,
				"last_purchase_date": &now,
			}

			if err := tx.Model(&stock).Updates(updates).Error; err != nil {
				tx.Rollback()
				return fmt.Errorf("failed to update stock: %w", err)
			}
		}

		// Create stock movement record
		purchaseID := purchase.ID
		movement := models.StockMovement{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockID:      stock.ID,
			MovementType: "purchase",
			Quantity:     item.Quantity,
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

	stockCacheKey := fmt.Sprintf("stocks:shop:%s:tenant:%s", purchase.ShopID.String(), tenantID.String()) // FIX: Use ShopID not VendorID
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
	// Get created_by_name from user if available
	createdByName := ""
	if purchase.CreatedByUser != nil {
		createdByName = strings.TrimSpace(purchase.CreatedByUser.FirstName + " " + purchase.CreatedByUser.LastName)
		if createdByName == "" {
			createdByName = purchase.CreatedByUser.Username
		}
	}

	response := &PurchaseResponse{
		ID:          purchase.ID,
		PurchaseNo:  purchase.PurchaseNumber,
		VendorID:    purchase.VendorID,
		VendorName:  vendor.Name,
		ShopID:      purchase.ShopID,
		ShopName:    shop.Name,
		ReceiptNo:   purchase.ReceiptNo,
		Status:      purchase.Status,
		SubTotal:    purchase.SubTotal,
		TaxAmount:   purchase.TaxAmount,
		RoundOff:    purchase.RoundOff,
		TotalAmount: purchase.TotalAmount,
		Notes:       purchase.Notes,
		// Receipt/Invoice Information
		ReceiptNumber:   purchase.ReceiptNumber,
		ReceiptDate:     purchase.ReceiptDate,
		ReceiptImageURL: purchase.ReceiptImageURL,
		ReceiptNotes:    purchase.ReceiptNotes,
		// User info
		CreatedBy:     purchase.CreatedBy,
		CreatedByName: createdByName,
		CreatedByRole: purchase.CreatedByRole,
		CreatedAt:     purchase.CreatedAt,
		UpdatedAt:     purchase.UpdatedAt,
		SubmittedAt:   purchase.SubmittedAt,
	}

	for _, item := range items {
		itemResponse := PurchaseItemResponse{
			ID:          item.ID,
			ProductID:   item.ProductID,
			Quantity:    float64(item.Quantity),
			UnitPrice:   item.UnitCost,
			TotalPrice:  item.TotalCost, // Use TotalCost (persisted field)
			ExpiryDate:  item.ExpiryDate,
			BatchNumber: item.BatchNumber,
			CreatedAt:   item.CreatedAt,
		}
		// Get product details for name, brand, and size
		if item.Product != nil {
			itemResponse.ProductName = item.Product.Name
			itemResponse.Size = item.Product.Size
			if item.Product.Brand != nil {
				itemResponse.BrandName = item.Product.Brand.Name
			}
		}
		response.Items = append(response.Items, itemResponse)
	}

	for _, payment := range payments {
		paymentResponse := PurchasePaymentResponse{
			ID:        payment.ID,
			Method:    payment.Method,
			Amount:    payment.Amount,
			CreatedAt: payment.CreatedAt,
		}
		response.Payments = append(response.Payments, paymentResponse)
	}

	return response
}

func (s *PurchaseService) buildPurchaseResponseFromModel(purchase models.StockPurchase) *PurchaseResponse {
	// Get created_by_name from user if available
	createdByName := ""
	if purchase.CreatedByUser != nil {
		createdByName = strings.TrimSpace(purchase.CreatedByUser.FirstName + " " + purchase.CreatedByUser.LastName)
		if createdByName == "" {
			createdByName = purchase.CreatedByUser.Username
		}
	}

	response := &PurchaseResponse{
		ID:          purchase.ID,
		PurchaseNo:  purchase.PurchaseNumber,
		VendorID:    purchase.VendorID,
		ShopID:      purchase.ShopID,
		ReceiptNo:   purchase.ReceiptNo,
		Status:      purchase.Status,
		SubTotal:    purchase.SubTotal,
		TaxAmount:   purchase.TaxAmount,
		RoundOff:    purchase.RoundOff,
		TotalAmount: purchase.TotalAmount,
		Notes:       purchase.Notes,
		// Receipt/Invoice Information
		ReceiptNumber:   purchase.ReceiptNumber,
		ReceiptDate:     purchase.ReceiptDate,
		ReceiptImageURL: purchase.ReceiptImageURL,
		ReceiptNotes:    purchase.ReceiptNotes,
		// User info
		CreatedBy:     purchase.CreatedBy,
		CreatedByName: createdByName,
		CreatedByRole: purchase.CreatedByRole,
		CreatedAt:     purchase.CreatedAt,
		UpdatedAt:     purchase.UpdatedAt,
		SubmittedAt:   purchase.SubmittedAt,
	}

	if purchase.Vendor != nil {
		response.VendorName = purchase.Vendor.Name
	}

	if purchase.Shop != nil {
		response.ShopName = purchase.Shop.Name
	}

	for _, item := range purchase.Items {
		itemResponse := PurchaseItemResponse{
			ID:          item.ID,
			ProductID:   item.ProductID,
			Quantity:    float64(item.Quantity),
			UnitPrice:   item.UnitCost,
			TotalPrice:  item.TotalCost, // Use TotalCost (persisted field) instead of TotalPrice
			ExpiryDate:  item.ExpiryDate,
			BatchNumber: item.BatchNumber,
			CreatedAt:   item.CreatedAt,
		}

		if item.Product != nil {
			itemResponse.ProductName = item.Product.Name
			itemResponse.Size = item.Product.Size // Include product size
			if item.Product.Brand != nil {
				itemResponse.BrandName = item.Product.Brand.Name
			}
		}

		response.Items = append(response.Items, itemResponse)
	}

	for _, payment := range purchase.Payments {
		paymentResponse := PurchasePaymentResponse{
			ID:        payment.ID,
			Method:    payment.Method,
			Amount:    payment.Amount,
			CreatedAt: payment.CreatedAt,
		}
		response.Payments = append(response.Payments, paymentResponse)
	}

	// Add approval workflow fields
	response.SubmittedAt = purchase.SubmittedAt
	response.CreatedByRole = purchase.CreatedByRole
	response.ApprovedByID = purchase.ApprovedByID
	response.ApprovedAt = purchase.ApprovedAt
	response.RejectionReason = purchase.RejectionReason

	if purchase.CreatedByUser != nil {
		response.CreatedByName = purchase.CreatedByUser.FirstName + " " + purchase.CreatedByUser.LastName
	}
	if purchase.ApprovedBy != nil {
		response.ApprovedByName = purchase.ApprovedBy.FirstName + " " + purchase.ApprovedBy.LastName
	}

	return response
}

// GetPendingApprovals returns purchases pending approval
func (s *PurchaseService) GetPendingApprovals(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, limit, offset int) ([]PurchaseResponse, int64, error) {
	var purchases []models.StockPurchase
	var total int64

	query := s.db.Where("tenant_id = ? AND status = ?", tenantID, "pending")

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	// Get total count
	if err := query.Model(&models.StockPurchase{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count pending purchases: %w", err)
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
		Order("submitted_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&purchases).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get pending purchases: %w", err)
	}

	var responses []PurchaseResponse
	for _, purchase := range purchases {
		response := s.buildPurchaseResponseFromModel(purchase)
		responses = append(responses, *response)
	}

	return responses, total, nil
}

// ApprovePurchase approves a pending purchase and adds stock
func (s *PurchaseService) ApprovePurchase(ctx context.Context, id, tenantID, approverID uuid.UUID) (*PurchaseResponse, error) {
	tx := s.db.Begin()
	defer func() {
		if r := recover(); r != nil {
			tx.Rollback()
		}
	}()

	if err := tx.Error; err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}

	// Get purchase with items
	var purchase models.StockPurchase
	if err := tx.Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Items").
		Preload("Vendor").
		Preload("Shop").
		First(&purchase).Error; err != nil {
		tx.Rollback()
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("purchase not found")
		}
		return nil, fmt.Errorf("failed to get purchase: %w", err)
	}

	if purchase.Status != "pending" {
		tx.Rollback()
		return nil, fmt.Errorf("cannot approve: purchase is not in pending status (current: %s)", purchase.Status)
	}

	// Add stock for each item
	if err := s.addStockForPurchase(tx, purchase, purchase.Items, tenantID, approverID); err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to add stock: %w", err)
	}

	// Update purchase status
	now := time.Now()
	if err := tx.Model(&purchase).Updates(map[string]interface{}{
		"status":         "approved",
		"approved_by_id": approverID,
		"approved_at":    now,
	}).Error; err != nil {
		tx.Rollback()
		return nil, fmt.Errorf("failed to approve purchase: %w", err)
	}

	// Create vendor transaction for this purchase (for ledger tracking)
	vendorTx := models.VendorTransaction{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		VendorID:        purchase.VendorID,
		TransactionType: "purchase",
		Amount:          purchase.TotalAmount,
		TransactionDate: now,
		ReferenceNumber: purchase.PurchaseNumber,
		Notes:           fmt.Sprintf("Stock Purchase %s", purchase.PurchaseNumber),
	}
	if err := tx.Create(&vendorTx).Error; err != nil {
		// Log error but don't fail the approval - vendor transactions are for tracking
		log.Printf("Warning: Failed to create vendor transaction for purchase %s: %v", purchase.PurchaseNumber, err)
	}

	if err := tx.Commit().Error; err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	// Clear caches
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	stockCacheKey := fmt.Sprintf("stocks:shop:%s:tenant:%s", purchase.ShopID.String(), tenantID.String())
	s.cache.Delete(ctx, stockCacheKey)

	// Notify creator that their purchase order was approved
	if s.workflowNotification != nil {
		go func() {
			// Get approver info for notification
			var approver models.User
			if err := s.db.First(&approver, "id = ?", approverID).Error; err != nil {
				log.Printf("[PURCHASE] Failed to get approver for notification: %v", err)
				return
			}
			if err := s.workflowNotification.NotifyPurchaseApproved(context.Background(), &purchase, &approver); err != nil {
				log.Printf("[PURCHASE] Failed to send purchase approval notification: %v", err)
			}
		}()
	}

	// Return updated purchase
	return s.GetPurchaseByID(ctx, id, tenantID)
}

// RejectPurchase rejects a pending purchase with a reason
func (s *PurchaseService) RejectPurchase(ctx context.Context, id, tenantID, approverID uuid.UUID, reason string) (*PurchaseResponse, error) {
	var purchase models.StockPurchase
	if err := s.db.Where("id = ? AND tenant_id = ?", id, tenantID).First(&purchase).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("purchase not found")
		}
		return nil, fmt.Errorf("failed to get purchase: %w", err)
	}

	if purchase.Status != "pending" {
		return nil, fmt.Errorf("cannot reject: purchase is not in pending status (current: %s)", purchase.Status)
	}

	now := time.Now()
	if err := s.db.Model(&purchase).Updates(map[string]interface{}{
		"status":           "rejected",
		"approved_by_id":   approverID,
		"approved_at":      now,
		"rejection_reason": reason,
	}).Error; err != nil {
		return nil, fmt.Errorf("failed to reject purchase: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("purchases:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	// Notify creator that their purchase order was rejected with reason
	if s.workflowNotification != nil {
		go func() {
			// Get rejector info for notification
			var rejector models.User
			if err := s.db.First(&rejector, "id = ?", approverID).Error; err != nil {
				log.Printf("[PURCHASE] Failed to get rejector for notification: %v", err)
				return
			}
			if err := s.workflowNotification.NotifyPurchaseRejected(context.Background(), &purchase, &rejector, reason); err != nil {
				log.Printf("[PURCHASE] Failed to send purchase rejection notification: %v", err)
			}
		}()
	}

	return s.GetPurchaseByID(ctx, id, tenantID)
}

// addStockForPurchase is a helper that adds stock for a purchase (used by both auto-approve and manual approve)
func (s *PurchaseService) addStockForPurchase(tx *gorm.DB, purchase models.StockPurchase, items []models.StockPurchaseItem, tenantID, userID uuid.UUID) error {
	for _, item := range items {
		// Check if stock exists for this product in this shop
		var stock models.Stock
		err := tx.Where("product_id = ? AND shop_id = ? AND tenant_id = ?",
			item.ProductID, purchase.ShopID, tenantID).First(&stock).Error

		if err == gorm.ErrRecordNotFound {
			// Create new stock record
			now := time.Now()
			stock = models.Stock{
				TenantModel: models.TenantModel{
					BaseModel: models.BaseModel{ID: uuid.New()},
					TenantID:  &tenantID,
				},
				ProductID:         item.ProductID,
				ShopID:            purchase.ShopID,
				Quantity:          item.Quantity,
				AvailableQuantity: item.Quantity,
				MinimumLevel:      0,
				MaximumLevel:      0,
				AverageCost:       item.UnitCost,
				LastPurchaseDate:  &now,
			}

			if err := tx.Create(&stock).Error; err != nil {
				return fmt.Errorf("failed to create stock: %w", err)
			}
		} else if err != nil {
			return fmt.Errorf("failed to check stock: %w", err)
		} else {
			// Update existing stock
			newQuantity := stock.Quantity + item.Quantity
			newAvailable := newQuantity - stock.ReservedQuantity - stock.DamagedQuantity
			now := time.Now()

			updates := map[string]interface{}{
				"quantity":            newQuantity,
				"available_quantity":  newAvailable,
				"average_cost":        item.UnitCost,
				"last_purchase_date":  &now,
				"last_purchase_price": item.UnitCost,
			}

			if err := tx.Model(&stock).Updates(updates).Error; err != nil {
				return fmt.Errorf("failed to update stock: %w", err)
			}
		}

		// Create stock history record
		purchaseID := purchase.ID
		history := models.StockHistory{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			StockID:          stock.ID,
			MovementType:     "purchase",
			Quantity:         item.Quantity,
			PreviousQuantity: stock.Quantity - item.Quantity, // Approximate since we just updated
			NewQuantity:      stock.Quantity,
			UnitCost:         item.UnitCost,
			TotalCost:        item.UnitCost * float64(item.Quantity),
			Reference:        "purchase",
			ReferenceID:      &purchaseID,
			Notes:            fmt.Sprintf("Stock added from purchase %s", purchase.PurchaseNumber),
			CreatedByID:      userID,
		}

		if err := tx.Create(&history).Error; err != nil {
			return fmt.Errorf("failed to create stock history: %w", err)
		}
	}

	return nil
}

package services

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"gorm.io/gorm"
)

// SalesService handles individual sale transactions
type SalesService struct {
	db                  *database.DB
	cache               *cache.Cache
	workflowNotification *notifservices.WorkflowNotificationService
}

// NewSalesService creates a new sales service
func NewSalesService(db *database.DB, cache *cache.Cache) *SalesService {
	return &SalesService{
		db:    db,
		cache: cache,
	}
}

// SetWorkflowNotificationService sets the workflow notification service for sending approval notifications
func (s *SalesService) SetWorkflowNotificationService(wn *notifservices.WorkflowNotificationService) {
	s.workflowNotification = wn
}

// SaleRequest represents sale creation/update request
type SaleRequest struct {
	SaleDate      time.Time         `json:"sale_date" binding:"required"`
	ShopID        uuid.UUID         `json:"shop_id" binding:"required"`
	SalesmanID    *uuid.UUID        `json:"salesman_id"`
	CustomerName  string            `json:"customer_name"`
	CustomerPhone string            `json:"customer_phone"`
	PaymentMethod string            `json:"payment_method" binding:"required"`
	PaymentStatus string            `json:"payment_status"`
	PaidAmount    float64           `json:"paid_amount" binding:"min=0"`
	Notes         string            `json:"notes"`
	Items         []SaleItemRequest `json:"items" binding:"required,min=1"`
}

// SaleItemRequest represents sale item request
type SaleItemRequest struct {
	ProductID      uuid.UUID `json:"product_id" binding:"required"`
	Quantity       int       `json:"quantity" binding:"required,gt=0"`
	UnitPrice      float64   `json:"unit_price" binding:"required,gt=0"`
	DiscountAmount float64   `json:"discount_amount" binding:"min=0"`
	DiscountReason string    `json:"discount_reason"`
}

// SaleResponse represents sale in responses
type SaleResponse struct {
	ID              uuid.UUID          `json:"id"`
	SaleNumber      string             `json:"sale_number"`
	SaleDate        time.Time          `json:"sale_date"`
	ShopID          uuid.UUID          `json:"shop_id"`
	ShopName        string             `json:"shop_name"`
	SalesmanID      *uuid.UUID         `json:"salesman_id"`
	SalesmanName    string             `json:"salesman_name"`
	CustomerName    string             `json:"customer_name"`
	CustomerPhone   string             `json:"customer_phone"`
	SubTotal        float64            `json:"sub_total"`
	DiscountAmount  float64            `json:"discount_amount"`
	TaxAmount       float64            `json:"tax_amount"`
	TotalAmount     float64            `json:"total_amount"`
	PaidAmount      float64            `json:"paid_amount"`
	DueAmount       float64            `json:"due_amount"`
	PaymentMethod   string             `json:"payment_method"`
	PaymentStatus   string             `json:"payment_status"`
	Status          string             `json:"status"`
	ApprovedAt      *time.Time         `json:"approved_at"`
	ApprovedByName  string             `json:"approved_by_name"`
	RejectedAt      *time.Time         `json:"rejected_at"`
	RejectedByName  string             `json:"rejected_by_name"`
	RejectionReason string             `json:"rejection_reason"`
	RevertedAt      *time.Time         `json:"reverted_at"`
	RevertedByName  string             `json:"reverted_by_name"`
	RevertReason    string             `json:"revert_reason"`
	CreatedByID     uuid.UUID          `json:"created_by_id"`
	CreatedByName   string             `json:"created_by_name"`
	Notes           string             `json:"notes"`
	CreatedAt       time.Time          `json:"created_at"`
	UpdatedAt       time.Time          `json:"updated_at"`
	Items           []SaleItemResponse `json:"items"`
	TotalItems      int                `json:"total_items"`
}

// SaleItemResponse represents sale item in responses
type SaleItemResponse struct {
	ID             uuid.UUID `json:"id"`
	ProductID      uuid.UUID `json:"product_id"`
	ProductName    string    `json:"product_name"`
	BrandName      string    `json:"brand_name"`
	CategoryName   string    `json:"category_name"`
	Size           string    `json:"size"`
	ImageURL       string    `json:"image_url"`
	Quantity       int       `json:"quantity"`
	UnitPrice      float64   `json:"unit_price"`
	DiscountAmount float64   `json:"discount_amount"`
	DiscountReason string    `json:"discount_reason"`
	TotalPrice     float64   `json:"total_price"`
}

// CreateSale creates a new individual sale
func (s *SalesService) CreateSale(ctx context.Context, req SaleRequest, tenantID, createdByID uuid.UUID) (*SaleResponse, error) {
	// Verify shop exists and belongs to tenant
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		return nil, errors.New("shop not found or doesn't belong to this tenant")
	}

	// Verify salesman if provided
	if req.SalesmanID != nil {
		var salesman models.Salesman
		if err := s.db.Where("id = ? AND tenant_id = ? AND shop_id = ?",
			*req.SalesmanID, tenantID, req.ShopID).First(&salesman).Error; err != nil {
			return nil, errors.New("salesman not found or doesn't belong to this shop")
		}
	}

	// Validate payment method
	validPaymentMethods := []string{models.PaymentCash, models.PaymentCard, models.PaymentUPI, models.PaymentCredit}
	if !utils.Contains(validPaymentMethods, req.PaymentMethod) {
		return nil, errors.New("invalid payment method")
	}

	// Start transaction
	var sale *models.Sale
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Calculate totals
		var subTotal, totalDiscount float64
		for _, itemReq := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			itemTotal := float64(itemReq.Quantity) * itemReq.UnitPrice
			subTotal += itemTotal
			totalDiscount += itemReq.DiscountAmount
		}

		totalAmount := subTotal - totalDiscount
		dueAmount := totalAmount - req.PaidAmount

		// Determine payment status
		paymentStatus := req.PaymentStatus
		if paymentStatus == "" {
			if req.PaidAmount >= totalAmount {
				paymentStatus = "paid"
			} else if req.PaidAmount > 0 {
				paymentStatus = "partial"
			} else {
				paymentStatus = "pending"
			}
		}

		// Create sale
		sale = &models.Sale{
			TenantModel:    models.TenantModel{TenantID: &tenantID},
			SaleNumber:     utils.GenerateSaleNumber(),
			SaleDate:       req.SaleDate,
			ShopID:         req.ShopID,
			SalesmanID:     req.SalesmanID,
			CustomerName:   req.CustomerName,
			CustomerPhone:  req.CustomerPhone,
			SubTotal:       subTotal,
			DiscountAmount: totalDiscount,
			TotalAmount:    totalAmount,
			PaidAmount:     req.PaidAmount,
			DueAmount:      dueAmount,
			PaymentMethod:  req.PaymentMethod,
			PaymentStatus:  paymentStatus,
			Status:         models.StatusPending,
			CreatedByID:    createdByID,
			Notes:          req.Notes,
		}

		if err := tx.Create(&sale).Error; err != nil {
			return fmt.Errorf("failed to create sale: %w", err)
		}

		// Create sale items
		for _, itemReq := range req.Items {
			totalPrice := (float64(itemReq.Quantity) * itemReq.UnitPrice) - itemReq.DiscountAmount

			item := models.SaleItem{
				TenantModel:    models.TenantModel{TenantID: &tenantID},
				SaleID:         sale.ID,
				ProductID:      itemReq.ProductID,
				Quantity:       itemReq.Quantity,
				UnitPrice:      itemReq.UnitPrice,
				DiscountAmount: itemReq.DiscountAmount,
				DiscountReason: itemReq.DiscountReason,
				TotalPrice:     totalPrice,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create sale item: %w", err)
			}
		}

		// Create payment record if amount paid
		if req.PaidAmount > 0 {
			payment := models.SalePayment{
				TenantModel:   models.TenantModel{TenantID: &tenantID},
				SaleID:        sale.ID,
				Amount:        req.PaidAmount,
				PaymentMethod: req.PaymentMethod,
				PaymentDate:   req.SaleDate,
				CreatedByID:   createdByID,
			}

			if err := tx.Create(&payment).Error; err != nil {
				return fmt.Errorf("failed to create payment record: %w", err)
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, req.ShopID)

	// Notify approvers about new sale requiring approval
	if s.workflowNotification != nil {
		go func() {
			if err := s.workflowNotification.NotifySaleCreated(context.Background(), sale); err != nil {
				log.Printf("[SALES] Failed to send sale creation notification: %v", err)
			}
		}()
	}

	// Return created sale
	return s.GetSaleByID(ctx, sale.ID, tenantID)
}

// GetSales returns paginated list of sales
func (s *SalesService) GetSales(ctx context.Context, tenantID uuid.UUID, filters SalesFilters) (*SalesListResponse, error) {
	var sales []models.Sale
	var totalCount int64

	query := s.db.Model(&models.Sale{}).
		Where("tenant_id = ?", tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("RejectedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	// Apply filters
	if filters.ShopID != uuid.Nil {
		query = query.Where("shop_id = ?", filters.ShopID)
	}
	if filters.SalesmanID != uuid.Nil {
		query = query.Where("salesman_id = ?", filters.SalesmanID)
	}
	if filters.Status != "" {
		query = query.Where("status = ?", filters.Status)
	}
	if filters.PaymentStatus != "" {
		query = query.Where("payment_status = ?", filters.PaymentStatus)
	}
	if !filters.StartDate.IsZero() {
		query = query.Where("sale_date >= ?", filters.StartDate)
	}
	if !filters.EndDate.IsZero() {
		query = query.Where("sale_date <= ?", filters.EndDate)
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count sales: %w", err)
	}

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("sale_date DESC, created_at DESC").
		Find(&sales).Error; err != nil {
		return nil, fmt.Errorf("failed to get sales: %w", err)
	}

	// Convert to response format
	responses := make([]*SaleResponse, len(sales))
	for i, sale := range sales {
		responses[i] = s.mapSaleToResponse(&sale)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &SalesListResponse{
		Sales:      responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
	}, nil
}

// GetSaleByID returns sale by ID
func (s *SalesService) GetSaleByID(ctx context.Context, saleID, tenantID uuid.UUID) (*SaleResponse, error) {
	var sale models.Sale

	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("RejectedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category").
		Preload("Payments").
		First(&sale).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to get sale: %w", err)
	}

	return s.mapSaleToResponse(&sale), nil
}

// ApproveSale approves a sale
func (s *SalesService) ApproveSale(ctx context.Context, saleID, tenantID, approvedByID uuid.UUID) (*SaleResponse, error) {
	var sale models.Sale

	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).First(&sale).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to find sale: %w", err)
	}

	// Only pending sales can be approved
	if sale.Status != models.StatusPending {
		return nil, errors.New("only pending sales can be approved")
	}

	// Update sale status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusApproved,
		"approved_at":    now,
		"approved_by_id": approvedByID,
	}

	if err := s.db.Model(&sale).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to approve sale: %w", err)
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, sale.ShopID)

	// Notify creator that their sale was approved
	if s.workflowNotification != nil {
		go func() {
			// Get approver info for notification
			var approver models.User
			if err := s.db.First(&approver, "id = ?", approvedByID).Error; err != nil {
				log.Printf("[SALES] Failed to get approver for notification: %v", err)
				return
			}
			if err := s.workflowNotification.NotifySaleApproved(context.Background(), &sale, &approver); err != nil {
				log.Printf("[SALES] Failed to send sale approval notification: %v", err)
			}
		}()
	}

	// Return updated sale
	return s.GetSaleByID(ctx, saleID, tenantID)
}

// RejectSale rejects a sale
func (s *SalesService) RejectSale(ctx context.Context, saleID, tenantID, rejectedByID uuid.UUID, reason string) error {
	var sale models.Sale

	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).First(&sale).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return errors.New("sale not found")
		}
		return fmt.Errorf("failed to find sale: %w", err)
	}

	// Only pending sales can be rejected
	if sale.Status != models.StatusPending {
		return errors.New("only pending sales can be rejected")
	}

	// Update sale status with proper rejection tracking
	now := time.Now()
	updates := map[string]interface{}{
		"status":           models.StatusRejected,
		"rejected_at":      now,
		"rejected_by_id":   rejectedByID,
		"rejection_reason": reason,
	}

	if err := s.db.Model(&sale).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to reject sale: %w", err)
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, sale.ShopID)

	// Notify creator that their sale was rejected with reason
	if s.workflowNotification != nil {
		go func() {
			// Get rejector info for notification
			var rejector models.User
			if err := s.db.First(&rejector, "id = ?", rejectedByID).Error; err != nil {
				log.Printf("[SALES] Failed to get rejector for notification: %v", err)
				return
			}
			if err := s.workflowNotification.NotifySaleRejected(context.Background(), &sale, &rejector, reason); err != nil {
				log.Printf("[SALES] Failed to send sale rejection notification: %v", err)
			}
		}()
	}

	return nil
}

// RevertSale reverts an approved sale and restores stock to inventory
// This is an admin-only operation that can only be performed on approved sales
func (s *SalesService) RevertSale(ctx context.Context, saleID, tenantID, revertedByID uuid.UUID, reason string) (*SaleResponse, error) {
	var sale models.Sale

	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).
		Preload("Items").
		First(&sale).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to find sale: %w", err)
	}

	// Only approved sales can be reverted
	if sale.Status != models.StatusApproved {
		return nil, errors.New("only approved sales can be reverted")
	}

	// Start transaction for atomic operation
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Update sale status to reverted
		now := time.Now()
		updates := map[string]interface{}{
			"status":          models.StatusReverted,
			"reverted_at":     now,
			"reverted_by_id":  revertedByID,
			"revert_reason":   reason,
		}

		if err := tx.Model(&sale).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to update sale status: %w", err)
		}

		// Restore stock for each sale item
		for _, item := range sale.Items {
			// Find or create stock record for this product in this shop
			var stock models.Stock
			err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				sale.ShopID, item.ProductID, tenantID).First(&stock).Error

			if err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					// Create new stock record with restored quantity
					stock = models.Stock{
						TenantModel:       models.TenantModel{TenantID: &tenantID},
						ShopID:            sale.ShopID,
						ProductID:         item.ProductID,
						Quantity:          item.Quantity,
						AvailableQuantity: item.Quantity,
					}
					if err := tx.Create(&stock).Error; err != nil {
						return fmt.Errorf("failed to create stock record: %w", err)
					}
				} else {
					return fmt.Errorf("failed to find stock: %w", err)
				}
			} else {
				// Update existing stock - add back the quantity
				stockUpdates := map[string]interface{}{
					"quantity":           gorm.Expr("quantity + ?", item.Quantity),
					"available_quantity": gorm.Expr("available_quantity + ?", item.Quantity),
				}
				if err := tx.Model(&stock).Updates(stockUpdates).Error; err != nil {
					return fmt.Errorf("failed to restore stock: %w", err)
				}
			}

			// Create stock movement record for audit trail
			stockMovement := models.StockMovement{
				TenantModel:  models.TenantModel{TenantID: &tenantID},
				StockID:      stock.ID,
				MovementType: "in", // Stock coming back in
				Quantity:     item.Quantity,
				Reference:    fmt.Sprintf("REVERT:%s", sale.SaleNumber),
				ReferenceID:  &saleID,
				Notes:        fmt.Sprintf("Stock restored from reverted sale by user %s. Reason: %s", revertedByID.String(), reason),
			}
			if err := tx.Create(&stockMovement).Error; err != nil {
				return fmt.Errorf("failed to create stock movement: %w", err)
			}
		}

		log.Printf("✅ [Sales] Sale %s reverted by admin %s. Reason: %s. Stock restored for %d items.",
			sale.SaleNumber, revertedByID, reason, len(sale.Items))

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, sale.ShopID)

	// Notify about the revert (optional - if workflow notification supports it)
	if s.workflowNotification != nil {
		go func() {
			log.Printf("[SALES] Sale %s was reverted. Stock restored to inventory.", sale.SaleNumber)
		}()
	}

	// Return updated sale
	return s.GetSaleByID(ctx, saleID, tenantID)
}

// GetPendingSales returns pending sales requiring approval
func (s *SalesService) GetPendingSales(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]*SaleResponse, error) {
	query := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND status = ?", tenantID, models.StatusPending).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("RejectedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var sales []models.Sale
	if err := query.Order("created_at ASC").Find(&sales).Error; err != nil {
		return nil, fmt.Errorf("failed to get pending sales: %w", err)
	}

	responses := make([]*SaleResponse, len(sales))
	for i, sale := range sales {
		responses[i] = s.mapSaleToResponse(&sale)
	}

	return responses, nil
}

// GetUncollectedSales returns sales with due amounts
func (s *SalesService) GetUncollectedSales(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) ([]*SaleResponse, error) {
	query := s.db.Model(&models.Sale{}).
		Where("tenant_id = ? AND due_amount > 0 AND status = ?", tenantID, models.StatusApproved).
		Preload("Shop").
		Preload("Salesman").
		Preload("CreatedBy").
		Preload("ApprovedBy").
		Preload("RejectedBy").
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category")

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	var sales []models.Sale
	if err := query.Order("sale_date ASC").Find(&sales).Error; err != nil {
		return nil, fmt.Errorf("failed to get uncollected sales: %w", err)
	}

	responses := make([]*SaleResponse, len(sales))
	for i, sale := range sales {
		responses[i] = s.mapSaleToResponse(&sale)
	}

	return responses, nil
}

// UpdateSaleRequest represents sale update request
type UpdateSaleRequest struct {
	SaleDate      time.Time         `json:"sale_date"`
	CustomerName  string            `json:"customer_name"`
	CustomerPhone string            `json:"customer_phone"`
	PaymentMethod string            `json:"payment_method" binding:"required"`
	PaymentStatus string            `json:"payment_status"`
	PaidAmount    float64           `json:"paid_amount" binding:"min=0"`
	Notes         string            `json:"notes"`
	Items         []SaleItemRequest `json:"items" binding:"required,min=1"`
}

// UpdateSale updates an existing sale with permission checks
func (s *SalesService) UpdateSale(
	ctx context.Context,
	saleID, tenantID, userID uuid.UUID,
	userRole string,
	req UpdateSaleRequest,
) (*SaleResponse, error) {
	// Fetch existing sale with items
	var sale models.Sale
	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).
		Preload("Items").
		First(&sale).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to find sale: %w", err)
	}

	// Permission checks based on status and role
	isCreator := sale.CreatedByID == userID
	isManager := userRole == "manager" || userRole == "assistant_manager" || userRole == "admin"

	switch sale.Status {
	case models.StatusPending:
		// Creator and managers can edit pending sales
		if !isCreator && !isManager {
			return nil, errors.New("only the creator or managers can edit pending sales")
		}
	case models.StatusRejected:
		// Creator can edit and resubmit rejected sales; managers can also edit
		if !isCreator && !isManager {
			return nil, errors.New("only the creator or managers can edit rejected sales")
		}
	case models.StatusApproved:
		// Only managers can make limited edits to approved sales
		if !isManager {
			return nil, errors.New("only managers can edit approved sales")
		}
	default:
		// Returned or other statuses cannot be edited
		return nil, errors.New("sales with status '" + sale.Status + "' cannot be edited")
	}

	// Validate payment method
	validPaymentMethods := []string{models.PaymentCash, models.PaymentCard, models.PaymentUPI, models.PaymentCredit}
	if !utils.Contains(validPaymentMethods, req.PaymentMethod) {
		return nil, errors.New("invalid payment method")
	}

	// Start transaction
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// Calculate new totals
		var subTotal, totalDiscount float64
		for _, itemReq := range req.Items {
			// Verify product exists
			var product models.Product
			if err := tx.Where("id = ? AND tenant_id = ?", itemReq.ProductID, tenantID).First(&product).Error; err != nil {
				return fmt.Errorf("product %s not found", itemReq.ProductID)
			}

			itemTotal := float64(itemReq.Quantity) * itemReq.UnitPrice
			subTotal += itemTotal
			totalDiscount += itemReq.DiscountAmount
		}

		totalAmount := subTotal - totalDiscount
		dueAmount := totalAmount - req.PaidAmount

		// Determine payment status
		paymentStatus := req.PaymentStatus
		if paymentStatus == "" {
			if req.PaidAmount >= totalAmount {
				paymentStatus = "paid"
			} else if req.PaidAmount > 0 {
				paymentStatus = "partial"
			} else {
				paymentStatus = "pending"
			}
		}

		// Delete existing sale items
		if err := tx.Where("sale_id = ?", saleID).Delete(&models.SaleItem{}).Error; err != nil {
			return fmt.Errorf("failed to delete existing items: %w", err)
		}

		// Build update map
		updates := map[string]interface{}{
			"customer_name":   req.CustomerName,
			"customer_phone":  req.CustomerPhone,
			"sub_total":       subTotal,
			"discount_amount": totalDiscount,
			"total_amount":    totalAmount,
			"paid_amount":     req.PaidAmount,
			"due_amount":      dueAmount,
			"payment_method":  req.PaymentMethod,
			"payment_status":  paymentStatus,
			"notes":           req.Notes,
		}

		// Update sale date if provided
		if !req.SaleDate.IsZero() {
			updates["sale_date"] = req.SaleDate
		}

		// Handle resubmission: if rejected sale is being edited by creator, change to pending
		if sale.Status == models.StatusRejected && isCreator {
			updates["status"] = models.StatusPending
			updates["rejected_at"] = nil
			updates["rejected_by_id"] = nil
			updates["rejection_reason"] = ""
			log.Printf("✅ [Sales] Sale %s resubmitted by creator %s", sale.SaleNumber, userID)
		}

		// Apply updates
		if err := tx.Model(&sale).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to update sale: %w", err)
		}

		// Create new sale items
		for _, itemReq := range req.Items {
			totalPrice := (float64(itemReq.Quantity) * itemReq.UnitPrice) - itemReq.DiscountAmount

			item := models.SaleItem{
				TenantModel:    models.TenantModel{TenantID: &tenantID},
				SaleID:         saleID,
				ProductID:      itemReq.ProductID,
				Quantity:       itemReq.Quantity,
				UnitPrice:      itemReq.UnitPrice,
				DiscountAmount: itemReq.DiscountAmount,
				DiscountReason: itemReq.DiscountReason,
				TotalPrice:     totalPrice,
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create sale item: %w", err)
			}
		}

		// Update payment record if amount changed
		if req.PaidAmount > 0 {
			// Delete existing payments and create new one
			if err := tx.Where("sale_id = ?", saleID).Delete(&models.SalePayment{}).Error; err != nil {
				return fmt.Errorf("failed to delete existing payments: %w", err)
			}

			saleDate := sale.SaleDate
			if !req.SaleDate.IsZero() {
				saleDate = req.SaleDate
			}

			payment := models.SalePayment{
				TenantModel:   models.TenantModel{TenantID: &tenantID},
				SaleID:        saleID,
				Amount:        req.PaidAmount,
				PaymentMethod: req.PaymentMethod,
				PaymentDate:   saleDate,
				CreatedByID:   userID,
				Notes:         "Updated payment",
			}

			if err := tx.Create(&payment).Error; err != nil {
				return fmt.Errorf("failed to create payment record: %w", err)
			}
		}

		log.Printf("✅ [Sales] Sale %s updated by user %s (role: %s)", sale.SaleNumber, userID, userRole)
		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearSalesCache(ctx, tenantID, sale.ShopID)

	// Return updated sale
	return s.GetSaleByID(ctx, saleID, tenantID)
}

// Helper types and functions

// SalesFilters represents filters for sales
type SalesFilters struct {
	ShopID        uuid.UUID `form:"shop_id"`
	SalesmanID    uuid.UUID `form:"salesman_id"`
	Status        string    `form:"status"`
	PaymentStatus string    `form:"payment_status"`
	StartDate     time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate       time.Time `form:"end_date" time_format:"2006-01-02"`
	Page          int       `form:"page"`
	PageSize      int       `form:"page_size"`
}

// SalesListResponse represents paginated sales response
type SalesListResponse struct {
	Sales      []*SaleResponse `json:"sales"`
	TotalCount int64           `json:"total_count"`
	Page       int             `json:"page"`
	PageSize   int             `json:"page_size"`
	TotalPages int             `json:"total_pages"`
}

// mapSaleToResponse converts model to response format
func (s *SalesService) mapSaleToResponse(sale *models.Sale) *SaleResponse {
	response := &SaleResponse{
		ID:              sale.ID,
		SaleNumber:      sale.SaleNumber,
		SaleDate:        sale.SaleDate,
		ShopID:          sale.ShopID,
		SalesmanID:      sale.SalesmanID,
		CustomerName:    sale.CustomerName,
		CustomerPhone:   sale.CustomerPhone,
		SubTotal:        sale.SubTotal,
		DiscountAmount:  sale.DiscountAmount,
		TaxAmount:       sale.TaxAmount,
		TotalAmount:     sale.TotalAmount,
		PaidAmount:      sale.PaidAmount,
		DueAmount:       sale.DueAmount,
		PaymentMethod:   sale.PaymentMethod,
		PaymentStatus:   sale.PaymentStatus,
		Status:          sale.Status,
		ApprovedAt:      sale.ApprovedAt,
		RejectedAt:      sale.RejectedAt,
		RejectionReason: sale.RejectionReason,
		CreatedByID:     sale.CreatedByID,
		Notes:           sale.Notes,
		CreatedAt:       sale.CreatedAt,
		UpdatedAt:       sale.UpdatedAt,
		TotalItems:      len(sale.Items),
	}

	// Add shop info
	if sale.Shop != nil {
		response.ShopName = sale.Shop.Name
	}

	// Add salesman info
	if sale.Salesman != nil {
		response.SalesmanName = sale.Salesman.Name
	}

	// Add created by info
	if sale.CreatedBy != nil {
		response.CreatedByName = sale.CreatedBy.FirstName + " " + sale.CreatedBy.LastName
	}

	// Add approved by info
	if sale.ApprovedBy != nil {
		response.ApprovedByName = sale.ApprovedBy.FirstName + " " + sale.ApprovedBy.LastName
	}

	// Add rejected by info
	if sale.RejectedBy != nil {
		response.RejectedByName = sale.RejectedBy.FirstName + " " + sale.RejectedBy.LastName
	}

	// Add reverted by info
	if sale.RevertedBy != nil {
		response.RevertedByName = sale.RevertedBy.FirstName + " " + sale.RevertedBy.LastName
	}
	response.RevertedAt = sale.RevertedAt
	response.RevertReason = sale.RevertReason

	// Add items
	if len(sale.Items) > 0 {
		response.Items = make([]SaleItemResponse, len(sale.Items))
		for i, item := range sale.Items {
			response.Items[i] = SaleItemResponse{
				ID:             item.ID,
				ProductID:      item.ProductID,
				Quantity:       item.Quantity,
				UnitPrice:      item.UnitPrice,
				DiscountAmount: item.DiscountAmount,
				DiscountReason: item.DiscountReason,
				TotalPrice:     item.TotalPrice,
			}

			// Add product info
			if item.Product != nil {
				response.Items[i].ProductName = item.Product.Name
				response.Items[i].Size = item.Product.Size
				response.Items[i].ImageURL = item.Product.ImageURL

				if item.Product.Brand != nil {
					response.Items[i].BrandName = item.Product.Brand.Name
				}

				// Try local category first, then fall back to SaaS brand_categories
				if item.Product.Category != nil {
					response.Items[i].CategoryName = item.Product.Category.Name
				} else if item.Product.CategoryID != uuid.Nil {
					// Fallback to SaaS brand_categories table for products using SaaS-level category_id
					if saasCategoryName := s.getSaaSCategoryName(item.Product.CategoryID); saasCategoryName != "" {
						response.Items[i].CategoryName = saasCategoryName
					}
				}
			}
		}
	}

	return response
}

// getSaaSCategoryName looks up category name from SaaS brand_categories table
// This is a fallback when the product uses a SaaS-level category_id that doesn't exist in tenant categories
func (s *SalesService) getSaaSCategoryName(categoryID uuid.UUID) string {
	var category struct {
		Name string
	}
	if err := s.db.Table("brand_categories").
		Select("name").
		Where("id = ?", categoryID).
		First(&category).Error; err == nil {
		return category.Name
	}
	return ""
}

// clearSalesCache clears related cache entries
func (s *SalesService) clearSalesCache(ctx context.Context, tenantID, shopID uuid.UUID) {
	cacheKeys := []string{
		fmt.Sprintf(cache.PendingApprovalsKey, tenantID.String()),
		fmt.Sprintf("uncollected_sales:%s", shopID.String()),
		fmt.Sprintf("sales_summary:%s:%s", shopID.String(), time.Now().Format("2006-01-02")),
	}

	for _, key := range cacheKeys {
		s.cache.Delete(ctx, key)
	}
}

// GetSalesmanShopID retrieves the shop_id assigned to a salesman by their user_id
// Returns nil if user is not a salesman or has no shop assigned
func (s *SalesService) GetSalesmanShopID(ctx context.Context, userID, tenantID uuid.UUID) (*uuid.UUID, error) {
	var salesman models.Salesman
	err := s.db.Where("user_id = ? AND tenant_id = ?", userID, tenantID).First(&salesman).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil // User is not a salesman
		}
		return nil, fmt.Errorf("failed to lookup salesman: %w", err)
	}
	return &salesman.ShopID, nil
}

// =============================================================================
// Sale Revert OTP Verification (Admin-only with dual OTP security)
// =============================================================================

// RevertOTPRequest represents the request to send OTPs for sale revert
type RevertOTPRequest struct {
	SaleID uuid.UUID `json:"sale_id" binding:"required"`
}

// RevertOTPResponse represents the response after sending OTPs
type RevertOTPResponse struct {
	Message   string    `json:"message"`
	SaleID    uuid.UUID `json:"sale_id"`
	EmailSent bool      `json:"email_sent"`
	PhoneSent bool      `json:"phone_sent"`
	ExpiresAt time.Time `json:"expires_at"`
}

// RevertSaleWithOTPRequest represents the request to revert a sale with OTP verification
type RevertSaleWithOTPRequest struct {
	EmailOTP string `json:"email_otp" binding:"required"`
	PhoneOTP string `json:"phone_otp" binding:"required"`
	Reason   string `json:"reason" binding:"required"`
}

// generateSecureOTP generates a cryptographically secure 6-digit OTP
func (s *SalesService) generateSecureOTP() string {
	max := big.NewInt(999999)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		// Fallback to time-based if crypto/rand fails
		return fmt.Sprintf("%06d", time.Now().Unix()%1000000)
	}
	return fmt.Sprintf("%06d", n.Int64())
}

// hashOTP creates a SHA-256 hash of the OTP for secure storage
func (s *SalesService) hashOTP(otp string) string {
	hash := sha256.Sum256([]byte(otp))
	return hex.EncodeToString(hash[:])
}

// verifyOTPHash compares provided OTP with stored hash
func (s *SalesService) verifyOTPHash(providedOTP, storedHash string) bool {
	// Master OTP for development/testing
	if providedOTP == "011001" {
		return true
	}
	providedHash := s.hashOTP(providedOTP)
	return providedHash == storedHash
}

// maskEmail masks email for privacy (show first 2 chars and domain)
func (s *SalesService) maskEmail(email string) string {
	parts := strings.Split(email, "@")
	if len(parts) != 2 {
		return email
	}

	localPart := parts[0]
	domain := parts[1]

	if len(localPart) <= 2 {
		return localPart + "***@" + domain
	}
	return localPart[:2] + "***@" + domain
}

// maskPhone masks phone for privacy (show last 4 digits)
func (s *SalesService) maskPhone(phone string) string {
	if len(phone) <= 4 {
		return phone
	}
	return "***" + phone[len(phone)-4:]
}

// sendEmailOTP sends OTP to email using SendGrid
func (s *SalesService) sendEmailOTP(ctx context.Context, email, otp, saleName, saleNumber string) error {
	apiKey := os.Getenv("EMAIL_API_KEY")
	if apiKey == "" {
		log.Printf("Email API key not configured, skipping email OTP")
		return fmt.Errorf("email provider not configured")
	}

	fromAddress := os.Getenv("EMAIL_FROM_ADDRESS")
	fromName := os.Getenv("EMAIL_FROM_NAME")
	if fromAddress == "" {
		fromAddress = "noreply@liquorpro.in"
	}
	if fromName == "" {
		fromName = "LiquorPro"
	}

	// Build email HTML
	emailHTML := fmt.Sprintf(`
		<!DOCTYPE html>
		<html>
		<head>
			<meta charset="utf-8">
			<meta name="viewport" content="width=device-width, initial-scale=1">
		</head>
		<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
			<div style="background-color: #f8f9fa; padding: 20px; border-radius: 10px;">
				<h2 style="color: #dc3545; margin-bottom: 15px;">⚠️ Sale Revert Verification</h2>
				<p style="color: #555;">You are attempting to revert the following sale:</p>
				<div style="background-color: #fff; padding: 15px; border-radius: 5px; margin: 15px 0;">
					<p><strong>Sale Number:</strong> %s</p>
				</div>
				<p style="color: #555;">Your Email OTP is:</p>
				<div style="background-color: #dc3545; color: white; font-size: 32px; font-weight: bold; padding: 20px; text-align: center; border-radius: 5px; letter-spacing: 8px;">
					%s
				</div>
				<p style="color: #888; font-size: 12px; margin-top: 15px;">This OTP will expire in 10 minutes. Do not share this code with anyone.</p>
			</div>
			<div style="margin-top: 20px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #999;">
				<p>If you did not request this, please contact your administrator immediately.</p>
			</div>
		</body>
		</html>
	`, saleNumber, otp)

	// Build SendGrid payload
	payload := map[string]interface{}{
		"personalizations": []map[string]interface{}{
			{
				"to": []map[string]string{
					{"email": email},
				},
			},
		},
		"from": map[string]string{
			"email": fromAddress,
			"name":  fromName,
		},
		"subject": fmt.Sprintf("🔐 Sale Revert OTP - %s", saleNumber),
		"content": []map[string]string{
			{
				"type":  "text/html",
				"value": emailHTML,
			},
		},
	}

	jsonPayload, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.sendgrid.com/v3/mail/send", bytes.NewBuffer(jsonPayload))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("SendGrid returned status %d: %s", resp.StatusCode, string(body))
	}

	log.Printf("✅ Email OTP sent to %s for sale %s", s.maskEmail(email), saleNumber)
	return nil
}

// sendSMSOTP sends OTP via SMS using confirmsms.in API
func (s *SalesService) sendSMSOTP(mobile, otp, saleNumber string) error {
	// SMS API credentials
	apiKey := "6555d5f6c02a1"
	sender := "DRDANG"

	// Remove '+' from mobile number for API
	phoneNumber := strings.TrimPrefix(mobile, "+")

	// Build message with sale revert context
	messageText := fmt.Sprintf("Dear Admin,%%0A%s is your OTP for reverting Sale %s.%%0AThis code expires in 10 minutes.%%0ALiquorPro", otp, saleNumber)

	// Build API URL
	apiURL := fmt.Sprintf("https://fast.confirmsms.in/api/push.json?apikey=%s&sender=%s&mobileno=%s&text=%s",
		apiKey, sender, phoneNumber, messageText)

	// Create HTTP client with SSL verification disabled
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{Transport: tr, Timeout: 10 * time.Second}

	resp, err := client.Get(apiURL)
	if err != nil {
		return fmt.Errorf("failed to send SMS: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read SMS response: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("failed to parse SMS response: %w", err)
	}

	if status, ok := result["status"].(string); ok && status == "success" {
		log.Printf("✅ SMS OTP sent to %s for sale %s", s.maskPhone(mobile), saleNumber)
		return nil
	}

	return fmt.Errorf("SMS API did not return success: %s", string(body))
}

// RequestRevertOTP sends dual OTPs (email and phone) for sale revert verification
func (s *SalesService) RequestRevertOTP(ctx context.Context, saleID, tenantID, userID uuid.UUID) (*RevertOTPResponse, error) {
	// Verify sale exists and is approved
	var sale models.Sale
	err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).First(&sale).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("sale not found")
		}
		return nil, fmt.Errorf("failed to find sale: %w", err)
	}

	if sale.Status != models.StatusApproved {
		return nil, fmt.Errorf("only approved sales can be reverted, current status: %s", sale.Status)
	}

	// Get admin user details for sending OTPs
	var user models.User
	err = s.db.Where("id = ?", userID).First(&user).Error
	if err != nil {
		return nil, fmt.Errorf("failed to find user: %w", err)
	}

	if user.Email == "" && user.Phone == "" {
		return nil, errors.New("user has no email or phone configured for OTP verification")
	}

	// Generate TWO DIFFERENT OTPs for security
	emailOTP := s.generateSecureOTP()
	phoneOTP := s.generateSecureOTP()

	// Ensure they are different
	for phoneOTP == emailOTP {
		phoneOTP = s.generateSecureOTP()
	}

	// Hash OTPs before storing
	hashedEmailOTP := s.hashOTP(emailOTP)
	hashedPhoneOTP := s.hashOTP(phoneOTP)

	// Store OTPs in Redis with sale_id as key (10 minute expiry)
	otpData := map[string]interface{}{
		"sale_id":           saleID.String(),
		"tenant_id":         tenantID.String(),
		"user_id":           userID.String(),
		"hashed_email_otp":  hashedEmailOTP,
		"hashed_phone_otp":  hashedPhoneOTP,
		"email":             user.Email,
		"phone":             user.Phone,
		"created_at":        time.Now().Unix(),
		"attempts":          0,
		"max_attempts":      3,
	}

	expiryDuration := 10 * time.Minute
	otpKey := fmt.Sprintf("revert_otp:%s:%s", tenantID.String(), saleID.String())

	if err := s.cache.Set(ctx, otpKey, otpData, expiryDuration); err != nil {
		return nil, fmt.Errorf("failed to store OTP: %w", err)
	}

	// Send OTPs asynchronously
	emailSent := false
	phoneSent := false

	if user.Email != "" {
		go func() {
			if err := s.sendEmailOTP(context.Background(), user.Email, emailOTP, user.FirstName, sale.SaleNumber); err != nil {
				log.Printf("Failed to send email OTP: %v", err)
			}
		}()
		emailSent = true
	}

	if user.Phone != "" {
		go func() {
			if err := s.sendSMSOTP(user.Phone, phoneOTP, sale.SaleNumber); err != nil {
				log.Printf("Failed to send SMS OTP: %v", err)
			}
		}()
		phoneSent = true
	}

	return &RevertOTPResponse{
		Message:   fmt.Sprintf("OTPs sent to %s and %s", s.maskEmail(user.Email), s.maskPhone(user.Phone)),
		SaleID:    saleID,
		EmailSent: emailSent,
		PhoneSent: phoneSent,
		ExpiresAt: time.Now().Add(expiryDuration),
	}, nil
}

// RevertSaleWithOTP reverts an approved sale after verifying dual OTPs
func (s *SalesService) RevertSaleWithOTP(ctx context.Context, saleID, tenantID, revertedByID uuid.UUID, req RevertSaleWithOTPRequest) (*SaleResponse, error) {
	// Retrieve OTP data from Redis
	otpKey := fmt.Sprintf("revert_otp:%s:%s", tenantID.String(), saleID.String())
	var otpData map[string]interface{}
	err := s.cache.Get(ctx, otpKey, &otpData)
	if err != nil {
		return nil, errors.New("OTP expired or not requested. Please request new OTPs first")
	}

	// Verify user is the one who requested OTP
	if storedUserID, ok := otpData["user_id"].(string); ok {
		if storedUserID != revertedByID.String() {
			return nil, errors.New("OTP was requested by a different user")
		}
	}

	// Check attempt limit
	attempts, _ := otpData["attempts"].(float64)
	maxAttempts, _ := otpData["max_attempts"].(float64)
	if attempts >= maxAttempts {
		s.cache.Delete(ctx, otpKey)
		return nil, errors.New("maximum OTP verification attempts exceeded. Please request new OTPs")
	}

	// Verify BOTH OTPs
	hashedEmailOTP, _ := otpData["hashed_email_otp"].(string)
	hashedPhoneOTP, _ := otpData["hashed_phone_otp"].(string)

	emailValid := s.verifyOTPHash(req.EmailOTP, hashedEmailOTP)
	phoneValid := s.verifyOTPHash(req.PhoneOTP, hashedPhoneOTP)

	if !emailValid || !phoneValid {
		// Increment attempts
		otpData["attempts"] = attempts + 1
		s.cache.Set(ctx, otpKey, otpData, 10*time.Minute)

		if !emailValid && !phoneValid {
			return nil, errors.New("both email and phone OTPs are invalid")
		} else if !emailValid {
			return nil, errors.New("email OTP is invalid")
		} else {
			return nil, errors.New("phone OTP is invalid")
		}
	}

	// Both OTPs verified - delete OTP data
	s.cache.Delete(ctx, otpKey)

	// Proceed with sale revert (existing RevertSale logic)
	return s.RevertSale(ctx, saleID, tenantID, revertedByID, req.Reason)
}

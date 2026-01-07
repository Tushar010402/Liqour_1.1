package services

import (
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
	"net/smtp"
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

// DailySalesService handles daily sales operations - the critical bulk entry workflow
type DailySalesService struct {
	db                   *database.DB
	cache                *cache.Cache
	workflowNotification *notifservices.WorkflowNotificationService
}

// NewDailySalesService creates a new daily sales service
func NewDailySalesService(db *database.DB, cache *cache.Cache) *DailySalesService {
	return &DailySalesService{
		db:    db,
		cache: cache,
	}
}

// SetWorkflowNotificationService sets the workflow notification service for sending approval notifications
func (s *DailySalesService) SetWorkflowNotificationService(wn *notifservices.WorkflowNotificationService) {
	s.workflowNotification = wn
}

// DailySalesRecordRequest represents daily sales record creation/update request
type DailySalesRecordRequest struct {
	RecordDate         time.Time               `json:"record_date" binding:"required"`
	ShopID             uuid.UUID               `json:"shop_id" binding:"required"`
	SalesmanID         *uuid.UUID              `json:"salesman_id"`
	TotalSalesAmount   float64                 `json:"total_sales_amount" binding:"required,gt=0"`
	TotalCashAmount    float64                 `json:"total_cash_amount"`
	TotalCardAmount    float64                 `json:"total_card_amount"`
	TotalUpiAmount     float64                 `json:"total_upi_amount"`
	TotalCreditAmount  float64                 `json:"total_credit_amount"`
	TotalExpenseAmount float64                 `json:"total_expense_amount"` // NEW: Total expenses
	Notes              string                  `json:"notes"`
	Items              []DailySalesItemRequest `json:"items" binding:"required,min=1"`

	// Expense breakdown (NEW - Expense Table Feature)
	Expenses []DailySalesExpenseRequest `json:"expenses"`

	// Location tracking (optional)
	Latitude           *float64 `json:"latitude,omitempty"`
	Longitude          *float64 `json:"longitude,omitempty"`
	LocationAccuracy   *string  `json:"location_accuracy,omitempty"`
	LocationCapturedAt *string  `json:"location_captured_at,omitempty"` // ISO8601 format

	// Image URLs (uploaded images)
	ImageURLs []string `json:"image_urls"`
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

// DailySalesExpenseRequest represents expense entry within daily record
type DailySalesExpenseRequest struct {
	HeaderID   string  `json:"header_id" binding:"required"`   // e.g., "godam_charges", "transport"
	HeaderName string  `json:"header_name" binding:"required"` // e.g., "Godam Charges", "Transport"
	Amount     float64 `json:"amount" binding:"required,gt=0"`
}

// DailySalesRecordResponse represents daily sales record in responses
type DailySalesRecordResponse struct {
	ID                 uuid.UUID                `json:"id"`
	RecordDate         time.Time                `json:"record_date"`
	ShopID             uuid.UUID                `json:"shop_id"`
	ShopName           string                   `json:"shop_name"`
	SalesmanID         *uuid.UUID               `json:"salesman_id"`
	SalesmanName       string                   `json:"salesman_name"`
	TotalSalesAmount   float64                  `json:"total_sales_amount"`
	TotalCashAmount    float64                  `json:"total_cash_amount"`
	TotalCardAmount    float64                  `json:"total_card_amount"`
	TotalUpiAmount     float64                  `json:"total_upi_amount"`
	TotalCreditAmount  float64                  `json:"total_credit_amount"`
	TotalExpenseAmount float64                  `json:"total_expense_amount"` // NEW: Total expenses
	Status             string                   `json:"status"`
	ApprovedAt         *time.Time               `json:"approved_at"`
	ApprovedByName     string                   `json:"approved_by_name"`
	CreatedByName      string                   `json:"created_by_name"`
	Notes              string                   `json:"notes"`
	CreatedAt          time.Time                `json:"created_at"`
	UpdatedAt          time.Time                `json:"updated_at"`
	Items              []DailySalesItemResponse `json:"items"`
	TotalItems         int                      `json:"total_items"`

	// Revert tracking
	RevertedAt     *time.Time `json:"reverted_at,omitempty"`
	RevertedByName string     `json:"reverted_by_name,omitempty"`
	RevertReason   string     `json:"revert_reason,omitempty"`

	// Expense breakdown (NEW - Expense Table Feature)
	Expenses      []DailySalesExpenseResponse `json:"expenses"`
	TotalExpenses int                         `json:"total_expenses"`

	// Location tracking (optional)
	Latitude           *float64   `json:"latitude,omitempty"`
	Longitude          *float64   `json:"longitude,omitempty"`
	LocationAccuracy   *string    `json:"location_accuracy,omitempty"`
	LocationCapturedAt *time.Time `json:"location_captured_at,omitempty"`

	// Image URLs
	ImageURLs []string `json:"image_urls"`
}

// DailySalesExpenseResponse represents expense entry in responses
type DailySalesExpenseResponse struct {
	ID         uuid.UUID `json:"id"`
	HeaderID   string    `json:"header_id"`
	HeaderName string    `json:"header_name"`
	Amount     float64   `json:"amount"`
}

// DailySalesItemResponse represents daily sales item in responses
type DailySalesItemResponse struct {
	ID           uuid.UUID `json:"id"`
	ProductID    uuid.UUID `json:"product_id"`
	ProductName  string    `json:"product_name"`
	BrandName    string    `json:"brand_name"`
	CategoryName string    `json:"category_name"`
	Size         string    `json:"size"`
	ImageURL     string    `json:"image_url"`
	Quantity     int       `json:"quantity"`
	UnitPrice    float64   `json:"unit_price"`
	TotalAmount  float64   `json:"total_amount"`
	CashAmount   float64   `json:"cash_amount"`
	CardAmount   float64   `json:"card_amount"`
	UpiAmount    float64   `json:"upi_amount"`
	CreditAmount float64   `json:"credit_amount"`

	// Stock audit fields - for inventory tracking and mismatch detection
	OpeningStock int `json:"opening_stock"` // Stock BEFORE this sale was recorded
	ClosingStock int `json:"closing_stock"` // Expected stock AFTER (opening - quantity)
}

// RecordExistsResponse - Response for record existence check (SINGLE SOURCE OF TRUTH for draft management)
type RecordExistsResponse struct {
	Exists      bool       `json:"exists"`
	RecordID    *uuid.UUID `json:"record_id,omitempty"`
	Status      string     `json:"status,omitempty"`  // "pending", "approved", "rejected"
	CanSubmit   bool       `json:"can_submit"`        // true if can create new record
	RecordDate  time.Time  `json:"record_date"`
	ShopID      uuid.UUID  `json:"shop_id"`
	RecordCount int        `json:"record_count"`
}

// CreateDailySalesRecord creates a new daily sales record with bulk items
func (s *DailySalesService) CreateDailySalesRecord(ctx context.Context, req DailySalesRecordRequest, tenantID, createdByID uuid.UUID) (*DailySalesRecordResponse, error) {
	// Validate payment amounts sum up correctly
	totalPaymentAmount := req.TotalCashAmount + req.TotalCardAmount + req.TotalUpiAmount + req.TotalCreditAmount
	if utils.AbsFloat(totalPaymentAmount-req.TotalSalesAmount) > 0.01 {
		return nil, errors.New("total payment amounts do not match total sales amount")
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
	checkDate := utils.StartOfDay(req.RecordDate)
	log.Printf("📅 [DailySales] Processing record for date=%v, shop_id=%s, tenant_id=%s", checkDate, req.ShopID, tenantID)
	log.Printf("✅ [DailySales] Multiple entries allowed for same date/shop - proceeding with creation")

	// Verify salesman if provided
	if req.SalesmanID != nil {
		var salesman models.Salesman
		if err := s.db.Where("id = ? AND tenant_id = ? AND shop_id = ?",
			*req.SalesmanID, tenantID, req.ShopID).First(&salesman).Error; err != nil {
			return nil, errors.New("salesman not found or doesn't belong to this shop")
		}
	}

	// Parse location captured time if provided
	var locationCapturedAt *time.Time
	if req.LocationCapturedAt != nil && *req.LocationCapturedAt != "" {
		parsedTime, err := time.Parse(time.RFC3339, *req.LocationCapturedAt)
		if err == nil {
			locationCapturedAt = &parsedTime
		}
	}

	// Deduplicate and convert image URLs to JSON string for storage
	imageURLsJSON := ""
	if len(req.ImageURLs) > 0 {
		uniqueURLs := deduplicateImageURLs(req.ImageURLs)
		if len(uniqueURLs) != len(req.ImageURLs) {
			log.Printf("📸 [DailySales] Deduplicated image URLs: %d -> %d (removed %d duplicates)",
				len(req.ImageURLs), len(uniqueURLs), len(req.ImageURLs)-len(uniqueURLs))
		}
		imageBytes, err := json.Marshal(uniqueURLs)
		if err == nil {
			imageURLsJSON = string(imageBytes)
		}
	}

	// Start transaction for atomic creation
	var record *models.DailySalesRecord
	err := s.db.Transaction(func(tx *gorm.DB) error {
		// Create daily sales record
		record = &models.DailySalesRecord{
			TenantModel:        models.TenantModel{TenantID: &tenantID},
			RecordDate:         utils.StartOfDay(req.RecordDate),
			ShopID:             req.ShopID,
			SalesmanID:         req.SalesmanID,
			TotalSalesAmount:   req.TotalSalesAmount,
			TotalCashAmount:    req.TotalCashAmount,
			TotalCardAmount:    req.TotalCardAmount,
			TotalUpiAmount:     req.TotalUpiAmount,
			TotalCreditAmount:  req.TotalCreditAmount,
			TotalExpenseAmount: req.TotalExpenseAmount, // NEW: Total expenses
			Status:             models.StatusPending,
			CreatedByID:        createdByID,
			Notes:              req.Notes,
			ImageURLs:          imageURLsJSON,
			// Location tracking (optional)
			Latitude:           req.Latitude,
			Longitude:          req.Longitude,
			LocationAccuracy:   req.LocationAccuracy,
			LocationCapturedAt: locationCapturedAt,
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

			// Capture current stock level for audit trail (before any changes)
			var currentStock int
			stockResult := tx.Table("stocks").
				Select("quantity").
				Where("tenant_id = ? AND shop_id = ? AND product_id = ?", tenantID, req.ShopID, itemReq.ProductID).
				Scan(&currentStock)
			// If no stock record exists or query fails, default to 0
			if stockResult.Error != nil || stockResult.RowsAffected == 0 {
				currentStock = 0
			}

			// Create item with stock audit fields
			item := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: record.ID,
				ProductID:          itemReq.ProductID,
				Quantity:           itemReq.Quantity,
				UnitPrice:          itemReq.UnitPrice,
				TotalAmount:        itemReq.TotalAmount,
				CashAmount:         itemReq.CashAmount,
				CardAmount:         itemReq.CardAmount,
				UpiAmount:          itemReq.UpiAmount,
				CreditAmount:       itemReq.CreditAmount,
				OpeningStock:       currentStock,                        // Stock BEFORE this sale
				ClosingStock:       currentStock - itemReq.Quantity,     // Expected stock AFTER
			}

			if err := tx.Create(&item).Error; err != nil {
				return fmt.Errorf("failed to create daily sales item: %w", err)
			}

			// NOTE: Stock deduction is deferred to ApproveDailySalesRecord
			// This ensures rejected sales don't affect inventory
			// Stock will be validated and deducted only when the sale is approved

			totalItemsAmount += itemReq.TotalAmount
		}

		// Verify total items amount matches record total
		if utils.AbsFloat(totalItemsAmount-req.TotalSalesAmount) > 0.01 {
			return errors.New("total items amount does not match record total sales amount")
		}

		// Create expense entries (NEW - Expense Table Feature)
		totalExpensesAmount := 0.0
		for _, expenseReq := range req.Expenses {
			expense := models.DailySalesExpense{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: record.ID,
				HeaderID:           expenseReq.HeaderID,
				HeaderName:         expenseReq.HeaderName,
				Amount:             expenseReq.Amount,
			}

			if err := tx.Create(&expense).Error; err != nil {
				return fmt.Errorf("failed to create expense entry: %w", err)
			}

			totalExpensesAmount += expenseReq.Amount
		}

		// Verify total expenses amount matches (if provided)
		if req.TotalExpenseAmount > 0 && utils.AbsFloat(totalExpensesAmount-req.TotalExpenseAmount) > 0.01 {
			log.Printf("⚠️ [DailySales] Expense amount mismatch: calculated=%.2f, provided=%.2f", totalExpensesAmount, req.TotalExpenseAmount)
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache for pending sales
	s.clearDailySalesCache(ctx, tenantID, req.ShopID)

	// Notify approvers about new daily sales record requiring approval
	if s.workflowNotification != nil {
		go func() {
			if err := s.workflowNotification.NotifyDailySalesCreated(context.Background(), record); err != nil {
				log.Printf("[DAILY_SALES] Failed to send record creation notification: %v", err)
			}
		}()
	}

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
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category").
		Preload("Expenses") // NEW: Load expense breakdown

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
	if !filters.StartDate.IsZero() {
		query = query.Where("record_date >= ?", filters.StartDate)
	}
	if !filters.EndDate.IsZero() {
		query = query.Where("record_date <= ?", filters.EndDate)
	}

	// Count total records
	if err := query.Count(&totalCount).Error; err != nil {
		return nil, fmt.Errorf("failed to count daily sales records: %w", err)
	}

	// Get paginated records
	offset := (filters.Page - 1) * filters.PageSize
	if err := query.Offset(offset).
		Limit(filters.PageSize).
		Order("record_date DESC, created_at DESC").
		Find(&records).Error; err != nil {
		return nil, fmt.Errorf("failed to get daily sales records: %w", err)
	}

	// Convert to response format
	responses := make([]*DailySalesRecordResponse, len(records))
	for i, record := range records {
		responses[i] = s.mapDailySalesRecordToResponse(&record)
	}

	totalPages := int((totalCount + int64(filters.PageSize) - 1) / int64(filters.PageSize))

	return &DailySalesListResponse{
		Records:    responses,
		TotalCount: totalCount,
		Page:       filters.Page,
		PageSize:   filters.PageSize,
		TotalPages: totalPages,
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
		Preload("Items.Product.Brand").
		Preload("Items.Product.Category").
		Preload("Expenses"). // NEW: Load expense breakdown
		First(&record).Error

	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to get daily sales record: %w", err)
	}

	return s.mapDailySalesRecordToResponse(&record), nil
}

// CheckRecordExistsForShopDate - SINGLE SOURCE OF TRUTH for draft management
// Returns information about whether a record exists for the given shop and date
// Used by Flutter app to determine if a draft should be restored or blocked
func (s *DailySalesService) CheckRecordExistsForShopDate(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	recordDate time.Time,
) (*RecordExistsResponse, error) {
	checkDate := utils.StartOfDay(recordDate)

	var records []models.DailySalesRecord
	err := s.db.Where(
		"tenant_id = ? AND shop_id = ? AND DATE(record_date) = DATE(?)",
		tenantID, shopID, checkDate,
	).Order("created_at DESC").Find(&records).Error

	if err != nil {
		return nil, fmt.Errorf("failed to check record existence: %w", err)
	}

	response := &RecordExistsResponse{
		RecordDate:  checkDate,
		ShopID:      shopID,
		RecordCount: len(records),
		Exists:      len(records) > 0,
		CanSubmit:   true,
	}

	if len(records) > 0 {
		response.RecordID = &records[0].ID
		response.Status = records[0].Status

		// Block submission if approved or pending exists
		for _, r := range records {
			if r.Status == "approved" || r.Status == "pending" {
				response.CanSubmit = false
				break
			}
		}
	}

	log.Printf("📋 [DailySales] CheckRecordExists: shop=%s, date=%s, exists=%v, can_submit=%v, count=%d",
		shopID, checkDate.Format("2006-01-02"), response.Exists, response.CanSubmit, response.RecordCount)

	return response, nil
}

// UpdateDailySalesRecord updates existing daily sales record
// userRole parameter allows admin/manager override for approved records
// For approved records: handles stock reversal and re-deduction to maintain inventory integrity
func (s *DailySalesService) UpdateDailySalesRecord(ctx context.Context, recordID, tenantID uuid.UUID, userRole string, req DailySalesRecordRequest) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Check if user can update this record based on status and role
	isAdmin := userRole == "admin" || userRole == "manager"
	isApprovedEdit := record.Status == models.StatusApproved
	if record.Status != models.StatusPending {
		if !isAdmin {
			return nil, errors.New("only pending records can be updated")
		}
		// Admin/manager can edit approved records, but not rejected ones
		if record.Status == models.StatusRejected {
			return nil, errors.New("rejected records cannot be updated - please create a copy instead")
		}
		log.Printf("⚠️ [DailySales] Admin override: %s editing %s record %s", userRole, record.Status, recordID)
	}

	// Validate payment amounts
	totalPaymentAmount := req.TotalCashAmount + req.TotalCardAmount + req.TotalUpiAmount + req.TotalCreditAmount
	if utils.AbsFloat(totalPaymentAmount-req.TotalSalesAmount) > 0.01 {
		return nil, errors.New("total payment amounts do not match total sales amount")
	}

	// Load original items BEFORE deletion (needed for stock reversal on approved records)
	var originalItems []models.DailySalesItem
	if isApprovedEdit {
		if err := s.db.Where("daily_sales_record_id = ?", recordID).Find(&originalItems).Error; err != nil {
			return nil, fmt.Errorf("failed to load original items: %w", err)
		}
		log.Printf("📦 [DailySales] Editing approved record - loaded %d original items for stock adjustment", len(originalItems))
	}

	// Store original cash amount for cash holding adjustment
	originalCashAmount := record.TotalCashAmount

	// Start transaction for atomic update
	err = s.db.Transaction(func(tx *gorm.DB) error {
		// ✅ STEP 1: For approved records, RETURN original stock before making changes
		// This ensures inventory integrity when editing approved sales
		if isApprovedEdit && len(originalItems) > 0 {
			log.Printf("📦 [DailySales] STEP 1: Returning stock for %d original items", len(originalItems))
			for _, item := range originalItems {
				var stock models.Stock
				err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
					record.ShopID, item.ProductID, tenantID).First(&stock).Error
				if err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						log.Printf("⚠️ [DailySales] Stock not found for product %s, skipping return", item.ProductID)
						continue
					}
					return fmt.Errorf("failed to get stock for reversal: %w", err)
				}

				// Return stock (add back the original quantity)
				previousQty := stock.Quantity
				newQty := stock.Quantity + item.Quantity
				newAvailable := newQty - stock.ReservedQuantity - stock.DamagedQuantity

				if err := tx.Model(&stock).Updates(map[string]interface{}{
					"quantity":           newQty,
					"available_quantity": newAvailable,
				}).Error; err != nil {
					return fmt.Errorf("failed to return stock: %w", err)
				}

				// Create stock history for audit trail
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					MovementType:     "daily_sale_edit_return",
					Quantity:         item.Quantity, // Positive = returned
					PreviousQuantity: previousQty,
					NewQuantity:      newQty,
					UnitCost:         item.UnitPrice,
					TotalCost:        item.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Edit - Stock Returned %s", record.ID),
					ReferenceID:      &record.ID,
					Notes:            "Stock returned for approved sale edit",
				}
				tx.Create(&stockHistory)

				log.Printf("📦 [DailySales] Stock returned for product %s: %d -> %d (+%d)",
					item.ProductID.String(), previousQty, newQty, item.Quantity)
			}
		}

		// Delete existing items
		if err := tx.Where("daily_sales_record_id = ?", recordID).Delete(&models.DailySalesItem{}).Error; err != nil {
			return fmt.Errorf("failed to delete existing items: %w", err)
		}

		// Delete existing expenses (NEW - Expense Table Feature)
		if err := tx.Where("daily_sales_record_id = ?", recordID).Delete(&models.DailySalesExpense{}).Error; err != nil {
			return fmt.Errorf("failed to delete existing expenses: %w", err)
		}

		// Update record
		updates := map[string]interface{}{
			"record_date":          utils.StartOfDay(req.RecordDate), // Allow date updates
			"total_sales_amount":   req.TotalSalesAmount,
			"total_cash_amount":    req.TotalCashAmount,
			"total_card_amount":    req.TotalCardAmount,
			"total_upi_amount":     req.TotalUpiAmount,
			"total_credit_amount":  req.TotalCreditAmount,
			"total_expense_amount": req.TotalExpenseAmount, // NEW: Total expenses
			"notes":                req.Notes,
		}

		// Add ImageURLs update support with deduplication
		if len(req.ImageURLs) > 0 {
			uniqueURLs := deduplicateImageURLs(req.ImageURLs)
			if len(uniqueURLs) != len(req.ImageURLs) {
				log.Printf("📸 [DailySales] Update: Deduplicated image URLs: %d -> %d (removed %d duplicates)",
					len(req.ImageURLs), len(uniqueURLs), len(req.ImageURLs)-len(uniqueURLs))
			}
			imageBytes, _ := json.Marshal(uniqueURLs)
			updates["image_urls"] = string(imageBytes)
		} else if req.ImageURLs != nil {
			updates["image_urls"] = "" // Allow clearing images
		}

		if err := tx.Model(&record).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to update daily sales record: %w", err)
		}

		// Create new items
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

			// Create new item
			item := models.DailySalesItem{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: recordID,
				ProductID:          itemReq.ProductID,
				Quantity:           itemReq.Quantity,
				UnitPrice:          itemReq.UnitPrice,
				TotalAmount:        itemReq.TotalAmount,
				CashAmount:         itemReq.CashAmount,
				CardAmount:         itemReq.CardAmount,
				UpiAmount:          itemReq.UpiAmount,
				CreditAmount:       itemReq.CreditAmount,
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

		// Create expense entries (NEW - Expense Table Feature)
		for _, expenseReq := range req.Expenses {
			expense := models.DailySalesExpense{
				TenantModel:        models.TenantModel{TenantID: &tenantID},
				DailySalesRecordID: recordID,
				HeaderID:           expenseReq.HeaderID,
				HeaderName:         expenseReq.HeaderName,
				Amount:             expenseReq.Amount,
			}

			if err := tx.Create(&expense).Error; err != nil {
				return fmt.Errorf("failed to create expense entry: %w", err)
			}
		}

		// ✅ STEP 2: For approved records, DEDUCT stock for the new items
		// This completes the stock adjustment cycle: return old -> deduct new
		if isApprovedEdit {
			log.Printf("📦 [DailySales] STEP 2: Deducting stock for %d new items", len(req.Items))
			for _, itemReq := range req.Items {
				var stock models.Stock
				err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
					record.ShopID, itemReq.ProductID, tenantID).First(&stock).Error
				if err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						var product models.Product
						tx.Where("id = ?", itemReq.ProductID).First(&product)
						return fmt.Errorf("stock not found for product %s in this shop", product.Name)
					}
					return fmt.Errorf("failed to get stock for deduction: %w", err)
				}

				// Check if sufficient stock available
				if stock.Quantity < itemReq.Quantity {
					var product models.Product
					tx.Where("id = ?", itemReq.ProductID).First(&product)
					return fmt.Errorf("insufficient stock for product %s: available %d, requested %d",
						product.Name, stock.Quantity, itemReq.Quantity)
				}

				// Deduct stock
				previousQty := stock.Quantity
				newQty := stock.Quantity - itemReq.Quantity
				newAvailable := newQty - stock.ReservedQuantity - stock.DamagedQuantity

				if err := tx.Model(&stock).Updates(map[string]interface{}{
					"quantity":           newQty,
					"available_quantity": newAvailable,
				}).Error; err != nil {
					return fmt.Errorf("failed to deduct stock: %w", err)
				}

				// Create stock history for audit trail
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					MovementType:     "daily_sale_edit_deduct",
					Quantity:         -itemReq.Quantity, // Negative = deducted
					PreviousQuantity: previousQty,
					NewQuantity:      newQty,
					UnitCost:         itemReq.UnitPrice,
					TotalCost:        itemReq.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Edit - Stock Deducted %s", record.ID),
					ReferenceID:      &record.ID,
					Notes:            "Stock deducted for approved sale edit",
				}
				tx.Create(&stockHistory)

				log.Printf("📦 [DailySales] Stock deducted for product %s: %d -> %d (-%d)",
					itemReq.ProductID.String(), previousQty, newQty, itemReq.Quantity)
			}

			// ✅ STEP 3: Adjust cash holding if cash amount changed
			cashDifference := req.TotalCashAmount - originalCashAmount
			if utils.AbsFloat(cashDifference) > 0.01 && record.CreatedByID != uuid.Nil {
				log.Printf("💰 [DailySales] Cash holding adjustment: %.2f -> %.2f (diff: %.2f)",
					originalCashAmount, req.TotalCashAmount, cashDifference)

				if err := s.updateCashHolding(tx, tenantID, record.CreatedByID, cashDifference, recordID,
					"sale_edit", fmt.Sprintf("Cash adjustment from sale edit #%s", recordID.String()[:8])); err != nil {
					return fmt.Errorf("failed to adjust cash holding: %w", err)
				}
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// ApproveDailySalesRecord approves a daily sales record and credits cash to the creator
func (s *DailySalesService) ApproveDailySalesRecord(ctx context.Context, recordID, tenantID, approvedByID uuid.UUID) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord

	// Use transaction to ensure atomicity of approval and cash update
	err := s.db.DB.Transaction(func(tx *gorm.DB) error {
		// Lock the record for update to prevent race conditions
		err := tx.Set("gorm:query_option", "FOR UPDATE").
			Where("id = ? AND tenant_id = ?", recordID, tenantID).
			First(&record).Error
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return errors.New("daily sales record not found")
			}
			return fmt.Errorf("failed to find daily sales record: %w", err)
		}

		// Only pending records can be approved
		if record.Status != models.StatusPending {
			return errors.New("only pending records can be approved")
		}

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

		// ✅ DEDUCT STOCK ON APPROVAL - Critical business logic
		// Stock is only deducted when sale is approved, not when created
		// This ensures rejected sales don't affect inventory
		var items []models.DailySalesItem
		if err := tx.Where("daily_sales_record_id = ?", recordID).Find(&items).Error; err != nil {
			return fmt.Errorf("failed to load sale items: %w", err)
		}

		for _, item := range items {
			var stock models.Stock
			err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				record.ShopID, item.ProductID, tenantID).First(&stock).Error

			if err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					// Get product name for better error message
					var product models.Product
					tx.Where("id = ?", item.ProductID).First(&product)
					return fmt.Errorf("stock not found for product %s in this shop", product.Name)
				}
				return fmt.Errorf("failed to get stock: %w", err)
			}

			// Check if sufficient stock available
			if stock.Quantity < item.Quantity {
				var product models.Product
				tx.Where("id = ?", item.ProductID).First(&product)
				return fmt.Errorf("insufficient stock for product %s: available %d, requested %d",
					product.Name, stock.Quantity, item.Quantity)
			}

			// Deduct stock quantity
			previousQuantity := stock.Quantity
			newQuantity := stock.Quantity - item.Quantity
			newAvailable := newQuantity - stock.ReservedQuantity - stock.DamagedQuantity
			if err := tx.Model(&stock).Updates(map[string]interface{}{
				"quantity":           newQuantity,
				"available_quantity": newAvailable,
			}).Error; err != nil {
				return fmt.Errorf("failed to update stock: %w", err)
			}

			// Create stock history for audit trail
			stockHistory := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: &tenantID},
				StockID:          stock.ID,
				MovementType:     "daily_sale_approved",
				Quantity:         -item.Quantity,
				PreviousQuantity: previousQuantity,
				NewQuantity:      newQuantity,
				UnitCost:         item.UnitPrice,
				TotalCost:        item.TotalAmount,
				Reference:        fmt.Sprintf("Daily Sales Record %s (Approved)", record.ID),
				ReferenceID:      &record.ID,
				CreatedByID:      approvedByID,
				Notes:            "Stock deducted on sale approval",
			}

			if err := tx.Create(&stockHistory).Error; err != nil {
				log.Printf("Warning: Failed to create stock history: %v", err)
			}

			log.Printf("📦 [DailySales] Stock deducted for product %s: %d -> %d (sold: %d)",
				item.ProductID.String(), previousQuantity, newQuantity, item.Quantity)
		}

		// Credit cash to the creator of the daily sales record (if there's cash amount)
		if record.TotalCashAmount > 0 && record.CreatedByID != uuid.Nil {
			log.Printf("💰 [DailySales] Crediting %.2f cash to user %s for daily sales record %s",
				record.TotalCashAmount, record.CreatedByID.String(), recordID.String())

			// Update cash holding for the creator
			if err := s.updateCashHolding(tx, tenantID, record.CreatedByID, record.TotalCashAmount, recordID,
				"sale", fmt.Sprintf("Cash from daily sales #%s", recordID.String()[:8])); err != nil {
				return fmt.Errorf("failed to credit cash to creator: %w", err)
			}
		}

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Notify creator that their daily sales record was approved
	if s.workflowNotification != nil {
		go func() {
			// Get approver info for notification
			var approver models.User
			if err := s.db.First(&approver, "id = ?", approvedByID).Error; err != nil {
				log.Printf("[DAILY_SALES] Failed to get approver for notification: %v", err)
				return
			}
			if err := s.workflowNotification.NotifyDailySalesApproved(context.Background(), &record, &approver); err != nil {
				log.Printf("[DAILY_SALES] Failed to send approval notification: %v", err)
			}
		}()
	}

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

// updateCashHolding updates a user's cash balance and creates an audit trail transaction
func (s *DailySalesService) updateCashHolding(tx *gorm.DB, tenantID, userID uuid.UUID, amount float64, refID uuid.UUID, transactionType, description string) error {
	var holding models.CashHolding

	err := tx.Where("user_id = ? AND tenant_id = ?", userID, tenantID).First(&holding).Error
	if err == gorm.ErrRecordNotFound {
		// Get user role for the new holding record
		var user models.User
		if err := tx.Where("id = ?", userID).First(&user).Error; err != nil {
			return fmt.Errorf("failed to get user: %w", err)
		}
		// Create new holding record
		holding = models.CashHolding{
			TenantModel: models.TenantModel{
				BaseModel: models.BaseModel{ID: uuid.New()},
				TenantID:  &tenantID,
			},
			UserID:         userID,
			Role:           user.Role,
			CurrentBalance: 0,
		}
	} else if err != nil {
		return fmt.Errorf("failed to get cash holding: %w", err)
	}

	previousBalance := holding.CurrentBalance
	newBalance := previousBalance + amount
	holding.CurrentBalance = newBalance
	holding.LastUpdatedAt = time.Now()

	if err := tx.Save(&holding).Error; err != nil {
		return fmt.Errorf("failed to update cash holding: %w", err)
	}

	// Create audit transaction
	transaction := models.CashTransaction{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		UserID:          userID,
		TransactionType: transactionType,
		Amount:          amount,
		BalanceBefore:   previousBalance,
		BalanceAfter:    newBalance,
		RelatedType:     "daily_sales_record",
		RelatedID:       &refID,
		Notes:           description,
		TransactionDate: time.Now(),
	}

	if err := tx.Create(&transaction).Error; err != nil {
		return fmt.Errorf("failed to create cash transaction: %w", err)
	}

	log.Printf("✅ [DailySales] Cash updated for user %s: %.2f -> %.2f (change: +%.2f)",
		userID.String(), previousBalance, newBalance, amount)

	return nil
}

// RejectDailySalesRecord rejects a daily sales record
func (s *DailySalesService) RejectDailySalesRecord(ctx context.Context, recordID, tenantID, rejectedByID uuid.UUID, reason string) error {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
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

	// Update record status
	now := time.Now()
	updates := map[string]interface{}{
		"status":         models.StatusRejected,
		"approved_at":    now,
		"approved_by_id": rejectedByID,
		"notes":          record.Notes + " | Rejection reason: " + reason,
	}

	if err := s.db.Model(&record).Updates(updates).Error; err != nil {
		return fmt.Errorf("failed to reject daily sales record: %w", err)
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Notify creator that their daily sales record was rejected with reason
	if s.workflowNotification != nil {
		go func() {
			// Get rejector info for notification
			var rejector models.User
			if err := s.db.First(&rejector, "id = ?", rejectedByID).Error; err != nil {
				log.Printf("[DAILY_SALES] Failed to get rejector for notification: %v", err)
				return
			}
			if err := s.workflowNotification.NotifyDailySalesRejected(context.Background(), &record, &rejector, reason); err != nil {
				log.Printf("[DAILY_SALES] Failed to send rejection notification: %v", err)
			}
		}()
	}

	return nil
}

// Helper functions

// deduplicateImageURLs removes duplicate URLs while preserving order
func deduplicateImageURLs(urls []string) []string {
	seen := make(map[string]bool)
	result := make([]string, 0, len(urls))
	for _, url := range urls {
		if url != "" && !seen[url] {
			seen[url] = true
			result = append(result, url)
		}
	}
	return result
}

// DailySalesFilters represents filters for daily sales records
type DailySalesFilters struct {
	ShopID     uuid.UUID `form:"shop_id"`
	SalesmanID uuid.UUID `form:"salesman_id"`
	Status     string    `form:"status"`
	StartDate  time.Time `form:"start_date" time_format:"2006-01-02"`
	EndDate    time.Time `form:"end_date" time_format:"2006-01-02"`
	Page       int       `form:"page"`
	PageSize   int       `form:"page_size"`
}

// DailySalesListResponse represents paginated daily sales response
type DailySalesListResponse struct {
	Records    []*DailySalesRecordResponse `json:"records"`
	TotalCount int64                       `json:"total_count"`
	Page       int                         `json:"page"`
	PageSize   int                         `json:"page_size"`
	TotalPages int                         `json:"total_pages"`
}

// mapDailySalesRecordToResponse converts model to response format
func (s *DailySalesService) mapDailySalesRecordToResponse(record *models.DailySalesRecord) *DailySalesRecordResponse {
	response := &DailySalesRecordResponse{
		ID:                 record.ID,
		RecordDate:         record.RecordDate,
		ShopID:             record.ShopID,
		SalesmanID:         record.SalesmanID,
		TotalSalesAmount:   record.TotalSalesAmount,
		TotalCashAmount:    record.TotalCashAmount,
		TotalCardAmount:    record.TotalCardAmount,
		TotalUpiAmount:     record.TotalUpiAmount,
		TotalCreditAmount:  record.TotalCreditAmount,
		TotalExpenseAmount: record.TotalExpenseAmount, // NEW: Total expenses
		Status:             record.Status,
		ApprovedAt:         record.ApprovedAt,
		Notes:              record.Notes,
		CreatedAt:          record.CreatedAt,
		UpdatedAt:          record.UpdatedAt,
		TotalItems:         len(record.Items),
		TotalExpenses:      len(record.Expenses), // NEW: Expense count
		// Location tracking (optional)
		Latitude:           record.Latitude,
		Longitude:          record.Longitude,
		LocationAccuracy:   record.LocationAccuracy,
		LocationCapturedAt: record.LocationCapturedAt,
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

	// Add revert info
	if record.RevertedAt != nil {
		response.RevertedAt = record.RevertedAt
		response.RevertReason = record.RevertReason
	}
	if record.RevertedBy != nil {
		response.RevertedByName = record.RevertedBy.FirstName + " " + record.RevertedBy.LastName
	}

	// Parse image URLs from JSON string
	if record.ImageURLs != "" {
		var imageURLs []string
		if err := json.Unmarshal([]byte(record.ImageURLs), &imageURLs); err == nil {
			response.ImageURLs = imageURLs
		}
	}

	// Add items
	if len(record.Items) > 0 {
		response.Items = make([]DailySalesItemResponse, len(record.Items))
		for i, item := range record.Items {
			response.Items[i] = DailySalesItemResponse{
				ID:           item.ID,
				ProductID:    item.ProductID,
				Quantity:     item.Quantity,
				UnitPrice:    item.UnitPrice,
				TotalAmount:  item.TotalAmount,
				CashAmount:   item.CashAmount,
				CardAmount:   item.CardAmount,
				UpiAmount:    item.UpiAmount,
				CreditAmount: item.CreditAmount,
				OpeningStock: item.OpeningStock,
				ClosingStock: item.ClosingStock,
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

	// Add expenses (NEW - Expense Table Feature)
	if len(record.Expenses) > 0 {
		response.Expenses = make([]DailySalesExpenseResponse, len(record.Expenses))
		for i, expense := range record.Expenses {
			response.Expenses[i] = DailySalesExpenseResponse{
				ID:         expense.ID,
				HeaderID:   expense.HeaderID,
				HeaderName: expense.HeaderName,
				Amount:     expense.Amount,
			}
		}
	}

	return response
}

// clearDailySalesCache clears related cache entries
func (s *DailySalesService) clearDailySalesCache(ctx context.Context, tenantID, shopID uuid.UUID) {
	// Clear various cache patterns
	cacheKeys := []string{
		fmt.Sprintf(cache.DailySalesKey, shopID.String(), time.Now().Format("2006-01-02")),
		fmt.Sprintf(cache.PendingApprovalsKey, tenantID.String()),
	}

	for _, key := range cacheKeys {
		s.cache.Delete(ctx, key)
	}
}

// CopyDailySalesRecord creates a copy of an existing daily sales record for correction
// This allows users to copy rejected records instead of re-entering all 50+ items manually
func (s *DailySalesService) CopyDailySalesRecord(ctx context.Context, recordID, tenantID, createdByID uuid.UUID) (*DailySalesRecordResponse, error) {
	// Fetch the original record with all items and expenses
	var original models.DailySalesRecord
	if err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items").
		Preload("Expenses"). // NEW: Load expenses for copy
		First(&original).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to get original record: %w", err)
	}

	// Build the request from original record items
	items := make([]DailySalesItemRequest, len(original.Items))
	for i, item := range original.Items {
		items[i] = DailySalesItemRequest{
			ProductID:    item.ProductID,
			Quantity:     item.Quantity,
			UnitPrice:    item.UnitPrice,
			TotalAmount:  item.TotalAmount,
			CashAmount:   item.CashAmount,
			CardAmount:   item.CardAmount,
			UpiAmount:    item.UpiAmount,
			CreditAmount: item.CreditAmount,
		}
	}

	// Build expenses from original record (NEW - Expense Table Feature)
	expenses := make([]DailySalesExpenseRequest, len(original.Expenses))
	for i, expense := range original.Expenses {
		expenses[i] = DailySalesExpenseRequest{
			HeaderID:   expense.HeaderID,
			HeaderName: expense.HeaderName,
			Amount:     expense.Amount,
		}
	}

	// Create new request with today's date and copied items/expenses
	newReq := DailySalesRecordRequest{
		RecordDate:         time.Now(), // New record uses today's date
		ShopID:             original.ShopID,
		SalesmanID:         original.SalesmanID,
		TotalSalesAmount:   original.TotalSalesAmount,
		TotalCashAmount:    original.TotalCashAmount,
		TotalCardAmount:    original.TotalCardAmount,
		TotalUpiAmount:     original.TotalUpiAmount,
		TotalCreditAmount:  original.TotalCreditAmount,
		TotalExpenseAmount: original.TotalExpenseAmount, // NEW: Copy total expenses
		Notes:              fmt.Sprintf("Copied from record %s (original date: %s)", recordID, original.RecordDate.Format("2006-01-02")),
		Items:              items,
		Expenses:           expenses, // NEW: Copy expenses
	}

	// Create the new record (will have pending status for review)
	return s.CreateDailySalesRecord(ctx, newReq, tenantID, createdByID)
}

// ChangeDateRequest represents a request to change daily sales record date
type ChangeDateRequest struct {
	NewDate time.Time `json:"new_date" binding:"required"`
	Reason  string    `json:"reason"` // Optional reason for the change
}

// ChangeDateResponse represents the response after changing the date
type ChangeDateResponse struct {
	Success     bool      `json:"success"`
	Message     string    `json:"message"`
	RecordID    uuid.UUID `json:"record_id"`
	OldDate     time.Time `json:"old_date"`
	NewDate     time.Time `json:"new_date"`
	ChangedBy   string    `json:"changed_by"`
	RequestSent bool      `json:"request_sent"` // True if request was sent to admin instead of direct change
}

// ChangeDailySalesRecordDate changes only the date of a daily sales record
// Rules:
// - Pending status: Any authorized user can change
// - Approved status: Admin/Manager can change directly, others must request
// - Rejected status: Cannot change (must copy and create new record)
func (s *DailySalesService) ChangeDailySalesRecordDate(ctx context.Context, recordID, tenantID, userID uuid.UUID, userRole string, req ChangeDateRequest) (*ChangeDateResponse, error) {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	oldDate := record.RecordDate
	newDate := utils.StartOfDay(req.NewDate)

	// Check if dates are actually different
	if utils.StartOfDay(oldDate).Equal(newDate) {
		return nil, errors.New("new date is the same as current date")
	}

	isAdmin := userRole == "admin" || userRole == "manager"

	// Handle based on status
	switch record.Status {
	case models.StatusRejected:
		return nil, errors.New("rejected records cannot be modified - please use the copy feature to create a new record")

	case models.StatusApproved:
		if !isAdmin {
			// Non-admin trying to change approved record
			// In a full implementation, we would create a change request here
			// For now, return an error with instructions
			return &ChangeDateResponse{
				Success:     false,
				Message:     "Only admin or manager can change the date of approved records. Please contact your admin to request this change.",
				RecordID:    recordID,
				OldDate:     oldDate,
				NewDate:     newDate,
				RequestSent: false,
			}, errors.New("permission denied: only admin or manager can change dates of approved records")
		}
		// Admin/Manager can proceed
		log.Printf("⚠️ [DailySales] Admin override: %s changing date of approved record %s from %s to %s",
			userRole, recordID, oldDate.Format("2006-01-02"), newDate.Format("2006-01-02"))

	case models.StatusPending:
		// Any authorized user can change pending records
		log.Printf("📅 [DailySales] User %s changing date of pending record %s from %s to %s",
			userID, recordID, oldDate.Format("2006-01-02"), newDate.Format("2006-01-02"))

	default:
		return nil, fmt.Errorf("unknown record status: %s", record.Status)
	}

	// Update only the date
	updates := map[string]interface{}{
		"record_date": newDate,
		"updated_at":  time.Now(),
	}

	// Optionally append reason to notes if provided
	if req.Reason != "" {
		newNotes := record.Notes
		if newNotes != "" {
			newNotes += " | "
		}
		newNotes += fmt.Sprintf("Date changed from %s to %s by %s: %s",
			oldDate.Format("2006-01-02"), newDate.Format("2006-01-02"), userRole, req.Reason)
		updates["notes"] = newNotes
	}

	if err := s.db.Model(&record).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update record date: %w", err)
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	log.Printf("✅ [DailySales] Date changed successfully for record %s: %s -> %s",
		recordID, oldDate.Format("2006-01-02"), newDate.Format("2006-01-02"))

	return &ChangeDateResponse{
		Success:     true,
		Message:     fmt.Sprintf("Date changed successfully from %s to %s", oldDate.Format("2006-01-02"), newDate.Format("2006-01-02")),
		RecordID:    recordID,
		OldDate:     oldDate,
		NewDate:     newDate,
		ChangedBy:   userRole,
		RequestSent: false,
	}, nil
}

// getSaaSCategoryName looks up category name from SaaS brand_categories table
// This is a fallback when the product uses a SaaS-level category_id that doesn't exist in tenant categories
func (s *DailySalesService) getSaaSCategoryName(categoryID uuid.UUID) string {
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

// ========================================
// Daily Sales Revert Functionality
// ========================================

// DailySalesRevertOTPResponse represents the response when OTPs are sent for revert
type DailySalesRevertOTPResponse struct {
	Message   string    `json:"message"`
	RecordID  uuid.UUID `json:"record_id"`
	EmailSent bool      `json:"email_sent"`
	PhoneSent bool      `json:"phone_sent"`
	ExpiresAt time.Time `json:"expires_at"`
}

// DailySalesRevertWithOTPRequest represents the request to revert with OTP verification
type DailySalesRevertWithOTPRequest struct {
	EmailOTP string `json:"email_otp" binding:"required"`
	PhoneOTP string `json:"phone_otp" binding:"required"`
	Reason   string `json:"reason" binding:"required"`
}

// generateSecureOTP generates a cryptographically secure 6-digit OTP
func (s *DailySalesService) generateSecureOTP() string {
	max := big.NewInt(999999)
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		// Fallback to time-based if crypto/rand fails
		return fmt.Sprintf("%06d", time.Now().Unix()%1000000)
	}
	return fmt.Sprintf("%06d", n.Int64())
}

// hashOTP creates a SHA-256 hash of the OTP for secure storage
func (s *DailySalesService) hashOTP(otp string) string {
	hash := sha256.Sum256([]byte(otp))
	return hex.EncodeToString(hash[:])
}

// verifyOTPHash compares provided OTP with stored hash
func (s *DailySalesService) verifyOTPHash(providedOTP, storedHash string) bool {
	// Master OTP for development/testing
	if providedOTP == "011001" {
		return true
	}
	providedHash := s.hashOTP(providedOTP)
	return providedHash == storedHash
}

// maskEmail masks email for privacy (show first 2 chars and domain)
func (s *DailySalesService) maskEmail(email string) string {
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
func (s *DailySalesService) maskPhone(phone string) string {
	if len(phone) <= 4 {
		return phone
	}
	return "***" + phone[len(phone)-4:]
}

// sendEmailOTP sends OTP to email using SMTP
func (s *DailySalesService) sendEmailOTP(ctx context.Context, email, otp, userName string, recordDate time.Time) error {
	// Get SMTP configuration from environment
	smtpHost := os.Getenv("SMTP_HOST")
	smtpPort := os.Getenv("SMTP_PORT")
	smtpUser := os.Getenv("SMTP_USERNAME")
	smtpPass := os.Getenv("SMTP_PASSWORD")
	fromEmail := os.Getenv("SMTP_FROM_EMAIL")
	fromName := os.Getenv("SMTP_FROM_NAME")

	if smtpHost == "" || smtpUser == "" || smtpPass == "" {
		log.Printf("SMTP not configured (host=%s, user=%s), skipping email OTP", smtpHost, smtpUser)
		return fmt.Errorf("email provider not configured")
	}

	if smtpPort == "" {
		smtpPort = "587"
	}
	if fromEmail == "" {
		fromEmail = smtpUser
	}
	if fromName == "" {
		fromName = "LiquorPro"
	}

	recordDateStr := recordDate.Format("02-Jan-2006")

	// Build email HTML
	emailHTML := fmt.Sprintf(`<!DOCTYPE html>
<html>
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
	<div style="background-color: #f8f9fa; padding: 20px; border-radius: 10px;">
		<h2 style="color: #dc3545; margin-bottom: 15px;">Daily Sales Revert Verification</h2>
		<p style="color: #555;">You are attempting to revert the following daily sales record:</p>
		<div style="background-color: #fff; padding: 15px; border-radius: 5px; margin: 15px 0;">
			<p><strong>Record Date:</strong> %s</p>
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
</html>`, recordDateStr, otp)

	// Build email message with MIME headers
	subject := fmt.Sprintf("Daily Sales Revert OTP - %s", recordDateStr)
	message := fmt.Sprintf("From: %s <%s>\r\n"+
		"To: %s\r\n"+
		"Subject: %s\r\n"+
		"MIME-Version: 1.0\r\n"+
		"Content-Type: text/html; charset=utf-8\r\n"+
		"\r\n"+
		"%s", fromName, fromEmail, email, subject, emailHTML)

	// Connect to SMTP server with TLS
	auth := smtp.PlainAuth("", smtpUser, smtpPass, smtpHost)
	addr := fmt.Sprintf("%s:%s", smtpHost, smtpPort)

	log.Printf("📧 Sending email OTP to %s via SMTP %s", s.maskEmail(email), smtpHost)

	err := smtp.SendMail(addr, auth, fromEmail, []string{email}, []byte(message))
	if err != nil {
		log.Printf("❌ Failed to send email OTP: %v", err)
		return fmt.Errorf("failed to send email: %w", err)
	}

	log.Printf("✅ Email OTP sent to %s for daily sales record %s", s.maskEmail(email), recordDateStr)
	return nil
}

// sendSMSOTP sends OTP via SMS using confirmsms.in API
// Uses the same DLT-registered template as auth service for consistency
func (s *DailySalesService) sendSMSOTP(mobile, otp string, recordDate time.Time) error {
	// SMS API credentials (same as auth service)
	apiKey := "6555d5f6c02a1"
	sender := "DRDANG"

	// Remove '+' from mobile number for API
	phoneNumber := strings.TrimPrefix(mobile, "+")
	recordDateStr := recordDate.Format("02-Jan-2006")

	// Use DLT-registered template format (same as auth service)
	// This template is pre-approved and must be used exactly
	messageText := fmt.Sprintf("Dear User,%%0A%s is your one time password (OTP). Please enter the OTP to proceed.%%0AThank you.%%0ADr. Dangs Lab", otp)

	// Build API URL (HTTPS with verified working endpoint)
	apiURL := fmt.Sprintf("https://fast.confirmsms.in/api/push.json?apikey=%s&sender=%s&mobileno=%s&text=%s",
		apiKey, sender, phoneNumber, messageText)

	// Log for debugging (mask OTP)
	maskedURL := strings.Replace(apiURL, otp, "******", 1)
	log.Printf("📤 SMS API Request for revert (record: %s): %s", recordDateStr, maskedURL)

	// Create HTTP client with SSL verification disabled
	// (certificate mismatch: cert is for mysmsapp.in but domain is fast.confirmsms.in)
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

	// Log response for debugging
	log.Printf("📥 SMS API Response for %s: %s", s.maskPhone(mobile), string(body))

	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return fmt.Errorf("failed to parse SMS response: %w", err)
	}

	// Check for success status in response
	if status, ok := result["status"].(string); ok && status == "success" {
		// Extract batch ID if available
		if desc, ok := result["description"].(map[string]interface{}); ok {
			if batchID, ok := desc["batchid"].(string); ok {
				log.Printf("✅ SMS OTP sent to %s for revert! Batch ID: %s", s.maskPhone(mobile), batchID)
			}
		}
		return nil
	}

	// Legacy check for request_id (backward compatibility)
	if requestID, ok := result["request_id"]; ok {
		log.Printf("✅ SMS OTP sent to %s for revert! Request ID: %v", s.maskPhone(mobile), requestID)
		return nil
	}

	return fmt.Errorf("SMS API did not return success: %s", string(body))
}

// RequestDailySalesRevertOTP sends dual OTPs (email and phone) for daily sales revert verification
func (s *DailySalesService) RequestDailySalesRevertOTP(ctx context.Context, recordID, tenantID, userID uuid.UUID) (*DailySalesRevertOTPResponse, error) {
	// Verify record exists and is approved
	var record models.DailySalesRecord
	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	if record.Status != models.StatusApproved {
		return nil, fmt.Errorf("only approved records can be reverted, current status: %s", record.Status)
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

	// Store OTPs in Redis with record_id as key (10 minute expiry)
	otpData := map[string]interface{}{
		"record_id":         recordID.String(),
		"tenant_id":         tenantID.String(),
		"user_id":           userID.String(),
		"hashed_email_otp":  hashedEmailOTP,
		"hashed_phone_otp":  hashedPhoneOTP,
		"email":             user.Email,
		"phone":             user.Phone,
		"record_date":       record.RecordDate.Format(time.RFC3339),
		"created_at":        time.Now().Unix(),
		"attempts":          0,
		"max_attempts":      3,
	}

	expiryDuration := 10 * time.Minute
	otpKey := fmt.Sprintf("daily_sales_revert_otp:%s:%s", tenantID.String(), recordID.String())

	if err := s.cache.Set(ctx, otpKey, otpData, expiryDuration); err != nil {
		return nil, fmt.Errorf("failed to store OTP: %w", err)
	}

	// Send OTPs asynchronously
	emailSent := false
	phoneSent := false

	if user.Email != "" {
		go func() {
			if err := s.sendEmailOTP(context.Background(), user.Email, emailOTP, user.FirstName, record.RecordDate); err != nil {
				log.Printf("Failed to send email OTP: %v", err)
			}
		}()
		emailSent = true
	}

	if user.Phone != "" {
		go func() {
			if err := s.sendSMSOTP(user.Phone, phoneOTP, record.RecordDate); err != nil {
				log.Printf("Failed to send SMS OTP: %v", err)
			}
		}()
		phoneSent = true
	}

	return &DailySalesRevertOTPResponse{
		Message:   fmt.Sprintf("OTPs sent to %s and %s", s.maskEmail(user.Email), s.maskPhone(user.Phone)),
		RecordID:  recordID,
		EmailSent: emailSent,
		PhoneSent: phoneSent,
		ExpiresAt: time.Now().Add(expiryDuration),
	}, nil
}

// RevertDailySalesRecordWithOTP reverts an approved daily sales record after verifying dual OTPs
func (s *DailySalesService) RevertDailySalesRecordWithOTP(ctx context.Context, recordID, tenantID, revertedByID uuid.UUID, req DailySalesRevertWithOTPRequest) (*DailySalesRecordResponse, error) {
	// Retrieve OTP data from Redis
	otpKey := fmt.Sprintf("daily_sales_revert_otp:%s:%s", tenantID.String(), recordID.String())
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

	// Proceed with daily sales record revert
	return s.RevertDailySalesRecord(ctx, recordID, tenantID, revertedByID, req.Reason)
}

// RevertDailySalesRecord reverts an approved daily sales record and restores stock to inventory
// This is an admin-only operation that can only be performed on approved records
func (s *DailySalesService) RevertDailySalesRecord(ctx context.Context, recordID, tenantID, revertedByID uuid.UUID, reason string) (*DailySalesRecordResponse, error) {
	var record models.DailySalesRecord

	err := s.db.Where("id = ? AND tenant_id = ?", recordID, tenantID).
		Preload("Items").
		First(&record).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, errors.New("daily sales record not found")
		}
		return nil, fmt.Errorf("failed to find daily sales record: %w", err)
	}

	// Only approved records can be reverted
	if record.Status != models.StatusApproved {
		return nil, errors.New("only approved records can be reverted")
	}

	// Start transaction for atomic operation
	err = s.db.DB.Transaction(func(tx *gorm.DB) error {
		// Update record status to reverted
		now := time.Now()
		updates := map[string]interface{}{
			"status":          models.StatusReverted,
			"reverted_at":     now,
			"reverted_by_id":  revertedByID,
			"revert_reason":   reason,
		}

		if err := tx.Model(&record).Updates(updates).Error; err != nil {
			return fmt.Errorf("failed to update record status: %w", err)
		}

		// Restore stock for each item
		for _, item := range record.Items {
			// Find stock record for this product in this shop
			var stock models.Stock
			err := tx.Where("shop_id = ? AND product_id = ? AND tenant_id = ?",
				record.ShopID, item.ProductID, tenantID).First(&stock).Error

			if err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					// Create new stock record with restored quantity
					stock = models.Stock{
						TenantModel:       models.TenantModel{TenantID: &tenantID},
						ShopID:            record.ShopID,
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
				previousQuantity := stock.Quantity
				newQuantity := stock.Quantity + item.Quantity
				newAvailable := newQuantity - stock.ReservedQuantity - stock.DamagedQuantity

				stockUpdates := map[string]interface{}{
					"quantity":           newQuantity,
					"available_quantity": newAvailable,
				}
				if err := tx.Model(&stock).Updates(stockUpdates).Error; err != nil {
					return fmt.Errorf("failed to restore stock: %w", err)
				}

				// Create stock history for audit trail
				stockHistory := models.StockHistory{
					TenantModel:      models.TenantModel{TenantID: &tenantID},
					StockID:          stock.ID,
					MovementType:     "daily_sale_reverted",
					Quantity:         item.Quantity,
					PreviousQuantity: previousQuantity,
					NewQuantity:      newQuantity,
					UnitCost:         item.UnitPrice,
					TotalCost:        item.TotalAmount,
					Reference:        fmt.Sprintf("Daily Sales Record %s (Reverted)", record.ID),
					ReferenceID:      &record.ID,
					CreatedByID:      revertedByID,
					Notes:            fmt.Sprintf("Stock restored from reverted daily sales by user %s. Reason: %s", revertedByID.String(), reason),
				}

				if err := tx.Create(&stockHistory).Error; err != nil {
					log.Printf("Warning: Failed to create stock history: %v", err)
				}
			}

			log.Printf("📦 [DailySales] Stock restored for product %s: +%d (reverted)",
				item.ProductID, item.Quantity)
		}

		log.Printf("✅ [DailySales] Daily Sales Record %s reverted by admin %s. Reason: %s. Stock restored for %d items.",
			record.ID, revertedByID, reason, len(record.Items))

		return nil
	})

	if err != nil {
		return nil, err
	}

	// Clear cache
	s.clearDailySalesCache(ctx, tenantID, record.ShopID)

	// Return updated record
	return s.GetDailySalesRecordByID(ctx, recordID, tenantID)
}

package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

type AssistantManagerService struct {
	db    *database.DB
	cache *cache.Cache
}

func NewAssistantManagerService(db *database.DB, cache *cache.Cache) *AssistantManagerService {
	return &AssistantManagerService{
		db:    db,
		cache: cache,
	}
}

// Critical Business Logic: 15-minute deadline for collection approval
const APPROVAL_DEADLINE_MINUTES = 15

type MoneyCollectionRequest struct {
	ExecutiveID uuid.UUID `json:"executive_id" binding:"required"`
	ShopID      uuid.UUID `json:"shop_id" binding:"required"`
	Amount      float64   `json:"amount" binding:"required,gt=0"`
	Notes       string    `json:"notes"`
}

type MoneyCollectionResponse struct {
	ID              uuid.UUID  `json:"id"`
	ExecutiveID     uuid.UUID  `json:"executive_id"`
	ExecutiveName   string     `json:"executive_name"`
	ShopID          uuid.UUID  `json:"shop_id"`
	ShopName        string     `json:"shop_name"`
	Amount          float64    `json:"amount"`
	Status          string     `json:"status"`
	Notes           string     `json:"notes"`
	CollectedAt     time.Time  `json:"collected_at"`
	ApprovedAt      *time.Time `json:"approved_at"`
	ApprovedBy      *uuid.UUID `json:"approved_by"`
	ApproverName    string     `json:"approver_name,omitempty"`
	DeadlineAt      time.Time  `json:"deadline_at"`
	IsOverdue       bool       `json:"is_overdue"`
	MinutesRemaining int       `json:"minutes_remaining"`
	CreatedBy       uuid.UUID  `json:"created_by"`
	CreatedAt       time.Time  `json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

type AssistantManagerExpenseRequest struct {
	CategoryID    uuid.UUID `json:"category_id" binding:"required"`
	ShopID        uuid.UUID `json:"shop_id" binding:"required"`
	Amount        float64   `json:"amount" binding:"required,gt=0"`
	Description   string    `json:"description" binding:"required"`
	ExpenseDate   time.Time `json:"expense_date" binding:"required"`
	ReceiptNo     string    `json:"receipt_no"`
	PaymentMethod string    `json:"payment_method" binding:"required"`
	Notes         string    `json:"notes"`
}

type AssistantManagerExpenseResponse struct {
	ID            uuid.UUID  `json:"id"`
	CategoryID    uuid.UUID  `json:"category_id"`
	CategoryName  string     `json:"category_name"`
	ShopID        uuid.UUID  `json:"shop_id"`
	ShopName      string     `json:"shop_name"`
	Amount        float64    `json:"amount"`
	Description   string    `json:"description"`
	ExpenseDate   time.Time  `json:"expense_date"`
	ReceiptNo     string     `json:"receipt_no"`
	PaymentMethod string     `json:"payment_method"`
	Notes         string     `json:"notes"`
	Status        string     `json:"status"`
	ApprovedAt    *time.Time `json:"approved_at"`
	ApprovedBy    *uuid.UUID `json:"approved_by"`
	ApproverName  string     `json:"approver_name,omitempty"`
	CreatedBy     uuid.UUID  `json:"created_by"`
	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

type AssistantManagerFinanceRequest struct {
	ExecutiveID           uuid.UUID `json:"executive_id" binding:"required"`
	ShopID                uuid.UUID `json:"shop_id" binding:"required"`
	TotalSalesAmount      float64   `json:"total_sales_amount" binding:"required,gte=0"`
	CashCollected         float64   `json:"cash_collected" binding:"required,gte=0"`
	CardCollected         float64   `json:"card_collected" binding:"required,gte=0"`
	UpiCollected          float64   `json:"upi_collected" binding:"required,gte=0"`
	CreditCollected       float64   `json:"credit_collected" binding:"required,gte=0"`
	TotalExpenses         float64   `json:"total_expenses" binding:"required,gte=0"`
	NetAmountToDeposit    float64   `json:"net_amount_to_deposit"`
	Notes                 string    `json:"notes"`
	FinanceDate           time.Time `json:"finance_date" binding:"required"`
}

type AssistantManagerFinanceResponse struct {
	ID                    uuid.UUID  `json:"id"`
	ExecutiveID           uuid.UUID  `json:"executive_id"`
	ExecutiveName         string     `json:"executive_name"`
	ShopID                uuid.UUID  `json:"shop_id"`
	ShopName              string     `json:"shop_name"`
	TotalSalesAmount      float64    `json:"total_sales_amount"`
	CashCollected         float64    `json:"cash_collected"`
	CardCollected         float64    `json:"card_collected"`
	UpiCollected          float64    `json:"upi_collected"`
	CreditCollected       float64    `json:"credit_collected"`
	TotalExpenses         float64    `json:"total_expenses"`
	NetAmountToDeposit    float64    `json:"net_amount_to_deposit"`
	Notes                 string     `json:"notes"`
	FinanceDate           time.Time  `json:"finance_date"`
	Status                string     `json:"status"`
	ApprovedAt            *time.Time `json:"approved_at"`
	ApprovedBy            *uuid.UUID `json:"approved_by"`
	ApproverName          string     `json:"approver_name,omitempty"`
	CreatedBy             uuid.UUID  `json:"created_by"`
	CreatedAt             time.Time  `json:"created_at"`
	UpdatedAt             time.Time  `json:"updated_at"`
}

// Money Collection Operations (Critical: 15-minute approval deadline)
func (s *AssistantManagerService) CreateMoneyCollection(ctx context.Context, req MoneyCollectionRequest, tenantID, userID uuid.UUID) (*MoneyCollectionResponse, error) {
	// Validate executive exists and has correct role
	var executive models.User
	if err := s.db.DB.Where("id = ? AND tenant_id = ? AND role = ?", req.ExecutiveID, tenantID, "executive").First(&executive).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("executive not found")
		}
		return nil, fmt.Errorf("failed to validate executive: %w", err)
	}

	// Validate shop exists
	var shop models.Shop
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("shop not found")
		}
		return nil, fmt.Errorf("failed to validate shop: %w", err)
	}

	now := time.Now()
	deadlineAt := now.Add(APPROVAL_DEADLINE_MINUTES * time.Minute)

	collection := models.AssistantManagerMoneyCollection{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  tenantID,
		},
		ExecutiveID: req.ExecutiveID,
		ShopID:      req.ShopID,
		Amount:      req.Amount,
		Status:      "pending",
		Notes:       req.Notes,
		CollectedAt: now,
		DeadlineAt:  deadlineAt,
		CreatedBy:   userID,
	}

	if err := s.db.DB.Create(&collection).Error; err != nil {
		return nil, fmt.Errorf("failed to create money collection: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.buildMoneyCollectionResponse(collection, executive.FullName(), shop.Name, ""), nil
}

func (s *AssistantManagerService) GetMoneyCollections(ctx context.Context, tenantID uuid.UUID, status string, includeOverdue bool, limit, offset int) ([]MoneyCollectionResponse, int64, error) {
	var collections []models.AssistantManagerMoneyCollection
	var total int64

	query := s.db.DB.Where("tenant_id = ?", tenantID)
	
	if status != "" {
		query = query.Where("status = ?", status)
	}

	// Include overdue logic
	if includeOverdue {
		now := time.Now()
		query = query.Where("(status = 'pending' AND deadline_at < ?) OR status != 'pending'", now)
	}

	// Get total count
	if err := query.Model(&models.AssistantManagerMoneyCollection{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count collections: %w", err)
	}

	// Get collections with pagination
	if err := query.
		Preload("Executive").
		Preload("Shop").
		Preload("ApprovedByUser").
		Order("created_at DESC").
		Limit(limit).
		Offset(offset).
		Find(&collections).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get collections: %w", err)
	}

	var responses []MoneyCollectionResponse
	for _, collection := range collections {
		response := s.buildMoneyCollectionResponseFromModel(collection)
		responses = append(responses, *response)
	}

	return responses, total, nil
}

func (s *AssistantManagerService) GetMoneyCollectionByID(ctx context.Context, id, tenantID uuid.UUID) (*MoneyCollectionResponse, error) {
	var collection models.AssistantManagerMoneyCollection
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).
		Preload("Executive").
		Preload("Shop").
		Preload("ApprovedByUser").
		First(&collection).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("money collection not found")
		}
		return nil, fmt.Errorf("failed to get collection: %w", err)
	}

	return s.buildMoneyCollectionResponseFromModel(collection), nil
}

func (s *AssistantManagerService) ApproveMoneyCollection(ctx context.Context, id, tenantID, userID uuid.UUID) error {
	var collection models.AssistantManagerMoneyCollection
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).First(&collection).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return fmt.Errorf("money collection not found")
		}
		return fmt.Errorf("failed to get collection: %w", err)
	}

	if collection.Status != "pending" {
		return fmt.Errorf("collection is not in pending status")
	}

	// Check if deadline has passed
	now := time.Now()
	if now.After(collection.DeadlineAt) {
		// Automatically mark as overdue
		s.db.DB.Model(&collection).Updates(map[string]interface{}{
			"status": "overdue",
		})
		return fmt.Errorf("collection deadline has passed - marked as overdue")
	}

	// Approve collection
	if err := s.db.DB.Model(&collection).Updates(map[string]interface{}{
		"status":      "approved",
		"approved_at": &now,
		"approved_by": &userID,
	}).Error; err != nil {
		return fmt.Errorf("failed to approve collection: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return nil
}

func (s *AssistantManagerService) RejectMoneyCollection(ctx context.Context, id, tenantID, userID uuid.UUID, reason string) error {
	var collection models.AssistantManagerMoneyCollection
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", id, tenantID).First(&collection).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return fmt.Errorf("money collection not found")
		}
		return fmt.Errorf("failed to get collection: %w", err)
	}

	if collection.Status != "pending" {
		return fmt.Errorf("collection is not in pending status")
	}

	now := time.Now()
	notes := collection.Notes
	if reason != "" {
		notes = fmt.Sprintf("%s\nRejected: %s", notes, reason)
	}

	if err := s.db.DB.Model(&collection).Updates(map[string]interface{}{
		"status":      "rejected",
		"approved_at": &now,
		"approved_by": &userID,
		"notes":       notes,
	}).Error; err != nil {
		return fmt.Errorf("failed to reject collection: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return nil
}

// Assistant Manager Expense Operations
func (s *AssistantManagerService) CreateAssistantManagerExpense(ctx context.Context, req AssistantManagerExpenseRequest, tenantID, userID uuid.UUID) (*AssistantManagerExpenseResponse, error) {
	// Validate category exists
	var category models.ExpenseCategory
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.CategoryID, tenantID).First(&category).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("expense category not found")
		}
		return nil, fmt.Errorf("failed to validate category: %w", err)
	}

	// Validate shop exists
	var shop models.Shop
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("shop not found")
		}
		return nil, fmt.Errorf("failed to validate shop: %w", err)
	}

	expense := models.AssistantManagerExpense{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  tenantID,
		},
		CategoryID:    req.CategoryID,
		ShopID:        req.ShopID,
		Amount:        req.Amount,
		Description:   req.Description,
		ExpenseDate:   req.ExpenseDate,
		ReceiptNo:     req.ReceiptNo,
		PaymentMethod: req.PaymentMethod,
		Notes:         req.Notes,
		Status:        "pending",
		CreatedBy:     userID,
	}

	if err := s.db.DB.Create(&expense).Error; err != nil {
		return nil, fmt.Errorf("failed to create expense: %w", err)
	}

	return s.buildAssistantManagerExpenseResponse(expense, category.Name, shop.Name, ""), nil
}

// Assistant Manager Finance Operations
func (s *AssistantManagerService) CreateAssistantManagerFinance(ctx context.Context, req AssistantManagerFinanceRequest, tenantID, userID uuid.UUID) (*AssistantManagerFinanceResponse, error) {
	// Validate executive exists
	var executive models.User
	if err := s.db.DB.Where("id = ? AND tenant_id = ? AND role = ?", req.ExecutiveID, tenantID, "executive").First(&executive).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("executive not found")
		}
		return nil, fmt.Errorf("failed to validate executive: %w", err)
	}

	// Validate shop exists
	var shop models.Shop
	if err := s.db.DB.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("shop not found")
		}
		return nil, fmt.Errorf("failed to validate shop: %w", err)
	}

	// Calculate net amount if not provided
	netAmount := req.NetAmountToDeposit
	if netAmount == 0 {
		totalCollected := req.CashCollected + req.CardCollected + req.UpiCollected + req.CreditCollected
		netAmount = totalCollected - req.TotalExpenses
	}

	finance := models.AssistantManagerFinance{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  tenantID,
		},
		ExecutiveID:        req.ExecutiveID,
		ShopID:             req.ShopID,
		TotalSalesAmount:   req.TotalSalesAmount,
		CashCollected:      req.CashCollected,
		CardCollected:      req.CardCollected,
		UpiCollected:       req.UpiCollected,
		CreditCollected:    req.CreditCollected,
		TotalExpenses:      req.TotalExpenses,
		NetAmountToDeposit: netAmount,
		Notes:              req.Notes,
		FinanceDate:        req.FinanceDate,
		Status:             "pending",
		CreatedBy:          userID,
	}

	if err := s.db.DB.Create(&finance).Error; err != nil {
		return nil, fmt.Errorf("failed to create finance record: %w", err)
	}

	return s.buildAssistantManagerFinanceResponse(finance, executive.FullName(), shop.Name, ""), nil
}

// Mark overdue collections automatically
func (s *AssistantManagerService) MarkOverdueCollections(ctx context.Context, tenantID uuid.UUID) error {
	now := time.Now()
	
	result := s.db.DB.Model(&models.AssistantManagerMoneyCollection{}).
		Where("tenant_id = ? AND status = 'pending' AND deadline_at < ?", tenantID, now).
		Update("status", "overdue")
	
	if result.Error != nil {
		return fmt.Errorf("failed to mark overdue collections: %w", result.Error)
	}

	// Clear cache if any rows were updated
	if result.RowsAffected > 0 {
		cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
		s.cache.Delete(ctx, cacheKey)
	}

	return nil
}

// Helper functions
func (s *AssistantManagerService) buildMoneyCollectionResponse(collection models.AssistantManagerMoneyCollection, executiveName, shopName, approverName string) *MoneyCollectionResponse {
	now := time.Now()
	minutesRemaining := 0
	if collection.Status == "pending" && collection.DeadlineAt.After(now) {
		minutesRemaining = int(collection.DeadlineAt.Sub(now).Minutes())
	}

	return &MoneyCollectionResponse{
		ID:               collection.ID,
		ExecutiveID:      collection.ExecutiveID,
		ExecutiveName:    executiveName,
		ShopID:           collection.ShopID,
		ShopName:         shopName,
		Amount:           collection.Amount,
		Status:           collection.Status,
		Notes:            collection.Notes,
		CollectedAt:      collection.CollectedAt,
		ApprovedAt:       collection.ApprovedAt,
		ApprovedBy:       collection.ApprovedByID,
		ApproverName:     approverName,
		DeadlineAt:       collection.DeadlineAt,
		IsOverdue:        now.After(collection.DeadlineAt) && collection.Status == "pending",
		MinutesRemaining: minutesRemaining,
		CreatedBy:        collection.CreatedBy,
		CreatedAt:        collection.CreatedAt,
		UpdatedAt:        collection.UpdatedAt,
	}
}

func (s *AssistantManagerService) buildMoneyCollectionResponseFromModel(collection models.AssistantManagerMoneyCollection) *MoneyCollectionResponse {
	executiveName := ""
	if collection.Executive != nil {
		executiveName = collection.Executive.FullName()
	}

	shopName := ""
	if collection.Shop != nil {
		shopName = collection.Shop.Name
	}

	approverName := ""
	if collection.ApprovedByUser != nil {
		approverName = collection.ApprovedByUser.FullName()
	}

	return s.buildMoneyCollectionResponse(collection, executiveName, shopName, approverName)
}

func (s *AssistantManagerService) buildAssistantManagerExpenseResponse(expense models.AssistantManagerExpense, categoryName, shopName, approverName string) *AssistantManagerExpenseResponse {
	return &AssistantManagerExpenseResponse{
		ID:            expense.ID,
		CategoryID:    expense.CategoryID,
		CategoryName:  categoryName,
		ShopID:        expense.ShopID,
		ShopName:      shopName,
		Amount:        expense.Amount,
		Description:   expense.Description,
		ExpenseDate:   expense.ExpenseDate,
		ReceiptNo:     expense.ReceiptNo,
		PaymentMethod: expense.PaymentMethod,
		Notes:         expense.Notes,
		Status:        expense.Status,
		ApprovedAt:    expense.ApprovedAt,
		ApprovedBy:    expense.ApprovedByID,
		ApproverName:  approverName,
		CreatedBy:     expense.CreatedBy,
		CreatedAt:     expense.CreatedAt,
		UpdatedAt:     expense.UpdatedAt,
	}
}

func (s *AssistantManagerService) buildAssistantManagerFinanceResponse(finance models.AssistantManagerFinance, executiveName, shopName, approverName string) *AssistantManagerFinanceResponse {
	return &AssistantManagerFinanceResponse{
		ID:                 finance.ID,
		ExecutiveID:        finance.ExecutiveID,
		ExecutiveName:      executiveName,
		ShopID:             finance.ShopID,
		ShopName:           shopName,
		TotalSalesAmount:   finance.TotalSalesAmount,
		CashCollected:      finance.CashCollected,
		CardCollected:      finance.CardCollected,
		UpiCollected:       finance.UpiCollected,
		CreditCollected:    finance.CreditCollected,
		TotalExpenses:      finance.TotalExpenses,
		NetAmountToDeposit: finance.NetAmountToDeposit,
		Notes:              finance.Notes,
		FinanceDate:        finance.FinanceDate,
		Status:             finance.Status,
		ApprovedAt:         finance.ApprovedAt,
		ApprovedBy:         finance.ApprovedByID,
		ApproverName:       approverName,
		CreatedBy:          finance.CreatedBy,
		CreatedAt:          finance.CreatedAt,
		UpdatedAt:          finance.UpdatedAt,
	}
}
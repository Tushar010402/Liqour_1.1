package services

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	notifservices "github.com/liquorpro/go-backend/internal/notifications/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

type AssistantManagerService struct {
	db                   *database.DB
	cache                *cache.Cache
	workflowNotification *notifservices.WorkflowNotificationService
}

func NewAssistantManagerService(db *database.DB, cache *cache.Cache) *AssistantManagerService {
	return &AssistantManagerService{
		db:    db,
		cache: cache,
	}
}

// SetWorkflowNotificationService sets the workflow notification service
func (s *AssistantManagerService) SetWorkflowNotificationService(wn *notifservices.WorkflowNotificationService) {
	s.workflowNotification = wn
}

// Default deadline for collection approval (configurable per tenant via tenant_settings)
const DEFAULT_APPROVAL_DEADLINE_MINUTES = 15

// GetDeadlineMinutes returns the configured deadline for a tenant
func (s *AssistantManagerService) GetDeadlineMinutes(tenantID uuid.UUID) int {
	if tenantID == uuid.Nil {
		return DEFAULT_APPROVAL_DEADLINE_MINUTES // Default for saas_admin
	}

	var settings models.TenantSettings
	if err := s.db.DB.Where("tenant_id = ?", tenantID).First(&settings).Error; err != nil {
		return DEFAULT_APPROVAL_DEADLINE_MINUTES // Default if not found
	}
	return settings.MoneyCollectionDeadlineMinutes
}

// GetTenantSettings retrieves tenant settings
func (s *AssistantManagerService) GetTenantSettings(ctx context.Context, tenantID uuid.UUID) (*models.TenantSettings, error) {
	var settings models.TenantSettings

	if tenantID == uuid.Nil {
		return nil, fmt.Errorf("tenant ID required")
	}

	if err := s.db.DB.Where("tenant_id = ?", tenantID).First(&settings).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			// Create default settings
			settings = models.TenantSettings{
				ID:                             uuid.New(),
				TenantID:                       tenantID,
				MoneyCollectionDeadlineMinutes: DEFAULT_APPROVAL_DEADLINE_MINUTES,
			}
			if err := s.db.DB.Create(&settings).Error; err != nil {
				return nil, fmt.Errorf("failed to create default settings: %w", err)
			}
		} else {
			return nil, fmt.Errorf("failed to get tenant settings: %w", err)
		}
	}

	return &settings, nil
}

// UpdateTenantSettings updates the deadline configuration
func (s *AssistantManagerService) UpdateTenantSettings(ctx context.Context, tenantID uuid.UUID, deadlineMinutes int) (*models.TenantSettings, error) {
	if tenantID == uuid.Nil {
		return nil, fmt.Errorf("tenant ID required")
	}

	var settings models.TenantSettings
	if err := s.db.DB.Where("tenant_id = ?", tenantID).First(&settings).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			// Create new settings
			settings = models.TenantSettings{
				ID:                             uuid.New(),
				TenantID:                       tenantID,
				MoneyCollectionDeadlineMinutes: deadlineMinutes,
			}
			if err := s.db.DB.Create(&settings).Error; err != nil {
				return nil, fmt.Errorf("failed to create settings: %w", err)
			}
		} else {
			return nil, fmt.Errorf("failed to get tenant settings: %w", err)
		}
	} else {
		// Update existing settings
		if err := s.db.DB.Model(&settings).Update("money_collection_deadline_minutes", deadlineMinutes).Error; err != nil {
			return nil, fmt.Errorf("failed to update settings: %w", err)
		}
		settings.MoneyCollectionDeadlineMinutes = deadlineMinutes
	}

	return &settings, nil
}

type MoneyCollectionRequest struct {
	RequestedFromUserID uuid.UUID  `json:"requested_from_user_id"` // Target user (who we're requesting FROM) - preferred field
	ExecutiveID         uuid.UUID  `json:"executive_id"`           // Deprecated, kept for backward compatibility
	ShopID              *uuid.UUID `json:"shop_id,omitempty"`
	Amount              float64    `json:"amount" binding:"required,gt=0"`
	Notes               string     `json:"notes"`
}

type MoneyCollectionResponse struct {
	ID                  uuid.UUID `json:"id"`
	ExecutiveID         uuid.UUID `json:"executive_id"`
	ExecutiveName       string    `json:"executive_name"`
	RequestedFromUserID string    `json:"requested_from_user_id"` // Target user (who is being requested FROM) - string for Flutter compatibility
	RequestedFromName   string    `json:"requested_from_name"`    // Target user's name
	RequesterID         uuid.UUID `json:"requester_id"`           // Who created the request (same as created_by)
	RequesterName       string    `json:"requester_name"`         // Requester's name
	ShopID              string    `json:"shop_id"`
	ShopName            string    `json:"shop_name"`
	Amount              float64   `json:"amount"`
	Status              string    `json:"status"`
	Notes               string    `json:"notes"`
	CollectedAt         time.Time `json:"collected_at"`
	ApprovedAt          string    `json:"approved_at"`
	ApprovedBy          string    `json:"approved_by"`
	ApproverName        string    `json:"approver_name"`
	DeadlineAt          time.Time `json:"deadline_at"`
	IsOverdue           bool      `json:"is_overdue"`
	MinutesRemaining    int       `json:"minutes_remaining"`
	CreatedBy           uuid.UUID `json:"created_by"`
	CreatedAt           time.Time `json:"created_at"`
	UpdatedAt           time.Time `json:"updated_at"`
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
	Description   string     `json:"description"`
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
	ExecutiveID        uuid.UUID `json:"executive_id" binding:"required"`
	ShopID             uuid.UUID `json:"shop_id" binding:"required"`
	TotalSalesAmount   float64   `json:"total_sales_amount" binding:"required,gte=0"`
	CashCollected      float64   `json:"cash_collected" binding:"required,gte=0"`
	CardCollected      float64   `json:"card_collected" binding:"required,gte=0"`
	UpiCollected       float64   `json:"upi_collected" binding:"required,gte=0"`
	CreditCollected    float64   `json:"credit_collected" binding:"required,gte=0"`
	TotalExpenses      float64   `json:"total_expenses" binding:"required,gte=0"`
	NetAmountToDeposit float64   `json:"net_amount_to_deposit"`
	Notes              string    `json:"notes"`
	FinanceDate        time.Time `json:"finance_date" binding:"required"`
}

type AssistantManagerFinanceResponse struct {
	ID                 uuid.UUID  `json:"id"`
	ExecutiveID        uuid.UUID  `json:"executive_id"`
	ExecutiveName      string     `json:"executive_name"`
	ShopID             uuid.UUID  `json:"shop_id"`
	ShopName           string     `json:"shop_name"`
	TotalSalesAmount   float64    `json:"total_sales_amount"`
	CashCollected      float64    `json:"cash_collected"`
	CardCollected      float64    `json:"card_collected"`
	UpiCollected       float64    `json:"upi_collected"`
	CreditCollected    float64    `json:"credit_collected"`
	TotalExpenses      float64    `json:"total_expenses"`
	NetAmountToDeposit float64    `json:"net_amount_to_deposit"`
	Notes              string     `json:"notes"`
	FinanceDate        time.Time  `json:"finance_date"`
	Status             string     `json:"status"`
	ApprovedAt         *time.Time `json:"approved_at"`
	ApprovedBy         *uuid.UUID `json:"approved_by"`
	ApproverName       string     `json:"approver_name,omitempty"`
	CreatedBy          uuid.UUID  `json:"created_by"`
	CreatedAt          time.Time  `json:"created_at"`
	UpdatedAt          time.Time  `json:"updated_at"`
}

// Money Collection Operations (Configurable approval deadline)
// CreateMoneyCollection creates a UPI-like cash request from current user to another user
func (s *AssistantManagerService) CreateMoneyCollection(ctx context.Context, req MoneyCollectionRequest, tenantID, userID uuid.UUID) (*MoneyCollectionResponse, error) {
	// Determine target user (who we're requesting FROM)
	// Prefer RequestedFromUserID, fall back to ExecutiveID for backward compatibility
	requestedFromID := req.RequestedFromUserID
	if requestedFromID == uuid.Nil && req.ExecutiveID != uuid.Nil {
		requestedFromID = req.ExecutiveID
	}
	if requestedFromID == uuid.Nil {
		return nil, fmt.Errorf("requested_from_user_id is required (specify who to request cash from)")
	}

	// Prevent self-request
	if requestedFromID == userID {
		return nil, fmt.Errorf("cannot request cash from yourself")
	}

	// Validate target user exists in the same tenant
	var targetUser models.User
	targetQuery := s.db.DB.Where("id = ? AND deleted_at IS NULL", requestedFromID)
	if tenantID != uuid.Nil {
		targetQuery = targetQuery.Where("tenant_id = ?", tenantID)
	}
	if err := targetQuery.First(&targetUser).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("target user not found in tenant")
		}
		return nil, fmt.Errorf("failed to validate target user: %w", err)
	}

	// Get requester info for response
	var requesterUser models.User
	if err := s.db.DB.Where("id = ?", userID).First(&requesterUser).Error; err != nil {
		return nil, fmt.Errorf("failed to get requester info: %w", err)
	}

	// Validate shop if provided (optional)
	var shopName string
	if req.ShopID != nil {
		var shop models.Shop
		shopQuery := s.db.DB.Where("id = ?", req.ShopID)
		if tenantID != uuid.Nil {
			shopQuery = shopQuery.Where("tenant_id = ?", tenantID)
		}
		if err := shopQuery.First(&shop).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				return nil, fmt.Errorf("shop not found")
			}
			return nil, fmt.Errorf("failed to validate shop: %w", err)
		}
		shopName = shop.Name
	}

	// Get configurable deadline for this tenant
	deadlineMinutes := s.GetDeadlineMinutes(tenantID)
	now := time.Now()
	deadlineAt := now.Add(time.Duration(deadlineMinutes) * time.Minute)

	collection := models.AssistantManagerMoneyCollection{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		ExecutiveID:         requestedFromID, // Keep for backward compatibility
		RequestedFromUserID: &requestedFromID,
		ShopID:              req.ShopID,
		Amount:              req.Amount,
		Status:              "pending",
		Notes:               req.Notes,
		CollectionDate:      now,
		CollectionType:      "cash_request",
		CollectedAt:         now,
		SubmittedAt:         now,
		DeadlineAt:          deadlineAt,
		CreatedBy:           userID,
	}

	if err := s.db.DB.Create(&collection).Error; err != nil {
		return nil, fmt.Errorf("failed to create money collection: %w", err)
	}

	// Clear cache
	cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	return s.buildMoneyCollectionResponseWithNames(collection, targetUser.FullName(), shopName, "", requesterUser.FullName()), nil
}

// GetMoneyCollections retrieves money collections with user-specific filtering
// filter: "sent" (requests I created), "received" (requests targeting me), "all" (admin view)
// userID: current user for filtering (required for sent/received filters)
func (s *AssistantManagerService) GetMoneyCollections(ctx context.Context, tenantID uuid.UUID, filter string, userID uuid.UUID, status string, includeOverdue bool, limit, offset int) ([]MoneyCollectionResponse, int64, error) {
	var collections []models.AssistantManagerMoneyCollection
	var total int64

	// Build query - if tenantID is uuid.Nil (saas_admin), don't filter by tenant
	// Always filter out soft-deleted records
	query := s.db.DB.Where("deleted_at IS NULL")
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	// Apply user-specific filtering based on filter type
	switch filter {
	case "sent", "outgoing":
		// Requests I created (I am requesting FROM someone)
		if userID != uuid.Nil {
			query = query.Where("created_by = ?", userID)
		}
	case "received", "incoming":
		// Requests where I am the target (someone is requesting FROM me)
		if userID != uuid.Nil {
			// Check both requested_from_user_id and executive_id for backward compatibility
			query = query.Where("requested_from_user_id = ? OR (requested_from_user_id IS NULL AND executive_id = ?)", userID, userID)
		}
	case "all":
		// All requests (admin view) - no user filter
	default:
		// Default: show requests involving current user (either as requester or target)
		if userID != uuid.Nil {
			query = query.Where("created_by = ? OR requested_from_user_id = ? OR executive_id = ?", userID, userID, userID)
		}
	}

	if status != "" && status != "all" {
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
		Preload("RejectedByUser").
		Preload("RequestedFromUser").
		Preload("CreatedByUser").
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

	// Build query with soft delete filter
	query := s.db.DB.Where("id = ?", id).Where("deleted_at IS NULL")

	// Only filter by tenant if not saas_admin
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	if err := query.
		Preload("Executive").
		Preload("Shop").
		Preload("ApprovedByUser").
		Preload("RejectedByUser").
		First(&collection).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("money collection not found")
		}
		return nil, fmt.Errorf("failed to get collection: %w", err)
	}

	return s.buildMoneyCollectionResponseFromModel(collection), nil
}

// updateCashHolding updates a user's cash balance and creates an audit trail transaction
func (s *AssistantManagerService) updateCashHolding(tx *gorm.DB, tenantID, userID uuid.UUID, amount float64, refID uuid.UUID, transactionType, description string, counterpartyID *uuid.UUID, createdByID uuid.UUID) error {
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

	// Create audit transaction (matching existing cash_transactions table schema)
	absAmount := amount
	if amount < 0 {
		absAmount = -amount
	}

	transaction := models.CashTransaction{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		UserID:          userID,
		TransactionType: transactionType,
		Amount:          absAmount,
		BalanceBefore:   previousBalance,
		BalanceAfter:    newBalance,
		RelatedType:     "money_collection",
		RelatedID:       &refID,
		Notes:           description,
		TransactionDate: time.Now(),
	}

	return tx.Create(&transaction).Error
}

func (s *AssistantManagerService) ApproveMoneyCollection(ctx context.Context, id, tenantID, userID uuid.UUID) error {
	// Use transaction with row lock to prevent race conditions
	return s.db.DB.Transaction(func(tx *gorm.DB) error {
		var collection models.AssistantManagerMoneyCollection

		// Build query with row lock (FOR UPDATE)
		query := tx.Set("gorm:query_option", "FOR UPDATE").Where("id = ?", id).Where("deleted_at IS NULL")
		if tenantID != uuid.Nil {
			query = query.Where("tenant_id = ?", tenantID)
		}

		if err := query.First(&collection).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				return fmt.Errorf("money collection not found")
			}
			return fmt.Errorf("failed to get collection: %w", err)
		}

		if collection.Status != "pending" {
			return fmt.Errorf("collection is not pending (current status: %s)", collection.Status)
		}

		// Check if deadline has passed
		now := time.Now()
		if now.After(collection.DeadlineAt) {
			// Atomically mark as overdue
			if err := tx.Model(&collection).Updates(map[string]interface{}{
				"status": "overdue",
			}).Error; err != nil {
				return fmt.Errorf("failed to mark as overdue: %w", err)
			}
			return fmt.Errorf("collection deadline has passed - marked as overdue")
		}

		// Approve collection atomically
		if err := tx.Model(&collection).Updates(map[string]interface{}{
			"status":      "approved",
			"approved_at": &now,
			"approved_by": &userID,
		}).Error; err != nil {
			return fmt.Errorf("failed to approve collection: %w", err)
		}

		// Update cash holdings for both parties
		requesterID := collection.CreatedBy
		targetID := collection.RequestedFromUserID
		if targetID == nil {
			targetID = &collection.ExecutiveID // Backward compatibility
		}

		// Lock cash_holdings rows for both users to prevent race conditions on concurrent approvals
		userIDs := []uuid.UUID{requesterID}
		if targetID != nil && *targetID != uuid.Nil {
			userIDs = append(userIDs, *targetID)
		}
		var holdingsLock []models.CashHolding
		if err := tx.Set("gorm:query_option", "FOR UPDATE").
			Where("user_id IN ? AND tenant_id = ?", userIDs, tenantID).
			Find(&holdingsLock).Error; err != nil && err != gorm.ErrRecordNotFound {
			return fmt.Errorf("failed to lock cash holdings: %w", err)
		}

		// Debit from target (person being requested FROM) - their cash decreases
		if targetID != nil && *targetID != uuid.Nil {
			if err := s.updateCashHolding(tx, tenantID, *targetID, -collection.Amount, collection.ID,
				"collection_sent", fmt.Sprintf("Cash sent via request #%s", collection.ID.String()[:8]), &requesterID, userID); err != nil {
				return fmt.Errorf("failed to debit target: %w", err)
			}
		}

		// Credit to requester (person who requested) - their cash increases
		if err := s.updateCashHolding(tx, tenantID, requesterID, collection.Amount, collection.ID,
			"collection_received", fmt.Sprintf("Cash received via request #%s", collection.ID.String()[:8]), targetID, userID); err != nil {
			return fmt.Errorf("failed to credit requester: %w", err)
		}

		// Clear cache after successful transaction
		cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
		s.cache.Delete(ctx, cacheKey)

		// Send notification to requester about approval
		if s.workflowNotification != nil {
			// Get approver name
			var approver models.User
			if err := tx.First(&approver, "id = ?", userID).Error; err == nil {
				go func() {
					if err := s.workflowNotification.NotifyMoneyCollectionApproved(
						context.Background(), tenantID, requesterID, userID,
						collection.Amount, approver.FullName(),
					); err != nil {
						// Log error but don't fail the transaction
					}
				}()
			}
		}

		return nil
	})
}

func (s *AssistantManagerService) RejectMoneyCollection(ctx context.Context, id, tenantID, userID uuid.UUID, reason string) error {
	// Use transaction with row lock to prevent race conditions
	return s.db.DB.Transaction(func(tx *gorm.DB) error {
		var collection models.AssistantManagerMoneyCollection

		// Build query with row lock (FOR UPDATE)
		query := tx.Set("gorm:query_option", "FOR UPDATE").Where("id = ?", id).Where("deleted_at IS NULL")
		if tenantID != uuid.Nil {
			query = query.Where("tenant_id = ?", tenantID)
		}

		if err := query.First(&collection).Error; err != nil {
			if err == gorm.ErrRecordNotFound {
				return fmt.Errorf("money collection not found")
			}
			return fmt.Errorf("failed to get collection: %w", err)
		}

		if collection.Status != "pending" {
			return fmt.Errorf("collection is not pending (current status: %s)", collection.Status)
		}

		now := time.Now()

		// Use proper rejection fields (not approved_at/approved_by)
		if err := tx.Model(&collection).Updates(map[string]interface{}{
			"status":           "rejected",
			"rejected_at":      &now,
			"rejected_by_id":   &userID,
			"rejection_reason": reason,
		}).Error; err != nil {
			return fmt.Errorf("failed to reject collection: %w", err)
		}

		// Clear cache after successful transaction
		cacheKey := fmt.Sprintf("collections:tenant:%s", tenantID.String())
		s.cache.Delete(ctx, cacheKey)

		// Send notification to requester about rejection
		if s.workflowNotification != nil {
			// Get rejector name
			var rejector models.User
			if err := tx.First(&rejector, "id = ?", userID).Error; err == nil {
				go func() {
					if err := s.workflowNotification.NotifyMoneyCollectionRejected(
						context.Background(), tenantID, collection.CreatedBy, userID,
						collection.Amount, rejector.FullName(), reason,
					); err != nil {
						// Log error but don't fail the transaction
					}
				}()
			}
		}

		return nil
	})
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
			TenantID:  &tenantID,
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
			TenantID:  &tenantID,
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

// MarkOverdueCollections marks overdue collections for a specific tenant
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

// MarkAllOverdueCollections marks overdue collections for ALL tenants
// Used by the auto-expiry scheduler
func (s *AssistantManagerService) MarkAllOverdueCollections(ctx context.Context) (int64, error) {
	now := time.Now()

	result := s.db.DB.Model(&models.AssistantManagerMoneyCollection{}).
		Where("status = 'pending' AND deadline_at < ? AND deleted_at IS NULL", now).
		Update("status", "overdue")

	if result.Error != nil {
		return 0, fmt.Errorf("failed to mark overdue collections: %w", result.Error)
	}

	return result.RowsAffected, nil
}

// GetAssistantManagerExpenses retrieves expenses created by assistant managers
func (s *AssistantManagerService) GetAssistantManagerExpenses(ctx context.Context, tenantID uuid.UUID, limit, offset int) ([]AssistantManagerExpenseResponse, int64, error) {
	var expenses []models.AssistantManagerExpense
	var total int64

	query := s.db.DB.Where("deleted_at IS NULL")
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	if err := query.Model(&models.AssistantManagerExpense{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count expenses: %w", err)
	}

	if err := query.Preload("Category").Preload("Shop").Preload("ApprovedBy").Preload("AssistantManager").
		Order("created_at DESC").
		Limit(limit).Offset(offset).
		Find(&expenses).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get expenses: %w", err)
	}

	var responses []AssistantManagerExpenseResponse
	for _, e := range expenses {
		categoryName := ""
		if e.Category != nil {
			categoryName = e.Category.Name
		}
		shopName := ""
		if e.Shop != nil {
			shopName = e.Shop.Name
		}
		approverName := ""
		if e.ApprovedBy != nil {
			approverName = e.ApprovedBy.FullName()
		}
		responses = append(responses, *s.buildAssistantManagerExpenseResponse(e, categoryName, shopName, approverName))
	}

	return responses, total, nil
}

// GetAssistantManagerFinanceRecords retrieves finance records
func (s *AssistantManagerService) GetAssistantManagerFinanceRecords(ctx context.Context, tenantID uuid.UUID, limit, offset int) ([]AssistantManagerFinanceResponse, int64, error) {
	var records []models.AssistantManagerFinance
	var total int64

	query := s.db.DB.Where("deleted_at IS NULL")
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	if err := query.Model(&models.AssistantManagerFinance{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count records: %w", err)
	}

	if err := query.Preload("Executive").Preload("Shop").Preload("ApprovedBy").Preload("AssistantManager").
		Order("created_at DESC").
		Limit(limit).Offset(offset).
		Find(&records).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to get records: %w", err)
	}

	var responses []AssistantManagerFinanceResponse
	for _, r := range records {
		executiveName := ""
		if r.Executive != nil {
			executiveName = r.Executive.FullName()
		}
		shopName := ""
		if r.Shop != nil {
			shopName = r.Shop.Name
		}
		approverName := ""
		if r.ApprovedBy != nil {
			approverName = r.ApprovedBy.FullName()
		}
		responses = append(responses, *s.buildAssistantManagerFinanceResponse(r, executiveName, shopName, approverName))
	}

	return responses, total, nil
}

// Helper functions

// buildMoneyCollectionResponseWithNames builds response with all user names provided
func (s *AssistantManagerService) buildMoneyCollectionResponseWithNames(collection models.AssistantManagerMoneyCollection, targetUserName, shopName, approverName, requesterName string) *MoneyCollectionResponse {
	now := time.Now()
	minutesRemaining := 0
	if collection.Status == "pending" && collection.DeadlineAt.After(now) {
		minutesRemaining = int(collection.DeadlineAt.Sub(now).Minutes())
	}

	// Convert *uuid.UUID to string (empty string if nil) for Flutter compatibility
	shopIDStr := ""
	if collection.ShopID != nil {
		shopIDStr = collection.ShopID.String()
	}

	approvedByStr := ""
	if collection.ApprovedByID != nil {
		approvedByStr = collection.ApprovedByID.String()
	}

	approvedAtStr := ""
	if collection.ApprovedAt != nil {
		approvedAtStr = collection.ApprovedAt.Format(time.RFC3339)
	}

	// Convert RequestedFromUserID pointer to string for Flutter compatibility
	requestedFromUserIDStr := ""
	if collection.RequestedFromUserID != nil {
		requestedFromUserIDStr = collection.RequestedFromUserID.String()
	}

	return &MoneyCollectionResponse{
		ID:                  collection.ID,
		ExecutiveID:         collection.ExecutiveID,
		ExecutiveName:       targetUserName, // For backward compatibility
		RequestedFromUserID: requestedFromUserIDStr,
		RequestedFromName:   targetUserName,
		RequesterID:         collection.CreatedBy,
		RequesterName:       requesterName,
		ShopID:              shopIDStr,
		ShopName:            shopName,
		Amount:              collection.Amount,
		Status:              collection.Status,
		Notes:               collection.Notes,
		CollectedAt:         collection.CollectedAt,
		ApprovedAt:          approvedAtStr,
		ApprovedBy:          approvedByStr,
		ApproverName:        approverName,
		DeadlineAt:          collection.DeadlineAt,
		IsOverdue:           now.After(collection.DeadlineAt) && collection.Status == "pending",
		MinutesRemaining:    minutesRemaining,
		CreatedBy:           collection.CreatedBy,
		CreatedAt:           collection.CreatedAt,
		UpdatedAt:           collection.UpdatedAt,
	}
}

// buildMoneyCollectionResponse is kept for backward compatibility
func (s *AssistantManagerService) buildMoneyCollectionResponse(collection models.AssistantManagerMoneyCollection, executiveName, shopName, approverName string) *MoneyCollectionResponse {
	return s.buildMoneyCollectionResponseWithNames(collection, executiveName, shopName, approverName, "")
}

func (s *AssistantManagerService) buildMoneyCollectionResponseFromModel(collection models.AssistantManagerMoneyCollection) *MoneyCollectionResponse {
	// Get target user name (who is being requested FROM)
	targetUserName := ""
	if collection.RequestedFromUser != nil {
		targetUserName = collection.RequestedFromUser.FullName()
	} else if collection.Executive != nil {
		targetUserName = collection.Executive.FullName() // Backward compatibility
	}

	shopName := ""
	if collection.Shop != nil {
		shopName = collection.Shop.Name
	}

	approverName := ""
	if collection.ApprovedByUser != nil {
		approverName = collection.ApprovedByUser.FullName()
	}

	// Get requester name (who created the request)
	requesterName := ""
	if collection.CreatedByUser != nil {
		requesterName = collection.CreatedByUser.FullName()
	}

	return s.buildMoneyCollectionResponseWithNames(collection, targetUserName, shopName, approverName, requesterName)
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

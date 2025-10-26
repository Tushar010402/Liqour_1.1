package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// CashService handles all cash management operations
type CashService struct {
	db *database.DB
}

// NewCashService creates a new cash service instance
func NewCashService(db *database.DB) *CashService {
	return &CashService{db: db}
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Holdings Management
// ═══════════════════════════════════════════════════════════════════════════

// GetCashBalance returns current cash balance for a user
// If shopID is uuid.Nil, returns total balance across ALL shops (user-specific)
// If shopID is provided, returns balance for that specific shop (backward compatible)
func (s *CashService) GetCashBalance(ctx context.Context, userID, shopID, tenantID uuid.UUID) (float64, error) {
	// If shopID is Nil, sum balances across ALL shops (user-specific balance)
	if shopID == uuid.Nil {
		var totalBalance float64
		err := s.db.DB.WithContext(ctx).
			Model(&models.CashHolding{}).
			Where("user_id = ? AND tenant_id = ?", userID, tenantID).
			Select("COALESCE(SUM(current_balance), 0)").
			Scan(&totalBalance).Error

		if err != nil {
			return 0, fmt.Errorf("failed to get total cash balance: %w", err)
		}

		log.Printf("💰 [GetCashBalance] User %s total balance across all shops: %.2f", userID, totalBalance)
		return totalBalance, nil
	}

	// Shop-specific balance (backward compatible)
	var holding models.CashHolding
	err := s.db.DB.WithContext(ctx).
		Where("user_id = ? AND shop_id = ? AND tenant_id = ?", userID, shopID, tenantID).
		First(&holding).Error

	if err == gorm.ErrRecordNotFound {
		return 0, nil // No holding means zero balance
	}
	if err != nil {
		return 0, fmt.Errorf("failed to get cash balance: %w", err)
	}

	return holding.CurrentBalance, nil
}

// GetCashHolding returns the complete cash holding record
func (s *CashService) GetCashHolding(ctx context.Context, userID, shopID, tenantID uuid.UUID) (*models.CashHolding, error) {
	var holding models.CashHolding
	err := s.db.DB.WithContext(ctx).
		Preload("User").
		Preload("Shop").
		Where("user_id = ? AND shop_id = ? AND tenant_id = ?", userID, shopID, tenantID).
		First(&holding).Error

	if err == gorm.ErrRecordNotFound {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get cash holding: %w", err)
	}

	return &holding, nil
}

// GetTeamCashBalances returns AGGREGATED cash balances for all subordinates (user-specific, not shop-specific)
// Returns total balance per user (sum across all shops)
func (s *CashService) GetTeamCashBalances(ctx context.Context, userID, shopID, tenantID uuid.UUID) ([]models.CashHolding, error) {
	// Get current user's role to determine subordinates
	var currentUser models.User
	err := s.db.DB.WithContext(ctx).
		Where("id = ? AND tenant_id = ?", userID, tenantID).
		First(&currentUser).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get current user: %w", err)
	}

	// Define role hierarchy (higher index = lower in hierarchy)
	roleHierarchy := map[string]int{
		"admin":             1,
		"manager":           2,
		"assistant_manager": 3,
		"executive":         4,
		"salesman":          5,
	}

	currentRoleLevel, exists := roleHierarchy[currentUser.Role]
	if !exists {
		return nil, fmt.Errorf("unknown role: %s", currentUser.Role)
	}

	// Determine subordinate roles (roles with higher level numbers)
	subordinateRoles := []string{}
	for role, level := range roleHierarchy {
		if level > currentRoleLevel {
			subordinateRoles = append(subordinateRoles, role)
		}
	}

	// If no subordinate roles (e.g., salesman), return empty list
	if len(subordinateRoles) == 0 {
		return []models.CashHolding{}, nil
	}

	// Struct to hold aggregated balance data
	type AggregatedBalance struct {
		UserID         uuid.UUID `gorm:"column:user_id"`
		TotalBalance   float64   `gorm:"column:total_balance"`
		LastUpdatedAt  time.Time `gorm:"column:last_updated_at"`
	}

	// Query to aggregate balances by user (GROUP BY user_id, SUM balances)
	var aggregatedBalances []AggregatedBalance
	query := s.db.DB.WithContext(ctx).
		Table("cash_holdings").
		Select(`
			cash_holdings.user_id,
			SUM(cash_holdings.current_balance) as total_balance,
			MAX(cash_holdings.last_updated_at) as last_updated_at
		`).
		Joins("JOIN users ON users.id = cash_holdings.user_id").
		Where("cash_holdings.tenant_id = ?", tenantID).
		Where("cash_holdings.user_id != ?", userID).  // Exclude current user
		Where("users.role IN ?", subordinateRoles).   // Only subordinate roles
		Group("cash_holdings.user_id").
		Having("SUM(cash_holdings.current_balance) > 0").
		Order("total_balance DESC")

	err = query.Find(&aggregatedBalances).Error
	if err != nil {
		return nil, fmt.Errorf("failed to get aggregated team balances: %w", err)
	}

	// Transform aggregated results into CashHolding format expected by handler
	// We populate User info but leave Shop info empty since balances are user-specific now
	holdings := make([]models.CashHolding, 0, len(aggregatedBalances))
	for _, agg := range aggregatedBalances {
		// Fetch user details
		var user models.User
		err := s.db.DB.WithContext(ctx).Where("id = ?", agg.UserID).First(&user).Error
		if err != nil {
			log.Printf("⚠️ Warning: Could not load user %s: %v", agg.UserID, err)
			continue
		}

		holding := models.CashHolding{
			UserID:         agg.UserID,
			ShopID:         nil,  // No shop_id - this is user-aggregated balance
			CurrentBalance: agg.TotalBalance,
			LastUpdatedAt:  agg.LastUpdatedAt,
			User:           &user,
			Shop:           nil,  // No shop - balance is across all shops
		}
		holding.TenantID = &tenantID

		holdings = append(holdings, holding)
	}

	log.Printf("📊 [GetTeamCashBalances] User: %s (%s), Found %d subordinates with aggregated cash (user-specific)",
		currentUser.FullName(), currentUser.Role, len(holdings))

	return holdings, nil
}

// TenantUserInfo represents basic user info for cash requests (NO cash amounts shown)
type TenantUserInfo struct {
	UserID   uuid.UUID
	UserName string
	Role     string
	ShopID   *uuid.UUID
	ShopName *string
}

// GetTenantUsers returns tenant users for cash request selection (NO cash amounts shown)
// Maintains hierarchical privacy - users don't see cash holdings, just user list
func (s *CashService) GetTenantUsers(ctx context.Context, currentUserID, tenantID uuid.UUID, shopID *uuid.UUID) ([]TenantUserInfo, error) {
	query := s.db.DB.WithContext(ctx).
		Table("users").
		Select("users.id as user_id, CONCAT(users.first_name, ' ', users.last_name) as user_name, users.role, salesmen.shop_id, shops.name as shop_name").
		Joins("LEFT JOIN salesmen ON salesmen.user_id = users.id AND salesmen.tenant_id = users.tenant_id").
		Joins("LEFT JOIN shops ON shops.id = salesmen.shop_id").
		Where("users.tenant_id = ? AND users.id != ?", tenantID, currentUserID)

	// Optional shop filter
	if shopID != nil && *shopID != uuid.Nil {
		query = query.Where("salesmen.shop_id = ?", *shopID)
	}

	var results []struct {
		UserID   uuid.UUID  `gorm:"column:user_id"`
		UserName string     `gorm:"column:user_name"`
		Role     string     `gorm:"column:role"`
		ShopID   *uuid.UUID `gorm:"column:shop_id"`
		ShopName *string    `gorm:"column:shop_name"`
	}

	err := query.
		Order("CASE users.role WHEN 'admin' THEN 1 WHEN 'manager' THEN 2 WHEN 'assistant_manager' THEN 3 WHEN 'executive' THEN 4 WHEN 'salesman' THEN 5 END").
		Find(&results).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get tenant users: %w", err)
	}

	// Convert to TenantUserInfo
	users := make([]TenantUserInfo, len(results))
	for i, r := range results {
		users[i] = TenantUserInfo{
			UserID:   r.UserID,
			UserName: r.UserName,
			Role:     r.Role,
			ShopID:   r.ShopID,
			ShopName: r.ShopName,
		}
	}

	log.Printf("📊 [GetTenantUsers] Tenant: %s, Found %d users (NO cash amounts shown)", tenantID, len(users))

	return users, nil
}

// UpdateCashBalance updates or creates cash holding and creates audit trail
func (s *CashService) UpdateCashBalance(
	ctx context.Context,
	userID, shopID, tenantID uuid.UUID,
	amount float64,
	transactionType, description string,
	relatedEntityType string,
	relatedEntityID *uuid.UUID,
	createdByID uuid.UUID,
) error {
	return s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var holding models.CashHolding
		var err error

		// Special handling when shopID is Nil (NULL) - use user's total balance
		if shopID == uuid.Nil {
			log.Printf("💰 [UpdateCashBalance] NULL shop_id detected - using user's total balance")

			// For deductions (negative amounts), check total balance and deduct from largest holding
			if amount < 0 {
				// Get total balance across all holdings
				totalBalance, err := s.GetCashBalance(ctx, userID, uuid.Nil, tenantID)
				if err != nil {
					return fmt.Errorf("failed to get total balance: %w", err)
				}

				log.Printf("💰 [UpdateCashBalance] User total balance: %.2f, attempting to deduct: %.2f", totalBalance, -amount)

				if totalBalance+amount < 0 {
					return fmt.Errorf("insufficient cash balance: total %.2f, requested %.2f", totalBalance, -amount)
				}

				// Find the holding with the largest balance to deduct from
				err = tx.Where("user_id = ? AND tenant_id = ?", userID, tenantID).
					Order("current_balance DESC").
					First(&holding).Error

				if err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						return errors.New("no cash holdings found for user")
					}
					return fmt.Errorf("failed to find cash holding: %w", err)
				}

				log.Printf("💰 [UpdateCashBalance] Deducting from holding with shop_id: %v, balance: %.2f", holding.ShopID, holding.CurrentBalance)
			} else {
				// For additions (positive amounts), try to add to existing NULL shop_id holding or create one
				err = tx.Where("user_id = ? AND shop_id IS NULL AND tenant_id = ?", userID, tenantID).
					First(&holding).Error

				if err != nil {
					if errors.Is(err, gorm.ErrRecordNotFound) {
						// Create new cash holding with NULL shop_id
						holding = models.CashHolding{
							TenantModel: models.TenantModel{
								TenantID: &tenantID,
							},
							UserID:         userID,
							ShopID:         nil, // NULL shop_id
							CurrentBalance: 0,
							LastUpdatedAt:  time.Now(),
						}

						err = tx.Clauses(clause.OnConflict{
							Columns:   []clause.Column{{Name: "tenant_id"}, {Name: "user_id"}, {Name: "shop_id"}},
							DoNothing: true,
						}).Create(&holding).Error

						if err != nil {
							return fmt.Errorf("failed to create cash holding: %w", err)
						}

						// If conflict occurred, fetch the existing record
						if holding.ID == uuid.Nil {
							err = tx.Where("user_id = ? AND shop_id IS NULL AND tenant_id = ?", userID, tenantID).
								First(&holding).Error
							if err != nil {
								return fmt.Errorf("failed to fetch existing cash holding: %w", err)
							}
						}

						log.Printf("💰 [UpdateCashBalance] Created new holding with NULL shop_id for additions")
					} else {
						return fmt.Errorf("failed to get cash holding: %w", err)
					}
				}
			}
		} else {
			// Shop-specific logic (backward compatible)
			err = tx.Where("user_id = ? AND shop_id = ? AND tenant_id = ?", userID, shopID, tenantID).
				First(&holding).Error

			if err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					// Create new cash holding
					var shopIDPtr *uuid.UUID
					if shopID != uuid.Nil {
						shopIDPtr = &shopID
					}

					holding = models.CashHolding{
						TenantModel: models.TenantModel{
							TenantID: &tenantID,
						},
						UserID:         userID,
						ShopID:         shopIDPtr,
						CurrentBalance: 0,
						LastUpdatedAt:  time.Now(),
					}

					err = tx.Clauses(clause.OnConflict{
						Columns:   []clause.Column{{Name: "tenant_id"}, {Name: "user_id"}, {Name: "shop_id"}},
						DoNothing: true,
					}).Create(&holding).Error

					if err != nil {
						return fmt.Errorf("failed to create cash holding: %w", err)
					}

					// If conflict occurred (DoNothing), fetch the existing record
					if holding.ID == uuid.Nil {
						err = tx.Where("user_id = ? AND shop_id = ? AND tenant_id = ?", userID, shopID, tenantID).
							First(&holding).Error
						if err != nil {
							return fmt.Errorf("failed to fetch existing cash holding after conflict: %w", err)
						}
					}
				} else {
					return fmt.Errorf("failed to get cash holding: %w", err)
				}
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
			return fmt.Errorf("failed to update balance: %w", err)
		}

		// Create audit trail
		// Convert shopID to pointer (nil if uuid.Nil, otherwise pointer to value)
		var transactionShopIDPtr *uuid.UUID
		if shopID != uuid.Nil {
			transactionShopIDPtr = &shopID
		}

		transaction := &models.CashTransaction{
			TenantModel: models.TenantModel{
				TenantID: &tenantID,
			},
			UserID:            userID,
			ShopID:            transactionShopIDPtr,
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
			return fmt.Errorf("failed to create transaction record: %w", err)
		}

		log.Printf("✅ Cash updated: User %s, Shop %s, Amount: %.2f, New Balance: %.2f",
			userID, shopID, amount, newBalance)

		return nil
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Collection
// ═══════════════════════════════════════════════════════════════════════════

// CollectionRequest represents a cash collection request
type CollectionRequest struct {
	FromUserID uuid.UUID
	ToUserID   uuid.UUID
	ShopID     uuid.UUID
	TenantID   uuid.UUID
	Amount     float64
	Notes      string
}

// CollectCash creates a PENDING cash collection request with 10-minute expiration
func (s *CashService) CollectCash(ctx context.Context, req *CollectionRequest, createdByID uuid.UUID) (*models.CashCollection, error) {
	var collection *models.CashCollection

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch user details for descriptive audit trail
		var fromUser, toUser models.User
		if err := tx.Where("id = ?", req.FromUserID).First(&fromUser).Error; err != nil {
			return fmt.Errorf("failed to fetch from_user: %w", err)
		}
		if err := tx.Where("id = ?", req.ToUserID).First(&toUser).Error; err != nil {
			return fmt.Errorf("failed to fetch to_user: %w", err)
		}

		// 2. Validate hierarchy (TODO: implement role checking)

		// 3. Check sufficient balance (validation only, no balance change yet)
		balance, err := s.GetCashBalance(ctx, req.FromUserID, req.ShopID, req.TenantID)
		if err != nil {
			return fmt.Errorf("failed to check balance: %w", err)
		}
		if balance < req.Amount {
			return fmt.Errorf("insufficient balance: %s (%s) has %.2f, needs %.2f",
				fromUser.FullName(), fromUser.Role, balance, req.Amount)
		}

		// 4. Create PENDING collection request with 10-minute expiration
		now := time.Now().UTC() // CRITICAL: Use UTC for consistent timestamps
		expiresAt := now.Add(10 * time.Minute)

		collection = &models.CashCollection{
			TenantModel: models.TenantModel{
				TenantID: &req.TenantID,
			},
			FromUserID:     req.FromUserID,
			ToUserID:       req.ToUserID,
			ShopID:         req.ShopID,
			Amount:         req.Amount,
			CollectionDate: now,
			Notes:          req.Notes,
			Status:         "pending", // Pending approval
			ExpiresAt:      &expiresAt,
			CreatedByID:    createdByID,
		}

		if err := tx.Create(collection).Error; err != nil {
			return fmt.Errorf("failed to create collection request: %w", err)
		}

		log.Printf("📝 Collection request created: %.2f from %s (%s) to %s (%s), expires at %s",
			req.Amount, fromUser.FullName(), fromUser.Role, toUser.FullName(), toUser.Role, expiresAt.Format(time.RFC3339))

		return nil
	})

	if err != nil {
		return nil, err
	}

	return collection, nil
}

// ApproveCollection approves a pending collection request and updates balances
func (s *CashService) ApproveCollection(ctx context.Context, collectionID, approverID uuid.UUID) error {
	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch collection with user details
		var collection models.CashCollection
		if err := tx.Preload("FromUser").Preload("ToUser").Where("id = ?", collectionID).First(&collection).Error; err != nil {
			return fmt.Errorf("collection not found: %w", err)
		}

		// 2. Validate status
		if collection.Status != "pending" {
			return fmt.Errorf("collection is not pending (current status: %s)", collection.Status)
		}

		// 3. Check expiration
		now := time.Now().UTC()
		if collection.ExpiresAt != nil && now.After(*collection.ExpiresAt) {
			// Mark as expired
			collection.Status = "expired"
			if err := tx.Save(&collection).Error; err != nil {
				return fmt.Errorf("failed to mark as expired: %w", err)
			}
			return fmt.Errorf("collection request expired at %s", collection.ExpiresAt.Format(time.RFC3339))
		}

		// 4. Verify sufficient balance (may have changed since request)
		balance, err := s.GetCashBalance(ctx, collection.FromUserID, collection.ShopID, *collection.TenantID)
		if err != nil {
			return fmt.Errorf("failed to check balance: %w", err)
		}
		if balance < collection.Amount {
			return fmt.Errorf("insufficient balance: %s (%s) has %.2f, needs %.2f",
				collection.FromUser.FullName(), collection.FromUser.Role, balance, collection.Amount)
		}

		// 5. Update balances with descriptive audit trail
		// Deduct from source user
		fromDesc := fmt.Sprintf("Collected by %s (%s)", collection.ToUser.FullName(), collection.ToUser.Role)
		err = s.UpdateCashBalance(ctx, collection.FromUserID, collection.ShopID, *collection.TenantID,
			-collection.Amount, "collection_given", fromDesc, "collection", &collectionID, approverID)
		if err != nil {
			return fmt.Errorf("failed to deduct from source: %w", err)
		}

		// Add to destination user
		toDesc := fmt.Sprintf("Collected from %s (%s)", collection.FromUser.FullName(), collection.FromUser.Role)
		err = s.UpdateCashBalance(ctx, collection.ToUserID, collection.ShopID, *collection.TenantID,
			collection.Amount, "collection_received", toDesc, "collection", &collectionID, approverID)
		if err != nil {
			return fmt.Errorf("failed to add to destination: %w", err)
		}

		// 6. Mark collection as approved
		collection.Status = "approved"
		collection.ApprovedAt = &now
		collection.ApprovedByID = &approverID

		if err := tx.Save(&collection).Error; err != nil {
			return fmt.Errorf("failed to update collection status: %w", err)
		}

		log.Printf("✅ Collection approved: %.2f from %s (%s) to %s (%s) by approver %s",
			collection.Amount, collection.FromUser.FullName(), collection.FromUser.Role,
			collection.ToUser.FullName(), collection.ToUser.Role, approverID)

		return nil
	})

	return err
}

// RejectCollection rejects a pending collection request
func (s *CashService) RejectCollection(ctx context.Context, collectionID, rejecterID uuid.UUID, reason string) error {
	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch collection with user details
		var collection models.CashCollection
		if err := tx.Preload("FromUser").Preload("ToUser").Where("id = ?", collectionID).First(&collection).Error; err != nil {
			return fmt.Errorf("collection not found: %w", err)
		}

		// 2. Validate status
		if collection.Status != "pending" {
			return fmt.Errorf("collection is not pending (current status: %s)", collection.Status)
		}

		// 3. Check expiration (auto-mark as expired if needed)
		now := time.Now().UTC()
		if collection.ExpiresAt != nil && now.After(*collection.ExpiresAt) {
			collection.Status = "expired"
			if err := tx.Save(&collection).Error; err != nil {
				return fmt.Errorf("failed to mark as expired: %w", err)
			}
			return fmt.Errorf("collection request already expired at %s", collection.ExpiresAt.Format(time.RFC3339))
		}

		// 4. Mark collection as rejected (no balance changes)
		collection.Status = "rejected"
		collection.RejectedAt = &now
		collection.RejectReason = reason

		if err := tx.Save(&collection).Error; err != nil {
			return fmt.Errorf("failed to update collection status: %w", err)
		}

		log.Printf("❌ Collection rejected: %.2f from %s (%s) to %s (%s) - Reason: %s",
			collection.Amount, collection.FromUser.FullName(), collection.FromUser.Role,
			collection.ToUser.FullName(), collection.ToUser.Role, reason)

		return nil
	})

	return err
}

// ExpireOldCollections marks all pending collections past their expiration time as expired
// This can be called periodically as a background job or on-demand
func (s *CashService) ExpireOldCollections(ctx context.Context) (int64, error) {
	now := time.Now().UTC()

	// Update all pending collections where expires_at < now
	result := s.db.DB.WithContext(ctx).
		Model(&models.CashCollection{}).
		Where("status = ? AND expires_at IS NOT NULL AND expires_at < ?", "pending", now).
		Update("status", "expired")

	if result.Error != nil {
		return 0, fmt.Errorf("failed to expire old collections: %w", result.Error)
	}

	if result.RowsAffected > 0 {
		log.Printf("⏰ Expired %d collection requests past their deadline", result.RowsAffected)
	}

	return result.RowsAffected, nil
}

// GetCollections returns cash collections with filters
func (s *CashService) GetCollections(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]models.CashCollection, error) {
	var collections []models.CashCollection
	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if fromUserID, ok := filters["from_user_id"].(uuid.UUID); ok {
		query = query.Where("from_user_id = ?", fromUserID)
	}
	if toUserID, ok := filters["to_user_id"].(uuid.UUID); ok {
		query = query.Where("to_user_id = ?", toUserID)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if status, ok := filters["status"].(string); ok {
		query = query.Where("status = ?", status)
	}

	err := query.
		Preload("FromUser").
		Preload("ToUser").
		Preload("Shop").
		Preload("ApprovedBy").
		Order("collection_date DESC").
		Find(&collections).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get collections: %w", err)
	}

	return collections, nil
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Submission
// ═══════════════════════════════════════════════════════════════════════════

// SubmissionRequest represents a cash submission request
type SubmissionRequest struct {
	UserID          uuid.UUID
	ShopID          uuid.UUID
	TenantID        uuid.UUID
	TotalAmount     float64
	Notes500        int
	Notes200        int
	Notes100        int
	Notes50         int
	Notes20         int
	Notes10         int
	BankAccountID   *uuid.UUID
	BankSlipNumber  string
	DepositDate     time.Time
	ReceiptPhotoURL string
	Notes           string
}

// SubmitCash creates a cash submission (pending approval)
func (s *CashService) SubmitCash(ctx context.Context, req *SubmissionRequest, createdByID uuid.UUID) (*models.CashSubmission, error) {
	// Validate denomination total
	calculatedTotal := float64(req.Notes500*500 + req.Notes200*200 + req.Notes100*100 +
		req.Notes50*50 + req.Notes20*20 + req.Notes10*10)

	if calculatedTotal != req.TotalAmount {
		return nil, fmt.Errorf("denomination total %.2f doesn't match declared amount %.2f",
			calculatedTotal, req.TotalAmount)
	}

	var submission *models.CashSubmission

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// Check sufficient balance
		balance, err := s.GetCashBalance(ctx, req.UserID, req.ShopID, req.TenantID)
		if err != nil {
			return err
		}
		if balance < req.TotalAmount {
			return fmt.Errorf("insufficient balance for submission: has %.2f, needs %.2f", balance, req.TotalAmount)
		}

		// Create submission (doesn't deduct yet - pending approval)
		submission = &models.CashSubmission{
			TenantModel: models.TenantModel{
				TenantID: &req.TenantID,
			},
			UserID:          req.UserID,
			ShopID:          req.ShopID,
			TotalAmount:     req.TotalAmount,
			Notes500:        req.Notes500,
			Notes200:        req.Notes200,
			Notes100:        req.Notes100,
			Notes50:         req.Notes50,
			Notes20:         req.Notes20,
			Notes10:         req.Notes10,
			BankAccountID:   req.BankAccountID,
			BankSlipNumber:  req.BankSlipNumber,
			DepositDate:     req.DepositDate,
			ReceiptPhotoURL: req.ReceiptPhotoURL,
			Notes:           req.Notes,
			Status:          "pending",
			CreatedByID:     createdByID,
		}

		if err := tx.Create(submission).Error; err != nil {
			return fmt.Errorf("failed to create submission: %w", err)
		}

		log.Printf("✅ Cash submission created: %.2f by user %s, ID: %s", req.TotalAmount, req.UserID, submission.ID)

		return nil
	})

	if err != nil {
		return nil, err
	}

	return submission, nil
}

// ApproveSubmission approves a cash submission and deducts from balance
func (s *CashService) ApproveSubmission(ctx context.Context, submissionID, approvedByID, tenantID uuid.UUID) error {
	return s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var submission models.CashSubmission
		if err := tx.Where("id = ? AND tenant_id = ?", submissionID, tenantID).
			First(&submission).Error; err != nil {
			return fmt.Errorf("submission not found: %w", err)
		}

		if submission.Status != "pending" {
			return fmt.Errorf("submission already %s", submission.Status)
		}

		// Deduct cash from user's balance
		err := s.UpdateCashBalance(ctx, submission.UserID, submission.ShopID, tenantID,
			-submission.TotalAmount, "submission",
			fmt.Sprintf("Cash submitted to bank - Slip %s", submission.BankSlipNumber),
			"submission", &submissionID, approvedByID)
		if err != nil {
			return err
		}

		// Update submission status
		now := time.Now()
		submission.Status = "approved"
		submission.ApprovedAt = &now
		submission.ApprovedByID = &approvedByID

		if err := tx.Save(&submission).Error; err != nil {
			return fmt.Errorf("failed to update submission: %w", err)
		}

		log.Printf("✅ Cash submission approved: ID %s, Amount %.2f", submissionID, submission.TotalAmount)

		return nil
	})
}

// RejectSubmission rejects a cash submission
func (s *CashService) RejectSubmission(ctx context.Context, submissionID, rejectedByID, tenantID uuid.UUID, reason string) error {
	return s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var submission models.CashSubmission
		if err := tx.Where("id = ? AND tenant_id = ?", submissionID, tenantID).
			First(&submission).Error; err != nil {
			return fmt.Errorf("submission not found: %w", err)
		}

		if submission.Status != "pending" {
			return fmt.Errorf("submission already %s", submission.Status)
		}

		submission.Status = "rejected"
		submission.RejectionReason = reason

		if err := tx.Save(&submission).Error; err != nil {
			return fmt.Errorf("failed to update submission: %w", err)
		}

		log.Printf("❌ Cash submission rejected: ID %s, Reason: %s", submissionID, reason)

		return nil
	})
}

// GetSubmissions returns cash submissions with filters
func (s *CashService) GetSubmissions(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]models.CashSubmission, error) {
	var submissions []models.CashSubmission
	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if userID, ok := filters["user_id"].(uuid.UUID); ok {
		query = query.Where("user_id = ?", userID)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if status, ok := filters["status"].(string); ok {
		query = query.Where("status = ?", status)
	}

	err := query.
		Preload("User").
		Preload("Shop").
		Preload("ApprovedBy").
		Order("deposit_date DESC").
		Find(&submissions).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get submissions: %w", err)
	}

	return submissions, nil
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Request System
// ═══════════════════════════════════════════════════════════════════════════

// CashRequestInput represents a cash request input
type CashRequestInput struct {
	RequesterID     uuid.UUID
	RequestedFromID uuid.UUID
	ShopID          *uuid.UUID // Shop is optional - cash is user-specific
	TenantID        uuid.UUID
	Amount          float64
	Reason          string
}

// CreateCashRequest creates a PENDING cash request with 10-minute expiration
func (s *CashService) CreateCashRequest(ctx context.Context, req *CashRequestInput, createdByID uuid.UUID) (*models.CashRequest, error) {
	var request *models.CashRequest

	// Convert nullable ShopID pointer to uuid.UUID (use uuid.Nil if nil for user-specific balance)
	shopID := uuid.Nil
	if req.ShopID != nil {
		shopID = *req.ShopID
	}

	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch user details for descriptive audit trail
		var requester, requestedFrom models.User
		if err := tx.Where("id = ?", req.RequesterID).First(&requester).Error; err != nil {
			return fmt.Errorf("failed to fetch requester: %w", err)
		}
		if err := tx.Where("id = ?", req.RequestedFromID).First(&requestedFrom).Error; err != nil {
			return fmt.Errorf("failed to fetch requested_from user: %w", err)
		}

		// 2. Check if requested_from user has sufficient balance
		balance, err := s.GetCashBalance(ctx, req.RequestedFromID, shopID, req.TenantID)
		if err != nil {
			return fmt.Errorf("failed to check balance: %w", err)
		}
		if balance < req.Amount {
			return fmt.Errorf("insufficient balance: %s (%s) has %.2f, request is for %.2f",
				requestedFrom.FullName(), requestedFrom.Role, balance, req.Amount)
		}

		// 3. Create PENDING request with 10-minute expiration
		now := time.Now().UTC()
		expiresAt := now.Add(10 * time.Minute)

		request = &models.CashRequest{
			TenantModel: models.TenantModel{
				TenantID: &req.TenantID,
			},
			RequesterID:     req.RequesterID,
			RequestedFromID: req.RequestedFromID,
			ShopID:          req.ShopID,
			Amount:          req.Amount,
			Reason:          req.Reason,
			RequestDate:     now,
			Status:          "pending",
			ExpiresAt:       &expiresAt,
			CreatedByID:     createdByID,
		}

		if err := tx.Create(request).Error; err != nil {
			return fmt.Errorf("failed to create cash request: %w", err)
		}

		log.Printf("📝 Cash request created: %.2f from %s (%s) to %s (%s), expires at %s",
			req.Amount, requestedFrom.FullName(), requestedFrom.Role, requester.FullName(), requester.Role, expiresAt.Format(time.RFC3339))

		return nil
	})

	if err != nil {
		return nil, err
	}

	return request, nil
}

// ApproveCashRequest approves a pending cash request and transfers cash
func (s *CashService) ApproveCashRequest(ctx context.Context, requestID, approverID uuid.UUID) error {
	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch request with user details
		var request models.CashRequest
		if err := tx.Preload("Requester").Preload("RequestedFrom").Where("id = ?", requestID).First(&request).Error; err != nil {
			return fmt.Errorf("request not found: %w", err)
		}

		// Convert nullable ShopID pointer to uuid.UUID (use uuid.Nil if nil for user-specific balance)
		shopID := uuid.Nil
		if request.ShopID != nil {
			shopID = *request.ShopID
		}

		// 2. Validate status
		if request.Status != "pending" {
			return fmt.Errorf("request is not pending (current status: %s)", request.Status)
		}

		// 3. Check expiration
		now := time.Now().UTC()
		if request.ExpiresAt != nil && now.After(*request.ExpiresAt) {
			// Mark as expired
			request.Status = "expired"
			if err := tx.Save(&request).Error; err != nil {
				return fmt.Errorf("failed to mark as expired: %w", err)
			}
			return fmt.Errorf("request expired at %s", request.ExpiresAt.Format(time.RFC3339))
		}

		// 4. Verify sufficient balance (may have changed since request)
		balance, err := s.GetCashBalance(ctx, request.RequestedFromID, shopID, *request.TenantID)
		if err != nil {
			return fmt.Errorf("failed to check balance: %w", err)
		}
		if balance < request.Amount {
			return fmt.Errorf("insufficient balance: %s (%s) has %.2f, needs %.2f",
				request.RequestedFrom.FullName(), request.RequestedFrom.Role, balance, request.Amount)
		}

		// 5. Transfer cash: deduct from requested_from, add to requester
		// Deduct from requested_from
		fromDesc := fmt.Sprintf("Cash request approved for %s (%s)", request.Requester.FullName(), request.Requester.Role)
		err = s.UpdateCashBalance(ctx, request.RequestedFromID, shopID, *request.TenantID,
			-request.Amount, "request_given", fromDesc, "cash_request", &requestID, approverID)
		if err != nil {
			return fmt.Errorf("failed to deduct from giver: %w", err)
		}

		// Add to requester
		toDesc := fmt.Sprintf("Cash request received from %s (%s)", request.RequestedFrom.FullName(), request.RequestedFrom.Role)
		err = s.UpdateCashBalance(ctx, request.RequesterID, shopID, *request.TenantID,
			request.Amount, "request_received", toDesc, "cash_request", &requestID, approverID)
		if err != nil {
			return fmt.Errorf("failed to add to requester: %w", err)
		}

		// 6. Mark request as approved
		request.Status = "approved"
		request.ApprovedAt = &now
		request.ApprovedByID = &approverID

		if err := tx.Save(&request).Error; err != nil {
			return fmt.Errorf("failed to update request status: %w", err)
		}

		log.Printf("✅ Cash request approved: %.2f from %s (%s) to %s (%s) by approver %s",
			request.Amount, request.RequestedFrom.FullName(), request.RequestedFrom.Role,
			request.Requester.FullName(), request.Requester.Role, approverID)

		return nil
	})

	return err
}

// RejectCashRequest rejects a pending cash request
func (s *CashService) RejectCashRequest(ctx context.Context, requestID, rejecterID uuid.UUID, reason string) error {
	err := s.db.DB.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// 1. Fetch request with user details
		var request models.CashRequest
		if err := tx.Preload("Requester").Preload("RequestedFrom").Where("id = ?", requestID).First(&request).Error; err != nil {
			return fmt.Errorf("request not found: %w", err)
		}

		// 2. Validate status
		if request.Status != "pending" {
			return fmt.Errorf("request is not pending (current status: %s)", request.Status)
		}

		// 3. Check expiration (auto-mark as expired if needed)
		now := time.Now().UTC()
		if request.ExpiresAt != nil && now.After(*request.ExpiresAt) {
			request.Status = "expired"
			if err := tx.Save(&request).Error; err != nil {
				return fmt.Errorf("failed to mark as expired: %w", err)
			}
			return fmt.Errorf("request already expired at %s", request.ExpiresAt.Format(time.RFC3339))
		}

		// 4. Mark request as rejected (no balance changes)
		request.Status = "rejected"
		request.RejectedAt = &now
		request.RejectReason = reason

		if err := tx.Save(&request).Error; err != nil {
			return fmt.Errorf("failed to update request status: %w", err)
		}

		log.Printf("❌ Cash request rejected: %.2f from %s (%s) to %s (%s) - Reason: %s",
			request.Amount, request.RequestedFrom.FullName(), request.RequestedFrom.Role,
			request.Requester.FullName(), request.Requester.Role, reason)

		return nil
	})

	return err
}

// ExpireOldCashRequests marks all pending requests past their expiration time as expired
func (s *CashService) ExpireOldCashRequests(ctx context.Context) (int64, error) {
	now := time.Now().UTC()

	result := s.db.DB.WithContext(ctx).
		Model(&models.CashRequest{}).
		Where("status = ? AND expires_at IS NOT NULL AND expires_at < ?", "pending", now).
		Update("status", "expired")

	if result.Error != nil {
		return 0, fmt.Errorf("failed to expire old requests: %w", result.Error)
	}

	if result.RowsAffected > 0 {
		log.Printf("⏰ Expired %d cash requests past their deadline", result.RowsAffected)
	}

	return result.RowsAffected, nil
}

// GetCashRequests returns cash requests with filters
func (s *CashService) GetCashRequests(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}) ([]models.CashRequest, error) {
	var requests []models.CashRequest
	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if requesterID, ok := filters["requester_id"].(uuid.UUID); ok {
		query = query.Where("requester_id = ?", requesterID)
	}
	if requestedFromID, ok := filters["requested_from_id"].(uuid.UUID); ok {
		query = query.Where("requested_from_id = ?", requestedFromID)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if status, ok := filters["status"].(string); ok {
		query = query.Where("status = ?", status)
	}

	err := query.
		Preload("Requester").
		Preload("RequestedFrom").
		Preload("Shop").
		Preload("ApprovedBy").
		Order("request_date DESC").
		Find(&requests).Error

	if err != nil {
		return nil, fmt.Errorf("failed to get cash requests: %w", err)
	}

	return requests, nil
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash History
// ═══════════════════════════════════════════════════════════════════════════

// GetCashHistory returns transaction history for a user
func (s *CashService) GetCashHistory(ctx context.Context, tenantID uuid.UUID, filters map[string]interface{}, limit, offset int) ([]models.CashTransaction, int64, error) {
	var transactions []models.CashTransaction
	var total int64

	query := s.db.DB.WithContext(ctx).Where("tenant_id = ?", tenantID)

	// Apply filters
	if userID, ok := filters["user_id"].(uuid.UUID); ok {
		query = query.Where("user_id = ?", userID)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}
	if transactionType, ok := filters["transaction_type"].(string); ok {
		query = query.Where("transaction_type = ?", transactionType)
	}
	if startDate, ok := filters["start_date"].(time.Time); ok {
		query = query.Where("transaction_date >= ?", startDate)
	}
	if endDate, ok := filters["end_date"].(time.Time); ok {
		query = query.Where("transaction_date <= ?", endDate)
	}

	// Get total count
	if err := query.Model(&models.CashTransaction{}).Count(&total).Error; err != nil {
		return nil, 0, fmt.Errorf("failed to count transactions: %w", err)
	}

	// Get paginated results
	err := query.
		Preload("User").
		Preload("Shop").
		Preload("CreatedByUser").
		Order("transaction_date DESC").
		Limit(limit).
		Offset(offset).
		Find(&transactions).Error

	if err != nil {
		return nil, 0, fmt.Errorf("failed to get transaction history: %w", err)
	}

	return transactions, total, nil
}

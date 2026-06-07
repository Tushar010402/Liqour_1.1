package services

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// DayClosingService handles day-closing reconciliation operations
type DayClosingService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewDayClosingService creates a new day-closing service
func NewDayClosingService(db *database.DB, cache *cache.Cache) *DayClosingService {
	return &DayClosingService{
		db:    db,
		cache: cache,
	}
}

// DayClosingRequest represents the request body for saving day-closing data
type DayClosingRequest struct {
	ShopID            uuid.UUID          `json:"shop_id" binding:"required"`
	Date              string             `json:"date" binding:"required"` // "2026-03-20"
	CashDenominations map[string]int     `json:"cash_denominations"`
	CashTotal         float64            `json:"cash_total"`
	UpiBreakdown      map[string]float64 `json:"upi_breakdown"`
	UpiTotal          float64            `json:"upi_total"`
	Expenses          map[string]float64 `json:"expenses"`
	ExpenseTotal      float64            `json:"expense_total"`
}

// DayClosingResponse represents the response after saving
type DayClosingResponse struct {
	ID                uuid.UUID          `json:"id"`
	ShopID            uuid.UUID          `json:"shop_id"`
	Date              string             `json:"date"`
	CashDenominations map[string]int     `json:"cash_denominations"`
	CashTotal         float64            `json:"cash_total"`
	UpiBreakdown      map[string]float64 `json:"upi_breakdown"`
	UpiTotal          float64            `json:"upi_total"`
	Expenses          map[string]float64 `json:"expenses"`
	ExpenseTotal      float64            `json:"expense_total"`
	CreatedAt         time.Time          `json:"created_at"`
	UpdatedAt         time.Time          `json:"updated_at"`
}

// SaveDayClosing upserts a day-closing record for a given shop+user+date
func (s *DayClosingService) SaveDayClosing(ctx context.Context, req DayClosingRequest, tenantID, userID uuid.UUID) (*DayClosingResponse, error) {
	// Parse date
	date, err := time.Parse("2006-01-02", req.Date)
	if err != nil {
		return nil, fmt.Errorf("invalid date format, expected YYYY-MM-DD: %w", err)
	}

	// Marshal JSON fields
	cashDenomJSON, err := json.Marshal(req.CashDenominations)
	if err != nil {
		cashDenomJSON = []byte("{}")
	}
	upiBreakdownJSON, err := json.Marshal(req.UpiBreakdown)
	if err != nil {
		upiBreakdownJSON = []byte("{}")
	}
	expensesJSON, err := json.Marshal(req.Expenses)
	if err != nil {
		expensesJSON = []byte("{}")
	}

	record := models.DayClosingRecord{
		TenantModel: models.TenantModel{
			TenantID: &tenantID,
		},
		ShopID:            req.ShopID,
		UserID:            userID,
		Date:              date,
		CashDenominations: string(cashDenomJSON),
		CashTotal:         req.CashTotal,
		UpiBreakdown:      string(upiBreakdownJSON),
		UpiTotal:          req.UpiTotal,
		Expenses:          string(expensesJSON),
		ExpenseTotal:      req.ExpenseTotal,
	}

	// Upsert: if record exists for same tenant+shop+user+date, update it
	result := s.db.Where(
		"tenant_id = ? AND shop_id = ? AND user_id = ? AND date = ? AND deleted_at IS NULL",
		tenantID, req.ShopID, userID, date,
	).First(&models.DayClosingRecord{})

	if result.Error == gorm.ErrRecordNotFound {
		// Create new record
		record.ID = uuid.New()
		if err := s.db.Create(&record).Error; err != nil {
			return nil, fmt.Errorf("failed to create day-closing record: %w", err)
		}
	} else if result.Error != nil {
		return nil, fmt.Errorf("failed to check existing record: %w", result.Error)
	} else {
		// Update existing record
		var existing models.DayClosingRecord
		s.db.Where(
			"tenant_id = ? AND shop_id = ? AND user_id = ? AND date = ? AND deleted_at IS NULL",
			tenantID, req.ShopID, userID, date,
		).First(&existing)

		updates := map[string]interface{}{
			"cash_denominations": string(cashDenomJSON),
			"cash_total":         req.CashTotal,
			"upi_breakdown":      string(upiBreakdownJSON),
			"upi_total":          req.UpiTotal,
			"expenses":           string(expensesJSON),
			"expense_total":      req.ExpenseTotal,
		}
		if err := s.db.Model(&existing).Updates(updates).Error; err != nil {
			return nil, fmt.Errorf("failed to update day-closing record: %w", err)
		}
		record = existing
		// Re-read to get updated values
		s.db.First(&record, existing.ID)
	}

	// Invalidate dashboard cache for this tenant
	s.invalidateDashboardCache(ctx, tenantID, &req.ShopID)

	// Build response
	resp := s.buildResponse(&record)
	return resp, nil
}

// GetDayClosing retrieves the day-closing record for a given shop+date
func (s *DayClosingService) GetDayClosing(ctx context.Context, tenantID uuid.UUID, shopID uuid.UUID, date string) (*DayClosingResponse, error) {
	parsedDate, err := time.Parse("2006-01-02", date)
	if err != nil {
		return nil, fmt.Errorf("invalid date format: %w", err)
	}

	var record models.DayClosingRecord
	query := s.db.Where("shop_id = ? AND date = ? AND deleted_at IS NULL", shopID, parsedDate)
	if tenantID != uuid.Nil {
		query = query.Where("tenant_id = ?", tenantID)
	}

	if err := query.First(&record).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, fmt.Errorf("no day-closing record found")
		}
		return nil, fmt.Errorf("failed to get day-closing record: %w", err)
	}

	return s.buildResponse(&record), nil
}

func (s *DayClosingService) invalidateDashboardCache(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) {
	// Invalidate both the tenant-wide and shop-specific cache
	cacheKey := fmt.Sprintf("dashboard_summary:%s", tenantID.String())
	s.cache.Delete(ctx, cacheKey)

	if shopID != nil {
		shopCacheKey := fmt.Sprintf("dashboard_summary:%s:%s", tenantID.String(), shopID.String())
		s.cache.Delete(ctx, shopCacheKey)
	}
}

func (s *DayClosingService) buildResponse(record *models.DayClosingRecord) *DayClosingResponse {
	var cashDenom map[string]int
	var upiBreakdown map[string]float64
	var expenses map[string]float64

	_ = json.Unmarshal([]byte(record.CashDenominations), &cashDenom)
	_ = json.Unmarshal([]byte(record.UpiBreakdown), &upiBreakdown)
	_ = json.Unmarshal([]byte(record.Expenses), &expenses)

	return &DayClosingResponse{
		ID:                record.ID,
		ShopID:            record.ShopID,
		Date:              record.Date.Format("2006-01-02"),
		CashDenominations: cashDenom,
		CashTotal:         record.CashTotal,
		UpiBreakdown:      upiBreakdown,
		UpiTotal:          record.UpiTotal,
		Expenses:          expenses,
		ExpenseTotal:      record.ExpenseTotal,
		CreatedAt:         record.CreatedAt,
		UpdatedAt:         record.UpdatedAt,
	}
}

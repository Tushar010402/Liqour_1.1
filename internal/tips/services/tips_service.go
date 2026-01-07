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

// TipsService handles tip management operations
type TipsService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewTipsService creates a new tips service
func NewTipsService(db *database.DB, cache *cache.Cache) *TipsService {
	return &TipsService{
		db:    db,
		cache: cache,
	}
}

// =====================================================
// Individual Tips
// =====================================================

// RecordTip records an individual tip transaction
func (s *TipsService) RecordTip(ctx context.Context, tenantID uuid.UUID, recorderID uuid.UUID, req *models.CreateTipRequest) (*models.TipTransaction, error) {
	tip := &models.TipTransaction{
		TenantID:     tenantID,
		ShopID:       req.ShopID,
		SalesmanID:   req.SalesmanID,
		DailySalesID: req.DailySalesID,
		TipType:      req.TipType,
		Amount:       req.Amount,
		Source:       req.Source,
		PayoutStatus: models.TipPayoutStatusPending,
		CustomerName: req.CustomerName,
		Description:  req.Description,
		RecordedAt:   time.Now(),
		RecordedBy:   recorderID,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	if tip.Source == "" {
		tip.Source = models.TipSourceCash
	}

	// If it's a pooled tip, find or create today's pool
	if req.TipType == models.TipTypePooled {
		pool, err := s.getOrCreateDailyPool(ctx, tenantID, req.ShopID, time.Now())
		if err != nil {
			return nil, err
		}
		tip.PoolID = &pool.ID
	}

	if err := s.db.WithContext(ctx).Create(tip).Error; err != nil {
		return nil, err
	}

	// Update pool total if pooled
	if tip.PoolID != nil {
		s.db.WithContext(ctx).Model(&models.TipPool{}).
			Where("id = ?", *tip.PoolID).
			Updates(map[string]interface{}{
				"total_amount": gorm.Expr("total_amount + ?", tip.Amount),
				"updated_at":   time.Now(),
			})
	}

	return tip, nil
}

// GetTipsByUser returns tips for a specific user
func (s *TipsService) GetTipsByUser(ctx context.Context, tenantID, userID uuid.UUID, startDate, endDate time.Time) ([]models.TipTransaction, error) {
	var tips []models.TipTransaction
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND salesman_id = ? AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL",
			tenantID, userID, startDate, endDate).
		Preload("Shop").
		Order("recorded_at DESC").
		Find(&tips).Error
	return tips, err
}

// GetTipsByShop returns tips for a shop
func (s *TipsService) GetTipsByShop(ctx context.Context, tenantID, shopID uuid.UUID, startDate, endDate time.Time) ([]models.TipTransaction, error) {
	var tips []models.TipTransaction
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND shop_id = ? AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL",
			tenantID, shopID, startDate, endDate).
		Preload("Salesman").
		Order("recorded_at DESC").
		Find(&tips).Error
	return tips, err
}

// ApproveTip approves a tip transaction
func (s *TipsService) ApproveTip(ctx context.Context, tipID uuid.UUID, approverID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Where("id = ? AND payout_status = 'pending'", tipID).
		Updates(map[string]interface{}{
			"payout_status": models.TipPayoutStatusApproved,
			"approved_at":   now,
			"approved_by":   approverID,
			"updated_at":    now,
		}).Error
}

// RejectTip rejects a tip transaction
func (s *TipsService) RejectTip(ctx context.Context, tipID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Where("id = ? AND payout_status = 'pending'", tipID).
		Updates(map[string]interface{}{
			"payout_status": models.TipPayoutStatusRejected,
			"updated_at":    now,
		}).Error
}

// =====================================================
// Tip Pools
// =====================================================

// CreatePool creates a new tip pool
func (s *TipsService) CreatePool(ctx context.Context, tenantID, creatorID uuid.UUID, req *models.CreateTipPoolRequest) (*models.TipPool, error) {
	pool := &models.TipPool{
		TenantID:           tenantID,
		ShopID:             req.ShopID,
		PoolDate:           req.PoolDate,
		TotalAmount:        0,
		DistributionMethod: req.DistributionMethod,
		Status:             models.TipPoolStatusPending,
		Notes:              req.Notes,
		CreatedAt:          time.Now(),
		UpdatedAt:          time.Now(),
	}

	if err := s.db.WithContext(ctx).Create(pool).Error; err != nil {
		return nil, err
	}

	return pool, nil
}

// GetPool returns pool details
func (s *TipsService) GetPool(ctx context.Context, poolID uuid.UUID) (*models.PoolDetailResponse, error) {
	var pool models.TipPool
	if err := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("Distributor").
		First(&pool, "id = ?", poolID).Error; err != nil {
		return nil, err
	}

	// Get contributions
	var contributions []models.TipTransaction
	s.db.WithContext(ctx).
		Where("pool_id = ? AND deleted_at IS NULL", poolID).
		Preload("Salesman").
		Find(&contributions)

	// Get distributions
	var distributions []models.TipDistribution
	s.db.WithContext(ctx).
		Where("pool_id = ?", poolID).
		Preload("Salesman").
		Find(&distributions)

	// Calculate summary
	var pendingAmount float64
	for _, d := range distributions {
		if d.PayoutStatus == models.TipPayoutStatusPending {
			pendingAmount += d.Amount
		}
	}

	return &models.PoolDetailResponse{
		Pool:          pool,
		Contributions: contributions,
		Distributions: distributions,
		Summary: models.PoolSummary{
			TotalContributions: len(contributions),
			TotalAmount:        pool.TotalAmount,
			ParticipantCount:   pool.ParticipantCount,
			DistributedAmount:  pool.TotalAmount - pendingAmount,
			PendingAmount:      pendingAmount,
		},
	}, nil
}

// AddToPool adds a tip contribution to a pool
func (s *TipsService) AddToPool(ctx context.Context, tenantID, recorderID uuid.UUID, req *models.AddToPoolRequest) (*models.TipTransaction, error) {
	// Verify pool exists and is pending
	var pool models.TipPool
	if err := s.db.WithContext(ctx).First(&pool, "id = ? AND status = 'pending'", req.PoolID).Error; err != nil {
		return nil, fmt.Errorf("pool not found or not in pending status")
	}

	tip := &models.TipTransaction{
		TenantID:     tenantID,
		ShopID:       pool.ShopID,
		SalesmanID:   recorderID, // Recorder is the contributor
		PoolID:       &req.PoolID,
		TipType:      models.TipTypePooled,
		Amount:       req.Amount,
		Source:       req.Source,
		PayoutStatus: models.TipPayoutStatusPending,
		RecordedAt:   time.Now(),
		RecordedBy:   recorderID,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}

	if tip.Source == "" {
		tip.Source = models.TipSourceCash
	}

	if err := s.db.WithContext(ctx).Create(tip).Error; err != nil {
		return nil, err
	}

	// Update pool total
	s.db.WithContext(ctx).Model(&pool).
		Updates(map[string]interface{}{
			"total_amount": gorm.Expr("total_amount + ?", req.Amount),
			"updated_at":   time.Now(),
		})

	return tip, nil
}

// DistributePool distributes pool tips to salesmen
func (s *TipsService) DistributePool(ctx context.Context, tenantID, distributorID uuid.UUID, req *models.DistributePoolRequest) error {
	// Get pool
	var pool models.TipPool
	if err := s.db.WithContext(ctx).First(&pool, "id = ? AND status = 'pending'", req.PoolID).Error; err != nil {
		return fmt.Errorf("pool not found or already distributed")
	}

	// Calculate distribution amounts based on method
	distributions, err := s.calculateDistributions(ctx, &pool, req.Distributions)
	if err != nil {
		return err
	}

	// Validate total equals pool amount
	var totalDistributed float64
	for _, d := range distributions {
		totalDistributed += d.Amount
	}
	if totalDistributed > pool.TotalAmount {
		return fmt.Errorf("distribution total (%.2f) exceeds pool amount (%.2f)", totalDistributed, pool.TotalAmount)
	}

	// Create distribution records
	for _, dist := range distributions {
		dist.TenantID = tenantID
		dist.PoolID = pool.ID
		dist.PayoutStatus = models.TipPayoutStatusPending
		dist.CreatedAt = time.Now()
		dist.UpdatedAt = time.Now()

		if err := s.db.WithContext(ctx).Create(&dist).Error; err != nil {
			return err
		}
	}

	// Update pool status
	now := time.Now()
	pool.Status = models.TipPoolStatusDistributed
	pool.ParticipantCount = len(distributions)
	pool.DistributedAt = &now
	pool.DistributedBy = &distributorID
	pool.UpdatedAt = now

	return s.db.WithContext(ctx).Save(&pool).Error
}

func (s *TipsService) calculateDistributions(ctx context.Context, pool *models.TipPool, allocations []models.DistributionAllocation) ([]models.TipDistribution, error) {
	var distributions []models.TipDistribution

	switch pool.DistributionMethod {
	case models.TipDistributionEqual:
		// Equal distribution
		if len(allocations) == 0 {
			return nil, fmt.Errorf("no participants specified for equal distribution")
		}
		shareAmount := pool.TotalAmount / float64(len(allocations))
		for _, alloc := range allocations {
			distributions = append(distributions, models.TipDistribution{
				SalesmanID: alloc.SalesmanID,
				Amount:     shareAmount,
			})
		}

	case models.TipDistributionHoursWorked:
		// Distribution based on hours worked
		var totalHours float64
		for _, alloc := range allocations {
			if alloc.HoursWorked != nil {
				totalHours += *alloc.HoursWorked
			}
		}
		if totalHours == 0 {
			return nil, fmt.Errorf("no hours data provided for hours-based distribution")
		}
		for _, alloc := range allocations {
			hours := 0.0
			if alloc.HoursWorked != nil {
				hours = *alloc.HoursWorked
			}
			shareAmount := (hours / totalHours) * pool.TotalAmount
			distributions = append(distributions, models.TipDistribution{
				SalesmanID:  alloc.SalesmanID,
				Amount:      shareAmount,
				HoursWorked: alloc.HoursWorked,
			})
		}

	case models.TipDistributionSalesProportional:
		// Distribution based on sales
		var totalSales float64
		for _, alloc := range allocations {
			if alloc.SalesAmount != nil {
				totalSales += *alloc.SalesAmount
			}
		}
		if totalSales == 0 {
			return nil, fmt.Errorf("no sales data provided for sales-based distribution")
		}
		for _, alloc := range allocations {
			sales := 0.0
			if alloc.SalesAmount != nil {
				sales = *alloc.SalesAmount
			}
			shareAmount := (sales / totalSales) * pool.TotalAmount
			distributions = append(distributions, models.TipDistribution{
				SalesmanID:  alloc.SalesmanID,
				Amount:      shareAmount,
				SalesAmount: alloc.SalesAmount,
			})
		}

	case models.TipDistributionCustom:
		// Custom percentage distribution
		var totalPercent float64
		for _, alloc := range allocations {
			if alloc.CustomPercentage != nil {
				totalPercent += *alloc.CustomPercentage
			}
		}
		if totalPercent != 100 {
			return nil, fmt.Errorf("custom percentages must sum to 100 (got %.2f)", totalPercent)
		}
		for _, alloc := range allocations {
			percent := 0.0
			if alloc.CustomPercentage != nil {
				percent = *alloc.CustomPercentage
			}
			shareAmount := (percent / 100) * pool.TotalAmount
			distributions = append(distributions, models.TipDistribution{
				SalesmanID:       alloc.SalesmanID,
				Amount:           shareAmount,
				CustomPercentage: alloc.CustomPercentage,
			})
		}

	default:
		return nil, fmt.Errorf("unknown distribution method: %s", pool.DistributionMethod)
	}

	return distributions, nil
}

// GetPools returns tip pools for a shop
func (s *TipsService) GetPools(ctx context.Context, tenantID, shopID uuid.UUID, status string, page, pageSize int) ([]models.TipPool, int64, error) {
	var pools []models.TipPool
	var total int64

	query := s.db.WithContext(ctx).Model(&models.TipPool{}).
		Where("tenant_id = ? AND shop_id = ? AND deleted_at IS NULL", tenantID, shopID)

	if status != "" {
		query = query.Where("status = ?", status)
	}

	query.Count(&total)

	offset := (page - 1) * pageSize
	err := query.
		Preload("Shop").
		Order("pool_date DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&pools).Error

	return pools, total, err
}

// =====================================================
// Tip Payouts
// =====================================================

// CreatePayoutBatch creates a batch payout
func (s *TipsService) CreatePayoutBatch(ctx context.Context, tenantID, processorID uuid.UUID, req *models.TipPayoutRequest) (*models.TipPayoutBatch, error) {
	// Get all approved tips and distributions in the period
	var totalAmount float64
	var transactionCount int

	// Count individual tips
	var tips []models.TipTransaction
	tipQuery := s.db.WithContext(ctx).
		Where("tenant_id = ? AND payout_status = 'approved' AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL",
			tenantID, req.PeriodStart, req.PeriodEnd)
	if req.ShopID != nil {
		tipQuery = tipQuery.Where("shop_id = ?", *req.ShopID)
	}
	tipQuery.Find(&tips)

	for _, tip := range tips {
		totalAmount += tip.Amount
		transactionCount++
	}

	// Count pool distributions
	var distributions []models.TipDistribution
	distQuery := s.db.WithContext(ctx).
		Joins("JOIN tip_pools ON tip_distributions.pool_id = tip_pools.id").
		Where("tip_distributions.tenant_id = ? AND tip_distributions.payout_status = 'approved' AND tip_pools.pool_date BETWEEN ? AND ?",
			tenantID, req.PeriodStart, req.PeriodEnd)
	distQuery.Find(&distributions)

	for _, dist := range distributions {
		totalAmount += dist.Amount
		transactionCount++
	}

	if transactionCount == 0 {
		return nil, fmt.Errorf("no approved tips found for the specified period")
	}

	// Generate batch number
	batchNumber := s.generateBatchNumber(ctx, tenantID)

	batch := &models.TipPayoutBatch{
		TenantID:         tenantID,
		ShopID:           req.ShopID,
		BatchNumber:      batchNumber,
		TotalAmount:      totalAmount,
		TransactionCount: transactionCount,
		Status:           models.TipPayoutStatusPending,
		PaymentMethod:    req.PaymentMethod,
		PaymentReference: req.PaymentReference,
		PeriodStart:      req.PeriodStart,
		PeriodEnd:        req.PeriodEnd,
		Notes:            req.Notes,
		CreatedAt:        time.Now(),
		UpdatedAt:        time.Now(),
	}

	if err := s.db.WithContext(ctx).Create(batch).Error; err != nil {
		return nil, err
	}

	// Update tips and distributions with batch ID
	s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Where("id IN ?", getTipIDs(tips)).
		Update("payout_batch_id", batch.ID)

	s.db.WithContext(ctx).Model(&models.TipDistribution{}).
		Where("id IN ?", getDistributionIDs(distributions)).
		Update("payout_batch_id", batch.ID)

	return batch, nil
}

// ApprovePayoutBatch approves a payout batch
func (s *TipsService) ApprovePayoutBatch(ctx context.Context, batchID, approverID uuid.UUID) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.TipPayoutBatch{}).
		Where("id = ? AND status = 'pending'", batchID).
		Updates(map[string]interface{}{
			"status":      models.TipPayoutStatusApproved,
			"approved_at": now,
			"approved_by": approverID,
			"updated_at":  now,
		}).Error
}

// ProcessPayoutBatch marks a batch as paid
func (s *TipsService) ProcessPayoutBatch(ctx context.Context, batchID, processorID uuid.UUID, paymentReference string) error {
	now := time.Now()

	// Update batch
	if err := s.db.WithContext(ctx).Model(&models.TipPayoutBatch{}).
		Where("id = ? AND status = 'approved'", batchID).
		Updates(map[string]interface{}{
			"status":            models.TipPayoutStatusPaid,
			"payment_reference": paymentReference,
			"processed_at":      now,
			"processed_by":      processorID,
			"updated_at":        now,
		}).Error; err != nil {
		return err
	}

	// Update related tips
	s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Where("payout_batch_id = ?", batchID).
		Updates(map[string]interface{}{
			"payout_status": models.TipPayoutStatusPaid,
			"paid_at":       now,
			"updated_at":    now,
		})

	// Update related distributions
	s.db.WithContext(ctx).Model(&models.TipDistribution{}).
		Where("payout_batch_id = ?", batchID).
		Updates(map[string]interface{}{
			"payout_status": models.TipPayoutStatusPaid,
			"paid_at":       now,
			"updated_at":    now,
		})

	return nil
}

// GetPayoutBatches returns payout batches
func (s *TipsService) GetPayoutBatches(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, status string, page, pageSize int) ([]models.TipPayoutBatch, int64, error) {
	var batches []models.TipPayoutBatch
	var total int64

	query := s.db.WithContext(ctx).Model(&models.TipPayoutBatch{}).
		Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}
	if status != "" {
		query = query.Where("status = ?", status)
	}

	query.Count(&total)

	offset := (page - 1) * pageSize
	err := query.
		Preload("Shop").
		Order("created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&batches).Error

	return batches, total, err
}

// =====================================================
// Summary & Reports
// =====================================================

// GetTipsSummary returns tips summary for a period
func (s *TipsService) GetTipsSummary(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) (*models.TipSummaryResponse, error) {
	summary := &models.TipSummaryResponse{
		SourceBreakdown: make(map[models.TipSource]float64),
	}

	// Get individual tips summary
	var individualStats struct {
		Total   float64
		Count   int64
		Pending float64
		Paid    float64
	}
	indQuery := s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Select(`
			COALESCE(SUM(amount), 0) as total,
			COUNT(*) as count,
			COALESCE(SUM(CASE WHEN payout_status = 'pending' THEN amount ELSE 0 END), 0) as pending,
			COALESCE(SUM(CASE WHEN payout_status = 'paid' THEN amount ELSE 0 END), 0) as paid
		`).
		Where("tenant_id = ? AND tip_type = 'individual' AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL",
			tenantID, startDate, endDate)
	if shopID != nil {
		indQuery = indQuery.Where("shop_id = ?", *shopID)
	}
	indQuery.Scan(&individualStats)

	// Get pooled tips summary
	var pooledStats struct {
		Total   float64
		Count   int64
		Pending float64
		Paid    float64
	}
	poolQuery := s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Select(`
			COALESCE(SUM(amount), 0) as total,
			COUNT(*) as count,
			COALESCE(SUM(CASE WHEN payout_status = 'pending' THEN amount ELSE 0 END), 0) as pending,
			COALESCE(SUM(CASE WHEN payout_status = 'paid' THEN amount ELSE 0 END), 0) as paid
		`).
		Where("tenant_id = ? AND tip_type = 'pooled' AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL",
			tenantID, startDate, endDate)
	if shopID != nil {
		poolQuery = poolQuery.Where("shop_id = ?", *shopID)
	}
	poolQuery.Scan(&pooledStats)

	summary.TotalTips = individualStats.Total + pooledStats.Total
	summary.IndividualTips = individualStats.Total
	summary.PooledTips = pooledStats.Total
	summary.PendingPayout = individualStats.Pending + pooledStats.Pending
	summary.PaidAmount = individualStats.Paid + pooledStats.Paid
	summary.TipCount = int(individualStats.Count + pooledStats.Count)

	// Get breakdown by source
	var sourceResults []struct {
		Source models.TipSource
		Total  float64
	}
	srcQuery := s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Select("source, SUM(amount) as total").
		Where("tenant_id = ? AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL", tenantID, startDate, endDate)
	if shopID != nil {
		srcQuery = srcQuery.Where("shop_id = ?", *shopID)
	}
	srcQuery.Group("source").Scan(&sourceResults)
	for _, r := range sourceResults {
		summary.SourceBreakdown[r.Source] = r.Total
	}

	// Get breakdown by salesman
	summary.SalesmanBreakdown = s.getSalesmanTipBreakdown(ctx, tenantID, shopID, startDate, endDate)

	// Get daily trend
	summary.DailyTrend = s.getDailyTipTrend(ctx, tenantID, shopID, startDate, endDate)

	return summary, nil
}

func (s *TipsService) getSalesmanTipBreakdown(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) []models.SalesmanTipSummary {
	var breakdown []models.SalesmanTipSummary

	query := s.db.WithContext(ctx).
		Table("v_tips_summary").
		Select(`
			salesman_id,
			salesman_name,
			SUM(CASE WHEN tip_type = 'individual' THEN total_tips ELSE 0 END) as individual_tips,
			SUM(CASE WHEN tip_type = 'pooled' THEN total_tips ELSE 0 END) as pooled_share,
			SUM(total_tips) as total_tips,
			SUM(pending_payout) as pending_payout,
			SUM(paid_amount) as paid_amount,
			SUM(tip_count) as tip_count
		`).
		Where("tenant_id = ? AND (month BETWEEN ? AND ? OR week BETWEEN ? AND ?)",
			tenantID, startDate, endDate, startDate, endDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	query.Group("salesman_id, salesman_name").
		Order("total_tips DESC").
		Scan(&breakdown)

	return breakdown
}

func (s *TipsService) getDailyTipTrend(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, startDate, endDate time.Time) []models.DailyTipStat {
	var trend []models.DailyTipStat

	query := s.db.WithContext(ctx).Model(&models.TipTransaction{}).
		Select(`
			DATE(recorded_at) as date,
			SUM(amount) as total_amount,
			SUM(CASE WHEN tip_type = 'individual' THEN amount ELSE 0 END) as individual_tips,
			SUM(CASE WHEN tip_type = 'pooled' THEN amount ELSE 0 END) as pooled_tips,
			COUNT(*) as tip_count
		`).
		Where("tenant_id = ? AND recorded_at BETWEEN ? AND ? AND deleted_at IS NULL",
			tenantID, startDate, endDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	query.Group("DATE(recorded_at)").
		Order("date").
		Scan(&trend)

	return trend
}

// =====================================================
// Helper Functions
// =====================================================

func (s *TipsService) getOrCreateDailyPool(ctx context.Context, tenantID, shopID uuid.UUID, date time.Time) (*models.TipPool, error) {
	poolDate := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())

	var pool models.TipPool
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND shop_id = ? AND pool_date = ? AND deleted_at IS NULL",
			tenantID, shopID, poolDate).
		First(&pool).Error

	if err == gorm.ErrRecordNotFound {
		// Create new pool
		pool = models.TipPool{
			TenantID:           tenantID,
			ShopID:             shopID,
			PoolDate:           poolDate,
			TotalAmount:        0,
			DistributionMethod: models.TipDistributionEqual, // Default
			Status:             models.TipPoolStatusPending,
			CreatedAt:          time.Now(),
			UpdatedAt:          time.Now(),
		}
		if err := s.db.WithContext(ctx).Create(&pool).Error; err != nil {
			return nil, err
		}
	} else if err != nil {
		return nil, err
	}

	return &pool, nil
}

func (s *TipsService) generateBatchNumber(ctx context.Context, tenantID uuid.UUID) string {
	var count int64
	s.db.WithContext(ctx).Model(&models.TipPayoutBatch{}).
		Where("tenant_id = ?", tenantID).
		Count(&count)
	return fmt.Sprintf("TIP-%s-%05d", time.Now().Format("200601"), count+1)
}

func getTipIDs(tips []models.TipTransaction) []uuid.UUID {
	ids := make([]uuid.UUID, len(tips))
	for i, t := range tips {
		ids[i] = t.ID
	}
	return ids
}

func getDistributionIDs(distributions []models.TipDistribution) []uuid.UUID {
	ids := make([]uuid.UUID, len(distributions))
	for i, d := range distributions {
		ids[i] = d.ID
	}
	return ids
}

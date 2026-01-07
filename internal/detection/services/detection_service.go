package services

import (
	"context"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

// DetectionService handles theft detection and investigation
type DetectionService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewDetectionService creates a new detection service
func NewDetectionService(db *database.DB, cache *cache.Cache) *DetectionService {
	return &DetectionService{
		db:    db,
		cache: cache,
	}
}

// =====================================================
// Anomaly Detection
// =====================================================

// AnalyzeCashVariance analyzes cash variance for anomalies
func (s *DetectionService) AnalyzeCashVariance(ctx context.Context, tenantID, shopID uuid.UUID, date time.Time, expected, actual float64, responsibleStaff []uuid.UUID) (*models.AnomalyDetectionResult, error) {
	variance := actual - expected
	variancePercent := 0.0
	if expected != 0 {
		variancePercent = (variance / expected) * 100
	}

	// Get historical data for Z-score calculation
	stats, err := s.getHistoricalCashStats(ctx, tenantID, shopID, 30)
	if err != nil {
		return nil, err
	}

	// Calculate Z-score
	zScore := 0.0
	if stats.StdDev > 0 {
		zScore = (math.Abs(variance) - stats.Mean) / stats.StdDev
	}

	// Get threshold configuration
	config, err := s.getAlertConfig(ctx, tenantID, &shopID, models.DetectionTypeCashShortage)
	if err != nil {
		config = &models.AlertConfiguration{
			ZScoreThreshold:  2.5,
			ThresholdAmount:  newFloat64(500),
			ThresholdPercent: newFloat64(5),
		}
	}

	// Determine if anomaly
	isAnomaly := false
	riskLevel := models.RiskLevelLow

	if config.ThresholdAmount != nil && math.Abs(variance) > *config.ThresholdAmount {
		isAnomaly = true
	}
	if config.ThresholdPercent != nil && math.Abs(variancePercent) > *config.ThresholdPercent {
		isAnomaly = true
	}
	if zScore > config.ZScoreThreshold {
		isAnomaly = true
	}

	// Calculate risk level
	if isAnomaly {
		if zScore > 4 || math.Abs(variance) > 5000 {
			riskLevel = models.RiskLevelCritical
		} else if zScore > 3 || math.Abs(variance) > 2000 {
			riskLevel = models.RiskLevelHigh
		} else if zScore > 2.5 || math.Abs(variance) > 1000 {
			riskLevel = models.RiskLevelMedium
		}
	}

	// Calculate confidence score (0-1)
	confidenceScore := calculateConfidence(zScore, stats.SampleSize)

	// Determine detection type
	detectionType := models.DetectionTypeCashShortage
	if variance > 0 {
		detectionType = models.DetectionTypeCashOverage
	}

	result := &models.AnomalyDetectionResult{
		IsAnomaly:       isAnomaly,
		DetectionType:   detectionType,
		ZScore:          zScore,
		ConfidenceScore: confidenceScore,
		RiskLevel:       riskLevel,
		Value:           variance,
		ExpectedRange:   [2]float64{stats.Mean - 2*stats.StdDev, stats.Mean + 2*stats.StdDev},
		Metrics: map[string]interface{}{
			"expected":         expected,
			"actual":           actual,
			"variance_percent": variancePercent,
			"historical_mean":  stats.Mean,
			"historical_std":   stats.StdDev,
			"sample_size":      stats.SampleSize,
		},
	}

	if isAnomaly {
		result.Description = fmt.Sprintf("Cash variance of ₹%.2f detected (%.1f%%, Z-score: %.2f)", variance, variancePercent, zScore)

		// Create variance record
		s.createCashVarianceRecord(ctx, tenantID, shopID, date, detectionType, expected, actual, variance, variancePercent, zScore, riskLevel, responsibleStaff)

		// Create alert if configured
		if config.IsEnabled {
			s.createDetectionAlert(ctx, tenantID, shopID, detectionType, riskLevel, result.Description, variance, nil, config)
		}
	}

	return result, nil
}

// AnalyzeDiscountPatterns analyzes discount patterns for abuse
func (s *DetectionService) AnalyzeDiscountPatterns(ctx context.Context, tenantID uuid.UUID, userID uuid.UUID, date time.Time) (*models.AnomalyDetectionResult, error) {
	// Get user's discount stats for the day
	var userStats struct {
		DiscountCount  int64
		TotalDiscount  float64
		AvgDiscount    float64
		MaxDiscount    float64
		TransactionCount int64
	}

	s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select(`
			COUNT(CASE WHEN discount_amount > 0 THEN 1 END) as discount_count,
			COALESCE(SUM(discount_amount), 0) as total_discount,
			COALESCE(AVG(discount_amount), 0) as avg_discount,
			COALESCE(MAX(discount_amount), 0) as max_discount,
			COUNT(*) as transaction_count
		`).
		Where("tenant_id = ? AND salesman_id = ? AND record_date = ? AND status = 'approved'", tenantID, userID, date).
		Scan(&userStats)

	// Get historical stats for this user
	historicalStats, _ := s.getHistoricalDiscountStats(ctx, tenantID, userID, 30)

	// Get shop average for comparison
	shopStats, _ := s.getShopDiscountStats(ctx, tenantID, date)

	// Calculate Z-score
	zScore := 0.0
	if historicalStats.StdDev > 0 {
		zScore = (userStats.TotalDiscount - historicalStats.Mean) / historicalStats.StdDev
	}

	// Calculate discount ratio
	discountRatio := 0.0
	if userStats.TransactionCount > 0 {
		discountRatio = float64(userStats.DiscountCount) / float64(userStats.TransactionCount) * 100
	}

	// Determine anomaly
	isAnomaly := false
	riskLevel := models.RiskLevelLow

	config, _ := s.getAlertConfig(ctx, tenantID, nil, models.DetectionTypeDiscountAbuse)
	if config == nil {
		config = &models.AlertConfiguration{ZScoreThreshold: 2.5}
	}

	// Check for anomaly conditions
	if zScore > config.ZScoreThreshold {
		isAnomaly = true
	}
	if discountRatio > 50 && userStats.DiscountCount > 5 { // More than 50% transactions with discounts
		isAnomaly = true
	}
	if shopStats.AvgDiscount > 0 && userStats.AvgDiscount > shopStats.AvgDiscount*2 { // 2x shop average
		isAnomaly = true
	}

	if isAnomaly {
		if zScore > 4 || userStats.TotalDiscount > shopStats.TotalDiscount*0.5 {
			riskLevel = models.RiskLevelCritical
		} else if zScore > 3 {
			riskLevel = models.RiskLevelHigh
		} else {
			riskLevel = models.RiskLevelMedium
		}
	}

	confidenceScore := calculateConfidence(zScore, historicalStats.SampleSize)

	result := &models.AnomalyDetectionResult{
		IsAnomaly:       isAnomaly,
		DetectionType:   models.DetectionTypeDiscountAbuse,
		ZScore:          zScore,
		ConfidenceScore: confidenceScore,
		RiskLevel:       riskLevel,
		Value:           userStats.TotalDiscount,
		Metrics: map[string]interface{}{
			"discount_count":   userStats.DiscountCount,
			"total_discount":   userStats.TotalDiscount,
			"avg_discount":     userStats.AvgDiscount,
			"discount_ratio":   discountRatio,
			"shop_avg":         shopStats.AvgDiscount,
			"historical_mean":  historicalStats.Mean,
		},
	}

	if isAnomaly {
		result.Description = fmt.Sprintf("Unusual discount pattern detected: %.1f%% of transactions discounted, total ₹%.2f (Z-score: %.2f)", discountRatio, userStats.TotalDiscount, zScore)

		// Create suspicious activity record
		s.createSuspiciousActivity(ctx, tenantID, uuid.Nil, userID, models.DetectionTypeDiscountAbuse, riskLevel, confidenceScore, zScore, result.Description, userStats.TotalDiscount, nil)
	}

	return result, nil
}

// AnalyzeInventoryShrinkage analyzes inventory for shrinkage patterns
func (s *DetectionService) AnalyzeInventoryShrinkage(ctx context.Context, tenantID, shopID, productID uuid.UUID, systemQty, physicalQty int, unitCost float64) (*models.AnomalyDetectionResult, error) {
	variance := systemQty - physicalQty
	varianceValue := float64(variance) * unitCost
	variancePercent := 0.0
	if systemQty > 0 {
		variancePercent = float64(variance) / float64(systemQty) * 100
	}

	// Get historical shrinkage for this product
	stats, _ := s.getHistoricalShrinkageStats(ctx, tenantID, shopID, productID, 90)

	// Calculate Z-score
	zScore := 0.0
	if stats.StdDev > 0 {
		zScore = (float64(variance) - stats.Mean) / stats.StdDev
	}

	// Get configuration
	config, _ := s.getAlertConfig(ctx, tenantID, &shopID, models.DetectionTypeInventoryShrink)
	if config == nil {
		config = &models.AlertConfiguration{
			ZScoreThreshold:  2.5,
			ThresholdPercent: newFloat64(5),
		}
	}

	isAnomaly := false
	riskLevel := models.RiskLevelLow

	if variance > 0 { // Shrinkage detected
		if config.ThresholdPercent != nil && variancePercent > *config.ThresholdPercent {
			isAnomaly = true
		}
		if zScore > config.ZScoreThreshold {
			isAnomaly = true
		}
		if varianceValue > 1000 {
			isAnomaly = true
		}

		if isAnomaly {
			if varianceValue > 10000 || zScore > 4 {
				riskLevel = models.RiskLevelCritical
			} else if varianceValue > 5000 || zScore > 3 {
				riskLevel = models.RiskLevelHigh
			} else if varianceValue > 1000 || zScore > 2.5 {
				riskLevel = models.RiskLevelMedium
			}
		}
	}

	confidenceScore := calculateConfidence(zScore, stats.SampleSize)

	result := &models.AnomalyDetectionResult{
		IsAnomaly:       isAnomaly,
		DetectionType:   models.DetectionTypeInventoryShrink,
		ZScore:          zScore,
		ConfidenceScore: confidenceScore,
		RiskLevel:       riskLevel,
		Value:           varianceValue,
		ExpectedRange:   [2]float64{stats.Mean - 2*stats.StdDev, stats.Mean + 2*stats.StdDev},
		Metrics: map[string]interface{}{
			"system_qty":       systemQty,
			"physical_qty":     physicalQty,
			"variance_qty":     variance,
			"variance_value":   varianceValue,
			"variance_percent": variancePercent,
			"unit_cost":        unitCost,
		},
	}

	if isAnomaly {
		result.Description = fmt.Sprintf("Inventory shrinkage: %d units (₹%.2f, %.1f%%) detected", variance, varianceValue, variancePercent)
	}

	return result, nil
}

// =====================================================
// Investigation Management
// =====================================================

// CreateInvestigation creates a new investigation case
func (s *DetectionService) CreateInvestigation(ctx context.Context, tenantID uuid.UUID, req *models.CreateInvestigationRequest) (*models.Investigation, error) {
	// Generate case number
	caseNumber := s.generateCaseNumber(ctx, tenantID)

	investigation := &models.Investigation{
		TenantID:      tenantID,
		ShopID:        req.ShopID,
		CaseNumber:    caseNumber,
		Title:         req.Title,
		Description:   req.Description,
		DetectionType: req.DetectionType,
		RiskLevel:     req.RiskLevel,
		Status:        models.InvestigationStatusOpen,
		Priority:      req.Priority,
		EstimatedLoss: req.EstimatedLoss,
		SuspectUserID: req.SuspectUserID,
		AssignedTo:    req.AssignedTo,
		DetectedAt:    time.Now(),
		CreatedAt:     time.Now(),
		UpdatedAt:     time.Now(),
	}

	if investigation.Priority == "" {
		investigation.Priority = models.InvestigationPriorityMedium
	}

	if err := s.db.WithContext(ctx).Create(investigation).Error; err != nil {
		return nil, err
	}

	// Link related activities
	if len(req.RelatedActivityIDs) > 0 {
		s.db.WithContext(ctx).Model(&models.SuspiciousActivity{}).
			Where("id IN ?", req.RelatedActivityIDs).
			Update("investigation_id", investigation.ID)
	}

	return investigation, nil
}

// UpdateInvestigation updates an investigation
func (s *DetectionService) UpdateInvestigation(ctx context.Context, investigationID uuid.UUID, req *models.UpdateInvestigationRequest) error {
	updates := map[string]interface{}{
		"updated_at": time.Now(),
	}

	if req.Title != nil {
		updates["title"] = *req.Title
	}
	if req.Description != nil {
		updates["description"] = *req.Description
	}
	if req.Status != nil {
		updates["status"] = *req.Status
		if *req.Status == models.InvestigationStatusInProgress {
			now := time.Now()
			updates["started_at"] = now
		} else if strings.HasPrefix(string(*req.Status), "closed") {
			now := time.Now()
			updates["resolved_at"] = now
		}
	}
	if req.Priority != nil {
		updates["priority"] = *req.Priority
	}
	if req.ConfirmedLoss != nil {
		updates["confirmed_loss"] = *req.ConfirmedLoss
	}
	if req.AssignedTo != nil {
		updates["assigned_to"] = *req.AssignedTo
	}
	if req.Resolution != nil {
		updates["resolution"] = *req.Resolution
	}

	return s.db.WithContext(ctx).Model(&models.Investigation{}).
		Where("id = ?", investigationID).
		Updates(updates).Error
}

// AddInvestigationNote adds a note to investigation
func (s *DetectionService) AddInvestigationNote(ctx context.Context, investigationID, authorID uuid.UUID, req *models.AddInvestigationNoteRequest) (*models.InvestigationNote, error) {
	note := &models.InvestigationNote{
		InvestigationID: investigationID,
		AuthorID:        authorID,
		NoteType:        req.NoteType,
		Content:         req.Content,
		Attachments:     req.Attachments,
		IsInternal:      req.IsInternal,
		CreatedAt:       time.Now(),
		UpdatedAt:       time.Now(),
	}

	if note.NoteType == "" {
		note.NoteType = "comment"
	}

	if err := s.db.WithContext(ctx).Create(note).Error; err != nil {
		return nil, err
	}

	return note, nil
}

// GetInvestigation returns investigation details
func (s *DetectionService) GetInvestigation(ctx context.Context, investigationID uuid.UUID) (*models.Investigation, error) {
	var investigation models.Investigation
	err := s.db.WithContext(ctx).
		Preload("Shop").
		Preload("SuspectUser").
		Preload("Assignee").
		Preload("Notes", func(db *gorm.DB) *gorm.DB {
			return db.Order("created_at DESC")
		}).
		Preload("Notes.Author").
		Preload("Activities").
		First(&investigation, "id = ?", investigationID).Error
	return &investigation, err
}

// ListInvestigations returns paginated investigations
func (s *DetectionService) ListInvestigations(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, status string, page, pageSize int) ([]models.Investigation, int64, error) {
	var investigations []models.Investigation
	var total int64

	query := s.db.WithContext(ctx).Model(&models.Investigation{}).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID)

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
		Preload("SuspectUser").
		Preload("Assignee").
		Order("priority DESC, created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&investigations).Error

	return investigations, total, err
}

// =====================================================
// Alert Management
// =====================================================

// GetActiveAlerts returns active detection alerts
func (s *DetectionService) GetActiveAlerts(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, limit int) ([]models.DetectionAlert, error) {
	var alerts []models.DetectionAlert

	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND status IN ('active', 'escalated')", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	err := query.
		Preload("Shop").
		Preload("AffectedUser").
		Order("risk_level DESC, triggered_at DESC").
		Limit(limit).
		Find(&alerts).Error

	return alerts, err
}

// AcknowledgeAlert acknowledges an alert
func (s *DetectionService) AcknowledgeAlert(ctx context.Context, alertID, userID uuid.UUID, notes string) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.DetectionAlert{}).
		Where("id = ?", alertID).
		Updates(map[string]interface{}{
			"status":          models.AlertStatusAcknowledged,
			"acknowledged_at": now,
			"acknowledged_by": userID,
			"updated_at":      now,
		}).Error
}

// ResolveAlert resolves an alert
func (s *DetectionService) ResolveAlert(ctx context.Context, alertID, userID uuid.UUID, resolution string) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.DetectionAlert{}).
		Where("id = ?", alertID).
		Updates(map[string]interface{}{
			"status":      models.AlertStatusResolved,
			"resolved_at": now,
			"resolved_by": userID,
			"resolution":  resolution,
			"updated_at":  now,
		}).Error
}

// EscalateAlerts escalates overdue alerts
func (s *DetectionService) EscalateAlerts(ctx context.Context) error {
	now := time.Now()
	return s.db.WithContext(ctx).Model(&models.DetectionAlert{}).
		Where("status = 'active' AND escalate_at <= ? AND escalated_at IS NULL", now).
		Updates(map[string]interface{}{
			"status":       models.AlertStatusEscalated,
			"escalated_at": now,
			"updated_at":   now,
		}).Error
}

// ConfigureAlert creates or updates alert configuration
func (s *DetectionService) ConfigureAlert(ctx context.Context, tenantID uuid.UUID, req *models.ConfigureAlertRequest) (*models.AlertConfiguration, error) {
	var config models.AlertConfiguration

	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND detection_type = ?", tenantID, req.DetectionType)
	if req.ShopID != nil {
		query = query.Where("shop_id = ?", *req.ShopID)
	} else {
		query = query.Where("shop_id IS NULL")
	}

	err := query.First(&config).Error
	if err == gorm.ErrRecordNotFound {
		config = models.AlertConfiguration{
			TenantID:      tenantID,
			ShopID:        req.ShopID,
			DetectionType: req.DetectionType,
			IsEnabled:     true,
			CreatedAt:     time.Now(),
		}
	}

	// Update fields
	if req.IsEnabled != nil {
		config.IsEnabled = *req.IsEnabled
	}
	if req.ThresholdAmount != nil {
		config.ThresholdAmount = req.ThresholdAmount
	}
	if req.ThresholdPercent != nil {
		config.ThresholdPercent = req.ThresholdPercent
	}
	if req.ZScoreThreshold != nil {
		config.ZScoreThreshold = *req.ZScoreThreshold
	}
	if req.MinOccurrences != nil {
		config.MinOccurrences = *req.MinOccurrences
	}
	if req.TimeWindowMinutes != nil {
		config.TimeWindowMinutes = *req.TimeWindowMinutes
	}
	if req.EscalationMinutes != nil {
		config.EscalationMinutes = *req.EscalationMinutes
	}
	if req.NotifyRoles != nil {
		config.NotifyRoles = req.NotifyRoles
	}
	if req.AutoInvestigate != nil {
		config.AutoInvestigate = *req.AutoInvestigate
	}
	if req.AutoInvestigateAt != nil {
		config.AutoInvestigateAt = *req.AutoInvestigateAt
	}
	config.UpdatedAt = time.Now()

	if err := s.db.WithContext(ctx).Save(&config).Error; err != nil {
		return nil, err
	}

	return &config, nil
}

// GetDashboard returns detection dashboard data
func (s *DetectionService) GetDashboard(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) (*models.DetectionDashboardResponse, error) {
	response := &models.DetectionDashboardResponse{}

	// Get summary
	summary, _ := s.getSummaryStats(ctx, tenantID, shopID)
	response.Summary = *summary

	// Get active alerts
	alerts, _ := s.GetActiveAlerts(ctx, tenantID, shopID, 10)
	response.ActiveAlerts = alerts

	// Get open investigations
	investigations, _, _ := s.ListInvestigations(ctx, tenantID, shopID, "open", 1, 10)
	response.OpenInvestigations = investigations

	// Get recent suspicious activities
	var activities []models.SuspiciousActivity
	query := s.db.WithContext(ctx).
		Where("tenant_id = ? AND deleted_at IS NULL", tenantID).
		Order("detected_at DESC").
		Limit(10)
	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}
	query.Find(&activities)
	response.RecentActivities = activities

	// Get risk trend (last 7 days)
	response.RiskTrend = s.getRiskTrend(ctx, tenantID, shopID, 7)

	// Get top risk users
	response.TopRiskUsers = s.getTopRiskUsers(ctx, tenantID, shopID, 5)

	return response, nil
}

// =====================================================
// Helper Functions
// =====================================================

type HistoricalStats struct {
	Mean       float64
	StdDev     float64
	SampleSize int
}

func (s *DetectionService) getHistoricalCashStats(ctx context.Context, tenantID, shopID uuid.UUID, days int) (*HistoricalStats, error) {
	var result struct {
		Mean       float64
		StdDev     float64
		SampleSize int64
	}

	startDate := time.Now().AddDate(0, 0, -days)
	s.db.WithContext(ctx).Model(&models.CashVariance{}).
		Select("AVG(ABS(variance_amount)) as mean, STDDEV(ABS(variance_amount)) as std_dev, COUNT(*) as sample_size").
		Where("tenant_id = ? AND shop_id = ? AND variance_date >= ? AND deleted_at IS NULL", tenantID, shopID, startDate).
		Scan(&result)

	return &HistoricalStats{
		Mean:       result.Mean,
		StdDev:     result.StdDev,
		SampleSize: int(result.SampleSize),
	}, nil
}

func (s *DetectionService) getHistoricalDiscountStats(ctx context.Context, tenantID, userID uuid.UUID, days int) (*HistoricalStats, error) {
	var result struct {
		Mean       float64
		StdDev     float64
		SampleSize int64
	}

	startDate := time.Now().AddDate(0, 0, -days)
	s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select("AVG(discount_amount) as mean, STDDEV(discount_amount) as std_dev, COUNT(*) as sample_size").
		Where("tenant_id = ? AND salesman_id = ? AND record_date >= ? AND status = 'approved'", tenantID, userID, startDate).
		Scan(&result)

	return &HistoricalStats{
		Mean:       result.Mean,
		StdDev:     result.StdDev,
		SampleSize: int(result.SampleSize),
	}, nil
}

func (s *DetectionService) getShopDiscountStats(ctx context.Context, tenantID uuid.UUID, date time.Time) (*struct{ AvgDiscount, TotalDiscount float64 }, error) {
	var result struct {
		AvgDiscount   float64
		TotalDiscount float64
	}

	s.db.WithContext(ctx).
		Table("daily_sales_records").
		Select("AVG(discount_amount) as avg_discount, SUM(discount_amount) as total_discount").
		Where("tenant_id = ? AND record_date = ? AND status = 'approved'", tenantID, date).
		Scan(&result)

	return &result, nil
}

func (s *DetectionService) getHistoricalShrinkageStats(ctx context.Context, tenantID, shopID, productID uuid.UUID, days int) (*HistoricalStats, error) {
	var result struct {
		Mean       float64
		StdDev     float64
		SampleSize int64
	}

	startDate := time.Now().AddDate(0, 0, -days)
	s.db.WithContext(ctx).Model(&models.ShrinkageRecord{}).
		Select("AVG(variance_quantity) as mean, STDDEV(variance_quantity) as std_dev, COUNT(*) as sample_size").
		Where("tenant_id = ? AND shop_id = ? AND product_id = ? AND verification_date >= ?", tenantID, shopID, productID, startDate).
		Scan(&result)

	return &HistoricalStats{
		Mean:       result.Mean,
		StdDev:     result.StdDev,
		SampleSize: int(result.SampleSize),
	}, nil
}

func (s *DetectionService) getAlertConfig(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, detectionType models.DetectionType) (*models.AlertConfiguration, error) {
	var config models.AlertConfiguration

	// Try shop-specific first
	if shopID != nil {
		err := s.db.WithContext(ctx).
			Where("tenant_id = ? AND shop_id = ? AND detection_type = ?", tenantID, *shopID, detectionType).
			First(&config).Error
		if err == nil {
			return &config, nil
		}
	}

	// Fall back to tenant-level
	err := s.db.WithContext(ctx).
		Where("tenant_id = ? AND shop_id IS NULL AND detection_type = ?", tenantID, detectionType).
		First(&config).Error

	return &config, err
}

func (s *DetectionService) createCashVarianceRecord(ctx context.Context, tenantID, shopID uuid.UUID, date time.Time, varType models.DetectionType, expected, actual, variance, variancePercent, zScore float64, riskLevel models.RiskLevel, staff []uuid.UUID) {
	vType := models.VarianceTypeShortage
	if variance > 0 {
		vType = models.VarianceTypeOverage
	}

	record := &models.CashVariance{
		TenantID:         tenantID,
		ShopID:           shopID,
		VarianceDate:     date,
		VarianceType:     vType,
		ExpectedAmount:   expected,
		ActualAmount:     actual,
		VarianceAmount:   variance,
		VariancePercent:  variancePercent,
		ResponsibleStaff: staff,
		Status:           "detected",
		RiskLevel:        riskLevel,
		ZScore:           &zScore,
		CreatedAt:        time.Now(),
		UpdatedAt:        time.Now(),
	}

	s.db.WithContext(ctx).Create(record)
}

func (s *DetectionService) createSuspiciousActivity(ctx context.Context, tenantID, shopID, userID uuid.UUID, detectionType models.DetectionType, riskLevel models.RiskLevel, confidence, zScore float64, description string, impact float64, transactions []uuid.UUID) {
	activity := &models.SuspiciousActivity{
		TenantID:            tenantID,
		ShopID:              shopID,
		UserID:              userID,
		DetectionType:       detectionType,
		RiskLevel:           riskLevel,
		ConfidenceScore:     confidence,
		ZScore:              &zScore,
		Description:         description,
		TotalImpact:         &impact,
		RelatedTransactions: transactions,
		Status:              "detected",
		DetectedAt:          time.Now(),
		CreatedAt:           time.Now(),
		UpdatedAt:           time.Now(),
	}

	s.db.WithContext(ctx).Create(activity)
}

func (s *DetectionService) createDetectionAlert(ctx context.Context, tenantID, shopID uuid.UUID, detectionType models.DetectionType, riskLevel models.RiskLevel, description string, impact float64, userID *uuid.UUID, config *models.AlertConfiguration) {
	now := time.Now()
	escalateAt := now.Add(time.Duration(config.EscalationMinutes) * time.Minute)

	alert := &models.DetectionAlert{
		TenantID:       tenantID,
		ShopID:         shopID,
		ConfigID:       &config.ID,
		DetectionType:  detectionType,
		RiskLevel:      riskLevel,
		Status:         models.AlertStatusActive,
		Title:          fmt.Sprintf("%s Alert", detectionType),
		Description:    description,
		AffectedUserID: userID,
		ImpactAmount:   &impact,
		TriggeredAt:    now,
		EscalateAt:     &escalateAt,
		CreatedAt:      now,
		UpdatedAt:      now,
	}

	s.db.WithContext(ctx).Create(alert)

	// Auto-create investigation if configured
	if config.AutoInvestigate && riskLevel >= config.AutoInvestigateAt {
		s.CreateInvestigation(ctx, tenantID, &models.CreateInvestigationRequest{
			ShopID:        shopID,
			Title:         fmt.Sprintf("Auto-Investigation: %s", detectionType),
			Description:   description,
			DetectionType: detectionType,
			RiskLevel:     riskLevel,
			Priority:      models.InvestigationPriorityHigh,
			EstimatedLoss: impact,
			SuspectUserID: userID,
		})
	}
}

func (s *DetectionService) generateCaseNumber(ctx context.Context, tenantID uuid.UUID) string {
	var count int64
	s.db.WithContext(ctx).Model(&models.Investigation{}).
		Where("tenant_id = ?", tenantID).
		Count(&count)

	return fmt.Sprintf("INV-%s-%05d", time.Now().Format("200601"), count+1)
}

func (s *DetectionService) getSummaryStats(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID) (*models.DetectionSummary, error) {
	summary := &models.DetectionSummary{}

	// Use int64 variables for GORM Count() compatibility
	var totalAlerts, activeAlerts, criticalAlerts, openInvestigations int64

	baseQuery := s.db.WithContext(ctx).Model(&models.DetectionAlert{}).Where("tenant_id = ?", tenantID)
	if shopID != nil {
		baseQuery = baseQuery.Where("shop_id = ?", *shopID)
	}

	baseQuery.Count(&totalAlerts)
	s.db.WithContext(ctx).Model(&models.DetectionAlert{}).
		Where("tenant_id = ?", tenantID).
		Where("status IN ('active', 'escalated')").
		Count(&activeAlerts)
	s.db.WithContext(ctx).Model(&models.DetectionAlert{}).
		Where("tenant_id = ?", tenantID).
		Where("risk_level = 'critical'").
		Count(&criticalAlerts)

	invQuery := s.db.WithContext(ctx).Model(&models.Investigation{}).Where("tenant_id = ?", tenantID)
	if shopID != nil {
		invQuery = invQuery.Where("shop_id = ?", *shopID)
	}
	invQuery.Where("status NOT LIKE 'closed%'").Count(&openInvestigations)

	// Assign to summary struct
	summary.TotalAlerts = int(totalAlerts)
	summary.ActiveAlerts = int(activeAlerts)
	summary.CriticalAlerts = int(criticalAlerts)
	summary.OpenInvestigations = int(openInvestigations)

	// Loss totals
	s.db.WithContext(ctx).Model(&models.Investigation{}).
		Select("COALESCE(SUM(estimated_loss), 0)").
		Where("tenant_id = ?", tenantID).
		Scan(&summary.EstimatedLossTotal)

	s.db.WithContext(ctx).Model(&models.Investigation{}).
		Select("COALESCE(SUM(confirmed_loss), 0)").
		Where("tenant_id = ? AND confirmed_loss IS NOT NULL", tenantID).
		Scan(&summary.ConfirmedLossTotal)

	return summary, nil
}

func (s *DetectionService) getRiskTrend(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, days int) []models.DailyRiskStat {
	var trend []models.DailyRiskStat
	startDate := time.Now().AddDate(0, 0, -days)

	query := s.db.WithContext(ctx).Model(&models.DetectionAlert{}).
		Select(`
			DATE(triggered_at) as date,
			COUNT(*) as alert_count,
			SUM(CASE WHEN risk_level = 'critical' THEN 1 ELSE 0 END) as critical_count,
			SUM(CASE WHEN risk_level = 'high' THEN 1 ELSE 0 END) as high_count,
			SUM(CASE WHEN risk_level = 'medium' THEN 1 ELSE 0 END) as medium_count,
			SUM(CASE WHEN risk_level = 'low' THEN 1 ELSE 0 END) as low_count,
			COALESCE(SUM(impact_amount), 0) as estimated_loss
		`).
		Where("tenant_id = ? AND triggered_at >= ?", tenantID, startDate)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	query.Group("DATE(triggered_at)").Order("date").Scan(&trend)
	return trend
}

func (s *DetectionService) getTopRiskUsers(ctx context.Context, tenantID uuid.UUID, shopID *uuid.UUID, limit int) []models.UserRiskProfile {
	var profiles []models.UserRiskProfile

	query := s.db.WithContext(ctx).
		Table("v_suspicious_activity_summary").
		Select(`
			user_id,
			user_name,
			user_role as role,
			shop_name,
			SUM(incident_count) as total_incidents,
			SUM(confirmed_count) as confirmed_count,
			SUM(false_positive_count) as false_positives,
			SUM(total_impact) as total_impact,
			MAX(month) as latest_incident
		`).
		Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("shop_id = ?", *shopID)
	}

	query.Group("user_id, user_name, user_role, shop_name").
		Order("total_incidents DESC").
		Limit(limit).
		Scan(&profiles)

	// Calculate risk scores
	for i := range profiles {
		profiles[i].RiskScore = calculateUserRiskScore(profiles[i])
	}

	return profiles
}

func calculateConfidence(zScore float64, sampleSize int) float64 {
	// Higher Z-score and larger sample size = higher confidence
	baseConfidence := 0.5
	if zScore > 0 {
		baseConfidence = math.Min(0.95, 0.5+zScore*0.1)
	}
	if sampleSize < 10 {
		baseConfidence *= 0.7 // Reduce confidence for small samples
	} else if sampleSize < 30 {
		baseConfidence *= 0.85
	}
	return baseConfidence
}

func calculateUserRiskScore(profile models.UserRiskProfile) float64 {
	if profile.TotalIncidents == 0 {
		return 0
	}
	confirmationRate := float64(profile.ConfirmedCount) / float64(profile.TotalIncidents)
	impactScore := math.Min(1, profile.TotalImpact/50000) // Normalize to 50k max
	frequencyScore := math.Min(1, float64(profile.TotalIncidents)/20) // Normalize to 20 incidents max

	return (confirmationRate*0.4 + impactScore*0.35 + frequencyScore*0.25) * 100
}

func newFloat64(v float64) *float64 {
	return &v
}

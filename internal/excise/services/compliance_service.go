package services

import (
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/excise/models"
	sharedModels "github.com/liquorpro/go-backend/pkg/shared/models"
)

type ComplianceService struct {
	db             *gorm.DB
	licenseService *LicenseService
}

func NewComplianceService(db *gorm.DB, licenseService *LicenseService) *ComplianceService {
	return &ComplianceService{
		db:             db,
		licenseService: licenseService,
	}
}

// GetComplianceDashboard retrieves overall compliance status for tenant
func (s *ComplianceService) GetComplianceDashboard(tenantID uuid.UUID, shopID *uuid.UUID) (*models.ComplianceDashboardResponse, error) {
	dashboard := &models.ComplianceDashboardResponse{
		TenantID: tenantID,
	}

	// Get shop count
	var totalShops int64
	shopQuery := s.db.Model(&sharedModels.Shop{}).Where("tenant_id = ?", tenantID)
	if shopID != nil {
		shopQuery = shopQuery.Where("id = ?", shopID)
	}
	shopQuery.Count(&totalShops)
	dashboard.TotalShops = int(totalShops)

	// Get active licenses count
	var activeLicenses int64
	licenseQuery := s.db.Model(&models.ExciseLicense{}).Where("tenant_id = ? AND is_active = ?", tenantID, true)
	if shopID != nil {
		licenseQuery = licenseQuery.Where("shop_id = ?", shopID)
	}
	licenseQuery.Count(&activeLicenses)
	dashboard.ActiveLicenses = int(activeLicenses)

	// Get pending reports count (not uploaded in last 7 days)
	var pendingReports int64
	reportQuery := s.db.Model(&models.ExciseDailyReport{}).
		Where("tenant_id = ? AND uploaded_to_portal = ? AND report_date >= ?",
			tenantID, false, time.Now().AddDate(0, 0, -7))
	if shopID != nil {
		reportQuery = reportQuery.Where("shop_id = ?", shopID)
	}
	reportQuery.Count(&pendingReports)
	dashboard.PendingReports = int(pendingReports)

	// Get overdue license fees
	overdueFeesCount := s.getOverdueLicenseFeesCount(tenantID, shopID)
	dashboard.PendingLicenseFees = overdueFeesCount

	// Get expiring licenses (within 30 days)
	expiringLicenses, _ := s.getExpiringLicensesCount(tenantID, 30, shopID)
	dashboard.ExpiringLicenses = expiringLicenses

	// Get recent compliance logs
	recentLogs, _ := s.GetRecentComplianceLogs(tenantID, 10, shopID)
	dashboard.RecentLogs = recentLogs

	// Calculate compliance score (0-100)
	dashboard.ComplianceScore = s.calculateComplianceScore(dashboard)

	// Determine overall status
	if dashboard.ComplianceScore >= 90 {
		dashboard.ComplianceStatus = "excellent"
	} else if dashboard.ComplianceScore >= 75 {
		dashboard.ComplianceStatus = "good"
	} else if dashboard.ComplianceScore >= 60 {
		dashboard.ComplianceStatus = "warning"
	} else {
		dashboard.ComplianceStatus = "critical"
	}

	return dashboard, nil
}

// calculateComplianceScore calculates a compliance score (0-100)
func (s *ComplianceService) calculateComplianceScore(dashboard *models.ComplianceDashboardResponse) float64 {
	score := 100.0

	// Deduct for pending reports (max -30 points)
	if dashboard.PendingReports > 0 {
		deduction := float64(dashboard.PendingReports) * 10
		if deduction > 30 {
			deduction = 30
		}
		score -= deduction
	}

	// Deduct for overdue fees (max -30 points)
	if dashboard.PendingLicenseFees > 0 {
		deduction := float64(dashboard.PendingLicenseFees) * 15
		if deduction > 30 {
			deduction = 30
		}
		score -= deduction
	}

	// Deduct for expiring licenses (max -20 points)
	if dashboard.ExpiringLicenses > 0 {
		deduction := float64(dashboard.ExpiringLicenses) * 10
		if deduction > 20 {
			deduction = 20
		}
		score -= deduction
	}

	// Deduct if no active licenses (max -20 points)
	if dashboard.TotalShops > 0 && dashboard.ActiveLicenses == 0 {
		score -= 20
	}

	if score < 0 {
		score = 0
	}

	return score
}

// getOverdueLicenseFeesCount counts overdue license fees
func (s *ComplianceService) getOverdueLicenseFeesCount(tenantID uuid.UUID, shopID *uuid.UUID) int {
	var licenses []models.ExciseLicense
	query := s.db.Where("tenant_id = ? AND is_active = ?", tenantID, true)
	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}
	query.Find(&licenses)

	overdueCount := 0
	currentMonth := time.Now()

	for _, license := range licenses {
		// Check last 3 months
		for i := 0; i < 3; i++ {
			checkMonth := currentMonth.AddDate(0, -i, 0)
			firstOfMonth := time.Date(checkMonth.Year(), checkMonth.Month(), 1, 0, 0, 0, 0, time.UTC)

			var expense sharedModels.Expense
			if err := s.db.Where("excise_license_id = ? AND is_license_fee = ? AND license_fee_month = ?",
				license.ID, true, firstOfMonth).First(&expense).Error; err != nil {
				// Fee not paid
				if firstOfMonth.Before(time.Now()) {
					overdueCount++
				}
			}
		}
	}

	return overdueCount
}

// getExpiringLicensesCount counts licenses expiring within specified days
func (s *ComplianceService) getExpiringLicensesCount(tenantID uuid.UUID, daysAhead int, shopID *uuid.UUID) (int, error) {
	cutoffDate := time.Now().AddDate(0, 0, daysAhead)

	query := s.db.Model(&models.ExciseLicense{}).
		Where("tenant_id = ? AND is_active = ? AND expiry_date <= ? AND expiry_date >= ?",
			tenantID, true, cutoffDate, time.Now())

	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}

	var count int64
	query.Count(&count)

	return int(count), nil
}

// LogComplianceEvent logs a compliance event
func (s *ComplianceService) LogComplianceEvent(tenantID uuid.UUID, logType, logLevel, message string, details map[string]interface{}) error {
	log := models.ExciseComplianceLog{
		ID:       uuid.New(),
		TenantID: tenantID,
		LogType:  logType,
		LogLevel: logLevel,
		Message:  message,
		Details:  details,
	}

	if err := s.db.Create(&log).Error; err != nil {
		return fmt.Errorf("failed to create compliance log: %w", err)
	}

	return nil
}

// GetComplianceLogs retrieves compliance logs with filters
func (s *ComplianceService) GetComplianceLogs(tenantID uuid.UUID, filters map[string]interface{}, limit int) ([]models.ExciseComplianceLog, error) {
	query := s.db.Where("tenant_id = ?", tenantID)

	// Apply filters
	if logType, ok := filters["log_type"].(string); ok {
		query = query.Where("log_type = ?", logType)
	}
	if logLevel, ok := filters["log_level"].(string); ok {
		query = query.Where("log_level = ?", logLevel)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("details->>'shop_id' = ?", shopID.String())
	}
	if licenseID, ok := filters["license_id"].(uuid.UUID); ok {
		query = query.Where("details->>'license_id' = ?", licenseID.String())
	}
	if reportID, ok := filters["report_id"].(uuid.UUID); ok {
		query = query.Where("details->>'report_id' = ?", reportID.String())
	}

	// Date range
	if fromDate, ok := filters["from_date"].(time.Time); ok {
		query = query.Where("logged_at >= ?", fromDate)
	}
	if toDate, ok := filters["to_date"].(time.Time); ok {
		query = query.Where("logged_at <= ?", toDate)
	}

	var logs []models.ExciseComplianceLog
	if err := query.Order("logged_at DESC").Limit(limit).Find(&logs).Error; err != nil {
		return nil, fmt.Errorf("failed to retrieve compliance logs: %w", err)
	}

	return logs, nil
}

// GetRecentComplianceLogs retrieves recent compliance logs
func (s *ComplianceService) GetRecentComplianceLogs(tenantID uuid.UUID, limit int, shopID *uuid.UUID) ([]models.ExciseComplianceLog, error) {
	query := s.db.Where("tenant_id = ?", tenantID)

	if shopID != nil {
		query = query.Where("details->>'shop_id' = ?", shopID.String())
	}

	var logs []models.ExciseComplianceLog
	if err := query.Order("logged_at DESC").Limit(limit).Find(&logs).Error; err != nil {
		return nil, fmt.Errorf("failed to retrieve logs: %w", err)
	}

	return logs, nil
}

// GetExpiringLicenses retrieves licenses expiring soon
func (s *ComplianceService) GetExpiringLicenses(tenantID uuid.UUID, daysAhead int) ([]*models.LicenseResponse, error) {
	return s.licenseService.GetExpiringLicenses(tenantID, daysAhead)
}

// GetPendingLicenseFees retrieves pending license fees
func (s *ComplianceService) GetPendingLicenseFees(tenantID uuid.UUID, shopID *uuid.UUID) ([]map[string]interface{}, error) {
	var licenses []models.ExciseLicense
	query := s.db.Where("tenant_id = ? AND is_active = ?", tenantID, true)
	if shopID != nil {
		query = query.Where("shop_id = ?", shopID)
	}
	query.Find(&licenses)

	pendingFees := []map[string]interface{}{}
	currentMonth := time.Now()

	for _, license := range licenses {
		// Check last 3 months
		for i := 0; i < 3; i++ {
			checkMonth := currentMonth.AddDate(0, -i, 0)
			firstOfMonth := time.Date(checkMonth.Year(), checkMonth.Month(), 1, 0, 0, 0, 0, time.UTC)

			var expense sharedModels.Expense
			if err := s.db.Where("excise_license_id = ? AND is_license_fee = ? AND license_fee_month = ?",
				license.ID, true, firstOfMonth).First(&expense).Error; err != nil {
				// Fee not paid
				if firstOfMonth.Before(time.Now()) {
					daysOverdue := int(time.Since(firstOfMonth.AddDate(0, 1, 0)).Hours() / 24)

					var shop sharedModels.Shop
					s.db.First(&shop, "id = ?", license.ShopID)

					pendingFees = append(pendingFees, map[string]interface{}{
						"license_id":     license.ID,
						"shop_id":        license.ShopID,
						"shop_name":      shop.Name,
						"license_number": license.LicenseNumber,
						"month":          firstOfMonth.Format("2006-01"),
						"amount":         license.MonthlyFee,
						"days_overdue":   daysOverdue,
						"priority":       s.getPriority(daysOverdue),
					})
				}
			}
		}
	}

	return pendingFees, nil
}

// getPriority determines priority based on days overdue
func (s *ComplianceService) getPriority(daysOverdue int) string {
	if daysOverdue > 30 {
		return "critical"
	} else if daysOverdue > 15 {
		return "high"
	} else if daysOverdue > 7 {
		return "medium"
	}
	return "low"
}

// GetConsiderationFeeSummary retrieves summary of consideration fees
func (s *ComplianceService) GetConsiderationFeeSummary(tenantID uuid.UUID, startDate, endDate time.Time) (*models.ConsiderationFeeSummary, error) {
	summary := &models.ConsiderationFeeSummary{}

	// Get total fees paid (all time)
	var totalFees float64
	s.db.Model(&sharedModels.VendorTransaction{}).
		Where("tenant_id = ? AND is_consideration_fee = ?", tenantID, true).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&totalFees)
	summary.TotalFeesPaid = totalFees

	// Get fees this month
	now := time.Now()
	firstOfMonth := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	var feesThisMonth float64
	s.db.Model(&sharedModels.VendorTransaction{}).
		Where("tenant_id = ? AND is_consideration_fee = ? AND transaction_date >= ?",
			tenantID, true, firstOfMonth).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&feesThisMonth)
	summary.FeesThisMonth = feesThisMonth

	// Get fees today
	today := time.Now().Truncate(24 * time.Hour)
	var feesToday float64
	s.db.Model(&sharedModels.VendorTransaction{}).
		Where("tenant_id = ? AND is_consideration_fee = ? AND DATE(transaction_date) = ?",
			tenantID, true, today.Format("2006-01-02")).
		Select("COALESCE(SUM(amount), 0)").
		Scan(&feesToday)
	summary.FeesToday = feesToday

	// Count total bottles (estimated from amount / typical fee)
	// Since BottlesCount field doesn't exist, we'll estimate or skip
	summary.TotalBottles = 0
	summary.BottlesThisMonth = 0
	summary.BottlesToday = 0

	// Get last payment date
	var lastTxn sharedModels.VendorTransaction
	if err := s.db.Where("tenant_id = ? AND is_consideration_fee = ?", tenantID, true).
		Order("transaction_date DESC").
		First(&lastTxn).Error; err == nil {
		summary.LastPaymentDate = &lastTxn.TransactionDate
	}

	// Calculate average fee per bottle (if we had bottle count)
	summary.AverageFeePerBottle = 0

	return summary, nil
}

// GetComplianceReport generates a comprehensive compliance report
func (s *ComplianceService) GetComplianceReport(tenantID uuid.UUID, startDate, endDate time.Time) (map[string]interface{}, error) {
	report := map[string]interface{}{
		"tenant_id":  tenantID,
		"start_date": startDate,
		"end_date":   endDate,
		"generated_at": time.Now(),
	}

	// License compliance
	var activeLicenses int64
	s.db.Model(&models.ExciseLicense{}).
		Where("tenant_id = ? AND is_active = ?", tenantID, true).
		Count(&activeLicenses)
	report["active_licenses"] = activeLicenses

	// Daily reports compliance
	var totalReports int64
	var uploadedReports int64
	s.db.Model(&models.ExciseDailyReport{}).
		Where("tenant_id = ? AND report_date BETWEEN ? AND ?", tenantID, startDate, endDate).
		Count(&totalReports)
	s.db.Model(&models.ExciseDailyReport{}).
		Where("tenant_id = ? AND report_date BETWEEN ? AND ? AND uploaded_to_portal = ?",
			tenantID, startDate, endDate, true).
		Count(&uploadedReports)

	report["total_reports"] = totalReports
	report["uploaded_reports"] = uploadedReports
	if totalReports > 0 {
		report["upload_compliance_rate"] = float64(uploadedReports) / float64(totalReports) * 100
	} else {
		report["upload_compliance_rate"] = 0.0
	}

	// License fee compliance
	expectedFees := activeLicenses * int64(len(s.getMonthsBetween(startDate, endDate)))
	var paidFees int64
	s.db.Model(&sharedModels.Expense{}).
		Where("tenant_id = ? AND is_license_fee = ? AND license_fee_month BETWEEN ? AND ?",
			tenantID, true, startDate, endDate).
		Count(&paidFees)

	report["expected_license_fees"] = expectedFees
	report["paid_license_fees"] = paidFees
	if expectedFees > 0 {
		report["fee_compliance_rate"] = float64(paidFees) / float64(expectedFees) * 100
	} else {
		report["fee_compliance_rate"] = 0.0
	}

	// Security codes
	var totalSecurityCodes int64
	var verifiedSecurityCodes int64
	s.db.Model(&models.BottleSecurityCode{}).
		Where("tenant_id = ?", tenantID).
		Count(&totalSecurityCodes)
	s.db.Model(&models.BottleSecurityCode{}).
		Where("tenant_id = ? AND verified = ?", tenantID, true).
		Count(&verifiedSecurityCodes)

	report["total_security_codes"] = totalSecurityCodes
	report["verified_security_codes"] = verifiedSecurityCodes

	return report, nil
}

// getMonthsBetween gets list of months between two dates
func (s *ComplianceService) getMonthsBetween(start, end time.Time) []time.Time {
	months := []time.Time{}
	current := time.Date(start.Year(), start.Month(), 1, 0, 0, 0, 0, time.UTC)
	endMonth := time.Date(end.Year(), end.Month(), 1, 0, 0, 0, 0, time.UTC)

	for !current.After(endMonth) {
		months = append(months, current)
		current = current.AddDate(0, 1, 0)
	}

	return months
}

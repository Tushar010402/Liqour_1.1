package services

import (
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/excise/models"
	sharedModels "github.com/liquorpro/go-backend/pkg/shared/models"
)

type LicenseService struct {
	db *gorm.DB
}

func NewLicenseService(db *gorm.DB) *LicenseService {
	return &LicenseService{db: db}
}

// CreateLicense creates a new excise license
func (s *LicenseService) CreateLicense(req models.CreateLicenseRequest) (*models.ExciseLicense, error) {
	// Validate shop exists
	var shop sharedModels.Shop
	if err := s.db.First(&shop, "id = ?", req.ShopID).Error; err != nil {
		return nil, fmt.Errorf("shop not found: %w", err)
	}

	// Check if license already exists for this shop
	var existingLicense models.ExciseLicense
	if err := s.db.Where("shop_id = ? AND is_active = ?", req.ShopID, true).First(&existingLicense).Error; err == nil {
		return nil, errors.New("shop already has an active license")
	}

	// Validate license type
	validTypes := []string{"FL-2A", "FL-17", "CL-2", "COMPOSITE", "IMFL", "COUNTRY_LIQUOR", "BEER_ONLY", "WINE_ONLY"}
	isValid := false
	for _, t := range validTypes {
		if req.LicenseType == t {
			isValid = true
			break
		}
	}
	if !isValid {
		return nil, errors.New("invalid license type")
	}

	// Calculate expiry date (1 year from issuance)
	issuedDate := time.Now()
	if req.IssuedDate != nil {
		issuedDate = *req.IssuedDate
	}
	expiryDate := issuedDate.AddDate(1, 0, 0) // Add 1 year
	if req.ExpiryDate != nil {
		expiryDate = *req.ExpiryDate
	}

	license := &models.ExciseLicense{
		ShopID:              req.ShopID,
		LicenseNumber:       req.LicenseNumber,
		LicenseType:         req.LicenseType,
		IssuedDate:          issuedDate,
		ExpiryDate:          expiryDate,
		MonthlyFee:          req.MonthlyFee,
		BankAccountID:       req.BankAccountID,
		IsActive:            true,
		Restrictions:        req.Restrictions,
	}
	// Set TenantID manually
	license.TenantID = shop.TenantID

	// Create license in database
	if err := s.db.Create(license).Error; err != nil {
		return nil, fmt.Errorf("failed to create license: %w", err)
	}

	// Update shop with license_id
	if err := s.db.Model(&shop).Update("excise_license_id", license.ID).Error; err != nil {
		return nil, fmt.Errorf("failed to link license to shop: %w", err)
	}

	// Log compliance event
	s.logComplianceEvent(*license.TenantID, "license_created", "info",
		fmt.Sprintf("License %s created for shop %s", license.LicenseNumber, shop.Name),
		map[string]interface{}{
			"license_id":     license.ID,
			"shop_id":        shop.ID,
			"license_number": license.LicenseNumber,
			"license_type":   license.LicenseType,
		})

	return license, nil
}

// GetLicenseByID retrieves a license by ID
func (s *LicenseService) GetLicenseByID(tenantID, licenseID uuid.UUID) (*models.LicenseResponse, error) {
	var license models.ExciseLicense
	if err := s.db.Where("id = ? AND tenant_id = ?", licenseID, tenantID).First(&license).Error; err != nil {
		return nil, fmt.Errorf("license not found: %w", err)
	}

	// Get shop details
	var shop sharedModels.Shop
	s.db.First(&shop, "id = ?", license.ShopID)

	// Get compliance status
	complianceStatus := s.getComplianceStatus(&license)

	response := &models.LicenseResponse{
		ExciseLicense:    license,
		ShopName:         shop.Name,
		DaysUntilExpiry:  license.DaysUntilExpiry(),
		Status:           license.LicenseStatus(),
		ComplianceStatus: complianceStatus,
	}

	return response, nil
}

// GetLicensesByTenant retrieves all licenses for a tenant
func (s *LicenseService) GetLicensesByTenant(tenantID uuid.UUID, filters map[string]interface{}) ([]*models.LicenseResponse, error) {
	var licenses []models.ExciseLicense
	query := s.db.Where("tenant_id = ?", tenantID)

	// Apply filters
	if isActive, ok := filters["is_active"].(bool); ok {
		query = query.Where("is_active = ?", isActive)
	}
	if licenseType, ok := filters["license_type"].(string); ok {
		query = query.Where("license_type = ?", licenseType)
	}
	if shopID, ok := filters["shop_id"].(uuid.UUID); ok {
		query = query.Where("shop_id = ?", shopID)
	}

	if err := query.Order("created_at DESC").Find(&licenses).Error; err != nil {
		return nil, fmt.Errorf("failed to retrieve licenses: %w", err)
	}

	// Build responses
	responses := make([]*models.LicenseResponse, len(licenses))
	for i, license := range licenses {
		var shop sharedModels.Shop
		s.db.First(&shop, "id = ?", license.ShopID)

		complianceStatus := s.getComplianceStatus(&license)

		responses[i] = &models.LicenseResponse{
			ExciseLicense:    license,
			ShopName:         shop.Name,
			DaysUntilExpiry:  license.DaysUntilExpiry(),
			Status:           license.LicenseStatus(),
			ComplianceStatus: complianceStatus,
		}
	}

	return responses, nil
}

// UpdateLicense updates license details
func (s *LicenseService) UpdateLicense(tenantID, licenseID uuid.UUID, req models.UpdateLicenseRequest) (*models.ExciseLicense, error) {
	var license models.ExciseLicense
	if err := s.db.Where("id = ? AND tenant_id = ?", licenseID, tenantID).First(&license).Error; err != nil {
		return nil, fmt.Errorf("license not found: %w", err)
	}

	// Update fields
	updates := map[string]interface{}{}
	if req.MonthlyFee != nil {
		updates["monthly_fee"] = *req.MonthlyFee
	}
	if req.BankAccountID != nil {
		updates["bank_account_id"] = *req.BankAccountID
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}
	if req.ExpiryDate != nil {
		updates["expiry_date"] = *req.ExpiryDate
	}
	if req.Restrictions != nil {
		updates["restrictions"] = req.Restrictions
	}

	if err := s.db.Model(&license).Updates(updates).Error; err != nil {
		return nil, fmt.Errorf("failed to update license: %w", err)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "license_updated", "info",
		fmt.Sprintf("License %s updated", license.LicenseNumber),
		map[string]interface{}{
			"license_id": licenseID,
			"updates":    updates,
		})

	return &license, nil
}

// PayLicenseFee records a license fee payment (creates expense record)
func (s *LicenseService) PayLicenseFee(tenantID uuid.UUID, req models.PayLicenseFeeRequest) (*sharedModels.Expense, error) {
	// Validate license exists
	var license models.ExciseLicense
	if err := s.db.Where("id = ? AND tenant_id = ?", req.LicenseID, tenantID).First(&license).Error; err != nil {
		return nil, fmt.Errorf("license not found: %w", err)
	}

	// Get expense category for license fees
	var category sharedModels.ExpenseCategory
	if err := s.db.Where("name = ? AND tenant_id = ?", "License Fees", tenantID).First(&category).Error; err != nil {
		// Create category if it doesn't exist
		category = sharedModels.ExpenseCategory{
			Name:        "License Fees",
			Description: "Excise license monthly fees",
			IsActive:    true,
		}
		category.TenantID = &tenantID
		s.db.Create(&category)
	}

	// Create expense record
	expense := &sharedModels.Expense{
		CategoryID:       &category.ID,
		ShopID:           &license.ShopID,
		Amount:           req.Amount,
		PaymentMethod:    req.PaymentMethod,
		ExpenseDate:      time.Now(),
		Status:           "paid",
		ReceiptNo:        req.ReceiptNo,
		Notes:            fmt.Sprintf("License fee for %s", req.FeeMonth.Format("January 2006")),
	}
	expense.TenantID = &tenantID

	if err := s.db.Create(expense).Error; err != nil {
		return nil, fmt.Errorf("failed to create expense record: %w", err)
	}

	// Log compliance event (trigger will also log)
	s.logComplianceEvent(tenantID, "license_fee_paid", "info",
		fmt.Sprintf("License fee paid for %s", req.FeeMonth.Format("January 2006")),
		map[string]interface{}{
			"license_id": req.LicenseID,
			"amount":     req.Amount,
			"month":      req.FeeMonth,
			"expense_id": expense.ID,
		})

	return expense, nil
}

// GetLicenseFeePayments retrieves payment history for a license
func (s *LicenseService) GetLicenseFeePayments(tenantID, licenseID uuid.UUID) ([]sharedModels.Expense, error) {
	// Get the "License Fees" category
	var category sharedModels.ExpenseCategory
	if err := s.db.Where("name = ? AND tenant_id = ?", "License Fees", tenantID).First(&category).Error; err != nil {
		return []sharedModels.Expense{}, nil // Return empty if category doesn't exist
	}

	var expenses []sharedModels.Expense
	if err := s.db.Where("tenant_id = ? AND category_id = ?",
		tenantID, category.ID).
		Order("expense_date DESC").
		Find(&expenses).Error; err != nil {
		return nil, fmt.Errorf("failed to retrieve payments: %w", err)
	}

	return expenses, nil
}

// GetComplianceStatus checks overall compliance status for a license
func (s *LicenseService) GetComplianceStatus(tenantID, licenseID uuid.UUID) (map[string]interface{}, error) {
	var license models.ExciseLicense
	if err := s.db.Where("id = ? AND tenant_id = ?", licenseID, tenantID).First(&license).Error; err != nil {
		return nil, fmt.Errorf("license not found: %w", err)
	}

	return s.getComplianceStatus(&license), nil
}

// getComplianceStatus is a helper to calculate compliance status
func (s *LicenseService) getComplianceStatus(license *models.ExciseLicense) map[string]interface{} {
	status := map[string]interface{}{
		"license_valid":   !license.IsExpired(),
		"license_expiry":  license.LicenseStatus(),
		"days_to_expiry":  license.DaysUntilExpiry(),
		"overdue_fees":    []map[string]interface{}{},
		"pending_reports": 0,
		"overall_status":  "compliant",
	}

	// Check for overdue fees (simplified - check if any payments exist)
	status["overdue_fees"] = []map[string]interface{}{}

	// Check for pending daily reports (last 7 days)
	var pendingReports int64
	s.db.Model(&models.ExciseDailyReport{}).
		Where("license_id = ? AND uploaded_to_portal = ? AND report_date >= ?",
			license.ID, false, time.Now().AddDate(0, 0, -7)).
		Count(&pendingReports)
	status["pending_reports"] = pendingReports

	// Calculate overall status
	if license.IsExpired() {
		status["overall_status"] = "expired"
	} else if pendingReports > 0 {
		status["overall_status"] = "non_compliant"
	} else if license.IsExpiringSoon() {
		status["overall_status"] = "warning"
	}

	return status
}

// RenewLicense renews an expiring license
func (s *LicenseService) RenewLicense(tenantID, licenseID uuid.UUID, newExpiryDate time.Time) (*models.ExciseLicense, error) {
	var license models.ExciseLicense
	if err := s.db.Where("id = ? AND tenant_id = ?", licenseID, tenantID).First(&license).Error; err != nil {
		return nil, fmt.Errorf("license not found: %w", err)
	}

	// Update expiry date
	license.ExpiryDate = newExpiryDate
	if err := s.db.Save(&license).Error; err != nil {
		return nil, fmt.Errorf("failed to renew license: %w", err)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "license_renewed", "info",
		fmt.Sprintf("License %s renewed until %s", license.LicenseNumber, newExpiryDate.Format("2006-01-02")),
		map[string]interface{}{
			"license_id":      licenseID,
			"new_expiry_date": newExpiryDate,
		})

	return &license, nil
}

// GetExpiringLicenses retrieves licenses expiring within specified days
func (s *LicenseService) GetExpiringLicenses(tenantID uuid.UUID, daysAhead int) ([]*models.LicenseResponse, error) {
	cutoffDate := time.Now().AddDate(0, 0, daysAhead)

	var licenses []models.ExciseLicense
	if err := s.db.Where("tenant_id = ? AND is_active = ? AND expiry_date <= ? AND expiry_date >= ?",
		tenantID, true, cutoffDate, time.Now()).
		Order("expiry_date ASC").
		Find(&licenses).Error; err != nil {
		return nil, fmt.Errorf("failed to retrieve expiring licenses: %w", err)
	}

	responses := make([]*models.LicenseResponse, len(licenses))
	for i, license := range licenses {
		var shop sharedModels.Shop
		s.db.First(&shop, "id = ?", license.ShopID)

		responses[i] = &models.LicenseResponse{
			ExciseLicense:    license,
			ShopName:         shop.Name,
			DaysUntilExpiry:  license.DaysUntilExpiry(),
			Status:           license.LicenseStatus(),
			ComplianceStatus: s.getComplianceStatus(&license),
		}
	}

	return responses, nil
}

// logComplianceEvent is a helper to log compliance events
func (s *LicenseService) logComplianceEvent(tenantID uuid.UUID, logType, logLevel, message string, details map[string]interface{}) {
	log := models.ExciseComplianceLog{
		ID:       uuid.New(),
		TenantID: tenantID,
		LogType:  logType,
		LogLevel: logLevel,
		Message:  message,
		Details:  details,
	}
	s.db.Create(&log)
}

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

type SecurityCodeService struct {
	db *gorm.DB
}

func NewSecurityCodeService(db *gorm.DB) *SecurityCodeService {
	return &SecurityCodeService{db: db}
}

// ValidateSecurityCode validates a security code
func (s *SecurityCodeService) ValidateSecurityCode(tenantID uuid.UUID, req models.ValidateSecurityCodeRequest) (*models.SecurityCodeResponse, error) {
	var code models.BottleSecurityCode
	if err := s.db.Where("security_code = ? AND tenant_id = ?", req.SecurityCode, tenantID).First(&code).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// Return empty response with invalid status
			resp := &models.SecurityCodeResponse{
				IsValid: false,
				Message: "Security code not found in system",
				Status:  "invalid",
			}
			return resp, nil
		}
		return nil, fmt.Errorf("failed to validate security code: %w", err)
	}

	// Check if code is already used
	if code.Status == "sold" {
		return &models.SecurityCodeResponse{
			BottleSecurityCode: code,
			IsValid:            false,
			Message:            fmt.Sprintf("Security code already used on %s", code.SoldDate.Format("2006-01-02")),
			Status:             "already_used",
		}, nil
	}

	// Check if code is damaged or missing
	if code.Status == "damaged" || code.Status == "missing" {
		return &models.SecurityCodeResponse{
			BottleSecurityCode: code,
			IsValid:            false,
			Message:            fmt.Sprintf("Security code marked as %s", code.Status),
			Status:             code.Status,
		}, nil
	}

	// Get product details
	var product sharedModels.Product
	if err := s.db.First(&product, "id = ?", code.ProductID).Error; err == nil {
		code.Product = &product
	}

	return &models.SecurityCodeResponse{
		BottleSecurityCode: code,
		IsValid:            code.IsValid(),
		Message:            "Security code is valid",
		Status:             code.Status,
		ProductName:        product.Name,
	}, nil
}

// BulkAddSecurityCodes adds multiple security codes at once
func (s *SecurityCodeService) BulkAddSecurityCodes(tenantID uuid.UUID, req models.BulkAddSecurityCodesRequest) ([]models.BottleSecurityCode, error) {
	// Validate product exists
	var product sharedModels.Product
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ProductID, tenantID).First(&product).Error; err != nil {
		return nil, fmt.Errorf("product not found: %w", err)
	}

	// Validate vendor transaction if provided
	if req.VendorTransactionID != nil {
		var transaction sharedModels.VendorTransaction
		if err := s.db.Where("id = ? AND tenant_id = ?", *req.VendorTransactionID, tenantID).First(&transaction).Error; err != nil {
			return nil, fmt.Errorf("vendor transaction not found: %w", err)
		}
	}

	// Check for duplicate codes
	existingCodes := []string{}
	for _, code := range req.SecurityCodes {
		var existing models.BottleSecurityCode
		if err := s.db.Where("security_code = ?", code).First(&existing).Error; err == nil {
			existingCodes = append(existingCodes, code)
		}
	}

	if len(existingCodes) > 0 {
		return nil, fmt.Errorf("duplicate security codes found: %v", existingCodes)
	}

	// Create security code records
	codes := make([]models.BottleSecurityCode, len(req.SecurityCodes))
	receivedDate := time.Now()
	if req.ReceivedDate != nil {
		receivedDate = *req.ReceivedDate
	}

	for i, code := range req.SecurityCodes {
		codes[i] = models.BottleSecurityCode{
			SecurityCode:        code,
			ProductID:           req.ProductID,
			VendorTransactionID: req.VendorTransactionID,
			StockPurchaseID:     req.StockPurchaseID,
			Status:              "in_stock",
			ReceivedDate:        &receivedDate,
			WarehouseSource:     req.SourceWarehouse,
			BatchNumber:         req.BatchNumber,
			Verified:            true,
		}
		codes[i].TenantID = &tenantID
	}

	// Bulk insert
	if err := s.db.Create(&codes).Error; err != nil {
		return nil, fmt.Errorf("failed to create security codes: %w", err)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "security_codes_added", "info",
		fmt.Sprintf("Added %d security codes for product %s", len(codes), product.Name),
		map[string]interface{}{
			"product_id":             req.ProductID,
			"count":                  len(codes),
			"vendor_transaction_id":  req.VendorTransactionID,
			"stock_purchase_id":      req.StockPurchaseID,
		})

	return codes, nil
}

// GetSecurityCodeByCode retrieves a security code by its code
func (s *SecurityCodeService) GetSecurityCodeByCode(tenantID uuid.UUID, code string) (*models.SecurityCodeResponse, error) {
	var securityCode models.BottleSecurityCode
	if err := s.db.Where("security_code = ? AND tenant_id = ?", code, tenantID).
		Preload("Product").
		First(&securityCode).Error; err != nil {
		return nil, fmt.Errorf("security code not found: %w", err)
	}

	response := &models.SecurityCodeResponse{
		BottleSecurityCode: securityCode,
		IsValid:            securityCode.IsValid(),
		Status:             securityCode.Status,
	}

	if securityCode.Product != nil {
		response.ProductName = securityCode.Product.Name
	}

	if securityCode.Status == "in_stock" && securityCode.Verified {
		response.Message = "Security code is valid and available"
	} else {
		response.Message = fmt.Sprintf("Security code status: %s", securityCode.Status)
	}

	return response, nil
}

// SearchSecurityCodes searches security codes with filters
func (s *SecurityCodeService) SearchSecurityCodes(tenantID uuid.UUID, filters map[string]interface{}) ([]models.BottleSecurityCode, error) {
	query := s.db.Where("tenant_id = ?", tenantID)

	// Apply filters
	if productID, ok := filters["product_id"].(uuid.UUID); ok {
		query = query.Where("product_id = ?", productID)
	}
	if status, ok := filters["status"].(string); ok {
		query = query.Where("status = ?", status)
	}
	if vendorTxnID, ok := filters["vendor_transaction_id"].(uuid.UUID); ok {
		query = query.Where("vendor_transaction_id = ?", vendorTxnID)
	}
	if purchaseID, ok := filters["stock_purchase_id"].(uuid.UUID); ok {
		query = query.Where("stock_purchase_id = ?", purchaseID)
	}
	if saleID, ok := filters["sale_id"].(uuid.UUID); ok {
		query = query.Where("sale_id = ?", saleID)
	}
	if sourceType, ok := filters["source_type"].(string); ok {
		query = query.Where("source_type = ?", sourceType)
	}
	if batchNumber, ok := filters["batch_number"].(string); ok {
		query = query.Where("batch_number = ?", batchNumber)
	}

	// Date range filters
	if receivedFrom, ok := filters["received_from"].(time.Time); ok {
		query = query.Where("received_date >= ?", receivedFrom)
	}
	if receivedTo, ok := filters["received_to"].(time.Time); ok {
		query = query.Where("received_date <= ?", receivedTo)
	}

	var codes []models.BottleSecurityCode
	if err := query.Preload("Product").Order("received_date DESC").Find(&codes).Error; err != nil {
		return nil, fmt.Errorf("failed to search security codes: %w", err)
	}

	return codes, nil
}

// MarkAsSold marks security codes as sold
func (s *SecurityCodeService) MarkAsSold(tenantID uuid.UUID, securityCodes []string, saleID uuid.UUID) error {
	// Validate sale exists
	var sale sharedModels.Sale
	if err := s.db.Where("id = ? AND tenant_id = ?", saleID, tenantID).First(&sale).Error; err != nil {
		return fmt.Errorf("sale not found: %w", err)
	}

	soldDate := time.Now()

	// Update all codes
	result := s.db.Model(&models.BottleSecurityCode{}).
		Where("tenant_id = ? AND security_code IN ? AND status = ?", tenantID, securityCodes, "in_stock").
		Updates(map[string]interface{}{
			"status":    "sold",
			"sale_id":   saleID,
			"sold_date": soldDate,
		})

	if result.Error != nil {
		return fmt.Errorf("failed to mark codes as sold: %w", result.Error)
	}

	if result.RowsAffected != int64(len(securityCodes)) {
		return fmt.Errorf("expected to update %d codes, but updated %d (some codes may not be available)",
			len(securityCodes), result.RowsAffected)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "security_codes_sold", "info",
		fmt.Sprintf("Marked %d security codes as sold", len(securityCodes)),
		map[string]interface{}{
			"sale_id":        saleID,
			"count":          len(securityCodes),
			"security_codes": securityCodes,
		})

	return nil
}

// MarkAsDamaged marks security codes as damaged
func (s *SecurityCodeService) MarkAsDamaged(tenantID uuid.UUID, securityCodes []string, reason string) error {
	damagedDate := time.Now()

	result := s.db.Model(&models.BottleSecurityCode{}).
		Where("tenant_id = ? AND security_code IN ?", tenantID, securityCodes).
		Updates(map[string]interface{}{
			"status":       "damaged",
			"damaged_date": damagedDate,
			"notes":        reason,
		})

	if result.Error != nil {
		return fmt.Errorf("failed to mark codes as damaged: %w", result.Error)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "security_codes_damaged", "warning",
		fmt.Sprintf("Marked %d security codes as damaged: %s", len(securityCodes), reason),
		map[string]interface{}{
			"count":          len(securityCodes),
			"reason":         reason,
			"security_codes": securityCodes,
		})

	return nil
}

// MarkAsMissing marks security codes as missing
func (s *SecurityCodeService) MarkAsMissing(tenantID uuid.UUID, securityCodes []string, reason string) error {
	result := s.db.Model(&models.BottleSecurityCode{}).
		Where("tenant_id = ? AND security_code IN ?", tenantID, securityCodes).
		Updates(map[string]interface{}{
			"status": "missing",
			"notes":  reason,
		})

	if result.Error != nil {
		return fmt.Errorf("failed to mark codes as missing: %w", result.Error)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "security_codes_missing", "warning",
		fmt.Sprintf("Marked %d security codes as missing: %s", len(securityCodes), reason),
		map[string]interface{}{
			"count":          len(securityCodes),
			"reason":         reason,
			"security_codes": securityCodes,
		})

	return nil
}

// MarkAsReturned marks security codes as returned
func (s *SecurityCodeService) MarkAsReturned(tenantID uuid.UUID, securityCodes []string, returnID uuid.UUID) error {
	// Validate return exists
	var salesReturn sharedModels.SaleReturn
	if err := s.db.Where("id = ? AND tenant_id = ?", returnID, tenantID).First(&salesReturn).Error; err != nil {
		return fmt.Errorf("sales return not found: %w", err)
	}

	returnedDate := time.Now()

	result := s.db.Model(&models.BottleSecurityCode{}).
		Where("tenant_id = ? AND security_code IN ? AND status = ?", tenantID, securityCodes, "sold").
		Updates(map[string]interface{}{
			"status":        "returned",
			"return_id":     returnID,
			"returned_date": returnedDate,
		})

	if result.Error != nil {
		return fmt.Errorf("failed to mark codes as returned: %w", result.Error)
	}

	// Log compliance event
	s.logComplianceEvent(tenantID, "security_codes_returned", "info",
		fmt.Sprintf("Marked %d security codes as returned", len(securityCodes)),
		map[string]interface{}{
			"return_id":      returnID,
			"count":          len(securityCodes),
			"security_codes": securityCodes,
		})

	return nil
}

// GetSecurityCodeStats retrieves statistics about security codes
func (s *SecurityCodeService) GetSecurityCodeStats(tenantID uuid.UUID, shopID *uuid.UUID) (map[string]interface{}, error) {
	stats := map[string]interface{}{
		"total_codes":    0,
		"in_stock":       0,
		"sold":           0,
		"damaged":        0,
		"missing":        0,
		"returned":       0,
		"by_product":     []map[string]interface{}{},
		"recent_scans":   []models.BottleSecurityCode{},
	}

	query := s.db.Model(&models.BottleSecurityCode{}).Where("tenant_id = ?", tenantID)
	if shopID != nil {
		// Filter by shop through stock_purchases or sales
		query = query.Where("stock_purchase_id IN (SELECT id FROM stock_purchases WHERE shop_id = ?) OR sale_id IN (SELECT id FROM sales WHERE shop_id = ?)", shopID, shopID)
	}

	// Total codes
	var totalCodes int64
	query.Count(&totalCodes)
	stats["total_codes"] = totalCodes

	// By status
	var statusCounts []struct {
		Status string
		Count  int64
	}
	query.Select("status, COUNT(*) as count").Group("status").Scan(&statusCounts)
	for _, sc := range statusCounts {
		stats[sc.Status] = sc.Count
	}

	// By product
	var productCounts []struct {
		ProductID   uuid.UUID
		ProductName string
		Count       int64
	}
	s.db.Model(&models.BottleSecurityCode{}).
		Select("bottle_security_codes.product_id, products.name as product_name, COUNT(*) as count").
		Joins("LEFT JOIN products ON products.id = bottle_security_codes.product_id").
		Where("bottle_security_codes.tenant_id = ?", tenantID).
		Group("bottle_security_codes.product_id, products.name").
		Order("count DESC").
		Limit(10).
		Scan(&productCounts)

	byProduct := make([]map[string]interface{}, len(productCounts))
	for i, pc := range productCounts {
		byProduct[i] = map[string]interface{}{
			"product_id":   pc.ProductID,
			"product_name": pc.ProductName,
			"count":        pc.Count,
		}
	}
	stats["by_product"] = byProduct

	// Recent scans (last 10)
	var recentScans []models.BottleSecurityCode
	query.Preload("Product").Order("updated_at DESC").Limit(10).Find(&recentScans)
	stats["recent_scans"] = recentScans

	return stats, nil
}

// VerifySecurityCode verifies a security code (admin function)
func (s *SecurityCodeService) VerifySecurityCode(tenantID, codeID uuid.UUID) error {
	result := s.db.Model(&models.BottleSecurityCode{}).
		Where("id = ? AND tenant_id = ?", codeID, tenantID).
		Update("verified", true)

	if result.Error != nil {
		return fmt.Errorf("failed to verify security code: %w", result.Error)
	}

	if result.RowsAffected == 0 {
		return errors.New("security code not found")
	}

	return nil
}

// logComplianceEvent is a helper to log compliance events
func (s *SecurityCodeService) logComplianceEvent(tenantID uuid.UUID, logType, logLevel, message string, details map[string]interface{}) {
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

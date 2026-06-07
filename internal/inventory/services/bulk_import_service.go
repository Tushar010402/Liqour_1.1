package services

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// BulkImportService handles bulk import operations from Excel/CSV
type BulkImportService struct {
	db                   *gorm.DB
	logger               *logrus.Logger
	brandOnboardingService *BrandOnboardingService
	stockService         *StockService
	saaSBrandClient      *SaaSBrandClient
}

// NewBulkImportService creates a new bulk import service
func NewBulkImportService(
	db *gorm.DB,
	logger *logrus.Logger,
	brandOnboardingService *BrandOnboardingService,
	stockService *StockService,
	saaSBrandClient *SaaSBrandClient,
) *BulkImportService {
	return &BulkImportService{
		db:                   db,
		logger:               logger,
		brandOnboardingService: brandOnboardingService,
		stockService:         stockService,
		saaSBrandClient:      saaSBrandClient,
	}
}

// ParseAndValidateExcel parses Excel file and validates all rows with smart brand matching
func (s *BulkImportService) ParseAndValidateExcel(
	ctx context.Context,
	fileReader io.Reader,
	fileName string,
	req models.BulkImportRequest,
) (*models.ImportValidationResult, error) {
	startTime := time.Now()

	// Create import history record
	importHistory := models.ImportHistory{
		ID:         uuid.New(),
		TenantID:   req.TenantID,
		UserID:     req.UserID,
		ShopID:     req.ShopID,
		ImportType: req.ImportType,
		Status:     models.ImportStatusValidating,
		FileName:   fileName,
		CreatedAt:  time.Now(),
		UpdatedAt:  time.Now(),
	}

	if err := s.db.Create(&importHistory).Error; err != nil {
		s.logger.Errorf("Failed to create import history: %v", err)
		return nil, fmt.Errorf("failed to create import history: %w", err)
	}

	// Parse Excel file
	xlsxFile, err := excelize.OpenReader(fileReader)
	if err != nil {
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, fmt.Sprintf("Failed to open Excel file: %v", err))
		return nil, fmt.Errorf("failed to open Excel file: %w", err)
	}
	defer xlsxFile.Close()

	// Get first sheet
	sheetName := xlsxFile.GetSheetName(0)
	if sheetName == "" {
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, "Excel file is empty")
		return nil, fmt.Errorf("excel file has no sheets")
	}

	rows, err := xlsxFile.GetRows(sheetName)
	if err != nil {
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, fmt.Sprintf("Failed to read rows: %v", err))
		return nil, fmt.Errorf("failed to read rows: %w", err)
	}

	if len(rows) < 2 {
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, "Excel file must have at least header + 1 data row")
		return nil, fmt.Errorf("insufficient rows in Excel file")
	}

	// Parse header to detect column mapping
	header := rows[0]
	columnMap := s.parseHeader(header)

	// Validate required columns
	requiredColumns := []string{"brand_name", "size", "category"}
	missingColumns := []string{}
	for _, col := range requiredColumns {
		if columnMap[col] == -1 {
			missingColumns = append(missingColumns, col)
		}
	}

	if len(missingColumns) > 0 {
		errMsg := fmt.Sprintf("Missing required columns: %v", missingColumns)
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, errMsg)
		return nil, fmt.Errorf(errMsg)
	}

	// Fetch SaaS brands catalog for matching
	saaSBrands, err := s.saaSBrandClient.GetAllBrandTemplates(true) // include variants
	if err != nil {
		s.logger.Warnf("Failed to fetch SaaS brands for matching: %v", err)
		saaSBrands = []SaaSBrandTemplate{} // Continue without smart matching
	}

	// Fetch tenant's shops for shop name matching
	shops, err := s.getTenantShops(req.TenantID)
	if err != nil {
		s.logger.Warnf("Failed to fetch shops: %v", err)
		shops = []models.Shop{}
	}

	// Parse and validate all data rows
	importRows := []models.ImportRow{}
	validCount := 0
	invalidCount := 0

	for rowNum := 1; rowNum < len(rows); rowNum++ { // Skip header
		row := rows[rowNum]

		// Skip empty rows
		if s.isEmptyRow(row) {
			continue
		}

		importRow := s.parseRow(row, rowNum+1, columnMap, shops)

		// Validate row
		s.validateRow(&importRow, req)

		// Smart brand matching
		if importRow.IsValid {
			matchResult := s.smartBrandMatch(importRow.BrandName, importRow.Size, importRow.Category, saaSBrands, req)
			importRow.MatchedBrand = matchResult

			// Apply fetched prices if available
			if matchResult != nil && matchResult.FetchedMRP > 0 {
				if importRow.MRP == 0 {
					importRow.MRP = matchResult.FetchedMRP
				}
				if importRow.Duty == 0 {
					importRow.Duty = matchResult.FetchedDuty
				}
				if importRow.BuyingPrice == 0 {
					importRow.BuyingPrice = matchResult.FetchedCost
				}
				if importRow.SellingPrice == 0 {
					importRow.SellingPrice = matchResult.FetchedSelling
				}
			}

			// Add warning if low confidence match
			if matchResult != nil && matchResult.MatchType == "fuzzy" && matchResult.Confidence < 90 {
				importRow.ValidationErrors = append(importRow.ValidationErrors,
					fmt.Sprintf("Low confidence match: %s (%.0f%% confidence)", matchResult.BrandName, matchResult.Confidence))
			}
		}

		if importRow.IsValid {
			validCount++
		} else {
			invalidCount++
		}

		importRows = append(importRows, importRow)
	}

	// Update import history with counts
	importHistory.TotalRows = len(importRows)
	importHistory.ValidRows = validCount
	importHistory.InvalidRows = invalidCount
	importHistory.Status = models.ImportStatusValidated
	importHistory.ProcessingTime = int(time.Since(startTime).Milliseconds())

	// Serialize validation result to JSON
	validationJSON, _ := json.Marshal(importRows)
	validationJSONStr := string(validationJSON)
	importHistory.ValidationJSON = &validationJSONStr

	s.db.Save(&importHistory)

	result := &models.ImportValidationResult{
		ImportID:         importHistory.ID,
		TenantID:         req.TenantID,
		ShopID:           req.ShopID,
		Status:           models.ImportStatusValidated,
		TotalRows:        len(importRows),
		ValidRows:        validCount,
		InvalidRows:      invalidCount,
		CanProceed:       validCount > 0,
		Rows:             importRows,
		ProcessingTimeMs: int(time.Since(startTime).Milliseconds()),
	}

	// Add warnings
	if invalidCount > 0 {
		result.Warnings = append(result.Warnings,
			fmt.Sprintf("%d rows have validation errors and will be skipped", invalidCount))
	}

	s.logger.Infof("Excel validation complete: %d total, %d valid, %d invalid", len(importRows), validCount, invalidCount)

	return result, nil
}

// ExecuteBulkImport executes the validated import and creates products/stocks
func (s *BulkImportService) ExecuteBulkImport(
	ctx context.Context,
	confirmReq models.BulkImportConfirmRequest,
) error {
	startTime := time.Now()

	// Fetch import history
	var importHistory models.ImportHistory
	if err := s.db.Where("id = ? AND tenant_id = ?", confirmReq.ImportID, confirmReq.TenantID).First(&importHistory).Error; err != nil {
		return fmt.Errorf("import not found: %w", err)
	}

	if importHistory.Status != models.ImportStatusValidated {
		return fmt.Errorf("import must be in validated status")
	}

	// Update status to processing
	s.updateImportStatus(importHistory.ID, models.ImportStatusProcessing, "")

	// Parse validation JSON
	var importRows []models.ImportRow
	if importHistory.ValidationJSON == nil {
		return fmt.Errorf("validation data is missing")
	}
	if err := json.Unmarshal([]byte(*importHistory.ValidationJSON), &importRows); err != nil {
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, "Failed to parse validation data")
		return fmt.Errorf("failed to parse validation data: %w", err)
	}

	// Apply user corrections
	if len(confirmReq.RowCorrections) > 0 {
		for rowNum, correction := range confirmReq.RowCorrections {
			for i := range importRows {
				if importRows[i].RowNumber == rowNum {
					importRows[i] = correction
					break
				}
			}
		}
	}

	// Filter rows to import
	rowsToImport := []models.ImportRow{}
	if len(confirmReq.SelectedRows) > 0 {
		// Import only selected rows
		selectedMap := make(map[int]bool)
		for _, rowNum := range confirmReq.SelectedRows {
			selectedMap[rowNum] = true
		}
		for _, row := range importRows {
			if selectedMap[row.RowNumber] && row.IsValid {
				rowsToImport = append(rowsToImport, row)
			}
		}
	} else {
		// Import all valid rows
		for _, row := range importRows {
			if row.IsValid {
				rowsToImport = append(rowsToImport, row)
			}
		}
	}

	s.logger.Infof("Starting bulk import of %d rows for tenant %s", len(rowsToImport), confirmReq.TenantID)

	// Execute in transaction
	productsCreated := 0
	stocksCreated := 0
	processedRows := 0

	err := s.db.Transaction(func(tx *gorm.DB) error {
		for _, row := range rowsToImport {
			// Determine shop ID
			shopID := row.ShopID
			if shopID == nil {
				shopID = importHistory.ShopID
			}
			if shopID == nil {
				// Get first shop as fallback
				var shop models.Shop
				if err := tx.Where("tenant_id = ?", confirmReq.TenantID).First(&shop).Error; err == nil {
					shopID = &shop.ID
				}
			}

			// Create product and stock
			if err := s.createProductFromRow(ctx, tx, row, confirmReq.TenantID, shopID, &productsCreated, &stocksCreated); err != nil {
				s.logger.Errorf("Failed to create product from row %d: %v", row.RowNumber, err)
				// Continue with other rows instead of failing entire import
				continue
			}

			processedRows++
		}
		return nil
	})

	if err != nil {
		s.updateImportStatus(importHistory.ID, models.ImportStatusFailed, fmt.Sprintf("Transaction failed: %v", err))
		return fmt.Errorf("import transaction failed: %w", err)
	}

	// Update import history with final counts
	completedAt := time.Now()
	importHistory.Status = models.ImportStatusCompleted
	importHistory.ProcessedRows = processedRows
	importHistory.ProductsCreated = productsCreated
	importHistory.StocksCreated = stocksCreated
	importHistory.CompletedAt = &completedAt
	importHistory.ProcessingTime = int(time.Since(startTime).Milliseconds())
	importHistory.UpdatedAt = time.Now()

	s.db.Save(&importHistory)

	s.logger.Infof("Bulk import completed: %d products, %d stocks created in %dms",
		productsCreated, stocksCreated, importHistory.ProcessingTime)

	return nil
}

// smartBrandMatch performs intelligent brand matching using multiple strategies
func (s *BulkImportService) smartBrandMatch(
	brandName string,
	size string,
	category string,
	saaSBrands []SaaSBrandTemplate,
	req models.BulkImportRequest,
) *models.BrandMatchResult {
	if len(saaSBrands) == 0 {
		return &models.BrandMatchResult{
			MatchType:  "no_match",
			Confidence: 0,
		}
	}

	// Normalize inputs
	brandName = strings.TrimSpace(strings.ToLower(brandName))
	size = strings.TrimSpace(strings.ToLower(size))
	category = strings.TrimSpace(strings.ToLower(category))

	bestMatch := &models.BrandMatchResult{
		MatchType:  "no_match",
		Confidence: 0,
	}
	alternates := []models.AlternateMatch{}

	minConfidence := req.MinConfidence
	if minConfidence == 0 {
		minConfidence = 80.0 // Default 80% threshold
	}

	for _, brand := range saaSBrands {
		// Category filter (if category provided) - skip for now as Category is embedded in variant
		// We'll filter by variant category instead

		// Match brand variants
		for _, variant := range brand.BrandVariants {
			// Category filter at variant level
			if category != "" && variant.Category != nil {
				brandCategory := strings.ToLower(variant.Category.Name)
				if !strings.Contains(brandCategory, category) && !strings.Contains(category, brandCategory) {
					continue
				}
			}

			matchResult := s.calculateMatchScore(brandName, size, brand.Name, variant.Size, variant, variant.Category)

			if matchResult.Confidence > bestMatch.Confidence {
				// Save previous best match as alternate
				if bestMatch.Confidence >= minConfidence {
					alternates = append(alternates, models.AlternateMatch{
						SaaSBrandID:   *bestMatch.SaaSBrandID,
						SaaSVariantID: *bestMatch.SaaSVariantID,
						BrandName:     bestMatch.BrandName,
						VariantSize:   bestMatch.VariantSize,
						Confidence:    bestMatch.Confidence,
						MRP:           bestMatch.FetchedMRP,
						CategoryName:  bestMatch.CategoryName,
					})
				}

				// Update best match
				bestMatch = matchResult
			} else if matchResult.Confidence >= minConfidence && matchResult.Confidence > 60 {
				// Add as alternate
				alternates = append(alternates, models.AlternateMatch{
					SaaSBrandID:   *matchResult.SaaSBrandID,
					SaaSVariantID: *matchResult.SaaSVariantID,
					BrandName:     matchResult.BrandName,
					VariantSize:   matchResult.VariantSize,
					Confidence:    matchResult.Confidence,
					MRP:           matchResult.FetchedMRP,
					CategoryName:  matchResult.CategoryName,
				})
			}
		}
	}

	// Apply strict matching if required
	if req.StrictMatching && bestMatch.Confidence < minConfidence {
		return &models.BrandMatchResult{
			MatchType:  "no_match",
			Confidence: 0,
		}
	}

	bestMatch.AlternateMatches = alternates

	return bestMatch
}

// calculateMatchScore calculates match score using multiple heuristics
func (s *BulkImportService) calculateMatchScore(
	inputBrand, inputSize, catalogBrand, catalogSize string,
	variant SaaSBrandVariant,
	category *SaaSCategory,
) *models.BrandMatchResult {
	// Normalize
	inputBrand = strings.ToLower(strings.TrimSpace(inputBrand))
	inputSize = strings.ToLower(strings.TrimSpace(inputSize))
	catalogBrand = strings.ToLower(strings.TrimSpace(catalogBrand))
	catalogSize = strings.ToLower(strings.TrimSpace(catalogSize))

	result := &models.BrandMatchResult{
		SaaSBrandID:   &variant.BrandID, // Fixed: BrandID instead of SaaSBrandID
		SaaSVariantID: &variant.ID,
		BrandName:     catalogBrand,
		VariantSize:   catalogSize,
		FetchedMRP:    variant.MRP,
		FetchedDuty:   variant.GovernmentDuty,
		FetchedCost:   variant.BuyingPrice,
		FetchedSelling: variant.SellingPrice,
	}

	if category != nil {
		result.CategoryID = &category.ID
		result.CategoryName = category.Name
		if variant.Subcategory != nil {
			result.SubcategoryID = variant.SubcategoryID
			result.SubcategoryName = variant.Subcategory.Name
		}
	}

	// 1. Exact match (100%)
	if inputBrand == catalogBrand && inputSize == catalogSize {
		result.MatchType = "exact"
		result.Confidence = 100.0
		return result
	}

	// 2. Brand exact + size fuzzy (95%)
	if inputBrand == catalogBrand && s.sizeSimilarity(inputSize, catalogSize) > 0.8 {
		result.MatchType = "exact"
		result.Confidence = 95.0
		return result
	}

	// 3. Fuzzy brand match + exact size (90%)
	brandSimilarity := s.levenshteinSimilarity(inputBrand, catalogBrand)
	if brandSimilarity > 0.85 && inputSize == catalogSize {
		result.MatchType = "fuzzy"
		result.Confidence = 90.0
		return result
	}

	// 4. Both fuzzy (weighted average)
	sizeSimilarity := s.sizeSimilarity(inputSize, catalogSize)
	weightedScore := (brandSimilarity * 0.7) + (sizeSimilarity * 0.3) // Brand weight = 70%, Size = 30%
	result.MatchType = "fuzzy"
	result.Confidence = weightedScore * 100

	return result
}

// levenshteinSimilarity calculates Levenshtein distance-based similarity (0-1)
func (s *BulkImportService) levenshteinSimilarity(s1, s2 string) float64 {
	distance := s.levenshteinDistance(s1, s2)
	maxLen := len(s1)
	if len(s2) > maxLen {
		maxLen = len(s2)
	}
	if maxLen == 0 {
		return 1.0
	}
	return 1.0 - (float64(distance) / float64(maxLen))
}

// levenshteinDistance computes the Levenshtein distance between two strings
func (s *BulkImportService) levenshteinDistance(s1, s2 string) int {
	if len(s1) == 0 {
		return len(s2)
	}
	if len(s2) == 0 {
		return len(s1)
	}

	matrix := make([][]int, len(s1)+1)
	for i := range matrix {
		matrix[i] = make([]int, len(s2)+1)
		matrix[i][0] = i
	}
	for j := range matrix[0] {
		matrix[0][j] = j
	}

	for i := 1; i <= len(s1); i++ {
		for j := 1; j <= len(s2); j++ {
			cost := 0
			if s1[i-1] != s2[j-1] {
				cost = 1
			}
			matrix[i][j] = minInt(
				matrix[i-1][j]+1,      // deletion
				matrix[i][j-1]+1,      // insertion
				matrix[i-1][j-1]+cost, // substitution
			)
		}
	}

	return matrix[len(s1)][len(s2)]
}

// sizeSimilarity checks if sizes are similar (handles variations like 750ml, 750, FL, Bottle)
func (s *BulkImportService) sizeSimilarity(size1, size2 string) float64 {
	// Normalize size representations
	normalize := func(s string) string {
		s = strings.ToLower(strings.TrimSpace(s))
		s = strings.ReplaceAll(s, " ", "")
		s = strings.ReplaceAll(s, "ml", "")
		s = strings.ReplaceAll(s, "l", "")
		return s
	}

	norm1 := normalize(size1)
	norm2 := normalize(size2)

	if norm1 == norm2 {
		return 1.0
	}

	// Check common equivalents
	equivalents := map[string][]string{
		"750":  {"750", "bottle", "fl", "full"},
		"375":  {"375", "half", "halfbottle"},
		"180":  {"180", "quarter", "quart", "quater"},
		"650":  {"650", "king", "large"},
		"330":  {"330", "can"},
		"200":  {"200", "pint"},
		"90":   {"90", "nip"},
		"1000": {"1000", "1l", "litre", "liter"},
	}

	for _, variants := range equivalents {
		match1 := false
		match2 := false
		for _, v := range variants {
			if strings.Contains(norm1, v) {
				match1 = true
			}
			if strings.Contains(norm2, v) {
				match2 = true
			}
		}
		if match1 && match2 {
			return 1.0
		}
	}

	// Levenshtein as fallback
	return s.levenshteinSimilarity(norm1, norm2)
}

// Helper functions

func (s *BulkImportService) parseHeader(header []string) map[string]int {
	columnMap := map[string]int{
		"brand_name":    -1,
		"size":          -1,
		"category":      -1,
		"subcategory":   -1,
		"quantity":      -1,
		"buying_price":  -1,
		"mrp":           -1,
		"duty":          -1,
		"selling_price": -1,
		"shop":          -1,
	}

	for i, col := range header {
		colLower := strings.ToLower(strings.TrimSpace(col))
		colLower = strings.ReplaceAll(colLower, " ", "_")

		if strings.Contains(colLower, "brand") && strings.Contains(colLower, "name") {
			columnMap["brand_name"] = i
		} else if strings.Contains(colLower, "size") || colLower == "volume" || colLower == "ml" {
			columnMap["size"] = i
		} else if strings.Contains(colLower, "category") && !strings.Contains(colLower, "sub") {
			columnMap["category"] = i
		} else if strings.Contains(colLower, "subcategory") || strings.Contains(colLower, "sub_category") {
			columnMap["subcategory"] = i
		} else if strings.Contains(colLower, "quantity") || colLower == "qty" || colLower == "stock" {
			columnMap["quantity"] = i
		} else if strings.Contains(colLower, "buying") || strings.Contains(colLower, "cost") || strings.Contains(colLower, "purchase") {
			columnMap["buying_price"] = i
		} else if colLower == "mrp" || strings.Contains(colLower, "retail") {
			columnMap["mrp"] = i
		} else if strings.Contains(colLower, "duty") || strings.Contains(colLower, "tax") {
			columnMap["duty"] = i
		} else if strings.Contains(colLower, "selling") || strings.Contains(colLower, "sale_price") {
			columnMap["selling_price"] = i
		} else if strings.Contains(colLower, "shop") || strings.Contains(colLower, "store") || strings.Contains(colLower, "location") {
			columnMap["shop"] = i
		}
	}

	return columnMap
}

func (s *BulkImportService) parseRow(row []string, rowNum int, columnMap map[string]int, shops []models.Shop) models.ImportRow {
	getCell := func(key string) string {
		idx := columnMap[key]
		if idx >= 0 && idx < len(row) {
			return strings.TrimSpace(row[idx])
		}
		return ""
	}

	importRow := models.ImportRow{
		RowNumber:    rowNum,
		BrandName:    getCell("brand_name"),
		Size:         getCell("size"),
		Category:     getCell("category"),
		Subcategory:  getCell("subcategory"),
		Quantity:     s.parseIntSafe(getCell("quantity")),
		BuyingPrice:  s.parseFloatSafe(getCell("buying_price")),
		MRP:          s.parseFloatSafe(getCell("mrp")),
		Duty:         s.parseFloatSafe(getCell("duty")),
		SellingPrice: s.parseFloatSafe(getCell("selling_price")),
		ShopName:     getCell("shop"),
		IsValid:      true,
	}

	// Match shop by name
	if importRow.ShopName != "" {
		for _, shop := range shops {
			if strings.EqualFold(shop.Name, importRow.ShopName) {
				importRow.ShopID = &shop.ID
				break
			}
		}
	}

	return importRow
}

func (s *BulkImportService) validateRow(row *models.ImportRow, req models.BulkImportRequest) {
	errors := []string{}

	if row.BrandName == "" {
		errors = append(errors, "Brand name is required")
	}
	if row.Size == "" {
		errors = append(errors, "Size is required")
	}
	if row.Category == "" {
		errors = append(errors, "Category is required")
	}
	if row.Quantity < 0 {
		errors = append(errors, "Quantity must be >= 0")
	}

	if len(errors) > 0 {
		row.IsValid = false
		row.ValidationErrors = errors
	}
}

func (s *BulkImportService) createProductFromRow(
	ctx context.Context,
	tx *gorm.DB,
	row models.ImportRow,
	tenantID uuid.UUID,
	shopID *uuid.UUID,
	productsCreated *int,
	stocksCreated *int,
) error {
	// Check if product already exists (by SaaS variant or name+size combination)
	if row.MatchedBrand != nil && row.MatchedBrand.SaaSVariantID != nil {
		var existing models.Product
		err := tx.Where("tenant_id = ? AND saas_variant_id = ?", tenantID, row.MatchedBrand.SaaSVariantID).First(&existing).Error
		if err == nil {
			// Product exists, update stock only
			return s.updateStockOnly(tx, existing.ID, shopID, row.Quantity, stocksCreated)
		}
	}

	// Create new product
	tenantIDPtr := &tenantID

	// Generate unique SKU
	sku := s.generateSKU(row.BrandName, row.Size)

	// Get or create default brand for imported products
	defaultBrandID, err := s.getOrCreateDefaultBrand(tx, tenantID)
	if err != nil {
		return fmt.Errorf("failed to get default brand: %w", err)
	}

	// Get or create default category for imported products
	defaultCategoryID, err := s.getOrCreateDefaultCategory(tx, tenantID)
	if err != nil {
		return fmt.Errorf("failed to get default category: %w", err)
	}

	product := models.Product{
		TenantModel: models.TenantModel{TenantID: tenantIDPtr},
		Name:        fmt.Sprintf("%s - %s", row.BrandName, row.Size),
		Size:        row.Size,
		SKU:         sku,
		BrandID:     defaultBrandID,     // Use default "Imported Brands" placeholder
		CategoryID:  defaultCategoryID,  // Use default "Uncategorized" placeholder
		MRP:         row.MRP,
		CostPrice:   row.BuyingPrice,
		DutyFee:     row.Duty,
		TotalCost:   row.BuyingPrice + row.Duty,
		SellingPrice: row.SellingPrice,
		CreatedVia:   "bulk_import", // 2026-05-18 — provenance (exempt from AI-Purchase image gate)
	}

	// Override with SaaS brand match if available
	if row.MatchedBrand != nil && row.MatchedBrand.CategoryID != nil {
		product.SaaSBrandID = row.MatchedBrand.SaaSBrandID
		product.SaaSVariantID = row.MatchedBrand.SaaSVariantID
		product.CategoryID = *row.MatchedBrand.CategoryID
		if row.MatchedBrand.SubcategoryID != nil {
			product.SubcategoryID = row.MatchedBrand.SubcategoryID
		}
	}

	if err := tx.Create(&product).Error; err != nil {
		return fmt.Errorf("failed to create product: %w", err)
	}

	*productsCreated++

	// Create stock
	if shopID != nil && row.Quantity >= 0 {
		stock := models.Stock{
			TenantModel: models.TenantModel{TenantID: tenantIDPtr},
			ProductID:   product.ID,
			ShopID:      *shopID,
			Quantity:    row.Quantity,
			MinimumLevel: 10,
		}

		if err := tx.Create(&stock).Error; err != nil {
			return fmt.Errorf("failed to create stock: %w", err)
		}

		*stocksCreated++
	}

	return nil
}

func (s *BulkImportService) updateStockOnly(tx *gorm.DB, productID uuid.UUID, shopID *uuid.UUID, quantity int, stocksCreated *int) error {
	return s.updateStockOnlyV2(tx, productID, shopID, nil, uuid.Nil, quantity, stocksCreated)
}

// updateStockOnlyV2 — banking-grade variant that writes a stock_histories row
// for the bulk-import bump. Called from createProductFromRow with tenant + user
// context. Old updateStockOnly delegates here with nils so unaudited callers
// stay compileable; future code should call this directly.
func (s *BulkImportService) updateStockOnlyV2(tx *gorm.DB, productID uuid.UUID, shopID *uuid.UUID, tenantID *uuid.UUID, userID uuid.UUID, quantity int, stocksCreated *int) error {
	if shopID == nil || quantity == 0 {
		return nil
	}

	var stock models.Stock
	err := tx.Where("product_id = ? AND shop_id = ?", productID, shopID).First(&stock).Error

	if err == gorm.ErrRecordNotFound {
		// Create new stock
		stock = models.Stock{
			ProductID:    productID,
			ShopID:       *shopID,
			Quantity:     quantity,
			MinimumLevel: 10,
		}
		if err := tx.Create(&stock).Error; err != nil {
			return fmt.Errorf("failed to create stock: %w", err)
		}
		*stocksCreated++
	} else if err != nil {
		return err
	} else {
		// Update existing stock
		prevQty := stock.Quantity
		stock.Quantity = prevQty + quantity
		if err := tx.Save(&stock).Error; err != nil {
			return fmt.Errorf("failed to update stock: %w", err)
		}

		// v1.0.216 — write the audit row so bulk-import bumps don't show up
		// as silent +N drift in the reconciliation sweep.
		if tenantID != nil {
			tid := *tenantID
			biShopRef, biProdRef := stock.ShopID, stock.ProductID
			hist := models.StockHistory{
				TenantModel:      models.TenantModel{TenantID: &tid},
				StockID:          stock.ID,
				ShopID:           &biShopRef,
				ProductID:        &biProdRef,
				MovementType:     "bulk_import",
				Quantity:         quantity,
				PreviousQuantity: prevQty,
				NewQuantity:      stock.Quantity,
				Reference:        "Bulk import",
				CreatedByID:      userID,
			}
			_ = tx.Create(&hist).Error
		}
	}

	return nil
}

func (s *BulkImportService) getTenantShops(tenantID uuid.UUID) ([]models.Shop, error) {
	var shops []models.Shop
	err := s.db.Where("tenant_id = ?", tenantID).Find(&shops).Error
	return shops, err
}

func (s *BulkImportService) updateImportStatus(importID uuid.UUID, status models.ImportStatus, errorMsg string) {
	updates := map[string]interface{}{
		"status":     status,
		"updated_at": time.Now(),
	}
	if errorMsg != "" {
		updates["error_message"] = errorMsg
	}
	s.db.Table("import_history").Where("id = ?", importID).Updates(updates)
}

func (s *BulkImportService) isEmptyRow(row []string) bool {
	for _, cell := range row {
		if strings.TrimSpace(cell) != "" {
			return false
		}
	}
	return true
}

func (s *BulkImportService) parseIntSafe(str string) int {
	str = strings.TrimSpace(str)
	if str == "" {
		return 0
	}
	var val int
	fmt.Sscanf(str, "%d", &val)
	return val
}

func (s *BulkImportService) parseFloatSafe(str string) float64 {
	str = strings.TrimSpace(str)
	if str == "" {
		return 0.0
	}
	var val float64
	fmt.Sscanf(str, "%f", &val)
	return val
}

func minInt(a, b, c int) int {
	if a < b {
		if a < c {
			return a
		}
		return c
	}
	if b < c {
		return b
	}
	return c
}

// generateSKU generates a unique SKU for imported products
func (s *BulkImportService) generateSKU(brandName, size string) string {
	// Normalize brand name to create prefix
	prefix := strings.ToUpper(strings.ReplaceAll(brandName, " ", ""))
	if len(prefix) > 10 {
		prefix = prefix[:10]
	}

	// Normalize size
	sizeNorm := strings.ToUpper(strings.ReplaceAll(size, " ", ""))
	sizeNorm = strings.ReplaceAll(sizeNorm, "ML", "")

	// Generate unique suffix using UUID short form
	uuidSuffix := uuid.New().String()[:8]

	return fmt.Sprintf("%s-%s-%s", prefix, sizeNorm, uuidSuffix)
}

// getOrCreateDefaultBrand gets or creates a default "Custom Brands" placeholder brand for imported products
func (s *BulkImportService) getOrCreateDefaultBrand(tx *gorm.DB, tenantID uuid.UUID) (uuid.UUID, error) {
	var brand models.Brand

	// Try to find existing "Imported Brands" placeholder
	err := tx.Where("tenant_id = ? AND name = ?", tenantID, "Imported Brands").First(&brand).Error

	if err == nil {
		return brand.ID, nil
	}

	if err != gorm.ErrRecordNotFound {
		return uuid.Nil, fmt.Errorf("failed to check for default brand: %w", err)
	}

	// Create new default brand
	tenantIDPtr := &tenantID
	brand = models.Brand{
		TenantModel: models.TenantModel{TenantID: tenantIDPtr},
		Name:        "Imported Brands",
		Description: "Default brand for bulk imported products",
		IsActive:    true,
	}

	if err := tx.Create(&brand).Error; err != nil {
		return uuid.Nil, fmt.Errorf("failed to create default brand: %w", err)
	}

	s.logger.Infof("Created default 'Imported Brands' brand for tenant %s", tenantID)

	return brand.ID, nil
}

// getOrCreateDefaultCategory gets or creates a default "Uncategorized" placeholder category for imported products
func (s *BulkImportService) getOrCreateDefaultCategory(tx *gorm.DB, tenantID uuid.UUID) (uuid.UUID, error) {
	var category models.Category

	// Try to find existing "Uncategorized" placeholder
	err := tx.Where("tenant_id = ? AND name = ?", tenantID, "Uncategorized").First(&category).Error

	if err == nil {
		return category.ID, nil
	}

	if err != gorm.ErrRecordNotFound {
		return uuid.Nil, fmt.Errorf("failed to check for default category: %w", err)
	}

	// Create new default category
	tenantIDPtr := &tenantID
	category = models.Category{
		TenantModel: models.TenantModel{TenantID: tenantIDPtr},
		Name:        "Uncategorized",
		Description: "Default category for bulk imported products",
		IsActive:    true,
	}

	if err := tx.Create(&category).Error; err != nil {
		return uuid.Nil, fmt.Errorf("failed to create default category: %w", err)
	}

	s.logger.Infof("Created default 'Uncategorized' category for tenant %s", tenantID)

	return category.ID, nil
}

package services

import (
	"context"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
)

// StockMatcher intelligently matches extracted items with actual inventory
type StockMatcher struct {
	db             *database.DB
	logger         *logrus.Logger
	sizeNormalizer *SizeNormalizer
	saasClient     *SaaSBrandClient  // Client to fetch SaaS admin brands
}

// MatchResult represents a product match with confidence score
type MatchResult struct {
	ProductID       uuid.UUID
	Product         *models.Product
	BrandName       string
	CategoryName    string
	Size            string
	SizeML          int
	AvailableStock  int
	MatchConfidence float64
	MatchMethod     models.MatchMethod
	MatchDetails    *models.MatchDetails
}

// MatchOptions configures the matching behavior
type MatchOptions struct {
	ShopID           uuid.UUID
	TenantID         uuid.UUID
	MinConfidence    float64 // Minimum confidence to return (default: 0.6)
	RequireStock     bool    // Only match items with stock > 0
	MaxResults       int     // Maximum matches to return (default: 5)
	CategoryFilter   string  // Filter by category (beer, whiskey, etc.)
}

// NewStockMatcher creates a new stock matcher
func NewStockMatcher(db *database.DB, logger *logrus.Logger) *StockMatcher {
	// Initialize SaaS brand client
	saasClient := NewSaaSBrandClient(logger)

	return &StockMatcher{
		db:             db,
		logger:         logger,
		sizeNormalizer: NewSizeNormalizer(),
		saasClient:     saasClient,
	}
}

// MatchItem finds the best matching product for an extracted item
func (sm *StockMatcher) MatchItem(ctx context.Context, item *ExtractedReceiptItem, options MatchOptions) ([]*MatchResult, error) {
	// Set defaults
	if options.MinConfidence == 0 {
		options.MinConfidence = 0.6
	}
	if options.MaxResults == 0 {
		options.MaxResults = 5
	}

	sm.logger.Infof("Matching item: %s (%s, %dml, qty:%d) for shop %s", item.Brand, item.Category, item.SizeML, item.Quantity, options.ShopID)

	// First, try to match with SaaS brand templates
	sm.logger.Infof("Checking SaaS brand templates for: %s", item.Brand)
	saasMatch, err := sm.matchWithSaaSBrand(ctx, item, options)
	if err != nil {
		sm.logger.Warnf("Failed to match with SaaS brands: %v", err)
	} else if saasMatch != nil {
		sm.logger.Infof("Found SaaS brand match: %s (confidence: %.2f)", saasMatch.BrandName, saasMatch.MatchConfidence)

		// Check if brand needs to be onboarded
		if saasMatch.ProductID == uuid.Nil {
			sm.logger.Infof("Brand %s needs to be onboarded for tenant %s", saasMatch.BrandName, options.TenantID)

			// Trigger auto-onboarding process
			sm.logger.Infof("🚀 Initiating auto-onboarding for brand: %s", saasMatch.BrandName)
			// We'll store the SaaS brand info in MatchDetails so the OCR service can trigger onboarding
			if saasMatch.MatchDetails != nil {
				saasMatch.MatchDetails.MatchedFields = append(saasMatch.MatchDetails.MatchedFields, "needs_onboarding")
			}
		}
	}

	// Step 1: Get all products with stock for this shop
	products, err := sm.getProductsWithStock(ctx, options.TenantID, options.ShopID, item.Category)
	if err != nil {
		sm.logger.Errorf("Database error getting products: %v", err)
		return nil, fmt.Errorf("failed to get products: %w", err)
	}

	if len(products) == 0 {
		sm.logger.Warnf("No products found for tenant %s, shop %s, category: %s", options.TenantID, options.ShopID, item.Category)
		// Try without category filter for better matching
		products, err = sm.getProductsWithStock(ctx, options.TenantID, options.ShopID, "")
		if err != nil {
			return nil, fmt.Errorf("failed to get all products: %w", err)
		}
		if len(products) == 0 {
			sm.logger.Infof("No products found locally, checking if SaaS match exists")

			// If we have a SaaS match but no local products, suggest auto-onboarding
			if saasMatch != nil {
				return []*MatchResult{saasMatch}, nil
			}

			return nil, nil
		}
		sm.logger.Infof("Using all %d products (ignoring category filter)", len(products))
	}

	sm.logger.Infof("Found %d products to match against", len(products))

	// Step 2: Score each product
	var matches []*MatchResult
	for _, product := range products {
		result := sm.scoreProduct(item, product)

		// Apply filters
		if result.MatchConfidence < options.MinConfidence {
			continue
		}
		if options.RequireStock && result.AvailableStock <= 0 {
			continue
		}

		matches = append(matches, result)
	}

	// Step 3: Sort by confidence (highest first)
	sm.sortByConfidence(matches)

	// Step 4: Limit results
	if len(matches) > options.MaxResults {
		matches = matches[:options.MaxResults]
	}

	sm.logger.Infof("Found %d matches for '%s'", len(matches), item.Brand)
	if len(matches) > 0 {
		sm.logger.Infof("Best match: %s (confidence: %.2f, stock: %d)",
			matches[0].BrandName, matches[0].MatchConfidence, matches[0].AvailableStock)
	}

	return matches, nil
}

// getProductsWithStock retrieves products with their stock levels
func (sm *StockMatcher) getProductsWithStock(ctx context.Context, tenantID, shopID uuid.UUID, category string) ([]*ProductWithStock, error) {
	query := `
		SELECT
			p.id as product_id,
			p.name as product_name,
			b.name as brand_name,
			c.name as category_name,
			p.size,
			COALESCE(s.quantity, 0) as stock_quantity
		FROM products p
		LEFT JOIN brands b ON p.brand_id = b.id
		LEFT JOIN categories c ON p.category_id = c.id
		LEFT JOIN stocks s ON p.id = s.product_id AND s.shop_id = ?
		WHERE p.tenant_id = ? AND p.is_active = true
	`

	args := []interface{}{shopID, tenantID}

	// Add category filter if specified
	if category != "" {
		query += " AND LOWER(c.name) = LOWER(?)"
		args = append(args, category)
	}

	query += " ORDER BY b.name, p.size"

	rows, err := sm.db.Raw(query, args...).Rows()
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var products []*ProductWithStock
	for rows.Next() {
		var p ProductWithStock
		if err := rows.Scan(
			&p.ProductID,
			&p.ProductName,
			&p.BrandName,
			&p.CategoryName,
			&p.Size,
			&p.StockQuantity,
		); err != nil {
			sm.logger.Errorf("Failed to scan product: %v", err)
			continue
		}
		products = append(products, &p)
	}

	return products, nil
}

// scoreProduct calculates match confidence for a product
func (sm *StockMatcher) scoreProduct(item *ExtractedReceiptItem, product *ProductWithStock) *MatchResult {
	confidence := 0.0
	method := models.MatchMethodFuzzy
	details := &models.MatchDetails{
		Algorithm:     "multi-factor",
		MatchedFields: []string{},
	}

	// Factor 1: Brand name match (40% weight)
	brandScore := sm.calculateBrandSimilarity(item.Brand, product.BrandName)
	confidence += brandScore * 0.4
	if brandScore > 0.8 {
		details.MatchedFields = append(details.MatchedFields, "brand")
	}

	// Factor 2: Size match (30% weight)
	sizeScore := sm.calculateSizeSimilarity(item.SizeML, item.SizeText, product.Size)
	confidence += sizeScore * 0.3
	if sizeScore >= 1.0 {
		details.MatchedFields = append(details.MatchedFields, "size")
	}

	// Factor 3: Category match (20% weight)
	categoryScore := sm.calculateCategoryMatch(item.Category, product.CategoryName)
	confidence += categoryScore * 0.2
	if categoryScore >= 1.0 {
		details.MatchedFields = append(details.MatchedFields, "category")
	}

	// Factor 4: Stock availability (10% bonus)
	if product.StockQuantity >= item.Quantity {
		confidence += 0.1
		details.MatchedFields = append(details.MatchedFields, "stock")
	}

	// Determine match method
	if confidence >= 0.95 && brandScore >= 0.9 && sizeScore >= 1.0 {
		method = models.MatchMethodExact
	} else if brandScore >= 0.8 {
		method = models.MatchMethodFuzzy
	} else {
		method = models.MatchMethodPattern
	}

	// Extract size ML from product
	productML, _ := sm.sizeNormalizer.Normalize(product.Size, product.CategoryName)

	details.Score = confidence

	return &MatchResult{
		ProductID:       product.ProductID,
		BrandName:       product.BrandName,
		CategoryName:    product.CategoryName,
		Size:            product.Size,
		SizeML:          productML,
		AvailableStock:  product.StockQuantity,
		MatchConfidence: confidence,
		MatchMethod:     method,
		MatchDetails:    details,
	}
}

// calculateBrandSimilarity calculates brand name similarity (0-1)
func (sm *StockMatcher) calculateBrandSimilarity(extracted, database string) float64 {
	extractedLower := strings.ToLower(strings.TrimSpace(extracted))
	databaseLower := strings.ToLower(strings.TrimSpace(database))

	// Exact match
	if extractedLower == databaseLower {
		return 1.0
	}

	// Contains match
	if strings.Contains(databaseLower, extractedLower) || strings.Contains(extractedLower, databaseLower) {
		return 0.9
	}

	// Levenshtein distance
	distance := levenshteinDistance(extractedLower, databaseLower)
	maxLen := max(len(extractedLower), len(databaseLower))
	if maxLen == 0 {
		return 0
	}

	similarity := 1.0 - (float64(distance) / float64(maxLen))

	// Boost score if key words match
	if sm.hasCommonKeywords(extractedLower, databaseLower) {
		similarity += 0.1
	}

	return clamp(similarity, 0, 1)
}

// calculateSizeSimilarity calculates size match score (0-1)
func (sm *StockMatcher) calculateSizeSimilarity(extractedML int, extractedText, databaseSize string) float64 {
	if extractedML == 0 {
		return 0.5 // No size info, neutral score
	}

	// Normalize database size
	databaseML, _ := sm.sizeNormalizer.Normalize(databaseSize, "")

	if databaseML == 0 {
		return 0.5 // Can't compare
	}

	// Exact match
	if extractedML == databaseML {
		return 1.0
	}

	// Within 10% tolerance
	tolerance := float64(databaseML) * 0.1
	diff := float64(abs(extractedML - databaseML))
	if diff <= tolerance {
		return 0.95
	}

	// Within 20% tolerance
	tolerance = float64(databaseML) * 0.2
	if diff <= tolerance {
		return 0.8
	}

	// Different sizes
	return 0.3
}

// calculateCategoryMatch calculates category match score (0-1)
func (sm *StockMatcher) calculateCategoryMatch(extracted, database string) float64 {
	extractedLower := strings.ToLower(strings.TrimSpace(extracted))
	databaseLower := strings.ToLower(strings.TrimSpace(database))

	// Exact match
	if extractedLower == databaseLower {
		return 1.0
	}

	// Contains match (e.g., "beer" in "Premium Beer")
	if strings.Contains(databaseLower, extractedLower) || strings.Contains(extractedLower, databaseLower) {
		return 0.9
	}

	// Related categories (whiskey/whisky, etc.)
	if sm.areSimilarCategories(extractedLower, databaseLower) {
		return 0.8
	}

	return 0.0
}

// hasCommonKeywords checks if brand names share key words
func (sm *StockMatcher) hasCommonKeywords(str1, str2 string) bool {
	words1 := strings.Fields(str1)
	words2 := strings.Fields(str2)

	commonCount := 0
	for _, w1 := range words1 {
		for _, w2 := range words2 {
			if w1 == w2 && len(w1) > 2 { // Ignore short words
				commonCount++
			}
		}
	}

	return commonCount > 0
}

// areSimilarCategories checks if categories are related
func (sm *StockMatcher) areSimilarCategories(cat1, cat2 string) bool {
	similarPairs := map[string][]string{
		"whiskey": {"whisky", "scotch", "bourbon"},
		"beer":    {"lager", "ale", "stout"},
		"wine":    {"red wine", "white wine"},
	}

	for key, related := range similarPairs {
		if (cat1 == key || contains(related, cat1)) && (cat2 == key || contains(related, cat2)) {
			return true
		}
	}

	return false
}

// sortByConfidence sorts matches by confidence (highest first)
func (sm *StockMatcher) sortByConfidence(matches []*MatchResult) {
	for i := 0; i < len(matches)-1; i++ {
		for j := i + 1; j < len(matches); j++ {
			if matches[j].MatchConfidence > matches[i].MatchConfidence {
				matches[i], matches[j] = matches[j], matches[i]
			}
		}
	}
}

// ProductWithStock combines product info with stock level
type ProductWithStock struct {
	ProductID     uuid.UUID
	ProductName   string
	BrandName     string
	CategoryName  string
	Size          string
	StockQuantity int
}

// Helper functions

func levenshteinDistance(s1, s2 string) int {
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
			matrix[i][j] = min(
				matrix[i-1][j]+1,      // deletion
				matrix[i][j-1]+1,      // insertion
				matrix[i-1][j-1]+cost, // substitution
			)
		}
	}

	return matrix[len(s1)][len(s2)]
}

func min(a, b, c int) int {
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

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func clamp(value, min, max float64) float64 {
	if value < min {
		return min
	}
	if value > max {
		return max
	}
	return value
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

// abs function is already defined in size_normalizer.go

// GetAvailableCategories gets all available categories for debugging
func (sm *StockMatcher) GetAvailableCategories(ctx context.Context, tenantID uuid.UUID) ([]string, error) {
	var categories []string
	err := sm.db.Table("categories").
		Where("tenant_id = ? AND is_active = true", tenantID).
		Pluck("name", &categories).Error
	return categories, err
}

// GetProductCount gets count of products for debugging
func (sm *StockMatcher) GetProductCount(ctx context.Context, tenantID, shopID uuid.UUID) (int64, error) {
	var count int64
	err := sm.db.Table("products").
		Where("tenant_id = ? AND is_active = true", tenantID).
		Count(&count).Error
	sm.logger.Infof("Product count for tenant %s: %d", tenantID, count)

	// Also count stock entries for the shop
	var stockCount int64
	sm.db.Table("stocks").
		Where("shop_id = ?", shopID).
		Count(&stockCount)
	sm.logger.Infof("Stock entries for shop %s: %d", shopID, stockCount)

	return count, err
}

// matchWithSaaSBrand attempts to match an extracted item with SaaS brand templates
func (sm *StockMatcher) matchWithSaaSBrand(ctx context.Context, item *ExtractedReceiptItem, options MatchOptions) (*MatchResult, error) {
	if sm.saasClient == nil {
		return nil, nil
	}

	// Search for brand in SaaS templates
	saasTemplate, err := sm.saasClient.SearchBrandByName(item.Brand)
	if err != nil {
		return nil, err
	}

	if saasTemplate == nil {
		sm.logger.Infof("No SaaS brand template found for: %s", item.Brand)
		return nil, nil
	}

	sm.logger.Infof("Found SaaS brand template: %s (ID: %s)", saasTemplate.Name, saasTemplate.ID)

	// Check if this brand is already onboarded for the tenant
	var existingProductID uuid.UUID
	err = sm.db.Table("products p").
		Select("p.id").
		Joins("JOIN brands b ON p.brand_id = b.id").
		Where("b.saas_brand_id = ? AND p.tenant_id = ? AND p.size = ?",
			saasTemplate.ID, options.TenantID, item.SizeText).
		Scan(&existingProductID).Error

	if err == nil && existingProductID != uuid.Nil {
		sm.logger.Infof("Brand already onboarded, product ID: %s", existingProductID)
	}

	// Find matching variant based on size
	var matchedVariant *SaaSBrandVariant
	if saasTemplate.Variants != nil && len(saasTemplate.Variants) > 0 {
		for _, variant := range saasTemplate.Variants {
			// Compare sizes (normalized)
			variantSizeML, _ := sm.sizeNormalizer.Normalize(variant.Size, "")
			if variantSizeML == item.SizeML {
				matchedVariant = &variant
				break
			}
		}
	}

	// Use display name for user, fall back to official name
	displayName := saasTemplate.Description
	if displayName == "" {
		displayName = saasTemplate.Name
	}

	// Create match result
	result := &MatchResult{
		ProductID:       existingProductID, // Will be uuid.Nil if not onboarded
		BrandName:       displayName,
		CategoryName:    item.Category,
		Size:            item.SizeText,
		SizeML:          item.SizeML,
		AvailableStock:  0, // Will be updated after onboarding
		MatchConfidence: 0.95, // High confidence for SaaS template match
		MatchMethod:     models.MatchMethodExact,
		MatchDetails: &models.MatchDetails{
			Algorithm:     "saas-template",
			MatchedFields: []string{"brand", "saas_id"},
			Score:         0.95,
			// Store SaaS brand ID for auto-onboarding (stored as string in metadata)
			Metadata: map[string]interface{}{
				"saas_brand_id":   saasTemplate.ID,
				"saas_brand_name": saasTemplate.Name,
			},
		},
	}

	// If variant matched, add pricing information
	if matchedVariant != nil {
		result.MatchDetails.MatchedFields = append(result.MatchDetails.MatchedFields, "size", "variant")

		// Store variant info for auto-onboarding
		result.MatchDetails.Score = 1.0
		result.MatchConfidence = 1.0
		result.MatchDetails.Metadata["saas_variant_id"] = matchedVariant.ID
		result.MatchDetails.Metadata["variant_size"] = matchedVariant.Size
		result.MatchDetails.Metadata["variant_duty"] = matchedVariant.GovernmentDuty
		result.MatchDetails.Metadata["variant_mrp"] = matchedVariant.MRP

		sm.logger.Infof("Matched with variant: %s (Duty: %.2f, MRP: %.2f)",
			matchedVariant.Size, matchedVariant.GovernmentDuty, matchedVariant.MRP)
	}

	return result, nil
}

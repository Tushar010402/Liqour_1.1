package services

import (
	"fmt"
	"strings"
	"sync"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

// CategoryMapper handles mapping of detected category names to SaaS category IDs
type CategoryMapper struct {
	db                  *gorm.DB
	logger              *logrus.Logger
	categories          map[string]uuid.UUID  // lowercase category name → category_id
	subcategories       map[string]uuid.UUID  // lowercase subcategory name → subcategory_id
	categoryNames       []string              // Ordered list of category names (for prompts)
	subcategoryNames    []string              // Ordered list of subcategory names (for prompts)
	brandExamples       map[string][]string   // category name → list of brand examples
	brandToCategory     map[string]string     // brand name pattern → category name
	categoryAliases     map[string]string     // alias → canonical category name
	subcategoryAliases  map[string]string     // alias → canonical subcategory name
	mu                  sync.RWMutex          // Thread-safe access
}

// CategoryMapping represents a category mapping record
type CategoryMapping struct {
	ID   uuid.UUID `gorm:"type:uuid;primary_key"`
	Name string    `gorm:"column:name"`
}

// NewCategoryMapper creates a new category mapper service
func NewCategoryMapper(db *gorm.DB, logger *logrus.Logger) *CategoryMapper {
	return &CategoryMapper{
		db:                 db,
		logger:             logger,
		categories:         make(map[string]uuid.UUID),
		subcategories:      make(map[string]uuid.UUID),
		categoryNames:      []string{},
		subcategoryNames:   []string{},
		brandExamples:      make(map[string][]string),
		brandToCategory:    initBrandToCategoryMap(),
		categoryAliases:    initCategoryAliases(),
		subcategoryAliases: initSubcategoryAliases(),
	}
}

// LoadCategories loads categories and subcategories from database
func (c *CategoryMapper) LoadCategories() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Load brand categories
	var categories []CategoryMapping
	err := c.db.Table("brand_categories").
		Where("deleted_at IS NULL").
		Select("id, name").
		Find(&categories).Error
	if err != nil {
		c.logger.Errorf("Failed to load categories: %v", err)
		return err
	}

	for _, cat := range categories {
		c.categories[strings.ToLower(cat.Name)] = cat.ID
		c.categoryNames = append(c.categoryNames, cat.Name)
		c.logger.Debugf("Loaded category: %s → %s", cat.Name, cat.ID)
	}

	// Load brand subcategories
	var subcategories []CategoryMapping
	err = c.db.Table("brand_subcategories").
		Where("deleted_at IS NULL").
		Select("id, name").
		Find(&subcategories).Error
	if err != nil {
		c.logger.Warnf("Failed to load subcategories: %v", err)
		// Don't fail if subcategories don't exist
	}

	for _, subcat := range subcategories {
		c.subcategories[strings.ToLower(subcat.Name)] = subcat.ID
		c.subcategoryNames = append(c.subcategoryNames, subcat.Name)
		c.logger.Debugf("Loaded subcategory: %s → %s", subcat.Name, subcat.ID)
	}

	// Load brand examples for each category
	if err := c.loadBrandExamples(); err != nil {
		c.logger.Warnf("Failed to load brand examples: %v", err)
		// Don't fail if brand examples can't be loaded
	}

	c.logger.Infof("✅ CategoryMapper loaded: %d categories, %d subcategories",
		len(c.categories), len(c.subcategories))
	return nil
}

// GetCategoryID maps a detected category name to its SaaS category ID
func (c *CategoryMapper) GetCategoryID(categoryName string) *uuid.UUID {
	if categoryName == "" {
		return nil
	}

	c.mu.RLock()
	defer c.mu.RUnlock()

	// Normalize to lowercase
	normalized := strings.ToLower(strings.TrimSpace(categoryName))

	// Check aliases first (e.g., "whisky" → "whiskey")
	if canonical, ok := c.categoryAliases[normalized]; ok {
		normalized = canonical
	}

	// Look up category ID
	if id, ok := c.categories[normalized]; ok {
		c.logger.Debugf("Mapped category '%s' → %s", categoryName, id)
		return &id
	}

	c.logger.Warnf("Category '%s' not found in database", categoryName)
	return nil
}

// GetSubcategoryID maps a detected subcategory name to its SaaS subcategory ID
func (c *CategoryMapper) GetSubcategoryID(subcategoryName string) *uuid.UUID {
	if subcategoryName == "" {
		return nil
	}

	c.mu.RLock()
	defer c.mu.RUnlock()

	// Normalize to lowercase
	normalized := strings.ToLower(strings.TrimSpace(subcategoryName))

	// Check aliases
	if canonical, ok := c.subcategoryAliases[normalized]; ok {
		normalized = canonical
	}

	// Look up subcategory ID
	if id, ok := c.subcategories[normalized]; ok {
		c.logger.Debugf("Mapped subcategory '%s' → %s", subcategoryName, id)
		return &id
	}

	c.logger.Debugf("Subcategory '%s' not found in database (may not exist yet)", subcategoryName)
	return nil
}

// DetectFromBrandName intelligently detects category from brand name
func (c *CategoryMapper) DetectFromBrandName(brandName string) (category, subcategory string) {
	if brandName == "" {
		return "", ""
	}

	normalized := strings.ToLower(strings.TrimSpace(brandName))

	// Check brand patterns
	for pattern, cat := range c.brandToCategory {
		if strings.Contains(normalized, pattern) {
			category = cat
			c.logger.Debugf("Detected category '%s' from brand '%s' (pattern: %s)",
				cat, brandName, pattern)
			break
		}
	}

	// Detect subcategory based on known premium brands
	if isPremiumBrand(normalized) {
		subcategory = "premium"
	} else {
		subcategory = "normal"
	}

	return category, subcategory
}

// initBrandToCategoryMap initializes brand name patterns for category detection
func initBrandToCategoryMap() map[string]string {
	return map[string]string{
		// Whiskey brands
		"royal stag":        "whiskey",
		"imperial blue":     "whiskey",
		"black dog":         "whiskey",
		"100 piper":         "whiskey",
		"blenders pride":    "whiskey",
		"mcdowell":          "whiskey",
		"officers choice":   "whiskey",
		"8 pm":              "whiskey",
		"signature":         "whiskey",
		"antiquity":         "whiskey",
		"rs barrel":         "whiskey",
		"r.s. barrel":       "whiskey",
		"johnnie walker":    "whiskey",
		"chivas":            "whiskey",
		"b7":                "whiskey",
		"royal green":       "whiskey",
		"royal challenge":   "whiskey",

		// Rum brands
		"old monk":          "rum",
		"bacardi":           "rum",
		"captain morgan":    "rum",
		"havana":            "rum",

		// Vodka brands
		"magic moments":     "vodka",
		"smirnoff":          "vodka",
		"absolute":          "vodka",
		"grey goose":        "vodka",

		// Beer brands
		"kingfisher":        "beer",
		"carlsberg":         "beer",
		"tuborg":            "beer",
		"budweiser":         "beer",
		"heineken":          "beer",
		"corona":            "beer",

		// Gin brands
		"bombay sapphire":   "gin",
		"tanqueray":         "gin",
		"hendricks":         "gin",
		"gordon":            "gin",

		// Brandy
		"morpheus":          "brandy",
		"mansion house":     "brandy",
	}
}

// initCategoryAliases initializes category name aliases for normalization
func initCategoryAliases() map[string]string {
	return map[string]string{
		"whisky":     "whiskey",
		"wisky":      "whiskey",
		"gin":        "jin",  // Map to SaaS table name "Jin"
		"bear":       "beer", // Common OCR error
		"beer":       "beer",
		"vodka":      "vodka",
		"rum":        "rum",
		"brandy":     "brandy",
		"wine":       "wine",
	}
}

// initSubcategoryAliases initializes subcategory name aliases
func initSubcategoryAliases() map[string]string {
	return map[string]string{
		"premium":    "premium",
		"normal":     "normal",
		"regular":    "normal",
		"standard":   "normal",
		"economy":    "normal",
		"luxury":     "premium",
		"deluxe":     "premium",
	}
}

// isPremiumBrand checks if a brand is considered premium quality
func isPremiumBrand(brandName string) bool {
	premiumBrands := []string{
		"royal stag", "black dog", "100 piper", "johnnie walker",
		"chivas", "blenders pride", "signature", "antiquity",
	}

	for _, premium := range premiumBrands {
		if strings.Contains(brandName, premium) {
			return true
		}
	}

	return false
}

// BrandExample represents a brand example for category detection
type BrandExample struct {
	BrandName string `gorm:"column:brand_name"`
	Category  string `gorm:"column:category"`
}

// loadBrandExamples loads brand examples from database for each category
func (c *CategoryMapper) loadBrandExamples() error {
	// Query to get brand examples grouped by category
	var examples []BrandExample
	err := c.db.Raw(`
		SELECT
			DISTINCT sb.name as brand_name,
			bc.name as category
		FROM saas_brands sb
		JOIN brand_variants bv ON bv.brand_id = sb.id
		JOIN brand_categories bc ON bc.id = bv.category_id
		WHERE sb.deleted_at IS NULL
			AND bv.deleted_at IS NULL
			AND bc.deleted_at IS NULL
		ORDER BY bc.name, sb.name
	`).Scan(&examples).Error

	if err != nil {
		return err
	}

	// Group brands by category
	for _, example := range examples {
		categoryKey := strings.ToLower(example.Category)
		c.brandExamples[categoryKey] = append(c.brandExamples[categoryKey], example.BrandName)
	}

	// Limit to 10 examples per category for prompt efficiency
	for category, brands := range c.brandExamples {
		if len(brands) > 10 {
			c.brandExamples[category] = brands[:10]
		}
	}

	c.logger.Infof("✅ Loaded brand examples for %d categories", len(c.brandExamples))
	return nil
}

// GetCategoryPromptText generates formatted category text for Gemini prompts
func (c *CategoryMapper) GetCategoryPromptText() string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if len(c.categoryNames) == 0 {
		// Fallback to hardcoded list if database not loaded
		return `**whiskey**, **rum**, **vodka**, **beer**, **gin**, **brandy**`
	}

	var lines []string
	for _, catName := range c.categoryNames {
		categoryKey := strings.ToLower(catName)
		brands := c.brandExamples[categoryKey]

		if len(brands) > 0 {
			// Include brand examples if available
			brandList := strings.Join(brands, ", ")
			lines = append(lines, fmt.Sprintf("- **%s**: %s", strings.ToLower(catName), brandList))
		} else {
			// No examples, just list the category
			lines = append(lines, fmt.Sprintf("- **%s**", strings.ToLower(catName)))
		}
	}

	return strings.Join(lines, "\n")
}

// GetSubcategoryPromptText generates formatted subcategory text for Gemini prompts
func (c *CategoryMapper) GetSubcategoryPromptText() string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if len(c.subcategoryNames) == 0 {
		// No subcategories in database - return empty or default
		return `- **premium**: High-quality brands (₹150+ per 90ml)
- **normal**: Standard brands (₹50-150 per 90ml)`
	}

	var lines []string
	for _, subcatName := range c.subcategoryNames {
		lines = append(lines, fmt.Sprintf("- **%s**", strings.ToLower(subcatName)))
	}

	return strings.Join(lines, "\n")
}

// GetCategoryList returns comma-separated lowercase category names for prompts
func (c *CategoryMapper) GetCategoryList() string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if len(c.categoryNames) == 0 {
		return "whiskey, rum, vodka, beer, gin, brandy"
	}

	lowercase := make([]string, len(c.categoryNames))
	for i, name := range c.categoryNames {
		lowercase[i] = fmt.Sprintf("\"%s\"", strings.ToLower(name))
	}
	return strings.Join(lowercase, ", ")
}

// GetSubcategoryList returns comma-separated lowercase subcategory names for prompts
func (c *CategoryMapper) GetSubcategoryList() string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if len(c.subcategoryNames) == 0 {
		return "premium, normal"
	}

	lowercase := make([]string, len(c.subcategoryNames))
	for i, name := range c.subcategoryNames {
		lowercase[i] = fmt.Sprintf("\"%s\"", strings.ToLower(name))
	}
	return strings.Join(lowercase, ", ")
}

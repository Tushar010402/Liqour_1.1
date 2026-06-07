package services

import (
	"bytes"
	"fmt"
	"regexp"
	"strconv"
	"strings"

	"github.com/xuri/excelize/v2"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// BrandExcelService handles Excel template generation and parsing for brand onboarding
type BrandExcelService struct {
	db     *gorm.DB
	logger *zap.Logger
}

// NewBrandExcelService creates a new brand Excel service
func NewBrandExcelService(db *gorm.DB, logger *zap.Logger) *BrandExcelService {
	return &BrandExcelService{
		db:     db,
		logger: logger,
	}
}

// GenerateBrandOnboardingTemplate generates an Excel template for bulk brand import
func (s *BrandExcelService) GenerateBrandOnboardingTemplate() (*bytes.Buffer, error) {
	f := excelize.NewFile()
	defer f.Close()

	// Fetch dynamic data from database
	categories, err := s.fetchCategories()
	if err != nil {
		return nil, fmt.Errorf("failed to fetch categories: %w", err)
	}

	subcategories, err := s.fetchSubcategories()
	if err != nil {
		return nil, fmt.Errorf("failed to fetch subcategories: %w", err)
	}

	categorySizes, err := s.fetchCategorySizes()
	if err != nil {
		return nil, fmt.Errorf("failed to fetch category sizes: %w", err)
	}

	// Create reference sheets first
	s.addCategoriesSheet(f, categories)
	s.addSubcategoriesSheet(f, subcategories)
	s.addSizesReferenceSheet(f, categorySizes)

	// Create main brand onboarding sheet
	sheetName := "Brand Onboarding"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to create sheet: %w", err)
	}
	f.SetActiveSheet(index)
	f.DeleteSheet("Sheet1") // Remove default sheet

	// Define headers. The two Bold columns enable per-brand display-name highlighting:
	// the UI bolds the substring `Display Name[start : start+length]`. Leave both blank
	// for plain rendering. Indices are 0-based and clipped to the display name length.
	headers := []string{
		"Brand Name*",
		"Display Name",
		"Display Name Bold Start",
		"Display Name Bold Length",
		"Description",
		"Category*",
		"Subcategory",
		"Size*",
		"Alcohol %",
		"MRP",
		"Government Duty",
		"Buying Price",
		"Selling Price",
		"Barcode",
		"Origin Country",
		"Notes",
		"Initial Stock Qty",
	}

	// Create header style
	headerStyle, err := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{
			Bold:  true,
			Size:  12,
			Color: "FFFFFF",
		},
		Fill: excelize.Fill{
			Type:    "pattern",
			Color:   []string{"2E75B6"},
			Pattern: 1,
		},
		Alignment: &excelize.Alignment{
			Horizontal: "center",
			Vertical:   "center",
		},
		Border: []excelize.Border{
			{Type: "left", Color: "000000", Style: 1},
			{Type: "right", Color: "000000", Style: 1},
			{Type: "top", Color: "000000", Style: 1},
			{Type: "bottom", Color: "000000", Style: 1},
		},
	})
	if err != nil {
		s.logger.Warn("Failed to create header style", zap.Error(err))
	}

	// Write headers
	for i, header := range headers {
		cell := fmt.Sprintf("%s1", columnIndexToLetter(i))
		f.SetCellValue(sheetName, cell, header)
		if headerStyle != 0 {
			f.SetCellStyle(sheetName, cell, cell, headerStyle)
		}
	}

	// Set column widths (column letters reflect new layout with bold columns at C/D)
	widths := map[string]float64{
		"A": 30, // Brand Name
		"B": 30, // Display Name
		"C": 14, // Display Name Bold Start
		"D": 14, // Display Name Bold Length
		"E": 35, // Description
		"F": 15, // Category
		"G": 18, // Subcategory
		"H": 12, // Size
		"I": 12, // Alcohol %
		"J": 12, // MRP
		"K": 15, // Government Duty
		"L": 15, // Buying Price
		"M": 15, // Selling Price
		"N": 18, // Barcode
		"O": 18, // Origin Country
		"P": 30, // Notes
		"Q": 18, // Initial Stock Qty
	}

	for col, width := range widths {
		f.SetColWidth(sheetName, col, col, width)
	}

	// Add data validation for categories using reference sheet (Category moved F)
	if len(categories) > 0 {
		dvCategory := excelize.NewDataValidation(true)
		dvCategory.Sqref = "F2:F1000"
		dvCategory.SetDropList(categories)
		f.AddDataValidation(sheetName, dvCategory)
	}

	// Add data validation for subcategories using reference sheet (Subcategory moved G)
	if len(subcategories) > 0 {
		dvSubcategory := excelize.NewDataValidation(true)
		dvSubcategory.Sqref = "G2:G1000"
		dvSubcategory.SetDropList(subcategories)
		f.AddDataValidation(sheetName, dvSubcategory)
	}

	// Add example rows with data from DB
	if len(categories) > 0 {
		examples := s.generateExampleRows(categories, subcategories, categorySizes)
		for i, example := range examples {
			row := i + 2
			for j, val := range example {
				cell := fmt.Sprintf("%s%d", columnIndexToLetter(j), row)
				f.SetCellValue(sheetName, cell, val)
			}
		}
	}

	// Add instructions sheet
	s.addInstructionsSheet(f, categories, categorySizes)

	// Write to buffer
	buf := new(bytes.Buffer)
	if err := f.Write(buf); err != nil {
		return nil, fmt.Errorf("failed to write Excel file: %w", err)
	}

	return buf, nil
}

// fetchCategories retrieves all active brand categories from database
func (s *BrandExcelService) fetchCategories() ([]string, error) {
	type Category struct {
		Name string
	}
	var categories []Category
	err := s.db.Table("brand_categories").
		Select("name").
		Where("is_active = ?", true).
		Order("sort_order ASC, name ASC").
		Find(&categories).Error
	if err != nil {
		return nil, err
	}

	names := make([]string, len(categories))
	for i, cat := range categories {
		names[i] = cat.Name
	}
	return names, nil
}

// fetchSubcategories retrieves all active brand subcategories from database
func (s *BrandExcelService) fetchSubcategories() ([]string, error) {
	type Subcategory struct {
		Name string
	}
	var subcategories []Subcategory
	err := s.db.Table("brand_subcategories").
		Select("name").
		Where("is_active = ?", true).
		Order("sort_order ASC, name ASC").
		Find(&subcategories).Error
	if err != nil {
		return nil, err
	}

	names := make([]string, len(subcategories))
	for i, subcat := range subcategories {
		names[i] = subcat.Name
	}
	return names, nil
}

// CategorySize represents a category and its valid sizes
type CategorySize struct {
	CategoryName string
	SizeName     string
	SortOrder    int64
}

// fetchCategorySizes retrieves all category-size mappings from database
func (s *BrandExcelService) fetchCategorySizes() (map[string][]string, error) {
	var results []CategorySize
	err := s.db.Table("category_sizes cs").
		Select("bc.name as category_name, cs.size_name, cs.sort_order").
		Joins("JOIN brand_categories bc ON cs.category_id = bc.id").
		Where("cs.is_active = ? AND cs.deleted_at IS NULL AND bc.is_active = ?", true, true).
		Order("bc.name ASC, cs.sort_order ASC").
		Find(&results).Error
	if err != nil {
		return nil, err
	}

	// Group sizes by category
	categorySizes := make(map[string][]string)
	for _, cs := range results {
		categorySizes[cs.CategoryName] = append(categorySizes[cs.CategoryName], cs.SizeName)
	}

	return categorySizes, nil
}

// addCategoriesSheet creates a reference sheet with all categories
func (s *BrandExcelService) addCategoriesSheet(f *excelize.File, categories []string) {
	sheetName := "Categories"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return
	}

	// Header
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 12, Color: "FFFFFF"},
		Fill:      excelize.Fill{Type: "pattern", Color: []string{"2E75B6"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})
	f.SetCellValue(sheetName, "A1", "Category Name")
	f.SetCellStyle(sheetName, "A1", "A1", headerStyle)
	f.SetColWidth(sheetName, "A", "A", 25)

	// Data
	for i, category := range categories {
		f.SetCellValue(sheetName, fmt.Sprintf("A%d", i+2), category)
	}

	// Don't set as active sheet
	_ = index
}

// addSubcategoriesSheet creates a reference sheet with all subcategories
func (s *BrandExcelService) addSubcategoriesSheet(f *excelize.File, subcategories []string) {
	sheetName := "Subcategories"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return
	}

	// Header
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 12, Color: "FFFFFF"},
		Fill:      excelize.Fill{Type: "pattern", Color: []string{"2E75B6"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})
	f.SetCellValue(sheetName, "A1", "Subcategory Name")
	f.SetCellStyle(sheetName, "A1", "A1", headerStyle)
	f.SetColWidth(sheetName, "A", "A", 30)

	// Data
	for i, subcategory := range subcategories {
		f.SetCellValue(sheetName, fmt.Sprintf("A%d", i+2), subcategory)
	}

	_ = index
}

// addSizesReferenceSheet creates a reference sheet showing valid sizes for each category
func (s *BrandExcelService) addSizesReferenceSheet(f *excelize.File, categorySizes map[string][]string) {
	sheetName := "Valid Sizes"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return
	}

	// Header
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 12, Color: "FFFFFF"},
		Fill:      excelize.Fill{Type: "pattern", Color: []string{"2E75B6"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})
	f.SetCellValue(sheetName, "A1", "Category")
	f.SetCellValue(sheetName, "B1", "Valid Sizes")
	f.SetCellStyle(sheetName, "A1", "B1", headerStyle)
	f.SetColWidth(sheetName, "A", "A", 20)
	f.SetColWidth(sheetName, "B", "B", 50)

	// Data
	row := 2
	for category, sizes := range categorySizes {
		f.SetCellValue(sheetName, fmt.Sprintf("A%d", row), category)
		sizesStr := ""
		for i, size := range sizes {
			if i > 0 {
				sizesStr += ", "
			}
			sizesStr += size
		}
		f.SetCellValue(sheetName, fmt.Sprintf("B%d", row), sizesStr)
		row++
	}

	_ = index
}

// generateExampleRows creates example rows based on actual database data
func (s *BrandExcelService) generateExampleRows(categories []string, subcategories []string, categorySizes map[string][]string) [][]interface{} {
	examples := [][]interface{}{}

	// Generate 1-3 examples if we have data
	if len(categories) > 0 {
		// Example 1: First category
		cat1 := categories[0]
		sizes1 := categorySizes[cat1]
		size1 := "750"
		if len(sizes1) > 0 {
			size1 = sizes1[0]
		}
		subcat1 := ""
		if len(subcategories) > 0 {
			subcat1 = subcategories[0]
		}
		examples = append(examples, []interface{}{
			"Example Brand 1", "Example Brand One", 0, 13, "Premium quality product", cat1, subcat1, size1, 40.0, 750.00, 120.00, 630.00, 700.00, "1234567890123", "India", "Example brand for reference", 100,
		})
	}

	if len(categories) > 1 {
		// Example 2: Second category
		cat2 := categories[1]
		sizes2 := categorySizes[cat2]
		size2 := "650"
		if len(sizes2) > 0 {
			size2 = sizes2[0]
		}
		subcat2 := ""
		if len(subcategories) > 1 {
			subcat2 = subcategories[1]
		}
		examples = append(examples, []interface{}{
			"Example Brand 2", "", "", "", "Popular choice", cat2, subcat2, size2, 5.0, 120.00, 15.00, 105.00, 110.00, "1234567890124", "India", "Another example", 200,
		})
	}

	if len(categories) > 2 {
		// Example 3: Third category
		cat3 := categories[2]
		sizes3 := categorySizes[cat3]
		size3 := "750"
		if len(sizes3) > 0 {
			size3 = sizes3[0]
		}
		subcat3 := ""
		if len(subcategories) > 2 {
			subcat3 = subcategories[2]
		}
		examples = append(examples, []interface{}{
			"Example Brand 3", "Brand Three", 6, 5, "Premium international", cat3, subcat3, size3, 40.0, 1500.00, 200.00, 1300.00, 1400.00, "1234567890125", "Scotland", "Delete these examples before uploading", 50,
		})
	}

	return examples
}

// addInstructionsSheet adds detailed instructions for brand onboarding
func (s *BrandExcelService) addInstructionsSheet(f *excelize.File, categories []string, categorySizes map[string][]string) {
	sheetName := "Instructions"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return
	}
	f.SetActiveSheet(index)

	// Title
	titleStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 16, Color: "2E75B6"},
		Alignment: &excelize.Alignment{Vertical: "center"},
	})
	f.SetCellValue(sheetName, "A1", "📋 Brand Onboarding Instructions")
	f.SetCellStyle(sheetName, "A1", "A1", titleStyle)
	f.SetRowHeight(sheetName, 1, 30)

	// Build dynamic instructions content
	instructions := []string{
		"",
		"✅ HOW TO USE THIS TEMPLATE:",
		"",
		"📊 IMPORTANT: This template uses DYNAMIC DATA from your system!",
		"   • Categories, Subcategories, and Sizes are pulled from your database",
		"   • Check the 'Categories', 'Subcategories', and 'Valid Sizes' sheets for reference",
		"   • This ensures uniformity with your stock management system",
		"",
		"1. REQUIRED FIELDS (marked with *):",
		"   • Brand Name: Enter the official brand name",
		"   • Category: Select from dropdown - MUST match your system categories",
		"   • Size: Enter size (e.g., 750, 650, 375) - check 'Valid Sizes' sheet for each category",
		"   • MRP: Maximum Retail Price as per government regulations",
		"   • Government Duty: Excise duty/tax amount per bottle",
		"",
		"2. OPTIONAL FIELDS:",
		"   • Display Name: User-friendly name shown in app (leave blank to use Brand Name)",
		"   • Description: Detailed description of the brand",
		"   • Subcategory: Select from dropdown - check 'Subcategories' sheet",
		"   • Alcohol %: Alcohol percentage (e.g., 40.0, 5.0)",
		"   • Buying Price: Your wholesale/purchasing cost per bottle",
		"   • Selling Price: Your retail selling price to customers",
		"   • Barcode: Product barcode/EAN code if available",
		"   • Origin Country: Country of origin/manufacture",
		"   • Notes: Any additional notes or remarks",
		"   • Initial Stock Qty: Starting inventory quantity for selected shop",
		"",
		"3. REFERENCE SHEETS (Check these for valid values):",
		"   • 'Categories' sheet: All available categories from your system",
		"   • 'Subcategories' sheet: All available subcategories",
		"   • 'Valid Sizes' sheet: Category-specific valid sizes",
		"",
		"4. CATEGORY-SPECIFIC SIZES:",
		fmt.Sprintf("   %d categories loaded from your database", len(categories)),
	}

	// Add category-size info dynamically
	instructions = append(instructions, "   Each category has its own valid sizes:")
	for _, cat := range categories {
		if sizes, ok := categorySizes[cat]; ok && len(sizes) > 0 {
			sizesStr := ""
			for i, size := range sizes {
				if i > 0 {
					sizesStr += ", "
				}
				sizesStr += size
			}
			instructions = append(instructions, fmt.Sprintf("   • %s: %s", cat, sizesStr))
		}
	}

	instructions = append(instructions, []string{
		"",
		"5. BRAND VARIANTS:",
		"   • Each row represents ONE variant of a brand",
		"   • For multiple sizes, add separate rows with same brand name",
		"   • Example: Royal Stag with 3 sizes = 3 separate rows",
		"",
		"6. PRICING GUIDANCE:",
		"   • MRP = Government-regulated maximum price",
		"   • Government Duty = Excise tax per bottle",
		"   • Buying Price = Your purchase cost",
		"   • Selling Price = Your retail price (must be ≤ MRP)",
		"   • Formula: Buying Price + Duty + Margin = Selling Price ≤ MRP",
		"",
		"7. DATA QUALITY TIPS:",
		"   • Categories MUST match exactly (use dropdown)",
		"   • Sizes MUST match valid sizes for selected category",
		"   • Use exact brand names as printed on bottles",
		"   • Double-check MRP matches product label",
		"   • Ensure Government Duty is accurate per state regulations",
		"   • Delete example rows before uploading",
		"   • Maximum 500 rows per upload",
		"   • Save file as .xlsx format",
		"",
		"8. SHOP-SPECIFIC STOCK SETUP:",
		"   • Select target shop BEFORE uploading",
		"   • Initial Stock Qty column sets starting inventory for that shop",
		"   • Leave blank or 0 if no initial stock needed",
		"   • Stock can be adjusted later via inventory management",
		"   • Stock will ONLY be created if shop is selected during upload",
		"",
		"9. AFTER UPLOAD:",
		"   • System will validate all data against your categories/sizes",
		"   • Review validation results",
		"   • Correct any errors highlighted",
		"   • Confirm import to add brands to catalog",
		"   • Initial stock will be created for selected shop",
		"",
		"10. COMMON ERRORS TO AVOID:",
		"   • Missing required fields (Brand Name, Category, Size, MRP, Duty)",
		"   • Invalid category (not in your system)",
		"   • Invalid size for selected category (check Valid Sizes sheet)",
		"   • Duplicate brand variants (same brand + category + size)",
		"   • Selling Price > MRP",
		"   • Negative values in price fields",
		"   • Invalid alcohol percentage (must be 0-100)",
		"",
		"⚠️  VALIDATION:",
		"   • Categories are validated against your system database",
		"   • Sizes should match your category-size mappings",
		"   • Mismatched data will be flagged during import",
		"",
		"📞 Need help? Contact support or check documentation.",
		"",
		"💡 TIP: Start with 5-10 brands to test the process before",
		"uploading your complete catalog.",
	}...)

	for i, line := range instructions {
		row := i + 1
		f.SetCellValue(sheetName, fmt.Sprintf("A%d", row), line)

		// Style section headers
		if i > 0 && len(line) > 0 && (line[0] >= '1' && line[0] <= '9') {
			sectionStyle, _ := f.NewStyle(&excelize.Style{
				Font: &excelize.Font{Bold: true, Size: 11, Color: "2E75B6"},
			})
			f.SetCellStyle(sheetName, fmt.Sprintf("A%d", row), fmt.Sprintf("A%d", row), sectionStyle)
		}
	}

	f.SetColWidth(sheetName, "A", "A", 90)
}

// ParseBrandExcelFile parses an uploaded Excel file and returns brand data
func (s *BrandExcelService) ParseBrandExcelFile(file []byte) (*BrandImportResult, error) {
	f, err := excelize.OpenReader(bytes.NewReader(file))
	if err != nil {
		return nil, fmt.Errorf("failed to open Excel file: %w", err)
	}
	defer f.Close()

	result := &BrandImportResult{
		TotalRows:      0,
		SuccessCount:   0,
		ErrorCount:     0,
		Errors:         []BrandImportError{},
		ImportedBrands: []ImportedBrandData{},
	}

	sheetName := "Brand Onboarding"
	rows, err := f.GetRows(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to read sheet: %w", err)
	}

	if len(rows) < 2 {
		return nil, fmt.Errorf("no data rows found in Excel file")
	}

	// Load valid category names from the DB ONCE per import. The previous hardcoded
	// list ("Whiskey","Beer",…) drifted from the actual brand_categories table — UP
	// Excise data uses "Whisky" (British spelling) and "Country Liquor", neither in
	// the hardcoded list, so 690+ rows were rejected. The DB is authoritative.
	categoryNames, err := s.fetchCategories()
	if err != nil {
		return nil, fmt.Errorf("failed to load categories for validation: %w", err)
	}
	validCategories := make(map[string]bool, len(categoryNames))
	for _, name := range categoryNames {
		validCategories[strings.ToLower(strings.TrimSpace(name))] = true
	}

	// Skip header row (row 0) and process data rows
	for rowIdx := 1; rowIdx < len(rows); rowIdx++ {
		row := rows[rowIdx]
		result.TotalRows++

		// Skip empty rows
		if len(row) == 0 || (len(row) > 0 && row[0] == "") {
			continue
		}

		brandData, err := s.parseRowWithCategories(row, rowIdx+1, validCategories)
		if err != nil {
			result.ErrorCount++
			result.Errors = append(result.Errors, BrandImportError{
				Row:     rowIdx + 1,
				Message: err.Error(),
			})
			continue
		}

		result.ImportedBrands = append(result.ImportedBrands, *brandData)
		result.SuccessCount++
	}

	return result, nil
}

// parseRowWithCategories is the production parser used by ParseBrandExcelFile.
// It accepts a pre-built lowercase category set so we don't hammer the DB for
// every row. parseRow remains as a thin wrapper for back-compat with any tests.
func (s *BrandExcelService) parseRowWithCategories(row []string, rowNum int, validCategories map[string]bool) (*ImportedBrandData, error) {
	data, err := s.parseRowFields(row)
	if err != nil {
		return nil, err
	}
	if !validCategories[strings.ToLower(strings.TrimSpace(data.Category))] {
		return nil, fmt.Errorf("Invalid category: %s", data.Category)
	}
	return data, nil
}

// parseRow uses the legacy hardcoded category list. Kept for back-compat only —
// new code paths must use parseRowWithCategories so the DB stays authoritative.
func (s *BrandExcelService) parseRow(row []string, rowNum int) (*ImportedBrandData, error) {
	data, err := s.parseRowFields(row)
	if err != nil {
		return nil, err
	}
	validCategories := map[string]bool{
		"Whiskey": true, "Beer": true, "Wine": true, "Vodka": true,
		"Rum": true, "Brandy": true, "Gin": true, "Tequila": true,
		"Champagne": true, "RTD": true, "Cider": true, "Liqueur": true, "Others": true,
	}
	if !validCategories[data.Category] {
		return nil, fmt.Errorf("Invalid category: %s", data.Category)
	}
	return data, nil
}

// normalizeSize coerces every size literal we accept ("180", "180 ML", "180ml",
// "180Ml", "1L", "1 l") into the canonical UPPER+no-space form ("180ML", "1L").
// Bare numbers default to ML since UP Excise master data ships sizes that way.
// Without this, the import created twin rows like "180" + "180ML" for the same
// physical SKU and downstream lookups split across both.
func normalizeSize(s string) string {
	t := strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(s), " ", ""))
	if t == "" {
		return ""
	}
	switch {
	case sizeNumOnlyRegex.MatchString(t):
		return t + "ML"
	case sizeNumMLRegex.MatchString(t), sizeNumLRegex.MatchString(t):
		return t
	default:
		return t // unrecognized formats (e.g. "Keg") pass through uppercased
	}
}

var (
	sizeNumOnlyRegex = regexp.MustCompile(`^[0-9]+$`)
	sizeNumMLRegex   = regexp.MustCompile(`^[0-9]+ML$`)
	sizeNumLRegex    = regexp.MustCompile(`^[0-9]+L$`)
)

// parseRowFields handles the column extraction + non-category validation shared
// between parseRow (legacy hardcoded categories) and parseRowWithCategories
// (DB-backed). Splitting category validation lets the DB-backed caller accept
// e.g. "Whisky" / "Country Liquor" that the hardcoded list never knew about.
func (s *BrandExcelService) parseRowFields(row []string) (*ImportedBrandData, error) {
	// Ensure row has enough columns (17 with the two display-name bold columns)
	for len(row) < 17 {
		row = append(row, "")
	}

	data := &ImportedBrandData{
		BrandName:             getString(row, 0),
		DisplayName:           getString(row, 1),
		DisplayNameBoldStart:  getString(row, 2),
		DisplayNameBoldLength: getString(row, 3),
		Description:           getString(row, 4),
		Category:              getString(row, 5),
		Subcategory:           getString(row, 6),
		Size:                  getString(row, 7),
		AlcoholContent:        getString(row, 8),
		MRP:                   getString(row, 9),
		GovernmentDuty:        getString(row, 10),
		BuyingPrice:           getString(row, 11),
		SellingPrice:          getString(row, 12),
		Barcode:               getString(row, 13),
		OriginCountry:         getString(row, 14),
		Notes:                 getString(row, 15),
		InitialStockQty:       getString(row, 16),
	}

	if data.BrandName == "" {
		return nil, fmt.Errorf("Brand Name is required")
	}
	if data.Category == "" {
		return nil, fmt.Errorf("Category is required")
	}
	if data.Size == "" {
		return nil, fmt.Errorf("Size is required")
	}
	// Canonicalize Size before any downstream lookup so "180", "180 ml", "180ML" all
	// resolve to the same brand_variants row. The catalog had ~1.4k duplicate variants
	// from this drift before normalization was added.
	data.Size = normalizeSize(data.Size)
	// MRP and Government Duty are optional for bulk catalog imports — many master
	// data feeds (e.g. UP Excise full catalog) ship name+size+category only and
	// expect prices to be set later per-tenant. Rows without these still create the
	// brand/variant; missing numeric fields fall through parseFloat as 0.

	// Validate Bold Start/Length pair. Treat length=0 (or both 0) as "no highlight"
	// so spreadsheets that pre-fill zeros for unused rows still import. Only fail
	// when start/length form an INVALID range (negative start, length>0 but slice
	// out-of-bounds, or non-integer values).
	if data.DisplayNameBoldStart != "" || data.DisplayNameBoldLength != "" {
		startStr := strings.TrimSpace(data.DisplayNameBoldStart)
		lenStr := strings.TrimSpace(data.DisplayNameBoldLength)
		if startStr == "" {
			startStr = "0"
		}
		if lenStr == "" {
			lenStr = "0"
		}
		startVal, errStart := strconv.Atoi(startStr)
		lenVal, errLen := strconv.Atoi(lenStr)
		if errStart != nil || errLen != nil {
			return nil, fmt.Errorf("Display Name Bold Start/Length must be integers (got start=%q length=%q)", data.DisplayNameBoldStart, data.DisplayNameBoldLength)
		}
		if lenVal == 0 {
			// No highlight requested — clear both so import doesn't persist a dead range.
			data.DisplayNameBoldStart = ""
			data.DisplayNameBoldLength = ""
		} else {
			if startVal < 0 {
				return nil, fmt.Errorf("Display Name Bold Start must be >= 0 (got %d)", startVal)
			}
			if lenVal < 0 {
				return nil, fmt.Errorf("Display Name Bold Length must be >= 0 (got %d)", lenVal)
			}
			anchor := data.DisplayName
			if anchor == "" {
				anchor = data.BrandName
			}
			if startVal+lenVal > len(anchor) {
				return nil, fmt.Errorf("Display Name Bold range start=%d length=%d exceeds name length %d", startVal, lenVal, len(anchor))
			}
			// Re-normalize back into the data so the importer reads them as integers.
			data.DisplayNameBoldStart = strconv.Itoa(startVal)
			data.DisplayNameBoldLength = strconv.Itoa(lenVal)
		}
	}

	return data, nil
}

// getString safely gets a string from row at index
func getString(row []string, index int) string {
	if index < len(row) {
		return row[index]
	}
	return ""
}

// columnIndexToLetter converts column index to Excel column letter
func columnIndexToLetter(index int) string {
	if index < 26 {
		return string(rune('A' + index))
	}
	return string(rune('A'+(index/26)-1)) + string(rune('A'+(index%26)))
}

// BrandImportResult represents the result of parsing an Excel file
type BrandImportResult struct {
	TotalRows      int                 `json:"total_rows"`
	SuccessCount   int                 `json:"success_count"`
	ErrorCount     int                 `json:"error_count"`
	Errors         []BrandImportError  `json:"errors"`
	ImportedBrands []ImportedBrandData `json:"imported_brands"`
}

// BrandImportError represents an error during import
type BrandImportError struct {
	Row     int    `json:"row"`
	Message string `json:"message"`
}

// ImportedBrandData represents parsed brand data from Excel
type ImportedBrandData struct {
	BrandName             string `json:"brand_name"`
	DisplayName           string `json:"display_name"`
	DisplayNameBoldStart  string `json:"display_name_bold_start"`
	DisplayNameBoldLength string `json:"display_name_bold_length"`
	Description           string `json:"description"`
	Category              string `json:"category"`
	Subcategory           string `json:"subcategory"`
	Size                  string `json:"size"`
	AlcoholContent        string `json:"alcohol_content"`
	MRP                   string `json:"mrp"`
	GovernmentDuty        string `json:"government_duty"`
	BuyingPrice           string `json:"buying_price"`
	SellingPrice          string `json:"selling_price"`
	Barcode               string `json:"barcode"`
	OriginCountry         string `json:"origin_country"`
	Notes                 string `json:"notes"`
	InitialStockQty       string `json:"initial_stock_qty"`
}

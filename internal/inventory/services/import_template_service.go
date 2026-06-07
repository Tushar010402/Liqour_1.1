package services

import (
	"bytes"
	"fmt"

	"github.com/sirupsen/logrus"
	"github.com/xuri/excelize/v2"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// ImportTemplateService handles generation of Excel import templates
type ImportTemplateService struct {
	db     *gorm.DB
	logger *logrus.Logger
}

// NewImportTemplateService creates a new import template service
func NewImportTemplateService(db *gorm.DB, logger *logrus.Logger) *ImportTemplateService {
	return &ImportTemplateService{
		db:     db,
		logger: logger,
	}
}

// GenerateBasicTemplate generates a basic product import template
func (s *ImportTemplateService) GenerateBasicTemplate(req models.ExcelTemplateRequest) (*bytes.Buffer, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheetName := "Products Import"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to create sheet: %w", err)
	}
	f.SetActiveSheet(index)
	f.DeleteSheet("Sheet1") // Remove default sheet

	// Define headers with styling
	headers := []string{
		"Brand Name*",
		"Size*",
		"Category*",
		"Subcategory",
		"Quantity*",
		"Buying Price",
		"MRP",
		"Duty",
		"Selling Price",
		"Shop",
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
			Color:   []string{"4472C4"},
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
		s.logger.Warnf("Failed to create header style: %v", err)
	}

	// Write headers
	for i, header := range headers {
		cell := fmt.Sprintf("%s1", string(rune('A'+i)))
		f.SetCellValue(sheetName, cell, header)
		if headerStyle != 0 {
			f.SetCellStyle(sheetName, cell, cell, headerStyle)
		}
	}

	// Set column widths
	widths := map[string]float64{
		"A": 25, // Brand Name
		"B": 15, // Size
		"C": 15, // Category
		"D": 15, // Subcategory
		"E": 12, // Quantity
		"F": 15, // Buying Price
		"G": 12, // MRP
		"H": 12, // Duty
		"I": 15, // Selling Price
		"J": 20, // Shop
	}

	for col, width := range widths {
		f.SetColWidth(sheetName, col, col, width)
	}

	// Add data validation for categories
	categories := s.getCategories()
	if len(categories) > 0 {
		dvRange := excelize.NewDataValidation(true)
		dvRange.Sqref = "C2:C1000"
		dvRange.SetDropList(categories)
		f.AddDataValidation(sheetName, dvRange)
	}

	// Add example rows if requested
	if req.IncludeExamples {
		examples := [][]interface{}{
			{"Royal Stag", "750ml", "Whiskey", "Blended Scotch", 24, 680.00, 750.00, 120.00, 700.00, "Shop A"},
			{"Kingfisher Premium", "650ml", "Beer", "Lager", 48, 80.00, 120.00, 15.00, 100.00, "Shop A"},
			{"100 Pipers", "375ml", "Whiskey", "Blended Scotch", 12, 340.00, 400.00, 60.00, 380.00, "Shop B"},
			{"Breezer", "275ml", "RTD", "Flavored Drink", 36, 45.00, 60.00, 8.00, 55.00, "Shop A"},
		}

		for i, example := range examples {
			row := i + 2
			for j, val := range example {
				cell := fmt.Sprintf("%s%d", string(rune('A'+j)), row)
				f.SetCellValue(sheetName, cell, val)
			}
		}
	}

	// Add instructions sheet
	s.addInstructionsSheet(f)

	// Write to buffer
	buf := new(bytes.Buffer)
	if err := f.Write(buf); err != nil {
		return nil, fmt.Errorf("failed to write Excel file: %w", err)
	}

	return buf, nil
}

// GenerateAdvancedTemplate generates an advanced template with additional fields
func (s *ImportTemplateService) GenerateAdvancedTemplate(req models.ExcelTemplateRequest) (*bytes.Buffer, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheetName := "Advanced Import"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to create sheet: %w", err)
	}
	f.SetActiveSheet(index)
	f.DeleteSheet("Sheet1")

	// Extended headers
	headers := []string{
		"Brand Name*",
		"Size*",
		"Category*",
		"Subcategory",
		"Quantity*",
		"Buying Price",
		"MRP",
		"Duty",
		"Selling Price",
		"Shop",
		"Barcode",
		"SKU",
		"Description",
		"Manufacturer",
		"Country",
		"Alcohol %",
		"Reorder Level",
		"Expiry Date",
	}

	// Create header style
	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font: &excelize.Font{Bold: true, Size: 11, Color: "FFFFFF"},
		Fill: excelize.Fill{Type: "pattern", Color: []string{"2E75B6"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})

	// Write headers
	for i, header := range headers {
		cell := fmt.Sprintf("%s1", s.columnIndexToLetter(i))
		f.SetCellValue(sheetName, cell, header)
		f.SetCellStyle(sheetName, cell, cell, headerStyle)
	}

	// Set column widths
	for i := 0; i < len(headers); i++ {
		col := s.columnIndexToLetter(i)
		width := 15.0
		if i == 0 {
			width = 25.0 // Brand Name
		} else if i == 12 {
			width = 30.0 // Description
		}
		f.SetColWidth(sheetName, col, col, width)
	}

	// Add example if requested
	if req.IncludeExamples {
		example := []interface{}{
			"Black Label", "750ml", "Whiskey", "Premium Scotch", 12, 1200.00, 1500.00, 200.00, 1400.00,
			"Main Store", "8901234567890", "BL-750-001", "Premium Blended Scotch Whiskey",
			"Diageo", "Scotland", 40.0, 5, "2026-12-31",
		}
		for j, val := range example {
			cell := fmt.Sprintf("%s2", s.columnIndexToLetter(j))
			f.SetCellValue(sheetName, cell, val)
		}
	}

	s.addInstructionsSheet(f)

	buf := new(bytes.Buffer)
	if err := f.Write(buf); err != nil {
		return nil, fmt.Errorf("failed to write Excel file: %w", err)
	}

	return buf, nil
}

// GenerateInvoiceTemplate generates a template matching invoice format
func (s *ImportTemplateService) GenerateInvoiceTemplate(req models.ExcelTemplateRequest) (*bytes.Buffer, error) {
	f := excelize.NewFile()
	defer f.Close()

	sheetName := "Invoice Import"
	index, err := f.NewSheet(sheetName)
	if err != nil {
		return nil, fmt.Errorf("failed to create sheet: %w", err)
	}
	f.SetActiveSheet(index)
	f.DeleteSheet("Sheet1")

	// Invoice-style headers
	headers := []string{
		"S.No.",
		"Product Name*",
		"Size*",
		"Category*",
		"Cases",
		"Bottles Per Case",
		"Total Bottles*",
		"Rate Per Bottle",
		"Total Amount",
		"Duty Amount",
		"Invoice Number",
		"Invoice Date",
		"Supplier Name",
	}

	headerStyle, _ := f.NewStyle(&excelize.Style{
		Font:      &excelize.Font{Bold: true, Size: 11, Color: "FFFFFF"},
		Fill:      excelize.Fill{Type: "pattern", Color: []string{"70AD47"}, Pattern: 1},
		Alignment: &excelize.Alignment{Horizontal: "center", Vertical: "center"},
	})

	for i, header := range headers {
		cell := fmt.Sprintf("%s1", s.columnIndexToLetter(i))
		f.SetCellValue(sheetName, cell, header)
		f.SetCellStyle(sheetName, cell, cell, headerStyle)
	}

	// Set widths
	for i := 0; i < len(headers); i++ {
		col := s.columnIndexToLetter(i)
		width := 15.0
		if i == 1 {
			width = 30.0 // Product Name
		} else if i == 12 {
			width = 25.0 // Supplier Name
		}
		f.SetColWidth(sheetName, col, col, width)
	}

	if req.IncludeExamples {
		examples := [][]interface{}{
			{1, "Royal Stag 750ml", "750ml", "Whiskey", 2, 12, 24, 680.00, 16320.00, 2880.00, "INV-2025-001", "2025-10-21", "ABC Distributors"},
			{2, "Kingfisher Premium 650ml", "650ml", "Beer", 4, 12, 48, 80.00, 3840.00, 720.00, "INV-2025-001", "2025-10-21", "ABC Distributors"},
		}

		for i, example := range examples {
			row := i + 2
			for j, val := range example {
				cell := fmt.Sprintf("%s%d", s.columnIndexToLetter(j), row)
				f.SetCellValue(sheetName, cell, val)
			}
		}

		// Add formulas for calculated fields
		f.SetCellFormula(sheetName, "G2", "=E2*F2")  // Total Bottles
		f.SetCellFormula(sheetName, "I2", "=G2*H2")  // Total Amount
		f.SetCellFormula(sheetName, "G3", "=E3*F3")
		f.SetCellFormula(sheetName, "I3", "=G3*H3")
	}

	s.addInstructionsSheet(f)

	buf := new(bytes.Buffer)
	if err := f.Write(buf); err != nil {
		return nil, fmt.Errorf("failed to write Excel file: %w", err)
	}

	return buf, nil
}

// addInstructionsSheet adds an instructions sheet to the workbook
func (s *ImportTemplateService) addInstructionsSheet(f *excelize.File) {
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
	f.SetCellValue(sheetName, "A1", "📋 Import Instructions")
	f.SetCellStyle(sheetName, "A1", "A1", titleStyle)
	f.SetRowHeight(sheetName, 1, 30)

	// Instructions
	instructions := []string{
		"",
		"✅ HOW TO USE THIS TEMPLATE:",
		"",
		"1. REQUIRED FIELDS (marked with *):",
		"   • Brand Name: Enter the exact brand name (e.g., Royal Stag, Kingfisher)",
		"   • Size: Enter bottle size (e.g., 750ml, 650ml, 375ml, 180ml)",
		"   • Category: Select from dropdown (Whiskey, Beer, Wine, Vodka, Rum, etc.)",
		"   • Quantity: Number of bottles to stock",
		"",
		"2. OPTIONAL FIELDS:",
		"   • Subcategory: More specific categorization (e.g., Blended Scotch, Lager)",
		"   • Buying Price: Your purchase cost per bottle",
		"   • MRP: Maximum Retail Price printed on bottle",
		"   • Duty: Government duty/tax per bottle",
		"   • Selling Price: Your selling price to customers",
		"   • Shop: Shop name (if managing multiple locations)",
		"",
		"3. SMART MATCHING:",
		"   • System will auto-match brands from SaaS catalog",
		"   • Prices will be auto-filled from catalog when available",
		"   • You can override auto-filled prices if needed",
		"",
		"4. TIPS FOR BEST RESULTS:",
		"   • Use exact brand names from your supplier invoice",
		"   • Include size with 'ml' (e.g., 750ml, not just 750)",
		"   • Delete example rows before uploading",
		"   • Maximum 1000 rows per upload",
		"   • Save file as .xlsx format",
		"",
		"5. COMMON SIZE FORMATS:",
		"   • Full Bottle: 750ml, 750, FL, Bottle",
		"   • Half Bottle: 375ml, 375, Half",
		"   • Quarter: 180ml, 180, Quarter, Quart",
		"   • Pint: 200ml, 200, Pint",
		"   • Beer Can: 330ml, 330, Can",
		"   • Beer Large: 650ml, 650, King, Large",
		"",
		"6. AFTER UPLOAD:",
		"   • Review validation results",
		"   • Correct any errors highlighted",
		"   • Confirm import to add products",
		"   • Check your stock to verify",
		"",
		"📞 Need help? Contact support or check documentation.",
	}

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

	f.SetColWidth(sheetName, "A", "A", 80)
}

// getCategories fetches available categories from database
func (s *ImportTemplateService) getCategories() []string {
	var categories []models.Category
	s.db.Select("name").Where("is_active = ?", true).Find(&categories)

	categoryNames := make([]string, len(categories))
	for i, cat := range categories {
		categoryNames[i] = cat.Name
	}

	// Add common categories if none in database
	if len(categoryNames) == 0 {
		categoryNames = []string{
			"Whiskey", "Beer", "Wine", "Vodka", "Rum", "Brandy", "Gin",
			"Tequila", "Champagne", "RTD", "Others",
		}
	}

	return categoryNames
}

// columnIndexToLetter converts column index to Excel column letter
func (s *ImportTemplateService) columnIndexToLetter(index int) string {
	if index < 26 {
		return string(rune('A' + index))
	}
	return string(rune('A'+(index/26)-1)) + string(rune('A'+(index%26)))
}

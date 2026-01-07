package services

import (
	"testing"

	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/pkg/ocr"
)

// Test cleanOCRText function
func TestCleanOCRText(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Remove Devanagari numerals",
			input:    "Royal Green ५० 0",
			expected: "Royal Green 0",
		},
		{
			name:     "Remove Bengali numerals",
			input:    "Black Dog ৬ a 0",
			expected: "Black Dog a 0",
		},
		{
			name:     "Remove pipe artifacts",
			input:    "Brand Name | | Value",
			expected: "Brand Name | Value",
		},
		{
			name:     "Remove double pipes",
			input:    "Brand || Price",
			expected: "Brand | Price",
		},
		{
			name:     "Remove excessive whitespace",
			input:    "Royal  Green    180ml",
			expected: "Royal Green 180ml",
		},
		{
			name:     "Complex case with multiple artifacts",
			input:    "8 P.M. Black ५०  | | 0",
			expected: "8 P.M. Black | 0",
		},
		{
			name:     "Empty string",
			input:    "",
			expected: "",
		},
		{
			name:     "Only whitespace",
			input:    "   ",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := cleanOCRText(tt.input)
			if result != tt.expected {
				t.Errorf("cleanOCRText() = %q, expected %q", result, tt.expected)
			}
		})
	}
}

// Test cleanBrandName function
func TestCleanBrandName(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Remove trailing numbers and pipes",
			input:    "Royal Green 0 0 | 0",
			expected: "Royal Green",
		},
		{
			name:     "Remove trailing single letters",
			input:    "Black Dog 6 a 0 0",
			expected: "Black Dog",
		},
		{
			name:     "Remove trailing dots",
			input:    "8 P.M. Black | 0 .",
			expected: "8 P.M. Black",
		},
		{
			name:     "Keep valid brand with abbreviations",
			input:    "8 P.M. Black",
			expected: "8 P.M. Black",
		},
		{
			name:     "Remove Devanagari numerals",
			input:    "Royal Green ५० 0",
			expected: "Royal Green",
		},
		{
			name:     "Remove Bengali numerals",
			input:    "Black Dog ৬ 0",
			expected: "Black Dog",
		},
		{
			name:     "Keep brand with capital letters",
			input:    "OLD MONK GOLD RESERVE",
			expected: "OLD MONK GOLD RESERVE",
		},
		{
			name:     "Complex case - keep valid words only",
			input:    "Royal Stag Barrel Select 0 0 | . 0",
			expected: "Royal Stag Barrel Select",
		},
		{
			name:     "Single word brand",
			input:    "Smirnoff 0",
			expected: "Smirnoff",
		},
		{
			name:     "Brand with numbers in name (not trailing)",
			input:    "100 Pipers 0",
			expected: "100 Pipers",
		},
		{
			name:     "Empty string",
			input:    "",
			expected: "",
		},
		{
			name:     "Only garbage",
			input:    "0 0 | . 0",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := cleanBrandName(tt.input)
			if result != tt.expected {
				t.Errorf("cleanBrandName() = %q, expected %q", result, tt.expected)
			}
		})
	}
}

// Test validateExtractedItem function
func TestValidateExtractedItem(t *testing.T) {
	tests := []struct {
		name     string
		item     *models.OCRItem
		expected bool
	}{
		{
			name: "Valid brand name",
			item: &models.OCRItem{
				BrandText: "Royal Green",
				Quantity:  10,
			},
			expected: true,
		},
		{
			name: "Valid brand with abbreviations",
			item: &models.OCRItem{
				BrandText: "8 P.M. Black",
				Quantity:  5,
			},
			expected: true,
		},
		{
			name: "Valid brand with multiple words",
			item: &models.OCRItem{
				BrandText: "Old Monk Gold Reserve",
				Quantity:  8,
			},
			expected: true,
		},
		{
			name: "Invalid - too short (single letter)",
			item: &models.OCRItem{
				BrandText: "A",
				Quantity:  1,
			},
			expected: false,
		},
		{
			name: "Invalid - only numbers",
			item: &models.OCRItem{
				BrandText: "123",
				Quantity:  1,
			},
			expected: false,
		},
		{
			name: "Invalid - only special characters",
			item: &models.OCRItem{
				BrandText: "| | .",
				Quantity:  1,
			},
			expected: false,
		},
		{
			name: "Invalid - empty string",
			item: &models.OCRItem{
				BrandText: "",
				Quantity:  1,
			},
			expected: false,
		},
		{
			name: "Invalid - only whitespace",
			item: &models.OCRItem{
				BrandText: "   ",
				Quantity:  1,
			},
			expected: false,
		},
		{
			name: "Invalid - garbage characters",
			item: &models.OCRItem{
				BrandText: "0 0 | 0",
				Quantity:  1,
			},
			expected: false,
		},
		{
			name: "Valid - brand with number in name",
			item: &models.OCRItem{
				BrandText: "100 Pipers",
				Quantity:  5,
			},
			expected: true,
		},
		{
			name: "Valid - minimum valid length",
			item: &models.OCRItem{
				BrandText: "AB",
				Quantity:  2,
			},
			expected: true,
		},
		{
			name:     "Invalid - nil item",
			item:     nil,
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := validateExtractedItem(tt.item)
			if result != tt.expected {
				brandText := ""
				if tt.item != nil {
					brandText = tt.item.BrandText
				}
				t.Errorf("validateExtractedItem(%q) = %v, expected %v", brandText, result, tt.expected)
			}
		})
	}
}

// Test preprocessVisionText function
func TestPreprocessVisionText(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected string
	}{
		{
			name:     "Clean Vision API output with pipes",
			input:    "Royal Green | 180ml | 0",
			expected: "Royal Green | 180ml | 0",
		},
		{
			name:     "Remove Devanagari numerals",
			input:    "Royal Green ५० | 180ml",
			expected: "Royal Green | 180ml",
		},
		{
			name:     "Remove double pipes",
			input:    "Brand || Price || Qty",
			expected: "Brand | Price | Qty",
		},
		{
			name:     "Remove excessive whitespace",
			input:    "Royal  Green   |  180ml",
			expected: "Royal Green | 180ml",
		},
		{
			name:     "Complex case with multiple artifacts",
			input:    "8 P.M. Black ५०  | | 180ml || 0",
			expected: "8 P.M. Black | 180ml | 0",
		},
		{
			name:     "Clean table with multiple rows",
			input:    "Brand | Size | Qty\nRoyal Green ५० | 180ml | 0\nBlack Dog ৬ | 750ml | 10",
			expected: "Brand | Size | Qty\nRoyal Green | 180ml | 0\nBlack Dog | 750ml | 10",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := preprocessVisionText(tt.input)
			if result != tt.expected {
				t.Errorf("preprocessVisionText() = %q, expected %q", result, tt.expected)
			}
		})
	}
}

// Benchmark tests to ensure performance
func BenchmarkCleanOCRText(b *testing.B) {
	input := "Royal Green ५० 0 | | 180ml    "
	for i := 0; i < b.N; i++ {
		cleanOCRText(input)
	}
}

func BenchmarkCleanBrandName(b *testing.B) {
	input := "Royal Green 0 0 | 0"
	for i := 0; i < b.N; i++ {
		cleanBrandName(input)
	}
}

func BenchmarkValidateExtractedItem(b *testing.B) {
	item := &models.OCRItem{
		BrandText: "Royal Green",
		Quantity:  10,
	}
	for i := 0; i < b.N; i++ {
		validateExtractedItem(item)
	}
}

func BenchmarkPreprocessVisionText(b *testing.B) {
	input := "Brand | Size | Qty\nRoyal Green ५० | 180ml | 0\nBlack Dog ৬ | 750ml | 10"
	for i := 0; i < b.N; i++ {
		preprocessVisionText(input)
	}
}

// 🔧 Phase 1.3 Tests: Fuzzy Size Detection
func TestDetectReceiptType(t *testing.T) {
	tests := []struct {
		name     string
		rawText  string
		expected string
	}{
		{
			name:     "Detect 90ml standard",
			rawText:  "SALE RECEIPT - 90 M.L\nSerial Brand Opening",
			expected: "90ml",
		},
		{
			name:     "Detect 90ml with OCR error (9O)",
			rawText:  "SALE RECEIPT - 9O M.L\nSerial Brand Opening",
			expected: "90ml",
		},
		{
			name:     "Detect 90ml alias (nip)",
			rawText:  "SALE RECEIPT - NIP\nSerial Brand Opening",
			expected: "90ml",
		},
		{
			name:     "Detect 180ml standard",
			rawText:  "SALE RECEIPT - 180 M.L\nSerial Brand Opening",
			expected: "180ml",
		},
		{
			name:     "Detect 180ml with OCR error (18O)",
			rawText:  "SALE RECEIPT - 18O M.L\nSerial Brand Opening",
			expected: "180ml",
		},
		{
			name:     "Detect 180ml alias (quarter)",
			rawText:  "SALE RECEIPT - QUARTER\nSerial Brand Opening",
			expected: "180ml",
		},
		{
			name:     "Detect 375ml standard",
			rawText:  "SALE RECEIPT - 375 M.L\nSerial Brand Opening",
			expected: "375ml",
		},
		{
			name:     "Detect 375ml with OCR error (37S)",
			rawText:  "SALE RECEIPT - 37S M.L\nSerial Brand Opening",
			expected: "375ml",
		},
		{
			name:     "Detect 375ml alias (half)",
			rawText:  "SALE RECEIPT - HALF\nSerial Brand Opening",
			expected: "375ml",
		},
		{
			name:     "Detect 750ml standard",
			rawText:  "SALE RECEIPT - 750 M.L\nSerial Brand Opening",
			expected: "750ml",
		},
		{
			name:     "Detect 750ml with OCR error (75O)",
			rawText:  "SALE RECEIPT - 75O M.L\nSerial Brand Opening",
			expected: "750ml",
		},
		{
			name:     "Detect 750ml alias (bottle)",
			rawText:  "SALE RECEIPT - BOTTLE\nSerial Brand Opening",
			expected: "750ml",
		},
		{
			name:     "Default to 180ml when no match",
			rawText:  "SALE RECEIPT\nSerial Brand Opening",
			expected: "180ml",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := detectReceiptType(tt.rawText)
			if result != tt.expected {
				t.Errorf("detectReceiptType() = %q, expected %q", result, tt.expected)
			}
		})
	}
}

// 🔧 Phase 2.1 Tests: Refactored Price Calculation
func TestValidatePriceRange(t *testing.T) {
	tests := []struct {
		name        string
		price       float64
		receiptType string
		expected    bool
	}{
		// 90ml valid range: ₹40-₹300
		{"90ml - valid min", 40.0, "90ml", true},
		{"90ml - valid mid", 90.0, "90ml", true},
		{"90ml - valid max", 300.0, "90ml", true},
		{"90ml - too low", 30.0, "90ml", false},
		{"90ml - too high", 350.0, "90ml", false},

		// 180ml valid range: ₹80-₹500
		{"180ml - valid min", 80.0, "180ml", true},
		{"180ml - valid mid", 150.0, "180ml", true},
		{"180ml - valid max", 500.0, "180ml", true},
		{"180ml - too low", 70.0, "180ml", false},
		{"180ml - too high", 600.0, "180ml", false},

		// 375ml valid range: ₹150-₹1000
		{"375ml - valid min", 150.0, "375ml", true},
		{"375ml - valid mid", 400.0, "375ml", true},
		{"375ml - valid max", 1000.0, "375ml", true},
		{"375ml - too low", 100.0, "375ml", false},
		{"375ml - too high", 1200.0, "375ml", false},

		// 750ml valid range: ₹300-₹3000
		{"750ml - valid min", 300.0, "750ml", true},
		{"750ml - valid mid", 800.0, "750ml", true},
		{"750ml - valid max", 3000.0, "750ml", true},
		{"750ml - too low", 250.0, "750ml", false},
		{"750ml - too high", 3500.0, "750ml", false},

		// Unknown type: ₹50-₹2000
		{"unknown - valid", 500.0, "unknown", true},
		{"unknown - too low", 40.0, "unknown", false},
		{"unknown - too high", 2500.0, "unknown", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := validatePriceRange(tt.price, tt.receiptType)
			if result != tt.expected {
				t.Errorf("validatePriceRange(%.2f, %s) = %v, expected %v",
					tt.price, tt.receiptType, result, tt.expected)
			}
		})
	}
}

func TestExtractPriceFromRate(t *testing.T) {
	tests := []struct {
		name        string
		numbers     []float64
		receiptType string
		columnMap   map[string]int
		expectedOk  bool
		expectedVal float64
	}{
		{
			name:        "Valid 90ml price extraction",
			numbers:     []float64{40, 0, 40, 12, 90, 1080, 28},
			receiptType: "90ml",
			columnMap:   map[string]int{"rate": 4, "sale": 3, "amount": 5},
			expectedOk:  true,
			expectedVal: 90.0,
		},
		{
			name:        "Price out of range - rejected",
			numbers:     []float64{40, 0, 40, 12, 500, 1080, 28}, // 500 too high for 90ml
			receiptType: "90ml",
			columnMap:   map[string]int{"rate": 4, "sale": 3, "amount": 5},
			expectedOk:  false,
			expectedVal: 0.0,
		},
		{
			name:        "Rate position out of bounds",
			numbers:     []float64{40, 0, 40},
			receiptType: "90ml",
			columnMap:   map[string]int{"rate": 10, "sale": 1, "amount": 2},
			expectedOk:  false,
			expectedVal: 0.0,
		},
		{
			name:        "Zero price",
			numbers:     []float64{40, 0, 40, 12, 0, 1080, 28},
			receiptType: "90ml",
			columnMap:   map[string]int{"rate": 4, "sale": 3, "amount": 5},
			expectedOk:  false,
			expectedVal: 0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, ok := extractPriceFromRate(tt.numbers, tt.receiptType, tt.columnMap)
			if ok != tt.expectedOk {
				t.Errorf("extractPriceFromRate() ok = %v, expected %v", ok, tt.expectedOk)
			}
			if price != tt.expectedVal {
				t.Errorf("extractPriceFromRate() price = %.2f, expected %.2f", price, tt.expectedVal)
			}
		})
	}
}

func TestExtractPriceFromCalculation(t *testing.T) {
	tests := []struct {
		name        string
		numbers     []float64
		columnMap   map[string]int
		expectedOk  bool
		expectedVal float64
	}{
		{
			name:        "Valid calculation: 1080 ÷ 12 = 90",
			numbers:     []float64{40, 0, 40, 12, 90, 1080, 28},
			columnMap:   map[string]int{"sale": 3, "amount": 5},
			expectedOk:  true,
			expectedVal: 90.0,
		},
		{
			name:        "Valid calculation: 1170 ÷ 13 = 90",
			numbers:     []float64{40, 0, 40, 13, 90, 1170, 27},
			columnMap:   map[string]int{"sale": 3, "amount": 5},
			expectedOk:  true,
			expectedVal: 90.0,
		},
		{
			name:        "Sale is zero - fails",
			numbers:     []float64{40, 0, 40, 0, 90, 1080, 28},
			columnMap:   map[string]int{"sale": 3, "amount": 5},
			expectedOk:  false,
			expectedVal: 0.0,
		},
		{
			name:        "Amount is zero - fails",
			numbers:     []float64{40, 0, 40, 12, 90, 0, 28},
			columnMap:   map[string]int{"sale": 3, "amount": 5},
			expectedOk:  false,
			expectedVal: 0.0,
		},
		{
			name:        "Calculated price out of range (too high)",
			numbers:     []float64{40, 0, 40, 1, 90, 20000, 28},
			columnMap:   map[string]int{"sale": 3, "amount": 5},
			expectedOk:  false,
			expectedVal: 0.0,
		},
		{
			name:        "Calculated price out of range (too low)",
			numbers:     []float64{40, 0, 40, 100, 90, 1000, 28},
			columnMap:   map[string]int{"sale": 3, "amount": 5},
			expectedOk:  false,
			expectedVal: 0.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			price, ok := extractPriceFromCalculation(tt.numbers, tt.columnMap)
			if ok != tt.expectedOk {
				t.Errorf("extractPriceFromCalculation() ok = %v, expected %v", ok, tt.expectedOk)
			}
			if price != tt.expectedVal {
				t.Errorf("extractPriceFromCalculation() price = %.2f, expected %.2f", price, tt.expectedVal)
			}
		})
	}
}

// 🔧 Phase 2.2 Tests: Merged Row Detection
func TestDetectMergedRows(t *testing.T) {
	tests := []struct {
		name          string
		line          string
		expectedCount int
		expectedFirst string
	}{
		{
			name:          "Single row - no merge",
			line:          "1 Royal Stag 40 0 40 12 90 1080 28",
			expectedCount: 1,
			expectedFirst: "1 Royal Stag 40 0 40 12 90 1080 28",
		},
		{
			name:          "Two merged rows",
			line:          "1 Royal Stag 40 0 40 12 90 1080 28 2 8PM Black 0 0 0 0 90 0 0",
			expectedCount: 2,
			expectedFirst: "1 Royal Stag 40 0 40 12 90 1080 28",
		},
		{
			name:          "Three merged rows",
			line:          "1 Royal Stag 40 0 40 12 90 2 8PM Black 0 0 0 3 Blenders 10 5 15",
			expectedCount: 3,
			expectedFirst: "1 Royal Stag 40 0 40 12 90",
		},
		{
			name:          "No serial numbers - single row",
			line:          "Royal Stag Premium Whisky",
			expectedCount: 1,
			expectedFirst: "Royal Stag Premium Whisky",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := detectMergedRows(tt.line)
			if len(result) != tt.expectedCount {
				t.Errorf("detectMergedRows() returned %d rows, expected %d", len(result), tt.expectedCount)
			}
			if len(result) > 0 && result[0] != tt.expectedFirst {
				t.Errorf("detectMergedRows() first row = %q, expected %q", result[0], tt.expectedFirst)
			}
		})
	}
}

// 🔧 Phase 3.1 Tests: Cross-Field Validation
func TestValidateCrossFields(t *testing.T) {
	tests := []struct {
		name           string
		brand          ocr.ExtractedBrand
		detectedSize   string
		expectValid    bool
		expectWarnings int
		expectCritical int
	}{
		{
			name: "All valid fields",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "90ml",
				Price:          90.0,
				Quantity:       27,
			},
			detectedSize:   "90ml",
			expectValid:    true,
			expectWarnings: 0,
			expectCritical: 0,
		},
		{
			name: "Size mismatch warning",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "180ml",
				Price:          90.0,
				Quantity:       27,
			},
			detectedSize:   "90ml",
			expectValid:    true,
			expectWarnings: 1,
			expectCritical: 0,
		},
		{
			name: "Negative price - critical",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "90ml",
				Price:          -50.0,
				Quantity:       27,
			},
			detectedSize:   "90ml",
			expectValid:    false,
			expectWarnings: 0,
			expectCritical: 1,
		},
		{
			name: "Negative quantity - critical",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "90ml",
				Price:          90.0,
				Quantity:       -5,
			},
			detectedSize:   "90ml",
			expectValid:    false,
			expectWarnings: 0,
			expectCritical: 1,
		},
		{
			name: "Suspiciously high quantity - warning",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "90ml",
				Price:          90.0,
				Quantity:       15000,
			},
			detectedSize:   "90ml",
			expectValid:    true,
			expectWarnings: 1,
			expectCritical: 0,
		},
		{
			name: "Suspiciously high price - warning",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "90ml",
				Price:          25000.0,
				Quantity:       10,
			},
			detectedSize:   "90ml",
			expectValid:    true,
			expectWarnings: 1,
			expectCritical: 0,
		},
		{
			name: "Non-standard size - warning",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "200ml",
				Price:          90.0,
				Quantity:       10,
			},
			detectedSize:   "90ml",
			expectValid:    true,
			expectWarnings: 2, // Size mismatch + non-standard size
			expectCritical: 0,
		},
		{
			name: "Price too low for quantity - warning",
			brand: ocr.ExtractedBrand{
				NormalizedName: "Royal Stag",
				Size:           "90ml",
				Price:          5.0,
				Quantity:       100,
			},
			detectedSize:   "90ml",
			expectValid:    true,
			expectWarnings: 1,
			expectCritical: 0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := validateCrossFields(&tt.brand, tt.detectedSize)
			if result.IsValid != tt.expectValid {
				t.Errorf("validateCrossFields() IsValid = %v, expected %v", result.IsValid, tt.expectValid)
			}
			if result.WarningCount != tt.expectWarnings {
				t.Errorf("validateCrossFields() WarningCount = %d, expected %d", result.WarningCount, tt.expectWarnings)
			}
			if result.CriticalCount != tt.expectCritical {
				t.Errorf("validateCrossFields() CriticalCount = %d, expected %d", result.CriticalCount, tt.expectCritical)
			}
		})
	}
}

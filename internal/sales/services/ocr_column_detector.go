package services

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// ColumnType represents the type of data in a column
type ColumnType string

const (
	ColSerialNo   ColumnType = "sno"
	ColBrand      ColumnType = "brand"
	ColOpening    ColumnType = "opening"
	ColReceipt    ColumnType = "receipt"
	ColTotal      ColumnType = "total"
	ColSale       ColumnType = "sale"
	ColRate       ColumnType = "rate"
	ColAmount     ColumnType = "amount"
	ColClosing    ColumnType = "closing"
)

// ColumnPattern holds patterns for detecting column types
type ColumnPattern struct {
	Type            ColumnType
	HeaderPatterns  []string                   // Regex patterns for headers
	DataValidator   func(string) (bool, float64) // Validates data and returns confidence
	LikelyPositions []int                      // Common positions for this column
	ValueRange      [2]float64                 // Expected min/max values
}

// TableStructureCache caches learned table structures per tenant
type TableStructureCache struct {
	TenantID     string
	InvoiceType  string
	ColumnMap    map[ColumnType]int
	Confidence   float64
	LastUsed     time.Time
	SuccessCount int
}

// SmartColumnDetector provides intelligent column detection
type SmartColumnDetector struct {
	patterns     []ColumnPattern
	cache        map[string]*TableStructureCache // Key: "tenantID:invoiceType"
	debugEnabled bool
}

// NewSmartColumnDetector creates a new intelligent column detector
func NewSmartColumnDetector() *SmartColumnDetector {
	detector := &SmartColumnDetector{
		cache:        make(map[string]*TableStructureCache),
		debugEnabled: true,
	}

	// Define smart patterns for each column type
	detector.patterns = []ColumnPattern{
		{
			Type: ColSerialNo,
			HeaderPatterns: []string{
				`(?i)s\.?\s*no\.?`, `(?i)sr\.?\s*no\.?`, `(?i)serial`, `(?i)^#$`, `(?i)^no\.?$`,
			},
			DataValidator: func(s string) (bool, float64) {
				// Should be sequential integers
				if num, err := strconv.Atoi(strings.TrimSpace(s)); err == nil {
					if num >= 1 && num <= 100 {
						return true, 0.95
					}
				}
				return false, 0
			},
			LikelyPositions: []int{0},
			ValueRange:      [2]float64{1, 100},
		},
		{
			Type: ColBrand,
			HeaderPatterns: []string{
				`(?i)brand`, `(?i)item`, `(?i)product`, `(?i)name`,
			},
			DataValidator: func(s string) (bool, float64) {
				// Should contain text, may have numbers
				s = strings.TrimSpace(s)
				if len(s) < 2 || len(s) > 50 {
					return false, 0
				}
				// Count letters vs numbers
				letterCount := 0
				digitCount := 0
				for _, r := range s {
					if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
						letterCount++
					} else if r >= '0' && r <= '9' {
						digitCount++
					}
				}
				// Should have more letters than numbers (or at least some letters)
				if letterCount > 0 {
					confidence := float64(letterCount) / float64(letterCount+digitCount)
					return true, confidence
				}
				return false, 0
			},
			LikelyPositions: []int{1},
			ValueRange:      [2]float64{0, 0}, // Not numeric
		},
		{
			Type: ColOpening,
			HeaderPatterns: []string{
				`(?i)opening`, `(?i)open`, `(?i)initial`, `(?i)start`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					if num >= 0 && num <= 10000 {
						return true, 0.9
					}
				}
				return false, 0
			},
			LikelyPositions: []int{2},
			ValueRange:      [2]float64{0, 10000},
		},
		{
			Type: ColReceipt,
			HeaderPatterns: []string{
				`(?i)receipt`, `(?i)received`, `(?i)rcpt`, `(?i)purchase`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					if num >= 0 && num <= 10000 {
						return true, 0.9
					}
				}
				return false, 0
			},
			LikelyPositions: []int{3},
			ValueRange:      [2]float64{0, 10000},
		},
		{
			Type: ColTotal,
			HeaderPatterns: []string{
				`(?i)total`, `(?i)sum`, `(?i)stock`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					if num >= 0 && num <= 20000 {
						return true, 0.9
					}
				}
				return false, 0
			},
			LikelyPositions: []int{4},
			ValueRange:      [2]float64{0, 20000},
		},
		{
			Type: ColSale,
			HeaderPatterns: []string{
				`(?i)sale`, `(?i)sold`, `(?i)qty`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					if num >= 0 && num <= 5000 {
						return true, 0.9
					}
				}
				return false, 0
			},
			LikelyPositions: []int{5},
			ValueRange:      [2]float64{0, 5000},
		},
		{
			Type: ColRate,
			HeaderPatterns: []string{
				`(?i)rate`, `(?i)price`, `(?i)mrp`, `(?i)cost`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					// Rate/price typically between 10 and 50000
					if num >= 10 && num <= 50000 {
						// Higher confidence for typical price ranges
						if num >= 50 && num <= 5000 {
							return true, 0.95
						}
						return true, 0.8
					}
				}
				return false, 0
			},
			LikelyPositions: []int{6},
			ValueRange:      [2]float64{10, 50000},
		},
		{
			Type: ColAmount,
			HeaderPatterns: []string{
				`(?i)amount`, `(?i)value`, `(?i)total\s*amount`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					// Amount is typically larger (rate × quantity)
					if num >= 0 && num <= 1000000 {
						return true, 0.9
					}
				}
				return false, 0
			},
			LikelyPositions: []int{7},
			ValueRange:      [2]float64{0, 1000000},
		},
		{
			Type: ColClosing,
			HeaderPatterns: []string{
				`(?i)closing`, `(?i)balance`, `(?i)final`, `(?i)end`,
			},
			DataValidator: func(s string) (bool, float64) {
				if num, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
					if num >= 0 && num <= 10000 {
						return true, 0.9
					}
				}
				return false, 0
			},
			LikelyPositions: []int{8},
			ValueRange:      [2]float64{0, 10000},
		},
	}

	return detector
}

// DetectColumns intelligently detects column types from headers and data
func (d *SmartColumnDetector) DetectColumns(headers []string, dataRows [][]string, tenantID, invoiceType string) map[string]int {
	columnMap := make(map[string]int)

	// Log what we received
	if d.debugEnabled {
		fmt.Printf("\n🧠 [Smart Detection] Analyzing table structure...\n")
		fmt.Printf("   Headers (%d): %v\n", len(headers), headers)
		if len(dataRows) > 0 {
			fmt.Printf("   Sample data rows: %d\n", len(dataRows))
			for i := 0; i < min(3, len(dataRows)); i++ {
				fmt.Printf("   Row %d: %v\n", i+1, dataRows[i])
			}
		}
	}

	// Try cached structure first
	cacheKey := fmt.Sprintf("%s:%s", tenantID, invoiceType)
	if cached, ok := d.cache[cacheKey]; ok && cached.Confidence > 0.8 {
		if d.validateMapping(cached.ColumnMap, dataRows) {
			if d.debugEnabled {
				fmt.Printf("✅ [Smart Detection] Using cached structure (confidence: %.2f)\n", cached.Confidence)
			}
			cached.LastUsed = time.Now()
			cached.SuccessCount++
			return d.convertToStringMap(cached.ColumnMap)
		}
	}

	// Step 1: Try header-based detection
	headerMap := d.detectFromHeaders(headers)

	// Step 2: Validate with data patterns
	if len(dataRows) > 0 {
		dataMap := d.detectFromDataPatterns(dataRows)

		// Step 3: Merge header and data detection
		columnMap = d.mergeDetections(headerMap, dataMap, len(headers))

		// Step 4: Apply relationship validation
		if d.validateRelationships(columnMap, dataRows) {
			confidence := d.calculateConfidence(columnMap, dataRows)

			// Cache successful detection
			if confidence > 0.7 {
				d.cache[cacheKey] = &TableStructureCache{
					TenantID:     tenantID,
					InvoiceType:  invoiceType,
					ColumnMap:    d.convertFromStringMap(columnMap),
					Confidence:   confidence,
					LastUsed:     time.Now(),
					SuccessCount: 1,
				}
			}
		}
	} else {
		columnMap = headerMap
	}

	// Step 5: Fallback to positional hints if needed
	if len(columnMap) < 5 {
		if d.debugEnabled {
			fmt.Println("⚠️  [Smart Detection] Low confidence, using positional fallback")
		}
		columnMap = d.applyPositionalFallback(len(headers), invoiceType)
	}

	if d.debugEnabled {
		fmt.Printf("📊 [Smart Detection] Final column mapping:\n")
		for colType, idx := range columnMap {
			fmt.Printf("   %s -> Column %d\n", colType, idx)
		}
	}

	return columnMap
}

// detectFromHeaders analyzes headers to identify column types
func (d *SmartColumnDetector) detectFromHeaders(headers []string) map[string]int {
	columnMap := make(map[string]int)

	for i, header := range headers {
		headerLower := strings.ToLower(strings.TrimSpace(header))

		for _, pattern := range d.patterns {
			for _, regex := range pattern.HeaderPatterns {
				if matched, _ := regexp.MatchString(regex, headerLower); matched {
					columnMap[string(pattern.Type)] = i
					if d.debugEnabled {
						fmt.Printf("   ✓ Header '%s' matched %s pattern\n", header, pattern.Type)
					}
					break
				}
			}
		}
	}

	return columnMap
}

// detectFromDataPatterns analyzes actual data to identify column types
func (d *SmartColumnDetector) detectFromDataPatterns(dataRows [][]string) map[string]int {
	if len(dataRows) == 0 {
		return make(map[string]int)
	}

	numCols := len(dataRows[0])
	columnScores := make(map[int]map[ColumnType]float64)

	// Initialize scores
	for i := 0; i < numCols; i++ {
		columnScores[i] = make(map[ColumnType]float64)
	}

	// Analyze each column's data
	for colIdx := 0; colIdx < numCols; colIdx++ {
		for _, pattern := range d.patterns {
			totalScore := 0.0
			validCount := 0

			for _, row := range dataRows {
				if colIdx < len(row) {
					if valid, confidence := pattern.DataValidator(row[colIdx]); valid {
						totalScore += confidence
						validCount++
					}
				}
			}

			if validCount > 0 {
				avgScore := totalScore / float64(len(dataRows))
				columnScores[colIdx][pattern.Type] = avgScore
			}
		}
	}

	// Assign columns to best matching type
	columnMap := make(map[string]int)
	usedColumns := make(map[int]bool)

	// Find best matches
	for {
		bestScore := 0.0
		var bestCol int
		var bestType ColumnType

		for colIdx, scores := range columnScores {
			if usedColumns[colIdx] {
				continue
			}
			for colType, score := range scores {
				if _, exists := columnMap[string(colType)]; exists {
					continue
				}
				if score > bestScore {
					bestScore = score
					bestCol = colIdx
					bestType = colType
				}
			}
		}

		if bestScore > 0.5 {
			columnMap[string(bestType)] = bestCol
			usedColumns[bestCol] = true
		} else {
			break
		}
	}

	return columnMap
}

// validateRelationships checks if column relationships make sense
func (d *SmartColumnDetector) validateRelationships(columnMap map[string]int, dataRows [][]string) bool {
	if len(dataRows) < 3 {
		return true // Not enough data to validate
	}

	// Check if we have the required columns
	openingIdx, hasOpening := columnMap["opening"]
	receiptIdx, hasReceipt := columnMap["receipt"]
	totalIdx, hasTotal := columnMap["total"]
	saleIdx, hasSale := columnMap["sale"]
	rateIdx, hasRate := columnMap["rate"]
	amountIdx, hasAmount := columnMap["amount"]
	closingIdx, hasClosing := columnMap["closing"]

	validCount := 0
	totalCount := 0

	for _, row := range dataRows[:min(10, len(dataRows))] {
		// Validate: Opening + Receipt ≈ Total
		if hasOpening && hasReceipt && hasTotal &&
			openingIdx < len(row) && receiptIdx < len(row) && totalIdx < len(row) {
			if opening, e1 := strconv.ParseFloat(row[openingIdx], 64); e1 == nil {
				if receipt, e2 := strconv.ParseFloat(row[receiptIdx], 64); e2 == nil {
					if total, e3 := strconv.ParseFloat(row[totalIdx], 64); e3 == nil {
						expected := opening + receipt
						if math.Abs(expected-total) < expected*0.1 || math.Abs(expected-total) < 5 {
							validCount++
						}
						totalCount++
					}
				}
			}
		}

		// Validate: Sale × Rate ≈ Amount
		if hasSale && hasRate && hasAmount &&
			saleIdx < len(row) && rateIdx < len(row) && amountIdx < len(row) {
			if sale, e1 := strconv.ParseFloat(row[saleIdx], 64); e1 == nil {
				if rate, e2 := strconv.ParseFloat(row[rateIdx], 64); e2 == nil {
					if amount, e3 := strconv.ParseFloat(row[amountIdx], 64); e3 == nil {
						expected := sale * rate
						if math.Abs(expected-amount) < expected*0.1 || math.Abs(expected-amount) < 10 {
							validCount++
						}
						totalCount++
					}
				}
			}
		}

		// Validate: Total - Sale = Closing
		if hasTotal && hasSale && hasClosing &&
			totalIdx < len(row) && saleIdx < len(row) && closingIdx < len(row) {
			if total, e1 := strconv.ParseFloat(row[totalIdx], 64); e1 == nil {
				if sale, e2 := strconv.ParseFloat(row[saleIdx], 64); e2 == nil {
					if closing, e3 := strconv.ParseFloat(row[closingIdx], 64); e3 == nil {
						expected := total - sale
						if math.Abs(expected-closing) < expected*0.1 || math.Abs(expected-closing) < 5 {
							validCount++
						}
						totalCount++
					}
				}
			}
		}
	}

	if totalCount == 0 {
		return true // No relationships to validate
	}

	validRatio := float64(validCount) / float64(totalCount)
	if d.debugEnabled {
		fmt.Printf("   🔍 Relationship validation: %.1f%% valid (%d/%d checks)\n",
			validRatio*100, validCount, totalCount)
	}

	return validRatio > 0.6 // At least 60% of relationships should be valid
}

// mergeDetections combines header and data-based detection
func (d *SmartColumnDetector) mergeDetections(headerMap, dataMap map[string]int, numCols int) map[string]int {
	merged := make(map[string]int)

	// Start with header detection (higher priority)
	for colType, idx := range headerMap {
		merged[colType] = idx
	}

	// Add data detection for missing columns
	for colType, idx := range dataMap {
		if _, exists := merged[colType]; !exists {
			merged[colType] = idx
		}
	}

	return merged
}

// applyPositionalFallback uses common positions for invoice types
func (d *SmartColumnDetector) applyPositionalFallback(numCols int, invoiceType string) map[string]int {
	columnMap := make(map[string]int)

	// For 180ml invoices with 9 columns, use standard structure
	if strings.Contains(strings.ToLower(invoiceType), "180") && numCols >= 9 {
		columnMap["sno"] = 0
		columnMap["brand"] = 1
		columnMap["opening"] = 2
		columnMap["receipt"] = 3
		columnMap["total"] = 4
		columnMap["sale"] = 5
		columnMap["rate"] = 6
		columnMap["amount"] = 7
		columnMap["closing"] = 8

		if d.debugEnabled {
			fmt.Println("   📋 Using 180ml standard format (9 columns)")
		}
	} else if numCols >= 7 {
		// Generic fallback for 7+ columns
		columnMap["sno"] = 0
		columnMap["brand"] = 1
		columnMap["rate"] = numCols - 3
		columnMap["closing"] = numCols - 1

		if d.debugEnabled {
			fmt.Printf("   📋 Using generic fallback (columns: %d)\n", numCols)
		}
	}

	return columnMap
}

// Helper functions
func (d *SmartColumnDetector) calculateConfidence(columnMap map[string]int, dataRows [][]string) float64 {
	// Calculate confidence based on validation results
	if d.validateRelationships(columnMap, dataRows) {
		return 0.9
	}
	return 0.5
}

func (d *SmartColumnDetector) validateMapping(columnMap map[ColumnType]int, dataRows [][]string) bool {
	stringMap := d.convertToStringMap(columnMap)
	return d.validateRelationships(stringMap, dataRows)
}

func (d *SmartColumnDetector) convertToStringMap(typeMap map[ColumnType]int) map[string]int {
	result := make(map[string]int)
	for k, v := range typeMap {
		result[string(k)] = v
	}
	return result
}

func (d *SmartColumnDetector) convertFromStringMap(stringMap map[string]int) map[ColumnType]int {
	result := make(map[ColumnType]int)
	for k, v := range stringMap {
		result[ColumnType(k)] = v
	}
	return result
}
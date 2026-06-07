package services

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/sirupsen/logrus"
)

// TableRowParser handles parsing of line-by-line OCR text into table rows
type TableRowParser struct {
	logger *logrus.Logger
}

// NewTableRowParser creates a new table row parser
func NewTableRowParser(logger *logrus.Logger) *TableRowParser {
	return &TableRowParser{
		logger: logger,
	}
}

// ParsedRow represents a single row extracted from the table
type ParsedRow struct {
	SerialNo     int
	BrandName    string
	Opening      *int
	Receipt      *int
	Total        *int
	Sale         *int
	Rate         *int
	Amount       *int
	Closing      *int
	Numbers      []int // All numbers found in this row
	Confidence   float64
}

// ParseTableRows parses line-by-line OCR text into structured table rows
func (p *TableRowParser) ParseTableRows(rawText string) []ParsedRow {
	lines := strings.Split(rawText, "\n")

	var rows []ParsedRow
	var currentRow *ParsedRow
	var currentBrand strings.Builder
	var orphanNumbers []int // Numbers before first serial number
	collectingRow := false
	headerPassed := false
	firstRowSeen := false

	// Number pattern
	numRegex := regexp.MustCompile(`^\d+$`)

	for i, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Skip header lines - detect by looking for header keywords
		if !headerPassed {
			lineLower := strings.ToLower(line)
			// Detect header as soon as we see ANY header indicator
			if strings.Contains(lineLower, "s.no") ||
				strings.Contains(lineLower, "serial") ||
				strings.Contains(lineLower, "brand") ||
				strings.Contains(lineLower, "opening") ||
				strings.Contains(lineLower, "rate") ||
				strings.Contains(lineLower, "closing") ||
				strings.Contains(lineLower, "amount") {
				headerPassed = true
				p.logger.Infof("Header detected: '%s'", line)
			}
			continue
		}

		// Check if this is a serial number (1-50)
		if numRegex.MatchString(line) {
			num, _ := strconv.Atoi(line)
			if num >= 1 && num <= 50 {
				// Smart serial number detection: only accept as serial if:
				// 1. This is the first row (no currentRow exists), OR
				// 2. This is the expected next serial number AND current row has content
				isSerialNumber := false

				if currentRow == nil {
					// First row - accept any 1-50 as serial
					isSerialNumber = true
					p.logger.Infof("First row: accepting %d as serial number", num)
				} else {
					expectedNext := currentRow.SerialNo + 1

					// Accept if this is the expected next serial number AND current row has AT LEAST a brand name
					// We DON'T require numbers anymore - brand name is enough to move to next row
					if num == expectedNext {
						hasBrand := currentRow.BrandName != ""

						if hasBrand {
							isSerialNumber = true
							p.logger.Infof("Row %d has brand '%s', accepting %d as next serial",
								currentRow.SerialNo, currentRow.BrandName, num)
						} else {
							p.logger.Infof("Rejecting %d as serial - row %d has no brand name yet",
								num, currentRow.SerialNo)
						}
					} else {
						p.logger.Infof("Rejecting %d as serial - expected %d (current: %d)",
							num, expectedNext, currentRow.SerialNo)
					}
				}

				if isSerialNumber {
					// Save previous row if exists
					if currentRow != nil {
						p.finalizeRow(currentRow)
						rows = append(rows, *currentRow)
						p.logger.Debugf("Completed row %d: %s with %d numbers",
							currentRow.SerialNo, currentRow.BrandName, len(currentRow.Numbers))
					}

					// Start new row
					currentRow = &ParsedRow{
						SerialNo: num,
						Numbers:  []int{},
					}

					// If this is the first row and we have orphan numbers, assign them
					if !firstRowSeen && len(orphanNumbers) > 0 {
						currentRow.Numbers = append(currentRow.Numbers, orphanNumbers...)
						p.logger.Debugf("Assigned %d orphan numbers to row 1: %v", len(orphanNumbers), orphanNumbers)
						firstRowSeen = true
					}

					currentBrand.Reset()
					collectingRow = true
					p.logger.Debugf("Started new row: S.No %d (line %d)", num, i)
					continue
				} else {
					// Not a serial number - treat as data number
					if collectingRow && currentRow != nil {
						currentRow.Numbers = append(currentRow.Numbers, num)
						p.logger.Debugf("  Row %d: Added number %d as data (total: %d numbers)",
							currentRow.SerialNo, num, len(currentRow.Numbers))
					}
					continue
				}
			}
		}

		if !collectingRow {
			// Collect orphan numbers (after header, before first serial number)
			if headerPassed && !firstRowSeen && numRegex.MatchString(line) {
				num, _ := strconv.Atoi(line)
				if num > 50 { // Not a serial number
					orphanNumbers = append(orphanNumbers, num)
					p.logger.Debugf("Collected orphan number: %d", num)
				}
			}
			continue
		}

		// Check if this is a number (data)
		if numRegex.MatchString(line) {
			num, _ := strconv.Atoi(line)
			currentRow.Numbers = append(currentRow.Numbers, num)
			p.logger.Debugf("  Row %d: Added number %d (total: %d numbers)",
				currentRow.SerialNo, num, len(currentRow.Numbers))
		} else {
			// This is text, likely brand name
			// BUT: Stop adding to brand name if we've already collected numbers
			// This prevents accumulating column headers or other text after data starts
			if len(currentRow.Numbers) == 0 {
				if currentBrand.Len() > 0 {
					currentBrand.WriteString(" ")
				}
				currentBrand.WriteString(line)
				currentRow.BrandName = currentBrand.String()
				p.logger.Debugf("  Row %d: Added brand text '%s' (total: '%s')",
					currentRow.SerialNo, line, currentRow.BrandName)
			} else {
				p.logger.Debugf("  Row %d: Skipping text '%s' (already have %d numbers, brand name complete)",
					currentRow.SerialNo, line, len(currentRow.Numbers))
			}
		}
	}

	// Save last row
	if currentRow != nil {
		p.finalizeRow(currentRow)
		rows = append(rows, *currentRow)
		p.logger.Debugf("Completed final row %d: %s with %d numbers",
			currentRow.SerialNo, currentRow.BrandName, len(currentRow.Numbers))
	}

	p.logger.Infof("Parsed %d rows from %d lines of text", len(rows), len(lines))
	return rows
}

// finalizeRow assigns numbers to appropriate columns based on value analysis
func (p *TableRowParser) finalizeRow(row *ParsedRow) {
	if len(row.Numbers) == 0 {
		return
	}

	p.logger.Debugf("Finalizing row %d (%s) with numbers: %v",
		row.SerialNo, row.BrandName, row.Numbers)

	// Analyze numbers and categorize them
	// Small numbers (0-500): Stock counts
	// Medium numbers (100-2000): Rates
	// Large numbers (1000+): Amounts

	var stockNums []int
	var rateNums []int
	var amountNums []int

	for _, num := range row.Numbers {
		if num >= 1000 {
			amountNums = append(amountNums, num)
		} else if num >= 100 && num <= 2000 {
			rateNums = append(rateNums, num)
		} else if num >= 0 && num <= 500 {
			stockNums = append(stockNums, num)
		}
	}

	p.logger.Debugf("  Categorized: %d stock, %d rate, %d amount",
		len(stockNums), len(rateNums), len(amountNums))

	// Typical patterns based on number of values:
	// Pattern 1: Opening, Sale, Rate, Amount, Closing (5 numbers)
	// Pattern 2: Opening, Closing (2 numbers)
	// Pattern 3: Opening, Receipt, Sale, Rate, Amount, Closing (6+ numbers)

	if len(row.Numbers) >= 5 {
		// Full data row
		// Try to map: Opening, Sale, Rate, Amount, Closing
		// Stock numbers appear at beginning and end
		// Rate and Amount in middle

		for i, num := range row.Numbers {
			if num >= 1000 {
				// This is Amount
				row.Amount = &num
				p.logger.Debugf("  Amount: %d (position %d)", num, i)
			} else if num >= 100 && num <= 2000 && row.Rate == nil {
				// This is Rate (comes before Amount)
				row.Rate = &num
				p.logger.Debugf("  Rate: %d (position %d)", num, i)
			}
		}

		// Stock numbers: first few are Opening/Sale, last is Closing
		if len(stockNums) > 0 {
			row.Opening = &stockNums[0]
			p.logger.Debugf("  Opening: %d", stockNums[0])

			// Sale is typically the smallest stock number
			if len(stockNums) >= 2 {
				row.Sale = &stockNums[1]
				p.logger.Debugf("  Sale: %d", stockNums[1])
			}

			// Closing is the LAST stock number
			if len(stockNums) >= 3 {
				row.Closing = &stockNums[len(stockNums)-1]
				p.logger.Debugf("  Closing: %d", stockNums[len(stockNums)-1])
			} else if len(stockNums) == 2 && row.Sale != nil {
				// Calculate closing from opening - sale
				closing := *row.Opening - *row.Sale
				row.Closing = &closing
				p.logger.Debugf("  Closing (calculated): %d", closing)
			}
		}

		row.Confidence = 0.9

	} else if len(row.Numbers) >= 2 {
		// Partial data: likely Opening and Closing
		if len(stockNums) >= 2 {
			row.Opening = &stockNums[0]
			row.Closing = &stockNums[len(stockNums)-1]
			p.logger.Debugf("  Opening: %d, Closing: %d (partial row)",
				*row.Opening, *row.Closing)
			row.Confidence = 0.7
		} else if len(stockNums) == 1 {
			row.Opening = &stockNums[0]
			p.logger.Debugf("  Opening only: %d (partial row)", *row.Opening)
			row.Confidence = 0.6
		} else {
			p.logger.Warnf("  Row %d: Has %d numbers but no stock values (0-500)",
				row.SerialNo, len(row.Numbers))
			row.Confidence = 0.4
		}
	} else if len(row.Numbers) == 1 {
		// Single number: likely opening stock
		if len(stockNums) > 0 {
			row.Opening = &stockNums[0]
			p.logger.Debugf("  Opening only: %d", *row.Opening)
			row.Confidence = 0.5
		} else {
			p.logger.Warnf("  Row %d: Single number %d is not a stock value",
				row.SerialNo, row.Numbers[0])
			row.Confidence = 0.3
		}
	}

	// Validate closing stock is reasonable
	if row.Closing != nil && *row.Closing > 500 {
		p.logger.Warnf("  Row %d: Closing %d > 500, likely extracted Amount! Fixing...",
			row.SerialNo, *row.Closing)

		// Try to find the real closing (should be last small number)
		for i := len(row.Numbers) - 1; i >= 0; i-- {
			if row.Numbers[i] < 500 {
				row.Closing = &row.Numbers[i]
				p.logger.Infof("  Fixed closing to: %d", *row.Closing)
				break
			}
		}
	}
}

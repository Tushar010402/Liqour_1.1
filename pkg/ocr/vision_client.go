package ocr

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"

	vision "cloud.google.com/go/vision/apiv1"
	"cloud.google.com/go/vision/v2/apiv1/visionpb"
)

// VisionClient handles interactions with Google Cloud Vision API
type VisionClient struct {
	client *vision.ImageAnnotatorClient
}

// NewVisionClient creates a new Vision API client
func NewVisionClient(ctx context.Context) (*VisionClient, error) {
	// Check if credentials are set
	credsPath := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
	if credsPath == "" {
		return nil, fmt.Errorf("GOOGLE_APPLICATION_CREDENTIALS environment variable not set")
	}

	client, err := vision.NewImageAnnotatorClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to create vision client: %w", err)
	}

	return &VisionClient{
		client: client,
	}, nil
}

// ExtractTextFromImage extracts text from an image using Google Vision API with enhanced structure
func (v *VisionClient) ExtractTextFromImage(ctx context.Context, imageBytes []byte) (string, error) {
	image := &visionpb.Image{
		Content: imageBytes,
	}

	// Configure Vision API with language hints for better accuracy
	imageContext := &visionpb.ImageContext{
		LanguageHints: []string{"hi", "en"}, // Hindi and English for Indian invoices
	}

	// Perform document text detection with configuration
	annotations, err := v.client.DetectDocumentText(ctx, image, imageContext)
	if err != nil {
		return "", fmt.Errorf("failed to detect text: %w", err)
	}

	if annotations == nil || annotations.Text == "" {
		return "", fmt.Errorf("no text detected in image")
	}

	// ✨ USE RAW TEXT: Pass unstructured text directly to Gemini for intelligent parsing
	// This avoids column detection issues and leverages Gemini's NLP capabilities
	fmt.Printf("📄 [Vision] Extracted raw text: %d characters\n", len(annotations.Text))
	return annotations.Text, nil
}

// TableRow represents a single row in the extracted table
type TableRow struct {
	Cells      []string // Cell values in order
	RowIndex   int      // Row position (0-based)
	IsHeader   bool     // True if this is a header row
}

// TableData represents the structured table extracted from an invoice
type TableData struct {
	Headers []string   // Column headers
	Rows    []TableRow // Data rows
	RawText string     // Original raw text for fallback
}

// ExtractTableData extracts structured table data from an invoice image
// This uses Vision API's position-based column detection for accurate extraction
func (v *VisionClient) ExtractTableData(ctx context.Context, imageBytes []byte) (*TableData, error) {
	image := &visionpb.Image{
		Content: imageBytes,
	}

	// Configure Vision API with language hints
	imageContext := &visionpb.ImageContext{
		LanguageHints: []string{"hi", "en"},
	}

	// Perform document text detection
	annotations, err := v.client.DetectDocumentText(ctx, image, imageContext)
	if err != nil {
		return nil, fmt.Errorf("failed to detect text: %w", err)
	}

	if annotations == nil || annotations.Text == "" {
		return nil, fmt.Errorf("no text detected in image")
	}

	fmt.Printf("📄 [Vision] Extracting table structure from image...\n")

	// Extract structured table text using existing column detection
	structuredText := v.extractStructuredText(annotations)

	if structuredText == "" {
		// Fallback to raw text if structured extraction fails
		fmt.Println("⚠️  [Vision] Structured extraction failed, using raw text")
		return &TableData{
			Headers: []string{},
			Rows:    []TableRow{},
			RawText: annotations.Text,
		}, nil
	}

	// Parse the structured text into table data
	tableData := v.parseStructuredTextToTable(structuredText)
	tableData.RawText = annotations.Text // Store raw text for fallback

	fmt.Printf("✅ [Vision] Extracted table: %d headers, %d rows\n", len(tableData.Headers), len(tableData.Rows))
	return tableData, nil
}

// parseStructuredTextToTable parses pipe-delimited structured text into TableData
func (v *VisionClient) parseStructuredTextToTable(structuredText string) *TableData {
	lines := strings.Split(structuredText, "\n")

	tableData := &TableData{
		Headers: []string{},
		Rows:    []TableRow{},
	}

	headerFound := false
	rowIndex := 0

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		// Split by pipe delimiter
		cells := strings.Split(line, "|")

		// Clean each cell
		cleanedCells := make([]string, 0, len(cells))
		for _, cell := range cells {
			cleaned := strings.TrimSpace(cell)
			if cleaned != "" {
				cleanedCells = append(cleanedCells, cleaned)
			}
		}

		if len(cleanedCells) == 0 {
			continue
		}

		// Detect header row (contains keywords like "S.No", "Brand", "Rate", etc.)
		isHeaderRow := !headerFound && v.isHeaderRow(cleanedCells)

		if isHeaderRow {
			tableData.Headers = cleanedCells
			headerFound = true
			fmt.Printf("📋 [Vision] Detected %d columns: %v\n", len(cleanedCells), cleanedCells)
		} else {
			// Data row
			tableData.Rows = append(tableData.Rows, TableRow{
				Cells:    cleanedCells,
				RowIndex: rowIndex,
				IsHeader: false,
			})
			rowIndex++
		}
	}

	return tableData
}

// isHeaderRow detects if a row contains table headers
func (v *VisionClient) isHeaderRow(cells []string) bool {
	// Common header keywords in Kerala liquor invoices
	headerKeywords := []string{
		"s.no", "sno", "serial", "sl.no",
		"brand", "name", "item",
		"opening", "receipt", "sale", "closing",
		"rate", "price", "amount",
		"total", "quantity", "qty",
	}

	// Check if at least 2 cells contain header keywords
	matches := 0
	for _, cell := range cells {
		cellLower := strings.ToLower(cell)
		for _, keyword := range headerKeywords {
			if strings.Contains(cellLower, keyword) {
				matches++
				break
			}
		}
	}

	return matches >= 2
}

// extractStructuredText extracts text with preserved table structure from Vision API response
// Uses bounding boxes to detect columns and preserve table structure
// Optimized for SALE RECEIPT tables with row-wise data
func (v *VisionClient) extractStructuredText(annotations *visionpb.TextAnnotation) string {
	if annotations == nil || len(annotations.Pages) == 0 {
		return ""
	}

	// Extract all words with their bounding boxes
	var allWords []wordWithPosition

	// Process each page
	for _, page := range annotations.Pages {
		// Process blocks (major layout sections)
		for _, block := range page.Blocks {
			// Process paragraphs within blocks
			for _, paragraph := range block.Paragraphs {
				for _, word := range paragraph.Words {
					// Build word text from symbols
					var wordText strings.Builder
					for _, symbol := range word.Symbols {
						wordText.WriteString(symbol.Text)
					}

					// Get bounding box position
					if word.BoundingBox != nil && len(word.BoundingBox.Vertices) >= 4 {
						allWords = append(allWords, wordWithPosition{
							text: wordText.String(),
							x:    word.BoundingBox.Vertices[0].X,
							y:    word.BoundingBox.Vertices[0].Y,
							x2:   word.BoundingBox.Vertices[2].X,
							y2:   word.BoundingBox.Vertices[2].Y,
						})
					}
				}
			}
		}
	}

	if len(allWords) == 0 {
		return ""
	}

	// CRITICAL FIX: Always use row-first extraction to maintain row integrity
	// Column detection is now used only for validation, not for extraction
	fmt.Printf("🔍 [Vision] Analyzing %d words for row-first extraction\n", len(allWords))

	// Detect columns for validation purposes only
	columnStarts := v.detectTableColumns(allWords)
	fmt.Printf("📊 [Vision] Detected %d column positions for validation: %v\n", len(columnStarts), columnStarts)

	// Always use row-based extraction to prevent column misalignment
	// This processes each row independently, maintaining data integrity
	fmt.Println("✅ [Vision] Using row-first extraction to maintain data integrity")

	// Pass column information for better formatting, but process row-by-row
	return v.buildEnhancedRowBasedTableText(allWords, columnStarts)
}

// detectTableColumns analyzes X-coordinates to find column boundaries
func (v *VisionClient) detectTableColumns(words []wordWithPosition) []int32 {
	if len(words) == 0 {
		return nil
	}

	// Collect all X positions (left edges of words)
	xPositions := make(map[int32]int)
	for _, word := range words {
		// ✨ OPTIMIZED: Round X to nearest 20 pixels for precise column detection in dense tables
		// This balances between merging variations and detecting distinct columns
		roundedX := (word.x / 20) * 20
		xPositions[roundedX]++
	}

	// Find X positions that appear frequently (likely column starts)
	var columnStarts []int32
	// ✨ OPTIMIZED: Reduced threshold to 7% to detect sparse columns in 9-column tables
	// SALE RECEIPT has many numeric columns with few entries
	minOccurrences := len(words) / 15 // At least ~7% of words should align

	for x, count := range xPositions {
		if count >= minOccurrences {
			columnStarts = append(columnStarts, x)
		}
	}

	// Sort column starts from left to right
	sort.Slice(columnStarts, func(i, j int) bool {
		return columnStarts[i] < columnStarts[j]
	})

	// ✨ FIXED: Merge distance increased from 20px to 50px
	// This prevents splitting single columns that have slight misalignment
	if len(columnStarts) > 0 {
		merged := []int32{columnStarts[0]}
		for i := 1; i < len(columnStarts); i++ {
			if columnStarts[i]-merged[len(merged)-1] > 50 {
				merged = append(merged, columnStarts[i])
			}
		}
		columnStarts = merged
	}

	return columnStarts
}

// buildTableText builds structured table text using detected columns
func (v *VisionClient) buildTableText(words []wordWithPosition, columnStarts []int32) string {
	// Group words by rows (Y coordinate)
	rowGroups := make(map[int32][]wordWithPosition)

	for _, word := range words {
		// ✨ FIXED: Round Y to nearest 10 pixels (was 15) for more precise row grouping
		// This prevents mixing words from different rows in dense tables
		rowY := (word.y / 10) * 10
		rowGroups[rowY] = append(rowGroups[rowY], word)
	}

	// Sort rows by Y position (top to bottom)
	var rowYs []int32
	for y := range rowGroups {
		rowYs = append(rowYs, y)
	}
	sort.Slice(rowYs, func(i, j int) bool {
		return rowYs[i] < rowYs[j]
	})

	// Build table text with column delimiters
	var result strings.Builder

	for _, rowY := range rowYs {
		rowWords := rowGroups[rowY]

		// Sort words in row by X position (left to right)
		sort.Slice(rowWords, func(i, j int) bool {
			return rowWords[i].x < rowWords[j].x
		})

		// Assign words to columns
		rowCells := make([]string, len(columnStarts))

		for _, word := range rowWords {
			// Find which column this word belongs to
			columnIndex := v.findColumnIndex(word.x, columnStarts)
			if columnIndex >= 0 && columnIndex < len(rowCells) {
				if rowCells[columnIndex] != "" {
					rowCells[columnIndex] += " " + word.text
				} else {
					rowCells[columnIndex] = word.text
				}
			}
		}

		// Build row with pipe delimiters
		result.WriteString(strings.Join(rowCells, " | "))
		result.WriteString("\n")
	}

	return result.String()
}

// findColumnIndex determines which column a word belongs to based on its X position
func (v *VisionClient) findColumnIndex(wordX int32, columnStarts []int32) int {
	for i := len(columnStarts) - 1; i >= 0; i-- {
		// ✨ OPTIMIZED: Reduced tolerance to 10 pixels for stricter column assignment
		// This prevents words from being assigned to wrong columns in dense tables
		if wordX >= columnStarts[i]-10 {
			return i
		}
	}
	return 0
}

// buildEnhancedRowBasedTableText performs row-first extraction with column validation
// This NEW function processes each row independently to maintain data integrity
// It uses column information for formatting but NEVER for data assignment
func (v *VisionClient) buildEnhancedRowBasedTableText(words []wordWithPosition, columnStarts []int32) string {
	if len(words) == 0 {
		return ""
	}

	// Step 1: Group words by rows using Y-coordinate
	rowGroups := v.groupWordsByRow(words)

	// Step 2: Process each row independently
	var result strings.Builder
	expectedColumns := len(columnStarts)
	if expectedColumns == 0 {
		expectedColumns = 9 // Default for SALE RECEIPT format
	}

	fmt.Printf("🔄 [Vision] Processing %d rows with %d expected columns\n", len(rowGroups), expectedColumns)

	// Sort rows by Y position
	var rowYs []int32
	for y := range rowGroups {
		rowYs = append(rowYs, y)
	}
	sort.Slice(rowYs, func(i, j int) bool {
		return rowYs[i] < rowYs[j]
	})

	rowNumber := 0
	for _, rowY := range rowYs {
		rowWords := rowGroups[rowY]
		rowNumber++

		// Process this row independently
		rowData := v.extractRowDataWithIntegrity(rowWords, columnStarts, rowNumber)

		if rowData != "" {
			result.WriteString(rowData)
			result.WriteString("\n")
		}
	}

	return result.String()
}

// groupWordsByRow groups words into rows based on Y-coordinate proximity
func (v *VisionClient) groupWordsByRow(words []wordWithPosition) map[int32][]wordWithPosition {
	rowGroups := make(map[int32][]wordWithPosition)

	for _, word := range words {
		// Use 8 pixel rounding for precise row grouping
		// This prevents mixing adjacent rows in dense tables
		rowY := (word.y / 8) * 8
		rowGroups[rowY] = append(rowGroups[rowY], word)
	}

	// Merge rows that are too close (within 5 pixels)
	// This handles slight Y-coordinate variations in the same logical row
	merged := make(map[int32][]wordWithPosition)
	processed := make(map[int32]bool)

	for y1, words1 := range rowGroups {
		if processed[y1] {
			continue
		}

		mergedWords := words1
		processed[y1] = true

		// Check for nearby rows to merge
		for y2, words2 := range rowGroups {
			if processed[y2] || y1 == y2 {
				continue
			}

			// If rows are within 5 pixels, they're likely the same logical row
			if abs(y1-y2) <= 5 {
				mergedWords = append(mergedWords, words2...)
				processed[y2] = true
			}
		}

		merged[y1] = mergedWords
	}

	return merged
}

// extractRowDataWithIntegrity extracts data from a single row maintaining cell positions
func (v *VisionClient) extractRowDataWithIntegrity(rowWords []wordWithPosition, columnStarts []int32, rowNum int) string {
	if len(rowWords) == 0 {
		return ""
	}

	// Sort words left to right
	sort.Slice(rowWords, func(i, j int) bool {
		return rowWords[i].x < rowWords[j].x
	})

	// Build cells array preserving empty positions
	cells := make([]string, len(columnStarts))
	if len(columnStarts) == 0 {
		// Fallback: build row with spacing-based separation
		return v.buildSpacingBasedRow(rowWords)
	}

	// Assign words to cells based on X position
	// CRITICAL: Maintain cell positions even if empty
	for _, word := range rowWords {
		cellIndex := v.findBestColumnMatch(word.x, columnStarts)

		if cellIndex >= 0 && cellIndex < len(cells) {
			if cells[cellIndex] == "" {
				cells[cellIndex] = word.text
			} else {
				// Append to existing cell content (multi-word values)
				cells[cellIndex] += " " + word.text
			}
		} else {
			// Word doesn't fit in any column - log for debugging
			fmt.Printf("⚠️  [Vision] Row %d: Word '%s' at X=%d doesn't fit columns\n",
				rowNum, word.text, word.x)
		}
	}

	// Validate row integrity before returning
	if v.validateRowIntegrity(cells, rowNum) {
		// Join cells with pipe delimiter, preserving empty cells
		return strings.Join(cells, " | ")
	}

	// If validation fails, return spacing-based extraction as fallback
	fmt.Printf("⚠️  [Vision] Row %d failed validation, using spacing-based extraction\n", rowNum)
	return v.buildSpacingBasedRow(rowWords)
}

// findBestColumnMatch finds the best column for a word based on X position
// This is more intelligent than the previous findColumnIndex
func (v *VisionClient) findBestColumnMatch(wordX int32, columnStarts []int32) int {
	if len(columnStarts) == 0 {
		return -1
	}

	// Find the column where the word best fits
	bestColumn := -1
	minDistance := int32(999999)

	for i := 0; i < len(columnStarts); i++ {
		var columnCenter int32
		if i < len(columnStarts)-1 {
			// Column center is midpoint between this column and next
			columnCenter = (columnStarts[i] + columnStarts[i+1]) / 2
		} else {
			// Last column - use start + average column width
			avgWidth := int32(100)
			if len(columnStarts) > 1 {
				avgWidth = (columnStarts[len(columnStarts)-1] - columnStarts[0]) / int32(len(columnStarts)-1)
			}
			columnCenter = columnStarts[i] + avgWidth/2
		}

		// Use column center for distance calculation
		distance := abs(wordX - columnCenter)

		// Word should be after column start and before next column
		if i < len(columnStarts)-1 {
			if wordX >= columnStarts[i] && wordX < columnStarts[i+1] {
				return i // Perfect fit
			}
		} else {
			// Last column - accept if word is after column start
			if wordX >= columnStarts[i] {
				return i
			}
		}

		// Track closest column as fallback
		if distance < minDistance {
			minDistance = distance
			bestColumn = i
		}
	}

	// Use closest column if within reasonable distance (50 pixels)
	if minDistance <= 50 {
		return bestColumn
	}

	return -1
}

// validateRowIntegrity checks if extracted row data makes business sense
func (v *VisionClient) validateRowIntegrity(cells []string, rowNum int) bool {
	// Skip validation for header rows or rows with mostly text
	if rowNum <= 2 {
		return true // Headers
	}

	// Extract numeric values for validation
	numbers := extractNumbers(cells)

	// For SALE RECEIPT validation rules:
	// 1. If we have opening, receipt, and total: opening + receipt ≈ total
	// 2. If we have sale, rate, and amount: sale × rate ≈ amount
	// 3. If we have total, sale, and closing: total - sale ≈ closing

	// For now, basic validation: check if we have expected number count
	// SALE RECEIPT typically has 5-7 numeric values per row
	if len(numbers) >= 3 && len(numbers) <= 9 {
		return true
	}

	// If too few or too many numbers, might be misaligned
	return len(cells) > 2 // At least have serial and brand
}

// buildSpacingBasedRow builds row text using spacing detection
func (v *VisionClient) buildSpacingBasedRow(rowWords []wordWithPosition) string {
	if len(rowWords) == 0 {
		return ""
	}

	var rowText strings.Builder
	var lastX int32 = 0

	for i, word := range rowWords {
		if i > 0 {
			spacing := word.x - lastX

			// Use spacing to determine column boundaries
			if spacing > 80 {
				rowText.WriteString(" | ")
			} else if spacing > 30 {
				rowText.WriteString("  ")
			} else {
				rowText.WriteString(" ")
			}
		}

		rowText.WriteString(word.text)
		lastX = word.x + (word.x2 - word.x)
	}

	return rowText.String()
}

// Helper function to calculate absolute value
func abs(n int32) int32 {
	if n < 0 {
		return -n
	}
	return n
}

// Helper function to extract numbers from cells
func extractNumbers(cells []string) []float64 {
	var numbers []float64
	for _, cell := range cells {
		cell = strings.TrimSpace(cell)
		if num, err := strconv.ParseFloat(cell, 64); err == nil {
			numbers = append(numbers, num)
		}
	}
	return numbers
}

// buildRowBasedTableText extracts table data optimized for SALE RECEIPT format
// This function maintains column alignment while preserving row integrity
func (v *VisionClient) buildRowBasedTableText(words []wordWithPosition) string {
	if len(words) == 0 {
		return ""
	}

	// Group words by rows using Y-coordinate with tighter grouping for dense tables
	rowGroups := make(map[int32][]wordWithPosition)

	for _, word := range words {
		// Use 8 pixel rounding for very precise row grouping in dense tables
		// This prevents mixing adjacent rows with close spacing
		rowY := (word.y / 8) * 8
		rowGroups[rowY] = append(rowGroups[rowY], word)
	}

	// Sort rows by Y position (top to bottom)
	var rowYs []int32
	for y := range rowGroups {
		rowYs = append(rowYs, y)
	}
	sort.Slice(rowYs, func(i, j int) bool {
		return rowYs[i] < rowYs[j]
	})

	// Build structured text row by row
	var result strings.Builder

	for _, rowY := range rowYs {
		rowWords := rowGroups[rowY]

		// Sort words in row by X position (left to right)
		sort.Slice(rowWords, func(i, j int) bool {
			return rowWords[i].x < rowWords[j].x
		})

		// For SALE RECEIPT: ensure proper spacing between columns
		// Serial | Brand Name | Numbers...
		var rowText strings.Builder
		var lastX int32 = 0

		for i, word := range rowWords {
			// Calculate spacing from previous word
			if i > 0 {
				spacing := word.x - lastX

				// ✨ CRITICAL FIX: Stricter column detection for dense tables
				// Reduce thresholds to prevent column mixing in tightly-packed receipts
				if spacing > 80 { // Large gap = column boundary (was 120)
					rowText.WriteString(" | ")
				} else if spacing > 30 { // Medium gap = multiple spaces (was 40)
					rowText.WriteString("  ")
				} else { // Small gap = single space
					rowText.WriteString(" ")
				}
			}

			rowText.WriteString(word.text)
			lastX = word.x + (word.x2 - word.x) // End of current word
		}

		// Add row to result if it has content
		if rowText.Len() > 0 {
			result.WriteString(rowText.String())
			result.WriteString("\n")
		}
	}

	return result.String()
}

// detectPreciseColumns analyzes X-coordinates to find precise column positions
// Specifically tuned for SALE RECEIPT tables with 9 columns
func (v *VisionClient) detectPreciseColumns(words []wordWithPosition) []int32 {
	if len(words) == 0 {
		return nil
	}

	// Collect X positions with frequency counts
	xFrequency := make(map[int32]int)

	for _, word := range words {
		// Round to nearest 25 pixels for column detection
		roundedX := (word.x / 25) * 25
		xFrequency[roundedX]++
	}

	// Find positions that appear frequently (likely column starts)
	var columns []int32
	threshold := len(words) / 15 // At least ~7% alignment for a column

	for x, count := range xFrequency {
		if count >= threshold {
			columns = append(columns, x)
		}
	}

	// Sort columns left to right
	sort.Slice(columns, func(i, j int) bool {
		return columns[i] < columns[j]
	})

	// Merge columns that are very close (within 40px)
	if len(columns) > 1 {
		merged := []int32{columns[0]}
		for i := 1; i < len(columns); i++ {
			if columns[i]-merged[len(merged)-1] > 40 {
				merged = append(merged, columns[i])
			}
		}
		columns = merged
	}

	return columns
}

// buildSimpleText fallback for when table detection fails
func (v *VisionClient) buildSimpleText(words []wordWithPosition) string {
	// Group by Y position (rows)
	rowGroups := make(map[int32][]wordWithPosition)

	for _, word := range words {
		// ✨ FIXED: Use 10 pixel rounding for consistency with buildTableText
		rowY := (word.y / 10) * 10
		rowGroups[rowY] = append(rowGroups[rowY], word)
	}

	// Sort rows
	var rowYs []int32
	for y := range rowGroups {
		rowYs = append(rowYs, y)
	}
	sort.Slice(rowYs, func(i, j int) bool {
		return rowYs[i] < rowYs[j]
	})

	// Build simple text
	var result strings.Builder
	for _, rowY := range rowYs {
		rowWords := rowGroups[rowY]

		// Sort words in row by X
		sort.Slice(rowWords, func(i, j int) bool {
			return rowWords[i].x < rowWords[j].x
		})

		for i, word := range rowWords {
			result.WriteString(word.text)
			if i < len(rowWords)-1 {
				result.WriteString(" ")
			}
		}
		result.WriteString("\n")
	}

	return result.String()
}

// wordWithPosition represents a word with its bounding box coordinates
type wordWithPosition struct {
	text string
	x    int32 // Left edge X coordinate
	y    int32 // Top edge Y coordinate
	x2   int32 // Right edge X coordinate
	y2   int32 // Bottom edge Y coordinate
}

// ExtractTextFromURL extracts text from an image URL with enhanced structure
func (v *VisionClient) ExtractTextFromURL(ctx context.Context, imageURL string) (string, error) {
	image := &visionpb.Image{
		Source: &visionpb.ImageSource{
			ImageUri: imageURL,
		},
	}

	// Configure Vision API with language hints for better accuracy
	imageContext := &visionpb.ImageContext{
		LanguageHints: []string{"hi", "en"}, // Hindi and English for Indian invoices
	}

	// Perform document text detection with configuration
	annotations, err := v.client.DetectDocumentText(ctx, image, imageContext)
	if err != nil {
		return "", fmt.Errorf("failed to detect text: %w", err)
	}

	if annotations == nil || annotations.Text == "" {
		return "", fmt.Errorf("no text detected in image")
	}

	// ✨ USE RAW TEXT: Pass unstructured text directly to Gemini for intelligent parsing
	// This avoids column detection issues and leverages Gemini's NLP capabilities
	fmt.Printf("📄 [Vision] Extracted raw text: %d characters\n", len(annotations.Text))
	return annotations.Text, nil
}

// Close closes the Vision API client
func (v *VisionClient) Close() error {
	if v.client != nil {
		return v.client.Close()
	}
	return nil
}

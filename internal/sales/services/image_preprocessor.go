package services

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"image/png"
	"math"
	"os"
	"sort"
	"time"

	"github.com/disintegration/imaging"
	"github.com/sirupsen/logrus"
	"golang.org/x/image/font"
	"golang.org/x/image/font/basicfont"
	"golang.org/x/image/math/fixed"
)

// ImagePreprocessor handles preprocessing of receipt images for better OCR accuracy
type ImagePreprocessor struct {
	logger                 *logrus.Logger
	enabled                bool
	fillChar               string
	minCellSize            int
	emptyThreshold         float64
	minLineLength          int
	debugMode              bool
}

// PreprocessorConfig holds configuration for image preprocessing
type PreprocessorConfig struct {
	Enabled        bool    // Enable/disable preprocessing
	FillChar       string  // Character to fill empty cells ("0" or "-")
	MinCellSize    int     // Minimum cell size in pixels (default: 50)
	EmptyThreshold float64 // Threshold for empty cell detection (0.0-1.0, default: 0.15)
	MinLineLength  int     // Minimum line length for table detection (default: 100)
	DebugMode      bool    // Enable debug logging and image saving
}

// DefaultPreprocessorConfig returns default configuration
func DefaultPreprocessorConfig() *PreprocessorConfig {
	return &PreprocessorConfig{
		Enabled:        getEnvBool("ENABLE_IMAGE_PREPROCESSING", true),
		FillChar:       getEnvString("PREPROCESSING_FILL_CHAR", "0"),
		MinCellSize:    getEnvInt("PREPROCESSING_MIN_CELL_SIZE", 50),
		EmptyThreshold: getEnvFloat("PREPROCESSING_EMPTY_THRESHOLD", 0.15),
		MinLineLength:  getEnvInt("PREPROCESSING_MIN_LINE_LENGTH", 100),
		DebugMode:      getEnvBool("PREPROCESSING_DEBUG_MODE", false),
	}
}

// NewImagePreprocessor creates a new image preprocessor
func NewImagePreprocessor(logger *logrus.Logger, config *PreprocessorConfig) *ImagePreprocessor {
	if config == nil {
		config = DefaultPreprocessorConfig()
	}

	logger.Infof("Image Preprocessor initialized: enabled=%v, fillChar=%s, minCellSize=%d, emptyThreshold=%.2f",
		config.Enabled, config.FillChar, config.MinCellSize, config.EmptyThreshold)

	return &ImagePreprocessor{
		logger:         logger,
		enabled:        config.Enabled,
		fillChar:       config.FillChar,
		minCellSize:    config.MinCellSize,
		emptyThreshold: config.EmptyThreshold,
		minLineLength:  config.MinLineLength,
		debugMode:      config.DebugMode,
	}
}

// PreprocessResult holds the result of preprocessing
type PreprocessResult struct {
	ProcessedImageBytes []byte
	ProcessingTime      time.Duration
	CellsFilled         int
	TableDetected       bool
	OriginalSize        image.Point
	ProcessedSize       image.Point
}

// PreprocessImage preprocesses a receipt image to improve OCR accuracy
func (p *ImagePreprocessor) PreprocessImage(imageBytes []byte, imageType string) (*PreprocessResult, error) {
	startTime := time.Now()

	if !p.enabled {
		p.logger.Debug("Image preprocessing is disabled, returning original image")
		return &PreprocessResult{
			ProcessedImageBytes: imageBytes,
			ProcessingTime:      time.Since(startTime),
			CellsFilled:         0,
			TableDetected:       false,
		}, nil
	}

	// Decode image
	img, err := decodeImage(imageBytes, imageType)
	if err != nil {
		return nil, fmt.Errorf("failed to decode image: %w", err)
	}

	originalSize := img.Bounds().Size()
	p.logger.Infof("Preprocessing image: %dx%d", originalSize.X, originalSize.Y)

	// Convert to grayscale for analysis
	grayImgNRGBA := imaging.Grayscale(img)
	// Convert NRGBA to Gray for processing
	grayImg := convertToGray(grayImgNRGBA)

	// Detect table structure
	tableGrid, tableDetected := p.detectTableGrid(grayImg)
	if !tableDetected || len(tableGrid.Cells) == 0 {
		p.logger.Warn("No table structure detected, returning original image")
		return &PreprocessResult{
			ProcessedImageBytes: imageBytes,
			ProcessingTime:      time.Since(startTime),
			CellsFilled:         0,
			TableDetected:       false,
			OriginalSize:        originalSize,
			ProcessedSize:       originalSize,
		}, nil
	}

	p.logger.Infof("Table detected: %d rows × %d cols = %d cells",
		len(tableGrid.Rows)-1, len(tableGrid.Cols)-1, len(tableGrid.Cells))

	// Draw visual grid lines on the image (helps OCR align columns)
	imgWithGrid := p.drawGridLines(img, tableGrid)
	p.logger.Info("Visual grid lines drawn on image")

	// Identify empty cells
	emptyCells := p.identifyEmptyCells(grayImg, tableGrid)
	p.logger.Infof("Found %d empty cells (threshold: %.2f)", len(emptyCells), p.emptyThreshold)

	// Fill empty cells with markers
	processedImg := p.fillEmptyCells(imgWithGrid, emptyCells, p.fillChar)

	// Encode processed image
	var buf bytes.Buffer
	var encodeErr error
	if imageType == "png" {
		encodeErr = png.Encode(&buf, processedImg)
	} else {
		encodeErr = jpeg.Encode(&buf, processedImg, &jpeg.Options{Quality: 95})
	}
	if encodeErr != nil {
		return nil, fmt.Errorf("failed to encode processed image: %w", encodeErr)
	}

	processedBytes := buf.Bytes()
	processingTime := time.Since(startTime)

	// Save debug images if enabled
	if p.debugMode {
		p.saveDebugImages(img, processedImg, tableGrid, emptyCells)
	}

	result := &PreprocessResult{
		ProcessedImageBytes: processedBytes,
		ProcessingTime:      processingTime,
		CellsFilled:         len(emptyCells),
		TableDetected:       tableDetected,
		OriginalSize:        originalSize,
		ProcessedSize:       processedImg.Bounds().Size(),
	}

	p.logger.Infof("Preprocessing complete: %d cells filled in %v", len(emptyCells), processingTime)
	return result, nil
}

// TableGrid represents detected table structure
type TableGrid struct {
	Rows  []int            // Y-coordinates of horizontal lines
	Cols  []int            // X-coordinates of vertical lines
	Cells []image.Rectangle // Cell boundaries
}

// detectTableGrid detects table structure using line detection or text-based detection
func (p *ImagePreprocessor) detectTableGrid(grayImg *image.Gray) (*TableGrid, bool) {
	bounds := grayImg.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	// Try line-based detection first
	horizontalLines := p.detectHorizontalLines(grayImg)
	verticalLines := p.detectVerticalLines(grayImg)

	// If line detection failed, try text-based column detection
	if len(horizontalLines) < 3 || len(verticalLines) < 2 {
		p.logger.Info("Line detection insufficient, trying text-based column detection...")
		return p.detectTableFromTextPositions(grayImg)
	}

	// Add image boundaries if not present
	if horizontalLines[0] > 10 {
		horizontalLines = append([]int{0}, horizontalLines...)
	}
	if horizontalLines[len(horizontalLines)-1] < height-10 {
		horizontalLines = append(horizontalLines, height)
	}

	if verticalLines[0] > 10 {
		verticalLines = append([]int{0}, verticalLines...)
	}
	if verticalLines[len(verticalLines)-1] < width-10 {
		verticalLines = append(verticalLines, width)
	}

	// Generate cell boundaries
	cells := []image.Rectangle{}
	for i := 0; i < len(horizontalLines)-1; i++ {
		for j := 0; j < len(verticalLines)-1; j++ {
			cell := image.Rect(
				verticalLines[j],
				horizontalLines[i],
				verticalLines[j+1],
				horizontalLines[i+1],
			)
			// Only include cells that meet minimum size requirement
			if cell.Dx() >= p.minCellSize && cell.Dy() >= p.minCellSize {
				cells = append(cells, cell)
			}
		}
	}

	grid := &TableGrid{
		Rows:  horizontalLines,
		Cols:  verticalLines,
		Cells: cells,
	}

	return grid, len(cells) > 0
}

// detectTableFromTextPositions detects table structure by analyzing text positions using projection profiles
func (p *ImagePreprocessor) detectTableFromTextPositions(grayImg *image.Gray) (*TableGrid, bool) {
	bounds := grayImg.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	p.logger.Info("Analyzing text positions using projection profiles...")

	// Calculate vertical projection (sum of dark pixels per column)
	verticalProjection := make([]int, width)
	for x := 0; x < width; x++ {
		darkCount := 0
		for y := 0; y < height; y++ {
			pixel := grayImg.GrayAt(x, y).Y
			if pixel < 200 { // Dark pixel (text)
				darkCount++
			}
		}
		verticalProjection[x] = darkCount
	}

	// Calculate horizontal projection (sum of dark pixels per row)
	horizontalProjection := make([]int, height)
	for y := 0; y < height; y++ {
		darkCount := 0
		for x := 0; x < width; x++ {
			pixel := grayImg.GrayAt(x, y).Y
			if pixel < 200 { // Dark pixel (text)
				darkCount++
			}
		}
		horizontalProjection[y] = darkCount
	}

	// Find column boundaries (valleys in vertical projection)
	// Use more lenient parameters: smaller gap width (8px) and higher threshold (100)
	verticalLines := p.findProjectionValleys(verticalProjection, width, 8, 100)
	p.logger.Infof("Found %d column boundaries from projection analysis", len(verticalLines))

	// Find row boundaries (valleys in horizontal projection)
	// Use more lenient parameters: smaller gap width (3px) and higher threshold (30)
	horizontalLines := p.findProjectionValleys(horizontalProjection, height, 3, 30)
	p.logger.Infof("Found %d row boundaries from projection analysis", len(horizontalLines))

	// If insufficient columns found, try fallback: divide into equal columns
	if len(verticalLines) < 2 {
		p.logger.Info("Insufficient columns from projection, using equal-width fallback")
		// Stock receipts typically have 5-7 columns (S.No, Brand, Size, Opening, Receipt, Total, Sale, Rate, Amount, Closing)
		// Let's create 6 equal-width columns
		numColumns := 6
		colWidth := width / numColumns
		verticalLines = make([]int, numColumns+1)
		for i := 0; i <= numColumns; i++ {
			verticalLines[i] = i * colWidth
		}
		p.logger.Infof("Created %d equal-width columns (width=%dpx each)", numColumns, colWidth)
	}

	// If insufficient rows found, create evenly spaced rows
	if len(horizontalLines) < 3 {
		p.logger.Info("Insufficient rows from projection, using equal-height fallback")
		// Assume ~25 rows for a typical stock list
		numRows := 25
		rowHeight := height / numRows
		horizontalLines = make([]int, numRows+1)
		for i := 0; i <= numRows; i++ {
			horizontalLines[i] = i * rowHeight
		}
		p.logger.Infof("Created %d equal-height rows (height=%dpx each)", numRows, rowHeight)
	}

	// Final check
	if len(verticalLines) < 2 || len(horizontalLines) < 3 {
		p.logger.Warn("Insufficient text-based structure detected even after fallback")
		return nil, false
	}

	// Add image boundaries
	if verticalLines[0] > 10 {
		verticalLines = append([]int{0}, verticalLines...)
	}
	if verticalLines[len(verticalLines)-1] < width-10 {
		verticalLines = append(verticalLines, width)
	}

	if horizontalLines[0] > 10 {
		horizontalLines = append([]int{0}, horizontalLines...)
	}
	if horizontalLines[len(horizontalLines)-1] < height-10 {
		horizontalLines = append(horizontalLines, height)
	}

	// Generate cell boundaries
	cells := []image.Rectangle{}
	for i := 0; i < len(horizontalLines)-1; i++ {
		for j := 0; j < len(verticalLines)-1; j++ {
			cell := image.Rect(
				verticalLines[j],
				horizontalLines[i],
				verticalLines[j+1],
				horizontalLines[i+1],
			)
			// Only include cells that meet minimum size requirement
			if cell.Dx() >= p.minCellSize && cell.Dy() >= 20 { // Relaxed height for text rows
				cells = append(cells, cell)
			}
		}
	}

	grid := &TableGrid{
		Rows:  horizontalLines,
		Cols:  verticalLines,
		Cells: cells,
	}

	p.logger.Infof("Text-based detection: %d columns × %d rows = %d cells",
		len(verticalLines)-1, len(horizontalLines)-1, len(cells))

	return grid, len(cells) > 0
}

// findProjectionValleys finds valleys (gaps) in projection profile
func (p *ImagePreprocessor) findProjectionValleys(projection []int, length int, minGapWidth int, maxThreshold int) []int {
	valleys := []int{}

	// Calculate average projection value
	sum := 0
	for _, v := range projection {
		sum += v
	}
	avgProjection := sum / length
	threshold := avgProjection / 3 // Valleys are regions with <33% of average (more lenient)

	if threshold > maxThreshold {
		threshold = maxThreshold
	}

	p.logger.Debugf("Projection analysis: avgProjection=%d, threshold=%d, maxThreshold=%d", avgProjection, threshold, maxThreshold)

	// Find valleys (consecutive low values)
	inValley := false
	valleyStart := 0

	for i := 0; i < length; i++ {
		if projection[i] < threshold {
			if !inValley {
				// Starting a new valley
				valleyStart = i
				inValley = true
			}
		} else {
			if inValley {
				// Ending valley
				valleyWidth := i - valleyStart
				if valleyWidth >= minGapWidth {
					// Mark middle of valley as boundary
					valleyMid := valleyStart + valleyWidth/2
					valleys = append(valleys, valleyMid)
				}
				inValley = false
			}
		}
	}

	// Merge nearby valleys
	mergedValleys := mergeSimilarValues(valleys, minGapWidth*2)
	sort.Ints(mergedValleys)

	return mergedValleys
}

// detectHorizontalLines detects horizontal table lines
func (p *ImagePreprocessor) detectHorizontalLines(grayImg *image.Gray) []int {
	bounds := grayImg.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	// Scan each row and count dark pixels
	rowScores := make([]int, height)
	for y := 0; y < height; y++ {
		darkCount := 0
		for x := 0; x < width; x++ {
			pixel := grayImg.GrayAt(x, y).Y
			if pixel < 200 { // Dark pixel threshold
				darkCount++
			}
		}
		rowScores[y] = darkCount
	}

	// Find rows with high dark pixel density (likely lines)
	threshold := int(float64(width) * 0.5) // At least 50% dark pixels
	lines := []int{}

	for y := 5; y < height-5; y++ {
		if rowScores[y] > threshold {
			// Check if this is a local maximum
			isLocalMax := true
			for dy := -3; dy <= 3; dy++ {
				if dy != 0 && y+dy >= 0 && y+dy < height && rowScores[y+dy] > rowScores[y] {
					isLocalMax = false
					break
				}
			}
			if isLocalMax {
				lines = append(lines, y)
			}
		}
	}

	// Merge nearby lines (within 10 pixels)
	mergedLines := mergeSimilarValues(lines, 10)

	sort.Ints(mergedLines)
	return mergedLines
}

// detectVerticalLines detects vertical table lines
func (p *ImagePreprocessor) detectVerticalLines(grayImg *image.Gray) []int {
	bounds := grayImg.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	// Scan each column and count dark pixels
	colScores := make([]int, width)
	for x := 0; x < width; x++ {
		darkCount := 0
		for y := 0; y < height; y++ {
			pixel := grayImg.GrayAt(x, y).Y
			if pixel < 200 { // Dark pixel threshold
				darkCount++
			}
		}
		colScores[x] = darkCount
	}

	// Find columns with high dark pixel density (likely lines)
	threshold := int(float64(height) * 0.3) // At least 30% dark pixels
	lines := []int{}

	for x := 5; x < width-5; x++ {
		if colScores[x] > threshold {
			// Check if this is a local maximum
			isLocalMax := true
			for dx := -3; dx <= 3; dx++ {
				if dx != 0 && x+dx >= 0 && x+dx < width && colScores[x+dx] > colScores[x] {
					isLocalMax = false
					break
				}
			}
			if isLocalMax {
				lines = append(lines, x)
			}
		}
	}

	// Merge nearby lines (within 15 pixels)
	mergedLines := mergeSimilarValues(lines, 15)

	sort.Ints(mergedLines)
	return mergedLines
}

// identifyEmptyCells identifies cells that appear empty based on pixel density
func (p *ImagePreprocessor) identifyEmptyCells(grayImg *image.Gray, grid *TableGrid) []image.Rectangle {
	emptyCells := []image.Rectangle{}

	for _, cell := range grid.Cells {
		if p.isCellEmpty(grayImg, cell) {
			emptyCells = append(emptyCells, cell)
		}
	}

	return emptyCells
}

// isCellEmpty checks if a cell is empty based on pixel density
func (p *ImagePreprocessor) isCellEmpty(grayImg *image.Gray, cell image.Rectangle) bool {
	// Add padding to avoid borders
	padding := 5
	innerCell := cell.Inset(padding)
	if innerCell.Dx() <= 0 || innerCell.Dy() <= 0 {
		return false
	}

	totalPixels := innerCell.Dx() * innerCell.Dy()
	darkPixelCount := 0

	// Count dark pixels in cell
	for y := innerCell.Min.Y; y < innerCell.Max.Y; y++ {
		for x := innerCell.Min.X; x < innerCell.Max.X; x++ {
			pixel := grayImg.GrayAt(x, y).Y
			if pixel < 200 { // Dark pixel threshold
				darkPixelCount++
			}
		}
	}

	pixelDensity := float64(darkPixelCount) / float64(totalPixels)
	return pixelDensity < p.emptyThreshold
}

// drawGridLines draws visual grid lines on the image at detected boundaries
func (p *ImagePreprocessor) drawGridLines(img image.Image, grid *TableGrid) image.Image {
	// Create a mutable copy of the image
	dst := imaging.Clone(img)
	rgba := image.NewRGBA(dst.Bounds())
	draw.Draw(rgba, rgba.Bounds(), dst, image.Point{}, draw.Src)

	// Draw horizontal lines
	lineColor := color.RGBA{128, 128, 128, 255} // Gray color for subtle lines
	lineThickness := 2

	for _, y := range grid.Rows {
		for x := 0; x < rgba.Bounds().Dx(); x++ {
			for dy := -lineThickness / 2; dy <= lineThickness/2; dy++ {
				if y+dy >= 0 && y+dy < rgba.Bounds().Dy() {
					rgba.Set(x, y+dy, lineColor)
				}
			}
		}
	}

	// Draw vertical lines
	for _, x := range grid.Cols {
		for y := 0; y < rgba.Bounds().Dy(); y++ {
			for dx := -lineThickness / 2; dx <= lineThickness/2; dx++ {
				if x+dx >= 0 && x+dx < rgba.Bounds().Dx() {
					rgba.Set(x+dx, y, lineColor)
				}
			}
		}
	}

	p.logger.Infof("Drew %d horizontal and %d vertical grid lines", len(grid.Rows), len(grid.Cols))
	return rgba
}

// fillEmptyCells fills empty cells with text markers
func (p *ImagePreprocessor) fillEmptyCells(img image.Image, emptyCells []image.Rectangle, fillChar string) image.Image {
	// Create a mutable copy of the image
	dst := imaging.Clone(img)
	rgba := image.NewRGBA(dst.Bounds())
	draw.Draw(rgba, rgba.Bounds(), dst, image.Point{}, draw.Src)

	// Fill each empty cell
	for _, cell := range emptyCells {
		p.drawTextInCell(rgba, cell, fillChar)
	}

	return rgba
}

// drawTextInCell draws text centered in a cell
func (p *ImagePreprocessor) drawTextInCell(img *image.RGBA, cell image.Rectangle, text string) {
	// Calculate center position
	centerX := cell.Min.X + cell.Dx()/2
	centerY := cell.Min.Y + cell.Dy()/2

	// Use basic font (7x13 pixels)
	face := basicfont.Face7x13

	// Measure text size
	drawer := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(color.Black),
		Face: face,
	}

	textWidth := drawer.MeasureString(text).Round()
	textHeight := face.Metrics().Height.Round()

	// Calculate text position (centered)
	x := centerX - textWidth/2
	y := centerY + textHeight/2

	// Draw text
	drawer.Dot = fixed.P(x, y)
	drawer.DrawString(text)

	if p.debugMode {
		p.logger.Debugf("Drew '%s' at cell (%d,%d) - (%d,%d), center: (%d,%d)",
			text, cell.Min.X, cell.Min.Y, cell.Max.X, cell.Max.Y, centerX, centerY)
	}
}

// saveDebugImages saves debug images for troubleshooting
func (p *ImagePreprocessor) saveDebugImages(original, processed image.Image, grid *TableGrid, emptyCells []image.Rectangle) {
	timestamp := time.Now().Unix()

	// Save original
	p.saveImage(original, fmt.Sprintf("/tmp/preprocess_original_%d.jpg", timestamp))

	// Save processed
	p.saveImage(processed, fmt.Sprintf("/tmp/preprocess_processed_%d.jpg", timestamp))

	// Create and save grid visualization
	gridViz := p.visualizeGrid(original, grid, emptyCells)
	p.saveImage(gridViz, fmt.Sprintf("/tmp/preprocess_grid_%d.jpg", timestamp))

	p.logger.Infof("Debug images saved to /tmp/preprocess_*_%d.jpg", timestamp)
}

// visualizeGrid creates a visualization of detected table grid
func (p *ImagePreprocessor) visualizeGrid(img image.Image, grid *TableGrid, emptyCells []image.Rectangle) image.Image {
	// Create a copy for visualization
	dst := imaging.Clone(img)
	rgba := image.NewRGBA(dst.Bounds())
	draw.Draw(rgba, rgba.Bounds(), dst, image.Point{}, draw.Src)

	// Draw horizontal lines in red
	red := color.RGBA{255, 0, 0, 255}
	for _, y := range grid.Rows {
		for x := 0; x < rgba.Bounds().Dx(); x++ {
			for dy := -1; dy <= 1; dy++ {
				if y+dy >= 0 && y+dy < rgba.Bounds().Dy() {
					rgba.Set(x, y+dy, red)
				}
			}
		}
	}

	// Draw vertical lines in blue
	blue := color.RGBA{0, 0, 255, 255}
	for _, x := range grid.Cols {
		for y := 0; y < rgba.Bounds().Dy(); y++ {
			for dx := -1; dx <= 1; dx++ {
				if x+dx >= 0 && x+dx < rgba.Bounds().Dx() {
					rgba.Set(x+dx, y, blue)
				}
			}
		}
	}

	// Highlight empty cells in green
	green := color.RGBA{0, 255, 0, 128}
	for _, cell := range emptyCells {
		// Draw a semi-transparent overlay
		for y := cell.Min.Y; y < cell.Max.Y; y++ {
			for x := cell.Min.X; x < cell.Max.X; x++ {
				if (x-cell.Min.X) < 3 || (cell.Max.X-x) < 3 ||
					(y-cell.Min.Y) < 3 || (cell.Max.Y-y) < 3 {
					rgba.Set(x, y, green)
				}
			}
		}
	}

	return rgba
}

// saveImage saves an image to disk
func (p *ImagePreprocessor) saveImage(img image.Image, filename string) {
	f, err := os.Create(filename)
	if err != nil {
		p.logger.Errorf("Failed to create debug image file: %v", err)
		return
	}
	defer f.Close()

	if err := jpeg.Encode(f, img, &jpeg.Options{Quality: 95}); err != nil {
		p.logger.Errorf("Failed to encode debug image: %v", err)
	}
}

// Helper functions

// decodeImage decodes image bytes into an Image
func decodeImage(imageBytes []byte, imageType string) (image.Image, error) {
	reader := bytes.NewReader(imageBytes)

	if imageType == "png" {
		return png.Decode(reader)
	}
	return jpeg.Decode(reader)
}

// mergeSimilarValues merges values that are within threshold of each other
func mergeSimilarValues(values []int, threshold int) []int {
	if len(values) == 0 {
		return values
	}

	sort.Ints(values)
	merged := []int{values[0]}

	for i := 1; i < len(values); i++ {
		if values[i]-merged[len(merged)-1] > threshold {
			merged = append(merged, values[i])
		} else {
			// Average the similar values
			merged[len(merged)-1] = (merged[len(merged)-1] + values[i]) / 2
		}
	}

	return merged
}

// getEnvBool gets a boolean environment variable with default
func getEnvBool(key string, defaultValue bool) bool {
	val := os.Getenv(key)
	if val == "" {
		return defaultValue
	}
	return val == "true" || val == "1" || val == "yes"
}

// getEnvString gets a string environment variable with default
func getEnvString(key string, defaultValue string) string {
	val := os.Getenv(key)
	if val == "" {
		return defaultValue
	}
	return val
}

// getEnvInt gets an integer environment variable with default
func getEnvInt(key string, defaultValue int) int {
	val := os.Getenv(key)
	if val == "" {
		return defaultValue
	}
	var result int
	if _, err := fmt.Sscanf(val, "%d", &result); err != nil {
		return defaultValue
	}
	return result
}

// getEnvFloat gets a float environment variable with default
func getEnvFloat(key string, defaultValue float64) float64 {
	val := os.Getenv(key)
	if val == "" {
		return defaultValue
	}
	var result float64
	if _, err := fmt.Sscanf(val, "%f", &result); err != nil {
		return defaultValue
	}
	return result
}

// CalculateImageQuality calculates image quality metrics
func CalculateImageQuality(img image.Image) map[string]float64 {
	bounds := img.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	// Convert to grayscale
	grayImgNRGBA := imaging.Grayscale(img)
	grayImg := convertToGray(grayImgNRGBA)

	// Calculate sharpness (variance of Laplacian)
	sharpness := calculateSharpness(grayImg)

	// Calculate contrast
	contrast := calculateContrast(grayImg)

	// Calculate brightness
	brightness := calculateBrightness(grayImg)

	return map[string]float64{
		"width":      float64(width),
		"height":     float64(height),
		"sharpness":  sharpness,
		"contrast":   contrast,
		"brightness": brightness,
	}
}

// calculateSharpness calculates image sharpness using Laplacian variance
func calculateSharpness(img *image.Gray) float64 {
	bounds := img.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	var sum, sumSq float64
	count := 0

	// Apply Laplacian operator
	for y := 1; y < height-1; y++ {
		for x := 1; x < width-1; x++ {
			center := float64(img.GrayAt(x, y).Y)
			neighbors := float64(img.GrayAt(x-1, y).Y) +
				float64(img.GrayAt(x+1, y).Y) +
				float64(img.GrayAt(x, y-1).Y) +
				float64(img.GrayAt(x, y+1).Y)

			laplacian := math.Abs(4*center - neighbors)
			sum += laplacian
			sumSq += laplacian * laplacian
			count++
		}
	}

	mean := sum / float64(count)
	variance := (sumSq / float64(count)) - (mean * mean)

	return variance
}

// calculateContrast calculates RMS contrast
func calculateContrast(img *image.Gray) float64 {
	bounds := img.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	var sum float64
	count := width * height

	// Calculate mean
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			sum += float64(img.GrayAt(x, y).Y)
		}
	}
	mean := sum / float64(count)

	// Calculate RMS contrast
	var sumSqDiff float64
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			diff := float64(img.GrayAt(x, y).Y) - mean
			sumSqDiff += diff * diff
		}
	}

	return math.Sqrt(sumSqDiff / float64(count))
}

// calculateBrightness calculates average brightness
func calculateBrightness(img *image.Gray) float64 {
	bounds := img.Bounds()
	width, height := bounds.Dx(), bounds.Dy()

	var sum float64
	count := width * height

	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			sum += float64(img.GrayAt(x, y).Y)
		}
	}

	return sum / float64(count)
}

// convertToGray converts any image to *image.Gray
func convertToGray(img image.Image) *image.Gray {
	bounds := img.Bounds()
	grayImg := image.NewGray(bounds)

	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			grayImg.Set(x, y, img.At(x, y))
		}
	}

	return grayImg
}

package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// TrainingImageService handles training image operations
type TrainingImageService struct {
	db *database.DB
}

// NewTrainingImageService creates a new training image service
func NewTrainingImageService(db *database.DB) *TrainingImageService {
	return &TrainingImageService{
		db: db,
	}
}

// dailySalesRecordRow represents a row from daily_sales_records query
type dailySalesRecordRow struct {
	ID         string    `gorm:"column:id"`
	RecordDate time.Time `gorm:"column:record_date"`
	ShopID     string    `gorm:"column:shop_id"`
	ShopName   string    `gorm:"column:shop_name"`
	ImageURLs  string    `gorm:"column:image_urls"`
}

// dailySalesItemRow represents a row from daily_sales_items query
type dailySalesItemRow struct {
	ID           string  `gorm:"column:id"`
	ProductID    string  `gorm:"column:product_id"`
	BrandName    string  `gorm:"column:brand_name"`
	Size         string  `gorm:"column:size"`
	OpeningStock int     `gorm:"column:opening_stock"`
	Quantity     int     `gorm:"column:quantity"`
	UnitPrice    float64 `gorm:"column:unit_price"`
	TotalAmount  float64 `gorm:"column:total_amount"`
	ClosingStock int     `gorm:"column:closing_stock"`
}

// GetTrainingImagesWithSales fetches all training images with their linked sale entries
func (s *TrainingImageService) GetTrainingImagesWithSales(ctx context.Context, tenantID string) (*models.TrainingImageListResponse, error) {
	// Get list of all image files from the uploads directory
	// Try multiple paths to handle both Docker container and local development
	imageDirs := []string{
		"./uploads/daily_sales",                    // Docker container path (relative to /root/)
		"/var/www/liquorpro/uploads/daily_sales",   // Host machine path
		"/root/uploads/daily_sales",                // Absolute Docker path
	}

	var files []os.DirEntry
	var imageDir string
	var err error

	for _, dir := range imageDirs {
		files, err = os.ReadDir(dir)
		if err == nil {
			imageDir = dir
			break
		}
	}

	if files == nil {
		return nil, fmt.Errorf("could not find uploads directory in any of: %v", imageDirs)
	}

	_ = imageDir // Suppress unused warning

	var images []models.TrainingImageData
	withSales := 0
	withoutSales := 0

	for _, file := range files {
		if file.IsDir() {
			continue
		}

		filename := file.Name()
		ext := strings.ToLower(filepath.Ext(filename))
		if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".webp" {
			continue
		}

		imageData, err := s.GetImageSaleData(ctx, filename, tenantID)
		if err != nil {
			// If error, still include the image but mark as no linked sale
			images = append(images, models.TrainingImageData{
				ImageURL:      "/uploads/daily_sales/" + filename,
				ImageFilename: filename,
				HasLinkedSale: false,
			})
			withoutSales++
			continue
		}

		images = append(images, *imageData)
		if imageData.HasLinkedSale {
			withSales++
		} else {
			withoutSales++
		}
	}

	return &models.TrainingImageListResponse{
		Images:       images,
		TotalImages:  len(images),
		WithSales:    withSales,
		WithoutSales: withoutSales,
	}, nil
}

// GetImageSaleData fetches sale data linked to a specific image
func (s *TrainingImageService) GetImageSaleData(ctx context.Context, imageFilename string, tenantID string) (*models.TrainingImageData, error) {
	imageData := &models.TrainingImageData{
		ImageURL:      "/uploads/daily_sales/" + imageFilename,
		ImageFilename: imageFilename,
		HasLinkedSale: false,
	}

	// Find daily_sales_record that contains this image
	// image_urls is stored as JSON array text like ["/uploads/daily_sales/filename.jpg"]
	// or with escapes like ["\/uploads\/daily_sales\/filename.jpg"]
	// We search for the filename within the JSON array
	var record dailySalesRecordRow
	query := `
		SELECT
			dsr.id,
			dsr.record_date,
			dsr.shop_id::text as shop_id,
			COALESCE(s.name, '') as shop_name,
			dsr.image_urls
		FROM daily_sales_records dsr
		LEFT JOIN shops s ON s.id = dsr.shop_id
		WHERE dsr.image_urls IS NOT NULL
		AND dsr.image_urls != ''
		AND dsr.image_urls != '[]'
		AND dsr.deleted_at IS NULL
		AND (
			dsr.image_urls LIKE $1
			OR dsr.image_urls LIKE $2
		)
	`

	// Use wildcard search for the image filename in the JSON array
	// Search for both the filename and the full path pattern
	searchPattern1 := "%" + imageFilename + "%"
	// Also try with the full path in case it's stored differently
	searchPattern2 := "%/uploads/daily_sales/" + imageFilename + "%"

	// Add tenant filter if provided
	if tenantID != "" {
		query += " AND dsr.tenant_id = $3 LIMIT 1"
		if err := s.db.Raw(query, searchPattern1, searchPattern2, tenantID).Scan(&record).Error; err != nil {
			return imageData, nil // Not found is not an error, just no linked sale
		}
	} else {
		query += " LIMIT 1"
		if err := s.db.Raw(query, searchPattern1, searchPattern2).Scan(&record).Error; err != nil {
			return imageData, nil // Not found is not an error, just no linked sale
		}
	}

	// Check if we found a record
	if record.ID == "" {
		return imageData, nil
	}

	imageData.RecordID = record.ID
	imageData.RecordDate = record.RecordDate
	imageData.ShopID = record.ShopID
	imageData.ShopName = record.ShopName
	imageData.HasLinkedSale = true

	// Get the items for this record with product details
	var items []dailySalesItemRow
	itemQuery := `
		SELECT
			dsi.id,
			dsi.product_id::text as product_id,
			COALESCE(p.name, '') as brand_name,
			COALESCE(p.size, '') as size,
			COALESCE(dsi.opening_stock, 0) as opening_stock,
			dsi.quantity,
			dsi.unit_price,
			dsi.total_amount,
			COALESCE(dsi.closing_stock, 0) as closing_stock
		FROM daily_sales_items dsi
		LEFT JOIN products p ON p.id = dsi.product_id
		WHERE dsi.daily_sales_record_id = $1
		AND dsi.deleted_at IS NULL
		ORDER BY p.name, p.size
	`

	if err := s.db.Raw(itemQuery, record.ID).Scan(&items).Error; err != nil {
		return imageData, err
	}

	// Convert to response format
	for _, item := range items {
		imageData.Items = append(imageData.Items, models.SaleItemData{
			ProductID:    item.ProductID,
			BrandName:    item.BrandName,
			Size:         item.Size,
			OpeningStock: item.OpeningStock,
			SaleQuantity: item.Quantity,
			Rate:         item.UnitPrice,
			Amount:       item.TotalAmount,
			ClosingStock: item.ClosingStock,
		})
	}

	imageData.TotalItems = len(imageData.Items)

	return imageData, nil
}

// ExportTrainingData exports all images with sale data as JSONL format
func (s *TrainingImageService) ExportTrainingData(ctx context.Context, tenantID string) (string, error) {
	response, err := s.GetTrainingImagesWithSales(ctx, tenantID)
	if err != nil {
		return "", err
	}

	var output []string
	for _, img := range response.Images {
		if !img.HasLinkedSale {
			continue
		}

		// Convert items to ground truth format
		groundTruth := make([]models.GroundTruthItem, len(img.Items))
		for i, item := range img.Items {
			groundTruth[i] = models.GroundTruthItem{
				Brand:   item.BrandName,
				Size:    item.Size,
				Opening: item.OpeningStock,
				Sale:    item.SaleQuantity,
				Rate:    item.Rate,
				Amount:  item.Amount,
				Closing: item.ClosingStock,
			}
		}

		exportData := models.TrainingExportData{
			Image:       img.ImageFilename,
			GroundTruth: groundTruth,
			Metadata: models.TrainingExportMetadata{
				Date:   img.RecordDate.Format("2006-01-02"),
				Shop:   img.ShopName,
				ShopID: img.ShopID,
			},
		}

		jsonLine, err := json.Marshal(exportData)
		if err != nil {
			continue
		}
		output = append(output, string(jsonLine))
	}

	return strings.Join(output, "\n"), nil
}

// GetDB returns the database connection
func (s *TrainingImageService) GetDB() *database.DB {
	return s.db
}

// GetRecordsWithImages returns all daily_sales_records that have images attached (for debugging)
func (s *TrainingImageService) GetRecordsWithImages(ctx context.Context) ([]map[string]interface{}, error) {
	var results []struct {
		ID         string    `gorm:"column:id"`
		RecordDate time.Time `gorm:"column:record_date"`
		ImageURLs  string    `gorm:"column:image_urls"`
		ShopName   string    `gorm:"column:shop_name"`
		ItemCount  int       `gorm:"column:item_count"`
	}

	query := `
		SELECT
			dsr.id,
			dsr.record_date,
			dsr.image_urls,
			COALESCE(s.name, '') as shop_name,
			(SELECT COUNT(*) FROM daily_sales_items WHERE daily_sales_record_id = dsr.id AND deleted_at IS NULL) as item_count
		FROM daily_sales_records dsr
		LEFT JOIN shops s ON s.id = dsr.shop_id
		WHERE dsr.image_urls IS NOT NULL
		AND dsr.image_urls != ''
		AND dsr.image_urls != '[]'
		AND dsr.deleted_at IS NULL
		ORDER BY dsr.created_at DESC
		LIMIT 50
	`

	if err := s.db.Raw(query).Scan(&results).Error; err != nil {
		return nil, err
	}

	var output []map[string]interface{}
	for _, r := range results {
		// Parse image_urls JSON to show individual filenames
		var urls []string
		if err := json.Unmarshal([]byte(r.ImageURLs), &urls); err == nil {
			// Extract just filenames for easier reading
			var filenames []string
			for _, url := range urls {
				parts := strings.Split(url, "/")
				if len(parts) > 0 {
					filenames = append(filenames, parts[len(parts)-1])
				}
			}
			output = append(output, map[string]interface{}{
				"id":          r.ID,
				"record_date": r.RecordDate.Format("2006-01-02"),
				"shop_name":   r.ShopName,
				"item_count":  r.ItemCount,
				"filenames":   filenames,
				"raw_urls":    r.ImageURLs,
			})
		} else {
			output = append(output, map[string]interface{}{
				"id":          r.ID,
				"record_date": r.RecordDate.Format("2006-01-02"),
				"shop_name":   r.ShopName,
				"item_count":  r.ItemCount,
				"raw_urls":    r.ImageURLs,
				"parse_error": err.Error(),
			})
		}
	}
	return output, nil
}

// ===============================================
// Size-based Training Image Processing (V2)
// ===============================================

// ProcessImageForTraining detects size from an image and creates size mappings
func (s *TrainingImageService) ProcessImageForTraining(ctx context.Context, filename, tenantID string) (*models.ProcessImageResponse, error) {
	response := &models.ProcessImageResponse{
		Filename: filename,
		Success:  false,
	}

	// Find the image file
	imagePath, err := s.findImageFile(filename)
	if err != nil {
		response.Error = fmt.Sprintf("Image file not found: %v", err)
		return response, nil
	}

	// Read the image
	imageData, err := os.ReadFile(imagePath)
	if err != nil {
		response.Error = fmt.Sprintf("Failed to read image: %v", err)
		return response, nil
	}

	// Create the size detector
	detector, err := NewSizeHeaderDetector()
	if err != nil {
		response.Error = fmt.Sprintf("Failed to create detector: %v", err)
		return response, nil
	}

	// Detect size from image
	detectionResult, err := detector.DetectSizeFromImage(ctx, imageData, "")
	if err != nil {
		response.Error = fmt.Sprintf("Size detection failed: %v", err)
		return response, nil
	}

	response.DetectionResult = detectionResult

	// Get the daily_sales_record for this image
	imageInfo, err := s.GetImageSaleData(ctx, filename, tenantID)
	if err != nil {
		response.Error = fmt.Sprintf("Failed to get image info: %v", err)
		return response, nil
	}

	// If it's a beer page with multiple sizes, split the image
	if detectionResult.IsBeerPage && len(detectionResult.SizeRegions) > 1 {
		croppedPaths, err := s.SplitBeerPageImage(ctx, imageData, detectionResult.SizeRegions, filename)
		if err != nil {
			response.Error = fmt.Sprintf("Failed to split beer page: %v", err)
			return response, nil
		}

		// Create mappings for each cropped image
		for i, croppedPath := range croppedPaths {
			if i >= len(detectionResult.SizeRegions) {
				break
			}
			region := detectionResult.SizeRegions[i]

			mapping := models.TrainingImageSizeMapping{
				TenantID:            tenantID,
				DailySalesRecordID:  imageInfo.RecordID,
				ImageFilename:       filepath.Base(croppedPath),
				ImageURL:            "/uploads/daily_sales/cropped/" + filepath.Base(croppedPath),
				DetectedSize:        region.Size,
				DetectionMethod:     "fomoa_vision",
				IsCropped:           true,
				SourceImageFilename: &filename,
				IsBeerPage:          true,
				SizeSectionIndex:    &i,
				CroppedImagePath:    &croppedPath,
			}

			// Store crop region as JSON
			cropRegion := models.CropRegionData{
				YStartPct: region.YStartPct,
				YEndPct:   region.YEndPct,
			}
			cropRegionJSON, _ := json.Marshal(cropRegion)
			mapping.CropRegion = cropRegionJSON

			confidence := detectionResult.Confidence
			mapping.DetectionConfidence = &confidence

			// Save to database
			if err := s.SaveSizeMapping(ctx, &mapping); err != nil {
				fmt.Printf("Warning: Failed to save mapping for %s: %v\n", region.Size, err)
			} else {
				response.Mappings = append(response.Mappings, mapping)
			}
		}
	} else {
		// Single size page - create one mapping
		size := detectionResult.Sizes[0]
		mapping := models.TrainingImageSizeMapping{
			TenantID:           tenantID,
			DailySalesRecordID: imageInfo.RecordID,
			ImageFilename:      filename,
			ImageURL:           "/uploads/daily_sales/" + filename,
			DetectedSize:       size,
			DetectionMethod:    "fomoa_vision",
			IsCropped:          false,
			IsBeerPage:         false,
		}

		confidence := detectionResult.Confidence
		mapping.DetectionConfidence = &confidence

		// Save to database
		if err := s.SaveSizeMapping(ctx, &mapping); err != nil {
			response.Error = fmt.Sprintf("Failed to save mapping: %v", err)
			return response, nil
		}

		response.Mappings = append(response.Mappings, mapping)
	}

	response.Success = true
	return response, nil
}

// SplitBeerPageImage splits a beer page image into separate size sections
func (s *TrainingImageService) SplitBeerPageImage(ctx context.Context, imageData []byte, regions []models.SizeRegionData, originalFilename string) ([]string, error) {
	// Decode the image
	img, format, err := image.Decode(bytes.NewReader(imageData))
	if err != nil {
		return nil, fmt.Errorf("failed to decode image: %w", err)
	}

	bounds := img.Bounds()
	totalHeight := bounds.Dy()
	width := bounds.Dx()

	// Ensure cropped directory exists
	croppedDir := s.getCroppedDirectory()
	if err := os.MkdirAll(croppedDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create cropped directory: %w", err)
	}

	var croppedPaths []string
	baseFilename := strings.TrimSuffix(originalFilename, filepath.Ext(originalFilename))

	for _, region := range regions {
		// Calculate pixel coordinates from percentages
		yStart := int(float64(totalHeight) * region.YStartPct / 100)
		yEnd := int(float64(totalHeight) * region.YEndPct / 100)

		// Create cropped image
		croppedImg := image.NewRGBA(image.Rect(0, 0, width, yEnd-yStart))

		// Copy pixels
		for y := yStart; y < yEnd; y++ {
			for x := 0; x < width; x++ {
				croppedImg.Set(x, y-yStart, img.At(x, y))
			}
		}

		// Generate filename
		croppedFilename := fmt.Sprintf("%s_%s%s", baseFilename, region.Size, filepath.Ext(originalFilename))
		croppedPath := filepath.Join(croppedDir, croppedFilename)

		// Save cropped image
		outFile, err := os.Create(croppedPath)
		if err != nil {
			return nil, fmt.Errorf("failed to create cropped file: %w", err)
		}

		switch strings.ToLower(format) {
		case "jpeg", "jpg":
			err = jpeg.Encode(outFile, croppedImg, &jpeg.Options{Quality: 90})
		case "png":
			err = png.Encode(outFile, croppedImg)
		default:
			err = jpeg.Encode(outFile, croppedImg, &jpeg.Options{Quality: 90})
		}

		outFile.Close()
		if err != nil {
			return nil, fmt.Errorf("failed to encode cropped image: %w", err)
		}

		croppedPaths = append(croppedPaths, croppedPath)
		fmt.Printf("Created cropped image: %s (y: %d-%d)\n", croppedFilename, yStart, yEnd)
	}

	return croppedPaths, nil
}

// GetSizeFilteredItems returns items filtered by a specific size
func (s *TrainingImageService) GetSizeFilteredItems(ctx context.Context, recordID, size string) ([]models.SaleItemData, error) {
	var items []dailySalesItemRow

	query := `
		SELECT
			dsi.id,
			dsi.product_id::text as product_id,
			COALESCE(p.name, '') as brand_name,
			COALESCE(p.size, '') as size,
			COALESCE(dsi.opening_stock, 0) as opening_stock,
			dsi.quantity,
			dsi.unit_price,
			dsi.total_amount,
			COALESCE(dsi.closing_stock, 0) as closing_stock
		FROM daily_sales_items dsi
		LEFT JOIN products p ON p.id = dsi.product_id
		WHERE dsi.daily_sales_record_id = $1
		AND dsi.deleted_at IS NULL
		AND UPPER(REPLACE(p.size, ' ', '')) = $2
		ORDER BY p.name
	`

	normalizedSize := strings.ToUpper(strings.ReplaceAll(size, " ", ""))
	if err := s.db.Raw(query, recordID, normalizedSize).Scan(&items).Error; err != nil {
		return nil, err
	}

	var result []models.SaleItemData
	for _, item := range items {
		result = append(result, models.SaleItemData{
			ProductID:    item.ProductID,
			BrandName:    item.BrandName,
			Size:         item.Size,
			OpeningStock: item.OpeningStock,
			SaleQuantity: item.Quantity,
			Rate:         item.UnitPrice,
			Amount:       item.TotalAmount,
			ClosingStock: item.ClosingStock,
		})
	}

	return result, nil
}

// SaveSizeMapping saves a training image size mapping to the database
func (s *TrainingImageService) SaveSizeMapping(ctx context.Context, mapping *models.TrainingImageSizeMapping) error {
	query := `
		INSERT INTO training_image_size_mappings (
			tenant_id, daily_sales_record_id, image_filename, image_url,
			detected_size, detection_method, detection_confidence,
			is_cropped, source_image_filename, crop_region, cropped_image_path,
			is_beer_page, size_section_index, is_manually_verified
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
		RETURNING id, created_at, updated_at
	`

	var id string
	var createdAt, updatedAt time.Time

	// Handle empty tenant_id as NULL
	var tenantID interface{} = mapping.TenantID
	if mapping.TenantID == "" {
		tenantID = nil
	}

	err := s.db.Raw(query,
		tenantID,
		mapping.DailySalesRecordID,
		mapping.ImageFilename,
		mapping.ImageURL,
		mapping.DetectedSize,
		mapping.DetectionMethod,
		mapping.DetectionConfidence,
		mapping.IsCropped,
		mapping.SourceImageFilename,
		mapping.CropRegion,
		mapping.CroppedImagePath,
		mapping.IsBeerPage,
		mapping.SizeSectionIndex,
		mapping.IsManuallyVerified,
	).Row().Scan(&id, &createdAt, &updatedAt)

	if err != nil {
		return err
	}

	mapping.ID = id
	mapping.CreatedAt = createdAt
	mapping.UpdatedAt = updatedAt

	return nil
}

// GetSizeMappingsForRecord returns all size mappings for a daily sales record
func (s *TrainingImageService) GetSizeMappingsForRecord(ctx context.Context, recordID string) ([]models.TrainingImageSizeMapping, error) {
	var mappings []models.TrainingImageSizeMapping

	query := `
		SELECT
			id, tenant_id, daily_sales_record_id,
			image_filename, image_url, detected_size,
			detection_method, detection_confidence,
			is_cropped, source_image_filename, crop_region, cropped_image_path,
			is_beer_page, size_section_index,
			is_manually_verified, verified_by_id, verified_at,
			created_at, updated_at
		FROM training_image_size_mappings
		WHERE daily_sales_record_id = $1
		ORDER BY detected_size, size_section_index
	`

	if err := s.db.Raw(query, recordID).Scan(&mappings).Error; err != nil {
		return nil, err
	}

	return mappings, nil
}

// GetTrainingImagesWithMappings returns training images with their size mappings
func (s *TrainingImageService) GetTrainingImagesWithMappings(ctx context.Context, tenantID string, sizeFilter string) (*models.TrainingImageListResponseV2, error) {
	// Get base training images
	baseResponse, err := s.GetTrainingImagesWithSales(ctx, tenantID)
	if err != nil {
		return nil, err
	}

	response := &models.TrainingImageListResponseV2{
		TotalImages:      baseResponse.TotalImages,
		WithSales:        baseResponse.WithSales,
		WithoutSales:     baseResponse.WithoutSales,
		SizeDistribution: make(map[string]int),
	}

	// Get all mappings for this tenant (skip if no tenant)
	var allMappings []models.TrainingImageSizeMapping
	if tenantID != "" {
		mappingQuery := `
			SELECT * FROM training_image_size_mappings
			WHERE tenant_id = $1
			ORDER BY created_at DESC
		`
		if err := s.db.Raw(mappingQuery, tenantID).Scan(&allMappings).Error; err != nil {
			// If table doesn't exist yet, continue without mappings
			if !strings.Contains(err.Error(), "does not exist") {
				return nil, err
			}
		}
	} else {
		// No tenant filter - get all mappings (for admin/internal use)
		mappingQuery := `
			SELECT * FROM training_image_size_mappings
			ORDER BY created_at DESC
			LIMIT 1000
		`
		if err := s.db.Raw(mappingQuery).Scan(&allMappings).Error; err != nil {
			if !strings.Contains(err.Error(), "does not exist") {
				// Ignore error and continue without mappings
				fmt.Printf("Warning: Could not load mappings: %v\n", err)
			}
		}
	}

	// Create a map for quick lookup - index by both cropped and source filename
	mappingsByFilename := make(map[string]*models.TrainingImageSizeMapping)
	for i := range allMappings {
		m := &allMappings[i]
		mappingsByFilename[m.ImageFilename] = m
		// Also index by source filename so original images show as processed
		if m.SourceImageFilename != nil && *m.SourceImageFilename != "" {
			mappingsByFilename[*m.SourceImageFilename] = m
		}
		response.SizeDistribution[m.DetectedSize]++
	}

	// Combine base images with mappings
	for _, img := range baseResponse.Images {
		imageWithMapping := models.TrainingImageWithMapping{
			TrainingImageData: img,
			ProcessingStatus:  "pending",
		}

		if mapping, ok := mappingsByFilename[img.ImageFilename]; ok {
			imageWithMapping.SizeMapping = mapping
			imageWithMapping.DetectedSize = mapping.DetectedSize
			imageWithMapping.DetectionMethod = mapping.DetectionMethod
			imageWithMapping.IsBeerPage = mapping.IsBeerPage
			imageWithMapping.ProcessingStatus = "processed"
			response.ProcessedImages++
		} else {
			response.PendingImages++
		}

		// Apply size filter if specified
		if sizeFilter != "" && imageWithMapping.DetectedSize != sizeFilter {
			continue
		}

		response.Images = append(response.Images, imageWithMapping)
	}

	return response, nil
}

// ExportTrainingDataV2 exports training data with size-filtered ground truth
func (s *TrainingImageService) ExportTrainingDataV2(ctx context.Context, tenantID string) (string, error) {
	// Get all size mappings
	var mappings []models.TrainingImageSizeMapping
	var err error
	if tenantID != "" {
		query := `
			SELECT * FROM training_image_size_mappings
			WHERE tenant_id = $1
			AND detection_method != 'pending'
			ORDER BY daily_sales_record_id, detected_size
		`
		err = s.db.Raw(query, tenantID).Scan(&mappings).Error
	} else {
		query := `
			SELECT * FROM training_image_size_mappings
			WHERE detection_method != 'pending'
			ORDER BY daily_sales_record_id, detected_size
			LIMIT 1000
		`
		err = s.db.Raw(query).Scan(&mappings).Error
	}
	if err != nil {
		return "", err
	}

	var output []string
	for _, mapping := range mappings {
		// Get size-filtered items
		items, err := s.GetSizeFilteredItems(ctx, mapping.DailySalesRecordID, mapping.DetectedSize)
		if err != nil {
			continue
		}

		if len(items) == 0 {
			continue // Skip if no items for this size
		}

		// Get record info for metadata
		imageInfo, _ := s.GetImageSaleDataByRecordID(ctx, mapping.DailySalesRecordID)

		// Convert items to ground truth format
		groundTruth := make([]models.GroundTruthItem, len(items))
		for i, item := range items {
			groundTruth[i] = models.GroundTruthItem{
				Brand:   item.BrandName,
				Size:    item.Size,
				Opening: item.OpeningStock,
				Sale:    item.SaleQuantity,
				Rate:    item.Rate,
				Amount:  item.Amount,
				Closing: item.ClosingStock,
			}
		}

		// Determine image path
		imagePath := mapping.ImageFilename
		if mapping.IsCropped && mapping.CroppedImagePath != nil {
			imagePath = "cropped/" + filepath.Base(*mapping.CroppedImagePath)
		}

		// Get original image filename if cropped
		originalImage := ""
		if mapping.SourceImageFilename != nil {
			originalImage = *mapping.SourceImageFilename
		}

		exportData := models.TrainingExportDataV2{
			Image:       imagePath,
			Size:        mapping.DetectedSize,
			GroundTruth: groundTruth,
			Metadata: models.TrainingExportMetadataV2{
				Date:          time.Now().Format("2006-01-02"), // Will be replaced with actual date
				Shop:          "",
				ShopID:        "",
				IsBeerPage:    mapping.IsBeerPage,
				OriginalImage: originalImage,
				IsCropped:     mapping.IsCropped,
			},
		}

		// Fill in metadata from image info if available
		if imageInfo != nil {
			exportData.Metadata.Date = imageInfo.RecordDate.Format("2006-01-02")
			exportData.Metadata.Shop = imageInfo.ShopName
			exportData.Metadata.ShopID = imageInfo.ShopID
		}

		jsonLine, err := json.Marshal(exportData)
		if err != nil {
			continue
		}
		output = append(output, string(jsonLine))
	}

	return strings.Join(output, "\n"), nil
}

// GetImageSaleDataByRecordID fetches sale data by record ID
func (s *TrainingImageService) GetImageSaleDataByRecordID(ctx context.Context, recordID string) (*models.TrainingImageData, error) {
	var record dailySalesRecordRow
	query := `
		SELECT
			dsr.id,
			dsr.record_date,
			dsr.shop_id::text as shop_id,
			COALESCE(s.name, '') as shop_name,
			dsr.image_urls
		FROM daily_sales_records dsr
		LEFT JOIN shops s ON s.id = dsr.shop_id
		WHERE dsr.id = $1
		AND dsr.deleted_at IS NULL
	`

	if err := s.db.Raw(query, recordID).Scan(&record).Error; err != nil {
		return nil, err
	}

	return &models.TrainingImageData{
		RecordID:   record.ID,
		RecordDate: record.RecordDate,
		ShopID:     record.ShopID,
		ShopName:   record.ShopName,
	}, nil
}

// VerifySizeMapping manually verifies or overrides a size mapping
func (s *TrainingImageService) VerifySizeMapping(ctx context.Context, req *models.VerifySizeMappingRequest) error {
	query := `
		UPDATE training_image_size_mappings
		SET detected_size = $1,
			is_beer_page = $2,
			is_manually_verified = true,
			verified_by_id = $3,
			verified_at = NOW(),
			updated_at = NOW()
		WHERE id = $4
	`

	return s.db.Exec(query, req.CorrectSize, req.IsBeerPage, req.VerifiedByID, req.MappingID).Error
}

// ProcessAllImages processes all unprocessed images in the uploads folder
func (s *TrainingImageService) ProcessAllImages(ctx context.Context, tenantID string) (int, int, error) {
	// Get list of all image files
	imageDir, err := s.getImageDirectory()
	if err != nil {
		return 0, 0, err
	}

	files, err := os.ReadDir(imageDir)
	if err != nil {
		return 0, 0, err
	}

	// Get already processed filenames
	var processedFilenames []string
	query := `SELECT image_filename FROM training_image_size_mappings WHERE tenant_id = $1`
	s.db.Raw(query, tenantID).Pluck("image_filename", &processedFilenames)

	processedSet := make(map[string]bool)
	for _, f := range processedFilenames {
		processedSet[f] = true
	}

	processed := 0
	failed := 0

	for _, file := range files {
		if file.IsDir() {
			continue
		}

		filename := file.Name()
		ext := strings.ToLower(filepath.Ext(filename))
		if ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".webp" {
			continue
		}

		// Skip if already processed
		if processedSet[filename] {
			continue
		}

		// Process the image
		result, err := s.ProcessImageForTraining(ctx, filename, tenantID)
		if err != nil || !result.Success {
			failed++
			fmt.Printf("Failed to process %s: %v\n", filename, err)
			// Add delay to avoid rate limiting
			time.Sleep(3 * time.Second)
			continue
		}

		processed++
		fmt.Printf("Processed %s: %v\n", filename, result.DetectionResult.Sizes)

		// Add delay between API calls to avoid rate limiting
		time.Sleep(5 * time.Second)
	}

	return processed, failed, nil
}

// Helper functions

func (s *TrainingImageService) findImageFile(filename string) (string, error) {
	imageDirs := []string{
		"./uploads/daily_sales",
		"/var/www/liquorpro/uploads/daily_sales",
		"/root/uploads/daily_sales",
	}

	for _, dir := range imageDirs {
		path := filepath.Join(dir, filename)
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}

	return "", fmt.Errorf("image not found: %s", filename)
}

func (s *TrainingImageService) getImageDirectory() (string, error) {
	imageDirs := []string{
		"./uploads/daily_sales",
		"/var/www/liquorpro/uploads/daily_sales",
		"/root/uploads/daily_sales",
	}

	for _, dir := range imageDirs {
		if _, err := os.Stat(dir); err == nil {
			return dir, nil
		}
	}

	return "", fmt.Errorf("could not find image directory")
}

func (s *TrainingImageService) getCroppedDirectory() string {
	imageDirs := []string{
		"/var/www/liquorpro/uploads/daily_sales/cropped",
		"./uploads/daily_sales/cropped",
		"/root/uploads/daily_sales/cropped",
	}

	for _, dir := range imageDirs {
		parentDir := filepath.Dir(dir)
		if _, err := os.Stat(parentDir); err == nil {
			return dir
		}
	}

	return "/var/www/liquorpro/uploads/daily_sales/cropped"
}

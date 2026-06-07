package backfill

// v1.0.140 — Retrospective digit-training-data backfill.
//
// Walks every approved daily_sales_records row, re-loads the source image
// from /app/uploads, runs cv-sidecar /sheet (using the cache when present),
// matches each daily_sales_items row to its CV row by MRP-sorted printed
// brand list + product_id lookup, crops the Sale cell, and inserts one
// digit_training_samples row per match (source='backfill').
//
// Idempotent: skips images already mined (image_sha256 + source='backfill'
// already present). Safe to run any number of times.

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"image"
	_ "image/jpeg"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/sirupsen/logrus"
)

const (
	cropDir          = "/app/ai-training/digits"
	pipelineVersion  = "sheet-v1.0.138"
	defaultMaxRecord = 1000
)

type Options struct {
	Since       time.Time
	TenantID    *uuid.UUID
	ShopID      *uuid.UUID
	MaxRecords  int
	DryRun      bool
}

// ParseFlagsAndRun is the CLI entry point — parses os.Args[2:] (everything
// after the --backfill-training-data sentinel) and runs the backfill.
func ParseFlagsAndRun(db *database.DB, redisCache *cache.Cache, logger *logrus.Logger) {
	fs := flag.NewFlagSet("backfill-training-data", flag.ExitOnError)
	since := fs.String("since", "2025-01-01", "RFC3339 or YYYY-MM-DD; only mine records approved at-or-after this date")
	tenant := fs.String("tenant-id", "", "optional tenant UUID filter")
	shop := fs.String("shop-id", "", "optional shop UUID filter")
	maxRecs := fs.Int("max-records", defaultMaxRecord, "safety cap on number of records to process")
	dry := fs.Bool("dry-run", false, "print planned inserts without writing")
	if err := fs.Parse(os.Args[2:]); err != nil {
		logger.Fatalf("backfill flag parse: %v", err)
	}

	opts := Options{MaxRecords: *maxRecs, DryRun: *dry}
	parsed, err := time.Parse(time.RFC3339, *since)
	if err != nil {
		parsed, err = time.Parse("2006-01-02", *since)
		if err != nil {
			logger.Fatalf("backfill --since invalid: %v", err)
		}
	}
	opts.Since = parsed
	if *tenant != "" {
		id, perr := uuid.Parse(*tenant)
		if perr != nil {
			logger.Fatalf("backfill --tenant-id invalid: %v", perr)
		}
		opts.TenantID = &id
	}
	if *shop != "" {
		id, perr := uuid.Parse(*shop)
		if perr != nil {
			logger.Fatalf("backfill --shop-id invalid: %v", perr)
		}
		opts.ShopID = &id
	}

	aliasService := alias.NewAliasService(db, alias.WithRedis(redisCache.Client()))
	if err := Run(db, aliasService, logger, opts); err != nil {
		logger.Fatalf("backfill failed: %v", err)
	}
}

// Run executes the backfill with provided options. Returns final summary
// stats; logs detail along the way.
func Run(db *database.DB, aliasService *alias.AliasService, logger *logrus.Logger, opts Options) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	cvSidecar := services.NewCVSidecarClient(logger)
	if cvSidecar == nil {
		return fmt.Errorf("cv-sidecar client init failed")
	}
	extractor := services.NewSaleSheetExtractor(db.DB, logger, cvSidecar, aliasService)

	type recordRow struct {
		ID            uuid.UUID
		TenantID      uuid.UUID
		ShopID        uuid.UUID
		RecordDate    time.Time
		ImageURLs     string // JSON text from receipt_images column
	}
	var records []recordRow
	sqlBuf := strings.Builder{}
	sqlBuf.WriteString(`
		SELECT id, tenant_id, shop_id, record_date,
		       COALESCE(receipt_images::text, '[]') AS image_urls
		FROM daily_sales_records
		WHERE deleted_at IS NULL
		  AND approved_at IS NOT NULL
		  AND approved_at >= ?
	`)
	args := []any{opts.Since}
	if opts.TenantID != nil {
		sqlBuf.WriteString(" AND tenant_id = ? ")
		args = append(args, *opts.TenantID)
	}
	if opts.ShopID != nil {
		sqlBuf.WriteString(" AND shop_id = ? ")
		args = append(args, *opts.ShopID)
	}
	sqlBuf.WriteString(" ORDER BY approved_at ASC LIMIT ? ")
	args = append(args, opts.MaxRecords)
	if err := db.WithContext(ctx).Raw(sqlBuf.String(), args...).Scan(&records).Error; err != nil {
		return fmt.Errorf("query approved records: %w", err)
	}
	logger.Infof("backfill: found %d approved records since %s", len(records), opts.Since.Format("2006-01-02"))

	type itemRow struct {
		ID            uuid.UUID
		ProductID     uuid.UUID
		QuantitySold  int
		OCRTotal      int
		ProductName   string
		ProductSize   string
		CategoryName  string
	}

	totalInserted := 0
	totalSkipped := 0
	totalImages := 0
	for _, rec := range records {
		var urls []string
		if jerr := json.Unmarshal([]byte(rec.ImageURLs), &urls); jerr != nil || len(urls) == 0 {
			logger.Debugf("backfill: record %s no images, skipping", rec.ID)
			continue
		}

		// Items for this record.
		var items []itemRow
		if err := db.WithContext(ctx).Raw(`
			SELECT dsi.id, dsi.product_id, dsi.quantity_sold, COALESCE(dsi.ocr_total, 0) AS ocr_total,
			       p.name AS product_name, COALESCE(p.size, '') AS product_size,
			       COALESCE(c.name, '') AS category_name
			FROM daily_sales_items dsi
			JOIN products p ON p.id = dsi.product_id
			LEFT JOIN categories c ON c.id = p.category_id
			WHERE dsi.daily_sales_record_id = ?
			  AND dsi.deleted_at IS NULL
			  AND dsi.quantity_sold > 0
		`, rec.ID).Scan(&items).Error; err != nil {
			logger.Warnf("backfill: items query failed for record %s: %v", rec.ID, err)
			continue
		}
		if len(items) == 0 {
			continue
		}

		// Group items by inferred page (we use product_size to pick which
		// register image they belong to; assumption: 1 image per size).
		// Conservative: process every image, match items whose size matches.
		for pageIdx, url := range urls {
			imgBytes, err := readImageBytes(url)
			if err != nil {
				logger.Warnf("backfill: read image %q: %v", url, err)
				continue
			}
			totalImages++
			sum := sha256.Sum256(imgBytes)
			imageSHA := hex.EncodeToString(sum[:])

			// Idempotency: skip if already mined.
			var existing int
			db.WithContext(ctx).Raw(`SELECT count(*) FROM digit_training_samples WHERE image_sha256=? AND source='backfill'`, imageSHA).Row().Scan(&existing)
			if existing > 0 {
				logger.Debugf("backfill: image %s already mined (%d rows), skipping", imageSHA[:12], existing)
				totalSkipped += existing
				continue
			}

			// Get CV /sheet for this image (cache or fresh).
			sheet, serr := getOrFetchSheet(ctx, db, extractor, imageSHA, imgBytes)
			if serr != nil {
				logger.Warnf("backfill: sheet fetch failed for %s: %v", imageSHA[:12], serr)
				continue
			}
			if sheet == nil || !sheet.OK || len(sheet.Rows) == 0 {
				continue
			}
			byRow := indexCellsByRow(sheet.Cells)

			// Pick the printed brand list for the item's size+category. We
			// determine size from the FIRST item that has a size.
			itemSize := ""
			itemCat := ""
			for _, it := range items {
				if it.ProductSize != "" {
					itemSize = it.ProductSize
					break
				}
			}
			for _, it := range items {
				if itemCat = inferCategory(it.CategoryName); itemCat != "" {
					break
				}
			}
			sizeML := parseFirstInt(itemSize)
			if sizeML == 0 {
				logger.Debugf("backfill: page=%d couldn't infer sizeML, skipping", pageIdx)
				continue
			}
			printed, perr := services.LoadShopPrintedBrandList(db.DB, rec.TenantID, rec.ShopID, sizeML, itemCat)
			if perr != nil || len(printed) == 0 {
				logger.Debugf("backfill: page=%d no printed list (%v)", pageIdx, perr)
				continue
			}

			// Decode image once.
			srcImg, _, derr := image.Decode(bytes.NewReader(imgBytes))
			if derr != nil {
				logger.Warnf("backfill: decode failed for %s: %v", imageSHA[:12], derr)
				continue
			}

			// Map products → printed list position.
			productToPos := make(map[uuid.UUID]int, len(printed))
			for k, pb := range printed {
				productToPos[pb.ProductID] = k
			}

			// Walk CV data rows in order; bind each to printed[k] by position.
			dataRowIdxs := inferDataRowsCompat(sheet)

			dateDir := filepath.Join(cropDir, time.Now().UTC().Format("2006/01/02"))
			if !opts.DryRun {
				if mkErr := os.MkdirAll(dateDir, 0o755); mkErr != nil {
					logger.Warnf("backfill: mkdir %s: %v", dateDir, mkErr)
					continue
				}
			}

			pageInserted := 0
			for kPos, rowIdx := range dataRowIdxs {
				if kPos >= len(printed) {
					break
				}
				pb := printed[kPos]
				// Find an item with this product_id; if none, skip (no label).
				var matchedItem *itemRow
				for i := range items {
					if items[i].ProductID == pb.ProductID {
						matchedItem = &items[i]
						break
					}
				}
				if matchedItem == nil {
					continue
				}
				cells, ok := byRow[rowIdx]
				if !ok {
					continue
				}
				saleCell, scOk := cells["sale"]
				if !scOk {
					continue
				}
				// Cross-check: positive truth qty implies the sale cell should have writing
				if !saleCell.HasWriting {
					continue
				}

				crop, cerr := services.CropCellJPEGPaddedExt(srcImg, saleCell, 0.25, 0.10)
				if cerr != nil {
					continue
				}
				cropSum := sha256.Sum256(crop)
				cropSHA := hex.EncodeToString(cropSum[:])
				cropPath := filepath.Join(dateDir,
					fmt.Sprintf("%s_p%d_r%d_sale_BF.jpg", imageSHA[:12], pageIdx+1, rowIdx))

				if opts.DryRun {
					logger.Infof("[dry-run] would insert: shop=%s row=%d truth=%d", rec.ShopID, rowIdx, matchedItem.QuantitySold)
					pageInserted++
					continue
				}
				if werr := os.WriteFile(cropPath, crop, 0o644); werr != nil {
					logger.Warnf("backfill: write %s: %v", cropPath, werr)
					continue
				}
				ins := db.WithContext(ctx).Exec(`
					INSERT INTO digit_training_samples (
						tenant_id, shop_id, daily_sales_record_id, daily_sales_item_id,
						source, pipeline_version, capture_reason,
						image_sha256, image_path,
						page_index, row_idx, col_name,
						x_left, x_right, y_top, y_bot, page_w, page_h,
						crop_path, crop_sha256, crop_w, crop_h,
						ai_raw_value, truth_value, was_corrected,
						math_consistent
					) VALUES (
						?, ?, ?, ?,
						'backfill', ?, 'backfill_mined',
						?, ?,
						?, ?, ?,
						?, ?, ?, ?, ?, ?,
						?, ?, ?, ?,
						?, ?, ?,
						NULL
					) ON CONFLICT (image_sha256, page_index, row_idx, col_name) DO NOTHING
				`,
					rec.TenantID, rec.ShopID, rec.ID, matchedItem.ID,
					pipelineVersion,
					imageSHA, url,
					pageIdx+1, rowIdx, "sale",
					saleCell.XLeft, saleCell.XRight, saleCell.YTop, saleCell.YBot,
					sheet.PageSizePx[0], sheet.PageSizePx[1],
					cropPath, cropSHA, saleCell.XRight-saleCell.XLeft, saleCell.YBot-saleCell.YTop,
					strconv.Itoa(matchedItem.OCRTotal), strconv.Itoa(matchedItem.QuantitySold),
					matchedItem.OCRTotal != matchedItem.QuantitySold,
				)
				if ins.Error != nil {
					logger.Warnf("backfill: insert failed row=%d: %v", rowIdx, ins.Error)
					_ = os.Remove(cropPath)
					continue
				}
				if ins.RowsAffected > 0 {
					pageInserted++
				}
			}
			logger.Infof("backfill: record=%s page=%d inserted=%d", rec.ID, pageIdx+1, pageInserted)
			totalInserted += pageInserted
		}
	}

	logger.Infof("backfill SUMMARY: records=%d images=%d inserted=%d skipped_existing=%d dry_run=%v",
		len(records), totalImages, totalInserted, totalSkipped, opts.DryRun)
	return nil
}

func nullableUUID(p *uuid.UUID) interface{} {
	if p == nil {
		return nil
	}
	return *p
}

func indexCellsByRow(cells []services.SheetCell) map[int]map[string]services.SheetCell {
	out := make(map[int]map[string]services.SheetCell, 64)
	for _, c := range cells {
		if out[c.RowIdx] == nil {
			out[c.RowIdx] = map[string]services.SheetCell{}
		}
		out[c.RowIdx][c.ColName] = c
	}
	return out
}

// inferDataRowsCompat picks data rows (skips header + grand-total) — minimal
// version of the same logic in sale_sheet_grid.go.
func inferDataRowsCompat(sheet *services.SheetResponse) []int {
	if sheet == nil || len(sheet.Rows) == 0 {
		return nil
	}
	byRow := indexCellsByRow(sheet.Cells)
	maxIdx := 0
	for _, r := range sheet.Rows {
		if r.Idx > maxIdx {
			maxIdx = r.Idx
		}
	}
	bottomCutoff := maxIdx - (maxIdx / 4)
	out := make([]int, 0, len(sheet.Rows))
	for i, r := range sheet.Rows {
		if i == 0 {
			continue
		}
		cells := byRow[r.Idx]
		if cells == nil {
			continue
		}
		brandCell, hasBrand := cells["brand"]
		numericCount := 0
		for _, col := range []string{"open", "sale", "amount", "closing", "total"} {
			if c, ok := cells[col]; ok && c.HasWriting {
				numericCount++
			}
		}
		if r.Idx >= bottomCutoff && hasBrand && brandCell.InkRatio < 0.04 && numericCount >= 2 {
			continue
		}
		anyDataInk := false
		for _, col := range []string{"open", "sale", "amount", "closing"} {
			if c, ok := cells[col]; ok && c.HasWriting {
				anyDataInk = true
				break
			}
		}
		if anyDataInk || (hasBrand && brandCell.HasWriting) {
			out = append(out, r.Idx)
		}
	}
	return out
}

func getOrFetchSheet(ctx context.Context, db *database.DB, extractor *services.SaleSheetExtractor, imageSHA string, imgBytes []byte) (*services.SheetResponse, error) {
	var raw []byte
	row := db.WithContext(ctx).Raw(`SELECT cv_sheet_jsonb::text FROM sale_image_extraction_cache WHERE image_sha256=? AND pipeline_version=? LIMIT 1`,
		imageSHA, pipelineVersion).Row()
	if scanErr := row.Scan(&raw); scanErr == nil && len(raw) > 0 {
		var sheet services.SheetResponse
		if jerr := json.Unmarshal(raw, &sheet); jerr == nil {
			return &sheet, nil
		}
	}
	return services.FetchSheetFromCVExt(ctx, extractor, imgBytes)
}

func readImageBytes(url string) ([]byte, error) {
	if strings.HasPrefix(url, "/uploads/") {
		return os.ReadFile("/app" + url)
	}
	if strings.HasPrefix(url, "http://") || strings.HasPrefix(url, "https://") {
		req, _ := http.NewRequest("GET", url, nil)
		client := &http.Client{Timeout: 10 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != 200 {
			return nil, fmt.Errorf("http %d", resp.StatusCode)
		}
		return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	}
	if strings.HasPrefix(url, "/") {
		return os.ReadFile(url)
	}
	return nil, fmt.Errorf("unsupported url: %s", url)
}

// parseFirstInt finds the first integer in a string (e.g. "180ML" → 180).
func parseFirstInt(s string) int {
	start := -1
	for i, r := range s {
		if r >= '0' && r <= '9' {
			start = i
			break
		}
	}
	if start < 0 {
		return 0
	}
	end := start
	for end < len(s) && s[end] >= '0' && s[end] <= '9' {
		end++
	}
	v, _ := strconv.Atoi(s[start:end])
	return v
}

func inferCategory(catName string) string {
	low := strings.ToLower(catName)
	for _, b := range []string{"beer", "lager", "ale", "rtd"} {
		if strings.Contains(low, b) {
			return "beer"
		}
	}
	if low != "" {
		return "non_beer"
	}
	return ""
}

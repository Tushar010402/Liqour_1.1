package services

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"
	reportModels "github.com/liquorpro/go-backend/internal/sales/models"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// PurchaReportService handles purcha report generation
type PurchaReportService struct {
	db    *database.DB
	cache *cache.Cache
}

// NewPurchaReportService creates a new purcha report service
func NewPurchaReportService(db *database.DB, cache *cache.Cache) *PurchaReportService {
	return &PurchaReportService{db: db, cache: cache}
}

// GeneratePurchaReport generates the daily sales register (purcha report)
func (s *PurchaReportService) GeneratePurchaReport(
	ctx context.Context,
	tenantID uuid.UUID,
	req reportModels.PurchaReportRequest,
) (*reportModels.PurchaReportResponse, error) {
	// 1. Validate shop belongs to tenant
	var shop models.Shop
	if err := s.db.Where("id = ? AND tenant_id = ?", req.ShopID, tenantID).First(&shop).Error; err != nil {
		return nil, fmt.Errorf("shop not found or access denied")
	}

	// 2. Get all products with stock for this shop
	products, err := s.getProductsWithStock(ctx, tenantID, req.ShopID, req.CategoryFilter)
	if err != nil {
		return nil, fmt.Errorf("failed to get products: %w", err)
	}

	if len(products) == 0 {
		return &reportModels.PurchaReportResponse{
			ShopID:         shop.ID,
			ShopName:       shop.Name,
			ReportDate:     req.Date,
			GeneratedAt:    time.Now(),
			CategoryFilter: req.CategoryFilter,
			ViewMode:       req.ViewMode,
			ShowOpening:    req.ShowOpening,
			Pages:          []reportModels.PurchaReportSizePage{},
		}, nil
	}

	// 3. Get opening stock (previous day's closing OR current stock)
	openingStockMap, err := s.getOpeningStock(ctx, tenantID, req.ShopID, req.Date)
	if err != nil {
		return nil, fmt.Errorf("failed to get opening stock: %w", err)
	}

	// 4. Get today's receipts (approved purchases for this date)
	receiptMap, err := s.getTodaysReceipts(ctx, tenantID, req.ShopID, req.Date)
	if err != nil {
		return nil, fmt.Errorf("failed to get receipts: %w", err)
	}

	// 5. Get today's sales (approved daily sales for this date)
	salesMap, err := s.getTodaysSales(ctx, tenantID, req.ShopID, req.Date)
	if err != nil {
		return nil, fmt.Errorf("failed to get sales: %w", err)
	}

	// 6. Build report items
	reportItems := s.buildReportItems(products, openingStockMap, receiptMap, salesMap, req.ShowOpening)

	// 7. Filter by sizes if specified
	if len(req.Sizes) > 0 {
		reportItems = s.filterBySizes(reportItems, req.Sizes)
	}

	// 8. Organize by view mode
	response := s.organizeReport(reportItems, shop, req)

	return response, nil
}

// getProductsWithStock retrieves all products with stock for a shop
func (s *PurchaReportService) getProductsWithStock(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	categoryFilter string,
) ([]reportModels.ProductWithDetails, error) {
	var products []reportModels.ProductWithDetails

	query := `
		SELECT
			p.id,
			p.name,
			UPPER(p.size) as size,
			p.selling_price,
			b.name as brand_name,
			c.name as category_name,
			COALESCE(st.quantity, 0) as current_stock
		FROM products p
		JOIN brands b ON b.id = p.brand_id
		JOIN categories c ON c.id = p.category_id
		LEFT JOIN stocks st ON st.product_id = p.id AND st.shop_id = $2
		WHERE p.tenant_id = $1
		  AND p.is_active = true
		  AND (st.quantity > 0 OR st.quantity IS NULL)
	`

	// Apply category filter
	switch categoryFilter {
	case "non_beer":
		query += " AND LOWER(c.name) != 'beer'"
	case "beer":
		query += " AND LOWER(c.name) = 'beer'"
	// "all" - no additional filter
	}

	query += " ORDER BY p.selling_price ASC"

	rows, err := s.db.Raw(query, tenantID, shopID).Rows()
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var p reportModels.ProductWithDetails
		if err := rows.Scan(&p.ID, &p.Name, &p.Size, &p.SellingPrice, &p.BrandName, &p.CategoryName, &p.CurrentStock); err != nil {
			return nil, err
		}
		products = append(products, p)
	}

	return products, nil
}

// getOpeningStock retrieves opening stock based on previous day's closing or current stock
func (s *PurchaReportService) getOpeningStock(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	date time.Time,
) (map[uuid.UUID]int, error) {
	openingMap := make(map[uuid.UUID]int)
	yesterday := date.AddDate(0, 0, -1)

	// Try to get from stock history (closing of previous day)
	var histories []struct {
		ProductID   uuid.UUID
		NewQuantity int
	}

	err := s.db.Raw(`
		SELECT DISTINCT ON (st.product_id)
			st.product_id,
			sh.new_quantity
		FROM stock_histories sh
		JOIN stocks st ON st.id = sh.stock_id
		WHERE st.shop_id = $1
		  AND st.tenant_id = $2
		  AND DATE(sh.created_at) = $3
		ORDER BY st.product_id, sh.created_at DESC
	`, shopID, tenantID, yesterday.Format("2006-01-02")).Scan(&histories).Error

	if err == nil && len(histories) > 0 {
		for _, h := range histories {
			openingMap[h.ProductID] = h.NewQuantity
		}
	}

	// For products without history, use current stock
	var currentStocks []struct {
		ProductID uuid.UUID
		Quantity  int
	}
	s.db.Raw(`
		SELECT product_id, quantity
		FROM stocks
		WHERE shop_id = $1 AND tenant_id = $2
	`, shopID, tenantID).Scan(&currentStocks)

	for _, cs := range currentStocks {
		if _, exists := openingMap[cs.ProductID]; !exists {
			openingMap[cs.ProductID] = cs.Quantity
		}
	}

	return openingMap, nil
}

// getTodaysReceipts gets purchases received today
func (s *PurchaReportService) getTodaysReceipts(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	date time.Time,
) (map[uuid.UUID]int, error) {
	receiptMap := make(map[uuid.UUID]int)

	var items []struct {
		ProductID uuid.UUID
		Quantity  int
	}

	dateStr := date.Format("2006-01-02")
	err := s.db.Raw(`
		SELECT spi.product_id, SUM(spi.quantity) as quantity
		FROM stock_purchase_items spi
		JOIN stock_purchases sp ON sp.id = spi.purchase_id
		WHERE sp.shop_id = $1
		  AND sp.tenant_id = $2
		  AND sp.status = 'approved'
		  AND DATE(sp.purchase_date) = $3
		GROUP BY spi.product_id
	`, shopID, tenantID, dateStr).Scan(&items).Error

	if err != nil {
		return receiptMap, err
	}

	for _, item := range items {
		receiptMap[item.ProductID] = item.Quantity
	}

	return receiptMap, nil
}

// getTodaysSales gets sales made today
func (s *PurchaReportService) getTodaysSales(
	ctx context.Context,
	tenantID, shopID uuid.UUID,
	date time.Time,
) (map[uuid.UUID]int, error) {
	salesMap := make(map[uuid.UUID]int)

	var items []struct {
		ProductID uuid.UUID
		Quantity  int
	}

	dateStr := date.Format("2006-01-02")

	// From daily sales records (approved)
	err := s.db.Raw(`
		SELECT dsi.product_id, SUM(dsi.quantity) as quantity
		FROM daily_sales_items dsi
		JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		WHERE dsr.shop_id = $1
		  AND dsr.tenant_id = $2
		  AND dsr.status = 'approved'
		  AND DATE(dsr.record_date) = $3
		GROUP BY dsi.product_id
	`, shopID, tenantID, dateStr).Scan(&items).Error

	if err != nil {
		return salesMap, err
	}

	for _, item := range items {
		salesMap[item.ProductID] = item.Quantity
	}

	// Also include individual sales if any
	var individualItems []struct {
		ProductID uuid.UUID
		Quantity  int
	}
	s.db.Raw(`
		SELECT si.product_id, SUM(si.quantity) as quantity
		FROM sale_items si
		JOIN sales s ON s.id = si.sale_id
		WHERE s.shop_id = $1
		  AND s.tenant_id = $2
		  AND s.status = 'approved'
		  AND DATE(s.sale_date) = $3
		GROUP BY si.product_id
	`, shopID, tenantID, dateStr).Scan(&individualItems)

	for _, item := range individualItems {
		salesMap[item.ProductID] += item.Quantity
	}

	return salesMap, nil
}

// buildReportItems creates report items with calculations
func (s *PurchaReportService) buildReportItems(
	products []reportModels.ProductWithDetails,
	openingMap, receiptMap, salesMap map[uuid.UUID]int,
	showOpening bool,
) []reportModels.PurchaReportItem {
	var items []reportModels.PurchaReportItem

	for _, p := range products {
		opening := openingMap[p.ID]
		if opening == 0 {
			opening = p.CurrentStock
		}
		receipt := receiptMap[p.ID]
		sale := salesMap[p.ID]
		total := opening + receipt
		closing := total - sale
		amount := float64(sale) * p.SellingPrice

		item := reportModels.PurchaReportItem{
			ProductID:    p.ID,
			BrandName:    p.BrandName,
			ProductName:  p.Name,
			Size:         p.Size,
			CategoryName: p.CategoryName,
			OpeningStock: opening,
			Receipt:      receipt,
			Total:        total,
			Sale:         sale,
			Rate:         p.SellingPrice,
			Amount:       amount,
			ClosingStock: closing,
		}

		if !showOpening {
			item.OpeningStock = 0
			item.Total = receipt
			item.ClosingStock = receipt - sale
		}

		items = append(items, item)
	}

	return items
}

// filterBySizes filters items by selected sizes
func (s *PurchaReportService) filterBySizes(items []reportModels.PurchaReportItem, sizes []string) []reportModels.PurchaReportItem {
	sizeSet := make(map[string]bool)
	for _, size := range sizes {
		sizeSet[size] = true
	}

	var filtered []reportModels.PurchaReportItem
	for _, item := range items {
		if sizeSet[item.Size] {
			filtered = append(filtered, item)
		}
	}
	return filtered
}

// organizeReport organizes items by view mode
func (s *PurchaReportService) organizeReport(
	items []reportModels.PurchaReportItem,
	shop models.Shop,
	req reportModels.PurchaReportRequest,
) *reportModels.PurchaReportResponse {
	// Group by size
	sizeGroups := make(map[string][]reportModels.PurchaReportItem)
	for _, item := range items {
		sizeGroups[item.Size] = append(sizeGroups[item.Size], item)
	}

	var pages []reportModels.PurchaReportSizePage

	for _, size := range reportModels.SizeOrder {
		sizeItems, exists := sizeGroups[size]
		if !exists || len(sizeItems) == 0 {
			continue
		}

		page := s.buildSizePage(sizeItems, size, req.ViewMode)
		pages = append(pages, page)
	}

	// Handle any sizes not in SizeOrder
	for size, sizeItems := range sizeGroups {
		found := false
		for _, s := range reportModels.SizeOrder {
			if s == size {
				found = true
				break
			}
		}
		if !found && len(sizeItems) > 0 {
			page := s.buildSizePage(sizeItems, size, req.ViewMode)
			pages = append(pages, page)
		}
	}

	// Calculate grand totals
	response := &reportModels.PurchaReportResponse{
		ShopID:         shop.ID,
		ShopName:       shop.Name,
		ReportDate:     req.Date,
		GeneratedAt:    time.Now(),
		CategoryFilter: req.CategoryFilter,
		ViewMode:       req.ViewMode,
		ShowOpening:    req.ShowOpening,
		Pages:          pages,
	}

	for _, page := range pages {
		response.TotalOpening += page.GrandOpening
		response.TotalReceipt += page.GrandReceipt
		response.TotalStock += page.GrandTotal
		response.TotalSale += page.GrandSale
		response.TotalAmount += page.GrandAmount
		response.TotalClosing += page.GrandClosing
		response.TotalItems += page.ItemCount
	}

	return response
}

// buildSizePage builds a page for a specific size
func (s *PurchaReportService) buildSizePage(items []reportModels.PurchaReportItem, size, viewMode string) reportModels.PurchaReportSizePage {
	page := reportModels.PurchaReportSizePage{
		Size: size,
	}

	if viewMode == "category" {
		// Group by category
		catGroups := make(map[string][]reportModels.PurchaReportItem)
		for _, item := range items {
			catGroups[item.CategoryName] = append(catGroups[item.CategoryName], item)
		}

		// Sort categories by order
		var catNames []string
		for name := range catGroups {
			catNames = append(catNames, name)
		}
		sort.Slice(catNames, func(i, j int) bool {
			return reportModels.GetCategoryOrder(catNames[i]) < reportModels.GetCategoryOrder(catNames[j])
		})

		globalSno := 1
		for _, catName := range catNames {
			catItems := catGroups[catName]

			// Sort by rate within category
			sort.Slice(catItems, func(i, j int) bool {
				return catItems[i].Rate < catItems[j].Rate
			})

			cat := reportModels.PurchaReportCategory{
				CategoryName: catName,
				SortOrder:    reportModels.GetCategoryOrder(catName),
			}

			for i := range catItems {
				catItems[i].SerialNo = globalSno
				globalSno++
				cat.Items = append(cat.Items, catItems[i])
				cat.TotalOpening += catItems[i].OpeningStock
				cat.TotalReceipt += catItems[i].Receipt
				cat.TotalStock += catItems[i].Total
				cat.TotalSale += catItems[i].Sale
				cat.TotalAmount += catItems[i].Amount
				cat.TotalClosing += catItems[i].ClosingStock
			}
			cat.ItemCount = len(catItems)

			page.Categories = append(page.Categories, cat)
			page.GrandOpening += cat.TotalOpening
			page.GrandReceipt += cat.TotalReceipt
			page.GrandTotal += cat.TotalStock
			page.GrandSale += cat.TotalSale
			page.GrandAmount += cat.TotalAmount
			page.GrandClosing += cat.TotalClosing
			page.ItemCount += cat.ItemCount
		}
	} else {
		// Price-wise: flat list sorted by rate
		sort.Slice(items, func(i, j int) bool {
			return items[i].Rate < items[j].Rate
		})

		cat := reportModels.PurchaReportCategory{
			CategoryName: "All Products",
		}

		for i := range items {
			items[i].SerialNo = i + 1
			cat.Items = append(cat.Items, items[i])
			cat.TotalOpening += items[i].OpeningStock
			cat.TotalReceipt += items[i].Receipt
			cat.TotalStock += items[i].Total
			cat.TotalSale += items[i].Sale
			cat.TotalAmount += items[i].Amount
			cat.TotalClosing += items[i].ClosingStock
		}
		cat.ItemCount = len(items)

		page.Categories = append(page.Categories, cat)
		page.GrandOpening = cat.TotalOpening
		page.GrandReceipt = cat.TotalReceipt
		page.GrandTotal = cat.TotalStock
		page.GrandSale = cat.TotalSale
		page.GrandAmount = cat.TotalAmount
		page.GrandClosing = cat.TotalClosing
		page.ItemCount = cat.ItemCount
	}

	return page
}

// contains checks if a string is in a slice
func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

package handlers

// PrintPurchaseRegister renders a purchase as a print-friendly HTML page
// ("Bahishara") that mirrors the inventory page sort order. Operators save
// the page to PDF via the browser's print dialog; the same HTML can be
// rendered headlessly to PDF later if/when we wire that up server-side.
//
// Sort order (matches the Inventory list screen):
//
//   1. Category name        — alphabetical (A-Z), case-insensitive
//   2. Rate (unit_price)    — ascending within category (cheapest at top)
//   3. Display name         — COALESCE(display_name, name) ascending
//                              within each rate band
//
// Tenant safety: every query filters on tenant_id pulled from the gin
// context (handles the uuid.UUID + string forms set by the gateway and the
// service-direct middleware respectively).
//
// Route is mounted in routes.go under the existing inventory group:
//
//   inventory.GET("/purchases/:id/print", inventoryHandlers.PrintPurchaseRegister)
//
// The `?layout=inventory` query param is accepted but currently the only
// supported layout, so it is not gated on. Future layouts (vendor-grouped,
// category-paged) will reuse this same endpoint.

import (
	"fmt"
	"html"
	"html/template"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// printPurchaseRow is the flat shape we feed into the HTML template.
// It carries everything the operator wants to see at a glance — brand,
// size, rate, MRP, case/bottle counts, line total and per-line duty.
type printPurchaseRow struct {
	CategoryName string
	BrandName    string
	Size         string
	Rate         float64
	MRP          float64
	Cases        int
	Bottles      int
	Amount       float64
	Duty         float64
}

// purchaseHeader is the small top-of-page block (shop, vendor, totals).
type purchaseHeader struct {
	ShopName       string
	PurchaseNumber string
	VendorName     string
	PurchaseDate   string
	ReceiptNo      string
	TotalAmount    float64
	TotalCases     int
	TotalBottles   int
}

// printPurchaseTemplateData is the full payload passed to the html/template.
// Rows is already sorted; CategoryGroups are pre-computed group boundaries
// so the template can render category banners between rows without doing
// any logic itself.
type printPurchaseTemplateData struct {
	Header        purchaseHeader
	CategoryRows  []categoryRowGroup
	GeneratedAt   string
}

// categoryRowGroup is one category's slice of the table.
// The template renders a "── BEER ──" banner row above each group's items.
type categoryRowGroup struct {
	CategoryName string
	Rows         []printPurchaseRow
}

// extractTenantID is a tiny adapter for the dual-form `tenant_id` value
// kept in the gin context. The auth middleware sometimes stores it as
// uuid.UUID and sometimes as string (depending on whether the request
// came through the gateway or hit the service directly), and every
// handler that filters by tenant has to handle both forms — see
// /var/www/liquorpro/internal/sales/handlers/sales_handlers.go:1060.
func extractTenantID(c *gin.Context) (uuid.UUID, bool) {
	raw, exists := c.Get("tenant_id")
	if !exists {
		return uuid.Nil, false
	}
	if u, ok := raw.(uuid.UUID); ok {
		return u, true
	}
	if s, ok := raw.(string); ok {
		parsed, err := uuid.Parse(s)
		if err != nil {
			return uuid.Nil, false
		}
		return parsed, true
	}
	return uuid.Nil, false
}

// PrintPurchaseRegister handles GET /api/inventory/purchases/:id/print.
// Returns text/html the operator can save as PDF via browser print.
func (h *InventoryHandlers) PrintPurchaseRegister(c *gin.Context) {
	idStr := c.Param("id")
	purchaseID, err := uuid.Parse(idStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid purchase ID"})
		return
	}

	tenantID, ok := extractTenantID(c)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Tenant ID not found"})
		return
	}

	// Layout param accepted but not gated — only "inventory" supported today.
	layout := strings.ToLower(strings.TrimSpace(c.Query("layout")))
	if layout == "" {
		layout = "inventory"
	}

	db := h.purchaseService.DB()

	// 1) Pull purchase header + vendor + shop. Tenant-scoped.
	var purchase models.StockPurchase
	if err := db.
		Preload("Vendor").
		Preload("Shop").
		Where("id = ? AND tenant_id = ?", purchaseID, tenantID).
		First(&purchase).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "purchase not found"})
		return
	}

	// 2) Pull items joined to product + category in a single query so the
	// sort happens DB-side. We over-select so the row builder has every
	// field it needs without a second round-trip per item.
	type rawRow struct {
		PurchaseItemID uuid.UUID `gorm:"column:purchase_item_id"`
		Quantity       int       `gorm:"column:quantity"`
		UnitPrice      float64   `gorm:"column:unit_price"`
		TotalPrice     float64   `gorm:"column:total_price"`
		DutyFee        float64   `gorm:"column:duty_fee"`
		ProductID      uuid.UUID `gorm:"column:product_id"`
		ProductName    string    `gorm:"column:product_name"`
		DisplayName    string    `gorm:"column:display_name"`
		ProductSize    string    `gorm:"column:product_size"`
		ProductMRP     float64   `gorm:"column:product_mrp"`
		CategoryID     uuid.UUID `gorm:"column:category_id"`
		CategoryName   string    `gorm:"column:category_name"`
	}

	var raws []rawRow
	if err := db.
		Table("stock_purchase_items AS pi").
		Select(`
			pi.id              AS purchase_item_id,
			pi.quantity        AS quantity,
			pi.unit_price      AS unit_price,
			pi.total_price     AS total_price,
			pi.duty_fee        AS duty_fee,
			p.id               AS product_id,
			p.name             AS product_name,
			COALESCE(p.display_name, '') AS display_name,
			COALESCE(p.size, '')         AS product_size,
			COALESCE(p.mrp, 0)           AS product_mrp,
			p.category_id      AS category_id,
			COALESCE(c.name, '') AS category_name
		`).
		Joins("JOIN products p ON p.id = pi.product_id").
		Joins("LEFT JOIN categories c ON c.id = p.category_id").
		Where("pi.purchase_id = ? AND pi.tenant_id = ?", purchaseID, tenantID).
		Scan(&raws).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to load purchase items: " + err.Error()})
		return
	}

	// 3) Sort items: category ASC, rate ASC within category, display name
	// ASC within rate band. Done in Go (after the DB load) so the comparator
	// is one place — matches what the Flutter inventory list does too.
	rows := make([]printPurchaseRow, 0, len(raws))
	for _, r := range raws {
		displayLabel := r.DisplayName
		if strings.TrimSpace(displayLabel) == "" {
			displayLabel = r.ProductName
		}
		categoryName := r.CategoryName
		if strings.TrimSpace(categoryName) == "" {
			categoryName = "Uncategorised"
		}
		// Cases / bottles split — assume 12 bottles per case (matches the
		// inventory + DSE convention used everywhere else in the app).
		// Fractional cases shown as "0.5 c + 6 b" via the Bottles field
		// holding the leftover bottles.
		cases := r.Quantity / 12
		bottles := r.Quantity - cases*12
		rows = append(rows, printPurchaseRow{
			CategoryName: categoryName,
			BrandName:    displayLabel,
			Size:         r.ProductSize,
			Rate:         r.UnitPrice,
			MRP:          r.ProductMRP,
			Cases:        cases,
			Bottles:      bottles,
			Amount:       r.TotalPrice,
			Duty:         r.DutyFee,
		})
	}

	sort.SliceStable(rows, func(i, j int) bool {
		ci := strings.ToLower(rows[i].CategoryName)
		cj := strings.ToLower(rows[j].CategoryName)
		if ci != cj {
			return ci < cj
		}
		if rows[i].Rate != rows[j].Rate {
			return rows[i].Rate < rows[j].Rate
		}
		return strings.ToLower(rows[i].BrandName) < strings.ToLower(rows[j].BrandName)
	})

	// 4) Group rows by category for the template (banner rows between
	// categories). Stable sort guarantees adjacent grouping above.
	var groups []categoryRowGroup
	var totalCases, totalBottles int
	var totalAmount float64
	for _, row := range rows {
		if len(groups) == 0 || groups[len(groups)-1].CategoryName != row.CategoryName {
			groups = append(groups, categoryRowGroup{CategoryName: row.CategoryName})
		}
		idx := len(groups) - 1
		groups[idx].Rows = append(groups[idx].Rows, row)
		totalCases += row.Cases
		totalBottles += row.Bottles
		totalAmount += row.Amount
	}

	shopName := ""
	if purchase.Shop != nil {
		shopName = purchase.Shop.Name
	}
	vendorName := ""
	if purchase.Vendor != nil {
		vendorName = purchase.Vendor.Name
	}

	data := printPurchaseTemplateData{
		Header: purchaseHeader{
			ShopName:       shopName,
			PurchaseNumber: purchase.PurchaseNumber,
			VendorName:     vendorName,
			PurchaseDate:   purchase.PurchaseDate.Format("02 Jan 2006"),
			ReceiptNo:      purchase.ReceiptNo,
			TotalAmount:    purchase.TotalAmount,
			TotalCases:     totalCases,
			TotalBottles:   totalBottles,
		},
		CategoryRows: groups,
		GeneratedAt:  time.Now().Format("02 Jan 2006 15:04"),
	}
	// Override the header total with the sum-of-rows when the stored
	// total_amount is zero (older purchases). Keeps the printed bottom
	// total honest even if a bookkeeping field was never written.
	if data.Header.TotalAmount == 0 && totalAmount > 0 {
		data.Header.TotalAmount = totalAmount
	}

	tmpl, err := template.New("bahishara").Funcs(template.FuncMap{
		"money": func(v float64) string { return fmt.Sprintf("%.2f", v) },
		"safe":  func(s string) template.HTML { return template.HTML(html.EscapeString(s)) },
	}).Parse(printPurchaseHTML)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "template parse failed: " + err.Error()})
		return
	}

	c.Header("Content-Type", "text/html; charset=utf-8")
	c.Status(http.StatusOK)
	if err := tmpl.Execute(c.Writer, data); err != nil {
		// Best-effort — once we've started writing the body we can't
		// rewrite the status, just log via gin.
		_ = c.Error(err)
		return
	}
}

// printPurchaseHTML is the embedded template. Self-contained — no external
// CSS/JS, so it prints identically whether opened from disk, served over
// HTTP, or fed to headless Chrome later. Monospace numbers keep columns
// aligned in the printed register.
const printPurchaseHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Bahishara — {{.Header.PurchaseNumber}}</title>
<style>
  @page { margin: 1cm; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: #111; margin: 0; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  .meta { font-size: 11px; color: #444; margin-bottom: 12px; }
  .meta strong { color: #111; }
  table { width: 100%; border-collapse: collapse; font-size: 11px; }
  th, td { border-bottom: 1px solid #ddd; padding: 4px 6px; text-align: left; vertical-align: top; }
  th { background: #f3f3f3; font-weight: 600; border-bottom: 1px solid #999; }
  td.num, th.num { text-align: right; font-family: "SF Mono", "Menlo", "Consolas", "Liberation Mono", monospace; }
  tr.cat-banner td { background: #222; color: #fff; font-weight: 700; letter-spacing: 1px; padding: 6px; font-size: 10px; }
  tfoot td { font-weight: 700; border-top: 2px solid #111; border-bottom: none; background: #fafafa; }
  .footer-meta { margin-top: 12px; font-size: 10px; color: #666; text-align: right; }
  @media print {
    a { color: inherit; text-decoration: none; }
    tr { page-break-inside: avoid; }
  }
</style>
</head>
<body>
  <h1>Purchase Register — {{.Header.PurchaseNumber}}</h1>
  <div class="meta">
    <div><strong>Shop:</strong> {{.Header.ShopName}}</div>
    <div><strong>Vendor:</strong> {{.Header.VendorName}}</div>
    <div><strong>Date:</strong> {{.Header.PurchaseDate}}{{if .Header.ReceiptNo}} &nbsp;·&nbsp; <strong>Receipt:</strong> {{.Header.ReceiptNo}}{{end}}</div>
    <div><strong>Total:</strong> &#8377;{{money .Header.TotalAmount}}</div>
  </div>
  <table>
    <thead>
      <tr>
        <th>Brand</th>
        <th>Size</th>
        <th class="num">Rate (&#8377;)</th>
        <th class="num">MRP (&#8377;)</th>
        <th class="num">Cases</th>
        <th class="num">Bottles</th>
        <th class="num">Amount</th>
        <th class="num">Duty</th>
      </tr>
    </thead>
    <tbody>
    {{range .CategoryRows}}
      <tr class="cat-banner"><td colspan="8">── {{.CategoryName}} ──</td></tr>
      {{range .Rows}}
      <tr>
        <td>{{.BrandName}}</td>
        <td>{{.Size}}</td>
        <td class="num">{{money .Rate}}</td>
        <td class="num">{{money .MRP}}</td>
        <td class="num">{{.Cases}}</td>
        <td class="num">{{.Bottles}}</td>
        <td class="num">{{money .Amount}}</td>
        <td class="num">{{money .Duty}}</td>
      </tr>
      {{end}}
    {{end}}
    </tbody>
    <tfoot>
      <tr>
        <td colspan="4">Total</td>
        <td class="num">{{.Header.TotalCases}}</td>
        <td class="num">{{.Header.TotalBottles}}</td>
        <td class="num">{{money .Header.TotalAmount}}</td>
        <td class="num"></td>
      </tr>
    </tfoot>
  </table>
  <div class="footer-meta">Generated {{.GeneratedAt}}</div>
</body>
</html>`

package models

import (
	"time"

	"github.com/google/uuid"
)

// PurchaReportRequest contains the request parameters for generating a purcha report
type PurchaReportRequest struct {
	ShopID         uuid.UUID `form:"shop_id" binding:"required"`
	Date           time.Time `form:"date" time_format:"2006-01-02"`
	CategoryFilter string    `form:"category_filter"` // "non_beer", "beer", "all"
	ViewMode       string    `form:"view_mode"`       // "category", "price", "size"
	Sizes          []string  `form:"sizes"`           // ["90ML", "180ML", "375ML", "750ML"]
	ShowOpening    bool      `form:"show_opening"`
	BlankRows      int       `form:"blank_rows"`
}

// PurchaReportItem represents a single product row in the report
type PurchaReportItem struct {
	SerialNo     int       `json:"serial_no"`
	ProductID    uuid.UUID `json:"product_id"`
	BrandName    string    `json:"brand_name"`
	ProductName  string    `json:"product_name"`
	Size         string    `json:"size"`
	CategoryName string    `json:"category_name"`

	// Stock columns matching register format
	OpeningStock int     `json:"opening_stock"` // Column 1: Opening
	Receipt      int     `json:"receipt"`       // Column 2: Receipt (today's purchases)
	Total        int     `json:"total"`         // Column 3: Opening + Receipt
	Sale         int     `json:"sale"`          // Column 4: Today's sales
	Rate         float64 `json:"rate"`          // Column 5: Selling price
	Amount       float64 `json:"amount"`        // Column 6: Sale * Rate
	ClosingStock int     `json:"closing_stock"` // Column 7: Total - Sale
}

// PurchaReportCategory represents a category grouping with items and subtotals
type PurchaReportCategory struct {
	CategoryName string             `json:"category_name"`
	SortOrder    int                `json:"sort_order"`
	Items        []PurchaReportItem `json:"items"`

	// Subtotals for this category
	TotalOpening int     `json:"total_opening"`
	TotalReceipt int     `json:"total_receipt"`
	TotalStock   int     `json:"total_stock"`
	TotalSale    int     `json:"total_sale"`
	TotalAmount  float64 `json:"total_amount"`
	TotalClosing int     `json:"total_closing"`
	ItemCount    int     `json:"item_count"`
}

// PurchaReportSizePage represents a page for a specific size (e.g., 180ML)
type PurchaReportSizePage struct {
	Size       string                 `json:"size"`
	Categories []PurchaReportCategory `json:"categories"`

	// Grand totals for this size page
	GrandOpening int     `json:"grand_opening"`
	GrandReceipt int     `json:"grand_receipt"`
	GrandTotal   int     `json:"grand_total"`
	GrandSale    int     `json:"grand_sale"`
	GrandAmount  float64 `json:"grand_amount"`
	GrandClosing int     `json:"grand_closing"`
	ItemCount    int     `json:"item_count"`
}

// PurchaReportResponse is the full report response
type PurchaReportResponse struct {
	// Header information
	ShopID      uuid.UUID `json:"shop_id"`
	ShopName    string    `json:"shop_name"`
	ReportDate  time.Time `json:"report_date"`
	GeneratedAt time.Time `json:"generated_at"`

	// Report options applied
	CategoryFilter string `json:"category_filter"`
	ViewMode       string `json:"view_mode"`
	ShowOpening    bool   `json:"show_opening"`

	// Report data - organized by size pages
	Pages []PurchaReportSizePage `json:"pages"`

	// Overall grand totals
	TotalOpening int     `json:"total_opening"`
	TotalReceipt int     `json:"total_receipt"`
	TotalStock   int     `json:"total_stock"`
	TotalSale    int     `json:"total_sale"`
	TotalAmount  float64 `json:"total_amount"`
	TotalClosing int     `json:"total_closing"`
	TotalItems   int     `json:"total_items"`
}

// ProductWithDetails holds product info joined with brand and category
type ProductWithDetails struct {
	ID           uuid.UUID
	Name         string
	Size         string
	SellingPrice float64
	BrandName    string
	CategoryName string
	CurrentStock int
}

// CategoryOrder defines the display order for categories
var CategoryOrder = map[string]int{
	"Whisky": 1,
	"Rum":    2,
	"Vodka":  3,
	"Wine":   4,
	"Brandy": 5,
	"IMFL":   6,
	"Beer":   99,
}

// SizeOrder defines the display order for sizes
var SizeOrder = []string{
	"90ML",
	"180ML",
	"375ML",
	"750ML",
	"500ML",
	"650ML",
	"1L",
	"2L",
}

// GetCategoryOrder returns the sort order for a category name
func GetCategoryOrder(categoryName string) int {
	if order, exists := CategoryOrder[categoryName]; exists {
		return order
	}
	return 50 // Default for unknown categories
}

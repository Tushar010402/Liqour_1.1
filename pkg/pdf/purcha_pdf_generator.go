package pdf

import (
	"bytes"
	"fmt"

	"github.com/jung-kurt/gofpdf"
	reportModels "github.com/liquorpro/go-backend/internal/sales/models"
)

// PurchaPDFGenerator generates PDF reports for purcha (daily sales register)
type PurchaPDFGenerator struct{}

// NewPurchaPDFGenerator creates a new PDF generator
func NewPurchaPDFGenerator() *PurchaPDFGenerator {
	return &PurchaPDFGenerator{}
}

// GeneratePDF creates a PDF from the purcha report
func (g *PurchaPDFGenerator) GeneratePDF(report *reportModels.PurchaReportResponse) ([]byte, error) {
	pdf := gofpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(8, 8, 8)
	pdf.SetAutoPageBreak(true, 10)

	for _, page := range report.Pages {
		pdf.AddPage()
		g.renderHeader(pdf, report, page.Size)
		g.renderTable(pdf, page, report.ShowOpening)
	}

	var buf bytes.Buffer
	if err := pdf.Output(&buf); err != nil {
		return nil, err
	}

	return buf.Bytes(), nil
}

// renderHeader renders the page header
func (g *PurchaPDFGenerator) renderHeader(pdf *gofpdf.Fpdf, report *reportModels.PurchaReportResponse, size string) {
	// Title
	pdf.SetFont("Arial", "B", 14)
	pdf.CellFormat(194, 8, fmt.Sprintf("SALE RECEIPT - %s", size), "", 1, "C", false, 0, "")

	// Shop and Date line
	pdf.SetFont("Arial", "", 10)
	pdf.CellFormat(65, 6, fmt.Sprintf("Shop: %s", report.ShopName), "", 0, "L", false, 0, "")
	pdf.CellFormat(64, 6, "", "", 0, "C", false, 0, "") // Hindi text placeholder
	pdf.CellFormat(65, 6, fmt.Sprintf("Date: %s", report.ReportDate.Format("02/01/2006")), "", 1, "R", false, 0, "")

	pdf.Ln(3)
}

// renderTable renders the main table with data
func (g *PurchaPDFGenerator) renderTable(pdf *gofpdf.Fpdf, page reportModels.PurchaReportSizePage, showOpening bool) {
	// Column widths: S.No(10), Brand(58), Open(15), Rcpt(15), Total(15), Sale(15), Rate(17), Amt(22), Close(17)
	widths := []float64{10, 58, 15, 15, 15, 15, 17, 22, 17}
	headers := []string{"S.No", "Brand Name", "Open", "Rcpt", "Total", "Sale", "Rate", "Amount", "Close"}

	if !showOpening {
		// Adjust widths when opening is hidden
		headers = []string{"S.No", "Brand Name", "", "Rcpt", "Total", "Sale", "Rate", "Amount", "Close"}
	}

	for _, cat := range page.Categories {
		// Category header
		pdf.SetFillColor(224, 224, 224) // Light gray
		pdf.SetFont("Arial", "B", 9)
		pdf.CellFormat(194, 6, cat.CategoryName, "1", 1, "L", true, 0, "")

		// Table header
		pdf.SetFillColor(25, 118, 210) // Blue
		pdf.SetTextColor(255, 255, 255)
		pdf.SetFont("Arial", "B", 8)

		for i, h := range headers {
			pdf.CellFormat(widths[i], 5, h, "1", 0, "C", true, 0, "")
		}
		pdf.Ln(-1)

		// Reset text color
		pdf.SetTextColor(0, 0, 0)
		pdf.SetFont("Arial", "", 8)

		// Data rows
		for _, item := range cat.Items {
			// Alternate row colors
			if item.SerialNo%2 == 0 {
				pdf.SetFillColor(245, 245, 245)
			} else {
				pdf.SetFillColor(255, 255, 255)
			}

			pdf.CellFormat(widths[0], 5, fmt.Sprintf("%d", item.SerialNo), "1", 0, "C", true, 0, "")

			// Brand name - bold
			pdf.SetFont("Arial", "B", 8)
			brandName := item.BrandName
			if len(brandName) > 28 {
				brandName = brandName[:28] + "..."
			}
			pdf.CellFormat(widths[1], 5, brandName, "1", 0, "L", true, 0, "")
			pdf.SetFont("Arial", "", 8)

			// Opening
			if showOpening {
				pdf.CellFormat(widths[2], 5, fmt.Sprintf("%d", item.OpeningStock), "1", 0, "C", true, 0, "")
			} else {
				pdf.CellFormat(widths[2], 5, "", "1", 0, "C", true, 0, "")
			}

			// Receipt, Total, Sale
			pdf.CellFormat(widths[3], 5, g.formatInt(item.Receipt), "1", 0, "C", true, 0, "")
			pdf.CellFormat(widths[4], 5, g.formatInt(item.Total), "1", 0, "C", true, 0, "")
			pdf.CellFormat(widths[5], 5, g.formatInt(item.Sale), "1", 0, "C", true, 0, "")

			// Rate - bold
			pdf.SetFont("Arial", "B", 8)
			pdf.CellFormat(widths[6], 5, fmt.Sprintf("%.0f", item.Rate), "1", 0, "C", true, 0, "")
			pdf.SetFont("Arial", "", 8)

			// Amount
			pdf.CellFormat(widths[7], 5, g.formatFloat(item.Amount), "1", 0, "R", true, 0, "")

			// Closing
			pdf.CellFormat(widths[8], 5, g.formatInt(item.ClosingStock), "1", 0, "C", true, 0, "")
			pdf.Ln(-1)
		}

		// Add blank rows for manual entries
		pdf.SetFillColor(255, 255, 255)
		for i := 0; i < 3; i++ {
			sno := len(cat.Items) + i + 1
			pdf.CellFormat(widths[0], 5, fmt.Sprintf("%d", sno), "1", 0, "C", false, 0, "")
			for j := 1; j < 9; j++ {
				pdf.CellFormat(widths[j], 5, "", "1", 0, "C", false, 0, "")
			}
			pdf.Ln(-1)
		}

		// Category subtotal
		pdf.SetFillColor(187, 222, 251) // Light blue
		pdf.SetFont("Arial", "B", 8)
		pdf.CellFormat(widths[0]+widths[1], 5, fmt.Sprintf("%s Subtotal", cat.CategoryName), "1", 0, "L", true, 0, "")

		if showOpening {
			pdf.CellFormat(widths[2], 5, fmt.Sprintf("%d", cat.TotalOpening), "1", 0, "C", true, 0, "")
		} else {
			pdf.CellFormat(widths[2], 5, "", "1", 0, "C", true, 0, "")
		}
		pdf.CellFormat(widths[3], 5, fmt.Sprintf("%d", cat.TotalReceipt), "1", 0, "C", true, 0, "")
		pdf.CellFormat(widths[4], 5, fmt.Sprintf("%d", cat.TotalStock), "1", 0, "C", true, 0, "")
		pdf.CellFormat(widths[5], 5, fmt.Sprintf("%d", cat.TotalSale), "1", 0, "C", true, 0, "")
		pdf.CellFormat(widths[6], 5, "", "1", 0, "C", true, 0, "")
		pdf.CellFormat(widths[7], 5, fmt.Sprintf("%.0f", cat.TotalAmount), "1", 0, "R", true, 0, "")
		pdf.CellFormat(widths[8], 5, fmt.Sprintf("%d", cat.TotalClosing), "1", 0, "C", true, 0, "")
		pdf.Ln(-1)
		pdf.SetFont("Arial", "", 8)

		pdf.Ln(2)
	}

	// Grand total
	g.renderGrandTotal(pdf, page, widths, showOpening)
}

// renderGrandTotal renders the grand total row
func (g *PurchaPDFGenerator) renderGrandTotal(pdf *gofpdf.Fpdf, page reportModels.PurchaReportSizePage, widths []float64, showOpening bool) {
	pdf.SetFillColor(13, 71, 161) // Dark blue
	pdf.SetTextColor(255, 255, 255)
	pdf.SetFont("Arial", "B", 9)

	pdf.CellFormat(widths[0]+widths[1], 6, "GRAND TOTAL", "1", 0, "L", true, 0, "")

	if showOpening {
		pdf.CellFormat(widths[2], 6, fmt.Sprintf("%d", page.GrandOpening), "1", 0, "C", true, 0, "")
	} else {
		pdf.CellFormat(widths[2], 6, "", "1", 0, "C", true, 0, "")
	}
	pdf.CellFormat(widths[3], 6, fmt.Sprintf("%d", page.GrandReceipt), "1", 0, "C", true, 0, "")
	pdf.CellFormat(widths[4], 6, fmt.Sprintf("%d", page.GrandTotal), "1", 0, "C", true, 0, "")
	pdf.CellFormat(widths[5], 6, fmt.Sprintf("%d", page.GrandSale), "1", 0, "C", true, 0, "")
	pdf.CellFormat(widths[6], 6, "", "1", 0, "C", true, 0, "")
	pdf.CellFormat(widths[7], 6, fmt.Sprintf("%.0f", page.GrandAmount), "1", 0, "R", true, 0, "")
	pdf.CellFormat(widths[8], 6, fmt.Sprintf("%d", page.GrandClosing), "1", 0, "C", true, 0, "")
	pdf.Ln(-1)

	pdf.SetTextColor(0, 0, 0)
}

// formatInt formats an integer, returning empty string for zero
func (g *PurchaPDFGenerator) formatInt(n int) string {
	if n == 0 {
		return ""
	}
	return fmt.Sprintf("%d", n)
}

// formatFloat formats a float, returning empty string for zero
func (g *PurchaPDFGenerator) formatFloat(n float64) string {
	if n == 0 {
		return ""
	}
	return fmt.Sprintf("%.0f", n)
}

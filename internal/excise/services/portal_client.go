package services

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/liquorpro/go-backend/internal/excise/models"
)

// PortalClient handles communication with UP Excise portal
type PortalClient struct {
	baseURL    string
	apiKey     string
	httpClient *http.Client
}

// PortalReportPayload represents the data format for portal submission
type PortalReportPayload struct {
	LicenseNumber        string                 `json:"license_number"`
	ShopName             string                 `json:"shop_name"`
	ReportDate           string                 `json:"report_date"`
	OpeningStock         map[string]interface{} `json:"opening_stock"`
	StockLifted          map[string]interface{} `json:"stock_lifted"`
	Sales                map[string]interface{} `json:"sales"`
	Returns              map[string]interface{} `json:"returns"`
	ClosingStock         map[string]interface{} `json:"closing_stock"`
	ConsiderationFeePaid float64                `json:"consideration_fee_paid"`
	CashDeposited        float64                `json:"cash_deposited"`
	Timestamp            string                 `json:"timestamp"`
}

// PortalResponse represents the response from UP Excise portal
type PortalResponse struct {
	Success        bool   `json:"success"`
	Message        string `json:"message"`
	SMSConfirmation string `json:"sms_confirmation"`
	ReferenceNumber string `json:"reference_number"`
	ErrorCode      string `json:"error_code,omitempty"`
}

// NewPortalClient creates a new portal client
func NewPortalClient(baseURL, apiKey string) *PortalClient {
	return &PortalClient{
		baseURL: baseURL,
		apiKey:  apiKey,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// UploadDailyReport uploads a daily report to the UP Excise portal
func (c *PortalClient) UploadDailyReport(report *models.ExciseDailyReport) (string, error) {
	// Format report for portal
	payload, err := c.FormatReportForPortal(report)
	if err != nil {
		return "", fmt.Errorf("failed to format report: %w", err)
	}

	// Send to portal
	response, err := c.sendToPortal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to send to portal: %w", err)
	}

	if !response.Success {
		return "", fmt.Errorf("portal rejected report: %s (code: %s)", response.Message, response.ErrorCode)
	}

	log.Printf("Report uploaded successfully. SMS: %s, Ref: %s",
		response.SMSConfirmation, response.ReferenceNumber)

	return response.SMSConfirmation, nil
}

// FormatReportForPortal converts internal report format to portal format
func (c *PortalClient) FormatReportForPortal(report *models.ExciseDailyReport) (*PortalReportPayload, error) {
	// TODO: Get actual shop and license details from database
	// For now, using placeholder data

	payload := &PortalReportPayload{
		LicenseNumber:        "LICENSE-PLACEHOLDER", // Should be fetched from license table
		ShopName:             "SHOP-PLACEHOLDER",    // Should be fetched from shop table
		ReportDate:           report.ReportDate.Format("2006-01-02"),
		OpeningStock:         c.formatStockBreakdown(report.OpeningStock),
		StockLifted:          c.formatStockBreakdown(report.StockLifted),
		Sales:                c.formatStockBreakdown(report.Sales),
		Returns:              c.formatStockBreakdown(report.Returns),
		ClosingStock:         c.formatStockBreakdown(report.ClosingStock),
		ConsiderationFeePaid: report.ConsiderationFeePaid,
		CashDeposited:        0, // TODO: Get from cash_deposit table
		Timestamp:            time.Now().Format(time.RFC3339),
	}

	return payload, nil
}

// formatStockBreakdown converts StockBreakdown to portal format
func (c *PortalClient) formatStockBreakdown(breakdown models.StockBreakdown) map[string]interface{} {
	return map[string]interface{}{
		"country_liquor": c.formatBottleEntries(breakdown.CountryLiquor),
		"imfl":           c.formatBottleEntries(breakdown.IMFL),
		"beer":           c.formatBottleEntries(breakdown.Beer),
		"wine":           c.formatBottleEntries(breakdown.Wine),
		"total_bottles":  breakdown.TotalBottles,
		"total_value":    breakdown.TotalValue,
	}
}

// formatBottleEntries converts bottle entries to portal format
func (c *PortalClient) formatBottleEntries(entries []models.BottleEntry) []map[string]interface{} {
	result := make([]map[string]interface{}, len(entries))
	for i, entry := range entries {
		result[i] = map[string]interface{}{
			"product_id":     entry.ProductID,
			"product_name":   entry.ProductName,
			"quantity":       entry.Quantity,
			"unit_price":     entry.UnitPrice,
			"security_codes": entry.SecurityCodes,
		}
	}
	return result
}

// sendToPortal sends the payload to UP Excise portal
func (c *PortalClient) sendToPortal(payload *PortalReportPayload) (*PortalResponse, error) {
	// Marshal payload to JSON
	jsonData, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal payload: %w", err)
	}

	log.Printf("Sending report to portal: %s", string(jsonData))

	// Create request
	url := fmt.Sprintf("%s/api/daily-reports", c.baseURL)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))
	req.Header.Set("X-Source", "LiquorPro")

	// Send request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	// Read response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	log.Printf("Portal response (status %d): %s", resp.StatusCode, string(body))

	// Check status code
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return nil, fmt.Errorf("portal returned status %d: %s", resp.StatusCode, string(body))
	}

	// Parse response
	var portalResp PortalResponse
	if err := json.Unmarshal(body, &portalResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &portalResp, nil
}

// CheckUploadStatus checks the status of a previously uploaded report
func (c *PortalClient) CheckUploadStatus(referenceNumber string) (*PortalResponse, error) {
	url := fmt.Sprintf("%s/api/daily-reports/status/%s", c.baseURL, referenceNumber)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("portal returned status %d: %s", resp.StatusCode, string(body))
	}

	var portalResp PortalResponse
	if err := json.Unmarshal(body, &portalResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return &portalResp, nil
}

// GetSMSConfirmation retrieves SMS confirmation for a report
func (c *PortalClient) GetSMSConfirmation(licenseNumber, reportDate string) (string, error) {
	url := fmt.Sprintf("%s/api/daily-reports/sms-confirmation", c.baseURL)

	payload := map[string]string{
		"license_number": licenseNumber,
		"report_date":    reportDate,
	}

	jsonData, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("failed to marshal payload: %w", err)
	}

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("portal returned status %d: %s", resp.StatusCode, string(body))
	}

	var portalResp PortalResponse
	if err := json.Unmarshal(body, &portalResp); err != nil {
		return "", fmt.Errorf("failed to parse response: %w", err)
	}

	if !portalResp.Success {
		return "", errors.New(portalResp.Message)
	}

	return portalResp.SMSConfirmation, nil
}

// TestConnection tests the connection to the UP Excise portal
func (c *PortalClient) TestConnection() error {
	url := fmt.Sprintf("%s/api/health", c.baseURL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.apiKey))

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to connect to portal: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("portal health check failed (status %d): %s", resp.StatusCode, string(body))
	}

	log.Println("Successfully connected to UP Excise portal")
	return nil
}

// MockPortalClient creates a mock client for testing (doesn't actually call portal)
type MockPortalClient struct {
	shouldFail bool
}

func NewMockPortalClient(shouldFail bool) *MockPortalClient {
	return &MockPortalClient{
		shouldFail: shouldFail,
	}
}

func (m *MockPortalClient) UploadDailyReport(report *models.ExciseDailyReport) (string, error) {
	if m.shouldFail {
		return "", errors.New("mock upload failure")
	}

	// Generate mock SMS confirmation
	smsConfirmation := fmt.Sprintf("SMS-%s-%d",
		report.ReportDate.Format("20060102"),
		time.Now().Unix()%10000)

	log.Printf("Mock upload successful. SMS: %s", smsConfirmation)
	return smsConfirmation, nil
}

func (m *MockPortalClient) FormatReportForPortal(report *models.ExciseDailyReport) (*PortalReportPayload, error) {
	payload := &PortalReportPayload{
		LicenseNumber:        "MOCK-LICENSE-001",
		ShopName:             "Mock Shop",
		ReportDate:           report.ReportDate.Format("2006-01-02"),
		ConsiderationFeePaid: report.ConsiderationFeePaid,
		Timestamp:            time.Now().Format(time.RFC3339),
	}
	return payload, nil
}

func (m *MockPortalClient) CheckUploadStatus(referenceNumber string) (*PortalResponse, error) {
	if m.shouldFail {
		return nil, errors.New("mock status check failure")
	}

	return &PortalResponse{
		Success:         true,
		Message:         "Report uploaded successfully",
		SMSConfirmation: "SMS-MOCK-1234",
		ReferenceNumber: referenceNumber,
	}, nil
}

func (m *MockPortalClient) TestConnection() error {
	if m.shouldFail {
		return errors.New("mock connection failure")
	}
	log.Println("Mock portal connection successful")
	return nil
}

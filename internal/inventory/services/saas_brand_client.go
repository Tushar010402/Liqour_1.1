package services

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"
)

const (
	maxRetries     = 3
	retryDelay     = 1 * time.Second
	requestTimeout = 30 * time.Second
)

// SaaSBrandClient handles communication with SaaS service for brand templates
type SaaSBrandClient struct {
	baseURL    string
	httpClient *http.Client
	logger     *zap.Logger
}

// NewSaaSBrandClient creates a new SaaS brand client
func NewSaaSBrandClient(saasServiceURL string, logger *zap.Logger) *SaaSBrandClient {
	return &SaaSBrandClient{
		baseURL: saasServiceURL,
		httpClient: &http.Client{
			Timeout: requestTimeout,
		},
		logger: logger,
	}
}

// doRequestWithRetry performs HTTP request with exponential backoff retry logic
func (c *SaaSBrandClient) doRequestWithRetry(req *http.Request) (*http.Response, error) {
	var lastErr error

	for attempt := 0; attempt < maxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff: wait retryDelay * 2^(attempt-1)
			waitTime := retryDelay * time.Duration(1<<uint(attempt-1))
			c.logger.Info("Retrying SaaS service request",
				zap.Int("attempt", attempt+1),
				zap.Int("max_retries", maxRetries),
				zap.Duration("wait_time", waitTime))
			time.Sleep(waitTime)
		}

		resp, err := c.httpClient.Do(req)
		if err == nil && resp.StatusCode < 500 {
			// Success or client error (4xx) - don't retry client errors
			return resp, nil
		}

		// Log error and prepare for retry
		if err != nil {
			lastErr = fmt.Errorf("request failed: %w", err)
			c.logger.Warn("SaaS service request failed",
				zap.Error(err),
				zap.Int("attempt", attempt+1))
		} else {
			// Server error (5xx)
			lastErr = fmt.Errorf("server error: status %d", resp.StatusCode)
			c.logger.Warn("SaaS service returned server error",
				zap.Int("status_code", resp.StatusCode),
				zap.Int("attempt", attempt+1))
			resp.Body.Close()
		}
	}

	return nil, fmt.Errorf("max retries exceeded: %w", lastErr)
}

// Brand template structures from SaaS service
type SaaSBrandTemplate struct {
	ID            uuid.UUID               `json:"id"`
	Name          string                  `json:"name"`
	Description   string                  `json:"description"`
	Picture       string                  `json:"picture"`
	IsActive      bool                    `json:"is_active"`
	SortOrder     int                     `json:"sort_order"`
	BrandVariants []SaaSBrandVariant      `json:"brand_variants,omitempty"`
	IsOnboarded   bool                    `json:"is_onboarded"` // True if any variant is onboarded for tenant
	CreatedAt     interface{}             `json:"created_at"`
	UpdatedAt     interface{}             `json:"updated_at"`
}

type SaaSBrandVariant struct {
	ID             uuid.UUID        `json:"id"`
	BrandID        uuid.UUID        `json:"brand_id"`
	CategoryID     uuid.UUID        `json:"category_id"`
	SubcategoryID  *uuid.UUID       `json:"subcategory_id"`
	Size           string           `json:"size"`
	AlcoholContent float64          `json:"alcohol_content"`
	Picture        string           `json:"picture"`
	GovernmentDuty float64          `json:"government_duty"`
	BuyingPrice    float64          `json:"buying_price"`
	SellingPrice   float64          `json:"selling_price"`
	MRP            float64          `json:"mrp"`
	Description    string           `json:"description"`
	Barcode        string           `json:"barcode"`
	HSNCode        string           `json:"hsn_code"`
	IsActive       bool             `json:"is_active"`
	SortOrder      int              `json:"sort_order"`
	IsOnboarded    bool             `json:"is_onboarded"` // True if this variant exists in tenant's products
	Category       *SaaSCategory    `json:"category,omitempty"`
	Subcategory    *SaaSSubcategory `json:"subcategory,omitempty"`
	CreatedAt      interface{}      `json:"created_at"`
	UpdatedAt      interface{}      `json:"updated_at"`
}

type SaaSCategory struct {
	ID          uuid.UUID   `json:"id"`
	Name        string      `json:"name"`
	Description string      `json:"description"`
	IsActive    bool        `json:"is_active"`
	SortOrder   int         `json:"sort_order"`
	CreatedAt   interface{} `json:"created_at"`
	UpdatedAt   interface{} `json:"updated_at"`
}

type SaaSSubcategory struct {
	ID          uuid.UUID   `json:"id"`
	CategoryID  uuid.UUID   `json:"category_id"`
	Name        string      `json:"name"`
	Description string      `json:"description"`
	IsActive    bool        `json:"is_active"`
	SortOrder   int         `json:"sort_order"`
	CreatedAt   interface{} `json:"created_at"`
	UpdatedAt   interface{} `json:"updated_at"`
}

// GetAllBrandTemplates fetches all brand templates from SaaS service
func (c *SaaSBrandClient) GetAllBrandTemplates(includeVariants bool) ([]SaaSBrandTemplate, error) {
	url := fmt.Sprintf("%s/api/internal/brands?include_variants=%v&active_only=true", c.baseURL, includeVariants)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Use retry logic
	resp, err := c.doRequestWithRetry(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch brand templates: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("SaaS service returned status %d: %s", resp.StatusCode, string(body))
	}

	var response struct {
		Data []SaaSBrandTemplate `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return response.Data, nil
}

// GetBrandTemplate fetches a specific brand template by ID
func (c *SaaSBrandClient) GetBrandTemplate(brandID uuid.UUID) (*SaaSBrandTemplate, error) {
	url := fmt.Sprintf("%s/api/internal/brands/%s", c.baseURL, brandID.String())

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Use retry logic
	resp, err := c.doRequestWithRetry(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch brand template: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("SaaS service returned status %d: %s", resp.StatusCode, string(body))
	}

	var response struct {
		Data SaaSBrandTemplate `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &response.Data, nil
}

// GetCategories fetches all brand categories from SaaS service
func (c *SaaSBrandClient) GetCategories() ([]SaaSCategory, error) {
	url := fmt.Sprintf("%s/api/internal/brands/categories", c.baseURL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch categories: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("SaaS service returned status %d: %s", resp.StatusCode, string(body))
	}

	var response struct {
		Data []SaaSCategory `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return response.Data, nil
}

// GetSubcategories fetches all brand subcategories from SaaS service
func (c *SaaSBrandClient) GetSubcategories() ([]SaaSSubcategory, error) {
	url := fmt.Sprintf("%s/api/internal/brands/subcategories", c.baseURL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch subcategories: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("SaaS service returned status %d: %s", resp.StatusCode, string(body))
	}

	var response struct {
		Data []SaaSSubcategory `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return response.Data, nil
}

package services

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

// SaaSBrandClient handles fetching brand templates from SaaS service
type SaaSBrandClient struct {
	baseURL    string
	httpClient *http.Client
	logger     *logrus.Logger
}

// NewSaaSBrandClient creates a new SaaS brand client
func NewSaaSBrandClient(logger *logrus.Logger) *SaaSBrandClient {
	// Get SaaS service URL from environment or use default
	saasURL := os.Getenv("SERVICES_SAAS_URL")
	if saasURL == "" {
		saasURL = os.Getenv("SAAS_SERVICE_URL") // Fallback to old env var name
	}
	if saasURL == "" {
		saasURL = "http://saas:8095" // Default to Docker service name
	}

	return &SaaSBrandClient{
		baseURL: saasURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		logger: logger,
	}
}

// SaaSBrandTemplate represents a brand from SaaS admin
type SaaSBrandTemplate struct {
	ID                    uuid.UUID          `json:"id"`
	Name                  string             `json:"name"`
	DisplayName           string             `json:"display_name"`
	DisplayNameBoldStart  *int               `json:"display_name_bold_start,omitempty"`
	DisplayNameBoldLength *int               `json:"display_name_bold_length,omitempty"`
	Description           string             `json:"description"`
	Picture               string             `json:"picture"`
	IsActive              bool               `json:"is_active"`
	Variants              []SaaSBrandVariant `json:"brand_variants,omitempty"`
}

// SaaSBrandVariant represents a brand variant from SaaS admin
type SaaSBrandVariant struct {
	ID             uuid.UUID  `json:"id"`
	BrandID        uuid.UUID  `json:"brand_id"`
	CategoryID     uuid.UUID  `json:"category_id"`
	SubcategoryID  *uuid.UUID `json:"subcategory_id"`
	Size           string     `json:"size"`
	AlcoholContent float64    `json:"alcohol_content"`
	GovernmentDuty float64    `json:"government_duty"`
	BuyingPrice    float64    `json:"buying_price"`
	SellingPrice   float64    `json:"selling_price"`
	MRP            float64    `json:"mrp"`
	Barcode        string     `json:"barcode"`
}

// GetAllBrandTemplates fetches all active brand templates
func (c *SaaSBrandClient) GetAllBrandTemplates() ([]SaaSBrandTemplate, error) {
	url := fmt.Sprintf("%s/api/internal/brands?include_variants=true&active_only=true", c.baseURL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Warnf("Failed to fetch brand templates from SaaS service: %v", err)
		// Return empty list instead of error to allow OCR to continue
		return []SaaSBrandTemplate{}, nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		c.logger.Warnf("SaaS service returned status %d: %s", resp.StatusCode, string(body))
		return []SaaSBrandTemplate{}, nil
	}

	var response struct {
		Data []SaaSBrandTemplate `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	c.logger.Infof("Fetched %d brand templates from SaaS service", len(response.Data))
	return response.Data, nil
}

// SearchBrandByName searches for a brand by name with fuzzy matching
func (c *SaaSBrandClient) SearchBrandByName(brandName string) (*SaaSBrandTemplate, error) {
	brands, err := c.GetAllBrandTemplates()
	if err != nil {
		return nil, err
	}

	brandNameLower := strings.ToLower(strings.TrimSpace(brandName))

	// First try exact match on name or display_name
	for _, brand := range brands {
		if strings.ToLower(brand.Name) == brandNameLower ||
			(brand.DisplayName != "" && strings.ToLower(brand.DisplayName) == brandNameLower) {
			return &brand, nil
		}
	}

	// Then try contains match on name or display_name
	for _, brand := range brands {
		nameLower := strings.ToLower(brand.Name)
		displayNameLower := strings.ToLower(brand.DisplayName)
		if strings.Contains(nameLower, brandNameLower) ||
			strings.Contains(brandNameLower, nameLower) ||
			(brand.DisplayName != "" && (strings.Contains(displayNameLower, brandNameLower) ||
				strings.Contains(brandNameLower, displayNameLower))) {
			return &brand, nil
		}
	}

	// Finally try fuzzy match with common variations
	variations := c.generateBrandVariations(brandName)
	for _, variation := range variations {
		for _, brand := range brands {
			if strings.ToLower(brand.Name) == strings.ToLower(variation) {
				return &brand, nil
			}
		}
	}

	return nil, nil // No match found
}

// generateBrandVariations generates common variations of a brand name
func (c *SaaSBrandClient) generateBrandVariations(brandName string) []string {
	variations := []string{brandName}

	// Common replacements
	replacements := map[string][]string{
		"&": {"and"},
		"and": {"&"},
		"whisky": {"whiskey"},
		"whiskey": {"whisky"},
	}

	for old, news := range replacements {
		if strings.Contains(strings.ToLower(brandName), old) {
			for _, new := range news {
				variation := strings.ReplaceAll(strings.ToLower(brandName), old, new)
				variations = append(variations, variation)
			}
		}
	}

	return variations
}
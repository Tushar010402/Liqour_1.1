package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"go.uber.org/zap"
)

// InventoryClient handles communication with the inventory service
type InventoryClient struct {
	baseURL    string
	httpClient *http.Client
	logger     *zap.Logger
}

// NewInventoryClient creates a new inventory service client
func NewInventoryClient(config *config.Config, logger *zap.Logger) *InventoryClient {
	// Default inventory service port to 8082 if not configured
	inventoryPort := 8082

	return &InventoryClient{
		baseURL: fmt.Sprintf("http://localhost:%d", inventoryPort),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
		logger: logger,
	}
}

// ProductSyncRequest represents the request to sync products to inventory
type ProductSyncRequest struct {
	TenantID   uuid.UUID          `json:"tenant_id"`
	Categories []CategorySyncData `json:"categories"`
	Products   []ProductSyncData  `json:"products"`
	SyncType   string             `json:"sync_type"` // "onboarding", "update", "delete"
	Source     string             `json:"source"`    // "saas_brand_assignment"
}

type CategorySyncData struct {
	ID          uuid.UUID `json:"id"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	IsActive    bool      `json:"is_active"`
}

type ProductSyncData struct {
	ID             uuid.UUID `json:"id"`
	Name           string    `json:"name"`
	CategoryID     uuid.UUID `json:"category_id"`
	BrandName      string    `json:"brand_name"`
	Size           string    `json:"size"`
	AlcoholContent float64   `json:"alcohol_content"`
	BuyingPrice    float64   `json:"buying_price"`
	SellingPrice   float64   `json:"selling_price"`
	MRP            float64   `json:"mrp"`
	GovernmentDuty float64   `json:"government_duty"`
	Barcode        string    `json:"barcode"`
	HSNCode        string    `json:"hsn_code"`
	Description    string    `json:"description"`
	IsActive       bool      `json:"is_active"`
	InitialStock   int       `json:"initial_stock"` // Default stock to set
}

// SyncBrandsToInventory syncs assigned brands to tenant's inventory
func (c *InventoryClient) SyncBrandsToInventory(request ProductSyncRequest) error {
	// Prepare the request
	jsonData, err := json.Marshal(request)
	if err != nil {
		return fmt.Errorf("failed to marshal sync request: %w", err)
	}

	// Create HTTP request
	url := fmt.Sprintf("%s/api/tenant/%s/products/sync", c.baseURL, request.TenantID)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create HTTP request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Service", "saas-admin")

	// Send request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Error("Failed to sync brands to inventory", zap.Error(err), zap.String("tenant_id", request.TenantID.String()))
		return fmt.Errorf("failed to call inventory service: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		c.logger.Error("Inventory sync failed", zap.Int("status", resp.StatusCode), zap.String("tenant_id", request.TenantID.String()))
		return fmt.Errorf("inventory service returned status %d", resp.StatusCode)
	}

	c.logger.Info("Successfully synced brands to inventory",
		zap.String("tenant_id", request.TenantID.String()),
		zap.Int("products", len(request.Products)),
		zap.Int("categories", len(request.Categories)))

	return nil
}

// PrepareBrandSyncData converts SaaS brand data to inventory sync format
func (c *InventoryClient) PrepareBrandSyncData(tenantID uuid.UUID, brands []models.SaasBrand, variants []models.BrandVariant) ProductSyncRequest {
	// Collect unique categories
	categoryMap := make(map[uuid.UUID]CategorySyncData)

	// Prepare products from variants
	var products []ProductSyncData

	for _, variant := range variants {
		// Find the brand for this variant
		var brand *models.SaasBrand
		for _, b := range brands {
			if b.ID == variant.BrandID {
				brand = &b
				break
			}
		}

		if brand == nil {
			continue
		}

		// Add category if not already added
		if variant.Category != nil {
			categoryMap[variant.CategoryID] = CategorySyncData{
				ID:          variant.Category.ID,
				Name:        variant.Category.Name,
				Description: variant.Category.Description,
				IsActive:    variant.Category.IsActive,
			}
		}

		// Create product from variant
		product := ProductSyncData{
			ID:             variant.ID,
			Name:           fmt.Sprintf("%s - %s", brand.Name, variant.Size),
			CategoryID:     variant.CategoryID,
			BrandName:      brand.Name,
			Size:           variant.Size,
			AlcoholContent: variant.AlcoholContent,
			BuyingPrice:    variant.BuyingPrice,
			SellingPrice:   variant.SellingPrice,
			MRP:            variant.MRP,
			GovernmentDuty: variant.GovernmentDuty,
			Barcode:        variant.Barcode,
			HSNCode:        variant.HSNCode,
			Description:    variant.Description,
			IsActive:       variant.IsActive,
			InitialStock:   0, // Start with 0 stock - tenant will add manually
		}

		products = append(products, product)
	}

	// Convert category map to slice
	var categories []CategorySyncData
	for _, cat := range categoryMap {
		categories = append(categories, cat)
	}

	return ProductSyncRequest{
		TenantID:   tenantID,
		Categories: categories,
		Products:   products,
		SyncType:   "onboarding",
		Source:     "saas_brand_assignment",
	}
}

// NotifyInventoryOnBrandAssignment notifies inventory service when brands are assigned
func (c *InventoryClient) NotifyInventoryOnBrandAssignment(tenantID uuid.UUID, brandIDs []uuid.UUID, variantIDs []uuid.UUID) error {
	// This is a simpler notification that could trigger inventory service to pull data
	notification := map[string]interface{}{
		"tenant_id":   tenantID,
		"brand_ids":   brandIDs,
		"variant_ids": variantIDs,
		"action":      "brands_assigned",
		"timestamp":   time.Now(),
	}

	jsonData, err := json.Marshal(notification)
	if err != nil {
		return fmt.Errorf("failed to marshal notification: %w", err)
	}

	url := fmt.Sprintf("%s/api/tenant/%s/notifications/brand-assignment", c.baseURL, tenantID)
	req, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("failed to create notification request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Service", "saas-admin")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		c.logger.Warn("Failed to notify inventory service", zap.Error(err), zap.String("tenant_id", tenantID.String()))
		// Don't fail the brand assignment if notification fails
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		c.logger.Warn("Inventory notification failed", zap.Int("status", resp.StatusCode), zap.String("tenant_id", tenantID.String()))
	}

	return nil
}

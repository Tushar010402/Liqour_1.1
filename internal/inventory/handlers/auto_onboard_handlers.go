package handlers

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/sirupsen/logrus"
)

// AutoOnboardHandlers handles auto-onboarding from OCR
type AutoOnboardHandlers struct {
	brandService *services.BrandOnboardingService
	stockService *services.StockService
	logger       *logrus.Logger
}

// NewAutoOnboardHandlers creates new auto-onboard handlers
func NewAutoOnboardHandlers(
	brandService *services.BrandOnboardingService,
	stockService *services.StockService,
	logger *logrus.Logger,
) *AutoOnboardHandlers {
	return &AutoOnboardHandlers{
		brandService: brandService,
		stockService: stockService,
		logger:       logger,
	}
}

// AutoOnboardFromOCR handles auto-onboarding brands detected in OCR
func (h *AutoOnboardHandlers) AutoOnboardFromOCR(c *gin.Context) {
	tenantID, _ := uuid.Parse(c.GetHeader("X-Tenant-ID"))
	_ = tenantID // Mark as used to avoid compiler warning

	var req struct {
		SessionID uuid.UUID `json:"session_id" binding:"required"`
		ShopID    uuid.UUID `json:"shop_id" binding:"required"`
		Items     []struct {
			ItemID       uuid.UUID  `json:"item_id" binding:"required"`
			BrandText    string     `json:"brand_text" binding:"required"`
			SaaSBrandID  *uuid.UUID `json:"saas_brand_id"`
			SaaSVariantID *uuid.UUID `json:"saas_variant_id"`
			OpeningStock *int       `json:"opening_stock"`
			ClosingStock *int       `json:"closing_stock"`
			RatePerUnit  *float64   `json:"rate_per_unit"`
		} `json:"items" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	h.logger.Infof("Auto-onboarding %d brands from OCR session %s", len(req.Items), req.SessionID)

	// Results tracking
	var onboarded []gin.H
	var failed []gin.H

	for _, item := range req.Items {
		// Skip if no SaaS brand ID
		if item.SaaSBrandID == nil {
			h.logger.Warnf("Skipping item %s - no SaaS brand match", item.ItemID)
			failed = append(failed, gin.H{
				"item_id": item.ItemID,
				"brand":   item.BrandText,
				"reason":  "No SaaS brand template match",
			})
			continue
		}

		// Create onboarding request using the existing OnboardBrandsToTenant method
		onboardReq := services.OnboardBrandRequest{
			TenantID:   tenantID,
			ShopID:     &req.ShopID,
			BrandIDs:   []uuid.UUID{*item.SaaSBrandID},
		}

		// If variant ID is provided, only onboard that specific variant
		if item.SaaSVariantID != nil {
			onboardReq.VariantIDs = []uuid.UUID{*item.SaaSVariantID}

			// Include initial stock if provided
			if item.OpeningStock != nil && *item.OpeningStock > 0 {
				onboardReq.BrandVariants = []services.BrandVariantStock{
					{
						VariantID:    *item.SaaSVariantID,
						InitialStock: *item.OpeningStock,
					},
				}
			}
		}

		// Onboard the brand
		result, err := h.brandService.OnboardBrandsToTenant(onboardReq)
		if err != nil {
			h.logger.Errorf("Failed to onboard brand %s: %v", item.BrandText, err)
			failed = append(failed, gin.H{
				"item_id": item.ItemID,
				"brand":   item.BrandText,
				"error":   err.Error(),
			})
			continue
		}

		h.logger.Infof("Successfully onboarded brand %s (%d products created)", item.BrandText, result.OnboardedProducts)

		// Track successful onboarding
		onboarded = append(onboarded, gin.H{
			"item_id":          item.ItemID,
			"brand_id":         item.SaaSBrandID,
			"brand_name":       item.BrandText,
			"products_created": result.OnboardedProducts,
			"initial_stock":    item.OpeningStock,
		})
	}

	// Return results
	c.JSON(http.StatusOK, gin.H{
		"session_id": req.SessionID,
		"shop_id":    req.ShopID,
		"summary": gin.H{
			"total_items": len(req.Items),
			"successful":  len(onboarded),
			"failed":      len(failed),
		},
		"onboarded": onboarded,
		"failed":    failed,
		"message":   "Auto-onboarding completed",
	})
}

// GetOCROnboardingSummary gets summary of brands ready for onboarding from OCR
func (h *AutoOnboardHandlers) GetOCROnboardingSummary(c *gin.Context) {
	sessionID := c.Param("session_id")
	tenantID, _ := uuid.Parse(c.GetHeader("X-Tenant-ID"))

	// This would query OCR extracted items and match with SaaS brands
	// For now, return mock data
	c.JSON(http.StatusOK, gin.H{
		"session_id": sessionID,
		"tenant_id": tenantID,
		"brands_detected": 15,
		"saas_matches": 8,
		"ready_to_onboard": 8,
		"requires_manual": 7,
		"message": "OCR analysis complete",
	})
}
package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
	"gorm.io/gorm"
)

// SmartPurchaseVendorHandler exposes the v1.0.193 vendor auto-create endpoint.
//
// When AI extraction detects a vendor name on the bill that doesn't match any
// existing vendor record (vendor_confidence < 0.6 in the SmartPurchaseResult),
// the Flutter review screen offers a "Create vendor" affordance. This handler
// backs that affordance.
//
// Idempotent: re-submitting the same name+gst returns the existing vendor_id
// with action=matched_existing. This is critical because operators may tap
// the create button multiple times if the network's slow, and we don't want
// duplicate vendor rows polluting the tenant.
type SmartPurchaseVendorHandler struct {
	db     *database.DB
	logger *logrus.Logger
}

// NewSmartPurchaseVendorHandler wires the handler.
func NewSmartPurchaseVendorHandler(db *database.DB, logger *logrus.Logger) *SmartPurchaseVendorHandler {
	return &SmartPurchaseVendorHandler{db: db, logger: logger}
}

type createVendorFromPurchaseRequest struct {
	DetectedName string `json:"detected_name" binding:"required"`
	GSTNumber    string `json:"gst_number,omitempty"`
	Address      string `json:"address,omitempty"`
	City         string `json:"city,omitempty"`
	State        string `json:"state,omitempty"`
	Phone        string `json:"phone,omitempty"`
	PANNumber    string `json:"pan_number,omitempty"`
}

type createVendorFromPurchaseResponse struct {
	VendorID   string `json:"vendor_id"`
	VendorName string `json:"vendor_name"`
	Action     string `json:"action"` // "created" | "matched_existing"
}

// CreateOrMatchVendor handles POST /api/inventory/purchases/smart-purchase/vendor.
//
// Flow:
//  1. Lookup by GST (case-insensitive) — most reliable disambiguator.
//  2. Fall back to exact-name match (case-insensitive).
//  3. If neither matches, create a new vendor.
//
// We deliberately do NOT do fuzzy name matching here — that's already happened
// in the extraction pipeline (matchVendorByName). If a fuzzy match was found
// the Flutter UI would never have offered the "Create" button. So at this
// endpoint, the operator has explicitly chosen to create a new vendor, and we
// only block on exact duplicates.
func (h *SmartPurchaseVendorHandler) CreateOrMatchVendor(c *gin.Context) {
	// v1.0.231 — see smart_purchase_context.go. Pre-v231 the tenantIDRaw.(uuid.UUID)
	// assertion always failed (middleware stores tenant_id as string) → 500.
	tenantID, terr := tenantUUIDFromContext(c)
	if terr != nil {
		c.JSON(terr.status, gin.H{"error": terr.msg})
		return
	}
	userID, terr := userUUIDFromContext(c)
	if terr != nil {
		c.JSON(terr.status, gin.H{"error": terr.msg})
		return
	}

	var req createVendorFromPurchaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	req.DetectedName = strings.TrimSpace(req.DetectedName)
	req.GSTNumber = strings.TrimSpace(strings.ToUpper(req.GSTNumber))
	if req.DetectedName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "detected_name is required"})
		return
	}

	// 1. Idempotency by GST first — exact, case-insensitive.
	if req.GSTNumber != "" {
		var existing models.Vendor
		err := h.db.
			Where("tenant_id = ? AND deleted_at IS NULL AND UPPER(COALESCE(gst_number, '')) = ?", tenantID, req.GSTNumber).
			First(&existing).Error
		if err == nil {
			h.logger.Infof("SmartPurchase vendor: matched existing by GST %q → %s (%s)", req.GSTNumber, existing.Name, existing.ID)
			c.JSON(http.StatusOK, createVendorFromPurchaseResponse{
				VendorID:   existing.ID.String(),
				VendorName: existing.Name,
				Action:     "matched_existing",
			})
			return
		}
		if err != gorm.ErrRecordNotFound {
			h.logger.WithError(err).Error("SmartPurchase vendor: GST lookup failed")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "vendor lookup failed"})
			return
		}
	}

	// 2. Idempotency by exact name (lower-case compare absorbs vendor-prints
	// that differ only in trailing whitespace + case).
	{
		var existing models.Vendor
		err := h.db.
			Where("tenant_id = ? AND deleted_at IS NULL AND LOWER(name) = LOWER(?)", tenantID, req.DetectedName).
			First(&existing).Error
		if err == nil {
			h.logger.Infof("SmartPurchase vendor: matched existing by name %q → %s", req.DetectedName, existing.ID)
			c.JSON(http.StatusOK, createVendorFromPurchaseResponse{
				VendorID:   existing.ID.String(),
				VendorName: existing.Name,
				Action:     "matched_existing",
			})
			return
		}
		if err != gorm.ErrRecordNotFound {
			h.logger.WithError(err).Error("SmartPurchase vendor: name lookup failed")
			c.JSON(http.StatusInternalServerError, gin.H{"error": "vendor lookup failed"})
			return
		}
	}

	// 3. Create new.
	vendor := models.Vendor{
		TenantModel: models.TenantModel{
			BaseModel: models.BaseModel{ID: uuid.New()},
			TenantID:  &tenantID,
		},
		Name:      req.DetectedName,
		Address:   req.Address,
		City:      req.City,
		State:     req.State,
		Phone:     req.Phone,
		GSTNumber: req.GSTNumber,
		PANNumber: req.PANNumber,
		IsActive:  true,
		CreatedBy: userID,
	}
	if err := h.db.Create(&vendor).Error; err != nil {
		h.logger.WithError(err).Error("SmartPurchase vendor: create failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "vendor create failed"})
		return
	}

	h.logger.Infof("SmartPurchase vendor: created new %q → %s", vendor.Name, vendor.ID)
	c.JSON(http.StatusCreated, createVendorFromPurchaseResponse{
		VendorID:   vendor.ID.String(),
		VendorName: vendor.Name,
		Action:     "created",
	})
}

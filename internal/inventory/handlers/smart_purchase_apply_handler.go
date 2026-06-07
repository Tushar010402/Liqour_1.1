package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/sirupsen/logrus"
)

// SmartPurchaseApplyHandler exposes POST /api/inventory/purchases/smart-purchase/apply.
//
// This is the operator-confirmed apply endpoint. Flutter posts the final
// review state (per-item product_id picks + cost + qty + AI metadata for
// learning) and we (a) write the stock_purchase rows, (b) capture all four
// learning signals (alias / negative-alias / shop rate / digit corrections).
//
// Distinct from the legacy /purchases POST handler because that one takes
// a pre-AI request shape and has no AI metadata to learn from. Keeping the
// two paths separate avoids muddling the legacy create-purchase contract.
type SmartPurchaseApplyHandler struct {
	service *services.SmartPurchaseService
	logger  *logrus.Logger
}

// NewSmartPurchaseApplyHandler wires the handler.
func NewSmartPurchaseApplyHandler(service *services.SmartPurchaseService, logger *logrus.Logger) *SmartPurchaseApplyHandler {
	return &SmartPurchaseApplyHandler{service: service, logger: logger}
}

// Apply handles POST /api/inventory/purchases/smart-purchase/apply.
//
// Request body: services.SmartPurchaseApplyRequest (JSON).
// Response: 201 Created with services.SmartPurchaseApplyResponse on success;
// 400 on bad request; 422 when an unconfirmed block-severity warning exists;
// 500 on DB failure.
func (h *SmartPurchaseApplyHandler) Apply(c *gin.Context) {
	if h.service == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase apply not configured"})
		return
	}
	// v1.0.231 — shared tenant/user UUID resolver. Pre-v231 this handler
	// type-asserted tenant_id to uuid.UUID which never matched the string
	// stored by the inventory middleware → 500 "Invalid tenant ID" on EVERY
	// apply. Symptom was hidden because chhotu's disambig step (same bug
	// class) blocked apply from being reached.
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

	var req services.SmartPurchaseApplyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// v1.0.216 — mandatory review gate. Re-derives blocking warnings from
	// the apply payload itself (math_fail / pack_size_violation / zero_cost
	// / duplicate_product) and matches them against UserConfirmedWarnings.
	// Rejected rows surface in the 422 body so Flutter can scroll-to + fix.
	gate := services.ValidatePurchaseApply(req.Items, req.UserConfirmedReconciliations)
	if len(gate.Rejected) > 0 && gate.Enforced {
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":         "Some rows still have unconfirmed warnings. Review them and try again.",
			"rejected_rows": gate.Rejected,
		})
		return
	}

	resp, err := h.service.ApplySmartPurchase(c.Request.Context(), tenantID, userID, req)
	if err != nil {
		// 2026-05-18 — image gate. A matched product created by AI Stock
		// Setup with no bottle photo blocks apply; 409 + the product list so
		// the app lets the operator photograph them inline and resubmit.
		// Mirrors the name-unverified mapping in inventory_handlers.go:658.
		if imgErr, ok := err.(*services.PurchaseImageRequiredError); ok {
			c.JSON(http.StatusConflict, gin.H{
				"error":                   "image_required",
				"message":                 imgErr.Error(),
				"image_required_products": imgErr.Products,
				"hint":                    "Attach a product photo for the listed items from the review row, then submit again.",
			})
			return
		}
		// v1.0.217 Track 8 — receipt dedup surfaces as 409 Conflict so
		// Flutter can render a friendly "already submitted" dialog with
		// a link to the existing purchase rather than a generic 500.
		if strings.HasPrefix(err.Error(), "duplicate_receipt:") {
			c.JSON(http.StatusConflict, gin.H{
				"error":            "duplicate_receipt",
				"message":          err.Error(),
				"hint":             "This invoice number was already applied at this shop within the past 7 days. If this is a different bill, change the invoice number and retry.",
			})
			return
		}
		h.logger.WithError(err).Error("SmartPurchase apply failed")
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, resp)
}

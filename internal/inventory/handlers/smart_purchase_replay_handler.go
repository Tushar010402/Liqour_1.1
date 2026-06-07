package handlers

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/inventory/services"
	"github.com/sirupsen/logrus"
)

// SmartPurchaseReplayHandler exposes the v1.0.193 W4.1 diagnostic endpoint:
//
//	POST /api/inventory/purchases/smart-purchase/replay/:job_id
//
// Re-runs the matcher against the persisted SmartPurchaseResult on the
// given job using current alias / shop-rate / shop-bias state, and returns
// counts of how many rows would now resolve differently. Read-only — does
// NOT mutate the job or write learning. Pure diagnostic for admin tooling
// to validate "are the corrections we taught moving the needle?".
//
// See services.ReplaySmartPurchaseMatcher for the limitations.
type SmartPurchaseReplayHandler struct {
	service *services.SmartPurchaseService
	logger  *logrus.Logger
}

// NewSmartPurchaseReplayHandler wires the handler.
func NewSmartPurchaseReplayHandler(service *services.SmartPurchaseService, logger *logrus.Logger) *SmartPurchaseReplayHandler {
	return &SmartPurchaseReplayHandler{service: service, logger: logger}
}

// Replay handles POST /api/inventory/purchases/smart-purchase/replay/:job_id.
//
// Response: 200 + SmartPurchaseReplayResponse on success.
// 400 on bad job_id; 401 on missing tenant; 404 on unknown job;
// 409 when job status is not done; 500 on internal error.
func (h *SmartPurchaseReplayHandler) Replay(c *gin.Context) {
	if h.service == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Smart Purchase replay not configured"})
		return
	}
	// v1.0.231 — fixed broken uuid.UUID assertion; see smart_purchase_context.go.
	tenantID, terr := tenantUUIDFromContext(c)
	if terr != nil {
		c.JSON(terr.status, gin.H{"error": terr.msg})
		return
	}

	jobIDStr := c.Param("job_id")
	if jobIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "job_id is required"})
		return
	}
	jobID, err := uuid.Parse(jobIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid job_id"})
		return
	}

	resp, err := h.service.ReplaySmartPurchaseMatcher(c.Request.Context(), jobID, tenantID)
	if err != nil {
		// Differentiate "not found" from "wrong status" from "internal".
		msg := err.Error()
		switch {
		case strings.Contains(msg, "not found"):
			c.JSON(http.StatusNotFound, gin.H{"error": msg})
		case strings.Contains(msg, "status is"):
			c.JSON(http.StatusConflict, gin.H{"error": msg})
		default:
			h.logger.WithError(err).Error("SmartPurchase replay failed")
			c.JSON(http.StatusInternalServerError, gin.H{"error": msg})
		}
		return
	}

	c.JSON(http.StatusOK, resp)
}

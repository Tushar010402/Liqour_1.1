package handlers

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/tips/services"
	"github.com/liquorpro/go-backend/pkg/shared/models"
)

// TipsHandler handles tip-related HTTP requests
type TipsHandler struct {
	service *services.TipsService
}

// NewTipsHandler creates a new tips handler
func NewTipsHandler(service *services.TipsService) *TipsHandler {
	return &TipsHandler{service: service}
}

// =====================================================
// Individual Tips
// =====================================================

// RecordTip records a new individual tip
// POST /api/tips
func (h *TipsHandler) RecordTip(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	var input struct {
		ShopID      uuid.UUID  `json:"shop_id" binding:"required"`
		SaleID      *uuid.UUID `json:"sale_id"`
		Amount      float64    `json:"amount" binding:"required,gt=0"`
		PaymentType string     `json:"payment_type" binding:"required,oneof=cash card upi"`
		Notes       string     `json:"notes"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tip := &models.TipTransaction{
		TenantID:    tenantID.(uuid.UUID),
		ShopID:      input.ShopID,
		RecipientID: userID.(uuid.UUID),
		SaleID:      input.SaleID,
		Amount:      input.Amount,
		PaymentType: input.PaymentType,
		TipType:     models.TipTypeIndividual,
		Notes:       input.Notes,
	}

	if err := h.service.RecordIndividualTip(c.Request.Context(), tip); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Tip recorded successfully",
		"tip":     tip,
	})
}

// GetMyTips gets tips for the authenticated user
// GET /api/tips/my
func (h *TipsHandler) GetMyTips(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	start, _ := time.Parse("2006-01-02", startDate)
	end, _ := time.Parse("2006-01-02", endDate)
	if end.IsZero() {
		end = time.Now()
	}
	if start.IsZero() {
		start = end.AddDate(0, -1, 0)
	}

	tips, err := h.service.GetTipsForRecipient(c.Request.Context(), tenantID.(uuid.UUID), userID.(uuid.UUID), start, end)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"tips": tips})
}

// =====================================================
// Tip Pools
// =====================================================

// CreatePool creates a new tip pool
// POST /api/tips/pools
func (h *TipsHandler) CreatePool(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	var input struct {
		ShopID             uuid.UUID `json:"shop_id" binding:"required"`
		Name               string    `json:"name" binding:"required"`
		DistributionMethod string    `json:"distribution_method" binding:"required,oneof=equal hours_worked sales_proportional custom"`
		DistributionDay    int       `json:"distribution_day"`
		IsActive           bool      `json:"is_active"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	pool := &models.TipPool{
		TenantID:           tenantID.(uuid.UUID),
		ShopID:             input.ShopID,
		Name:               input.Name,
		DistributionMethod: input.DistributionMethod,
		DistributionDay:    input.DistributionDay,
		IsActive:           input.IsActive,
	}

	if err := h.service.CreatePool(c.Request.Context(), pool, userID.(uuid.UUID)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Pool created successfully",
		"pool":    pool,
	})
}

// GetPools gets all tip pools for a shop
// GET /api/tips/pools
func (h *TipsHandler) GetPools(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	shopIDStr := c.Query("shop_id")

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id"})
		return
	}

	pools, err := h.service.GetPoolsForShop(c.Request.Context(), tenantID.(uuid.UUID), shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"pools": pools})
}

// GetPool gets a specific tip pool
// GET /api/tips/pools/:pool_id
func (h *TipsHandler) GetPool(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	poolID, err := uuid.Parse(c.Param("pool_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool_id"})
		return
	}

	pool, err := h.service.GetPool(c.Request.Context(), tenantID.(uuid.UUID), poolID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"pool": pool})
}

// AddPoolMember adds a member to a tip pool
// POST /api/tips/pools/:pool_id/members
func (h *TipsHandler) AddPoolMember(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	poolID, err := uuid.Parse(c.Param("pool_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool_id"})
		return
	}

	var input struct {
		UserID       uuid.UUID `json:"user_id" binding:"required"`
		SharePercent float64   `json:"share_percent"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.AddPoolMember(c.Request.Context(), tenantID.(uuid.UUID), poolID, input.UserID, input.SharePercent); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member added to pool"})
}

// RemovePoolMember removes a member from a tip pool
// DELETE /api/tips/pools/:pool_id/members/:user_id
func (h *TipsHandler) RemovePoolMember(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	poolID, err := uuid.Parse(c.Param("pool_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool_id"})
		return
	}

	userID, err := uuid.Parse(c.Param("user_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid user_id"})
		return
	}

	if err := h.service.RemovePoolMember(c.Request.Context(), tenantID.(uuid.UUID), poolID, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Member removed from pool"})
}

// AddToPool adds a tip to the pool
// POST /api/tips/pools/:pool_id/contribute
func (h *TipsHandler) AddToPool(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	poolID, err := uuid.Parse(c.Param("pool_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool_id"})
		return
	}

	var input struct {
		Amount      float64    `json:"amount" binding:"required,gt=0"`
		SaleID      *uuid.UUID `json:"sale_id"`
		PaymentType string     `json:"payment_type" binding:"required,oneof=cash card upi"`
		Notes       string     `json:"notes"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tip := &models.TipTransaction{
		TenantID:    tenantID.(uuid.UUID),
		PoolID:      &poolID,
		SaleID:      input.SaleID,
		Amount:      input.Amount,
		PaymentType: input.PaymentType,
		TipType:     models.TipTypePooled,
		Notes:       input.Notes,
	}

	if err := h.service.AddToPool(c.Request.Context(), tip, userID.(uuid.UUID)); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Tip added to pool",
		"tip":     tip,
	})
}

// =====================================================
// Distributions
// =====================================================

// CalculateDistribution calculates pool distribution preview
// GET /api/tips/pools/:pool_id/distribution/preview
func (h *TipsHandler) CalculateDistribution(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	poolID, err := uuid.Parse(c.Param("pool_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool_id"})
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	start, _ := time.Parse("2006-01-02", startDate)
	end, _ := time.Parse("2006-01-02", endDate)
	if end.IsZero() {
		end = time.Now()
	}
	if start.IsZero() {
		start = end.AddDate(0, 0, -7)
	}

	distributions, err := h.service.CalculateDistribution(c.Request.Context(), tenantID.(uuid.UUID), poolID, start, end)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"distributions": distributions})
}

// ExecuteDistribution executes pool distribution
// POST /api/tips/pools/:pool_id/distribution/execute
func (h *TipsHandler) ExecuteDistribution(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	poolID, err := uuid.Parse(c.Param("pool_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid pool_id"})
		return
	}

	var input struct {
		StartDate     time.Time `json:"start_date" binding:"required"`
		EndDate       time.Time `json:"end_date" binding:"required"`
		Distributions []struct {
			UserID       uuid.UUID `json:"user_id"`
			Amount       float64   `json:"amount"`
			SharePercent float64   `json:"share_percent"`
		} `json:"distributions" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var distributions []models.TipDistribution
	for _, d := range input.Distributions {
		distributions = append(distributions, models.TipDistribution{
			TenantID:     tenantID.(uuid.UUID),
			PoolID:       poolID,
			RecipientID:  d.UserID,
			Amount:       d.Amount,
			SharePercent: d.SharePercent,
		})
	}

	if err := h.service.ExecuteDistribution(c.Request.Context(), tenantID.(uuid.UUID), poolID, distributions, userID.(uuid.UUID), input.StartDate, input.EndDate); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Distribution executed successfully"})
}

// =====================================================
// Payouts
// =====================================================

// CreatePayoutBatch creates a new payout batch
// POST /api/tips/payouts/batch
func (h *TipsHandler) CreatePayoutBatch(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	var input struct {
		ShopID      uuid.UUID   `json:"shop_id" binding:"required"`
		RecipientID *uuid.UUID  `json:"recipient_id"`
		UserIDs     []uuid.UUID `json:"user_ids"`
		StartDate   time.Time   `json:"start_date" binding:"required"`
		EndDate     time.Time   `json:"end_date" binding:"required"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	batch, err := h.service.CreatePayoutBatch(c.Request.Context(), tenantID.(uuid.UUID), input.ShopID, input.UserIDs, userID.(uuid.UUID), input.StartDate, input.EndDate)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"message": "Payout batch created",
		"batch":   batch,
	})
}

// GetPayoutBatches gets payout batches
// GET /api/tips/payouts/batches
func (h *TipsHandler) GetPayoutBatches(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	shopIDStr := c.Query("shop_id")

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id"})
		return
	}

	batches, err := h.service.GetPayoutBatches(c.Request.Context(), tenantID.(uuid.UUID), shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"batches": batches})
}

// ProcessPayout processes a payout batch
// POST /api/tips/payouts/:batch_id/process
func (h *TipsHandler) ProcessPayout(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	userID, _ := c.Get("user_id")

	batchID, err := uuid.Parse(c.Param("batch_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid batch_id"})
		return
	}

	var input struct {
		PaymentMethod string `json:"payment_method" binding:"required,oneof=cash bank_transfer upi"`
		Reference     string `json:"reference"`
	}

	if err := c.ShouldBindJSON(&input); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := h.service.ProcessPayout(c.Request.Context(), tenantID.(uuid.UUID), batchID, userID.(uuid.UUID), input.PaymentMethod, input.Reference); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Payout processed successfully"})
}

// =====================================================
// Reports
// =====================================================

// GetTipsSummary gets tips summary report
// GET /api/tips/reports/summary
func (h *TipsHandler) GetTipsSummary(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	shopIDStr := c.Query("shop_id")

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id"})
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	start, _ := time.Parse("2006-01-02", startDate)
	end, _ := time.Parse("2006-01-02", endDate)
	if end.IsZero() {
		end = time.Now()
	}
	if start.IsZero() {
		start = end.AddDate(0, -1, 0)
	}

	summary, err := h.service.GetTipsSummary(c.Request.Context(), tenantID.(uuid.UUID), shopID, start, end)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, summary)
}

// GetTipsLeaderboard gets tips leaderboard
// GET /api/tips/reports/leaderboard
func (h *TipsHandler) GetTipsLeaderboard(c *gin.Context) {
	tenantID, _ := c.Get("tenant_id")
	shopIDStr := c.Query("shop_id")

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid shop_id"})
		return
	}

	startDate := c.Query("start_date")
	endDate := c.Query("end_date")

	start, _ := time.Parse("2006-01-02", startDate)
	end, _ := time.Parse("2006-01-02", endDate)
	if end.IsZero() {
		end = time.Now()
	}
	if start.IsZero() {
		start = end.AddDate(0, -1, 0)
	}

	leaderboard, err := h.service.GetTipsLeaderboard(c.Request.Context(), tenantID.(uuid.UUID), shopID, start, end, 10)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"leaderboard": leaderboard})
}

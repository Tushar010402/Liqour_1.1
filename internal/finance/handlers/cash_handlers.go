package handlers

import (
	"fmt"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/finance/services"
)

// CashHandlers handles all cash management endpoints
type CashHandlers struct {
	cashService         *services.CashService
	bankAccountService  *services.BankAccountService
	notificationService *services.NotificationService
}

// NewCashHandlers creates a new cash handlers instance
func NewCashHandlers(cashService *services.CashService, bankAccountService *services.BankAccountService) *CashHandlers {
	return &CashHandlers{
		cashService:         cashService,
		bankAccountService:  bankAccountService,
		notificationService: nil, // Will be set via SetNotificationService
	}
}

// SetNotificationService sets the notification service for sending push notifications
func (h *CashHandlers) SetNotificationService(notificationService *services.NotificationService) {
	h.notificationService = notificationService
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Balance Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// GetCashBalance godoc
// @Summary Get user's cash balance
// @Description Get current cash balance for authenticated user. If shop_id is provided, returns shop-specific balance. If shop_id is omitted, returns total balance across ALL shops.
// @Tags Cash
// @Accept json
// @Produce json
// @Param shop_id query string false "Shop ID (optional - omit to get total across all shops)"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/balance [get]
func (h *CashHandlers) GetCashBalance(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// shop_id is now OPTIONAL - if not provided, returns total balance across ALL shops
	shopIDStr := c.Query("shop_id")
	var shopID uuid.UUID
	if shopIDStr != "" {
		shopID, err = uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
	} else {
		shopID = uuid.Nil // Will sum across all shops
	}

	balance, err := h.cashService.GetCashBalance(c.Request.Context(), userID, shopID, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	response := gin.H{
		"user_id": userID,
		"balance": balance,
	}
	// Only include shop_id in response if it was specified
	if shopID != uuid.Nil {
		response["shop_id"] = shopID
	}

	c.JSON(http.StatusOK, response)
}

// GetCashHolding godoc
// @Summary Get detailed cash holding
// @Description Get complete cash holding record with user and shop details
// @Tags Cash
// @Accept json
// @Produce json
// @Param shop_id query string true "Shop ID"
// @Success 200 {object} models.CashHolding
// @Router /api/finance/cash/holding [get]
func (h *CashHandlers) GetCashHolding(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	shopIDStr := c.Query("shop_id")
	if shopIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "shop_id is required"})
		return
	}

	shopID, err := uuid.Parse(shopIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
		return
	}

	holding, err := h.cashService.GetCashHolding(c.Request.Context(), userID, shopID, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if holding == nil {
		c.JSON(http.StatusOK, gin.H{
			"user_id": userID,
			"shop_id": shopID,
			"balance": 0,
		})
		return
	}

	c.JSON(http.StatusOK, holding)
}

// GetTeamCashBalances godoc
// @Summary Get team cash balances
// @Description Get cash balances for all subordinates in the hierarchy (optionally filtered by shop)
// @Tags Cash
// @Accept json
// @Produce json
// @Param shop_id query string false "Shop ID (optional - omit to get balances across all shops)"
// @Success 200 {array} models.CashHolding
// @Router /api/finance/cash/team-balances [get]
func (h *CashHandlers) GetTeamBalances(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Get aggregated user-specific balances (sum across all shops per user)
	// shopID parameter is no longer used - kept for backward compatibility
	var shopID uuid.UUID // Always uuid.Nil for user-aggregated balances

	holdings, err := h.cashService.GetTeamCashBalances(c.Request.Context(), userID, shopID, tenantID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Transform holdings to team balance format expected by Flutter (user-specific, no shop info)
	teamBalances := make([]map[string]interface{}, 0, len(holdings))
	for _, holding := range holdings {
		balance := map[string]interface{}{
			"user_id":         holding.UserID,
			"current_balance": holding.CurrentBalance,
			"last_updated_at": holding.LastUpdatedAt,
		}

		// Add user info if available (flattened structure)
		if holding.User != nil {
			// Construct full name from FirstName and LastName
			userName := holding.User.FirstName
			if holding.User.LastName != "" {
				if userName != "" {
					userName += " " + holding.User.LastName
				} else {
					userName = holding.User.LastName
				}
			}
			if userName == "" {
				userName = holding.User.Username // Fallback to username
			}
			balance["user_name"] = userName
			balance["role"] = holding.User.Role
		} else {
			balance["user_name"] = "Unknown User"
			balance["role"] = "unknown"
		}

		teamBalances = append(teamBalances, balance)
	}

	c.JSON(http.StatusOK, gin.H{
		"team_balances": teamBalances,
		"count":         len(teamBalances),
	})
}

// GetTenantUsers godoc
// @Summary Get tenant users for cash requests
// @Description Get list of tenant users (NO cash amounts shown) - maintains hierarchical privacy
// @Tags Cash
// @Accept json
// @Produce json
// @Param shop_id query string false "Shop ID (optional - filter users by shop)"
// @Success 200 {array} services.TenantUserInfo
// @Router /api/finance/cash/tenant-users [get]
func (h *CashHandlers) GetTenantUsers(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Shop ID is optional
	shopIDStr := c.Query("shop_id")
	var shopID *uuid.UUID
	if shopIDStr != "" {
		parsed, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
		shopID = &parsed
	}

	users, err := h.cashService.GetTenantUsers(c.Request.Context(), userID, tenantID, shopID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Transform to simple JSON format for Flutter
	userList := make([]map[string]interface{}, 0, len(users))
	for _, user := range users {
		userMap := map[string]interface{}{
			"user_id":   user.UserID,
			"user_name": user.UserName,
			"role":      user.Role,
		}
		if user.ShopID != nil {
			userMap["shop_id"] = *user.ShopID
		}
		if user.ShopName != nil {
			userMap["shop_name"] = *user.ShopName
		}
		userList = append(userList, userMap)
	}

	c.JSON(http.StatusOK, gin.H{
		"users": userList,
		"count": len(userList),
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Collection Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// CollectCashRequest represents the request body for cash collection
type CollectCashRequest struct {
	FromUserID uuid.UUID  `json:"from_user_id" binding:"required"`
	ShopID     *uuid.UUID `json:"shop_id"` // Shop is optional
	Amount     float64    `json:"amount" binding:"required,gt=0"`
	Notes      string     `json:"notes"`
}

// RejectCollectionRequest represents the request body for rejecting a collection
type RejectCollectionRequest struct {
	Reason string `json:"reason" binding:"required"`
}

// CollectCash godoc
// @Summary Collect cash from subordinate
// @Description Collect cash from a subordinate user in the hierarchy
// @Tags Cash
// @Accept json
// @Produce json
// @Param request body CollectCashRequest true "Collection request"
// @Success 201 {object} models.CashCollection
// @Router /api/finance/cash/collect [post]
func (h *CashHandlers) CollectCash(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req CollectCashRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create collection request
	collectionReq := &services.CollectionRequest{
		FromUserID: req.FromUserID,
		ToUserID:   userID, // Current user is collecting
		ShopID:     req.ShopID,
		TenantID:   tenantID,
		Amount:     req.Amount,
		Notes:      req.Notes,
	}

	collection, err := h.cashService.CollectCash(c.Request.Context(), collectionReq, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, collection)
}

// ApproveCollectionRequest godoc
// @Summary Approve a pending cash collection request
// @Description Approve a cash collection request within 10-minute deadline
// @Tags Cash
// @Accept json
// @Produce json
// @Param id path string true "Collection ID"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/collections/{id}/approve [post]
func (h *CashHandlers) ApproveCollectionRequest(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	collectionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid collection ID"})
		return
	}

	// Get collection details before approval for notification
	collections, _ := h.cashService.GetCollections(c.Request.Context(), tenantID, map[string]interface{}{
		"id": collectionID,
	})

	err = h.cashService.ApproveCollection(c.Request.Context(), collectionID, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Send push notification to the user who initiated the collection
	if h.notificationService != nil && len(collections) > 0 {
		collection := collections[0]
		go func() {
			if err := h.notificationService.SendCollectionApproved(
				c.Request.Context(),
				collection.CreatedByID, // Who initiated the collection
				tenantID,
				collection.Amount,
				collectionID,
			); err != nil {
				log.Printf("⚠️ Failed to send collection approval notification: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "Collection approved successfully",
		"collection_id": collectionID,
		"approved_by":   userID,
		"approved_at":   time.Now().UTC(),
		"tenant_id":     tenantID,
	})
}

// RejectCollectionRequest godoc
// @Summary Reject a pending cash collection request
// @Description Reject a cash collection request with reason
// @Tags Cash
// @Accept json
// @Produce json
// @Param id path string true "Collection ID"
// @Param request body RejectCollectionRequest true "Rejection request"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/collections/{id}/reject [post]
func (h *CashHandlers) RejectCollectionRequest(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	collectionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid collection ID"})
		return
	}

	var req RejectCollectionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get collection details before rejection for notification
	collections, _ := h.cashService.GetCollections(c.Request.Context(), tenantID, map[string]interface{}{
		"id": collectionID,
	})

	err = h.cashService.RejectCollection(c.Request.Context(), collectionID, userID, req.Reason)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Send push notification to the user who initiated the collection
	if h.notificationService != nil && len(collections) > 0 {
		collection := collections[0]
		go func() {
			if err := h.notificationService.SendCollectionRejected(
				c.Request.Context(),
				collection.CreatedByID, // Who initiated the collection
				tenantID,
				req.Reason,
				collectionID,
			); err != nil {
				log.Printf("⚠️ Failed to send collection rejection notification: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "Collection rejected successfully",
		"collection_id": collectionID,
		"rejected_by":   userID,
		"rejected_at":   time.Now().UTC(),
		"reason":        req.Reason,
		"tenant_id":     tenantID,
	})
}

// GetPendingCollections godoc
// @Summary Get pending collection requests for current user
// @Description Get all pending collection requests that require approval by the current user
// @Tags Cash
// @Accept json
// @Produce json
// @Param shop_id query string false "Shop ID"
// @Success 200 {array} models.CashCollection
// @Router /api/finance/cash/collections/pending [get]
func (h *CashHandlers) GetPendingCollections(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters for pending collections TO current user
	filters := map[string]interface{}{
		"to_user_id": userID,
		"status":     "pending",
	}

	// Optional shop filter
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		shopID, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
		filters["shop_id"] = shopID
	}

	// Call ExpireOldCollections to ensure expired ones are marked
	h.cashService.ExpireOldCollections(c.Request.Context())

	collections, err := h.cashService.GetCollections(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"collections": collections,
		"count":       len(collections),
	})
}

// GetCollections godoc
// @Summary Get cash collections
// @Description Get list of cash collections with filters
// @Tags Cash
// @Accept json
// @Produce json
// @Param from_user_id query string false "From User ID"
// @Param to_user_id query string false "To User ID"
// @Param shop_id query string false "Shop ID"
// @Param status query string false "Status (pending/approved/rejected)"
// @Success 200 {array} models.CashCollection
// @Router /api/finance/cash/collections [get]
func (h *CashHandlers) GetCollections(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters
	filters := make(map[string]interface{})

	if fromUserID := c.Query("from_user_id"); fromUserID != "" {
		if id, err := uuid.Parse(fromUserID); err == nil {
			filters["from_user_id"] = id
		}
	}

	if toUserID := c.Query("to_user_id"); toUserID != "" {
		if id, err := uuid.Parse(toUserID); err == nil {
			filters["to_user_id"] = id
		}
	}

	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}

	collections, err := h.cashService.GetCollections(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"collections": collections,
		"count":       len(collections),
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Submission Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// SubmitCashRequest represents the request body for cash submission
type SubmitCashRequest struct {
	ShopID          *uuid.UUID `json:"shop_id"` // Shop is optional
	TotalAmount     float64    `json:"total_amount" binding:"required,gt=0"`
	Notes500        int        `json:"notes_500" binding:"gte=0"`
	Notes200        int        `json:"notes_200" binding:"gte=0"`
	Notes100        int        `json:"notes_100" binding:"gte=0"`
	Notes50         int        `json:"notes_50" binding:"gte=0"`
	Notes20         int        `json:"notes_20" binding:"gte=0"`
	Notes10         int        `json:"notes_10" binding:"gte=0"`
	BankAccountID   *uuid.UUID `json:"bank_account_id"`
	BankSlipNumber  string     `json:"bank_slip_number"`
	DepositDate     time.Time  `json:"deposit_date" binding:"required"`
	ReceiptPhotoURL string     `json:"receipt_photo_url" binding:"required"`
	Notes           string     `json:"notes"`
}

// SubmitCash godoc
// @Summary Submit cash to bank
// @Description Create a cash submission to bank with denomination breakdown
// @Tags Cash
// @Accept json
// @Produce json
// @Param request body SubmitCashRequest true "Submission request"
// @Success 201 {object} models.CashSubmission
// @Router /api/finance/cash/submit [post]
func (h *CashHandlers) SubmitCash(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req SubmitCashRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create submission request
	submissionReq := &services.SubmissionRequest{
		UserID:          userID,
		ShopID:          req.ShopID,
		TenantID:        tenantID,
		TotalAmount:     req.TotalAmount,
		Notes500:        req.Notes500,
		Notes200:        req.Notes200,
		Notes100:        req.Notes100,
		Notes50:         req.Notes50,
		Notes20:         req.Notes20,
		Notes10:         req.Notes10,
		BankAccountID:   req.BankAccountID,
		BankSlipNumber:  req.BankSlipNumber,
		DepositDate:     req.DepositDate,
		ReceiptPhotoURL: req.ReceiptPhotoURL,
		Notes:           req.Notes,
	}

	submission, err := h.cashService.SubmitCash(c.Request.Context(), submissionReq, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Return submission wrapped in object to match Flutter expectations
	c.JSON(http.StatusCreated, gin.H{
		"submission": submission,
		"message":    "Cash submission created successfully",
	})
}

// GetSubmissions godoc
// @Summary Get cash submissions
// @Description Get list of cash submissions with filters
// @Tags Cash
// @Accept json
// @Produce json
// @Param user_id query string false "User ID"
// @Param shop_id query string false "Shop ID"
// @Param status query string false "Status (pending/approved/rejected)"
// @Success 200 {array} models.CashSubmission
// @Router /api/finance/cash/submissions [get]
func (h *CashHandlers) GetSubmissions(c *gin.Context) {
	tenantID, _, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters
	filters := make(map[string]interface{})

	if userIDStr := c.Query("user_id"); userIDStr != "" {
		if id, err := uuid.Parse(userIDStr); err == nil {
			filters["user_id"] = id
		}
	}

	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}

	submissions, err := h.cashService.GetSubmissions(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"submissions": submissions,
		"count":       len(submissions),
	})
}

// ApproveSubmission godoc
// @Summary Approve cash submission
// @Description Approve a pending cash submission and link to bank account if specified
// @Tags Cash
// @Accept json
// @Produce json
// @Param id path string true "Submission ID"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/submissions/:id/approve [post]
func (h *CashHandlers) ApproveSubmission(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	submissionIDStr := c.Param("id")
	submissionID, err := uuid.Parse(submissionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid submission ID"})
		return
	}

	// Step 1: Approve the cash submission (deduct from user's cash balance)
	err = h.cashService.ApproveSubmission(c.Request.Context(), submissionID, userID, tenantID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Step 2: Link to bank account and record deposit (if bank account was specified)
	// Get submission to check if bank account ID was provided
	submissions, err := h.cashService.GetSubmissions(c.Request.Context(), tenantID, map[string]interface{}{
		"id": submissionID,
	})
	if err == nil && len(submissions) > 0 {
		submission := submissions[0]
		if submission.BankAccountID != nil {
			// Link submission to bank account and create deposit transaction
			if err := h.bankAccountService.LinkCashSubmissionToBank(
				c.Request.Context(),
				submissionID,
				*submission.BankAccountID,
				tenantID,
				userID,
			); err != nil {
				log.Printf("⚠️  Warning: Cash submission approved but bank deposit failed: %v", err)
				// Don't fail the entire operation - submission is already approved
				// Just log the error for manual investigation
				c.JSON(http.StatusOK, gin.H{
					"message":       "submission approved successfully (bank deposit failed - manual intervention required)",
					"submission_id": submissionID,
					"warning":       err.Error(),
				})
				return
			}
			log.Printf("✅ Cash submission approved and deposited to bank: ID %s, Account %s", submissionID, *submission.BankAccountID)
		}
	}

	// Send push notification to the user who submitted the cash
	if h.notificationService != nil && len(submissions) > 0 {
		submission := submissions[0]
		go func() {
			if err := h.notificationService.SendCashSubmissionApproved(
				c.Request.Context(),
				submission.UserID, // Who submitted the cash
				tenantID,
				submission.TotalAmount,
				submissionID,
			); err != nil {
				log.Printf("⚠️ Failed to send approval notification: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "submission approved successfully",
		"submission_id": submissionID,
	})
}

// RejectSubmissionRequest represents the request body for rejection
type RejectSubmissionRequest struct {
	Reason string `json:"reason" binding:"required"`
}

// RejectSubmission godoc
// @Summary Reject cash submission
// @Description Reject a pending cash submission with reason
// @Tags Cash
// @Accept json
// @Produce json
// @Param id path string true "Submission ID"
// @Param request body RejectSubmissionRequest true "Rejection reason"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/submissions/:id/reject [post]
func (h *CashHandlers) RejectSubmission(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	submissionIDStr := c.Param("id")
	submissionID, err := uuid.Parse(submissionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid submission ID"})
		return
	}

	var req RejectSubmissionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get submission details before rejection for notification
	submissions, _ := h.cashService.GetSubmissions(c.Request.Context(), tenantID, map[string]interface{}{
		"id": submissionID,
	})

	err = h.cashService.RejectSubmission(c.Request.Context(), submissionID, userID, tenantID, req.Reason)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Send push notification to the user who submitted the cash
	if h.notificationService != nil && len(submissions) > 0 {
		submission := submissions[0]
		go func() {
			if err := h.notificationService.SendCashSubmissionRejected(
				c.Request.Context(),
				submission.UserID, // Who submitted the cash
				tenantID,
				req.Reason,
				submissionID,
			); err != nil {
				log.Printf("⚠️ Failed to send rejection notification: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"message":       "submission rejected successfully",
		"submission_id": submissionID,
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash History Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// GetCashHistory godoc
// @Summary Get cash transaction history
// @Description Get paginated cash transaction history with filters
// @Tags Cash
// @Accept json
// @Produce json
// @Param user_id query string false "User ID"
// @Param shop_id query string false "Shop ID"
// @Param transaction_type query string false "Transaction type"
// @Param start_date query string false "Start date (YYYY-MM-DD)"
// @Param end_date query string false "End date (YYYY-MM-DD)"
// @Param limit query int false "Limit (default 50)"
// @Param offset query int false "Offset (default 0)"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/history [get]
func (h *CashHandlers) GetCashHistory(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse pagination
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	if limit > 100 {
		limit = 100 // Max limit
	}

	// Build filters
	filters := make(map[string]interface{})

	// Default: filter by current user (user-specific view)
	// Admin/Managers can override by passing user_id query param
	if userIDStr := c.Query("user_id"); userIDStr != "" {
		if id, err := uuid.Parse(userIDStr); err == nil {
			filters["user_id"] = id
		}
	} else {
		// No user_id provided - default to logged-in user's transactions
		filters["user_id"] = userID
	}

	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	if transactionType := c.Query("transaction_type"); transactionType != "" {
		filters["transaction_type"] = transactionType
	}

	if startDateStr := c.Query("start_date"); startDateStr != "" {
		if startDate, err := time.Parse("2006-01-02", startDateStr); err == nil {
			filters["start_date"] = startDate
		}
	}

	if endDateStr := c.Query("end_date"); endDateStr != "" {
		if endDate, err := time.Parse("2006-01-02", endDateStr); err == nil {
			filters["end_date"] = endDate
		}
	}

	transactions, total, err := h.cashService.GetCashHistory(c.Request.Context(), tenantID, filters, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"transactions": transactions,
		"total":        total,
		"limit":        limit,
		"offset":       offset,
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Cash Request Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// CreateCashRequestBody represents the request body for cash request
type CreateCashRequestBody struct {
	RequestedFromID uuid.UUID  `json:"requested_from_id" binding:"required"`
	ShopID          *uuid.UUID `json:"shop_id"` // Shop is optional - cash is user-specific
	Amount          float64    `json:"amount" binding:"required,gt=0"`
	Reason          string     `json:"reason"`
}

// CreateCashRequest godoc
// @Summary Create a cash request
// @Description Create a cash request from one user to another with 10-minute approval deadline
// @Tags Cash
// @Accept json
// @Produce json
// @Param request body CreateCashRequestBody true "Cash request"
// @Success 201 {object} models.CashRequest
// @Router /api/finance/cash/request [post]
func (h *CashHandlers) CreateCashRequest(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	var req CreateCashRequestBody
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Create request input
	requestInput := &services.CashRequestInput{
		RequesterID:     userID, // Current user is requesting
		RequestedFromID: req.RequestedFromID,
		ShopID:          req.ShopID,
		TenantID:        tenantID,
		Amount:          req.Amount,
		Reason:          req.Reason,
	}

	request, err := h.cashService.CreateCashRequest(c.Request.Context(), requestInput, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, request)
}

// GetCashRequests godoc
// @Summary Get cash requests
// @Description Get list of cash requests with filters
// @Tags Cash
// @Accept json
// @Produce json
// @Param requester_id query string false "Requester User ID"
// @Param requested_from_id query string false "Requested From User ID"
// @Param shop_id query string false "Shop ID"
// @Param status query string false "Status (pending/approved/rejected/expired)"
// @Success 200 {array} models.CashRequest
// @Router /api/finance/cash/requests [get]
func (h *CashHandlers) GetCashRequests(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters
	filters := make(map[string]interface{})

	// Handle 'filter' parameter for sent/received requests
	if filterType := c.Query("filter"); filterType != "" {
		switch filterType {
		case "sent":
			// Requests sent BY current user
			filters["requester_id"] = userID
		case "received":
			// Requests sent TO current user
			filters["requested_from_id"] = userID
		}
	}

	// Allow manual override of IDs (takes precedence over filter parameter)
	if requesterID := c.Query("requester_id"); requesterID != "" {
		if id, err := uuid.Parse(requesterID); err == nil {
			filters["requester_id"] = id
		}
	}

	if requestedFromID := c.Query("requested_from_id"); requestedFromID != "" {
		if id, err := uuid.Parse(requestedFromID); err == nil {
			filters["requested_from_id"] = id
		}
	}

	if shopID := c.Query("shop_id"); shopID != "" {
		if id, err := uuid.Parse(shopID); err == nil {
			filters["shop_id"] = id
		}
	}

	if status := c.Query("status"); status != "" {
		filters["status"] = status
	}

	requests, err := h.cashService.GetCashRequests(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"requests": requests,
		"count":    len(requests),
	})
}

// GetPendingCashRequests godoc
// @Summary Get pending cash requests for current user
// @Description Get all pending cash requests where current user needs to approve
// @Tags Cash
// @Accept json
// @Produce json
// @Param shop_id query string false "Shop ID"
// @Success 200 {array} models.CashRequest
// @Router /api/finance/cash/requests/pending [get]
func (h *CashHandlers) GetPendingCashRequests(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Build filters for pending requests TO current user (requested_from_id)
	filters := map[string]interface{}{
		"requested_from_id": userID,
		"status":            "pending",
	}

	// Optional shop filter
	if shopIDStr := c.Query("shop_id"); shopIDStr != "" {
		shopID, err := uuid.Parse(shopIDStr)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid shop_id"})
			return
		}
		filters["shop_id"] = shopID
	}

	// Call ExpireOldCashRequests to ensure expired ones are marked
	h.cashService.ExpireOldCashRequests(c.Request.Context())

	requests, err := h.cashService.GetCashRequests(c.Request.Context(), tenantID, filters)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"cash_requests": requests,
		"count":         len(requests),
	})
}

// ApproveCashRequestHandler godoc
// @Summary Approve a pending cash request
// @Description Approve a cash request within 10-minute deadline and transfer cash
// @Tags Cash
// @Accept json
// @Produce json
// @Param id path string true "Request ID"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/requests/{id}/approve [post]
func (h *CashHandlers) ApproveCashRequestHandler(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	requestID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request ID"})
		return
	}

	// Get request details before approval for notification
	requests, _ := h.cashService.GetCashRequests(c.Request.Context(), tenantID, map[string]interface{}{
		"id": requestID,
	})

	err = h.cashService.ApproveCashRequest(c.Request.Context(), requestID, userID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Send push notification to the user who requested the cash
	if h.notificationService != nil && len(requests) > 0 {
		request := requests[0]
		go func() {
			if err := h.notificationService.SendCashRequestApproved(
				c.Request.Context(),
				request.RequesterID, // Who requested the cash
				tenantID,
				request.Amount,
				requestID,
			); err != nil {
				log.Printf("⚠️ Failed to send cash request approval notification: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Cash request approved successfully",
		"request_id": requestID,
		"approved_by": userID,
		"approved_at": time.Now().UTC(),
		"tenant_id":  tenantID,
	})
}

// RejectCashRequestHandler godoc
// @Summary Reject a pending cash request
// @Description Reject a cash request with reason
// @Tags Cash
// @Accept json
// @Produce json
// @Param id path string true "Request ID"
// @Param request body RejectCollectionRequest true "Rejection request"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/requests/{id}/reject [post]
func (h *CashHandlers) RejectCashRequestHandler(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	requestID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request ID"})
		return
	}

	var req RejectCollectionRequest // Reuse existing struct
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Get request details before rejection for notification
	requests, _ := h.cashService.GetCashRequests(c.Request.Context(), tenantID, map[string]interface{}{
		"id": requestID,
	})

	err = h.cashService.RejectCashRequest(c.Request.Context(), requestID, userID, req.Reason)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Send push notification to the user who requested the cash
	if h.notificationService != nil && len(requests) > 0 {
		request := requests[0]
		go func() {
			if err := h.notificationService.SendCashRequestRejected(
				c.Request.Context(),
				request.RequesterID, // Who requested the cash
				tenantID,
				req.Reason,
				requestID,
			); err != nil {
				log.Printf("⚠️ Failed to send cash request rejection notification: %v", err)
			}
		}()
	}

	c.JSON(http.StatusOK, gin.H{
		"message":    "Cash request rejected successfully",
		"request_id": requestID,
		"rejected_by": userID,
		"rejected_at": time.Now().UTC(),
		"reason":     req.Reason,
		"tenant_id":  tenantID,
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// File Upload Endpoints
// ═══════════════════════════════════════════════════════════════════════════

// UploadReceiptPhoto godoc
// @Summary Upload receipt photo
// @Description Upload receipt photo and get URL for cash submission
// @Tags Cash
// @Accept multipart/form-data
// @Produce json
// @Param file formData file true "Receipt photo"
// @Success 200 {object} map[string]interface{}
// @Router /api/finance/cash/upload-receipt [post]
func (h *CashHandlers) UploadReceiptPhoto(c *gin.Context) {
	tenantID, userID, err := extractTenantAndUser(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": err.Error()})
		return
	}

	// Parse multipart form
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file uploaded"})
		return
	}

	// Validate file type (only images)
	contentType := file.Header.Get("Content-Type")
	if contentType != "image/jpeg" && contentType != "image/png" && contentType != "image/jpg" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only JPEG and PNG images are allowed"})
		return
	}

	// Validate file size (max 5MB)
	if file.Size > 5*1024*1024 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "File size exceeds 5MB limit"})
		return
	}

	// Generate unique filename
	timestamp := time.Now().Unix()
	filename := fmt.Sprintf("receipt_%s_%s_%d.jpg", tenantID, userID, timestamp)

	// TODO: Implement actual cloud storage upload (S3, Firebase, etc.)
	// For now, return a placeholder URL
	// In production, you would:
	// 1. Upload to S3: uploadedUrl := s3Service.Upload(file, filename)
	// 2. Upload to Firebase: uploadedUrl := firebaseStorage.Upload(file, filename)
	// 3. Store locally: save to /uploads folder and return local URL

	placeholderUrl := fmt.Sprintf("https://storage.liquorpro.com/receipts/%s", filename)

	log.Printf("📸 Receipt photo upload requested: %s (tenant: %s, user: %s)", filename, tenantID, userID)
	log.Printf("⚠️  PLACEHOLDER URL returned (cloud storage not yet implemented)")

	c.JSON(http.StatusOK, gin.H{
		"url":      placeholderUrl,
		"filename": filename,
		"size":     file.Size,
		"message":  "Receipt photo uploaded successfully (using placeholder URL)",
	})
}

// ═══════════════════════════════════════════════════════════════════════════
// Helper Functions
// ═══════════════════════════════════════════════════════════════════════════

func extractTenantAndUser(c *gin.Context) (uuid.UUID, uuid.UUID, error) {
	tenantIDStr := c.GetString("tenant_id")
	userIDStr := c.GetString("user_id")

	if userIDStr == "" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("user ID not found in context")
	}

	userID, err := uuid.Parse(userIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid user ID")
	}

	if tenantIDStr == "" {
		return uuid.Nil, uuid.Nil, fmt.Errorf("tenant ID not found in context")
	}

	tenantID, err := uuid.Parse(tenantIDStr)
	if err != nil {
		return uuid.Nil, uuid.Nil, fmt.Errorf("invalid tenant ID")
	}

	return tenantID, userID, nil
}

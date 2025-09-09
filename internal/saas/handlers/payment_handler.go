package handlers

import (
	"io"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
)

type PaymentHandler struct {
	paymentService *services.PaymentService
}

func NewPaymentHandler(paymentService *services.PaymentService) *PaymentHandler {
	return &PaymentHandler{
		paymentService: paymentService,
	}
}

func (h *PaymentHandler) CreatePayment(c *gin.Context) {
	var req models.CreatePaymentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	payment, err := h.paymentService.CreatePayment(c.Request.Context(), &req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, payment)
}

func (h *PaymentHandler) GetPayment(c *gin.Context) {
	paymentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment ID"})
		return
	}

	payment, err := h.paymentService.GetPayment(c.Request.Context(), paymentID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, payment)
}

func (h *PaymentHandler) GetPayments(c *gin.Context) {
	// Get subscription ID from query params
	subscriptionIDStr := c.Query("subscription_id")
	if subscriptionIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "subscription_id is required"})
		return
	}

	subscriptionID, err := uuid.Parse(subscriptionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription_id format"})
		return
	}

	// Parse pagination parameters
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 10
	}

	offset := (page - 1) * limit

	payments, total, err := h.paymentService.GetPaymentsBySubscription(c.Request.Context(), subscriptionID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"payments": payments,
		"total":    total,
		"page":     page,
		"limit":    limit,
	})
}

func (h *PaymentHandler) RefundPayment(c *gin.Context) {
	paymentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment ID"})
		return
	}

	var req struct {
		Amount float64 `json:"amount" binding:"required,min=0"`
		Reason string  `json:"reason"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	payment, err := h.paymentService.RefundPayment(c.Request.Context(), paymentID, req.Amount, req.Reason)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, payment)
}

func (h *PaymentHandler) UpdatePaymentStatus(c *gin.Context) {
	paymentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment ID"})
		return
	}

	var req struct {
		Status            string `json:"status" binding:"required"`
		RazorpayPaymentID string `json:"razorpay_payment_id"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	err = h.paymentService.UpdatePaymentStatus(c.Request.Context(), paymentID, req.Status, req.RazorpayPaymentID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "payment status updated successfully"})
}

// Webhook handler - no authentication required
func (h *PaymentHandler) HandleRazorpayWebhook(c *gin.Context) {
	// Read the entire request body
	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "failed to read request body"})
		return
	}

	// Get event type from headers
	eventType := c.GetHeader("X-Razorpay-Event-Id")
	if eventType == "" {
		// Try to get from X-Razorpay-Event header
		eventType = c.GetHeader("X-Razorpay-Event")
	}

	// Get signature for verification
	signature := c.GetHeader("X-Razorpay-Signature")
	if signature == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing signature"})
		return
	}

	// TODO: Verify webhook signature before processing
	// For now, we'll process all webhooks

	// Parse event type from body if not in headers
	if eventType == "" {
		eventType = "payment.captured" // default for testing
	}

	// Process the webhook
	err = h.paymentService.HandleWebhook(c.Request.Context(), eventType, body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Razorpay expects a 200 OK response
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

// Invoice handlers

func (h *PaymentHandler) GetInvoices(c *gin.Context) {
	// Get subscription ID from query params
	subscriptionIDStr := c.Query("subscription_id")
	if subscriptionIDStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "subscription_id is required"})
		return
	}

	subscriptionID, err := uuid.Parse(subscriptionIDStr)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid subscription_id format"})
		return
	}

	// Parse pagination parameters
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 100 {
		limit = 10
	}

	offset := (page - 1) * limit

	invoices, total, err := h.paymentService.GetInvoices(c.Request.Context(), subscriptionID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"invoices": invoices,
		"total":    total,
		"page":     page,
		"limit":    limit,
	})
}

func (h *PaymentHandler) GetInvoice(c *gin.Context) {
	invoiceID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invoice ID"})
		return
	}

	invoice, err := h.paymentService.GetInvoice(c.Request.Context(), invoiceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, invoice)
}

func (h *PaymentHandler) DownloadInvoice(c *gin.Context) {
	invoiceID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invoice ID"})
		return
	}

	invoice, err := h.paymentService.GetInvoice(c.Request.Context(), invoiceID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	// TODO: Generate PDF invoice
	// For now, return invoice data as JSON with appropriate headers
	c.Header("Content-Type", "application/json")
	c.Header("Content-Disposition", "attachment; filename=invoice_"+invoice.InvoiceNumber+".json")
	c.JSON(http.StatusOK, invoice)
}

// Utility endpoints

func (h *PaymentHandler) GetPaymentMethods(c *gin.Context) {
	// Return supported payment methods
	methods := []gin.H{
		{"id": "card", "name": "Credit/Debit Card", "enabled": true},
		{"id": "netbanking", "name": "Net Banking", "enabled": true},
		{"id": "wallet", "name": "Digital Wallet", "enabled": true},
		{"id": "upi", "name": "UPI", "enabled": true},
	}

	c.JSON(http.StatusOK, gin.H{"payment_methods": methods})
}

func (h *PaymentHandler) GetPaymentStatus(c *gin.Context) {
	paymentID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid payment ID"})
		return
	}

	payment, err := h.paymentService.GetPayment(c.Request.Context(), paymentID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"payment_id": payment.ID,
		"status":     payment.Status,
		"amount":     payment.Amount,
		"currency":   payment.Currency,
		"created_at": payment.CreatedAt,
		"processed_at": payment.ProcessedAt,
	})
}
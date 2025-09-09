package webhook

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// WebhookEvent represents different types of webhook events
type WebhookEvent string

const (
	EventUserCreated      WebhookEvent = "user.created"
	EventUserUpdated      WebhookEvent = "user.updated"
	EventUserDeleted      WebhookEvent = "user.deleted"
	EventProductCreated   WebhookEvent = "product.created"
	EventProductUpdated   WebhookEvent = "product.updated"
	EventProductDeleted   WebhookEvent = "product.deleted"
	EventOrderCreated     WebhookEvent = "order.created"
	EventOrderUpdated     WebhookEvent = "order.updated"
	EventOrderCompleted   WebhookEvent = "order.completed"
	EventPaymentReceived  WebhookEvent = "payment.received"
	EventPaymentFailed    WebhookEvent = "payment.failed"
)

// WebhookPayload represents the structure of webhook data
type WebhookPayload struct {
	ID        string                 `json:"id"`
	Event     WebhookEvent          `json:"event"`
	Data      map[string]interface{} `json:"data"`
	TenantID  string                `json:"tenant_id"`
	Timestamp time.Time             `json:"timestamp"`
	Version   string                `json:"version"`
}

// WebhookEndpoint represents a registered webhook endpoint
type WebhookEndpoint struct {
	ID          string    `gorm:"primaryKey;type:uuid;default:gen_random_uuid()" json:"id"`
	TenantID    string    `gorm:"type:uuid;not null;index" json:"tenant_id"`
	URL         string    `gorm:"type:varchar(500);not null" json:"url"`
	Secret      string    `gorm:"type:varchar(100);not null" json:"secret"`
	Events      []string  `gorm:"type:text[]" json:"events"`
	IsActive    bool      `gorm:"default:true" json:"is_active"`
	RetryCount  int       `gorm:"default:3" json:"retry_count"`
	Timeout     int       `gorm:"default:30" json:"timeout"` // seconds
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// WebhookDelivery tracks webhook delivery attempts
type WebhookDelivery struct {
	ID           string    `gorm:"primaryKey;type:uuid;default:gen_random_uuid()" json:"id"`
	EndpointID   string    `gorm:"type:uuid;not null;index" json:"endpoint_id"`
	PayloadID    string    `gorm:"type:varchar(100);not null" json:"payload_id"`
	Event        string    `gorm:"type:varchar(50);not null" json:"event"`
	Status       string    `gorm:"type:varchar(20);not null" json:"status"` // pending, success, failed
	AttemptCount int       `gorm:"default:0" json:"attempt_count"`
	LastAttempt  *time.Time `json:"last_attempt"`
	NextRetry    *time.Time `json:"next_retry"`
	Response     string    `gorm:"type:text" json:"response"`
	ErrorMessage string    `gorm:"type:text" json:"error_message"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// WebhookManager manages webhook registrations and deliveries
type WebhookManager struct {
	db       *gorm.DB
	logger   *zap.Logger
	client   *http.Client
	workers  int
	jobQueue chan *WebhookJob
}

// WebhookJob represents a webhook delivery job
type WebhookJob struct {
	Endpoint *WebhookEndpoint
	Payload  *WebhookPayload
	Delivery *WebhookDelivery
}

// NewWebhookManager creates a new webhook manager
func NewWebhookManager(db *gorm.DB, logger *zap.Logger, workers int) *WebhookManager {
	wm := &WebhookManager{
		db:       db,
		logger:   logger,
		client:   &http.Client{Timeout: 30 * time.Second},
		workers:  workers,
		jobQueue: make(chan *WebhookJob, 1000),
	}
	
	// Start worker goroutines
	for i := 0; i < workers; i++ {
		go wm.worker(i)
	}
	
	// Start retry scheduler
	go wm.retryScheduler()
	
	return wm
}

// RegisterEndpoint registers a new webhook endpoint
func (wm *WebhookManager) RegisterEndpoint(c *gin.Context) {
	var req struct {
		URL         string   `json:"url" binding:"required,url"`
		Events      []string `json:"events" binding:"required"`
		Secret      string   `json:"secret" binding:"required,min=10"`
		RetryCount  int      `json:"retry_count"`
		Timeout     int      `json:"timeout"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}
	
	tenantID := c.GetString("tenant_id")
	
	endpoint := WebhookEndpoint{
		TenantID:   tenantID,
		URL:        req.URL,
		Secret:     req.Secret,
		Events:     req.Events,
		IsActive:   true,
		RetryCount: req.RetryCount,
		Timeout:    req.Timeout,
	}
	
	// Set defaults
	if endpoint.RetryCount == 0 {
		endpoint.RetryCount = 3
	}
	if endpoint.Timeout == 0 {
		endpoint.Timeout = 30
	}
	
	if err := wm.db.Create(&endpoint).Error; err != nil {
		wm.logger.Error("Failed to create webhook endpoint", zap.Error(err))
		c.JSON(500, gin.H{"error": "Failed to create webhook endpoint"})
		return
	}
	
	wm.logger.Info("Webhook endpoint registered",
		zap.String("id", endpoint.ID),
		zap.String("tenant_id", tenantID),
		zap.String("url", endpoint.URL),
		zap.Strings("events", endpoint.Events),
	)
	
	c.JSON(201, endpoint)
}

// ListEndpoints lists all webhook endpoints for a tenant
func (wm *WebhookManager) ListEndpoints(c *gin.Context) {
	tenantID := c.GetString("tenant_id")
	
	var endpoints []WebhookEndpoint
	if err := wm.db.Where("tenant_id = ?", tenantID).Find(&endpoints).Error; err != nil {
		wm.logger.Error("Failed to list webhook endpoints", zap.Error(err))
		c.JSON(500, gin.H{"error": "Failed to list webhook endpoints"})
		return
	}
	
	c.JSON(200, gin.H{"endpoints": endpoints})
}

// UpdateEndpoint updates a webhook endpoint
func (wm *WebhookManager) UpdateEndpoint(c *gin.Context) {
	endpointID := c.Param("id")
	tenantID := c.GetString("tenant_id")
	
	var req struct {
		URL        string   `json:"url" binding:"omitempty,url"`
		Events     []string `json:"events"`
		Secret     string   `json:"secret" binding:"omitempty,min=10"`
		IsActive   *bool    `json:"is_active"`
		RetryCount int      `json:"retry_count"`
		Timeout    int      `json:"timeout"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}
	
	var endpoint WebhookEndpoint
	if err := wm.db.Where("id = ? AND tenant_id = ?", endpointID, tenantID).First(&endpoint).Error; err != nil {
		c.JSON(404, gin.H{"error": "Webhook endpoint not found"})
		return
	}
	
	// Update fields
	updates := make(map[string]interface{})
	if req.URL != "" {
		updates["url"] = req.URL
	}
	if len(req.Events) > 0 {
		updates["events"] = req.Events
	}
	if req.Secret != "" {
		updates["secret"] = req.Secret
	}
	if req.IsActive != nil {
		updates["is_active"] = *req.IsActive
	}
	if req.RetryCount > 0 {
		updates["retry_count"] = req.RetryCount
	}
	if req.Timeout > 0 {
		updates["timeout"] = req.Timeout
	}
	
	if err := wm.db.Model(&endpoint).Updates(updates).Error; err != nil {
		wm.logger.Error("Failed to update webhook endpoint", zap.Error(err))
		c.JSON(500, gin.H{"error": "Failed to update webhook endpoint"})
		return
	}
	
	c.JSON(200, endpoint)
}

// DeleteEndpoint deletes a webhook endpoint
func (wm *WebhookManager) DeleteEndpoint(c *gin.Context) {
	endpointID := c.Param("id")
	tenantID := c.GetString("tenant_id")
	
	result := wm.db.Where("id = ? AND tenant_id = ?", endpointID, tenantID).Delete(&WebhookEndpoint{})
	if result.Error != nil {
		wm.logger.Error("Failed to delete webhook endpoint", zap.Error(result.Error))
		c.JSON(500, gin.H{"error": "Failed to delete webhook endpoint"})
		return
	}
	
	if result.RowsAffected == 0 {
		c.JSON(404, gin.H{"error": "Webhook endpoint not found"})
		return
	}
	
	c.JSON(204, nil)
}

// TriggerEvent triggers webhook events for registered endpoints
func (wm *WebhookManager) TriggerEvent(tenantID string, event WebhookEvent, data map[string]interface{}) error {
	// Find all active endpoints for this tenant and event
	var endpoints []WebhookEndpoint
	if err := wm.db.Where("tenant_id = ? AND is_active = true", tenantID).Find(&endpoints).Error; err != nil {
		return fmt.Errorf("failed to find webhook endpoints: %w", err)
	}
	
	payload := &WebhookPayload{
		ID:        generateID(),
		Event:     event,
		Data:      data,
		TenantID:  tenantID,
		Timestamp: time.Now(),
		Version:   "1.0",
	}
	
	for _, endpoint := range endpoints {
		// Check if endpoint is subscribed to this event
		if wm.isEventSubscribed(&endpoint, string(event)) {
			delivery := &WebhookDelivery{
				EndpointID: endpoint.ID,
				PayloadID:  payload.ID,
				Event:      string(event),
				Status:     "pending",
			}
			
			if err := wm.db.Create(delivery).Error; err != nil {
				wm.logger.Error("Failed to create webhook delivery", zap.Error(err))
				continue
			}
			
			// Queue for delivery
			wm.jobQueue <- &WebhookJob{
				Endpoint: &endpoint,
				Payload:  payload,
				Delivery: delivery,
			}
		}
	}
	
	return nil
}

// isEventSubscribed checks if endpoint is subscribed to an event
func (wm *WebhookManager) isEventSubscribed(endpoint *WebhookEndpoint, event string) bool {
	for _, subscribedEvent := range endpoint.Events {
		if subscribedEvent == "*" || subscribedEvent == event {
			return true
		}
	}
	return false
}

// worker processes webhook delivery jobs
func (wm *WebhookManager) worker(id int) {
	wm.logger.Info("Starting webhook worker", zap.Int("worker_id", id))
	
	for job := range wm.jobQueue {
		wm.processWebhookJob(job)
	}
}

// processWebhookJob processes a single webhook delivery job
func (wm *WebhookManager) processWebhookJob(job *WebhookJob) {
	wm.logger.Debug("Processing webhook job",
		zap.String("endpoint_id", job.Endpoint.ID),
		zap.String("event", string(job.Payload.Event)),
	)
	
	// Update attempt count
	job.Delivery.AttemptCount++
	now := time.Now()
	job.Delivery.LastAttempt = &now
	
	// Prepare request
	payloadBytes, err := json.Marshal(job.Payload)
	if err != nil {
		wm.updateDeliveryStatus(job.Delivery, "failed", "", fmt.Sprintf("Failed to marshal payload: %v", err))
		return
	}
	
	req, err := http.NewRequest("POST", job.Endpoint.URL, bytes.NewBuffer(payloadBytes))
	if err != nil {
		wm.updateDeliveryStatus(job.Delivery, "failed", "", fmt.Sprintf("Failed to create request: %v", err))
		return
	}
	
	// Set headers
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "LiquorPro-Webhook/1.0")
	req.Header.Set("X-Webhook-Event", string(job.Payload.Event))
	req.Header.Set("X-Webhook-ID", job.Payload.ID)
	req.Header.Set("X-Webhook-Timestamp", fmt.Sprintf("%d", job.Payload.Timestamp.Unix()))
	
	// Generate signature
	signature := wm.generateSignature(payloadBytes, job.Endpoint.Secret)
	req.Header.Set("X-Webhook-Signature", signature)
	
	// Set timeout
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(job.Endpoint.Timeout)*time.Second)
	defer cancel()
	req = req.WithContext(ctx)
	
	// Send request
	resp, err := wm.client.Do(req)
	if err != nil {
		wm.scheduleRetry(job, fmt.Sprintf("Request failed: %v", err))
		return
	}
	defer resp.Body.Close()
	
	// Read response
	var responseBody bytes.Buffer
	responseBody.ReadFrom(resp.Body)
	responseStr := responseBody.String()
	
	// Check status code
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		wm.updateDeliveryStatus(job.Delivery, "success", responseStr, "")
		wm.logger.Info("Webhook delivered successfully",
			zap.String("endpoint_id", job.Endpoint.ID),
			zap.String("event", string(job.Payload.Event)),
			zap.Int("status_code", resp.StatusCode),
		)
	} else {
		wm.scheduleRetry(job, fmt.Sprintf("HTTP %d: %s", resp.StatusCode, responseStr))
	}
}

// generateSignature generates HMAC signature for webhook payload
func (wm *WebhookManager) generateSignature(payload []byte, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(payload)
	return "sha256=" + hex.EncodeToString(mac.Sum(nil))
}

// scheduleRetry schedules a retry for failed webhook delivery
func (wm *WebhookManager) scheduleRetry(job *WebhookJob, errorMsg string) {
	if job.Delivery.AttemptCount >= job.Endpoint.RetryCount {
		wm.updateDeliveryStatus(job.Delivery, "failed", "", errorMsg)
		wm.logger.Error("Webhook delivery failed after max retries",
			zap.String("endpoint_id", job.Endpoint.ID),
			zap.String("event", string(job.Payload.Event)),
			zap.Int("attempts", job.Delivery.AttemptCount),
			zap.String("error", errorMsg),
		)
		return
	}
	
	// Calculate exponential backoff: 2^attempt minutes
	retryDelayMinutes := 1 << job.Delivery.AttemptCount // 2, 4, 8 minutes
	nextRetry := time.Now().Add(time.Duration(retryDelayMinutes) * time.Minute)
	job.Delivery.NextRetry = &nextRetry
	
	wm.updateDeliveryStatus(job.Delivery, "pending", "", errorMsg)
	
	wm.logger.Warn("Webhook delivery failed, scheduled for retry",
		zap.String("endpoint_id", job.Endpoint.ID),
		zap.String("event", string(job.Payload.Event)),
		zap.Int("attempt", job.Delivery.AttemptCount),
		zap.Time("next_retry", nextRetry),
		zap.String("error", errorMsg),
	)
}

// updateDeliveryStatus updates webhook delivery status
func (wm *WebhookManager) updateDeliveryStatus(delivery *WebhookDelivery, status, response, errorMsg string) {
	updates := map[string]interface{}{
		"status":        status,
		"response":      response,
		"error_message": errorMsg,
		"attempt_count": delivery.AttemptCount,
		"last_attempt":  delivery.LastAttempt,
	}
	
	if delivery.NextRetry != nil {
		updates["next_retry"] = delivery.NextRetry
	}
	
	if err := wm.db.Model(delivery).Updates(updates).Error; err != nil {
		wm.logger.Error("Failed to update webhook delivery status", zap.Error(err))
	}
}

// retryScheduler handles retry scheduling for failed webhooks
func (wm *WebhookManager) retryScheduler() {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()
	
	for range ticker.C {
		var deliveries []WebhookDelivery
		now := time.Now()
		
		// Find deliveries ready for retry
		if err := wm.db.Where("status = ? AND next_retry <= ?", "pending", now).
			Preload("Endpoint").
			Find(&deliveries).Error; err != nil {
			wm.logger.Error("Failed to find deliveries for retry", zap.Error(err))
			continue
		}
		
		for _, delivery := range deliveries {
			// Reconstruct payload (in real implementation, you might want to store this)
			payload := &WebhookPayload{
				ID:        delivery.PayloadID,
				Event:     WebhookEvent(delivery.Event),
				TenantID:  delivery.Endpoint.TenantID,
				Timestamp: delivery.CreatedAt,
				Version:   "1.0",
			}
			
			// Queue for retry
			wm.jobQueue <- &WebhookJob{
				Endpoint: &delivery.Endpoint,
				Payload:  payload,
				Delivery: &delivery,
			}
		}
	}
}

// GetDeliveries returns webhook deliveries for an endpoint
func (wm *WebhookManager) GetDeliveries(c *gin.Context) {
	endpointID := c.Param("endpoint_id")
	tenantID := c.GetString("tenant_id")
	
	// Verify endpoint belongs to tenant
	var endpoint WebhookEndpoint
	if err := wm.db.Where("id = ? AND tenant_id = ?", endpointID, tenantID).First(&endpoint).Error; err != nil {
		c.JSON(404, gin.H{"error": "Webhook endpoint not found"})
		return
	}
	
	var deliveries []WebhookDelivery
	if err := wm.db.Where("endpoint_id = ?", endpointID).
		Order("created_at DESC").
		Limit(100).
		Find(&deliveries).Error; err != nil {
		wm.logger.Error("Failed to get webhook deliveries", zap.Error(err))
		c.JSON(500, gin.H{"error": "Failed to get webhook deliveries"})
		return
	}
	
	c.JSON(200, gin.H{"deliveries": deliveries})
}

// generateID generates a unique ID for webhook payloads
func generateID() string {
	return fmt.Sprintf("wh_%d", time.Now().UnixNano())
}

// SetupRoutes sets up webhook management routes
func (wm *WebhookManager) SetupRoutes(router *gin.RouterGroup) {
	webhooks := router.Group("/webhooks")
	{
		webhooks.POST("", wm.RegisterEndpoint)
		webhooks.GET("", wm.ListEndpoints)
		webhooks.PUT("/:id", wm.UpdateEndpoint)
		webhooks.DELETE("/:id", wm.DeleteEndpoint)
		webhooks.GET("/:endpoint_id/deliveries", wm.GetDeliveries)
	}
}
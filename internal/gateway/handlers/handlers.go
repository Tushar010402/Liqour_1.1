package handlers

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/liquorpro/go-backend/pkg/messaging"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	ws "github.com/liquorpro/go-backend/pkg/websocket"
	"go.uber.org/zap"
)

// GatewayHandlers handles API gateway routing and service communication
type GatewayHandlers struct {
	config     *config.Config
	httpClient *http.Client
	wsManager  *ws.Manager
	logger     *zap.Logger
}

// NewGatewayHandlers creates a new gateway handlers instance
func NewGatewayHandlers(config *config.Config, httpClient *http.Client, kafkaClient *messaging.KafkaClient, logger *zap.Logger) *GatewayHandlers {
	// Create WebSocket manager with JWT authentication function
	authFunc := func(tokenString string) (userID, tenantID, role string, err error) {
		if tokenString == "" {
			return "", "", "", fmt.Errorf("token is required")
		}

		// Parse and validate JWT token
		token, parseErr := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			// Validate signing method
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(config.JWT.Secret), nil
		})

		if parseErr != nil {
			logger.Warn("JWT parse error", zap.Error(parseErr))
			return "", "", "", fmt.Errorf("invalid token: %w", parseErr)
		}

		if !token.Valid {
			return "", "", "", fmt.Errorf("token is not valid")
		}

		// Extract claims
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			return "", "", "", fmt.Errorf("invalid token claims")
		}

		// Extract user_id
		userIDClaim, ok := claims["user_id"].(string)
		if !ok {
			return "", "", "", fmt.Errorf("user_id not found in token")
		}

		// Extract tenant_id
		tenantIDClaim, ok := claims["tenant_id"].(string)
		if !ok {
			return "", "", "", fmt.Errorf("tenant_id not found in token")
		}

		// Extract role (optional, default to "user")
		roleClaim, ok := claims["role"].(string)
		if !ok {
			roleClaim = "user" // Default role
		}

		logger.Info("WebSocket JWT validated",
			zap.String("user_id", userIDClaim),
			zap.String("tenant_id", tenantIDClaim),
			zap.String("role", roleClaim))

		return userIDClaim, tenantIDClaim, roleClaim, nil
	}

	wsManager := ws.NewManager(ws.ManagerConfig{
		KafkaClient: kafkaClient,
		Logger:      logger,
		AuthFunc:    authFunc,
	})

	return &GatewayHandlers{
		config:     config,
		httpClient: httpClient,
		wsManager:  wsManager,
		logger:     logger,
	}
}

// ProxyRequest proxies requests to appropriate microservices
func (h *GatewayHandlers) ProxyRequest(serviceName string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get service URL
		serviceURL := h.getServiceURL(serviceName)
		if serviceURL == "" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Service not found"})
			return
		}

		// Build target URL - strip service prefix for microservices
		path := c.Request.URL.Path
		targetPath := h.transformPath(path, serviceName)
		targetURL := serviceURL + targetPath
		if c.Request.URL.RawQuery != "" {
			targetURL += "?" + c.Request.URL.RawQuery
		}

		// For OCR endpoints with large payloads, use streaming to avoid memory issues
		// Smart Sale also uses AI vision processing and needs similar handling
		isOCREndpoint := strings.Contains(path, "/ocr/") || strings.Contains(path, "/smart-sale/") || strings.Contains(path, "/smart-purchase/") || strings.Contains(path, "/smart-setup/")
		// For Excel template endpoints, longer timeout is needed for file generation
		isExcelEndpoint := strings.Contains(path, "/template/download") || strings.Contains(path, "/bulk-import")

		var bodyReader io.Reader
		if c.Request.Body != nil {
			if isOCREndpoint {
				// For OCR endpoints, stream the body directly
				bodyReader = c.Request.Body
			} else {
				// For other endpoints, read body into memory for potential retry
				bodyBytes, err := io.ReadAll(c.Request.Body)
				if err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read request body"})
					return
				}
				bodyReader = bytes.NewReader(bodyBytes)
			}
		}

		// Create new request
		req, err := http.NewRequestWithContext(c.Request.Context(), c.Request.Method, targetURL, bodyReader)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create request"})
			return
		}

		// Copy headers
		for key, values := range c.Request.Header {
			for _, value := range values {
				req.Header.Add(key, value)
			}
		}

		// Add gateway headers
		req.Header.Set("X-Gateway", "liquorpro-gateway")
		req.Header.Set("X-Service", serviceName)

		// Forward user context if available
		if userID := c.GetString("user_id"); userID != "" {
			req.Header.Set("X-User-ID", userID)
		}
		if tenantID := c.GetString("tenant_id"); tenantID != "" {
			req.Header.Set("X-Tenant-ID", tenantID)
		}
		if role := c.GetString("role"); role != "" {
			req.Header.Set("X-User-Role", role)
		}
		if perms, exists := c.Get("permissions"); exists {
			if permsList, ok := perms.([]interface{}); ok {
				permsStr := make([]string, 0, len(permsList))
				for _, p := range permsList {
					if s, ok := p.(string); ok {
						permsStr = append(permsStr, s)
					}
				}
				if len(permsStr) > 0 {
					req.Header.Set("X-User-Permissions", strings.Join(permsStr, ","))
				}
			}
		}

		// For OCR, Smart Sale and Excel endpoints, set longer timeout
		client := h.httpClient
		if isOCREndpoint || isExcelEndpoint {
			client = &http.Client{
				Timeout: 180 * time.Second, // 3 minutes for AI processing (multiple images with Gemini)
			}
		}

		// Make request to service
		resp, err := client.Do(req)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "Service unavailable"})
			return
		}
		defer resp.Body.Close()

		// Copy response headers (excluding hop-by-hop headers)
		hopHeaders := map[string]bool{
			"Connection":          true,
			"Keep-Alive":          true,
			"Transfer-Encoding":   true,
			"TE":                  true,
			"Trailer":             true,
			"Upgrade":             true,
			"Proxy-Authorization": true,
			"Proxy-Authenticate":  true,
		}

		for key, values := range resp.Header {
			if !hopHeaders[key] {
				for _, value := range values {
					c.Header(key, value)
				}
			}
		}

		// Stream response body
		c.Status(resp.StatusCode)

		// Use buffered copying for better performance
		buf := make([]byte, 32*1024) // 32KB buffer
		_, err = io.CopyBuffer(c.Writer, resp.Body, buf)
		if err != nil && err != io.EOF {
			// Log error but don't send response as headers are already sent
			// The client will handle partial response
		}
	}
}

// HealthCheck handles health check requests
func (h *GatewayHandlers) HealthCheck(c *gin.Context) {
	// Simple gateway health check - don't check other services to avoid circular issues
	healthStatus := gin.H{
		"status":    "healthy",
		"service":   "gateway",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"version":   h.config.App.Version,
	}

	c.JSON(http.StatusOK, healthStatus)
}

// GetVersion returns gateway version information
func (h *GatewayHandlers) GetVersion(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"name":        h.config.App.Name,
		"version":     h.config.App.Version,
		"environment": h.config.App.Environment,
		"component":   "gateway",
	})
}

// ServiceDiscovery returns available services and their endpoints
func (h *GatewayHandlers) ServiceDiscovery(c *gin.Context) {
	services := gin.H{
		"auth": gin.H{
			"url":    h.config.Services.Auth.URL,
			"status": h.checkServiceHealth(h.config.Services.Auth.URL),
		},
		"sales": gin.H{
			"url":    h.config.Services.Sales.URL,
			"status": h.checkServiceHealth(h.config.Services.Sales.URL),
		},
		"inventory": gin.H{
			"url":    h.config.Services.Inventory.URL,
			"status": h.checkServiceHealth(h.config.Services.Inventory.URL),
		},
		"finance": gin.H{
			"url":    h.config.Services.Finance.URL,
			"status": h.checkServiceHealth(h.config.Services.Finance.URL),
		},
		"saas": gin.H{
			"url":    "http://saas:8095",
			"status": h.checkServiceHealth("http://saas:8095"),
		},
	}

	c.JSON(http.StatusOK, gin.H{
		"gateway":  h.config.Services.Gateway.URL,
		"services": services,
	})
}

// transformPath strips the service prefix from the path
func (h *GatewayHandlers) transformPath(path, serviceName string) string {
	switch strings.ToLower(serviceName) {
	case "sales":
		// Sales service uses SetupProtectedRoutes which registers routes at root level
		// Transform /api/sales/* to /* for sales service
		if strings.HasPrefix(path, "/api/sales/") {
			return strings.Replace(path, "/api/sales/", "/", 1)
		}
	case "inventory":
		// Keep saas-brands paths intact
		if strings.HasPrefix(path, "/api/inventory/saas-brands/") {
			return path // Keep full path for saas-brands
		}
		// Keep custom brand paths intact
		if strings.HasPrefix(path, "/api/inventory/brands/custom") ||
			strings.HasPrefix(path, "/api/inventory/brands/with-variants") {
			return path // Keep full path for custom brand endpoints
		}
		// Keep brand edit proxy paths intact (for EditBrandVariantScreen)
		if strings.HasPrefix(path, "/api/inventory/brand-categories") ||
			strings.HasPrefix(path, "/api/inventory/brand-subcategories") ||
			strings.HasPrefix(path, "/api/inventory/category-sizes") {
			return path // Keep full path for brand edit endpoints
		}
		// Transform /api/inventory/* to /* for inventory service
		// Inventory service uses SetupProtectedRoutes which registers at root level
		if strings.HasPrefix(path, "/api/inventory/") {
			return strings.Replace(path, "/api/inventory/", "/", 1)
		}
	case "finance":
		// Finance service uses SetupProtectedRoutes which registers routes at root level
		// Transform /api/finance/* to /* for finance service
		if strings.HasPrefix(path, "/api/finance/") {
			return strings.Replace(path, "/api/finance/", "/", 1)
		}
	case "saas":
		// SaaS service already registers routes under /api/saas/, so no transformation needed
		return path
	case "auth":
		// Auth service paths don't need transformation
		return path
	}
	return path
}

// getServiceURL returns the URL for a given service name
func (h *GatewayHandlers) getServiceURL(serviceName string) string {
	switch strings.ToLower(serviceName) {
	case "auth":
		return h.config.Services.Auth.URL
	case "sales":
		return h.config.Services.Sales.URL
	case "inventory":
		return h.config.Services.Inventory.URL
	case "finance":
		return h.config.Services.Finance.URL
	case "saas":
		return "http://saas:8095"
	default:
		return ""
	}
}

// checkServiceHealth checks if a service is healthy
func (h *GatewayHandlers) checkServiceHealth(serviceURL string) string {
	if serviceURL == "" {
		return "unknown"
	}

	req, err := http.NewRequest("GET", serviceURL+"/health", nil)
	if err != nil {
		return "error"
	}
	req.Header.Set("User-Agent", "liquorpro-gateway-health-check")

	client := &http.Client{
		Timeout: 5 * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		return "unhealthy"
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return "healthy"
	}
	return "unhealthy"
}

// LoadBalancer handles load balancing for services (future enhancement)
func (h *GatewayHandlers) LoadBalancer(serviceName string, instances []string) gin.HandlerFunc {
	// Simple round-robin load balancer implementation
	counter := 0
	return func(c *gin.Context) {
		if len(instances) == 0 {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "No service instances available"})
			return
		}

		// Select instance using round-robin
		selectedInstance := instances[counter%len(instances)]
		counter++

		// Update the target URL temporarily
		originalURL := h.getServiceURL(serviceName)
		defer func() {
			// Restore original URL after request
			h.setServiceURL(serviceName, originalURL)
		}()

		h.setServiceURL(serviceName, selectedInstance)
		h.ProxyRequest(serviceName)(c)
	}
}

// setServiceURL sets the URL for a service (helper for load balancing)
func (h *GatewayHandlers) setServiceURL(serviceName, url string) {
	// This is a simplified implementation
	// In production, you'd want a more robust service registry
	switch strings.ToLower(serviceName) {
	case "auth":
		h.config.Services.Auth.URL = url
	case "sales":
		h.config.Services.Sales.URL = url
	case "inventory":
		h.config.Services.Inventory.URL = url
	case "finance":
		h.config.Services.Finance.URL = url
	}
}

// HandleWebSocket handles WebSocket upgrade requests
func (h *GatewayHandlers) HandleWebSocket(c *gin.Context) {
	h.wsManager.HandleWebSocket(c)
}

// GetWebSocketStats returns WebSocket connection statistics
func (h *GatewayHandlers) GetWebSocketStats(c *gin.Context) {
	stats := h.wsManager.GetConnectionStats()
	c.JSON(http.StatusOK, stats)
}

// BroadcastInventoryUpdate broadcasts inventory updates via WebSocket
func (h *GatewayHandlers) BroadcastInventoryUpdate(tenantID, productID string, updates map[string]interface{}) {
	h.wsManager.BroadcastInventoryUpdate(tenantID, productID, updates)
}

// BroadcastSaleUpdate broadcasts sale updates via WebSocket
func (h *GatewayHandlers) BroadcastSaleUpdate(tenantID, saleID string, saleData map[string]interface{}) {
	h.wsManager.BroadcastSaleUpdate(tenantID, saleID, saleData)
}

// BroadcastCashFlowUpdate broadcasts cash flow updates via WebSocket
func (h *GatewayHandlers) BroadcastCashFlowUpdate(tenantID, flowType string, amount float64, details map[string]interface{}) {
	h.wsManager.BroadcastCashFlowUpdate(tenantID, flowType, amount, details)
}

// BroadcastNotification sends notifications via WebSocket
func (h *GatewayHandlers) BroadcastNotification(tenantID, userID string, notification map[string]interface{}) {
	h.wsManager.BroadcastNotification(tenantID, userID, notification)
}

// BroadcastDashboardUpdate broadcasts dashboard metric updates
func (h *GatewayHandlers) BroadcastDashboardUpdate(tenantID string, metrics map[string]interface{}) {
	h.wsManager.BroadcastDashboardUpdate(tenantID, metrics)
}

// BroadcastOCRProgress broadcasts OCR progress updates via WebSocket (v1.0.28)
func (h *GatewayHandlers) BroadcastOCRProgress(tenantID, sessionID, batchID string, progressData map[string]interface{}) {
	h.wsManager.BroadcastOCRProgress(tenantID, sessionID, batchID, progressData)
}

// HandleOCRProgressBroadcast handles HTTP requests from services to broadcast OCR progress (v1.0.28)
func (h *GatewayHandlers) HandleOCRProgressBroadcast(c *gin.Context) {
	var req struct {
		TenantID     string                 `json:"tenant_id" binding:"required"`
		SessionID    string                 `json:"session_id"`
		BatchID      string                 `json:"batch_id"`
		ProgressData map[string]interface{} `json:"progress_data" binding:"required"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		h.logger.Warn("Invalid OCR broadcast request", zap.Error(err))
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request payload"})
		return
	}

	h.logger.Info("📡 Received OCR broadcast request",
		zap.String("tenant_id", req.TenantID),
		zap.String("batch_id", req.BatchID),
		zap.String("session_id", req.SessionID),
		zap.Any("progress_data", req.ProgressData))

	h.BroadcastOCRProgress(req.TenantID, req.SessionID, req.BatchID, req.ProgressData)

	h.logger.Info("✅ OCR broadcast forwarded to WebSocket clients",
		zap.String("tenant_id", req.TenantID),
		zap.String("batch_id", req.BatchID))

	c.JSON(http.StatusOK, gin.H{"status": "broadcast_sent"})
}

// RegisterDevice handles FCM device registration (stub - accepts and acknowledges)
func (h *GatewayHandlers) RegisterDevice(c *gin.Context) {
	var req struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
		Device   string `json:"device"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		// Even on error, return success to prevent app errors
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"message": "Device registration acknowledged",
		})
		return
	}

	h.logger.Info("Device registration received",
		zap.String("platform", req.Platform),
		zap.String("device", req.Device))

	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Device registered successfully",
	})
}

// BatchLogs handles client log batch uploads (stub - accepts and acknowledges)
func (h *GatewayHandlers) BatchLogs(c *gin.Context) {
	// Accept the logs but don't process them (stub implementation)
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"message": "Logs received",
	})
}

// GetProductSizes returns available product sizes (stub - returns empty for now)
func (h *GatewayHandlers) GetProductSizes(c *gin.Context) {
	// Return empty sizes array - app handles this gracefully
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"sizes":   []interface{}{},
		"message": "Sizes endpoint not yet implemented",
	})
}

// GetNotifications returns notifications list (stub)
func (h *GatewayHandlers) GetNotifications(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"success":       true,
		"notifications": []interface{}{},
		"total":         0,
		"unread_count":  0,
	})
}

// GetUnreadCount returns unread notification count (stub)
func (h *GatewayHandlers) GetUnreadCount(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"success":      true,
		"unread_count": 0,
	})
}

// Shutdown gracefully shuts down the gateway handlers including WebSocket manager
func (h *GatewayHandlers) Shutdown() {
	if h.wsManager != nil {
		h.wsManager.Shutdown()
	}
	h.logger.Info("Gateway handlers shutdown complete")
}

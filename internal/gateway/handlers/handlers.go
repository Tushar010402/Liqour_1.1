package handlers

import (
	"bytes"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

// GatewayHandlers handles API gateway routing and service communication
type GatewayHandlers struct {
	config     *config.Config
	httpClient *http.Client
}

// NewGatewayHandlers creates a new gateway handlers instance
func NewGatewayHandlers(config *config.Config, httpClient *http.Client) *GatewayHandlers {
	return &GatewayHandlers{
		config:     config,
		httpClient: httpClient,
	}
}

// ProxyRequest proxies requests to appropriate microservices
func (h *GatewayHandlers) ProxyRequest(serviceName string) gin.HandlerFunc {
	log.Printf("🔌 [ProxyRequest] Creating handler for service: %s", serviceName)
	return func(c *gin.Context) {
		log.Printf("🔌 [ProxyRequest] Handler called for %s: %s %s", serviceName, c.Request.Method, c.Request.URL.Path)
		// Get service URL
		serviceURL := h.getServiceURL(serviceName)
		if serviceURL == "" {
			log.Printf("❌ [ProxyRequest] Service URL not found for %s", serviceName)
			c.JSON(http.StatusNotFound, gin.H{"error": "Service not found"})
			return
		}
		log.Printf("✅ [ProxyRequest] Service URL: %s", serviceURL)

		// Build target URL - strip service prefix for microservices
		path := c.Request.URL.Path
		targetPath := h.transformPath(path, serviceName)
		targetURL := serviceURL + targetPath
		log.Printf("🎯 [ProxyRequest] Proxying to: %s", targetURL)
		if c.Request.URL.RawQuery != "" {
			targetURL += "?" + c.Request.URL.RawQuery
		}

		// Read request body
		var bodyReader io.Reader
		if c.Request.Body != nil {
			bodyBytes, err := io.ReadAll(c.Request.Body)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read request body"})
				return
			}
			bodyReader = bytes.NewReader(bodyBytes)
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

		// Make request to service
		resp, err := h.httpClient.Do(req)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "Service unavailable"})
			return
		}
		defer resp.Body.Close()

		// Copy response headers
		for key, values := range resp.Header {
			for _, value := range values {
				c.Header(key, value)
			}
		}

		// Copy response body
		c.Status(resp.StatusCode)
		io.Copy(c.Writer, resp.Body)
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
		// Transform /api/reports/* to /reports/* for reports service (purcha reports)
		if strings.HasPrefix(path, "/api/reports/") {
			return strings.Replace(path, "/api/reports/", "/reports/", 1)
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
		// Transform /api/notifications/* to /notifications/* for finance service
		// Notification routes are handled by finance service
		if strings.HasPrefix(path, "/api/notifications/") {
			return strings.Replace(path, "/api/notifications/", "/notifications/", 1)
		}
		if path == "/api/notifications" {
			return "/notifications"
		}
		// Transform /api/alarms/* to /alarms/* for finance service
		if strings.HasPrefix(path, "/api/alarms/") {
			return strings.Replace(path, "/api/alarms/", "/alarms/", 1)
		}
		if path == "/api/alarms" {
			return "/alarms"
		}
		// Transform /api/logs/* to /logs/* for finance service (app logging)
		if strings.HasPrefix(path, "/api/logs/") {
			return strings.Replace(path, "/api/logs/", "/logs/", 1)
		}
		if path == "/api/logs" {
			return "/logs"
		}
	case "saas":
		// Transform /api/inventory/brand-categories to /api/internal/brands/categories (for Flutter app)
		if path == "/api/inventory/brand-categories" {
			return "/api/internal/brands/categories"
		}
		if path == "/api/inventory/brand-subcategories" {
			return "/api/internal/brands/subcategories"
		}
		// Different transformations for different super-admin endpoints
		if strings.HasPrefix(path, "/api/super-admin/brands/onboarding-stats") ||
			strings.HasPrefix(path, "/api/super-admin/brands/packages") ||
			strings.HasPrefix(path, "/api/super-admin/tenants") {
			// These endpoints exist under /api/super-admin in saas service
			return path
		}
		// Transform other super-admin brand paths to internal paths
		if strings.HasPrefix(path, "/api/super-admin/brands") {
			return strings.Replace(path, "/api/super-admin/brands", "/api/internal/brands", 1)
		}
		// Transform /api/saas/brands/* to /api/internal/brands/* (for tenant access to brand catalog)
		if strings.HasPrefix(path, "/api/saas/brands/") {
			return strings.Replace(path, "/api/saas/brands/", "/api/internal/brands/", 1)
		}
		if strings.HasPrefix(path, "/api/saas/") {
			return strings.Replace(path, "/api/saas/", "/api/", 1)
		}
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

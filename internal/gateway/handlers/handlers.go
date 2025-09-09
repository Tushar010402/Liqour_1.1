package handlers

import (
	"bytes"
	"io"
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
	return func(c *gin.Context) {
		// Get service URL
		serviceURL := h.getServiceURL(serviceName)
		if serviceURL == "" {
			c.JSON(http.StatusNotFound, gin.H{"error": "Service not found"})
			return
		}

		// Build target URL - strip service prefix from path for microservices (not auth)
		path := c.Request.URL.Path
		
		// For non-auth services, remove service prefix (e.g., /api/inventory/categories -> /api/categories)
		if serviceName != "auth" && strings.HasPrefix(path, "/api/"+serviceName+"/") {
			path = "/api/" + strings.TrimPrefix(path, "/api/"+serviceName+"/")
		}
		
		targetURL := serviceURL + path
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
		"frontend": gin.H{
			"url":    h.config.Services.Frontend.URL,
			"status": h.checkServiceHealth(h.config.Services.Frontend.URL),
		},
	}

	c.JSON(http.StatusOK, gin.H{
		"gateway": h.config.Services.Gateway.URL,
		"services": services,
	})
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
	case "frontend":
		return h.config.Services.Frontend.URL
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
	case "frontend":
		h.config.Services.Frontend.URL = url
	}
}
package httpclient

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// Client wraps http.Client with correlation ID propagation
type Client struct {
	httpClient *http.Client
	logger     *zap.Logger
}

// New creates a new HTTP client with default configuration
func New(timeout time.Duration, logger *zap.Logger) *Client {
	return &Client{
		httpClient: &http.Client{
			Timeout: timeout,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 10,
				IdleConnTimeout:     90 * time.Second,
			},
		},
		logger: logger,
	}
}

// Do executes an HTTP request with correlation ID propagation
func (c *Client) Do(req *http.Request) (*http.Response, error) {
	start := time.Now()

	// Log outgoing request
	if c.logger != nil {
		c.logger.Debug("Outgoing HTTP request",
			zap.String("method", req.Method),
			zap.String("url", req.URL.String()),
			zap.String("correlation_id", req.Header.Get("X-Correlation-ID")),
		)
	}

	resp, err := c.httpClient.Do(req)
	duration := time.Since(start)

	// Log response
	if c.logger != nil {
		fields := []zap.Field{
			zap.String("method", req.Method),
			zap.String("url", req.URL.String()),
			zap.Duration("duration", duration),
			zap.String("correlation_id", req.Header.Get("X-Correlation-ID")),
		}

		if err != nil {
			fields = append(fields, zap.Error(err))
			c.logger.Error("HTTP request failed", fields...)
		} else {
			fields = append(fields, zap.Int("status_code", resp.StatusCode))
			if resp.StatusCode >= 500 {
				c.logger.Error("HTTP request server error", fields...)
			} else if resp.StatusCode >= 400 {
				c.logger.Warn("HTTP request client error", fields...)
			} else {
				c.logger.Debug("HTTP request completed", fields...)
			}
		}
	}

	return resp, err
}

// NewRequestWithContext creates a new HTTP request with correlation ID from Gin context
func NewRequestWithContext(c *gin.Context, method, url string, body interface{}) (*http.Request, error) {
	req, err := http.NewRequestWithContext(c.Request.Context(), method, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Propagate correlation ID
	if correlationID := c.GetString("correlation_id"); correlationID != "" {
		req.Header.Set("X-Correlation-ID", correlationID)
		req.Header.Set("X-Request-ID", correlationID)
	}

	// Propagate span ID (create parent-child relationship)
	if spanID := c.GetString("span_id"); spanID != "" {
		req.Header.Set("X-Parent-Span-ID", spanID)
	}

	// Add service identification
	if serviceName := c.GetString("service_name"); serviceName != "" {
		req.Header.Set("X-Source-Service", serviceName)
	}

	// Propagate tenant context
	if tenantID := c.GetString("tenant_id"); tenantID != "" {
		req.Header.Set("X-Tenant-ID", tenantID)
	}

	// Propagate user context
	if userID := c.GetString("user_id"); userID != "" {
		req.Header.Set("X-User-ID", userID)
	}

	// Copy authorization header if present
	if auth := c.GetHeader("Authorization"); auth != "" {
		req.Header.Set("Authorization", auth)
	}

	return req, nil
}

// NewRequestWithContextAndBody creates a new HTTP request with body and correlation ID
func NewRequestWithContextAndBody(ctx context.Context, method, url string, body interface{}) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Try to extract correlation ID from context
	if correlationID, ok := ctx.Value("correlation_id").(string); ok && correlationID != "" {
		req.Header.Set("X-Correlation-ID", correlationID)
		req.Header.Set("X-Request-ID", correlationID)
	}

	return req, nil
}

// PropagateHeaders copies trace headers from source to destination request
func PropagateHeaders(source *http.Request, dest *http.Request) {
	traceHeaders := []string{
		"X-Correlation-ID",
		"X-Request-ID",
		"X-Span-ID",
		"X-Parent-Span-ID",
		"X-Source-Service",
		"X-Tenant-ID",
		"X-User-ID",
	}

	for _, header := range traceHeaders {
		if value := source.Header.Get(header); value != "" {
			dest.Header.Set(header, value)
		}
	}
}

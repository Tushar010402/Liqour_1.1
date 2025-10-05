package middleware

import (
	"github.com/gin-gonic/gin"
)

// SecurityHeaders adds security headers to all responses
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Prevent clickjacking attacks
		c.Header("X-Frame-Options", "DENY")

		// Prevent MIME type sniffing
		c.Header("X-Content-Type-Options", "nosniff")

		// Enable XSS protection in browsers
		c.Header("X-XSS-Protection", "1; mode=block")

		// Enforce HTTPS (only in production)
		if gin.Mode() == gin.ReleaseMode {
			c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload")
		}

		// Content Security Policy - restrict resource loading
		c.Header("Content-Security-Policy",
			"default-src 'self'; "+
			"script-src 'self' 'unsafe-inline' 'unsafe-eval'; "+
			"style-src 'self' 'unsafe-inline'; "+
			"img-src 'self' data: https:; "+
			"font-src 'self'; "+
			"connect-src 'self'; "+
			"frame-ancestors 'none'; "+
			"base-uri 'self'; "+
			"form-action 'self'")

		// Referrer policy - control referrer information
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// Feature policy / Permissions policy
		c.Header("Permissions-Policy",
			"geolocation=(), "+
			"microphone=(), "+
			"camera=(), "+
			"payment=(), "+
			"usb=(), "+
			"magnetometer=(), "+
			"gyroscope=(), "+
			"accelerometer=()")

		// Prevent caching of sensitive data
		if c.Request.URL.Path != "/health" && c.Request.URL.Path != "/metrics" {
			c.Header("Cache-Control", "no-store, no-cache, must-revalidate, private")
			c.Header("Pragma", "no-cache")
			c.Header("Expires", "0")
		}

		c.Next()
	}
}

// APISecurityHeaders adds API-specific security headers
func APISecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Add security headers
		SecurityHeaders()(c)

		// API-specific headers
		c.Header("X-Robots-Tag", "noindex, nofollow")

		// Prevent DNS prefetching
		c.Header("X-DNS-Prefetch-Control", "off")

		c.Next()
	}
}

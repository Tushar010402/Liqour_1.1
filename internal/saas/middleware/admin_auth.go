package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// AdminAuthMiddleware provides authentication for SaaS admin routes
func AdminAuthMiddleware(jwtSecret string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get token from Authorization header
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header required"})
			c.Abort()
			return
		}

		// Extract token
		tokenString := strings.TrimPrefix(authHeader, "Bearer ")
		if tokenString == authHeader {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Bearer token required"})
			c.Abort()
			return
		}

		// Parse and validate token
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			return []byte(jwtSecret), nil
		})

		if err != nil || !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
			c.Abort()
			return
		}

		// Extract claims
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token claims"})
			c.Abort()
			return
		}

		// Set user context for admin operations
		if userID, ok := claims["user_id"].(string); ok {
			c.Set("user_id", userID)
			c.Set("admin_user_id", userID)
		} else {
			// Generate a default admin ID for system operations
			adminID := uuid.New().String()
			c.Set("user_id", adminID)
			c.Set("admin_user_id", adminID)
		}

		// Set role
		if role, ok := claims["role"].(string); ok {
			c.Set("role", role)
		} else {
			c.Set("role", "saas_admin")
		}

		// Set mobile for tracking
		if mobile, ok := claims["mobile"].(string); ok {
			c.Set("mobile", mobile)
		}

		c.Next()
	}
}

// SetAdminContext sets admin context without full authentication (for testing)
func SetAdminContext() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check if user_id already set
		if c.GetString("user_id") == "" {
			// Set default admin context
			adminID := "00000000-0000-0000-0000-000000000001" // System admin ID
			c.Set("user_id", adminID)
			c.Set("admin_user_id", adminID)
			c.Set("role", "saas_admin")
			c.Set("is_super_admin", true)
		}
		c.Next()
	}
}

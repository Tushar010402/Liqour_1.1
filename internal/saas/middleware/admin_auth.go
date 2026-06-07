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

		// Extract permissions from JWT claims
		if permsRaw, ok := claims["permissions"].([]interface{}); ok {
			var perms []string
			for _, p := range permsRaw {
				if pStr, ok := p.(string); ok {
					perms = append(perms, pStr)
				}
			}
			c.Set("permissions", perms)
		}

		// Set department
		if dept, ok := claims["department"].(string); ok {
			c.Set("department", dept)
		}

		c.Next()
	}
}

// AdminPermissionMiddleware checks if the admin user has the required permission
func AdminPermissionMiddleware(requiredPermission string) gin.HandlerFunc {
	return func(c *gin.Context) {
		role := c.GetString("role")

		// super_admin bypasses all permission checks
		if role == "super_admin" {
			c.Next()
			return
		}

		// Get permissions from context (set by AdminAuthMiddleware or superAdmin middleware)
		perms, exists := c.Get("permissions")
		if !exists {
			c.JSON(http.StatusForbidden, gin.H{"error": "No permissions found"})
			c.Abort()
			return
		}

		permsList, ok := perms.([]string)
		if !ok {
			c.JSON(http.StatusForbidden, gin.H{"error": "Invalid permissions format"})
			c.Abort()
			return
		}

		// Check if user has the required permission
		for _, p := range permsList {
			if p == requiredPermission {
				c.Next()
				return
			}
		}

		c.JSON(http.StatusForbidden, gin.H{
			"error":      "Insufficient permissions",
			"required":   requiredPermission,
		})
		c.Abort()
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

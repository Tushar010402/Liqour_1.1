package middleware

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
)

// Helper function to get minimum of two integers
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// AuthMiddleware validates JWT tokens
func AuthMiddleware(jwtConfig config.JWTConfig, cacheClient *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = c.GetString("request_id")
		}

		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":      "Authorization header required",
				"details":    "Please include the Authorization header in the format: Bearer <token>",
				"request_id": requestID,
			})
			c.Abort()
			return
		}

		// Extract token from "Bearer <token>"
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":      "Invalid authorization header format",
				"details":    "Expected format: Bearer <token>",
				"got":        fmt.Sprintf("%s...", authHeader[:min(20, len(authHeader))]),
				"request_id": requestID,
			})
			c.Abort()
			return
		}

		tokenString := parts[1]

		// Parse and validate token
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			// Validate signing method
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(jwtConfig.Secret), nil
		})

		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":      "Invalid token",
				"details":    err.Error(),
				"request_id": requestID,
			})
			c.Abort()
			return
		}

		if !token.Valid {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":      "Token is not valid",
				"details":    "Token validation failed",
				"request_id": requestID,
			})
			c.Abort()
			return
		}

		// Extract claims
		claims, ok := token.Claims.(jwt.MapClaims)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":      "Invalid token claims",
				"request_id": requestID,
			})
			c.Abort()
			return
		}

		// Extract user_id from claims
		userID, ok := claims["user_id"].(string)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{
				"error":      "Invalid user ID in token",
				"request_id": requestID,
			})
			c.Abort()
			return
		}

		// Check session validity - device-specific or user-level
		if sessionID, ok := claims["session_id"].(string); ok && sessionID != "" {
			// Device-specific session validation
			deviceKey := fmt.Sprintf("session:device:%s", sessionID)
			exists, err := cacheClient.Exists(c.Request.Context(), deviceKey)
			if err != nil || !exists {
				c.JSON(http.StatusUnauthorized, gin.H{
					"error":      "Session expired",
					"details":    "This device has been logged out. Please log in again.",
					"request_id": requestID,
				})
				c.Abort()
				return
			}
		} else {
			// Fallback: User-level validation (for tokens without session_id)
			sessionKey := fmt.Sprintf(cache.UserSessionKey, userID)
			exists, err := cacheClient.Exists(c.Request.Context(), sessionKey)
			if err != nil || !exists {
				c.JSON(http.StatusUnauthorized, gin.H{
					"error":      "Session expired",
					"details":    "Please log in again",
					"request_id": requestID,
				})
				c.Abort()
				return
			}
		}

		// Set user context
		c.Set("user_id", userID)
		c.Set("tenant_id", claims["tenant_id"])
		c.Set("role", claims["role"])
		c.Set("permissions", claims["permissions"])

		c.Next()
	}
}

// TenantMiddleware ensures tenant isolation
func TenantMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		tenantID := c.GetString("tenant_id")
		userRole := c.GetString("role")

		// Allow Super Users (saas_admin) to access resources without tenant restrictions
		if userRole == "saas_admin" {
			c.Next()
			return
		}

		if tenantID == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Tenant ID required"})
			c.Abort()
			return
		}

		c.Set("tenant_id", tenantID)
		c.Next()
	}
}

// RoleMiddleware checks user roles
func RoleMiddleware(allowedRoles ...string) gin.HandlerFunc {
	return func(c *gin.Context) {
		userRole := c.GetString("role")
		if userRole == "" {
			c.JSON(http.StatusForbidden, gin.H{"error": "Role not found"})
			c.Abort()
			return
		}

		for _, role := range allowedRoles {
			if userRole == role {
				c.Next()
				return
			}
		}

		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		c.Abort()
	}
}

// RoleHierarchy returns the level of a role (higher = more permissions)
func RoleHierarchy(role string) int {
	hierarchy := map[string]int{
		"saas_admin":        100,
		"admin":             90,
		"manager":           70,
		"assistant_manager": 50,
		"executive":         30,
		"salesman":          10,
	}
	if level, ok := hierarchy[role]; ok {
		return level
	}
	return 0
}

// CanManageRole checks if a role can manage (create/update/delete) another role
func CanManageRole(actorRole, targetRole string) bool {
	return RoleHierarchy(actorRole) > RoleHierarchy(targetRole)
}

// GetManageableRoles returns a list of roles that the given role can manage
func GetManageableRoles(actorRole string) []string {
	actorLevel := RoleHierarchy(actorRole)
	allRoles := []string{"admin", "manager", "assistant_manager", "executive", "salesman"}
	var manageable []string
	for _, role := range allRoles {
		if RoleHierarchy(role) < actorLevel {
			manageable = append(manageable, role)
		}
	}
	return manageable
}

// PermissionMiddleware checks specific permissions
func PermissionMiddleware(requiredPermission string) gin.HandlerFunc {
	return func(c *gin.Context) {
		permissions, exists := c.Get("permissions")
		if !exists {
			c.JSON(http.StatusForbidden, gin.H{"error": "Permissions not found"})
			c.Abort()
			return
		}

		permList, ok := permissions.([]interface{})
		if !ok {
			c.JSON(http.StatusForbidden, gin.H{"error": "Invalid permissions format"})
			c.Abort()
			return
		}

		for _, perm := range permList {
			if permStr, ok := perm.(string); ok && permStr == requiredPermission {
				c.Next()
				return
			}
		}

		c.JSON(http.StatusForbidden, gin.H{"error": "Insufficient permissions"})
		c.Abort()
	}
}

// OptionalAuthMiddleware validates JWT tokens but doesn't fail if missing
func OptionalAuthMiddleware(jwtConfig config.JWTConfig, cacheClient *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			c.Next()
			return
		}

		// Extract token from "Bearer <token>"
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			c.Next()
			return
		}

		tokenString := parts[1]

		// Parse and validate token
		token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				return nil, jwt.ErrSignatureInvalid
			}
			return []byte(jwtConfig.Secret), nil
		})

		if err != nil || !token.Valid {
			c.Next()
			return
		}

		// Extract claims if token is valid
		if claims, ok := token.Claims.(jwt.MapClaims); ok {
			if userID, ok := claims["user_id"].(string); ok {
				sessionKey := fmt.Sprintf(cache.UserSessionKey, userID)
				if exists, _ := cacheClient.Exists(c.Request.Context(), sessionKey); exists {
					c.Set("user_id", userID)
					c.Set("tenant_id", claims["tenant_id"])
					c.Set("role", claims["role"])
					c.Set("permissions", claims["permissions"])
				}
			}
		}

		c.Next()
	}
}

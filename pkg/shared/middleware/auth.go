package middleware

import (
	"fmt"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/utils"
)

// AuthMiddleware validates JWT tokens
func AuthMiddleware(jwtConfig config.JWTConfig, cacheClient *cache.Cache) gin.HandlerFunc {
	return func(c *gin.Context) {
		authHeader := c.GetHeader("Authorization")
		if authHeader == "" {
			utils.HandleUnauthorized(c, "Authorization header required")
			c.Abort()
			return
		}

		// Extract token from "Bearer <token>"
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			utils.HandleUnauthorized(c, "Invalid authorization header format")
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
			utils.HandleUnauthorized(c, "Invalid token")
			c.Abort()
			return
		}

		if !token.Valid {
			utils.HandleUnauthorized(c, "Token is not valid")
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

		// Check if session exists in cache
		userID, ok := claims["user_id"].(string)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid user ID in token"})
			c.Abort()
			return
		}

		sessionKey := fmt.Sprintf(cache.UserSessionKey, userID)
		exists, err := cacheClient.Exists(c.Request.Context(), sessionKey)
		if err != nil || !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Session expired"})
			c.Abort()
			return
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
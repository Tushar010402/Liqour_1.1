package handlers

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
	ws "github.com/liquorpro/go-backend/pkg/shared/websocket"
	"go.uber.org/zap"
)

// WebSocket upgrader configuration
var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// Allow all origins for now (should be restricted in production)
		return true
	},
}

// HandleWebSocket handles WebSocket connections
func HandleWebSocket(logger *zap.Logger, jwtSecret string) gin.HandlerFunc {
	hub := ws.GetHub(logger)

	return func(c *gin.Context) {
		// Debug logging for WebSocket connection attempt
		fmt.Printf("🔌 [WebSocket] Connection attempt from: %s\n", c.ClientIP())
		fmt.Printf("🔌 [WebSocket] Request URL: %s\n", c.Request.URL.String())
		fmt.Printf("🔌 [WebSocket] Headers: %v\n", c.Request.Header)

		// Get token from query parameter
		token := c.Query("token")
		if token == "" {
			fmt.Printf("❌ [WebSocket] Missing token in query parameters\n")
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Missing token"})
			return
		}

		fmt.Printf("✅ [WebSocket] Token received (length: %d chars)\n", len(token))

		// Verify JWT token
		claims := jwt.MapClaims{}
		parsedToken, err := jwt.ParseWithClaims(token, claims, func(token *jwt.Token) (interface{}, error) {
			if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
				fmt.Printf("❌ [WebSocket] Invalid signing method: %v\n", token.Header["alg"])
				return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
			}
			return []byte(jwtSecret), nil
		})

		if err != nil || !parsedToken.Valid {
			fmt.Printf("❌ [WebSocket] Token validation failed: %v\n", err)
			c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid token"})
			return
		}

		fmt.Printf("✅ [WebSocket] Token validated successfully\n")

		// Extract tenant ID
		tenantID, ok := claims["tenant_id"].(string)
		if !ok {
			tenantID = c.Query("tenant_id")
			if tenantID == "" {
				fmt.Printf("❌ [WebSocket] Missing tenant_id in token and query\n")
				c.JSON(http.StatusBadRequest, gin.H{"error": "Missing tenant_id"})
				return
			}
			fmt.Printf("⚠️ [WebSocket] Tenant ID from query parameter: %s\n", tenantID)
		} else {
			fmt.Printf("✅ [WebSocket] Tenant ID from token: %s\n", tenantID)
		}

		// Upgrade connection
		fmt.Printf("🔄 [WebSocket] Attempting to upgrade connection...\n")
		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			fmt.Printf("❌ [WebSocket] Failed to upgrade connection: %v\n", err)
			logger.Error("Failed to upgrade WebSocket connection", zap.Error(err))
			return
		}

		fmt.Printf("✅ [WebSocket] Connection upgraded successfully\n")

		// Create client
		clientID := fmt.Sprintf("%s-%d", tenantID, time.Now().UnixNano())
		fmt.Printf("🆔 [WebSocket] Created client ID: %s\n", clientID)
		client := ws.NewClient(clientID, tenantID, conn, hub)

		// Register client
		hub.RegisterClient(client)
		fmt.Printf("✅ [WebSocket] Client registered and connected\n")

		// Start goroutines
		go client.WritePump()
		go client.ReadPump()
	}
}

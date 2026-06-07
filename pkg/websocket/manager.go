package websocket

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"github.com/liquorpro/go-backend/pkg/messaging"
	"go.uber.org/zap"
)

// Manager manages WebSocket connections and integrates with other services
type Manager struct {
	hub          *Hub
	kafkaClient  *messaging.KafkaClient
	logger       *zap.Logger
	upgrader     websocket.Upgrader
	authFunc     AuthFunc
	eventChannel chan *messaging.BusinessEvent
}

// AuthFunc is a function type for authenticating WebSocket connections
type AuthFunc func(token string) (userID, tenantID, role string, err error)

// ManagerConfig contains configuration for the WebSocket manager
type ManagerConfig struct {
	KafkaClient *messaging.KafkaClient
	Logger      *zap.Logger
	AuthFunc    AuthFunc
}

// NewManager creates a new WebSocket manager
func NewManager(config ManagerConfig) *Manager {
	hub := NewHub(config.Logger)

	manager := &Manager{
		hub:         hub,
		kafkaClient: config.KafkaClient,
		logger:      config.Logger,
		authFunc:    config.AuthFunc,
		eventChannel: make(chan *messaging.BusinessEvent, 100),
		upgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				// In production, implement proper origin checking
				return true
			},
		},
	}

	// Start the hub
	go hub.Run()

	// Start Kafka event listener if available
	if config.KafkaClient != nil {
		go manager.listenToKafkaEvents()
	}

	return manager
}

// HandleWebSocket handles WebSocket upgrade requests
func (m *Manager) HandleWebSocket(c *gin.Context) {
	// Extract authentication token from query params or headers
	token := c.Query("token")
	if token == "" {
		authHeader := c.GetHeader("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	// Authenticate the connection
	userID, tenantID, role, err := m.authFunc(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authentication failed"})
		return
	}

	// Upgrade HTTP connection to WebSocket
	conn, err := m.upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		m.logger.Error("Failed to upgrade connection", zap.Error(err))
		return
	}

	// Create new client
	client := NewClient(ClientOptions{
		UserID:   userID,
		TenantID: tenantID,
		Role:     role,
		Conn:     conn,
		Hub:      m.hub,
		Logger:   m.logger,
	})

	// Register client with hub
	m.hub.register <- client

	// Start client pumps
	go client.WritePump(m.logger)
	go client.ReadPump(m.logger)

	m.logger.Info("WebSocket connection established",
		zap.String("user_id", userID),
		zap.String("tenant_id", tenantID),
		zap.String("role", role))
}

// listenToKafkaEvents listens to Kafka events and broadcasts them via WebSocket
func (m *Manager) listenToKafkaEvents() {
	// Subscribe to multiple Kafka topics
	topics := []string{
		"sales-events",
		"inventory-events",
		"payment-events",
		"notification-events",
	}

	for _, topic := range topics {
		go m.subscribeToTopic(topic)
	}

	// Process events and broadcast via WebSocket
	for event := range m.eventChannel {
		m.processAndBroadcastEvent(event)
	}
}

// subscribeToTopic subscribes to a Kafka topic
func (m *Manager) subscribeToTopic(topic string) {
	err := m.kafkaClient.Subscribe(topic, "websocket-manager", func(ctx context.Context, msg messaging.Message) error {
		// Parse business event
		var event messaging.BusinessEvent
		if eventData, ok := msg.Value.(map[string]interface{}); ok {
			// Convert map to BusinessEvent
			eventJSON, _ := json.Marshal(eventData)
			if err := json.Unmarshal(eventJSON, &event); err == nil {
				select {
				case m.eventChannel <- &event:
				default:
					m.logger.Warn("Event channel full, dropping event",
						zap.String("event_type", string(event.Type)))
				}
			}
		}
		return nil
	})

	if err != nil {
		m.logger.Error("Failed to subscribe to Kafka topic",
			zap.String("topic", topic),
			zap.Error(err))
	}
}

// processAndBroadcastEvent processes Kafka events and broadcasts them via WebSocket
func (m *Manager) processAndBroadcastEvent(event *messaging.BusinessEvent) {
	// Convert Kafka event to WebSocket message
	wsMessage := &Message{
		ID:        event.ID,
		Type:      m.mapEventTypeToMessageType(event.Type),
		Channel:   m.getChannelForEvent(event.Type),
		Data:      event.Data,
		Timestamp: event.Timestamp,
		TenantID:  event.TenantID,
	}

	// Broadcast based on event type and tenant
	if event.TenantID != "" {
		// Send to specific tenant
		m.hub.BroadcastToTenant(event.TenantID, wsMessage)
	} else if wsMessage.Channel != "" {
		// Send to channel subscribers
		m.hub.BroadcastToChannel(wsMessage.Channel, wsMessage)
	} else {
		// Broadcast to all (use sparingly)
		m.hub.BroadcastToAll(wsMessage)
	}

	m.logger.Debug("Event broadcasted via WebSocket",
		zap.String("event_id", event.ID),
		zap.String("event_type", string(event.Type)),
		zap.String("tenant_id", event.TenantID))
}

// mapEventTypeToMessageType maps Kafka event types to WebSocket message types
func (m *Manager) mapEventTypeToMessageType(eventType messaging.EventType) MessageType {
	switch eventType {
	case messaging.EventTypeSaleCreated, messaging.EventTypeSaleUpdated:
		return MessageTypeSaleUpdate
	case messaging.EventTypeInventoryUpdated, messaging.EventTypeStockLow:
		return MessageTypeInventoryUpdate
	case messaging.EventTypePaymentProcessed:
		return MessageTypeCashFlow
	case messaging.EventTypeNotification:
		return MessageTypeNotification
	default:
		return MessageTypeDashboard
	}
}

// getChannelForEvent determines the appropriate channel for an event type
func (m *Manager) getChannelForEvent(eventType messaging.EventType) string {
	switch eventType {
	case messaging.EventTypeSaleCreated, messaging.EventTypeSaleUpdated:
		return "sales"
	case messaging.EventTypeInventoryUpdated, messaging.EventTypeStockLow:
		return "inventory"
	case messaging.EventTypePaymentProcessed:
		return "cashflow"
	case messaging.EventTypeNotification:
		return "notifications"
	default:
		return "dashboard"
	}
}

// BroadcastInventoryUpdate broadcasts an inventory update to relevant clients
func (m *Manager) BroadcastInventoryUpdate(tenantID string, productID string, updates map[string]interface{}) {
	message := &Message{
		Type:      MessageTypeInventoryUpdate,
		Channel:   "inventory",
		TenantID:  tenantID,
		Timestamp: time.Now(),
		Data: map[string]interface{}{
			"product_id": productID,
			"updates":    updates,
		},
	}

	m.hub.BroadcastToTenant(tenantID, message)
}

// BroadcastSaleUpdate broadcasts a sale update to relevant clients
func (m *Manager) BroadcastSaleUpdate(tenantID string, saleID string, saleData map[string]interface{}) {
	message := &Message{
		Type:      MessageTypeSaleUpdate,
		Channel:   "sales",
		TenantID:  tenantID,
		Timestamp: time.Now(),
		Data: map[string]interface{}{
			"sale_id": saleID,
			"sale":    saleData,
		},
	}

	m.hub.BroadcastToTenant(tenantID, message)
}

// BroadcastCashFlowUpdate broadcasts cash flow updates
func (m *Manager) BroadcastCashFlowUpdate(tenantID string, flowType string, amount float64, details map[string]interface{}) {
	message := &Message{
		Type:      MessageTypeCashFlow,
		Channel:   "cashflow",
		TenantID:  tenantID,
		Timestamp: time.Now(),
		Data: map[string]interface{}{
			"type":    flowType,
			"amount":  amount,
			"details": details,
		},
	}

	m.hub.BroadcastToTenant(tenantID, message)
}

// BroadcastNotification sends a notification to specific users or all users of a tenant
func (m *Manager) BroadcastNotification(tenantID, userID string, notification map[string]interface{}) {
	message := &Message{
		Type:      MessageTypeNotification,
		Channel:   "notifications",
		TenantID:  tenantID,
		UserID:    userID,
		Timestamp: time.Now(),
		Data:      notification,
	}

	if userID != "" {
		// Send to specific user (would need to implement user-specific routing)
		// For now, send to tenant
		m.hub.BroadcastToTenant(tenantID, message)
	} else {
		m.hub.BroadcastToTenant(tenantID, message)
	}
}

// BroadcastDashboardUpdate broadcasts dashboard metric updates
func (m *Manager) BroadcastDashboardUpdate(tenantID string, metrics map[string]interface{}) {
	message := &Message{
		Type:      MessageTypeDashboard,
		Channel:   "dashboard",
		TenantID:  tenantID,
		Timestamp: time.Now(),
		Data: map[string]interface{}{
			"metrics": metrics,
			"updated_at": time.Now(),
		},
	}

	m.hub.BroadcastToTenant(tenantID, message)
}

// BroadcastOCRProgress broadcasts OCR processing progress updates (v1.0.28)
func (m *Manager) BroadcastOCRProgress(tenantID string, sessionID string, batchID string, progressData map[string]interface{}) {
	message := &Message{
		Type:      MessageTypeOCRProgress,
		Channel:   "ocr_progress",
		TenantID:  tenantID,
		Timestamp: time.Now(),
		Data: map[string]interface{}{
			"session_id": sessionID,
			"batch_id":   batchID,
			"progress":   progressData,
		},
	}

	m.logger.Info("📤 Broadcasting OCR progress to WebSocket clients",
		zap.String("tenant_id", tenantID),
		zap.String("batch_id", batchID),
		zap.String("session_id", sessionID),
		zap.Any("progress_data", progressData))

	m.hub.BroadcastToTenant(tenantID, message)

	m.logger.Info("✅ OCR progress broadcast queued for delivery",
		zap.String("tenant_id", tenantID),
		zap.String("batch_id", batchID))
}

// GetConnectionStats returns WebSocket connection statistics
func (m *Manager) GetConnectionStats() map[string]interface{} {
	stats := m.hub.GetStats()
	stats["kafka_connected"] = m.kafkaClient != nil
	return stats
}

// Shutdown gracefully shuts down the WebSocket manager
func (m *Manager) Shutdown() {
	m.logger.Info("Shutting down WebSocket manager")
	m.hub.Stop()
	close(m.eventChannel)
}

// SendDirectMessage sends a message directly to a specific client
func (m *Manager) SendDirectMessage(clientID string, message *Message) error {
	m.hub.mu.RLock()
	defer m.hub.mu.RUnlock()

	for client := range m.hub.clients {
		if client.ID == clientID {
			return client.SendMessage(message)
		}
	}
	return fmt.Errorf("client not found: %s", clientID)
}

// GetConnectedClients returns a list of connected clients
func (m *Manager) GetConnectedClients() []map[string]interface{} {
	m.hub.mu.RLock()
	defer m.hub.mu.RUnlock()

	clients := make([]map[string]interface{}, 0, len(m.hub.clients))
	for client := range m.hub.clients {
		clients = append(clients, map[string]interface{}{
			"id":       client.ID,
			"user_id":  client.UserID,
			"tenant_id": client.TenantID,
			"role":     client.Role,
			"channels": client.GetChannels(),
			"is_alive": client.IsAlive(),
		})
	}
	return clients
}
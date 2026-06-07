package websocket

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// MessageType defines the type of WebSocket message
type MessageType string

const (
	// Message types
	MessageTypeNotification   MessageType = "notification"
	MessageTypeInventoryUpdate MessageType = "inventory_update"
	MessageTypeSaleUpdate      MessageType = "sale_update"
	MessageTypeCashFlow        MessageType = "cash_flow"
	MessageTypeDashboard       MessageType = "dashboard"
	MessageTypeOCRProgress     MessageType = "ocr_progress"  // v1.0.28: OCR real-time progress
	MessageTypePing            MessageType = "ping"
	MessageTypePong            MessageType = "pong"
	MessageTypeAuth            MessageType = "auth"
	MessageTypeError           MessageType = "error"
	MessageTypeAck             MessageType = "ack"
)

// Message represents a WebSocket message
type Message struct {
	ID        string                 `json:"id"`
	Type      MessageType            `json:"type"`
	Channel   string                 `json:"channel"`
	Data      map[string]interface{} `json:"data"`
	Timestamp time.Time              `json:"timestamp"`
	TenantID  string                 `json:"tenant_id,omitempty"`
	UserID    string                 `json:"user_id,omitempty"`
}

// Client represents a WebSocket client
type Client struct {
	ID          string
	UserID      string
	TenantID    string
	Role        string
	conn        *websocket.Conn
	send        chan []byte
	hub         *Hub
	channels    map[string]bool
	isAlive     bool
	lastPing    time.Time
	mu          sync.RWMutex
}

// Hub maintains active clients and broadcasts messages
type Hub struct {
	// Registered clients
	clients map[*Client]bool

	// Channel subscriptions
	channels map[string]map[*Client]bool

	// Tenant-based client mapping
	tenants map[string]map[*Client]bool

	// Inbound messages from clients
	broadcast chan *Message

	// Register requests from clients
	register chan *Client

	// Unregister requests from clients
	unregister chan *Client

	// Logger
	logger *zap.Logger

	// Mutex for concurrent access
	mu sync.RWMutex

	// Context for graceful shutdown
	ctx    context.Context
	cancel context.CancelFunc
}

// NewHub creates a new WebSocket hub
func NewHub(logger *zap.Logger) *Hub {
	ctx, cancel := context.WithCancel(context.Background())
	return &Hub{
		clients:    make(map[*Client]bool),
		channels:   make(map[string]map[*Client]bool),
		tenants:    make(map[string]map[*Client]bool),
		broadcast:  make(chan *Message, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
		logger:     logger,
		ctx:        ctx,
		cancel:     cancel,
	}
}

// Run starts the hub's main loop
func (h *Hub) Run() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-h.ctx.Done():
			h.logger.Info("WebSocket hub shutting down")
			return

		case client := <-h.register:
			h.registerClient(client)

		case client := <-h.unregister:
			h.unregisterClient(client)

		case message := <-h.broadcast:
			h.broadcastMessage(message)

		case <-ticker.C:
			h.checkClientHealth()
		}
	}
}

// Stop gracefully shuts down the hub
func (h *Hub) Stop() {
	h.cancel()
	h.closeAllClients()
}

// RegisterClient registers a new client
func (h *Hub) registerClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	h.clients[client] = true

	// Add to tenant mapping
	if client.TenantID != "" {
		if h.tenants[client.TenantID] == nil {
			h.tenants[client.TenantID] = make(map[*Client]bool)
		}
		h.tenants[client.TenantID][client] = true
	}

	h.logger.Info("Client registered",
		zap.String("client_id", client.ID),
		zap.String("user_id", client.UserID),
		zap.String("tenant_id", client.TenantID))

	// Send welcome message
	welcome := &Message{
		Type: MessageTypeAck,
		Data: map[string]interface{}{
			"message":   "Connected to real-time service",
			"client_id": client.ID,
		},
		Timestamp: time.Now(),
	}

	if data, err := json.Marshal(welcome); err == nil {
		select {
		case client.send <- data:
		default:
			// Client's send channel is full
		}
	}
}

// UnregisterClient unregisters a client
func (h *Hub) unregisterClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, ok := h.clients[client]; ok {
		delete(h.clients, client)

		// Remove from tenant mapping
		if client.TenantID != "" {
			if tenantClients, exists := h.tenants[client.TenantID]; exists {
				delete(tenantClients, client)
				if len(tenantClients) == 0 {
					delete(h.tenants, client.TenantID)
				}
			}
		}

		// Remove from all channel subscriptions
		for channel := range client.channels {
			if channelClients, exists := h.channels[channel]; exists {
				delete(channelClients, client)
				if len(channelClients) == 0 {
					delete(h.channels, channel)
				}
			}
		}

		close(client.send)

		h.logger.Info("Client unregistered",
			zap.String("client_id", client.ID),
			zap.String("user_id", client.UserID))
	}
}

// BroadcastMessage broadcasts a message to relevant clients
func (h *Hub) broadcastMessage(message *Message) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	data, err := json.Marshal(message)
	if err != nil {
		h.logger.Error("Failed to marshal message", zap.Error(err))
		return
	}

	// Determine target clients based on message properties
	targetClients := make(map[*Client]bool)

	// If both channel and tenant are specified, send to BOTH channel subscribers AND tenant clients
	if message.Channel != "" && message.TenantID != "" {
		// Add channel subscribers
		if channelClients, exists := h.channels[message.Channel]; exists {
			for client := range channelClients {
				// Only include if client belongs to the tenant
				if client.TenantID == message.TenantID {
					targetClients[client] = true
				}
			}
		}
		// Also add all tenant clients (even if not subscribed to channel)
		// This ensures clients receive messages without explicit subscription
		if tenantClients, exists := h.tenants[message.TenantID]; exists {
			for client := range tenantClients {
				targetClients[client] = true
			}
		}
	} else if message.Channel != "" {
		// Send to specific channel subscribers only
		if channelClients, exists := h.channels[message.Channel]; exists {
			targetClients = channelClients
		}
	} else if message.TenantID != "" {
		// Send to specific tenant only
		if tenantClients, exists := h.tenants[message.TenantID]; exists {
			targetClients = tenantClients
		}
	} else {
		// Broadcast to all clients
		targetClients = h.clients
	}

	// Send message to target clients
	sentCount := 0
	for client := range targetClients {
		select {
		case client.send <- data:
			// Message sent successfully
			sentCount++
		default:
			// Client's send channel is full, close it
			h.logger.Warn("Client send channel full, disconnecting",
				zap.String("client_id", client.ID))
			go func(c *Client) {
				h.unregister <- c
			}(client)
		}
	}

	h.logger.Info("📨 Message broadcast delivered",
		zap.String("type", string(message.Type)),
		zap.String("channel", message.Channel),
		zap.String("tenant_id", message.TenantID),
		zap.Int("recipients", len(targetClients)),
		zap.Int("sent", sentCount))
}

// BroadcastToTenant sends a message to all clients of a specific tenant
func (h *Hub) BroadcastToTenant(tenantID string, message *Message) {
	message.TenantID = tenantID
	h.broadcast <- message
}

// BroadcastToChannel sends a message to all clients subscribed to a channel
func (h *Hub) BroadcastToChannel(channel string, message *Message) {
	message.Channel = channel
	h.broadcast <- message
}

// BroadcastToAll sends a message to all connected clients
func (h *Hub) BroadcastToAll(message *Message) {
	h.broadcast <- message
}

// SubscribeClientToChannel subscribes a client to a channel
func (h *Hub) SubscribeClientToChannel(client *Client, channel string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.channels[channel] == nil {
		h.channels[channel] = make(map[*Client]bool)
	}
	h.channels[channel][client] = true
	client.channels[channel] = true

	h.logger.Info("Client subscribed to channel",
		zap.String("client_id", client.ID),
		zap.String("channel", channel))
}

// UnsubscribeClientFromChannel unsubscribes a client from a channel
func (h *Hub) UnsubscribeClientFromChannel(client *Client, channel string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if channelClients, exists := h.channels[channel]; exists {
		delete(channelClients, client)
		if len(channelClients) == 0 {
			delete(h.channels, channel)
		}
	}
	delete(client.channels, channel)

	h.logger.Info("Client unsubscribed from channel",
		zap.String("client_id", client.ID),
		zap.String("channel", channel))
}

// checkClientHealth checks the health of all connected clients
func (h *Hub) checkClientHealth() {
	h.mu.RLock()
	clients := make([]*Client, 0, len(h.clients))
	for client := range h.clients {
		clients = append(clients, client)
	}
	h.mu.RUnlock()

	for _, client := range clients {
		client.mu.RLock()
		timeSinceLastPing := time.Since(client.lastPing)
		client.mu.RUnlock()

		if timeSinceLastPing > 60*time.Second {
			h.logger.Warn("Client inactive, disconnecting",
				zap.String("client_id", client.ID),
				zap.Duration("inactive_duration", timeSinceLastPing))
			h.unregister <- client
		} else if timeSinceLastPing > 30*time.Second {
			// Send ping to check if client is still alive
			ping := &Message{
				Type:      MessageTypePing,
				Timestamp: time.Now(),
			}
			if data, err := json.Marshal(ping); err == nil {
				select {
				case client.send <- data:
				default:
					// Channel full, will be handled in next iteration
				}
			}
		}
	}
}

// closeAllClients closes all client connections
func (h *Hub) closeAllClients() {
	h.mu.Lock()
	defer h.mu.Unlock()

	for client := range h.clients {
		close(client.send)
		client.conn.Close()
	}
	h.clients = make(map[*Client]bool)
	h.channels = make(map[string]map[*Client]bool)
	h.tenants = make(map[string]map[*Client]bool)
}

// GetStats returns hub statistics
func (h *Hub) GetStats() map[string]interface{} {
	h.mu.RLock()
	defer h.mu.RUnlock()

	tenantCount := make(map[string]int)
	for tenantID, clients := range h.tenants {
		tenantCount[tenantID] = len(clients)
	}

	channelCount := make(map[string]int)
	for channel, clients := range h.channels {
		channelCount[channel] = len(clients)
	}

	return map[string]interface{}{
		"total_clients":    len(h.clients),
		"total_tenants":    len(h.tenants),
		"total_channels":   len(h.channels),
		"clients_by_tenant": tenantCount,
		"clients_by_channel": channelCount,
	}
}
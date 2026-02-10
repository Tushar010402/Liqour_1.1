package websocket

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

// Message types
type Message struct {
	Type      string                 `json:"type"`
	Channel   string                 `json:"channel"`
	Data      map[string]interface{} `json:"data"`
	Timestamp time.Time              `json:"timestamp"`
}

// Client represents a WebSocket client
type Client struct {
	ID         string
	TenantID   string
	Conn       *websocket.Conn
	Send       chan Message
	Hub        *Hub
	Channels   map[string]bool // Subscribed channels
	mu         sync.RWMutex
	ctx        context.Context
	cancelFunc context.CancelFunc
}

// Hub manages all active clients
type Hub struct {
	clients    map[string]*Client             // client ID -> client
	tenants    map[string]map[string]bool     // tenant ID -> set of client IDs
	channels   map[string]map[string]bool     // channel name -> set of client IDs
	broadcast  chan Message
	register   chan *Client
	unregister chan *Client
	mu         sync.RWMutex
	logger     *zap.Logger
	maxClients int
}

// Global hub instance
var hub *Hub
var hubOnce sync.Once

// GetHub returns the singleton WebSocket hub instance
func GetHub(logger *zap.Logger) *Hub {
	hubOnce.Do(func() {
		hub = &Hub{
			clients:    make(map[string]*Client),
			tenants:    make(map[string]map[string]bool),
			channels:   make(map[string]map[string]bool),
			broadcast:  make(chan Message, 4096),
			register:   make(chan *Client),
			unregister: make(chan *Client),
			logger:     logger,
			maxClients: 10000,
		}
		go hub.Run()
	})
	return hub
}

// Run starts the WebSocket hub
func (h *Hub) Run() {
	if h.logger != nil {
		h.logger.Info("🔌 WebSocket Hub started")
	}
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			if h.maxClients > 0 && len(h.clients) >= h.maxClients {
				h.mu.Unlock()
				if h.logger != nil {
					h.logger.Warn("WebSocket connection rejected: max clients reached",
						zap.Int("max_clients", h.maxClients),
						zap.String("client_id", client.ID))
				}
				close(client.Send)
				client.Conn.Close()
				continue
			}
			h.clients[client.ID] = client

			// Add to tenant map
			if h.tenants[client.TenantID] == nil {
				h.tenants[client.TenantID] = make(map[string]bool)
			}
			h.tenants[client.TenantID][client.ID] = true
			h.mu.Unlock()

			if h.logger != nil {
				h.logger.Info("WebSocket client connected",
					zap.String("client_id", client.ID),
					zap.String("tenant_id", client.TenantID),
					zap.Int("total_clients", len(h.clients)))
			}

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client.ID]; ok {
				// Remove from channels
				for channel := range client.Channels {
					if h.channels[channel] != nil {
						delete(h.channels[channel], client.ID)
						if len(h.channels[channel]) == 0 {
							delete(h.channels, channel)
						}
					}
				}

				// Remove from tenants
				if h.tenants[client.TenantID] != nil {
					delete(h.tenants[client.TenantID], client.ID)
					if len(h.tenants[client.TenantID]) == 0 {
						delete(h.tenants, client.TenantID)
					}
				}

				delete(h.clients, client.ID)
				close(client.Send)
			}
			h.mu.Unlock()

			if h.logger != nil {
				h.logger.Info("❌ WebSocket client disconnected",
					zap.String("client_id", client.ID),
					zap.String("tenant_id", client.TenantID))
			}

		case message := <-h.broadcast:
			h.mu.RLock()
			var targets []*Client

			// Snapshot client pointers under single lock (no per-client re-lock)
			if message.Channel != "" {
				if subscribers, ok := h.channels[message.Channel]; ok {
					targets = make([]*Client, 0, len(subscribers))
					for clientID := range subscribers {
						if client, ok := h.clients[clientID]; ok {
							targets = append(targets, client)
						}
					}
				}
			}
			h.mu.RUnlock()

			// Send to all targets without holding any lock
			for _, client := range targets {
				select {
				case client.Send <- message:
					// Message sent successfully
				default:
					// Client's send channel is full, disconnect
					if h.logger != nil {
						h.logger.Warn("WebSocket send buffer full, disconnecting client",
							zap.String("client_id", client.ID))
					}
					go func(c *Client) { h.unregister <- c }(client)
				}
			}
		}
	}
}

// Broadcast sends a message to all clients subscribed to a channel
func (h *Hub) Broadcast(channel string, messageType string, data map[string]interface{}) {
	message := Message{
		Type:      messageType,
		Channel:   channel,
		Data:      data,
		Timestamp: time.Now(),
	}

	select {
	case h.broadcast <- message:
		if h.logger != nil {
			h.logger.Debug("📡 Broadcasting message",
				zap.String("channel", channel),
				zap.String("type", messageType))
		}
	default:
		if h.logger != nil {
			h.logger.Warn("⚠️  Broadcast channel full, message dropped",
				zap.String("channel", channel))
		}
	}
}

// Subscribe adds a client to a channel
func (h *Hub) Subscribe(clientID, channel string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if client, ok := h.clients[clientID]; ok {
		client.mu.Lock()
		client.Channels[channel] = true
		client.mu.Unlock()

		if h.channels[channel] == nil {
			h.channels[channel] = make(map[string]bool)
		}
		h.channels[channel][clientID] = true

		if h.logger != nil {
			h.logger.Info("📢 Client subscribed to channel",
				zap.String("client_id", clientID),
				zap.String("channel", channel))
		}
	}
}

// Unsubscribe removes a client from a channel
func (h *Hub) Unsubscribe(clientID, channel string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if client, ok := h.clients[clientID]; ok {
		client.mu.Lock()
		delete(client.Channels, channel)
		client.mu.Unlock()

		if h.channels[channel] != nil {
			delete(h.channels[channel], clientID)
			if len(h.channels[channel]) == 0 {
				delete(h.channels, channel)
			}
		}

		if h.logger != nil {
			h.logger.Info("🔇 Client unsubscribed from channel",
				zap.String("client_id", clientID),
				zap.String("channel", channel))
		}
	}
}

// RegisterClient registers a new client
func (h *Hub) RegisterClient(client *Client) {
	h.register <- client
}

// UnregisterClient unregisters a client
func (h *Hub) UnregisterClient(client *Client) {
	h.unregister <- client
}

// Read pump reads messages from the WebSocket
func (c *Client) ReadPump() {
	defer func() {
		c.cancelFunc()
		c.Hub.UnregisterClient(c)
		c.Conn.Close()
	}()

	c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		select {
		case <-c.ctx.Done():
			return
		default:
			_, message, err := c.Conn.ReadMessage()
			if err != nil {
				if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
					if c.Hub.logger != nil {
						c.Hub.logger.Error("WebSocket read error", zap.Error(err))
					}
				}
				return
			}

			// Parse message
			var msg map[string]interface{}
			if err := json.Unmarshal(message, &msg); err != nil {
				if c.Hub.logger != nil {
					c.Hub.logger.Warn("Failed to parse WebSocket message", zap.Error(err))
				}
				continue
			}

			// Handle subscribe/unsubscribe
			if action, ok := msg["action"].(string); ok {
				if channel, ok := msg["channel"].(string); ok {
					switch action {
					case "subscribe":
						c.Hub.Subscribe(c.ID, channel)
					case "unsubscribe":
						c.Hub.Unsubscribe(c.ID, channel)
					}
				}
			}
		}
	}
}

// Write pump sends messages to the WebSocket
func (c *Client) WritePump() {
	ticker := time.NewTicker(54 * time.Second)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case <-c.ctx.Done():
			return
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			// Send message as JSON
			if err := c.Conn.WriteJSON(message); err != nil {
				if c.Hub.logger != nil {
					c.Hub.logger.Error("WebSocket write error", zap.Error(err))
				}
				return
			}

		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// NewClient creates a new WebSocket client
func NewClient(id, tenantID string, conn *websocket.Conn, hub *Hub) *Client {
	ctx, cancel := context.WithCancel(context.Background())
	return &Client{
		ID:         id,
		TenantID:   tenantID,
		Conn:       conn,
		Send:       make(chan Message, 256),
		Hub:        hub,
		Channels:   make(map[string]bool),
		ctx:        ctx,
		cancelFunc: cancel,
	}
}

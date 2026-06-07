package websocket

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"go.uber.org/zap"
)

const (
	// Time allowed to write a message to the peer
	writeWait = 10 * time.Second

	// Time allowed to read the next pong message from the peer
	pongWait = 60 * time.Second

	// Send pings to peer with this period (must be less than pongWait)
	pingPeriod = (pongWait * 9) / 10

	// Maximum message size allowed from peer
	maxMessageSize = 512 * 1024 // 512KB
)

// ClientOptions contains options for creating a new client
type ClientOptions struct {
	UserID   string
	TenantID string
	Role     string
	Conn     *websocket.Conn
	Hub      *Hub
	Logger   *zap.Logger
}

// NewClient creates a new WebSocket client
func NewClient(opts ClientOptions) *Client {
	return &Client{
		ID:       uuid.New().String(),
		UserID:   opts.UserID,
		TenantID: opts.TenantID,
		Role:     opts.Role,
		conn:     opts.Conn,
		hub:      opts.Hub,
		send:     make(chan []byte, 256),
		channels: make(map[string]bool),
		isAlive:  true,
		lastPing: time.Now(),
	}
}

// ReadPump pumps messages from the WebSocket connection to the hub
func (c *Client) ReadPump(logger *zap.Logger) {
	defer func() {
		c.hub.unregister <- c
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.mu.Lock()
		c.lastPing = time.Now()
		c.isAlive = true
		c.mu.Unlock()
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, messageBytes, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				logger.Error("WebSocket read error",
					zap.String("client_id", c.ID),
					zap.Error(err))
			}
			break
		}

		// Parse incoming message
		var msg Message
		if err := json.Unmarshal(messageBytes, &msg); err != nil {
			logger.Warn("Invalid message format",
				zap.String("client_id", c.ID),
				zap.Error(err))
			c.sendError("Invalid message format")
			continue
		}

		// Handle different message types
		c.handleMessage(&msg, logger)
	}
}

// WritePump pumps messages from the hub to the WebSocket connection
func (c *Client) WritePump(logger *zap.Logger) {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				// Hub closed the channel
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			// Add queued messages to the current WebSocket frame
			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// handleMessage processes incoming messages based on their type
func (c *Client) handleMessage(msg *Message, logger *zap.Logger) {
	// Set message metadata
	msg.UserID = c.UserID
	msg.TenantID = c.TenantID
	msg.Timestamp = time.Now()

	switch msg.Type {
	case MessageTypePong:
		// Update last ping time
		c.mu.Lock()
		c.lastPing = time.Now()
		c.isAlive = true
		c.mu.Unlock()

	case MessageTypeAuth:
		// Handle authentication/re-authentication
		c.handleAuth(msg, logger)

	case MessageTypeNotification:
		// Handle notification subscription/unsubscription
		c.handleNotificationRequest(msg, logger)

	case MessageTypeInventoryUpdate:
		// Subscribe to inventory updates
		c.hub.SubscribeClientToChannel(c, "inventory")
		c.sendAck("Subscribed to inventory updates")

	case MessageTypeSaleUpdate:
		// Subscribe to sales updates
		c.hub.SubscribeClientToChannel(c, "sales")
		c.sendAck("Subscribed to sales updates")

	case MessageTypeCashFlow:
		// Subscribe to cash flow updates
		c.hub.SubscribeClientToChannel(c, "cashflow")
		c.sendAck("Subscribed to cash flow updates")

	case MessageTypeDashboard:
		// Subscribe to dashboard updates
		c.hub.SubscribeClientToChannel(c, "dashboard")
		c.sendAck("Subscribed to dashboard updates")

	case MessageTypeOCRProgress:
		// Subscribe to OCR progress updates (v1.0.28)
		c.hub.SubscribeClientToChannel(c, "ocr_progress")
		c.sendAck("Subscribed to OCR progress updates")

	default:
		// Broadcast the message if it's a valid type for broadcasting
		if c.isAuthorized(msg.Type) {
			c.hub.broadcast <- msg
		} else {
			c.sendError(fmt.Sprintf("Unknown or unauthorized message type: %s", msg.Type))
		}
	}
}

// handleAuth processes authentication messages
func (c *Client) handleAuth(msg *Message, logger *zap.Logger) {
	// Extract token from message data
	_, ok := msg.Data["token"].(string)
	if !ok {
		c.sendError("Authentication token required")
		return
	}

	// TODO: Validate token with auth service
	// For now, we'll just acknowledge
	logger.Info("Client authenticated",
		zap.String("client_id", c.ID),
		zap.String("user_id", c.UserID))

	c.sendAck("Authentication successful")
}

// handleNotificationRequest processes notification subscription requests
func (c *Client) handleNotificationRequest(msg *Message, logger *zap.Logger) {
	action, ok := msg.Data["action"].(string)
	if !ok {
		c.sendError("Action required for notification request")
		return
	}

	channel, ok := msg.Data["channel"].(string)
	if !ok {
		c.sendError("Channel required for notification request")
		return
	}

	switch action {
	case "subscribe":
		c.hub.SubscribeClientToChannel(c, channel)
		c.sendAck(fmt.Sprintf("Subscribed to channel: %s", channel))
	case "unsubscribe":
		c.hub.UnsubscribeClientFromChannel(c, channel)
		c.sendAck(fmt.Sprintf("Unsubscribed from channel: %s", channel))
	default:
		c.sendError(fmt.Sprintf("Unknown action: %s", action))
	}
}

// isAuthorized checks if the client is authorized for a specific message type
func (c *Client) isAuthorized(msgType MessageType) bool {
	// Implement role-based authorization logic
	switch c.Role {
	case "admin", "super_admin":
		return true // Admins can send all message types
	case "manager":
		// Managers can send most messages except system-level ones
		return msgType != MessageTypeAuth
	case "salesman":
		// Salesman can only send sales-related messages
		return msgType == MessageTypeSaleUpdate || msgType == MessageTypeNotification
	default:
		return false
	}
}

// sendAck sends an acknowledgment message to the client
func (c *Client) sendAck(message string) {
	ack := &Message{
		Type: MessageTypeAck,
		Data: map[string]interface{}{
			"message": message,
		},
		Timestamp: time.Now(),
	}

	if data, err := json.Marshal(ack); err == nil {
		select {
		case c.send <- data:
		default:
			// Channel full, message dropped
		}
	}
}

// sendError sends an error message to the client
func (c *Client) sendError(errorMsg string) {
	errMessage := &Message{
		Type: MessageTypeError,
		Data: map[string]interface{}{
			"error": errorMsg,
		},
		Timestamp: time.Now(),
	}

	if data, err := json.Marshal(errMessage); err == nil {
		select {
		case c.send <- data:
		default:
			// Channel full, message dropped
		}
	}
}

// SendMessage sends a message to this specific client
func (c *Client) SendMessage(msg *Message) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal message: %w", err)
	}

	select {
	case c.send <- data:
		return nil
	default:
		return fmt.Errorf("client send channel is full")
	}
}

// IsAlive returns whether the client connection is alive
func (c *Client) IsAlive() bool {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.isAlive
}

// GetChannels returns the channels the client is subscribed to
func (c *Client) GetChannels() []string {
	c.mu.RLock()
	defer c.mu.RUnlock()

	channels := make([]string, 0, len(c.channels))
	for channel := range c.channels {
		channels = append(channels, channel)
	}
	return channels
}
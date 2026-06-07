package messaging

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

// KafkaConfig holds Kafka configuration
type KafkaConfig struct {
	Brokers       []string `yaml:"brokers" json:"brokers"`
	GroupID       string   `yaml:"group_id" json:"group_id"`
	Topic         string   `yaml:"topic" json:"topic"`
	BatchSize     int      `yaml:"batch_size" json:"batch_size"`
	BatchTimeout  int      `yaml:"batch_timeout" json:"batch_timeout"`
	RetryAttempts int      `yaml:"retry_attempts" json:"retry_attempts"`
}

// KafkaClient handles Kafka operations
type KafkaClient struct {
	config    KafkaConfig
	writer    *kafka.Writer
	readers   map[string]*kafka.Reader
	readersMu sync.RWMutex  // Protect concurrent map access
	logger    *zap.Logger
}

// Message represents a Kafka message
type Message struct {
	Key       string                 `json:"key"`
	Value     interface{}            `json:"value"`
	Headers   map[string]string      `json:"headers"`
	Topic     string                 `json:"topic"`
	Partition int                    `json:"partition"`
	Offset    int64                  `json:"offset"`
	Timestamp time.Time              `json:"timestamp"`
	Metadata  map[string]interface{} `json:"metadata"`
}

// EventType represents different event types
type EventType string

const (
	EventTypeSaleCreated       EventType = "sale.created"
	EventTypeSaleUpdated       EventType = "sale.updated"
	EventTypeInventoryUpdated  EventType = "inventory.updated"
	EventTypeStockLow          EventType = "stock.low"
	EventTypePaymentProcessed  EventType = "payment.processed"
	EventTypeUserAuthenticated EventType = "user.authenticated"
	EventTypeOrderPlaced       EventType = "order.placed"
	EventTypeNotification      EventType = "notification.send"
)

// BusinessEvent represents a business event
type BusinessEvent struct {
	ID            string                 `json:"id"`
	Type          EventType              `json:"type"`
	Source        string                 `json:"source"`
	Subject       string                 `json:"subject"`
	Data          map[string]interface{} `json:"data"`
	Timestamp     time.Time              `json:"timestamp"`
	Version       string                 `json:"version"`
	TenantID      string                 `json:"tenant_id"`
	CorrelationID string                 `json:"correlation_id"`
}

// NewKafkaClient creates a new Kafka client
func NewKafkaClient(config KafkaConfig, logger *zap.Logger) (*KafkaClient, error) {
	client := &KafkaClient{
		config:  config,
		readers: make(map[string]*kafka.Reader),
		logger:  logger,
	}

	// Initialize writer with advanced configuration
	client.writer = &kafka.Writer{
		Addr:                   kafka.TCP(config.Brokers...),
		Balancer:               &kafka.LeastBytes{}, // Efficient load balancing
		BatchSize:              config.BatchSize,
		BatchTimeout:           time.Duration(config.BatchTimeout) * time.Millisecond,
		RequiredAcks:           kafka.RequireAll, // Wait for all replicas
		Async:                  false,            // Synchronous for reliability
		Compression:            kafka.Snappy,     // Efficient compression
		Logger:                 kafka.LoggerFunc(client.logKafka),
		ErrorLogger:            kafka.LoggerFunc(client.logKafkaError),
		AllowAutoTopicCreation: true,
	}

	return client, nil
}

// PublishEvent publishes a business event to Kafka
func (k *KafkaClient) PublishEvent(ctx context.Context, event BusinessEvent) error {
	// Serialize event data
	eventData, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	// Create Kafka message
	message := kafka.Message{
		Key:   []byte(event.Subject),
		Value: eventData,
		Headers: []kafka.Header{
			{Key: "event-type", Value: []byte(event.Type)},
			{Key: "source", Value: []byte(event.Source)},
			{Key: "version", Value: []byte(event.Version)},
			{Key: "tenant-id", Value: []byte(event.TenantID)},
			{Key: "correlation-id", Value: []byte(event.CorrelationID)},
			{Key: "timestamp", Value: []byte(event.Timestamp.Format(time.RFC3339))},
		},
	}

	// Determine topic based on event type
	topic := k.getTopicForEventType(event.Type)

	// Publish with retry logic
	return k.publishWithRetry(ctx, topic, message)
}

// PublishMessage publishes a raw message to Kafka
func (k *KafkaClient) PublishMessage(ctx context.Context, topic string, message Message) error {
	// Serialize message value
	valueData, err := json.Marshal(message.Value)
	if err != nil {
		return fmt.Errorf("failed to marshal message value: %w", err)
	}

	// Create Kafka headers
	headers := make([]kafka.Header, 0, len(message.Headers))
	for key, value := range message.Headers {
		headers = append(headers, kafka.Header{
			Key:   key,
			Value: []byte(value),
		})
	}

	kafkaMessage := kafka.Message{
		Topic:   topic,
		Key:     []byte(message.Key),
		Value:   valueData,
		Headers: headers,
		Time:    message.Timestamp,
	}

	return k.publishWithRetry(ctx, topic, kafkaMessage)
}

// Subscribe creates a consumer for a topic
func (k *KafkaClient) Subscribe(topic string, groupID string, handler func(ctx context.Context, message Message) error) error {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:        k.config.Brokers,
		Topic:          topic,
		GroupID:        groupID,
		MinBytes:       10e3, // 10KB
		MaxBytes:       10e6, // 10MB
		CommitInterval: time.Second,
		StartOffset:    kafka.LastOffset,
		Logger:         kafka.LoggerFunc(k.logKafka),
		ErrorLogger:    kafka.LoggerFunc(k.logKafkaError),
	})

	// Thread-safe map write
	k.readersMu.Lock()
	k.readers[topic] = reader
	k.readersMu.Unlock()

	// Start consuming in a goroutine
	go k.consumeMessages(reader, handler)

	k.logger.Info("Kafka consumer started",
		zap.String("topic", topic),
		zap.String("group_id", groupID))

	return nil
}

// consumeMessages consumes messages from Kafka
func (k *KafkaClient) consumeMessages(reader *kafka.Reader, handler func(ctx context.Context, message Message) error) {
	for {
		kafkaMessage, err := reader.ReadMessage(context.Background())
		if err != nil {
			k.logger.Error("Failed to read Kafka message", zap.Error(err))
			continue
		}

		// Convert Kafka message to our Message format
		headers := make(map[string]string)
		for _, header := range kafkaMessage.Headers {
			headers[header.Key] = string(header.Value)
		}

		message := Message{
			Key:       string(kafkaMessage.Key),
			Headers:   headers,
			Topic:     kafkaMessage.Topic,
			Partition: kafkaMessage.Partition,
			Offset:    kafkaMessage.Offset,
			Timestamp: kafkaMessage.Time,
		}

		// Deserialize value
		if err := json.Unmarshal(kafkaMessage.Value, &message.Value); err != nil {
			k.logger.Error("Failed to unmarshal message value", zap.Error(err))
			continue
		}

		// Handle message
		ctx := context.Background()
		if err := handler(ctx, message); err != nil {
			k.logger.Error("Failed to handle message",
				zap.Error(err),
				zap.String("topic", message.Topic),
				zap.Int64("offset", message.Offset))
		}
	}
}

// publishWithRetry publishes a message with retry logic
func (k *KafkaClient) publishWithRetry(ctx context.Context, topic string, message kafka.Message) error {
	message.Topic = topic

	var lastErr error
	for attempt := 0; attempt <= k.config.RetryAttempts; attempt++ {
		if attempt > 0 {
			// Exponential backoff
			backoff := time.Duration(attempt*attempt) * time.Second
			time.Sleep(backoff)
		}

		err := k.writer.WriteMessages(ctx, message)
		if err == nil {
			k.logger.Debug("Message published successfully",
				zap.String("topic", topic),
				zap.String("key", string(message.Key)))
			return nil
		}

		lastErr = err
		k.logger.Warn("Failed to publish message, retrying",
			zap.Error(err),
			zap.Int("attempt", attempt+1),
			zap.String("topic", topic))
	}

	return fmt.Errorf("failed to publish message after %d attempts: %w", k.config.RetryAttempts, lastErr)
}

// getTopicForEventType returns the appropriate topic for an event type
func (k *KafkaClient) getTopicForEventType(eventType EventType) string {
	switch eventType {
	case EventTypeSaleCreated, EventTypeSaleUpdated:
		return "sales-events"
	case EventTypeInventoryUpdated, EventTypeStockLow:
		return "inventory-events"
	case EventTypePaymentProcessed:
		return "payment-events"
	case EventTypeUserAuthenticated:
		return "auth-events"
	case EventTypeOrderPlaced:
		return "order-events"
	case EventTypeNotification:
		return "notification-events"
	default:
		return "general-events"
	}
}

// Close closes all Kafka connections
func (k *KafkaClient) Close() error {
	// Close writer
	if k.writer != nil {
		if err := k.writer.Close(); err != nil {
			k.logger.Error("Failed to close Kafka writer", zap.Error(err))
		}
	}

	// Close all readers (thread-safe)
	k.readersMu.Lock()
	for topic, reader := range k.readers {
		if err := reader.Close(); err != nil {
			k.logger.Error("Failed to close Kafka reader",
				zap.Error(err),
				zap.String("topic", topic))
		}
	}
	k.readersMu.Unlock()

	return nil
}

// HealthCheck performs a health check on Kafka
func (k *KafkaClient) HealthCheck(ctx context.Context) error {
	// Try to create a temporary topic to test connectivity
	conn, err := kafka.DialContext(ctx, "tcp", k.config.Brokers[0])
	if err != nil {
		return fmt.Errorf("failed to connect to Kafka: %w", err)
	}
	defer conn.Close()

	// List topics to verify connectivity
	_, err = conn.ReadPartitions()
	if err != nil {
		return fmt.Errorf("failed to read Kafka partitions: %w", err)
	}

	return nil
}

// GetMetrics returns Kafka client metrics
func (k *KafkaClient) GetMetrics() map[string]interface{} {
	stats := k.writer.Stats()
	return map[string]interface{}{
		"messages_written": stats.Messages,
		"bytes_written":    stats.Bytes,
		"errors":           stats.Errors,
		"batch_time_avg":   stats.BatchTime.Avg,
		"batch_time_max":   stats.BatchTime.Max,
		"write_time_avg":   stats.WriteTime.Avg,
		"write_time_max":   stats.WriteTime.Max,
	}
}

// logKafka logs Kafka messages
func (k *KafkaClient) logKafka(msg string, args ...interface{}) {
	k.logger.Debug(fmt.Sprintf(msg, args...))
}

// logKafkaError logs Kafka errors
func (k *KafkaClient) logKafkaError(msg string, args ...interface{}) {
	k.logger.Error(fmt.Sprintf(msg, args...))
}

// EventPublisher is a helper for publishing domain events
type EventPublisher struct {
	client   *KafkaClient
	logger   *zap.Logger
	source   string
	tenantID string
}

// NewEventPublisher creates a new event publisher
func NewEventPublisher(client *KafkaClient, source string, tenantID string, logger *zap.Logger) *EventPublisher {
	return &EventPublisher{
		client:   client,
		logger:   logger,
		source:   source,
		tenantID: tenantID,
	}
}

// PublishSaleEvent publishes a sale-related event
func (p *EventPublisher) PublishSaleEvent(ctx context.Context, eventType EventType, saleID string, data map[string]interface{}) error {
	event := BusinessEvent{
		ID:            fmt.Sprintf("%s-%d", saleID, time.Now().UnixNano()),
		Type:          eventType,
		Source:        p.source,
		Subject:       saleID,
		Data:          data,
		Timestamp:     time.Now(),
		Version:       "1.0",
		TenantID:      p.tenantID,
		CorrelationID: ctx.Value("correlation_id").(string),
	}

	return p.client.PublishEvent(ctx, event)
}

// PublishInventoryEvent publishes an inventory-related event
func (p *EventPublisher) PublishInventoryEvent(ctx context.Context, eventType EventType, productID string, data map[string]interface{}) error {
	event := BusinessEvent{
		ID:            fmt.Sprintf("%s-%d", productID, time.Now().UnixNano()),
		Type:          eventType,
		Source:        p.source,
		Subject:       productID,
		Data:          data,
		Timestamp:     time.Now(),
		Version:       "1.0",
		TenantID:      p.tenantID,
		CorrelationID: ctx.Value("correlation_id").(string),
	}

	return p.client.PublishEvent(ctx, event)
}

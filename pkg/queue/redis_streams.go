package queue

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/go-redis/redis/v8"
	"go.uber.org/zap"
	
	"github.com/liquorpro/pkg/monitoring"
)

// MessageHandler defines the function signature for message handlers
type MessageHandler func(ctx context.Context, message *Message) error

// Message represents a queue message
type Message struct {
	ID        string                 `json:"id"`
	Stream    string                 `json:"stream"`
	Data      map[string]interface{} `json:"data"`
	Timestamp time.Time             `json:"timestamp"`
	Attempts  int                   `json:"attempts"`
}

// StreamConfig holds configuration for a Redis stream
type StreamConfig struct {
	StreamName     string        `json:"stream_name"`
	ConsumerGroup  string        `json:"consumer_group"`
	ConsumerName   string        `json:"consumer_name"`
	MaxRetries     int           `json:"max_retries"`
	RetryDelay     time.Duration `json:"retry_delay"`
	BlockDuration  time.Duration `json:"block_duration"`
	BatchSize      int64         `json:"batch_size"`
	MaxLen         int64         `json:"max_len"`
}

// QueueManager manages Redis streams for message queuing
type QueueManager struct {
	client    *redis.Client
	logger    *zap.Logger
	streams   map[string]*StreamConfig
	handlers  map[string]MessageHandler
	consumers map[string]*StreamConsumer
	mutex     sync.RWMutex
	ctx       context.Context
	cancel    context.CancelFunc
}

// NewQueueManager creates a new Redis streams queue manager
func NewQueueManager(redisClient *redis.Client, logger *zap.Logger) *QueueManager {
	ctx, cancel := context.WithCancel(context.Background())
	
	return &QueueManager{
		client:    redisClient,
		logger:    logger,
		streams:   make(map[string]*StreamConfig),
		handlers:  make(map[string]MessageHandler),
		consumers: make(map[string]*StreamConsumer),
		ctx:       ctx,
		cancel:    cancel,
	}
}

// RegisterStream registers a new stream with configuration
func (qm *QueueManager) RegisterStream(config StreamConfig, handler MessageHandler) error {
	qm.mutex.Lock()
	defer qm.mutex.Unlock()
	
	// Set defaults
	if config.MaxRetries == 0 {
		config.MaxRetries = 3
	}
	if config.RetryDelay == 0 {
		config.RetryDelay = 30 * time.Second
	}
	if config.BlockDuration == 0 {
		config.BlockDuration = 5 * time.Second
	}
	if config.BatchSize == 0 {
		config.BatchSize = 10
	}
	if config.MaxLen == 0 {
		config.MaxLen = 10000
	}
	
	// Create consumer group if it doesn't exist
	err := qm.client.XGroupCreateMkStream(qm.ctx, config.StreamName, config.ConsumerGroup, "0").Err()
	if err != nil && err.Error() != "BUSYGROUP Consumer Group name already exists" {
		return fmt.Errorf("failed to create consumer group: %w", err)
	}
	
	qm.streams[config.StreamName] = &config
	qm.handlers[config.StreamName] = handler
	
	qm.logger.Info("Stream registered",
		zap.String("stream", config.StreamName),
		zap.String("consumer_group", config.ConsumerGroup),
		zap.String("consumer_name", config.ConsumerName),
	)
	
	return nil
}

// StartConsumer starts consuming messages from a stream
func (qm *QueueManager) StartConsumer(streamName string) error {
	qm.mutex.Lock()
	defer qm.mutex.Unlock()
	
	config, exists := qm.streams[streamName]
	if !exists {
		return fmt.Errorf("stream %s not registered", streamName)
	}
	
	handler, exists := qm.handlers[streamName]
	if !exists {
		return fmt.Errorf("no handler registered for stream %s", streamName)
	}
	
	consumer := NewStreamConsumer(qm.client, config, handler, qm.logger)
	qm.consumers[streamName] = consumer
	
	go consumer.Start(qm.ctx)
	
	qm.logger.Info("Consumer started", zap.String("stream", streamName))
	return nil
}

// StartAllConsumers starts all registered consumers
func (qm *QueueManager) StartAllConsumers() error {
	qm.mutex.RLock()
	streamNames := make([]string, 0, len(qm.streams))
	for streamName := range qm.streams {
		streamNames = append(streamNames, streamName)
	}
	qm.mutex.RUnlock()
	
	for _, streamName := range streamNames {
		if err := qm.StartConsumer(streamName); err != nil {
			return fmt.Errorf("failed to start consumer for stream %s: %w", streamName, err)
		}
	}
	
	return nil
}

// Publish publishes a message to a stream
func (qm *QueueManager) Publish(streamName string, data map[string]interface{}) error {
	qm.mutex.RLock()
	config, exists := qm.streams[streamName]
	qm.mutex.RUnlock()
	
	if !exists {
		return fmt.Errorf("stream %s not registered", streamName)
	}
	
	// Convert data to string map for Redis
	values := make(map[string]interface{})
	for k, v := range data {
		jsonBytes, err := json.Marshal(v)
		if err != nil {
			return fmt.Errorf("failed to marshal field %s: %w", k, err)
		}
		values[k] = string(jsonBytes)
	}
	
	// Add metadata
	values["published_at"] = time.Now().Format(time.RFC3339)
	values["attempts"] = "0"
	
	// Publish to stream with max length limit
	args := &redis.XAddArgs{
		Stream: streamName,
		MaxLen: config.MaxLen,
		Approx: true, // Use approximate trimming for better performance
		Values: values,
	}
	
	messageID, err := qm.client.XAdd(qm.ctx, args).Result()
	if err != nil {
		monitoring.RecordRedisOperation("queue_manager", "xadd", "error")
		return fmt.Errorf("failed to publish message: %w", err)
	}
	
	monitoring.RecordRedisOperation("queue_manager", "xadd", "success")
	
	qm.logger.Debug("Message published",
		zap.String("stream", streamName),
		zap.String("message_id", messageID),
	)
	
	return nil
}

// PublishDelayed publishes a message with a delay
func (qm *QueueManager) PublishDelayed(streamName string, data map[string]interface{}, delay time.Duration) error {
	// Add delay information to the message
	data["scheduled_for"] = time.Now().Add(delay).Format(time.RFC3339)
	data["delayed"] = true
	
	return qm.Publish(streamName+"_delayed", data)
}

// Stop stops all consumers and closes connections
func (qm *QueueManager) Stop() error {
	qm.cancel()
	
	qm.mutex.Lock()
	defer qm.mutex.Unlock()
	
	for streamName, consumer := range qm.consumers {
		consumer.Stop()
		qm.logger.Info("Consumer stopped", zap.String("stream", streamName))
	}
	
	return nil
}

// StreamConsumer handles consuming messages from a Redis stream
type StreamConsumer struct {
	client   *redis.Client
	config   *StreamConfig
	handler  MessageHandler
	logger   *zap.Logger
	stopChan chan struct{}
	stopped  bool
	mutex    sync.Mutex
}

// NewStreamConsumer creates a new stream consumer
func NewStreamConsumer(client *redis.Client, config *StreamConfig, handler MessageHandler, logger *zap.Logger) *StreamConsumer {
	return &StreamConsumer{
		client:   client,
		config:   config,
		handler:  handler,
		logger:   logger,
		stopChan: make(chan struct{}),
	}
}

// Start starts the consumer loop
func (sc *StreamConsumer) Start(ctx context.Context) {
	sc.logger.Info("Starting stream consumer",
		zap.String("stream", sc.config.StreamName),
		zap.String("consumer_group", sc.config.ConsumerGroup),
	)
	
	// Start two goroutines: one for new messages, one for pending messages
	go sc.consumeNewMessages(ctx)
	go sc.processPendingMessages(ctx)
	go sc.processDelayedMessages(ctx)
}

// consumeNewMessages consumes new messages from the stream
func (sc *StreamConsumer) consumeNewMessages(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-sc.stopChan:
			return
		default:
		}
		
		// Read messages from the stream
		streams, err := sc.client.XReadGroup(ctx, &redis.XReadGroupArgs{
			Group:    sc.config.ConsumerGroup,
			Consumer: sc.config.ConsumerName,
			Streams:  []string{sc.config.StreamName, ">"},
			Count:    sc.config.BatchSize,
			Block:    sc.config.BlockDuration,
		}).Result()
		
		if err != nil {
			if err != redis.Nil && err != context.Canceled {
				sc.logger.Error("Failed to read from stream", 
					zap.String("stream", sc.config.StreamName),
					zap.Error(err),
				)
				monitoring.RecordRedisOperation("stream_consumer", "xreadgroup", "error")
				time.Sleep(time.Second)
			}
			continue
		}
		
		monitoring.RecordRedisOperation("stream_consumer", "xreadgroup", "success")
		
		// Process messages
		for _, stream := range streams {
			for _, message := range stream.Messages {
				sc.processMessage(ctx, &message)
			}
		}
	}
}

// processPendingMessages processes pending messages (messages that failed previously)
func (sc *StreamConsumer) processPendingMessages(ctx context.Context) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-sc.stopChan:
			return
		case <-ticker.C:
			sc.handlePendingMessages(ctx)
		}
	}
}

// processDelayedMessages processes delayed messages
func (sc *StreamConsumer) processDelayedMessages(ctx context.Context) {
	delayedStream := sc.config.StreamName + "_delayed"
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-sc.stopChan:
			return
		case <-ticker.C:
			sc.handleDelayedMessages(ctx, delayedStream)
		}
	}
}

// handleDelayedMessages checks for delayed messages that are ready to be processed
func (sc *StreamConsumer) handleDelayedMessages(ctx context.Context, delayedStream string) {
	// Read from delayed stream
	streams, err := sc.client.XRead(ctx, &redis.XReadArgs{
		Streams: []string{delayedStream, "0"},
		Count:   10,
	}).Result()
	
	if err != nil {
		if err != redis.Nil {
			sc.logger.Error("Failed to read delayed messages", zap.Error(err))
		}
		return
	}
	
	now := time.Now()
	
	for _, stream := range streams {
		for _, message := range stream.Messages {
			// Check if message is ready
			if scheduledForStr, exists := message.Values["scheduled_for"]; exists {
				scheduledFor, err := time.Parse(time.RFC3339, scheduledForStr.(string))
				if err == nil && now.After(scheduledFor) {
					// Message is ready, move it to main stream
					delete(message.Values, "scheduled_for")
					delete(message.Values, "delayed")
					
					// Add to main stream
					sc.client.XAdd(ctx, &redis.XAddArgs{
						Stream: sc.config.StreamName,
						Values: message.Values,
					})
					
					// Remove from delayed stream
					sc.client.XDel(ctx, delayedStream, message.ID)
				}
			}
		}
	}
}

// handlePendingMessages processes messages that are pending acknowledgment
func (sc *StreamConsumer) handlePendingMessages(ctx context.Context) {
	// Get pending messages for this consumer
	pending, err := sc.client.XPendingExt(ctx, &redis.XPendingExtArgs{
		Stream:   sc.config.StreamName,
		Group:    sc.config.ConsumerGroup,
		Start:    "-",
		End:      "+",
		Count:    100,
		Consumer: sc.config.ConsumerName,
	}).Result()
	
	if err != nil {
		sc.logger.Error("Failed to get pending messages", zap.Error(err))
		return
	}
	
	for _, msg := range pending {
		// Check if message has been idle for too long
		if time.Since(msg.Idle) > sc.config.RetryDelay {
			// Claim the message and retry
			messages, err := sc.client.XClaim(ctx, &redis.XClaimArgs{
				Stream:   sc.config.StreamName,
				Group:    sc.config.ConsumerGroup,
				Consumer: sc.config.ConsumerName,
				MinIdle:  sc.config.RetryDelay,
				Messages: []string{msg.ID},
			}).Result()
			
			if err != nil {
				sc.logger.Error("Failed to claim pending message", 
					zap.String("message_id", msg.ID),
					zap.Error(err),
				)
				continue
			}
			
			// Process claimed messages
			for _, message := range messages {
				sc.processMessage(ctx, &message)
			}
		}
	}
}

// processMessage processes a single message
func (sc *StreamConsumer) processMessage(ctx context.Context, redisMsg *redis.XMessage) {
	// Convert Redis message to our Message struct
	message := &Message{
		ID:        redisMsg.ID,
		Stream:    sc.config.StreamName,
		Data:      make(map[string]interface{}),
		Timestamp: time.Now(),
	}
	
	// Parse message data
	for k, v := range redisMsg.Values {
		if k == "published_at" {
			if timestamp, err := time.Parse(time.RFC3339, v.(string)); err == nil {
				message.Timestamp = timestamp
			}
			continue
		}
		
		if k == "attempts" {
			if attempts, err := json.Unmarshal([]byte(v.(string)), &message.Attempts); err == nil {
				message.Attempts++
			}
			continue
		}
		
		// Unmarshal JSON data
		var data interface{}
		if err := json.Unmarshal([]byte(v.(string)), &data); err == nil {
			message.Data[k] = data
		} else {
			message.Data[k] = v
		}
	}
	
	sc.logger.Debug("Processing message",
		zap.String("stream", sc.config.StreamName),
		zap.String("message_id", message.ID),
		zap.Int("attempts", message.Attempts),
	)
	
	// Process message with timeout
	processCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	
	err := sc.handler(processCtx, message)
	if err != nil {
		sc.logger.Error("Failed to process message",
			zap.String("stream", sc.config.StreamName),
			zap.String("message_id", message.ID),
			zap.Int("attempts", message.Attempts),
			zap.Error(err),
		)
		
		// Check if we should retry
		if message.Attempts < sc.config.MaxRetries {
			// Update attempts count and re-add to stream for retry
			retryData := make(map[string]interface{})
			for k, v := range message.Data {
				jsonBytes, _ := json.Marshal(v)
				retryData[k] = string(jsonBytes)
			}
			retryData["attempts"] = fmt.Sprintf("%d", message.Attempts)
			retryData["last_error"] = err.Error()
			retryData["retry_at"] = time.Now().Add(sc.config.RetryDelay).Format(time.RFC3339)
			
			// Add to delayed stream for retry
			sc.client.XAdd(ctx, &redis.XAddArgs{
				Stream: sc.config.StreamName + "_delayed",
				Values: retryData,
			})
		} else {
			// Max retries reached, move to dead letter queue
			sc.moveToDeadLetterQueue(ctx, message, err)
		}
	}
	
	// Acknowledge message
	if err := sc.client.XAck(ctx, sc.config.StreamName, sc.config.ConsumerGroup, redisMsg.ID).Err(); err != nil {
		sc.logger.Error("Failed to acknowledge message",
			zap.String("message_id", redisMsg.ID),
			zap.Error(err),
		)
	}
}

// moveToDeadLetterQueue moves failed messages to dead letter queue
func (sc *StreamConsumer) moveToDeadLetterQueue(ctx context.Context, message *Message, err error) {
	dlqStream := sc.config.StreamName + "_dlq"
	
	data := make(map[string]interface{})
	for k, v := range message.Data {
		jsonBytes, _ := json.Marshal(v)
		data[k] = string(jsonBytes)
	}
	data["original_message_id"] = message.ID
	data["failed_at"] = time.Now().Format(time.RFC3339)
	data["error"] = err.Error()
	data["attempts"] = fmt.Sprintf("%d", message.Attempts)
	
	_, err = sc.client.XAdd(ctx, &redis.XAddArgs{
		Stream: dlqStream,
		Values: data,
	}).Result()
	
	if err != nil {
		sc.logger.Error("Failed to add message to dead letter queue", zap.Error(err))
	} else {
		sc.logger.Info("Message moved to dead letter queue",
			zap.String("stream", sc.config.StreamName),
			zap.String("message_id", message.ID),
		)
	}
}

// Stop stops the consumer
func (sc *StreamConsumer) Stop() {
	sc.mutex.Lock()
	defer sc.mutex.Unlock()
	
	if !sc.stopped {
		close(sc.stopChan)
		sc.stopped = true
	}
}

// QueueStats represents queue statistics
type QueueStats struct {
	StreamName      string `json:"stream_name"`
	Length          int64  `json:"length"`
	ConsumerGroup   string `json:"consumer_group"`
	PendingMessages int64  `json:"pending_messages"`
	Consumers       int64  `json:"consumers"`
}

// GetStats returns statistics for all streams
func (qm *QueueManager) GetStats() ([]QueueStats, error) {
	qm.mutex.RLock()
	defer qm.mutex.RUnlock()
	
	stats := make([]QueueStats, 0, len(qm.streams))
	
	for streamName, config := range qm.streams {
		// Get stream length
		length, err := qm.client.XLen(qm.ctx, streamName).Result()
		if err != nil {
			length = 0
		}
		
		// Get pending messages count
		pending, err := qm.client.XPending(qm.ctx, streamName, config.ConsumerGroup).Result()
		var pendingCount int64 = 0
		var consumersCount int64 = 0
		if err == nil {
			pendingCount = pending.Count
			consumersCount = int64(len(pending.Consumers))
		}
		
		stats = append(stats, QueueStats{
			StreamName:      streamName,
			Length:          length,
			ConsumerGroup:   config.ConsumerGroup,
			PendingMessages: pendingCount,
			Consumers:       consumersCount,
		})
	}
	
	return stats, nil
}
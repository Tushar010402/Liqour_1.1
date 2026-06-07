package cqrs

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"
)

// EventType represents the type of event
type EventType string

const (
	EventTypeProductCreated   EventType = "ProductCreated"
	EventTypeProductUpdated   EventType = "ProductUpdated"
	EventTypeProductDeleted   EventType = "ProductDeleted"
	EventTypeStockAdjusted    EventType = "StockAdjusted"
	EventTypeSaleProcessed    EventType = "SaleProcessed"
	EventTypeReturnProcessed  EventType = "ReturnProcessed"
	EventTypeTransferCreated  EventType = "TransferCreated"
	EventTypePriceChanged     EventType = "PriceChanged"
)

// Event represents a domain event
type Event interface {
	GetID() string
	GetType() EventType
	GetAggregateID() string
	GetAggregateType() string
	GetVersion() int
	GetTimestamp() time.Time
	GetTenantID() string
	GetUserID() string
	GetData() map[string]interface{}
}

// BaseEvent contains common event fields
type BaseEvent struct {
	ID            string                 `json:"id"`
	Type          EventType              `json:"type"`
	AggregateID   string                 `json:"aggregate_id"`
	AggregateType string                 `json:"aggregate_type"`
	Version       int                    `json:"version"`
	Timestamp     time.Time              `json:"timestamp"`
	TenantID      string                 `json:"tenant_id"`
	UserID        string                 `json:"user_id"`
	Data          map[string]interface{} `json:"data"`
	Metadata      map[string]interface{} `json:"metadata"`
}

func (e BaseEvent) GetID() string                      { return e.ID }
func (e BaseEvent) GetType() EventType                 { return e.Type }
func (e BaseEvent) GetAggregateID() string             { return e.AggregateID }
func (e BaseEvent) GetAggregateType() string           { return e.AggregateType }
func (e BaseEvent) GetVersion() int                    { return e.Version }
func (e BaseEvent) GetTimestamp() time.Time            { return e.Timestamp }
func (e BaseEvent) GetTenantID() string                { return e.TenantID }
func (e BaseEvent) GetUserID() string                  { return e.UserID }
func (e BaseEvent) GetData() map[string]interface{}    { return e.Data }

// EventStore interface for storing and retrieving events
type EventStore interface {
	Store(ctx context.Context, event Event) error
	GetEvents(ctx context.Context, aggregateID string, fromVersion int) ([]Event, error)
	GetEventsByType(ctx context.Context, eventType EventType, from, to time.Time) ([]Event, error)
	GetAllEvents(ctx context.Context, from, to time.Time, limit int, offset int) ([]Event, error)
	GetSnapshot(ctx context.Context, aggregateID string) (*AggregateSnapshot, error)
	SaveSnapshot(ctx context.Context, snapshot *AggregateSnapshot) error
}

// AggregateSnapshot represents a snapshot of an aggregate at a point in time
type AggregateSnapshot struct {
	AggregateID   string                 `json:"aggregate_id"`
	AggregateType string                 `json:"aggregate_type"`
	Version       int                    `json:"version"`
	State         map[string]interface{} `json:"state"`
	Timestamp     time.Time              `json:"timestamp"`
}

// InMemoryEventStore is an in-memory implementation of EventStore
type InMemoryEventStore struct {
	events    []Event
	snapshots map[string]*AggregateSnapshot
	mu        sync.RWMutex
	logger    *zap.Logger
}

func NewInMemoryEventStore(logger *zap.Logger) *InMemoryEventStore {
	return &InMemoryEventStore{
		events:    make([]Event, 0),
		snapshots: make(map[string]*AggregateSnapshot),
		logger:    logger,
	}
}

func (s *InMemoryEventStore) Store(ctx context.Context, event Event) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.events = append(s.events, event)
	s.logger.Debug("Event stored",
		zap.String("event_id", event.GetID()),
		zap.String("event_type", string(event.GetType())),
		zap.String("aggregate_id", event.GetAggregateID()))

	return nil
}

func (s *InMemoryEventStore) GetEvents(ctx context.Context, aggregateID string, fromVersion int) ([]Event, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []Event
	for _, event := range s.events {
		if event.GetAggregateID() == aggregateID && event.GetVersion() >= fromVersion {
			result = append(result, event)
		}
	}

	return result, nil
}

func (s *InMemoryEventStore) GetEventsByType(ctx context.Context, eventType EventType, from, to time.Time) ([]Event, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var result []Event
	for _, event := range s.events {
		if event.GetType() == eventType &&
			!event.GetTimestamp().Before(from) &&
			!event.GetTimestamp().After(to) {
			result = append(result, event)
		}
	}

	return result, nil
}

func (s *InMemoryEventStore) GetAllEvents(ctx context.Context, from, to time.Time, limit int, offset int) ([]Event, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	var filtered []Event
	for _, event := range s.events {
		if !event.GetTimestamp().Before(from) && !event.GetTimestamp().After(to) {
			filtered = append(filtered, event)
		}
	}

	// Apply pagination
	start := offset
	if start > len(filtered) {
		start = len(filtered)
	}

	end := start + limit
	if end > len(filtered) {
		end = len(filtered)
	}

	return filtered[start:end], nil
}

func (s *InMemoryEventStore) GetSnapshot(ctx context.Context, aggregateID string) (*AggregateSnapshot, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	snapshot, exists := s.snapshots[aggregateID]
	if !exists {
		return nil, fmt.Errorf("snapshot not found for aggregate: %s", aggregateID)
	}

	return snapshot, nil
}

func (s *InMemoryEventStore) SaveSnapshot(ctx context.Context, snapshot *AggregateSnapshot) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.snapshots[snapshot.AggregateID] = snapshot
	s.logger.Debug("Snapshot saved",
		zap.String("aggregate_id", snapshot.AggregateID),
		zap.Int("version", snapshot.Version))

	return nil
}

// Event Bus for publishing events

// EventBus publishes events to subscribers
type EventBus struct {
	subscribers map[EventType][]EventHandler
	mu          sync.RWMutex
	logger      *zap.Logger
}

// EventHandler handles events
type EventHandler interface {
	Handle(ctx context.Context, event Event) error
	CanHandle(event Event) bool
}

func NewEventBus(logger *zap.Logger) *EventBus {
	return &EventBus{
		subscribers: make(map[EventType][]EventHandler),
		logger:      logger,
	}
}

func (eb *EventBus) Subscribe(eventType EventType, handler EventHandler) {
	eb.mu.Lock()
	defer eb.mu.Unlock()

	eb.subscribers[eventType] = append(eb.subscribers[eventType], handler)
	eb.logger.Info("Event handler subscribed",
		zap.String("event_type", string(eventType)))
}

func (eb *EventBus) Publish(ctx context.Context, event Event) error {
	eb.mu.RLock()
	handlers := eb.subscribers[event.GetType()]
	eb.mu.RUnlock()

	for _, handler := range handlers {
		if handler.CanHandle(event) {
			go func(h EventHandler) {
				if err := h.Handle(ctx, event); err != nil {
					eb.logger.Error("Event handler failed",
						zap.String("event_type", string(event.GetType())),
						zap.Error(err))
				}
			}(handler)
		}
	}

	return nil
}

// Projection for updating read models

// Projection updates read models based on events
type Projection interface {
	Name() string
	Handle(ctx context.Context, event Event) error
	GetPosition() int64
	SetPosition(position int64)
}

// BaseProjection provides common projection functionality
type BaseProjection struct {
	name     string
	position int64
	mu       sync.RWMutex
}

func (p *BaseProjection) Name() string { return p.name }

func (p *BaseProjection) GetPosition() int64 {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return p.position
}

func (p *BaseProjection) SetPosition(position int64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.position = position
}

// ProductProjection updates product read models
type ProductProjection struct {
	BaseProjection
	repository ReadRepository
	logger     *zap.Logger
}

func NewProductProjection(repo ReadRepository, logger *zap.Logger) *ProductProjection {
	return &ProductProjection{
		BaseProjection: BaseProjection{name: "product_projection"},
		repository:     repo,
		logger:         logger,
	}
}

func (p *ProductProjection) Handle(ctx context.Context, event Event) error {
	switch event.GetType() {
	case EventTypeProductCreated:
		return p.handleProductCreated(ctx, event)
	case EventTypeProductUpdated:
		return p.handleProductUpdated(ctx, event)
	case EventTypeStockAdjusted:
		return p.handleStockAdjusted(ctx, event)
	default:
		return nil
	}
}

func (p *ProductProjection) handleProductCreated(ctx context.Context, event Event) error {
	data := event.GetData()
	product := &ProductReadModel{
		ID:           event.GetAggregateID(),
		TenantID:     event.GetTenantID(),
		Name:         data["name"].(string),
		SKU:          data["sku"].(string),
		Price:        data["price"].(float64),
		CreatedAt:    event.GetTimestamp(),
		UpdatedAt:    event.GetTimestamp(),
	}

	return p.repository.SaveProductReadModel(ctx, product)
}

func (p *ProductProjection) handleProductUpdated(ctx context.Context, event Event) error {
	return p.repository.UpdateProductReadModel(ctx, event.GetAggregateID(), event.GetData())
}

func (p *ProductProjection) handleStockAdjusted(ctx context.Context, event Event) error {
	data := event.GetData()
	return p.repository.UpdateStockReadModel(ctx,
		event.GetAggregateID(),
		data["shop_id"].(string),
		data["new_stock"].(int))
}

// Event Sourced Aggregate

// EventSourcedAggregate represents an aggregate that sources its state from events
type EventSourcedAggregate interface {
	GetID() string
	GetVersion() int
	GetUncommittedEvents() []Event
	MarkEventsAsCommitted()
	LoadFromHistory(events []Event) error
	Apply(event Event) error
}

// AggregateRoot base implementation
type AggregateRoot struct {
	ID                string
	Version           int
	uncommittedEvents []Event
	mu                sync.RWMutex
}

func (a *AggregateRoot) GetID() string { return a.ID }
func (a *AggregateRoot) GetVersion() int { return a.Version }

func (a *AggregateRoot) GetUncommittedEvents() []Event {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.uncommittedEvents
}

func (a *AggregateRoot) MarkEventsAsCommitted() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.uncommittedEvents = []Event{}
}

func (a *AggregateRoot) AddEvent(event Event) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.uncommittedEvents = append(a.uncommittedEvents, event)
	a.Version++
}

// Product Aggregate

// ProductAggregate represents a product aggregate
type ProductAggregate struct {
	AggregateRoot
	Name       string
	SKU        string
	Price      float64
	Stock      map[string]int // shopID -> quantity
	IsDeleted  bool
}

func NewProductAggregate(id string) *ProductAggregate {
	return &ProductAggregate{
		AggregateRoot: AggregateRoot{ID: id},
		Stock:         make(map[string]int),
	}
}

func (p *ProductAggregate) LoadFromHistory(events []Event) error {
	for _, event := range events {
		if err := p.Apply(event); err != nil {
			return err
		}
	}
	return nil
}

func (p *ProductAggregate) Apply(event Event) error {
	switch event.GetType() {
	case EventTypeProductCreated:
		return p.applyProductCreated(event)
	case EventTypeProductUpdated:
		return p.applyProductUpdated(event)
	case EventTypeStockAdjusted:
		return p.applyStockAdjusted(event)
	case EventTypeProductDeleted:
		p.IsDeleted = true
	}
	p.Version = event.GetVersion()
	return nil
}

func (p *ProductAggregate) applyProductCreated(event Event) error {
	data := event.GetData()
	p.Name = data["name"].(string)
	p.SKU = data["sku"].(string)
	p.Price = data["price"].(float64)
	return nil
}

func (p *ProductAggregate) applyProductUpdated(event Event) error {
	data := event.GetData()
	if name, ok := data["name"].(string); ok {
		p.Name = name
	}
	if price, ok := data["price"].(float64); ok {
		p.Price = price
	}
	return nil
}

func (p *ProductAggregate) applyStockAdjusted(event Event) error {
	data := event.GetData()
	shopID := data["shop_id"].(string)
	newStock := data["new_stock"].(int)
	p.Stock[shopID] = newStock
	return nil
}

// Commands on Product Aggregate

func (p *ProductAggregate) Create(name, sku string, price float64) Event {
	event := &BaseEvent{
		ID:            uuid.New().String(),
		Type:          EventTypeProductCreated,
		AggregateID:   p.ID,
		AggregateType: "Product",
		Version:       p.Version + 1,
		Timestamp:     time.Now(),
		Data: map[string]interface{}{
			"name":  name,
			"sku":   sku,
			"price": price,
		},
	}

	p.Apply(event)
	p.AddEvent(event)
	return event
}

func (p *ProductAggregate) UpdatePrice(newPrice float64) Event {
	event := &BaseEvent{
		ID:            uuid.New().String(),
		Type:          EventTypePriceChanged,
		AggregateID:   p.ID,
		AggregateType: "Product",
		Version:       p.Version + 1,
		Timestamp:     time.Now(),
		Data: map[string]interface{}{
			"old_price": p.Price,
			"new_price": newPrice,
		},
	}

	p.Apply(event)
	p.AddEvent(event)
	return event
}

func (p *ProductAggregate) AdjustStock(shopID string, adjustment int, reason string) (Event, error) {
	currentStock := p.Stock[shopID]
	newStock := currentStock + adjustment

	if newStock < 0 {
		return nil, fmt.Errorf("insufficient stock: current=%d, adjustment=%d", currentStock, adjustment)
	}

	event := &BaseEvent{
		ID:            uuid.New().String(),
		Type:          EventTypeStockAdjusted,
		AggregateID:   p.ID,
		AggregateType: "Product",
		Version:       p.Version + 1,
		Timestamp:     time.Now(),
		Data: map[string]interface{}{
			"shop_id":       shopID,
			"old_stock":     currentStock,
			"new_stock":     newStock,
			"adjustment":    adjustment,
			"reason":        reason,
		},
	}

	p.Apply(event)
	p.AddEvent(event)
	return event, nil
}

// Repository interfaces

// WriteRepository for command side
type WriteRepository interface {
	CreateProduct(ctx context.Context, product *Product) error
	UpdateProduct(ctx context.Context, id string, updates map[string]interface{}) error
	DeleteProduct(ctx context.Context, id string) error
	GetProduct(ctx context.Context, id string) (*Product, error)
	AdjustStock(ctx context.Context, productID, shopID string, adjustment int) (int, error)
}

// ReadRepository for query side
type ReadRepository interface {
	GetProductReadModel(ctx context.Context, id string) (*ProductReadModel, error)
	ListProductReadModels(ctx context.Context, query *ListProductsQuery) ([]*ProductReadModel, error)
	GetStockReadModel(ctx context.Context, productID, shopID string) (*StockReadModel, error)
	SaveProductReadModel(ctx context.Context, model *ProductReadModel) error
	UpdateProductReadModel(ctx context.Context, id string, updates map[string]interface{}) error
	UpdateStockReadModel(ctx context.Context, productID, shopID string, stock int) error
	RefreshMaterializedView(ctx context.Context, name, query string) error
}

// Product domain model for write side
type Product struct {
	ID         string
	TenantID   string
	Name       string
	SKU        string
	BrandID    string
	CategoryID string
	Price      float64
	CreatedBy  string
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// Event creation helpers

func NewProductCreatedEvent(product *Product) Event {
	return &BaseEvent{
		ID:            uuid.New().String(),
		Type:          EventTypeProductCreated,
		AggregateID:   product.ID,
		AggregateType: "Product",
		Version:       1,
		Timestamp:     time.Now(),
		TenantID:      product.TenantID,
		UserID:        product.CreatedBy,
		Data: map[string]interface{}{
			"name":        product.Name,
			"sku":         product.SKU,
			"brand_id":    product.BrandID,
			"category_id": product.CategoryID,
			"price":       product.Price,
		},
	}
}

func NewProductUpdatedEvent(productID string, updates map[string]interface{}) Event {
	return &BaseEvent{
		ID:            uuid.New().String(),
		Type:          EventTypeProductUpdated,
		AggregateID:   productID,
		AggregateType: "Product",
		Timestamp:     time.Now(),
		Data:          updates,
	}
}

func NewStockAdjustedEvent(productID, shopID string, adjustment, newStock int, reason string) Event {
	return &BaseEvent{
		ID:            uuid.New().String(),
		Type:          EventTypeStockAdjusted,
		AggregateID:   productID,
		AggregateType: "Product",
		Timestamp:     time.Now(),
		Data: map[string]interface{}{
			"shop_id":    shopID,
			"adjustment": adjustment,
			"new_stock":  newStock,
			"reason":     reason,
		},
	}
}
package cqrs

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"
)

// CommandType represents the type of command
type CommandType string

const (
	CommandTypeCreateProduct     CommandType = "CreateProduct"
	CommandTypeUpdateProduct     CommandType = "UpdateProduct"
	CommandTypeDeleteProduct     CommandType = "DeleteProduct"
	CommandTypeAdjustStock       CommandType = "AdjustStock"
	CommandTypeProcessSale       CommandType = "ProcessSale"
	CommandTypeProcessReturn     CommandType = "ProcessReturn"
	CommandTypeTransferInventory CommandType = "TransferInventory"
)

// Command represents a write operation
type Command interface {
	GetID() string
	GetType() CommandType
	GetAggregateID() string
	GetTimestamp() time.Time
	GetTenantID() string
	GetUserID() string
	Validate() error
}

// BaseCommand contains common command fields
type BaseCommand struct {
	ID          string      `json:"id"`
	Type        CommandType `json:"type"`
	AggregateID string      `json:"aggregate_id"`
	TenantID    string      `json:"tenant_id"`
	UserID      string      `json:"user_id"`
	Timestamp   time.Time   `json:"timestamp"`
	Version     int         `json:"version"`
}

func (c BaseCommand) GetID() string          { return c.ID }
func (c BaseCommand) GetType() CommandType   { return c.Type }
func (c BaseCommand) GetAggregateID() string { return c.AggregateID }
func (c BaseCommand) GetTimestamp() time.Time { return c.Timestamp }
func (c BaseCommand) GetTenantID() string    { return c.TenantID }
func (c BaseCommand) GetUserID() string      { return c.UserID }

// CommandHandler handles command execution
type CommandHandler interface {
	Handle(ctx context.Context, cmd Command) error
	CanHandle(cmd Command) bool
}

// CommandBus dispatches commands to appropriate handlers
type CommandBus struct {
	handlers       map[CommandType]CommandHandler
	eventStore     EventStore
	projections    []Projection
	logger         *zap.Logger
	middleware     []CommandMiddleware
}

// CommandMiddleware represents middleware for command processing
type CommandMiddleware func(next CommandHandlerFunc) CommandHandlerFunc

// CommandHandlerFunc is a function that handles commands
type CommandHandlerFunc func(context.Context, Command) error

// NewCommandBus creates a new command bus
func NewCommandBus(eventStore EventStore, logger *zap.Logger) *CommandBus {
	return &CommandBus{
		handlers:    make(map[CommandType]CommandHandler),
		eventStore:  eventStore,
		projections: make([]Projection, 0),
		logger:      logger,
		middleware:  make([]CommandMiddleware, 0),
	}
}

// RegisterHandler registers a command handler
func (cb *CommandBus) RegisterHandler(cmdType CommandType, handler CommandHandler) {
	cb.handlers[cmdType] = handler
	cb.logger.Info("Command handler registered",
		zap.String("command_type", string(cmdType)))
}

// RegisterProjection registers a projection
func (cb *CommandBus) RegisterProjection(projection Projection) {
	cb.projections = append(cb.projections, projection)
}

// UseMiddleware adds middleware to the command bus
func (cb *CommandBus) UseMiddleware(middleware CommandMiddleware) {
	cb.middleware = append(cb.middleware, middleware)
}

// Send dispatches a command to the appropriate handler
func (cb *CommandBus) Send(ctx context.Context, cmd Command) error {
	// Validate command
	if err := cmd.Validate(); err != nil {
		return fmt.Errorf("command validation failed: %w", err)
	}

	// Get handler
	handler, exists := cb.handlers[cmd.GetType()]
	if !exists {
		return fmt.Errorf("no handler registered for command type: %s", cmd.GetType())
	}

	// Build middleware chain
	handlerFunc := func(ctx context.Context, cmd Command) error {
		return handler.Handle(ctx, cmd)
	}

	// Apply middleware in reverse order
	for i := len(cb.middleware) - 1; i >= 0; i-- {
		handlerFunc = cb.middleware[i](handlerFunc)
	}

	// Execute command
	if err := handlerFunc(ctx, cmd); err != nil {
		cb.logger.Error("Command execution failed",
			zap.String("command_id", cmd.GetID()),
			zap.String("command_type", string(cmd.GetType())),
			zap.Error(err))
		return err
	}

	cb.logger.Info("Command executed successfully",
		zap.String("command_id", cmd.GetID()),
		zap.String("command_type", string(cmd.GetType())))

	return nil
}

// Product Commands

// CreateProductCommand creates a new product
type CreateProductCommand struct {
	BaseCommand
	Name          string                 `json:"name"`
	SKU           string                 `json:"sku"`
	BrandID       string                 `json:"brand_id"`
	CategoryID    string                 `json:"category_id"`
	Price         float64                `json:"price"`
	InitialStock  int                    `json:"initial_stock"`
	Metadata      map[string]interface{} `json:"metadata"`
}

func NewCreateProductCommand(tenantID, userID, name, sku string, price float64) *CreateProductCommand {
	return &CreateProductCommand{
		BaseCommand: BaseCommand{
			ID:        uuid.New().String(),
			Type:      CommandTypeCreateProduct,
			TenantID:  tenantID,
			UserID:    userID,
			Timestamp: time.Now(),
		},
		Name:  name,
		SKU:   sku,
		Price: price,
	}
}

func (c *CreateProductCommand) Validate() error {
	if c.Name == "" {
		return fmt.Errorf("product name is required")
	}
	if c.SKU == "" {
		return fmt.Errorf("product SKU is required")
	}
	if c.Price < 0 {
		return fmt.Errorf("product price must be positive")
	}
	return nil
}

// UpdateProductCommand updates a product
type UpdateProductCommand struct {
	BaseCommand
	ProductID string                 `json:"product_id"`
	Updates   map[string]interface{} `json:"updates"`
}

func (c *UpdateProductCommand) Validate() error {
	if c.ProductID == "" {
		return fmt.Errorf("product ID is required")
	}
	if len(c.Updates) == 0 {
		return fmt.Errorf("no updates provided")
	}
	return nil
}

// Stock Commands

// AdjustStockCommand adjusts product stock
type AdjustStockCommand struct {
	BaseCommand
	ProductID   string    `json:"product_id"`
	ShopID      string    `json:"shop_id"`
	Adjustment  int       `json:"adjustment"`
	Reason      string    `json:"reason"`
	Reference   string    `json:"reference"`
}

func NewAdjustStockCommand(tenantID, userID, productID, shopID string, adjustment int, reason string) *AdjustStockCommand {
	return &AdjustStockCommand{
		BaseCommand: BaseCommand{
			ID:          uuid.New().String(),
			Type:        CommandTypeAdjustStock,
			AggregateID: productID,
			TenantID:    tenantID,
			UserID:      userID,
			Timestamp:   time.Now(),
		},
		ProductID:  productID,
		ShopID:     shopID,
		Adjustment: adjustment,
		Reason:     reason,
	}
}

func (c *AdjustStockCommand) Validate() error {
	if c.ProductID == "" {
		return fmt.Errorf("product ID is required")
	}
	if c.ShopID == "" {
		return fmt.Errorf("shop ID is required")
	}
	if c.Reason == "" {
		return fmt.Errorf("adjustment reason is required")
	}
	return nil
}

// Sales Commands

// ProcessSaleCommand processes a sale
type ProcessSaleCommand struct {
	BaseCommand
	SaleID      string                   `json:"sale_id"`
	ShopID      string                   `json:"shop_id"`
	Items       []SaleItem               `json:"items"`
	Total       float64                  `json:"total"`
	PaymentType string                   `json:"payment_type"`
	CustomerID  string                   `json:"customer_id"`
	Metadata    map[string]interface{}   `json:"metadata"`
}

type SaleItem struct {
	ProductID string  `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
	Discount  float64 `json:"discount"`
}

func (c *ProcessSaleCommand) Validate() error {
	if c.ShopID == "" {
		return fmt.Errorf("shop ID is required")
	}
	if len(c.Items) == 0 {
		return fmt.Errorf("sale must have at least one item")
	}
	for i, item := range c.Items {
		if item.ProductID == "" {
			return fmt.Errorf("product ID required for item %d", i)
		}
		if item.Quantity <= 0 {
			return fmt.Errorf("quantity must be positive for item %d", i)
		}
		if item.Price < 0 {
			return fmt.Errorf("price cannot be negative for item %d", i)
		}
	}
	return nil
}

// Command Handlers Implementation

// ProductCommandHandler handles product commands
type ProductCommandHandler struct {
	eventStore EventStore
	repository WriteRepository
	logger     *zap.Logger
}

func NewProductCommandHandler(eventStore EventStore, repo WriteRepository, logger *zap.Logger) *ProductCommandHandler {
	return &ProductCommandHandler{
		eventStore: eventStore,
		repository: repo,
		logger:     logger,
	}
}

func (h *ProductCommandHandler) Handle(ctx context.Context, cmd Command) error {
	switch c := cmd.(type) {
	case *CreateProductCommand:
		return h.handleCreateProduct(ctx, c)
	case *UpdateProductCommand:
		return h.handleUpdateProduct(ctx, c)
	case *AdjustStockCommand:
		return h.handleAdjustStock(ctx, c)
	default:
		return fmt.Errorf("unsupported command type: %T", cmd)
	}
}

func (h *ProductCommandHandler) CanHandle(cmd Command) bool {
	switch cmd.GetType() {
	case CommandTypeCreateProduct, CommandTypeUpdateProduct, CommandTypeAdjustStock:
		return true
	default:
		return false
	}
}

func (h *ProductCommandHandler) handleCreateProduct(ctx context.Context, cmd *CreateProductCommand) error {
	// Create product in write model
	product := &Product{
		ID:         cmd.AggregateID,
		TenantID:   cmd.TenantID,
		Name:       cmd.Name,
		SKU:        cmd.SKU,
		BrandID:    cmd.BrandID,
		CategoryID: cmd.CategoryID,
		Price:      cmd.Price,
		CreatedBy:  cmd.UserID,
		CreatedAt:  cmd.Timestamp,
	}

	if err := h.repository.CreateProduct(ctx, product); err != nil {
		return fmt.Errorf("failed to create product: %w", err)
	}

	// Create event
	event := NewProductCreatedEvent(product)

	// Store event
	if err := h.eventStore.Store(ctx, event); err != nil {
		// Compensate by deleting the product
		h.repository.DeleteProduct(ctx, product.ID)
		return fmt.Errorf("failed to store event: %w", err)
	}

	return nil
}

func (h *ProductCommandHandler) handleUpdateProduct(ctx context.Context, cmd *UpdateProductCommand) error {
	// Load current state (validate product exists)
	_, err := h.repository.GetProduct(ctx, cmd.ProductID)
	if err != nil {
		return fmt.Errorf("failed to get product: %w", err)
	}

	// Apply updates
	if err := h.repository.UpdateProduct(ctx, cmd.ProductID, cmd.Updates); err != nil {
		return fmt.Errorf("failed to update product: %w", err)
	}

	// Create event
	event := NewProductUpdatedEvent(cmd.ProductID, cmd.Updates)

	// Store event
	if err := h.eventStore.Store(ctx, event); err != nil {
		return fmt.Errorf("failed to store event: %w", err)
	}

	return nil
}

func (h *ProductCommandHandler) handleAdjustStock(ctx context.Context, cmd *AdjustStockCommand) error {
	// Adjust stock in write model
	newStock, err := h.repository.AdjustStock(ctx, cmd.ProductID, cmd.ShopID, cmd.Adjustment)
	if err != nil {
		return fmt.Errorf("failed to adjust stock: %w", err)
	}

	// Create event
	event := NewStockAdjustedEvent(cmd.ProductID, cmd.ShopID, cmd.Adjustment, newStock, cmd.Reason)

	// Store event
	if err := h.eventStore.Store(ctx, event); err != nil {
		// Compensate by reversing the adjustment
		h.repository.AdjustStock(ctx, cmd.ProductID, cmd.ShopID, -cmd.Adjustment)
		return fmt.Errorf("failed to store event: %w", err)
	}

	return nil
}

// Saga for complex workflows
type Saga struct {
	ID            string
	Name          string
	State         string
	CompletedSteps []string
	Context       map[string]interface{}
	StartedAt     time.Time
	CompletedAt   *time.Time
}

// SagaOrchestrator manages saga execution
type SagaOrchestrator struct {
	commandBus *CommandBus
	eventStore EventStore
	logger     *zap.Logger
}

func (so *SagaOrchestrator) ExecuteSaga(ctx context.Context, saga *Saga, steps []SagaStep) error {
	for _, step := range steps {
		if err := step.Execute(ctx, saga); err != nil {
			// Compensate previous steps
			for i := len(saga.CompletedSteps) - 1; i >= 0; i-- {
				if compensateErr := steps[i].Compensate(ctx, saga); compensateErr != nil {
					so.logger.Error("Compensation failed",
						zap.String("saga_id", saga.ID),
						zap.String("step", saga.CompletedSteps[i]),
						zap.Error(compensateErr))
				}
			}
			return err
		}
		saga.CompletedSteps = append(saga.CompletedSteps, step.Name())
	}

	now := time.Now()
	saga.CompletedAt = &now
	saga.State = "completed"

	return nil
}

// SagaStep represents a step in a saga
type SagaStep interface {
	Name() string
	Execute(ctx context.Context, saga *Saga) error
	Compensate(ctx context.Context, saga *Saga) error
}
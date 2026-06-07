package cqrs

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"go.uber.org/zap"
)

// QueryType represents the type of query
type QueryType string

const (
	QueryTypeGetProduct        QueryType = "GetProduct"
	QueryTypeListProducts      QueryType = "ListProducts"
	QueryTypeGetStock          QueryType = "GetStock"
	QueryTypeGetSalesSummary   QueryType = "GetSalesSummary"
	QueryTypeGetInventoryStats QueryType = "GetInventoryStats"
)

// Query represents a read operation
type Query interface {
	GetType() QueryType
	GetTenantID() string
	Validate() error
}

// BaseQuery contains common query fields
type BaseQuery struct {
	Type     QueryType `json:"type"`
	TenantID string    `json:"tenant_id"`
}

func (q BaseQuery) GetType() QueryType { return q.Type }
func (q BaseQuery) GetTenantID() string { return q.TenantID }

// QueryHandler handles query execution
type QueryHandler interface {
	Handle(ctx context.Context, query Query) (interface{}, error)
	CanHandle(query Query) bool
}

// QueryBus dispatches queries to appropriate handlers
type QueryBus struct {
	handlers   map[QueryType]QueryHandler
	cache      QueryCache
	logger     *zap.Logger
	middleware []QueryMiddleware
}

// QueryMiddleware represents middleware for query processing
type QueryMiddleware func(next QueryHandlerFunc) QueryHandlerFunc

// QueryHandlerFunc is a function that handles queries
type QueryHandlerFunc func(context.Context, Query) (interface{}, error)

// QueryCache provides caching for query results
type QueryCache interface {
	Get(ctx context.Context, key string) (interface{}, bool)
	Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error
	Delete(ctx context.Context, key string) error
	Clear(ctx context.Context) error
}

// NewQueryBus creates a new query bus
func NewQueryBus(cache QueryCache, logger *zap.Logger) *QueryBus {
	return &QueryBus{
		handlers:   make(map[QueryType]QueryHandler),
		cache:      cache,
		logger:     logger,
		middleware: make([]QueryMiddleware, 0),
	}
}

// RegisterHandler registers a query handler
func (qb *QueryBus) RegisterHandler(queryType QueryType, handler QueryHandler) {
	qb.handlers[queryType] = handler
	qb.logger.Info("Query handler registered",
		zap.String("query_type", string(queryType)))
}

// UseMiddleware adds middleware to the query bus
func (qb *QueryBus) UseMiddleware(middleware QueryMiddleware) {
	qb.middleware = append(qb.middleware, middleware)
}

// Send dispatches a query to the appropriate handler
func (qb *QueryBus) Send(ctx context.Context, query Query) (interface{}, error) {
	// Validate query
	if err := query.Validate(); err != nil {
		return nil, fmt.Errorf("query validation failed: %w", err)
	}

	// Check cache
	cacheKey := qb.getCacheKey(query)
	if cached, found := qb.cache.Get(ctx, cacheKey); found {
		qb.logger.Debug("Query result from cache",
			zap.String("query_type", string(query.GetType())))
		return cached, nil
	}

	// Get handler
	handler, exists := qb.handlers[query.GetType()]
	if !exists {
		return nil, fmt.Errorf("no handler registered for query type: %s", query.GetType())
	}

	// Build middleware chain
	handlerFunc := func(ctx context.Context, q Query) (interface{}, error) {
		return handler.Handle(ctx, q)
	}

	// Apply middleware in reverse order
	for i := len(qb.middleware) - 1; i >= 0; i-- {
		handlerFunc = qb.middleware[i](handlerFunc)
	}

	// Execute query
	result, err := handlerFunc(ctx, query)
	if err != nil {
		qb.logger.Error("Query execution failed",
			zap.String("query_type", string(query.GetType())),
			zap.Error(err))
		return nil, err
	}

	// Cache result
	if err := qb.cache.Set(ctx, cacheKey, result, 5*time.Minute); err != nil {
		qb.logger.Warn("Failed to cache query result",
			zap.String("query_type", string(query.GetType())),
			zap.Error(err))
	}

	return result, nil
}

func (qb *QueryBus) getCacheKey(query Query) string {
	data, _ := json.Marshal(query)
	return fmt.Sprintf("query:%s:%s", query.GetType(), string(data))
}

// Product Queries

// GetProductQuery gets a product by ID
type GetProductQuery struct {
	BaseQuery
	ProductID string `json:"product_id"`
}

func (q *GetProductQuery) Validate() error {
	if q.ProductID == "" {
		return fmt.Errorf("product ID is required")
	}
	return nil
}

// ListProductsQuery lists products with filters
type ListProductsQuery struct {
	BaseQuery
	ShopID     string   `json:"shop_id"`
	CategoryID string   `json:"category_id"`
	BrandID    string   `json:"brand_id"`
	Search     string   `json:"search"`
	Limit      int      `json:"limit"`
	Offset     int      `json:"offset"`
	SortBy     string   `json:"sort_by"`
	SortOrder  string   `json:"sort_order"`
}

func (q *ListProductsQuery) Validate() error {
	if q.Limit < 0 {
		return fmt.Errorf("limit must be non-negative")
	}
	if q.Offset < 0 {
		return fmt.Errorf("offset must be non-negative")
	}
	return nil
}

// Stock Queries

// GetStockQuery gets stock for a product
type GetStockQuery struct {
	BaseQuery
	ProductID string `json:"product_id"`
	ShopID    string `json:"shop_id"`
}

func (q *GetStockQuery) Validate() error {
	if q.ProductID == "" {
		return fmt.Errorf("product ID is required")
	}
	return nil
}

// Analytics Queries

// GetSalesSummaryQuery gets sales summary
type GetSalesSummaryQuery struct {
	BaseQuery
	ShopID    string    `json:"shop_id"`
	StartDate time.Time `json:"start_date"`
	EndDate   time.Time `json:"end_date"`
	GroupBy   string    `json:"group_by"` // day, week, month
}

func (q *GetSalesSummaryQuery) Validate() error {
	if q.EndDate.Before(q.StartDate) {
		return fmt.Errorf("end date must be after start date")
	}
	return nil
}

// Read Models (Projections)

// ProductReadModel optimized for queries
type ProductReadModel struct {
	ID               string                 `json:"id"`
	TenantID         string                 `json:"tenant_id"`
	Name             string                 `json:"name"`
	SKU              string                 `json:"sku"`
	BrandID          string                 `json:"brand_id"`
	BrandName        string                 `json:"brand_name"`
	CategoryID       string                 `json:"category_id"`
	CategoryName     string                 `json:"category_name"`
	Price            float64                `json:"price"`
	Stock            int                    `json:"stock"`
	ReservedStock    int                    `json:"reserved_stock"`
	AvailableStock   int                    `json:"available_stock"`
	LastStockUpdate  time.Time              `json:"last_stock_update"`
	Metadata         map[string]interface{} `json:"metadata"`
	SearchVector     string                 `json:"-"` // For full-text search
	CreatedAt        time.Time              `json:"created_at"`
	UpdatedAt        time.Time              `json:"updated_at"`
}

// StockReadModel optimized for stock queries
type StockReadModel struct {
	ProductID      string    `json:"product_id"`
	ProductName    string    `json:"product_name"`
	ShopID         string    `json:"shop_id"`
	ShopName       string    `json:"shop_name"`
	Quantity       int       `json:"quantity"`
	Reserved       int       `json:"reserved"`
	Available      int       `json:"available"`
	MinimumLevel   int       `json:"minimum_level"`
	ReorderPoint   int       `json:"reorder_point"`
	LastMovement   time.Time `json:"last_movement"`
	LastAdjustment time.Time `json:"last_adjustment"`
}

// SalesSummaryReadModel for analytics
type SalesSummaryReadModel struct {
	Period        string  `json:"period"`
	TotalSales    float64 `json:"total_sales"`
	TotalQuantity int     `json:"total_quantity"`
	TotalOrders   int     `json:"total_orders"`
	AverageOrder  float64 `json:"average_order"`
	TopProducts   []struct {
		ProductID   string  `json:"product_id"`
		ProductName string  `json:"product_name"`
		Quantity    int     `json:"quantity"`
		Revenue     float64 `json:"revenue"`
	} `json:"top_products"`
}

// Query Handlers Implementation

// ProductQueryHandler handles product queries
type ProductQueryHandler struct {
	repository ReadRepository
	cache      QueryCache
	logger     *zap.Logger
}

func NewProductQueryHandler(repo ReadRepository, cache QueryCache, logger *zap.Logger) *ProductQueryHandler {
	return &ProductQueryHandler{
		repository: repo,
		cache:      cache,
		logger:     logger,
	}
}

func (h *ProductQueryHandler) Handle(ctx context.Context, query Query) (interface{}, error) {
	switch q := query.(type) {
	case *GetProductQuery:
		return h.handleGetProduct(ctx, q)
	case *ListProductsQuery:
		return h.handleListProducts(ctx, q)
	case *GetStockQuery:
		return h.handleGetStock(ctx, q)
	default:
		return nil, fmt.Errorf("unsupported query type: %T", query)
	}
}

func (h *ProductQueryHandler) CanHandle(query Query) bool {
	switch query.GetType() {
	case QueryTypeGetProduct, QueryTypeListProducts, QueryTypeGetStock:
		return true
	default:
		return false
	}
}

func (h *ProductQueryHandler) handleGetProduct(ctx context.Context, query *GetProductQuery) (*ProductReadModel, error) {
	return h.repository.GetProductReadModel(ctx, query.ProductID)
}

func (h *ProductQueryHandler) handleListProducts(ctx context.Context, query *ListProductsQuery) ([]*ProductReadModel, error) {
	return h.repository.ListProductReadModels(ctx, query)
}

func (h *ProductQueryHandler) handleGetStock(ctx context.Context, query *GetStockQuery) (*StockReadModel, error) {
	return h.repository.GetStockReadModel(ctx, query.ProductID, query.ShopID)
}

// Materialized Views for complex queries

// MaterializedView represents a pre-computed view
type MaterializedView struct {
	Name           string
	Query          string
	RefreshPolicy  RefreshPolicy
	LastRefresh    time.Time
	NextRefresh    time.Time
	Dependencies   []string
	mu             sync.RWMutex
}

// RefreshPolicy determines when to refresh the view
type RefreshPolicy interface {
	ShouldRefresh(view *MaterializedView) bool
	NextRefreshTime(view *MaterializedView) time.Time
}

// TimeBasedRefreshPolicy refreshes based on time interval
type TimeBasedRefreshPolicy struct {
	Interval time.Duration
}

func (p *TimeBasedRefreshPolicy) ShouldRefresh(view *MaterializedView) bool {
	return time.Since(view.LastRefresh) >= p.Interval
}

func (p *TimeBasedRefreshPolicy) NextRefreshTime(view *MaterializedView) time.Time {
	return view.LastRefresh.Add(p.Interval)
}

// EventBasedRefreshPolicy refreshes on specific events
type EventBasedRefreshPolicy struct {
	TriggerEvents []EventType
}

func (p *EventBasedRefreshPolicy) ShouldRefresh(view *MaterializedView) bool {
	// Check if any trigger event has occurred since last refresh
	return false // Implementation would check event store
}

func (p *EventBasedRefreshPolicy) NextRefreshTime(view *MaterializedView) time.Time {
	return time.Now().Add(24 * time.Hour) // Default to daily
}

// ViewManager manages materialized views
type ViewManager struct {
	views      map[string]*MaterializedView
	repository ReadRepository
	logger     *zap.Logger
	mu         sync.RWMutex
}

func NewViewManager(repo ReadRepository, logger *zap.Logger) *ViewManager {
	return &ViewManager{
		views:      make(map[string]*MaterializedView),
		repository: repo,
		logger:     logger,
	}
}

func (vm *ViewManager) RegisterView(view *MaterializedView) {
	vm.mu.Lock()
	defer vm.mu.Unlock()

	vm.views[view.Name] = view
	vm.logger.Info("Materialized view registered",
		zap.String("view", view.Name))

	// Start refresh goroutine
	go vm.refreshLoop(view)
}

func (vm *ViewManager) refreshLoop(view *MaterializedView) {
	for {
		if view.RefreshPolicy.ShouldRefresh(view) {
			if err := vm.refreshView(view); err != nil {
				vm.logger.Error("Failed to refresh materialized view",
					zap.String("view", view.Name),
					zap.Error(err))
			}
		}

		// Sleep until next refresh
		sleepDuration := time.Until(view.RefreshPolicy.NextRefreshTime(view))
		time.Sleep(sleepDuration)
	}
}

func (vm *ViewManager) refreshView(view *MaterializedView) error {
	view.mu.Lock()
	defer view.mu.Unlock()

	// Execute refresh query
	if err := vm.repository.RefreshMaterializedView(context.Background(), view.Name, view.Query); err != nil {
		return err
	}

	view.LastRefresh = time.Now()
	view.NextRefresh = view.RefreshPolicy.NextRefreshTime(view)

	vm.logger.Info("Materialized view refreshed",
		zap.String("view", view.Name),
		zap.Time("next_refresh", view.NextRefresh))

	return nil
}

// Denormalized Read Models for performance

// DenormalizedProductView combines multiple entities for fast reads
type DenormalizedProductView struct {
	// Product details
	ProductID    string  `json:"product_id"`
	ProductName  string  `json:"product_name"`
	SKU          string  `json:"sku"`
	Price        float64 `json:"price"`

	// Brand details
	BrandID   string `json:"brand_id"`
	BrandName string `json:"brand_name"`

	// Category details
	CategoryID       string `json:"category_id"`
	CategoryName     string `json:"category_name"`
	SubcategoryID    string `json:"subcategory_id"`
	SubcategoryName  string `json:"subcategory_name"`

	// Stock across all shops
	TotalStock     int                    `json:"total_stock"`
	StockByShop    map[string]int         `json:"stock_by_shop"`

	// Sales metrics
	TotalSold      int                    `json:"total_sold"`
	LastSaleDate   *time.Time             `json:"last_sale_date"`
	SalesVelocity  float64                `json:"sales_velocity"`

	// Metadata
	Tags           []string               `json:"tags"`
	Attributes     map[string]interface{} `json:"attributes"`
	LastUpdated    time.Time              `json:"last_updated"`
}
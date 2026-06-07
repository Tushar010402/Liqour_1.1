package featureflags

import (
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

// FeatureFlag represents a feature flag configuration
type FeatureFlag struct {
	ID          string                 `json:"id" gorm:"primaryKey"`
	Name        string                 `json:"name" gorm:"unique;not null"`
	Description string                 `json:"description"`
	Enabled     bool                   `json:"enabled"`
	Type        FlagType               `json:"type"`
	Rules       []Rule                 `json:"rules" gorm:"serializer:json"`
	Percentage  float64                `json:"percentage"` // For gradual rollout
	Variants    []Variant              `json:"variants" gorm:"serializer:json"`
	Tags        []string               `json:"tags" gorm:"serializer:json"`
	Metadata    map[string]interface{} `json:"metadata" gorm:"serializer:json"`
	CreatedAt   time.Time              `json:"created_at"`
	UpdatedAt   time.Time              `json:"updated_at"`
	ExpiresAt   *time.Time             `json:"expires_at"`
}

// FlagType represents the type of feature flag
type FlagType string

const (
	FlagTypeBoolean     FlagType = "boolean"
	FlagTypePercentage  FlagType = "percentage"
	FlagTypeVariant     FlagType = "variant"
	FlagTypeScheduled   FlagType = "scheduled"
	FlagTypeConditional FlagType = "conditional"
)

// Rule represents a targeting rule for feature flags
type Rule struct {
	ID         string                 `json:"id"`
	Attribute  string                 `json:"attribute"`
	Operator   Operator               `json:"operator"`
	Value      interface{}            `json:"value"`
	Percentage float64                `json:"percentage,omitempty"`
	Variant    string                 `json:"variant,omitempty"`
	Metadata   map[string]interface{} `json:"metadata,omitempty"`
}

// Operator represents comparison operators for rules
type Operator string

const (
	OperatorEquals      Operator = "equals"
	OperatorNotEquals   Operator = "not_equals"
	OperatorContains    Operator = "contains"
	OperatorStartsWith  Operator = "starts_with"
	OperatorEndsWith    Operator = "ends_with"
	OperatorIn          Operator = "in"
	OperatorNotIn       Operator = "not_in"
	OperatorGreaterThan Operator = "greater_than"
	OperatorLessThan    Operator = "less_than"
	OperatorRegex       Operator = "regex"
)

// Variant represents a feature variant for A/B testing
type Variant struct {
	ID          string                 `json:"id"`
	Name        string                 `json:"name"`
	Description string                 `json:"description"`
	Weight      float64                `json:"weight"` // Distribution weight
	Value       interface{}            `json:"value"`
	Metadata    map[string]interface{} `json:"metadata,omitempty"`
}

// EvaluationContext contains context for evaluating feature flags
type EvaluationContext struct {
	UserID     string                 `json:"user_id"`
	TenantID   string                 `json:"tenant_id"`
	Role       string                 `json:"role"`
	Email      string                 `json:"email"`
	IPAddress  string                 `json:"ip_address"`
	UserAgent  string                 `json:"user_agent"`
	Country    string                 `json:"country"`
	Region     string                 `json:"region"`
	DeviceType string                 `json:"device_type"`
	AppVersion string                 `json:"app_version"`
	Attributes map[string]interface{} `json:"attributes"`
}

// FeatureFlagManager manages feature flags
type FeatureFlagManager struct {
	db          *gorm.DB
	redis       *redis.Client
	logger      *zap.Logger
	config      *Config
	flags       map[string]*FeatureFlag
	evaluators  map[FlagType]Evaluator
	subscribers []Subscriber
	metrics     *Metrics
	mu          sync.RWMutex
}

// Config contains feature flag configuration
type Config struct {
	RefreshInterval   time.Duration `json:"refresh_interval"`
	CacheTTL          time.Duration `json:"cache_ttl"`
	EnableMetrics     bool          `json:"enable_metrics"`
	EnableWebhooks    bool          `json:"enable_webhooks"`
	DefaultPercentage float64       `json:"default_percentage"`
	StickyBucketing   bool          `json:"sticky_bucketing"`
}

// Evaluator evaluates feature flags
type Evaluator interface {
	Evaluate(flag *FeatureFlag, context *EvaluationContext) (bool, interface{})
}

// Subscriber receives feature flag updates
type Subscriber interface {
	OnFlagUpdate(flag *FeatureFlag)
	OnFlagDelete(flagName string)
}

// Metrics tracks feature flag usage
type Metrics struct {
	Evaluations map[string]int64
	Hits        map[string]int64
	Misses      map[string]int64
	Errors      map[string]int64
	mu          sync.Mutex
}

// NewFeatureFlagManager creates a new feature flag manager
func NewFeatureFlagManager(db *gorm.DB, redis *redis.Client, config *Config, logger *zap.Logger) (*FeatureFlagManager, error) {
	// Auto-migrate feature flags table
	if err := db.AutoMigrate(&FeatureFlag{}); err != nil {
		return nil, err
	}

	ffm := &FeatureFlagManager{
		db:          db,
		redis:       redis,
		logger:      logger,
		config:      config,
		flags:       make(map[string]*FeatureFlag),
		evaluators:  make(map[FlagType]Evaluator),
		subscribers: make([]Subscriber, 0),
		metrics: &Metrics{
			Evaluations: make(map[string]int64),
			Hits:        make(map[string]int64),
			Misses:      make(map[string]int64),
			Errors:      make(map[string]int64),
		},
	}

	// Register evaluators
	ffm.RegisterEvaluator(FlagTypeBoolean, &BooleanEvaluator{})
	ffm.RegisterEvaluator(FlagTypePercentage, &PercentageEvaluator{})
	ffm.RegisterEvaluator(FlagTypeVariant, &VariantEvaluator{})
	ffm.RegisterEvaluator(FlagTypeScheduled, &ScheduledEvaluator{})
	ffm.RegisterEvaluator(FlagTypeConditional, &ConditionalEvaluator{})

	// Load flags from database
	if err := ffm.LoadFlags(); err != nil {
		return nil, err
	}

	// Start refresh goroutine
	go ffm.refreshLoop()

	// Start metrics reporter if enabled
	if config.EnableMetrics {
		go ffm.reportMetrics()
	}

	return ffm, nil
}

// RegisterEvaluator registers a flag evaluator
func (ffm *FeatureFlagManager) RegisterEvaluator(flagType FlagType, evaluator Evaluator) {
	ffm.evaluators[flagType] = evaluator
}

// Subscribe adds a subscriber for flag updates
func (ffm *FeatureFlagManager) Subscribe(subscriber Subscriber) {
	ffm.mu.Lock()
	defer ffm.mu.Unlock()
	ffm.subscribers = append(ffm.subscribers, subscriber)
}

// LoadFlags loads all flags from database
func (ffm *FeatureFlagManager) LoadFlags() error {
	var flags []FeatureFlag
	if err := ffm.db.Find(&flags).Error; err != nil {
		return err
	}

	ffm.mu.Lock()
	defer ffm.mu.Unlock()

	for i := range flags {
		ffm.flags[flags[i].Name] = &flags[i]

		// Cache in Redis
		if ffm.redis != nil {
			ctx := context.Background()
			data, _ := json.Marshal(&flags[i])
			ffm.redis.Set(ctx, ffm.cacheKey(flags[i].Name), data, ffm.config.CacheTTL)
		}
	}

	ffm.logger.Info("Feature flags loaded",
		zap.Int("count", len(flags)))

	return nil
}

// refreshLoop periodically refreshes flags
func (ffm *FeatureFlagManager) refreshLoop() {
	ticker := time.NewTicker(ffm.config.RefreshInterval)
	defer ticker.Stop()

	for range ticker.C {
		if err := ffm.LoadFlags(); err != nil {
			ffm.logger.Error("Failed to refresh feature flags",
				zap.Error(err))
		}
	}
}

// IsEnabled checks if a feature is enabled for the given context
func (ffm *FeatureFlagManager) IsEnabled(flagName string, context *EvaluationContext) bool {
	result, _ := ffm.Evaluate(flagName, context)
	return result
}

// Evaluate evaluates a feature flag
func (ffm *FeatureFlagManager) Evaluate(flagName string, context *EvaluationContext) (bool, interface{}) {
	// Record evaluation
	ffm.recordEvaluation(flagName)

	// Try cache first
	if cached := ffm.getFromCache(flagName); cached != nil {
		return ffm.evaluateFlag(cached, context)
	}

	ffm.mu.RLock()
	flag, exists := ffm.flags[flagName]
	ffm.mu.RUnlock()

	if !exists {
		ffm.recordMiss(flagName)
		return false, nil
	}

	// Check expiration
	if flag.ExpiresAt != nil && time.Now().After(*flag.ExpiresAt) {
		ffm.recordMiss(flagName)
		return false, nil
	}

	// Cache for next time
	ffm.cacheFlag(flag)

	return ffm.evaluateFlag(flag, context)
}

func (ffm *FeatureFlagManager) evaluateFlag(flag *FeatureFlag, context *EvaluationContext) (bool, interface{}) {
	// Global kill switch
	if !flag.Enabled {
		ffm.recordMiss(flag.Name)
		return false, nil
	}

	// Get appropriate evaluator
	evaluator, exists := ffm.evaluators[flag.Type]
	if !exists {
		ffm.recordError(flag.Name)
		return false, nil
	}

	// Evaluate
	enabled, value := evaluator.Evaluate(flag, context)

	if enabled {
		ffm.recordHit(flag.Name)
	} else {
		ffm.recordMiss(flag.Name)
	}

	return enabled, value
}

// GetVariant gets the variant for a feature flag
func (ffm *FeatureFlagManager) GetVariant(flagName string, context *EvaluationContext) *Variant {
	_, value := ffm.Evaluate(flagName, context)
	if variant, ok := value.(*Variant); ok {
		return variant
	}
	return nil
}

// CreateFlag creates a new feature flag
func (ffm *FeatureFlagManager) CreateFlag(flag *FeatureFlag) error {
	flag.ID = generateID()
	flag.CreatedAt = time.Now()
	flag.UpdatedAt = time.Now()

	if err := ffm.db.Create(flag).Error; err != nil {
		return err
	}

	ffm.mu.Lock()
	ffm.flags[flag.Name] = flag
	ffm.mu.Unlock()

	// Notify subscribers
	ffm.notifyUpdate(flag)

	ffm.logger.Info("Feature flag created",
		zap.String("flag", flag.Name))

	return nil
}

// UpdateFlag updates a feature flag
func (ffm *FeatureFlagManager) UpdateFlag(flagName string, updates map[string]interface{}) error {
	ffm.mu.Lock()
	_, exists := ffm.flags[flagName]
	ffm.mu.Unlock()

	if !exists {
		return fmt.Errorf("flag not found: %s", flagName)
	}

	updates["updated_at"] = time.Now()

	if err := ffm.db.Model(&FeatureFlag{}).Where("name = ?", flagName).Updates(updates).Error; err != nil {
		return err
	}

	// Reload flag
	var updatedFlag FeatureFlag
	if err := ffm.db.Where("name = ?", flagName).First(&updatedFlag).Error; err != nil {
		return err
	}

	ffm.mu.Lock()
	ffm.flags[flagName] = &updatedFlag
	ffm.mu.Unlock()

	// Clear cache
	ffm.clearCache(flagName)

	// Notify subscribers
	ffm.notifyUpdate(&updatedFlag)

	ffm.logger.Info("Feature flag updated",
		zap.String("flag", flagName))

	return nil
}

// DeleteFlag deletes a feature flag
func (ffm *FeatureFlagManager) DeleteFlag(flagName string) error {
	if err := ffm.db.Where("name = ?", flagName).Delete(&FeatureFlag{}).Error; err != nil {
		return err
	}

	ffm.mu.Lock()
	delete(ffm.flags, flagName)
	ffm.mu.Unlock()

	// Clear cache
	ffm.clearCache(flagName)

	// Notify subscribers
	ffm.notifyDelete(flagName)

	ffm.logger.Info("Feature flag deleted",
		zap.String("flag", flagName))

	return nil
}

// Cache operations

func (ffm *FeatureFlagManager) cacheKey(flagName string) string {
	return fmt.Sprintf("featureflag:%s", flagName)
}

func (ffm *FeatureFlagManager) cacheFlag(flag *FeatureFlag) {
	if ffm.redis == nil {
		return
	}

	ctx := context.Background()
	data, _ := json.Marshal(flag)
	ffm.redis.Set(ctx, ffm.cacheKey(flag.Name), data, ffm.config.CacheTTL)
}

func (ffm *FeatureFlagManager) getFromCache(flagName string) *FeatureFlag {
	if ffm.redis == nil {
		return nil
	}

	ctx := context.Background()
	data, err := ffm.redis.Get(ctx, ffm.cacheKey(flagName)).Result()
	if err != nil {
		return nil
	}

	var flag FeatureFlag
	if err := json.Unmarshal([]byte(data), &flag); err != nil {
		return nil
	}

	return &flag
}

func (ffm *FeatureFlagManager) clearCache(flagName string) {
	if ffm.redis == nil {
		return
	}

	ctx := context.Background()
	ffm.redis.Del(ctx, ffm.cacheKey(flagName))
}

// Notification

func (ffm *FeatureFlagManager) notifyUpdate(flag *FeatureFlag) {
	for _, subscriber := range ffm.subscribers {
		go subscriber.OnFlagUpdate(flag)
	}
}

func (ffm *FeatureFlagManager) notifyDelete(flagName string) {
	for _, subscriber := range ffm.subscribers {
		go subscriber.OnFlagDelete(flagName)
	}
}

// Metrics

func (ffm *FeatureFlagManager) recordEvaluation(flagName string) {
	ffm.metrics.mu.Lock()
	defer ffm.metrics.mu.Unlock()
	ffm.metrics.Evaluations[flagName]++
}

func (ffm *FeatureFlagManager) recordHit(flagName string) {
	ffm.metrics.mu.Lock()
	defer ffm.metrics.mu.Unlock()
	ffm.metrics.Hits[flagName]++
}

func (ffm *FeatureFlagManager) recordMiss(flagName string) {
	ffm.metrics.mu.Lock()
	defer ffm.metrics.mu.Unlock()
	ffm.metrics.Misses[flagName]++
}

func (ffm *FeatureFlagManager) recordError(flagName string) {
	ffm.metrics.mu.Lock()
	defer ffm.metrics.mu.Unlock()
	ffm.metrics.Errors[flagName]++
}

func (ffm *FeatureFlagManager) reportMetrics() {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		ffm.metrics.mu.Lock()
		metrics := *ffm.metrics
		ffm.metrics.mu.Unlock()

		for flagName, evals := range metrics.Evaluations {
			hits := metrics.Hits[flagName]
			misses := metrics.Misses[flagName]
			errors := metrics.Errors[flagName]

			hitRate := float64(0)
			if evals > 0 {
				hitRate = float64(hits) / float64(evals) * 100
			}

			ffm.logger.Info("Feature flag metrics",
				zap.String("flag", flagName),
				zap.Int64("evaluations", evals),
				zap.Int64("hits", hits),
				zap.Int64("misses", misses),
				zap.Int64("errors", errors),
				zap.Float64("hit_rate", hitRate))
		}
	}
}

// GetMetrics returns current metrics
func (ffm *FeatureFlagManager) GetMetrics() map[string]interface{} {
	ffm.metrics.mu.Lock()
	defer ffm.metrics.mu.Unlock()

	return map[string]interface{}{
		"evaluations": ffm.metrics.Evaluations,
		"hits":        ffm.metrics.Hits,
		"misses":      ffm.metrics.Misses,
		"errors":      ffm.metrics.Errors,
	}
}

// Evaluators

// BooleanEvaluator evaluates simple boolean flags
type BooleanEvaluator struct{}

func (e *BooleanEvaluator) Evaluate(flag *FeatureFlag, context *EvaluationContext) (bool, interface{}) {
	// Check rules first
	for _, rule := range flag.Rules {
		if evaluateRule(rule, context) {
			return true, true
		}
	}

	return flag.Enabled, flag.Enabled
}

// PercentageEvaluator evaluates percentage-based rollouts
type PercentageEvaluator struct{}

func (e *PercentageEvaluator) Evaluate(flag *FeatureFlag, context *EvaluationContext) (bool, interface{}) {
	// Use consistent hashing for sticky bucketing
	bucket := getBucket(flag.Name, context.UserID)
	enabled := bucket < flag.Percentage

	return enabled, enabled
}

// VariantEvaluator evaluates A/B test variants
type VariantEvaluator struct{}

func (e *VariantEvaluator) Evaluate(flag *FeatureFlag, context *EvaluationContext) (bool, interface{}) {
	if len(flag.Variants) == 0 {
		return false, nil
	}

	// Use consistent hashing to assign variant
	bucket := getBucket(flag.Name, context.UserID)

	// Find variant based on weight distribution
	cumWeight := float64(0)
	for _, variant := range flag.Variants {
		cumWeight += variant.Weight
		if bucket < cumWeight {
			return true, &variant
		}
	}

	// Default to first variant
	return true, &flag.Variants[0]
}

// ScheduledEvaluator evaluates time-based flags
type ScheduledEvaluator struct{}

func (e *ScheduledEvaluator) Evaluate(flag *FeatureFlag, context *EvaluationContext) (bool, interface{}) {
	now := time.Now()

	// Check if within schedule
	if flag.Metadata != nil {
		if startStr, ok := flag.Metadata["start_time"].(string); ok {
			if start, err := time.Parse(time.RFC3339, startStr); err == nil && now.Before(start) {
				return false, nil
			}
		}

		if endStr, ok := flag.Metadata["end_time"].(string); ok {
			if end, err := time.Parse(time.RFC3339, endStr); err == nil && now.After(end) {
				return false, nil
			}
		}
	}

	return flag.Enabled, flag.Enabled
}

// ConditionalEvaluator evaluates complex conditional rules
type ConditionalEvaluator struct{}

func (e *ConditionalEvaluator) Evaluate(flag *FeatureFlag, context *EvaluationContext) (bool, interface{}) {
	// Evaluate all rules
	for _, rule := range flag.Rules {
		if !evaluateRule(rule, context) {
			return false, nil
		}
	}

	return true, true
}

// Helper functions

func evaluateRule(rule Rule, context *EvaluationContext) bool {
	// Get attribute value from context
	value := getAttributeValue(context, rule.Attribute)
	if value == nil {
		return false
	}

	// Evaluate based on operator
	switch rule.Operator {
	case OperatorEquals:
		return fmt.Sprintf("%v", value) == fmt.Sprintf("%v", rule.Value)

	case OperatorNotEquals:
		return fmt.Sprintf("%v", value) != fmt.Sprintf("%v", rule.Value)

	case OperatorContains:
		return strings.Contains(fmt.Sprintf("%v", value), fmt.Sprintf("%v", rule.Value))

	case OperatorStartsWith:
		return strings.HasPrefix(fmt.Sprintf("%v", value), fmt.Sprintf("%v", rule.Value))

	case OperatorEndsWith:
		return strings.HasSuffix(fmt.Sprintf("%v", value), fmt.Sprintf("%v", rule.Value))

	case OperatorIn:
		if list, ok := rule.Value.([]interface{}); ok {
			valueStr := fmt.Sprintf("%v", value)
			for _, item := range list {
				if fmt.Sprintf("%v", item) == valueStr {
					return true
				}
			}
		}
		return false

	default:
		return false
	}
}

func getAttributeValue(context *EvaluationContext, attribute string) interface{} {
	switch attribute {
	case "user_id":
		return context.UserID
	case "tenant_id":
		return context.TenantID
	case "role":
		return context.Role
	case "email":
		return context.Email
	case "ip_address":
		return context.IPAddress
	case "country":
		return context.Country
	default:
		if context.Attributes != nil {
			return context.Attributes[attribute]
		}
		return nil
	}
}

func getBucket(flagName, userID string) float64 {
	h := fnv.New64a()
	h.Write([]byte(flagName + userID))
	hash := h.Sum64()
	return float64(hash%100) / 100.0
}

func generateID() string {
	return fmt.Sprintf("ff_%d", time.Now().UnixNano())
}

// FeatureFlagMiddleware provides Gin middleware for feature flags
func (ffm *FeatureFlagManager) FeatureFlagMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Build evaluation context from request
		context := &EvaluationContext{
			UserID:     c.GetString("user_id"),
			TenantID:   c.GetString("tenant_id"),
			Role:       c.GetString("role"),
			IPAddress:  c.ClientIP(),
			UserAgent:  c.Request.UserAgent(),
			Attributes: make(map[string]interface{}),
		}

		// Store in request context
		c.Set("feature_flags", ffm)
		c.Set("evaluation_context", context)

		c.Next()
	}
}

// GetFeatureFlag helper for handlers
func GetFeatureFlag(c *gin.Context, flagName string) bool {
	ffm, exists := c.Get("feature_flags")
	if !exists {
		return false
	}

	context, exists := c.Get("evaluation_context")
	if !exists {
		return false
	}

	manager := ffm.(*FeatureFlagManager)
	evalContext := context.(*EvaluationContext)

	return manager.IsEnabled(flagName, evalContext)
}

// WebhookSubscriber sends webhook notifications
type WebhookSubscriber struct {
	URL    string
	Secret string
	Logger *zap.Logger
}

func (ws *WebhookSubscriber) OnFlagUpdate(flag *FeatureFlag) {
	// Send webhook notification
	payload, _ := json.Marshal(map[string]interface{}{
		"event": "flag_updated",
		"flag":  flag,
		"timestamp": time.Now().Unix(),
	})

	// Implementation would send HTTP POST to webhook URL
	ws.Logger.Info("Webhook notification sent",
		zap.String("flag", flag.Name),
		zap.String("url", ws.URL))
	_ = payload
}

func (ws *WebhookSubscriber) OnFlagDelete(flagName string) {
	// Send webhook notification for deletion
	payload, _ := json.Marshal(map[string]interface{}{
		"event": "flag_deleted",
		"flag_name": flagName,
		"timestamp": time.Now().Unix(),
	})

	ws.Logger.Info("Webhook deletion notification sent",
		zap.String("flag", flagName),
		zap.String("url", ws.URL))
	_ = payload
}
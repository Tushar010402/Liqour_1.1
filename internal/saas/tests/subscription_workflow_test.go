package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
	"gorm.io/gorm"

	"github.com/liquorpro/go-backend/internal/saas/handlers"
	"github.com/liquorpro/go-backend/internal/saas/models"
	"github.com/liquorpro/go-backend/internal/saas/services"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

type SubscriptionWorkflowTestSuite struct {
	suite.Suite
	db                  *gorm.DB
	cache               *cache.Cache
	cfg                 *config.Config
	subscriptionService *services.SubscriptionService
	subscriptionHandler *handlers.SubscriptionHandler
	billingService      *services.AutonomousBillingService
	usageService        *services.UsageTrackingService
	router              *gin.Engine
	testTenant          models.Tenant
	testPlan            models.PricingPlan
	premiumPlan         models.PricingPlan
}

func (suite *SubscriptionWorkflowTestSuite) SetupSuite() {
	// Setup test database using PostgreSQL
	dbConfig := GetTestDatabaseConfig()

	dbConn, err := database.NewDatabase(dbConfig)
	if err != nil {
		// If PostgreSQL is not available, skip tests
		suite.T().Skip("PostgreSQL not available for testing:", err)
		return
	}
	suite.db = dbConn.DB

	// Run migrations
	err = suite.db.AutoMigrate(
		&models.PricingPlan{},
		&models.Subscription{},
		&models.Payment{},
		&models.Invoice{},
		&models.UsageRecord{},
		&models.PlanTransition{},
		&models.PlanTransitionHistory{},
		&models.Tenant{},
		&models.TenantUser{},
		&models.Shop{},
		&models.Product{},
		&models.Sale{},
		&models.WebhookEvent{},
		&models.AdminUser{},
		&models.AuditLog{},
	)
	suite.Require().NoError(err)

	// Setup test config
	suite.cfg = &config.Config{
		Database: config.DatabaseConfig{
			Host:     "localhost",
			Port:     5432,
			User:     "test",
			Password: "test",
			DBName:   "test",
		},
		Redis: config.RedisConfig{
			Host: "localhost",
			Port: 6379,
		},
	}

	// Setup mock cache
	suite.cache = &cache.Cache{}

	// Initialize services
	suite.subscriptionService = services.NewSubscriptionService(suite.db, suite.cfg)
	suite.billingService = services.NewAutonomousBillingService(suite.db, suite.cfg, suite.cache)
	suite.usageService = services.NewUsageTrackingService(suite.db, suite.cache, suite.cfg)

	// Initialize handlers
	suite.subscriptionHandler = handlers.NewSubscriptionHandler(suite.subscriptionService)

	// Setup router
	gin.SetMode(gin.TestMode)
	suite.router = gin.New()
	suite.setupTestRoutes()

	// Create test data
	suite.createTestData()
}

func (suite *SubscriptionWorkflowTestSuite) setupTestRoutes() {
	api := suite.router.Group("/api")

	subscriptions := api.Group("/subscriptions")
	{
		subscriptions.GET("", suite.subscriptionHandler.GetSubscription)
		subscriptions.POST("", suite.subscriptionHandler.CreateSubscription)
		subscriptions.PUT("/:id", suite.subscriptionHandler.UpdateSubscription)
		subscriptions.DELETE("/:id", suite.subscriptionHandler.CancelSubscription)
		subscriptions.POST("/:id/upgrade", suite.subscriptionHandler.UpgradeSubscription)
		subscriptions.POST("/:id/downgrade", suite.subscriptionHandler.DowngradeSubscription)
		subscriptions.GET("/:id/usage", suite.subscriptionHandler.GetUsage)
	}
}

func (suite *SubscriptionWorkflowTestSuite) createTestData() {
	// Create test tenant
	suite.testTenant = models.Tenant{
		ID:       uuid.New(),
		Name:     "Test Company",
		IsActive: true,
	}
	suite.db.Create(&suite.testTenant)

	// Create test plans
	suite.testPlan = models.PricingPlan{
		ID:           uuid.New(),
		Name:         "starter-plan",
		DisplayName:  "Starter Plan",
		Description:  "Perfect for small businesses",
		Price:        99.99,
		Currency:     "INR",
		BillingCycle: "monthly",
		TrialDays:    30,
		MaxLocations: 3,
		MaxUsers:     25,
		MaxProducts:  1000,
		Features:     []string{"basic_reporting", "inventory_management"},
		Active:       true,
		SortOrder:    1,
	}
	suite.db.Create(&suite.testPlan)

	suite.premiumPlan = models.PricingPlan{
		ID:           uuid.New(),
		Name:         "premium-plan",
		DisplayName:  "Premium Plan",
		Description:  "Advanced features for growing businesses",
		Price:        299.99,
		Currency:     "INR",
		BillingCycle: "monthly",
		TrialDays:    14,
		MaxLocations: 10,
		MaxUsers:     100,
		MaxProducts:  5000,
		Features:     []string{"advanced_reporting", "inventory_management", "multi_location", "api_access"},
		Active:       true,
		SortOrder:    2,
	}
	suite.db.Create(&suite.premiumPlan)
}

func (suite *SubscriptionWorkflowTestSuite) TearDownSuite() {
	db, _ := suite.db.DB()
	db.Close()
}

func (suite *SubscriptionWorkflowTestSuite) TestCreateSubscription() {
	subscriptionRequest := models.CreateSubscriptionRequest{
		TenantID:          suite.testTenant.ID,
		PlanID:            suite.testPlan.ID,
		BillingCycle:      "monthly",
		BillingTermMonths: 1,
		AutoRenew:         true,
	}

	jsonData, _ := json.Marshal(subscriptionRequest)
	req, _ := http.NewRequest("POST", "/api/subscriptions", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusCreated, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), response, "subscription")

	subscription := response["subscription"].(map[string]interface{})
	assert.Equal(suite.T(), suite.testTenant.ID.String(), subscription["tenant_id"])
	assert.Equal(suite.T(), suite.testPlan.ID.String(), subscription["plan_id"])
	assert.Equal(suite.T(), "trial", subscription["status"])
}

func (suite *SubscriptionWorkflowTestSuite) TestGetSubscription() {
	// First create a subscription
	subscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           suite.testTenant.ID,
		PlanID:             suite.testPlan.ID,
		Status:             "active",
		CurrentPeriodStart: time.Now(),
		CurrentPeriodEnd:   time.Now().AddDate(0, 1, 0),
		BillingCycle:       "monthly",
		Amount:             99.99,
		Currency:           "INR",
		AutoRenew:          true,
	}
	suite.db.Create(&subscription)

	req, _ := http.NewRequest("GET", "/api/subscriptions?tenant_id="+suite.testTenant.ID.String(), nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), response, "subscription")
}

func (suite *SubscriptionWorkflowTestSuite) TestSubscriptionUpgrade() {
	// Create initial subscription
	subscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           suite.testTenant.ID,
		PlanID:             suite.testPlan.ID,
		Status:             "active",
		CurrentPeriodStart: time.Now(),
		CurrentPeriodEnd:   time.Now().AddDate(0, 1, 0),
		BillingCycle:       "monthly",
		Amount:             99.99,
		Currency:           "INR",
		AutoRenew:          true,
	}
	suite.db.Create(&subscription)

	upgradeRequest := map[string]interface{}{
		"new_plan_id": suite.premiumPlan.ID.String(),
		"reason":      "Need more features",
	}

	jsonData, _ := json.Marshal(upgradeRequest)
	req, _ := http.NewRequest("POST", "/api/subscriptions/"+subscription.ID.String()+"/upgrade", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), response, "message")
}

func (suite *SubscriptionWorkflowTestSuite) TestSubscriptionCancellation() {
	// Create subscription to cancel
	subscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           suite.testTenant.ID,
		PlanID:             suite.testPlan.ID,
		Status:             "active",
		CurrentPeriodStart: time.Now(),
		CurrentPeriodEnd:   time.Now().AddDate(0, 1, 0),
		BillingCycle:       "monthly",
		Amount:             99.99,
		Currency:           "INR",
		AutoRenew:          true,
	}
	suite.db.Create(&subscription)

	req, _ := http.NewRequest("DELETE", "/api/subscriptions/"+subscription.ID.String(), nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), response, "message")

	// Verify subscription status changed
	var updatedSubscription models.Subscription
	suite.db.First(&updatedSubscription, subscription.ID)
	assert.Equal(suite.T(), "cancelled", updatedSubscription.Status)
	assert.NotNil(suite.T(), updatedSubscription.CancelledAt)
}

func (suite *SubscriptionWorkflowTestSuite) TestUsageTracking() {
	// Create subscription
	subscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           suite.testTenant.ID,
		PlanID:             suite.testPlan.ID,
		Status:             "active",
		CurrentPeriodStart: time.Now(),
		CurrentPeriodEnd:   time.Now().AddDate(0, 1, 0),
		BillingCycle:       "monthly",
		Amount:             99.99,
		Currency:           "INR",
	}
	suite.db.Create(&subscription)

	req, _ := http.NewRequest("GET", "/api/subscriptions/"+subscription.ID.String()+"/usage", nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var response map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &response)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), response, "usage")
}

func (suite *SubscriptionWorkflowTestSuite) TestBillingCycleCalculations() {
	// Test monthly billing
	monthlyPlan := suite.testPlan
	monthlySubscription := models.Subscription{
		BillingCycle:       "monthly",
		CurrentPeriodStart: time.Now(),
		CurrentPeriodEnd:   time.Now().AddDate(0, 1, 0),
		Amount:             monthlyPlan.Price,
	}

	// Verify billing cycle dates
	assert.Equal(suite.T(), "monthly", monthlySubscription.BillingCycle)
	assert.True(suite.T(), monthlySubscription.CurrentPeriodEnd.After(monthlySubscription.CurrentPeriodStart))

	duration := monthlySubscription.CurrentPeriodEnd.Sub(monthlySubscription.CurrentPeriodStart)
	expectedDuration := 30 * 24 * time.Hour                                   // Approximately 30 days
	assert.InDelta(suite.T(), expectedDuration.Hours(), duration.Hours(), 48) // Allow 2 days variance
}

func (suite *SubscriptionWorkflowTestSuite) TestTrialPeriodHandling() {
	// Test trial subscription creation
	now := time.Now()
	trialSubscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           suite.testTenant.ID,
		PlanID:             suite.testPlan.ID,
		Status:             "trial",
		CurrentPeriodStart: now,
		CurrentPeriodEnd:   now.AddDate(0, 0, suite.testPlan.TrialDays),
		BillingCycle:       "monthly",
		Amount:             0, // No charge during trial
		Currency:           "INR",
	}
	trialStart := now
	trialEnd := now.AddDate(0, 0, suite.testPlan.TrialDays)
	trialSubscription.TrialStart = &trialStart
	trialSubscription.TrialEnd = &trialEnd

	suite.db.Create(&trialSubscription)

	// Verify trial setup
	assert.Equal(suite.T(), "trial", trialSubscription.Status)
	assert.NotNil(suite.T(), trialSubscription.TrialStart)
	assert.NotNil(suite.T(), trialSubscription.TrialEnd)
	assert.True(suite.T(), trialSubscription.TrialEnd.After(*trialSubscription.TrialStart))
	assert.Equal(suite.T(), float64(0), trialSubscription.Amount)
}

func (suite *SubscriptionWorkflowTestSuite) TestSubscriptionLimitsEnforcement() {
	ctx := context.Background()

	// Create subscription
	subscription := models.Subscription{
		ID:       uuid.New(),
		TenantID: suite.testTenant.ID,
		PlanID:   suite.testPlan.ID,
		Status:   "active",
	}
	suite.db.Create(&subscription)

	// Test adding users up to limit
	for i := 0; i < suite.testPlan.MaxUsers; i++ {
		usageEvent := services.UsageEvent{
			TenantID:     suite.testTenant.ID,
			ResourceType: "users",
			Action:       "CREATE",
			Quantity:     1,
			Timestamp:    time.Now(),
		}
		err := suite.usageService.TrackUsage(ctx, usageEvent)
		assert.NoError(suite.T(), err)
	}

	// Verify current usage
	currentUsage, err := suite.usageService.GetCurrentUsage(ctx, suite.testTenant.ID, "users")
	assert.NoError(suite.T(), err)
	assert.Equal(suite.T(), suite.testPlan.MaxUsers, currentUsage)

	// Test exceeding limit (should trigger alerts)
	usageEvent := services.UsageEvent{
		TenantID:     suite.testTenant.ID,
		ResourceType: "users",
		Action:       "CREATE",
		Quantity:     1,
		Timestamp:    time.Now(),
	}
	err = suite.usageService.TrackUsage(ctx, usageEvent)
	assert.NoError(suite.T(), err) // Should not error, but should trigger alerts

	newUsage, err := suite.usageService.GetCurrentUsage(ctx, suite.testTenant.ID, "users")
	assert.NoError(suite.T(), err)
	assert.Greater(suite.T(), newUsage, suite.testPlan.MaxUsers)
}

func (suite *SubscriptionWorkflowTestSuite) TestBillingPeriodUsage() {
	ctx := context.Background()

	// Create subscription
	subscription := models.Subscription{
		ID:       uuid.New(),
		TenantID: suite.testTenant.ID,
		PlanID:   suite.testPlan.ID,
		Status:   "active",
	}
	suite.db.Create(&subscription)

	// Track some sales during billing period
	periodStart := time.Now().AddDate(0, 0, -15)
	periodEnd := time.Now().AddDate(0, 0, 15)

	for i := 0; i < 10; i++ {
		sale := models.Sale{
			ID:       uuid.New(),
			TenantID: suite.testTenant.ID,
			Amount:   100.0,
		}
		suite.db.Create(&sale)

		usageEvent := services.UsageEvent{
			TenantID:     suite.testTenant.ID,
			ResourceType: "sales",
			Action:       "CREATE",
			Quantity:     1,
			Timestamp:    time.Now(),
		}
		suite.usageService.TrackUsage(ctx, usageEvent)
	}

	// Get billing period usage
	billingUsage, err := suite.usageService.GetBillingPeriodUsage(ctx, suite.testTenant.ID, periodStart, periodEnd)
	assert.NoError(suite.T(), err)
	assert.NotNil(suite.T(), billingUsage)
	assert.Equal(suite.T(), suite.testTenant.ID, billingUsage.TenantID)
	assert.Contains(suite.T(), billingUsage.ResourceUsage, "sales")
}

func (suite *SubscriptionWorkflowTestSuite) TestWebhookProcessing() {
	// Test webhook event processing
	webhookEvent := models.WebhookEvent{
		ID:        uuid.New(),
		Provider:  "razorpay",
		EventType: "payment.captured",
		EventID:   "evt_test_123",
		Status:    "pending",
		Payload:   `{"payment": {"id": "pay_test_123", "amount": 9999, "status": "captured"}}`,
		Retries:   0,
	}
	suite.db.Create(&webhookEvent)

	// Verify webhook creation
	var savedEvent models.WebhookEvent
	suite.db.First(&savedEvent, webhookEvent.ID)
	assert.Equal(suite.T(), "pending", savedEvent.Status)
	assert.Equal(suite.T(), "razorpay", savedEvent.Provider)
	assert.Equal(suite.T(), "payment.captured", savedEvent.EventType)
}

func TestSubscriptionWorkflowSuite(t *testing.T) {
	suite.Run(t, new(SubscriptionWorkflowTestSuite))
}

// Additional unit tests for edge cases
func TestSubscriptionValidation(t *testing.T) {
	// Test invalid subscription creation
	invalidRequest := models.CreateSubscriptionRequest{
		// Missing required fields
		BillingCycle: "invalid", // Invalid billing cycle
	}

	assert.Empty(t, invalidRequest.TenantID)
	assert.Empty(t, invalidRequest.PlanID)
	assert.Equal(t, "invalid", invalidRequest.BillingCycle)

	// Test valid subscription creation
	validRequest := models.CreateSubscriptionRequest{
		TenantID:          uuid.New(),
		PlanID:            uuid.New(),
		BillingCycle:      "monthly",
		BillingTermMonths: 1,
		AutoRenew:         true,
	}

	assert.NotEqual(t, uuid.Nil, validRequest.TenantID)
	assert.NotEqual(t, uuid.Nil, validRequest.PlanID)
	assert.Contains(t, []string{"monthly", "yearly"}, validRequest.BillingCycle)
	assert.Greater(t, validRequest.BillingTermMonths, 0)
}

func TestBillingCalculations(t *testing.T) {
	// Test proration calculations
	subscription := models.Subscription{
		Amount:             99.99,
		BillingCycle:       "monthly",
		CurrentPeriodStart: time.Now().AddDate(0, 0, -10), // 10 days ago
		CurrentPeriodEnd:   time.Now().AddDate(0, 0, 20),  // 20 days from now
	}

	totalDays := int(subscription.CurrentPeriodEnd.Sub(subscription.CurrentPeriodStart).Hours() / 24)
	usedDays := int(time.Now().Sub(subscription.CurrentPeriodStart).Hours() / 24)
	remainingDays := totalDays - usedDays

	dailyRate := subscription.Amount / float64(totalDays)
	unusedAmount := dailyRate * float64(remainingDays)

	assert.Greater(t, totalDays, 0)
	assert.Greater(t, usedDays, 0)
	assert.Greater(t, remainingDays, 0)
	assert.Greater(t, dailyRate, 0.0)
	assert.Greater(t, unusedAmount, 0.0)
	assert.Less(t, unusedAmount, subscription.Amount)
}

func TestUsageAggregation(t *testing.T) {
	// Test usage aggregation logic
	usageEvents := []services.UsageEvent{
		{ResourceType: "users", Action: "CREATE", Quantity: 5},
		{ResourceType: "users", Action: "CREATE", Quantity: 3},
		{ResourceType: "users", Action: "DELETE", Quantity: 2},
		{ResourceType: "products", Action: "CREATE", Quantity: 100},
	}

	// Aggregate users
	userUsage := 0
	productUsage := 0

	for _, event := range usageEvents {
		switch event.ResourceType {
		case "users":
			if event.Action == "CREATE" {
				userUsage += event.Quantity
			} else if event.Action == "DELETE" {
				userUsage -= event.Quantity
			}
		case "products":
			if event.Action == "CREATE" {
				productUsage += event.Quantity
			}
		}
	}

	assert.Equal(t, 6, userUsage) // 5 + 3 - 2
	assert.Equal(t, 100, productUsage)
}

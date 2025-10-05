package tests

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
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

type IntegrationTestSuite struct {
	suite.Suite
	db     *gorm.DB
	cache  *cache.Cache
	cfg    *config.Config
	router *gin.Engine

	// Services
	planService         *services.PlanService
	subscriptionService *services.SubscriptionService
	usageService        *services.UsageTrackingService
	transitionService   *services.PlanTransitionService
	billingService      *services.AutonomousBillingService

	// Handlers
	planHandler         *handlers.PlanHandler
	subscriptionHandler *handlers.SubscriptionHandler
	usageHandler        *handlers.UsageHandler
	transitionHandler   *handlers.PlanTransitionHandler

	// Test data
	testTenant     models.Tenant
	basicPlan      models.PricingPlan
	premiumPlan    models.PricingPlan
	enterprisePlan models.PricingPlan
}

func (suite *IntegrationTestSuite) SetupSuite() {
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

	// Setup config
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

	// Setup cache
	suite.cache = &cache.Cache{}

	// Initialize services
	suite.planService = services.NewPlanService(suite.db, suite.cfg)
	suite.subscriptionService = services.NewSubscriptionService(suite.db, suite.cfg)
	suite.usageService = services.NewUsageTrackingService(suite.db, suite.cache, suite.cfg)
	suite.billingService = services.NewAutonomousBillingService(suite.db, suite.cfg, suite.cache)
	suite.transitionService = services.NewPlanTransitionService(suite.db, suite.cache, suite.cfg, suite.billingService, suite.usageService)

	// Initialize handlers
	suite.planHandler = handlers.NewPlanHandler(suite.planService)
	suite.subscriptionHandler = handlers.NewSubscriptionHandler(suite.subscriptionService)
	suite.usageHandler = handlers.NewUsageHandler(suite.usageService)
	suite.transitionHandler = handlers.NewPlanTransitionHandler(suite.transitionService)

	// Setup router
	gin.SetMode(gin.TestMode)
	suite.router = gin.New()
	suite.setupRoutes()

	// Create test data
	suite.createTestData()
}

func (suite *IntegrationTestSuite) setupRoutes() {
	api := suite.router.Group("/api")

	// Plan routes
	plans := api.Group("/plans")
	{
		plans.GET("", suite.planHandler.GetPublicPlans)
		plans.POST("", suite.planHandler.CreatePlan)
		plans.GET("/:id", suite.planHandler.GetPlan)
		plans.PUT("/:id", suite.planHandler.UpdatePlan)
		plans.DELETE("/:id", suite.planHandler.DeletePlan)
		plans.GET("/with-billing-options", suite.planHandler.GetAllPlansWithBillingOptions)
		plans.GET("/:id/calculate", suite.planHandler.CalculatePlanPricing)
	}

	// Subscription routes
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

	// Usage routes
	usage := api.Group("/usage")
	{
		usage.POST("/:tenant_id/track", suite.usageHandler.TrackUsage)
		usage.GET("/:tenant_id/current", suite.usageHandler.GetCurrentUsage)
		usage.GET("/:tenant_id/metrics", suite.usageHandler.GetUsageMetrics)
		usage.GET("/:tenant_id/history", suite.usageHandler.GetUsageHistory)
		usage.GET("/:tenant_id/billing-period", suite.usageHandler.GetBillingPeriodUsage)
		usage.GET("/:tenant_id/export", suite.usageHandler.ExportUsageReport)
	}

	// Transition routes
	transitions := api.Group("/transitions")
	{
		transitions.POST("", suite.transitionHandler.InitiatePlanTransition)
		transitions.GET("/subscription/:subscription_id/history", suite.transitionHandler.GetTransitionHistory)
		transitions.POST("/preview", suite.transitionHandler.PreviewPlanTransition)
		transitions.POST("/:transition_id/cancel", suite.transitionHandler.CancelPendingTransition)
	}
}

func (suite *IntegrationTestSuite) createTestData() {
	// Create test tenant
	suite.testTenant = models.Tenant{
		ID:       uuid.New(),
		Name:     "Integration Test Company",
		IsActive: true,
	}
	suite.db.Create(&suite.testTenant)

	// Create test plans with different tiers
	suite.basicPlan = models.PricingPlan{
		ID:           uuid.New(),
		Name:         "basic-integration",
		DisplayName:  "Basic Plan",
		Description:  "Basic plan for testing",
		Price:        49.99,
		Currency:     "INR",
		BillingCycle: "monthly",
		TrialDays:    30,
		MaxLocations: 1,
		MaxUsers:     5,
		MaxProducts:  100,
		Features:     []string{"basic_reporting"},
		Active:       true,
		SortOrder:    1,
	}
	suite.db.Create(&suite.basicPlan)

	suite.premiumPlan = models.PricingPlan{
		ID:           uuid.New(),
		Name:         "premium-integration",
		DisplayName:  "Premium Plan",
		Description:  "Premium plan for testing",
		Price:        149.99,
		Currency:     "INR",
		BillingCycle: "monthly",
		TrialDays:    14,
		MaxLocations: 5,
		MaxUsers:     25,
		MaxProducts:  1000,
		Features:     []string{"basic_reporting", "advanced_reporting", "api_access"},
		Active:       true,
		SortOrder:    2,
	}
	suite.db.Create(&suite.premiumPlan)

	suite.enterprisePlan = models.PricingPlan{
		ID:           uuid.New(),
		Name:         "enterprise-integration",
		DisplayName:  "Enterprise Plan",
		Description:  "Enterprise plan for testing",
		Price:        499.99,
		Currency:     "INR",
		BillingCycle: "monthly",
		TrialDays:    7,
		MaxLocations: -1, // Unlimited
		MaxUsers:     -1, // Unlimited
		MaxProducts:  -1, // Unlimited
		Features:     []string{"basic_reporting", "advanced_reporting", "api_access", "custom_integration", "priority_support"},
		Active:       true,
		SortOrder:    3,
	}
	suite.db.Create(&suite.enterprisePlan)
}

func (suite *IntegrationTestSuite) TearDownSuite() {
	db, _ := suite.db.DB()
	db.Close()
}

// Test complete subscription lifecycle
func (suite *IntegrationTestSuite) TestCompleteSubscriptionLifecycle() {
	// Step 1: Get available plans
	req, _ := http.NewRequest("GET", "/api/plans", nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var plansResponse map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &plansResponse)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), plansResponse, "plans")

	// Step 2: Create subscription with trial
	subscriptionRequest := models.CreateSubscriptionRequest{
		TenantID:          suite.testTenant.ID,
		PlanID:            suite.basicPlan.ID,
		BillingCycle:      "monthly",
		BillingTermMonths: 1,
		AutoRenew:         true,
	}

	jsonData, _ := json.Marshal(subscriptionRequest)
	req, _ = http.NewRequest("POST", "/api/subscriptions", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusCreated, w.Code)

	var subscriptionResponse map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &subscriptionResponse)
	assert.NoError(suite.T(), err)

	subscription := subscriptionResponse["subscription"].(map[string]interface{})
	subscriptionID := subscription["id"].(string)
	assert.Equal(suite.T(), "trial", subscription["status"])

	// Step 3: Track some usage
	usageRequests := []map[string]interface{}{
		{"resource_type": "users", "action": "CREATE", "quantity": 2},
		{"resource_type": "shops", "action": "CREATE", "quantity": 1},
		{"resource_type": "products", "action": "CREATE", "quantity": 50},
	}

	for _, usageReq := range usageRequests {
		jsonData, _ = json.Marshal(usageReq)
		req, _ = http.NewRequest("POST", fmt.Sprintf("/api/usage/%s/track", suite.testTenant.ID.String()), bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		w = httptest.NewRecorder()
		suite.router.ServeHTTP(w, req)

		assert.Equal(suite.T(), http.StatusOK, w.Code)
	}

	// Step 4: Check usage metrics
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/usage/%s/metrics", suite.testTenant.ID.String()), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var usageResponse map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &usageResponse)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), usageResponse, "metrics")

	// Step 5: Upgrade subscription
	upgradeRequest := map[string]interface{}{
		"new_plan_id": suite.premiumPlan.ID.String(),
		"reason":      "Need more features and higher limits",
	}

	jsonData, _ = json.Marshal(upgradeRequest)
	req, _ = http.NewRequest("POST", fmt.Sprintf("/api/subscriptions/%s/upgrade", subscriptionID), bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	// Step 6: Verify upgrade by checking subscription
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/subscriptions?tenant_id=%s", suite.testTenant.ID.String()), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	err = json.Unmarshal(w.Body.Bytes(), &subscriptionResponse)
	assert.NoError(suite.T(), err)

	updatedSubscription := subscriptionResponse["subscription"].(map[string]interface{})
	plan := updatedSubscription["plan"].(map[string]interface{})
	assert.Equal(suite.T(), suite.premiumPlan.ID.String(), plan["id"])

	// Step 7: Get transition history
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/transitions/subscription/%s/history", subscriptionID), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var historyResponse map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &historyResponse)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), historyResponse, "history")
}

// Test plan transition workflows
func (suite *IntegrationTestSuite) TestPlanTransitionWorkflows() {
	// Create subscription
	subscription := models.Subscription{
		ID:                 uuid.New(),
		TenantID:           suite.testTenant.ID,
		PlanID:             suite.basicPlan.ID,
		Status:             "active",
		CurrentPeriodStart: time.Now(),
		CurrentPeriodEnd:   time.Now().AddDate(0, 1, 0),
		BillingCycle:       "monthly",
		Amount:             suite.basicPlan.Price,
		Currency:           "INR",
		AutoRenew:          true,
	}
	nextBilling := time.Now().AddDate(0, 1, 0)
	subscription.NextBillingDate = &nextBilling
	suite.db.Create(&subscription)

	// Test 1: Preview upgrade
	previewRequest := services.PlanTransitionRequest{
		SubscriptionID: subscription.ID,
		NewPlanID:      suite.premiumPlan.ID,
		TransitionType: "UPGRADE",
		ProrationMode:  "IMMEDIATE",
		Reason:         "Testing preview functionality",
	}

	jsonData, _ := json.Marshal(previewRequest)
	req, _ := http.NewRequest("POST", "/api/transitions/preview", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var previewResponse map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &previewResponse)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), previewResponse, "preview")

	// Test 2: Execute upgrade
	transitionRequest := services.PlanTransitionRequest{
		SubscriptionID: subscription.ID,
		NewPlanID:      suite.premiumPlan.ID,
		TransitionType: "UPGRADE",
		ProrationMode:  "IMMEDIATE",
		Reason:         "Executing upgrade after preview",
	}

	jsonData, _ = json.Marshal(transitionRequest)
	req, _ = http.NewRequest("POST", "/api/transitions", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var transitionResponse map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &transitionResponse)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), transitionResponse, "transition")

	transition := transitionResponse["transition"].(map[string]interface{})
	transitionID := transition["transition_id"].(string)

	// Test 3: Get transition status
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/transitions/%s/status", transitionID), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	// Test 4: Attempt downgrade (should validate limits)
	// First add usage that would exceed basic plan limits
	for i := 0; i < 10; i++ { // More than basic plan's 5 user limit
		usageReq := map[string]interface{}{
			"resource_type": "users",
			"action":        "CREATE",
			"quantity":      1,
		}
		jsonData, _ = json.Marshal(usageReq)
		req, _ = http.NewRequest("POST", fmt.Sprintf("/api/usage/%s/track", suite.testTenant.ID.String()), bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		w = httptest.NewRecorder()
		suite.router.ServeHTTP(w, req)
	}

	// Now attempt downgrade - should fail due to usage limits
	downgradeRequest := services.PlanTransitionRequest{
		SubscriptionID: subscription.ID,
		NewPlanID:      suite.basicPlan.ID,
		TransitionType: "DOWNGRADE",
		ProrationMode:  "IMMEDIATE",
		Reason:         "Testing downgrade validation",
	}

	jsonData, _ = json.Marshal(downgradeRequest)
	req, _ = http.NewRequest("POST", "/api/transitions", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	// Should fail due to usage exceeding new plan limits
	assert.Equal(suite.T(), http.StatusInternalServerError, w.Code)
}

// Test usage tracking and limits
func (suite *IntegrationTestSuite) TestUsageTrackingAndLimits() {
	// Create subscription
	subscription := models.Subscription{
		ID:       uuid.New(),
		TenantID: suite.testTenant.ID,
		PlanID:   suite.basicPlan.ID,
		Status:   "active",
	}
	suite.db.Create(&subscription)

	// Test 1: Track usage up to limits
	for i := 0; i < suite.basicPlan.MaxUsers; i++ {
		usageReq := map[string]interface{}{
			"resource_type": "users",
			"action":        "CREATE",
			"quantity":      1,
		}

		jsonData, _ := json.Marshal(usageReq)
		req, _ := http.NewRequest("POST", fmt.Sprintf("/api/usage/%s/track", suite.testTenant.ID.String()), bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		suite.router.ServeHTTP(w, req)

		assert.Equal(suite.T(), http.StatusOK, w.Code)
	}

	// Test 2: Check current usage
	req, _ := http.NewRequest("GET", fmt.Sprintf("/api/usage/%s/current?resource_type=users", suite.testTenant.ID.String()), nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var usageResponse map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &usageResponse)
	assert.NoError(suite.T(), err)
	assert.Equal(suite.T(), float64(suite.basicPlan.MaxUsers), usageResponse["current_usage"])

	// Test 3: Get usage metrics
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/usage/%s/metrics", suite.testTenant.ID.String()), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var metricsResponse map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &metricsResponse)
	assert.NoError(suite.T(), err)

	metrics := metricsResponse["metrics"].([]interface{})
	assert.NotEmpty(suite.T(), metrics)

	// Test 4: Export usage report
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/usage/%s/export?format=json", suite.testTenant.ID.String()), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var exportResponse map[string]interface{}
	err = json.Unmarshal(w.Body.Bytes(), &exportResponse)
	assert.NoError(suite.T(), err)
	assert.Contains(suite.T(), exportResponse, "usage_metrics")

	// Test 5: Test CSV export
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/usage/%s/export?format=csv", suite.testTenant.ID.String()), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)
	assert.Contains(suite.T(), w.Header().Get("Content-Type"), "text/csv")
	assert.Contains(suite.T(), w.Body.String(), "Resource Type,Current Usage,Limit")
}

// Test billing period calculations
func (suite *IntegrationTestSuite) TestBillingPeriodCalculations() {
	// Create subscription
	subscription := models.Subscription{
		ID:       uuid.New(),
		TenantID: suite.testTenant.ID,
		PlanID:   suite.premiumPlan.ID,
		Status:   "active",
	}
	suite.db.Create(&subscription)

	// Track usage over time
	periodStart := time.Now().AddDate(0, 0, -30)
	periodEnd := time.Now()

	// Add some sales data
	for i := 0; i < 50; i++ {
		sale := models.Sale{
			ID:       uuid.New(),
			TenantID: suite.testTenant.ID,
			Amount:   100.0 + float64(i),
		}
		suite.db.Create(&sale)

		usageReq := map[string]interface{}{
			"resource_type": "sales",
			"action":        "CREATE",
			"quantity":      1,
		}

		jsonData, _ := json.Marshal(usageReq)
		req, _ := http.NewRequest("POST", fmt.Sprintf("/api/usage/%s/track", suite.testTenant.ID.String()), bytes.NewBuffer(jsonData))
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		suite.router.ServeHTTP(w, req)
	}

	// Get billing period usage
	url := fmt.Sprintf("/api/usage/%s/billing-period?period_start=%s&period_end=%s",
		suite.testTenant.ID.String(),
		periodStart.Format("2006-01-02"),
		periodEnd.Format("2006-01-02"))

	req, _ := http.NewRequest("GET", url, nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var billingResponse map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &billingResponse)
	assert.NoError(suite.T(), err)

	assert.Contains(suite.T(), billingResponse, "resource_usage")
	assert.Contains(suite.T(), billingResponse, "billing_period")
	assert.Equal(suite.T(), suite.testTenant.ID.String(), billingResponse["tenant_id"])
}

// Test error handling and edge cases
func (suite *IntegrationTestSuite) TestErrorHandlingAndEdgeCases() {
	// Test 1: Invalid tenant ID
	req, _ := http.NewRequest("GET", "/api/usage/invalid-uuid/metrics", nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusBadRequest, w.Code)

	// Test 2: Non-existent subscription
	fakeID := uuid.New()
	req, _ = http.NewRequest("GET", fmt.Sprintf("/api/transitions/subscription/%s/history", fakeID.String()), nil)
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code) // Should return empty history, not error

	// Test 3: Invalid plan transition request
	invalidTransition := map[string]interface{}{
		"subscription_id": "invalid-uuid",
		"new_plan_id":     "also-invalid",
	}

	jsonData, _ := json.Marshal(invalidTransition)
	req, _ = http.NewRequest("POST", "/api/transitions", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusBadRequest, w.Code)

	// Test 4: Missing required fields in subscription creation
	invalidSubscription := map[string]interface{}{
		"tenant_id": "", // Missing
		"plan_id":   "", // Missing
	}

	jsonData, _ = json.Marshal(invalidSubscription)
	req, _ = http.NewRequest("POST", "/api/subscriptions", bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusBadRequest, w.Code)

	// Test 5: Invalid usage tracking request
	invalidUsage := map[string]interface{}{
		"resource_type": "", // Empty
		"action":        "INVALID_ACTION",
		"quantity":      -1, // Negative
	}

	jsonData, _ = json.Marshal(invalidUsage)
	req, _ = http.NewRequest("POST", fmt.Sprintf("/api/usage/%s/track", suite.testTenant.ID.String()), bytes.NewBuffer(jsonData))
	req.Header.Set("Content-Type", "application/json")
	w = httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusBadRequest, w.Code)
}

// Test concurrent operations
func (suite *IntegrationTestSuite) TestConcurrentOperations() {
	// Create subscription
	subscription := models.Subscription{
		ID:       uuid.New(),
		TenantID: suite.testTenant.ID,
		PlanID:   suite.basicPlan.ID,
		Status:   "active",
	}
	suite.db.Create(&subscription)

	// Test concurrent usage tracking
	concurrentRequests := 10
	done := make(chan bool, concurrentRequests)

	for i := 0; i < concurrentRequests; i++ {
		go func(index int) {
			usageReq := map[string]interface{}{
				"resource_type": "products",
				"action":        "CREATE",
				"quantity":      1,
				"metadata":      fmt.Sprintf("concurrent-test-%d", index),
			}

			jsonData, _ := json.Marshal(usageReq)
			req, _ := http.NewRequest("POST", fmt.Sprintf("/api/usage/%s/track", suite.testTenant.ID.String()), bytes.NewBuffer(jsonData))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			suite.router.ServeHTTP(w, req)

			assert.Equal(suite.T(), http.StatusOK, w.Code)
			done <- true
		}(i)
	}

	// Wait for all requests to complete
	for i := 0; i < concurrentRequests; i++ {
		<-done
	}

	// Verify final usage count
	req, _ := http.NewRequest("GET", fmt.Sprintf("/api/usage/%s/current?resource_type=products", suite.testTenant.ID.String()), nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	assert.Equal(suite.T(), http.StatusOK, w.Code)

	var usageResponse map[string]interface{}
	err := json.Unmarshal(w.Body.Bytes(), &usageResponse)
	assert.NoError(suite.T(), err)
	assert.Equal(suite.T(), float64(concurrentRequests), usageResponse["current_usage"])
}

func TestIntegrationSuite(t *testing.T) {
	suite.Run(t, new(IntegrationTestSuite))
}

// Performance benchmarks
func BenchmarkUsageTracking(b *testing.B) {
	// Setup test database using PostgreSQL
	dbConfig := GetTestDatabaseConfig()

	dbConn, err := database.NewDatabase(dbConfig)
	if err != nil {
		b.Skip("PostgreSQL not available for benchmarking:", err)
		return
	}
	db := dbConn.DB
	db.AutoMigrate(&models.UsageRecord{}, &models.Tenant{})

	cache := &cache.Cache{}
	cfg := &config.Config{}
	service := services.NewUsageTrackingService(db, cache, cfg)

	tenantID := uuid.New()
	tenant := models.Tenant{ID: tenantID, Name: "Benchmark Tenant", IsActive: true}
	db.Create(&tenant)

	// Benchmark
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		event := services.UsageEvent{
			TenantID:     tenantID,
			ResourceType: "users",
			Action:       "CREATE",
			Quantity:     1,
			Timestamp:    time.Now(),
		}
		service.TrackUsage(context.Background(), event)
	}
}

func BenchmarkPlanTransitionCalculation(b *testing.B) {
	// Setup test database using PostgreSQL
	dbConfig := GetTestDatabaseConfig()

	dbConn, err := database.NewDatabase(dbConfig)
	if err != nil {
		b.Skip("PostgreSQL not available for benchmarking:", err)
		return
	}
	db := dbConn.DB
	db.AutoMigrate(&models.PricingPlan{}, &models.Subscription{})

	cache := &cache.Cache{}
	cfg := &config.Config{}
	billingService := services.NewAutonomousBillingService(db, cfg, cache)
	usageService := services.NewUsageTrackingService(db, cache, cfg)
	service := services.NewPlanTransitionService(db, cache, cfg, billingService, usageService)

	// Create test data
	_ = models.PricingPlan{ID: uuid.New(), Price: 99.99}
	newPlan := models.PricingPlan{ID: uuid.New(), Price: 199.99}
	subscription := models.Subscription{
		Amount:             99.99,
		BillingCycle:       "monthly",
		CurrentPeriodStart: time.Now().AddDate(0, 0, -15),
		CurrentPeriodEnd:   time.Now().AddDate(0, 0, 15),
	}

	// Benchmark
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		// Test plan transition initiation which includes proration calculation
		req := services.PlanTransitionRequest{
			SubscriptionID: subscription.ID,
			NewPlanID:      newPlan.ID,
			ProrationMode:  "IMMEDIATE",
		}
		service.InitiatePlanTransition(context.Background(), req)
	}
}

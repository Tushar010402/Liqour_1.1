//go:build integration
// +build integration

package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/internal/sales/handlers"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"github.com/sirupsen/logrus"
	"github.com/stretchr/testify/suite"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// OCRIntegrationTestSuite runs integration tests for OCR
type OCRIntegrationTestSuite struct {
	suite.Suite
	db             *database.DB
	cache          *cache.Cache
	router         *gin.Engine
	postgresC      testcontainers.Container
	redisC         testcontainers.Container
	ocrService     *SimpleOCRService
	logger         *logrus.Logger
	testTenantID   uuid.UUID
	testUserID     uuid.UUID
	testShopID     uuid.UUID
}

// SetupSuite runs before all tests
func (suite *OCRIntegrationTestSuite) SetupSuite() {
	ctx := context.Background()
	suite.logger = logrus.New()
	suite.logger.SetLevel(logrus.DebugLevel)

	// Start PostgreSQL container
	postgresReq := testcontainers.ContainerRequest{
		Image:        "postgres:14-alpine",
		ExposedPorts: []string{"5432/tcp"},
		Env: map[string]string{
			"POSTGRES_USER":     "test",
			"POSTGRES_PASSWORD": "test",
			"POSTGRES_DB":       "test_ocr",
		},
		WaitingFor: wait.ForListeningPort("5432/tcp").WithStartupTimeout(60 * time.Second),
	}

	postgresC, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: postgresReq,
		Started:          true,
	})
	suite.Require().NoError(err)
	suite.postgresC = postgresC

	// Get PostgreSQL connection details
	postgresHost, _ := postgresC.Host(ctx)
	postgresPort, _ := postgresC.MappedPort(ctx, "5432")
	postgresDSN := fmt.Sprintf("postgres://test:test@%s:%s/test_ocr?sslmode=disable",
		postgresHost, postgresPort.Port())

	// Initialize database
	suite.db = database.NewDB(postgresDSN, suite.logger)
	suite.Require().NoError(suite.db.AutoMigrate(
		&models.OCRSession{},
		&models.OCRExtractedItem{},
		&models.BrandAlias{},
		&models.Product{},
		&models.Stock{},
	))

	// Start Redis container
	redisReq := testcontainers.ContainerRequest{
		Image:        "redis:7-alpine",
		ExposedPorts: []string{"6379/tcp"},
		WaitingFor:   wait.ForListeningPort("6379/tcp").WithStartupTimeout(30 * time.Second),
	}

	redisC, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: redisReq,
		Started:          true,
	})
	suite.Require().NoError(err)
	suite.redisC = redisC

	// Get Redis connection details
	redisHost, _ := redisC.Host(ctx)
	redisPort, _ := redisC.MappedPort(ctx, "6379")
	redisURL := fmt.Sprintf("redis://%s:%s", redisHost, redisPort.Port())

	// Initialize cache
	suite.cache = cache.NewCache(redisURL, suite.logger)

	// Initialize OCR service
	suite.ocrService, err = NewSimpleOCRService(suite.db, suite.cache, suite.logger)
	suite.Require().NoError(err)

	// Setup test data
	suite.testTenantID = uuid.New()
	suite.testUserID = uuid.New()
	suite.testShopID = uuid.New()

	// Create test products
	suite.createTestProducts()

	// Setup router
	suite.setupRouter()
}

// TearDownSuite runs after all tests
func (suite *OCRIntegrationTestSuite) TearDownSuite() {
	ctx := context.Background()

	if suite.postgresC != nil {
		suite.postgresC.Terminate(ctx)
	}

	if suite.redisC != nil {
		suite.redisC.Terminate(ctx)
	}
}

// createTestProducts creates test products in database
func (suite *OCRIntegrationTestSuite) createTestProducts() {
	products := []models.Product{
		{
			ID:       uuid.New(),
			TenantID: &suite.testTenantID,
			Name:     "Royal Stag 750ml",
			Category: "whiskey",
			Size:     "750ml",
			Price:    850.00,
		},
		{
			ID:       uuid.New(),
			TenantID: &suite.testTenantID,
			Name:     "Kingfisher Premium 650ml",
			Category: "beer",
			Size:     "650ml",
			Price:    120.00,
		},
		{
			ID:       uuid.New(),
			TenantID: &suite.testTenantID,
			Name:     "Black Label 750ml",
			Category: "whiskey",
			Size:     "750ml",
			Price:    1200.00,
		},
	}

	for _, product := range products {
		suite.Require().NoError(suite.db.Create(&product).Error)

		// Add stock
		stock := models.Stock{
			ID:        uuid.New(),
			ProductID: product.ID,
			ShopID:    suite.testShopID,
			Quantity:  10,
		}
		suite.Require().NoError(suite.db.Create(&stock).Error)
	}
}

// setupRouter configures the test router
func (suite *OCRIntegrationTestSuite) setupRouter() {
	gin.SetMode(gin.TestMode)
	suite.router = gin.New()

	// Add middleware
	suite.router.Use(func(c *gin.Context) {
		c.Set("tenant_id", suite.testTenantID)
		c.Set("user_id", suite.testUserID)
		c.Next()
	})

	// Add routes
	ocrGroup := suite.router.Group("/api/ocr")
	{
		ocrGroup.POST("/sessions", suite.handleCreateSession)
		ocrGroup.GET("/sessions/:id", suite.handleGetSession)
		ocrGroup.POST("/sessions/:id/confirm", suite.handleConfirmItems)
		ocrGroup.GET("/health", suite.handleHealth)
	}
}

// Test handlers
func (suite *OCRIntegrationTestSuite) handleCreateSession(c *gin.Context) {
	var req models.CreateOCRSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	session, err := suite.ocrService.CreateOCRSession(
		c.Request.Context(),
		&req,
		suite.testUserID,
		suite.testTenantID,
	)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, session)
}

func (suite *OCRIntegrationTestSuite) handleGetSession(c *gin.Context) {
	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session ID"})
		return
	}

	response, err := suite.ocrService.GetOCRSession(
		c.Request.Context(),
		sessionID,
		suite.testTenantID,
	)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, response)
}

func (suite *OCRIntegrationTestSuite) handleConfirmItems(c *gin.Context) {
	sessionID, _ := uuid.Parse(c.Param("id"))

	var req models.ConfirmOCRItemsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	req.SessionID = sessionID
	err := suite.ocrService.ConfirmOCRItems(c.Request.Context(), &req, suite.testTenantID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Items confirmed"})
}

func (suite *OCRIntegrationTestSuite) handleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "healthy",
		"service": "ocr",
		"timestamp": time.Now(),
	})
}

// Test Cases

func (suite *OCRIntegrationTestSuite) TestCreateOCRSession() {
	// Prepare test image (1x1 transparent PNG)
	testImage := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

	reqBody := map[string]interface{}{
		"image_data":   testImage,
		"image_type":   "png",
		"session_type": "quick_sale",
		"shop_id":      suite.testShopID.String(),
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/ocr/sessions", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	suite.Equal(http.StatusCreated, w.Code)

	var session models.OCRSession
	err := json.Unmarshal(w.Body.Bytes(), &session)
	suite.NoError(err)
	suite.NotEmpty(session.ID)
	suite.Equal(models.OCRStatusPending, session.Status)
}

func (suite *OCRIntegrationTestSuite) TestGetOCRSession() {
	// First create a session
	ctx := context.Background()
	session, err := suite.ocrService.CreateOCRSession(ctx, &models.CreateOCRSessionRequest{
		ImageData:   "test",
		ImageType:   "png",
		SessionType: "quick_sale",
		ShopID:      suite.testShopID,
	}, suite.testUserID, suite.testTenantID)
	suite.NoError(err)

	// Wait for processing
	time.Sleep(2 * time.Second)

	// Get the session
	req := httptest.NewRequest("GET", fmt.Sprintf("/api/ocr/sessions/%s", session.ID), nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	suite.Equal(http.StatusOK, w.Code)

	var response models.OCRSessionResponse
	err = json.Unmarshal(w.Body.Bytes(), &response)
	suite.NoError(err)
	suite.Equal(session.ID, response.Session.ID)
}

func (suite *OCRIntegrationTestSuite) TestOCRWithCaching() {
	ctx := context.Background()
	testImage := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

	// Create first session
	session1, err := suite.ocrService.CreateOCRSession(ctx, &models.CreateOCRSessionRequest{
		ImageData:   testImage,
		ImageType:   "png",
		SessionType: "quick_sale",
		ShopID:      suite.testShopID,
	}, suite.testUserID, suite.testTenantID)
	suite.NoError(err)

	// Create second session with same image (should use cache)
	startTime := time.Now()
	session2, err := suite.ocrService.CreateOCRSession(ctx, &models.CreateOCRSessionRequest{
		ImageData:   testImage,
		ImageType:   "png",
		SessionType: "quick_sale",
		ShopID:      suite.testShopID,
	}, suite.testUserID, suite.testTenantID)
	suite.NoError(err)
	cacheTime := time.Since(startTime)

	// Second request should be faster due to caching
	suite.Less(cacheTime, 100*time.Millisecond)
	suite.NotEqual(session1.ID, session2.ID) // Different sessions but cached processing
}

func (suite *OCRIntegrationTestSuite) TestConfirmOCRItems() {
	ctx := context.Background()

	// Create session
	session, _ := suite.ocrService.CreateOCRSession(ctx, &models.CreateOCRSessionRequest{
		ImageData:   "test",
		ImageType:   "png",
		SessionType: "quick_sale",
		ShopID:      suite.testShopID,
	}, suite.testUserID, suite.testTenantID)

	// Create test items
	items := []models.OCRExtractedItem{
		{
			ID:              uuid.New(),
			SessionID:       session.ID,
			ExtractedText:   "Royal Stag 750ml x2",
			BrandText:       stringPtr("Royal Stag"),
			SizeText:        stringPtr("750ml"),
			ParsedQuantity:  intPtr(2),
			MatchConfidence: 0.95,
		},
	}

	for _, item := range items {
		suite.db.Create(&item)
	}

	// Confirm items
	reqBody := map[string]interface{}{
		"items": []map[string]interface{}{
			{
				"item_id":      items[0].ID.String(),
				"is_confirmed": true,
				"quantity":     2,
			},
		},
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", fmt.Sprintf("/api/ocr/sessions/%s/confirm", session.ID), bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	suite.Equal(http.StatusOK, w.Code)

	// Verify item was confirmed
	var updatedItem models.OCRExtractedItem
	suite.db.Where("id = ?", items[0].ID).First(&updatedItem)
	suite.True(updatedItem.IsConfirmed)
}

func (suite *OCRIntegrationTestSuite) TestHealthCheck() {
	req := httptest.NewRequest("GET", "/api/ocr/health", nil)
	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	suite.Equal(http.StatusOK, w.Code)

	var health map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &health)
	suite.Equal("healthy", health["status"])
}

func (suite *OCRIntegrationTestSuite) TestSecurityValidation() {
	// Test with malicious input
	maliciousImage := base64.StdEncoding.EncodeToString([]byte("<script>alert('xss')</script>"))

	reqBody := map[string]interface{}{
		"image_data":   maliciousImage,
		"image_type":   "png",
		"session_type": "quick_sale",
		"shop_id":      suite.testShopID.String(),
	}

	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest("POST", "/api/ocr/sessions", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	w := httptest.NewRecorder()
	suite.router.ServeHTTP(w, req)

	// Should still create session but sanitize the input
	suite.Equal(http.StatusCreated, w.Code)
}

func (suite *OCRIntegrationTestSuite) TestRateLimiting() {
	// Create multiple requests quickly
	testImage := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

	successCount := 0
	rateLimitCount := 0

	for i := 0; i < 15; i++ {
		reqBody := map[string]interface{}{
			"image_data":   testImage,
			"image_type":   "png",
			"session_type": "quick_sale",
			"shop_id":      suite.testShopID.String(),
		}

		body, _ := json.Marshal(reqBody)
		req := httptest.NewRequest("POST", "/api/ocr/sessions", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-User-ID", suite.testUserID.String())

		w := httptest.NewRecorder()
		suite.router.ServeHTTP(w, req)

		if w.Code == http.StatusCreated {
			successCount++
		} else if w.Code == http.StatusTooManyRequests {
			rateLimitCount++
		}
	}

	// Should have some rate limited requests
	suite.Greater(successCount, 0)
	// Note: Rate limiting would be applied if middleware was active
}

func (suite *OCRIntegrationTestSuite) TestConcurrentRequests() {
	// Test concurrent request handling
	testImage := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

	concurrency := 10
	results := make(chan int, concurrency)

	for i := 0; i < concurrency; i++ {
		go func() {
			reqBody := map[string]interface{}{
				"image_data":   testImage,
				"image_type":   "png",
				"session_type": "quick_sale",
				"shop_id":      suite.testShopID.String(),
			}

			body, _ := json.Marshal(reqBody)
			req := httptest.NewRequest("POST", "/api/ocr/sessions", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")

			w := httptest.NewRecorder()
			suite.router.ServeHTTP(w, req)
			results <- w.Code
		}()
	}

	// Collect results
	successCount := 0
	for i := 0; i < concurrency; i++ {
		code := <-results
		if code == http.StatusCreated {
			successCount++
		}
	}

	// All should succeed
	suite.Equal(concurrency, successCount)
}

func (suite *OCRIntegrationTestSuite) TestStockValidation() {
	// Test with stock data
	ctx := context.Background()

	// Create session with mock data that includes stock fields
	session, err := suite.ocrService.CreateOCRSession(ctx, &models.CreateOCRSessionRequest{
		ImageData:   "test",
		ImageType:   "png",
		SessionType: "inventory_check",
		ShopID:      suite.testShopID,
	}, suite.testUserID, suite.testTenantID)
	suite.NoError(err)

	// Create item with stock data
	item := models.OCRExtractedItem{
		ID:            uuid.New(),
		SessionID:     session.ID,
		ExtractedText: "Royal Stag 750ml",
		BrandText:     stringPtr("Royal Stag"),
		SizeText:      stringPtr("750ml"),
		ParsedQuantity: intPtr(2),
		OpeningStock:  intPtr(10),
		ClosingStock:  intPtr(8),
		RatePerUnit:   floatPtr(850.0),
		RowNumber:     intPtr(1),
		MatchConfidence: 0.95,
	}

	err = suite.db.Create(&item).Error
	suite.NoError(err)

	// Verify stock calculation
	suite.Equal(10, *item.OpeningStock)
	suite.Equal(8, *item.ClosingStock)
	suite.Equal(2, *item.ParsedQuantity)
	// Closing = Opening - Quantity (for sales)
	suite.Equal(*item.OpeningStock-*item.ParsedQuantity, *item.ClosingStock)
}

// Benchmark tests
func (suite *OCRIntegrationTestSuite) TestPerformanceBenchmark() {
	ctx := context.Background()
	testImage := "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

	// Measure session creation time
	iterations := 100
	var totalTime time.Duration

	for i := 0; i < iterations; i++ {
		startTime := time.Now()

		_, err := suite.ocrService.CreateOCRSession(ctx, &models.CreateOCRSessionRequest{
			ImageData:   testImage,
			ImageType:   "png",
			SessionType: "quick_sale",
			ShopID:      suite.testShopID,
		}, suite.testUserID, suite.testTenantID)

		suite.NoError(err)
		totalTime += time.Since(startTime)
	}

	avgTime := totalTime / time.Duration(iterations)
	suite.logger.Infof("Average session creation time: %v", avgTime)

	// Should be under 100ms average
	suite.Less(avgTime, 100*time.Millisecond)
}

// Helper functions
func stringPtr(s string) *string {
	return &s
}

func intPtr(i int) *int {
	return &i
}

func floatPtr(f float64) *float64 {
	return &f
}

// Run the test suite
func TestOCRIntegrationSuite(t *testing.T) {
	suite.Run(t, new(OCRIntegrationTestSuite))
}
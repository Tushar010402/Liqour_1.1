package integration

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/suite"
)

// IntegrationTestSuite holds the integration test suite
type IntegrationTestSuite struct {
	suite.Suite
	baseURL     string
	adminToken  string
	userToken   string
	tenantID    string
	client      *http.Client
}

// SetupSuite runs once before all tests
func (suite *IntegrationTestSuite) SetupSuite() {
	suite.baseURL = getEnvOrDefault("API_BASE_URL", "http://localhost:8090")
	suite.client = &http.Client{Timeout: 30 * time.Second}
	
	// Wait for services to be ready
	suite.waitForServices()
	
	// Create test users and get tokens
	suite.setupTestUsers()
}

// TearDownSuite runs once after all tests
func (suite *IntegrationTestSuite) TearDownSuite() {
	// Cleanup test data if needed
	suite.cleanupTestData()
}

// waitForServices waits for all services to be healthy
func (suite *IntegrationTestSuite) waitForServices() {
	services := []string{
		"/gateway/health",
		"/api/auth/health", 
		"/api/inventory/health",
		"/api/sales/health",
		"/api/finance/health",
	}
	
	maxAttempts := 30
	for _, endpoint := range services {
		for i := 0; i < maxAttempts; i++ {
			resp, err := suite.client.Get(suite.baseURL + endpoint)
			if err == nil && resp.StatusCode == 200 {
				resp.Body.Close()
				break
			}
			if resp != nil {
				resp.Body.Close()
			}
			time.Sleep(2 * time.Second)
		}
	}
}

// setupTestUsers creates test users and obtains tokens
func (suite *IntegrationTestSuite) setupTestUsers() {
	// Create admin user
	adminPayload := map[string]interface{}{
		"username":     "integration_admin",
		"email":        "admin@integration.test",
		"password":     "IntegrationTest123!",
		"first_name":   "Integration",
		"last_name":    "Admin",
		"role":         "admin",
		"company_name": "Integration Test Co",
		"tenant_name":  "Integration Test Tenant",
	}
	
	adminResp := suite.makeRequest("POST", "/api/auth/register", adminPayload, "")
	suite.Equal(200, adminResp.StatusCode)
	
	var adminResult map[string]interface{}
	json.NewDecoder(adminResp.Body).Decode(&adminResult)
	adminResp.Body.Close()
	
	suite.adminToken = adminResult["token"].(string)
	suite.tenantID = adminResult["tenant"].(map[string]interface{})["id"].(string)
	
	// Create regular user
	userPayload := map[string]interface{}{
		"username":   "integration_user",
		"email":      "user@integration.test",
		"password":   "IntegrationTest123!",
		"first_name": "Integration",
		"last_name":  "User",
		"role":       "user",
	}
	
	userResp := suite.makeRequest("POST", "/api/admin/users", userPayload, suite.adminToken)
	suite.Equal(200, userResp.StatusCode)
	userResp.Body.Close()
	
	// Login as regular user to get token
	loginPayload := map[string]interface{}{
		"username": "integration_user",
		"password": "IntegrationTest123!",
	}
	
	loginResp := suite.makeRequest("POST", "/api/auth/login", loginPayload, "")
	suite.Equal(200, loginResp.StatusCode)
	
	var loginResult map[string]interface{}
	json.NewDecoder(loginResp.Body).Decode(&loginResult)
	loginResp.Body.Close()
	
	suite.userToken = loginResult["token"].(string)
}

// Test Authentication Flow
func (suite *IntegrationTestSuite) TestAuthenticationFlow() {
	suite.Run("Registration", func() {
		payload := map[string]interface{}{
			"username":     "test_reg_user",
			"email":        "test@registration.test",
			"password":     "TestPassword123!",
			"first_name":   "Test",
			"last_name":    "User",
			"role":         "admin",
			"company_name": "Test Company",
			"tenant_name":  "Test Tenant",
		}
		
		resp := suite.makeRequest("POST", "/api/auth/register", payload, "")
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		suite.NotEmpty(result["token"])
		suite.NotEmpty(result["user"])
		suite.NotEmpty(result["tenant"])
	})
	
	suite.Run("Login", func() {
		payload := map[string]interface{}{
			"username": "integration_admin",
			"password": "IntegrationTest123!",
		}
		
		resp := suite.makeRequest("POST", "/api/auth/login", payload, "")
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		suite.NotEmpty(result["token"])
	})
	
	suite.Run("Profile Access", func() {
		resp := suite.makeRequest("GET", "/api/auth/profile", nil, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		suite.Equal("integration_admin", result["username"])
	})
	
	suite.Run("Unauthorized Access", func() {
		resp := suite.makeRequest("GET", "/api/auth/profile", nil, "")
		suite.Equal(401, resp.StatusCode)
		resp.Body.Close()
	})
}

// Test Inventory Management
func (suite *IntegrationTestSuite) TestInventoryManagement() {
	var brandID, categoryID, productID string
	
	suite.Run("Create Brand", func() {
		payload := map[string]interface{}{
			"name":        "Integration Test Brand",
			"description": "Brand for integration testing",
		}
		
		resp := suite.makeRequest("POST", "/api/inventory/brands", payload, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		brandID = result["id"].(string)
		suite.NotEmpty(brandID)
		suite.Equal("Integration Test Brand", result["name"])
	})
	
	suite.Run("Create Category", func() {
		payload := map[string]interface{}{
			"name":        "Integration Test Category",
			"description": "Category for integration testing",
		}
		
		resp := suite.makeRequest("POST", "/api/inventory/categories", payload, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		categoryID = result["id"].(string)
		suite.NotEmpty(categoryID)
		suite.Equal("Integration Test Category", result["name"])
	})
	
	suite.Run("Create Product", func() {
		payload := map[string]interface{}{
			"name":          "Integration Test Product",
			"sku":           "ITP-001",
			"brand_id":      brandID,
			"category_id":   categoryID,
			"size":          "750ml",
			"selling_price": 100.00,
			"mrp":           120.00,
			"cost_price":    80.00,
			"description":   "Product for integration testing",
		}
		
		resp := suite.makeRequest("POST", "/api/inventory/products", payload, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		productID = result["id"].(string)
		suite.NotEmpty(productID)
		suite.Equal("Integration Test Product", result["name"])
	})
	
	suite.Run("List Products", func() {
		resp := suite.makeRequest("GET", "/api/inventory/products", nil, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		products := result["products"].([]interface{})
		suite.NotEmpty(products)
		
		// Find our test product
		found := false
		for _, p := range products {
			product := p.(map[string]interface{})
			if product["id"].(string) == productID {
				found = true
				suite.Equal("Integration Test Product", product["name"])
				break
			}
		}
		suite.True(found, "Test product should be in the list")
	})
}

// Test Multi-Tenant Isolation
func (suite *IntegrationTestSuite) TestMultiTenantIsolation() {
	// Create second tenant
	secondTenantPayload := map[string]interface{}{
		"username":     "second_tenant_admin",
		"email":        "admin@second.tenant",
		"password":     "SecondTenant123!",
		"first_name":   "Second",
		"last_name":    "Admin",
		"role":         "admin",
		"company_name": "Second Tenant Co",
		"tenant_name":  "Second Tenant",
	}
	
	secondTenantResp := suite.makeRequest("POST", "/api/auth/register", secondTenantPayload, "")
	suite.Equal(200, secondTenantResp.StatusCode)
	
	var secondTenantResult map[string]interface{}
	json.NewDecoder(secondTenantResp.Body).Decode(&secondTenantResult)
	secondTenantResp.Body.Close()
	
	secondTenantToken := secondTenantResult["token"].(string)
	
	suite.Run("First Tenant Creates Brand", func() {
		payload := map[string]interface{}{
			"name":        "Tenant 1 Brand",
			"description": "Brand for first tenant",
		}
		
		resp := suite.makeRequest("POST", "/api/inventory/brands", payload, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		resp.Body.Close()
	})
	
	suite.Run("Second Tenant Cannot See First Tenant's Brand", func() {
		resp := suite.makeRequest("GET", "/api/inventory/brands", nil, secondTenantToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		brands := result["brands"]
		if brands != nil {
			brandsList := brands.([]interface{})
			for _, b := range brandsList {
				brand := b.(map[string]interface{})
				suite.NotEqual("Tenant 1 Brand", brand["name"], "Second tenant should not see first tenant's brand")
			}
		}
	})
	
	suite.Run("Second Tenant Creates Own Brand", func() {
		payload := map[string]interface{}{
			"name":        "Tenant 2 Brand",
			"description": "Brand for second tenant",
		}
		
		resp := suite.makeRequest("POST", "/api/inventory/brands", payload, secondTenantToken)
		suite.Equal(200, resp.StatusCode)
		resp.Body.Close()
	})
	
	suite.Run("First Tenant Cannot See Second Tenant's Brand", func() {
		resp := suite.makeRequest("GET", "/api/inventory/brands", nil, suite.adminToken)
		suite.Equal(200, resp.StatusCode)
		
		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		resp.Body.Close()
		
		brands := result["brands"].([]interface{})
		for _, b := range brands {
			brand := b.(map[string]interface{})
			suite.NotEqual("Tenant 2 Brand", brand["name"], "First tenant should not see second tenant's brand")
		}
	})
}

// Test Error Handling
func (suite *IntegrationTestSuite) TestErrorHandling() {
	suite.Run("Invalid JSON", func() {
		resp, err := suite.client.Post(suite.baseURL+"/api/inventory/brands", "application/json", bytes.NewBufferString("invalid json"))
		suite.NoError(err)
		suite.Equal(400, resp.StatusCode)
		resp.Body.Close()
	})
	
	suite.Run("Missing Required Fields", func() {
		payload := map[string]interface{}{
			"description": "Brand without name",
		}
		
		resp := suite.makeRequest("POST", "/api/inventory/brands", payload, suite.adminToken)
		suite.Equal(400, resp.StatusCode)
		resp.Body.Close()
	})
	
	suite.Run("Invalid UUID", func() {
		resp := suite.makeRequest("GET", "/api/inventory/products/invalid-uuid", nil, suite.adminToken)
		suite.Equal(400, resp.StatusCode)
		resp.Body.Close()
	})
	
	suite.Run("Duplicate Brand Name", func() {
		// Create first brand
		payload := map[string]interface{}{
			"name":        "Duplicate Test Brand",
			"description": "First brand",
		}
		
		resp1 := suite.makeRequest("POST", "/api/inventory/brands", payload, suite.adminToken)
		suite.Equal(200, resp1.StatusCode)
		resp1.Body.Close()
		
		// Try to create duplicate
		resp2 := suite.makeRequest("POST", "/api/inventory/brands", payload, suite.adminToken)
		suite.Equal(409, resp2.StatusCode)
		resp2.Body.Close()
	})
}

// Test Performance
func (suite *IntegrationTestSuite) TestPerformance() {
	suite.Run("Response Time", func() {
		start := time.Now()
		resp := suite.makeRequest("GET", "/api/inventory/brands", nil, suite.adminToken)
		duration := time.Since(start)
		
		suite.Equal(200, resp.StatusCode)
		resp.Body.Close()
		
		// Response should be under 1 second for simple operations
		suite.Less(duration, 1*time.Second, "Response time should be under 1 second")
	})
	
	suite.Run("Concurrent Requests", func() {
		concurrency := 10
		done := make(chan bool, concurrency)
		errors := make(chan error, concurrency)
		
		for i := 0; i < concurrency; i++ {
			go func() {
				defer func() { done <- true }()
				
				resp := suite.makeRequest("GET", "/api/inventory/brands", nil, suite.adminToken)
				if resp.StatusCode != 200 {
					errors <- fmt.Errorf("Expected 200, got %d", resp.StatusCode)
				}
				resp.Body.Close()
			}()
		}
		
		// Wait for all requests to complete
		for i := 0; i < concurrency; i++ {
			select {
			case <-done:
				// Request completed
			case err := <-errors:
				suite.Fail("Concurrent request failed", err.Error())
			case <-time.After(10 * time.Second):
				suite.Fail("Concurrent request timed out")
			}
		}
	})
}

// Helper methods

func (suite *IntegrationTestSuite) makeRequest(method, endpoint string, payload interface{}, token string) *http.Response {
	var body *bytes.Buffer
	if payload != nil {
		jsonData, _ := json.Marshal(payload)
		body = bytes.NewBuffer(jsonData)
	} else {
		body = bytes.NewBuffer([]byte{})
	}
	
	req, err := http.NewRequest(method, suite.baseURL+endpoint, body)
	suite.NoError(err)
	
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	
	resp, err := suite.client.Do(req)
	suite.NoError(err)
	
	return resp
}

func (suite *IntegrationTestSuite) cleanupTestData() {
	// Add cleanup logic here if needed
}

func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// TestIntegrationSuite runs the integration test suite
func TestIntegrationSuite(t *testing.T) {
	suite.Run(t, new(IntegrationTestSuite))
}
package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

type FrontendService struct {
	db     *database.DB
	cache  *cache.Cache
	config *config.Config
}

func NewFrontendService(db *database.DB, cache *cache.Cache, cfg *config.Config) *FrontendService {
	return &FrontendService{
		db:     db,
		cache:  cache,
		config: cfg,
	}
}

// API Client for communicating with microservices
func (s *FrontendService) makeAPIRequest(ctx context.Context, method, serviceURL, endpoint string, body interface{}, token string) (*http.Response, error) {
	var reqBody *bytes.Buffer
	if body != nil {
		jsonData, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal request body: %w", err)
		}
		reqBody = bytes.NewBuffer(jsonData)
	} else {
		reqBody = bytes.NewBuffer(nil)
	}

	url := fmt.Sprintf("%s%s", serviceURL, endpoint)
	req, err := http.NewRequestWithContext(ctx, method, url, reqBody)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))
	}

	client := &http.Client{
		Timeout: 30 * time.Second,
	}

	return client.Do(req)
}

// Auth service methods
func (s *FrontendService) Login(ctx context.Context, email, password string) (map[string]interface{}, error) {
	loginData := map[string]string{
		"email":    email,
		"password": password,
	}

	resp, err := s.makeAPIRequest(ctx, "POST", s.config.Services.Auth.URL, "/api/auth/login", loginData, "")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("login failed: %s", result["error"])
	}

	return result, nil
}

func (s *FrontendService) GetCurrentUser(ctx context.Context, token string) (map[string]interface{}, error) {
	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Auth.URL, "/api/auth/me", nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("failed to get user: %s", result["error"])
	}

	return result, nil
}

// Sales service methods
func (s *FrontendService) GetDailySalesRecords(ctx context.Context, token string, params map[string]string) (map[string]interface{}, error) {
	endpoint := "/api/daily-records"
	if len(params) > 0 {
		endpoint += "?"
		for key, value := range params {
			endpoint += fmt.Sprintf("%s=%s&", key, value)
		}
		endpoint = endpoint[:len(endpoint)-1] // Remove trailing &
	}

	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Sales.URL, endpoint, nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

func (s *FrontendService) CreateDailySalesRecord(ctx context.Context, token string, data map[string]interface{}) (map[string]interface{}, error) {
	resp, err := s.makeAPIRequest(ctx, "POST", s.config.Services.Sales.URL, "/api/daily-records", data, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if resp.StatusCode != http.StatusCreated {
		return nil, fmt.Errorf("failed to create daily sales record: %s", result["error"])
	}

	return result, nil
}

func (s *FrontendService) GetSales(ctx context.Context, token string, params map[string]string) (map[string]interface{}, error) {
	endpoint := "/api/sales"
	if len(params) > 0 {
		endpoint += "?"
		for key, value := range params {
			endpoint += fmt.Sprintf("%s=%s&", key, value)
		}
		endpoint = endpoint[:len(endpoint)-1]
	}

	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Sales.URL, endpoint, nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

// Inventory service methods
func (s *FrontendService) GetProducts(ctx context.Context, token string, params map[string]string) (map[string]interface{}, error) {
	endpoint := "/api/products"
	if len(params) > 0 {
		endpoint += "?"
		for key, value := range params {
			endpoint += fmt.Sprintf("%s=%s&", key, value)
		}
		endpoint = endpoint[:len(endpoint)-1]
	}

	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Inventory.URL, endpoint, nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

func (s *FrontendService) GetStocks(ctx context.Context, token string, params map[string]string) (map[string]interface{}, error) {
	endpoint := "/api/stocks"
	if len(params) > 0 {
		endpoint += "?"
		for key, value := range params {
			endpoint += fmt.Sprintf("%s=%s&", key, value)
		}
		endpoint = endpoint[:len(endpoint)-1]
	}

	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Inventory.URL, endpoint, nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

func (s *FrontendService) GetCategories(ctx context.Context, token string) (map[string]interface{}, error) {
	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Inventory.URL, "/api/categories", nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

func (s *FrontendService) GetBrands(ctx context.Context, token string) (map[string]interface{}, error) {
	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Inventory.URL, "/api/brands", nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

// Finance service methods
func (s *FrontendService) GetVendors(ctx context.Context, token string) (map[string]interface{}, error) {
	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Finance.URL, "/api/vendors", nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

func (s *FrontendService) GetExpenses(ctx context.Context, token string, params map[string]string) (map[string]interface{}, error) {
	endpoint := "/api/expenses"
	if len(params) > 0 {
		endpoint += "?"
		for key, value := range params {
			endpoint += fmt.Sprintf("%s=%s&", key, value)
		}
		endpoint = endpoint[:len(endpoint)-1]
	}

	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Finance.URL, endpoint, nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

func (s *FrontendService) GetMoneyCollections(ctx context.Context, token string, params map[string]string) (map[string]interface{}, error) {
	endpoint := "/api/assistant-manager/money-collections"
	if len(params) > 0 {
		endpoint += "?"
		for key, value := range params {
			endpoint += fmt.Sprintf("%s=%s&", key, value)
		}
		endpoint = endpoint[:len(endpoint)-1]
	}

	resp, err := s.makeAPIRequest(ctx, "GET", s.config.Services.Finance.URL, endpoint, nil, token)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return result, nil
}

// Dashboard data aggregation
func (s *FrontendService) GetDashboardData(ctx context.Context, token string) (map[string]interface{}, error) {
	dashboardData := make(map[string]interface{})

	// Get sales summary
	salesData, err := s.GetSales(ctx, token, map[string]string{"limit": "10"})
	if err == nil {
		dashboardData["recent_sales"] = salesData
	}

	// Get low stock items
	stockData, err := s.GetStocks(ctx, token, map[string]string{"low_stock": "true", "limit": "10"})
	if err == nil {
		dashboardData["low_stock_items"] = stockData
	}

	// Get pending money collections (for assistant managers)
	collectionsData, err := s.GetMoneyCollections(ctx, token, map[string]string{"status": "pending", "limit": "5"})
	if err == nil {
		dashboardData["pending_collections"] = collectionsData
	}

	// Get recent expenses
	expensesData, err := s.GetExpenses(ctx, token, map[string]string{"limit": "5"})
	if err == nil {
		dashboardData["recent_expenses"] = expensesData
	}

	return dashboardData, nil
}

// Cache management
func (s *FrontendService) CacheData(ctx context.Context, key string, data interface{}, expiration time.Duration) error {
	return s.cache.Set(ctx, key, data, expiration)
}

func (s *FrontendService) GetCachedData(ctx context.Context, key string, dest interface{}) error {
	return s.cache.Get(ctx, key, dest)
}

func (s *FrontendService) ClearCache(ctx context.Context, pattern string) error {
	return s.cache.Delete(ctx, pattern)
}
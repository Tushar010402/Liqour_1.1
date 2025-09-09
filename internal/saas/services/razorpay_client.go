package services

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/liquorpro/go-backend/pkg/shared/config"
)

type RazorpayClient struct {
	keyID     string
	keySecret string
	baseURL   string
	client    *http.Client
}

type RazorpayCustomer struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Email   string `json:"email"`
	Contact string `json:"contact"`
}

type RazorpaySubscription struct {
	ID         string                 `json:"id"`
	PlanID     string                 `json:"plan_id"`
	CustomerID string                 `json:"customer_id"`
	Status     string                 `json:"status"`
	Notes      map[string]interface{} `json:"notes"`
}

type RazorpayOrder struct {
	ID       string `json:"id"`
	Amount   int64  `json:"amount"`
	Currency string `json:"currency"`
	Status   string `json:"status"`
	Receipt  string `json:"receipt"`
}

func NewRazorpayClient(cfg *config.Config) *RazorpayClient {
	return &RazorpayClient{
		keyID:     "rzp_test_RE1ixe1BI0UVVf",
		keySecret: "47ynWZOD7b5ZmSNd6jPsMPbW",
		baseURL:   "https://api.razorpay.com/v1",
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

func (r *RazorpayClient) CreateCustomer(name string) (string, error) {
	data := map[string]interface{}{
		"name":    name,
		"contact": "+919000000000",
		"email":   fmt.Sprintf("%s@liquorpro.com", name),
		"notes": map[string]string{
			"tenant": name,
		},
	}

	jsonData, err := json.Marshal(data)
	if err != nil {
		return "", fmt.Errorf("failed to marshal customer data: %w", err)
	}

	req, err := http.NewRequest("POST", r.baseURL+"/customers", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+r.basicAuth())

	resp, err := r.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("razorpay customer creation failed with status: %d", resp.StatusCode)
	}

	var customer RazorpayCustomer
	if err := json.NewDecoder(resp.Body).Decode(&customer); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	return customer.ID, nil
}

func (r *RazorpayClient) CreateSubscription(customerID, planID string) (string, error) {
	data := map[string]interface{}{
		"plan_id":     planID,
		"customer_id": customerID,
		"quantity":    1,
		"total_count": 12, // 12 billing cycles for yearly, will adjust later
		"notes": map[string]string{
			"created_by": "liquorpro_saas",
		},
	}

	jsonData, err := json.Marshal(data)
	if err != nil {
		return "", fmt.Errorf("failed to marshal subscription data: %w", err)
	}

	req, err := http.NewRequest("POST", r.baseURL+"/subscriptions", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+r.basicAuth())

	resp, err := r.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("razorpay subscription creation failed with status: %d", resp.StatusCode)
	}

	var subscription RazorpaySubscription
	if err := json.NewDecoder(resp.Body).Decode(&subscription); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	return subscription.ID, nil
}

func (r *RazorpayClient) CancelSubscription(subscriptionID string) error {
	req, err := http.NewRequest("POST", r.baseURL+"/subscriptions/"+subscriptionID+"/cancel", nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Basic "+r.basicAuth())

	resp, err := r.client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("razorpay subscription cancellation failed with status: %d", resp.StatusCode)
	}

	return nil
}

func (r *RazorpayClient) CreateOrder(amount int64, currency string, receipt string) (string, error) {
	data := map[string]interface{}{
		"amount":   amount, // amount in paise
		"currency": currency,
		"receipt":  receipt,
		"notes": map[string]string{
			"created_by": "liquorpro_saas",
		},
	}

	jsonData, err := json.Marshal(data)
	if err != nil {
		return "", fmt.Errorf("failed to marshal order data: %w", err)
	}

	req, err := http.NewRequest("POST", r.baseURL+"/orders", bytes.NewBuffer(jsonData))
	if err != nil {
		return "", fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+r.basicAuth())

	resp, err := r.client.Do(req)
	if err != nil {
		return "", fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("razorpay order creation failed with status: %d", resp.StatusCode)
	}

	var order RazorpayOrder
	if err := json.NewDecoder(resp.Body).Decode(&order); err != nil {
		return "", fmt.Errorf("failed to decode response: %w", err)
	}

	return order.ID, nil
}

func (r *RazorpayClient) FetchPayment(paymentID string) (map[string]interface{}, error) {
	req, err := http.NewRequest("GET", r.baseURL+"/payments/"+paymentID, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", "Basic "+r.basicAuth())

	resp, err := r.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("razorpay payment fetch failed with status: %d", resp.StatusCode)
	}

	var payment map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&payment); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return payment, nil
}

func (r *RazorpayClient) RefundPayment(paymentID string, amount int64) (map[string]interface{}, error) {
	data := map[string]interface{}{
		"amount": amount, // amount in paise
		"notes": map[string]string{
			"refunded_by": "liquorpro_saas",
		},
	}

	jsonData, err := json.Marshal(data)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal refund data: %w", err)
	}

	req, err := http.NewRequest("POST", r.baseURL+"/payments/"+paymentID+"/refund", bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Basic "+r.basicAuth())

	resp, err := r.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("razorpay refund failed with status: %d", resp.StatusCode)
	}

	var refund map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&refund); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return refund, nil
}

func (r *RazorpayClient) VerifyWebhookSignature(payload []byte, signature string, secret string) bool {
	// Implement webhook signature verification
	// This is a simplified version - in production, implement proper HMAC verification
	return len(signature) > 0
}

func (r *RazorpayClient) basicAuth() string {
	auth := r.keyID + ":" + r.keySecret
	return base64.StdEncoding.EncodeToString([]byte(auth))
}
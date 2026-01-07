package services

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/liquorpro/go-backend/internal/sales/models"
)

// OCRProvider defines the interface for OCR extraction providers
type OCRProvider interface {
	// Name returns the provider name (e.g., "ollama", "openai", "gemini")
	Name() string

	// IsAvailable checks if the provider is currently available
	IsAvailable(ctx context.Context) bool

	// ExtractSalesFromImage extracts sales data from a receipt image
	ExtractSalesFromImage(ctx context.Context, imageData []byte, imageURL string) (*ExtractionResult, error)

	// ExtractSalesFromImageWithPrompt extracts using a custom prompt
	ExtractSalesFromImageWithPrompt(ctx context.Context, imageData []byte, imageURL string, prompt string) (*ExtractionResult, error)

	// ConvertToOCRItems converts extraction result to OCRItem models
	ConvertToOCRItems(result *ExtractionResult, sessionID, batchID string) []models.OCRItem
}

// OCRProviderManager manages multiple OCR providers with fallback support
type OCRProviderManager struct {
	providers          []OCRProvider
	primaryProvider    string
	fallbackEnabled    bool
	confidenceThreshold float64
	mu                 sync.RWMutex
	stats              map[string]*ProviderStats
}

// ProviderStats tracks performance statistics for each provider
type ProviderStats struct {
	TotalRequests    int64
	SuccessRequests  int64
	FailedRequests   int64
	TotalLatencyMs   int64
	AvgLatencyMs     int64
	LastUsed         time.Time
	LastError        string
}

// NewOCRProviderManager creates a new provider manager with configured providers
func NewOCRProviderManager() (*OCRProviderManager, error) {
	manager := &OCRProviderManager{
		providers:          make([]OCRProvider, 0),
		primaryProvider:    os.Getenv("OCR_PROVIDER_PRIMARY"),
		fallbackEnabled:    os.Getenv("OCR_FALLBACK_ENABLED") != "false",
		confidenceThreshold: 0.85,
		stats:              make(map[string]*ProviderStats),
	}

	// Parse confidence threshold
	if threshold := os.Getenv("OCR_CONFIDENCE_THRESHOLD"); threshold != "" {
		if t, err := strconv.ParseFloat(threshold, 64); err == nil {
			manager.confidenceThreshold = t
		}
	}

	// Initialize providers in priority order
	// 1. Ollama (local, free) - if available
	if ollamaClient, err := NewOllamaVisionClient(); err == nil {
		manager.providers = append(manager.providers, &ollamaProviderWrapper{client: ollamaClient})
		manager.stats["ollama"] = &ProviderStats{}
		fmt.Printf("✅ [OCRProviderManager] Added Ollama provider\n")
	} else {
		fmt.Printf("⚠️  [OCRProviderManager] Ollama not available: %v\n", err)
	}

	// 2. OpenAI (cloud, paid)
	if openaiClient, err := NewOpenAIVisionClient(); err == nil {
		manager.providers = append(manager.providers, &openaiProviderWrapper{client: openaiClient})
		manager.stats["openai"] = &ProviderStats{}
		fmt.Printf("✅ [OCRProviderManager] Added OpenAI provider\n")
	} else {
		fmt.Printf("⚠️  [OCRProviderManager] OpenAI not available: %v\n", err)
	}

	// Set default primary if not specified
	if manager.primaryProvider == "" {
		if len(manager.providers) > 0 {
			manager.primaryProvider = manager.providers[0].Name()
		}
	}

	if len(manager.providers) == 0 {
		return nil, fmt.Errorf("no OCR providers available")
	}

	fmt.Printf("🎯 [OCRProviderManager] Primary provider: %s, Fallback enabled: %v\n",
		manager.primaryProvider, manager.fallbackEnabled)

	return manager, nil
}

// GetPrimaryProvider returns the primary provider
func (m *OCRProviderManager) GetPrimaryProvider() OCRProvider {
	m.mu.RLock()
	defer m.mu.RUnlock()

	for _, p := range m.providers {
		if p.Name() == m.primaryProvider {
			return p
		}
	}
	if len(m.providers) > 0 {
		return m.providers[0]
	}
	return nil
}

// GetProvider returns a specific provider by name
func (m *OCRProviderManager) GetProvider(name string) OCRProvider {
	m.mu.RLock()
	defer m.mu.RUnlock()

	name = strings.ToLower(name)
	for _, p := range m.providers {
		if strings.ToLower(p.Name()) == name {
			return p
		}
	}
	return nil
}

// ExtractWithFallback extracts using primary provider with fallback support
func (m *OCRProviderManager) ExtractWithFallback(ctx context.Context, imageData []byte, imageURL string) (*ExtractionResult, string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	var lastError error
	var usedProvider string

	// Reorder providers to put primary first
	orderedProviders := m.getOrderedProviders()

	for _, provider := range orderedProviders {
		providerName := provider.Name()

		// Check availability
		if !provider.IsAvailable(ctx) {
			fmt.Printf("⏭️  [OCRProviderManager] Skipping %s (not available)\n", providerName)
			continue
		}

		fmt.Printf("🔄 [OCRProviderManager] Trying provider: %s\n", providerName)
		startTime := time.Now()

		result, err := provider.ExtractSalesFromImage(ctx, imageData, imageURL)
		latency := time.Since(startTime).Milliseconds()

		// Update stats
		stats := m.stats[providerName]
		if stats != nil {
			stats.TotalRequests++
			stats.TotalLatencyMs += latency
			stats.AvgLatencyMs = stats.TotalLatencyMs / stats.TotalRequests
			stats.LastUsed = time.Now()
		}

		if err != nil {
			if stats != nil {
				stats.FailedRequests++
				stats.LastError = err.Error()
			}
			lastError = err
			fmt.Printf("❌ [OCRProviderManager] %s failed: %v\n", providerName, err)

			if !m.fallbackEnabled {
				return nil, providerName, err
			}
			continue
		}

		// Success
		if stats != nil {
			stats.SuccessRequests++
		}

		usedProvider = providerName
		fmt.Printf("✅ [OCRProviderManager] %s succeeded: %d items in %dms\n",
			providerName, len(result.Items), latency)

		// Check if result needs fallback due to low confidence
		if m.shouldFallback(result) && m.fallbackEnabled {
			fmt.Printf("🔄 [OCRProviderManager] Low confidence (%.0f%%), trying fallback...\n",
				m.calculateAverageConfidence(result)*100)
			continue
		}

		return result, usedProvider, nil
	}

	if lastError != nil {
		return nil, "", fmt.Errorf("all providers failed, last error: %w", lastError)
	}
	return nil, "", fmt.Errorf("no available providers")
}

// getOrderedProviders returns providers with primary first
func (m *OCRProviderManager) getOrderedProviders() []OCRProvider {
	ordered := make([]OCRProvider, 0, len(m.providers))

	// Add primary first
	for _, p := range m.providers {
		if p.Name() == m.primaryProvider {
			ordered = append(ordered, p)
			break
		}
	}

	// Add rest
	for _, p := range m.providers {
		if p.Name() != m.primaryProvider {
			ordered = append(ordered, p)
		}
	}

	return ordered
}

// shouldFallback checks if result should trigger fallback
func (m *OCRProviderManager) shouldFallback(result *ExtractionResult) bool {
	if result == nil || len(result.Items) == 0 {
		return true
	}

	avgConfidence := m.calculateAverageConfidence(result)
	return avgConfidence < m.confidenceThreshold
}

// calculateAverageConfidence calculates average confidence of extraction
func (m *OCRProviderManager) calculateAverageConfidence(result *ExtractionResult) float64 {
	if result == nil || len(result.Items) == 0 {
		return 0
	}

	var total float64
	for _, item := range result.Items {
		total += item.Confidence / 100.0 // Convert percentage to decimal
	}
	return total / float64(len(result.Items))
}

// GetStats returns provider statistics
func (m *OCRProviderManager) GetStats() map[string]*ProviderStats {
	m.mu.RLock()
	defer m.mu.RUnlock()

	// Return a copy
	stats := make(map[string]*ProviderStats)
	for k, v := range m.stats {
		stats[k] = &ProviderStats{
			TotalRequests:   v.TotalRequests,
			SuccessRequests: v.SuccessRequests,
			FailedRequests:  v.FailedRequests,
			TotalLatencyMs:  v.TotalLatencyMs,
			AvgLatencyMs:    v.AvgLatencyMs,
			LastUsed:        v.LastUsed,
			LastError:       v.LastError,
		}
	}
	return stats
}

// ListProviders returns list of available provider names
func (m *OCRProviderManager) ListProviders() []string {
	m.mu.RLock()
	defer m.mu.RUnlock()

	names := make([]string, 0, len(m.providers))
	for _, p := range m.providers {
		names = append(names, p.Name())
	}
	return names
}

// SetPrimaryProvider changes the primary provider
func (m *OCRProviderManager) SetPrimaryProvider(name string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	for _, p := range m.providers {
		if strings.EqualFold(p.Name(), name) {
			m.primaryProvider = p.Name()
			fmt.Printf("🎯 [OCRProviderManager] Primary provider changed to: %s\n", name)
			return nil
		}
	}
	return fmt.Errorf("provider '%s' not found", name)
}

// Provider wrappers to implement the OCRProvider interface

// ollamaProviderWrapper wraps OllamaVisionClient to implement OCRProvider
type ollamaProviderWrapper struct {
	client *OllamaVisionClient
}

func (w *ollamaProviderWrapper) Name() string {
	return "ollama"
}

func (w *ollamaProviderWrapper) IsAvailable(ctx context.Context) bool {
	return w.client.IsAvailable(ctx)
}

func (w *ollamaProviderWrapper) ExtractSalesFromImage(ctx context.Context, imageData []byte, imageURL string) (*ExtractionResult, error) {
	return w.client.ExtractSalesFromImage(ctx, imageData, imageURL)
}

func (w *ollamaProviderWrapper) ExtractSalesFromImageWithPrompt(ctx context.Context, imageData []byte, imageURL string, prompt string) (*ExtractionResult, error) {
	return w.client.ExtractSalesFromImageWithPrompt(ctx, imageData, imageURL, prompt)
}

func (w *ollamaProviderWrapper) ConvertToOCRItems(result *ExtractionResult, sessionID, batchID string) []models.OCRItem {
	return w.client.ConvertToOCRItems(result, sessionID, batchID)
}

// openaiProviderWrapper wraps OpenAIVisionClient to implement OCRProvider
type openaiProviderWrapper struct {
	client *OpenAIVisionClient
}

func (w *openaiProviderWrapper) Name() string {
	return "openai"
}

func (w *openaiProviderWrapper) IsAvailable(ctx context.Context) bool {
	// OpenAI is always available if API key is set
	return w.client != nil
}

func (w *openaiProviderWrapper) ExtractSalesFromImage(ctx context.Context, imageData []byte, imageURL string) (*ExtractionResult, error) {
	return w.client.ExtractSalesFromImage(ctx, imageData, imageURL)
}

func (w *openaiProviderWrapper) ExtractSalesFromImageWithPrompt(ctx context.Context, imageData []byte, imageURL string, prompt string) (*ExtractionResult, error) {
	return w.client.ExtractSalesFromImageWithPrompt(ctx, imageData, imageURL, prompt)
}

func (w *openaiProviderWrapper) ConvertToOCRItems(result *ExtractionResult, sessionID, batchID string) []models.OCRItem {
	return w.client.ConvertToOCRItems(result, sessionID, batchID)
}

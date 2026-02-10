package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/liquorpro/go-backend/internal/sales/models"
)

// SizeHeaderDetector handles Fomoa AI Vision API calls for size header detection
type SizeHeaderDetector struct {
	apiKey     string
	httpClient *http.Client
	model      string
	baseURL    string
	maxRetries int
}

// FomoaRequest represents the request structure for Fomoa AI Vision API (OpenAI compatible)
type FomoaRequest struct {
	Model       string         `json:"model"`
	Messages    []FomoaMessage `json:"messages"`
	MaxTokens   int            `json:"max_tokens"`
	Temperature float64        `json:"temperature"`
}

// FomoaMessage represents a message in the conversation
type FomoaMessage struct {
	Role    string         `json:"role"`
	Content []FomoaContent `json:"content"`
}

// FomoaContent represents content in a message (text or image)
type FomoaContent struct {
	Type     string         `json:"type"`
	Text     string         `json:"text,omitempty"`
	ImageURL *FomoaImageURL `json:"image_url,omitempty"`
}

// FomoaImageURL represents an image URL in the content
type FomoaImageURL struct {
	URL    string `json:"url"`
	Detail string `json:"detail,omitempty"`
}

// FomoaResponse represents the response from Fomoa AI Vision API
type FomoaResponse struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	Model   string `json:"model"`
	Choices []struct {
		Index   int `json:"index"`
		Message struct {
			Role    string `json:"role"`
			Content string `json:"content"`
		} `json:"message"`
		FinishReason string `json:"finish_reason"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage"`
	Error *struct {
		Message string `json:"message"`
		Type    string `json:"type"`
		Code    string `json:"code"`
	} `json:"error,omitempty"`
}

// NewSizeHeaderDetector creates a new Fomoa AI Vision client for size detection
func NewSizeHeaderDetector() (*SizeHeaderDetector, error) {
	apiKey := os.Getenv("FOMOA_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("FOMOA_API_KEY environment variable not set")
	}

	return &SizeHeaderDetector{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 60 * time.Second, // 1 minute timeout for vision processing
		},
		model:      "fomoa-vision-2.0",
		baseURL:    "https://fomoa.cloud/api/v1",
		maxRetries: 3,
	}, nil
}

// NewSizeHeaderDetectorWithKey creates a detector with a specific API key
func NewSizeHeaderDetectorWithKey(apiKey string) *SizeHeaderDetector {
	return &SizeHeaderDetector{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
		},
		model:      "fomoa-vision-2.0",
		baseURL:    "https://fomoa.cloud/api/v1",
		maxRetries: 3,
	}
}

// DetectSizeFromImage analyzes an image to detect the size header and page type
func (d *SizeHeaderDetector) DetectSizeFromImage(ctx context.Context, imageData []byte, imageURL string) (*models.SizeDetectionResult, error) {
	startTime := time.Now()

	fmt.Printf("[Fomoa Vision] Starting size detection...\n")

	// Prepare image content
	var imageContent FomoaContent
	if len(imageData) > 0 {
		base64Image := base64.StdEncoding.EncodeToString(imageData)
		mimeType := detectMimeType(imageData)
		imageContent = FomoaContent{
			Type: "image_url",
			ImageURL: &FomoaImageURL{
				URL:    fmt.Sprintf("data:%s;base64,%s", mimeType, base64Image),
				Detail: "high",
			},
		}
		fmt.Printf("[Fomoa Vision] Using base64 image (%d bytes, %s)\n", len(imageData), mimeType)
	} else if imageURL != "" {
		imageContent = FomoaContent{
			Type: "image_url",
			ImageURL: &FomoaImageURL{
				URL:    imageURL,
				Detail: "high",
			},
		}
		fmt.Printf("[Fomoa Vision] Using image URL: %s\n", truncateString(imageURL, 50))
	} else {
		return nil, fmt.Errorf("no image data or URL provided")
	}

	// Build the size detection prompt
	prompt := d.buildSizeDetectionPrompt()

	// Build the request
	request := FomoaRequest{
		Model: d.model,
		Messages: []FomoaMessage{
			{
				Role: "user",
				Content: []FomoaContent{
					{Type: "text", Text: prompt},
					imageContent,
				},
			},
		},
		MaxTokens:   1024,
		Temperature: 0.1, // Low temperature for consistent results
	}

	// Make the API call with retries (longer delays for rate limiting)
	var response *FomoaResponse
	var err error
	for attempt := 1; attempt <= d.maxRetries; attempt++ {
		response, err = d.makeAPICall(ctx, request)
		if err == nil {
			break
		}
		fmt.Printf("[Fomoa Vision] Attempt %d failed: %v\n", attempt, err)
		if attempt < d.maxRetries {
			// Use longer exponential backoff for rate limiting (10, 20, 30 seconds)
			delay := time.Duration(attempt) * 10 * time.Second
			fmt.Printf("[Fomoa Vision] Waiting %v before retry...\n", delay)
			time.Sleep(delay)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("Fomoa API call failed after %d attempts: %w", d.maxRetries, err)
	}

	// Parse the response
	result, err := d.parseSizeDetectionResponse(response)
	if err != nil {
		return nil, fmt.Errorf("failed to parse size detection response: %w", err)
	}

	fmt.Printf("[Fomoa Vision] Detection completed in %v - Beer page: %v, Sizes: %v, Confidence: %.1f%%\n",
		time.Since(startTime), result.IsBeerPage, result.Sizes, result.Confidence)

	return result, nil
}

// buildSizeDetectionPrompt creates the prompt for size header detection
func (d *SizeHeaderDetector) buildSizeDetectionPrompt() string {
	return `Analyze this Indian liquor sales register image carefully.

TASK: Identify the SIZE(s) shown in this page and whether it's a BEER page.

WHAT TO LOOK FOR:
1. Size headers like "SALE RECEIPT - 90ML", "180 ML", "375 ML", "750 ML", "650 ML"
2. Beer pages have ALL sizes (90ML, 180ML, 375ML, 650ML) stacked vertically in sections
3. Non-beer pages (IMFL/Country Liquor) show only ONE size per page
4. Size headers are usually at the TOP of each section

BEER PAGE CHARACTERISTICS:
- Multiple size sections visible vertically
- Sizes in order: typically 90ML at top, then 180ML, 375ML, 650ML
- Each section has its own header and list of brands
- Common beer brands: Kingfisher, Budweiser, Haywards, Tuborg, Carlsberg, Royal Challenge

NON-BEER PAGE CHARACTERISTICS:
- Single size header at top (e.g., "SALE RECEIPT - 180ML")
- One continuous list of brands
- Brands like: 8PM, Royal Stag, Imperial Blue, Old Monk, Blenders Pride

IMPORTANT: If you see multiple sizes in the image (like 90ML and 180ML sections), it's likely a BEER page.

Return ONLY this JSON (no other text):
{
  "is_beer_page": true or false,
  "sizes": ["180ML"],
  "size_regions": [
    {"size": "180ML", "y_start_pct": 0, "y_end_pct": 100}
  ],
  "confidence": 95
}

For beer pages with multiple sizes, include ALL size regions:
{
  "is_beer_page": true,
  "sizes": ["90ML", "180ML", "375ML", "650ML"],
  "size_regions": [
    {"size": "90ML", "y_start_pct": 0, "y_end_pct": 25},
    {"size": "180ML", "y_start_pct": 25, "y_end_pct": 50},
    {"size": "375ML", "y_start_pct": 50, "y_end_pct": 75},
    {"size": "650ML", "y_start_pct": 75, "y_end_pct": 100}
  ],
  "confidence": 90
}

Analyze the image now:`
}

// makeAPICall makes the HTTP request to Fomoa AI API
func (d *SizeHeaderDetector) makeAPICall(ctx context.Context, request FomoaRequest) (*FomoaResponse, error) {
	jsonData, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	apiURL := d.baseURL + "/chat"
	req, err := http.NewRequestWithContext(ctx, "POST", apiURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+d.apiKey)

	resp, err := d.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var response FomoaResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if response.Error != nil {
		return nil, fmt.Errorf("API error: %s (%s)", response.Error.Message, response.Error.Type)
	}

	fmt.Printf("[Fomoa Vision] Model: %s, Tokens: %d (prompt: %d, completion: %d)\n",
		response.Model, response.Usage.TotalTokens, response.Usage.PromptTokens, response.Usage.CompletionTokens)

	return &response, nil
}

// parseSizeDetectionResponse parses the Fomoa response into SizeDetectionResult
func (d *SizeHeaderDetector) parseSizeDetectionResponse(response *FomoaResponse) (*models.SizeDetectionResult, error) {
	if len(response.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	content := response.Choices[0].Message.Content
	content = cleanJSONResponse(content)

	fmt.Printf("[Fomoa Vision] Raw response: %s\n", truncateString(content, 500))

	var result models.SizeDetectionResult
	if err := json.Unmarshal([]byte(content), &result); err != nil {
		// Try to extract JSON from the response if wrapped in text
		jsonStart := strings.Index(content, "{")
		jsonEnd := strings.LastIndex(content, "}")
		if jsonStart >= 0 && jsonEnd > jsonStart {
			cleanedJSON := content[jsonStart : jsonEnd+1]
			if err := json.Unmarshal([]byte(cleanedJSON), &result); err != nil {
				fmt.Printf("[Fomoa Vision] Failed to parse JSON: %v\n", err)
				return nil, fmt.Errorf("failed to parse JSON response: %w", err)
			}
		} else {
			return nil, fmt.Errorf("no valid JSON found in response")
		}
	}

	// Normalize sizes to uppercase with ML suffix
	for i, size := range result.Sizes {
		result.Sizes[i] = normalizeSizeLabel(size)
	}
	for i := range result.SizeRegions {
		result.SizeRegions[i].Size = normalizeSizeLabel(result.SizeRegions[i].Size)
	}

	// Validate and set defaults
	if len(result.Sizes) == 0 {
		return nil, fmt.Errorf("no sizes detected in image")
	}

	if result.Confidence == 0 {
		result.Confidence = 80 // Default confidence
	}

	// Ensure size_regions matches sizes
	if len(result.SizeRegions) == 0 && len(result.Sizes) > 0 {
		// Create default region for single size
		if len(result.Sizes) == 1 {
			result.SizeRegions = []models.SizeRegionData{
				{Size: result.Sizes[0], YStartPct: 0, YEndPct: 100},
			}
		}
	}

	return &result, nil
}

// normalizeSizeLabel normalizes size labels to consistent format
func normalizeSizeLabel(size string) string {
	size = strings.ToUpper(strings.TrimSpace(size))
	size = strings.ReplaceAll(size, " ", "")

	// Common variations
	replacements := map[string]string{
		"90":     "90ML",
		"180":    "180ML",
		"375":    "375ML",
		"750":    "750ML",
		"650":    "650ML",
		"330":    "330ML",
		"500":    "500ML",
		"1000":   "1000ML",
		"1L":     "1000ML",
		"QUART":  "180ML",
		"HALF":   "375ML",
		"FULL":   "750ML",
	}

	if normalized, ok := replacements[size]; ok {
		return normalized
	}

	// Ensure ML suffix
	if !strings.HasSuffix(size, "ML") && !strings.HasSuffix(size, "L") {
		size = size + "ML"
	}

	return size
}

// DetectSizeFromFile reads a file and detects size
func (d *SizeHeaderDetector) DetectSizeFromFile(ctx context.Context, filePath string) (*models.SizeDetectionResult, error) {
	imageData, err := os.ReadFile(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read image file: %w", err)
	}

	return d.DetectSizeFromImage(ctx, imageData, "")
}

// BatchDetectSizes detects sizes for multiple images
func (d *SizeHeaderDetector) BatchDetectSizes(ctx context.Context, images []struct {
	Filename string
	Data     []byte
	URL      string
}) (map[string]*models.SizeDetectionResult, error) {
	results := make(map[string]*models.SizeDetectionResult)

	for _, img := range images {
		var data []byte
		var url string

		if len(img.Data) > 0 {
			data = img.Data
		} else {
			url = img.URL
		}

		result, err := d.DetectSizeFromImage(ctx, data, url)
		if err != nil {
			fmt.Printf("[Fomoa Vision] Error detecting size for %s: %v\n", img.Filename, err)
			continue
		}

		results[img.Filename] = result
	}

	return results, nil
}

// ReadFileHelper is a helper function to read files (exported for use in handlers)
func ReadFileHelper(path string) ([]byte, error) {
	return os.ReadFile(path)
}

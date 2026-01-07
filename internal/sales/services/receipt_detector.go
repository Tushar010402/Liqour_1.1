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
	"time"
)

// ReceiptDetector detects multiple receipts in a single image
type ReceiptDetector struct {
	apiKey     string
	httpClient *http.Client
	model      string
}

// BoundingBox represents the location of a receipt region as percentages (0-100)
type BoundingBox struct {
	X      float64 `json:"x"`      // Left edge as percentage
	Y      float64 `json:"y"`      // Top edge as percentage
	Width  float64 `json:"width"`  // Width as percentage
	Height float64 `json:"height"` // Height as percentage
}

// ReceiptRegion represents a detected receipt within the image
type ReceiptRegion struct {
	Index          int         `json:"index"`           // 0, 1, 2...
	Position       string      `json:"position"`        // "left", "right", "top", "bottom", "center"
	BoundingBox    BoundingBox `json:"bounding_box"`    // Location in image
	ReceiptType    string      `json:"receipt_type"`    // "HALF", "QUART", "FULL", etc.
	EstimatedItems int         `json:"estimated_items"` // Approximate item count
	Confidence     float64     `json:"confidence"`      // Detection confidence (0-100)
}

// MultiReceiptAnalysis represents the analysis of an image for multiple receipts
type MultiReceiptAnalysis struct {
	ReceiptCount       int             `json:"receipt_count"`
	Regions            []ReceiptRegion `json:"regions"`
	NeedsSplitting     bool            `json:"needs_splitting"`
	LayoutType         string          `json:"layout_type"`          // "side-by-side", "stacked", "single"
	TotalEstimatedItems int            `json:"total_estimated_items"`
	AnalysisTime       time.Duration   `json:"analysis_time"`
	Warnings           []string        `json:"warnings,omitempty"`
}

// NewReceiptDetector creates a new receipt detector
func NewReceiptDetector() (*ReceiptDetector, error) {
	apiKey := os.Getenv("OPENAI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY environment variable not set")
	}

	return &ReceiptDetector{
		apiKey: apiKey,
		httpClient: &http.Client{
			Timeout: 60 * time.Second,
		},
		model: "gpt-4o-2024-11-20",
	}, nil
}

// AnalyzeImage detects if the image contains multiple receipts
func (d *ReceiptDetector) AnalyzeImage(ctx context.Context, imageData []byte) (*MultiReceiptAnalysis, error) {
	startTime := time.Now()
	fmt.Printf("🔍 [ReceiptDetector] Analyzing image for multiple receipts...\n")

	// Prepare image content
	base64Image := base64.StdEncoding.EncodeToString(imageData)
	mimeType := detectMimeType(imageData)

	// Build the detection request
	request := OpenAIRequest{
		Model: d.model,
		Messages: []OpenAIMessage{
			{
				Role: "user",
				Content: []OpenAIContent{
					{
						Type: "text",
						Text: d.buildDetectionPrompt(),
					},
					{
						Type: "image_url",
						ImageURL: &OpenAIImageURL{
							URL:    fmt.Sprintf("data:%s;base64,%s", mimeType, base64Image),
							Detail: "low", // Low detail is sufficient for detection
						},
					},
				},
			},
		},
		MaxTokens:   1024, // Detection needs fewer tokens
		Temperature: 0.1,
	}

	// Make the API call
	jsonData, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(jsonData))
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

	var response OpenAIResponse
	if err := json.Unmarshal(body, &response); err != nil {
		return nil, fmt.Errorf("failed to unmarshal response: %w", err)
	}

	if response.Error != nil {
		return nil, fmt.Errorf("API error: %s", response.Error.Message)
	}

	// Parse the detection result
	analysis, err := d.parseDetectionResponse(&response)
	if err != nil {
		// If detection fails, assume single receipt
		fmt.Printf("⚠️ [ReceiptDetector] Detection failed, assuming single receipt: %v\n", err)
		return &MultiReceiptAnalysis{
			ReceiptCount:   1,
			NeedsSplitting: false,
			LayoutType:     "single",
			AnalysisTime:   time.Since(startTime),
		}, nil
	}

	analysis.AnalysisTime = time.Since(startTime)

	fmt.Printf("✅ [ReceiptDetector] Detected %d receipt(s) in %v (layout: %s)\n",
		analysis.ReceiptCount, analysis.AnalysisTime, analysis.LayoutType)

	return analysis, nil
}

// buildDetectionPrompt creates the prompt for multi-receipt detection
func (d *ReceiptDetector) buildDetectionPrompt() string {
	return `Analyze this image and detect how many separate receipt/invoice documents are visible.

TASK: Count and locate receipt regions in the image.

WHAT TO LOOK FOR:
1. Separate paper documents placed side by side or stacked
2. Distinct column headers (S.No, Brand, Opening, Receipt, etc.)
3. Separate "Grand Total" or "Total" rows
4. Physical gaps or boundaries between documents

For each receipt found, identify:
1. Its position (left, right, top, bottom, center)
2. Its approximate bounding box as percentages (0-100 of image dimensions)
3. The receipt type (HALF, QUART, FULL based on bottle sizes visible)
4. Approximate number of line items visible (count the rows)

IMPORTANT:
- Add 5% padding to bounding boxes to avoid cutting text
- If receipts overlap slightly, include overlapping area in both
- Count ALL visible line items, including partially visible ones

Return ONLY valid JSON with this structure:
{
  "receipt_count": 2,
  "layout": "side-by-side",
  "total_estimated_items": 38,
  "regions": [
    {
      "index": 0,
      "position": "left",
      "bounding_box": {"x": 0, "y": 0, "width": 50, "height": 100},
      "receipt_type": "HALF",
      "estimated_items": 27,
      "confidence": 95
    },
    {
      "index": 1,
      "position": "right",
      "bounding_box": {"x": 50, "y": 0, "width": 50, "height": 100},
      "receipt_type": "HALF",
      "estimated_items": 11,
      "confidence": 93
    }
  ],
  "warnings": []
}

If only ONE receipt is visible, return:
{
  "receipt_count": 1,
  "layout": "single",
  "total_estimated_items": 25,
  "regions": [
    {
      "index": 0,
      "position": "center",
      "bounding_box": {"x": 0, "y": 0, "width": 100, "height": 100},
      "receipt_type": "HALF",
      "estimated_items": 25,
      "confidence": 98
    }
  ],
  "warnings": []
}

Analyze the image now:`
}

// parseDetectionResponse parses the GPT-4o response for detection result
func (d *ReceiptDetector) parseDetectionResponse(response *OpenAIResponse) (*MultiReceiptAnalysis, error) {
	if len(response.Choices) == 0 {
		return nil, fmt.Errorf("no choices in response")
	}

	content := response.Choices[0].Message.Content
	content = cleanJSONResponse(content)

	var result struct {
		ReceiptCount        int             `json:"receipt_count"`
		Layout              string          `json:"layout"`
		TotalEstimatedItems int             `json:"total_estimated_items"`
		Regions             []ReceiptRegion `json:"regions"`
		Warnings            []string        `json:"warnings"`
	}

	if err := json.Unmarshal([]byte(content), &result); err != nil {
		// Try to extract JSON from wrapped text
		jsonStart := findJSONStart(content)
		jsonEnd := findJSONEnd(content)
		if jsonStart >= 0 && jsonEnd > jsonStart {
			cleanedJSON := content[jsonStart : jsonEnd+1]
			if err := json.Unmarshal([]byte(cleanedJSON), &result); err != nil {
				return nil, fmt.Errorf("failed to parse detection JSON: %w", err)
			}
		} else {
			return nil, fmt.Errorf("no valid JSON found in response")
		}
	}

	// Validate and normalize bounding boxes
	for i := range result.Regions {
		region := &result.Regions[i]
		// Ensure bounding boxes are valid percentages
		if region.BoundingBox.X < 0 {
			region.BoundingBox.X = 0
		}
		if region.BoundingBox.Y < 0 {
			region.BoundingBox.Y = 0
		}
		if region.BoundingBox.Width <= 0 {
			region.BoundingBox.Width = 100
		}
		if region.BoundingBox.Height <= 0 {
			region.BoundingBox.Height = 100
		}
		// Cap at 100%
		if region.BoundingBox.X + region.BoundingBox.Width > 100 {
			region.BoundingBox.Width = 100 - region.BoundingBox.X
		}
		if region.BoundingBox.Y + region.BoundingBox.Height > 100 {
			region.BoundingBox.Height = 100 - region.BoundingBox.Y
		}
	}

	return &MultiReceiptAnalysis{
		ReceiptCount:        result.ReceiptCount,
		Regions:             result.Regions,
		NeedsSplitting:      result.ReceiptCount > 1,
		LayoutType:          result.Layout,
		TotalEstimatedItems: result.TotalEstimatedItems,
		Warnings:            result.Warnings,
	}, nil
}

// Helper functions

func findJSONStart(s string) int {
	for i, c := range s {
		if c == '{' {
			return i
		}
	}
	return -1
}

func findJSONEnd(s string) int {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] == '}' {
			return i
		}
	}
	return -1
}

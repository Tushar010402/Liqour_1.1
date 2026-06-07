package services

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

// Training data storage for Smart Stock Setup
// Saves images, AI responses, and user corrections for future AI model training.
//
// Directory structure:
//   /var/www/liquorpro/uploads/ai-training/stock-setup/
//     {tenant_id_short}/
//       {session_id}/
//         image_1.jpg                 # Original register images
//         image_2.jpg
//         metadata.json               # Session metadata (who, when, scope)
//         ai_extraction.json          # Raw AI response (what AI saw)
//         matched_result.json         # After product matching (what system produced)
//         applied_corrections.json    # User-confirmed data (ground truth for training)

const stockSetupStorageBase = "/app/ai-training/stock-setup"

// StockSetupSessionMetadata holds context about an extraction session
type StockSetupSessionMetadata struct {
	SessionID    string    `json:"session_id"`
	TenantID     string    `json:"tenant_id"`
	ShopID       string    `json:"shop_id"`
	UserID       string    `json:"user_id"`
	CategoryID   string    `json:"category_id,omitempty"`
	CategoryName string    `json:"category_name,omitempty"`
	Size         string    `json:"size,omitempty"`
	SizeML       int       `json:"size_ml,omitempty"`
	StockColumn  string    `json:"stock_column"`
	ImageCount   int       `json:"image_count"`
	AIModel      string    `json:"ai_model"`
	CreatedAt    time.Time `json:"created_at"`
}

// StockSetupTrainingRecord links AI extraction with user corrections (ground truth)
type StockSetupTrainingRecord struct {
	SessionID   string                     `json:"session_id"`
	AppliedAt   time.Time                  `json:"applied_at"`
	Items       []SmartStockSetupApplyItem `json:"items"`        // what user confirmed
	ItemCount   int                        `json:"item_count"`
	CleanedUp   int                        `json:"cleaned_up"`
	CategoryID  string                     `json:"category_id,omitempty"`
	Size        string                     `json:"size,omitempty"`
}

// sessionDir returns the directory path for a session's training data
func sessionDir(tenantID, sessionID string) string {
	tenantShort := tenantID
	if len(tenantShort) > 8 {
		tenantShort = tenantShort[:8]
	}
	return filepath.Join(stockSetupStorageBase, tenantShort, sessionID)
}

// SaveSessionImages saves register images to disk asynchronously.
// Called during extraction — does not block the API response.
func SaveSessionImages(tenantID, sessionID string, images []SmartPurchaseImage) {
	go func() {
		dir := sessionDir(tenantID, sessionID)
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to create dir %s: %v", dir, err)
			return
		}

		for i, img := range images {
			ext := ".jpg"
			if len(img.ContentType) > 0 && (img.ContentType == "image/png" || img.ContentType == "png") {
				ext = ".png"
			}
			filename := fmt.Sprintf("image_%d%s", i+1, ext)
			path := filepath.Join(dir, filename)

			if err := os.WriteFile(path, img.Data, 0644); err != nil {
				log.Printf("Smart Stock Setup Storage: Failed to save image %s: %v", path, err)
				continue
			}
		}
		log.Printf("Smart Stock Setup Storage: Saved %d images to %s", len(images), dir)
	}()
}

// SaveSessionMetadata saves session context (who, when, scope)
func SaveSessionMetadata(tenantID, sessionID string, meta StockSetupSessionMetadata) {
	go func() {
		dir := sessionDir(tenantID, sessionID)
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to create dir: %v", err)
			return
		}

		data, err := json.MarshalIndent(meta, "", "  ")
		if err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to marshal metadata: %v", err)
			return
		}

		path := filepath.Join(dir, "metadata.json")
		if err := os.WriteFile(path, data, 0644); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to save metadata: %v", err)
		}
	}()
}

// SaveAIExtraction saves the raw AI extraction result (before product matching)
func SaveAIExtraction(tenantID, sessionID string, allExtracted []ExtractedStockRegisterItem, shopName string) {
	go func() {
		dir := sessionDir(tenantID, sessionID)
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to create dir: %v", err)
			return
		}

		record := map[string]interface{}{
			"shop_name":  shopName,
			"item_count": len(allExtracted),
			"items":      allExtracted,
			"saved_at":   time.Now(),
		}

		data, err := json.MarshalIndent(record, "", "  ")
		if err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to marshal AI extraction: %v", err)
			return
		}

		path := filepath.Join(dir, "ai_extraction.json")
		if err := os.WriteFile(path, data, 0644); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to save AI extraction: %v", err)
		}
	}()
}

// SaveMatchedResult saves the full extraction result after product matching
func SaveMatchedResult(tenantID, sessionID string, result *SmartStockSetupResult) {
	go func() {
		dir := sessionDir(tenantID, sessionID)
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to create dir: %v", err)
			return
		}

		data, err := json.MarshalIndent(result, "", "  ")
		if err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to marshal result: %v", err)
			return
		}

		path := filepath.Join(dir, "matched_result.json")
		if err := os.WriteFile(path, data, 0644); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to save matched result: %v", err)
		}
	}()
}

// SaveAppliedCorrections saves what the user actually confirmed — the ground truth for training.
// This is the most valuable data: AI extraction vs what user corrected.
func SaveAppliedCorrections(tenantID, sessionID string, record StockSetupTrainingRecord) {
	go func() {
		dir := sessionDir(tenantID, sessionID)
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to create dir: %v", err)
			return
		}

		data, err := json.MarshalIndent(record, "", "  ")
		if err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to marshal corrections: %v", err)
			return
		}

		path := filepath.Join(dir, "applied_corrections.json")
		if err := os.WriteFile(path, data, 0644); err != nil {
			log.Printf("Smart Stock Setup Storage: Failed to save corrections: %v", err)
		}
		log.Printf("Smart Stock Setup Storage: Saved training data for session %s (%d items)", sessionID, record.ItemCount)
	}()
}

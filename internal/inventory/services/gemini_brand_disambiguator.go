package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

// geminiBrandDisambiguator is a tiny text-only Gemini wrapper used as a
// matcher tiebreaker. When the fuzzy matcher returns NeedsReview=true (the
// top-2 candidates are tied within the ambiguity margin), we ask Gemini
// "given this OCR text and these N candidates, which is the right brand?"
// — a small text prompt, NO product image required. Brand identity is
// resolved entirely from OCR text + master-catalog candidate names.
//
// Wired from smart_stock_setup_service.matchAndEnrich. Disabled by default
// to avoid surprising costs; opt-in via GEMINI_DISAMBIG_ENABLED=1.
//
// Cost: gemini-2.5-flash, ~150 input tokens + ~30 output tokens per call.
// At ~₹0.001 per call, even a 100-row job with every row needing a
// tiebreaker stays under ₹0.10/page.
//
// v1.0.202.

type geminiBrandDisambiguator struct {
	client *genai.Client
	mu     sync.Mutex
}

var (
	geminiDisambigSingleton *geminiBrandDisambiguator
	geminiDisambigOnce      sync.Once
)

// getGeminiBrandDisambiguator returns the process-wide singleton. Cheap to
// call repeatedly — initialisation happens at most once. Returns nil when
// GEMINI_DISAMBIG_ENABLED is not 1, no API key is configured, or the SDK
// failed to initialise (caller treats nil as "feature off, fall back to
// the matcher's top candidate as-is").
func getGeminiBrandDisambiguator() *geminiBrandDisambiguator {
	if strings.TrimSpace(os.Getenv("GEMINI_DISAMBIG_ENABLED")) != "1" {
		return nil
	}
	geminiDisambigOnce.Do(func() {
		apiKey := strings.TrimSpace(os.Getenv("GEMINI_API_KEY"))
		if apiKey == "" {
			log.Printf("Gemini disambiguator: GEMINI_API_KEY missing, feature disabled")
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
		if err != nil {
			log.Printf("Gemini disambiguator: NewClient failed: %v", err)
			return
		}
		geminiDisambigSingleton = &geminiBrandDisambiguator{client: client}
		log.Printf("Gemini disambiguator: initialised (gemini-2.5-flash, text-only)")
	})
	return geminiDisambigSingleton
}

// GeminiBrandCandidate is one option presented to Gemini in the
// disambiguation prompt. Keep it minimal — adding extra fields inflates the
// token count without improving the pick. (Distinct name from the legacy
// BrandCandidate struct used for review-flow pick lists in
// smart_stock_setup_types.go.)
type GeminiBrandCandidate struct {
	ProductID   string
	DisplayName string
	Size        string
	MRP         float64
}

// PickBrand asks Gemini which candidate matches the OCR text best.
//
// Returns:
//   - productID (one of the input candidates' ProductID), and
//   - confidence in [0, 1] from Gemini's self-rating.
//
// Returns "" when Gemini can't decide, can't parse, or the network call
// times out — caller treats empty as "no override, keep matcher's top
// pick."
//
// The prompt is intentionally small: OCR text, candidates, "pick one
// or 'none'" instruction. No images, no extra context. Brand identity
// is resolved purely from text.
func (g *geminiBrandDisambiguator) PickBrand(ctx context.Context, ocrText string, candidates []GeminiBrandCandidate) (string, float64) {
	if g == nil || g.client == nil {
		return "", 0
	}
	if len(candidates) == 0 {
		return "", 0
	}
	if strings.TrimSpace(ocrText) == "" {
		return "", 0
	}

	g.mu.Lock()
	defer g.mu.Unlock()

	cctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()

	model := g.client.GenerativeModel("gemini-2.5-flash")
	model.ResponseMIMEType = "application/json"
	temp := float32(0.0) // deterministic — identical inputs MUST yield the same pick.
	model.Temperature = &temp

	var sb strings.Builder
	sb.WriteString("You are a liquor-shop brand-matching assistant. The shopkeeper wrote a brand name in their stock register; OCR read this text:\n\n")
	sb.WriteString("OCR TEXT: ")
	sb.WriteString(strings.TrimSpace(ocrText))
	sb.WriteString("\n\nThe shop's catalog has these candidate products at the same size. Pick the one that best matches the OCR text — accounting for typos, abbreviations, brand-family lineage, and product-line distinguishers (e.g. 'Premium Black' vs 'Special Rare', 'Verve Cranberry' vs 'Magic Moments Cranberry').\n\n")
	for i, c := range candidates {
		fmt.Fprintf(&sb, "%d. id=%s | name=%s", i+1, c.ProductID, c.DisplayName)
		if c.Size != "" {
			fmt.Fprintf(&sb, " | size=%s", c.Size)
		}
		if c.MRP > 0 {
			fmt.Fprintf(&sb, " | mrp=%.0f", c.MRP)
		}
		sb.WriteString("\n")
	}
	sb.WriteString("\nReturn JSON: {\"id\":\"<picked product id, or empty if none match>\",\"confidence\":<0..1>,\"why\":\"<one short sentence>\"}\n")
	sb.WriteString("If the OCR text plainly refers to a different product not in the list, return id=\"\".")

	resp, err := model.GenerateContent(cctx, genai.Text(sb.String()))
	if err != nil {
		log.Printf("Gemini disambiguator: GenerateContent err: %v", err)
		return "", 0
	}
	if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil || len(resp.Candidates[0].Content.Parts) == 0 {
		return "", 0
	}

	var raw strings.Builder
	for _, part := range resp.Candidates[0].Content.Parts {
		if t, ok := part.(genai.Text); ok {
			raw.WriteString(string(t))
		}
	}
	rawText := strings.TrimSpace(raw.String())
	if rawText == "" {
		return "", 0
	}

	var out struct {
		ID         string  `json:"id"`
		Confidence float64 `json:"confidence"`
		Why        string  `json:"why"`
	}
	if err := json.Unmarshal([]byte(rawText), &out); err != nil {
		log.Printf("Gemini disambiguator: JSON parse failed: %v (raw=%s)", err, rawText)
		return "", 0
	}
	pickedID := strings.TrimSpace(out.ID)
	if pickedID == "" {
		return "", 0
	}
	// Validate Gemini didn't hallucinate an ID outside the candidate list.
	for _, c := range candidates {
		if c.ProductID == pickedID {
			log.Printf("Gemini disambiguator: ocr=%q -> %s (conf=%.2f, why=%q)", ocrText, c.DisplayName, out.Confidence, out.Why)
			return pickedID, out.Confidence
		}
	}
	log.Printf("Gemini disambiguator: hallucinated id=%s, ignoring", pickedID)
	return "", 0
}

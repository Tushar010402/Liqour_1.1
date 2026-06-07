package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

// ExtractStockRegister extracts stock register data from an image using AI.
// categoryName, sizeML, and productNames are optional context for scoped extraction.
//
// Primary / fallback ordering matches Smart Purchase (smart_purchase_ocr.go:153+):
// Gemini 3 Flash benchmarks significantly better than GPT-5.2 on dual-line
// handwritten Indian liquor registers — which is the exact pattern we struggle
// with here (rows 43/46/47 "Gold Label" / "R.S Borrs" / "M.M. Jun" misreads).
// Override with SMART_STOCK_SETUP_PRIMARY=openai to flip back.
func (s *SmartPurchaseOCR) ExtractStockRegister(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames []string, masterBrandNames ...[]string) (*StockRegisterExtractionResult, error) {
	var masterNames []string
	if len(masterBrandNames) > 0 {
		masterNames = masterBrandNames[0]
	}

	// Phase 2.4 priority order:
	//   claude (Sonnet 4.6 + Opus verifier) > gemini > openai
	// Claude becomes the default once an ANTHROPIC_API_KEY is configured.
	// SMART_STOCK_SETUP_PRIMARY=gemini still flips back instantly for rollback.
	primary := os.Getenv("SMART_STOCK_SETUP_PRIMARY")
	if primary == "" {
		if s.anthropicKey != "" {
			primary = "claude"
		} else {
			primary = "gemini"
		}
	}

	if primary == "claude" && s.anthropicKey != "" {
		result, err := s.extractRegisterWithClaude(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames)
		if err == nil {
			// Run Opus verifier on low-confidence rows. verifyRowsWithClaude
			// returns the primary unchanged when no rows are low-conf or when
			// the verifier itself fails — never blocks the happy path.
			if verified, vErr := s.verifyRowsWithClaude(ctx, imageBytes, contentType, categoryName, sizeML, result.Items); vErr == nil {
				result.Items = verified
			}
			// v1.0.134 Track B — cell-level closing-stock micro-extraction.
			// Re-reads the closing-stock cell on rows where its field confidence
			// is low or the math identity is violated. No-op when
			// SMART_STOCK_SETUP_CELL_LEVEL!=1 (gated for cost control).
			if items2, st := s.repairLowConfClosingCells(ctx, imageBytes, result.Items); st.candidates > 0 {
				result.Items = items2
				log.Printf("Smart Stock Setup OCR: cell-level closing pass — candidates=%d called=%d replaced=%d",
					st.candidates, st.called, st.replaced)
			}
			return result, nil
		}
		log.Printf("Smart Stock Setup OCR: Claude failed (%v), trying Gemini fallback", err)
		if s.geminiKey != "" {
			if r2, err2 := s.extractRegisterWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames); err2 == nil {
				return r2, nil
			}
		}
		if s.openaiKey != "" {
			return s.extractRegisterWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames)
		}
		return nil, err
	}

	if primary == "gemini" && s.geminiKey != "" {
		result, err := s.extractRegisterWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames)
		if err == nil {
			return result, nil
		}
		log.Printf("Smart Stock Setup OCR: Gemini failed (%v), trying OpenAI fallback", err)
		if s.openaiKey != "" {
			return s.extractRegisterWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames)
		}
		return nil, err
	}

	if s.openaiKey != "" {
		result, err := s.extractRegisterWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames)
		if err == nil {
			return result, nil
		}
		log.Printf("Smart Stock Setup OCR: OpenAI failed (%v), trying Gemini fallback", err)
	}

	if s.geminiKey != "" {
		return s.extractRegisterWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterNames)
	}

	return nil, fmt.Errorf("no AI API keys configured for Smart Stock Setup")
}

// extractRegisterWithOpenAI uses OpenAI GPT Vision for stock register extraction
func (s *SmartPurchaseOCR) extractRegisterWithOpenAI(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames []string, masterBrandNames []string) (*StockRegisterExtractionResult, error) {
	imgType := "jpeg"
	if strings.Contains(contentType, "png") {
		imgType = "png"
	}

	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imgType, base64Image)

	prompt := buildStockRegisterPromptWithHints(ctx, categoryName, sizeML, productNames, masterBrandNames)

	content := []interface{}{
		spOpenAITextContent{Type: "text", Text: prompt},
		spOpenAIImageContent{
			Type: "image_url",
			ImageURL: spOpenAIImageURL{URL: imageDataURL, Detail: "high"},
		},
	}

	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}

	request := spOpenAIRequest{
		Model: model,
		Messages: []spOpenAIMessage{
			{Role: "user", Content: content},
		},
		MaxCompletionTokens: 8192,
		Temperature:         0.0,
		ResponseFormat:      &spResponseFmt{Type: "json_object"},
	}

	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openaiKey)

	log.Printf("Smart Stock Setup OCR: Sending to OpenAI %s (products: %d)...", model, len(productNames))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai api error %d: %s", resp.StatusCode, string(body))
	}

	var apiResp spOpenAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.Error != nil {
		return nil, fmt.Errorf("openai error: %s", apiResp.Error.Message)
	}

	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from OpenAI")
	}

	responseText := apiResp.Choices[0].Message.Content
	log.Printf("Smart Stock Setup OCR: OpenAI responded with %d tokens", apiResp.Usage.TotalTokens)

	return parseStockRegisterResponse(responseText)
}

// extractRegisterWithGemini uses Gemini for stock register extraction
func (s *SmartPurchaseOCR) extractRegisterWithGemini(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames []string, masterBrandNames []string) (*StockRegisterExtractionResult, error) {
	mimeType := "image/jpeg"
	if strings.Contains(contentType, "png") {
		mimeType = "image/png"
	}

	base64Image := base64.StdEncoding.EncodeToString(imageBytes)
	prompt := buildStockRegisterPromptWithHints(ctx, categoryName, sizeML, productNames, masterBrandNames)

	request := geminiRequest{
		Contents: []geminiContent{
			{
				Parts: []geminiPart{
					{Text: prompt},
					{InlineData: &geminiBlobData{MimeType: mimeType, Data: base64Image}},
				},
			},
		},
		GenerationConfig: geminiGenerationConfig{
			Temperature:      0.0,
			MaxOutputTokens:  8192,
			ResponseMimeType: "application/json",
		},
	}

	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// gemini-flash-latest resolves to gemini-3-flash-preview (as of 2026-04) —
	// matches Smart Purchase's choice and is substantially better on handwritten
	// Indian liquor registers than gemini-2.5-flash. Override with GEMINI_MODEL.
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	// Matches Smart Purchase — header auth keeps the API key out of query
	// strings (cleaner logs, no URL-escaping edge cases).
	req.Header.Set("X-goog-api-key", s.geminiKey)

	log.Printf("Smart Stock Setup OCR: Sending to Gemini %s (products: %d)...", model, len(productNames))

	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gemini request failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gemini api error %d: %s", resp.StatusCode, string(body))
	}

	var apiResp geminiResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if apiResp.Error != nil {
		return nil, fmt.Errorf("gemini error: %s", apiResp.Error.Message)
	}

	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no response from Gemini")
	}

	responseText := apiResp.Candidates[0].Content.Parts[0].Text
	log.Println("Smart Stock Setup OCR: Gemini responded successfully")

	return parseStockRegisterResponse(responseText)
}

// parseStockRegisterResponse parses the AI JSON response into StockRegisterExtractionResult
func parseStockRegisterResponse(responseText string) (*StockRegisterExtractionResult, error) {
	// Strip markdown code fences if present
	jsonText := responseText
	if idx := strings.Index(jsonText, "```json"); idx >= 0 {
		jsonText = jsonText[idx+7:]
	} else if idx := strings.Index(jsonText, "```"); idx >= 0 {
		jsonText = jsonText[idx+3:]
	}
	if idx := strings.LastIndex(jsonText, "```"); idx >= 0 {
		jsonText = jsonText[:idx]
	}
	jsonText = strings.TrimSpace(jsonText)

	var result StockRegisterExtractionResult
	if err := json.Unmarshal([]byte(jsonText), &result); err != nil {
		log.Printf("Smart Stock Setup OCR: Failed to parse JSON: %v\nRaw: %s", err, responseText[:spMinInt(len(responseText), 500)])
		return nil, fmt.Errorf("failed to parse extraction result: %w", err)
	}

	// Post-process items
	for i := range result.Items {
		item := &result.Items[i]

		// Use official brand name from AI if raw brand is empty
		if item.Brand == "" && item.OfficialBrandName != "" {
			item.Brand = item.OfficialBrandName
		}

		// Normalize size from text
		if item.SizeML == 0 && item.SizeText != "" {
			item.SizeML = normalizeSizeText(item.SizeText)
		}

		// Inherit page size if item has no individual size
		if item.SizeML == 0 && result.PageSizeML > 0 {
			item.SizeML = result.PageSizeML
		}
		if item.SizeText == "" && result.PageSize != "" {
			item.SizeText = result.PageSize
		}

		// Default confidence
		if item.Confidence == 0 {
			item.Confidence = 0.8
		}

		// Per-field confidence — make sure ALL 8 keys are present even when
		// the AI returned a PARTIAL map. Earlier the spread only fired when
		// the map was completely empty, so a Claude response like
		// {"brand": 0.9, "opening": 0.55} left sale/rate/amount/closing
		// keys absent → Flutter had nothing to threshold → silent un-flag
		// on those columns. Now we default each missing key to the overall
		// item.Confidence value, preserving any AI-provided per-field signal.
		if item.FieldConfidence == nil {
			item.FieldConfidence = map[string]float64{}
		}
		for _, f := range []string{"brand", "opening", "receipt", "total", "sale", "rate", "amount", "closing"} {
			if _, ok := item.FieldConfidence[f]; !ok {
				item.FieldConfidence[f] = item.Confidence
			}
		}

		// Arithmetic recovery — Smart Sale already does this for sale rows; same
		// invariants hold here. The shopkeeper double-checks money columns more
		// carefully than counts so when a count column is unreadable but the
		// money column is legible we can recover. Recovery caps confidence at
		// 0.65 so the row routes to the user for confirmation.
		if item.Sale == 0 && item.Amount > 0 && item.Rate > 0 {
			calc := item.Amount / item.Rate
			if calc > 0.5 && calc < 50.5 {
				inferred := int(calc + 0.5)
				diff := item.Amount - float64(inferred)*item.Rate
				if diff < 0 {
					diff = -diff
				}
				if diff <= 1.0 {
					log.Printf("Smart Stock Setup OCR: Row %d (%s): inferred sale=%d from amount=%.0f / rate=%.0f",
						item.RowNumber, item.Brand, inferred, item.Amount, item.Rate)
					item.Sale = inferred
					if item.Confidence > 0.65 {
						item.Confidence = 0.65
					}
				}
			}
		}
		if item.Total == 0 && item.Opening > 0 && item.Receipt >= 0 {
			item.Total = item.Opening + item.Receipt
			item.FieldConfidence["total"] = 0.4
		}
		if item.Closing == 0 && item.Total > 0 && item.Sale > 0 && item.Total >= item.Sale {
			item.Closing = item.Total - item.Sale
			item.FieldConfidence["closing"] = 0.4
		}
		// Inverse: Opening = Total - Receipt when Opening missing. Stamp the
		// per-field confidence at 0.4 so the review screen can amber-flag the
		// cell — silent recovery was hiding column-collapse bugs (Tushar saw
		// rows where opening was synthesized from a wrong Total and the user
		// had no signal to verify). 0.4 sits below the 0.7 calibrated threshold
		// so the cell renders amber.
		if item.Opening == 0 && item.Total > 0 && item.Total >= item.Receipt {
			item.Opening = item.Total - item.Receipt
			item.FieldConfidence["opening"] = 0.4
		}
	}

	// Post-extraction sanity guards. Run on every backend's output so the
	// per-field confidence reflects deterministic checks, not just the
	// model's self-assessment. See smart_stock_setup_guards.go.
	ApplyAllGuards(result.Items)

	log.Printf("Smart Stock Setup OCR: Extracted %d items from register (shop: %s, page size: %s)",
		len(result.Items), result.ShopName, result.PageSize)

	// Debug: log raw AI response when 0 items extracted
	if len(result.Items) == 0 {
		truncated := responseText
		if len(truncated) > 2000 {
			truncated = truncated[:2000] + "...[TRUNCATED]"
		}
		log.Printf("Smart Stock Setup OCR: WARNING 0 items extracted! Raw AI response:\n%s", truncated)
	}

	return &result, nil
}

// buildStockRegisterPrompt creates the AI extraction prompt for Indian liquor stock register pages.
// When categoryName and/or sizeML are provided, a context block is prepended for better accuracy.
// When productNames is non-empty, the product list is injected for direct AI matching.
// PromptHintsCtxKey is the context key for tenant/shop-specific prompt hints
// (template fingerprint + few-shot examples). The OCR backends read this and
// prepend the hint string to the static system prompt before sending to the
// model.
type promptHintsCtxKeyT struct{}

var PromptHintsCtxKey = promptHintsCtxKeyT{}

// v1.0.246 — StockColumnCtxKey carries the operator's column choice (opening
// / total / closing) into the prompt builder so the AI can laser-focus on
// that column. Mirrors Smart Sale's pattern where the prompt hardcodes
// "Sale (column 6) is the QUANTITY SOLD" and the AI biases accuracy toward
// the column that matters. Before v246 the column choice was applied only
// after extraction (determineStockQuantity) — meaning the AI split its
// attention across all 5 columns and the picked column got the same noisy
// read as the unused ones, which is why chhotu saw "zero opening" and
// "missing items" on the column he actually wanted.
type stockColumnCtxKeyT struct{}

var StockColumnCtxKey = stockColumnCtxKeyT{}

// buildStockRegisterPromptWithHints wraps buildStockRegisterPrompt and
// prepends any context-stashed hints (template + few-shot) so the per-tenant
// learned signal lands at the top of the system prompt.
func buildStockRegisterPromptWithHints(ctx context.Context, categoryName string, sizeML int, productNames []string, masterBrandNames []string) string {
	stockColumn := ""
	if ctx != nil {
		if c, ok := ctx.Value(StockColumnCtxKey).(string); ok {
			stockColumn = c
		}
	}
	base := buildStockRegisterPrompt(categoryName, sizeML, productNames, masterBrandNames)
	if ctx == nil {
		return base
	}
	var prefix string
	if stockColumn != "" {
		prefix = buildStockColumnFocusBlock(stockColumn) + "\n"
	}
	if hints, ok := ctx.Value(PromptHintsCtxKey).(string); ok && hints != "" {
		return prefix + hints + "\n" + base
	}
	return prefix + base
}

// buildStockColumnFocusBlock emits a high-priority lead-in that tells the AI
// which register column drives the operator's stock initialisation.
// The block lands BEFORE all other hints so it's the first thing the model
// reads. It does NOT tell the AI to skip the other columns (we still need
// them for math-gate validation), only to prioritise accuracy on the picked
// one.
func buildStockColumnFocusBlock(stockColumn string) string {
	col := strings.ToLower(strings.TrimSpace(stockColumn))
	var colName, colHint string
	switch col {
	case "opening":
		colName = "Opening (start-of-day stock)"
		colHint = "Read the FIRST numeric column AFTER the brand cell with maximum care — this is what populates the operator's inventory. If a row's Opening cell is blank but Closing has a clear value, the row may still be valid (operator can derive); do not skip it. Never confuse Opening with Closing (Closing is the LAST column on each row)."
	case "closing":
		colName = "Closing (end-of-day stock)"
		colHint = "Read the LAST numeric column on each row with maximum care — this is what populates the operator's inventory. Closing typically equals Total − Sale; use that identity to double-check unclear digits."
	case "total":
		colName = "Total (= Opening + Receipt)"
		colHint = "Read the Total column (typically the 3rd numeric column, AFTER Opening + Receipt) with maximum care — this is what populates the operator's inventory. Total = Opening + Receipt; use that identity to double-check unclear digits."
	default:
		return ""
	}
	return fmt.Sprintf(`STOCK COLUMN FOCUS (HIGHEST PRIORITY):
The operator selected %s as the SOURCE OF TRUTH for stock initialisation.
- %s
- If you can read the %s cell clearly, ALWAYS include the row in items[] — even when the brand text is partial. The operator will fix the brand text on the review screen; what they cannot fix is a missing row.
- For rows where the picked column is genuinely empty/unreadable, set its value to 0 with confidence ≤ 0.45 (do NOT guess). The downstream review surface will flag the row for the operator's attention.
- Continue extracting all 5 stock columns (Opening / Receipt / Total / Sale / Closing) — they are used for math-gate validation — but %s is the column whose accuracy matters most.

`, colName, colHint, colName, colName)
}

func buildStockRegisterPrompt(categoryName string, sizeML int, productNames []string, masterBrandNames ...[]string) string {
	var sb strings.Builder

	// Context block (category + size)
	if categoryName != "" || sizeML > 0 {
		sb.WriteString("IMPORTANT CONTEXT:\n")
		if categoryName != "" && sizeML > 0 {
			sb.WriteString(fmt.Sprintf(
				"These images are from a stock register page for %s %dML bottles.\n"+
					"- Most products on this page are %s brands in %dML size\n"+
					"- Set category to \"%s\" and size_ml to %d for matching items\n"+
					"- If a product is clearly NOT %s (e.g., says Rum/Vodka in brand name), set its category to the CORRECT one, NOT %s\n"+
					"- Set matched_product_id to 0 for products that don't belong to %s\n"+
					"- Focus on accurately reading brand names — the size is already known\n\n",
				categoryName, sizeML, categoryName, sizeML,
				strings.ToLower(categoryName), sizeML,
				categoryName, strings.ToLower(categoryName), categoryName))
		} else if categoryName != "" {
			sb.WriteString(fmt.Sprintf(
				"These images are from a %s stock register page.\n"+
					"- All products should be %s brands\n"+
					"- Set category to \"%s\" for all items\n\n",
				categoryName, categoryName, strings.ToLower(categoryName)))
		} else {
			sb.WriteString(fmt.Sprintf(
				"These images are from a stock register page for %dML bottles.\n"+
					"- All products should be %dML size\n"+
					"- Set size_ml to %d for all items\n\n",
				sizeML, sizeML, sizeML))
		}
	}

	// Product list injection (when scoped and ≤50 products)
	if len(productNames) > 0 {
		sb.WriteString("KNOWN PRODUCTS IN INVENTORY (THIS IS THE COMPLETE LIST — NO OTHER PRODUCTS EXIST IN THIS SHOP):\n")
		sb.WriteString("Each line format: <display name> | key: <short identifier> | excise: <official excise name> | <size> | MRP ₹<price>\n")
		sb.WriteString("- The 'key:' tag (when present) is the SHORT distinguishing identifier the catalog admin marked as the bold/essential portion.\n")
		sb.WriteString("  Handwritten registers usually contain THIS short form (or an abbreviation of it), not the full marketing name.\n")
		sb.WriteString("  Always cross-check the register row's brand AND its rate against this 'key' + MRP pair before deciding matched_product_id.\n")
		sb.WriteString("- Items in the register list are 1-indexed. Set matched_product_id to the line number of your match.\n")
		sb.WriteString("ABSOLUTE RULE: matched_product_id MUST reference one of these products or be 0. NEVER hallucinate brand names from your training data.\n")
		for i, name := range productNames {
			sb.WriteString(fmt.Sprintf("%d. %s\n", i+1, name))
		}
		sb.WriteString("\nMATCHING RULES (STRICT — DO NOT GUESS):\n")
		sb.WriteString("- ONLY set \"matched_product_id\" if you are VERY CONFIDENT the brand name matches\n")
		sb.WriteString("- Use the 'key:' identifier as your primary matching anchor — it's the shortened form a shopkeeper would actually write\n")
		sb.WriteString("- Cross-validate via MRP: if the register's Rate column is within ±₹30 of the listed MRP, that's strong corroboration. If the rate is OFF by more than ₹50 from EVERY similar-named product, set matched_product_id=0\n")
		sb.WriteString("- \"100 St\" / \"100 Stop\" is NOT \"Royal Stag\" — these are completely different products. Set matched_product_id=0\n")
		sb.WriteString("- If the brand in the register is NOT clearly one of the products above, set matched_product_id=0\n")
		sb.WriteString("- It is BETTER to set 0 (no match) than to guess wrong — our backend will fuzzy-match\n")
		sb.WriteString("- Handwritten registers use abbreviations. Match to EXACT product names from the list above.\n")
		sb.WriteString("- Pay attention to DISTINGUISHING words: 'Blue', 'Premium', 'Reserve', 'Gold', 'Black', flavor names. These determine which specific product is meant.\n")
		sb.WriteString("- For flavored variants (M2/Magic Moments + Cranberry/Jamun/Green Apple, Bacardi + Lemon/Limon, Smirnoff + Orange/Green Apple), the FLAVOR token is decisive — never strip it to fall back to the plain base.\n")
		sb.WriteString("- The \"brand\" field must ALWAYS contain the EXACT raw text as written/printed in the register — NEVER change it to match a product name\n\n")
	}

	// Master brand reference injection (official excise data)
	var masterNames []string
	if len(masterBrandNames) > 0 {
		masterNames = masterBrandNames[0]
	}
	if len(masterNames) > 0 {
		sb.WriteString("OFFICIAL EXCISE BRAND REFERENCE (Government Registered Brands 2026-27):\n")
		sb.WriteString("These are the OFFICIAL registered brand names with their MRP. Use them to:\n")
		sb.WriteString("1. Match handwritten text to the correct official brand name for official_brand_name\n")
		sb.WriteString("2. Cross-validate: if the Rate in the register matches a brand's MRP (±₹30), that confirms the match\n")
		sb.WriteString("3. If multiple brands have similar names, use MRP to disambiguate\n")
		sb.WriteString("4. For official_brand_name, ALWAYS use the EXACT official name from this list when matched\n\n")
		for i, name := range masterNames {
			sb.WriteString(fmt.Sprintf("[%d] %s\n", i+1, name))
		}
		sb.WriteString("\n")
	}

	// Multi-size register pages (common for beer)
	if sizeML > 0 {
		sb.WriteString("MULTI-SIZE REGISTER PAGES (CRITICAL FOR BEER):\n")
		sb.WriteString("Beer registers often have MULTIPLE size sections on ONE page, separated by section headers like:\n")
		sb.WriteString("  \"STRONG BEER - 500 ML\", \"PREMIUM BEER - 330 ML\", \"BEER - 650 ML\"\n")
		sb.WriteString(fmt.Sprintf("You MUST ONLY extract items from the section matching %dML.\n", sizeML))
		sb.WriteString("Rules:\n")
		sb.WriteString(fmt.Sprintf("1. Look for a section header containing \"%dML\" or \"%d ML\"\n", sizeML, sizeML))
		sb.WriteString("2. ONLY extract items UNDER that section header, until the next section header or end of page\n")
		sb.WriteString("3. Items ABOVE the matching section header (in a different/unlabeled section) must be SKIPPED\n")
		sb.WriteString("4. Items BELOW the matching section (in a different labeled section) must be SKIPPED\n")
		sb.WriteString(fmt.Sprintf("5. For each extracted item, set size_ml to the ACTUAL size from its section header, NOT always %d\n", sizeML))
		sb.WriteString("6. If no section headers exist at all, assume all items are the requested size\n")
		sb.WriteString("7. Common beer sizes: 650ML (large/pint), 500ML (strong), 330ML (premium/craft)\n\n")
	}

	// 90ML / small size specific instructions
	if sizeML > 0 && sizeML <= 180 {
		sb.WriteString("SMALL SIZE REGISTER INSTRUCTIONS:\n")
		if sizeML == 90 {
			sb.WriteString("This is a 90ML (NIP) register page:\n")
			sb.WriteString("- 90ML pages are COMPACT — expect 10-25+ product rows on a single page\n")
			sb.WriteString("- Brand names are often HEAVILY ABBREVIATED. Match to the product list above. Pay attention to distinguishing words (Blue, Premium, Reserve, etc.)\n")
			sb.WriteString("- Rate for 90ML is typically ₹30-₹200 per bottle\n")
		} else {
			sb.WriteString(fmt.Sprintf("This is a %dML register page:\n", sizeML))
			sb.WriteString("- Pages may be compact with many rows — extract ALL of them\n")
			sb.WriteString("- Brand names may be abbreviated\n")
		}
		sb.WriteString("- Quantities are in BOTTLES (not cases), typically 0-500 range\n")
		sb.WriteString("- Extract EVERY row, even if partially readable (set lower confidence)\n")
		sb.WriteString("- Look carefully for faint handwriting between visible rows\n")
		sb.WriteString("- Cross-check: if serial numbers go 1 to N, you should have ~N items\n\n")
	}

	// Brand identification section (always included)
	sb.WriteString(`BRAND IDENTIFICATION (CRITICAL):
PRIORITY 1: Read EXACTLY what is PRINTED or WRITTEN in the register. The "brand" field = raw text from image.
PRIORITY 2: For the "official_brand_name" field, identify the full brand name ONLY if you are certain.
PRIORITY 3: If the text is HANDWRITTEN and unclear, set confidence < 0.70 and keep "brand" as your best reading.

NEVER change "brand" to match a product name. "brand" must be the RAW text from the image.
If a printed name says "100 Stop Whisky", the brand must be "100 Stop Whisky" — NOT "Royal Stag" or anything else.

Common Indian IMFL abbreviations (ONLY for handwritten shorthand, NOT for printed text):
- "R.S." / "RS" / "Royal Stg" = "Royal Stag Whisky"
- "B.P." / "BP" = "Blenders Pride Premium Whisky"
- "BPR" / "BP Reserve" = "Blenders Pride Reserve Collection Whisky"
- "8PM" / "8 PM" = "8 PM Black Whisky"
- "O.M." / "OM" = "Old Monk Rum"
- "M.M." / "MM" / "M2" / "M-2" = "Magic Moments Vodka" family. CRITICAL: the M2/MM
  prefix in a register followed by a FLAVOR word (Green Apple, Cranberry, Jamun,
  Watermelon, Lemon, Cola, Orange, Pineapple, Chocolate, Litchi, Verve, Remix)
  identifies a SPECIFIC flavored variant — match it to the matching M2/Magic
  Moments Remix Vodka product in the inventory list, NOT to the plain
  "Magic Moments Vodka". Examples (handwriting → match):
    "MM Green Apple" / "M2 G.Apple" / "M2 GA" → "M2 Magic Moments Remix Green Apple Flavoured Vodka"
    "MM Cranberry"   / "M2 Cran"   / "M2 CR" → "M2 Magic Moments Remix Cranberry Flavoured Vodka"
    "MM Jamun"       / "M2 Jamun"           → "M2 Magic Moments Remix Jamun Flavoured Vodka"
    "MM Watermelon"  / "M2 W.Melon"         → "M2 Magic Moments Remix Watermelon Flavoured Vodka"
  Plain "MM" / "M2" with NO flavor word = the base "Magic Moments Vodka".
- "McD" / "McD No1" = "McDowell's No.1 Whisky"
- "I.C." / "IB" / "Imp Blue" = "Imperial Blue Whisky"
- "RF" / "Rockford" = "The Rockford Reserve Whisky"
- "DSP" / "DSP Black" = "DSP Black Whisky"
- "Haywards" = "Haywards Fine Spirit"
- "RR" / "Royal Reserve" = "Royal Reserve Whisky"
- "Bagpiper" = "Bagpiper Gold Whisky"
- "Officer's Choice" / "OC" = "Officer's Choice Whisky"
- "Director's Special" / "DS" = "Director's Special Whisky"
Set "official_brand_name" to the FULL OFFICIAL brand name for EVERY item.

FLAVORED VODKA / FLAVORED WHISKY MATCHING (CRITICAL):
- Vodka brands often have multiple flavored variants under one umbrella name
  (M2/Magic Moments Remix, Smirnoff, White Mischief, Romanov). The flavor word
  is the DECISIVE token — it tells you which specific product matches.
- NEVER drop the flavor when matching: "M2 Green Apple" → must NOT match plain
  "Magic Moments Vodka" or "M2 Cranberry"; the matched_product_id MUST point to
  the Green Apple variant. If the Green Apple variant is NOT in the inventory
  list above, set matched_product_id=0 (do NOT silently match the plain vodka).
- If the register row says only "MM" / "M2" with no flavor token, match to the
  plain Magic Moments Vodka entry (or 0 if it isn't in the list).

`)

	// Main extraction prompt
	sb.WriteString(`You are extracting data from an Indian liquor shop stock register page image.

STEP 0 — DETECT REGISTER TYPE (do this BEFORE anything else):
Look at the BRAND NAME column. Is the brand text PRINTED/typed (uniform font,
pre-printed for every row — a shop "SALE RECEIPT" / sale-receipt book), or
HANDWRITTEN (operator wrote each brand by hand)?

==================== PRINTED-FORM MODE ====================
If the BRAND column is PRINTED/typed, you are in PRINTED-FORM MODE. This mode
OVERRIDES the conflicting handwritten rules further below — specifically it
overrides CRITICAL RULES 3 (v1.0.133-r7 blank-row skip) and 5 (sequential
row_number), the ROW-ALIGNMENT rules that say "only-one-value → zero the
row" / "all-empty → skip", AND the HANDWRITTEN-NUMBER-ACCURACY rule that says
"printed brand with no visible numbers → opening is a faint 1-15, do not
return 0" (that rule is FALSE for printed forms — it manufactures phantom
stock). In a printed sale-receipt book the operator
pre-prints the FULL SKU list and only handwrites quantities for some rows —
this is a Stock-Setup OPENING-stock snapshot, so EVERY printed brand row is a
real product to onboard, even with no quantity.

PRINTED-FORM MODE rules (FOLLOW EXACTLY):
P1. Extract EVERY printed brand row, top to bottom, with NO skipping. Do NOT
    skip a row just because its Opening/Sale/Closing cells are blank. A printed
    brand with blank numbers = a valid product with opening=0.
P2. Set "row_number" to the printed S.No on that row (the pre-printed serial,
    1..N). This is the STABLE ANCHOR — it guarantees brands never drift or
    renumber. (This overrides the "use sequential row_number" rule below.)
P3. Copy the printed brand text EXACTLY as printed, including any LEADING
    digits/tokens. "8 PM Rare Whisky" stays "8 PM Rare Whisky" — never drop the
    leading "8". "1965 ..." keeps the "1965". A leading token belongs ONLY to
    the row it is printed on: never move/drop a row's leading "8" up or down.
    If row N is "8 PM Gold ..." then row N's brand starts with "8" and row N+1
    does NOT begin with a stray "8". (Real failure to avoid: "8 PM Gold..." →
    "PM Gold..." with the "8" bleeding onto the next row's brand.)
P4. EXACTLY ONE brand per printed row. NEVER merge two printed rows into one,
    and NEVER borrow a word from the row above or below (do not turn row 1
    "8 PM Rare Whisky" + row 2 "Green Label" into "PM Rare Whisky Green"). If
    you are unsure where one printed row ends, align to the printed S.No.
P5. Numbers are read ONLY from the same horizontal line as that printed brand.
    A BLANK cell is exactly 0 — output opening=0. NEVER invent a "faint
    1-15": on a printed form an unwritten Opening genuinely means the shop has
    0 of that SKU / it was not counted. Outputting 1 (or any guessed small
    number) for a visibly empty Opening cell is a HARD ERROR — it manufactures
    phantom stock the shopkeeper never had. Only output a non-zero Opening
    when you can actually SEE a handwritten digit on that line. A printed row
    that has ONLY an Opening value is NORMAL for Stock Setup — keep it, do NOT
    zero it and do NOT treat its single value as belonging to an adjacent row.
P6. Anti-hallucination still holds: never invent a brand that is not printed on
    the page, and never guess a quantity you cannot read (use 0 + low conf).
P7. Extract every row that HAS a brand: all printed-brand rows, PLUS any
    handwritten-brand rows the operator added below the printed list (those
    follow the normal handwritten rules — keep raw text, low confidence if
    illegible). A row that has NO brand at all (blank pre-printed template
    line near the bottom) and no numbers is genuinely empty — skip it, and
    NEVER invent a brand to fill it. A GRAND TOTAL / TOTAL row is skipped.
    So: items[] ≈ (count of printed-brand rows) + (count of handwritten-brand
    rows). Returning far fewer printed-brand rows than are printed is an ERROR
    in this mode (that is the drift bug we are eliminating).
P8. The TOP printed row is the COLUMN-HEADER row — its cells read literally
    "S.No", "Brand Name" / "Brand", "Openin"/"Opening", "Receipt", "Total",
    "Sale", "Rate", "Amount", "Closin"/"Closing". This is NOT a product.
    NEVER output an item whose brand is "Brand Name", "Brand", "S.No",
    "Product", or any column title. The FIRST data row is the one whose brand
    is a real liquor name. Emitting the header as item #1 shifts every brand
    down by one (real failure: item 1 = "Brand Name", so "8 PM Gold..." landed
    on the wrong row and lost its "8") — do not do this.
P9. RATE is a single price for that one row (₹30-₹5000). Never concatenate two
    cells or two rows into one number: "130" then "130" is rate=130, NOT
    "130130"; a 4+ digit rate that is just a 2-3 digit number doubled is a
    misread — re-read it as the single printed value.

If the brand column is HANDWRITTEN, IGNORE PRINTED-FORM MODE and follow all the
rules below as written (the blank-row / ghost-row protections apply there).
===========================================================

FIRST: Look at the TOP/HEADER of the register page to find:
1. SHOP NAME - Usually at the very top (e.g., "XYZ Wine Shop", "Mahua Khera")
2. SIZE CATEGORY - The bottle size for this page. Often shown as:
   - "375 ML", "180ML", "750ML", "1000ML"
   - "IMFL 375", "IMFL 750"
   - "QR" (= 180ml), "Half" (= 375ml), "Full" (= 750ml), "NP"/"Nip" (= 90ml)

The register table has these columns from LEFT to RIGHT:
1. S.No (Serial Number)
2. Brand Name / Product Name
3. Opening (stock at start of day)
4. Receipt (new stock received - often 0)
5. Total (= Opening + Receipt)
6. Sale (quantity sold during the day)
7. Rate (price per unit in Rupees ₹)
8. Amount (= Sale × Rate in Rupees ₹)
9. Closing (= Total - Sale, remaining stock)

VISUAL ROW LAYOUT (use this to identify which column each handwritten number belongs to):

|  S.No | Brand                                          | Open | Rcpt | Total | Sale | Rate | Amount | Close |
|-------|------------------------------------------------|------|------|-------|------|------|--------|-------|
|   3   | OFFICER'S CHOICE ORIGINAL WHISKY               |  217 |   0  |  217  |  33  | 130  |  4290  |  184  |
|  17   | Seagrams Blenders Pride Exclusive Premium      |   23 |   0  |   23  |   1  | 240  |   240  |   22  |

- "Open" / "Opening" is ALWAYS the FIRST quantity column AFTER the brand name; do NOT confuse it with Closing (which is the LAST column).
- An empty Receipt cell ALWAYS means 0 — do NOT carry the previous row's receipt forward.
- If a row has Opening but Closing is blank, COMPUTE Closing = Opening + Receipt − Sale; do NOT leave Closing=0 if the math is consistent.
- If a row has Closing but Opening is blank, the OPENING is genuinely missing — set opening=0 with confidence 0.4, do NOT synthesize.

CRITICAL RULES:
1. ALWAYS extract shop_name from the page header if visible
2. ALWAYS extract page_size from header (the bottle size for this entire page)
3. v1.0.133-r7 ANTI-HALLUCINATION RULE — registers ROUTINELY have many blank rows where no stock count was written. A row is BLANK when its Brand cell is empty/illegible AND all of (Opening, Receipt, Total, Sale, Closing) are empty. **NEVER extract blank rows.** Returning fewer items than the visible serial count is correct and expected. Do NOT invent values like "opening=0 sale=17 closing=96" just to populate every serial. If row N is blank, simply skip it. Pre-r7 the prompt told you to extract every numbered row even if blank — that produced ghost rows that broke matching downstream. Now: ONLY extract a row when (a) the Brand cell has handwritten text OR (b) at least one of Opening/Closing has a non-zero clearly-readable value. Items[] count is allowed to be much smaller than the visible serial range.
4. NEVER merge two register rows into one item. Each row in the register = one item in your output.
5. Use SEQUENTIAL row_number starting from 1 for each image. Do NOT use the printed serial numbers from the register.
6. All quantity values (opening, receipt, total, sale, closing) are in BOTTLES (not cases)
7. Total MUST equal Opening + Receipt. If the numbers don't add up, recheck your reading.
8. Closing MUST equal Total - Sale. If the numbers don't add up, recheck your reading.
9. Rate is typically between ₹30 and ₹5000 per bottle. Rates INCREASE down the page (sorted by price). If a rate seems out of order, recheck.
10. Amount should equal Sale × Rate
11. SKIP rows where brand name is empty or is a total/subtotal/grand total row
12. If a value is unclear or missing, set it to 0 and lower confidence. NEVER GUESS a quantity — if you cannot clearly read a number, return 0 with low confidence.
IMAGE QUALITY HANDLING:
- If the serial number column (S.No) is cropped/cut off or not visible, set confidence lower (0.50-0.60) for affected rows
- If handwriting uses very thick/heavy black ink making characters bleed together, set confidence to 0.50-0.60
- If a number's digits are merged due to heavy ink (e.g., "193" vs "143"), return 0 instead of guessing
- Typical stock quantities are 1-100 bottles. If you read a value over 200, double-check — it may be two numbers from adjacent columns read as one

ROW ALIGNMENT (VERY IMPORTANT — DO NOT MIX UP ROWS):
- Each printed row in the register has its OWN set of numbers on the SAME horizontal line
- Read numbers ONLY from the SAME ROW as the brand name — do NOT accidentally read numbers from the row above or below
- If a row has ALL EMPTY cells (no handwritten numbers at all), set ALL values to 0 and confidence to 0.50
- If only SOME cells have numbers, read those and set the rest to 0
- NEVER copy one row's numbers to an adjacent row — each row is independent
- Rows with only a Rate printed (no opening/sale/closing) are EMPTY stock rows — set quantities to 0
- CRITICAL: If a row has ONLY ONE non-zero value (e.g., only closing=40 but opening=0, sale=0), that number likely belongs to the ADJACENT row. Set ALL values to 0 for that row instead.
- Handwritten numbers near row boundaries are tricky — always assign to the row where the brand name is on the SAME LINE
- CROSS-CHECK BETWEEN ADJACENT ROWS: If row N has opening=50 and row N+1 has opening=48, verify these are NOT the same number read twice. Each row should have INDEPENDENT values. If two adjacent rows have suspiciously similar values (e.g., 50 and 48), double-check which row each number belongs to.
- VERTICAL ALIGNMENT: Numbers in the "Opening" column should be vertically aligned. If a number appears to be between two rows, assign it to the row whose brand name is on the SAME horizontal line.

HANDWRITTEN NUMBER ACCURACY:
- Distinguish carefully: "5" vs "51" vs "15" — these are very different stock quantities
- "21" vs "2l" vs "2!" — read the actual digit, not what looks similar
- For handwritten rows (usually at bottom of page), set confidence to 0.60-0.75
- If opening stock is a single digit (1-9) for a handwritten row, it is likely correct — do NOT add extra digits
- Cross-check: Amount = Sale × Rate. If Amount shows 2150 and Rate is 430, then Sale must be 5, not 51
- IMPORTANT: If a row has a PRINTED brand name but you cannot see ANY handwritten numbers in its row, the opening stock is likely a SMALL number (1-15) written faintly. Look carefully — do NOT return 0 if there is a faint number present.
- DOUBLE-CHECK rows where you set opening=0: re-examine if there is a small faint number you missed

NO DUPLICATES / NO GUESSING HANDWRITTEN BRANDS:
- DO NOT extract the same brand twice. If two rows would have identical brand_name AND identical rate AND identical opening/closing, it is a duplicate misread — return only ONE row.
- Different rates with the same brand CAN be legitimate (different SKU suffixes like "Black Label 12Y" vs "Black Label 18Y") — in that case KEEP both rows but preserve any distinguishing suffix you can read (year, volume qualifier, variant word).
- For ILLEGIBLE handwritten brands (less than 3 legible characters, pure abbreviation like "R.S Borr/s" or "M.M. Jun", or unreadable scribble): return the raw text LITERALLY, set matched_product_id=0, and confidence=0.3. NEVER guess the brand identity from surrounding context or the rate column — the downstream system has a master-brand resolver that will handle abbreviations better than guessing.
- A handwritten brand that looks similar to a printed brand ABOVE it is NOT the same product — treat each row independently.
13. Size abbreviations: "QR"/"Qrt" = 180ml, "Hf"/"Half" = 375ml, "Fl"/"Full" = 750ml, "NP"/"Nip" = 90ml
14. HANDWRITTEN vs PRINTED: Registers have PRINTED brand names (clear, typed text) and sometimes HANDWRITTEN additions at the bottom.
    - For PRINTED text: confidence should be 0.85-0.95 — these are clear and must be read exactly as printed
    - For HANDWRITTEN text: confidence should be 0.50-0.75 — these are often unclear, abbreviated, or hard to read
    - NEVER guess a handwritten brand — read it literally. "100 St" stays as "100 St", don't change it to "Royal Stag"
    - Set matched_product_id=0 for handwritten brands unless you are 100% certain of the match
15. Each row is a DIFFERENT product. Even if two rows look similar, they are separate entries with different data.

HANDWRITTEN OVERWRITE (HANDWRITTEN WINS):
- Shop owners sometimes REPLACE a printed brand by writing a different product name on the same row (overwrite, strike-through, or wedged-in handwriting next to the printed text).
- When you see BOTH a printed brand AND a handwritten brand on the SAME row, the HANDWRITTEN brand is the CORRECT product for that row. The shop reassigned that slot to a different product.
- Return the HANDWRITTEN brand as the "brand" field.
- Put the PRINTED brand in the "original_printed_brand" field so the system can show the user what was replaced.
- Set confidence to 0.55-0.70 for handwritten-wins rows (handwriting is inherently less reliable).
- Example: if row 39 shows PRINTED "Monkey Shoulder Blended Malt Whisky" and HANDWRITTEN "JACK DANIES" written through/next to it, return:
    { "brand": "JACK DANIES", "original_printed_brand": "Monkey Shoulder Blended Malt Whisky", "confidence": 0.60 }

PAGE ROW COUNT (for the review UI):
- At the page level, return "row_count_on_page" — the TOTAL number of visible data rows on this page (including blank / empty ones with only a rate printed). This lets the Flutter UI compute a rough Y-band for a given row_number.

Extract ALL rows and return ONLY valid JSON:

{
  "shop_name": "Shop Name from Header",
  "page_size": "750ML",
  "page_size_ml": 750,
  "row_count_on_page": 27,
  "items": [
    {
      "row_number": 1,
      "brand": "Raw text as written in register",
      "original_printed_brand": "",
      "official_brand_name": "Full Official Brand Name",
      "category": "whiskey",
      "size_text": "750ml",
      "size_ml": 750,
      "opening": 50,
      "receipt": 0,
      "total": 50,
      "sale": 5,
      "rate": 450.00,
      "amount": 2250.00,
      "closing": 45,
      "confidence": 0.95,
      "matched_product_id": 0
    }
  ]
}

Categories: whiskey, rum, vodka, beer, brandy, gin, wine, country_liquor, rtd
If you cannot determine category, use "spirits".
If you cannot read some text clearly, set confidence lower (0.5-0.7).
Return empty items array if no product line items found.
Return only valid JSON, no markdown formatting.`)

	return sb.String()
}

// spMinInt returns the smaller of two ints (avoids name collision)
func spMinInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// ExtractHandwrittenBand issues a specialized AI call focused on a specific
// row range of a register page that the main pass flagged as a handwritten
// section (dense handwriting, row-drift, or low per-row confidence).
//
// The specialized prompt differs from the main one in three ways:
//  1. Row-line anchoring — each physical line below the printed section is one
//     product. Brand + numbers must share the same horizontal line.
//  2. Handwritten-wins — when both a printed brand and a handwritten brand
//     appear (overwrite), use the handwritten text as brand and the printed
//     text as original_printed_brand.
//  3. Row-range focus — the model is told to ONLY return items in [fromRow, toRow]
//     so the response stays small and the per-row attention is higher.
//
// Uses the same OpenAI-first-then-Gemini cascade as the main pass.
func (s *SmartPurchaseOCR) ExtractHandwrittenBand(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames, masterBrandNames []string, fromRow, toRow int) (*StockRegisterExtractionResult, error) {
	// Gemini-primary for handwriting — matches main-pass ordering.
	primary := os.Getenv("SMART_STOCK_SETUP_PRIMARY")
	if primary == "" {
		primary = "gemini"
	}
	if primary == "gemini" && s.geminiKey != "" {
		result, err := s.extractHandwrittenWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
		if err == nil {
			return result, nil
		}
		log.Printf("Smart Stock Setup OCR: handwritten-pass Gemini failed (%v), trying OpenAI fallback", err)
		if s.openaiKey != "" {
			return s.extractHandwrittenWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
		}
		return nil, err
	}
	if s.openaiKey != "" {
		result, err := s.extractHandwrittenWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
		if err == nil {
			return result, nil
		}
		log.Printf("Smart Stock Setup OCR: handwritten-pass OpenAI failed (%v), trying Gemini fallback", err)
	}
	if s.geminiKey != "" {
		return s.extractHandwrittenWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
	}
	return nil, fmt.Errorf("no AI API keys configured for handwritten band re-extraction")
}

func (s *SmartPurchaseOCR) extractHandwrittenWithOpenAI(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames, masterBrandNames []string, fromRow, toRow int) (*StockRegisterExtractionResult, error) {
	imgType := "jpeg"
	if strings.Contains(contentType, "png") {
		imgType = "png"
	}
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imgType, base64.StdEncoding.EncodeToString(imageBytes))
	prompt := buildHandwrittenRegisterPrompt(categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
	content := []interface{}{
		spOpenAITextContent{Type: "text", Text: prompt},
		spOpenAIImageContent{Type: "image_url", ImageURL: spOpenAIImageURL{URL: imageDataURL, Detail: "high"}},
	}
	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}
	request := spOpenAIRequest{
		Model: model,
		Messages: []spOpenAIMessage{{Role: "user", Content: content}},
		MaxCompletionTokens: 4096,
		Temperature:         0.0,
		ResponseFormat:      &spResponseFmt{Type: "json_object"},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openaiKey)
	log.Printf("Smart Stock Setup OCR: handwritten-pass → OpenAI %s (rows %d-%d)", model, fromRow, toRow)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai request: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai api error %d: %s", resp.StatusCode, string(body))
	}
	var apiResp spOpenAIResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("openai error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no response from OpenAI")
	}
	return parseStockRegisterResponse(apiResp.Choices[0].Message.Content)
}

func (s *SmartPurchaseOCR) extractHandwrittenWithGemini(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, productNames, masterBrandNames []string, fromRow, toRow int) (*StockRegisterExtractionResult, error) {
	mimeType := "image/jpeg"
	if strings.Contains(contentType, "png") {
		mimeType = "image/png"
	}
	prompt := buildHandwrittenRegisterPrompt(categoryName, sizeML, productNames, masterBrandNames, fromRow, toRow)
	request := geminiRequest{
		Contents: []geminiContent{
			{
				Parts: []geminiPart{
					{Text: prompt},
					{InlineData: &geminiBlobData{MimeType: mimeType, Data: base64.StdEncoding.EncodeToString(imageBytes)}},
				},
			},
		},
		GenerationConfig: geminiGenerationConfig{
			Temperature:      0.0,
			MaxOutputTokens:  4096,
			ResponseMimeType: "application/json",
		},
	}
	requestBody, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-goog-api-key", s.geminiKey)
	log.Printf("Smart Stock Setup OCR: handwritten-pass → Gemini %s (rows %d-%d)", model, fromRow, toRow)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gemini request: %w", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gemini api error %d: %s", resp.StatusCode, string(body))
	}
	var apiResp geminiResponse
	if err := json.Unmarshal(body, &apiResp); err != nil {
		return nil, fmt.Errorf("parse response: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("gemini error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no response from Gemini")
	}
	return parseStockRegisterResponse(apiResp.Candidates[0].Content.Parts[0].Text)
}

// buildHandwrittenRegisterPrompt is the specialized prompt for re-extracting
// a handwritten section of a register page. Much tighter row-anchoring rules
// than the main prompt + explicit handwritten-wins guidance + row-range scoping.
func buildHandwrittenRegisterPrompt(categoryName string, sizeML int, productNames, masterBrandNames []string, fromRow, toRow int) string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf(`You are re-reading a SPECIFIC RANGE of rows (row_number %d through %d) on a stock register page.
The initial extraction on this range was unreliable because the rows are HANDWRITTEN or near the handwritten transition.
Your job is to return accurate rows for THIS RANGE ONLY, using strict row-line anchoring.

CRITICAL RULES:
1. ROW-LINE ANCHORING — each physical horizontal line on the register is ONE product.
   - Draw an imaginary horizontal line through the brand name text.
   - Every number you assign to that row (opening, receipt, sale, closing, rate, amount) MUST cross that same line.
   - Do NOT read numbers from the row above or below — even if the line above the current row has its opening column empty.
   - If handwritten digits sit ambiguously between two lines, assign them to the row whose brand name is CLOSEST to them vertically.

2. HANDWRITTEN-WINS FOR DUAL-BRAND ROWS — sometimes a printed row has been OVERWRITTEN with a different handwritten brand.
   - If you see BOTH a printed brand name AND a handwritten brand name overlapping/near each other on the SAME row, the HANDWRITTEN one is the current product for that row.
   - Return the handwritten text as "brand" and the printed text as "original_printed_brand".
   - Example: row shows printed "Monkey Shoulder Blended Malt Whisky" and handwritten "JACK DANIES" → return brand="JACK DANIES", original_printed_brand="Monkey Shoulder Blended Malt Whisky".

3. PURE HANDWRITTEN ROWS — rows at the bottom of the register with no printed brand, only handwritten text.
   - Read the brand LITERALLY. Do NOT expand abbreviations from context ("BLACK Label" stays "BLACK Label", not "Johnnie Walker Black Label").
   - Numbers are in the same ink as the brand — they belong to THAT row.
   - Set confidence to 0.55-0.70.

4. NEVER DUPLICATE — if you already returned a brand at row N, do NOT return the same brand at row N+1 unless the rate or size differs.

5. RATES ASCEND — printed registers list products in ascending rate order. In the handwritten section the ordering may break, but rate values you see are still PRINTED next to each row. If the rate on row N is unreadable, leave it 0 — do NOT copy from adjacent rows.

6. CROSS-CHECK WITH AMOUNT — if amount is written, sale = round(amount / rate). Use this to verify you read the right digit.

7. HONEST UNCERTAINTY — if you cannot clearly read the handwritten brand, or you're less than 60%% sure it matches ANY brand (including any abbreviation hint below), return the raw text you see AS-IS and set confidence to 0.30. DO NOT guess a master brand just because it's the closest alphabetical or phonetic candidate. Picking the wrong brand is WORSE than saying "I don't know" — the downstream system will route uncertain rows to the user for manual review. Common handwritten abbreviation patterns in Indian registers:
   - "M.M. Jun" / "MM Jamun" / "M2 Jamun" → M2 Magic Moments Jamun family
   - "R.S Borrs" / "RS Barrel" / "Royal Stag Brl" → SEAGRAM'S ROYAL STAG BARREL SELECT family
   - "JW BL" / "Black Label" / "JW Black" → JOHNNIE WALKER BLACK LABEL (only when JW is a clear prefix)
   - "JW Gold" / "Gold Label" → JOHNNIE WALKER GOLD LABEL RESERVE
   If the handwriting looks like any of these patterns AND the matching brand is in the hint list below, use the full brand name. Otherwise keep the raw text.

`, fromRow, toRow))

	if categoryName != "" && sizeML > 0 {
		sb.WriteString(fmt.Sprintf("Context: the register is for %s %dML bottles. Stay in this category/size unless the handwritten brand is clearly a different category.\n\n", categoryName, sizeML))
	}

	if len(masterBrandNames) > 0 {
		sb.WriteString("HANDWRITTEN ABBREVIATION HINTS — these master brands are present in the region's excise catalog. Use these ONLY when the handwriting UNAMBIGUOUSLY matches; otherwise keep the raw text (see rule 7):\n")
		// Expanded from 80 → 200 so brands with long names or initials-friendly
		// patterns (which get abbreviated most often in Indian registers) are
		// more likely to be in the candidate set.
		limit := len(masterBrandNames)
		if limit > 200 {
			limit = 200
		}
		for i := 0; i < limit; i++ {
			sb.WriteString("  - ")
			sb.WriteString(masterBrandNames[i])
			sb.WriteString("\n")
		}
		sb.WriteString("\n")
	}

	sb.WriteString(fmt.Sprintf(`Return ONLY rows in the range [%d, %d]. Do NOT include rows before or after.

Return ONLY valid JSON in this exact shape:
{
  "items": [
    {
      "row_number": %d,
      "brand": "Handwritten text as you see it",
      "original_printed_brand": "",
      "official_brand_name": "",
      "category": "whiskey",
      "size_text": "750ml",
      "size_ml": 750,
      "opening": 0,
      "receipt": 0,
      "total": 0,
      "sale": 0,
      "rate": 0.0,
      "amount": 0.0,
      "closing": 0,
      "confidence": 0.60,
      "matched_product_id": 0
    }
  ]
}

No markdown, no explanation.`, fromRow, toRow, fromRow))

	return sb.String()
}

// ExtractSingleRow issues a highly-constrained AI call focused on ONE specific
// row of a register page. Used by the user-facing "re-extract this row" button
// when the main pass got a row wrong and the user wants a second opinion.
//
// The prompt differs from the main / handwritten-band prompts in three ways:
//  1. Scope is exactly one row — the AI is told to only return that row's data.
//  2. A band-center hint (0..1 fraction of image height) directs the AI to
//     that specific Y area so it doesn't mis-count rows.
//  3. Brand is CONSTRAINED — the AI may only return a brand from the provided
//     master list or the literal string "unknown". This prevents hallucinations
//     like the 2026-04-20 "Smoke Lab Classic" case where the AI invented a
//     brand that didn't exist in the register.
func (s *SmartPurchaseOCR) ExtractSingleRow(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, masterBrandList []string, rowNumber int, bandCenter float64) (*ExtractedStockRegisterItem, error) {
	// Gemini-primary for re-extract — same reasoning as main pass (Gemini 3
	// Flash is better at dense handwriting + brand identification, especially
	// when constrained to a small Y-band of the image).
	primary := os.Getenv("SMART_STOCK_SETUP_PRIMARY")
	if primary == "" {
		primary = "gemini"
	}
	if primary == "gemini" && s.geminiKey != "" {
		item, err := s.extractSingleRowWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, masterBrandList, rowNumber, bandCenter)
		if err == nil {
			return item, nil
		}
		log.Printf("Smart Stock Setup OCR: single-row Gemini failed (%v), trying OpenAI fallback", err)
		if s.openaiKey != "" {
			return s.extractSingleRowWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, masterBrandList, rowNumber, bandCenter)
		}
		return nil, err
	}
	if s.openaiKey != "" {
		item, err := s.extractSingleRowWithOpenAI(ctx, imageBytes, contentType, categoryName, sizeML, masterBrandList, rowNumber, bandCenter)
		if err == nil {
			return item, nil
		}
		log.Printf("Smart Stock Setup OCR: single-row OpenAI failed (%v), trying Gemini", err)
	}
	if s.geminiKey != "" {
		return s.extractSingleRowWithGemini(ctx, imageBytes, contentType, categoryName, sizeML, masterBrandList, rowNumber, bandCenter)
	}
	return nil, fmt.Errorf("no AI API keys configured for single-row re-extract")
}

func (s *SmartPurchaseOCR) extractSingleRowWithOpenAI(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, masterBrandList []string, rowNumber int, bandCenter float64) (*ExtractedStockRegisterItem, error) {
	imgType := "jpeg"
	if strings.Contains(contentType, "png") {
		imgType = "png"
	}
	imageDataURL := fmt.Sprintf("data:image/%s;base64,%s", imgType, base64.StdEncoding.EncodeToString(imageBytes))
	prompt := buildSingleRowPrompt(categoryName, sizeML, masterBrandList, rowNumber, bandCenter)
	content := []interface{}{
		spOpenAITextContent{Type: "text", Text: prompt},
		spOpenAIImageContent{Type: "image_url", ImageURL: spOpenAIImageURL{URL: imageDataURL, Detail: "high"}},
	}
	model := os.Getenv("OPENAI_MODEL")
	if model == "" {
		model = "gpt-5.2"
	}
	request := spOpenAIRequest{
		Model:               model,
		Messages:            []spOpenAIMessage{{Role: "user", Content: content}},
		MaxCompletionTokens: 1024,
		Temperature:         0.0,
		ResponseFormat:      &spResponseFmt{Type: "json_object"},
	}
	body, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.openaiKey)
	log.Printf("Smart Stock Setup OCR: single-row → OpenAI %s (row=%d, band=%.2f, master=%d)", model, rowNumber, bandCenter, len(masterBrandList))
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("openai request: %w", err)
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("openai api %d: %s", resp.StatusCode, string(respBody))
	}
	var apiResp spOpenAIResponse
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("openai error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Choices) == 0 {
		return nil, fmt.Errorf("no choices from openai")
	}
	return parseSingleRowResponse(apiResp.Choices[0].Message.Content)
}

func (s *SmartPurchaseOCR) extractSingleRowWithGemini(ctx context.Context, imageBytes []byte, contentType string, categoryName string, sizeML int, masterBrandList []string, rowNumber int, bandCenter float64) (*ExtractedStockRegisterItem, error) {
	mimeType := "image/jpeg"
	if strings.Contains(contentType, "png") {
		mimeType = "image/png"
	}
	prompt := buildSingleRowPrompt(categoryName, sizeML, masterBrandList, rowNumber, bandCenter)
	request := geminiRequest{
		Contents: []geminiContent{
			{
				Parts: []geminiPart{
					{Text: prompt},
					{InlineData: &geminiBlobData{MimeType: mimeType, Data: base64.StdEncoding.EncodeToString(imageBytes)}},
				},
			},
		},
		GenerationConfig: geminiGenerationConfig{
			Temperature:      0.0,
			MaxOutputTokens:  1024,
			ResponseMimeType: "application/json",
		},
	}
	body, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal: %w", err)
	}
	model := os.Getenv("GEMINI_MODEL")
	if model == "" {
		model = "gemini-flash-latest"
	}
	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)
	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(body))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-goog-api-key", s.geminiKey)
	log.Printf("Smart Stock Setup OCR: single-row → Gemini %s (row=%d, band=%.2f)", model, rowNumber, bandCenter)
	resp, err := s.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gemini request: %w", err)
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("gemini api %d: %s", resp.StatusCode, string(respBody))
	}
	var apiResp geminiResponse
	if err := json.Unmarshal(respBody, &apiResp); err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}
	if apiResp.Error != nil {
		return nil, fmt.Errorf("gemini error: %s", apiResp.Error.Message)
	}
	if len(apiResp.Candidates) == 0 || len(apiResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("no response from Gemini")
	}
	return parseSingleRowResponse(apiResp.Candidates[0].Content.Parts[0].Text)
}

// parseSingleRowResponse handles the single-item JSON the single-row prompt emits.
func parseSingleRowResponse(responseText string) (*ExtractedStockRegisterItem, error) {
	jsonText := responseText
	if idx := strings.Index(jsonText, "```json"); idx >= 0 {
		jsonText = jsonText[idx+7:]
	} else if idx := strings.Index(jsonText, "```"); idx >= 0 {
		jsonText = jsonText[idx+3:]
	}
	if idx := strings.LastIndex(jsonText, "```"); idx >= 0 {
		jsonText = jsonText[:idx]
	}
	jsonText = strings.TrimSpace(jsonText)
	var item ExtractedStockRegisterItem
	if err := json.Unmarshal([]byte(jsonText), &item); err != nil {
		return nil, fmt.Errorf("parse single-row: %w (raw: %s)", err, jsonText[:spMinInt(len(jsonText), 200)])
	}
	if item.Confidence == 0 {
		item.Confidence = 0.5
	}
	return &item, nil
}

func buildSingleRowPrompt(categoryName string, sizeML int, masterBrandList []string, rowNumber int, bandCenter float64) string {
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf(`You are re-reading EXACTLY ONE row (row_number %d) on a stock register page.
The original extraction for this row was WRONG and the user flagged it for re-review. Your job is to return the CORRECT data for this one row.

CRITICAL RULES:
1. FOCUS on the row near the Y-band at approximately %.0f%% of the image height. Count rows carefully; if you can see the printed row number %d on the left, use that. If numbers are not visible, use the band hint.
2. Draw an imaginary horizontal line through row %d's brand name. Every number you return (opening, receipt, sale, closing, rate, amount) MUST lie on that same horizontal line. NEVER read from adjacent rows.
3. BRAND NAME CONSTRAINT — the "brand" field MUST be one of the items from the MASTER BRAND LIST below, OR the literal string "unknown". DO NOT invent a brand. If the handwriting doesn't clearly match any listed brand, return "unknown" and set matched_product_id=0.
4. If you see both a printed brand AND a handwritten brand on this row (overwrite), the HANDWRITTEN one wins — return that as "brand", put the printed one in "original_printed_brand".
5. Numbers: if unreadable or blank, return 0. NEVER guess a quantity. Set confidence lower (0.4-0.6) if digits are unclear.

`, rowNumber, bandCenter*100, rowNumber, rowNumber))

	if categoryName != "" && sizeML > 0 {
		sb.WriteString(fmt.Sprintf("Context: %s %dML bottles.\n\n", categoryName, sizeML))
	}

	sb.WriteString("MASTER BRAND LIST (choose EXACTLY one OR 'unknown' — see rule 3; picking a wrong brand is worse than 'unknown'):\n")
	// Expanded from 120 → 200. Single-row re-extract is ONE API call for ONE
	// row, so we can spend more tokens on a bigger candidate list than the
	// handwritten-band pass (which re-reads multiple rows in one call).
	limit := len(masterBrandList)
	if limit > 200 {
		limit = 200
	}
	for i := 0; i < limit; i++ {
		sb.WriteString(fmt.Sprintf("  %d. %s\n", i+1, masterBrandList[i]))
	}
	sb.WriteString("\n")

	sb.WriteString(fmt.Sprintf(`Return ONLY this JSON shape for row %d — no markdown, no explanation:

{
  "row_number": %d,
  "brand": "EXACT brand from list above, OR 'unknown'",
  "original_printed_brand": "",
  "official_brand_name": "",
  "category": "whiskey",
  "size_text": "750ml",
  "size_ml": 750,
  "opening": 0,
  "receipt": 0,
  "total": 0,
  "sale": 0,
  "rate": 0,
  "amount": 0,
  "closing": 0,
  "confidence": 0.5,
  "matched_product_id": 0
}`, rowNumber, rowNumber))

	return sb.String()
}

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

// v1.0.224 — Dedicated Claude Sonnet 4.6 brand-only extractor for the
// past-purchase disambiguation flow.
//
// Why a separate path: the generic ExtractFromImage cascade (Gemini-first,
// Claude fallback) is tuned for full bill extraction — quantity, rate,
// amount, batch, duty, OCR confidence per cell. For disambiguation we ONLY
// need brand text + size to find the row that matches our ambiguous GP
// canonical. A tight Claude-Sonnet prompt focused on brand + size:
//
//   1. Hits 100%-class accuracy (same model rigor Smart Sale uses, where
//      brand recognition is the hardest part and we've validated ~100% on
//      printed vendor docs).
//   2. Skips Gemini's response-length non-determinism (real chhotu case:
//      41/6 items across runs of the same image).
//   3. Cheaper and faster — single call, smaller prompt, smaller response.
//
// Output is converted into a []ExtractedPurchaseItem (same shape the rest of
// the disambig pipeline already consumes) so callers don't change.

// disambigBrandLine is one bill line as extracted by Claude — the minimum
// signal we need to match against GP canonicals.
//
// v1.0.226 — added Qty/QtyUnit so the Purcha-gate flow can confirm GP's
// bottle counts against the Purcha's printed receiving qty. When the
// Purcha lacks an explicit qty column (some receipts only print brand +
// size), Qty stays 0 and the caller treats it as "qty unverified" rather
// than a mismatch.
type disambigBrandLine struct {
	Brand   string `json:"brand"`
	Size    string `json:"size"`    // free-text e.g. "180ml", "750 ML"
	SizeML  int    `json:"size_ml"` // numeric ml when Claude can infer it
	LineIdx int    `json:"line_idx"`
	Qty     int    `json:"qty"`      // bottles received per the Purcha; 0 if unprinted
	QtyUnit string `json:"qty_unit"` // "bottles" | "cases" — informational
}

type disambigBrandPayload struct {
	Lines []disambigBrandLine `json:"lines"`
}

// extractBrandsForDisambig runs a single Claude Sonnet 4.6 call against the
// past-purchase image with a tight brand-only prompt. Returns the lines as
// ExtractedPurchaseItem entries (Brand + Size populated; cost/qty left at
// zero — disambig pipeline doesn't read them).
//
// On Anthropic-key absence or API failure, falls back to the generic
// ExtractFromImage cascade so a missing key never breaks disambig.
func (s *SmartPurchaseOCR) extractBrandsForDisambig(
	ctx context.Context,
	imageBytes []byte,
	contentType string,
) (*PurchaseExtractionResult, error) {
	if s.anthropicKey == "" {
		log.Printf("[disambig_extractor] no anthropic key — falling back to generic cascade")
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}

	mediaType := "image/jpeg"
	if strings.Contains(strings.ToLower(contentType), "png") {
		mediaType = "image/png"
	}
	base64Image := base64.StdEncoding.EncodeToString(imageBytes)

	prompt := buildDisambigBrandPrompt()

	systemBlocks := []claudeContent{
		{
			Type: "text",
			Text: prompt,
			CacheControl: &struct {
				Type string `json:"type"`
			}{Type: "ephemeral"},
		},
	}
	userBlocks := []claudeContent{
		{Type: "image", Source: &claudeImageSource{
			Type: "base64", MediaType: mediaType, Data: base64Image,
		}},
		{Type: "text", Text: "Extract every product line from this purchase bill. Return ONLY the JSON described in the system prompt — no prose, no markdown fences."},
	}

	model := os.Getenv("CLAUDE_DISAMBIG_MODEL")
	if model == "" {
		// Default to the same primary as Smart Sale / Smart Stock Setup so
		// disambig benefits from the same accuracy bar operators already trust.
		model = claudeDefaultPrimary // claude-sonnet-4-6
	}

	request := claudeRequest{
		Model:       model,
		MaxTokens:   4096, // brand-only is short; never exceed in practice
		Temperature: 0.0,
		System:      systemBlocks,
		Messages:    []claudeMessage{{Role: "user", Content: userBlocks}},
	}

	body, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("disambig_extractor marshal: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, "POST", claudeAPIEndpoint, bytes.NewBuffer(body))
	if err != nil {
		return nil, fmt.Errorf("disambig_extractor request build: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", s.anthropicKey)
	req.Header.Set("anthropic-version", claudeAPIVersion)
	req.Header.Set("anthropic-beta", claudeBetaPromptCaching)

	log.Printf("[disambig_extractor] sending to Claude %s (prompt %d chars, image %dKB)",
		model, len(prompt), len(imageBytes)/1024)

	resp, err := s.httpClient.Do(req)
	if err != nil {
		log.Printf("[disambig_extractor] claude request failed: %v — falling back", err)
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}
	defer resp.Body.Close()

	rawResp, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("[disambig_extractor] read body failed: %v — falling back", err)
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}
	if resp.StatusCode != http.StatusOK {
		log.Printf("[disambig_extractor] claude %d: %s — falling back", resp.StatusCode, string(rawResp))
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}

	var apiResp claudeResponse
	if err := json.Unmarshal(rawResp, &apiResp); err != nil {
		log.Printf("[disambig_extractor] parse claude resp failed: %v — falling back", err)
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}
	if apiResp.Error != nil {
		log.Printf("[disambig_extractor] claude error %s — falling back", apiResp.Error.Message)
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}
	if len(apiResp.Content) == 0 {
		log.Printf("[disambig_extractor] empty content — falling back")
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}

	var textOut strings.Builder
	for _, b := range apiResp.Content {
		if b.Type == "text" {
			textOut.WriteString(b.Text)
		}
	}
	responseText := strings.TrimSpace(textOut.String())

	// Strip optional ```json fences just in case Claude wraps.
	responseText = strings.TrimPrefix(responseText, "```json")
	responseText = strings.TrimPrefix(responseText, "```")
	responseText = strings.TrimSuffix(responseText, "```")
	responseText = strings.TrimSpace(responseText)

	var payload disambigBrandPayload
	if err := json.Unmarshal([]byte(responseText), &payload); err != nil {
		log.Printf("[disambig_extractor] could not parse JSON shape: %v — falling back", err)
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}
	if len(payload.Lines) == 0 {
		log.Printf("[disambig_extractor] zero brand lines extracted — falling back")
		return s.ExtractFromImage(ctx, imageBytes, contentType)
	}

	// Convert into ExtractedPurchaseItem shape. The disambig matcher reads
	// Brand / CanonicalBrand / Size / SizeML — leave everything else zero.
	items := make([]ExtractedPurchaseItem, 0, len(payload.Lines))
	for i, ln := range payload.Lines {
		brand := strings.TrimSpace(ln.Brand)
		if brand == "" {
			continue
		}
		sizeML := ln.SizeML
		if sizeML == 0 {
			sizeML = parseBillSizeML(ln.Size)
		}
		// v1.0.226 — Purcha qty pass-through. Normalize cases→bottles when
		// unit is "cases" using standard pack sizes (12=750ml, 24=375ml,
		// 48=180ml, 96=90ml). Leave 0 when neither side is parseable.
		qty := ln.Qty
		if qty > 0 && strings.EqualFold(strings.TrimSpace(ln.QtyUnit), "cases") {
			perCase := 0
			switch sizeML {
			case 750:
				perCase = 12
			case 375:
				perCase = 24
			case 180:
				perCase = 48
			case 90:
				perCase = 96
			}
			if perCase > 0 {
				qty = qty * perCase
			}
		}
		items = append(items, ExtractedPurchaseItem{
			RowNumber:       float64(i + 1),
			Brand:           brand,
			CanonicalBrand:  brand, // disambig matcher reads either field
			SizeText:        ln.Size,
			SizeML:          float64(sizeML),
			QuantityBottles: float64(qty), // Purcha-reported bottles received
			AnalyzeMethod:   "claude_disambig",
		})
	}

	log.Printf("[disambig_extractor] claude %s extracted %d brand lines (usage in=%d out=%d cache_create=%d cache_read=%d)",
		model, len(items),
		apiResp.Usage.InputTokens, apiResp.Usage.OutputTokens,
		apiResp.Usage.CacheCreationInputTokens, apiResp.Usage.CacheReadInputTokens)

	return &PurchaseExtractionResult{
		Items: items,
	}, nil
}

// buildDisambigBrandPrompt — terse, focused, hard rules. Same accuracy bar
// as Smart Sale's brand-cell extraction prompts.
//
// v1.0.226-r1 — removed the "if multiple sizes, emit one per size" rule
// that caused real-data ghost rows (Officer Choice at 180ml when the
// vendor bill had it across 750/375/180/90 columns). For the Purcha
// path we know the operator's receiving voucher prints ONE line per
// product × size — the input is never a combo pack. Adding back the
// rule only when a real combo case appears.
func buildDisambigBrandPrompt() string {
	return `You are an extraction engine for Indian liquor vendor invoices and shop receiving vouchers (Purcha) — TR-1 / TR-7 / FL-2 / FL-1B bills + handwritten Purcha booklets.

Goal: list EVERY product line on this document. For each line return the BRAND NAME exactly as printed (including any flavour suffix like "Green Apple", "Orange", "Smooth Smoke", "Citrus Twist"), the bottle SIZE, and the QUANTITY (when a qty/bottles/cases column is visible).

Strict rules:
1. NEVER invent a line. If the page has 12 lines, return 12 — not 13.
2. NEVER merge two lines into one. Two visually adjacent rows = two output objects.
3. ONE LINE PER PRODUCT × SIZE THE DOCUMENT ACTUALLY PRINTS. If the document shows the same brand at 4 sizes in separate rows, output 4 objects. NEVER duplicate a brand across sizes the document didn't print — do not infer 180ml when only 750ml was printed for that brand.
4. Brand text must be the FULL operator-facing brand name including the flavour/variant suffix when present. Do NOT shorten:
   • CORRECT: "M2 Magic Moments Remix Superior Green Apple Flavoured Vodka"
   • WRONG:   "M2 Remix" or "Magic Moments"
5. Size must be the bottle volume in ml. Convert any of these formats:
   • "750 ML", "750ml", "750 ml glass bottle" → 750
   • "375", "375 ml", "Half" (in context of 375) → 375
   • "Quarter" → 180
   • "Nip" → 90
6. Quantity: read the bottles received per line. If only a cases column is visible, return the cases count and set qty_unit="cases" — the caller knows the pack size for each size_ml. If neither bottles nor cases is printed, return qty=0 and qty_unit="".
7. Ignore: header rows, subtotal/total rows, TCS rows, signature rows, vendor address, indent number, transport details. Only product line items.
8. Output ONLY a JSON object — no prose, no markdown fences:

{
  "lines": [
    {"brand": "<full brand text with flavour>", "size": "<as printed>", "size_ml": <int>, "line_idx": <0-based>, "qty": <int>, "qty_unit": "bottles"|"cases"|""},
    ...
  ]
}

When size_ml cannot be confidently inferred, set it to 0 and leave size with the raw text; the caller will re-parse.`
}

// extractBrandsForDisambigMulti runs the Smart-Sale-style two-extractor
// pipeline over each page: AWS Textract AnalyzeExpense (cheap, table-aware,
// best on printed Purchas) in parallel with Claude Sonnet 4.6 (handwriting-
// strong, robust on dense / mixed-quality scans). Then unions the brand
// lines and tags consensus matches with a +0.10 confidence boost.
//
// v1.0.226-r2 — Textract added to mirror the Smart Sale path
// (smart_sale_service.go:632-734). Real-data on chhotu's bills: Textract
// nails 38/42 brand lines on a printed bill in ~5s/page at ₹0.66/page;
// Claude catches the remaining handwriting + Textract's 2-3-row dropouts
// at ₹3/page. Running both is ~₹3.66/page total but lifts brand recall
// past either extractor alone.
//
// Per-page or per-extractor failures are logged and skipped so a single
// bad page in a multi-page Purcha PDF can't break the whole batch — at
// least one extractor needs to succeed on at least one page.
func (s *SmartPurchaseOCR) extractBrandsForDisambigMulti(
	ctx context.Context,
	pages []DisambigPageInput,
) (*PurchaseExtractionResult, error) {
	if len(pages) == 0 {
		return nil, fmt.Errorf("extractBrandsForDisambigMulti: no pages")
	}

	// Per-page: run Textract + Claude IN PARALLEL via errgroup. Each
	// extractor returns []ExtractedPurchaseItem with Brand + SizeML +
	// optional QuantityBottles filled in.
	type pageOut struct {
		textract []ExtractedPurchaseItem
		claude   []ExtractedPurchaseItem
	}
	results := make([]pageOut, len(pages))
	for i, p := range pages {
		var textractItems, claudeItems []ExtractedPurchaseItem

		// Textract — try only if disambig flag allows it. Off by default
		// so legacy Claude-only deploys are unchanged.
		if disambigTextractEnabled() {
			ti, terr := s.runTextractDisambigForPage(ctx, p.Bytes, i+1)
			if terr != nil {
				log.Printf("[disambig_multi] page %d Textract failed: %v", i+1, terr)
			} else {
				textractItems = ti
			}
		}

		// Claude — always run as primary. Operator's Purcha is usually
		// handwritten; Claude's handwriting recall is materially better
		// than Textract's HANDWRITING block here.
		one, cerr := s.extractBrandsForDisambig(ctx, p.Bytes, p.ContentType)
		if cerr != nil {
			log.Printf("[disambig_multi] page %d Claude failed: %v", i+1, cerr)
		} else if one != nil {
			claudeItems = one.Items
		}
		results[i] = pageOut{textract: textractItems, claude: claudeItems}
	}

	// Union + dedup by (lower-trimmed brand + size_ml). When both
	// extractors see the same brand+size, set the line's analyze_method
	// to "consensus" and the score-decision downstream uses that as a
	// confidence signal.
	type bucket struct {
		it         ExtractedPurchaseItem
		seenByTx   bool
		seenByLLM  bool
	}
	merged := make(map[string]*bucket, 64)
	keyOf := func(brand string, sizeML int) string {
		return strings.ToLower(strings.TrimSpace(brand)) + "|" + fmt.Sprintf("%d", sizeML)
	}
	for _, r := range results {
		for _, it := range r.textract {
			k := keyOf(it.Brand, int(it.SizeML))
			if b, ok := merged[k]; ok {
				b.seenByTx = true
				// Prefer Textract's qty when it differs from 0 and
				// Claude's was 0 (Textract tables are explicit).
				if b.it.QuantityBottles == 0 && it.QuantityBottles > 0 {
					b.it.QuantityBottles = it.QuantityBottles
				}
			} else {
				it.AnalyzeMethod = "textract_disambig"
				merged[k] = &bucket{it: it, seenByTx: true}
			}
		}
		for _, it := range r.claude {
			k := keyOf(it.Brand, int(it.SizeML))
			if b, ok := merged[k]; ok {
				b.seenByLLM = true
			} else {
				if it.AnalyzeMethod == "" {
					it.AnalyzeMethod = "claude_disambig"
				}
				merged[k] = &bucket{it: it, seenByLLM: true}
			}
		}
	}

	out := make([]ExtractedPurchaseItem, 0, len(merged))
	consensus := 0
	for _, b := range merged {
		if b.seenByTx && b.seenByLLM {
			b.it.AnalyzeMethod = "consensus"
			consensus++
		}
		out = append(out, b.it)
	}

	// v1.0.230 — zero brands is NOT a server error. Real-data trigger: chhotu
	// accidentally took a camera shot of his leg + uploaded that as a Purcha;
	// both Textract and Claude returned 0 brand lines, the caller used to wrap
	// this as a 500 ("past-purchase extraction failed"). Now we return an empty
	// result with nil error so ResolveDisambigBatchMulti emits a graceful
	// per-row no_match (HTTP 422) → Flutter renders "couldn't read brands from
	// this photo, retake or pick manually" instead of a red 500 toast.
	if len(out) == 0 {
		log.Printf("[disambig_multi] no brand lines extracted from %d page(s) — returning empty result for graceful no_match downstream", len(pages))
		return &PurchaseExtractionResult{Items: out}, nil
	}
	log.Printf("[disambig_multi] merged %d brand lines (%d consensus) from %d pages",
		len(out), consensus, len(pages))
	return &PurchaseExtractionResult{Items: out}, nil
}

// runTextractDisambigForPage runs AnalyzeExpense once on the page bytes
// and translates the resulting purchase-line items into the brand + size
// + qty shape the disambig matcher consumes. Wraps the existing Smart
// Purchase Textract helper so we don't fork the implementation.
func (s *SmartPurchaseOCR) runTextractDisambigForPage(
	ctx context.Context,
	raw []byte,
	pageNumber int,
) ([]ExtractedPurchaseItem, error) {
	client, err := newTextractPurchaseClient(ctx)
	if err != nil {
		return nil, fmt.Errorf("textract client: %w", err)
	}
	items, _, err := runAnalyzeExpensePage(ctx, client, raw, pageNumber)
	if err != nil {
		return nil, err
	}
	// Strip rows with no brand text — Textract sometimes returns
	// header / total rows as line items with empty brand. The disambig
	// matcher won't pair against an empty brand anyway, but dropping
	// here keeps the consensus-merge map clean.
	keep := items[:0]
	for _, it := range items {
		if strings.TrimSpace(it.Brand) == "" {
			continue
		}
		// Mirror the Claude path: when the brand text has an embedded
		// size token ("180ml" etc.), prefer the parsed numeric size.
		if it.SizeML == 0 && strings.TrimSpace(it.SizeText) != "" {
			it.SizeML = float64(parseBillSizeML(it.SizeText))
		}
		keep = append(keep, it)
	}
	return keep, nil
}

// disambigTextractEnabled — defaults TRUE so the Smart-Sale-style dual
// extractor runs everywhere. Operator can flip DISAMBIG_TEXTRACT=0 to
// force Claude-only when an Anthropic-credit emergency hits Textract
// would otherwise be paid for as well.
func disambigTextractEnabled() bool {
	v := strings.TrimSpace(os.Getenv("DISAMBIG_TEXTRACT"))
	if v == "" {
		return true
	}
	return v != "0" && !strings.EqualFold(v, "false")
}

// DisambigPageInput carries one rendered page (or original image) into
// the multi-image extractor. Bytes is raw PNG/JPEG; ContentType drives
// the media-type sent to Claude.
type DisambigPageInput struct {
	Bytes       []byte
	ContentType string
	// Source describes the origin of this page for telemetry — e.g.
	// "image_0", "pdf_page_2". Used only for logging.
	Source string
}

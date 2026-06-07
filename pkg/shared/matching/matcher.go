package matching

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

// Product is a feature-agnostic product representation for matching.
// Each caller converts their own product type into this before calling MatchProducts.
type Product struct {
	ID                string
	Name              string  // Full product name (e.g., "Blenders Pride Premium Whisky - 750ML")
	BrandName         string  // Brand-only name (e.g., "Blenders Pride Premium Whisky")
	DisplayName       string  // Short clean name (e.g., "Magic Moments Vodka") — closer to OCR text, used as additional match signal
	ExciseBrandName   string  // Official UP Excise / master-catalog name from saas_brands (e.g. "Seagrams Blenders Pride Exclusive Premium Whisky")
	ExciseDisplayName string  // Excise display name (cleaner short form)
	// Synonyms is the master-curated set of shop-floor synonyms / abbreviations
	// for this product (e.g. ["mcd","mc dowells","no1 original"] for Mc Dowells).
	// Populated from saas_brands.meta_keywords by callers that load the master
	// catalog (Smart Sale + Stock Setup). Each entry is treated as an
	// additional name form during similarity scoring — a row whose OCR text
	// matches a synonym scores as if the OCR had said the canonical name.
	//
	// v1.0.187 — added so Stock Setup gets parity with Smart Sale's 100%
	// match coverage (chhotu's MCD / OC / AD / M.M / Iconic abbreviations).
	Synonyms []string
	Size              string  // Raw size string from DB (e.g., "750ML")
	SizeML            int     // Parsed size in ML (0 if unknown)
	SellingPrice      float64 // MRP / selling price
	CostPrice         float64 // Cost / purchase price
	CurrentStock      int     // Current stock quantity in shop (0 = out of stock)
	// LastSoldDaysAgo is the number of days since this product was last sold at this shop.
	// 0 means "sold today", -1 means "never sold here / unknown" (the default zero value
	// for callers that don't populate this field is 0, so callers MUST set this explicitly
	// if they want shop-inventory bias to use it; pass -1 from the loader when no sale row
	// exists). Used by ShopInventoryBias to favour products this shop actually moves.
	LastSoldDaysAgo   int
	// LastPurchasedDaysAgo is the number of days since this product was last purchased
	// at this shop (any non-rejected stock_purchase row). v1.0.220 — strongest single
	// signal for "this shop buys this brand", overrides the recent-sales channel for
	// purchase matching because purchases are upstream of sales. -1 means "never
	// purchased at this shop / unknown". Used by ShopInventoryPurchaseBoost.
	LastPurchasedDaysAgo int
	IsActive          bool
	CreatedAt         time.Time

	// v1.0.199 — Tenant-inventory bias inputs. Mirror ShopInventoryBias but
	// summed across every shop in the tenant. Lets the matcher tilt toward
	// "what this tenant actually stocks" when alias lookup misses and the
	// shop itself hasn't seen the brand yet but a sibling shop has.
	//
	// TenantTotalStockUnits = SUM(current_stock) across shops in tenant.
	// TenantSoldDaysAgo     = MIN(days_since_last_sale) across all shops; -1 if never.
	// TenantConfirmedAlias  = true when a tenant-wide alias row points to this product.
	TenantTotalStockUnits int
	TenantSoldDaysAgo     int
	TenantConfirmedAlias  bool
}

// MatchResult is a single candidate match with confidence score.
type MatchResult struct {
	ProductID   string
	ProductName string
	Size        string
	SizeML      int
	Price       float64 // SellingPrice or CostPrice depending on config
	Score       float64
	PriceMatch  bool
	// NeedsReview is set true when MatchProducts cannot confidently disambiguate
	// the top result from runner-up (e.g. two shop-stocked products tied within
	// AmbiguityNeedsReviewMargin). Caller surfaces this to Flutter as a swap-row
	// chip rather than persisting the top pick blindly.
	NeedsReview bool
}

// MatchConfig configures matching behavior per feature.
type MatchConfig struct {
	// Price matching
	EnablePriceMatching bool
	PriceExactBoost     float64 // ±₹5 boost (default: 0.20)
	PriceCloseBoost     float64 // ±₹20 boost (default: 0.10)
	PriceNearBoost      float64 // ±₹50 boost (default: 0.03)
	PriceFarPenalty     float64 // >₹100 penalty (default: 0.15)
	UseCostPrice        bool    // true = use CostPrice for matching, false = SellingPrice

	// Size handling
	SizeStrictFilter bool // true = skip on mismatch, false = just penalize
	SizeMatchBonus   float64

	// Thresholds
	MinThreshold     float64 // minimum FINAL score to be a candidate
	MinTextThreshold float64 // minimum TEXT-ONLY score before boosts apply (prevents price-only matches)
	MaxResults       int

	// Recently-created product boost
	RecentProductIDs   map[string]bool
	RecentProductBoost float64

	// Sort preference
	PreferPriceMatch bool // true = sort price-matched candidates first

	// Rejected product IDs (negative aliases)
	RejectedProductIDs map[string]bool

	// Stock matching
	FilterZeroStock     bool    // true = skip products with 0 stock
	StockMatchBoost     float64 // boost when OCR opening matches DB stock (±2)
	EnableStockMatching bool    // true = use stock as matching signal

	// Shop-inventory bias (v1.0.160)
	// When true, MatchProducts adds an additive score term that favours products
	// this shop actually has stock for AND/OR has sold recently, and penalises
	// products with neither stock nor sales history. The boost only fires
	// AFTER size/category gates and only when the text gate (MinTextThreshold)
	// has been crossed, so it never lets a price-only match win.
	ShopInventoryBias                 bool
	ShopInventoryStockBoost           float64 // CurrentStock > 0 → +X (default 0.10)
	ShopInventoryRecentBoost          float64 // CurrentStock > 0 AND last sold ≤30 days → +X (default 0.15, REPLACES StockBoost; not additive)
	ShopInventoryNoStockNoSalePenalty float64 // CurrentStock = 0 AND never sold → -X (default 0.05)
	ShopInventoryRecentDays           int     // window for "recent" sale (default 30)
	// v1.0.220 — Purchase-history bias. Products this shop has purchased within
	// the window get the LARGEST positive boost in the stack because a vendor
	// invoice naming a brand the shop bought 60 days ago is the strongest possible
	// signal "this is the brand". REPLACES recent-sale and stock boosts (not
	// additive) when the purchase-history boost fires — gives the cleanest tilt
	// toward "this shop's actual SKUs" even when current stock is zero.
	ShopInventoryPurchaseBoost        float64 // recently purchased here → +X (default 0.20)
	ShopInventoryPurchaseDays         int     // window for "recent" purchase (default 90)

	// Tenant-inventory bias (v1.0.199)
	// Parallel to ShopInventoryBias but uses tenant-wide signals. Fires when
	// the SHOP-level signal is ambiguous (no shop stock / no shop sales) but
	// a sibling shop in the same tenant has stocked or sold this product.
	// Concrete win: shop A in tenant T has been stocking M2 Magic Moments
	// Verve Cranberry; shop B in same tenant gets OCR "Verve Cranberry" with
	// no shop-level history → tenant bias tilts shop B's match toward the M2
	// product instead of an unrelated Canvas Cranberry.
	//
	// Stacking with ShopInventoryBias is additive but capped — when both
	// signals fire, the combined boost is capped at TenantInventoryMaxStack
	// (default 0.18) so a generic-text candidate can't be parachuted in by
	// stacked biases alone.
	TenantInventoryBias            bool
	TenantConfirmedAliasBoost      float64 // tenant-wide alias points here → +X (default 0.10)
	TenantStockBoost               float64 // any shop in tenant has stock → +X (default 0.05)
	TenantRecentSaleBoost          float64 // any shop in tenant sold within window → +X (default 0.03)
	TenantInventoryMaxStack        float64 // total cap on tenant additive (default 0.18)
	TenantInventoryRecentDays      int     // window for tenant "recent" sale (default 30)

	// Ambiguity → needs_review margin. When the top two candidates BOTH have
	// shop stock and their final scores differ by less than this margin, MarkResult
	// returns NeedsReview=true on the top result so the caller can surface a
	// swap-row chip rather than auto-pick.
	AmbiguityNeedsReviewMargin float64 // default 0.05

	// Rate-proximity tiebreaker (v1.0.327). When two candidates' final scores
	// are within RateTiebreakerTextEpsilon AND their rate-percent-diff from
	// ocrPrice differs by more than RateTiebreakerRateEpsilon, the closer-rate
	// candidate wins regardless of any PreferPriceMatch boost. Solves the
	// "PET ₹130 vs Tetra ₹140 both match same '8 PM Gold Scotch' brand text"
	// alias-collision class — rate is the decisive disambiguator. Only
	// consulted when ocrPrice > 0. Default OFF; DefaultSaleConfig() flips on.
	RateTiebreakerEnabled     bool
	RateTiebreakerTextEpsilon float64 // default 0.06
	RateTiebreakerRateEpsilon float64 // default 0.02 (2%)
}

// DefaultSaleConfig returns config tuned for Smart Sale (handwritten registers).
// Requires reasonable text match before price/size boosts can help.
func DefaultSaleConfig() MatchConfig {
	return MatchConfig{
		EnablePriceMatching: true,
		PriceExactBoost:     0.20, // Exact rate match is very strong for register receipts
		PriceCloseBoost:     0.10, // ±₹20 is still a good signal
		PriceNearBoost:      0.03,
		PriceFarPenalty:     0.15,
		UseCostPrice:        false,
		SizeStrictFilter:    false,
		SizeMatchBonus:      0.05, // All items on same page are same size, this shouldn't inflate scores
		MinThreshold:        0.55,
		MinTextThreshold:    0.40, // CRITICAL: text-only score must be >= 0.40 before any boosts apply
		MaxResults:          5,
		RecentProductBoost:  0.03,
		PreferPriceMatch:    true,
		// Stock-aware matching
		FilterZeroStock:     true, // Don't suggest products with 0 stock
		StockMatchBoost:     0.10, // Boost when opening stock matches DB stock (strong signal)
		EnableStockMatching: true,
		// v1.0.160 — shop-inventory bias defaults (caller toggles via env-aware wrapper)
		ShopInventoryBias:                 false, // off by default; smart_sale_service flips on per env
		ShopInventoryStockBoost:           0.10,
		ShopInventoryRecentBoost:          0.15,
		ShopInventoryNoStockNoSalePenalty: 0.05,
		ShopInventoryRecentDays:           30,
		AmbiguityNeedsReviewMargin:        0.05,
		// v1.0.199 — tenant-inventory bias defaults (caller flips on per env)
		TenantInventoryBias:        false,
		TenantConfirmedAliasBoost:  0.10,
		TenantStockBoost:           0.05,
		TenantRecentSaleBoost:      0.03,
		TenantInventoryMaxStack:    0.18,
		TenantInventoryRecentDays:  30,
		// v1.0.327 — rate-proximity tiebreaker ON for Smart Sale only.
		// Two same-brand SKUs at different MRPs (e.g. "8PM PET ₹130" vs
		// "8PM Tetra ₹140") tie on text score; we let OCR rate decide.
		RateTiebreakerEnabled:     true,
		RateTiebreakerTextEpsilon: 0.06,
		RateTiebreakerRateEpsilon: 0.02,
	}
}

// DefaultStockSetupConfig returns config tuned for Smart Stock Setup (register images).
// Strict size filtering, moderate price matching.
func DefaultStockSetupConfig() MatchConfig {
	return MatchConfig{
		EnablePriceMatching: true,
		PriceExactBoost:     0.12,
		PriceCloseBoost:     0.06,
		PriceNearBoost:      0.02,
		PriceFarPenalty:     0.10,
		UseCostPrice:        false,
		SizeStrictFilter:    true,
		SizeMatchBonus:      0.05,
		MinThreshold:        0.50,
		MinTextThreshold:    0.40,
		MaxResults:          5,
		RecentProductBoost:  0.03,
		PreferPriceMatch:    true,
		// v1.0.199 — tenant-inventory bias defaults; Stock Setup flips on
		// when SMART_STOCK_SETUP_TENANT_BIAS=1 (defaults on in production).
		TenantInventoryBias:        false,
		TenantConfirmedAliasBoost:  0.10,
		TenantStockBoost:           0.05,
		TenantRecentSaleBoost:      0.03,
		TenantInventoryMaxStack:    0.18,
		TenantInventoryRecentDays:  30,
	}
}

// DefaultPurchaseConfig returns config tuned for Smart Purchase (vendor invoices).
// Strict size, no price matching (cost prices on invoices don't help with name matching).
func DefaultPurchaseConfig() MatchConfig {
	return MatchConfig{
		EnablePriceMatching: false,
		UseCostPrice:        true,
		SizeStrictFilter:    true,
		SizeMatchBonus:      0.10,
		MinThreshold:        0.50,
		MinTextThreshold:    0.45,
		MaxResults:          5,
		RecentProductBoost:  0.05,
		PreferPriceMatch:    false,
		// v1.0.193 — Shop-inventory bias for purchase matching. Real-world
		// motivation: an operator's bill says "Royal Stag Premium 750ml".
		// The shop already onboarded "Royal Stag Premium 750 ML" (rounded ML
		// vs ML+space variant) at score 0.74 — just under 0.75 threshold to
		// be a confident match. With ShopInventoryBias on, the existing
		// shop product gets +0.15 (in-stock) or +0.10 (recently purchased)
		// bumping it over the line. Prevents spurious "create new product"
		// suggestions when the brand was already onboarded.
		ShopInventoryBias:                 true,
		// v1.0.217 — explicitly set the boost values (DefaultPurchaseConfig
		// previously relied on zero-init, which meant the bias was on but
		// the actual boost was 0). Mirrors smart_sale's bias defaults.
		ShopInventoryStockBoost:           0.10,
		ShopInventoryRecentBoost:          0.15,
		ShopInventoryNoStockNoSalePenalty: -0.05,
		ShopInventoryRecentDays:           30,
		// v1.0.220 — purchase-history boost (90-day window). Owner-reported
		// gap: items the shop has previously purchased but are currently
		// out-of-stock were losing to random master-catalog SKUs because the
		// matcher had no signal for "shop's own historical SKUs". This term
		// overrides recent-sale and stock boosts when it fires, fixing the
		// "vendor invoice naming a brand we bought 2 months ago doesn't match"
		// class of error.
		ShopInventoryPurchaseBoost:        0.20,
		ShopInventoryPurchaseDays:         90,
		// NOTE: TenantInventoryBias intentionally left OFF here — caller
		// (smart_purchase_service) would need to populate TenantSoldDaysAgo
		// to -1 (default zero would falsely qualify every product). Flip on
		// in a follow-up once the tenant signal loader is wired.
		AmbiguityNeedsReviewMargin:        0.05,
	}
}

// PreparedProduct has precomputed normalized fields for efficient matching.
type PreparedProduct struct {
	Product
	NormalizedName              string
	NormalizedBrandName         string
	NormalizedDisplayName       string
	NormalizedExciseBrandName   string
	NormalizedExciseDisplayName string
	NameLower                   string
	BrandNameLower              string
	DisplayNameLower            string
	ExciseBrandNameLower        string
	ExciseDisplayNameLower      string
	NameTokens                  []string
	BrandTokens                 []string
	DisplayNameTokens           []string
	ExciseBrandTokens           []string
	ExciseDisplayTokens         []string
	// v1.0.187 — pre-normalized synonyms (lower-cased + space-split + Levenshtein-ready).
	// Each entry has a matching SynonymsTokens row in the same index. Empty when
	// the source product has no master meta_keywords.
	SynonymsLower      []string
	NormalizedSynonyms []string
	SynonymsTokens     [][]string
	SizeNorm                    string
}

// PrepareProducts precomputes normalized forms. Call once per request, then use with MatchProducts.
func PrepareProducts(products []Product) []PreparedProduct {
	prepared := make([]PreparedProduct, len(products))
	for i, p := range products {
		nameLower := strings.ToLower(p.Name)
		brandLower := strings.ToLower(p.BrandName)
		displayLower := strings.ToLower(p.DisplayName)
		exciseBrandLower := strings.ToLower(p.ExciseBrandName)
		exciseDisplayLower := strings.ToLower(p.ExciseDisplayName)
		// v1.0.187 — normalize each synonym once. Skip entries that collapse
		// to <2 chars (after normalization) — those are noise and would
		// over-match on every short OCR string.
		var synLower []string
		var synNorm []string
		var synTokens [][]string
		for _, s := range p.Synonyms {
			s = strings.TrimSpace(s)
			if s == "" {
				continue
			}
			lo := strings.ToLower(s)
			no := NormalizeForMatch(s)
			if len(no) < 2 {
				continue
			}
			synLower = append(synLower, lo)
			synNorm = append(synNorm, no)
			synTokens = append(synTokens, strings.Fields(lo))
		}
		prepared[i] = PreparedProduct{
			Product:                     p,
			NormalizedName:              NormalizeForMatch(p.Name),
			NormalizedBrandName:         NormalizeForMatch(p.BrandName),
			NormalizedDisplayName:       NormalizeForMatch(p.DisplayName),
			NormalizedExciseBrandName:   NormalizeForMatch(p.ExciseBrandName),
			NormalizedExciseDisplayName: NormalizeForMatch(p.ExciseDisplayName),
			NameLower:                   nameLower,
			BrandNameLower:              brandLower,
			DisplayNameLower:            displayLower,
			ExciseBrandNameLower:        exciseBrandLower,
			ExciseDisplayNameLower:      exciseDisplayLower,
			NameTokens:                  strings.Fields(nameLower),
			BrandTokens:                 strings.Fields(brandLower),
			DisplayNameTokens:           strings.Fields(displayLower),
			ExciseBrandTokens:           strings.Fields(exciseBrandLower),
			ExciseDisplayTokens:         strings.Fields(exciseDisplayLower),
			SynonymsLower:               synLower,
			NormalizedSynonyms:          synNorm,
			SynonymsTokens:              synTokens,
			SizeNorm:                    NormalizeSize(p.Size),
		}
	}
	return prepared
}

// MatchProducts finds the best product matches for OCR-extracted text.
// ocrPrice is optional (pass 0 to disable price matching regardless of config).
// ocrOpeningStock is optional (pass 0 to disable stock matching).
//
// SCORING DESIGN: Text similarity is computed first (Levenshtein, substring, token overlap).
// Price/size/recent boosts are ONLY applied if the text score meets MinTextThreshold.
// This prevents products with matching prices but completely different names from being matched
// (e.g., "MCD Double Oak Barrel Whisky" ₹610 should NOT match "ICONIQ WHITE" ₹610).
func MatchProducts(ocrText string, ocrSizeML int, ocrPrice float64, products []PreparedProduct, config MatchConfig) []MatchResult {
	return MatchProductsWithStock(ocrText, ocrSizeML, ocrPrice, 0, products, config)
}

// MatchProductsWithStock is like MatchProducts but also uses opening stock as a matching signal.
func MatchProductsWithStock(ocrText string, ocrSizeML int, ocrPrice float64, ocrOpeningStock int, products []PreparedProduct, config MatchConfig) []MatchResult {
	if ocrText == "" || len(products) == 0 {
		return nil
	}

	ocrLower := strings.ToLower(strings.TrimSpace(ocrText))
	ocrNormalized := NormalizeForMatch(ocrText)
	ocrTokens := strings.Fields(ocrLower)

	// Compute dynamic token frequency from this tenant's actual product catalog
	tokenFreq := BuildTokenFrequency(products)
	totalProducts := len(products)

	// v1.0.179 — productLineWords are lineage / variant tokens that must
	// DIFFERENTIATE within a brand family (e.g. "Bagpiper RESERVE 180" vs
	// "Bagpiper EXCLUSIVE 180" — same brand "BP" prefix, different lineage).
	// These tokens are still excluded from the unique-word boost (see
	// categoryWords blocklist below) — that boost was too generous and
	// rescued bad text matches. Instead we apply a smaller +0.06
	// finalScore boost when the lineage word appears in the OCR AND in
	// this candidate's name AND is NOT shared by any rival candidate
	// across the same product set. Tightens BP-family disambiguation
	// without changing single-candidate behaviour.
	productLineWords := map[string]bool{
		"exclusive": true, "reserve": true, "signature": true, "vintage": true,
		"single": true, "double": true, "aged": true, "barrel": true, "cask": true,
		"select": true, "rare": true, "limited": true, "edition": true,
	}
	// For each productLineWord present in the OCR, count how many candidates
	// have that token in their name/brand/display tokens. count == 1 means
	// the lineage word is uniquely identifying within this product set.
	productLineHits := map[string]int{}      // word → number of candidates that contain it
	productLineHasIt := map[int]map[string]bool{} // candidateIdx → set of lineage words it has
	for _, ocrTok := range ocrTokens {
		if !productLineWords[ocrTok] {
			continue
		}
		productLineHits[ocrTok] = 0
		for i := range products {
			has := false
			for _, t := range products[i].NameTokens {
				if t == ocrTok {
					has = true
					break
				}
			}
			if !has {
				for _, t := range products[i].BrandTokens {
					if t == ocrTok {
						has = true
						break
					}
				}
			}
			if !has {
				for _, t := range products[i].DisplayNameTokens {
					if t == ocrTok {
						has = true
						break
					}
				}
			}
			if has {
				productLineHits[ocrTok]++
				if productLineHasIt[i] == nil {
					productLineHasIt[i] = map[string]bool{}
				}
				productLineHasIt[i][ocrTok] = true
			}
		}
	}

	// Size normalization: prefer explicit sizeML, fallback to parsing from text
	ocrSizeNorm := ""
	if ocrSizeML > 0 {
		ocrSizeNorm = fmt.Sprintf("%d", ocrSizeML)
	}

	var candidates []MatchResult

	for i := range products {
		p := &products[i]

		// Skip rejected products (negative aliases)
		if config.RejectedProductIDs != nil && config.RejectedProductIDs[p.ID] {
			continue
		}

		// Skip products with zero stock (can't sell what you don't have)
		if config.FilterZeroStock && p.CurrentStock <= 0 {
			continue
		}

		// --- Size matching ---
		sizeMatches := false
		if ocrSizeML > 0 && p.SizeML > 0 {
			sizeMatches = ocrSizeML == p.SizeML
		} else if p.SizeNorm != "" && ocrSizeNorm != "" {
			sizeMatches = p.SizeNorm == ocrSizeNorm
		} else {
			sizeMatches = true // unknown size = don't filter
		}

		if config.SizeStrictFilter && !sizeMatches && p.SizeNorm != "" && ocrSizeNorm != "" {
			continue // Hard filter: skip on mismatch
		}

		// =====================================================
		// PHASE 1: Compute text-only similarity (no boosts)
		// =====================================================

		// --- 1. Levenshtein similarity ---
		brandSim := StringSimilarity(ocrLower, p.BrandNameLower)
		nameSim := StringSimilarity(ocrLower, p.NameLower)
		normBrandSim := StringSimilarity(ocrNormalized, p.NormalizedBrandName)
		normNameSim := StringSimilarity(ocrNormalized, p.NormalizedName)

		textScore := maxFloat(maxFloat(brandSim, nameSim), maxFloat(normBrandSim, normNameSim))

		// Display name similarity — short clean name is often closer to OCR text
		if p.DisplayNameLower != "" {
			displaySim := StringSimilarity(ocrLower, p.DisplayNameLower)
			normDisplaySim := StringSimilarity(ocrNormalized, p.NormalizedDisplayName)
			textScore = maxFloat(textScore, maxFloat(displaySim, normDisplaySim))
		}

		// Excise (UP Excise / master catalog) name similarity — authoritative source.
		// OCR text often matches the official excise name better than the tenant's
		// (sometimes-hastily-created) product name.
		if p.ExciseBrandNameLower != "" {
			exciseSim := StringSimilarity(ocrLower, p.ExciseBrandNameLower)
			normExciseSim := StringSimilarity(ocrNormalized, p.NormalizedExciseBrandName)
			textScore = maxFloat(textScore, maxFloat(exciseSim, normExciseSim))
		}
		if p.ExciseDisplayNameLower != "" {
			exciseDispSim := StringSimilarity(ocrLower, p.ExciseDisplayNameLower)
			normExciseDispSim := StringSimilarity(ocrNormalized, p.NormalizedExciseDisplayName)
			textScore = maxFloat(textScore, maxFloat(exciseDispSim, normExciseDispSim))
		}

		// v1.0.187 — Synonyms / meta_keywords. Each master-curated synonym is
		// scored as an alternative name form. The best synonym score is
		// max'd into textScore so a row whose OCR text matches a synonym
		// (e.g. "MCD" → "Mc Dowells") scores as if the OCR had said the
		// canonical name. Substring containment caps at 0.95 for synonyms
		// (slightly below brand-name's 0.80 because synonyms are curated
		// shorthand, often unambiguous: "MCD" cannot mean anything else).
		for k, synLower := range p.SynonymsLower {
			synSim := StringSimilarity(ocrLower, synLower)
			synNormSim := StringSimilarity(ocrNormalized, p.NormalizedSynonyms[k])
			textScore = maxFloat(textScore, maxFloat(synSim, synNormSim))
			// Substring: OCR contains synonym OR synonym contains OCR.
			if strings.Contains(ocrLower, synLower) || strings.Contains(synLower, ocrLower) {
				textScore = maxFloat(textScore, 0.95)
			}
		}

		// --- 2. Substring containment ---
		if strings.Contains(ocrLower, p.BrandNameLower) || strings.Contains(p.BrandNameLower, ocrLower) {
			textScore = maxFloat(textScore, 0.80)
		}
		if strings.Contains(ocrLower, p.NameLower) || strings.Contains(p.NameLower, ocrLower) {
			textScore = maxFloat(textScore, 0.80)
		}
		if strings.Contains(ocrNormalized, p.NormalizedBrandName) || strings.Contains(p.NormalizedBrandName, ocrNormalized) {
			textScore = maxFloat(textScore, 0.80)
		}
		if p.DisplayNameLower != "" {
			if strings.Contains(ocrLower, p.DisplayNameLower) || strings.Contains(p.DisplayNameLower, ocrLower) {
				textScore = maxFloat(textScore, 0.80)
			}
			if strings.Contains(ocrNormalized, p.NormalizedDisplayName) || strings.Contains(p.NormalizedDisplayName, ocrNormalized) {
				textScore = maxFloat(textScore, 0.80)
			}
		}
		if p.ExciseBrandNameLower != "" {
			if strings.Contains(ocrLower, p.ExciseBrandNameLower) || strings.Contains(p.ExciseBrandNameLower, ocrLower) {
				textScore = maxFloat(textScore, 0.80)
			}
		}
		if p.ExciseDisplayNameLower != "" {
			if strings.Contains(ocrLower, p.ExciseDisplayNameLower) || strings.Contains(p.ExciseDisplayNameLower, ocrLower) {
				textScore = maxFloat(textScore, 0.80)
			}
		}

		// --- 3. Token overlap (IDF-weighted) ---
		if len(ocrTokens) > 0 {
			tokenScore1 := TokenOverlapScore(ocrTokens, p.NameTokens, tokenFreq, totalProducts)
			tokenScore2 := TokenOverlapScore(ocrTokens, p.BrandTokens, tokenFreq, totalProducts)
			tokenScore := maxFloat(tokenScore1, tokenScore2)
			if len(p.DisplayNameTokens) > 0 {
				tokenScore = maxFloat(tokenScore, TokenOverlapScore(ocrTokens, p.DisplayNameTokens, tokenFreq, totalProducts))
			}
			if len(p.ExciseBrandTokens) > 0 {
				tokenScore = maxFloat(tokenScore, TokenOverlapScore(ocrTokens, p.ExciseBrandTokens, tokenFreq, totalProducts))
			}
			if len(p.ExciseDisplayTokens) > 0 {
				tokenScore = maxFloat(tokenScore, TokenOverlapScore(ocrTokens, p.ExciseDisplayTokens, tokenFreq, totalProducts))
			}
			// v1.0.187 — synonym tokens. Each synonym's token list is scored
			// the same way the canonical names are; the best wins. Crucially,
			// synonyms can be SHORTER than canonical names (e.g. "MCD") so the
			// IDF-weighted token-overlap score can hit 1.0 for an exact short
			// abbreviation match.
			for _, st := range p.SynonymsTokens {
				if len(st) == 0 {
					continue
				}
				tokenScore = maxFloat(tokenScore, TokenOverlapScore(ocrTokens, st, tokenFreq, totalProducts))
			}
			if tokenScore > 0.5 {
				textScore = maxFloat(textScore, tokenScore*0.85)
			}
		}

		// --- 3b. Unique distinguishing word match ---
		// Generic category/style/flavor words should not trigger unique word boost.
		// Flavor tokens (green, apple, jamun, etc.) are intentionally blocked: on their own
		// they shouldn't pull an OCR row onto a flavored variant when the rest of the text
		// doesn't match. When the flavor IS part of the brand (e.g. "Magic Moments Green Apple"),
		// the second distinctive token ("moments") drives the match through regular token overlap.
		categoryWords := map[string]bool{
			// Spirit category
			"rum": true, "whisky": true, "whiskey": true, "vodka": true,
			"brandy": true, "gin": true, "wine": true, "scotch": true,
			"bourbon": true, "blended": true, "grain": true, "flavoured": true,
			"flavored": true,
			// Quality descriptors
			"superior": true, "deluxe": true, "premium": true,
			"special": true, "rare": true, "reserve": true, "international": true,
			// Flavor tokens — block these from unique-word boost (see comment above)
			"green": true, "apple": true, "orange": true, "jamun": true, "cranberry": true,
			"mint": true, "minty": true, "spicymint": true, "raspberry": true,
			"lemon": true, "lime": true, "honey": true, "verve": true, "remix": true,
			"tease": true, "zest": true, "pet": true,
			// Common English words that appear in product names but are not brand identifiers
			"very": true, "old": true, "the": true, "fine": true, "original": true,
			"exclusive": true, "select": true, "choice": true, "distilled": true,
			"triple": true, "indian": true,
		}
		for _, ocrTok := range ocrTokens {
			// Require >= 4 chars to avoid OCR artifacts ("mad", "why") from triggering unique-word boost
			if len(ocrTok) < 4 {
				continue
			}
			if categoryWords[ocrTok] {
				continue
			}
			inThisProduct := false
			for _, pTok := range p.NameTokens {
				if ocrTok == pTok || strings.HasPrefix(pTok, ocrTok) || strings.HasPrefix(ocrTok, pTok) {
					inThisProduct = true
					break
				}
			}
			if !inThisProduct {
				for _, pTok := range p.BrandTokens {
					if ocrTok == pTok || strings.HasPrefix(pTok, ocrTok) || strings.HasPrefix(ocrTok, pTok) {
						inThisProduct = true
						break
					}
				}
			}
			if !inThisProduct {
				for _, pTok := range p.DisplayNameTokens {
					if ocrTok == pTok || strings.HasPrefix(pTok, ocrTok) || strings.HasPrefix(ocrTok, pTok) {
						inThisProduct = true
						break
					}
				}
			}
			if !inThisProduct {
				for _, pTok := range p.ExciseBrandTokens {
					if ocrTok == pTok || strings.HasPrefix(pTok, ocrTok) || strings.HasPrefix(ocrTok, pTok) {
						inThisProduct = true
						break
					}
				}
			}
			if !inThisProduct {
				for _, pTok := range p.ExciseDisplayTokens {
					if ocrTok == pTok || strings.HasPrefix(pTok, ocrTok) || strings.HasPrefix(ocrTok, pTok) {
						inThisProduct = true
						break
					}
				}
			}
			if inThisProduct {
				matchCount := 0
				for j := range products {
					if j == i {
						continue
					}
					for _, otherTok := range products[j].NameTokens {
						if ocrTok == otherTok || strings.HasPrefix(otherTok, ocrTok) || strings.HasPrefix(ocrTok, otherTok) {
							matchCount++
							break
						}
					}
				}
				if matchCount == 0 {
					// Require a SECOND non-category token from the OCR text to also appear in
					// this product. A single rare token alone is not enough to justify 0.75 — it
					// lets "Rockford Reserve" (where "rockford" is unique) overpower scoring when
					// actually only the rare word matched and "reserve" is category-word.
					supportingTokens := 0
					for _, tok2 := range ocrTokens {
						if tok2 == ocrTok {
							continue
						}
						if len(tok2) < 4 || categoryWords[tok2] {
							continue
						}
						in2 := false
						for _, pTok := range p.NameTokens {
							if tok2 == pTok || strings.HasPrefix(pTok, tok2) || strings.HasPrefix(tok2, pTok) {
								in2 = true
								break
							}
						}
						if !in2 {
							for _, pTok := range p.BrandTokens {
								if tok2 == pTok || strings.HasPrefix(pTok, tok2) || strings.HasPrefix(tok2, pTok) {
									in2 = true
									break
								}
							}
						}
						if !in2 && len(p.DisplayNameTokens) > 0 {
							for _, pTok := range p.DisplayNameTokens {
								if tok2 == pTok || strings.HasPrefix(pTok, tok2) || strings.HasPrefix(tok2, pTok) {
									in2 = true
									break
								}
							}
						}
						if in2 {
							supportingTokens++
						}
					}
					// If OCR only had 1 non-category token, single-token rare match is accepted at 0.70.
					// If 2+ non-category tokens but only 1 matched, this is noisy — boost to 0.60 only.
					// If 2+ non-category tokens and ≥2 matched, full 0.80 boost.
					nonCategoryCount := 0
					for _, tok2 := range ocrTokens {
						if len(tok2) >= 4 && !categoryWords[tok2] {
							nonCategoryCount++
						}
					}
					switch {
					case nonCategoryCount <= 1:
						textScore = maxFloat(textScore, 0.70)
					case supportingTokens >= 1:
						textScore = maxFloat(textScore, 0.80)
					default:
						// Only 1 of multiple non-category tokens matched — weak signal, modest boost
						textScore = maxFloat(textScore, 0.60)
					}
				}
			}
		}

		// --- 4. Initials matching ---
		if len(ocrLower) <= 5 && len(ocrTokens) <= 2 {
			initScore := maxFloat(
				InitialsMatch(ocrLower, p.Product.Name),
				InitialsMatch(ocrLower, p.Product.BrandName),
			)
			textScore = maxFloat(textScore, initScore)
		}

		// =====================================================
		// PHASE 2: Apply boosts ONLY if text score is sufficient
		// This prevents price-only matches where names are unrelated
		// =====================================================

		finalScore := textScore
		priceMatch := false

		// Gate: only apply size/price/recent boosts if text matches reasonably
		minTextGate := config.MinTextThreshold
		if minTextGate <= 0 {
			minTextGate = 0.40 // default safety net
		}

		if textScore >= minTextGate {
			// --- 5. Size match bonus ---
			if sizeMatches && config.SizeMatchBonus > 0 {
				finalScore += config.SizeMatchBonus
			}

			// --- 6. Price matching (strengthened for register receipts) ---
			productPrice := p.SellingPrice
			if config.UseCostPrice {
				productPrice = p.CostPrice
			}

			if config.EnablePriceMatching && ocrPrice > 0 && productPrice > 0 {
				priceDiff := absFloat(ocrPrice - productPrice)
				pricePct := priceDiff / ocrPrice * 100

				if priceDiff <= 1.0 {
					// Exact rate match — very strong signal for register receipts
					finalScore += config.PriceExactBoost + 0.05
					priceMatch = true
				} else if priceDiff <= 5.0 {
					finalScore += config.PriceExactBoost
					priceMatch = true
				} else if priceDiff <= 20.0 {
					finalScore += config.PriceCloseBoost
					priceMatch = true
				} else if priceDiff <= 50.0 {
					finalScore += config.PriceNearBoost
				} else if pricePct <= 15.0 {
					// Within 15% — no boost, no penalty
				} else if pricePct <= 30.0 {
					if finalScore < 0.85 {
						finalScore -= config.PriceFarPenalty * 0.5
					}
				} else {
					if finalScore < 0.90 {
						finalScore -= config.PriceFarPenalty
					}
				}
			}

			// --- 7. Stock match boost ---
			// When OCR opening stock matches DB stock (±2), it strongly confirms the match
			if config.EnableStockMatching && ocrOpeningStock > 0 && p.CurrentStock > 0 {
				stockDiff := ocrOpeningStock - p.CurrentStock
				if stockDiff < 0 {
					stockDiff = -stockDiff
				}
				if stockDiff <= 2 {
					finalScore += config.StockMatchBoost
				}
			}

			// --- 8. Recently-created product boost ---
			if config.RecentProductIDs != nil && config.RecentProductIDs[p.ID] && config.RecentProductBoost > 0 {
				finalScore += config.RecentProductBoost
			}

			// --- 9. Shop-inventory bias (v1.0.160) ---
			// Favour products this shop actually moves over equally-ranked but never-
			// sold catalog entries. Bias is gated on text-confidence (already inside
			// the textScore >= minTextGate block), so we cannot up-rank a name-mismatch
			// just because the shop happens to stock it.
			//
			// Tiered: recent-sale beats stock-only beats neither. The "neither" path
			// is a small penalty (not a filter) so genuinely-new SKUs can still win
			// when the OCR text is unambiguous.
			if config.ShopInventoryBias {
				recentDays := config.ShopInventoryRecentDays
				if recentDays <= 0 {
					recentDays = 30
				}
				// v1.0.220 — purchase-history channel beats recent-sale and
				// stock channels because purchases are upstream of sales (if
				// we bought it in the last 90d at this shop, it's the right
				// SKU even if stock is now zero from heavy selling).
				// Guarded on ShopInventoryPurchaseBoost > 0 so callers that
				// don't populate LastPurchasedDaysAgo (which defaults to 0
				// and would otherwise wrongly qualify every candidate) don't
				// accidentally short-circuit the stock/recent-sale channels.
				purchaseDays := config.ShopInventoryPurchaseDays
				if purchaseDays <= 0 {
					purchaseDays = 90
				}
				purchaseChannelOn := config.ShopInventoryPurchaseBoost > 0
				purchasedRecently := purchaseChannelOn && p.LastPurchasedDaysAgo >= 0 && p.LastPurchasedDaysAgo <= purchaseDays
				hasStock := p.CurrentStock > 0
				soldRecently := p.LastSoldDaysAgo >= 0 && p.LastSoldDaysAgo <= recentDays
				neverSold := p.LastSoldDaysAgo < 0
				// Only treat "never purchased" as a negative signal when the purchase
				// channel is on; otherwise fall back to legacy (sale-only) semantics.
				neverPurchased := !purchaseChannelOn || p.LastPurchasedDaysAgo < 0
				switch {
				case purchasedRecently:
					finalScore += config.ShopInventoryPurchaseBoost
				case hasStock && soldRecently:
					finalScore += config.ShopInventoryRecentBoost
				case hasStock:
					finalScore += config.ShopInventoryStockBoost
				case !hasStock && neverSold && neverPurchased:
					finalScore -= config.ShopInventoryNoStockNoSalePenalty
				}
			}

			// --- 9b. Tenant-inventory bias (v1.0.199) ---
			// Tenant-wide signal: any shop in the tenant has stock / sold this /
			// has a tenant-wide confirmed alias pointing here. Helps when the
			// SHOP itself has no history but a sibling shop does — concrete
			// example: shop A in tenant T stocks M2 Magic Moments Verve
			// Cranberry; shop B's OCR "Verve Cranberry" gets tilted toward
			// the M2 product instead of an unrelated Canvas Cranberry SKU.
			//
			// Capped at TenantInventoryMaxStack so this can't single-handedly
			// outrank a shop's own confirmed pick. Combined with
			// ShopInventoryBias the total tenant boost is bounded.
			if config.TenantInventoryBias {
				tenantBoost := 0.0
				if p.TenantConfirmedAlias {
					tenantBoost += config.TenantConfirmedAliasBoost
				}
				if p.TenantTotalStockUnits > 0 {
					tenantBoost += config.TenantStockBoost
				}
				tenantRecentDays := config.TenantInventoryRecentDays
				if tenantRecentDays <= 0 {
					tenantRecentDays = 30
				}
				if p.TenantSoldDaysAgo >= 0 && p.TenantSoldDaysAgo <= tenantRecentDays {
					tenantBoost += config.TenantRecentSaleBoost
				}
				cap := config.TenantInventoryMaxStack
				if cap > 0 && tenantBoost > cap {
					tenantBoost = cap
				}
				finalScore += tenantBoost
			}
		}
		// If textScore < minTextGate, finalScore = textScore (no boosts applied)
		// This means products with completely different names can never match via price alone

		// v1.0.179 — productLine differentiation boost. When a lineage word
		// in the OCR appears in this candidate's tokens AND no rival
		// candidate has the same token, add +0.06 per unique lineage word
		// (capped at +0.10 total). Breaks BP Reserve vs BP Exclusive ties
		// without rescuing unrelated candidates.
		if textScore >= minTextGate && len(productLineHasIt[i]) > 0 {
			lineageBoost := 0.0
			for word := range productLineHasIt[i] {
				if productLineHits[word] == 1 {
					lineageBoost += 0.06
					if lineageBoost >= 0.10 {
						lineageBoost = 0.10
						break
					}
				}
			}
			finalScore += lineageBoost
		}

		// v1.0.240 — Dirty-SKU penalty. Products whose `name` contains a newline
		// are pre-v238 OCR-merge corruptions: two distinct brand cells from the
		// original extraction got concatenated into ONE product row at onboarding
		// time. Real-data (chhotu's Mahua Khera shop): we see entries like
		//   "Sterling Reserve B7 Whisky 180MD\n100 Strokes Royal Whisky 180m"
		//   "Royal Stag Superior Whisky 750ML\n375ML"
		// When the current bill says "Sterling Reserve B-7 180ml", the dirty SKU
		// can outscore a clean entry just because it has more matching tokens.
		// Apply a flat -0.20 penalty so the clean SKU wins whenever both exist.
		// When ONLY the dirty SKU exists, it still passes MinThreshold (0.50)
		// and shows up — the operator can fix the name from the review screen.
		if strings.Contains(p.Product.Name, "\n") {
			finalScore -= 0.20
		}

		// --- Collect candidate ---
		productPrice := p.SellingPrice
		if config.UseCostPrice {
			productPrice = p.CostPrice
		}

		// Clamp final score to [0, 1] — stacked boosts can otherwise push over 1.0
		// (e.g. strong text + size bonus + price bonus) which looks wrong in the UI.
		if finalScore > 1.0 {
			finalScore = 1.0
		}
		if finalScore < 0 {
			finalScore = 0
		}

		if finalScore >= config.MinThreshold {
			candidates = append(candidates, MatchResult{
				ProductID:   p.ID,
				ProductName: p.Product.Name,
				Size:        p.Product.Size,
				SizeML:      p.SizeML,
				Price:       productPrice,
				Score:       finalScore,
				PriceMatch:  priceMatch,
			})
		}
	}

	// --- Sort candidates ---
	// v1.0.327 — rate-proximity tiebreaker. When scores are within
	// RateTiebreakerTextEpsilon, closer OCR-rate match wins. Solves the
	// "8PM PET ₹130 vs 8PM Tetra ₹140 both bind to same product_id"
	// alias-collision class. Must run BEFORE PreferPriceMatch because the
	// boost is too coarse (it only sees the bool flag, not the magnitude).
	// Price match is a tiebreaker only when scores are close (within 0.12).
	sort.Slice(candidates, func(i, j int) bool {
		if config.RateTiebreakerEnabled && ocrPrice > 0 {
			textEps := config.RateTiebreakerTextEpsilon
			if textEps <= 0 {
				textEps = 0.06
			}
			rateEps := config.RateTiebreakerRateEpsilon
			if rateEps <= 0 {
				rateEps = 0.02
			}
			if absFloat(candidates[i].Score-candidates[j].Score) < textEps {
				iPct := ratePctDiff(ocrPrice, candidates[i].Price)
				jPct := ratePctDiff(ocrPrice, candidates[j].Price)
				if absFloat(iPct-jPct) > rateEps {
					return iPct < jPct // closer-rate wins
				}
			}
		}
		if config.PreferPriceMatch && candidates[i].PriceMatch != candidates[j].PriceMatch {
			scoreDiff := absFloat(candidates[i].Score - candidates[j].Score)
			if scoreDiff < 0.12 {
				return candidates[i].PriceMatch
			}
		}
		return candidates[i].Score > candidates[j].Score
	})

	// --- Cap results ---
	maxResults := config.MaxResults
	if maxResults <= 0 {
		maxResults = 5
	}
	if len(candidates) > maxResults {
		candidates = candidates[:maxResults]
	}

	// --- Ambiguity → needs_review (v1.0.160) ---
	// When the top two candidates BOTH have shop stock and their final scores
	// are within AmbiguityNeedsReviewMargin, we cannot pick blindly — flag the
	// top result so the caller can show a swap-row chip to the operator.
	// Only fires when ShopInventoryBias is on (otherwise we have no shop-stock
	// signal to compare).
	if config.ShopInventoryBias && len(candidates) >= 2 {
		margin := config.AmbiguityNeedsReviewMargin
		if margin <= 0 {
			margin = 0.05
		}
		// Look up CurrentStock for the top two via the prepared product slice.
		// (We didn't store stock on MatchResult; reuse a small loop.)
		topStock := stockForProductID(products, candidates[0].ProductID)
		secondStock := stockForProductID(products, candidates[1].ProductID)
		if topStock > 0 && secondStock > 0 {
			scoreDiff := candidates[0].Score - candidates[1].Score
			if scoreDiff < 0 {
				scoreDiff = -scoreDiff
			}
			if scoreDiff < margin {
				candidates[0].NeedsReview = true
			}
		}
	}

	return candidates
}

// stockForProductID is a tiny helper for the ambiguity check — small product
// slices (size+category-scoped) keep this O(n) acceptable.
func stockForProductID(products []PreparedProduct, id string) int {
	for i := range products {
		if products[i].ID == id {
			return products[i].CurrentStock
		}
	}
	return 0
}

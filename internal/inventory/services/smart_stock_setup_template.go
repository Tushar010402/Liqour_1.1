package services

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// ============================================================================
// Per-shop register-template fingerprinting (#1).
//
// After 5+ approved jobs from the same (shop, size) pair, hash the column
// layout — which columns the AI consistently identified as Brand/Opening/
// Receipt/Total/Sale/Rate/Amount, what their typical row count is, what the
// preprinted brand list looks like. Cache that fingerprint and inject it as
// a prompt hint on subsequent extractions:
//
//   "On this shop's 180ML register, expect ~28 preprinted rows. Header:
//   S.N | Brand | Opening | Receipt | Total | Sale | Rate | Amount | Closing.
//   Brands typically include: 8PM Gold, OFFICER'S CHOICE, M2 Magic Moments..."
//
// Templated extraction is how invoice OCR hits 99%+ — the model gets explicit
// field anchoring instead of inferring layout from scratch each time.
// ============================================================================

const (
	templateMinSamples       = 5
	templateMaxBrandHints    = 25
	templateCacheTTL         = 24 * time.Hour
	templateMatchedItemFloor = 0.85 // only feed approved+matched rows into the template
)

// ShopTemplate is the cached layout signature for a (tenant, shop, size_ml).
// Persisted in shop_register_templates so it survives restarts and is shared
// across containers.
type ShopTemplate struct {
	TenantID    uuid.UUID `gorm:"type:uuid;not null;index"`
	ShopID      uuid.UUID `gorm:"type:uuid;not null;index"`
	SizeML      int       `gorm:"not null;index"`
	SampleCount int       `gorm:"not null"`
	// LayoutHash is sha1(stable JSON of column-order signature). Detects when
	// the shopkeeper changes register style mid-quarter.
	LayoutHash string `gorm:"size:40;not null;index"`
	// PromptHint is the rendered hint to inject. Built once at fingerprint
	// time so the hot path is just a string read.
	PromptHint  string    `gorm:"type:text;not null"`
	UpdatedAt   time.Time `gorm:"not null"`
	ApprovedJob string    `gorm:"size:36"` // last contributing job_id, for audit
}

func (ShopTemplate) TableName() string { return "shop_register_templates" }

// shopTemplateCache is an in-memory L1 to keep the hot path under 1ms.
// Backing store is the DB; cache invalidates on TTL or version bump.
type shopTemplateCache struct {
	mu      sync.RWMutex
	entries map[string]cachedTemplate
}

type cachedTemplate struct {
	hint    string
	loaded  time.Time
	exists  bool // negative cache so we don't re-query for shops that never reached the threshold
}

var globalShopTemplateCache = &shopTemplateCache{entries: map[string]cachedTemplate{}}

func shopTemplateKey(tenantID, shopID uuid.UUID, sizeML int) string {
	return fmt.Sprintf("%s/%s/%d", tenantID, shopID, sizeML)
}

// ResolveTemplateHint returns the prompt hint for a (tenant,shop,size) — empty
// string when no template exists yet. Uses L1 cache with TTL fallback to DB.
func (s *SmartStockSetupService) ResolveTemplateHint(tenantID, shopID uuid.UUID, sizeML int) string {
	if sizeML <= 0 || tenantID == uuid.Nil || shopID == uuid.Nil {
		return ""
	}
	key := shopTemplateKey(tenantID, shopID, sizeML)

	globalShopTemplateCache.mu.RLock()
	c, ok := globalShopTemplateCache.entries[key]
	globalShopTemplateCache.mu.RUnlock()
	if ok && time.Since(c.loaded) < templateCacheTTL {
		return c.hint
	}

	var t ShopTemplate
	err := s.db.Where("tenant_id = ? AND shop_id = ? AND size_ml = ?", tenantID, shopID, sizeML).
		Order("updated_at DESC").
		First(&t).Error
	hint := ""
	exists := false
	if err == nil && t.SampleCount >= templateMinSamples {
		hint = t.PromptHint
		exists = true
	} else if err != nil && err != gorm.ErrRecordNotFound {
		log.Printf("Smart Stock Setup: template lookup failed (%s, %d): %v — proceeding without hint", shopID, sizeML, err)
	}

	globalShopTemplateCache.mu.Lock()
	globalShopTemplateCache.entries[key] = cachedTemplate{
		hint: hint, loaded: time.Now(), exists: exists,
	}
	globalShopTemplateCache.mu.Unlock()
	return hint
}

// RecordTemplateContribution is called from the approve path after a setup
// record is approved. It contributes that job's matched-row layout to the
// running template for this (shop, size). Async + idempotent.
func (s *SmartStockSetupService) RecordTemplateContribution(tenantID, shopID uuid.UUID, sizeML int, jobID string, items []SmartStockSetupExtractedItem) {
	if sizeML <= 0 || len(items) == 0 {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("Smart Stock Setup: template contribution panic recovered (job %s): %v", jobID, r)
			}
		}()

		// Build layout signature from approved-and-matched rows only.
		// Keeps the template clean of phantoms / user-rejected rows.
		var brands []string
		var maxRow int
		for _, it := range items {
			if it.Status != "matched" || it.MatchConfidence < templateMatchedItemFloor {
				continue
			}
			if it.RowNumber > maxRow {
				maxRow = it.RowNumber
			}
			name := strings.TrimSpace(firstNonEmpty(it.MatchedDisplayName, it.MatchedFullName, it.BrandName))
			if name != "" {
				brands = append(brands, name)
			}
		}
		if len(brands) < 5 {
			return // not enough signal yet
		}
		// Stable sort + dedupe so the layout-hash is deterministic.
		sort.Strings(brands)
		brands = uniqueStrings(brands)

		layoutSig := struct {
			RowCountBucket int      `json:"row_count_bucket"`
			Brands         []string `json:"brands"`
		}{
			RowCountBucket: bucketRowCount(maxRow),
			Brands:         brands,
		}
		sigBytes, _ := json.Marshal(layoutSig)
		h := sha1.Sum(sigBytes)
		layoutHash := hex.EncodeToString(h[:])

		// Render the hint. Trimmed list of frequent brands so the prompt
		// stays compact.
		topBrands := brands
		if len(topBrands) > templateMaxBrandHints {
			topBrands = topBrands[:templateMaxBrandHints]
		}
		hint := fmt.Sprintf(
			"\n\nSHOP-SPECIFIC TEMPLATE HINT (this shop has done %d+ stock setups at %dML):\n"+
				"- Expect ~%d preprinted rows on a typical page.\n"+
				"- Brands frequently seen here include: %s.\n"+
				"- If a row is illegible, prefer a brand from this list before suggesting auto_create.\n",
			templateMinSamples, sizeML, bucketRowCount(maxRow), strings.Join(topBrands, "; "),
		)

		// Upsert.
		var existing ShopTemplate
		err := s.db.Where("tenant_id = ? AND shop_id = ? AND size_ml = ?", tenantID, shopID, sizeML).First(&existing).Error
		if err == gorm.ErrRecordNotFound {
			row := ShopTemplate{
				TenantID:    tenantID,
				ShopID:      shopID,
				SizeML:      sizeML,
				SampleCount: 1,
				LayoutHash:  layoutHash,
				PromptHint:  hint,
				UpdatedAt:   time.Now(),
				ApprovedJob: jobID,
			}
			if err := s.db.Create(&row).Error; err != nil {
				log.Printf("Smart Stock Setup: template insert failed (job %s): %v", jobID, err)
				return
			}
			log.Printf("Smart Stock Setup: template seeded (shop=%s size=%dML samples=1)", shopID, sizeML)
		} else if err == nil {
			existing.SampleCount++
			existing.LayoutHash = layoutHash
			existing.PromptHint = hint
			existing.UpdatedAt = time.Now()
			existing.ApprovedJob = jobID
			if err := s.db.Save(&existing).Error; err != nil {
				log.Printf("Smart Stock Setup: template upsert failed (job %s): %v", jobID, err)
				return
			}
			log.Printf("Smart Stock Setup: template updated (shop=%s size=%dML samples=%d, hash=%s)",
				shopID, sizeML, existing.SampleCount, layoutHash[:8])
		} else {
			log.Printf("Smart Stock Setup: template lookup-for-upsert failed (job %s): %v", jobID, err)
			return
		}

		// Invalidate L1.
		key := shopTemplateKey(tenantID, shopID, sizeML)
		globalShopTemplateCache.mu.Lock()
		delete(globalShopTemplateCache.entries, key)
		globalShopTemplateCache.mu.Unlock()
	}()
}

// bucketRowCount rounds row count to the nearest 5 so the layout hash is
// stable across small variations (some pages are 28, others 32 — same template).
func bucketRowCount(n int) int {
	if n <= 0 {
		return 0
	}
	return ((n + 2) / 5) * 5
}

// uniqueStrings returns a copy of the slice with duplicates removed.
// Input must be sorted.
func uniqueStrings(in []string) []string {
	if len(in) == 0 {
		return in
	}
	out := in[:1]
	for _, s := range in[1:] {
		if s != out[len(out)-1] {
			out = append(out, s)
		}
	}
	return out
}

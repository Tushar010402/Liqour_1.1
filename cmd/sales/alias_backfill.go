package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/alias"
	"github.com/liquorpro/go-backend/pkg/shared/cache"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/sirupsen/logrus"
)

// runAliasBackfill scans the last N days of approved daily_sales_items and
// writes (ocr_brand_name → product.name) alias rows the live LearnAliasScoped
// hygiene allows through. The goal is to bootstrap the alias table from
// operator-confirmed truth so future Textract / Sonnet extractions hit the
// alias loop on day 1 instead of waiting weeks for organic learning.
//
// Usage:
//   /tmp/sales-bench --alias-backfill --tenant <uuid> [--days 30] [--dry-run]
//
// Idempotent: hygiene gates + ON CONFLICT DO UPDATE in LearnAliasScoped mean
// re-running adds nothing on a stable corpus. Each run logs counts of
// rejected vs accepted vs duplicate rows so the operator can audit.
//
// v1.0.167 D4.
func runAliasBackfill() {
	fs := flag.NewFlagSet("alias-backfill", flag.ExitOnError)
	tenantArg := fs.String("tenant", "", "tenant uuid (required)")
	daysArg := fs.Int("days", 30, "look back this many days of approved sales")
	dryArg := fs.Bool("dry-run", false, "log but don't write")
	_ = fs.Parse(os.Args[2:])

	if *tenantArg == "" {
		log.Fatalf("alias-backfill: --tenant required")
	}
	tenantID, err := uuid.Parse(*tenantArg)
	if err != nil {
		log.Fatalf("alias-backfill: invalid tenant uuid: %v", err)
	}

	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("alias-backfill: config: %v", err)
	}
	db, err := database.NewDatabase(database.Config{
		Host: cfg.Database.Host, Port: cfg.Database.Port,
		User: cfg.Database.User, Password: cfg.Database.Password,
		DBName: cfg.Database.DBName, SSLMode: cfg.Database.SSLMode, TimeZone: cfg.Database.TimeZone,
	})
	if err != nil {
		log.Fatalf("alias-backfill: db: %v", err)
	}
	defer db.Close()

	redisCache, err := cache.NewCache(cache.Config{
		Host: cfg.Redis.Host, Port: cfg.Redis.Port, Password: cfg.Redis.Password, DB: cfg.Redis.DB,
	})
	if err != nil {
		log.Fatalf("alias-backfill: redis: %v", err)
	}
	defer redisCache.Close()

	logger := logrus.New()
	logger.SetLevel(logrus.WarnLevel)
	_ = logger
	aliasService := alias.NewAliasService(db)

	// Pull (ocr_brand_name, product_name, shop_id) tuples from approved sales
	// where the OCR text is meaningfully different from the canonical name —
	// otherwise we'd just write trivial self-aliases that already exist.
	type row struct {
		OCRText      string    `gorm:"column:ocr_brand_name"`
		ProductName  string    `gorm:"column:product_name"`
		ProductID    uuid.UUID `gorm:"column:product_id"`
		ShopID       uuid.UUID `gorm:"column:shop_id"`
		Occurrences  int       `gorm:"column:occurrences"`
	}
	var rows []row
	since := time.Now().AddDate(0, 0, -*daysArg)
	err = db.Raw(`
		SELECT
		  TRIM(dsi.ocr_brand_name) AS ocr_brand_name,
		  p.name AS product_name,
		  dsi.product_id AS product_id,
		  dsr.shop_id AS shop_id,
		  COUNT(*) AS occurrences
		FROM daily_sales_items dsi
		JOIN daily_sales_records dsr ON dsr.id = dsi.daily_sales_record_id
		JOIN products p ON p.id = dsi.product_id
		WHERE dsr.tenant_id = ?
		  AND dsr.deleted_at IS NULL
		  AND dsi.deleted_at IS NULL
		  AND dsr.status = 'approved'
		  AND dsr.record_date >= ?
		  AND COALESCE(NULLIF(TRIM(dsi.ocr_brand_name),''),'') <> ''
		  AND LOWER(TRIM(dsi.ocr_brand_name)) <> LOWER(p.name)
		GROUP BY TRIM(dsi.ocr_brand_name), p.name, dsi.product_id, dsr.shop_id
		ORDER BY occurrences DESC
	`, tenantID, since).Scan(&rows).Error
	if err != nil {
		log.Fatalf("alias-backfill: query: %v", err)
	}

	// v1.0.172 — also harvest aliases from approved Stock Setup records.
	// raw_ai_extraction stores both the AI's interpreted brand
	// (`ai_brand`) and the raw register OCR text (`ocr_text`) — both are
	// excellent alias candidates because the operator approved the row.
	// Many shop-floor variants ("Magic Movement Jamun" → M2 Magic Moments
	// Jamun Spicymint) are captured here that don't appear in sales data.
	var stockRows []row
	_ = db.Raw(`
		SELECT
		  TRIM(COALESCE(ssi.raw_ai_extraction->>'ai_brand', ssi.raw_ai_extraction->>'ocr_text', '')) AS ocr_brand_name,
		  p.name AS product_name,
		  ssi.product_id AS product_id,
		  ssr.shop_id AS shop_id,
		  COUNT(*) AS occurrences
		FROM stock_setup_items ssi
		JOIN stock_setup_records ssr ON ssr.id = ssi.stock_setup_record_id
		JOIN products p ON p.id = ssi.product_id
		WHERE ssi.tenant_id = ?
		  AND ssr.deleted_at IS NULL
		  AND ssi.deleted_at IS NULL
		  AND ssr.status = 'approved'
		  AND ssr.created_at >= ?
		  AND ssi.raw_ai_extraction IS NOT NULL
		  AND COALESCE(ssi.raw_ai_extraction->>'ai_brand', ssi.raw_ai_extraction->>'ocr_text', '') <> ''
		  AND LOWER(TRIM(COALESCE(ssi.raw_ai_extraction->>'ai_brand', ssi.raw_ai_extraction->>'ocr_text', ''))) <> LOWER(p.name)
		GROUP BY TRIM(COALESCE(ssi.raw_ai_extraction->>'ai_brand', ssi.raw_ai_extraction->>'ocr_text', '')), p.name, ssi.product_id, ssr.shop_id
		ORDER BY occurrences DESC
	`, tenantID, since).Scan(&stockRows).Error

	// Dedup: prefer sales row over stock-setup row when same alias exists in both.
	seenKey := map[string]bool{}
	for _, r := range rows {
		seenKey[strings.ToLower(strings.TrimSpace(r.OCRText))+"|"+r.ProductID.String()] = true
	}
	stockAdds := 0
	for _, r := range stockRows {
		k := strings.ToLower(strings.TrimSpace(r.OCRText)) + "|" + r.ProductID.String()
		if seenKey[k] {
			continue
		}
		rows = append(rows, r)
		seenKey[k] = true
		stockAdds++
	}

	log.Printf("alias-backfill: tenant=%s days=%d sales_rows=%d stock_setup_rows_added=%d total=%d dry_run=%v",
		tenantID, *daysArg, len(rows)-stockAdds, stockAdds, len(rows), *dryArg)

	accepted := 0
	rejectedShort := 0
	rejectedSelf := 0
	rejectedJaccard := 0
	for _, r := range rows {
		ocr := strings.TrimSpace(r.OCRText)
		canon := strings.TrimSpace(r.ProductName)
		if len(ocr) < 2 {
			rejectedShort++
			continue
		}
		if strings.EqualFold(ocr, canon) {
			rejectedSelf++
			continue
		}
		// Cheap pre-filter equivalent to LearnAliasScoped's jaccard guard.
		// Avoids burning a DB roundtrip on obvious garbage.
		if aliasJaccardLocal(ocr, canon) < 0.20 {
			rejectedJaccard++
			continue
		}
		if *dryArg {
			accepted++
			if accepted <= 25 {
				log.Printf("  [dry] '%s' → '%s' (shop=%s, occ=%d)", ocr, canon, r.ShopID, r.Occurrences)
			}
			continue
		}
		pid := r.ProductID
		// Shop-scoped alias write — anchors the lesson to the shop where the
		// operator confirmed it.
		if err := aliasService.LearnAliasScoped(tenantID, r.ShopID, ocr, canon, &pid, "approved_history"); err != nil {
			log.Printf("  [warn] LearnAliasScoped failed for '%s' → '%s': %v", ocr, canon, err)
			continue
		}
		accepted++
	}

	log.Printf("alias-backfill DONE: accepted=%d rejected_short=%d rejected_self=%d rejected_jaccard=%d total=%d",
		accepted, rejectedShort, rejectedSelf, rejectedJaccard, len(rows))
	if *dryArg {
		log.Printf("alias-backfill: dry run — no writes performed. Re-run without --dry-run to commit.")
	}
}

// aliasJaccardLocal mirrors the alias service's hygiene jaccard but stays
// in this binary so the backfill doesn't need to re-export the helper.
func aliasJaccardLocal(a, b string) float64 {
	ta := tokenizeAliasLocal(a)
	tb := tokenizeAliasLocal(b)
	if len(ta) == 0 || len(tb) == 0 {
		return 0
	}
	inter := 0
	for k := range ta {
		if _, ok := tb[k]; ok {
			inter++
		}
	}
	un := len(ta) + len(tb) - inter
	if un == 0 {
		return 0
	}
	return float64(inter) / float64(un)
}

func tokenizeAliasLocal(s string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, t := range strings.Fields(strings.ToLower(s)) {
		t = strings.TrimFunc(t, func(r rune) bool {
			return !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9')
		})
		if len(t) >= 2 {
			out[t] = struct{}{}
		}
	}
	return out
}

// (compile guard — keep imports referenced even if dry-run path skips them)
var _ = fmt.Sprintf

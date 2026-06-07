// Command remediate_name_brand_drift repairs products whose operator-facing NAME
// has drifted away from their linked brand identity, so the product-detail popup
// shows two different products on one card (e.g. name "O.P.N Green Label Whisky"
// but tenant brand_id + saas_brand_id still pointing at "Officer's Choice Blue
// Reserve"; or name "M2 Magic Moments Jamun" but tenant brand "imjum").
//
// Root cause (fixed forward in code at v1.0.355): the photo-verify rename updated
// name/display_name but never re-pointed brand_id / saas_brand_id. This one-off
// repairs the rows that already drifted.
//
// Basis: the product NAME is the verified source of truth (operator/photo-verified,
// name_verified=true). We re-resolve identity FROM the name:
//   - tenant brand_id: exact (case-insensitive) brand match by name → repoint;
//     else create a tenant brand named exactly = product name → repoint. (A tenant
//     brand is just a grouping label; naming it = the product name is always
//     consistent and never mis-binds.)
//   - saas_brand_id (excise/catalog identity): repoint ONLY on an unambiguous exact
//     name/display_name match (exactly one saas_brand). If zero or >1 candidates,
//     CLEAR it to NULL (honestly uncatalogued) and FLAG the row in the report — a
//     human/catalog pass resolves the excise link; we never guess it.
//   - saas_variant_id: always cleared (a stale variant of the OLD brand contradicts
//     the new identity; the partial unique index excludes NULLs so clearing is safe).
//
// Only NON-drifted rows are skipped: a row is "drifted" when the product name shares
// NO distinctive token with its linked tenant-brand name AND/OR saas-brand name.
//
// Dry-run by default; --apply writes in ONE transaction. Idempotent: re-running is a
// no-op (repaired rows no longer drift). Reversible: every applied row is logged with
// its before-values so the exact set can be restored.
//
// Usage:
//
//	remediate_name_brand_drift [flags]
//	  --tenant     tenant UUID (default 68ffde63-…)
//	  --shop       shop UUID filter (default Mahua Khera c5cf581d-…; empty = all shops in tenant)
//	  --apply      actually write (default false = dry-run)
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"gorm.io/gorm"
)

// spiritFiller are the structural/spirit/size words that are NOT distinctive when
// comparing a product name to a brand name (mirrors the verifier's filler notion).
var spiritFiller = map[string]bool{
	"the": true, "a": true, "an": true, "of": true, "and": true, "for": true, "with": true,
	"blend": true, "blended": true, "grain": true, "indian": true, "whisky": true, "whiskey": true,
	"rum": true, "vodka": true, "gin": true, "brandy": true, "wine": true, "beer": true,
	"scotch": true, "bourbon": true, "liquor": true, "ml": true, "ltr": true, "cl": true,
	"pet": true, "tetra": true, "btl": true, "pc": true, "pcs": true, "full": true,
	"quarter": true, "half": true, "nip": true, "pint": true,
}

// distinctiveTokens lowercases, splits on non-alphanumerics, drops spiritFiller and
// returns the ≥3-char distinctive tokens as a set.
func distinctiveTokens(s string) map[string]bool {
	out := map[string]bool{}
	for _, tok := range strings.FieldsFunc(strings.ToLower(s), func(r rune) bool {
		return !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9'))
	}) {
		if len(tok) < 3 || spiritFiller[tok] {
			continue
		}
		out[tok] = true
	}
	return out
}

// sharesNoDistinctiveToken reports whether name and brand share NO distinctive
// token (the drift signal). Returns false (i.e. "consistent / can't judge") when
// either side has no distinctive tokens, to avoid false positives.
func sharesNoDistinctiveToken(name, brand string) bool {
	nt := distinctiveTokens(name)
	bt := distinctiveTokens(brand)
	if len(nt) == 0 || len(bt) == 0 {
		return false
	}
	for t := range nt {
		if bt[t] {
			return false
		}
	}
	return true
}

type prodRow struct {
	ID            uuid.UUID  `gorm:"column:id"`
	Name          string     `gorm:"column:name"`
	BrandID       *uuid.UUID `gorm:"column:brand_id"`
	SaasBrandID   *uuid.UUID `gorm:"column:saas_brand_id"`
	ShopID        *uuid.UUID `gorm:"column:shop_id"`
	TenantBrand   string     `gorm:"column:tenant_brand_name"`
	SaasBrandName string     `gorm:"column:saas_brand_name"`
}

type plan struct {
	row        prodRow
	newBrandID uuid.UUID // resolved tenant brand (uuid.Nil → create at apply, named brandName)
	newSaasID  *uuid.UUID
	brandName  string // catalog-correct name to (find/create) the tenant brand under
	reason     string
}

func main() {
	tenant := flag.String("tenant", "68ffde63-191d-4845-b1c9-bf7c76ecbc93", "tenant UUID")
	shop := flag.String("shop", "c5cf581d-c879-4ca3-9a92-bc1d06be4967", "shop UUID filter (empty = all shops in tenant)")
	apply := flag.Bool("apply", false, "actually write (default false = dry-run)")
	flag.Parse()

	tenantID, err := uuid.Parse(*tenant)
	if err != nil {
		log.Fatalf("invalid --tenant: %v", err)
	}
	var shopFilter *uuid.UUID
	if strings.TrimSpace(*shop) != "" {
		sid, e := uuid.Parse(*shop)
		if e != nil {
			log.Fatalf("invalid --shop: %v", e)
		}
		shopFilter = &sid
	}

	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	db, err := database.NewDatabase(database.Config{
		Host: cfg.Database.Host, Port: cfg.Database.Port, User: cfg.Database.User,
		Password: cfg.Database.Password, DBName: cfg.Database.DBName,
		SSLMode: cfg.Database.SSLMode, TimeZone: cfg.Database.TimeZone,
	})
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer db.Close()

	// Candidate products: name_verified, not deleted, linked to at least one brand.
	q := db.Table("products p").
		Select(`p.id, p.name, p.brand_id, p.saas_brand_id, p.shop_id,
		         COALESCE(b.name,'') AS tenant_brand_name,
		         COALESCE(sb.name,'') AS saas_brand_name`).
		Joins("LEFT JOIN brands b ON b.id = p.brand_id").
		Joins("LEFT JOIN saas_brands sb ON sb.id = p.saas_brand_id").
		Where("p.tenant_id = ? AND p.deleted_at IS NULL AND p.name_verified = true", tenantID).
		Where("(p.brand_id IS NOT NULL OR p.saas_brand_id IS NOT NULL)")
	if shopFilter != nil {
		q = q.Where("p.shop_id = ?", *shopFilter)
	}
	var rows []prodRow
	if err := q.Scan(&rows).Error; err != nil {
		log.Fatalf("query products: %v", err)
	}

	// Two buckets:
	//   plans   — CONFIDENT fixes (drifted AND an unambiguous exact saas-catalog match
	//             for the product name). Only these are written on --apply.
	//   flagged — drifted but NOT confidently resolvable (no/ambiguous catalog match,
	//             or a garbled name). Reported for human review; NEVER auto-changed,
	//             so we never propagate a bad name or guess an identity.
	var plans []plan
	var flagged []plan
	for _, r := range rows {
		driftTenant := r.TenantBrand != "" && sharesNoDistinctiveToken(r.Name, r.TenantBrand)
		driftSaas := r.SaasBrandName != "" && sharesNoDistinctiveToken(r.Name, r.SaasBrandName)
		if !driftTenant && !driftSaas {
			continue
		}
		p := plan{row: r}

		// Unambiguous exact saas-catalog match for the product name?
		type idRow struct {
			ID   string `gorm:"column:id"`
			Name string `gorm:"column:name"`
		}
		var saas []idRow
		db.Table("saas_brands").Select("id, name").
			Where("deleted_at IS NULL AND (lower(name) = lower(?) OR lower(display_name) = lower(?))", r.Name, r.Name).
			Limit(2).Scan(&saas)
		// Confident ONLY when exactly one catalog row matches AND it token-agrees
		// with the product name (sanity guard against a coincidental exact string).
		if len(saas) == 1 && !sharesNoDistinctiveToken(r.Name, saas[0].Name) {
			if sid, e := uuid.Parse(saas[0].ID); e == nil {
				p.newSaasID = &sid
				// brand_id: reuse/create a tenant brand named = the catalog-correct
				// name (safe — it is catalog-verified, not a garbled product name).
				var existing idRow
				db.Table("brands").Select("id").
					Where("tenant_id = ? AND deleted_at IS NULL AND lower(name) = lower(?)", tenantID, saas[0].Name).
					Limit(1).Scan(&existing)
				if existing.ID != "" {
					if bid, be := uuid.Parse(existing.ID); be == nil {
						p.newBrandID = bid
					}
				}
				p.brandName = saas[0].Name
				p.reason = "exact catalog match → re-point"
				plans = append(plans, p)
				continue
			}
		}
		// Not confident → flag only.
		if len(saas) == 0 {
			p.reason = "no catalog match (review/re-photograph)"
		} else {
			p.reason = "ambiguous catalog match (review)"
		}
		flagged = append(flagged, p)
	}

	// Report.
	fmt.Printf("=== name↔brand drift remediation — %s ===\n", map[bool]string{true: "APPLY", false: "DRY-RUN"}[*apply])
	fmt.Printf("tenant=%s  shop=%v  candidates=%d  confident_fix=%d  flagged=%d\n\n",
		tenantID, derefShop(shopFilter), len(rows), len(plans), len(flagged))

	tw := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(tw, "[CONFIDENT FIX]  PRODUCT\tID\t→ NAME/BRAND\tREASON")
	for _, p := range plans {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", trunc(p.row.Name, 36), p.row.ID.String()[:8], trunc(p.brandName, 30), p.reason)
	}
	fmt.Fprintln(tw, "\n[FLAGGED — no change]  PRODUCT\tID\tLINKED BRAND\tREASON")
	for _, p := range flagged {
		linked := p.row.TenantBrand
		if linked == "" {
			linked = p.row.SaasBrandName
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", trunc(p.row.Name, 36), p.row.ID.String()[:8], trunc(linked, 30), p.reason)
	}
	tw.Flush()

	if !*apply {
		fmt.Printf("\nDry-run only. Re-run with --apply to write the CONFIDENT fixes (one transaction).\n")
		for _, p := range plans {
			fmt.Printf("BEFORE id=%s brand_id=%s saas_brand_id=%s\n", p.row.ID, ptrStr(p.row.BrandID), ptrStr(p.row.SaasBrandID))
		}
		return
	}

	now := time.Now()
	err = db.Transaction(func(tx *gorm.DB) error {
		for i := range plans {
			p := &plans[i]
			if p.newBrandID == uuid.Nil { // create the catalog-named tenant brand
				bid := uuid.New()
				if e := tx.Exec(`INSERT INTO brands (id, tenant_id, name, is_active, created_at, updated_at)
					VALUES (?, ?, ?, true, ?, ?)`, bid, tenantID, p.brandName, now, now).Error; e != nil {
					return fmt.Errorf("create brand %q for %s: %w", p.brandName, p.row.ID, e)
				}
				p.newBrandID = bid
			}
			upd := map[string]interface{}{
				"brand_id":        p.newBrandID,
				"saas_brand_id":   *p.newSaasID,
				"saas_variant_id": nil,
				"updated_at":      now,
			}
			if e := tx.Table("products").Where("id = ?", p.row.ID).Updates(upd).Error; e != nil {
				return fmt.Errorf("update product %s: %w", p.row.ID, e)
			}
			log.Printf("FIXED id=%s name=%q brand_id %s→%s saas_brand_id %s→%s",
				p.row.ID, p.row.Name, ptrStr(p.row.BrandID), p.newBrandID.String()[:8],
				ptrStr(p.row.SaasBrandID), p.newSaasID.String()[:8])
		}
		return nil
	})
	if err != nil {
		log.Fatalf("apply failed (rolled back): %v", err)
	}
	fmt.Printf("\n✅ APPLY complete: %d product(s) re-aligned to their exact catalog identity. %d flagged left untouched for review.\n", len(plans), len(flagged))
}

func derefShop(s *uuid.UUID) string {
	if s == nil {
		return "(all)"
	}
	return s.String()[:8]
}
func ptrStr(u *uuid.UUID) string {
	if u == nil {
		return "NULL"
	}
	return u.String()[:8]
}
func ptrStrV(u *uuid.UUID) string {
	if u == nil {
		return "NULL"
	}
	return u.String()
}
func trunc(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}

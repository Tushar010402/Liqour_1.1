// Command remediate_drift_cancellation corrects the stock overstatement caused
// by the opening-drift-reconcile cancellation bug (fixed in code at v1.0.336).
//
// Bug recap: when a backlog of daily-sales records was batch-approved, the
// legacy approve path snapped live stock UP to each record's (identical)
// vouched opening before deducting, writing an `opening_drift_reconcile` ledger
// row each time. Those reconcile rows cancelled the PRIOR record's legitimate
// daily_sale, leaving stock overstated. On Mahua Khera (2026-06-02 batch) this
// overstated 60 stock rows by a total of 1035 units.
//
// Remediation basis (surgical & provably exact): the damage on each stock row
// equals the SUM of the opening_drift_reconcile quantities the bug wrongly added
// to it within the window. Reversing exactly that amount restores the correct
// balance (algebraically liveNow - Σreconcile == firstOpening - soldTotal). The
// reconcile rows carry stock_id, so we target the exact stock row even where a
// product has duplicate stock rows.
//
// Every correction is written as a `manual_correction` StockHistory row plus the
// matching stocks.quantity update, in ONE transaction. Dry-run by default;
// requires --apply to write. Idempotent: re-running after apply is a no-op
// (it skips any stock row that already has this remediation's manual_correction
// row). Reversible: undo with a sign-flipped manual_correction.
//
// Usage:
//
//	remediate_drift_cancellation [flags]
//	  --shop          shop UUID (default: Mahua Khera c5cf581d-…)
//	  --window-start  RFC3339 (default 2026-06-02T12:00:00Z)
//	  --window-end    RFC3339 (default 2026-06-03T12:00:00Z)
//	  --apply         actually write (default false = dry-run)
//	  --actor-id      operator/admin UUID stamped on the correction (required with --apply)
package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"text/tabwriter"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
	"github.com/liquorpro/go-backend/pkg/shared/models"
	"gorm.io/gorm"
)

const remediationReference = "Remediation: drift-reconcile cancellation 2026-06-02 batch"

type affectedRow struct {
	StockID    uuid.UUID  `gorm:"column:stock_id"`
	ProductID  uuid.UUID  `gorm:"column:product_id"`
	TenantID   *uuid.UUID `gorm:"column:tenant_id"`
	ShopID     uuid.UUID  `gorm:"column:shop_id"`
	Name       string     `gorm:"column:name"`
	LiveNow    int        `gorm:"column:live_now"`
	Overstated int        `gorm:"column:overstated"`
}

type correctionPlan struct {
	row     affectedRow
	correct int
	delta   int
}

func main() {
	shop := flag.String("shop", "c5cf581d-c879-4ca3-9a92-bc1d06be4967", "shop UUID to remediate")
	winStart := flag.String("window-start", "2026-06-02T12:00:00Z", "batch window start (RFC3339)")
	winEnd := flag.String("window-end", "2026-06-03T12:00:00Z", "batch window end (RFC3339)")
	apply := flag.Bool("apply", false, "actually write corrections (default false = dry-run)")
	actorID := flag.String("actor-id", "", "operator/admin UUID stamped on each correction (required with --apply)")
	flag.Parse()

	shopID, err := uuid.Parse(*shop)
	if err != nil {
		log.Fatalf("invalid --shop: %v", err)
	}
	start, err := time.Parse(time.RFC3339, *winStart)
	if err != nil {
		log.Fatalf("invalid --window-start: %v", err)
	}
	end, err := time.Parse(time.RFC3339, *winEnd)
	if err != nil {
		log.Fatalf("invalid --window-end: %v", err)
	}
	var actor uuid.UUID
	if *apply {
		actor, err = uuid.Parse(*actorID)
		if err != nil {
			log.Fatalf("--apply requires a valid --actor-id UUID: %v", err)
		}
	}

	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("load config: %v", err)
	}
	db, err := database.NewDatabase(database.Config{
		Host:     cfg.Database.Host,
		Port:     cfg.Database.Port,
		User:     cfg.Database.User,
		Password: cfg.Database.Password,
		DBName:   cfg.Database.DBName,
		SSLMode:  cfg.Database.SSLMode,
		TimeZone: cfg.Database.TimeZone,
	})
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer db.Close()

	// Per affected stock row: Σ(opening_drift_reconcile.quantity) in the window
	// = the exact overstatement to reverse. Join to the live stock + product name.
	var rows []affectedRow
	if err := db.Raw(`
		WITH recon AS (
			SELECT stock_id, SUM(quantity) AS overstated
			FROM stock_histories
			WHERE shop_id = ? AND movement_type = 'opening_drift_reconcile'
			  AND created_at >= ? AND created_at < ?
			GROUP BY stock_id
		)
		SELECT s.id AS stock_id, s.product_id, s.tenant_id, s.shop_id,
		       COALESCE(p.name, '(unknown product)') AS name,
		       s.quantity AS live_now, r.overstated
		FROM recon r
		JOIN stocks s ON s.id = r.stock_id
		LEFT JOIN products p ON p.id = s.product_id
		ORDER BY r.overstated DESC`,
		shopID, start, end).Scan(&rows).Error; err != nil {
		log.Fatalf("query affected rows: %v", err)
	}

	if len(rows) == 0 {
		log.Printf("No affected stock rows found for shop %s in [%s, %s). Nothing to do.", shopID, start, end)
		return
	}

	// Report
	mode := "DRY-RUN (no writes)"
	if *apply {
		mode = "APPLY"
	}
	fmt.Printf("\n=== Drift-reconcile cancellation remediation — %s ===\n", mode)
	fmt.Printf("shop=%s window=[%s, %s)\n\n", shopID, start.Format(time.RFC3339), end.Format(time.RFC3339))

	w := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	fmt.Fprintln(w, "PRODUCT\tSTOCK_ID\tLIVE_NOW\tOVERSTATED\tCORRECT\tDELTA\tACTION")

	var totalOver, totalDelta, willWrite, willSkip, willAbort int
	var toApply []correctionPlan

	for _, r := range rows {
		correct := r.LiveNow - r.Overstated
		delta := correct - r.LiveNow // == -overstated
		action := "WRITE"

		switch {
		case r.Overstated <= 0:
			action = "SKIP(non-positive overstatement)"
			willSkip++
		case correct < 0:
			action = "ABORT(correct<0 — assumption violated)"
			willAbort++
		case delta == 0:
			action = "SKIP(already correct)"
			willSkip++
		default:
			// Idempotency: already remediated?
			var existing int64
			if err := db.Table("stock_histories").
				Where("stock_id = ? AND movement_type = ? AND reference = ?",
					r.StockID, "manual_correction", remediationReference).
				Count(&existing).Error; err != nil {
				log.Fatalf("idempotency check failed for stock %s: %v", r.StockID, err)
			}
			if existing > 0 {
				action = "SKIP(already remediated)"
				willSkip++
			} else {
				willWrite++
				toApply = append(toApply, correctionPlan{row: r, correct: correct, delta: delta})
			}
		}

		totalOver += r.Overstated
		if action == "WRITE" {
			totalDelta += delta
		}
		fmt.Fprintf(w, "%s\t%s\t%d\t%d\t%d\t%d\t%s\n",
			truncate(r.Name, 38), r.StockID.String()[:8], r.LiveNow, r.Overstated, correct, delta, action)
	}
	w.Flush()

	fmt.Printf("\nrows=%d  total_overstated=%d  to_write=%d (net delta %d)  to_skip=%d  to_abort=%d\n",
		len(rows), totalOver, willWrite, totalDelta, willSkip, willAbort)

	if !*apply {
		fmt.Printf("\nDry-run only. Re-run with --apply --actor-id <uuid> to write the %d correction(s).\n", willWrite)
		return
	}
	if willWrite == 0 {
		fmt.Printf("\nNothing to write (idempotent no-op).\n")
		return
	}

	// Apply: one transaction. Each correction = manual_correction ledger row +
	// stocks.quantity update. Fail-loud: any error rolls back the whole batch.
	err = db.Transaction(func(tx *gorm.DB) error {
		return applyAll(tx, toApply, actor)
	})
	if err != nil {
		log.Fatalf("APPLY failed (rolled back, nothing written): %v", err)
	}
	fmt.Printf("\n✅ APPLY complete: %d correction(s) written (net stock delta %d). Reversible via sign-flipped manual_correction.\n", willWrite, totalDelta)
}

func applyAll(tx *gorm.DB, plans []correctionPlan, actor uuid.UUID) error {
	for _, p := range plans {
		r := p.row
		stockRef := r.StockID
		shopRef := r.ShopID
		prodRef := r.ProductID
		hist := models.StockHistory{
			TenantModel:      models.TenantModel{TenantID: r.TenantID},
			StockID:          stockRef,
			ShopID:           &shopRef,
			ProductID:        &prodRef,
			MovementType:     "manual_correction",
			Quantity:         p.delta,
			PreviousQuantity: r.LiveNow,
			NewQuantity:      p.correct,
			Reference:        remediationReference,
			Notes: fmt.Sprintf("Reversed %d units of opening_drift_reconcile cancellation for %s: %d → %d. The reconciles had cancelled prior records' legitimate daily_sale deductions during batch approval.",
				r.Overstated, r.Name, r.LiveNow, p.correct),
			CreatedByID: actor,
		}
		if err := tx.Create(&hist).Error; err != nil {
			return fmt.Errorf("create correction history for stock %s (%s): %w", stockRef, r.Name, err)
		}
		if err := tx.Model(&models.Stock{}).Where("id = ?", stockRef).
			Update("quantity", p.correct).Error; err != nil {
			return fmt.Errorf("update stock %s (%s): %w", stockRef, r.Name, err)
		}
		log.Printf("✅ corrected %s: %d → %d (delta %d)", r.Name, r.LiveNow, p.correct, p.delta)
	}
	return nil
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n-1] + "…"
}

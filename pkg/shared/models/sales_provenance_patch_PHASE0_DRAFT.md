# Track B Phase 0 — Go model + apply-write patch (DRAFT)

This file is a draft, not a build target. Move the changes into
`pkg/shared/models/sales.go` and `internal/sales/services/smart_sale_service.go`
when the operator approves Phase 0.

The migration `migrations/20260527_smart_sale_provenance.sql` has already been
written and dry-run validated. This file is the second half — the Go side that
populates the new columns on apply.

---

## 1) Patch `pkg/shared/models/sales.go` — add provenance fields to `DailySalesItem`

Append the following block to the `DailySalesItem` struct, immediately AFTER the
`Position` field (the last existing field in the struct, line ~239):

```go
// v1.0.327 Track B Phase 0 — provenance for true-AI-accuracy measurement.
//
// Pre-Phase-0 we wrote item.OriginalAIQuantity to OcrTotal and
// item.OriginalAIRate to OcrRate, but OcrTotal/OcrRate are post-voting
// (math-gate auto-fixes can mutate them), so they could not be used to
// separate "AI was wrong, operator fixed" from "AI was right, operator
// made a business edit." The columns below capture AI's FIRST read —
// before any auto-fix, before the matcher rewrote brand text, before the
// operator opened the review screen.
//
// Sweep impact: with these columns populated, qty_match accuracy can be
// computed as
//   count(*) FILTER (WHERE quantity_sold = original_ai_qty) / count(*)
// which is the metric Track B Phase 6 gates on (≥ 0.95).
OriginalAIBrand   *string  `json:"original_ai_brand,omitempty"   gorm:"column:original_ai_brand;type:varchar(255)"`
OriginalAIQty     *int     `json:"original_ai_qty,omitempty"     gorm:"column:original_ai_qty"`
OriginalAIRate    *float64 `json:"original_ai_rate,omitempty"    gorm:"column:original_ai_rate;type:numeric(10,2)"`
WasAICorrected    bool     `json:"was_ai_corrected"              gorm:"column:was_ai_corrected;not null;default:false"`
AIConfidenceQty   *float64 `json:"ai_confidence_qty,omitempty"   gorm:"column:ai_confidence_qty;type:numeric(4,3)"`
AISources         JSONB    `json:"ai_sources,omitempty"          gorm:"column:ai_sources;type:jsonb"`
```

Note: `JSONB` is the existing custom type in `pkg/shared/models/` used by other
jsonb columns (e.g. `Tenant.Settings`). If a different name is in use, swap to
match.

---

## 2) Patch `internal/sales/services/smart_sale_service.go` — populate on apply

Inside `ApplySmartSale` at the `saleItem := models.DailySalesItem{...}`
construction site (currently line 6474), append the following BEFORE the closing
brace. Reads payload fields that the apply path is already passing through
(see lines 263, 338-341 — `OriginalAIBrand`, `OriginalAIQuantity`,
`OriginalAIRate` are already in `SmartSaleApplyItem`):

```go
// v1.0.327 Track B Phase 0 — provenance. Mirror the AI's first read into
// dedicated columns (separate from Ocr* which double as "current state"
// after math-gate fixes). was_ai_corrected captures whether OUR pipeline
// (math gate / invariant gate / cell-level / rate-rescue) changed any
// field vs the raw AI read, distinct from a downstream operator edit.
if strings.TrimSpace(item.OriginalAIBrand) != "" {
    aiBrand := item.OriginalAIBrand
    saleItem.OriginalAIBrand = &aiBrand
}
if item.OriginalAIQuantity != nil {
    saleItem.OriginalAIQty = item.OriginalAIQuantity
}
if item.OriginalAIRate != nil {
    saleItem.OriginalAIRate = item.OriginalAIRate
}
// Pipeline-corrected detection: brand mismatch (matcher overwrote) OR
// qty mismatch (math gate fired) OR rate mismatch (rate-rescue fired).
// All three are pre-operator-edit; operator edits are captured separately
// via the existing was_corrected flag on the apply payload.
if (item.OriginalAIBrand != "" && !strings.EqualFold(item.OriginalAIBrand, item.BrandName)) ||
    (item.OriginalAIQuantity != nil && *item.OriginalAIQuantity != item.Quantity) ||
    (item.OriginalAIRate != nil && math.Abs(*item.OriginalAIRate-item.Rate) > 0.01) {
    saleItem.WasAICorrected = true
}
// ai_confidence_qty is optional — only set when the apply payload carries
// per-cell confidence (Flutter doesn't echo this yet; future Phase 2
// voting will write it directly server-side).
if item.AIConfidenceQty != nil {
    saleItem.AIConfidenceQty = item.AIConfidenceQty
}
// ai_sources is structured voting trail; populated server-side by Phase 2
// when multi-source resolution is wired in. Leave nil on Phase 0.
```

This patch requires adding `AIConfidenceQty *float64` to `SmartSaleApplyItem`
(the apply request struct, currently around line 256) AND importing `math` if
not already imported (it is — used by rate comparison elsewhere).

---

## 3) Sweep impact validation (NOT yet implemented — Phase 6)

Once apply writes provenance for ~50 records of operator activity, the sweep at
`/root/sweep_eval_real.py` can add a new metric block:

```python
# Section: true AI accuracy (Track B Phase 0 measurement)
out = psql("""
    SELECT
        count(*) FILTER (WHERE quantity_sold = original_ai_qty) AS qty_exact,
        count(*) FILTER (WHERE quantity_sold = original_ai_qty AND NOT was_ai_corrected) AS pure_ai_correct,
        count(*) FILTER (WHERE was_ai_corrected) AS pipeline_fixed,
        count(*) AS total
    FROM daily_sales_items
    WHERE original_ai_qty IS NOT NULL
      AND created_at > '2026-05-27 00:00:00';
""")
# True AI accuracy = pure_ai_correct / total
# Pipeline lift   = (qty_exact - pure_ai_correct) / total
# Honest gap     = total - qty_exact (this is what the operator actually edited)
```

This separates three numbers that today are conflated into one:
- True AI accuracy (no pipeline help, no operator help)
- Pipeline lift (how much our gates / rescues add on top of raw AI)
- Operator gap (how much the human still has to edit)

The 95% target in Track B Phase 6 is on `(pure_ai_correct + pipeline_fixed) / total`
— i.e. accuracy before the operator touches it. That is what 100%-accurate would
literally mean: zero operator edits required.

---

## Apply order (when approved)

1. Apply the migration: `docker exec -i liquorpro-postgres-prod psql -U liquorpro_prod -d liquorpro_production < /var/www/liquorpro/migrations/20260527_smart_sale_provenance.sql`
2. Patch `sales.go` (struct fields above)
3. Patch `smart_sale_service.go` (apply-write block above)
4. Patch `SmartSaleApplyItem` to add `AIConfidenceQty *float64` JSON field
5. Build new sales image: `docker build -t liquorpro/sales:v1.0.327 ./internal/sales`
6. Update production compose VERSION + restart sales container
7. After ~24h of operator activity, run the sweep with the new metric block above
8. Report true AI accuracy number to operator

Rollback (column-by-column drop):
```sql
ALTER TABLE daily_sales_items
    DROP COLUMN IF EXISTS ai_sources,
    DROP COLUMN IF EXISTS ai_confidence_qty,
    DROP COLUMN IF EXISTS was_ai_corrected,
    DROP COLUMN IF EXISTS original_ai_rate,
    DROP COLUMN IF EXISTS original_ai_qty,
    DROP COLUMN IF EXISTS original_ai_brand;
DROP INDEX IF EXISTS idx_daily_sales_items_original_ai_qty;
```

The new code does not break on missing columns (all reads guarded by
`if item.OriginalAI* != nil`); a partial rollback (only drop the columns,
revert the code separately) is safe.

-- Track B Phase 0 — Smart Sale provenance schema.
--
-- Today daily_sales_items has only the final (post-edit) quantity_sold,
-- unit_price, and ocr_brand_name. There is no way to tell, after the fact,
-- whether a row that differs from the original AI extraction differs because
-- (a) the AI was wrong and the operator fixed it, or
-- (b) the AI was right and the operator made a business edit (return / split).
--
-- The Track A forensic showed this is the load-bearing measurement gap:
-- the sweep's qty-match metric (76.9% live blended) conflates both, so it has
-- no honest 100% ceiling. Without provenance the team cannot tell which fixes
-- moved AI accuracy vs which only moved operator workload.
--
-- This migration adds the minimum columns required to compute true AI accuracy
-- on every approve going forward:
--
--   original_ai_brand   - AI's first read of the brand text (post-OCR,
--                         pre-matcher). Comparing to ocr_brand_name (the
--                         current "what AI said" field) tells us whether the
--                         matcher rewrote the brand or the operator did.
--   original_ai_qty     - AI's first read of the sale quantity, before any
--                         math-gate auto-fix, invariant-gate auto-fix, or
--                         operator edit. (quantity_sold today is post-edit.)
--   original_ai_rate    - AI's first read of the per-unit rate. (unit_price
--                         today is post-edit; ocr_rate is set but blends with
--                         our internal rate-rescue picks.)
--   was_ai_corrected    - true iff our voting pipeline (math gate, invariant
--                         gate, cell-level all-fields, rate-rescue, etc.)
--                         changed AT LEAST ONE of brand/qty/rate vs the raw
--                         AI extraction. Distinguishes our auto-fixes from
--                         operator edits.
--   ai_confidence_qty   - the per-cell confidence (0..1) of the quantity
--                         field after voting but before any operator edit.
--                         Lets the sweep filter "high-confidence wrong" rows
--                         from "low-confidence wrong" rows separately.
--   ai_sources          - jsonb keyed by field name ("brand","qty","rate",
--                         "opening","closing"); each value is an array of
--                         {source, value, confidence} from textract / claude /
--                         gemini / catalog / cnn etc. Records the full voting
--                         trail so future fixes can be evaluated against the
--                         votes already cast.
--
-- All columns are nullable (legacy rows keep NULL) and additive — the
-- migration is safe to run on a live database with no downtime. Rollback
-- is column-by-column DROP if needed.
--
-- Apply wiring (separate code change, NOT part of this migration):
--   internal/sales/services/smart_sale_service.go around the
--   INSERT INTO daily_sales_items block (currently ~line 2150-2200).
--
-- Sweep impact: once this is populated, the sweep at /root/sweep_eval_real.py
-- can compute true AI accuracy ignoring operator business edits:
--   count(*) FILTER (WHERE quantity_sold = original_ai_qty) / count(*)
-- That is the metric Track B Phase 6 will gate on (≥0.95).

ALTER TABLE daily_sales_items
    ADD COLUMN IF NOT EXISTS original_ai_brand    VARCHAR(255),
    ADD COLUMN IF NOT EXISTS original_ai_qty      INTEGER,
    ADD COLUMN IF NOT EXISTS original_ai_rate     NUMERIC(10, 2),
    ADD COLUMN IF NOT EXISTS was_ai_corrected     BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS ai_confidence_qty    NUMERIC(4, 3),
    ADD COLUMN IF NOT EXISTS ai_sources           JSONB;

-- Index supports the Phase 6 sweep query:
--   SELECT COUNT(*) FILTER (WHERE quantity_sold = original_ai_qty) / COUNT(*)
--   FROM daily_sales_items WHERE original_ai_qty IS NOT NULL
--   AND created_at > '<ship_date>';
-- Partial so we don't index the legacy NULL rows.
CREATE INDEX IF NOT EXISTS idx_daily_sales_items_original_ai_qty
    ON daily_sales_items (created_at)
    WHERE original_ai_qty IS NOT NULL;

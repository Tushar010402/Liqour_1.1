-- v1.0.133: per-shop handwriting / digit-shape learning.
--
-- When a user corrects a numeric cell on the Stock Setup or Smart Sale review
-- screen (qty/opening/receipt/sale/closing/rate/amount), capture the AI's raw
-- read vs the user's correction here. Aggregated by (tenant, shop, field,
-- raw_value, corrected_value) so common confusions (this shop's "7" reads
-- as "1" three times) bubble to the top. The Stock Setup + Smart Sale
-- extractor prompts then inject the top-N most-frequent (raw → corrected)
-- pairs as few-shot guidance: "at this shop the AI has previously misread
-- raw 7 as 1, raw 5 as 6 — verify carefully."
--
-- This is shop-scoped because handwriting varies per writer; one shop's
-- "1 with a flag" is another shop's "7 with a hook." Tenant-scoped fallback
-- is the obvious next step but keep it simple for the first cut.
CREATE TABLE IF NOT EXISTS ocr_digit_corrections (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         UUID NOT NULL,
  shop_id           UUID NOT NULL,
  source            VARCHAR(32) NOT NULL,    -- 'stock_setup' | 'smart_sale'
  field             VARCHAR(32) NOT NULL,    -- 'opening' | 'receipt' | 'sale' | 'closing' | 'rate' | 'amount' | 'quantity'
  raw_value         VARCHAR(32) NOT NULL,    -- AI's raw extracted value
  corrected_value   VARCHAR(32) NOT NULL,    -- user-corrected value
  occurrence_count  INTEGER NOT NULL DEFAULT 1,
  last_seen         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  first_seen        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ocr_digit_corrections_uq
    UNIQUE (tenant_id, shop_id, source, field, raw_value, corrected_value)
);

CREATE INDEX IF NOT EXISTS idx_ocr_digit_corrections_lookup
  ON ocr_digit_corrections (tenant_id, shop_id, field, occurrence_count DESC, last_seen DESC);

CREATE INDEX IF NOT EXISTS idx_ocr_digit_corrections_recent
  ON ocr_digit_corrections (tenant_id, last_seen DESC);

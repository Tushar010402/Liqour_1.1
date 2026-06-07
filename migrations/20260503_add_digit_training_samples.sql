-- v1.0.140 — Cell-level training data for the self-trained digit classifier.
--
-- One row per (image, page, row, cell). Crops live on disk under
-- /app/uploads/ai-training/digits/YYYY/MM/DD/ to keep DB rows small (~250 B);
-- 90 days at ~250 cells/day = ~5.6 MB metadata + ~13.5 GB JPEGs on the
-- existing uploads volume. Idempotent via the unique index — safe to re-run
-- the forward-capture goroutine or the backfill CLI any number of times.
--
-- Two writers:
--   1. captureCellCropsForTraining (forward, async on every Smart Sale apply)
--   2. RunDigitTrainingBackfill    (backfill CLI on existing approved records)
--
-- One reader (initially): cv-sidecar/training/dataset.py loads (crop_path,
-- truth_value) pairs into a PyTorch Dataset for the digit-classifier training
-- pipeline. eval_vs_anthropic.py reads ai_raw_value to compare model vs AI
-- with zero new Anthropic spend.

CREATE TABLE IF NOT EXISTS digit_training_samples (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Provenance
    tenant_id                UUID        NOT NULL,
    shop_id                  UUID        NOT NULL,
    daily_sales_record_id    UUID,                                -- nullable for backfill rows where the record is already deleted
    daily_sales_item_id      UUID,                                -- only Sale cell binds 1:1 to an item; Open/Close share the row
    client_row_id            UUID,                                -- carried from DailySalesItem.client_row_id when present
    source                   VARCHAR(16) NOT NULL,                -- 'forward' | 'backfill'
    pipeline_version         VARCHAR(32) NOT NULL,                -- 'sheet-v1.0.138' at capture time
    capture_reason           VARCHAR(32) NOT NULL,                -- 'apply_success' | 'apply_corrected' | 'apply_blocked' | 'backfill_mined'

    -- Image identity & cell coordinates (lets us reconstruct or re-crop later)
    image_sha256             CHAR(64)    NOT NULL,
    image_path               TEXT,                                -- /uploads/daily_sales/<tenant>/smart_sale_<...>.jpg
    page_index               INT         NOT NULL DEFAULT 0,
    row_idx                  INT         NOT NULL,                -- CV row idx within the page
    col_name                 VARCHAR(16) NOT NULL,                -- 'sale' | 'open' | 'closing'
    x_left                   INT         NOT NULL,
    x_right                  INT         NOT NULL,
    y_top                    INT         NOT NULL,
    y_bot                    INT         NOT NULL,
    page_w                   INT         NOT NULL,
    page_h                   INT         NOT NULL,

    -- Crop bytes — disk-stored (see header) with sha for de-dup integrity check
    crop_path                TEXT,                                -- absolute path inside the sales container
    crop_sha256              CHAR(64),
    crop_w                   INT,
    crop_h                   INT,

    -- Labels
    ai_raw_value             VARCHAR(8),                          -- AI's read of this cell, "" if AI returned null
    truth_value              VARCHAR(8)  NOT NULL,                -- operator-confirmed digit string (e.g. "12")
    was_corrected            BOOLEAN     NOT NULL,                -- truth_value != ai_raw_value
    ai_confidence            REAL,                                -- per-cell field_confidence when known
    -- Math-gate flag — true when AI's open-sale=close ±1 satisfied at capture time.
    -- Rows where math fails get dropped from the training pool by default
    -- (operator may have confirmed an AI typo; can't trust the label).
    math_consistent          BOOLEAN,

    -- Train bookkeeping (assigned by training script, not at capture)
    split                    VARCHAR(8),                          -- 'train' | 'val' | 'test'
    exported_at              TIMESTAMPTZ,
    model_version            VARCHAR(32),                         -- model that last consumed this row in eval

    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotency: one row per (image, page, row, cell). Repeat captures are no-ops.
CREATE UNIQUE INDEX IF NOT EXISTS uq_digit_training_samples_cell
    ON digit_training_samples (image_sha256, page_index, row_idx, col_name);

CREATE INDEX IF NOT EXISTS idx_digit_training_samples_tenant_shop
    ON digit_training_samples (tenant_id, shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_digit_training_samples_train_pool
    ON digit_training_samples (split, col_name)
    WHERE split IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_digit_training_samples_truth_class
    ON digit_training_samples (truth_value, col_name)
    WHERE math_consistent IS NOT FALSE;

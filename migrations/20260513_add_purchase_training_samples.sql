-- v1.0.238 Track C — Cell-level training corpus for AI Purchase (GP + Bill).
--
-- Mirrors digit_training_samples (v1.0.140, Smart Sale) so the cv-sidecar
-- training pipeline can reuse the same Dataset / Augment / Train scaffolding.
--
-- One row per (source-image, page, row, column-name). Crops live on disk at
-- /app/ai-training/purchase/YYYY/MM/DD/<job_id>/ to keep DB rows small.

CREATE TABLE IF NOT EXISTS purchase_training_samples (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Provenance
    tenant_id                UUID        NOT NULL,
    shop_id                  UUID        NOT NULL,
    smart_purchase_job_id    UUID,
    apply_record_id          UUID,
    source                   VARCHAR(16) NOT NULL,  -- 'forward' | 'backfill'
    pipeline_version         VARCHAR(32) NOT NULL,  -- 'gp-tables-v1.0.238' etc
    capture_reason           VARCHAR(32) NOT NULL,  -- 'apply_success' | 'apply_corrected' | 'backfill_mined'

    -- Which document the crop came from
    doc_kind                 VARCHAR(16) NOT NULL,  -- 'gp_page' | 'bill_page'
    -- Column taxonomy: GP cols + bill-only cols
    col_name                 VARCHAR(32) NOT NULL,
    engine                   VARCHAR(16) NOT NULL,  -- 'textract' | 'claude' | 'gemini' | 'openai' | 'local_cnn'
    engine_version           VARCHAR(64),

    -- Image identity + per-cell coords (resolved against original image)
    image_sha256             CHAR(64)    NOT NULL,
    image_path               TEXT,
    page_index               INT         NOT NULL DEFAULT 0,
    row_idx                  INT         NOT NULL,
    x_left                   INT         NOT NULL,
    x_right                  INT         NOT NULL,
    y_top                    INT         NOT NULL,
    y_bot                    INT         NOT NULL,
    page_w                   INT         NOT NULL,
    page_h                   INT         NOT NULL,

    -- Crop bytes on disk
    crop_path                TEXT,
    crop_sha256              CHAR(64),
    crop_w                   INT,
    crop_h                   INT,

    -- Labels
    ai_raw_value             TEXT,       -- raw OCR text from `engine`
    truth_value              TEXT,       -- operator-confirmed value
    was_corrected            BOOLEAN     NOT NULL DEFAULT false,
    ai_confidence            REAL,

    -- Train bookkeeping (filled by training script later)
    split                    VARCHAR(8), -- 'train' | 'val' | 'test'
    exported_at              TIMESTAMPTZ,
    model_version            VARCHAR(32),

    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotency: one row per (image, page, row, col).
CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_training_samples_cell
    ON purchase_training_samples (image_sha256, page_index, row_idx, col_name);

CREATE INDEX IF NOT EXISTS idx_purchase_training_samples_tenant_shop
    ON purchase_training_samples (tenant_id, shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_training_samples_train_pool
    ON purchase_training_samples (split, col_name)
    WHERE split IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_training_samples_truth_class
    ON purchase_training_samples (col_name, truth_value)
    WHERE truth_value IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_purchase_training_samples_job
    ON purchase_training_samples (smart_purchase_job_id)
    WHERE smart_purchase_job_id IS NOT NULL;

-- v1.0.138 sheet-grid pipeline — content-addressable cache for OCR results.
--
-- Re-running extraction against the same image returns the cached result
-- and pays $0 to Anthropic. Keyed by image SHA-256 + pipeline version, so
-- invalidations happen automatically when we ship a new version.
--
-- This table is INTENTIONALLY tenant-agnostic: the SAME image bytes always
-- produce the SAME extracted-cells output regardless of which tenant uploaded
-- it. Brand resolution (per-tenant inventory) happens AFTER the cache lookup.

CREATE TABLE IF NOT EXISTS sale_image_extraction_cache (
    image_sha256     CHAR(64)    NOT NULL,
    pipeline_version VARCHAR(32) NOT NULL,
    -- result_jsonb is the raw extractor output BEFORE brand resolution:
    --   { "rows": [{"row_idx":N, "sale":Q, "open":O, "close":C, "source":"ai-digit"}, ...],
    --     "calls_made":1, "cost_inr":0.27, "warnings":[] }
    result_jsonb     JSONB       NOT NULL,
    cv_sheet_jsonb   JSONB,                            -- optional: raw /sheet payload, useful for debugging
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_hit_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hit_count        INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (image_sha256, pipeline_version)
);

CREATE INDEX IF NOT EXISTS idx_sale_image_cache_created_at
    ON sale_image_extraction_cache (created_at DESC);

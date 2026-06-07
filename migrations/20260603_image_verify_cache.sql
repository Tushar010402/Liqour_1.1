-- v1.0.358 — Tenant-wide image-content-hash cache for photo brand/MRP verify.
--
-- The owner's invariant: the SAME bottle photo must produce the SAME canonical
-- name + MRP at EVERY shop. Today each shop re-reads independently and the read
-- is biased by the shop's current product name, so the same image can diverge
-- (e.g. "Moooz Sparkle Jamun" vs "mooz Jamun"). This cache makes an identical
-- image deterministic: first confident read is stored keyed by SHA-256 of the
-- (normalized) image bytes, and every later upload of the same image — at any
-- shop in the tenant — returns the identical result without calling Gemini.
--
-- Tenant-SCOPED (not cross-tenant like sale_image_extraction_cache): convergence
-- is a property of one tenant's catalog. `cache_version` auto-invalidates on a
-- normalize/prompt change; `invalidated_at` is the per-row escape hatch for a
-- poisoned first read (set on admin Revert; filtered out on lookup).

CREATE TABLE IF NOT EXISTS image_verify_cache (
    tenant_id       UUID        NOT NULL,
    image_sha256    CHAR(64)    NOT NULL,
    cache_version   VARCHAR(32) NOT NULL,
    face            VARCHAR(8)  NOT NULL DEFAULT 'front',  -- front (name) | back (MRP)
    canonical_name  TEXT        NOT NULL,
    master_brand_id UUID,
    extracted_mrp   NUMERIC(10,2),
    confidence      NUMERIC(4,3),
    raw_brand_read  TEXT,
    invalidated_at  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_hit_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hit_count       INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (tenant_id, image_sha256, cache_version, face)
);

-- Cross-shop consistency lookups (same tenant brand → expected one canonical).
CREATE INDEX IF NOT EXISTS idx_image_verify_cache_brand
    ON image_verify_cache (tenant_id, master_brand_id)
    WHERE invalidated_at IS NULL;

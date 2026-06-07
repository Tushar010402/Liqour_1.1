-- v1.0.349 — store the captured label photo(s) that drove each photo change
-- request, so the admin "Photo Reviews" page can show the exact image the
-- name/MRP read came from (front = name, back = MRP). Nullable + IF NOT EXISTS
-- so this is a safe, idempotent, non-blocking add; legacy rows stay NULL and
-- the page simply renders no thumbnail for them.
ALTER TABLE product_change_requests
    ADD COLUMN IF NOT EXISTS source_front_image_url TEXT,
    ADD COLUMN IF NOT EXISTS source_back_image_url  TEXT;

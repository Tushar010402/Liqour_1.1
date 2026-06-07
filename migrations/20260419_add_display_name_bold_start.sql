-- Add display_name_bold_start to saas_brands and products.
--
-- Combined with the existing display_name_bold_length, this defines an
-- arbitrary [start, start+length) character range inside display_name that
-- the client renders in big/bold style. The remainder (before AND after the
-- range) renders in the small/normal style.
--
-- start NULL or 0 + length > 0  → bold a prefix (existing behaviour)
-- start > 0   + length > 0      → bold a middle/end portion
-- length NULL or 0              → no bold styling at all
--
-- Backward compatible: existing rows with NULL start behave as if start=0,
-- preserving every previously-saved prefix-bold setting.

ALTER TABLE saas_brands
    ADD COLUMN IF NOT EXISTS display_name_bold_start INTEGER;

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS display_name_bold_start INTEGER;

-- Indexes are unnecessary; this column is read alongside display_name and is
-- never a filter predicate.

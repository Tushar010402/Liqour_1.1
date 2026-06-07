-- Add display_name_bold_length to saas_brands and products.
--
-- An integer >0 indicates the first N characters of display_name should render
-- in big/bold style (the "primary" portion of the name, e.g. the first brand
-- word "8 PM" in "8 PM Premium Black Superior Whisky"). NULL or 0 means the
-- whole display name renders in the default style (backward compatible).
--
-- Admin portal controls this via a slider; Flutter renders via a new
-- DisplayNameText widget that splits into big+small Text.rich spans.

ALTER TABLE saas_brands
    ADD COLUMN IF NOT EXISTS display_name_bold_length INTEGER;

ALTER TABLE products
    ADD COLUMN IF NOT EXISTS display_name_bold_length INTEGER;

-- Partial index so queries that filter on "has styling" stay cheap.
CREATE INDEX IF NOT EXISTS idx_saas_brands_display_name_bold_length
    ON saas_brands (display_name_bold_length)
    WHERE display_name_bold_length IS NOT NULL AND display_name_bold_length > 0;

CREATE INDEX IF NOT EXISTS idx_products_display_name_bold_length
    ON products (display_name_bold_length)
    WHERE display_name_bold_length IS NOT NULL AND display_name_bold_length > 0;

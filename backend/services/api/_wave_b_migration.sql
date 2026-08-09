-- Wave B: variants + multi-image, coupons, reviews, cart line-items.
-- create_all is OFF in production; DDL applied manually.
-- REMINDER: every new table must get "ALTER TABLE ... OWNER TO dilix" too.

ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS images JSON;
ALTER TABLE shop_orders   ADD COLUMN IF NOT EXISTS discount BIGINT NOT NULL DEFAULT 0;
ALTER TABLE shop_orders   ADD COLUMN IF NOT EXISTS coupon_code VARCHAR(24);

CREATE TABLE IF NOT EXISTS shop_product_variants (
    id UUID PRIMARY KEY,
    product_id UUID NOT NULL REFERENCES shop_products(id),
    name VARCHAR(80) NOT NULL,
    price BIGINT,
    stock INTEGER NOT NULL DEFAULT 0,
    image_url VARCHAR(500),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_shop_variant_product ON shop_product_variants (product_id, is_active);

CREATE TABLE IF NOT EXISTS shop_order_items (
    id UUID PRIMARY KEY,
    order_id UUID NOT NULL REFERENCES shop_orders(id),
    product_id UUID NOT NULL REFERENCES shop_products(id),
    variant_id UUID REFERENCES shop_product_variants(id),
    title VARCHAR(160) NOT NULL,
    unit_price BIGINT NOT NULL,
    qty INTEGER NOT NULL,
    subtotal BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_shop_item_order ON shop_order_items (order_id);
CREATE INDEX IF NOT EXISTS ix_shop_item_product ON shop_order_items (product_id);

CREATE TABLE IF NOT EXISTS shop_coupons (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES users(id),
    product_id UUID REFERENCES shop_products(id),
    code VARCHAR(24) NOT NULL UNIQUE,
    discount_type VARCHAR(10) NOT NULL,
    discount_value BIGINT NOT NULL,
    max_uses INTEGER,
    used_count INTEGER NOT NULL DEFAULT 0,
    min_order_total BIGINT NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_shop_coupon_owner ON shop_coupons (owner_id);

CREATE TABLE IF NOT EXISTS shop_reviews (
    id UUID PRIMARY KEY,
    order_id UUID NOT NULL REFERENCES shop_orders(id),
    product_id UUID NOT NULL REFERENCES shop_products(id),
    reviewer_id UUID NOT NULL REFERENCES users(id),
    seller_id UUID NOT NULL REFERENCES users(id),
    rating INTEGER NOT NULL,
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_shop_review_order_product ON shop_reviews (order_id, product_id);
CREATE INDEX IF NOT EXISTS ix_shop_review_product ON shop_reviews (product_id);

ALTER TABLE shop_product_variants OWNER TO dilix;
ALTER TABLE shop_order_items      OWNER TO dilix;
ALTER TABLE shop_coupons          OWNER TO dilix;
ALTER TABLE shop_reviews          OWNER TO dilix;

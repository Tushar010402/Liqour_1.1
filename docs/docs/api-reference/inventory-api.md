# Inventory API

## Overview

The Inventory API provides endpoints for managing products, stocks, purchases, categories, brands, and SaaS brand integration.

**Base URL**: `https://new.v2.floelife.in/api`

---

## Products

### List Products

#### GET /products

List products with filtering and pagination.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| category_id | UUID | Filter by category |
| brand_id | UUID | Filter by brand |
| search | string | Search by name or SKU |
| low_stock | bool | Filter low stock items |
| page | int | Page number |
| per_page | int | Items per page |

---

### Get Product

#### GET /products/:id

Get product details including pricing and stock info.

---

### Create Product

#### POST /products

Create a new product. Role required: `manager` or `admin`.

---

### Update Product

#### PUT /products/:id

Update product details. Role required: `manager` or `admin`.

---

### Delete Product

#### DELETE /products/:id

Delete a product. Role required: `admin`.

---

### Batch Validate Products

#### POST /products/validate-batch

Validate multiple products in a single request. Reduces N API calls to 1.

**Request:**
```json
{
  "product_ids": ["uuid-1", "uuid-2", "uuid-3"]
}
```

---

### Get Products by IDs

#### POST /products/by-ids

Fetch multiple products by IDs in a single request.

**Request:**
```json
{
  "ids": ["uuid-1", "uuid-2", "uuid-3"]
}
```

---

### Get Distinct Sizes

#### GET /products/sizes

Get all distinct product sizes for filter dropdowns.

---

### Update Product Pricing

#### PUT /products/:id/pricing

Update only the pricing information for a product.

---

## Stock Management

### Get Stocks

#### GET /stocks

Get stock levels with filtering.

**Query Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| product_id | UUID | Filter by product |
| low_stock | bool | Only show low stock items |

---

### Adjust Stock

#### POST /stocks/adjust

Adjust stock levels (increase/decrease). Role required: `manager` or `admin`.

**Request:**
```json
{
  "shop_id": "shop-uuid",
  "product_id": "product-uuid",
  "quantity": 10,
  "adjustment_type": "add",
  "reason": "Received shipment"
}
```

---

### Transfer Stock

#### POST /stocks/transfer

Transfer stock between shops. Role required: `manager` or `admin`.

**Request:**
```json
{
  "from_shop_id": "shop-uuid-1",
  "to_shop_id": "shop-uuid-2",
  "items": [
    {
      "product_id": "product-uuid",
      "quantity": 5
    }
  ],
  "notes": "Inter-shop transfer"
}
```

---

### Get Stock Movements

#### GET /stocks/movements

Get stock movement history/audit trail.

---

## Purchases

### List Purchases

#### GET /purchases

List purchase orders. Alias: `GET /stock-purchases`

---

### Create Purchase

#### POST /purchases

Create a purchase order. Alias: `POST /stock-purchases`

---

### Get Purchase

#### GET /purchases/:id

Get purchase order details.

---

### Get Pending Approvals

#### GET /purchases/pending

Get purchases awaiting approval. Role required: `assistant_manager`, `manager`, or `admin`.

---

### Approve Purchase

#### POST /purchases/:id/approve

Approve a pending purchase. Role required: `assistant_manager`, `manager`, or `admin`.

---

### Reject Purchase

#### POST /purchases/:id/reject

Reject a pending purchase. Role required: `assistant_manager`, `manager`, or `admin`.

---

### Receive Purchase

#### POST /purchases/:id/receive

Record received stock from purchase. Role required: `manager` or `admin`.

---

### Upload Purchase Receipt

#### POST /purchases/upload-receipt

Upload receipt image for a purchase.

---

## Purchase Drafts

Auto-save functionality for mobile app.

### Get Draft

#### GET /drafts/stock-purchase

Get current user's purchase draft.

---

### Save Draft

#### POST /drafts/stock-purchase

Save or update a purchase draft.

---

### Delete Draft

#### DELETE /drafts/stock-purchase

Delete a purchase draft.

---

### Get All Drafts

#### GET /drafts/stock-purchase/all

Get all drafts for current user.

---

## Categories

### List Categories

#### GET /categories

List all categories.

---

### Create Category

#### POST /categories

Create a new category. Role required: `manager` or `admin`.

---

### Get Category

#### GET /categories/:id

Get category details.

---

### Update Category

#### PUT /categories/:id

Update category. Role required: `manager` or `admin`.

---

### Delete Category

#### DELETE /categories/:id

Delete category. Role required: `admin`.

---

## Brands

### List Brands

#### GET /brands

List all brands.

---

### Create Brand

#### POST /brands

Create a new brand. Role required: `manager` or `admin`.

---

### Create Brand with Variants

#### POST /brands/with-variants

Create a brand with multiple size variants.

**Request:**
```json
{
  "name": "Royal Challenge",
  "category_id": "category-uuid",
  "variants": [
    {"size": "750ml", "mrp": 450.00},
    {"size": "375ml", "mrp": 230.00},
    {"size": "180ml", "mrp": 120.00}
  ]
}
```

---

### Get Brand

#### GET /brands/:id

Get brand details.

---

### Update Brand

#### PUT /brands/:id

Update brand. Role required: `manager` or `admin`.

---

### Delete Brand

#### DELETE /brands/:id

Delete brand. Role required: `admin`.

---

### Get Products by Brand

#### GET /brands/:id/products

Get all products for a specific brand.

---

### Get Products Grouped by Brand

#### GET /brands/products/grouped

Get products grouped by their parent brand.

---

### Check Duplicate Product

#### GET /brands/:id/check-duplicate

Check if a product variant already exists for this brand.

---

## SaaS Brand Integration

Integration with central SaaS brand catalog.

### Get Available Brand Templates

#### GET /api/inventory/saas-brands/available

Get brands available from SaaS catalog for onboarding.

---

### Onboard Brands

#### POST /api/inventory/saas-brands/onboard

Onboard selected brands from SaaS catalog to tenant.

---

### Get Onboarded Brands

#### GET /api/inventory/saas-brands/onboarded

Get brands already onboarded to tenant.

---

### Update Onboarded Brand

#### PUT /api/inventory/saas-brands/onboarded/:id

Update an onboarded brand's settings.

---

### Get Custom Brands

#### GET /api/inventory/brands/custom

Get tenant-created custom brands.

---

### Get Brand Metadata

#### GET /api/inventory/saas-brands/metadata

Get brand metadata (categories, sizes, etc.).

---

### Refresh Brand Cache

#### POST /api/inventory/saas-brands/refresh-cache

Refresh the brand cache from SaaS service.

---

### Legacy SaaS Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /brands/saas/available` | Get available SaaS brands |
| `GET /brands/saas/tenant` | Get tenant's SaaS brands |
| `POST /brands/saas/select` | Select brands from catalog |
| `POST /brands/saas/customize` | Customize brand variant |
| `POST /brands/saas/import-as-products` | Import brands as products |
| `GET /brands/available` | Legacy: available brands |
| `GET /brands/my-brands` | Legacy: tenant brands |
| `POST /brands/create-product` | Create product from brand |
| `GET /brands/products` | Get products from brands |
| `POST /brands/sync-pricing` | Sync brand pricing |

---

## Product Catalog

### Get Product Templates

#### GET /api/catalog/product-templates

Get predefined product templates.

---

### Get Subcategories

#### GET /api/catalog/subcategories

Get product subcategories.

---

## Pricing Utilities

### Calculate UP Duty

#### POST /pricing/calculate-up-duty

Calculate Uttar Pradesh duty based on product details.

---

## Reports

### Low Stock Report

#### GET /reports/low-stock

Get products with low stock levels. Uses query param `low_stock=true`.

---

### Stock Movements Report

#### GET /reports/stock-movements

Get stock movement history.

---

### Inventory Valuation Report

#### GET /reports/valuation

Get inventory valuation report (cost-based).

---

### Stock Turnover Report

#### GET /reports/turnover

Get stock turnover analysis.

---

### Stock Aging Report

#### GET /reports/aging

Get aging analysis of stock.

---

## Global Endpoints

### Get Distinct Sizes

#### GET /sizes

Get all distinct product sizes in the system.

---

## Error Codes

| Code | Description |
|------|-------------|
| PRODUCT_NOT_FOUND | Product not found |
| INSUFFICIENT_STOCK | Not enough stock for operation |
| DUPLICATE_SKU | SKU already exists |
| BRAND_NOT_FOUND | Brand not found |
| CATEGORY_NOT_FOUND | Category not found |
| PURCHASE_NOT_FOUND | Purchase order not found |
| INVALID_QUANTITY | Quantity must be positive |
| TRANSFER_FAILED | Stock transfer failed |

---

## Role Requirements Summary

| Endpoint | Roles Allowed |
|----------|---------------|
| View Products/Stocks | All authenticated users |
| Create/Update Products | manager, admin |
| Delete Products | admin |
| Stock Adjust/Transfer | manager, admin |
| Approve Purchases | assistant_manager, manager, admin |
| Delete Categories/Brands | admin |

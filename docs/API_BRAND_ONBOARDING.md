# Brand Onboarding API Documentation

## Overview
The Brand Onboarding API allows tenants to browse and onboard products from the SaaS-managed brand catalog into their inventory.

**Base URL:** `http://localhost:8083` (Inventory Service)

**Authentication:** Required - Bearer token in `Authorization` header

**Tenant Isolation:** Required - `X-Tenant-ID` header

---

## Endpoints

### 1. Get Available Brand Templates

Retrieve all active SaaS brand templates available for onboarding.

**Endpoint:** `GET /api/inventory/saas-brands/available`

**Headers:**
```http
Authorization: Bearer <token>
X-Tenant-ID: <tenant-uuid>
```

**Response:** `200 OK`
```json
{
  "message": "Brand templates retrieved successfully",
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Johnnie Walker",
      "description": "Premium Scotch Whisky",
      "picture": "https://cdn.example.com/johnnie-walker.jpg",
      "is_active": true,
      "sort_order": 1,
      "created_at": "2025-01-01T00:00:00Z",
      "updated_at": "2025-01-01T00:00:00Z",
      "brand_variants": [
        {
          "id": "660e8400-e29b-41d4-a716-446655440000",
          "brand_id": "550e8400-e29b-41d4-a716-446655440000",
          "category_id": "770e8400-e29b-41d4-a716-446655440000",
          "subcategory_id": null,
          "size": "750ml",
          "alcohol_content": 40.0,
          "picture": "https://cdn.example.com/jw-750ml.jpg",
          "barcode": "5000267024134",
          "hsn_code": "22083020",
          "government_duty": 250.00,
          "buying_price": 1200.00,
          "selling_price": 1500.00,
          "mrp": 1650.00,
          "description": "750ml bottle",
          "is_active": true,
          "sort_order": 1,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z",
          "category": {
            "id": "770e8400-e29b-41d4-a716-446655440000",
            "name": "Whisky",
            "description": "Whisky products",
            "is_active": true,
            "sort_order": 1
          }
        }
      ]
    }
  ],
  "count": 1
}
```

**Error Responses:**

- `401 Unauthorized` - Missing or invalid authentication
- `500 Internal Server Error` - SaaS service unavailable (after 3 retries)

---

### 2. Onboard Brands to Tenant

Onboard selected brand variants to create products in tenant's inventory.

**Endpoint:** `POST /api/inventory/saas-brands/onboard`

**Headers:**
```http
Authorization: Bearer <token>
X-Tenant-ID: <tenant-uuid>
Content-Type: application/json
```

**Request Body:**
```json
{
  "brand_ids": [
    "550e8400-e29b-41d4-a716-446655440000",
    "550e8400-e29b-41d4-a716-446655440001"
  ],
  "variant_ids": [
    "660e8400-e29b-41d4-a716-446655440000",
    "660e8400-e29b-41d4-a716-446655440001"
  ],
  "shop_id": "880e8400-e29b-41d4-a716-446655440000"
}
```

**Field Descriptions:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `brand_ids` | `string[]` | Yes | Array of SaaS brand UUIDs to onboard |
| `variant_ids` | `string[]` | No | Specific variant UUIDs (if empty, all variants from brands are onboarded) |
| `shop_id` | `string` | No | Target shop UUID for multi-shop tenants |

**Response:** `200 OK`
```json
{
  "message": "Brand onboarding completed",
  "data": {
    "tenant_id": "990e8400-e29b-41d4-a716-446655440000",
    "onboarded_brands": 2,
    "onboarded_products": 5,
    "categories_created": 2,
    "brand_details": [
      {
        "saas_brand_id": "550e8400-e29b-41d4-a716-446655440000",
        "saas_brand_name": "Johnnie Walker",
        "products_created": 3,
        "product_ids": [
          "aa0e8400-e29b-41d4-a716-446655440000",
          "bb0e8400-e29b-41d4-a716-446655440000",
          "cc0e8400-e29b-41d4-a716-446655440000"
        ],
        "success": true
      },
      {
        "saas_brand_id": "550e8400-e29b-41d4-a716-446655440001",
        "saas_brand_name": "Jack Daniels",
        "products_created": 2,
        "product_ids": [
          "dd0e8400-e29b-41d4-a716-446655440000",
          "ee0e8400-e29b-41d4-a716-446655440000"
        ],
        "success": true
      }
    ],
    "errors": []
  }
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `onboarded_brands` | `int` | Number of brands successfully onboarded |
| `onboarded_products` | `int` | Total products created |
| `categories_created` | `int` | Number of new categories created |
| `brand_details` | `object[]` | Detailed results per brand |
| `errors` | `string[]` | Error messages (if any) |

**Partial Success Response:** `200 OK`
```json
{
  "message": "Brand onboarding completed",
  "data": {
    "tenant_id": "990e8400-e29b-41d4-a716-446655440000",
    "onboarded_brands": 1,
    "onboarded_products": 2,
    "categories_created": 1,
    "brand_details": [
      {
        "saas_brand_id": "550e8400-e29b-41d4-a716-446655440000",
        "saas_brand_name": "Johnnie Walker",
        "products_created": 2,
        "product_ids": ["aa0e8400-...", "bb0e8400-..."],
        "success": true
      },
      {
        "saas_brand_id": "550e8400-e29b-41d4-a716-446655440001",
        "saas_brand_name": "Invalid Brand",
        "products_created": 0,
        "product_ids": [],
        "success": false,
        "error": "Failed to fetch brand template: not found"
      }
    ],
    "errors": [
      "Brand Invalid Brand: Failed to fetch brand template: not found"
    ]
  }
}
```

**Error Responses:**

- `400 Bad Request` - Invalid request body
- `401 Unauthorized` - Missing or invalid authentication
- `500 Internal Server Error` - Database or service error

---

### 3. Get Onboarded Brands

Retrieve products that were onboarded from SaaS templates.

**Endpoint:** `GET /api/inventory/saas-brands/onboarded`

**Headers:**
```http
Authorization: Bearer <token>
X-Tenant-ID: <tenant-uuid>
```

**Response:** `200 OK`
```json
{
  "message": "Onboarded brands retrieved successfully",
  "data": [
    {
      "id": "aa0e8400-e29b-41d4-a716-446655440000",
      "name": "Johnnie Walker - 750ml",
      "category_id": "770e8400-e29b-41d4-a716-446655440000",
      "brand_id": "bb0e8400-e29b-41d4-a716-446655440000",
      "saas_brand_id": "550e8400-e29b-41d4-a716-446655440000",
      "saas_variant_id": "660e8400-e29b-41d4-a716-446655440000",
      "size": "750ml",
      "alcohol_content": 40.0,
      "barcode": "5000267024134",
      "sku": "SAAS-550e8400-660e8400",
      "image_url": "https://cdn.example.com/jw-750ml.jpg",
      "cost_price": 1200.00,
      "duty_fee": 250.00,
      "total_cost": 1450.00,
      "selling_price": 1500.00,
      "mrp": 1650.00,
      "is_active": true,
      "created_at": "2025-01-15T10:30:00Z",
      "updated_at": "2025-01-15T10:30:00Z",
      "category": {
        "id": "770e8400-e29b-41d4-a716-446655440000",
        "name": "Whisky"
      },
      "brand": {
        "id": "bb0e8400-e29b-41d4-a716-446655440000",
        "name": "Johnnie Walker"
      }
    }
  ],
  "count": 1
}
```

**Notes:**
- Products with SKU pattern `SAAS-*` are identified as onboarded from SaaS
- `saas_brand_id` and `saas_variant_id` track the original template

---

### 4. Get Custom Brands

Retrieve products created directly by tenant (not from SaaS templates).

**Endpoint:** `GET /api/inventory/brands/custom`

**Headers:**
```http
Authorization: Bearer <token>
X-Tenant-ID: <tenant-uuid>
```

**Response:** `200 OK`
```json
{
  "message": "Custom brands retrieved successfully",
  "data": [
    {
      "id": "ff0e8400-e29b-41d4-a716-446655440000",
      "name": "House Special Rum - 1L",
      "category_id": "gg0e8400-e29b-41d4-a716-446655440000",
      "brand_id": "hh0e8400-e29b-41d4-a716-446655440000",
      "saas_brand_id": null,
      "saas_variant_id": null,
      "size": "1L",
      "alcohol_content": 42.5,
      "barcode": "1234567890123",
      "sku": "CUSTOM-001",
      "cost_price": 800.00,
      "selling_price": 1000.00,
      "mrp": 1100.00,
      "is_active": true
    }
  ],
  "count": 1
}
```

**Notes:**
- Products with `saas_variant_id = null` are custom products
- SKU doesn't follow `SAAS-*` pattern

---

### 5. Update Onboarded Brand

Customize an onboarded brand's pricing or details.

**Endpoint:** `PUT /api/inventory/saas-brands/onboarded/:id`

**Headers:**
```http
Authorization: Bearer <token>
X-Tenant-ID: <tenant-uuid>
Content-Type: application/json
```

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | `string` | Product UUID |

**Request Body:**
```json
{
  "selling_price": 1600.00,
  "mrp": 1750.00,
  "cost_price": 1250.00,
  "is_active": true
}
```

**Allowed Fields:**
- `selling_price`
- `mrp`
- `cost_price`
- `duty_fee`
- `total_cost`
- `is_active`
- `description`

**Response:** `200 OK`
```json
{
  "message": "Onboarded brand updated successfully"
}
```

**Error Responses:**
- `400 Bad Request` - Invalid product ID or tenant doesn't own product
- `404 Not Found` - Product not found

---

## Business Logic

### Duplicate Prevention

The system prevents duplicate onboarding:

1. **Database Constraint:** Unique index on `(tenant_id, saas_variant_id)`
2. **Application Check:** Before creating product, checks if variant already onboarded
3. **Behavior:** Silently skips duplicates (doesn't return error)

**Example:**
```
First onboarding: Creates product
Second onboarding: Skips, logs info message
Response: Shows 0 products created for that variant
```

### Retry Logic

SaaS service calls use exponential backoff:

- **Max Attempts:** 3
- **Retry Delay:** 1s, 2s, 4s (exponential)
- **Total Max Time:** ~7 seconds
- **Retries On:** Network errors, 5xx server errors
- **No Retry On:** 4xx client errors

### Category & Brand Creation

When onboarding:

1. **Ensures category exists** for tenant (creates if needed)
2. **Ensures brand exists** for tenant (creates if needed)
3. **Creates product** with references to tenant's category/brand
4. **Tracks created categories** in response

### SKU Generation

Onboarded products get auto-generated SKU:

**Pattern:** `SAAS-{brand_id_prefix}-{variant_id_prefix}`

**Example:** `SAAS-550e8400-660e8400`

---

## Error Codes

| HTTP Code | Description | Common Causes |
|-----------|-------------|---------------|
| 200 | Success | Request completed successfully |
| 400 | Bad Request | Invalid JSON, missing required fields |
| 401 | Unauthorized | Missing/invalid token or tenant ID |
| 404 | Not Found | Product or brand doesn't exist |
| 500 | Internal Server Error | Database error, SaaS service down |

---

## Integration Examples

### Flutter (Dart)

```dart
// Get available brands
final response = await apiService.get<List<SaasBrand>>(
  '/api/inventory/saas-brands/available',
  fromJson: (data) => (data as List)
    .map((json) => SaasBrand.fromJson(json))
    .toList(),
);

// Onboard brands
final onboardResponse = await apiService.post<OnboardingResult>(
  '/api/inventory/saas-brands/onboard',
  body: {
    'brand_ids': selectedBrandIds,
    'variant_ids': selectedVariantIds,
    'shop_id': selectedShopId,
  },
  fromJson: (data) => OnboardingResult.fromJson(data),
);

if (onboardResponse.success) {
  print('Onboarded ${onboardResponse.data?.brandsOnboarded} brands');
  print('Created ${onboardResponse.data?.productsCreated} products');
}
```

### cURL

```bash
# Get available brands
curl -X GET "http://localhost:8083/api/inventory/saas-brands/available" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-Tenant-ID: YOUR_TENANT_ID"

# Onboard brands
curl -X POST "http://localhost:8083/api/inventory/saas-brands/onboard" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-Tenant-ID: YOUR_TENANT_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "brand_ids": ["550e8400-e29b-41d4-a716-446655440000"],
    "variant_ids": ["660e8400-e29b-41d4-a716-446655440000"]
  }'
```

---

## Performance Considerations

### Caching
- Brand templates are fetched fresh each time (no caching currently)
- Consider implementing Redis cache for frequently accessed brands

### Batch Processing
- Onboarding multiple brands is processed sequentially
- Large batch sizes (>50 brands) may timeout
- Recommended: Limit to 20 brands per request

### Database Performance
- Unique constraint check is O(1) with index
- Category/brand existence checks are indexed
- Bulk operations use transactions

---

## Changelog

### v1.2.0 (2025-10-04)
- ✅ Fixed API endpoint routing (`/api/inventory` prefix)
- ✅ Added `categories_created` to response
- ✅ Implemented duplicate prevention
- ✅ Added exponential backoff retry logic
- ✅ Added `saas_brand_id` and `saas_variant_id` tracking

### v1.1.0 (2025-01-15)
- Initial release of brand onboarding API

---

## Support

For issues or questions:
- Check logs: `docker logs inventory | grep "SaaS"`
- Database inspection: `SELECT * FROM products WHERE saas_variant_id IS NOT NULL`
- Error tracking: Response `errors` array contains detailed messages

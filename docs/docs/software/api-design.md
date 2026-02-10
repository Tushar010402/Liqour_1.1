# API Design Document

## Document Information

| Field | Value |
|-------|-------|
| **Document ID** | API-DESIGN-001 |
| **Version** | 2.0.0 |
| **API Version** | v1 |
| **Base URL** | `https://new.v2.floelife.in/api` |
| **Last Updated** | January 2025 |

---

## 1. API Overview

### 1.1 Design Principles

| Principle | Implementation |
|-----------|----------------|
| **RESTful** | Resource-based URLs, HTTP verbs |
| **JSON** | All request/response bodies in JSON |
| **Versioning** | URL path versioning (`/api/v1/`) |
| **Pagination** | Cursor-based for large collections |
| **Filtering** | Query parameters for filtering |
| **HATEOAS** | Links in responses for navigation |

### 1.2 Base URL Structure

```
https://new.v2.floelife.in/api/v1/{service}/{resource}

Examples:
- /api/v1/auth/login
- /api/v1/sales/daily-records
- /api/v1/inventory/products
- /api/v1/finance/vendors
```

---

## 2. Authentication

### 2.1 Authentication Header

```http
Authorization: Bearer <jwt_token>
```

### 2.2 Token Response

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "token_type": "Bearer",
  "expires_in": 86400,
  "user": {
    "id": "uuid",
    "name": "John Doe",
    "role": "manager",
    "tenant_id": "uuid"
  }
}
```

### 2.3 Token Refresh

```http
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refresh_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

---

## 3. Request/Response Format

### 3.1 Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `Authorization` | Yes* | Bearer token (*except public endpoints) |
| `Content-Type` | Yes | `application/json` |
| `Accept` | No | `application/json` |
| `X-Request-ID` | No | Client-generated request ID |
| `X-Tenant-ID` | No | Override tenant (SaaS admin only) |

### 3.2 Standard Response Format

#### Success Response
```json
{
  "success": true,
  "data": {
    // Response data
  },
  "meta": {
    "request_id": "req_abc123",
    "timestamp": "2025-01-11T10:30:00Z"
  }
}
```

#### Paginated Response
```json
{
  "success": true,
  "data": [
    // Array of items
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 150,
    "total_pages": 8,
    "has_next": true,
    "has_prev": false
  },
  "meta": {
    "request_id": "req_abc123"
  }
}
```

#### Error Response
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid input data",
    "details": [
      {
        "field": "phone",
        "message": "Phone number is required"
      }
    ]
  },
  "meta": {
    "request_id": "req_abc123"
  }
}
```

### 3.3 HTTP Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| 200 | OK | Successful GET, PUT, PATCH |
| 201 | Created | Successful POST |
| 204 | No Content | Successful DELETE |
| 400 | Bad Request | Invalid input |
| 401 | Unauthorized | Missing/invalid token |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Resource not found |
| 409 | Conflict | Duplicate resource |
| 422 | Unprocessable Entity | Validation error |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |
| 503 | Service Unavailable | Service down |

---

## 4. API Endpoints

### 4.1 Authentication API

#### POST /api/v1/auth/login
Login with phone and password

**Request:**
```json
{
  "phone": "+919876543210",
  "password": "SecurePass123"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "OTP sent successfully",
    "otp_expires_in": 300
  }
}
```

---

#### POST /api/v1/auth/verify-otp
Verify OTP and get tokens

**Request:**
```json
{
  "phone": "+919876543210",
  "otp": "123456"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIs...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
    "expires_in": 86400,
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "John Doe",
      "phone": "+919876543210",
      "email": "john@example.com",
      "role": "manager",
      "tenant_id": "550e8400-e29b-41d4-a716-446655440001"
    }
  }
}
```

---

#### GET /api/v1/auth/profile
Get current user profile

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "John Doe",
    "phone": "+919876543210",
    "email": "john@example.com",
    "role": "manager",
    "tenant": {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "name": "ABC Liquors"
    },
    "shops": [
      {
        "id": "shop-uuid",
        "name": "Main Street Store"
      }
    ],
    "created_at": "2024-01-01T00:00:00Z"
  }
}
```

---

#### GET /api/v1/auth/sessions
List active sessions

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "session-uuid",
      "device_type": "mobile",
      "device_name": "iPhone 15",
      "ip_address": "192.168.1.1",
      "last_activity": "2025-01-11T10:00:00Z",
      "is_current": true
    },
    {
      "id": "session-uuid-2",
      "device_type": "web",
      "device_name": "Chrome on Windows",
      "ip_address": "192.168.1.2",
      "last_activity": "2025-01-10T15:00:00Z",
      "is_current": false
    }
  ]
}
```

---

#### DELETE /api/v1/auth/sessions/{session_id}
Terminate a session

**Response (204):** No content

---

### 4.2 Daily Sales API

#### GET /api/v1/sales/daily-records
List daily sales records

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| start_date | date | Start date (YYYY-MM-DD) |
| end_date | date | End date (YYYY-MM-DD) |
| status | string | draft, pending, approved, rejected |
| page | int | Page number (default: 1) |
| per_page | int | Items per page (default: 20) |

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "record-uuid",
      "shop": {
        "id": "shop-uuid",
        "name": "Main Street Store"
      },
      "record_date": "2025-01-11",
      "total_sales_amount": 45000.00,
      "total_items": 35,
      "status": "pending",
      "created_by": {
        "id": "user-uuid",
        "name": "John Salesman"
      },
      "created_at": "2025-01-11T18:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 30,
    "total_pages": 2
  }
}
```

---

#### POST /api/v1/sales/daily-records
Create daily sales record

**Request:**
```json
{
  "shop_id": "shop-uuid",
  "record_date": "2025-01-11",
  "items": [
    {
      "product_id": "product-uuid-1",
      "quantity": 10,
      "unit_price": 450.00,
      "discount_amount": 0
    },
    {
      "product_id": "product-uuid-2",
      "quantity": 5,
      "unit_price": 550.00,
      "discount_amount": 50.00
    }
  ],
  "expenses": [
    {
      "expense_type": "transport",
      "amount": 500.00,
      "description": "Delivery charges"
    }
  ],
  "notes": "Weekend sale"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "record-uuid",
    "shop_id": "shop-uuid",
    "record_date": "2025-01-11",
    "total_sales_amount": 7150.00,
    "total_items": 15,
    "status": "draft",
    "items": [...],
    "expenses": [...],
    "created_at": "2025-01-11T18:00:00Z"
  }
}
```

---

#### GET /api/v1/sales/daily-records/{id}
Get daily sales record details

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "record-uuid",
    "shop": {
      "id": "shop-uuid",
      "name": "Main Street Store"
    },
    "salesman": {
      "id": "salesman-uuid",
      "name": "John Salesman"
    },
    "record_date": "2025-01-11",
    "total_sales_amount": 45000.00,
    "total_items": 35,
    "total_discount": 500.00,
    "status": "approved",
    "items": [
      {
        "id": "item-uuid",
        "product": {
          "id": "product-uuid",
          "name": "Royal Challenge",
          "sku": "RC-750"
        },
        "quantity": 10,
        "unit_price": 450.00,
        "discount_amount": 0,
        "total_price": 4500.00
      }
    ],
    "expenses": [
      {
        "id": "expense-uuid",
        "expense_type": "transport",
        "amount": 500.00,
        "description": "Delivery charges"
      }
    ],
    "created_by": {
      "id": "user-uuid",
      "name": "John Salesman"
    },
    "approved_by": {
      "id": "manager-uuid",
      "name": "Jane Manager"
    },
    "approved_at": "2025-01-11T19:00:00Z",
    "created_at": "2025-01-11T18:00:00Z",
    "updated_at": "2025-01-11T19:00:00Z"
  }
}
```

---

#### PUT /api/v1/sales/daily-records/{id}
Update daily sales record

**Request:**
```json
{
  "items": [...],
  "expenses": [...],
  "notes": "Updated notes"
}
```

**Response (200):** Updated record

---

#### POST /api/v1/sales/daily-records/{id}/submit
Submit record for approval

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "record-uuid",
    "status": "pending",
    "submitted_at": "2025-01-11T18:30:00Z"
  }
}
```

---

#### POST /api/v1/sales/daily-records/{id}/approve
Approve daily sales record (Manager only)

**Request:**
```json
{
  "comments": "Approved. Good sales today!"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "record-uuid",
    "status": "approved",
    "approved_by": {
      "id": "manager-uuid",
      "name": "Jane Manager"
    },
    "approved_at": "2025-01-11T19:00:00Z"
  }
}
```

---

#### POST /api/v1/sales/daily-records/{id}/reject
Reject daily sales record (Manager only)

**Request:**
```json
{
  "reason": "Quantity mismatch. Please verify and resubmit."
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "record-uuid",
    "status": "rejected",
    "rejection_reason": "Quantity mismatch..."
  }
}
```

---

### 4.3 OCR API

#### POST /api/v1/sales/ocr/batch/sessions
Create OCR batch session

**Request (multipart/form-data):**
```
shop_id: shop-uuid
images[]: file1.jpg
images[]: file2.jpg
images[]: file3.jpg
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "session_id": "batch-uuid",
    "status": "processing",
    "total_images": 3,
    "processed": 0,
    "estimated_time": 45
  }
}
```

---

#### GET /api/v1/sales/ocr/batch/sessions/{id}
Get batch processing status

**Response (200):**
```json
{
  "success": true,
  "data": {
    "session_id": "batch-uuid",
    "status": "completed",
    "total_images": 3,
    "processed": 3,
    "success": 2,
    "failed": 1,
    "results": [
      {
        "image_index": 0,
        "status": "success",
        "confidence": 0.95,
        "extracted_data": {
          "brand": "Royal Challenge",
          "size": "750ml",
          "quantity": 10,
          "unit_price": 450.00,
          "total": 4500.00,
          "gst": 810.00
        },
        "matched_product": {
          "id": "product-uuid",
          "name": "Royal Challenge 750ml"
        }
      },
      {
        "image_index": 1,
        "status": "success",
        "confidence": 0.88,
        "extracted_data": {...},
        "needs_review": true
      },
      {
        "image_index": 2,
        "status": "failed",
        "error": "Could not extract text from image"
      }
    ]
  }
}
```

---

### 4.4 Inventory API

#### GET /api/v1/inventory/products
List products

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| category_id | UUID | Filter by category |
| brand_id | UUID | Filter by brand |
| search | string | Search by name/SKU |
| is_active | bool | Filter by status |
| page | int | Page number |
| per_page | int | Items per page |

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "product-uuid",
      "name": "Royal Challenge",
      "sku": "RC-750",
      "category": {
        "id": "cat-uuid",
        "name": "Whisky"
      },
      "brand": {
        "id": "brand-uuid",
        "name": "Royal Challenge"
      },
      "size": "750ml",
      "selling_price": 450.00,
      "mrp": 480.00,
      "tax_rate": 18.00,
      "is_active": true
    }
  ],
  "pagination": {...}
}
```

---

#### GET /api/v1/inventory/stocks
Get stock levels

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| low_stock | bool | Only low stock items |
| product_id | UUID | Specific product |

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "stock-uuid",
      "shop": {
        "id": "shop-uuid",
        "name": "Main Street Store"
      },
      "product": {
        "id": "product-uuid",
        "name": "Royal Challenge",
        "sku": "RC-750"
      },
      "quantity": 45,
      "reorder_level": 20,
      "is_low_stock": false,
      "cost_price": 380.00,
      "selling_price": 450.00,
      "last_sale_date": "2025-01-11"
    }
  ]
}
```

---

#### POST /api/v1/inventory/purchases
Create purchase order

**Request:**
```json
{
  "shop_id": "shop-uuid",
  "vendor_id": "vendor-uuid",
  "expected_date": "2025-01-15",
  "items": [
    {
      "product_id": "product-uuid",
      "quantity": 100,
      "unit_price": 380.00,
      "tax_rate": 18.00
    }
  ],
  "notes": "Weekly stock replenishment"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "purchase-uuid",
    "purchase_number": "PO-2025-0001",
    "vendor": {...},
    "shop": {...},
    "items": [...],
    "sub_total": 38000.00,
    "tax_amount": 6840.00,
    "total_amount": 44840.00,
    "status": "pending",
    "created_at": "2025-01-11T10:00:00Z"
  }
}
```

---

### 4.5 Finance API

#### GET /api/v1/finance/vendors/{id}/ledger
Get vendor ledger

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| start_date | date | Start date |
| end_date | date | End date |

**Response (200):**
```json
{
  "success": true,
  "data": {
    "vendor": {
      "id": "vendor-uuid",
      "name": "ABC Distributors"
    },
    "opening_balance": 50000.00,
    "closing_balance": 75000.00,
    "total_purchases": 100000.00,
    "total_payments": 75000.00,
    "transactions": [
      {
        "date": "2025-01-10",
        "type": "purchase",
        "reference": "PO-2025-0001",
        "amount": 50000.00,
        "balance": 100000.00
      },
      {
        "date": "2025-01-11",
        "type": "payment",
        "reference": "PAY-2025-0001",
        "amount": 25000.00,
        "balance": 75000.00
      }
    ]
  }
}
```

---

#### POST /api/v1/finance/money-collections
Record money collection (15-minute deadline)

**Request:**
```json
{
  "shop_id": "shop-uuid",
  "daily_sales_record_id": "record-uuid",
  "collection_amount": 45000.00,
  "notes": "Cash collected from register"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "id": "collection-uuid",
    "collection_amount": 45000.00,
    "collection_time": "2025-01-11T19:05:00Z",
    "approval_deadline": "2025-01-11T19:20:00Z",
    "status": "pending",
    "time_remaining_seconds": 900
  }
}
```

---

### 4.6 Dashboard API

#### GET /api/v1/sales/dashboard
Get sales dashboard data

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| shop_id | UUID | Filter by shop |
| period | string | today, week, month, custom |
| start_date | date | For custom period |
| end_date | date | For custom period |

**Response (200):**
```json
{
  "success": true,
  "data": {
    "summary": {
      "total_sales": 450000.00,
      "total_transactions": 150,
      "average_transaction": 3000.00,
      "growth_percentage": 12.5
    },
    "top_products": [
      {
        "product": {
          "id": "product-uuid",
          "name": "Royal Challenge"
        },
        "quantity_sold": 500,
        "revenue": 225000.00
      }
    ],
    "sales_by_day": [
      {
        "date": "2025-01-11",
        "amount": 45000.00,
        "count": 15
      }
    ],
    "pending_approvals": 5,
    "low_stock_alerts": 8
  }
}
```

---

## 5. WebSocket API

### 5.1 Connection

```javascript
const ws = new WebSocket('wss://new.v2.floelife.in/ws?token=<jwt_token>');
```

### 5.2 Event Format

```json
{
  "event": "sales.approved",
  "data": {
    "record_id": "record-uuid",
    "shop_id": "shop-uuid",
    "approved_by": "Jane Manager",
    "approved_at": "2025-01-11T19:00:00Z"
  },
  "timestamp": "2025-01-11T19:00:00Z"
}
```

### 5.3 Available Events

| Event | Description |
|-------|-------------|
| `sales.approved` | Daily sales approved |
| `sales.rejected` | Daily sales rejected |
| `stock.low` | Stock below reorder level |
| `deadline.approaching` | 15-minute deadline warning |
| `notification.new` | New notification |
| `collection.pending` | Money collection pending |

---

## 6. Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `AUTH_REQUIRED` | 401 | Authentication required |
| `TOKEN_EXPIRED` | 401 | JWT token expired |
| `TOKEN_INVALID` | 401 | Invalid JWT token |
| `PERMISSION_DENIED` | 403 | Insufficient permissions |
| `RESOURCE_NOT_FOUND` | 404 | Resource not found |
| `VALIDATION_ERROR` | 422 | Input validation failed |
| `DUPLICATE_RESOURCE` | 409 | Resource already exists |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Server error |
| `SERVICE_UNAVAILABLE` | 503 | Service temporarily unavailable |

---

## 7. Rate Limits

| Endpoint Category | Limit | Window |
|-------------------|-------|--------|
| Authentication | 5 requests | 15 minutes |
| OTP Send | 3 requests | 1 minute |
| Standard API | 100 requests | 1 minute |
| Admin API | 500 requests | 1 minute |
| Bulk Operations | 10 requests | 1 minute |
| Report Generation | 5 requests | 1 minute |

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 2.0.0 | Jan 2025 | API Team | Complete API documentation |
| 1.0.0 | Jul 2024 | API Team | Initial release |

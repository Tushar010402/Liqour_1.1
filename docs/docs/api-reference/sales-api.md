# Sales API

## Overview

The Sales API provides endpoints for managing daily sales records, individual transactions, returns, drafts, OCR processing, and AI validation.

**Base URL**: `https://new.v2.floelife.in/api`

---

## Daily Sales Records

### List Daily Sales Records

#### GET /daily-records

Retrieve daily sales records with filtering and pagination. Alias: `GET /daily-sales`

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| shop_id | UUID | No | Filter by shop |
| start_date | date | No | Start date (YYYY-MM-DD) |
| end_date | date | No | End date (YYYY-MM-DD) |
| status | string | No | pending, approved, rejected |
| salesman_id | UUID | No | Filter by salesman |
| page | int | No | Page number (default: 1) |
| per_page | int | No | Items per page (default: 20, max: 100) |

**Request:**
```http
GET /api/daily-records?shop_id=shop-uuid&status=pending&page=1
Authorization: Bearer <access_token>
X-Tenant-ID: <tenant_id>
```

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "dsr-uuid-1",
      "record_date": "2025-01-11",
      "shop": {
        "id": "shop-uuid",
        "name": "Main Street Store"
      },
      "salesman": {
        "id": "salesman-uuid",
        "name": "John Doe"
      },
      "total_sales_amount": 45000.00,
      "total_cash_amount": 30000.00,
      "total_card_amount": 10000.00,
      "total_upi_amount": 5000.00,
      "total_credit_amount": 0.00,
      "total_expense_amount": 500.00,
      "total_items": 35,
      "status": "pending",
      "created_at": "2025-01-11T18:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 20,
    "total": 45,
    "total_pages": 3
  }
}
```

---

### Check Record Exists

#### GET /daily-records/exists

Check if a daily sales record exists for a specific date and shop. Used to prevent duplicates.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| shop_id | UUID | Yes | Shop ID |
| record_date | date | Yes | Date to check (YYYY-MM-DD) |

**Request:**
```http
GET /api/daily-records/exists?shop_id=shop-uuid&record_date=2025-01-11
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "exists": true,
    "record_id": "dsr-uuid-1",
    "status": "pending"
  }
}
```

---

### Get Daily Sales Record

#### GET /daily-records/:id

Get detailed daily sales record including items and expenses.

**Response includes:**
- Payment breakdown (cash, card, UPI, credit)
- OCR session info (if created via OCR)
- Location tracking (latitude, longitude)
- Validation status
- Revert information (if applicable)

---

### Create Daily Sales Record

#### POST /daily-records

Create a new daily sales record. Role required: `salesman`, `manager`, or `admin`.

**Request:**
```http
POST /api/daily-records
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "shop_id": "shop-uuid",
  "record_date": "2025-01-11",
  "salesman_id": "salesman-uuid",
  "items": [
    {
      "product_id": "product-uuid-1",
      "quantity": 10,
      "unit_price": 450.00,
      "cash_amount": 4500.00,
      "card_amount": 0,
      "upi_amount": 0,
      "credit_amount": 0,
      "opening_stock": 50,
      "closing_stock": 40
    }
  ],
  "expenses": [
    {
      "header_id": "expense-header-uuid",
      "header_name": "Transport",
      "amount": 500.00,
      "description": "Delivery charges"
    }
  ],
  "notes": "Weekend sale"
}
```

---

### Update Daily Sales Record

#### PUT /daily-records/:id

Update a pending or rejected record. Role required: `salesman`, `manager`, or `admin`.

---

### Change Record Date

#### PATCH /daily-records/:id/change-date

Change only the date of a daily sales record. Role required: `salesman`, `manager`, or `admin`.

---

### Approve Daily Sales

#### POST /daily-records/:id/approve

Approve a pending record. Role required: `manager` or `admin`.

**Response includes:**
- Money collection created with 15-minute deadline
- Deadline timestamp for cash collection

---

### Reject Daily Sales

#### POST /daily-records/:id/reject

Reject a pending record. Role required: `manager` or `admin`.

**Request:**
```http
POST /api/daily-records/dsr-uuid/reject
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "reason": "Quantity mismatch detected. Please verify and resubmit."
}
```

---

### Copy Record

#### POST /daily-records/:id/copy

Copy a rejected record to create a new editable version. Role required: `salesman`, `manager`, or `admin`.

---

### Upload Images

#### POST /daily-records/upload-image

Upload images for a daily sales record.

---

## Draft Management

Drafts are stored server-side (replaces Hive local storage) and support auto-save.

### Get Draft

#### GET /daily-sales/draft

Get current user's draft for a specific shop and date.

**Query Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| shop_id | UUID | Yes | Shop ID |
| record_date | date | Yes | Date (YYYY-MM-DD) |

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "draft-uuid",
    "shop_id": "shop-uuid",
    "record_date": "2025-01-11",
    "draft_data": {
      "items": [...],
      "expenses": [...]
    },
    "last_saved_at": "2025-01-11T18:00:00Z"
  }
}
```

---

### Save Draft

#### POST /daily-sales/draft

Save or update a draft. Supports auto-save every 30 seconds.

**Request:**
```http
POST /api/daily-sales/draft
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "shop_id": "shop-uuid",
  "record_date": "2025-01-11",
  "draft_data": {
    "items": [...],
    "expenses": [...]
  }
}
```

---

### Discard Draft

#### DELETE /daily-sales/draft

Delete a draft.

---

### Submit Draft

#### POST /daily-sales/draft/submit

Convert a draft to a daily sales record (status: pending).

**Request:**
```http
POST /api/daily-sales/draft/submit
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "shop_id": "shop-uuid",
  "record_date": "2025-01-11"
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "daily_record_id": "dsr-uuid-new",
    "status": "pending",
    "message": "Draft submitted successfully"
  }
}
```

---

### List User Drafts

#### GET /daily-sales/drafts

Get all drafts for current user.

---

## Daily Sales Revert (Admin/Owner Only)

Revert approved sales requires dual OTP verification.

### Request Revert OTP

#### POST /daily-sales/:id/revert/request-otp

Request OTP for reverting an approved daily sales record. Role required: `admin` or `owner`.

---

### Revert Daily Sales

#### POST /daily-sales/:id/revert

Revert an approved record back to pending. Requires OTP verification.

**Request:**
```http
POST /api/daily-sales/dsr-uuid/revert
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "otp": "123456",
  "reason": "Discovered calculation error"
}
```

---

## AI Validation

### Get Validation Status

#### GET /daily-records/:id/validation

Get AI validation results for a daily sales record.

---

### Trigger Validation

#### POST /daily-records/:id/validation/trigger

Manually trigger AI validation. Role required: `manager` or `admin`.

---

### Confirm Validation

#### POST /daily-records/:id/validation/confirm

Confirm/accept AI validation results. Role required: `manager` or `admin`.

---

### Validation Accuracy Dashboard

#### GET /sales/validation/accuracy

Get validation accuracy metrics. Role required: `manager` or `admin`.

---

## Individual Sales

For single sale transactions (not bulk daily entry).

### List Sales

#### GET /sales

Get individual sales with filtering.

---

### Create Sale

#### POST /sales

Create a single sale transaction. Role required: `salesman`, `manager`, or `admin`.

---

### Get Sale

#### GET /sales/:id

Get sale details.

---

### Update Sale

#### PUT /sales/:id

Update a sale. Role required: `salesman`, `manager`, `assistant_manager`, or `admin`.

---

### Approve Sale

#### POST /sales/:id/approve

Approve a pending sale. Role required: `manager` or `admin`.

---

### Reject Sale

#### POST /sales/:id/reject

Reject a pending sale. Role required: `manager` or `admin`.

---

### Revert Sale

#### POST /sales/:id/revert/request-otp
#### POST /sales/:id/revert

Revert an approved sale (requires OTP). Role required: `admin` or `owner`.

---

## Sale Returns

### List Returns

#### GET /returns

Get sale returns with filtering.

---

### Create Return

#### POST /returns

Create a sale return. Role required: `salesman`, `manager`, or `admin`.

---

### Get Return

#### GET /returns/:id

Get return details.

---

### Approve Return

#### POST /returns/:id/approve

Approve a pending return. Role required: `manager` or `admin`.

---

### Reject Return

#### POST /returns/:id/reject

Reject a pending return. Role required: `manager` or `admin`.

---

## Pending Items

### Get Pending Sales

#### GET /pending/sales

Get all pending sales awaiting approval. Role required: `manager` or `admin`.

---

### Get Pending Returns

#### GET /pending/returns

Get all pending returns awaiting approval. Role required: `manager` or `admin`.

---

## Financial

### Get Uncollected Sales

#### GET /financial/uncollected

Get sales with uncollected money. Role required: `executive`, `manager`, or `admin`.

---

## Dashboard

### Get Dashboard Summary

#### GET /dashboard/summary

Get sales dashboard summary with metrics.

---

## Reports

### Purcha Report Preview

#### GET /reports/purcha/preview

Get daily sales register (Purcha) report preview in HTML.

---

### Purcha Report PDF

#### GET /reports/purcha/pdf

Download daily sales register as PDF.

---

## OCR Processing

OCR uses Google Cloud Vision (primary) with Gemini AI fallback for receipt processing.

### Create OCR Batch Session

#### POST /ocr/batch/sessions

Upload receipt images for OCR processing.

**Request (multipart/form-data):**
```http
POST /api/ocr/batch/sessions
Authorization: Bearer <access_token>
Content-Type: multipart/form-data

shop_id: shop-uuid
images[]: <file: receipt1.jpg>
images[]: <file: receipt2.jpg>
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "session_id": "ocr-session-uuid",
    "status": "processing",
    "total_images": 2,
    "processed": 0,
    "estimated_time_seconds": 30
  }
}
```

---

### Get OCR Session Status

#### GET /ocr/batch/sessions/:id

Check OCR processing status and results.

---

### Deduplicate OCR Items

#### POST /ocr/batch/deduplicate

Remove duplicate items from OCR results.

---

### Import OCR Results

#### POST /ocr/batch/import

Import reviewed OCR items into a daily sales record.

**Request:**
```http
POST /api/ocr/batch/import
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "session_id": "ocr-session-uuid",
  "daily_record_id": "dsr-uuid",
  "items": [
    {
      "row_index": 0,
      "product_id": "product-uuid-1",
      "quantity": 10,
      "unit_price": 450.00
    }
  ]
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "imported_count": 1,
    "daily_record_id": "dsr-uuid"
  }
}
```

---

### Find Brand Matches

#### POST /ocr/brands/match

Use Gemini AI to find matching brands for OCR text.

---

### Auto-Create Brand

#### POST /ocr/brands/create

Automatically create a new brand from OCR data.

---

### OCR Metrics

#### GET /ocr/metrics

Get OCR processing metrics.

---

### Validation Endpoints

#### POST /ocr/batch/validate/:id
#### POST /ocr/batch/validate-row
#### POST /ocr/batch/validate-comprehensive/:id
#### GET /ocr/accuracy/dashboard

Comprehensive validation endpoints for OCR results.

---

## Learning & Analytics

### Get Learning Stats

#### GET /sales/learning/stats

Get ML learning statistics. Role required: `manager` or `admin`.

---

### Get Accuracy Trend

#### GET /sales/learning/accuracy-trend

Get accuracy trend over time. Role required: `manager` or `admin`.

---

### Trigger Batch Learning

#### POST /sales/learning/batch-process

Trigger batch learning process. Role required: `admin`.

---

## WebSocket

### Real-time Updates

#### GET /ws

WebSocket endpoint for real-time updates. Handles auth via query parameters.

**Connection:**
```
wss://new.v2.floelife.in/ws?token=<access_token>
```

---

## Error Codes

| Code | Description |
|------|-------------|
| RECORD_NOT_FOUND | Daily sales record not found |
| DUPLICATE_RECORD | Record for this shop/date already exists |
| INVALID_STATUS | Cannot perform action on record in current status |
| INSUFFICIENT_STOCK | Product quantity exceeds available stock |
| FUTURE_DATE | Cannot create record for future date |
| BACKDATE_LIMIT | Cannot create record older than allowed limit |
| APPROVAL_REQUIRED | Only managers can approve/reject |
| OCR_FAILED | OCR processing failed for image |
| REVERT_OTP_REQUIRED | OTP required for revert operation |
| DRAFT_NOT_FOUND | Draft not found for specified shop/date |

---

## Role Requirements Summary

| Endpoint | Roles Allowed |
|----------|---------------|
| Create/Update/Copy Records | salesman, manager, admin |
| Approve/Reject Records | manager, admin |
| Revert Records | admin, owner |
| Pending Items | manager, admin |
| Uncollected Sales | executive, manager, admin |
| OCR Processing | salesman, manager, admin, owner, saas_admin |
| Learning Analytics | manager, admin |
| Batch Learning Trigger | admin |

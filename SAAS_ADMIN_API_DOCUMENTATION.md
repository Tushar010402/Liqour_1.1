# SaaS Admin Backend API Documentation

## Base URL
```
http://localhost:8095
```

## Service Health Check
**Endpoint:** `GET /health`
```bash
curl -X GET http://localhost:8095/health
```
**Response:**
```json
{
  "service": "saas",
  "status": "healthy"
}
```

---

## 🔐 Authentication APIs

### 1. Check SaaS Admin Status
**Endpoint:** `POST /api/saas-admin/is-admin`
```bash
curl -X POST http://localhost:8095/api/saas-admin/is-admin \
  -H "Content-Type: application/json" \
  -d '{"mobile": "+918630668488"}'
```
**Response:**
```json
{
  "is_saas_admin": true,
  "mobile": "+918630668488"
}
```

### 2. Send OTP
**Endpoint:** `POST /api/saas-admin/send-otp`
```bash
curl -X POST http://localhost:8095/api/saas-admin/send-otp \
  -H "Content-Type: application/json" \
  -d '{"mobile": "+918630668488"}'
```
**Response:**
```json
{
  "success": true,
  "message": "OTP sent successfully",
  "mobile": "+918630668488",
  "demo": true
}
```

### 3. Verify OTP & Login
**Endpoint:** `POST /api/saas-admin/verify-otp`
```bash
curl -X POST http://localhost:8095/api/saas-admin/verify-otp \
  -H "Content-Type: application/json" \
  -d '{"mobile": "+918630668488", "otp": "111111"}'
```
**Response:**
```json
{
  "success": true,
  "message": "Login successful",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJleHAiOjE3NTg5MTczMzUsImlhdCI6MTc1ODgzMDkzNSwiaXNzIjoic2Fhcy1hZG1pbi1zZXJ2aWNlIiwibW9iaWxlIjoiKzkxODYzMDY2ODQ4OCIsInJvbGUiOiJzYWFzX2FkbWluIiwidXNlcl9pZCI6IjUwYTUyODVlLWYxMGItNGUyNi1iYmE5LTIwZmVjNGYwZDQ1NCJ9._FKZzpu_Aw0-Pp5rjW2_Xsnesl__qZpsF7J1dPMD-hE",
  "user": {
    "active": true,
    "email": "tusharagrawal0104@gmail.com",
    "first_name": "Tushar",
    "last_name": "Agrawal",
    "mobile": "+918630668488",
    "name": "Tushar Agrawal",
    "role": "saas_admin"
  }
}
```

---

## 📋 Public APIs (No Authentication Required)

### 4. Get Public Plans
**Endpoint:** `GET /api/plans`
```bash
curl -X GET http://localhost:8095/api/plans
```
**Response:**
```json
{
  "plans": [
    {
      "id": "1691cc4d-856c-4662-b49a-ba0d3c6325ce",
      "name": "starter_plan",
      "display_name": "Starter Plan",
      "description": "Perfect for small liquor stores with basic inventory management needs",
      "price": 1999,
      "currency": "INR",
      "billing_cycle": "monthly",
      "trial_days": 30,
      "yearly_discount": 15,
      "max_users": 5,
      "max_products": 1000,
      "max_locations": 2,
      "features": [
        "inventory_management",
        "sales_tracking",
        "basic_reports",
        "mobile_app",
        "email_support"
      ],
      "ai_features": [
        "inventory_optimization",
        "sales_forecasting"
      ],
      "popular": false,
      "enterprise": false,
      "sort_order": 0
    }
  ]
}
```

### 5. Get Plans with Billing Options
**Endpoint:** `GET /api/plans/with-billing-options`
```bash
curl -X GET http://localhost:8095/api/plans/with-billing-options
```

### 6. Get Plan Billing Options
**Endpoint:** `GET /api/plans/{id}/billing-options`
```bash
curl -X GET http://localhost:8095/api/plans/1691cc4d-856c-4662-b49a-ba0d3c6325ce/billing-options
```

### 7. Get Public Brands
**Endpoint:** `GET /api/brands/public`
```bash
curl -X GET http://localhost:8095/api/brands/public
```

---

## 🔒 Super Admin APIs (Requires Token)

**Note:** All Super Admin APIs require the `Authorization: Bearer {token}` header.

### Tenant Management

#### 8. Get All Tenants
**Endpoint:** `GET /api/super-admin/tenants`
```bash
curl -X GET http://localhost:8095/api/super-admin/tenants \
  -H "Authorization: Bearer YOUR_TOKEN"
```
**Response:**
```json
{
  "tenants": [
    {
      "id": "712fd4a7-8879-4ad9-98c1-f054d1881669",
      "name": "Dr Dangs Lab",
      "email": "Dr Dangs Lab",
      "status": "active",
      "subscription_plan": "Professional Plan",
      "created_at": "2025-09-23T18:21:49.034855Z",
      "last_active": "2025-09-24T07:11:20.101382Z",
      "users_count": 0,
      "locations_count": 0,
      "products_count": 0
    }
  ],
  "total": 8
}
```

### Plan Management

#### 9. Get All Plans (Admin)
**Endpoint:** `GET /api/super-admin/plans`
```bash
curl -X GET http://localhost:8095/api/super-admin/plans \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 10. Create Plan
**Endpoint:** `POST /api/super-admin/plans`
```bash
curl -X POST http://localhost:8095/api/super-admin/plans \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "new_plan",
    "display_name": "New Plan",
    "description": "A new plan",
    "price": 2999,
    "currency": "INR",
    "billing_cycle": "monthly",
    "trial_days": 14,
    "max_users": 10,
    "max_products": 2000,
    "max_locations": 3,
    "features": ["inventory", "sales"],
    "yearly_discount": 20
  }'
```

#### 11. Update Plan
**Endpoint:** `PUT /api/super-admin/plans/{id}`
```bash
curl -X PUT http://localhost:8095/api/super-admin/plans/PLAN_ID \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "display_name": "Updated Plan Name",
    "price": 3999
  }'
```

#### 12. Delete Plan
**Endpoint:** `DELETE /api/super-admin/plans/{id}`
```bash
curl -X DELETE http://localhost:8095/api/super-admin/plans/PLAN_ID \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Subscription Management

#### 13. Get All Subscriptions
**Endpoint:** `GET /api/super-admin/subscriptions`
```bash
curl -X GET "http://localhost:8095/api/super-admin/subscriptions?page=1&limit=10&status=active" \
  -H "Authorization: Bearer YOUR_TOKEN"
```
**Query Parameters:**
- `page` (optional): Page number (default: 1)
- `limit` (optional): Results per page (default: 10, max: 100)
- `status` (optional): Filter by status (active, suspended, cancelled, trial, all)

#### 14. Get Subscription Details
**Endpoint:** `GET /api/super-admin/subscriptions/{id}`
```bash
curl -X GET http://localhost:8095/api/super-admin/subscriptions/SUBSCRIPTION_ID \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 15. Update Subscription Status
**Endpoint:** `PUT /api/super-admin/subscriptions/{id}/status`
```bash
curl -X PUT http://localhost:8095/api/super-admin/subscriptions/SUBSCRIPTION_ID/status \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "suspended",
    "reason": "Payment failure"
  }'
```
**Status options:** active, suspended, cancelled, trial

### Brand Management

#### 16. Get All Brands
**Endpoint:** `GET /api/super-admin/brands`
```bash
curl -X GET http://localhost:8095/api/super-admin/brands \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 17. Create Brand
**Endpoint:** `POST /api/super-admin/brands`
```bash
curl -X POST http://localhost:8095/api/super-admin/brands \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "New Brand",
    "category_id": "CATEGORY_ID",
    "description": "Brand description",
    "manufacturer": "Manufacturer Name"
  }'
```

#### 18. Get Brand Categories
**Endpoint:** `GET /api/super-admin/brands/categories`
```bash
curl -X GET http://localhost:8095/api/super-admin/brands/categories \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 19. Create Brand Category
**Endpoint:** `POST /api/super-admin/brands/categories`
```bash
curl -X POST http://localhost:8095/api/super-admin/brands/categories \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Wine",
    "description": "Wine category"
  }'
```

#### 20. Get Brand Variants
**Endpoint:** `GET /api/super-admin/brands/{brand_id}/variants`
```bash
curl -X GET "http://localhost:8095/api/super-admin/brands/4c6875f7-9d7e-4624-b02f-43f0571a4545/variants" \
  -H "Authorization: Bearer YOUR_TOKEN"
```
**Response:**
```json
{
  "count": 1,
  "data": [
    {
      "id": "8a9a61cc-cd88-4227-a77d-6585fc2efde4",
      "brand_id": "4c6875f7-9d7e-4624-b02f-43f0571a4545",
      "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
      "subcategory_id": null,
      "size": "750ml",
      "alcohol_content": 0,
      "picture": "",
      "government_duty": 0,
      "buying_price": 0,
      "selling_price": 0,
      "mrp": 0,
      "description": "",
      "barcode": "5000267024004",
      "hsn_code": "",
      "is_active": true,
      "sort_order": 0,
      "category": {
        "id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
        "name": "Whiskey",
        "description": "Whiskey and whiskey-based spirits",
        "is_active": true,
        "sort_order": 0
      },
      "created_at": "2025-09-25T20:29:04.813997Z",
      "updated_at": "2025-09-25T20:29:04.813997Z"
    }
  ],
  "message": "Brand variants retrieved successfully"
}
```

#### 21. Create Brand Variant
**Endpoint:** `POST /api/super-admin/brands/variants`
```bash
curl -X POST "http://localhost:8095/api/super-admin/brands/variants" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "brand_id": "4c6875f7-9d7e-4624-b02f-43f0571a4545",
    "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
    "size": "1L",
    "alcohol_content": 40,
    "selling_price": 2999,
    "buying_price": 2500,
    "mrp": 3200,
    "description": "Johnnie Walker Red Label 1L variant",
    "barcode": "5000267024005"
  }'
```
**Response:**
```json
{
  "data": {
    "id": "a9a91d9e-09f8-44f4-a436-bfa0856653f1",
    "brand_id": "4c6875f7-9d7e-4624-b02f-43f0571a4545",
    "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
    "subcategory_id": null,
    "size": "1L",
    "alcohol_content": 40,
    "picture": "",
    "government_duty": 0,
    "buying_price": 2500,
    "selling_price": 2999,
    "mrp": 3200,
    "description": "Johnnie Walker Red Label 1L variant",
    "barcode": "5000267024005",
    "hsn_code": "",
    "is_active": true,
    "sort_order": 0,
    "category": {
      "id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
      "name": "Whiskey",
      "description": "Whiskey and whiskey-based spirits",
      "is_active": true,
      "sort_order": 0
    },
    "created_at": "2025-09-25T20:41:41.676245Z",
    "updated_at": "2025-09-25T20:41:41.676245Z"
  },
  "message": "Brand variant created successfully"
}
```

#### 22. Get Brand Subcategories
**Endpoint:** `GET /api/super-admin/brands/subcategories`
```bash
curl -X GET "http://localhost:8095/api/super-admin/brands/subcategories" \
  -H "Authorization: Bearer YOUR_TOKEN"
```
**Response:**
```json
{
  "count": 7,
  "data": [
    {
      "id": "31b39579-7b09-42e9-9b46-77e261cb9175",
      "name": "Premium",
      "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
      "description": "Premium Quality Whiskey",
      "is_active": true,
      "sort_order": 0,
      "created_at": "2025-09-25T06:46:37.586593Z",
      "updated_at": "2025-09-25T06:46:37.586593Z"
    },
    {
      "id": "a5cd8f06-076b-4b6c-a1b2-442d9c30ce20",
      "name": "Single Malt",
      "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
      "description": "Single Malt Scotch Whisky",
      "is_active": true,
      "sort_order": 1,
      "created_at": "2025-09-25T20:28:24.591539Z",
      "updated_at": "2025-09-25T20:28:24.591539Z"
    }
  ],
  "message": "Brand subcategories retrieved successfully"
}
```

#### 23. Create Brand Subcategory
**Endpoint:** `POST /api/super-admin/brands/subcategories`
```bash
curl -X POST "http://localhost:8095/api/super-admin/brands/subcategories" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Blended Whisky",
    "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
    "description": "Premium blended whisky subcategory"
  }'
```
**Response:**
```json
{
  "data": {
    "id": "96b60656-3871-4a73-be6d-c0638a3e4348",
    "name": "Blended Whisky",
    "category_id": "fdce88eb-3e60-4bdb-82d7-a46998ec9298",
    "description": "Premium blended whisky subcategory",
    "is_active": true,
    "sort_order": 0,
    "created_at": "2025-09-25T20:42:25.013261786Z",
    "updated_at": "2025-09-25T20:42:25.013261786Z"
  },
  "message": "Brand subcategory created successfully"
}
```

### Discount Management

#### 24. Get Global Discount Configs
**Endpoint:** `GET /api/super-admin/discounts/configs`
```bash
curl -X GET http://localhost:8095/api/super-admin/discounts/configs \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 25. Create Global Discount Config
**Endpoint:** `POST /api/super-admin/discounts/configs`
```bash
curl -X POST http://localhost:8095/api/super-admin/discounts/configs \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "discount_type": "percentage",
    "discount_value": 10,
    "min_term_months": 12,
    "description": "Annual discount"
  }'
```

#### 26. Get Billing Term Configs
**Endpoint:** `GET /api/super-admin/discounts/billing-terms`
```bash
curl -X GET http://localhost:8095/api/super-admin/discounts/billing-terms \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Analytics

#### 27. Get Analytics Dashboard
**Endpoint:** `GET /api/super-admin/analytics/dashboard`
```bash
curl -X GET http://localhost:8095/api/super-admin/analytics/dashboard \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 28. Get Revenue Analytics
**Endpoint:** `GET /api/super-admin/analytics/revenue`
```bash
curl -X GET http://localhost:8095/api/super-admin/analytics/revenue \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 25. Get Subscription Metrics
**Endpoint:** `GET /api/super-admin/analytics/subscriptions`
```bash
curl -X GET http://localhost:8095/api/super-admin/analytics/subscriptions \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### System Management

#### 26. Get System Health
**Endpoint:** `GET /api/super-admin/system/health`
```bash
curl -X GET http://localhost:8095/api/super-admin/system/health \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 27. Get Audit Logs
**Endpoint:** `GET /api/super-admin/system/audit-logs`
```bash
curl -X GET "http://localhost:8095/api/super-admin/system/audit-logs?page=1&limit=20&resource=subscription" \
  -H "Authorization: Bearer YOUR_TOKEN"
```
**Query Parameters:**
- `page` (optional): Page number (default: 1)
- `limit` (optional): Results per page (default: 20, max: 100)
- `resource` (optional): Filter by resource type
- `tenant_id` (optional): Filter by tenant ID

#### 28. Toggle Maintenance Mode
**Endpoint:** `POST /api/super-admin/system/maintenance`
```bash
curl -X POST http://localhost:8095/api/super-admin/system/maintenance \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "message": "System maintenance in progress"
  }'
```

### Usage Tracking

#### 29. Get Tenant Usage
**Endpoint:** `GET /api/super-admin/usage/{tenant_id}/current`
```bash
curl -X GET http://localhost:8095/api/super-admin/usage/TENANT_ID/current \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 30. Get All Tenants Usage
**Endpoint:** `GET /api/super-admin/usage/all-tenants`
```bash
curl -X GET http://localhost:8095/api/super-admin/usage/all-tenants \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 31. Get Usage Alerts
**Endpoint:** `GET /api/super-admin/usage/alerts`
```bash
curl -X GET http://localhost:8095/api/super-admin/usage/alerts \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Plan Transitions

#### 32. Get Transition History
**Endpoint:** `GET /api/super-admin/transitions/subscription/{subscription_id}/history`
```bash
curl -X GET http://localhost:8095/api/super-admin/transitions/subscription/SUBSCRIPTION_ID/history \
  -H "Authorization: Bearer YOUR_TOKEN"
```

#### 33. Preview Plan Transition
**Endpoint:** `POST /api/super-admin/transitions/preview`
```bash
curl -X POST http://localhost:8095/api/super-admin/transitions/preview \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "subscription_id": "SUBSCRIPTION_ID",
    "new_plan_id": "NEW_PLAN_ID",
    "transition_type": "upgrade"
  }'
```

---

## 🔐 Protected Tenant APIs (Requires Authentication)

### Subscription Management (Tenant)

#### 34. Get Tenant Subscription
**Endpoint:** `GET /api/subscriptions`
```bash
curl -X GET http://localhost:8095/api/subscriptions \
  -H "Authorization: Bearer TENANT_TOKEN"
```

#### 35. Create Subscription
**Endpoint:** `POST /api/subscriptions`
```bash
curl -X POST http://localhost:8095/api/subscriptions \
  -H "Authorization: Bearer TENANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "plan_id": "PLAN_ID",
    "billing_cycle": "monthly"
  }'
```

#### 36. Get Subscription Usage
**Endpoint:** `GET /api/subscriptions/{id}/usage`
```bash
curl -X GET http://localhost:8095/api/subscriptions/SUBSCRIPTION_ID/usage \
  -H "Authorization: Bearer TENANT_TOKEN"
```

### Payment Management

#### 37. Get Payments
**Endpoint:** `GET /api/payments`
```bash
curl -X GET http://localhost:8095/api/payments \
  -H "Authorization: Bearer TENANT_TOKEN"
```

#### 38. Create Payment
**Endpoint:** `POST /api/payments`
```bash
curl -X POST http://localhost:8095/api/payments \
  -H "Authorization: Bearer TENANT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 2999,
    "currency": "INR",
    "payment_method": "razorpay"
  }'
```

#### 39. Get Invoices
**Endpoint:** `GET /api/invoices`
```bash
curl -X GET http://localhost:8095/api/invoices \
  -H "Authorization: Bearer TENANT_TOKEN"
```

### Usage Tracking (Tenant)

#### 40. Get Current Usage
**Endpoint:** `GET /api/usage/{tenant_id}/current`
```bash
curl -X GET http://localhost:8095/api/usage/TENANT_ID/current \
  -H "Authorization: Bearer TENANT_TOKEN"
```

#### 41. Get Usage Metrics
**Endpoint:** `GET /api/usage/{tenant_id}/metrics`
```bash
curl -X GET http://localhost:8095/api/usage/TENANT_ID/metrics \
  -H "Authorization: Bearer TENANT_TOKEN"
```

#### 42. Export Usage Report
**Endpoint:** `GET /api/usage/{tenant_id}/export`
```bash
curl -X GET http://localhost:8095/api/usage/TENANT_ID/export \
  -H "Authorization: Bearer TENANT_TOKEN"
```

---

## 🔗 Webhook Endpoints

#### 43. Razorpay Webhook
**Endpoint:** `POST /api/webhooks/razorpay`
```bash
curl -X POST http://localhost:8095/api/webhooks/razorpay \
  -H "Content-Type: application/json" \
  -d '{
    "event": "payment.captured",
    "payload": {
      "payment": {
        "entity": {
          "id": "pay_xxxxx",
          "amount": 299900,
          "status": "captured"
        }
      }
    }
  }'
```

---

## 📝 Error Response Format

All endpoints return errors in the following format:

```json
{
  "error": "Error message describing what went wrong"
}
```

Common HTTP status codes:
- `200` - Success
- `201` - Created
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `500` - Internal Server Error

---

## 🔑 Authentication Notes

1. **Demo Credentials:**
   - Mobile: `+918630668488`
   - OTP: `111111`

2. **Token Usage:**
   - Include in header: `Authorization: Bearer YOUR_TOKEN`
   - Tokens expire after 24 hours
   - Super Admin tokens have elevated permissions

3. **Rate Limiting:**
   - OTP requests: 5 attempts per hour per mobile number
   - API requests: Standard rate limiting applies

---

## 📊 Data Models

### Plan Object
```json
{
  "id": "uuid",
  "name": "string",
  "display_name": "string",
  "description": "string",
  "price": "number",
  "currency": "string",
  "billing_cycle": "monthly|yearly",
  "trial_days": "number",
  "yearly_discount": "number",
  "max_users": "number",
  "max_products": "number",
  "max_locations": "number",
  "features": ["string"],
  "ai_features": ["string"],
  "popular": "boolean",
  "enterprise": "boolean",
  "sort_order": "number"
}
```

### Tenant Object
```json
{
  "id": "uuid",
  "name": "string",
  "email": "string",
  "status": "active|trial|suspended|cancelled",
  "subscription_plan": "string",
  "created_at": "datetime",
  "last_active": "datetime",
  "users_count": "number",
  "locations_count": "number",
  "products_count": "number"
}
```

### User Object
```json
{
  "id": "uuid",
  "name": "string",
  "first_name": "string",
  "last_name": "string",
  "email": "string",
  "mobile": "string",
  "role": "saas_admin|tenant_admin|user",
  "active": "boolean"
}
```
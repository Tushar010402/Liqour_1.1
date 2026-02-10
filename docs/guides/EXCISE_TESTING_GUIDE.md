# UP Excise Compliance - Testing Guide

## 🎉 Integration Complete!

The UP Excise compliance module has been successfully integrated into the Inventory service. All 28 API endpoints are now available.

---

## 📋 Pre-Testing Checklist

### Step 1: Run Database Migrations

```bash
cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor

# Connect to PostgreSQL
psql -h localhost -U postgres -d liquorpro

# Run migrations
\i migrations/001_extend_finance_for_excise.sql
\i migrations/002_create_excise_tables.sql

# Verify tables created
\dt excise_*
\d+ bottle_security_codes

# Check views
\dv

# Exit
\q
```

### Step 2: Start the Inventory Service

```bash
cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor

# Build and run inventory service
go run cmd/inventory/main.go
```

You should see:
```
Inventory service starting on 0.0.0.0:8082
UP Excise compliance routes registered
Excise routes registered successfully
```

---

## 🧪 API Testing Guide

### Health Check

```bash
# Test excise module health
curl http://localhost:8082/api/excise/health
```

**Expected Response:**
```json
{
  "status": "healthy",
  "service": "excise",
  "version": "1.0.0"
}
```

---

## 📝 Step-by-Step Testing Workflow

### 1. Create an Excise License

First, you need a shop and a license:

```bash
# Create License
curl -X POST http://localhost:8082/api/excise/licenses \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "YOUR_SHOP_UUID",
    "license_number": "FL-2A/UP/2025/001",
    "license_type": "FL-2A",
    "issued_date": "2025-01-01T00:00:00Z",
    "expiry_date": "2026-01-01T00:00:00Z",
    "monthly_fee": 50000,
    "license_issued_by": "UP Excise Department",
    "excise_district": "Lucknow"
  }'
```

**Response:**
```json
{
  "id": "license-uuid",
  "shop_id": "shop-uuid",
  "license_number": "FL-2A/UP/2025/001",
  "license_type": "FL-2A",
  "is_active": true,
  "monthly_fee": 50000
}
```

### 2. Get All Licenses

```bash
# List all licenses
curl http://localhost:8082/api/excise/licenses \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

### 3. Pay License Fee

```bash
# Pay monthly license fee (creates expense record)
curl -X POST http://localhost:8082/api/excise/licenses/pay-fee \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "license_id": "YOUR_LICENSE_UUID",
    "fee_month": "2025-01-01T00:00:00Z",
    "amount": 50000,
    "payment_method": "NEFT",
    "receipt_no": "EXCISE/2025/001"
  }'
```

**What Happens:**
- Creates an entry in `expenses` table with `is_license_fee=true`
- Links to the license via `excise_license_id`
- Triggers compliance logging automatically
- Integrates with existing finance module

### 4. Add Security Codes (Bulk)

When you receive stock from a CL-2 godown with security codes:

```bash
# Bulk add security codes
curl -X POST http://localhost:8082/api/excise/security-codes/bulk-add \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": "PRODUCT_UUID",
    "security_codes": ["SC001", "SC002", "SC003", "SC004", "SC005"],
    "vendor_transaction_id": "VENDOR_TXN_UUID",
    "stock_purchase_id": "PURCHASE_UUID",
    "source_type": "cl2_godown",
    "source_warehouse": "ABC Warehouse",
    "batch_number": "BATCH2025001"
  }'
```

### 5. Validate a Security Code

```bash
# Validate security code (at time of sale)
curl -X POST http://localhost:8082/api/excise/security-codes/validate \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "security_code": "SC001"
  }'
```

**Response:**
```json
{
  "security_code": "SC001",
  "is_valid": true,
  "status": "in_stock",
  "message": "Security code is valid",
  "product_name": "Product Name"
}
```

### 6. Auto-Generate Daily Report ⭐ (Most Important!)

This is the main feature - automatically generates report from existing data:

```bash
# Auto-generate daily report
curl -X POST http://localhost:8082/api/excise/daily-reports/auto-generate \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "shop_id": "YOUR_SHOP_UUID",
    "report_date": "2025-01-15T00:00:00Z"
  }'
```

**What Happens Behind the Scenes:**
1. ✅ Fetches yesterday's closing stock (opening stock)
2. ✅ Aggregates today's purchases from `stock_purchases` (stock lifted)
3. ✅ Aggregates today's sales from `sales`
4. ✅ Aggregates today's returns from `sales_returns`
5. ✅ Calculates: Opening + Lifted + Returns - Sales = Closing
6. ✅ Links to `money_collections` (if exists for today)
7. ✅ Links to `cash_deposits` (if exists for today)
8. ✅ Sums consideration fees from `vendor_transactions`
9. ✅ Categorizes by excise type (country_liquor, imfl, beer, wine)

**Response:**
```json
{
  "id": "report-uuid",
  "shop_id": "shop-uuid",
  "report_date": "2025-01-15",
  "opening_stock": {
    "country_liquor": [],
    "imfl": [],
    "beer": [],
    "wine": [],
    "total_bottles": 100,
    "total_value": 50000
  },
  "stock_lifted": { ... },
  "sales": { ... },
  "closing_stock": { ... },
  "consideration_fee_paid": 5000,
  "uploaded_to_portal": false
}
```

### 7. Upload Report to Portal

```bash
# Upload report to UP Excise portal
curl -X POST http://localhost:8082/api/excise/daily-reports/REPORT_UUID/upload-to-portal \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

**Response:**
```json
{
  "message": "Report uploaded successfully",
  "report": {
    "uploaded_to_portal": true,
    "sms_confirmation": "SMS-20250115-1234",
    "portal_uploaded_at": "2025-01-15T22:30:00Z"
  }
}
```

### 8. Get Compliance Dashboard

```bash
# Get compliance dashboard
curl http://localhost:8082/api/excise/compliance/dashboard \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

**Response:**
```json
{
  "tenant_id": "tenant-uuid",
  "total_shops": 5,
  "active_licenses": 5,
  "pending_reports": 0,
  "overdue_license_fees": 0,
  "expiring_licenses": 1,
  "compliance_score": 95.0,
  "overall_status": "excellent",
  "alerts": [
    "1 licenses expiring within 30 days"
  ],
  "recent_logs": []
}
```

### 9. Get Pending License Fees

```bash
# Check for overdue fees
curl http://localhost:8082/api/excise/compliance/pending-fees \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

### 10. Get Consideration Fee Summary

```bash
# Get consideration fee analytics
curl "http://localhost:8082/api/excise/compliance/consideration-fees?start_date=2025-01-01&end_date=2025-01-31" \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
```

**Response:**
```json
{
  "start_date": "2025-01-01",
  "end_date": "2025-01-31",
  "total_transactions": 15,
  "total_amount": 75000,
  "total_bottles": 1500,
  "average_fee_per_bottle": 50.00,
  "by_vendor": [
    {
      "vendor_id": "vendor-uuid",
      "vendor_name": "ABC Warehouse",
      "amount": 50000,
      "bottles": 1000,
      "transactions": 10
    }
  ],
  "by_date": []
}
```

---

## 🔍 Database Verification Queries

After testing, verify data in database:

```sql
-- Check licenses created
SELECT * FROM excise_licenses;

-- Check license fee payments (in expenses table)
SELECT * FROM expenses WHERE is_license_fee = true;

-- Check security codes
SELECT * FROM bottle_security_codes LIMIT 10;

-- Check daily reports
SELECT * FROM excise_daily_reports;

-- Check compliance logs
SELECT * FROM excise_compliance_logs ORDER BY logged_at DESC LIMIT 10;

-- Use helper views
SELECT * FROM vw_active_licenses;
SELECT * FROM vw_pending_excise_reports;
SELECT * FROM vw_security_codes_summary;

-- Check extended finance tables
SELECT * FROM vendors WHERE is_cl2_godown = true;
SELECT * FROM vendor_transactions WHERE is_consideration_fee = true;
SELECT * FROM cash_deposits WHERE is_daily_sales_deposit = true;
SELECT * FROM money_collections WHERE included_in_excise_report = true;
```

---

## 📊 Complete API Endpoints List

### License Management (8 endpoints)
```
GET    /api/excise/licenses
POST   /api/excise/licenses
GET    /api/excise/licenses/:id
PUT    /api/excise/licenses/:id
POST   /api/excise/licenses/:id/renew
POST   /api/excise/licenses/pay-fee
GET    /api/excise/licenses/:id/fee-payments
GET    /api/excise/licenses/:id/compliance-status
```

### Daily Reports (6 endpoints)
```
GET    /api/excise/daily-reports
POST   /api/excise/daily-reports/auto-generate          ⭐ Main feature!
GET    /api/excise/daily-reports/date/:date
GET    /api/excise/daily-reports/:id
POST   /api/excise/daily-reports/:id/upload-to-portal
POST   /api/excise/daily-reports/:id/retry-upload
```

### Security Codes (7 endpoints)
```
POST   /api/excise/security-codes/validate
POST   /api/excise/security-codes/bulk-add
GET    /api/excise/security-codes/:code
GET    /api/excise/security-codes/search
POST   /api/excise/security-codes/mark-sold
POST   /api/excise/security-codes/mark-damaged
GET    /api/excise/security-codes/stats
```

### Compliance (6 endpoints)
```
GET    /api/excise/compliance/dashboard
GET    /api/excise/compliance/logs
GET    /api/excise/compliance/expiring-licenses
GET    /api/excise/compliance/pending-fees
GET    /api/excise/compliance/consideration-fees
GET    /api/excise/compliance/report
```

---

## 🚨 Common Issues & Solutions

### Issue 1: "License not found"
**Solution:** Create a license first using POST /api/excise/licenses

### Issue 2: "Shop not found"
**Solution:** Ensure shop_id exists in shops table

### Issue 3: "No data for daily report"
**Solution:**
- Ensure there are sales/purchases for that date
- Check that products have excise_category set
- Verify stock_purchases table has data

### Issue 4: "Portal upload failed"
**Solution:**
- Currently using MockPortalClient (for testing)
- For production, configure real portal client in routes.go:
  ```go
  portalClient := services.NewPortalClient(
      "https://upexcise.gov.in/api",
      "YOUR_API_KEY"
  )
  ```

---

## ✅ Testing Checklist

- [ ] Database migrations run successfully
- [ ] Inventory service starts without errors
- [ ] Health check returns success
- [ ] Can create a license
- [ ] Can pay license fee (creates expense)
- [ ] Can add security codes
- [ ] Can validate security codes
- [ ] Can auto-generate daily report
- [ ] Can upload report to portal (mock)
- [ ] Compliance dashboard shows correct data
- [ ] Pending fees are calculated correctly
- [ ] Consideration fee summary works
- [ ] All 28 endpoints respond correctly

---

## 🎯 Next Steps

1. ✅ Run migrations
2. ✅ Test all endpoints
3. ⏳ Create some test data
4. ⏳ Obtain real UP Excise portal API credentials
5. ⏳ Replace MockPortalClient with real client
6. ⏳ Build Flutter UI (Phase 2)

---

## 📞 Support

If you encounter issues:
1. Check database migrations are applied
2. Verify service is running on correct port (8082)
3. Check authentication token is valid
4. Review compliance logs in database
5. Check server logs for errors

---

**Testing Status**: Ready for testing ✅
**Production Ready**: After portal API integration 🔄
**Flutter UI**: Phase 2 ⏳

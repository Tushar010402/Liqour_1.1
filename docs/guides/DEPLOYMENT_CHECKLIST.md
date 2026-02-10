# Brand Onboarding Deployment Checklist

## Pre-Deployment

### 1. Code Review ✅
- [x] All fixes reviewed and tested
- [x] Backend compiles successfully
- [x] Unit tests created and passing
- [x] API documentation completed
- [x] Flutter code updated

### 2. Dependencies
- [x] Go modules updated (`go mod tidy`)
- [x] New dependencies:
  - `gorm.io/driver/sqlite` (for tests)
  - `github.com/stretchr/testify` (for mocking)

---

## Deployment Steps

### Step 1: Database Migration

**Priority:** HIGH - Must run before deploying new code

```bash
# Connect to production database
export DB_HOST="your-db-host"
export DB_PORT="5432"
export DB_NAME="liquorpro_db"
export DB_USER="liquorpro_user"

# Run migration
psql "postgresql://$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME" \
  -f migrations/add_saas_variant_tracking.sql

# Verify migration
psql "postgresql://$DB_USER@$DB_HOST:$DB_PORT/$DB_NAME" \
  -c "\d products" | grep saas
```

**Expected Output:**
```
saas_brand_id   | uuid        |           |          |
saas_variant_id | uuid        |           |          |
```

**Indexes to verify:**
```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'products'
AND indexname LIKE '%saas%';
```

---

### Step 2: Backend Deployment

#### Option A: Docker (Recommended)

```bash
# 1. Build new inventory service image
docker-compose build inventory

# 2. Stop current inventory service
docker-compose stop inventory

# 3. Start new version
docker-compose up -d inventory

# 4. Check logs
docker-compose logs -f inventory | grep "Starting"
```

#### Option B: Binary Deployment

```bash
# 1. Build binary
make build-inventory
# or
go build -o bin/inventory ./cmd/inventory/

# 2. Stop current service
systemctl stop liquorpro-inventory

# 3. Replace binary
cp bin/inventory /opt/liquorpro/bin/

# 4. Start service
systemctl start liquorpro-inventory

# 5. Check status
systemctl status liquorpro-inventory
```

---

### Step 3: Health Checks

```bash
# 1. Check service is running
curl http://localhost:8083/health

# Expected: {"status":"healthy","service":"inventory"}

# 2. Test new endpoint (with auth)
curl -H "Authorization: Bearer $TOKEN" \
     -H "X-Tenant-ID: $TENANT_ID" \
     http://localhost:8083/api/inventory/saas-brands/available

# Expected: 200 OK with brand list

# 3. Check SaaS service communication
docker logs inventory 2>&1 | grep "SaaS" | tail -10

# Should show successful SaaS service calls
```

---

### Step 4: Flutter App Deployment

#### Development Testing

```bash
cd liquor_pro_app

# 1. Clean build
flutter clean
flutter pub get

# 2. Run on device
flutter run --release

# 3. Test brand onboarding flow:
#    - Navigate to Inventory > Onboard Brands
#    - Verify shop dropdown appears (if multi-shop)
#    - Select brands
#    - Click "Onboard X Products"
#    - Verify success dialog shows correct counts
```

#### Production Build

```bash
# Android
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk

# iOS
flutter build ios --release
# Then upload to App Store via Xcode
```

---

### Step 5: Functional Testing

#### Test Case 1: First-Time Brand Onboarding

```bash
# 1. Login as tenant
# 2. Go to Inventory > Onboard Brands
# 3. Select 2-3 brand variants
# 4. Click Onboard

# Expected Results:
✓ Success dialog appears
✓ Shows correct brand/product/category counts
✓ Products visible in inventory
✓ Products have SKU pattern "SAAS-*"
```

#### Test Case 2: Duplicate Prevention

```bash
# 1. Repeat Test Case 1 with same brands
# 2. Click Onboard again

# Expected Results:
✓ Success dialog shows 0 brands onboarded
✓ No duplicate products created
✓ Database check shows only 1 product per variant
```

**Verification Query:**
```sql
SELECT saas_variant_id, COUNT(*) as count
FROM products
WHERE tenant_id = 'YOUR_TENANT_ID'
  AND saas_variant_id IS NOT NULL
GROUP BY saas_variant_id
HAVING COUNT(*) > 1;

-- Should return 0 rows
```

#### Test Case 3: Multi-Shop Selection

```bash
# 1. Login as multi-shop tenant
# 2. Go to Inventory > Onboard Brands
# 3. Verify shop dropdown appears
# 4. Select shop from dropdown
# 5. Onboard brands

# Expected Results:
✓ Shop dropdown visible
✓ Can select different shops
✓ Brands onboard to selected shop
```

#### Test Case 4: Error Resilience

```bash
# 1. Temporarily stop SaaS service
docker-compose stop saas

# 2. Try to onboard brands

# Expected Results:
✓ Loading spinner appears
✓ Retries 3 times (check logs)
✓ Error message after retries
✓ User can retry manually

# 3. Restart SaaS service
docker-compose start saas

# 4. Retry onboarding
# Expected: Success
```

---

## Rollback Plan

### If Critical Issues Found

#### Step 1: Revert Backend

```bash
# Docker
docker-compose down inventory
git checkout HEAD~1
docker-compose build inventory
docker-compose up -d inventory

# Binary
systemctl stop liquorpro-inventory
cp /opt/liquorpro/bin/inventory.backup /opt/liquorpro/bin/inventory
systemctl start liquorpro-inventory
```

#### Step 2: Revert Database (Only if necessary)

```sql
-- Remove columns
ALTER TABLE products
DROP COLUMN IF EXISTS saas_brand_id,
DROP COLUMN IF EXISTS saas_variant_id;

-- Drop indexes
DROP INDEX IF EXISTS idx_products_tenant_saas_variant_unique;
DROP INDEX IF EXISTS idx_products_saas_variant;
```

**⚠️ WARNING:** This will delete SaaS tracking data. Only do if critical.

#### Step 3: Revert Flutter App

```bash
cd liquor_pro_app
git checkout HEAD~1
flutter clean
flutter pub get
flutter build apk --release
```

---

## Post-Deployment Monitoring

### Week 1 Checklist

- [ ] **Day 1:** Monitor error logs for brand onboarding failures
- [ ] **Day 2:** Check duplicate prevention is working (query database)
- [ ] **Day 3:** Verify retry logic activations in logs
- [ ] **Day 7:** Generate onboarding analytics report

### Metrics to Track

```sql
-- Total brands onboarded per day
SELECT DATE(created_at) as date, COUNT(*) as onboarded_count
FROM products
WHERE saas_variant_id IS NOT NULL
  AND created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;

-- Most popular SaaS brands
SELECT b.name, COUNT(*) as tenant_count
FROM products p
JOIN brands b ON p.brand_id = b.id
WHERE p.saas_brand_id IS NOT NULL
GROUP BY b.id, b.name
ORDER BY tenant_count DESC
LIMIT 10;

-- Categories created from onboarding
SELECT c.name, COUNT(DISTINCT p.tenant_id) as tenant_count
FROM products p
JOIN categories c ON p.category_id = c.id
WHERE p.saas_variant_id IS NOT NULL
GROUP BY c.id, c.name
ORDER BY tenant_count DESC;
```

### Log Monitoring

```bash
# Watch for errors
docker logs -f inventory | grep -E "ERROR|WARN"

# Watch for duplicate skips
docker logs -f inventory | grep "already onboarded"

# Watch for retry attempts
docker logs -f inventory | grep "Retrying SaaS"
```

---

## Performance Benchmarks

### Expected Response Times

| Endpoint | Expected | Acceptable | Critical |
|----------|----------|------------|----------|
| GET /saas-brands/available | < 500ms | < 1s | > 2s |
| POST /saas-brands/onboard (5 brands) | < 2s | < 5s | > 10s |
| POST /saas-brands/onboard (20 brands) | < 10s | < 20s | > 30s |

### Load Testing

```bash
# Install Apache Bench
apt-get install apache2-utils

# Test available brands endpoint
ab -n 100 -c 10 \
   -H "Authorization: Bearer $TOKEN" \
   -H "X-Tenant-ID: $TENANT_ID" \
   http://localhost:8083/api/inventory/saas-brands/available

# Expected: 95% requests < 1s
```

---

## Security Verification

### Checklist

- [ ] Tenant isolation verified (can't access other tenant's brands)
- [ ] Authentication required on all endpoints
- [ ] SQL injection protection (parameterized queries)
- [ ] No sensitive data in logs
- [ ] Rate limiting functional

### Test Commands

```bash
# 1. Test without auth (should fail)
curl http://localhost:8083/api/inventory/saas-brands/available
# Expected: 401 Unauthorized

# 2. Test with wrong tenant ID (should return empty or 403)
curl -H "Authorization: Bearer $TOKEN" \
     -H "X-Tenant-ID: wrong-tenant-id" \
     http://localhost:8083/api/inventory/saas-brands/available
# Expected: Empty list or 403

# 3. Test SQL injection (should be safe)
curl -H "Authorization: Bearer $TOKEN" \
     -H "X-Tenant-ID: $TENANT_ID" \
     -X POST \
     -d '{"brand_ids":["550e8400' OR 1=1--"]}' \
     http://localhost:8083/api/inventory/saas-brands/onboard
# Expected: 400 Bad Request (invalid UUID)
```

---

## Documentation Updates

### Files to Review with Team

1. **API_BRAND_ONBOARDING.md** - Share with frontend team
2. **BRAND_ONBOARDING_FIXES_SUMMARY.md** - Share with stakeholders
3. **DEPLOYMENT_CHECKLIST.md** - Share with DevOps

### User Documentation

Update user manual with:
- How to onboard brands
- Shop selection for multi-shop tenants
- Understanding onboarded vs custom products

---

## Support Contacts

### If Issues Arise

**Backend Issues:**
- Check: `docker logs inventory`
- Contact: Backend team

**Database Issues:**
- Check: Migration status
- Contact: DBA team

**Flutter App Issues:**
- Check: Device logs
- Contact: Mobile team

**SaaS Service Issues:**
- Check: `docker logs saas`
- Contact: Platform team

---

## Success Criteria

### Deployment Successful If:

✅ All health checks pass
✅ Brand onboarding works end-to-end
✅ Duplicate prevention confirmed
✅ No increase in error rates
✅ Response times within acceptable range
✅ Security verification passed

### Deployment Failed If:

❌ Health checks fail
❌ Brand onboarding fails for majority of users
❌ Duplicates being created
❌ Error rate > 5%
❌ Response times exceed critical threshold
❌ Security vulnerabilities found

**Action if failed:** Execute rollback plan immediately

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Backend Lead | | | |
| Frontend Lead | | | |
| QA Lead | | | |
| DevOps | | | |
| Product Owner | | | |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-10-04 | Initial deployment checklist | System |

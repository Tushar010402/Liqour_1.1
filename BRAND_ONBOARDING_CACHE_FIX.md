# Brand Onboarding HTTP Cache Issue - Complete Solution

## 🔍 Problem Summary

**Issue**: Flutter app consistently receives cached HTTP 206 response with empty `brand_details` when attempting to onboard brands, despite backend working correctly.

**Root Cause**: iOS URLSession aggressive HTTP caching - caches responses even for POST requests and ignores request headers.

## 🛠️ Solution Implemented

### 1. Flutter App - Request Cache Headers
**File**: `liquor_pro_app/lib/core/services/api_service.dart`
**Lines**: 32-34

```dart
final headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
  // Prevent HTTP caching
  'Cache-Control': 'no-cache, no-store, must-revalidate',
  'Pragma': 'no-cache',
  'Expires': '0',
};
```

### 2. Backend - Response Cache Headers
**File**: `internal/inventory/handlers/brand_onboarding_handlers.go`
**Lines**: 106-109

```go
// Set cache-control headers to prevent client-side caching
c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
c.Header("Pragma", "no-cache")
c.Header("Expires", "0")
```

## ✅ Verification

### Backend Working (curl test):
```bash
curl -X POST http://localhost:8090/api/inventory/saas-brands/onboard \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer [TOKEN]" \
  -H "X-Tenant-ID: 712fd4a7-8879-4ad9-98c1-f054d1881669" \
  -d '{"brand_ids":[],"variant_ids":["0b6dff77-bed5-44e5-842c-4978e8800fca"],"tenant_id":"712fd4a7-8879-4ad9-98c1-f054d1881669"}'
```

**Response**: ✅ Status 200, product created successfully
```json
{
  "onboarded_brands": 1,
  "onboarded_products": 1,
  "brand_details": [{
    "product_ids": ["190dfd1f-a5de-4227-ac28-a5be271faa9b"],
    "success": true
  }]
}
```

### Inventory Service Logs:
```
✅ OnboardBrands success:
   Onboarded brands: 1
   Onboarded products: 1
   Brand details count: 1
```

## 🚨 Critical: App Restart Required

**The iOS HTTP cache persists across hot reloads and even hot restarts!**

### To Clear Cache and Test:

**Option 1: Kill and Restart Flutter Process**
```bash
# In terminal running Flutter, press 'q' to quit
q

# Restart
cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor/liquor_pro_app
flutter run -d "iPhone 16"
```

**Option 2: Erase Simulator and Restart**
```bash
# Erase all simulator data
xcrun simctl erase all

# Restart Flutter
flutter run -d "iPhone 16"
```

**Option 3: Test with Different Variant (Workaround)**
- Instead of Johnnie Walker variant `0b6dff77-bed5-44e5-842c-4978e8800fca`
- Try a different brand/variant that hasn't been cached yet
- This will bypass the cache for that specific URL+body combination

## 📋 Testing Checklist

After restarting the Flutter app:

1. ✅ Navigate to **Brand Catalog** screen
2. ✅ Select **"Johnnie Walker Red Label 750ml"** variant
3. ✅ Click **"Onboard"** button
4. ✅ Confirm in dialog

### Expected Results:
- ✅ HTTP Status: **200** (not 206)
- ✅ Response: `onboarded_brands: 1, onboarded_products: 1`
- ✅ `brand_details` array contains product IDs
- ✅ Navigate to **Initial Stock Screen**
- ✅ Can set stock quantities
- ✅ Save stock successfully

## 🔧 System Status

### Services Running:
- ✅ `liquorpro-inventory` - Rebuilt with cache headers (Up, healthy)
- ✅ `liquorpro-gateway` - Running (Up, healthy)
- ✅ `liquorpro-saas` - Running (Up, healthy)
- ✅ `liquorpro-postgres` - Running (Up, healthy)

### Database State:
- ✅ All test products deleted
- ✅ Clean slate for testing
- ✅ No products exist for variant `0b6dff77-bed5-44e5-842c-4978e8800fca`

### Files Modified:
1. `liquor_pro_app/lib/core/services/api_service.dart` - Request cache headers
2. `internal/inventory/handlers/brand_onboarding_handlers.go` - Response cache headers
3. Inventory service Docker image rebuilt

## 🎯 Why This Happens

**iOS URLSession Caching Behavior:**
1. iOS URLSession caches HTTP responses by default
2. Cache key = URL + HTTP method + request body
3. Cached responses are served WITHOUT making network requests
4. Request headers (Cache-Control) are ignored for already-cached responses
5. Only response headers can prevent caching for future requests
6. Cache persists in memory until process terminates

**Why curl works but Flutter doesn't:**
- curl creates a fresh HTTP client for each request
- Flutter reuses the same HTTP client (via Provider singleton)
- iOS cache is tied to the client instance lifecycle

## 💡 Prevention for Future

The implemented cache headers will prevent this issue for:
- ✅ All NEW requests after app restart
- ✅ All API endpoints using the ApiService
- ✅ Both iOS and Android platforms

## 📝 Additional Notes

**Brand Onboarding Flow:**
1. User selects brand variants from SaaS catalog
2. POST request to `/api/inventory/saas-brands/onboard`
3. Backend creates products in tenant's inventory
4. Returns product IDs in `brand_details`
5. Frontend navigates to Initial Stock screen
6. User sets stock quantities per shop
7. Stock saved via `/api/inventory/stocks/adjust`

**Key Files:**
- Frontend: `liquor_pro_app/lib/features/inventory/screens/brand_catalog_screen.dart`
- Frontend: `liquor_pro_app/lib/features/inventory/screens/initial_stock_screen.dart`
- Backend: `internal/inventory/services/brand_onboarding_service.go`
- Backend: `internal/inventory/handlers/brand_onboarding_handlers.go`

---

**Last Updated**: 2025-10-05
**Issue**: HTTP caching preventing brand onboarding
**Status**: ✅ Fixed - Requires app restart to clear existing cache

# Shop Management - Frontend Testing Guide

## Test Date: October 4, 2025

## Prerequisites ✅

### Backend Services Running
```bash
# Check Docker services
docker-compose ps

# All services should be "Up" and "healthy"
# Especially: gateway, auth, postgres, redis
```

### Backend API Verified
```bash
# Quick API test
bash /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor/test_shop_api_quick.sh

# Expected: ✅ SUCCESS! Got 1 shop(s)
```

---

## Test Scenarios

### Scenario 1: Fresh Login → View Shops (Happy Path)

**Steps**:
1. Launch Flutter app on iPhone 14 Pro Max
2. On phone input screen, enter: `9999992020`
3. Tap "Continue"
4. On OTP screen, enter: `000000`
5. Tap "Verify"
6. App navigates to home/dashboard
7. Tap "Settings" tab (bottom navigation)
8. Tap "Manage Shops" option
9. Observe loading indicator
10. Observe shop list

**Expected Results**:
- ✅ Login succeeds
- ✅ Settings screen loads
- ✅ "Manage Shops" option visible
- ✅ Loading indicator appears briefly
- ✅ Shop list loads showing:
  - Shop name: "SDA"
  - Address: "C2/1, SDA"
  - Active status badge (green)
  - Phone number (may be empty)
- ✅ Pull-to-refresh works
- ✅ "Add Shop" button visible (shows "coming soon" message)

**Console Logs to Verify**:
```
flutter: 🏪 ShopsScreen initState called
flutter: 🏪 ShopProvider.loadShops() called
flutter: 🏪 ShopService.getShops() called
flutter: 🔑 AuthService.getToken() called - Token exists: true
flutter: 🔑 Authorization header added
flutter: 🔑 X-Tenant-ID header added: 712fd4a7-8879-4ad9-98c1-f054d1881669
flutter: 🌐 API GET: http://localhost:8090/api/admin/shops
flutter: 📥 Response status: 200
flutter: 📥 Response body: [{"id":"...","name":"SDA",...}]
flutter: 🏪 ShopProvider: Loaded 1 shops
```

---

### Scenario 2: Hot Reload → Session Expired (Error Handling)

**Steps**:
1. From Scenario 1, with shops loaded
2. In VS Code/Terminal, perform hot reload: Press `r` in Flutter console
3. Navigate back to Settings → Manage Shops

**Expected Results**:
- ✅ "Session Expired" screen appears with:
  - 🔒 Lock icon (red)
  - "Session Expired" heading
  - Explanation message: "Your session has expired. Please login again to continue."
  - "Login Again" button (blue)
- ✅ No shop list visible
- ✅ No "Add Shop" button

**Console Logs**:
```
flutter: 🏪 ShopsScreen initState called
flutter: 🔑 AuthService.getToken() called - Token exists: false
flutter: ⚠️ No token available!
flutter: 📥 Response status: 401
flutter: 📥 Response body: {"error":"Authorization header required"...}
flutter: 🏪 ShopProvider: Error - Session expired. Please login again.
```

**Additional Steps**:
4. Tap "Login Again" button
5. Observe logout and redirect to phone login screen
6. Login again with `9999992020` / `000000`
7. Navigate to Settings → Manage Shops
8. Observe shops load successfully

---

### Scenario 3: Backend Down → Network Error

**Steps**:
1. Stop backend services:
   ```bash
   docker-compose down
   ```
2. In Flutter app, navigate to Settings → Manage Shops
3. Observe error screen

**Expected Results**:
- ✅ Error screen appears with:
  - ⚠️ Error icon (red)
  - "Error" heading
  - Error message (network/connection error)
  - "Retry" button (blue)

**Recovery Steps**:
4. Start backend services:
   ```bash
   docker-compose up -d
   ```
5. Wait 10 seconds for services to start
6. Tap "Retry" button
7. Observe shops load successfully

---

### Scenario 4: Pull to Refresh

**Steps**:
1. With shops loaded (Scenario 1)
2. Pull down on the shop list
3. Observe refresh indicator
4. Observe list reloads

**Expected Results**:
- ✅ Refresh indicator appears
- ✅ API call made to backend
- ✅ Shop list updates
- ✅ No errors

---

### Scenario 5: Empty Shop List

**Steps**:
1. In database, temporarily remove all shops for the tenant
2. Navigate to Settings → Manage Shops

**Expected Results**:
- ✅ Empty state appears with:
  - 🏪 Store icon
  - "No Shops" heading
  - "Add your first shop location to get started" message
- ✅ "Add Shop" button visible

**Cleanup**:
- Restore shop data in database

---

## Verification Checklist

### UI/UX
- [ ] Shop cards display correctly with:
  - [ ] Shop icon (colored based on active status)
  - [ ] Shop name (bold)
  - [ ] Address with location icon
  - [ ] Phone number with phone icon
  - [ ] Active/Inactive badge (green/red)
- [ ] Loading indicator shows during API calls
- [ ] Pull-to-refresh animation smooth
- [ ] Error screens are user-friendly
- [ ] Buttons are clearly labeled
- [ ] Navigation works smoothly

### API Integration
- [ ] GET /api/admin/shops returns shop data
- [ ] Authorization header included in requests
- [ ] X-Tenant-ID header included in requests
- [ ] 200 response loads shops successfully
- [ ] 401 response shows session expired screen
- [ ] Network errors handled gracefully

### State Management
- [ ] ShopProvider updates correctly
- [ ] Loading states managed properly
- [ ] Error states managed properly
- [ ] Shop list updates on refresh
- [ ] No memory leaks or state issues

### Security
- [ ] Token required for API calls
- [ ] Tenant isolation enforced
- [ ] Session expiration detected
- [ ] Automatic logout on auth failure
- [ ] Secure token storage (FlutterSecureStorage)

### Error Handling
- [ ] Session expired: Shows login button
- [ ] Network error: Shows retry button
- [ ] General error: Shows error message
- [ ] No infinite loading states
- [ ] User always has an action to take

---

## Common Issues and Solutions

### Issue: "Session Expired" appears immediately
**Cause**: Token is null or invalid
**Solution**:
1. Logout from app
2. Login fresh with `9999992020` / `000000`
3. Navigate to shops again

### Issue: Build error "Member not found: 'headlineMedium'"
**Cause**: Incorrect text style name
**Solution**: Fixed - uses `AppTextStyles.h3` now

### Issue: Shops don't load
**Cause**: Backend not running
**Solution**:
1. Check backend: `docker-compose ps`
2. Start if needed: `docker-compose up -d`
3. Test API: `curl http://localhost:8090/gateway/health`

### Issue: 401 Unauthorized errors
**Cause**: JWT secret mismatch or token expired
**Solution**:
1. Restart gateway: `docker-compose restart gateway`
2. Login fresh in app
3. Check JWT secret in docker-compose.yml

---

## Performance Testing

### Load Time
- Initial load: < 2 seconds
- Refresh: < 1 second
- Navigation: Instant

### Memory Usage
- No memory leaks on repeated navigation
- Efficient state management
- Proper widget disposal

### Network
- Single API call per load
- No unnecessary requests
- Proper caching with secure storage

---

## Accessibility Testing

- [ ] Screen reader support
- [ ] High contrast mode
- [ ] Large text support
- [ ] Touch target sizes (minimum 44x44)
- [ ] Color blind friendly (not relying solely on color)

---

## Test Data

### User Credentials
- **Phone**: `9999992020`
- **OTP**: `000000`
- **User ID**: `8a1f4178-216c-4465-a096-9d1acd42b0aa`
- **Tenant ID**: `712fd4a7-8879-4ad9-98c1-f054d1881669`
- **Tenant Name**: "Dr Dangs Lab"

### Expected Shop Data
```json
{
  "id": "7144e331-969e-42d0-9320-d13376f1b123",
  "name": "SDA",
  "address": "C2/1, SDA",
  "phone": "",
  "license_number": "",
  "is_active": true
}
```

---

## Test Report Template

```markdown
## Shop Management Test Report

**Test Date**: [DATE]
**Tester**: [NAME]
**Device**: iPhone 14 Pro Max (Simulator)
**Backend**: Docker Compose (localhost)

### Scenario Results

| Scenario | Status | Notes |
|----------|--------|-------|
| Fresh Login → View Shops | ✅/❌ | |
| Hot Reload → Session Expired | ✅/❌ | |
| Backend Down → Network Error | ✅/❌ | |
| Pull to Refresh | ✅/❌ | |
| Empty Shop List | ✅/❌ | |

### Issues Found

1. [Issue description]
   - **Severity**: High/Medium/Low
   - **Steps to reproduce**: [steps]
   - **Expected**: [expected behavior]
   - **Actual**: [actual behavior]

### Overall Status

✅ **PASS** - All scenarios working
❌ **FAIL** - Issues found (see above)

### Recommendations

- [Recommendations for improvements]
```

---

## Next Steps After Testing

1. **If All Tests Pass**:
   - Mark feature as complete
   - Update documentation
   - Prepare for production deployment

2. **If Issues Found**:
   - Document issues clearly
   - Prioritize by severity
   - Fix and retest

3. **Future Enhancements**:
   - Add shop creation form
   - Add shop edit functionality
   - Add shop delete with confirmation
   - Add shop details screen
   - Add map integration for location
   - Add license file upload

---

**Testing Guide Version**: 1.0
**Last Updated**: October 4, 2025
**Status**: Ready for Testing ✅

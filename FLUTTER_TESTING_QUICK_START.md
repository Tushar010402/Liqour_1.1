# Flutter App Testing - Quick Start Guide

**Date:** October 5, 2025, 1:45 AM IST
**Status:** Ready for Testing

---

## Prerequisites ✅

- [x] Backend services running (verified)
- [x] Database populated with 8 brands (verified)
- [x] Internal API working (verified)
- [x] Flutter environment ready (verified)

---

## Quick Test Steps

### Option 1: App Already Running

If the Flutter app is already running (you see it in simulator):

1. **Hot Restart**
   ```
   Press: R (capital R)
   ```

2. **Navigate**
   - Bottom Navigation → Inventory
   - Top Right → + Icon (Brand Onboarding)

3. **Verify**
   - ✅ See 8 real brands
   - ✅ Each brand shows variant count
   - ✅ No test brands ("AAAAAAAAAAAAPPPP")

### Option 2: Start Fresh

If the app is not running:

1. **Navigate to Project**
   ```bash
   cd /Users/macbookpro/Desktop/Liquor_1.1/Go-Backend-Liquor/liquor_pro_app
   ```

2. **Run App**
   ```bash
   flutter run
   ```

3. **Login**
   - Phone: `9999992020`
   - OTP: `000000`

4. **Navigate**
   - Dashboard → Inventory → + Icon

---

## Expected Results

### 1. Brand List Screen

You should see **8 real brands**:

```
✅ Johnnie Walker (4 variants)
   "World-famous Scotch whisky brand"

✅ Royal Stag (3 variants)
   "Popular Indian whisky by Pernod Ricard"

✅ Officer's Choice (3 variants)
   "India's largest selling whisky brand"

✅ Kingfisher Beer (4 variants)
   "India's most popular beer brand"

✅ Old Monk (3 variants)
   "Legendary Indian dark rum"

✅ Smirnoff (3 variants)
   "World's best-selling vodka brand"

✅ Signature (2 variants)
   "Premium Indian whisky"

✅ Bacardi Breezer (4 variants)
   "Fruit-flavored alcoholic beverage"
```

### 2. Flutter Console Logs

Expected logs:
```
flutter: 🎯 BrandOnboardingService.getAvailableBrands() called
flutter: 🌐 Making API request: GET /api/inventory/saas-brands/available
flutter: 🔑 Authorization header added
flutter: 🔑 X-Tenant-ID header added: {tenant-id}
flutter: 🎯 Parsing available brands response: _InternalLinkedHashMap<String, dynamic>
flutter: 🎯 Parsing from "data" key (8 brands)
flutter: 🎯 BrandOnboardingService: Response - success: true
flutter: ✅ Loaded 8 brands successfully
```

### 3. UI Features

Test these features:

**Search:**
- Type "Johnnie" → See Johnnie Walker
- Type "Beer" → See Kingfisher

**Category Filter:**
- Select "Whiskey" → See 4 whiskey brands
- Select "Beer" → See 1 beer brand
- Select "All" → See all 8 brands

**Selection:**
- Tap brand card → Select all variants
- Tap individual variant → Select single variant
- Tap again → Deselect

**Onboarding:**
1. Select "Kingfisher Beer"
2. Choose 2-3 variants
3. Tap "Onboard Selected Brands"
4. See success message
5. Navigate to Inventory tab
6. Verify new products appear

---

## Troubleshooting

### Issue: No brands showing

**Check 1: Backend Running**
```bash
docker-compose ps
# All services should show "Up"
```

**Check 2: API Accessible**
```bash
curl http://localhost:8095/api/internal/brands?include_variants=true&active_only=true
# Should return JSON with 8 brands
```

**Check 3: Flutter Logs**
```
Look for error messages in console
Check for "Authorization header added"
Check for "X-Tenant-ID header added"
```

### Issue: Shows test brands instead of real brands

**Solution: Restart App**
```bash
# In Flutter terminal, press:
q  # Quit
# Then:
flutter run  # Start again
```

### Issue: "Authorization header required" error

**Solution: Re-login**
1. Logout from app
2. Close and restart app
3. Login again (9999992020 / 000000)

### Issue: Brands load but can't onboard

**Check: Shop Selection**
- Verify you have a shop created
- If multi-shop tenant, select shop before onboarding

---

## Test Checklist

### Visual Tests
- [ ] 8 brands displayed with names
- [ ] Brand descriptions shown
- [ ] Variant counts displayed
- [ ] Brand cards look professional
- [ ] No layout issues

### Functional Tests
- [ ] Search works
- [ ] Category filter works
- [ ] Brand selection works
- [ ] Variant selection works
- [ ] Selection counter updates
- [ ] Clear selection works

### Integration Tests
- [ ] Onboarding succeeds
- [ ] Success message shown
- [ ] Products appear in inventory
- [ ] Duplicate prevention works
- [ ] Error handling works

---

## Success Criteria

### ✅ All Checks Must Pass

1. **Brand Display**
   - 8 real brands visible
   - Correct variant counts
   - Professional UI

2. **Functionality**
   - Search/filter working
   - Selection working
   - Onboarding working

3. **Data Integrity**
   - Products created correctly
   - No duplicates
   - Proper pricing

4. **Performance**
   - Fast loading (<2s)
   - Smooth scrolling
   - No crashes

---

## Next Steps After Testing

### If All Tests Pass ✅
1. Document any UI feedback
2. Test on physical device
3. Test with different tenants
4. Test edge cases

### If Tests Fail ❌
1. Note exact error message
2. Check Flutter console logs
3. Check backend logs: `docker-compose logs saas inventory`
4. Share error details for debugging

---

## Quick Reference Commands

```bash
# Backend Status
docker-compose ps

# Backend Logs
docker-compose logs -f saas inventory

# Test Internal API
curl "http://localhost:8095/api/internal/brands?include_variants=true&active_only=true"

# Flutter Hot Restart
Press: R (in terminal where flutter run is active)

# Flutter Hot Reload
Press: r (lowercase)

# Flutter Quit
Press: q
```

---

## Support

For issues:
1. Check logs (Flutter console + Docker logs)
2. Verify backend health
3. Review documentation:
   - `BRAND_ONBOARDING_COMPLETE_GUIDE.md`
   - `PRODUCTION_READINESS_REPORT.md`

---

**Ready to Test!** 🚀

Follow the steps above and verify that the brand onboarding system works as expected. All backend components are verified and ready.

---

**Created:** October 5, 2025, 1:45 AM IST
**Status:** ✅ Ready for User Testing

# Quick Start - New Brand UI Integration

## 🚀 5-Minute Integration Guide

### Step 1: Update Your Route (Choose One Option)

**Option A: Replace Old Screen** (Recommended)

Find your route file (usually `lib/routes/app_routes.dart` or similar):

```dart
// BEFORE:
import 'package:liquor_pro_app/features/inventory/screens/brand_onboarding_screen.dart';

routes: {
  '/brand-onboarding': (context) => const BrandOnboardingScreen(),
}

// AFTER:
import 'package:liquor_pro_app/features/inventory/screens/brand_onboarding_screen_new.dart';

routes: {
  '/brand-onboarding': (context) => const BrandOnboardingScreenNew(),
}
```

**Option B: Test Alongside Old Screen**

```dart
import 'package:liquor_pro_app/features/inventory/screens/brand_onboarding_screen_new.dart';

routes: {
  '/brand-onboarding': (context) => const BrandOnboardingScreen(), // Old
  '/brand-catalog': (context) => const BrandOnboardingScreenNew(), // New
}
```

### Step 2: Navigate to the Screen

```dart
// From any screen:
Navigator.pushNamed(context, '/brand-onboarding');

// Or with Navigator 2.0:
context.go('/brand-onboarding');

// Or directly:
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const BrandOnboardingScreenNew(),
  ),
);
```

### Step 3: That's It! 🎉

The screen will automatically:
- Load brands from your backend
- Display them in beautiful cards
- Handle category filtering
- Manage variant selection
- Complete the onboarding process

---

## 📱 What You'll See

### Main Screen Features:
1. **Stats Dashboard** - Live metrics at the top
2. **Search Bar** - Find brands quickly
3. **Category Filters** - Color-coded chip navigation
4. **Brand Grid** - Beautiful card layout
5. **Selection Summary** - Shows selected products
6. **Add Button** - Bottom action bar

### When User Taps a Brand:
- Beautiful bottom sheet slides up
- Shows all brand variants
- Each variant displays:
  - Size (e.g., "750ml")
  - MRP and Selling Price
  - Alcohol content
  - Checkbox for selection

### After Onboarding:
- Success dialog with statistics
- "View Inventory" button
- Automatic navigation back

---

## 🎨 Customization (Optional)

### Change Category Colors

Edit `brand_onboarding_screen_new.dart`:

```dart
Color _getCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'whiskey':
      return const Color(0xFFD97706); // ← Change this
    case 'vodka':
      return const Color(0xFF3B82F6); // ← Or this
    // Add your custom categories here
    default:
      return AppColors.primary;
  }
}
```

### Adjust Grid Layout

```dart
gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: isTablet ? 3 : 2, // ← Mobile: 2, Tablet: 3
  crossAxisSpacing: 16,              // ← Space between columns
  mainAxisSpacing: 16,               // ← Space between rows
  childAspectRatio: 0.75,            // ← Card height ratio
),
```

---

## ✅ Verification Checklist

After integration, verify:

- [ ] Screen loads without errors
- [ ] Brands display in grid
- [ ] Search works
- [ ] Category filters work
- [ ] Tapping brand shows bottom sheet
- [ ] Variant selection works
- [ ] Bottom bar appears when items selected
- [ ] Onboarding completes successfully
- [ ] Success dialog shows
- [ ] Navigation works

---

## 🐛 Troubleshooting

### Brands Not Showing?

**Check 1:** Backend is running
```bash
curl http://localhost:8090/api/inventory/saas-brands/available
```

**Check 2:** Provider is initialized
```dart
// In your main.dart or app setup:
ChangeNotifierProvider(
  create: (_) => BrandOnboardingProvider(),
),
```

**Check 3:** Authentication is set up
- JWT token is valid
- X-Tenant-ID header is present

### Empty State Showing?

This means:
- No brands match current filters
- API returned empty array
- All brands are inactive (`is_active: false`)

**Fix:** Check your database has active brands:
```sql
SELECT * FROM saas_brands WHERE is_active = true;
```

### Categories Not Showing?

**Fix:** Brands need `category_name` field in API response.

In backend, ensure brand model includes:
```go
CategoryName *string `json:"category_name,omitempty"`
```

---

## 📞 Need Help?

### Common Questions

**Q: Can I use this with existing brand data?**
A: Yes! It works with your current backend APIs.

**Q: Does it support multiple shops?**
A: Yes! Automatically shows shop selector if tenant has multiple shops.

**Q: Can I customize the colors?**
A: Absolutely! See customization section above.

**Q: Is it responsive?**
A: Yes! Adapts to mobile and tablet screens.

**Q: Does it work offline?**
A: The screen requires network to load brands. Consider adding offline support if needed.

---

## 🎯 Next Steps

1. ✅ Integrate the screen (Steps 1-2 above)
2. 🧪 Test with your brand data
3. 🎨 Customize colors if needed
4. 📱 Test on device
5. 🚀 Deploy to production

---

**Ready to go!** The new brand UI is production-ready and will significantly improve your user experience.

**Questions?** Check the full guide in `BRAND_UI_UX_UPGRADE_GUIDE.md`

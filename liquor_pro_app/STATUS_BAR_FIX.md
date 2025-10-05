# Status Bar (Notch Area) Fix

## Issue
The area above the inventory navbar (status bar/notch area) was not styled with the primary blue color, creating a visual disconnect.

## Solution Applied

### 1. Added SystemUiOverlayStyle
Wrapped the entire Scaffold with `AnnotatedRegion<SystemUiOverlayStyle>` to control the status bar appearance:

```dart
AnnotatedRegion<SystemUiOverlayStyle>(
  value: const SystemUiOverlayStyle(
    statusBarColor: AppColors.primary,        // Blue background
    statusBarIconBrightness: Brightness.light, // White icons
    statusBarBrightness: Brightness.dark,      // For iOS
  ),
  child: Scaffold(...)
)
```

### 2. Enhanced SliverAppBar Styling
- Added `foregroundColor: Colors.white` for consistent white text/icons
- Explicitly set icon colors to white
- Added `elevation: 0` for seamless blend with status bar

## Files Modified
- `lib/features/inventory/screens/inventory_screen.dart`

## Result
✅ Status bar area now displays in primary blue color
✅ Status bar icons are white for proper contrast
✅ Seamless visual flow from notch to navbar
✅ Professional, cohesive appearance

## Visual Hierarchy
```
┌─────────────────────────────┐
│   Status Bar (Blue)         │  ← Now blue with white icons
├─────────────────────────────┤
│   Inventory (Title)         │  ← Blue navbar
│   [Icons]                   │
├─────────────────────────────┤
│  All | Low | Out | Cat      │  ← Blue tabs
├─────────────────────────────┤
│                             │
│   Content Area              │  ← Light gray background
│                             │
└─────────────────────────────┘
```

## Platform Support
- ✅ iOS - Status bar properly styled
- ✅ Android - Status bar properly styled
- ✅ Notched devices - Seamless appearance
- ✅ Non-notched devices - Works correctly

## Testing
- [x] iPhone 14 Pro Max (notched) - Status bar blue
- [x] Status icons visible (white color)
- [x] No visual gaps or disconnects
- [x] Smooth visual transition

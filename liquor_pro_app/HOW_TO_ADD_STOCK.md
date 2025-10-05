# How to Add Stock to Products - Complete Guide

## Overview

The LiquorPro system has a robust stock management system. Here are multiple ways to add stock to your products.

---

## Method 1: Via API (Quick Test)

### Step 1: Get Product and Shop IDs

First, get your product ID from the products list:

```bash
curl 'http://localhost:8090/api/inventory/products?page=1&limit=10' \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-Tenant-ID: 712fd4a7-8879-4ad9-98c1-f054d1881669"
```

Sample product:
- **Product ID**: `ba862dc6-fc9a-434f-9184-baa8bfbb3fad` (Chivas Regal 12 Years)
- **Product Name**: Chivas Regal 12 Years
- **Current Stock**: 0

### Step 2: Adjust Stock via API

Use the `/api/inventory/stocks/adjust` endpoint:

```bash
curl -X POST 'http://localhost:8090/api/inventory/stocks/adjust' \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-Tenant-ID: 712fd4a7-8879-4ad9-98c1-f054d1881669" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": "ba862dc6-fc9a-434f-9184-baa8bfbb3fad",
    "quantity": 100,
    "adjustment_type": "purchase",
    "reference": "Initial stock",
    "notes": "Adding initial inventory"
  }'
```

**Adjustment Types**:
- `purchase` - Receiving new stock
- `sale` - Stock sold (reduces inventory)
- `damage` - Damaged/spoiled items
- `return` - Customer returns
- `adjustment` - Manual correction

### Step 3: Verify Stock

```bash
curl 'http://localhost:8090/api/inventory/stocks?product_id=ba862dc6-fc9a-434f-9184-baa8bfbb3fad' \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-Tenant-ID: 712fd4a7-8879-4ad9-98c1-f054d1881669"
```

---

## Method 2: Via Flutter App (Recommended)

### Current Status

The Flutter app currently has:
- ✅ Product listing
- ✅ Product details
- ✅ Product add/edit
- ❌ Stock adjustment screen (needs to be implemented)

### Implementation Plan

I'll create a stock management screen for you. Here's what it will include:

1. **Stock Adjustment Screen**:
   - View current stock
   - Add/remove stock
   - Select adjustment type
   - Add notes/reference
   - Transaction history

2. **Quick Stock Button** on product list:
   - Tap product → Show stock dialog
   - Enter quantity
   - Submit

---

## Let Me Implement the Stock Management UI

I'll create the following files for you:

### 1. Stock Model
```dart
// lib/features/inventory/models/stock.dart
class Stock {
  final String id;
  final String productId;
  final String productName;
  final int quantity;
  final String adjustmentType;
  final String reference;
  final String notes;
  final DateTime createdAt;
}
```

### 2. Stock Service
```dart
// lib/features/inventory/services/stock_service.dart
class StockService {
  Future<ApiResponse<Stock>> adjustStock({
    required String productId,
    required int quantity,
    required String adjustmentType,
    String? reference,
    String? notes,
  });

  Future<ApiResponse<List<Stock>>> getStockHistory(String productId);
}
```

### 3. Stock Adjustment Screen
```dart
// lib/features/inventory/screens/stock_adjustment_screen.dart
- Select product
- Enter quantity
- Choose adjustment type
- Add notes
- Submit
```

### 4. Quick Stock Dialog
```dart
// On product card, add stock button
- Tap → Dialog appears
- Enter quantity → Submit
- Stock updated
```

---

## Implementation Steps

Would you like me to:

1. ✅ **Create stock management models** (Stock, StockAdjustment)
2. ✅ **Create stock service** (API integration)
3. ✅ **Create stock provider** (state management)
4. ✅ **Create stock adjustment screen** (full UI)
5. ✅ **Add quick stock button** to product list
6. ✅ **Add stock display** on product cards
7. ✅ **Test everything** end-to-end

---

## Quick Implementation (Choose One):

### Option A: Full Stock Management Module
**Time**: ~15-20 minutes
**Includes**:
- Complete stock adjustment screen
- Stock history view
- Quick stock dialog on product list
- Stock reports
- Transaction tracking

### Option B: Simple Stock Dialog
**Time**: ~5-10 minutes
**Includes**:
- Add stock button on product list
- Simple dialog to enter quantity
- Update stock via API
- Refresh product list

### Option C: API Only (Manual Testing)
**Time**: ~2 minutes
**Use**: cURL commands to add stock manually
**Good for**: Quick testing before UI implementation

---

## Recommended Approach

I recommend **Option B** first (Simple Stock Dialog), then expand to **Option A** later. This gets you functional quickly.

### Let's Start: Simple Stock Dialog

Here's what I'll create:

1. **Update Product Model** - Add `currentStock` field
2. **Create Stock Service** - API integration
3. **Add Stock Dialog** - Simple UI
4. **Add Button** to product list
5. **Test** with your products

---

## Sample Usage

Once implemented, here's how you'll use it:

### In the App:

1. **Open Inventory** → See your products
2. **Tap "Add Stock"** button on any product
3. **Enter quantity** (e.g., 100 bottles)
4. **Select type** (Purchase/Adjustment/etc.)
5. **Add note** (optional): "Initial inventory"
6. **Submit** → Stock updated!

### Visual Flow:

```
┌─────────────────────────────────┐
│  Chivas Regal 12 Years         │
│  Stock: 0 bottles              │
│  [Add Stock] button            │ ← Tap this
└─────────────────────────────────┘
                ↓
┌─────────────────────────────────┐
│  Add Stock                     │
│  ─────────────────────────     │
│  Quantity: [____100____]       │
│  Type: [Purchase ▼]            │
│  Reference: [Initial stock]    │
│  Notes: [_____________]        │
│  [Cancel]  [Submit]            │
└─────────────────────────────────┘
                ↓
┌─────────────────────────────────┐
│  Chivas Regal 12 Years         │
│  Stock: 100 bottles  ✅        │
│  [Add Stock] button            │
└─────────────────────────────────┘
```

---

## Ready to Implement?

**Just say which option you want, and I'll implement it right now!**

Example responses:
- "Implement Option B - Simple Stock Dialog"
- "Go with Option A - Full Stock Management"
- "Show me Option C first (API commands)"

Or if you have specific requirements:
- "I want to add stock with purchase orders"
- "I need barcode scanning for stock"
- "I want batch/expiry date tracking"

I'm ready to code! 🚀

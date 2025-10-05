# Next Steps: API Integration Action Plan

**Date**: October 4, 2025, 03:30 AM IST
**Current Status**: 6/15 modules fully connected (40%)

---

## 🎯 **Critical Finding**

✅ **Backend APIs are READY!** The backend has comprehensive, production-ready APIs for:
- Sales Module (12+ endpoints)
- Finance Module (20+ endpoints)
- Inventory CRUD (all endpoints exist)
- User Management (endpoints exist)

❌ **Problem**: Flutter app is missing **service layer** implementations to connect to these APIs.

---

## 📋 **Immediate Priority: Create Missing Services**

### Phase 1: Sales Module (HIGHEST PRIORITY) 🔥

**Backend APIs Available** (Gateway proxies to Sales service):
- `GET /api/sales/sales` - List all sales
- `POST /api/sales/sales` - Create sale
- `GET /api/sales/sales/:id` - Get sale details
- `POST /api/sales/sales/:id/approve` - Approve sale
- `POST /api/sales/sales/:id/reject` - Reject sale
- `GET /api/sales/returns` - List returns
- `POST /api/sales/returns` - Create return
- `POST /api/sales/returns/:id/approve` - Approve return
- `GET /api/sales/daily-records` - Daily sales records
- `POST /api/sales/daily-records` - Create daily record
- `GET /api/sales/dashboard/summary` ✅ (Already connected)

**Action Required**:
1. Create `lib/features/sales/services/sales_service.dart`
2. Implement all sales API methods
3. Create `lib/features/sales/providers/sales_provider.dart`
4. Connect to screens:
   - `sales_history_screen.dart` → `GET /api/sales/sales`
   - `daily_sales_screen.dart` → `GET /api/sales/daily-records`
   - `returns_screen.dart` → `GET /api/sales/returns`
   - `new_sale_screen.dart` → `POST /api/sales/sales`
   - `sales_invoice_screen.dart` → `GET /api/sales/sales/:id`

**Estimated Time**: 4-6 hours

---

### Phase 2: Finance Module (HIGH PRIORITY) 🔥

**Backend APIs Available** (Gateway proxies to Finance service):
- `GET /api/finance/vendors` - List vendors
- `POST /api/finance/vendors` - Create vendor
- `PUT /api/finance/vendors/:id` - Update vendor
- `GET /api/finance/expenses` - List expenses
- `POST /api/finance/expenses` - Create expense
- `PUT /api/finance/expenses/:id` - Update expense
- `GET /api/finance/assistant-manager/money-collections` - Money collections
- `POST /api/finance/assistant-manager/money-collections` - Create collection
- `POST /api/finance/assistant-manager/money-collections/:id/approve` - Approve
- `GET /api/finance/dashboard/summary` - Finance summary
- `GET /api/finance/reports/profit-loss` - P&L report
- `GET /api/finance/reports/balance-sheet` - Balance sheet
- `GET /api/finance/reports/cash-flow` - Cash flow

**Action Required**:
1. Create `lib/features/finance/services/finance_service.dart`
2. Implement all finance API methods
3. Create `lib/features/finance/providers/finance_provider.dart`
4. Connect to screens:
   - `finance_screen.dart` → `GET /api/finance/dashboard/summary`
   - `expenses_screen.dart` → `GET /api/finance/expenses`
   - `vendors_screen.dart` → `GET /api/finance/vendors`
   - `assistant_managers_screen.dart` → `GET /api/finance/assistant-manager/money-collections`

**Estimated Time**: 4-6 hours

---

### Phase 3: Inventory CRUD Operations (MEDIUM PRIORITY)

**Backend APIs Available** (Gateway proxies to Inventory service):
- `GET /api/inventory/categories` ✅ (Already implemented)
- `POST /api/inventory/categories` - Create category
- `PUT /api/inventory/categories/:id` - Update category
- `DELETE /api/inventory/categories/:id` - Delete category
- `GET /api/inventory/brands` ✅ (Already implemented)
- `POST /api/inventory/brands` - Create brand
- `PUT /api/inventory/brands/:id` - Update brand
- `GET /api/inventory/products` ✅ (Already implemented)
- `POST /api/inventory/products` - Create product
- `PUT /api/inventory/products/:id` - Update product
- `DELETE /api/inventory/products/:id` - Delete product
- `POST /api/inventory/stock/adjust` - Adjust stock
- `GET /api/inventory/purchase-orders` - List POs
- `POST /api/inventory/purchase-orders` - Create PO

**Action Required**:
1. Extend `lib/features/inventory/services/product_service.dart`
2. Add CRUD methods for categories, brands, products
3. Connect to screens:
   - `categories_screen.dart` → POST/PUT category
   - `brands_screen.dart` → POST/PUT brand
   - `product_edit_screen.dart` → POST/PUT product
   - `stock_adjustment_screen.dart` → POST stock adjust
   - `purchase_orders_screen.dart` → GET/POST POs

**Estimated Time**: 3-4 hours

---

### Phase 4: User Management & Admin (MEDIUM PRIORITY)

**Backend APIs Available** (Gateway proxies to Auth service):
- `GET /api/admin/users` - List users
- `POST /api/admin/users` - Create user
- `PUT /api/admin/users/:id` - Update user
- `DELETE /api/admin/users/:id` - Delete user

**Action Required**:
1. Create `lib/features/admin/services/user_service.dart`
2. Implement user management methods
3. Connect to `user_management_screen.dart`

**Estimated Time**: 2-3 hours

---

### Phase 5: Profile, Settings & Miscellaneous (LOW PRIORITY)

**APIs Needed** (may need to be created in backend):
1. **Profile Update**: `PUT /api/users/profile`
2. **Password Change**: `POST /api/auth/change-password`
3. **Backup Settings**: `GET /api/settings/backup`
4. **Notifications**: `GET /api/notifications`
5. **Customer Management**: May need new endpoints

**Action Required**:
1. Verify if these endpoints exist in backend
2. If not, create backend handlers
3. Create Flutter services
4. Connect to screens

**Estimated Time**: 4-6 hours (includes backend work if needed)

---

## 🛠️ **Implementation Template**

### Step 1: Create Service Class

```dart
// lib/features/sales/services/sales_service.dart
import '../../core/services/api_service.dart';
import '../models/sale.dart';

class SalesService {
  final ApiService _apiService;

  SalesService(this._apiService);

  Future<ApiResponse<List<Sale>>> getSales({
    String? shopId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int page = 1,
    int limit = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'limit': limit,
      if (shopId != null) 'shop_id': shopId,
      if (status != null) 'status': status,
      if (startDate != null) 'start_date': startDate.toIso8601String(),
      if (endDate != null) 'end_date': endDate.toIso8601String(),
    };

    return await _apiService.get<List<Sale>>(
      '/api/sales/sales',
      queryParameters: params,
      parser: (data) {
        if (data is List) {
          return data.map((item) => Sale.fromJson(item)).toList();
        }
        return [];
      },
    );
  }

  Future<ApiResponse<Sale>> createSale(Map<String, dynamic> saleData) async {
    return await _apiService.post<Sale>(
      '/api/sales/sales',
      data: saleData,
      parser: (data) => Sale.fromJson(data),
    );
  }

  // Add more methods...
}
```

### Step 2: Create Provider

```dart
// lib/features/sales/providers/sales_provider.dart
import 'package:flutter/material.dart';
import '../services/sales_service.dart';
import '../models/sale.dart';

class SalesProvider with ChangeNotifier {
  final SalesService _salesService;

  List<Sale> _sales = [];
  bool _isLoading = false;
  String? _error;

  List<Sale> get sales => _sales;
  bool get isLoading => _isLoading;
  String? get error => _error;

  SalesProvider(this._salesService);

  Future<void> loadSales() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final response = await _salesService.getSales();

    if (response.success && response.data != null) {
      _sales = response.data!;
    } else {
      _error = response.message ?? 'Failed to load sales';
    }

    _isLoading = false;
    notifyListeners();
  }
}
```

### Step 3: Register in main.dart

```dart
// Add to providers list in main.dart
MultiProvider(
  providers: [
    // Existing providers...
    ChangeNotifierProvider(
      create: (context) => SalesProvider(
        SalesService(context.read<ApiService>()),
      ),
    ),
  ],
  child: MyApp(),
)
```

### Step 4: Update Screen

```dart
// lib/features/sales/screens/sales_history_screen.dart
import 'package:provider/provider.dart';
import '../providers/sales_provider.dart';

class SalesHistoryScreen extends StatefulWidget {
  // ...
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Load sales when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().loadSales();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SalesProvider>(
      builder: (context, salesProvider, child) {
        if (salesProvider.isLoading) {
          return Center(child: CircularProgressIndicator());
        }

        if (salesProvider.error != null) {
          return Center(child: Text('Error: ${salesProvider.error}'));
        }

        final sales = salesProvider.sales;

        if (sales.isEmpty) {
          return EmptyStateWidget(
            message: 'No sales records found',
          );
        }

        return ListView.builder(
          itemCount: sales.length,
          itemBuilder: (context, index) {
            final sale = sales[index];
            return SaleListItem(sale: sale);
          },
        );
      },
    );
  }
}
```

---

## 📊 **Summary of Work Required**

| Phase | Module | Service to Create | Screens to Connect | Time Estimate |
|-------|--------|-------------------|-------------------|---------------|
| 1 | Sales | `SalesService` | 5 screens | 4-6 hours |
| 2 | Finance | `FinanceService` | 4 screens | 4-6 hours |
| 3 | Inventory CRUD | Extend `ProductService` | 5 screens | 3-4 hours |
| 4 | User Management | `UserService` | 1 screen | 2-3 hours |
| 5 | Miscellaneous | Multiple services | 5 screens | 4-6 hours |
| **TOTAL** | - | - | **20 screens** | **17-25 hours** |

---

## ✅ **Already Complete (No Work Needed)**

1. ✅ Authentication APIs - Fully connected
2. ✅ Dashboard APIs - Fully connected
3. ✅ Shop Management APIs - Fully connected
4. ✅ Brand Onboarding APIs - Fully connected (fixed today)
5. ✅ Product Listing APIs - Fully connected
6. ✅ Excise Module APIs - Fully connected

---

## 🚀 **Recommended Execution Order**

### Week 1 (Days 1-3)
1. **Day 1**: Create SalesService + Sales screens (daily sales, sales history)
2. **Day 2**: Complete Sales module (returns, new sale, invoice)
3. **Day 3**: Create FinanceService + Finance screens (expenses, vendors)

### Week 2 (Days 4-5)
4. **Day 4**: Complete Finance module (assistant managers, reports)
5. **Day 5**: Extend ProductService for Inventory CRUD operations

### Week 3 (Days 6-7)
6. **Day 6**: User Management + Profile/Settings
7. **Day 7**: Testing, bug fixes, final polish

---

## 🎯 **Success Criteria**

By end of implementation:
- ✅ 15/15 modules connected (100%)
- ✅ All TODO comments removed
- ✅ No placeholder data in any screen
- ✅ Real-time data loading from APIs
- ✅ Error handling implemented
- ✅ Loading states displayed properly
- ✅ Pull-to-refresh working
- ✅ Pagination working where applicable

---

## 📝 **Notes**

1. **API Patterns Consistent**: All backend APIs follow the same structure
   - Authentication via JWT Bearer token
   - Tenant isolation via X-Tenant-ID header
   - Standard response format
   - RESTful endpoints

2. **No Backend Changes Needed**: Focus purely on Flutter service layer

3. **Use Existing Patterns**: Follow the same patterns used in:
   - `DashboardService` (working example)
   - `ShopService` (working example)
   - `ProductService` (working example)
   - `BrandOnboardingService` (working example)

4. **API Documentation**: All endpoints documented in backend route files:
   - `internal/sales/routes/routes.go`
   - `internal/finance/routes/routes.go`
   - `internal/inventory/routes/routes.go`
   - `internal/auth/routes/routes.go`

---

**Document Created**: October 4, 2025, 03:30 AM IST
**Estimated Completion**: 2-3 weeks (17-25 hours of development)
**Next Action**: Start Phase 1 - Sales Module Service Implementation

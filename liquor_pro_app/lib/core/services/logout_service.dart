import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import '../providers/shop_selection_provider.dart';
import '../providers/tagline_provider.dart' show TagLineProvider;
import '../services/dio_api_service.dart';
import '../services/fcm_service.dart';
import '../../features/admin/providers/shop_provider.dart';
import '../../features/admin/providers/user_management_provider.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/dashboard/providers/dashboard_provider.dart';
import '../../features/excise/providers/excise_provider.dart';
import '../../features/finance/providers/cash_approval_provider.dart';
import '../../features/finance/providers/cash_provider.dart';
import '../../features/finance/providers/vendor_provider.dart';
import '../../features/inventory/providers/brand_onboarding_provider.dart';
import '../../features/inventory/providers/brand_selection_provider.dart';
import '../../features/inventory/providers/product_provider.dart';
import '../../features/inventory/providers/stock_purchase_provider.dart';
import '../../features/reports/providers/purcha_report_provider.dart';
import '../../features/sales/providers/daily_sales_provider.dart';
import '../../features/sales/providers/expense_header_provider.dart';

/// Centralized logout service — resets ALL app state on logout.
///
/// IMPORTANT: When adding a new provider to the app, add its reset call here.
/// Forgetting to do so will cause stale data when switching accounts.
class LogoutService {
  /// Reset all app state, unregister FCM, logout auth, and navigate to login.
  /// Call this instead of manually resetting individual providers.
  static Future<void> resetAllState(BuildContext context) async {
    debugPrint('🔄 [LogoutService] Resetting all app state...');

    // ── 1. Reset all ChangeNotifier providers ──
    _resetChangeNotifierProviders(context);

    // ── 2. Invalidate all Riverpod providers ──
    _invalidateRiverpodProviders(context);

    // ── 3. Clear DioApiService caches ──
    _clearApiCaches(context);

    // ── 4. Unregister FCM device ──
    await _unregisterFcm(context);

    // ── 5. Perform auth logout (clears tokens, SecureStorage, SharedPrefs) ──
    try {
      await context.read<AuthProvider>().logout();
    } catch (e) {
      debugPrint('⚠️ [LogoutService] Auth logout error: $e');
    }

    debugPrint('✅ [LogoutService] All state reset complete');
  }

  /// Reset all ChangeNotifier-based providers.
  /// Each call is wrapped in try-catch — a failed reset shouldn't block logout.
  static void _resetChangeNotifierProviders(BuildContext context) {
    // Shop & navigation
    _tryReset(() => context.read<ShopSelectionProvider>().reset(), 'ShopSelectionProvider');
    _tryReset(() => context.read<ShopProvider>().reset(), 'ShopProvider');

    // Inventory
    _tryReset(() => context.read<ProductProvider>().reset(), 'ProductProvider');
    _tryReset(() => context.read<StockPurchaseProvider>().reset(), 'StockPurchaseProvider');
    _tryReset(() => context.read<BrandOnboardingProvider>().reset(), 'BrandOnboardingProvider');
    _tryReset(() => context.read<BrandSelectionProvider>().reset(), 'BrandSelectionProvider');

    // Sales
    _tryReset(() => context.read<DailySalesProvider>().reset(), 'DailySalesProvider');
    _tryReset(() => context.read<ExpenseHeaderProvider>().reset(), 'ExpenseHeaderProvider');

    // Finance
    _tryReset(() => context.read<VendorProvider>().reset(), 'VendorProvider');
    _tryReset(() => context.read<CashApprovalProvider>().reset(), 'CashApprovalProvider');

    // Dashboard & reports
    _tryReset(() => context.read<DashboardProvider>().reset(), 'DashboardProvider');
    _tryReset(() => context.read<PurchaReportProvider>().reset(), 'PurchaReportProvider');

    // Admin
    _tryReset(() => context.read<UserManagementProvider>().reset(), 'UserManagementProvider');
    _tryReset(() => context.read<ExciseProvider>().reset(), 'ExciseProvider');

    // Core
    _tryReset(() => context.read<TagLineProvider>().reset(), 'TagLineProvider');
  }

  /// Invalidate all Riverpod FutureProvider/StateNotifier caches.
  static void _invalidateRiverpodProviders(BuildContext context) {
    try {
      final container = riverpod.ProviderScope.containerOf(context);

      // Cash system
      container.invalidate(cashBalanceProvider);
      container.invalidate(teamBalancesProvider);
      container.invalidate(tenantUsersProvider);
      container.invalidate(cashNotifierProvider);

      debugPrint('✅ [LogoutService] Riverpod providers invalidated');
    } catch (e) {
      debugPrint('⚠️ [LogoutService] Riverpod invalidation error: $e');
    }
  }

  /// Clear DioApiService in-memory token cache and HTTP response cache.
  static void _clearApiCaches(BuildContext context) {
    try {
      final apiService = context.read<DioApiService>();
      apiService.resetSessionExpired();
      apiService.clearHttpCache();
      debugPrint('✅ [LogoutService] API caches cleared');
    } catch (e) {
      debugPrint('⚠️ [LogoutService] API cache clear error: $e');
    }
  }

  /// Unregister FCM device to stop push notifications for previous user.
  static Future<void> _unregisterFcm(BuildContext context) async {
    try {
      final container = riverpod.ProviderScope.containerOf(context);
      final fcmService = container.read(fcmServiceProvider);
      await fcmService.unregisterDevice();
      debugPrint('✅ [LogoutService] FCM device unregistered');
    } catch (e) {
      debugPrint('⚠️ [LogoutService] FCM unregister error (non-critical): $e');
    }
  }

  /// Helper: try to call a reset function, log and swallow errors.
  static void _tryReset(VoidCallback resetFn, String name) {
    try {
      resetFn();
    } catch (e) {
      debugPrint('⚠️ [LogoutService] $name reset failed: $e');
    }
  }
}

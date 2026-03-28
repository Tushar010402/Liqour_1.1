import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Notification Navigation Service
/// Handles deep linking from notifications to appropriate screens
/// Also handles session expiration navigation
class NotificationNavigationService {
  /// Global navigator key for navigation from outside widget tree
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// Flag to prevent multiple session expiration navigations
  static bool _isHandlingSessionExpiration = false;

  /// Handle session expiration - show dialog then navigate to login screen
  /// This is called from DioApiService when 401 is received or no token found
  /// Uses a flag to prevent multiple navigations from concurrent API calls
  static void handleSessionExpiration() {
    // Prevent multiple simultaneous session expiration handlers
    if (_isHandlingSessionExpiration) {
      return;
    }

    _isHandlingSessionExpiration = true;
    debugPrint('[SessionExpiration] Session expired - redirecting to login');

    // Use post-frame callback to ensure we're not in middle of build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null) {
        debugPrint('[SessionExpiration] No context available');
        _isHandlingSessionExpiration = false;
        return;
      }

      // Show a brief, polished dialog then redirect
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        builder: (ctx) {
          // Auto-redirect after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (ctx.mounted) Navigator.of(ctx).pop();
          });
          return PopScope(
            canPop: false,
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.lock_outline_rounded, size: 28, color: Color(0xFFE65100)),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Session Expired',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26)),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your session has expired for security.\nPlease log in again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF888888), height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity, height: 44,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D47A1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('Log In', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((_) {
        // After dialog closes (tap or auto), navigate to login
        if (context.mounted) {
          context.go('/phone-login');
        }
        // Reset flag after navigation
        Future.delayed(const Duration(seconds: 1), () {
          _isHandlingSessionExpiration = false;
        });
      });
    });
  }

  /// Reset session expiration flag (call on successful login)
  static void resetSessionExpirationFlag() {
    _isHandlingSessionExpiration = false;
  }

  /// Handle notification tap and navigate to appropriate screen
  static void handleNotificationTap(
    Map<String, dynamic> data,
    BuildContext context,
  ) {
    final type = data['type'] as String?;
    final actionUrl = data['action_url'] as String?;

    debugPrint('🔔 NotificationNavigation: type=$type, actionUrl=$actionUrl');

    // If actionUrl is provided, use it directly
    if (actionUrl != null && actionUrl.isNotEmpty) {
      _navigateToUrl(actionUrl, context);
      return;
    }

    // Otherwise, determine route based on notification type
    if (type != null) {
      final route = getRouteForType(type, data);
      if (route != null) {
        context.go(route);
      }
    }
  }

  /// Get the appropriate route for a notification type
  static String? getRouteForType(String type, [Map<String, dynamic>? data]) {
    switch (type.toLowerCase()) {
      // Low stock alerts - go to inventory
      case 'low_stock_alert':
      case 'low_stock':
      case 'stock_alert':
        return '/inventory';

      // Daily sales notifications
      case 'daily_sales':
      case 'daily_sales_reminder':
        return '/sales/daily-entry';

      // Cash management
      case 'cash_collection':
      case 'cash_request':
      case 'cash_submission':
      case 'cash':
        return '/cash';

      // Inventory related
      case 'inventory':
      case 'inventory_update':
      case 'stock_update':
        return '/inventory';

      // Sales related
      case 'sales':
      case 'sale':
      case 'new_sale':
        return '/sales';

      // Finance related
      case 'finance':
      case 'payment':
      case 'expense':
        return '/finance';

      // System notifications - go to notification center
      case 'system':
      case 'general':
      case 'announcement':
        return '/notifications';

      // Security/audit alerts
      case 'security':
      case 'theft':
      case 'audit':
        return '/notifications';

      default:
        debugPrint('🔔 Unknown notification type: $type');
        return '/notifications';
    }
  }

  /// Navigate to a specific URL/route
  static void _navigateToUrl(String url, BuildContext context) {
    // Handle different URL formats
    if (url.startsWith('/')) {
      // Internal app route
      context.go(url);
    } else if (url.startsWith('liquorpro://')) {
      // Deep link format: liquorpro://screen/id
      final path = url.replaceFirst('liquorpro://', '/');
      context.go(path);
    } else {
      // Unknown format - go to notifications
      debugPrint('🔔 Unknown URL format: $url');
      context.go('/notifications');
    }
  }

  /// Get icon for notification type
  static IconData getIconForType(String type) {
    final lowerType = type.toLowerCase();

    // Stock alerts (priority)
    if (lowerType.contains('stock') || lowerType.contains('out_of')) {
      return Icons.inventory_2_rounded;
    }

    // Sales related
    if (lowerType.contains('sales') || lowerType.contains('sale')) {
      return Icons.point_of_sale_rounded;
    }

    // Cash related
    if (lowerType.contains('cash') || lowerType.contains('collection')) {
      return Icons.account_balance_wallet_rounded;
    }

    // Inventory related
    if (lowerType.contains('inventory')) {
      return Icons.inventory_rounded;
    }

    // Finance related
    if (lowerType.contains('finance') || lowerType.contains('payment') || lowerType.contains('expense')) {
      return Icons.attach_money_rounded;
    }

    // Security related
    if (lowerType.contains('security') || lowerType.contains('theft')) {
      return Icons.security_rounded;
    }

    // Audit related
    if (lowerType.contains('audit')) {
      return Icons.fact_check_rounded;
    }

    // Alert type
    if (lowerType.contains('alert') || lowerType.contains('warning')) {
      return Icons.warning_amber_rounded;
    }

    // System type
    if (lowerType == 'system' || lowerType == 'general') {
      return Icons.campaign_rounded;
    }

    return Icons.notifications_rounded;
  }

  /// Get color for notification type
  static Color getColorForType(String type) {
    final lowerType = type.toLowerCase();

    // Stock alerts - orange/warning
    if (lowerType.contains('stock') || lowerType.contains('out_of')) {
      return const Color(0xFFFF9500); // iOS orange
    }

    // Sales related - green
    if (lowerType.contains('sales') || lowerType.contains('sale')) {
      return const Color(0xFF34C759); // iOS green
    }

    // Cash related - blue
    if (lowerType.contains('cash') || lowerType.contains('collection')) {
      return const Color(0xFF007AFF); // iOS blue
    }

    // Inventory related - indigo
    if (lowerType.contains('inventory')) {
      return const Color(0xFF5856D6); // iOS indigo
    }

    // Finance related - teal
    if (lowerType.contains('finance') || lowerType.contains('payment') || lowerType.contains('expense')) {
      return const Color(0xFF5AC8FA); // iOS teal
    }

    // Security related - red
    if (lowerType.contains('security') || lowerType.contains('theft')) {
      return const Color(0xFFFF3B30); // iOS red
    }

    // Audit related - purple
    if (lowerType.contains('audit')) {
      return const Color(0xFFAF52DE); // iOS purple
    }

    // Alert type - orange
    if (lowerType.contains('alert') || lowerType.contains('warning')) {
      return const Color(0xFFFF9500); // iOS orange
    }

    // System type - gray
    if (lowerType == 'system' || lowerType == 'general') {
      return const Color(0xFF8E8E93); // iOS gray
    }

    return const Color(0xFF8E8E93); // iOS gray as default
  }
}

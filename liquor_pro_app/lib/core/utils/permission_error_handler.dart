import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../models/api_response.dart';
import '../theme/ios_design_tokens.dart';
import '../widgets/permission_denied_screen.dart';

/// PermissionErrorHandler - Utility for handling 403 errors in the UI
///
/// Usage:
/// ```dart
/// final response = await apiService.deleteUser(userId);
/// if (PermissionErrorHandler.is403Error(response)) {
///   PermissionErrorHandler.showErrorDialog(context, response);
///   return;
/// }
/// ```
class PermissionErrorHandler {
  /// Check if an API response is a 403 permission denied error
  static bool is403Error(ApiResponse response) {
    return response.statusCode == 403 ||
        (response.errors?['permission_denied'] == true);
  }

  /// Extract the required role from a 403 response
  static String? getRequiredRole(ApiResponse response) {
    return response.errors?['required_role'] as String?;
  }

  /// Extract the user's current role from a 403 response
  static String? getUserRole(ApiResponse response) {
    return response.errors?['user_role'] as String?;
  }

  /// Show a permission denied dialog with details
  static Future<void> showErrorDialog(
    BuildContext context,
    ApiResponse response, {
    String? attemptedAction,
    VoidCallback? onContactAdmin,
  }) {
    final requiredRole = getRequiredRole(response);
    final userRole = getUserRole(response);

    return showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.lock_shield_fill,
              color: iOSDesignTokens.error,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text('Access Restricted'),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                response.message ?? 'You don\'t have permission for this action.',
                textAlign: TextAlign.center,
              ),
              if (userRole != null || requiredRole != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iOSDesignTokens.neutralGray100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      if (userRole != null)
                        _buildRoleRow('Your role:', userRole),
                      if (requiredRole != null) ...[
                        if (userRole != null) const SizedBox(height: 8),
                        _buildRoleRow('Required:', requiredRole),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
          if (onContactAdmin != null)
            CupertinoDialogAction(
              child: const Text('Contact Admin'),
              onPressed: () {
                Navigator.pop(context);
                onContactAdmin();
              },
            ),
        ],
      ),
    );
  }

  static Widget _buildRoleRow(String label, String role) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: iOSDesignTokens.labelSmall.copyWith(
            color: iOSDesignTokens.neutralGray600,
          ),
        ),
        Text(
          _formatRole(role),
          style: iOSDesignTokens.labelMedium.copyWith(
            color: iOSDesignTokens.neutralGray900,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Show a snackbar for permission errors (less intrusive)
  static void showErrorSnackBar(BuildContext context, ApiResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              CupertinoIcons.lock_fill,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                response.message ?? 'Permission denied',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: iOSDesignTokens.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Details',
          textColor: Colors.white,
          onPressed: () {
            showErrorDialog(context, response);
          },
        ),
      ),
    );
  }

  /// Navigate to full permission denied screen
  static void navigateToPermissionDenied(
    BuildContext context, {
    String? attemptedAction,
    String? userRole,
    String? requiredRole,
    VoidCallback? onContactAdmin,
  }) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => PermissionDeniedScreen(
          attemptedAction: attemptedAction,
          userRole: userRole,
          requiredRole: requiredRole,
          onGoBack: () => Navigator.pop(context),
          onContactAdmin: onContactAdmin,
        ),
      ),
    );
  }

  /// Handle a 403 response with appropriate UI feedback
  ///
  /// Returns true if the response was a 403 error and was handled
  static bool handleIfPermissionError(
    BuildContext context,
    ApiResponse response, {
    String? attemptedAction,
    bool useDialog = true,
    VoidCallback? onContactAdmin,
  }) {
    if (!is403Error(response)) return false;

    if (useDialog) {
      showErrorDialog(
        context,
        response,
        attemptedAction: attemptedAction,
        onContactAdmin: onContactAdmin,
      );
    } else {
      showErrorSnackBar(context, response);
    }

    return true;
  }

  /// Format role name for display
  static String _formatRole(String role) {
    return role
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}

/// Extension on ApiResponse for easier permission checking
extension PermissionApiResponseExtension on ApiResponse {
  /// Check if this is a 403 permission denied error
  bool get isPermissionDenied => PermissionErrorHandler.is403Error(this);

  /// Get the required role if this is a 403 error
  String? get requiredRole => PermissionErrorHandler.getRequiredRole(this);

  /// Get the user's role if this is a 403 error
  String? get currentUserRole => PermissionErrorHandler.getUserRole(this);
}

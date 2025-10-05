import 'package:permission_handler/permission_handler.dart';
import 'app_logger.dart';
import 'dialog_helper.dart';
import 'package:flutter/material.dart';

/// Permission Helper - Best Practice Permission Management
/// Centralized permission handling with user-friendly dialogs

class PermissionHelper {
  // Private constructor to prevent instantiation
  PermissionHelper._();

  // ==================== Camera Permission ====================

  /// Request camera permission
  static Future<bool> requestCamera(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.camera,
      title: 'Camera Permission',
      message: 'This app needs camera access to take photos.',
      settingsMessage: 'Please enable camera permission in settings to take photos.',
    );
  }

  /// Check camera permission
  static Future<bool> hasCamera() async {
    return await _checkPermission(Permission.camera);
  }

  // ==================== Photo Library Permission ====================

  /// Request photo library permission
  static Future<bool> requestPhotos(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.photos,
      title: 'Photo Library Permission',
      message: 'This app needs access to your photo library to select images.',
      settingsMessage: 'Please enable photo library permission in settings.',
    );
  }

  /// Check photo library permission
  static Future<bool> hasPhotos() async {
    return await _checkPermission(Permission.photos);
  }

  // ==================== Location Permission ====================

  /// Request location permission
  static Future<bool> requestLocation(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.location,
      title: 'Location Permission',
      message: 'This app needs your location to provide location-based services.',
      settingsMessage: 'Please enable location permission in settings.',
    );
  }

  /// Check location permission
  static Future<bool> hasLocation() async {
    return await _checkPermission(Permission.location);
  }

  /// Request location always permission
  static Future<bool> requestLocationAlways(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.locationAlways,
      title: 'Location Always Permission',
      message: 'This app needs continuous location access.',
      settingsMessage: 'Please enable location always permission in settings.',
    );
  }

  // ==================== Storage Permission ====================

  /// Request storage permission
  static Future<bool> requestStorage(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.storage,
      title: 'Storage Permission',
      message: 'This app needs storage access to save files.',
      settingsMessage: 'Please enable storage permission in settings.',
    );
  }

  /// Check storage permission
  static Future<bool> hasStorage() async {
    return await _checkPermission(Permission.storage);
  }

  // ==================== Microphone Permission ====================

  /// Request microphone permission
  static Future<bool> requestMicrophone(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.microphone,
      title: 'Microphone Permission',
      message: 'This app needs microphone access to record audio.',
      settingsMessage: 'Please enable microphone permission in settings.',
    );
  }

  /// Check microphone permission
  static Future<bool> hasMicrophone() async {
    return await _checkPermission(Permission.microphone);
  }

  // ==================== Contacts Permission ====================

  /// Request contacts permission
  static Future<bool> requestContacts(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.contacts,
      title: 'Contacts Permission',
      message: 'This app needs access to your contacts.',
      settingsMessage: 'Please enable contacts permission in settings.',
    );
  }

  /// Check contacts permission
  static Future<bool> hasContacts() async {
    return await _checkPermission(Permission.contacts);
  }

  // ==================== Notification Permission ====================

  /// Request notification permission
  static Future<bool> requestNotification(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.notification,
      title: 'Notification Permission',
      message: 'This app needs permission to send you notifications.',
      settingsMessage: 'Please enable notification permission in settings.',
    );
  }

  /// Check notification permission
  static Future<bool> hasNotification() async {
    return await _checkPermission(Permission.notification);
  }

  // ==================== Bluetooth Permission ====================

  /// Request bluetooth permission
  static Future<bool> requestBluetooth(BuildContext context) async {
    return await _requestPermission(
      context: context,
      permission: Permission.bluetooth,
      title: 'Bluetooth Permission',
      message: 'This app needs bluetooth access to connect to devices.',
      settingsMessage: 'Please enable bluetooth permission in settings.',
    );
  }

  /// Check bluetooth permission
  static Future<bool> hasBluetooth() async {
    return await _checkPermission(Permission.bluetooth);
  }

  // ==================== Core Permission Logic ====================

  /// Check if permission is granted
  static Future<bool> _checkPermission(Permission permission) async {
    try {
      final status = await permission.status;
      AppLogger.debug('Permission ${permission.toString()} status: $status');
      return status.isGranted;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Check Permission',
        additionalData: {'permission': permission.toString()},
      );
      return false;
    }
  }

  /// Request permission with user-friendly dialogs
  static Future<bool> _requestPermission({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String message,
    required String settingsMessage,
  }) async {
    try {
      // Check current status
      final status = await permission.status;

      AppLogger.info('Requesting permission: ${permission.toString()}, current status: $status');

      // If already granted
      if (status.isGranted) {
        return true;
      }

      // If permanently denied, show settings dialog
      if (status.isPermanentlyDenied) {
        return await _showSettingsDialog(
          context: context,
          title: title,
          message: settingsMessage,
        );
      }

      // If denied, show rationale dialog first
      if (status.isDenied) {
        final shouldRequest = await _showRationaleDialog(
          context: context,
          title: title,
          message: message,
        );

        if (!shouldRequest) {
          return false;
        }
      }

      // Request permission
      final result = await permission.request();

      AppLogger.info('Permission result: $result');

      // If granted after request
      if (result.isGranted) {
        return true;
      }

      // If permanently denied after request
      if (result.isPermanentlyDenied) {
        return await _showSettingsDialog(
          context: context,
          title: title,
          message: settingsMessage,
        );
      }

      return false;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Request Permission',
        additionalData: {'permission': permission.toString()},
      );
      return false;
    }
  }

  /// Show rationale dialog
  static Future<bool> _showRationaleDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    final result = await DialogHelper.confirm(
      context: context,
      title: title,
      message: message,
      confirmText: 'Allow',
      cancelText: 'Deny',
      icon: Icons.security,
    );

    return result ?? false;
  }

  /// Show settings dialog
  static Future<bool> _showSettingsDialog({
    required BuildContext context,
    required String title,
    required String message,
  }) async {
    final result = await DialogHelper.confirm(
      context: context,
      title: title,
      message: message,
      confirmText: 'Open Settings',
      cancelText: 'Cancel',
      icon: Icons.settings,
    );

    if (result == true) {
      await openAppSettings();
      return false; // User needs to manually grant in settings
    }

    return false;
  }

  // ==================== Multiple Permissions ====================

  /// Request multiple permissions
  static Future<Map<Permission, bool>> requestMultiple({
    required BuildContext context,
    required List<Permission> permissions,
  }) async {
    final results = <Permission, bool>{};

    for (final permission in permissions) {
      // Get permission name and details
      final permissionInfo = _getPermissionInfo(permission);

      final granted = await _requestPermission(
        context: context,
        permission: permission,
        title: permissionInfo['title']!,
        message: permissionInfo['message']!,
        settingsMessage: permissionInfo['settingsMessage']!,
      );

      results[permission] = granted;

      // If any permission denied, stop requesting
      if (!granted) {
        AppLogger.warning('Permission denied: ${permission.toString()}');
        break;
      }
    }

    return results;
  }

  /// Check multiple permissions
  static Future<Map<Permission, bool>> checkMultiple(
    List<Permission> permissions,
  ) async {
    final results = <Permission, bool>{};

    for (final permission in permissions) {
      results[permission] = await _checkPermission(permission);
    }

    return results;
  }

  /// Get permission info
  static Map<String, String> _getPermissionInfo(Permission permission) {
    switch (permission) {
      case Permission.camera:
        return {
          'title': 'Camera Permission',
          'message': 'This app needs camera access to take photos.',
          'settingsMessage': 'Please enable camera permission in settings.',
        };
      case Permission.photos:
        return {
          'title': 'Photo Library Permission',
          'message': 'This app needs access to your photo library.',
          'settingsMessage': 'Please enable photo library permission in settings.',
        };
      case Permission.location:
        return {
          'title': 'Location Permission',
          'message': 'This app needs your location.',
          'settingsMessage': 'Please enable location permission in settings.',
        };
      case Permission.storage:
        return {
          'title': 'Storage Permission',
          'message': 'This app needs storage access.',
          'settingsMessage': 'Please enable storage permission in settings.',
        };
      case Permission.microphone:
        return {
          'title': 'Microphone Permission',
          'message': 'This app needs microphone access.',
          'settingsMessage': 'Please enable microphone permission in settings.',
        };
      case Permission.notification:
        return {
          'title': 'Notification Permission',
          'message': 'This app needs to send notifications.',
          'settingsMessage': 'Please enable notification permission in settings.',
        };
      default:
        return {
          'title': 'Permission Required',
          'message': 'This app needs this permission to function properly.',
          'settingsMessage': 'Please enable this permission in settings.',
        };
    }
  }

  // ==================== Utility Methods ====================

  /// Open app settings
  static Future<bool> openSettings() async {
    try {
      final result = await openAppSettings();
      AppLogger.info('Opened app settings: $result');
      return result;
    } catch (e, stackTrace) {
      AppLogger.exception(
        exception: e,
        stackTrace: stackTrace,
        context: 'Open Settings',
      );
      return false;
    }
  }

  /// Check all permissions status
  static Future<void> logAllPermissionsStatus() async {
    final permissions = [
      Permission.camera,
      Permission.photos,
      Permission.location,
      Permission.storage,
      Permission.microphone,
      Permission.contacts,
      Permission.notification,
    ];

    for (final permission in permissions) {
      final status = await permission.status;
      AppLogger.info('${permission.toString()}: $status');
    }
  }
}

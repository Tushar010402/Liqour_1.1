import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

/// App Tracking Transparency Service
///
/// Handles iOS ATT permission request as required by Apple Guideline 5.1.2.
/// This service should be called after app launch to request tracking permission.
///
/// Note: On Android, this is a no-op since ATT is iOS-specific.
class AppTrackingService {
  static final AppTrackingService _instance = AppTrackingService._internal();
  factory AppTrackingService() => _instance;
  AppTrackingService._internal();

  /// Current tracking authorization status
  TrackingStatus? _status;

  /// Get the current tracking status
  TrackingStatus? get status => _status;

  /// Check if tracking is authorized
  bool get isAuthorized => _status == TrackingStatus.authorized;

  /// Check if we need to request permission (iOS 14+)
  bool get needsRequest => Platform.isIOS;

  /// Request App Tracking Transparency permission
  ///
  /// This should be called after app launch, typically after a brief delay
  /// to let the user see the app first (per Apple HIG guidelines).
  ///
  /// Returns the tracking status after the request.
  Future<TrackingStatus> requestTrackingPermission() async {
    // Only request on iOS
    if (!Platform.isIOS) {
      _status = TrackingStatus.notSupported;
      return _status!;
    }

    try {
      // Check current status first
      _status = await AppTrackingTransparency.trackingAuthorizationStatus;

      if (kDebugMode) {
        debugPrint('📱 ATT Current Status: $_status');
      }

      // If not determined, request permission
      if (_status == TrackingStatus.notDetermined) {
        // Small delay to ensure app is fully loaded (Apple HIG recommendation)
        await Future.delayed(const Duration(milliseconds: 500));

        _status = await AppTrackingTransparency.requestTrackingAuthorization();

        if (kDebugMode) {
          debugPrint('📱 ATT Permission Result: $_status');
        }
      }

      return _status!;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ ATT Error: $e');
      }
      _status = TrackingStatus.notSupported;
      return _status!;
    }
  }

  /// Get the advertising identifier (IDFA)
  ///
  /// Returns null if tracking is not authorized or not available.
  Future<String?> getAdvertisingIdentifier() async {
    if (!Platform.isIOS) return null;

    try {
      // Only get IDFA if authorized
      if (_status == TrackingStatus.authorized) {
        final idfa = await AppTrackingTransparency.getAdvertisingIdentifier();
        return idfa.isNotEmpty ? idfa : null;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ IDFA Error: $e');
      }
      return null;
    }
  }

  /// Initialize ATT - call this after app launch
  ///
  /// This method:
  /// 1. Waits for appropriate time after app launch
  /// 2. Requests tracking permission
  /// 3. Logs the result
  Future<void> initialize() async {
    if (!Platform.isIOS) {
      if (kDebugMode) {
        debugPrint('📱 ATT: Not iOS, skipping');
      }
      return;
    }

    // Wait for app to be ready (Apple recommends not showing immediately)
    await Future.delayed(const Duration(seconds: 1));

    final status = await requestTrackingPermission();

    if (kDebugMode) {
      debugPrint('📱 ATT Final Status: ${_statusToString(status)}');
    }
  }

  String _statusToString(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.notDetermined:
        return 'Not Determined';
      case TrackingStatus.restricted:
        return 'Restricted';
      case TrackingStatus.denied:
        return 'Denied';
      case TrackingStatus.authorized:
        return 'Authorized';
      case TrackingStatus.notSupported:
        return 'Not Supported';
    }
  }
}

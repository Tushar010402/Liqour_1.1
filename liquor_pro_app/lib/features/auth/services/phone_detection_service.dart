import 'package:flutter/foundation.dart';
// import 'package:mobile_number/mobile_number.dart'; // Disabled due to Gradle issues
import 'package:permission_handler/permission_handler.dart';

/// Model for detected phone number from SIM
class DetectedPhone {
  final String number;
  final String? carrierName;
  final String? simSlot; // "SIM 1", "SIM 2", etc.

  DetectedPhone({
    required this.number,
    this.carrierName,
    this.simSlot,
  });

  String get displayName => simSlot ?? 'Phone';
  String get displayCarrier => carrierName ?? 'Unknown Carrier';

  @override
  String toString() => '$displayName - $displayCarrier: $number';
}

/// Service for detecting phone numbers from SIM cards
class PhoneDetectionService {
  static final PhoneDetectionService _instance = PhoneDetectionService._internal();
  factory PhoneDetectionService() => _instance;
  PhoneDetectionService._internal();

  final List<DetectedPhone> _detectedPhones = [];
  bool _hasPermission = false;

  /// Get detected phone numbers from SIM cards
  /// NOTE: Phone detection disabled due to mobile_number package Gradle issues
  /// Users can enter phone numbers manually - OTP auto-fill still works!
  Future<List<DetectedPhone>> getPhoneNumbers() async {
    debugPrint('📱 [PhoneDetection] Phone detection disabled - manual entry available');
    debugPrint('📱 [PhoneDetection] ✅ OTP auto-fill is working and ready!');
    return [];
  }

  /// Check if we have permission to read phone state
  Future<bool> _checkAndRequestPermission() async {
    // Check current permission status
    final status = await Permission.phone.status;

    if (status.isGranted) {
      _hasPermission = true;
      return true;
    }

    // Request permission
    final result = await Permission.phone.request();

    _hasPermission = result.isGranted;

    if (result.isDenied) {
      debugPrint('📱 [PhoneDetection] Permission denied');
    } else if (result.isPermanentlyDenied) {
      debugPrint('📱 [PhoneDetection] Permission permanently denied');
      // Could show dialog to open app settings
    }

    return _hasPermission;
  }

  /// Format phone number to include country code
  String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digitsOnly = phone.replaceAll(RegExp(r'\D'), '');

    // If it starts with 91, add + prefix
    if (digitsOnly.startsWith('91') && digitsOnly.length > 10) {
      return '+$digitsOnly';
    }

    // If it's 10 digits, add +91 prefix (India)
    if (digitsOnly.length == 10) {
      return '+91$digitsOnly';
    }

    // If it already has +, return as-is
    if (phone.startsWith('+')) {
      return phone;
    }

    // Otherwise return with + prefix
    return '+$digitsOnly';
  }

  /// Check if phone detection is supported on this platform
  bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  /// Check if we have permission
  bool get hasPermission => _hasPermission;

  /// Get cached detected phones
  List<DetectedPhone> get cachedPhones => List.unmodifiable(_detectedPhones);

  /// Clear cached phones
  void clearCache() {
    _detectedPhones.clear();
  }
}

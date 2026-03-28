import 'package:flutter/foundation.dart';
import '../config/api_config.dart';

/// Security utilities for the LiquorPro app
class SecurityUtils {
  /// Sanitized logging that removes sensitive information
  static void secureLog(String message, {String? tag}) {
    if (!ApiConfig.enableLogging) return;
    
    // Remove potential sensitive data patterns
    String sanitized = message
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9\-_]+\.'), 'Bearer [REDACTED].')
        .replaceAll(RegExp(r'"token":"[^"]*"'), '"token":"[REDACTED]"')
        .replaceAll(RegExp(r'"refresh_token":"[^"]*"'), '"refresh_token":"[REDACTED]"')
        .replaceAll(RegExp(r'"password":"[^"]*"'), '"password":"[REDACTED]"')
        .replaceAll(RegExp(r'"otp":"[^"]*"'), '"otp":"[REDACTED]"')
        .replaceAll(RegExp(r'"session_id":"[^"]*"'), '"session_id":"[REDACTED]"')
        .replaceAll(RegExp(r'\+91\d{8,}'), '+91[REDACTED]')
        .replaceAll(RegExp(r'\d{4,}\s*\d{4,}\s*\d{4,}'), '[CARD_NUMBER_REDACTED]');
    
    if (tag != null) {
      debugPrint('[$tag] $sanitized');
    } else {
      debugPrint(sanitized);
    }
  }
  
  /// Validate if data should be cached based on security level
  static bool shouldCache(String dataType) {
    const nonCacheableData = {
      'token',
      'password',
      'otp',
      'session',
      'payment',
      'card',
      'bank',
    };
    
    return !nonCacheableData.any((sensitive) => 
        dataType.toLowerCase().contains(sensitive));
  }
  
  /// Generate secure headers for API requests
  static Map<String, String> getSecureHeaders({
    String? token,
    String? tenantId,
    String? userId,
  }) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': ApiConfig.userAgent,
    };
    
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    
    if (tenantId != null) {
      headers['X-Tenant-ID'] = tenantId;
    }
    
    if (userId != null) {
      headers['X-User-ID'] = userId;
    }
    
    return headers;
  }
  
  /// Validate input to prevent injection attacks
  static String sanitizeInput(String input) {
    return input
        .replaceAll(RegExp(r'''[<>"']'''), '')
        .replaceAll(RegExp(r'script', caseSensitive: false), '')
        .replaceAll(RegExp(r'javascript', caseSensitive: false), '')
        .trim();
  }
  
  /// Check if environment is secure for sensitive operations
  static bool get isSecureEnvironment {
    if (kDebugMode) {
      return false; // Debug mode is not secure
    }
    
    return ApiConfig.isProduction && ApiConfig.enableCertificatePinning;
  }
  
  /// Generate masked display for sensitive data
  static String maskSensitiveData(String data, {int visibleChars = 4}) {
    if (data.length <= visibleChars) {
      return '*' * data.length;
    }
    
    final masked = '*' * (data.length - visibleChars);
    final visible = data.substring(data.length - visibleChars);
    
    return '$masked$visible';
  }
  
  /// Validate GST number format
  static bool isValidGST(String gst) {
    // GST format: 15 digits, specific pattern
    final gstRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    return gstRegex.hasMatch(gst);
  }
  
  /// Validate PAN number format  
  static bool isValidPAN(String pan) {
    // PAN format: 10 characters, specific pattern
    final panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
    return panRegex.hasMatch(pan);
  }
}
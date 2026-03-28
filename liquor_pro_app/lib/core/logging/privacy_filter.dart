/// Privacy Filter - Redacts sensitive data before logging
///
/// This ensures compliance with privacy regulations by automatically
/// removing or masking sensitive information from logs.
///
/// Sensitive data includes:
/// - Authentication tokens
/// - Passwords and OTPs
/// - Credit card numbers
/// - Personal identifiers (PAN, Aadhaar)
/// - Phone numbers
/// - API keys and secrets
class PrivacyFilter {
  // Private constructor - all methods are static
  PrivacyFilter._();

  // ==================== PATTERNS FOR REDACTION ====================

  /// Patterns for sensitive data that should be completely redacted
  static final List<RegExp> _sensitivePatterns = [
    // Authentication tokens
    RegExp(r'Bearer\s+[A-Za-z0-9\-_\.]+', caseSensitive: false),
    RegExp(r'"token"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"access_token"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"refresh_token"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"id_token"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"jwt"\s*:\s*"[^"]*"', caseSensitive: false),

    // Passwords and secrets
    RegExp(r'"password"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"otp"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"pin"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"secret"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"api_key"\s*:\s*"[^"]*"', caseSensitive: false),
    RegExp(r'"apikey"\s*:\s*"[^"]*"', caseSensitive: false),

    // Credit card numbers (various formats)
    RegExp(r'\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b'),
    RegExp(r'\b\d{16}\b'),

    // Indian identifiers
    RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b'),  // PAN
    RegExp(r'\b\d{12}\b'),               // Aadhaar

    // Base64 encoded data (likely tokens)
    RegExp(r'"[A-Za-z0-9+/]{40,}={0,2}"'),
  ];

  /// Fields that should always be redacted (case-insensitive)
  static final Set<String> _sensitiveFields = {
    'password',
    'otp',
    'pin',
    'token',
    'access_token',
    'refresh_token',
    'id_token',
    'jwt',
    'secret',
    'api_key',
    'apikey',
    'authorization',
    'cookie',
    'set-cookie',
    'x-auth-token',
    'x-api-key',
    'private_key',
    'credit_card',
    'card_number',
    'cvv',
    'expiry',
  };

  /// Headers that should always be redacted
  static final Set<String> _sensitiveHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
    'x-auth-token',
    'x-api-key',
    'x-session-id',
  };

  // ==================== PUBLIC METHODS ====================

  /// Redact sensitive data from a string
  static String redactString(String input) {
    if (input.isEmpty) return input;

    var result = input;
    for (final pattern in _sensitivePatterns) {
      result = result.replaceAll(pattern, '[REDACTED]');
    }
    return result;
  }

  /// Redact sensitive fields from a Map
  static Map<String, dynamic> redactMap(Map<String, dynamic> data) {
    return data.map((key, value) {
      final lowerKey = key.toLowerCase();

      // Check if field name is sensitive
      if (_sensitiveFields.contains(lowerKey)) {
        return MapEntry(key, '[REDACTED]');
      }

      // Recursively handle nested maps
      if (value is Map<String, dynamic>) {
        return MapEntry(key, redactMap(value));
      }

      // Handle lists
      if (value is List) {
        return MapEntry(key, _redactList(value));
      }

      // Redact string values
      if (value is String) {
        return MapEntry(key, redactString(value));
      }

      return MapEntry(key, value);
    });
  }

  /// Redact sensitive headers
  static Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
    return headers.map((key, value) {
      final lowerKey = key.toLowerCase();

      if (_sensitiveHeaders.contains(lowerKey)) {
        return MapEntry(key, '[REDACTED]');
      }

      if (value is String) {
        return MapEntry(key, redactString(value));
      }

      return MapEntry(key, value);
    });
  }

  /// Mask phone number (show last 4 digits)
  static String maskPhoneNumber(String phone) {
    if (phone.length < 4) return '****';

    // Remove non-digit characters for processing
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');

    if (digitsOnly.length <= 4) {
      return '****';
    }

    // Show last 4 digits
    final masked = '*' * (digitsOnly.length - 4) + digitsOnly.substring(digitsOnly.length - 4);

    // If original had country code, try to preserve format
    if (phone.startsWith('+')) {
      return '+$masked';
    }
    return masked;
  }

  /// Mask email (show first 2 and last 2 characters before @)
  static String maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return '****@****.***';

    final local = parts[0];
    final domain = parts[1];

    String maskedLocal;
    if (local.length <= 4) {
      maskedLocal = '****';
    } else {
      maskedLocal = '${local.substring(0, 2)}${'*' * (local.length - 4)}${local.substring(local.length - 2)}';
    }

    return '$maskedLocal@$domain';
  }

  /// Truncate long strings (for request/response bodies)
  static String truncate(String input, {int maxLength = 2000}) {
    if (input.length <= maxLength) return input;
    return '${input.substring(0, maxLength)}... [TRUNCATED ${input.length - maxLength} chars]';
  }

  /// Redact and truncate request/response body
  static String redactBody(String body, {int maxLength = 2000}) {
    final redacted = redactString(body);
    return truncate(redacted, maxLength: maxLength);
  }

  /// Check if a URL contains sensitive parameters
  static String redactUrl(String url) {
    // Redact common sensitive query parameters
    var result = url;

    // Redact token parameters
    result = result.replaceAllMapped(
      RegExp(r'(token|access_token|refresh_token|api_key|key|secret)=([^&]+)', caseSensitive: false),
      (match) => '${match.group(1)}=[REDACTED]',
    );

    return result;
  }

  /// Sanitize log message
  static String sanitizeMessage(String message) {
    var result = message;

    // Redact patterns
    result = redactString(result);

    // Mask phone numbers in message
    result = result.replaceAllMapped(
      RegExp(r'(\+?\d{10,13})'),
      (match) => maskPhoneNumber(match.group(0)!),
    );

    // Mask emails in message
    result = result.replaceAllMapped(
      RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'),
      (match) => maskEmail(match.group(0)!),
    );

    return result;
  }

  // ==================== PRIVATE HELPERS ====================

  /// Redact sensitive data from a list
  static List<dynamic> _redactList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map<String, dynamic>) {
        return redactMap(item);
      }
      if (item is String) {
        return redactString(item);
      }
      if (item is List) {
        return _redactList(item);
      }
      return item;
    }).toList();
  }
}

/// Extension methods for easy privacy filtering
extension PrivacyExtensions on String {
  /// Redact sensitive patterns from string
  String get redacted => PrivacyFilter.redactString(this);

  /// Mask as phone number
  String get maskedPhone => PrivacyFilter.maskPhoneNumber(this);

  /// Mask as email
  String get maskedEmail => PrivacyFilter.maskEmail(this);

  /// Truncate to specified length
  String truncate([int maxLength = 2000]) =>
      PrivacyFilter.truncate(this, maxLength: maxLength);
}

extension PrivacyMapExtensions on Map<String, dynamic> {
  /// Redact sensitive fields from map
  Map<String, dynamic> get redacted => PrivacyFilter.redactMap(this);

  /// Redact headers specifically
  Map<String, dynamic> get redactedHeaders => PrivacyFilter.redactHeaders(this);
}

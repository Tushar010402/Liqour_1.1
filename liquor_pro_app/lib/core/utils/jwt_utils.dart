import 'dart:convert';
import 'package:flutter/foundation.dart';

/// JWT Token Utility Functions
class JwtUtils {
  /// Parse a JWT token and extract its payload
  static Map<String, dynamic>? parseJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        if (kDebugMode) print('❌ Invalid JWT format');
        return null;
      }

      // Get the payload part (second part)
      final payload = parts[1];

      // Add padding if needed for base64 decoding
      final normalizedPayload = base64Url.normalize(payload);

      // Decode the payload
      final payloadString = utf8.decode(base64Url.decode(normalizedPayload));
      return jsonDecode(payloadString) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) print('❌ JWT parsing error: $e');
      return null;
    }
  }

  /// Check if a JWT token is expired
  static bool isTokenExpired(String? token, {int bufferSeconds = 60}) {
    if (token == null || token.isEmpty) return true;

    try {
      final payload = parseJwtPayload(token);
      if (payload == null) return true;

      // Check for 'exp' claim
      final exp = payload['exp'];
      if (exp == null) {
        if (kDebugMode) print('⚠️ JWT has no expiration claim');
        return false; // No expiration means it doesn't expire
      }

      // Convert exp to DateTime
      final expirationTime = DateTime.fromMillisecondsSinceEpoch(
        (exp as num).toInt() * 1000, // JWT exp is in seconds
        isUtc: true,
      );

      // Add buffer time to refresh token before it actually expires
      final bufferTime = Duration(seconds: bufferSeconds);
      final expirationWithBuffer = expirationTime.subtract(bufferTime);

      final now = DateTime.now().toUtc();
      final isExpired = now.isAfter(expirationWithBuffer);

      if (kDebugMode && isExpired) {
        print('⚠️ JWT Token expired or expiring soon:');
        print('   Expiration: ${expirationTime.toLocal()}');
        print('   Current time: ${now.toLocal()}');
        print('   Buffer: ${bufferSeconds}s');
      }

      return isExpired;
    } catch (e) {
      if (kDebugMode) print('❌ Error checking token expiration: $e');
      return true; // Assume expired on error
    }
  }

  /// Get the expiration time of a JWT token
  static DateTime? getTokenExpiration(String? token) {
    if (token == null || token.isEmpty) return null;

    try {
      final payload = parseJwtPayload(token);
      if (payload == null) return null;

      final exp = payload['exp'];
      if (exp == null) return null;

      return DateTime.fromMillisecondsSinceEpoch(
        (exp as num).toInt() * 1000,
        isUtc: true,
      );
    } catch (e) {
      if (kDebugMode) print('❌ Error getting token expiration: $e');
      return null;
    }
  }

  /// Get time until token expires
  static Duration? getTimeUntilExpiration(String? token) {
    final expiration = getTokenExpiration(token);
    if (expiration == null) return null;

    final now = DateTime.now().toUtc();
    if (now.isAfter(expiration)) {
      return Duration.zero; // Already expired
    }

    return expiration.difference(now);
  }

  /// Check if token will expire within a given duration
  static bool willExpireSoon(String? token, {Duration within = const Duration(minutes: 5)}) {
    final timeLeft = getTimeUntilExpiration(token);
    if (timeLeft == null) return false;

    return timeLeft <= within;
  }

  /// Extract user information from JWT token
  static Map<String, dynamic>? getUserInfoFromToken(String? token) {
    if (token == null || token.isEmpty) return null;

    try {
      final payload = parseJwtPayload(token);
      if (payload == null) return null;

      return {
        'user_id': payload['user_id'],
        'tenant_id': payload['tenant_id'],
        'role': payload['role'],
        'exp': payload['exp'],
        'iat': payload['iat'],
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error extracting user info from token: $e');
      return null;
    }
  }
}
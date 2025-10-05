import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Red Colors
  static const Color primaryRed = Color(0xFFDC2626);
  static const Color darkRed = Color(0xFF991B1B);
  static const Color lightRed = Color(0xFFFEF2F2);
  static const Color redAccent = Color(0xFFF87171);

  // Black & Gray Colors
  static const Color primaryBlack = Color(0xFF111827);
  static const Color charcoalGray = Color(0xFF374151);
  static const Color mediumGray = Color(0xFF6B7280);
  static const Color lightGray = Color(0xFFF9FAFB);
  static const Color borderGray = Color(0xFFE5E7EB);

  // White & Background Colors
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFFAFAFA);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDEEDFF);
  static const Color primaryBlue = Color(0xFF3B82F6);

  // Chart Colors
  static const List<Color> chartColors = [
    primaryRed,
    info,
    success,
    warning,
    Color(0xFF8B5CF6), // Purple
    Color(0xFF06B6D4), // Cyan
    Color(0xFFF97316), // Orange
    Color(0xFF84CC16), // Lime
  ];

  // Gradient Colors
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryRed, darkRed],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [white, offWhite],
  );

  // Shadows
  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 8,
    offset: Offset(0, 4),
  );

  static const BoxShadow primaryShadow = BoxShadow(
    color: Color(0x26DC2626),
    blurRadius: 12,
    offset: Offset(0, 6),
  );

  // Dark Theme Colors (for future dark mode)
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
}

import 'package:flutter/material.dart';

/// Application color scheme - Modern vibrant palette
class AppColors {
  // Primary Colors - Rich Purple/Indigo
  static const Color primary = Color(0xFF6366F1); // Vibrant Indigo
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);

  // Accent Colors - Energetic Orange
  static const Color accent = Color(0xFFFF6B35); // Vibrant Orange
  static const Color accentLight = Color(0xFFFF8A5B);
  static const Color accentDark = Color(0xFFE85A2A);

  // Background Colors
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF0F172A);

  // Text Colors
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFFCBD5E1);
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color primaryWhite = Color(0xFFFFFFFF);
  static const Color secondaryWhite = Color(0xFFF8FAFC);
  static const Color mutedWhite = Color(0xFFE2E8F0);
  static const Color hintWhite = Color(0xFFCBD5E1);
  static const Color darkGrey = Color(0xFF334155);
  static const Color mediumGrey = Color(0xFF64748B);
  static const Color premiumGold = Color(0xFFFBBF24);
  static const Color errorRed = Color(0xFFEF4444);

  // Status Colors - Modern vibrant versions
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color error = Color(0xFFEF4444); // Red
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color info = Color(0xFF3B82F6); // Blue

  // UI Element Colors
  static const Color border = Color(0xFFE0E0E0);
  static const Color divider = Color(0xFFBDBDBD);
  static const Color disabled = Color(0xFF9E9E9E);
  static const Color shadow = Color(0x1A000000);

  // Card Colors
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color cardShadow = Color(0x0A000000);

  // Gradient Colors - Modern vibrant gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [Color(0xFFFF6B35), Color(0xFFFF8A5B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dark Theme Colors
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Chart Colors - Modern vibrant palette
  static const List<Color> chartColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFFFF6B35), // Orange
    Color(0xFF10B981), // Emerald
    Color(0xFFEF4444), // Red
    Color(0xFF3B82F6), // Blue
    Color(0xFFA855F7), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
  ];

  // Size-specific colors for variants - Modern vibrant
  static const Color size180ml = Color(0xFF10B981); // Emerald
  static const Color size350ml = Color(0xFF3B82F6); // Blue
  static const Color size750ml = Color(0xFFF59E0B); // Amber
  static const Color size1L = Color(0xFFEF4444); // Red

  // Get color by size
  static Color getSizeColor(String size) {
    switch (size.toLowerCase()) {
      case '180ml':
        return size180ml;
      case '350ml':
        return size350ml;
      case '750ml':
        return size750ml;
      case '1l':
      case '1000ml':
        return size1L;
      default:
        return primary;
    }
  }

  // Category Colors - Rich vibrant colors for different sections
  static const Color salesColor = Color(0xFF10B981); // Emerald green
  static const Color inventoryColor = Color(0xFF6366F1); // Indigo
  static const Color financeColor = Color(0xFFF59E0B); // Amber
  static const Color exciseColor = Color(0xFFA855F7); // Purple
  static const Color reportsColor = Color(0xFF3B82F6); // Blue
  static const Color customersColor = Color(0xFFEC4899); // Pink
  static const Color settingsColor = Color(0xFF64748B); // Slate

  // Feature highlight colors
  static const Color premium = Color(0xFFFBBF24); // Gold
  static const Color danger = Color(0xFFDC2626); // Dark red
  static const Color safe = Color(0xFF059669); // Green
  static const Color neutral = Color(0xFF6B7280); // Gray
}

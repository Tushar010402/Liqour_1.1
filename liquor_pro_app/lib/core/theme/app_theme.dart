import 'package:flutter/material.dart';

/// App Theme Configuration — Warm White (default), Cool White, Dark.
class AppTheme {
  // Brand colors
  static const Color primaryColor = Color(0xFF0D47A1);
  static const Color primaryDark = Color(0xFF0A3680);
  static const Color primaryLight = Color(0xFF2196F3);

  static const Color secondaryColor = Color(0xFF10B981);
  static const Color accentColor = Color(0xFFF59E0B);

  static const Color successColor = Color(0xFF10B981);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFE53935);
  static const Color infoColor = Color(0xFF3B82F6);

  // Default text & surface colors (warm white base — backward compat)
  static const Color textPrimary = Color(0xFF1C1917);
  static const Color textSecondary = Color(0xFF78716C);
  static const Color borderColor = Color(0xFFE7E5E4);
  static const Color backgroundColor = Color(0xFFFFF8EE);
  static const Color surfaceColor = Color(0xFFFFFDF8);

  // ──────────────────────────────────────────────────
  // Warm White Theme (default) — golden cream like Claude
  // ──────────────────────────────────────────────────
  static ThemeData get warmWhiteTheme {
    const bg = Color(0xFFF5F6FA); // light blue-gray
    const surface = Color(0xFFFFFFFF);
    const textPrimary = Color(0xFF0F172A);
    const textSecondary = Color(0xFF64748B);
    const border = Color(0xFFD0D5DD);
    const cardColor = Color(0xFFFFFFFF);

    return _buildTheme(
      brightness: Brightness.light,
      background: bg,
      surface: surface,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      border: border,
      cardColor: cardColor,
      seedColor: const Color(0xFF0D47A1), // Bold blue
    );
  }

  // ──────────────────────────────────────────────────
  // Cool White Theme — light sky blue tint
  // ──────────────────────────────────────────────────
  static ThemeData get coolWhiteTheme {
    const bg = Color(0xFFF0F7FF); // light sky blue
    const surface = Color(0xFFF8FBFF); // hint of blue-white
    const textPrimary = Color(0xFF0F172A);
    const textSecondary = Color(0xFF64748B);
    const border = Color(0xFFDAE5F2); // soft blue-gray border
    const cardColor = Color(0xFFF8FBFF);

    return _buildTheme(
      brightness: Brightness.light,
      background: bg,
      surface: surface,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      border: border,
      cardColor: cardColor,
    );
  }

  // ──────────────────────────────────────────────────
  // Dark Theme
  // ──────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const bg = Color(0xFF0F172A);
    const surface = Color(0xFF1E293B);
    const textPrimary = Color(0xFFF1F5F9);
    const textSecondary = Color(0xFF94A3B8);
    const border = Color(0xFF334155);
    const cardColor = Color(0xFF1E293B);

    return _buildTheme(
      brightness: Brightness.dark,
      background: bg,
      surface: surface,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      border: border,
      cardColor: cardColor,
    );
  }

  // Legacy getter for backward compatibility
  static ThemeData get lightTheme => warmWhiteTheme;

  // ──────────────────────────────────────────────────
  // Shared builder
  // ──────────────────────────────────────────────────
  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    required Color cardColor,
    Color? seedColor,
  }) {
    final isLight = brightness == Brightness.light;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor ?? primaryColor,
      brightness: brightness,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: border.withValues(alpha: 0.5),
    );

    // Override primary/secondary with the seed color for warm themes
    final colorScheme = seedColor != null
        ? baseScheme.copyWith(
            primary: seedColor,
            onPrimary: Colors.white,
          )
        : baseScheme;

    final themePrimary = colorScheme.primary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: isLight ? 1 : 2,
        color: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border.withValues(alpha: 0.5)),
        ),
      ),
      dividerColor: border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: themePrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: errorColor),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: themePrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: themePrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: themePrimary,
        foregroundColor: Colors.white,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: themePrimary,
        unselectedItemColor: textSecondary,
      ),
    );
  }
}

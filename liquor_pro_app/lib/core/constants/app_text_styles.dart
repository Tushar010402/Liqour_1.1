import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Application text styles.
///
/// Colors are NOT set here — they inherit from the theme's DefaultTextStyle
/// so that text automatically adapts to light/dark mode. Use
/// `.copyWith(color: ...)` when you need a specific color.
class AppTextStyles {
  // Headings
  static TextStyle h1 = GoogleFonts.nunito(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static TextStyle h2 = GoogleFonts.nunito(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
  );

  static TextStyle h3 = GoogleFonts.nunito(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static TextStyle h4 = GoogleFonts.nunito(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle h5 = GoogleFonts.nunito(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static TextStyle h6 = GoogleFonts.nunito(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  // Body Text
  static TextStyle bodyLarge = GoogleFonts.nunito(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static TextStyle bodyMedium = GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static TextStyle bodySmall = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  // Button Text
  static TextStyle button = GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textWhite,
    letterSpacing: 0.5,
  );

  static TextStyle buttonLarge = GoogleFonts.nunito(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textWhite,
    letterSpacing: 0.5,
  );

  // Caption
  static TextStyle caption = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.normal,
  );

  static TextStyle captionBold = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );

  // Overline
  static TextStyle overline = GoogleFonts.nunito(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.5,
  );

  // Label
  static TextStyle label = GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  // Price Text – no colour baked in; callers should use
  // `.copyWith(color: cs.primary)` where cs = Theme.of(context).colorScheme.
  static TextStyle priceLarge = GoogleFonts.nunito(
    fontSize: 24,
    fontWeight: FontWeight.bold,
  );

  static TextStyle priceMedium = GoogleFonts.nunito(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  static TextStyle priceSmall = GoogleFonts.nunito(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // Status Text
  static TextStyle statusSuccess = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.success,
  );

  static TextStyle statusError = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.error,
  );

  static TextStyle statusWarning = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.warning,
  );

  static TextStyle statusInfo = GoogleFonts.nunito(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.info,
  );
}

import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Premium typography system for LiquorPro mobile app
abstract class AppTypography {
  // Font families
  static const String primaryFont = 'Inter';
  static const String displayFont = 'Poppins';
  static const String codeFont = 'SF Mono';
  
  // Base font weights
  static const FontWeight thin = FontWeight.w100;
  static const FontWeight extraLight = FontWeight.w200;
  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extraBold = FontWeight.w800;
  static const FontWeight black = FontWeight.w900;
  
  // Display Styles - Large headlines and hero text
  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 40.0,
    fontWeight: extraBold,
    height: 1.1,
    letterSpacing: -0.8,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 32.0,
    fontWeight: bold,
    height: 1.2,
    letterSpacing: -0.6,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle displaySmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 28.0,
    fontWeight: bold,
    height: 1.2,
    letterSpacing: -0.4,
    color: AppColors.primaryWhite,
  );
  
  // Headline Styles - Section headers and important content
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 24.0,
    fontWeight: semiBold,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 20.0,
    fontWeight: semiBold,
    height: 1.3,
    letterSpacing: 0.0,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle headlineSmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 18.0,
    fontWeight: medium,
    height: 1.4,
    letterSpacing: 0.0,
    color: AppColors.primaryWhite,
  );
  
  // Title Styles - Card titles and subsection headers
  static const TextStyle titleLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 16.0,
    fontWeight: semiBold,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle titleMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 14.0,
    fontWeight: semiBold,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle titleSmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 12.0,
    fontWeight: medium,
    height: 1.4,
    letterSpacing: 0.2,
    color: AppColors.primaryWhite,
  );
  
  // Body Styles - Main readable content
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 16.0,
    fontWeight: regular,
    height: 1.5,
    letterSpacing: 0.0,
    color: AppColors.lightGrey,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 14.0,
    fontWeight: regular,
    height: 1.5,
    letterSpacing: 0.0,
    color: AppColors.lightGrey,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 12.0,
    fontWeight: regular,
    height: 1.4,
    letterSpacing: 0.1,
    color: AppColors.mutedWhite,
  );
  
  // Label Styles - Form labels, buttons, and UI elements
  static const TextStyle labelLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 14.0,
    fontWeight: medium,
    height: 1.3,
    letterSpacing: 0.1,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle labelMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 12.0,
    fontWeight: medium,
    height: 1.3,
    letterSpacing: 0.2,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle labelSmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 10.0,
    fontWeight: medium,
    height: 1.2,
    letterSpacing: 0.3,
    color: AppColors.mutedWhite,
  );
  
  // Special Purpose Styles
  
  // Button Text Styles
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 16.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.5,
    color: AppColors.premiumBlack,
  );
  
  static const TextStyle buttonMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 14.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.4,
    color: AppColors.premiumBlack,
  );
  
  static const TextStyle buttonSmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 12.0,
    fontWeight: medium,
    height: 1.2,
    letterSpacing: 0.3,
    color: AppColors.premiumBlack,
  );
  
  // Caption Styles - Small descriptive text
  static const TextStyle captionLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 12.0,
    fontWeight: regular,
    height: 1.3,
    letterSpacing: 0.2,
    color: AppColors.mutedWhite,
  );
  
  static const TextStyle captionMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 10.0,
    fontWeight: regular,
    height: 1.3,
    letterSpacing: 0.3,
    color: AppColors.mutedWhite,
  );
  
  static const TextStyle captionSmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 8.0,
    fontWeight: regular,
    height: 1.3,
    letterSpacing: 0.4,
    color: AppColors.hintGrey,
  );
  
  // Overline Styles - Labels above content
  static const TextStyle overlineLarge = TextStyle(
    fontFamily: primaryFont,
    fontSize: 12.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 1.0,
    color: AppColors.premiumGold,
  );
  
  static const TextStyle overlineMedium = TextStyle(
    fontFamily: primaryFont,
    fontSize: 10.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.8,
    color: AppColors.premiumGold,
  );
  
  static const TextStyle overlineSmall = TextStyle(
    fontFamily: primaryFont,
    fontSize: 8.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.6,
    color: AppColors.premiumGold,
  );
  
  // Monospace Styles - Code, numbers, and data
  static const TextStyle monoLarge = TextStyle(
    fontFamily: codeFont,
    fontSize: 14.0,
    fontWeight: regular,
    height: 1.4,
    letterSpacing: 0.0,
    color: AppColors.lightGrey,
  );
  
  static const TextStyle monoMedium = TextStyle(
    fontFamily: codeFont,
    fontSize: 12.0,
    fontWeight: regular,
    height: 1.4,
    letterSpacing: 0.0,
    color: AppColors.lightGrey,
  );
  
  static const TextStyle monoSmall = TextStyle(
    fontFamily: codeFont,
    fontSize: 10.0,
    fontWeight: regular,
    height: 1.4,
    letterSpacing: 0.0,
    color: AppColors.mutedWhite,
  );
  
  // Semantic Text Styles
  
  // Success Text
  static TextStyle get successText => bodyMedium.copyWith(
        color: AppColors.successGreen,
        fontWeight: medium,
      );
  
  // Warning Text
  static TextStyle get warningText => bodyMedium.copyWith(
        color: AppColors.warningAmber,
        fontWeight: medium,
      );
  
  // Error Text
  static TextStyle get errorText => bodyMedium.copyWith(
        color: AppColors.errorRed,
        fontWeight: medium,
      );
  
  // Info Text
  static TextStyle get infoText => bodyMedium.copyWith(
        color: AppColors.infoBlue,
        fontWeight: medium,
      );
  
  // Link Text
  static TextStyle get linkText => bodyMedium.copyWith(
        color: AppColors.premiumGold,
        fontWeight: medium,
        decoration: TextDecoration.underline,
        decorationColor: AppColors.premiumGold,
      );
  
  // Disabled Text
  static TextStyle get disabledText => bodyMedium.copyWith(
        color: AppColors.disabledGrey,
      );
  
  // Price Text Styles
  static const TextStyle priceLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 24.0,
    fontWeight: bold,
    height: 1.2,
    letterSpacing: -0.2,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle priceMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 18.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.0,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle priceSmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 14.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.0,
    color: AppColors.primaryWhite,
  );
  
  // Number Text Styles (for metrics, counts, etc.)
  static const TextStyle numberLarge = TextStyle(
    fontFamily: displayFont,
    fontSize: 32.0,
    fontWeight: extraBold,
    height: 1.1,
    letterSpacing: -0.4,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle numberMedium = TextStyle(
    fontFamily: displayFont,
    fontSize: 20.0,
    fontWeight: bold,
    height: 1.2,
    letterSpacing: -0.2,
    color: AppColors.primaryWhite,
  );
  
  static const TextStyle numberSmall = TextStyle(
    fontFamily: displayFont,
    fontSize: 16.0,
    fontWeight: semiBold,
    height: 1.2,
    letterSpacing: 0.0,
    color: AppColors.primaryWhite,
  );
  
  // Text style modifiers
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }
  
  static TextStyle withWeight(TextStyle style, FontWeight weight) {
    return style.copyWith(fontWeight: weight);
  }
  
  static TextStyle withSize(TextStyle style, double size) {
    return style.copyWith(fontSize: size);
  }
  
  static TextStyle withHeight(TextStyle style, double height) {
    return style.copyWith(height: height);
  }
  
  static TextStyle withSpacing(TextStyle style, double spacing) {
    return style.copyWith(letterSpacing: spacing);
  }
  
  static TextStyle withDecoration(TextStyle style, TextDecoration decoration) {
    return style.copyWith(decoration: decoration);
  }
  
  // Context-aware text styles
  static TextStyle getTextStyle(BuildContext context, TextStyle style) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    
    // Adjust colors based on theme
    if (style.color == AppColors.primaryWhite && !isDark) {
      return style.copyWith(color: AppColors.premiumBlack);
    } else if (style.color == AppColors.premiumBlack && isDark) {
      return style.copyWith(color: AppColors.primaryWhite);
    }
    
    return style;
  }
  
  // Text scaling for accessibility
  static TextStyle scaleForAccessibility(TextStyle style, double scaleFactor) {
    return style.copyWith(
      fontSize: (style.fontSize ?? 14.0) * scaleFactor,
    );
  }
  
  // Responsive text sizes based on screen size
  static double getResponsiveFontSize(
    BuildContext context,
    double baseFontSize, {
    double mobileScale = 1.0,
    double tabletScale = 1.2,
    double desktopScale = 1.4,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    if (screenWidth < 600) {
      return baseFontSize * mobileScale;
    } else if (screenWidth < 1024) {
      return baseFontSize * tabletScale;
    } else {
      return baseFontSize * desktopScale;
    }
  }
}
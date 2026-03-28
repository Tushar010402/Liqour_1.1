import 'package:flutter/material.dart';
import 'dart:ui';

/// iOS 16 Design Tokens - Liquid Glass Design System
///
/// Implements Apple's modern design language with translucency,
/// depth, and fluid responsiveness
class iOSDesignTokens {
  // ══════════════════════════════════════════════════════════════════════════════
  // Colors - Liquid Glass Palette
  // ══════════════════════════════════════════════════════════════════════════════

  /// Primary brand colors with iOS-style vibrancy
  static const Color primary = Color(0xFF007AFF); // iOS Blue
  static const Color primaryDark = Color(0xFF0051D5);
  static const Color primaryLight = Color(0xFF5AC8FA);

  /// Secondary accent colors
  static const Color accent = Color(0xFFFF9500); // iOS Orange
  static const Color accentGreen = Color(0xFF34C759); // iOS Green
  static const Color accentPurple = Color(0xFFAF52DE); // iOS Purple
  static const Color accentPink = Color(0xFFFF2D55); // iOS Pink

  /// Neutral colors with alpha variations
  static const Color neutralBlack = Color(0xFF000000);
  static const Color neutralGray900 = Color(0xFF1C1C1E);
  static const Color neutralGray800 = Color(0xFF2C2C2E);
  static const Color neutralGray700 = Color(0xFF3A3A3C);
  static const Color neutralGray600 = Color(0xFF48484A);
  static const Color neutralGray500 = Color(0xFF636366);
  static const Color neutralGray400 = Color(0xFF8E8E93);
  static const Color neutralGray300 = Color(0xFFC7C7CC);
  static const Color neutralGray200 = Color(0xFFD1D1D6);
  static const Color neutralGray100 = Color(0xFFE5E5EA);
  static const Color neutralGray50 = Color(0xFFF2F2F7);
  static const Color neutralWhite = Color(0xFFFFFFFF);

  /// Semantic colors
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF5AC8FA);

  /// Glass effect colors (translucent)
  static const Color glassMaterial = Color(0xFFF9F9F9);
  static final Color glassOverlay10 = neutralWhite.withOpacity(0.10);
  static final Color glassOverlay20 = neutralWhite.withOpacity(0.20);
  static final Color glassOverlay30 = neutralWhite.withOpacity(0.30);
  static final Color glassOverlay40 = neutralWhite.withOpacity(0.40);

  /// Dark mode glass overlays
  static final Color glassOverlayDark10 = neutralBlack.withOpacity(0.10);
  static final Color glassOverlayDark20 = neutralBlack.withOpacity(0.20);
  static final Color glassOverlayDark30 = neutralBlack.withOpacity(0.30);
  static final Color glassOverlayDark40 = neutralBlack.withOpacity(0.40);

  // ══════════════════════════════════════════════════════════════════════════════
  // Typography - San Francisco Font System
  // ══════════════════════════════════════════════════════════════════════════════

  static const String fontFamily = '.SF Pro Display';
  static const String fontFamilyText = '.SF Pro Text';
  static const String fontFamilyRounded = '.SF Pro Rounded';

  /// Display styles (Large text)
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
  );

  /// Headline styles
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.1,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  /// Body styles
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 17, // iOS default
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// Label styles
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamilyText,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  // ══════════════════════════════════════════════════════════════════════════════
  // Spacing System - 4pt Grid
  // ══════════════════════════════════════════════════════════════════════════════

  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // ══════════════════════════════════════════════════════════════════════════════
  // Border Radius - Rounded Corners
  // ══════════════════════════════════════════════════════════════════════════════

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusExtraLarge = 20.0;
  static const double radiusCard = 16.0;
  static const double radiusButton = 12.0;
  static const double radiusSheet = 20.0;

  static const BorderRadius borderRadiusSmall = BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius borderRadiusMedium = BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius borderRadiusLarge = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius borderRadiusCard = BorderRadius.all(Radius.circular(radiusCard));
  static const BorderRadius borderRadiusButton = BorderRadius.all(Radius.circular(radiusButton));

  // ══════════════════════════════════════════════════════════════════════════════
  // Elevation & Shadows - Subtle Depth
  // ══════════════════════════════════════════════════════════════════════════════

  static List<BoxShadow> shadowSmall = [
    BoxShadow(
      color: neutralBlack.withOpacity(0.08),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: neutralBlack.withOpacity(0.10),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowLarge = [
    BoxShadow(
      color: neutralBlack.withOpacity(0.12),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// Colored shadows for glass effect
  static List<BoxShadow> shadowGlass = [
    BoxShadow(
      color: primary.withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: neutralBlack.withOpacity(0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // ══════════════════════════════════════════════════════════════════════════════
  // Blur Effects - Glassmorphism
  // ══════════════════════════════════════════════════════════════════════════════

  static const double blurLight = 10.0;
  static const double blurMedium = 20.0;
  static const double blurHeavy = 30.0;

  static ImageFilter glassBlurLight = ImageFilter.blur(sigmaX: blurLight, sigmaY: blurLight);
  static ImageFilter glassBlurMedium = ImageFilter.blur(sigmaX: blurMedium, sigmaY: blurMedium);
  static ImageFilter glassBlurHeavy = ImageFilter.blur(sigmaX: blurHeavy, sigmaY: blurHeavy);

  // ══════════════════════════════════════════════════════════════════════════════
  // Animation Durations - Smooth Transitions
  // ══════════════════════════════════════════════════════════════════════════════

  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Duration durationSpring = Duration(milliseconds: 600);

  /// Easing curves (iOS-style)
  static const Curve curveStandard = Curves.easeInOut;
  static const Curve curveDecelerate = Curves.easeOut;
  static const Curve curveAccelerate = Curves.easeIn;
  static const Curve curveSpring = Curves.easeInOutCubic;

  // ══════════════════════════════════════════════════════════════════════════════
  // Touch Targets - Accessibility
  // ══════════════════════════════════════════════════════════════════════════════

  static const double touchTargetMin = 44.0; // Apple minimum
  static const double touchTargetComfortable = 56.0;

  // ══════════════════════════════════════════════════════════════════════════════
  // Opacity Levels - Hierarchy
  // ══════════════════════════════════════════════════════════════════════════════

  static const double opacityFull = 1.0;
  static const double opacityHigh = 0.87;
  static const double opacityMedium = 0.60;
  static const double opacityDisabled = 0.38;
  static const double opacityDivider = 0.12;
}

/// Glass Material Configuration
class GlassMaterial {
  final Color backgroundColor;
  final double backgroundOpacity;
  final double blurSigma;
  final List<BoxShadow>? shadows;
  final BorderRadius? borderRadius;

  const GlassMaterial({
    this.backgroundColor = iOSDesignTokens.neutralWhite,
    this.backgroundOpacity = 0.70,
    this.blurSigma = 20.0,
    this.shadows,
    this.borderRadius,
  });

  /// Predefined glass styles
  static const GlassMaterial light = GlassMaterial(
    backgroundColor: iOSDesignTokens.neutralWhite,
    backgroundOpacity: 0.70,
    blurSigma: 20.0,
  );

  static const GlassMaterial lightHeavy = GlassMaterial(
    backgroundColor: iOSDesignTokens.neutralWhite,
    backgroundOpacity: 0.85,
    blurSigma: 30.0,
  );

  static const GlassMaterial dark = GlassMaterial(
    backgroundColor: iOSDesignTokens.neutralGray900,
    backgroundOpacity: 0.70,
    blurSigma: 20.0,
  );

  static const GlassMaterial darkHeavy = GlassMaterial(
    backgroundColor: iOSDesignTokens.neutralGray900,
    backgroundOpacity: 0.85,
    blurSigma: 30.0,
  );
}

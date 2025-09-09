import 'package:flutter/material.dart';

/// Premium LiquorPro color system with dark theme focus
abstract class AppColors {
  // Primary Brand Colors - Premium Black & Gold
  static const Color premiumBlack = Color(0xFF000000);      // Pure Black
  static const Color deepBlack = Color(0xFF0A0A0A);         // Premium Background
  static const Color charcoalBlack = Color(0xFF1A1A1A);     // Card Background
  static const Color darkGrey = Color(0xFF2A2A2A);          // Secondary Background
  static const Color mediumGrey = Color(0xFF3A3A3A);        // Elevated Background
  
  // Text Colors - White Variations
  static const Color primaryWhite = Color(0xFFFFFFFF);      // Primary Text
  static const Color offWhite = Color(0xFFF8F8F8);          // Secondary Text
  static const Color lightGrey = Color(0xFFE0E0E0);         // Tertiary Text
  static const Color mutedWhite = Color(0xFFB0B0B0);        // Muted Text
  static const Color hintGrey = Color(0xFF666666);          // Hint Text
  static const Color disabledGrey = Color(0xFF4A4A4A);      // Disabled Text
  
  // Accent Colors - Premium Gold
  static const Color premiumGold = Color(0xFFD4AF37);       // Primary Gold
  static const Color richGold = Color(0xFFB8860B);          // Dark Gold
  static const Color lightGold = Color(0xFFE6D478);         // Light Gold
  static const Color paleGold = Color(0xFFF5E9A6);          // Pale Gold
  
  // Status Colors
  static const Color successGreen = Color(0xFF00C853);      // Success States
  static const Color warningAmber = Color(0xFFFFC107);      // Warning States
  static const Color errorRed = Color(0xFFFF5252);          // Error States
  static const Color infoBlue = Color(0xFF2196F3);          // Info States
  
  // Status Colors - Dark Variations
  static const Color darkSuccess = Color(0xFF00A048);
  static const Color darkWarning = Color(0xFFE6AC00);
  static const Color darkError = Color(0xFFE53E3E);
  static const Color darkInfo = Color(0xFF1976D2);
  
  // Background Gradients
  static const LinearGradient premiumGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [charcoalBlack, premiumBlack],
    stops: [0.0, 1.0],
  );
  
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [richGold, premiumGold, lightGold],
    stops: [0.0, 0.5, 1.0],
  );
  
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkSuccess, successGreen],
    stops: [0.0, 1.0],
  );
  
  static const LinearGradient errorGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [darkError, errorRed],
    stops: [0.0, 1.0],
  );
  
  // Surface Colors with Opacity
  static const Color surfaceLevel0 = premiumBlack;          // Base surface
  static const Color surfaceLevel1 = charcoalBlack;         // Elevated +1
  static const Color surfaceLevel2 = darkGrey;              // Elevated +2
  static const Color surfaceLevel3 = mediumGrey;            // Elevated +3
  
  // Border Colors
  static const Color primaryBorder = Color(0xFF3A3A3A);
  static const Color secondaryBorder = Color(0xFF2A2A2A);
  static const Color focusBorder = premiumGold;
  static const Color errorBorder = errorRed;
  static const Color successBorder = successGreen;
  
  // Shadow Colors
  static const Color shadowColor = Color(0x40000000);
  static const Color lightShadow = Color(0x20000000);
  static const Color mediumShadow = Color(0x60000000);
  static const Color heavyShadow = Color(0x80000000);
  
  // Overlay Colors
  static const Color overlayLight = Color(0x33FFFFFF);
  static const Color overlayMedium = Color(0x66000000);
  static const Color overlayHeavy = Color(0x99000000);
  static const Color overlayOpaque = Color(0xCC000000);
  
  // Interactive Colors
  static const Color rippleColor = Color(0x33FFFFFF);
  static const Color splashColor = Color(0x1AFFFFFF);
  static const Color highlightColor = Color(0x0DFFFFFF);
  static const Color hoverColor = Color(0x08FFFFFF);
  static const Color focusColor = Color(0x1FFFFFFF);
  
  // Category Colors (for product categories)
  static const Color whiskeyColor = Color(0xFFB8860B);
  static const Color wineColor = Color(0xFF722F37);
  static const Color beerColor = Color(0xFFDAA520);
  static const Color vodkaColor = Color(0xFF4682B4);
  static const Color rumColor = Color(0xFF8B4513);
  static const Color ginColor = Color(0xFF228B22);
  static const Color tequilaColor = Color(0xFFFF6347);
  static const Color brandyColor = Color(0xFF800080);
  
  // Chart Colors (for analytics)
  static const List<Color> chartColors = [
    premiumGold,
    successGreen,
    errorRed,
    infoBlue,
    warningAmber,
    Color(0xFF9C27B0), // Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFF9800), // Orange
    Color(0xFF607D8B), // Blue Grey
    Color(0xFF795548), // Brown
  ];
  
  // Semantic Colors
  static const Color onlineStatus = successGreen;
  static const Color offlineStatus = mutedWhite;
  static const Color busyStatus = warningAmber;
  static const Color awayStatus = Color(0xFFFF9800);
  
  // Priority Colors
  static const Color highPriority = errorRed;
  static const Color mediumPriority = warningAmber;
  static const Color lowPriority = successGreen;
  static const Color noPriority = mutedWhite;
  
  // Stock Level Colors
  static const Color inStock = successGreen;
  static const Color lowStock = warningAmber;
  static const Color outOfStock = errorRed;
  static const Color discontinuedStock = mutedWhite;
  
  // Payment Status Colors
  static const Color paidStatus = successGreen;
  static const Color pendingStatus = warningAmber;
  static const Color failedStatus = errorRed;
  static const Color refundedStatus = infoBlue;
  
  // Order Status Colors
  static const Color confirmedOrder = successGreen;
  static const Color processingOrder = warningAmber;
  static const Color shippedOrder = infoBlue;
  static const Color deliveredOrder = Color(0xFF4CAF50);
  static const Color cancelledOrder = errorRed;
  
  // Alpha Variations for Common Uses
  static Color get premiumBlackAlpha10 => premiumBlack.withOpacity(0.1);
  static Color get premiumBlackAlpha20 => premiumBlack.withOpacity(0.2);
  static Color get premiumBlackAlpha30 => premiumBlack.withOpacity(0.3);
  static Color get premiumBlackAlpha50 => premiumBlack.withOpacity(0.5);
  static Color get premiumBlackAlpha70 => premiumBlack.withOpacity(0.7);
  static Color get premiumBlackAlpha90 => premiumBlack.withOpacity(0.9);
  
  static Color get premiumGoldAlpha10 => premiumGold.withOpacity(0.1);
  static Color get premiumGoldAlpha20 => premiumGold.withOpacity(0.2);
  static Color get premiumGoldAlpha30 => premiumGold.withOpacity(0.3);
  static Color get premiumGoldAlpha50 => premiumGold.withOpacity(0.5);
  static Color get premiumGoldAlpha70 => premiumGold.withOpacity(0.7);
  static Color get premiumGoldAlpha90 => premiumGold.withOpacity(0.9);
  
  static Color get primaryWhiteAlpha10 => primaryWhite.withOpacity(0.1);
  static Color get primaryWhiteAlpha20 => primaryWhite.withOpacity(0.2);
  static Color get primaryWhiteAlpha30 => primaryWhite.withOpacity(0.3);
  static Color get primaryWhiteAlpha50 => primaryWhite.withOpacity(0.5);
  static Color get primaryWhiteAlpha70 => primaryWhite.withOpacity(0.7);
  static Color get primaryWhiteAlpha90 => primaryWhite.withOpacity(0.9);
  
  // Theme-specific color getters
  static Color getBackgroundColor(Brightness brightness) {
    return brightness == Brightness.dark ? premiumBlack : primaryWhite;
  }
  
  static Color getSurfaceColor(Brightness brightness) {
    return brightness == Brightness.dark ? charcoalBlack : offWhite;
  }
  
  static Color getTextColor(Brightness brightness) {
    return brightness == Brightness.dark ? primaryWhite : premiumBlack;
  }
  
  static Color getSecondaryTextColor(Brightness brightness) {
    return brightness == Brightness.dark ? lightGrey : darkGrey;
  }
  
  static Color getBorderColor(Brightness brightness) {
    return brightness == Brightness.dark ? primaryBorder : Color(0xFFE0E0E0);
  }

  // Common theme aliases for easier access
  static const Color primary = premiumGold;
  static const Color accent = lightGold;
  static const Color surface = charcoalBlack;
  static const Color background = premiumBlack;
  static const Color error = errorRed;
  static const Color success = successGreen;
  static const Color warning = warningAmber;
  static const Color info = infoBlue;
  static const Color textPrimary = primaryWhite;
  static const Color textSecondary = lightGrey;
  static const Color textTertiary = mutedWhite;
  static const Color border = primaryBorder;
  static const Color shadow = shadowColor;
  static const Color cardBackground = charcoalBlack;
  static const Color inputBackground = darkGrey;

  // Dark theme variants
  static const Color backgroundDark = premiumBlack;
  static const Color surfaceDark = charcoalBlack;
  static const Color cardBackgroundDark = charcoalBlack;
  static const Color inputBackgroundDark = darkGrey;
  static const Color textPrimaryDark = primaryWhite;
  static const Color textSecondaryDark = lightGrey;
  static const Color borderDark = primaryBorder;

  // Shimmer colors for loading states
  static const Color shimmerBase = Color(0xFF2A2A2A);
  static const Color shimmerHighlight = Color(0xFF3A3A3A);
}
import 'package:flutter/material.dart';

/// Responsive breakpoints for the app
class ResponsiveBreakpoints {
  static const double phone = 600;
  static const double tablet = 1200;
  static const double desktop = 1800;
}

/// Device type enum for responsive design
enum DeviceType {
  phone,
  tablet,
  desktop,
}

/// Responsive utilities for adaptive layouts
class ResponsiveUtils {
  /// Get the current device type based on screen width
  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (width < ResponsiveBreakpoints.phone) {
      return DeviceType.phone;
    } else if (width < ResponsiveBreakpoints.tablet) {
      return DeviceType.tablet;
    } else {
      return DeviceType.desktop;
    }
  }

  /// Check if the current device is a phone
  static bool isPhone(BuildContext context) {
    return getDeviceType(context) == DeviceType.phone;
  }

  /// Check if the current device is a tablet
  static bool isTablet(BuildContext context) {
    return getDeviceType(context) == DeviceType.tablet;
  }

  /// Check if the current device is a desktop
  static bool isDesktop(BuildContext context) {
    return getDeviceType(context) == DeviceType.desktop;
  }

  /// Check if the current device is at least a tablet
  static bool isLargeScreen(BuildContext context) {
    final type = getDeviceType(context);
    return type == DeviceType.tablet || type == DeviceType.desktop;
  }

  /// Get responsive value based on device type
  static T getValue<T>({
    required BuildContext context,
    required T phone,
    T? tablet,
    T? desktop,
  }) {
    final deviceType = getDeviceType(context);

    switch (deviceType) {
      case DeviceType.phone:
        return phone;
      case DeviceType.tablet:
        return tablet ?? phone;
      case DeviceType.desktop:
        return desktop ?? tablet ?? phone;
    }
  }

  /// Get responsive padding
  static EdgeInsetsGeometry getPadding(BuildContext context) {
    return EdgeInsets.all(
      getValue(
        context: context,
        phone: 24.0,
        tablet: 48.0,
        desktop: 64.0,
      ),
    );
  }

  /// Get responsive horizontal padding
  static EdgeInsetsGeometry getHorizontalPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: getValue(
        context: context,
        phone: 24.0,
        tablet: 48.0,
        desktop: 64.0,
      ),
    );
  }

  /// Get responsive vertical padding
  static EdgeInsetsGeometry getVerticalPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      vertical: getValue(
        context: context,
        phone: 16.0,
        tablet: 24.0,
        desktop: 32.0,
      ),
    );
  }

  /// Get max content width for centered layouts
  static double getMaxContentWidth(BuildContext context) {
    return getValue(
      context: context,
      phone: double.infinity,
      tablet: 600.0,
      desktop: 800.0,
    );
  }

  /// Get responsive spacing
  static double getSpacing(BuildContext context) {
    return getValue(
      context: context,
      phone: 16.0,
      tablet: 24.0,
      desktop: 32.0,
    );
  }

  /// Get responsive OTP field dimensions
  static Size getOtpFieldSize(BuildContext context) {
    if (isPhone(context)) {
      return const Size(48, 56);
    } else if (isTablet(context)) {
      return const Size(64, 72);
    } else {
      return const Size(72, 80);
    }
  }

  /// Get responsive OTP field spacing
  static double getOtpFieldSpacing(BuildContext context) {
    return getValue(
      context: context,
      phone: 8.0,
      tablet: 16.0,
      desktop: 20.0,
    );
  }

  /// Get responsive button height
  static double getButtonHeight(BuildContext context) {
    return getValue(
      context: context,
      phone: 56.0,
      tablet: 64.0,
      desktop: 72.0,
    );
  }

  /// Get responsive font scale
  static double getFontScale(BuildContext context) {
    return getValue(
      context: context,
      phone: 1.0,
      tablet: 1.1,
      desktop: 1.2,
    );
  }

  /// Get responsive border radius
  static double getBorderRadius(BuildContext context) {
    return getValue(
      context: context,
      phone: 12.0,
      tablet: 16.0,
      desktop: 20.0,
    );
  }

  /// Get responsive icon size
  static double getIconSize(BuildContext context) {
    return getValue(
      context: context,
      phone: 24.0,
      tablet: 28.0,
      desktop: 32.0,
    );
  }
}

/// Extension for easier access to responsive utilities
extension ResponsiveContext on BuildContext {
  DeviceType get deviceType => ResponsiveUtils.getDeviceType(this);
  bool get isPhone => ResponsiveUtils.isPhone(this);
  bool get isTablet => ResponsiveUtils.isTablet(this);
  bool get isDesktop => ResponsiveUtils.isDesktop(this);
  bool get isLargeScreen => ResponsiveUtils.isLargeScreen(this);

  EdgeInsetsGeometry get responsivePadding => ResponsiveUtils.getPadding(this);
  EdgeInsetsGeometry get responsiveHorizontalPadding => ResponsiveUtils.getHorizontalPadding(this);
  EdgeInsetsGeometry get responsiveVerticalPadding => ResponsiveUtils.getVerticalPadding(this);

  double get maxContentWidth => ResponsiveUtils.getMaxContentWidth(this);
  double get responsiveSpacing => ResponsiveUtils.getSpacing(this);

  Size get otpFieldSize => ResponsiveUtils.getOtpFieldSize(this);
  double get otpFieldSpacing => ResponsiveUtils.getOtpFieldSpacing(this);

  double get buttonHeight => ResponsiveUtils.getButtonHeight(this);
  double get fontScale => ResponsiveUtils.getFontScale(this);
  double get borderRadius => ResponsiveUtils.getBorderRadius(this);
  double get iconSize => ResponsiveUtils.getIconSize(this);
}
import 'package:flutter/services.dart';

/// Haptic Feedback Helper - Best Practice Utility
/// Centralized haptic feedback management for consistent UX
class HapticFeedbackHelper {
  // Private constructor to prevent instantiation
  HapticFeedbackHelper._();

  /// Light impact - For subtle interactions
  /// Use for: Selections, toggles, switches
  static Future<void> light() async {
    await HapticFeedback.lightImpact();
  }

  /// Medium impact - For standard interactions
  /// Use for: Button taps, list item selections, confirmations
  static Future<void> medium() async {
    await HapticFeedback.mediumImpact();
  }

  /// Heavy impact - For important actions
  /// Use for: Deletions, critical actions, alerts
  static Future<void> heavy() async {
    await HapticFeedback.heavyImpact();
  }

  /// Selection click - For picker changes
  /// Use for: Dropdown selections, picker wheel scrolling
  static Future<void> selection() async {
    await HapticFeedback.selectionClick();
  }

  /// Vibrate - For notifications
  /// Use for: Success messages, errors, warnings
  static Future<void> vibrate() async {
    await HapticFeedback.vibrate();
  }

  /// Success feedback - Custom pattern for success
  static Future<void> success() async {
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.lightImpact();
  }

  /// Error feedback - Custom pattern for errors
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
  }

  /// Warning feedback - Custom pattern for warnings
  static Future<void> warning() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await HapticFeedback.mediumImpact();
  }
}

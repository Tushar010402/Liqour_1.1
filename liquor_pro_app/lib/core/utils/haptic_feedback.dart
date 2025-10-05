import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/preferences_service.dart';
import 'logger.dart';

/// Haptic Feedback Utility - Industrial-grade tactile feedback
/// Provides consistent haptic feedback across the app
class HapticFeedbackUtil {
  static bool _enabled = true;

  /// Initialize haptic feedback settings
  static Future<void> init() async {
    try {
      final prefs = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefs);
      _enabled = userPrefs.isHapticFeedbackEnabled();
      Logger.info('Haptic feedback enabled: $_enabled');
    } catch (e) {
      Logger.error('Failed to initialize haptic feedback', e);
    }
  }

  /// Enable haptic feedback
  static Future<void> enable() async {
    _enabled = true;
    try {
      final prefs = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefs);
      await userPrefs.setHapticFeedback(true);
    } catch (e) {
      Logger.error('Failed to enable haptic feedback', e);
    }
  }

  /// Disable haptic feedback
  static Future<void> disable() async {
    _enabled = false;
    try {
      final prefs = await PreferencesService.getInstance();
      final userPrefs = UserPreferences(prefs);
      await userPrefs.setHapticFeedback(false);
    } catch (e) {
      Logger.error('Failed to disable haptic feedback', e);
    }
  }

  /// Check if haptic feedback is enabled
  static bool get isEnabled => _enabled;

  // ==================== Feedback Types ====================

  /// Light impact - For subtle interactions
  /// Use for: Selecting items, toggling switches
  static Future<void> lightImpact() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (e) {
      Logger.error('Light impact haptic failed', e);
    }
  }

  /// Medium impact - For standard interactions
  /// Use for: Button presses, confirmations
  static Future<void> mediumImpact() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (e) {
      Logger.error('Medium impact haptic failed', e);
    }
  }

  /// Heavy impact - For significant interactions
  /// Use for: Completing tasks, major state changes
  static Future<void> heavyImpact() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (e) {
      Logger.error('Heavy impact haptic failed', e);
    }
  }

  /// Selection click - For picker/selector changes
  /// Use for: Scrolling through pickers, selecting from lists
  static Future<void> selectionClick() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (e) {
      Logger.error('Selection click haptic failed', e);
    }
  }

  /// Vibrate - For alerts and notifications
  /// Use for: Errors, warnings, important notifications
  static Future<void> vibrate() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.vibrate();
    } catch (e) {
      Logger.error('Vibrate haptic failed', e);
    }
  }

  // ==================== Contextual Feedback ====================

  /// Feedback for successful actions
  static Future<void> success() async {
    await heavyImpact();
  }

  /// Feedback for errors
  static Future<void> error() async {
    await vibrate();
  }

  /// Feedback for warnings
  static Future<void> warning() async {
    await mediumImpact();
  }

  /// Feedback for button tap
  static Future<void> buttonTap() async {
    await lightImpact();
  }

  /// Feedback for toggle switch
  static Future<void> toggle() async {
    await lightImpact();
  }

  /// Feedback for selection change
  static Future<void> selection() async {
    await selectionClick();
  }

  /// Feedback for long press
  static Future<void> longPress() async {
    await mediumImpact();
  }

  /// Feedback for drag start
  static Future<void> dragStart() async {
    await lightImpact();
  }

  /// Feedback for drag end
  static Future<void> dragEnd() async {
    await mediumImpact();
  }

  /// Feedback for delete action
  static Future<void> delete() async {
    await heavyImpact();
  }

  /// Feedback for refresh
  static Future<void> refresh() async {
    await mediumImpact();
  }

  /// Feedback for navigation
  static Future<void> navigate() async {
    await lightImpact();
  }

  /// Feedback for form submission
  static Future<void> submit() async {
    await mediumImpact();
  }

  /// Feedback for item added to cart/selection
  static Future<void> add() async {
    await lightImpact();
  }

  /// Feedback for item removed from cart/selection
  static Future<void> remove() async {
    await lightImpact();
  }
}

/// Haptic Extension on Widgets
/// Allows easy haptic feedback on tap gestures
extension HapticGesture on Widget {
  /// Wrap widget with haptic feedback on tap
  Widget withHaptic({
    required VoidCallback onTap,
    HapticType type = HapticType.light,
  }) {
    return GestureDetector(
      onTap: () async {
        await _triggerHaptic(type);
        onTap();
      },
      child: this,
    );
  }

  /// Trigger haptic feedback based on type
  Future<void> _triggerHaptic(HapticType type) async {
    switch (type) {
      case HapticType.light:
        await HapticFeedbackUtil.lightImpact();
        break;
      case HapticType.medium:
        await HapticFeedbackUtil.mediumImpact();
        break;
      case HapticType.heavy:
        await HapticFeedbackUtil.heavyImpact();
        break;
      case HapticType.selection:
        await HapticFeedbackUtil.selectionClick();
        break;
      case HapticType.vibrate:
        await HapticFeedbackUtil.vibrate();
        break;
    }
  }
}

/// Haptic feedback types
enum HapticType {
  light,
  medium,
  heavy,
  selection,
  vibrate,
}

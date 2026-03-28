/// Animation Constants - Best Practice Animation Timings
/// Centralized animation configuration for consistent UX
library;

class AnimationConstants {
  // Private constructor
  AnimationConstants._();

  // ==================== Duration Constants ====================

  /// Extra fast - For instant feedback
  static const Duration extraFast = Duration(milliseconds: 100);

  /// Fast - For quick transitions
  static const Duration fast = Duration(milliseconds: 200);

  /// Standard - For normal animations
  static const Duration standard = Duration(milliseconds: 300);

  /// Moderate - For moderate animations
  static const Duration moderate = Duration(milliseconds: 400);

  /// Slow - For emphasis animations
  static const Duration slow = Duration(milliseconds: 500);

  /// Page transition - For screen transitions
  static const Duration pageTransition = Duration(milliseconds: 350);

  // ==================== Delay Constants ====================

  /// Stagger delay for list items
  static const Duration staggerDelay = Duration(milliseconds: 50);

  /// Short delay before animation
  static const Duration shortDelay = Duration(milliseconds: 100);

  /// Medium delay before animation
  static const Duration mediumDelay = Duration(milliseconds: 200);

  /// Long delay before animation
  static const Duration longDelay = Duration(milliseconds: 300);

  // ==================== Specific Use Cases ====================

  /// Button press animation
  static const Duration buttonPress = Duration(milliseconds: 150);

  /// Card flip animation
  static const Duration cardFlip = Duration(milliseconds: 600);

  /// Shimmer loading animation
  static const Duration shimmer = Duration(milliseconds: 1500);

  /// Ripple effect duration
  static const Duration ripple = Duration(milliseconds: 300);

  /// FAB animation
  static const Duration fab = Duration(milliseconds: 250);

  /// Bottom sheet animation
  static const Duration bottomSheet = Duration(milliseconds: 400);

  /// Dialog animation
  static const Duration dialog = Duration(milliseconds: 300);

  /// Snackbar animation
  static const Duration snackbar = Duration(milliseconds: 250);

  // ==================== Curve Constants ====================

  /// Standard ease curve
  static const standardCurve = 'easeInOut';

  /// Bounce curve
  static const bounceCurve = 'elasticOut';

  /// Fast out, slow in
  static const emphasizedCurve = 'fastOutSlowIn';

  // ==================== Helper Methods ====================

  /// Get delay for staggered animations
  static Duration getStaggerDelay(int index, {int baseDelay = 50}) {
    return Duration(milliseconds: baseDelay * index);
  }

  /// Calculate total duration with delay
  static Duration withDelay(Duration duration, Duration delay) {
    return Duration(milliseconds: duration.inMilliseconds + delay.inMilliseconds);
  }
}

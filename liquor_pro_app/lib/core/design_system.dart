/// Design System Barrel File
/// Import this file for canonical access to all design tokens.
///
/// Usage:
///   import 'package:liquor_pro_app/core/design_system.dart';
///
/// This provides:
/// - AppColors: Color palette
/// - AppTextStyles: Typography
/// - AppTheme: Theme data (light theme)
/// - AnimationConstants: Animation timings
/// - Spacing, Radii, FontSizes, IconSizes: Layout constants
library;
export 'constants/app_colors.dart';
export 'constants/app_text_styles.dart';
export 'constants/animation_constants.dart';
export 'constants/performance_constants.dart'
    show
        NetworkTimeouts,
        CacheDurations,
        Spacing,
        Radii,
        IconSizes,
        FontSizes,
        Limits,
        ValidationLimits;
export 'theme/app_theme.dart';

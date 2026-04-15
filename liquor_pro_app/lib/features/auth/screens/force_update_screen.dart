import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/models/app_version_config.dart';
import '../../../core/services/app_version_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/responsive_utils.dart';

/// Full-screen, non-dismissible update gate.
/// Blocks the app entirely when version is too old or maintenance mode is active.
class ForceUpdateScreen extends StatefulWidget {
  final AppVersionConfig? config;
  final String currentVersion;
  final bool isMaintenance;

  const ForceUpdateScreen({
    super.key,
    this.config,
    required this.currentVersion,
    this.isMaintenance = false,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Animated scale-in for icon
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );
    _scaleController.forward();

    // Haptic feedback on appear
    HapticFeedbackUtil.heavyImpact();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    AppVersionService.instance.resetForceUpdateFlag();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = ResponsiveUtils.getValue(
      context: context,
      phone: 80.0,
      tablet: 100.0,
      desktop: 120.0,
    );

    final titleFontSize = ResponsiveUtils.getValue(
      context: context,
      phone: 28.0,
      tablet: 36.0,
      desktop: 42.0,
    );

    final bodyFontSize = ResponsiveUtils.getValue(
      context: context,
      phone: 15.0,
      tablet: 18.0,
      desktop: 20.0,
    );

    final buttonHeight = ResponsiveUtils.getValue(
      context: context,
      phone: 56.0,
      tablet: 64.0,
      desktop: 72.0,
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated icon
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Icon(
                        widget.isMaintenance
                            ? Icons.construction_rounded
                            : Icons.system_update_rounded,
                        size: iconSize,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Title
                    Text(
                      widget.isMaintenance
                          ? 'Under Maintenance'
                          : 'Update Required',
                      style: AppTextStyles.h1.copyWith(
                        color: Colors.white,
                        fontSize: titleFontSize,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),

                    // Description
                    Text(
                      widget.isMaintenance
                          ? (widget.config?.maintenanceMessage?.isNotEmpty == true
                              ? widget.config!.maintenanceMessage!
                              : 'We\'re performing scheduled maintenance to improve your experience. We\'ll be back soon.')
                          : 'A new version of LiquorPro is available with important updates and improvements.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: bodyFontSize,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Version info (only for update, not maintenance)
                    if (!widget.isMaintenance) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Current: ${widget.currentVersion}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                        ),
                      ),
                      if (widget.config?.minVersion != null)
                        Text(
                          'Required: ${widget.config!.minVersion}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                    ],

                    const SizedBox(height: 40),

                    // Action button
                    if (!widget.isMaintenance)
                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedbackUtil.mediumImpact();
                            AppVersionService.instance.launchStoreUrl();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Update Now',
                                style: AppTextStyles.button.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Maintenance: "We'll be back soon" indicator
                    if (widget.isMaintenance) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'We\'ll be back soon',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: bodyFontSize,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

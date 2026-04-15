import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../models/app_version_config.dart';
import '../services/app_version_service.dart';
import '../utils/haptic_feedback.dart';

/// Show the soft update dialog. Call this as a static helper.
void showSoftUpdateDialog({
  required BuildContext context,
  required AppVersionConfig config,
  required VoidCallback onSkip,
}) {
  HapticFeedbackUtil.lightImpact();
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _SoftUpdateDialog(
      config: config,
      onSkip: () {
        onSkip();
        Navigator.of(ctx).pop();
      },
      onUpdate: () {
        Navigator.of(ctx).pop();
        AppVersionService.instance.launchStoreUrl();
      },
    ),
  );
}

class _SoftUpdateDialog extends StatelessWidget {
  final AppVersionConfig config;
  final VoidCallback onSkip;
  final VoidCallback onUpdate;

  const _SoftUpdateDialog({
    required this.config,
    required this.onSkip,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Row(
        children: [
          Icon(
            Icons.system_update_rounded,
            color: AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Text(
            'Update Available',
            style: AppTextStyles.h3.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version ${config.latestVersion} is available.',
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (config.releaseNotes != null &&
              config.releaseNotes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              config.releaseNotes!,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            HapticFeedbackUtil.lightImpact();
            onSkip();
          },
          child: Text(
            'Later',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            HapticFeedbackUtil.mediumImpact();
            onUpdate();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            'Update',
            style: AppTextStyles.button.copyWith(
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

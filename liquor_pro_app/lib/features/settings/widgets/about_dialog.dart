import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';

/// About LiquorPro Dialog
void showAboutAppDialog(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      contentPadding: EdgeInsets.zero,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Logo
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.local_bar,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'LiquorPro',
                    style: AppTextStyles.h3.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version 1.0.0',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: AppTextStyles.h5.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'LiquorPro is a comprehensive liquor store management solution designed to streamline your business operations. Manage inventory, track sales, handle customers, and analyze your business performance all in one place.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Features
                  Text(
                    'Key Features',
                    style: AppTextStyles.h5.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem('📦 Complete Inventory Management', cs),
                  _buildFeatureItem('💰 Point of Sale (POS) System', cs),
                  _buildFeatureItem('📊 Sales & Analytics Reports', cs),
                  _buildFeatureItem('👥 Customer Management', cs),
                  _buildFeatureItem('🏪 Multi-Shop Support', cs),
                  _buildFeatureItem('💵 Expense Tracking', cs),
                  _buildFeatureItem('🔒 Secure & Reliable', cs),
                  const SizedBox(height: 24),

                  // Credits
                  Text(
                    'Developed By',
                    style: AppTextStyles.h5.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'LiquorPro Development Team',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '© 2025 All rights reserved',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () {
                          // TODO: Open privacy policy
                        },
                        child: const Text('Privacy Policy'),
                      ),
                      Container(
                        width: 1,
                        height: 20,
                        color: cs.outlineVariant,
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: Open terms of service
                        },
                        child: const Text('Terms of Service'),
                      ),
                    ],
                  ),

                  // Website
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        // TODO: Open website
                      },
                      icon: const Icon(Icons.language, size: 18),
                      label: const Text('www.liquorpro.com'),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _buildFeatureItem(String text, ColorScheme cs) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        const Icon(
          Icons.check_circle,
          size: 18,
          color: AppColors.success,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Help & Support Screen
class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Help & Support',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Contact Support Card
          Card(
            color: AppColors.primary.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.support_agent,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Need Help?',
                    style: AppTextStyles.h4.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Our support team is here to help you',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Open email client
                          },
                          icon: const Icon(Icons.email_outlined),
                          label: const Text('Email'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Open phone dialer
                          },
                          icon: const Icon(Icons.phone_outlined),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Quick Help Section
          Text(
            'Quick Help',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),

          _buildHelpTile(
            icon: Icons.shopping_cart_outlined,
            title: 'How to make a sale?',
            onTap: () {
              _showHelpDialog(
                context,
                'Making a Sale',
                'To make a sale:\n\n'
                '1. Go to Dashboard\n'
                '2. Tap "New Sale" quick action\n'
                '3. Select products from the list\n'
                '4. Adjust quantities as needed\n'
                '5. Choose the shop location\n'
                '6. Tap "Checkout" to complete',
              );
            },
          ),

          _buildHelpTile(
            icon: Icons.inventory_outlined,
            title: 'How to add products?',
            onTap: () {
              _showHelpDialog(
                context,
                'Adding Products',
                'To add a new product:\n\n'
                '1. Go to Inventory tab\n'
                '2. Navigate to Products section\n'
                '3. Tap the + button at the bottom\n'
                '4. Fill in product details\n'
                '5. Set pricing and stock levels\n'
                '6. Tap "Save" to create',
              );
            },
          ),

          _buildHelpTile(
            icon: Icons.store_outlined,
            title: 'How to manage shops?',
            onTap: () {
              _showHelpDialog(
                context,
                'Managing Shops',
                'To manage your shops:\n\n'
                '1. Go to Settings tab\n'
                '2. Tap "Manage Shops"\n'
                '3. View all your shop locations\n'
                '4. Tap + to add new shop\n'
                '5. Fill in shop details and license info\n'
                '6. Set shop status (Active/Inactive)',
              );
            },
          ),

          _buildHelpTile(
            icon: Icons.assessment_outlined,
            title: 'How to view reports?',
            onTap: () {
              _showHelpDialog(
                context,
                'Viewing Reports',
                'To view reports:\n\n'
                '1. Go to Dashboard\n'
                '2. Tap "Reports" quick action\n'
                '3. Choose report type:\n'
                '   • Sales Analytics\n'
                '   • Inventory Reports\n'
                '   • Finance Reports\n'
                '4. Filter by time period\n'
                '5. View charts and statistics',
              );
            },
          ),

          _buildHelpTile(
            icon: Icons.people_outlined,
            title: 'How to add customers?',
            onTap: () {
              _showHelpDialog(
                context,
                'Adding Customers',
                'To add a customer:\n\n'
                '1. Tap "Customers" from dashboard\n'
                '2. Tap the "Add Customer" button\n'
                '3. Enter customer details:\n'
                '   • Name (required)\n'
                '   • Phone (required)\n'
                '   • Email (optional)\n'
                '   • Address (optional)\n'
                '4. Tap "Add" to save',
              );
            },
          ),

          const SizedBox(height: 24),

          // FAQs Section
          Text(
            'Frequently Asked Questions',
            style: AppTextStyles.h5,
          ),
          const SizedBox(height: 12),

          _buildExpandableTile(
            title: 'How do I reset my password?',
            content: 'Go to Settings > Security > Change Password. '
                'Enter your current password and set a new one.',
          ),

          _buildExpandableTile(
            title: 'Can I manage multiple shops?',
            content: 'Yes! LiquorPro supports multi-shop management. '
                'Add and manage all your shop locations from Settings > Manage Shops.',
          ),

          _buildExpandableTile(
            title: 'How do I track inventory?',
            content: 'Navigate to the Inventory tab to view all products, '
                'stock levels, categories, and brands. You can adjust stock '
                'from the Stock tab.',
          ),

          _buildExpandableTile(
            title: 'How do I export reports?',
            content: 'Currently, reports can be viewed in-app. Export functionality '
                'will be available in the next update.',
          ),

          _buildExpandableTile(
            title: 'Is my data secure?',
            content: 'Yes! All your data is encrypted and securely stored. '
                'We use industry-standard security practices to protect your information.',
          ),

          const SizedBox(height: 24),

          // Contact Information
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact Information',
                    style: AppTextStyles.h5,
                  ),
                  const Divider(height: 24),
                  _buildContactInfo(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: 'support@liquorpro.com',
                  ),
                  const SizedBox(height: 12),
                  _buildContactInfo(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: '+91 1800-XXX-XXXX',
                  ),
                  const SizedBox(height: 12),
                  _buildContactInfo(
                    icon: Icons.access_time,
                    label: 'Support Hours',
                    value: 'Mon-Sat, 9 AM - 6 PM IST',
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Video Tutorials
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Open video tutorials
            },
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('Watch Video Tutorials'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 12),

          // User Guide
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Open user guide PDF
            },
            icon: const Icon(Icons.menu_book_outlined),
            label: const Text('Download User Guide'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(
          title,
          style: AppTextStyles.bodyMedium,
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }

  Widget _buildExpandableTile({
    required String title,
    required String content,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactInfo({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showHelpDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

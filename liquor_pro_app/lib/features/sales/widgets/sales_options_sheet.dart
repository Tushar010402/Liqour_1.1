import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../screens/daily_sales_entry_screen.dart';
import '../screens/simple_sales_history.dart';
import '../screens/daily_sales_screen.dart';
import '../screens/smart_sale_screen.dart';

/// Sales options bottom sheet - Settings-style with uniform icons
class SalesOptionsSheet extends StatelessWidget {
  const SalesOptionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(iOSDesignTokens.radiusSheet)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            iOSDesignTokens.space16,
            0,
            iOSDesignTokens.space16,
            iOSDesignTokens.space12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Title row
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.primary,
                          cs.primary.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.point_of_sale_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: iOSDesignTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sales',
                          style: AppTextStyles.h5.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Manage daily sales & reports',
                          style: AppTextStyles.caption.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: iOSDesignTokens.space20),

              // Options - Settings-style tiles
              _buildSettingTile(
                context: context,
                icon: Icons.edit_note_outlined,
                title: 'Daily Entry',
                subtitle: 'Record today\'s sales transactions',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const DailySalesEntryScreen(showHeader: true),
                    ),
                  );
                },
              ),

              _buildSettingTile(
                context: context,
                icon: Icons.history_outlined,
                title: 'History',
                subtitle: 'View past sales & details',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('History'),
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          iconTheme: IconThemeData(
                              color: Theme.of(context).colorScheme.onSurface),
                          titleTextStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        body: const SimpleSalesHistory(),
                      ),
                    ),
                  );
                },
              ),

              _buildSettingTile(
                context: context,
                icon: Icons.bar_chart_outlined,
                title: 'Reports',
                subtitle: 'Sales analytics & insights',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('Reports'),
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          iconTheme: IconThemeData(
                              color: Theme.of(context).colorScheme.onSurface),
                          titleTextStyle: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        body: const DailySalesScreen(),
                      ),
                    ),
                  );
                },
              ),

              _buildSettingTile(
                context: context,
                icon: Icons.document_scanner_outlined,
                title: 'Smart Sale',
                subtitle: 'Quick entry with OCR scanning',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SmartSaleScreen(),
                    ),
                  );
                },
              ),

              SizedBox(height: iOSDesignTokens.space8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: iOSDesignTokens.space12,
              vertical: iOSDesignTokens.space12,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border:
                  Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.15),
                        color.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.caption
                            .copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper function to show the Sales options sheet
void showSalesOptionsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const SalesOptionsSheet(),
  );
}

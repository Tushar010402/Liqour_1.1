import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../core/widgets/glass_card.dart';

/// UserStatsCard - Dashboard card showing user statistics
///
/// Features:
/// - Total, active, inactive counts
/// - Animated number counters
/// - Role distribution
/// - Tap to filter
///
/// Usage:
/// ```dart
/// UserStatsCard(
///   totalUsers: 42,
///   activeUsers: 38,
///   inactiveUsers: 4,
///   onTapTotal: () => clearFilter(),
///   onTapActive: () => filterByStatus(true),
///   onTapInactive: () => filterByStatus(false),
/// )
/// ```
class UserStatsCard extends StatelessWidget {
  final int totalUsers;
  final int activeUsers;
  final int inactiveUsers;
  final Map<String, int>? roleDistribution;
  final VoidCallback? onTapTotal;
  final VoidCallback? onTapActive;
  final VoidCallback? onTapInactive;
  final bool isLoading;

  const UserStatsCard({
    super.key,
    required this.totalUsers,
    required this.activeUsers,
    required this.inactiveUsers,
    this.roleDistribution,
    this.onTapTotal,
    this.onTapActive,
    this.onTapInactive,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = ResponsiveUtils.isPhone(context);

    if (isLoading) {
      return _buildLoadingSkeleton(isPhone);
    }

    return GlassCard.heavy(
      padding: EdgeInsets.all(isPhone ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iOSDesignTokens.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.person_2_fill,
                  color: iOSDesignTokens.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Overview',
                      style: iOSDesignTokens.headlineSmall.copyWith(
                        color: iOSDesignTokens.neutralGray900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Manage team members and roles',
                      style: iOSDesignTokens.labelSmall.copyWith(
                        color: iOSDesignTokens.neutralGray500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  value: totalUsers,
                  label: 'Total',
                  color: iOSDesignTokens.primary,
                  icon: CupertinoIcons.person_2_fill,
                  onTap: onTapTotal,
                ),
              ),
              _VerticalDivider(),
              Expanded(
                child: _StatItem(
                  value: activeUsers,
                  label: 'Active',
                  color: iOSDesignTokens.success,
                  icon: CupertinoIcons.checkmark_circle_fill,
                  onTap: onTapActive,
                ),
              ),
              _VerticalDivider(),
              Expanded(
                child: _StatItem(
                  value: inactiveUsers,
                  label: 'Inactive',
                  color: iOSDesignTokens.neutralGray400,
                  icon: CupertinoIcons.pause_circle_fill,
                  onTap: onTapInactive,
                ),
              ),
            ],
          ),

          // Role distribution (if provided)
          if (roleDistribution != null && roleDistribution!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _RoleDistributionBar(distribution: roleDistribution!),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton(bool isPhone) {
    return GlassCard.heavy(
      padding: EdgeInsets.all(isPhone ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iOSDesignTokens.neutralGray200,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: iOSDesignTokens.neutralGray200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 180,
                      height: 12,
                      decoration: BoxDecoration(
                        color: iOSDesignTokens.neutralGray100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: List.generate(
              3,
              (index) => Expanded(
                child: Container(
                  height: 60,
                  margin: EdgeInsets.only(left: index > 0 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: iOSDesignTokens.neutralGray100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: value),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, animatedValue, child) {
            return Text(
              animatedValue.toString(),
              style: iOSDesignTokens.displayMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color.withOpacity(0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: iOSDesignTokens.labelSmall.copyWith(
                color: iOSDesignTokens.neutralGray600,
              ),
            ),
          ],
        ),
      ],
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: content,
          ),
        ),
      );
    }

    return content;
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      color: iOSDesignTokens.neutralGray200,
    );
  }
}

class _RoleDistributionBar extends StatelessWidget {
  final Map<String, int> distribution;

  const _RoleDistributionBar({required this.distribution});

  static const Map<String, Color> _roleColors = {
    'admin': Color(0xFFFF3B30),
    'manager': Color(0xFF007AFF),
    'assistant_manager': Color(0xFFFF9500),
    'executive': Color(0xFFAF52DE),
    'salesman': Color(0xFF34C759),
    'saas_admin': Color(0xFF5856D6),
  };

  @override
  Widget build(BuildContext context) {
    final total = distribution.values.fold(0, (sum, count) => sum + count);
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role Distribution',
          style: iOSDesignTokens.labelSmall.copyWith(
            color: iOSDesignTokens.neutralGray500,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: distribution.entries.map((entry) {
              final percentage = entry.value / total;
              final color = _roleColors[entry.key] ?? iOSDesignTokens.neutralGray400;

              return Expanded(
                flex: (percentage * 100).round(),
                child: Tooltip(
                  message: '${entry.key.replaceAll('_', ' ').toUpperCase()}: ${entry.value}',
                  child: Container(
                    height: 8,
                    color: color,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: distribution.entries.map((entry) {
            final color = _roleColors[entry.key] ?? iOSDesignTokens.neutralGray400;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_formatRoleName(entry.key)}: ${entry.value}',
                  style: iOSDesignTokens.labelSmall.copyWith(
                    color: iOSDesignTokens.neutralGray600,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  String _formatRoleName(String role) {
    return role
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

/// Compact version for smaller spaces
class UserStatsCompact extends StatelessWidget {
  final int totalUsers;
  final int activeUsers;

  const UserStatsCompact({
    super.key,
    required this.totalUsers,
    required this.activeUsers,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CompactStat(
          value: totalUsers,
          label: 'Total',
          color: iOSDesignTokens.primary,
        ),
        const SizedBox(width: 16),
        _CompactStat(
          value: activeUsers,
          label: 'Active',
          color: iOSDesignTokens.success,
        ),
      ],
    );
  }
}

class _CompactStat extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const _CompactStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$value $label',
          style: iOSDesignTokens.labelMedium.copyWith(
            color: iOSDesignTokens.neutralGray700,
          ),
        ),
      ],
    );
  }
}

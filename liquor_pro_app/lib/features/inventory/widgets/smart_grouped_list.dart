import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/deduplicated_item.dart';

/// Smart Grouped List for OCR Items
///
/// FEATURES:
/// - Group by confidence tier (High/Medium/Low)
/// - Group by match status (Found/New)
/// - Group by category
/// - Collapsible sections with animations
/// - Count badges per group
/// - Smooth expand/collapse
///
/// USAGE:
/// ```dart
/// SmartGroupedList(
///   items: deduplicatedItems,
///   groupBy: GroupBy.confidenceTier,
///   itemBuilder: (item) => YourCardWidget(item),
/// )
/// ```
enum GroupBy {
  confidenceTier,
  matchStatus,
  category,
  none,
}

class SmartGroupedList extends StatefulWidget {
  final List<DeduplicatedItem> items;
  final GroupBy groupBy;
  final Widget Function(DeduplicatedItem item) itemBuilder;
  final bool initiallyExpanded;
  final EdgeInsets? padding;

  const SmartGroupedList({
    super.key,
    required this.items,
    required this.groupBy,
    required this.itemBuilder,
    this.initiallyExpanded = true,
    this.padding,
  });

  @override
  State<SmartGroupedList> createState() => _SmartGroupedListState();
}

class _SmartGroupedListState extends State<SmartGroupedList> {
  final Map<String, bool> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    _initializeExpandedState();
  }

  @override
  void didUpdateWidget(SmartGroupedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupBy != widget.groupBy || oldWidget.items != widget.items) {
      _initializeExpandedState();
    }
  }

  void _initializeExpandedState() {
    final groups = _groupItems(widget.items, widget.groupBy);
    for (final groupKey in groups.keys) {
      _expandedGroups[groupKey] ??= widget.initiallyExpanded;
    }
  }

  Map<String, List<DeduplicatedItem>> _groupItems(
    List<DeduplicatedItem> items,
    GroupBy groupBy,
  ) {
    if (groupBy == GroupBy.none) {
      return {'All Items': items};
    }

    final Map<String, List<DeduplicatedItem>> grouped = {};

    for (final item in items) {
      final key = _getGroupKey(item, groupBy);
      grouped.putIfAbsent(key, () => []).add(item);
    }

    // Sort groups by priority
    final sortedKeys = grouped.keys.toList()..sort((a, b) {
      return _getGroupPriority(a, groupBy).compareTo(_getGroupPriority(b, groupBy));
    });

    final sortedGrouped = <String, List<DeduplicatedItem>>{};
    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }

    return sortedGrouped;
  }

  String _getGroupKey(DeduplicatedItem item, GroupBy groupBy) {
    switch (groupBy) {
      case GroupBy.confidenceTier:
        final confidence = item.confidence ?? 0.0;
        if (confidence >= 0.8) return 'High Confidence (80-100%)';
        if (confidence >= 0.5) return 'Medium Confidence (50-80%)';
        return 'Low Confidence (0-50%)';

      case GroupBy.matchStatus:
        final isMatched = item.matchedSaaSBrandId != null ||
                         item.matchedBrandVariantId != null;
        return isMatched ? 'Found in Database' : 'New Brands';

      case GroupBy.category:
        final category = item.inferredCategory ?? 'Unknown Category';
        final subcat = item.inferredSubcategory;
        if (subcat != null && subcat.isNotEmpty) {
          return '$category → $subcat';
        }
        return category;

      case GroupBy.none:
        return 'All Items';
    }
  }

  int _getGroupPriority(String groupKey, GroupBy groupBy) {
    switch (groupBy) {
      case GroupBy.confidenceTier:
        if (groupKey.contains('High')) return 0;
        if (groupKey.contains('Medium')) return 1;
        return 2;

      case GroupBy.matchStatus:
        if (groupKey.contains('Found')) return 0;
        return 1;

      case GroupBy.category:
        return 0; // Alphabetical by default

      case GroupBy.none:
        return 0;
    }
  }

  Color _getGroupColor(String groupKey, GroupBy groupBy, ColorScheme cs) {
    switch (groupBy) {
      case GroupBy.confidenceTier:
        if (groupKey.contains('High')) return AppColors.success;
        if (groupKey.contains('Medium')) return AppColors.warning;
        return AppColors.error;

      case GroupBy.matchStatus:
        if (groupKey.contains('Found')) return AppColors.info;
        return cs.primary;

      case GroupBy.category:
        return AppColors.info;

      case GroupBy.none:
        return cs.primary;
    }
  }

  IconData _getGroupIcon(String groupKey, GroupBy groupBy) {
    switch (groupBy) {
      case GroupBy.confidenceTier:
        if (groupKey.contains('High')) return Icons.verified_rounded;
        if (groupKey.contains('Medium')) return Icons.warning_amber_rounded;
        return Icons.error_outline_rounded;

      case GroupBy.matchStatus:
        if (groupKey.contains('Found')) return Icons.check_circle_rounded;
        return Icons.add_circle_outline_rounded;

      case GroupBy.category:
        return Icons.category_rounded;

      case GroupBy.none:
        return Icons.list_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groupBy == GroupBy.none) {
      // No grouping, just render items
      return ListView.separated(
        padding: widget.padding ?? const EdgeInsets.all(16),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return widget.itemBuilder(widget.items[index]);
        },
      );
    }

    final cs = Theme.of(context).colorScheme;
    final groups = _groupItems(widget.items, widget.groupBy);

    return ListView.separated(
      padding: widget.padding ?? const EdgeInsets.all(16),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, groupIndex) {
        final groupKey = groups.keys.elementAt(groupIndex);
        final groupItems = groups[groupKey]!;
        final isExpanded = _expandedGroups[groupKey] ?? true;
        final groupColor = _getGroupColor(groupKey, widget.groupBy, cs);
        final groupIcon = _getGroupIcon(groupKey, widget.groupBy);

        return _GroupSection(
          title: groupKey,
          itemCount: groupItems.length,
          color: groupColor,
          icon: groupIcon,
          isExpanded: isExpanded,
          onToggle: () {
            setState(() {
              _expandedGroups[groupKey] = !isExpanded;
            });
          },
          children: groupItems.map(widget.itemBuilder).toList(),
        );
      },
    );
  }
}

class _GroupSection extends StatelessWidget {
  final String title;
  final int itemCount;
  final Color color;
  final IconData icon;
  final bool isExpanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const _GroupSection({
    required this.title,
    required this.itemCount,
    required this.color,
    required this.icon,
    required this.isExpanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.1),
                    color.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(
                    color: color.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  // Count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: color.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '$itemCount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Expand/collapse icon
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Group items (collapsible)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isExpanded
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        for (int i = 0; i < children.length; i++) ...[
                          children[i],
                          if (i < children.length - 1)
                            const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Group By Selector Widget
class GroupBySelector extends StatelessWidget {
  final GroupBy selectedGroupBy;
  final ValueChanged<GroupBy> onChanged;

  const GroupBySelector({
    super.key,
    required this.selectedGroupBy,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.filter_list_rounded,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Group by:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(context,
                  'None',
                  GroupBy.none,
                  Icons.list_rounded,
                ),
                _buildChip(context,
                  'Confidence',
                  GroupBy.confidenceTier,
                  Icons.analytics_rounded,
                ),
                _buildChip(context,
                  'Match',
                  GroupBy.matchStatus,
                  Icons.check_circle_outline_rounded,
                ),
                _buildChip(context,
                  'Category',
                  GroupBy.category,
                  Icons.category_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, GroupBy value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedGroupBy == value;

    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

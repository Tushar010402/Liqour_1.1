import 'package:flutter/material.dart';
import '../models/sort_option.dart';

/// Sort Menu Widget
/// iOS-style menu for sorting options
class SortMenu extends StatelessWidget {
  final SortOption currentSort;
  final Function(SortOption) onSortChanged;

  const SortMenu({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<SortOption>(
      initialValue: currentSort,
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sort,
            size: 20,
            color: cs.primary,
          ),
          const SizedBox(width: 4),
          Text(
            'Sort',
            style: TextStyle(
              color: cs.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      offset: const Offset(0, 40),
      itemBuilder: (context) {
        final menuCs = Theme.of(context).colorScheme;
        return SortOption.values
            .map((option) => PopupMenuItem<SortOption>(
                  value: option,
                  child: Row(
                    children: [
                      Icon(
                        option.icon,
                        size: 18,
                        color: currentSort == option ? menuCs.primary : menuCs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            color: currentSort == option ? menuCs.primary : menuCs.onSurface,
                            fontWeight: currentSort == option ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (currentSort == option)
                        Icon(
                          Icons.check,
                          size: 18,
                          color: menuCs.primary,
                        ),
                    ],
                  ),
                ))
            .toList();
      },
      onSelected: onSortChanged,
    );
  }
}

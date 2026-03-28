import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_feedback.dart';

/// iOS-style filter chip model
class FilterChipData {
  final String id;
  final String label;
  final String? icon; // Emoji or icon name
  final int? count;
  final bool enabled;

  FilterChipData({
    required this.id,
    required this.label,
    this.icon,
    this.count,
    this.enabled = true,
  });
}

/// Horizontal scrollable filter chip row (iOS App Store style)
class FilterChipRow extends StatelessWidget {
  final String title;
  final List<FilterChipData> chips;
  final String? selectedChipId;
  final Function(String) onChipSelected;
  final bool showCounts;
  final EdgeInsets padding;

  const FilterChipRow({
    super.key,
    required this.title,
    required this.chips,
    this.selectedChipId,
    required this.onChipSelected,
    this.showCounts = true,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              title,
              style: AppTextStyles.caption.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),

        // Chips
        SizedBox(
          height: 36, // Reduced from 40px for mobile
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12), // Reduced from 16px
            itemCount: chips.length,
            itemBuilder: (context, index) {
              final chip = chips[index];
              final isSelected = chip.id == selectedChipId;

              return Padding(
                padding: const EdgeInsets.only(right: 6), // Reduced from 8px for mobile
                child: _FilterChip(
                  data: chip,
                  isSelected: isSelected,
                  showCount: showCounts,
                  onTap: () {
                    if (chip.enabled) {
                      HapticFeedbackUtil.selection();
                      onChipSelected(chip.id);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Individual filter chip with iOS styling
class _FilterChip extends StatelessWidget {
  final FilterChipData data;
  final bool isSelected;
  final bool showCount;
  final VoidCallback onTap;

  const _FilterChip({
    required this.data,
    required this.isSelected,
    required this.showCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Reduced from (16, 8) for mobile
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary
              : data.enabled
                  ? cs.surfaceContainerHighest
                  : cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: cs.primary, width: 1.5)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon/Emoji
            if (data.icon != null) ...[
              Text(
                data.icon!,
                style: TextStyle(
                  fontSize: 16,
                  color: isSelected
                      ? Colors.white
                      : data.enabled
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
            ],

            // Label
            Text(
              data.label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : data.enabled
                        ? cs.onSurface
                        : cs.onSurfaceVariant,
              ),
            ),

            // Count Badge
            if (showCount && data.count != null && data.count! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.3)
                      : cs.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${data.count}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : cs.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Multi-select filter chip row (for sizes, etc.)
class MultiSelectFilterChipRow extends StatelessWidget {
  final String title;
  final List<FilterChipData> chips;
  final Set<String> selectedChipIds;
  final Function(String) onChipToggled;
  final bool showCounts;

  const MultiSelectFilterChipRow({
    super.key,
    required this.title,
    required this.chips,
    required this.selectedChipIds,
    required this.onChipToggled,
    this.showCounts = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              title,
              style: AppTextStyles.caption.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),

        // Chips
        SizedBox(
          height: 36, // Reduced from 40px for mobile
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12), // Reduced from 16px
            itemCount: chips.length,
            itemBuilder: (context, index) {
              final chip = chips[index];
              final isSelected = selectedChipIds.contains(chip.id);

              return Padding(
                padding: const EdgeInsets.only(right: 6), // Reduced from 8px for mobile
                child: _FilterChip(
                  data: chip,
                  isSelected: isSelected,
                  showCount: showCounts,
                  onTap: () {
                    if (chip.enabled) {
                      HapticFeedbackUtil.selection();
                      onChipToggled(chip.id);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

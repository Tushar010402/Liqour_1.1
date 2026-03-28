import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/utils/formatters.dart';
import '../models/daily_sales_models.dart';

/// AI Missing Items Card - Shows items found in receipt but not entered
/// Groups missing items by severity with expandable lists
class AIMissingItemsCard extends StatefulWidget {
  final List<MissingItemGroup> missingGroups;
  final VoidCallback? onAddMissing;

  const AIMissingItemsCard({
    super.key,
    required this.missingGroups,
    this.onAddMissing,
  });

  @override
  State<AIMissingItemsCard> createState() => _AIMissingItemsCardState();
}

class _AIMissingItemsCardState extends State<AIMissingItemsCard> {
  final Map<String, bool> _expandedGroups = {};

  // Color constants
  static const Color _criticalRed = Color(0xFFFF3B30);
  static const Color _warningOrange = Color(0xFFFF9500);
  static const Color _infoBlue = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.missingGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    final totalMissing = widget.missingGroups.fold<int>(
      0,
      (sum, group) => sum + group.count,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _criticalRed.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _criticalRed.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(totalMissing, cs),

          // Severity groups
          ...widget.missingGroups.map((group) => _buildSeverityGroup(group, cs)),

          // Action button
          if (widget.onAddMissing != null) _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildHeader(int totalMissing, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _criticalRed.withOpacity(0.05),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _criticalRed.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.doc_text_search,
              color: _criticalRed,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Missing Items Detected',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalMissing item${totalMissing > 1 ? 's' : ''} found in receipt but not entered',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Alert badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _criticalRed,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$totalMissing',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeverityGroup(MissingItemGroup group, ColorScheme cs) {
    final isExpanded = _expandedGroups[group.severity] ?? false;
    final color = group.isCritical ? _criticalRed : _warningOrange;

    return Column(
      children: [
        // Group header (tappable)
        InkWell(
          onTap: () {
            setState(() {
              _expandedGroups[group.severity] = !isExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                // Severity icon
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    group.isCritical
                        ? CupertinoIcons.xmark_circle_fill
                        : CupertinoIcons.exclamationmark_triangle_fill,
                    size: 14,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                // Label
                Expanded(
                  child: Text(
                    '${_capitalizeFirst(group.severity)} Missing (${group.count})',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                // Expand indicator
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    color: cs.onSurfaceVariant,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded items list
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState:
              isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: group.items
                .map((item) => _buildMissingItem(item, color, cs))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildMissingItem(MissingItem item, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.03),
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Brand/Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.brand,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Size badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.size,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Quantity from receipt
                    Icon(
                      CupertinoIcons.cube_box,
                      size: 12,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item.ocrQuantity} qty',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Price from receipt
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Receipt shows',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Formatters.currency(item.ocrPrice),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 14),
          color: _infoBlue,
          borderRadius: BorderRadius.circular(12),
          onPressed: widget.onAddMissing,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.plus_circle_fill,
                size: 18,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                'Add Missing Items',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

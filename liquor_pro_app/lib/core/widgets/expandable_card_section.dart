import 'package:flutter/material.dart';

/// Expandable section for cards with smooth animation
/// Features:
/// - Tap to expand/collapse
/// - Smooth height animation
/// - Custom header and content
/// - Optional trailing widget
class ExpandableCardSection extends StatefulWidget {
  final String title;
  final Widget content;
  final IconData? leadingIcon;
  final Widget? trailing;
  final bool initiallyExpanded;
  final Color? headerColor;
  final EdgeInsets? contentPadding;
  final VoidCallback? onExpansionChanged;

  const ExpandableCardSection({
    super.key,
    required this.title,
    required this.content,
    this.leadingIcon,
    this.trailing,
    this.initiallyExpanded = false,
    this.headerColor,
    this.contentPadding,
    this.onExpansionChanged,
  });

  @override
  State<ExpandableCardSection> createState() => _ExpandableCardSectionState();
}

class _ExpandableCardSectionState extends State<ExpandableCardSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _iconRotationAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: _isExpanded ? 1.0 : 0.0,
    );

    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _iconRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 0.5, // 180 degrees
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onExpansionChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: _toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              color: widget.headerColor ?? Colors.transparent,
              child: Row(
                children: [
                  if (widget.leadingIcon != null) ...[
                    Icon(
                      widget.leadingIcon,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    widget.trailing!,
                    const SizedBox(width: 8),
                  ],
                  RotationTransition(
                    turns: _iconRotationAnimation,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: theme.iconTheme.color?.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          SizeTransition(
            sizeFactor: _expandAnimation,
            axisAlignment: -1.0,
            child: Container(
              padding: widget.contentPadding ??
                  const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
              child: widget.content,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick expansion panel wrapper for common use cases
class QuickExpansionPanels {
  /// Raw OCR text section
  static Widget rawOCRText({
    required BuildContext context,
    required String rawText,
    bool initiallyExpanded = false,
  }) {
    return ExpandableCardSection(
      title: 'Raw OCR Text',
      leadingIcon: Icons.text_snippet_outlined,
      initiallyExpanded: initiallyExpanded,
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded, size: 18),
        onPressed: () {
          // Copy to clipboard
          // Clipboard.setData(ClipboardData(text: rawText));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        tooltip: 'Copy to clipboard',
      ),
      content: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.2),
          ),
        ),
        child: SelectableText(
          rawText,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }

  /// Details section
  static Widget details({
    required String title,
    required List<DetailRow> details,
    IconData? icon,
    bool initiallyExpanded = false,
  }) {
    return ExpandableCardSection(
      title: title,
      leadingIcon: icon ?? Icons.info_outline_rounded,
      initiallyExpanded: initiallyExpanded,
      content: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details
            .map((detail) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${detail.label}:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          detail.value,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      );
      }),
    );
  }
}

/// Detail row model
class DetailRow {
  final String label;
  final String value;

  const DetailRow({
    required this.label,
    required this.value,
  });
}

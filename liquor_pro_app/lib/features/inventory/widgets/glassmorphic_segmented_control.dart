import 'dart:ui';
import 'package:flutter/material.dart';

/// Modern iOS 16+ style glassmorphic segmented control
/// Features:
/// - Blur backdrop effect
/// - Smooth sliding animation
/// - Haptic feedback
/// - Customizable segment colors
class GlassmorphicSegmentedControl<T> extends StatefulWidget {
  final List<SegmentOption<T>> segments;
  final T selectedValue;
  final ValueChanged<T> onChanged;
  final Color? backgroundColor;
  final Color? selectedColor;
  final double height;
  final EdgeInsets padding;
  final BorderRadius? borderRadius;

  const GlassmorphicSegmentedControl({
    super.key,
    required this.segments,
    required this.selectedValue,
    required this.onChanged,
    this.backgroundColor,
    this.selectedColor,
    this.height = 40,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius,
  });

  @override
  State<GlassmorphicSegmentedControl<T>> createState() =>
      _GlassmorphicSegmentedControlState<T>();
}

class _GlassmorphicSegmentedControlState<T>
    extends State<GlassmorphicSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _selectedIndex = 0;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.segments.indexWhere(
      (segment) => segment.value == widget.selectedValue,
    );
    _previousIndex = _selectedIndex;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(GlassmorphicSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = widget.segments.indexWhere(
      (segment) => segment.value == widget.selectedValue,
    );
    if (newIndex != _selectedIndex) {
      setState(() {
        _previousIndex = _selectedIndex;
        _selectedIndex = newIndex;
      });
      _animationController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = widget.backgroundColor ??
        theme.colorScheme.surface.withOpacity(0.1);
    final selectedColor = widget.selectedColor ??
        theme.colorScheme.primary.withOpacity(0.15);

    return Container(
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
        color: backgroundColor,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segmentWidth = constraints.maxWidth / widget.segments.length;

              return Stack(
                children: [
                  // Animated selection indicator
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final begin = _previousIndex * segmentWidth;
                      final end = _selectedIndex * segmentWidth;
                      final offset = begin + (end - begin) * _animation.value;

                      return Positioned(
                        left: offset,
                        top: 0,
                        bottom: 0,
                        width: segmentWidth,
                        child: Container(
                          decoration: BoxDecoration(
                            color: selectedColor,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Segment buttons
                  Row(
                    children: widget.segments.asMap().entries.map((entry) {
                      final index = entry.key;
                      final segment = entry.value;
                      final isSelected = index == _selectedIndex;

                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (!isSelected) {
                              widget.onChanged(segment.value);
                              // Haptic feedback
                              // HapticFeedback.selectionClick();
                            }
                          },
                          child: Container(
                            alignment: Alignment.center,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.textTheme.bodyMedium?.color
                                        ?.withOpacity(0.6),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (segment.icon != null) ...[
                                    Icon(
                                      segment.icon,
                                      size: 16,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.iconTheme.color
                                              ?.withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(segment.label),
                                  if (segment.badge != null) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.surface
                                                .withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        segment.badge!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? Colors.white
                                              : theme.textTheme.bodySmall?.color
                                                  ?.withOpacity(0.7),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Segment option model
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final String? badge;

  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.badge,
  });
}

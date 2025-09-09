import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

class ScreenReaderSupport {
  /// Enhanced semantic widget for screen readers
  static Widget enhance({
    required Widget child,
    String? label,
    String? hint,
    String? value,
    bool? button,
    bool? link,
    bool? header,
    bool? textField,
    bool? focusable,
    bool? selected,
    bool? checked,
    bool? expanded,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    VoidCallback? onIncrease,
    VoidCallback? onDecrease,
    VoidCallback? onMoveCursorForwardByCharacter,
    VoidCallback? onMoveCursorBackwardByCharacter,
    String? increasedValue,
    String? decreasedValue,
    SemanticsTag? tagForChildren,
    bool excludeSemantics = false,
  }) {
    if (excludeSemantics) {
      return ExcludeSemantics(child: child);
    }

    return Semantics(
      label: label,
      hint: hint,
      value: value,
      button: button,
      link: link,
      header: header,
      textField: textField,
      focusable: focusable ?? (onTap != null),
      selected: selected,
      checked: checked,
      expanded: expanded,
      onTap: onTap,
      onLongPress: onLongPress,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      onMoveCursorForwardByCharacter: onMoveCursorForwardByCharacter,
      onMoveCursorBackwardByCharacter: onMoveCursorBackwardByCharacter,
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      tagForChildren: tagForChildren,
      child: child,
    );
  }

  /// Merge semantics for complex widgets
  static Widget merge({
    required Widget child,
    bool? absorbing,
  }) {
    return MergeSemantics(
      child: child,
    );
  }

  /// Exclude from screen readers
  static Widget exclude(Widget child) {
    return ExcludeSemantics(child: child);
  }

  /// Create semantic announcements
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(
      message,
      Directionality.of(context),
    );
  }

  /// Create semantic tooltip announcement
  static void announceTooltip(BuildContext context, String tooltip) {
    SemanticsService.tooltip(tooltip);
  }
}

/// Enhanced button with screen reader support
class AccessibleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final String? tooltip;
  final bool enabled;

  const AccessibleButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.onLongPress,
    this.semanticLabel,
    this.tooltip,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = child;

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return ScreenReaderSupport.enhance(
      label: semanticLabel,
      button: true,
      focusable: enabled,
      onTap: enabled ? onPressed : null,
      onLongPress: onLongPress,
      child: button,
    );
  }
}

/// Accessible text field with proper semantics
class AccessibleTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final int? maxLines;
  final String? semanticLabel;

  const AccessibleTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.maxLines = 1,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenReaderSupport.enhance(
      label: semanticLabel ?? labelText,
      hint: hintText,
      textField: true,
      focusable: true,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
          helperText: helperText,
        ),
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onTap: onTap,
        readOnly: readOnly,
        maxLines: maxLines,
      ),
    );
  }
}

/// Accessible list item with proper semantics
class AccessibleListItem extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final bool selected;
  final int? index;
  final int? totalItems;

  const AccessibleListItem({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.selected = false,
    this.index,
    this.totalItems,
  });

  @override
  Widget build(BuildContext context) {
    String? enhancedLabel = semanticLabel;
    
    if (index != null && totalItems != null) {
      final position = '${index! + 1} of $totalItems';
      enhancedLabel = enhancedLabel != null 
          ? '$enhancedLabel. Item $position'
          : 'Item $position';
    }

    return ScreenReaderSupport.enhance(
      label: enhancedLabel,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      child: child,
    );
  }
}

/// Accessible navigation item
class AccessibleNavItem extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool selected;
  final bool isHeader;

  const AccessibleNavItem({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.selected = false,
    this.isHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenReaderSupport.enhance(
      label: semanticLabel,
      button: onTap != null,
      header: isHeader,
      selected: selected,
      onTap: onTap,
      child: child,
    );
  }
}

/// Accessible image with alt text
class AccessibleImage extends StatelessWidget {
  final Widget image;
  final String altText;
  final String? semanticLabel;
  final bool decorative;

  const AccessibleImage({
    super.key,
    required this.image,
    required this.altText,
    this.semanticLabel,
    this.decorative = false,
  });

  @override
  Widget build(BuildContext context) {
    if (decorative) {
      return ScreenReaderSupport.exclude(image);
    }

    return ScreenReaderSupport.enhance(
      label: semanticLabel ?? altText,
      child: image,
    );
  }
}

/// Accessible progress indicator
class AccessibleProgressIndicator extends StatelessWidget {
  final double? value;
  final String? semanticLabel;
  final Widget? child;

  const AccessibleProgressIndicator({
    super.key,
    this.value,
    this.semanticLabel,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    String progressLabel = semanticLabel ?? 'Loading progress';
    
    if (value != null) {
      final percentage = (value! * 100).round();
      progressLabel += ': $percentage percent complete';
    }

    Widget indicator = child ?? CircularProgressIndicator(value: value);

    return ScreenReaderSupport.enhance(
      label: progressLabel,
      value: value?.toString(),
      child: indicator,
    );
  }
}

/// Accessible slider with proper semantics
class AccessibleSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double>? onChanged;
  final String? semanticLabel;
  final String Function(double)? semanticFormatterCallback;

  const AccessibleSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
    this.semanticLabel,
    this.semanticFormatterCallback,
  });

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      onChanged: onChanged,
      label: semanticLabel,
      semanticFormatterCallback: semanticFormatterCallback,
    );
  }
}

/// Accessible modal/dialog announcements
class AccessibleModal {
  static void announceOpen(BuildContext context, String title) {
    ScreenReaderSupport.announce(context, 'Dialog opened: $title');
  }

  static void announceClose(BuildContext context) {
    ScreenReaderSupport.announce(context, 'Dialog closed');
  }

  static void announceError(BuildContext context, String error) {
    ScreenReaderSupport.announce(context, 'Error: $error');
  }

  static void announceSuccess(BuildContext context, String message) {
    ScreenReaderSupport.announce(context, 'Success: $message');
  }
}

/// Live region for dynamic content announcements
class AccessibleLiveRegion extends StatefulWidget {
  final Widget child;
  final String? announcement;
  final bool assertive;

  const AccessibleLiveRegion({
    super.key,
    required this.child,
    this.announcement,
    this.assertive = false,
  });

  @override
  State<AccessibleLiveRegion> createState() => _AccessibleLiveRegionState();
}

class _AccessibleLiveRegionState extends State<AccessibleLiveRegion> {
  @override
  void didUpdateWidget(AccessibleLiveRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.announcement != null && 
        widget.announcement != oldWidget.announcement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScreenReaderSupport.announce(context, widget.announcement!);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
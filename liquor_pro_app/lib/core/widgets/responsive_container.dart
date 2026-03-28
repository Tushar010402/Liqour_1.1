import 'package:flutter/material.dart';
import '../utils/responsive_utils.dart';

/// A responsive container that provides max-width constraints and adaptive padding
/// for better layouts on tablets and desktop screens
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool centerContent;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final List<BoxShadow>? boxShadow;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.centerContent = true,
    this.backgroundColor,
    this.borderRadius,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = ResponsiveUtils.isLargeScreen(context);
    final effectiveMaxWidth = maxWidth ?? ResponsiveUtils.getMaxContentWidth(context);
    final effectivePadding = padding ?? ResponsiveUtils.getPadding(context);

    Widget content = Padding(
      padding: effectivePadding,
      child: child,
    );

    // Apply container styling if provided
    if (backgroundColor != null || borderRadius != null || boxShadow != null) {
      content = Container(
        padding: effectivePadding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          boxShadow: boxShadow,
        ),
        child: child,
      );
    }

    // Apply max-width constraint for large screens
    if (isLargeScreen && effectiveMaxWidth != double.infinity) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
        child: content,
      );
    }

    // Center content on large screens if requested
    if (centerContent && isLargeScreen) {
      return Center(child: content);
    }

    return content;
  }
}

/// A responsive scrollable container for forms and long content
class ResponsiveScrollContainer extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool centerContent;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;

  const ResponsiveScrollContainer({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.centerContent = true,
    this.scrollController,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: scrollController,
          physics: physics ?? const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: ResponsiveContainer(
                maxWidth: maxWidth,
                padding: padding,
                centerContent: centerContent,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A responsive card widget with adaptive sizing and styling
class ResponsiveCard extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double? elevation;
  final bool centerContent;

  const ResponsiveCard({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.elevation,
    this.centerContent = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = ResponsiveUtils.getBorderRadius(context);
    final effectivePadding = padding ?? ResponsiveUtils.getPadding(context);

    Widget card = Card(
      elevation: elevation ?? 2,
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );

    if (margin != null) {
      card = Padding(
        padding: margin!,
        child: card,
      );
    }

    return ResponsiveContainer(
      maxWidth: maxWidth,
      padding: EdgeInsets.zero,
      centerContent: centerContent,
      child: card,
    );
  }
}

/// A responsive dialog wrapper that ensures proper sizing on tablets
class ResponsiveDialog extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;

  const ResponsiveDialog({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = maxWidth ??
      ResponsiveUtils.getValue(
        context: context,
        phone: double.infinity,
        tablet: 500.0,
        desktop: 600.0,
      );

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          ResponsiveUtils.getBorderRadius(context),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: effectiveMaxWidth ?? double.infinity),
        child: Padding(
          padding: padding ?? ResponsiveUtils.getPadding(context),
          child: child,
        ),
      ),
    );
  }
}

/// A responsive column that adjusts spacing based on device type
class ResponsiveColumn extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final double? spacing;

  const ResponsiveColumn({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSpacing = spacing ?? ResponsiveUtils.getSpacing(context);

    return Column(
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      children: _buildChildrenWithSpacing(effectiveSpacing),
    );
  }

  List<Widget> _buildChildrenWithSpacing(double spacing) {
    final List<Widget> widgets = [];
    for (int i = 0; i < children.length; i++) {
      widgets.add(children[i]);
      if (i < children.length - 1) {
        widgets.add(SizedBox(height: spacing));
      }
    }
    return widgets;
  }
}

/// A responsive row that can wrap on smaller screens
class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final MainAxisSize mainAxisSize;
  final CrossAxisAlignment crossAxisAlignment;
  final double? spacing;
  final bool wrapOnSmallScreen;

  const ResponsiveRow({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing,
    this.wrapOnSmallScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSpacing = spacing ?? ResponsiveUtils.getSpacing(context);
    final isPhone = ResponsiveUtils.isPhone(context);

    // If wrapping on small screens and it's a phone, use column instead
    if (wrapOnSmallScreen && isPhone) {
      return ResponsiveColumn(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: effectiveSpacing,
        children: children,
      );
    }

    // Otherwise use row with spacing
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      children: _buildChildrenWithSpacing(effectiveSpacing),
    );
  }

  List<Widget> _buildChildrenWithSpacing(double spacing) {
    final List<Widget> widgets = [];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        widgets.add(SizedBox(width: spacing));
      }
      widgets.add(
        children[i] is Expanded || children[i] is Flexible
            ? children[i]
            : Flexible(child: children[i]),
      );
    }
    return widgets;
  }
}
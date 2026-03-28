import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/animation_constants.dart';
import '../theme/ios_design_tokens.dart';
import '../utils/haptic_feedback.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Enums
// ══════════════════════════════════════════════════════════════════════════════

/// Status of a daily sales entry
enum EntryStatus {
  notSubmitted,
  draft,
  pending,
  approved,
  rejected;

  Color get color => switch (this) {
        notSubmitted => AppColors.error,
        draft => AppColors.info,
        pending => AppColors.warning,
        approved => AppColors.success,
        rejected => AppColors.error,
      };

  IconData get icon => switch (this) {
        notSubmitted => Icons.cancel_outlined,
        draft => Icons.edit_note_rounded,
        pending => Icons.hourglass_bottom_rounded,
        approved => Icons.check_circle_outline,
        rejected => Icons.highlight_off_rounded,
      };

  String get label => switch (this) {
        notSubmitted => 'Not Submitted',
        draft => 'Draft Saved',
        pending => 'Pending Approval',
        approved => 'Approved',
        rejected => 'Rejected',
      };
}

/// Severity of an exception/alert
enum ExceptionSeverity {
  warning,
  error,
  info;

  Color get color => switch (this) {
        warning => AppColors.warning,
        error => AppColors.error,
        info => AppColors.info,
      };

  IconData get icon => switch (this) {
        warning => Icons.warning_amber_rounded,
        error => Icons.error_outline_rounded,
        info => Icons.info_outline_rounded,
      };
}

// ══════════════════════════════════════════════════════════════════════════════
// Data classes
// ══════════════════════════════════════════════════════════════════════════════

/// Data for a single shop row in the comparison table
class ShopMetricData {
  final String shopName;
  final int salesCount;
  final double totalAmount;
  final int pendingCount;

  const ShopMetricData({
    required this.shopName,
    required this.salesCount,
    required this.totalAmount,
    required this.pendingCount,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 1: HomeStatusCard
// ══════════════════════════════════════════════════════════════════════════════

/// Entry status card with left color border.
class HomeStatusCard extends StatelessWidget {
  final String title;
  final EntryStatus status;
  final double? amount;
  final String? date;
  final String? shopName;
  final VoidCallback? onTap;
  final bool compact;

  const HomeStatusCard({
    super.key,
    required this.title,
    required this.status,
    this.amount,
    this.date,
    this.shopName,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (compact) return _buildCompact(cs);
    return _buildFull(cs);
  }

  Widget _buildFull(ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusCard),
          border: Border(
            left: BorderSide(color: status.color, width: 4),
          ),
          boxShadow: iOSDesignTokens.shadowSmall,
        ),
        padding: EdgeInsets.all(iOSDesignTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(status.icon, color: status.color, size: 20),
                SizedBox(width: iOSDesignTokens.space8),
                Expanded(
                  child: Text(title, style: AppTextStyles.bodyMedium.copyWith(color: cs.onSurface)),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant, size: 20),
              ],
            ),
            SizedBox(height: iOSDesignTokens.space8),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.1),
                    borderRadius:
                        BorderRadius.circular(iOSDesignTokens.radiusSmall),
                  ),
                  child: Text(
                    status.label,
                    style: AppTextStyles.overline.copyWith(color: status.color),
                  ),
                ),
                if (date != null) ...[
                  SizedBox(width: iOSDesignTokens.space8),
                  Text(date!, style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant)),
                ],
                const Spacer(),
                if (amount != null)
                  Text(
                    '₹${amount!.toStringAsFixed(0)}',
                    style: AppTextStyles.priceMedium.copyWith(color: cs.primary),
                  ),
              ],
            ),
            if (shopName != null) ...[
              SizedBox(height: iOSDesignTokens.space4),
              Text(shopName!,
                  style: AppTextStyles.caption
                      .copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(ColorScheme cs) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border(
            left: BorderSide(color: status.color, width: 3),
          ),
        ),
        padding: EdgeInsets.symmetric(
            horizontal: iOSDesignTokens.space12,
            vertical: iOSDesignTokens.space8),
        child: Row(
          children: [
            Icon(status.icon, color: status.color, size: 18),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(child: Text(title, style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(iOSDesignTokens.radiusSmall),
              ),
              child: Text(
                status.label,
                style: AppTextStyles.overline
                    .copyWith(color: status.color, fontSize: 10),
              ),
            ),
            if (amount != null) ...[
              SizedBox(width: iOSDesignTokens.space8),
              Text('₹${amount!.toStringAsFixed(0)}',
                  style: AppTextStyles.priceSmall),
            ],
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 2: HomeActionButton
// ══════════════════════════════════════════════════════════════════════════════

/// Primary/secondary action button with press animation.
class HomeActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final Color? color;
  final String? subtitle;
  final int? badge;
  final bool isExpanded;

  const HomeActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.isPrimary = false,
    this.color,
    this.subtitle,
    this.badge,
    this.isExpanded = true,
  });

  @override
  State<HomeActionButton> createState() => _HomeActionButtonState();
}

class _HomeActionButtonState extends State<HomeActionButton> {
  double _scale = 1.0;

  void _onTapDown(TapDownDetails _) {
    setState(() => _scale = 0.98);
  }

  void _onTapUp(TapUpDetails _) {
    setState(() => _scale = 1.0);
  }

  void _onTapCancel() {
    setState(() => _scale = 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = widget.color ?? cs.primary;

    final child = AnimatedScale(
      scale: _scale,
      duration: AnimationConstants.buttonPress,
      child: widget.isPrimary ? _buildPrimary(effectiveColor) : _buildSecondary(effectiveColor),
    );

    if (widget.isExpanded) return child;
    return child;
  }

  Widget _buildPrimary(Color color) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () {
        HapticFeedbackUtil.mediumImpact();
        widget.onTap?.call();
      },
      child: Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusCard),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: Colors.white, size: 24),
            SizedBox(width: iOSDesignTokens.space12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: AppTextStyles.button.copyWith(color: Colors.white)),
                if (widget.subtitle != null)
                  Text(widget.subtitle!,
                      style: AppTextStyles.caption
                          .copyWith(color: Colors.white70, fontSize: 11)),
              ],
            ),
            if (widget.badge != null && widget.badge! > 0) ...[
              SizedBox(width: iOSDesignTokens.space8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${widget.badge}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecondary(Color color) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: () {
        HapticFeedbackUtil.mediumImpact();
        widget.onTap?.call();
      },
      child: Container(
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: iOSDesignTokens.space12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.15),
                    color.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(widget.icon, color: color, size: 20),
            ),
            SizedBox(width: iOSDesignTokens.space12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label,
                      style: AppTextStyles.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!,
                        style: AppTextStyles.caption
                            .copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (widget.badge != null && widget.badge! > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${widget.badge}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ),
            ],
            Icon(Icons.chevron_right_rounded,
                color: color.withValues(alpha: 0.4), size: 20),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 3: HomeSubmissionRow
// ══════════════════════════════════════════════════════════════════════════════

/// Compact row for recent submissions list.
class HomeSubmissionRow extends StatelessWidget {
  final String date;
  final EntryStatus status;
  final double? amount;
  final String? shopName;
  final VoidCallback? onTap;

  const HomeSubmissionRow({
    super.key,
    required this.date,
    required this.status,
    this.amount,
    this.shopName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: iOSDesignTokens.space8,
            horizontal: iOSDesignTokens.space4),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(date, style: AppTextStyles.bodySmall.copyWith(color: cs.onSurfaceVariant)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.1),
                borderRadius:
                    BorderRadius.circular(iOSDesignTokens.radiusSmall),
              ),
              child: Text(
                status.label,
                style: AppTextStyles.overline
                    .copyWith(color: status.color, fontSize: 10),
              ),
            ),
            const Spacer(),
            if (amount != null)
              Text('₹${amount!.toStringAsFixed(0)}',
                  style: AppTextStyles.priceSmall.copyWith(color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 4: HomeSectionHeader
// ══════════════════════════════════════════════════════════════════════════════

/// Section title with optional trailing "See All" link.
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const HomeSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
          top: iOSDesignTokens.space20, bottom: iOSDesignTokens.space10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: iOSDesignTokens.space8),
          Text(title, style: AppTextStyles.h6.copyWith(color: cs.onSurface)),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('See All',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: cs.primary)),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 12, color: cs.primary),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 5: HomeApprovalCard
// ══════════════════════════════════════════════════════════════════════════════

/// Pending approval count card with gradient styling.
class HomeApprovalCard extends StatelessWidget {
  final String title;
  final int pendingCount;
  final IconData icon;
  final VoidCallback? onTap;

  const HomeApprovalCard({
    super.key,
    required this.title,
    required this.pendingCount,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingCount > 0;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          decoration: BoxDecoration(
            gradient: hasPending
                ? LinearGradient(
                    colors: [
                      AppColors.warning.withValues(alpha: 0.12),
                      AppColors.warning.withValues(alpha: 0.04),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [
                      AppColors.success.withValues(alpha: 0.08),
                      AppColors.success.withValues(alpha: 0.02),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusCard),
            border: Border.all(
              color: hasPending
                  ? AppColors.warning.withValues(alpha: 0.3)
                  : AppColors.success.withValues(alpha: 0.2),
            ),
            boxShadow: [
              BoxShadow(
                color: (hasPending ? AppColors.warning : AppColors.success)
                    .withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (hasPending ? AppColors.warning : AppColors.success)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon,
                        color:
                            hasPending ? AppColors.warning : AppColors.success,
                        size: 20),
                  ),
                  const Spacer(),
                  if (hasPending)
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: AppColors.warningGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.warning.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text('$pendingCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13)),
                    )
                  else
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.success, size: 18),
                    ),
                ],
              ),
              SizedBox(height: iOSDesignTokens.space12),
              Text(title,
                  style: AppTextStyles.bodySmall
                      .copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: iOSDesignTokens.space4),
              Text(
                hasPending ? '$pendingCount pending' : 'All clear',
                style: AppTextStyles.caption.copyWith(
                    color: hasPending
                        ? AppColors.warning
                        : AppColors.success),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 6: HomeTeamStatusRow
// ══════════════════════════════════════════════════════════════════════════════

/// Person submission indicator row with card styling.
class HomeTeamStatusRow extends StatelessWidget {
  final String personName;
  final bool hasSubmitted;
  final double? amount;
  final String? shopName;

  const HomeTeamStatusRow({
    super.key,
    required this.personName,
    required this.hasSubmitted,
    this.amount,
    this.shopName,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      padding: EdgeInsets.symmetric(
          horizontal: iOSDesignTokens.space12,
          vertical: iOSDesignTokens.space10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(
          color: hasSubmitted
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.error.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasSubmitted
                    ? [
                        AppColors.success.withValues(alpha: 0.2),
                        AppColors.success.withValues(alpha: 0.08),
                      ]
                    : [
                        AppColors.error.withValues(alpha: 0.15),
                        AppColors.error.withValues(alpha: 0.06),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasSubmitted ? Icons.check_rounded : Icons.close_rounded,
              color: hasSubmitted ? AppColors.success : AppColors.error,
              size: 15,
            ),
          ),
          SizedBox(width: iOSDesignTokens.space8),
          Expanded(
            child: Text(personName,
                style: AppTextStyles.bodySmall
                    .copyWith(fontWeight: FontWeight.w500, color: cs.onSurface)),
          ),
          if (shopName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.06),
                borderRadius:
                    BorderRadius.circular(iOSDesignTokens.radiusSmall),
              ),
              child: Text(shopName!,
                  style: AppTextStyles.caption
                      .copyWith(fontSize: 10, color: cs.primary)),
            ),
            SizedBox(width: iOSDesignTokens.space8),
          ],
          if (hasSubmitted && amount != null)
            Text('₹${amount!.toStringAsFixed(0)}',
                style: AppTextStyles.priceSmall
                    .copyWith(color: AppColors.success))
          else if (!hasSubmitted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius:
                    BorderRadius.circular(iOSDesignTokens.radiusSmall),
              ),
              child: Text('Missing',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 7: HomeShopComparisonTable
// ══════════════════════════════════════════════════════════════════════════════

/// Shop metrics comparison table.
class HomeShopComparisonTable extends StatelessWidget {
  final List<ShopMetricData> shops;

  const HomeShopComparisonTable({super.key, required this.shops});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (shops.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(iOSDesignTokens.space16),
          child: Text('No shop data available',
              style: AppTextStyles.caption
                  .copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.primary.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.08),
                  cs.primary.withValues(alpha: 0.03),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            padding: EdgeInsets.symmetric(
                horizontal: iOSDesignTokens.space12,
                vertical: iOSDesignTokens.space10),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Shop', style: AppTextStyles.captionBold.copyWith(color: cs.primary))),
                Expanded(flex: 2, child: Text('Sales', style: AppTextStyles.captionBold.copyWith(color: cs.primary), textAlign: TextAlign.center)),
                Expanded(flex: 3, child: Text('Amount', style: AppTextStyles.captionBold.copyWith(color: cs.primary), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('Pending', style: AppTextStyles.captionBold.copyWith(color: cs.primary), textAlign: TextAlign.center)),
              ],
            ),
          ),
          // Rows
          ...shops.asMap().entries.map((entry) {
            final i = entry.key;
            final shop = entry.value;
            return Container(
              color: i.isEven ? Colors.transparent : cs.outline.withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(
                  horizontal: iOSDesignTokens.space12,
                  vertical: iOSDesignTokens.space8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(shop.shopName,
                        style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('${shop.salesCount}',
                        style: AppTextStyles.bodySmall.copyWith(color: cs.onSurface),
                        textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('₹${shop.totalAmount.toStringAsFixed(0)}',
                        style: AppTextStyles.priceSmall.copyWith(color: cs.primary),
                        textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 2,
                    child: shop.pendingCount > 0
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${shop.pendingCount}',
                                  style: AppTextStyles.caption
                                      .copyWith(color: AppColors.warning),
                                  textAlign: TextAlign.center),
                            ),
                          )
                        : Center(
                            child: Icon(Icons.check,
                                color: AppColors.success, size: 16),
                          ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget 8: HomeExceptionAlert
// ══════════════════════════════════════════════════════════════════════════════

/// Warning/exception row with severity-based styling.
class HomeExceptionAlert extends StatelessWidget {
  final String message;
  final ExceptionSeverity severity;
  final VoidCallback? onTap;

  const HomeExceptionAlert({
    super.key,
    required this.message,
    required this.severity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: iOSDesignTokens.space6),
        padding: EdgeInsets.symmetric(
            horizontal: iOSDesignTokens.space12,
            vertical: iOSDesignTokens.space10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          border: Border(
            left: BorderSide(color: severity.color, width: 3),
          ),
          boxShadow: [
            BoxShadow(
              color: severity.color.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: severity.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(severity.icon, color: severity.color, size: 16),
            ),
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: Text(message,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: cs.onSurface)),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded,
                  color: severity.color.withValues(alpha: 0.5), size: 18),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Shared helpers for home screens
// ══════════════════════════════════════════════════════════════════════════════

/// Consistent header for all home screens.
class HomeScreenHeader extends StatelessWidget {
  final String greeting;
  final String userName;
  final String? shopName;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onShopTap;

  const HomeScreenHeader({
    super.key,
    required this.greeting,
    required this.userName,
    this.shopName,
    this.onSettingsTap,
    this.onShopTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
          top: iOSDesignTokens.space8, bottom: iOSDesignTokens.space4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.liquor,
                          color: Colors.white, size: 18),
                    ),
                    SizedBox(width: iOSDesignTokens.space8),
                    Text('LiquorPro',
                        style: AppTextStyles.h6.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary)),
                  ],
                ),
                SizedBox(height: iOSDesignTokens.space8),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: '$greeting, ',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: cs.onSurfaceVariant)),
                      TextSpan(
                          text: userName,
                          style: AppTextStyles.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ],
                  ),
                ),
                if (shopName != null) ...[
                  SizedBox(height: iOSDesignTokens.space4),
                  GestureDetector(
                    onTap: onShopTap,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.store_outlined,
                            size: 14, color: cs.onSurfaceVariant),
                        SizedBox(width: iOSDesignTokens.space4),
                        Flexible(
                          child: Text(shopName!,
                              style: AppTextStyles.caption
                                  .copyWith(color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (onShopTap != null) ...[
                          SizedBox(width: iOSDesignTokens.space4),
                          Icon(Icons.unfold_more_rounded,
                              size: 14, color: cs.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onSettingsTap != null)
            GestureDetector(
              onTap: onSettingsTap,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Greeting string based on time of day.
///   5 AM – 11:59 AM  → Good Morning
///  12 PM –  4:59 PM  → Good Afternoon
///   5 PM –  8:59 PM  → Good Evening
///   9 PM –  4:59 AM  → Good Night
String getTimeGreeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 17) return 'Good Afternoon';
  if (hour >= 17 && hour < 21) return 'Good Evening';
  return 'Good Night';
}

/// Map a record status string to EntryStatus enum.
EntryStatus mapRecordStatus(String? status) {
  return switch (status?.toLowerCase()) {
    'pending' => EntryStatus.pending,
    'approved' => EntryStatus.approved,
    'rejected' => EntryStatus.rejected,
    'draft' => EntryStatus.draft,
    _ => EntryStatus.notSubmitted,
  };
}

/// Format a DateTime as dd/MM.
String formatShortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

/// Show a bottom sheet to pick a shop from the provider's list.
void showShopPickerSheet(BuildContext context,
    {required List<dynamic> shops,
    required String? selectedShopId,
    required void Function(dynamic shop) onSelect}) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.all(iOSDesignTokens.space16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: iOSDesignTokens.space12),
            Text('Select Shop', style: AppTextStyles.h6),
            SizedBox(height: iOSDesignTokens.space12),
            if (shops.isEmpty)
              Padding(
                padding: EdgeInsets.all(iOSDesignTokens.space16),
                child: Text('No shops available',
                    style: AppTextStyles.caption
                        .copyWith(color: cs.onSurfaceVariant)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: shops.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: cs.outline),
                  itemBuilder: (_, i) {
                    final shop = shops[i];
                    final isSelected = shop.id == selectedShopId;
                    return ListTile(
                      leading: Icon(Icons.store_rounded,
                          color: isSelected
                              ? cs.primary
                              : cs.onSurfaceVariant),
                      title: Text(shop.name,
                          style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                      subtitle: shop.address != null &&
                              shop.address.toString().isNotEmpty
                          ? Text(shop.address.toString(),
                              style: AppTextStyles.caption
                                  .copyWith(color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              color: cs.primary, size: 22)
                          : null,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              iOSDesignTokens.radiusSmall)),
                      onTap: () {
                        Navigator.pop(ctx);
                        onSelect(shop);
                      },
                    );
                  },
                ),
              ),
            SizedBox(height: iOSDesignTokens.space8),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/constants/app_text_styles.dart';

/// Bottom action bar — JSX-matched.
///
/// Three modes:
/// 1. **Button** — `label` + `onPressed` → full-width blue pill button
/// 2. **Progress** — `progressFilled` + `progressTotal` → animated fill bar
/// 3. **Fallback** — `progressText` only (no fill values) → static blue segment
class BottomActionBar extends StatelessWidget {
  final String? label;
  final VoidCallback? onPressed;
  final String? userInitial;
  final String? progressText;
  final int? progressFilled;
  final int? progressTotal;

  const BottomActionBar({
    super.key,
    this.label,
    this.onPressed,
    this.userInitial,
    this.progressText,
    this.progressFilled,
    this.progressTotal,
  });

  bool get _isProgressMode => progressText != null;

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPadding + 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEAEDF1))),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFD5D9E2),
            ),
            child: Center(child: SvgPicture.asset('assets/icons/apps_add.svg', width: 24, height: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(child: _isProgressMode ? _ProgressPill(
            text: progressText!,
            filled: progressFilled ?? 0,
            total: progressTotal ?? 1,
          ) : _buildButton()),
        ],
      ),
    );
  }

  Widget _buildButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2196F3),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        child: Text(
          label ?? 'Next',
          style: AppTextStyles.h5.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
    );
  }
}

/// Animated progress pill — uses TweenAnimationBuilder for smooth fill.
class _ProgressPill extends StatelessWidget {
  final String text;
  final int filled;
  final int total;

  const _ProgressPill({
    required this.text,
    required this.filled,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (filled / total).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      height: 50,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          // Minimum 72px when filled > 0 so text is readable
          const minFill = 72.0;

          return TweenAnimationBuilder<double>(
            tween: Tween(end: ratio),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, animatedRatio, _) {
              final rawWidth = maxWidth * animatedRatio;
              final fillWidth = filled == 0
                  ? 0.0
                  : rawWidth.clamp(minFill, maxWidth);

              return Container(
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAEDF1),
                  borderRadius: BorderRadius.circular(30),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Blue fill
                    Container(
                      width: fillWidth,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D47A1),
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    // Text inside blue area
                    if (fillWidth > 0)
                      Positioned(
                        left: 0,
                        width: fillWidth,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Text(
                            text,
                            style: AppTextStyles.h5.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

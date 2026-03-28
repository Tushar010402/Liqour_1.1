import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../services/brand_onboarding_service.dart';

/// Professional Brand Import Success Dialog with Animations
class BrandImportSuccessDialog extends StatefulWidget {
  final BrandImportResult result;
  final String? shopName;

  const BrandImportSuccessDialog({
    super.key,
    required this.result,
    this.shopName,
  });

  static Future<void> show(
    BuildContext context,
    BrandImportResult result, {
    String? shopName,
  }) {
    // Haptic feedback for success
    HapticFeedback.mediumImpact();

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BrandImportSuccessDialog(
        result: result,
        shopName: shopName,
      ),
    );
  }

  @override
  State<BrandImportSuccessDialog> createState() => _BrandImportSuccessDialogState();
}

class _BrandImportSuccessDialogState extends State<BrandImportSuccessDialog>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _confettiController;
  late AnimationController _slideController;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  final List<_ConfettiParticle> _particles = [];

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _confettiController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    // Start animations
    _scaleController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _slideController.forward();
    });
  }

  bool _confettiGenerated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_confettiGenerated && widget.result.successCount > 0) {
      _confettiGenerated = true;
      final cs = Theme.of(context).colorScheme;
      _generateConfetti(cs);
      _confettiController.forward();
    }
  }

  void _generateConfetti(ColorScheme cs) {
    final random = math.Random();
    for (int i = 0; i < 50; i++) {
      _particles.add(_ConfettiParticle(
        color: [
          cs.primary,
          AppColors.success,
          AppColors.warning,
          AppColors.info,
          AppColors.primaryLight,
        ][random.nextInt(5)],
        x: random.nextDouble(),
        y: random.nextDouble() * -0.5,
        velocityX: (random.nextDouble() - 0.5) * 2,
        velocityY: random.nextDouble() * 3 + 2,
        size: random.nextDouble() * 10 + 5,
      ));
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _confettiController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasErrors = widget.result.errorCount > 0;
    final successCount = widget.result.successCount;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Confetti overlay
                  if (successCount > 0)
                    AnimatedBuilder(
                      animation: _confettiController,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _ConfettiPainter(
                            particles: _particles,
                            progress: _confettiController.value,
                          ),
                          size: Size.infinite,
                        );
                      },
                    ),

                  // Content
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with icon
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: hasErrors
                                ? [AppColors.warning, AppColors.warning.withValues(alpha: 0.8)]
                                : [cs.primary, cs.primary.withValues(alpha: 0.8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Animated icon
                            TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 800),
                              tween: Tween(begin: 0, end: 1),
                              builder: (context, value, child) {
                                return Transform.rotate(
                                  angle: value * 2 * math.pi,
                                  child: Icon(
                                    hasErrors
                                        ? Icons.warning_amber_rounded
                                        : Icons.celebration,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              hasErrors
                                  ? 'Import Completed with Warnings'
                                  : 'Brands Imported Successfully!',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.shopName != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.store,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Shop: ${widget.shopName}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Statistics
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Column(
                            children: [
                              // Summary cards
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatCard(
                                      'Total Rows',
                                      widget.result.totalRows.toString(),
                                      Icons.receipt_long,
                                      AppColors.info,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildStatCard(
                                      'Success',
                                      successCount.toString(),
                                      Icons.check_circle,
                                      AppColors.success,
                                    ),
                                  ),
                                  if (hasErrors) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildStatCard(
                                        'Errors',
                                        widget.result.errorCount.toString(),
                                        Icons.error,
                                        AppColors.error,
                                      ),
                                    ),
                                  ],
                                ],
                              ),

                              // Imported brands preview
                              if (widget.result.importedBrands.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: cs.outlineVariant.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.local_offer,
                                            color: cs.primary,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Imported Brands',
                                                  style: AppTextStyles.h6.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (widget.shopName != null)
                                                  Text(
                                                    'Stock added to ${widget.shopName}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: cs.onSurfaceVariant,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      ...widget.result.importedBrands
                                          .take(3)
                                          .map((brand) => _buildBrandTile(cs, brand)),
                                      if (widget.result.importedBrands.length > 3) ...[
                                        const SizedBox(height: 8),
                                        Center(
                                          child: Text(
                                            '+ ${widget.result.importedBrands.length - 3} more brands',
                                            style: TextStyle(
                                              color: cs.onSurfaceVariant,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],

                              // Error details (if any)
                              if (widget.result.errors.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.error.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.warning,
                                            color: AppColors.error,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Import Errors',
                                            style: TextStyle(
                                              color: AppColors.error,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...widget.result.errors.take(2).map(
                                            (error) => Padding(
                                              padding: const EdgeInsets.only(bottom: 4),
                                              child: Text(
                                                'Row ${error.row}: ${error.message}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Actions
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (successCount > 0) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    // Navigate to stock setup
                                  },
                                  icon: const Icon(Icons.inventory),
                                  label: const Text('Add Stock'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.check),
                                label: Text(successCount > 0 ? 'Done' : 'Close'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cs.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandTile(ColorScheme cs, ImportedBrandData brand) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withValues(alpha: 0.8),
                  cs.primary,
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                brand.brandName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brand.brandName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  '${brand.category} \u2022 ${brand.size} \u2022 \u20B9${brand.mrp}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: AppColors.success,
                ),
                const SizedBox(width: 4),
                Text(
                  'Added',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Confetti particle class
class _ConfettiParticle {
  final Color color;
  double x;
  double y;
  final double velocityX;
  final double velocityY;
  final double size;

  _ConfettiParticle({
    required this.color,
    required this.x,
    required this.y,
    required this.velocityX,
    required this.velocityY,
    required this.size,
  });

  void update(double progress) {
    x += velocityX * 0.01;
    y += velocityY * 0.01 * progress;
  }
}

// Confetti painter
class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;

    for (var particle in particles) {
      particle.update(progress);

      if (particle.y > 1.2) continue;

      final paint = Paint()
        ..color = particle.color.withValues(alpha: 1 - progress * 0.8)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(
            particle.x * size.width,
            particle.y * size.height,
          ),
          width: particle.size,
          height: particle.size * 0.7,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) => true;
}

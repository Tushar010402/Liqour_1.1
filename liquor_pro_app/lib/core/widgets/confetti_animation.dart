import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Confetti Animation Widget
///
/// PHASE 5.2: Success Celebration
/// Lightweight confetti animation without external dependencies
///
/// USAGE:
/// ```dart
/// // Show confetti overlay
/// showConfetti(context);
///
/// // Or use widget directly
/// ConfettiAnimation(
///   onComplete: () => Navigator.pop(context),
/// )
/// ```

/// Show confetti overlay
void showConfetti(BuildContext context, {VoidCallback? onComplete}) {
  showDialog(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: false,
    builder: (context) => ConfettiAnimation(
      onComplete: () {
        Navigator.of(context).pop();
        onComplete?.call();
      },
    ),
  );
}

class ConfettiAnimation extends StatefulWidget {
  final VoidCallback? onComplete;
  final Duration duration;

  const ConfettiAnimation({
    super.key,
    this.onComplete,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<ConfettiAnimation> createState() => _ConfettiAnimationState();
}

class _ConfettiAnimationState extends State<ConfettiAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // Generate random particles
    _particles = List.generate(
      80, // Number of confetti pieces
      (index) => ConfettiParticle(
        color: _randomColor(),
        position: Offset(
          math.Random().nextDouble(),
          -0.1, // Start above screen
        ),
        velocity: Offset(
          (math.Random().nextDouble() - 0.5) * 0.5, // Random horizontal
          math.Random().nextDouble() * 0.8 + 0.2, // Downward
        ),
        rotation: math.Random().nextDouble() * math.pi * 2,
        rotationSpeed: (math.Random().nextDouble() - 0.5) * 4,
        size: math.Random().nextDouble() * 8 + 4,
        shape: math.Random().nextBool()
            ? ConfettiShape.rectangle
            : ConfettiShape.circle,
      ),
    );

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _randomColor() {
    final colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.yellow,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.teal,
    ];
    return colors[math.Random().nextInt(colors.length)];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
          ),
          child: Container(),
        );
      },
    );
  }
}

class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> particles;
  final double progress;

  ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final paint = Paint()
        ..color = particle.color.withOpacity(
          (1 - progress).clamp(0.0, 1.0), // Fade out
        )
        ..style = PaintingStyle.fill;

      // Calculate current position
      final x = (particle.position.dx + particle.velocity.dx * progress) * size.width;
      final y = (particle.position.dy + particle.velocity.dy * progress) * size.height;

      // Calculate current rotation
      final rotation = particle.rotation + particle.rotationSpeed * progress * math.pi * 2;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      // Draw particle based on shape
      switch (particle.shape) {
        case ConfettiShape.rectangle:
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: particle.size,
              height: particle.size * 1.5,
            ),
            paint,
          );
          break;
        case ConfettiShape.circle:
          canvas.drawCircle(
            Offset.zero,
            particle.size / 2,
            paint,
          );
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) => true;
}

class ConfettiParticle {
  final Color color;
  final Offset position; // 0-1 normalized
  final Offset velocity; // Movement per second
  final double rotation; // Initial rotation
  final double rotationSpeed; // Rotation per second
  final double size;
  final ConfettiShape shape;

  ConfettiParticle({
    required this.color,
    required this.position,
    required this.velocity,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.shape,
  });
}

enum ConfettiShape {
  rectangle,
  circle,
}

/// Success celebration with confetti + message
void showSuccessCelebration(
  BuildContext context, {
  required String message,
  String? subtitle,
  IconData icon = Icons.check_circle_rounded,
  VoidCallback? onComplete,
}) {
  // Show confetti first
  showConfetti(context);

  // Show success dialog on top
  Future.delayed(const Duration(milliseconds: 300), () {
    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (context) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.green,
                    size: 48,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              // Close button
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Close confetti
                  onComplete?.call();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Awesome!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  });
}

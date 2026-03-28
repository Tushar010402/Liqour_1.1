import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';

/// Overlay widget shown during OCR processing
class OCRProcessingOverlay extends StatelessWidget {
  final Animation<double> scanAnimation;
  final String message;

  const OCRProcessingOverlay({
    super.key,
    required this.scanAnimation,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: 0.9),
            cs.primary.withValues(alpha: 0.95),
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated scanner
              SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background circle
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                    ),

                    // Receipt icon
                    Icon(
                      Icons.receipt_long,
                      size: 60,
                      color: Colors.white,
                    ),

                    // Animated scan line
                    AnimatedBuilder(
                      animation: scanAnimation,
                      builder: (context, child) {
                        return Positioned(
                          top: 20 + (scanAnimation.value * 160),
                          left: 20,
                          right: 20,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.white,
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Corner brackets
                    ..._buildCornerBrackets(),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Processing message
              Text(
                message,
                style: AppTextStyles.h5.copyWith(
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 16),

              // Loading indicator
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),

              const SizedBox(height: 40),

              // Tips
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'AI-Powered Recognition',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Using advanced OCR to identify products\nand extract quantities automatically',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCornerBrackets() {
    const bracketSize = 40.0;
    const bracketThickness = 3.0;
    const bracketLength = 15.0;

    return [
      // Top-left
      Positioned(
        top: 0,
        left: 0,
        child: SizedBox(
          width: bracketSize,
          height: bracketSize,
          child: Stack(
            children: [
              Container(
                width: bracketLength,
                height: bracketThickness,
                color: Colors.white,
              ),
              Container(
                width: bracketThickness,
                height: bracketLength,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
      // Top-right
      Positioned(
        top: 0,
        right: 0,
        child: SizedBox(
          width: bracketSize,
          height: bracketSize,
          child: Stack(
            children: [
              Positioned(
                right: 0,
                child: Container(
                  width: bracketLength,
                  height: bracketThickness,
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 0,
                child: Container(
                  width: bracketThickness,
                  height: bracketLength,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      // Bottom-left
      Positioned(
        bottom: 0,
        left: 0,
        child: SizedBox(
          width: bracketSize,
          height: bracketSize,
          child: Stack(
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: bracketLength,
                  height: bracketThickness,
                  color: Colors.white,
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  width: bracketThickness,
                  height: bracketLength,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
      // Bottom-right
      Positioned(
        bottom: 0,
        right: 0,
        child: SizedBox(
          width: bracketSize,
          height: bracketSize,
          child: Stack(
            children: [
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: bracketLength,
                  height: bracketThickness,
                  color: Colors.white,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: bracketThickness,
                  height: bracketLength,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }
}
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';

/// Confidence Visualization Dashboard
///
/// FEATURES:
/// - Distribution chart showing confidence tiers
/// - Interactive slider to filter by threshold
/// - Color-coded confidence levels (green/yellow/red)
/// - Quick stats: average confidence, counts per tier
/// - Tap chart to filter by tier
/// - Smooth animations
///
/// USAGE:
/// ```dart
/// ConfidenceDashboard(
///   items: deduplicatedItems,
///   onThresholdChanged: (threshold) {
///     // Filter items by confidence >= threshold
///   },
/// )
/// ```
class ConfidenceDashboard extends StatefulWidget {
  final List<DeduplicatedItem> items;
  final double initialThreshold;
  final ValueChanged<double>? onThresholdChanged;
  final ValueChanged<ConfidenceTier>? onTierTapped;

  const ConfidenceDashboard({
    super.key,
    required this.items,
    this.initialThreshold = 0.0,
    this.onThresholdChanged,
    this.onTierTapped,
  });

  @override
  State<ConfidenceDashboard> createState() => _ConfidenceDashboardState();
}

class _ConfidenceDashboardState extends State<ConfidenceDashboard> {
  late double _threshold;
  int _touchedIndex = -1;

  @override
  void initState() {
    super.initState();
    _threshold = widget.initialThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stats = _calculateStats();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.analytics_rounded,
                  color: AppColors.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Confidence Analysis',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Stats Cards
          _buildStatsCards(stats),

          const SizedBox(height: 20),

          // Pie Chart
          _buildPieChart(stats),

          const SizedBox(height: 20),

          // Threshold Slider
          _buildThresholdSlider(stats),

          const SizedBox(height: 12),

          // Legend
          _buildLegend(stats),
        ],
      ),
    );
  }

  /// Build quick stats cards
  Widget _buildStatsCards(ConfidenceStats stats) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Average',
            value: '${(stats.averageConfidence * 100).toInt()}%',
            color: _getConfidenceColor(stats.averageConfidence),
            icon: Icons.speed_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            label: 'Total',
            value: '${stats.totalItems}',
            color: AppColors.info,
            icon: Icons.inventory_2_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            label: 'Above ${(_threshold * 100).toInt()}%',
            value: '${stats.aboveThreshold}',
            color: AppColors.success,
            icon: Icons.check_circle_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build pie chart showing confidence distribution
  Widget _buildPieChart(ConfidenceStats stats) {
    final cs = Theme.of(context).colorScheme;

    if (stats.totalItems == 0) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No data to display',
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 180,
      child: PieChart(
        PieChartData(
          pieTouchData: PieTouchData(
            touchCallback: (FlTouchEvent event, pieTouchResponse) {
              setState(() {
                if (!event.isInterestedForInteractions ||
                    pieTouchResponse == null ||
                    pieTouchResponse.touchedSection == null) {
                  _touchedIndex = -1;
                  return;
                }
                _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
              });
            },
          ),
          borderData: FlBorderData(show: false),
          sectionsSpace: 2,
          centerSpaceRadius: 50,
          sections: _buildPieChartSections(stats),
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(ConfidenceStats stats) {
    final sections = <PieChartSectionData>[];
    int sectionIndex = 0;

    // High confidence (80-100%)
    if (stats.highCount > 0) {
      sections.add(_buildPieSection(
        index: sectionIndex++,
        value: stats.highCount.toDouble(),
        title: '${stats.highCount}',
        color: AppColors.success,
        tier: ConfidenceTier.high,
      ));
    }

    // Medium confidence (50-80%)
    if (stats.mediumCount > 0) {
      sections.add(_buildPieSection(
        index: sectionIndex++,
        value: stats.mediumCount.toDouble(),
        title: '${stats.mediumCount}',
        color: AppColors.warning,
        tier: ConfidenceTier.medium,
      ));
    }

    // Low confidence (0-50%)
    if (stats.lowCount > 0) {
      sections.add(_buildPieSection(
        index: sectionIndex++,
        value: stats.lowCount.toDouble(),
        title: '${stats.lowCount}',
        color: AppColors.error,
        tier: ConfidenceTier.low,
      ));
    }

    return sections;
  }

  PieChartSectionData _buildPieSection({
    required int index,
    required double value,
    required String title,
    required Color color,
    required ConfidenceTier tier,
  }) {
    final isTouched = _touchedIndex == index;
    final radius = isTouched ? 65.0 : 55.0;

    return PieChartSectionData(
      value: value,
      title: title,
      titleStyle: TextStyle(
        fontSize: isTouched ? 18 : 14,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      color: color,
      radius: radius,
      badgeWidget: isTouched
          ? GestureDetector(
              onTap: () {
                widget.onTierTapped?.call(tier);
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.touch_app_rounded,
                  size: 16,
                  color: color,
                ),
              ),
            )
          : null,
      badgePositionPercentageOffset: 1.3,
    );
  }

  /// Build threshold slider
  Widget _buildThresholdSlider(ConfidenceStats stats) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Confidence Threshold',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getConfidenceColor(_threshold).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(_threshold * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _getConfidenceColor(_threshold),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _getConfidenceColor(_threshold),
            inactiveTrackColor: cs.outlineVariant,
            thumbColor: _getConfidenceColor(_threshold),
            overlayColor: _getConfidenceColor(_threshold).withOpacity(0.2),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: _threshold,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: (value) {
              setState(() {
                _threshold = value;
              });
              widget.onThresholdChanged?.call(value);
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '0%',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              '50%',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              '100%',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build legend
  Widget _buildLegend(ConfidenceStats stats) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        _buildLegendItem(
          color: AppColors.success,
          label: 'High (80-100%)',
          count: stats.highCount,
          tier: ConfidenceTier.high,
          cs: cs,
        ),
        const SizedBox(height: 8),
        _buildLegendItem(
          color: AppColors.warning,
          label: 'Medium (50-80%)',
          count: stats.mediumCount,
          tier: ConfidenceTier.medium,
          cs: cs,
        ),
        const SizedBox(height: 8),
        _buildLegendItem(
          color: AppColors.error,
          label: 'Low (0-50%)',
          count: stats.lowCount,
          tier: ConfidenceTier.low,
          cs: cs,
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int count,
    required ConfidenceTier tier,
    required ColorScheme cs,
  }) {
    return InkWell(
      onTap: () {
        widget.onTierTapped?.call(tier);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Calculate confidence statistics
  ConfidenceStats _calculateStats() {
    if (widget.items.isEmpty) {
      return ConfidenceStats(
        totalItems: 0,
        highCount: 0,
        mediumCount: 0,
        lowCount: 0,
        averageConfidence: 0.0,
        aboveThreshold: 0,
      );
    }

    int highCount = 0;
    int mediumCount = 0;
    int lowCount = 0;
    double totalConfidence = 0.0;
    int aboveThreshold = 0;

    for (final item in widget.items) {
      final confidence = item.matchConfidence ?? 0.0;
      totalConfidence += confidence;

      if (confidence >= 0.8) {
        highCount++;
      } else if (confidence >= 0.5) {
        mediumCount++;
      } else {
        lowCount++;
      }

      if (confidence >= _threshold) {
        aboveThreshold++;
      }
    }

    return ConfidenceStats(
      totalItems: widget.items.length,
      highCount: highCount,
      mediumCount: mediumCount,
      lowCount: lowCount,
      averageConfidence: totalConfidence / widget.items.length,
      aboveThreshold: aboveThreshold,
    );
  }

  /// Get color based on confidence value
  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) {
      return AppColors.success;
    } else if (confidence >= 0.5) {
      return AppColors.warning;
    } else {
      return AppColors.error;
    }
  }
}

/// Confidence statistics model
class ConfidenceStats {
  final int totalItems;
  final int highCount;
  final int mediumCount;
  final int lowCount;
  final double averageConfidence;
  final int aboveThreshold;

  ConfidenceStats({
    required this.totalItems,
    required this.highCount,
    required this.mediumCount,
    required this.lowCount,
    required this.averageConfidence,
    required this.aboveThreshold,
  });
}

/// Confidence tier enum
enum ConfidenceTier {
  high,
  medium,
  low,
}

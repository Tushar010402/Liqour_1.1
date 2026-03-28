import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../features/inventory/models/product.dart' as models;
import '../../features/sales/models/daily_sales_models.dart';
import '../../features/sales/models/sale.dart' as sale_models;
import '../../features/sales/services/daily_sales_service.dart';
import '../../features/sales/screens/daily_sales_entry_screen.dart';
import '../services/auth_service.dart';
import '../../features/sales/widgets/receipt_table_widget.dart';
import '../../features/sales/widgets/ai_product_issue_popup.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../utils/formatters.dart';
import 'sale_details/sale_details_ai_insights.dart';
import 'sale_details/sale_details_image_viewer.dart';

/// Typedef for backward compatibility with private _AIBulletPoint references
typedef _AIBulletPoint = AIBulletPoint;

/// Modern iOS 16-style bottom sheet modal to display sale details with product list
class SaleDetailsModal extends StatefulWidget {
  final DailySalesRecord record;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onEdit;
  final bool showActions;

  const SaleDetailsModal({
    super.key,
    required this.record,
    this.onApprove,
    this.onReject,
    this.onEdit,
    this.showActions = false,
  });

  /// Show the modal as a bottom sheet
  static Future<void> show(
    BuildContext context,
    DailySalesRecord record, {
    VoidCallback? onApprove,
    VoidCallback? onReject,
    VoidCallback? onEdit,
    bool showActions = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SaleDetailsModal(
        record: record,
        onApprove: onApprove,
        onReject: onReject,
        onEdit: onEdit,
        showActions: showActions,
      ),
    );
  }

  @override
  State<SaleDetailsModal> createState() => _SaleDetailsModalState();
}

class _SaleDetailsModalState extends State<SaleDetailsModal> {
  bool _isTableView = true; // Default to table view

  // Edit mode state
  bool _isEditMode = false;
  bool _isSaving = false;
  final bool _isLoadingProducts = false;

  // Selected date for editing
  late DateTime _selectedDate;

  // All products for the shop (loaded in edit mode)
  List<models.Product> _allProducts = [];
  Map<String, models.Stock> _stockMap = {};

  // Quantity controllers for each product item
  final Map<String, TextEditingController> _quantityControllers = {};

  // Payment controllers
  late TextEditingController _cashController;
  late TextEditingController _cardController;
  late TextEditingController _upiController;
  late TextEditingController _creditController;

  // Location address state (Swiggy/Zomato style reverse geocoding)
  String? _locationAddress;
  bool _isLoadingAddress = false;

  // AI Validation state
  AIValidationResult? _aiValidation;
  bool _isLoadingAIValidation = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.record.recordDate;
    _cashController = TextEditingController();
    _cardController = TextEditingController();
    _upiController = TextEditingController();
    _creditController = TextEditingController();

    // Fetch address from coordinates if location exists (Swiggy/Zomato style)
    if (widget.record.hasLocation) {
      _fetchLocationAddress();
    }

    // Fetch AI validation if record has images (requires OCR)
    if (widget.record.hasImages && widget.record.id != null) {
      _fetchAIValidation();
    }
  }

  /// Fetch AI validation results from backend
  Future<void> _fetchAIValidation() async {
    if (widget.record.id == null) return;

    setState(() => _isLoadingAIValidation = true);

    try {
      final authService = context.read<AuthService>();
      final dailySalesService = DailySalesService(authService);

      print('🤖 [SaleDetailsModal] Fetching AI validation for ${widget.record.id}');
      final response = await dailySalesService.getValidation(widget.record.id!);

      if (mounted && response.success && response.data != null) {
        setState(() {
          _aiValidation = response.data;
          _isLoadingAIValidation = false;
        });
        print('✅ [SaleDetailsModal] AI validation loaded:');
        print('   - Accuracy: ${_aiValidation?.overallAccuracy}%');
        print('   - Critical: ${_aiValidation?.criticalCount}');
        print('   - Warning: ${_aiValidation?.warningCount}');
        print('   - Per-item insights: ${_aiValidation?.perItemInsights.length}');
      } else {
        if (mounted) setState(() => _isLoadingAIValidation = false);
        print('⚠️ [SaleDetailsModal] No AI validation: ${response.error}');
      }
    } catch (e) {
      print('❌ [SaleDetailsModal] AI validation error: $e');
      if (mounted) setState(() => _isLoadingAIValidation = false);
    }
  }

  /// Get AI insight for a specific product
  ItemInsight? _getItemInsight(String productId) {
    if (_aiValidation == null) return null;
    try {
      return _aiValidation!.perItemInsights.firstWhere(
        (insight) => insight.productId == productId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get validation color for a product based on AI insight
  Color _getValidationColor(String productId) {
    final insight = _getItemInsight(productId);
    if (insight == null) return Colors.transparent;

    if (insight.isCritical) return const Color(0xFFFF3B30); // iOS red
    if (insight.isWarning) return const Color(0xFFFF9500); // iOS orange
    if (insight.isMatched) return const Color(0xFF34C759); // iOS green
    return Colors.transparent;
  }

  /// Build the AI Validation Score Banner - Hinglish bullet points style
  Widget _buildAIValidationBanner() {
    // Loading state
    if (_isLoadingAIValidation) {
      return SliverToBoxAdapter(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF667EEA).withValues(alpha:0.1),
                const Color(0xFF764BA2).withValues(alpha:0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'AI check ho raha hai...',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    // No validation available
    if (_aiValidation == null || _aiValidation!.aiSummary == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final summary = _aiValidation!.aiSummary!;
    final accuracy = summary.overallAccuracy;

    // Color based on accuracy
    final Color accentColor = accuracy >= 80
        ? const Color(0xFF34C759)
        : accuracy >= 50
            ? const Color(0xFFFF9500)
            : const Color(0xFFFF3B30);

    // Build Hinglish bullet points
    final List<_AIBulletPoint> bulletPoints = _buildHinglishBulletPoints(summary);

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha:0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha:0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with score
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha:0.1),
                    accentColor.withValues(alpha:0.05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  // AI icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  // Score
                  Text(
                    '${accuracy.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Match Score',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  // Quick counts
                  _buildMiniCount(Icons.cancel, summary.criticalCount, const Color(0xFFFF3B30)),
                  const SizedBox(width: 6),
                  _buildMiniCount(Icons.warning_amber, summary.warningCount, const Color(0xFFFF9500)),
                  const SizedBox(width: 6),
                  _buildMiniCount(Icons.check_circle, summary.matchedCount, const Color(0xFF34C759)),
                ],
              ),
            ),

            // Hinglish bullet points
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: bulletPoints.map((bp) => _buildBulletPointRow(bp)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mini count badge for header
  Widget _buildMiniCount(IconData icon, int count, Color color) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  /// Build Hinglish bullet points from AI summary - using issue type breakdown
  List<_AIBulletPoint> _buildHinglishBulletPoints(AISummary summary) {
    final List<_AIBulletPoint> points = [];

    // Missing entries - items in receipt but NOT entered by salesman (CRITICAL)
    if (summary.missingEntryCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.cancel,
        color: const Color(0xFFFF3B30),
        text: '${summary.missingEntryCount} item receipt mein hai but entry nahi ki',
      ));
    }

    // Quantity mismatch (CRITICAL)
    if (summary.quantityMismatchCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.cancel,
        color: const Color(0xFFFF3B30),
        text: '${summary.quantityMismatchCount} item mein quantity galat hai',
      ));
    }

    // Price mismatch (WARNING)
    if (summary.priceMismatchCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.warning_amber,
        color: const Color(0xFFFF9500),
        text: '${summary.priceMismatchCount} item mein rate/price galat hai',
      ));
    }

    // Stock mismatch (WARNING)
    if (summary.stockMismatchCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.warning_amber,
        color: const Color(0xFFFF9500),
        text: '${summary.stockMismatchCount} item mein stock mismatch hai',
      ));
    }

    // Items entered but NOT in receipt (WARNING)
    if (summary.notInReceiptCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.warning_amber,
        color: const Color(0xFFFF9500),
        text: '${summary.notInReceiptCount} item entry ki but receipt mein nahi mila',
      ));
    }

    // Matched items
    if (summary.matchedCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.check_circle,
        color: const Color(0xFF34C759),
        text: '${summary.matchedCount} item sahi hai - Receipt se match ho gaya',
      ));
    }

    // Fallback: If no specific breakdown but has critical/warning counts
    if (points.isEmpty && summary.criticalCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.cancel,
        color: const Color(0xFFFF3B30),
        text: '${summary.criticalCount} item check karo - Kuch galat hai',
      ));
    }
    if (points.where((p) => p.color == const Color(0xFFFF9500)).isEmpty && summary.warningCount > 0) {
      points.add(_AIBulletPoint(
        icon: Icons.warning_amber,
        color: const Color(0xFFFF9500),
        text: '${summary.warningCount} item check karo - Thoda doubt hai',
      ));
    }

    // Add recommendation based on accuracy
    if (summary.overallAccuracy < 50) {
      points.add(_AIBulletPoint(
        icon: Icons.lightbulb,
        color: Colors.amber,
        text: 'Dobara check karo - Bahut zyada galti hai is entry mein',
      ));
    } else if (summary.overallAccuracy < 80 && points.length > 1) {
      points.add(_AIBulletPoint(
        icon: Icons.lightbulb,
        color: Colors.amber,
        text: 'Product pe tap karke red/orange dot dekho - wahi galti hai',
      ));
    }

    return points;
  }

  /// Show AI product issue popup when user taps on status indicator
  void _showProductAIPopup(String productId, ItemInsight insight) {
    AIProductIssuePopup.show(context, insight);
  }

  /// Build a single bullet point row
  Widget _buildBulletPointRow(_AIBulletPoint bp) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            child: Icon(bp.icon, size: 16, color: bp.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bp.text,
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build issue count chip for the banner (legacy - keeping for compatibility)
  Widget _buildIssueCountChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Build a single issue row showing entered vs OCR value comparison
  Widget _buildIssueRow(AIIssue issue) {
    final cs = Theme.of(context).colorScheme;
    final issueColor = issue.isCritical
        ? const Color(0xFFFF3B30) // iOS red
        : const Color(0xFFFF9500); // iOS orange

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: issueColor.withValues(alpha:0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Issue header with severity
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: issueColor.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      issue.isCritical ? Icons.error : Icons.warning_amber,
                      color: issueColor,
                      size: 10,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      issue.isCritical ? 'CRITICAL' : 'WARNING',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: issueColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.message.isNotEmpty ? issue.message : 'Data mismatch detected',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),

          // Value comparison: Entered vs OCR
          if (issue.enteredValue.isNotEmpty || issue.ocrValue.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  // Entered value (what user typed)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'YOU ENTERED',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: issueColor.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: issueColor.withValues(alpha:0.3)),
                          ),
                          child: Text(
                            issue.enteredValue.isNotEmpty ? issue.enteredValue : '-',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: issueColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Arrow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward,
                      color: cs.onSurfaceVariant,
                      size: 16,
                    ),
                  ),

                  // OCR value (what AI detected from receipt)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'RECEIPT SHOWS',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF34C759).withValues(alpha:0.3)),
                          ),
                          child: Text(
                            issue.ocrValue.isNotEmpty ? issue.ocrValue : '-',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF34C759),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Suggestion
          if (issue.suggestion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Colors.amber[700],
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    issue.suggestion,
                    style: TextStyle(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Build the missing items section - items detected on receipt but not entered
  Widget _buildMissingItemsSection() {
    if (_aiValidation == null || _aiValidation!.missingItemsGrouped.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final groups = _aiValidation!.missingItemsGrouped;
    final totalMissing = groups.fold<int>(0, (sum, g) => sum + g.count);

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9500).withValues(alpha:0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFF9500).withValues(alpha:0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withValues(alpha:0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500).withValues(alpha:0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.search_off,
                      color: Color(0xFFFF9500),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Missing from Entry',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF9500),
                          ),
                        ),
                        Text(
                          'AI found $totalMissing item${totalMissing > 1 ? 's' : ''} on receipt not in your entry',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9500),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$totalMissing',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Missing items grouped by severity
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (var group in groups)
                    _buildMissingItemGroup(group),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build a group of missing items by severity
  Widget _buildMissingItemGroup(MissingItemGroup group) {
    final isCritical = group.severity == 'critical';
    final color = isCritical
        ? const Color(0xFFFF3B30)
        : const Color(0xFFFF9500);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Row(
            children: [
              Icon(
                isCritical ? Icons.error : Icons.warning_amber,
                color: color,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                '${group.count} ${isCritical ? 'Critical' : 'Warning'} Missing',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Item list
          ...group.items.map((item) => _buildMissingItemRow(item, color)),
        ],
      ),
    );
  }

  /// Build a single missing item row
  Widget _buildMissingItemRow(MissingItem item, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha:0.2)),
      ),
      child: Row(
        children: [
          // Item info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.brand.isNotEmpty ? item.brand : 'Unknown Brand',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.size.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.size,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Quantity from OCR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Qty: ${item.ocrQuantity}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),

          // Price if available
          if (item.ocrPrice > 0) ...[
            const SizedBox(width: 8),
            Text(
              Formatters.currency(item.ocrPrice),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Dispose quantity controllers
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    // Dispose payment controllers
    _cashController.dispose();
    _cardController.dispose();
    _upiController.dispose();
    _creditController.dispose();
    super.dispose();
  }

  /// Enter edit mode - Navigate to Daily Sale Entry screen with pre-filled data
  /// BEST PRACTICE: Use full-screen page for editing instead of modal
  Future<void> _enterEditMode() async {
    // Close the modal first
    Navigator.pop(context);

    // Navigate to Daily Sale Entry screen with the record for editing
    // The screen will handle pre-filling all fields from the record
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DailySalesEntryScreen(
          showHeader: true,
          editRecord: widget.record,
        ),
      ),
    );

    // Trigger refresh callback when returning (in case changes were made)
    widget.onEdit?.call();
  }

  /// Exit edit mode - clear controllers
  void _exitEditMode() {
    // Dispose and clear quantity controllers
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _quantityControllers.clear();

    // Clear product data
    _allProducts = [];
    _stockMap = {};

    // Clear payment controllers (don't dispose, they're reusable)
    _cashController.clear();
    _cardController.clear();
    _upiController.clear();
    _creditController.clear();

    // Reset date
    _selectedDate = widget.record.recordDate;

    setState(() => _isEditMode = false);
  }

  /// Show date picker for editing sale date
  Future<void> _selectDate() async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: cs.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  /// Calculate total from current input values
  double _calculateEditTotal() {
    double total = 0;
    for (var product in _allProducts) {
      final qtyText = _quantityControllers[product.id]?.text ?? '0';
      final qty = int.tryParse(qtyText) ?? 0;
      total += qty * product.sellingPrice;
    }
    return total;
  }

  /// Check if only the date was changed (items are same as original)
  bool _isOnlyDateChanged() {
    // Check if date is different
    final originalDate = widget.record.recordDate;
    final dateChanged = !_isSameDay(originalDate, _selectedDate);

    if (!dateChanged) {
      return false; // Date not changed, so it's not "only date changed"
    }

    // Check if items quantities are same as original
    final originalItems = widget.record.items;
    for (var originalItem in originalItems) {
      final currentQty = int.tryParse(
        _quantityControllers[originalItem.productId]?.text ?? '0',
      ) ?? 0;
      if (currentQty != originalItem.quantity) {
        return false; // Item quantity changed
      }
    }

    // Check if any new items were added (products not in original but have qty > 0)
    final originalProductIds = originalItems.map((i) => i.productId).toSet();
    for (var product in _allProducts) {
      if (!originalProductIds.contains(product.id)) {
        final qty = int.tryParse(_quantityControllers[product.id]?.text ?? '0') ?? 0;
        if (qty > 0) {
          return false; // New item added
        }
      }
    }

    return true; // Only date was changed
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Save changes to the server
  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      // Use DailySalesService for daily sales records (correct endpoint: /api/sales/daily-sales/{id})
      final dailySalesService = DailySalesService(context.read<AuthService>());

      // ═══════════════════════════════════════════════════════════════════════════
      // CRITICAL: Check if ONLY the date was changed
      // If so, use the dedicated change-date API to prevent accidental item modification
      // This fixes the bug where changing date could corrupt the sale items
      // ═══════════════════════════════════════════════════════════════════════════
      if (_isOnlyDateChanged()) {
        debugPrint('📅 Only date changed - using dedicated change-date API');
        debugPrint('   Old date: ${widget.record.recordDate}');
        debugPrint('   New date: $_selectedDate');

        final response = await dailySalesService.changeDailySalesRecordDate(
          widget.record.id ?? '',
          newDate: _selectedDate,
          reason: 'Date correction via sale details modal',
        );

        if (response.success && response.data != null) {
          // Trigger refresh callback
          widget.onEdit?.call();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Date changed successfully to ${DateFormat.yMMMd().format(_selectedDate)}'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            Navigator.pop(context);
          }
        } else {
          throw Exception(response.error ?? 'Failed to change date');
        }
        return; // Early return - don't proceed with full update
      }

      // ═══════════════════════════════════════════════════════════════════════════
      // Items were also modified - use full update API
      // ═══════════════════════════════════════════════════════════════════════════
      debugPrint('📝 Items modified - using full update API');

      // Build updated items list from ALL products (not just original sale items)
      final List<DailySalesItemRequest> updatedItems = [];
      double totalSalesAmount = 0;
      for (var product in _allProducts) {
        final qtyText = _quantityControllers[product.id]?.text ?? '0';
        final qty = int.tryParse(qtyText) ?? 0;
        if (qty > 0) {
          final itemTotal = qty * product.sellingPrice;
          totalSalesAmount += itemTotal;
          // Note: Backend requires item-level payment breakdown to match total_amount
          // For edit mode, we default all item amounts to cash (will be recalculated below)
          updatedItems.add(DailySalesItemRequest(
            productId: product.id,
            quantity: qty,
            unitPrice: product.sellingPrice,
            totalAmount: itemTotal,
            cashAmount: itemTotal, // Default: full amount as cash
            cardAmount: 0,
            upiAmount: 0,
            creditAmount: 0,
          ));
        }
      }

      // Validate: Must have at least one item with quantity > 0
      if (updatedItems.isEmpty) {
        throw Exception('Please add at least one product with quantity greater than 0');
      }

      // Validate: Total sales amount must be > 0
      if (totalSalesAmount <= 0) {
        throw Exception('Total sales amount must be greater than 0');
      }

      // Get payment amounts from controllers
      double cashAmount = double.tryParse(_cashController.text) ?? 0;
      double cardAmount = double.tryParse(_cardController.text) ?? 0;
      double upiAmount = double.tryParse(_upiController.text) ?? 0;
      double creditAmount = double.tryParse(_creditController.text) ?? 0;

      // Validate: Payment amounts must match total sales amount
      final totalPayments = cashAmount + cardAmount + upiAmount + creditAmount;
      if ((totalPayments - totalSalesAmount).abs() > 0.01) {
        // Payment amounts don't match - auto-adjust cash to balance
        // This handles the case where items were changed but payment fields weren't updated
        debugPrint('⚠️ Payment mismatch detected:');
        debugPrint('   Total sales: $totalSalesAmount');
        debugPrint('   Total payments: $totalPayments');

        // Reset payments to match the new total - put everything in cash by default
        cashAmount = totalSalesAmount;
        cardAmount = 0;
        upiAmount = 0;
        creditAmount = 0;

        debugPrint('   Auto-adjusted: Cash=$cashAmount');
      }

      // Debug logging
      debugPrint('📝 Saving daily sales update:');
      debugPrint('   Record ID: ${widget.record.id}');
      debugPrint('   Shop ID: ${widget.record.shopId}');
      debugPrint('   Items: ${updatedItems.length}');
      debugPrint('   Total Sales: $totalSalesAmount');
      debugPrint('   Payments: Cash=$cashAmount, Card=$cardAmount, UPI=$upiAmount, Credit=$creditAmount');

      // Create request with updated data
      final request = DailySalesRecordRequest(
        shopId: widget.record.shopId,
        recordDate: _selectedDate,
        items: updatedItems,
        totalSalesAmount: totalSalesAmount,
        totalCashAmount: cashAmount,
        totalCardAmount: cardAmount,
        totalUpiAmount: upiAmount,
        totalCreditAmount: creditAmount,
        notes: widget.record.notes ?? '',
        imageUrls: widget.record.imageUrls,
      );

      // Check if record is rejected - use CREATE instead of UPDATE
      // Backend blocks updates to rejected records (must create a copy instead)
      final isRejected = widget.record.status.toLowerCase() == 'rejected';

      if (isRejected) {
        // For rejected records, create a NEW record with the corrected data
        debugPrint('📋 Record is rejected - creating new submission instead of update');

        final createResponse = await dailySalesService.createDailySalesRecord(request);

        if (createResponse.success) {
          // Trigger refresh callback
          widget.onEdit?.call();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('New sale record created successfully! (Rejected record cannot be updated)'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            Navigator.pop(context);
          }
        } else {
          throw Exception(createResponse.error ?? 'Failed to create new sale record');
        }
      } else {
        // For non-rejected records, use normal update
        final response = await dailySalesService.updateDailySalesRecord(
          widget.record.id ?? '',
          request,
        );

        if (response.success) {
          // Trigger refresh callback
          widget.onEdit?.call();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Sale updated successfully'),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            Navigator.pop(context);
          }
        } else {
          throw Exception(response.error ?? 'Failed to update sale');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        onTap: () {}, // Prevent dismissal when tapping content
        child: DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha:0.95),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.15),
                    blurRadius: 40,
                    offset: const Offset(0, -10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Column(
                    children: [
                      // Drag handle and header
                      _buildHeader(context),

                      // Scrollable content
                      Expanded(
                        child: CustomScrollView(
                          controller: scrollController,
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            // User Attribution Section (Created by, Approved by, etc.)
                            _buildUserAttributionSection(),

                            // AI Validation Score Banner (if images exist)
                            if (widget.record.hasImages)
                              _buildAIValidationBanner(),

                            // Location Section (prominent for manager review)
                            _buildLocationSection(),

                            // Attached Images Gallery (if images exist)
                            if (widget.record.hasImages)
                              _buildImagesSection(),

                            // Product list (shows editable rows in edit mode)
                            _buildProductList(),

                            // Payment summary OR editable payment section
                            if (_isEditMode)
                              _buildEditablePaymentSection()
                            else
                              _buildPaymentSummary(),

                            // Edit section (hidden in edit mode - actions in header)
                            if (!_isEditMode) _buildEditSection(context),

                            // Approval action buttons (only for pending sales with showActions, hidden in edit mode)
                            if (!_isEditMode &&
                                widget.showActions &&
                                widget.record.status.toLowerCase() == 'pending')
                              _buildActionButtons(context),

                            // Bottom padding
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: widget.showActions ? 100 : 32,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha:0.8),
        border: Border(
          bottom: BorderSide(
            color: cs.outline.withValues(alpha:0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header content
          Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // Title and info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isEditMode ? 'Edit Sale' : 'Sale Details',
                      style: AppTextStyles.h4.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Shop name row
                    if (widget.record.shopName != null) ...[
                      Text(
                        widget.record.shopName!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                    ],
                    // Date and status row - wrapped to prevent overflow
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Date - editable in edit mode
                        if (_isEditMode)
                          InkWell(
                            onTap: _selectDate,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 10,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat(
                                      'MMM d, yyyy',
                                    ).format(_selectedDate),
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    Icons.edit,
                                    size: 10,
                                    color: cs.primary,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Text(
                            DateFormat(
                              'MMM d, yyyy',
                            ).format(widget.record.recordDate),
                            style: AppTextStyles.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                        _buildStatusBadge(),
                      ],
                    ),
                  ],
                ),
              ),

              // Edit mode actions OR regular actions
              if (_isEditMode) ...[
                // Compact action buttons for edit mode
                IconButton(
                  onPressed: _isSaving ? null : _exitEditMode,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHighest,
                    foregroundColor: cs.onSurfaceVariant,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                  tooltip: 'Cancel',
                ),
                const SizedBox(width: 8),
                // Save button - compact
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveChanges,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Save', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ] else ...[
                // Toggle view button
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isTableView = !_isTableView;
                    });
                  },
                  icon: Icon(
                    _isTableView
                        ? Icons.view_list_rounded
                        : Icons.table_chart_rounded,
                    color: cs.primary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primary.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  tooltip: _isTableView ? 'Card View' : 'Table View',
                ),
                const SizedBox(width: 8),

                // Close button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final isApproved = widget.record.status.toLowerCase() == 'approved';
    final color = isApproved ? AppColors.success : AppColors.warning;
    final text = widget.record.status.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha:0.3), width: 1),
      ),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 9,
        ),
      ),
    );
  }

  Widget _buildProductList() {
    // Edit mode - show editable rows for ALL products with stock
    if (_isEditMode) {
      // Show loading indicator
      if (_isLoadingProducts) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading products...',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Filter products with stock > 0 OR products already in the sale
      final productsWithStock = _allProducts.where((product) {
        final stock = _stockMap[product.id];
        final hasStock = stock != null && stock.quantity > 0;
        // Also include products that were originally in the sale (even if stock is now 0)
        final wasInSale = widget.record.items.any(
          (item) => item.productId == product.id,
        );
        return hasStock || wasInSale;
      }).toList();

      // Count products with qty > 0 set
      final itemsInSale = productsWithStock.where((p) {
        final qty = int.tryParse(_quantityControllers[p.id]?.text ?? '0') ?? 0;
        return qty > 0;
      }).length;

      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Row(
                children: [
                  Text(
                    'Edit Products',
                    style: AppTextStyles.h5.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$itemsInSale in sale',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${productsWithStock.length} available',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.info,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Table Header - Compact with Stock column
              Builder(
                builder: (context) {
                  final cs = Theme.of(context).colorScheme;
                  return Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 28), // Avatar space
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Product',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        'Stock',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Price',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        'Qty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                  );
                },
              ),

              // Editable product rows - ALL products with stock
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < productsWithStock.length; i++)
                      _buildEditableProductRowFromProduct(
                        productsWithStock[i],
                        i,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isTableView) {
      // Convert DailySalesRecord to Sale for table view
      final sale = _convertToSale();
      final hasAIInsights = _aiValidation != null && _aiValidation!.perItemInsights.isNotEmpty;

      final cs = Theme.of(context).colorScheme;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Products Table',
                    style: AppTextStyles.h5.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.record.items.length} items',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              // AI Validation hint - tap colored dots for details
              if (hasAIInsights) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF667EEA).withValues(alpha:0.08),
                        const Color(0xFF764BA2).withValues(alpha:0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hint text
                      Row(
                        children: [
                          Icon(Icons.touch_app, size: 14, color: const Color(0xFF667EEA)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Colored dot pe tap karo - AI details dikhega',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Legend row - responsive wrap
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle)),
                              const SizedBox(width: 2),
                              Text('Galat', style: TextStyle(fontSize: 8, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFFF9500), shape: BoxShape.circle)),
                              const SizedBox(width: 2),
                              Text('Check', style: TextStyle(fontSize: 8, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF34C759), shape: BoxShape.circle)),
                              const SizedBox(width: 2),
                              Text('Sahi', style: TextStyle(fontSize: 8, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Table view with AI validation indicators
              ReceiptTableWidget(
                sale: sale,
                showHeader: false,
                showPaymentDetails: false,
                groupBySize: false,
                aiValidation: _aiValidation,
                onAIStatusTap: _showProductAIPopup,
              ),
            ],
          ),
        ),
      );
    } else {
      // Card view
      final cs = Theme.of(context).colorScheme;
      final hasAIInsights = _aiValidation != null && _aiValidation!.perItemInsights.isNotEmpty;

      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        'Products',
                        style: AppTextStyles.h5.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasAIInsights) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.auto_awesome, color: Colors.white, size: 10),
                              SizedBox(width: 4),
                              Text(
                                'AI',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${widget.record.items.length} items',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Product cards
              ...widget.record.items.map((item) => _buildProductCard(item)),
            ],
          ),
        ),
      );
    }
  }

  sale_models.Sale _convertToSale() {
    return sale_models.Sale(
      id: widget.record.id ?? '',
      saleNumber:
          'DSR-${DateFormat('yyyyMMdd').format(widget.record.recordDate)}',
      shopId: widget.record.shopId,
      saleDate: widget.record.recordDate,
      customerName: null,
      customerPhone: null,
      subTotal: widget.record.totalSalesAmount,
      discountAmount: 0,
      taxAmount: 0,
      totalAmount: widget.record.totalSalesAmount,
      paidAmount: widget.record.totalSalesAmount,
      dueAmount: 0,
      paymentMethod: 'mixed',
      paymentStatus: 'paid',
      status: widget.record.status,
      approvedAt: widget.record.approvedAt,
      createdAt: widget.record.createdAt ?? DateTime.now(),
      updatedAt: widget.record.updatedAt ?? DateTime.now(),
      items: widget.record.items
          .map(
            (item) => sale_models.SaleItem(
              id: item.id ?? '',
              saleId: widget.record.id ?? '',
              productId: item.productId,
              productName: item.productName,
              brandName: item.brandName,
              categoryName: item.categoryName,
              size: item.size,
              sku: null,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              totalPrice: item.totalAmount,
              discountAmount: 0,
              openingStock: item.openingStock,
              closingStock: item.closingStock,
            ),
          )
          .toList(),
    );
  }

  Widget _buildProductCard(DailySalesItem item) {
    final cs = Theme.of(context).colorScheme;
    // Get AI validation insight for this product
    final insight = _getItemInsight(item.productId);
    final hasAIValidation = insight != null;
    final validationColor = _getValidationColor(item.productId);
    final showValidationBorder = hasAIValidation && validationColor != Colors.transparent;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: showValidationBorder
              ? validationColor.withValues(alpha:0.5)
              : cs.outline.withValues(alpha:0.3),
          width: showValidationBorder ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: showValidationBorder
                ? validationColor.withValues(alpha:0.1)
                : Colors.black.withValues(alpha:0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product icon with validation indicator
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(item.categoryName).withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getCategoryIcon(item.categoryName),
                      color: _getCategoryColor(item.categoryName),
                      size: 20,
                    ),
                  ),
                  // AI validation status dot
                  if (hasAIValidation)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: validationColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: validationColor.withValues(alpha:0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          insight.isMatched
                              ? Icons.check
                              : insight.isCritical
                                  ? Icons.close
                                  : Icons.priority_high,
                          color: Colors.white,
                          size: 8,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name with size
                    Text(
                      item.productName ?? item.brandName ?? 'Product',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Category and brand
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.categoryName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.categoryName!,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        if (item.size != null)
                          Text(
                            item.size!,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),

                    // AI Validation Badge
                    if (hasAIValidation) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: validationColor.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: validationColor.withValues(alpha:0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              insight.isMatched
                                  ? Icons.verified
                                  : insight.isCritical
                                      ? Icons.error
                                      : Icons.warning_amber,
                              color: validationColor,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              insight.isMatched
                                  ? 'AI Verified'
                                  : '${insight.issueCount} Issue${insight.issueCount > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: validationColor,
                              ),
                            ),
                            if (!insight.isMatched) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${insight.matchConfidence.toStringAsFixed(0)}%',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                  color: validationColor.withValues(alpha:0.8),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Quantity badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha:0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Qty: ${item.quantity}',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Divider
          Container(height: 1, color: cs.outline.withValues(alpha:0.2)),

          const SizedBox(height: 12),

          // Pricing info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${Formatters.currency(item.unitPrice)} × ${item.quantity}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                Formatters.currency(item.totalAmount),
                style: AppTextStyles.h6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ),

          // AI Issues Section - Show inline issues for this product
          if (hasAIValidation && insight.hasIssues) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: validationColor.withValues(alpha:0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: validationColor.withValues(alpha:0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: validationColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'AI Found Issues',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: validationColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Issue list
                  ...insight.issues.map((issue) => _buildIssueRow(issue)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build editable product row (similar to DailySalesEntryScreen pattern)
  Widget _buildEditableProductRow(DailySalesItem item, int index) {
    final cs = Theme.of(context).colorScheme;
    // Ensure controller exists
    if (!_quantityControllers.containsKey(item.productId)) {
      _quantityControllers[item.productId] = TextEditingController(
        text: item.quantity.toString(),
      );
    }

    return Container(
      color: index % 2 == 0 ? cs.surface : cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Product Avatar - Compact
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _getCategoryColor(item.categoryName).withValues(alpha:0.12),
                  _getCategoryColor(item.categoryName).withValues(alpha:0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                (item.brandName ?? item.productName ?? 'P')[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _getCategoryColor(item.categoryName),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Product Name - Flexible
          Expanded(
            flex: 3,
            child: Text(
              item.productName ?? item.brandName ?? 'Product',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Size Badge - Flexible
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha:0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.size ?? '-',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppColors.info,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Price - Flexible
          Expanded(
            flex: 1,
            child: Text(
              '₹${item.unitPrice.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),

          // Quantity Input - Fixed width (minimum needed)
          SizedBox(
            width: 48,
            height: 30,
            child: TextField(
              controller: _quantityControllers[item.productId],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: cs.outlineVariant, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: cs.outlineVariant, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                isDense: true,
              ),
              onChanged: (_) =>
                  setState(() {}), // Trigger rebuild for total calculation
            ),
          ),
        ],
      ),
    );
  }

  /// Build editable product row from Product model (for all products view)
  Widget _buildEditableProductRowFromProduct(
    models.Product product,
    int index,
  ) {
    final cs = Theme.of(context).colorScheme;
    // Ensure controller exists
    if (!_quantityControllers.containsKey(product.id)) {
      _quantityControllers[product.id] = TextEditingController(text: '0');
    }

    final stock = _stockMap[product.id];
    final stockQty = stock?.quantity ?? 0;
    final currentQty =
        int.tryParse(_quantityControllers[product.id]?.text ?? '0') ?? 0;
    final isInSale = currentQty > 0;
    final categoryName = product.category?.name;
    final brandName = product.brand?.name;

    return Container(
      color: isInSale
          ? AppColors.success.withValues(alpha:0.05)
          : (index % 2 == 0 ? cs.surface : cs.surfaceContainerHighest),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // Product Avatar - Compact
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  _getCategoryColor(categoryName).withValues(alpha:0.12),
                  _getCategoryColor(categoryName).withValues(alpha:0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                (brandName ?? product.name)[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _getCategoryColor(categoryName),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Product Name - Flexible
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isInSale ? AppColors.success : cs.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  product.size,
                  style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Stock Badge
          SizedBox(
            width: 36,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: stockQty > 0
                    ? AppColors.success.withValues(alpha:0.1)
                    : AppColors.error.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$stockQty',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: stockQty > 0 ? AppColors.success : AppColors.error,
                ),
              ),
            ),
          ),

          // Price - Flexible
          Expanded(
            flex: 1,
            child: Text(
              '₹${product.sellingPrice.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),

          // Quantity Input - Fixed width (minimum needed)
          SizedBox(
            width: 48,
            height: 30,
            child: TextField(
              controller: _quantityControllers[product.id],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isInSale ? AppColors.success : cs.onSurface,
              ),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                filled: true,
                fillColor: isInSale
                    ? AppColors.success.withValues(alpha:0.1)
                    : cs.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isInSale ? AppColors.success : cs.outlineVariant,
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: isInSale ? AppColors.success : cs.outlineVariant,
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                isDense: true,
              ),
              onChanged: (_) =>
                  setState(() {}), // Trigger rebuild for total calculation
            ),
          ),
        ],
      ),
    );
  }

  /// Build editable payment section
  Widget _buildEditablePaymentSection() {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.05),
              AppColors.info.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Payment Breakdown',
                  style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Payment input fields
            _buildPaymentInputRow(
              icon: Icons.money_rounded,
              label: 'Cash',
              controller: _cashController,
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            _buildPaymentInputRow(
              icon: Icons.credit_card_rounded,
              label: 'Card',
              controller: _cardController,
              color: AppColors.info,
            ),
            const SizedBox(height: 12),
            _buildPaymentInputRow(
              icon: Icons.qr_code_scanner_rounded,
              label: 'UPI',
              controller: _upiController,
              color: AppColors.warning,
            ),
            const SizedBox(height: 12),
            _buildPaymentInputRow(
              icon: Icons.account_balance_rounded,
              label: 'Credit',
              controller: _creditController,
              color: AppColors.neutral,
            ),

            const SizedBox(height: 16),

            // Divider
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withValues(alpha: 0.1),
                    cs.primary.withValues(alpha: 0.3),
                    cs.primary.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Total (calculated from items)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Items Total',
                  style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    Formatters.currency(_calculateEditTotal()),
                    style: AppTextStyles.h4.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual payment input row
  Widget _buildPaymentInputRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 120,
          height: 40,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              prefixText: '₹ ',
              prefixStyle: TextStyle(color: color, fontWeight: FontWeight.w500),
              filled: true,
              fillColor: color.withValues(alpha:0.08),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: color.withValues(alpha:0.2), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: color, width: 2),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentSummary() {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary.withValues(alpha: 0.05),
              AppColors.info.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Payment Summary',
                  style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Payment methods
            if (widget.record.totalCashAmount > 0)
              _buildPaymentRow(
                icon: Icons.money_rounded,
                label: 'Cash',
                amount: widget.record.totalCashAmount,
                color: AppColors.success,
              ),
            if (widget.record.totalCardAmount > 0)
              _buildPaymentRow(
                icon: Icons.credit_card_rounded,
                label: 'Card',
                amount: widget.record.totalCardAmount,
                color: AppColors.info,
              ),
            if (widget.record.totalUpiAmount > 0)
              _buildPaymentRow(
                icon: Icons.qr_code_scanner_rounded,
                label: 'UPI',
                amount: widget.record.totalUpiAmount,
                color: AppColors.warning,
              ),
            if (widget.record.totalCreditAmount > 0)
              _buildPaymentRow(
                icon: Icons.account_balance_rounded,
                label: 'Credit',
                amount: widget.record.totalCreditAmount,
                color: AppColors.neutral,
              ),

            // Expenses Section (if any)
            if (widget.record.hasExpenses) ...[
              const SizedBox(height: 16),

              // Expenses Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.error,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Expenses',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${widget.record.expenses.length} items',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Individual expense entries
              ...widget.record.expenses.map((expense) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha:0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        expense.headerName,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      '- ${Formatters.currency(expense.amount)}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              )),

              // Total Expenses
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha:0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Expenses',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    Text(
                      '- ${Formatters.currency(widget.record.totalExpenseAmount)}',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Divider
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withValues(alpha: 0.1),
                    cs.primary.withValues(alpha: 0.3),
                    cs.primary.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Total with net calculation if expenses exist
            if (widget.record.hasExpenses) ...[
              // Gross Sales
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Gross Sales',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Formatters.currency(widget.record.totalSalesAmount),
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Less Expenses
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Less: Expenses',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                  Text(
                    '- ${Formatters.currency(widget.record.totalExpenseAmount)}',
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Net Cash Collected
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Net Cash',
                      style: AppTextStyles.h5.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      Formatters.currency(widget.record.totalSalesAmount - widget.record.totalExpenseAmount),
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // No expenses - show simple total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Amount',
                    style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      Formatters.currency(widget.record.totalSalesAmount),
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow({
    required IconData icon,
    required String label,
    required double amount,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            Formatters.currency(amount),
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for category-based styling
  IconData _getCategoryIcon(String? category) {
    if (category == null) return Icons.inventory_2_rounded;

    final cat = category.toLowerCase();
    if (cat.contains('beer')) return Icons.sports_bar_rounded;
    if (cat.contains('wine')) return Icons.wine_bar_rounded;
    if (cat.contains('whisky') || cat.contains('whiskey')) {
      return Icons.liquor_rounded;
    }
    if (cat.contains('vodka')) return Icons.local_bar_rounded;
    if (cat.contains('rum')) return Icons.local_drink_rounded;

    return Icons.local_bar_rounded;
  }

  Color _getCategoryColor(String? category) {
    if (category == null) return AppColors.neutral;

    final cat = category.toLowerCase();
    if (cat.contains('beer')) return AppColors.warning;
    if (cat.contains('wine')) return AppColors.exciseColor;
    if (cat.contains('whisky') || cat.contains('whiskey')) {
      return AppColors.info;
    }
    if (cat.contains('vodka')) return AppColors.success;
    if (cat.contains('rum')) return AppColors.error;

    return Theme.of(context).colorScheme.primary;
  }

  /// Get edit button label based on status
  String _getEditButtonLabel() {
    final status = widget.record.status.toLowerCase();
    if (status == 'rejected') {
      return 'Edit & Resubmit';
    }
    return 'Edit Sale';
  }

  /// Get edit button color based on status
  Color _getEditButtonColor() {
    final status = widget.record.status.toLowerCase();
    if (status == 'rejected') {
      return AppColors.warning;
    }
    return Theme.of(context).colorScheme.primary;
  }

  /// Build edit section for all sale statuses
  Widget _buildEditSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outline.withValues(alpha:0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Title
            Row(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  color: _getEditButtonColor(),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Quick Actions',
                  style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Edit button - triggers inline edit mode
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _enterEditMode,
                icon: Icon(
                  widget.record.status.toLowerCase() == 'rejected'
                      ? Icons.refresh_rounded
                      : Icons.edit_rounded,
                  size: 20,
                ),
                label: Text(_getEditButtonLabel()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getEditButtonColor(),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outline.withValues(alpha:0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Title
            Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Approval Actions',
                  style: AppTextStyles.h6.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                // Reject button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onReject?.call();
                    },
                    icon: const Icon(Icons.cancel_rounded, size: 20),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Approve button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onApprove?.call();
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build user attribution section (Created by, Approved by, Rejected by, etc.)
  Widget _buildUserAttributionSection() {
    final record = widget.record;
    final createdBy = record.createdByName ?? record.salesmanName;
    final status = record.status.toLowerCase();

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha:0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha:0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section title
              Row(
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Record Information',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Created by row
              if (createdBy != null) ...[
                _buildAttributionRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Created by',
                  value: createdBy,
                  timestamp: record.createdAt,
                  color: AppColors.info,
                ),
              ],

              // Salesman row (if different from created by)
              if (record.salesmanName != null &&
                  record.salesmanName != record.createdByName) ...[
                const SizedBox(height: 10),
                _buildAttributionRow(
                  icon: Icons.badge_outlined,
                  label: 'Salesman',
                  value: record.salesmanName!,
                  color: AppColors.neutral,
                ),
              ],

              // Approved by row (for approved status)
              if (status == 'approved' && record.approvedByName != null) ...[
                const SizedBox(height: 10),
                _buildAttributionRow(
                  icon: Icons.check_circle_outline_rounded,
                  label: 'Approved by',
                  value: record.approvedByName!,
                  timestamp: record.approvedAt,
                  color: AppColors.success,
                ),
              ],

              // Rejected by row (for rejected status)
              if (status == 'rejected') ...[
                const SizedBox(height: 10),
                _buildAttributionRow(
                  icon: Icons.cancel_outlined,
                  label: 'Rejected by',
                  value: record.rejectedByName ?? 'Manager',
                  timestamp: record.rejectedAt,
                  color: AppColors.error,
                ),
                // Rejection reason
                if (record.rejectionReason != null &&
                    record.rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha:0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha:0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reason',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                record.rejectionReason!,
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.error.withValues(alpha:0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // Resubmitted by row (if resubmit count > 0)
              if (record.resubmitCount > 0) ...[
                const SizedBox(height: 10),
                _buildAttributionRow(
                  icon: Icons.refresh_rounded,
                  label: 'Resubmitted by',
                  value: record.resubmittedByName ?? createdBy ?? 'Unknown',
                  timestamp: record.resubmittedAt,
                  color: AppColors.warning,
                  badge: 'Attempt ${record.resubmitCount + 1}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build a single attribution row (helper for _buildUserAttributionSection)
  Widget _buildAttributionRow({
    required IconData icon,
    required String label,
    required String value,
    DateTime? timestamp,
    required Color color,
    String? badge,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha:0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (timestamp != null) ...[
          Text(
            Formatters.timeAgo(timestamp),
            style: AppTextStyles.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  /// Build location section for manager review
  Widget _buildLocationSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: widget.record.hasLocation
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha:0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha:0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sale Location',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              Text(
                                'GPS Verified',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.green[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _openInMaps(),
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: const Text('Map'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Address display - Swiggy/Zomato style
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 16,
                          color: Colors.green[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Address - prominent display
                              Text(
                                _isLoadingAddress
                                    ? 'Fetching location...'
                                    : (_locationAddress ?? 'Location captured'),
                                style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green[800],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              // Coordinates - smaller text
                              Wrap(
                                children: [
                                  Text(
                                    '${widget.record.latitude?.toStringAsFixed(4)}, ${widget.record.longitude?.toStringAsFixed(4)}',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: Colors.green[600],
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (widget.record.locationAccuracy !=
                                      null) ...[
                                    Text(
                                      ' • ±${widget.record.locationAccuracy}m',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.green[500],
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
            : Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha:0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha:0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.location_off,
                        color: Colors.orange[700],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location Not Captured',
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[700],
                            ),
                          ),
                          Text(
                            'GPS location was not recorded for this sale',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: Colors.orange[600],
                            ),
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

  /// Build location detail row
  Widget _buildLocationDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.bodySmall.copyWith(color: Colors.green[600]),
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: Colors.green[800],
          ),
        ),
      ],
    );
  }

  /// Build attached images gallery section
  Widget _buildImagesSection() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha:0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.indigo.withValues(alpha:0.2)),
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
                      color: Colors.indigo.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.photo_library_outlined,
                      color: Colors.indigo,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attached Images',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[700],
                          ),
                        ),
                        Text(
                          '${widget.record.imageUrls.length} image(s)',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.indigo[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Image Gallery - Horizontal scrollable
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.record.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    return _buildImageThumbnail(index);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build individual image thumbnail
  Widget _buildImageThumbnail(int index) {
    final imageUrl = _getFullImageUrl(widget.record.imageUrls[index]);
    final totalImages = widget.record.imageUrls.length;

    return GestureDetector(
      onTap: () => _showFullScreenImage(index),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              // Image counter badge
              if (totalImages > 1)
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha:0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${index + 1}/$totalImages',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              // Zoom icon
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha:0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get full image URL (handles relative paths)
  String _getFullImageUrl(String url) {
    if (url.startsWith('http')) return url;
    return 'https://new.v2.floelife.in$url';
  }

  /// Show full-screen image viewer
  void _showFullScreenImage(int initialIndex) {
    final imageUrls = widget.record.imageUrls;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImageViewer(
          imageUrls: imageUrls,
          initialIndex: initialIndex,
          getFullUrl: _getFullImageUrl,
        ),
      ),
    );
  }

  /// Fetch address from coordinates using reverse geocoding (Swiggy/Zomato style)
  Future<void> _fetchLocationAddress() async {
    if (!widget.record.hasLocation) return;

    setState(() => _isLoadingAddress = true);

    try {
      final placemarks = await placemarkFromCoordinates(
        widget.record.latitude!,
        widget.record.longitude!,
      );

      if (placemarks.isNotEmpty && mounted) {
        final place = placemarks.first;
        // Build address like Swiggy/Zomato style - SubLocality, City, State
        final parts = <String>[];
        if (place.subLocality?.isNotEmpty == true) {
          parts.add(place.subLocality!);
        }
        if (place.locality?.isNotEmpty == true) parts.add(place.locality!);
        if (place.administrativeArea?.isNotEmpty == true) {
          parts.add(place.administrativeArea!);
        }

        setState(() {
          _locationAddress = parts.isNotEmpty
              ? parts.join(', ')
              : 'Location captured';
          _isLoadingAddress = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching address: $e');
      if (mounted) {
        setState(() {
          _locationAddress = 'Location captured';
          _isLoadingAddress = false;
        });
      }
    }
  }

  /// Open location in Maps app
  Future<void> _openInMaps() async {
    if (!widget.record.hasLocation) return;

    final lat = widget.record.latitude!;
    final lng = widget.record.longitude!;
    final googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final appleMapsUrl = Uri.parse('https://maps.apple.com/?q=$lat,$lng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(appleMapsUrl)) {
        await launchUrl(appleMapsUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Handle error silently
      debugPrint('Error opening maps: $e');
    }
  }

  /// Check if item is Beer based on category or product name
  bool _isItemBeer(DailySalesItem item) {
    final category = (item.categoryName ?? '').toLowerCase();
    final productName = (item.productName ?? '').toLowerCase();

    // Check category name
    if (category.contains('beer') ||
        category.contains('lager') ||
        category.contains('ale') ||
        category.contains('stout')) {
      return true;
    }

    // Fallback: Check product name for common beer brands
    final beerBrands = [
      'kingfisher', 'budweiser', 'heineken', 'corona', 'carlsberg',
      'tuborg', 'bira', 'amstel', 'foster', 'miller', 'stella',
      'hoegaarden', 'bro code', 'haywards', 'knockout', 'godfather',
      'kalyani', 'simba', 'white owl', 'medusa', 'breezer', 'god father'
    ];
    return beerBrands.any((brand) => productName.contains(brand));
  }

  /// Extract numeric size value from size string (e.g., "500ML" -> 500)
  int _extractSizeValue(String? size) {
    if (size == null) return 0;
    final numMatch = RegExp(r'(\d+)').firstMatch(size);
    if (numMatch != null) {
      return int.tryParse(numMatch.group(0)!) ?? 0;
    }
    return 0;
  }
}

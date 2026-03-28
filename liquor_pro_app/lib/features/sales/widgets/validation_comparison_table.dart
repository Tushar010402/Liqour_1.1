import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../core/utils/formatters.dart';
import '../models/daily_sales_models.dart';

/// Validation Comparison Table Widget
/// Shows side-by-side comparison of entered data vs OCR-extracted data
class ValidationComparisonTable extends StatelessWidget {
  final DailySalesRecord record;
  final AIValidationResult validationResult;

  const ValidationComparisonTable({
    super.key,
    required this.record,
    required this.validationResult,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary header
        _buildSummaryHeader(context),
        const SizedBox(height: 16),

        // Items comparison list
        if (validationResult.mismatches.isNotEmpty) ...[
          _buildSectionTitle('Mismatches Found', CupertinoIcons.exclamationmark_triangle_fill, Colors.orange),
          const SizedBox(height: 8),
          ...validationResult.mismatches.map((mismatch) => _buildMismatchCard(context, mismatch)),
        ],

        // Matched items section
        if (validationResult.matchedCount > 0) ...[
          const SizedBox(height: 16),
          _buildSectionTitle('Verified Items', CupertinoIcons.checkmark_circle_fill, Colors.green),
          const SizedBox(height: 8),
          _buildMatchedItemsCount(context),
        ],
      ],
    );
  }

  Widget _buildSummaryHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isVerified = validationResult.status == 'verified';
    final hasMismatches = validationResult.status == 'mismatches_found';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVerified
            ? Colors.green.withOpacity(0.08)
            : hasMismatches
                ? Colors.orange.withOpacity(0.08)
                : cs.onSurfaceVariant.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVerified
              ? Colors.green.withOpacity(0.3)
              : hasMismatches
                  ? Colors.orange.withOpacity(0.3)
                  : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isVerified
                  ? Colors.green.withOpacity(0.15)
                  : hasMismatches
                      ? Colors.orange.withOpacity(0.15)
                      : cs.onSurfaceVariant.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isVerified
                  ? CupertinoIcons.checkmark_shield_fill
                  : hasMismatches
                      ? CupertinoIcons.exclamationmark_triangle_fill
                      : CupertinoIcons.clock_fill,
              color: isVerified
                  ? Colors.green
                  : hasMismatches
                      ? Colors.orange
                      : cs.onSurfaceVariant,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          // Status text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVerified
                      ? 'All Items Verified'
                      : hasMismatches
                          ? '${validationResult.mismatchCount} Mismatch${validationResult.mismatchCount > 1 ? 'es' : ''} Found'
                          : 'Validation Pending',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isVerified
                        ? Colors.green[800]
                        : hasMismatches
                            ? Colors.orange[800]
                            : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${validationResult.matchedCount} of ${validationResult.totalItems} items matched',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ],
      );
    });
  }

  Widget _buildMismatchCard(BuildContext context, AIValidationMismatch mismatch) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item header with mismatch type badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mismatch.enteredBrand ?? mismatch.ocrBrand ?? 'Unknown Item',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      if (mismatch.size != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          mismatch.size!,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildMismatchTypeBadge(mismatch.mismatchType),
              ],
            ),
          ),
          // Comparison table
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildComparisonRow(mismatch),
          ),
        ],
      ),
    );
  }

  Widget _buildMismatchTypeBadge(String type) {
    final (label, color) = _getMismatchTypeStyle(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  (String, Color) _getMismatchTypeStyle(String type) {
    switch (type) {
      case 'quantity':
        return ('QTY', Colors.orange);
      case 'price':
        return ('PRICE', Colors.purple);
      case 'brand':
        return ('BRAND', Colors.blue);
      case 'missing_entry':
        return ('MISSING', Colors.red);
      case 'missing_receipt':
        return ('NOT IN RECEIPT', Colors.red);
      default:
        return ('MISMATCH', Colors.orange);
    }
  }

  Widget _buildComparisonRow(AIValidationMismatch mismatch) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Row(
      children: [
        // Entered Data Column
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.pencil, size: 12, color: Colors.blue[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Entered',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (mismatch.enteredBrand != null && mismatch.mismatchType == 'brand') ...[
                  Text(
                    mismatch.enteredBrand!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                ],
                if (mismatch.enteredQuantity != null) ...[
                  _buildValueRow('Qty', '${mismatch.enteredQuantity}',
                      isHighlighted: mismatch.mismatchType == 'quantity'),
                ],
                if (mismatch.enteredPrice != null) ...[
                  _buildValueRow('Price', Formatters.currency(mismatch.enteredPrice!),
                      isHighlighted: mismatch.mismatchType == 'price'),
                ],
                if (mismatch.mismatchType == 'missing_receipt') ...[
                  Text(
                    'Item entered',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // VS indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              shape: BoxShape.circle,
            ),
            child: Text(
              'vs',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
        // Receipt Data Column
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.doc_text_fill, size: 12, color: Colors.green[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Receipt',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (mismatch.ocrBrand != null && mismatch.mismatchType == 'brand') ...[
                  Text(
                    mismatch.ocrBrand!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                ],
                if (mismatch.ocrQuantity != null) ...[
                  _buildValueRow('Qty', '${mismatch.ocrQuantity}',
                      isHighlighted: mismatch.mismatchType == 'quantity',
                      isCorrect: mismatch.mismatchType == 'quantity'),
                ],
                if (mismatch.ocrPrice != null) ...[
                  _buildValueRow('Price', Formatters.currency(mismatch.ocrPrice!),
                      isHighlighted: mismatch.mismatchType == 'price',
                      isCorrect: mismatch.mismatchType == 'price'),
                ],
                if (mismatch.mismatchType == 'missing_entry') ...[
                  Text(
                    'Found in receipt',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
    });
  }

  Widget _buildValueRow(String label, String value, {bool isHighlighted = false, bool isCorrect = false}) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isHighlighted
                    ? (isCorrect ? Colors.green[700] : Colors.orange[700])
                    : cs.onSurface,
              ),
            ),
            if (isHighlighted) ...[
              const SizedBox(width: 4),
              Icon(
                isCorrect ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.xmark_circle_fill,
                size: 14,
                color: isCorrect ? Colors.green : Colors.orange,
              ),
            ],
          ],
        ),
      ],
    );
    });
  }

  Widget _buildMatchedItemsCount(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.checkmark_alt,
              color: Colors.green[700],
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${validationResult.matchedCount} items matched correctly',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[800],
                  ),
                ),
                Text(
                  'Quantity and price verified against receipt',
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
    );
  }
}

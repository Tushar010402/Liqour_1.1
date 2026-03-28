import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ai_purchase_models.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Bottom sheet for disambiguating a low-confidence or ambiguous AI purchase item.
/// Shows AI-detected info + radio-selectable alternative matches from backend.
///
/// Returns the selected alternative index (0-based) or -1 if skipped.
class PurchaseMatchPicker extends StatefulWidget {
  final SmartPurchaseItem item;

  const PurchaseMatchPicker({
    super.key,
    required this.item,
  });

  /// Show as a modal bottom sheet. Returns selected index or -1 if skipped.
  static Future<int?> show(
    BuildContext context, {
    required SmartPurchaseItem item,
  }) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PurchaseMatchPicker(item: item),
    );
  }

  @override
  State<PurchaseMatchPicker> createState() => _PurchaseMatchPickerState();
}

class _PurchaseMatchPickerState extends State<PurchaseMatchPicker> {
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.item.userSelectedIndex >= 0
        ? widget.item.userSelectedIndex
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final alternatives = item.alternativeMatches;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD0D5DD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Select Correct Product',
              style: _heading(size: 17, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),

          // AI info card
          _buildAIInfoCard(item),
          const SizedBox(height: 12),

          // Candidates list
          if (alternatives.isNotEmpty)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: alternatives.length,
                itemBuilder: (_, i) => _buildCandidateCard(i, alternatives[i]),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No alternative matches found.\nSkip this item or go back.',
                style: _body(size: 13, color: const Color(0xFF888888)),
                textAlign: TextAlign.center,
              ),
            ),

          // Footer
          const Divider(height: 1, color: Color(0xFFE8EAF0)),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, -1),
                  child: Text('Skip',
                    style: _body(size: 14, weight: FontWeight.w600,
                      color: const Color(0xFF888888))),
                ),
                const Spacer(),
                if (alternatives.isNotEmpty)
                  SizedBox(
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, _selectedIndex),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                        ),
                        child: Text('Confirm',
                          style: _body(size: 15, weight: FontWeight.w700,
                            color: Colors.white)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIInfoCard(SmartPurchaseItem item) {
    final qtyLabel = item.quantityUnit == 'cases'
        ? '${item.quantityRaw} cases (${item.quantityBottles} btls)'
        : '${item.quantityBottles} btls';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0D9F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF3855B3)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI detected: ${item.brandName} | ${item.size} | $qtyLabel | \u20B9${item.ratePerBottle.toStringAsFixed(0)}/btl',
              style: _body(size: 12, weight: FontWeight.w600,
                color: const Color(0xFF3855B3)),
              maxLines: 2, overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateCard(int index, AlternativeMatch alt) {
    final isSelected = _selectedIndex == index;
    final scorePercent = (alt.confidence * 100).toInt();

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFE8EAF0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFBDBDBD),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Center(
                      child: CircleAvatar(
                        radius: 6,
                        backgroundColor: Color(0xFF4CAF50),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alt.brandName,
                    style: _body(size: 13.5, weight: FontWeight.w700),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _pill(alt.size, const Color(0xFFE3F2FD), const Color(0xFF1565C0)),
                      const SizedBox(width: 6),
                      Text(
                        'Cost: \u20B9${alt.costPrice.toStringAsFixed(0)}',
                        style: _body(size: 11, color: const Color(0xFF666666)),
                      ),
                      if (alt.currentStock != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          'Stock: ${alt.currentStock}',
                          style: _body(size: 11, color: alt.currentStock! > 0
                              ? const Color(0xFF4CAF50) : const Color(0xFFE53935)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Score bar
                  Row(
                    children: [
                      SizedBox(
                        width: 60, height: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: alt.confidence,
                            backgroundColor: const Color(0xFFE0E0E0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _scoreColor(alt.confidence)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$scorePercent%',
                        style: _body(size: 10, weight: FontWeight.w700,
                          color: _scoreColor(alt.confidence)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: _body(size: 10, weight: FontWeight.w700, color: fg)),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 0.8) return const Color(0xFF4CAF50);
    if (score >= 0.5) return const Color(0xFFFFA726);
    return const Color(0xFFE53935);
  }
}

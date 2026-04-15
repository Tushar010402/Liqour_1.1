import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/bottom_action_bar.dart';
import '../models/smart_sale_models.dart';
import '../services/smart_sale_service.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _bodyText({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

class SalesSummaryItem {
  String productId;
  String name;
  double price;
  int quantity;
  double mrp;
  final int stock;
  int closingStock;
  final String? ocrText;
  bool isManuallyAdded;
  /// Whether item needs user review (low confidence, ambiguous, not found, etc.)
  final bool needsReview;
  final String? reviewReason;
  /// Match status: matched, low_confidence, ambiguous, not_found
  final String matchStatus;
  /// Alternative product candidates the user can pick from
  final List<AlternativeMatch> alternativeMatches;

  SalesSummaryItem({
    this.productId = '',
    required this.name,
    required this.price,
    required this.quantity,
    required this.mrp,
    required this.stock,
    required this.closingStock,
    this.ocrText,
    this.isManuallyAdded = false,
    this.needsReview = false,
    this.reviewReason,
    this.matchStatus = 'matched',
    this.alternativeMatches = const [],
  });
}

/// Represents an OCR-detected item that couldn't be matched to inventory
class SkippedItem {
  final String ocrName;
  final int quantity;
  final double rate;

  const SkippedItem({required this.ocrName, this.quantity = 0, this.rate = 0});
}

class SalesSummaryScreen extends StatefulWidget {
  final List<SalesSummaryItem> items;
  final VoidCallback? onSubmit;
  final void Function(List<SalesSummaryItem>)? onSubmitItems;
  final bool isAIMode;
  final int skippedItemCount;
  final List<SkippedItem> skippedItems;
  final List<SalesSummaryItem> availableProducts;
  final String? shopId;
  final String? saleDate;
  final String? saleCategory;
  final String? saleSize;
  final AuthService? authService;
  final double? processingTime;

  const SalesSummaryScreen({
    super.key,
    required this.items,
    this.onSubmit,
    this.onSubmitItems,
    this.isAIMode = false,
    this.skippedItemCount = 0,
    this.skippedItems = const [],
    this.availableProducts = const [],
    this.shopId,
    this.saleDate,
    this.saleCategory,
    this.saleSize,
    this.authService,
    this.processingTime,
  });

  @override
  State<SalesSummaryScreen> createState() => _SalesSummaryScreenState();
}

class _SalesSummaryScreenState extends State<SalesSummaryScreen> {
  late List<SalesSummaryItem> _items;
  late List<SalesSummaryItem> _allProducts; // Master list of ALL products (summary + available)
  bool _skippedExpanded = false;
  bool _isSubmitting = false;
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    // Build master list: items in summary + available products
    final allIds = <String>{};
    _allProducts = <SalesSummaryItem>[];
    for (final item in widget.items) {
      if (!allIds.contains(item.productId)) {
        _allProducts.add(item);
        allIds.add(item.productId);
      }
    }
    for (final item in widget.availableProducts) {
      if (!allIds.contains(item.productId)) {
        _allProducts.add(item);
        allIds.add(item.productId);
      }
    }
  }

  double get _grandTotal => _items.fold(0.0, (s, i) => s + i.price * i.quantity);
  int get _totalQty => _items.fold(0, (s, i) => s + i.quantity);
  int get _effectiveSkippedCount =>
      widget.skippedItems.isNotEmpty ? widget.skippedItems.length : widget.skippedItemCount;

  String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'\s*-\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*$'), '')
        .trim();
  }

  String _extractSize(String name) {
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML|ltr|LTR|L)', caseSensitive: false).firstMatch(name);
    return match != null ? match.group(0)!.toUpperCase().replaceAll(' ', '') : '';
  }

  // ── Submit via /apply ──

  Future<void> _submitViaApply() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    debugPrint('[SalesSummary] Submit via /apply started');
    debugPrint('[SalesSummary] shopId=${widget.shopId}, date=${widget.saleDate}, category=${widget.saleCategory}, size=${widget.saleSize}');
    debugPrint('[SalesSummary] authService null? ${widget.authService == null}');

    try {
      final service = SmartSaleService(widget.authService!);
      final applyItems = _items.where((i) => i.quantity > 0).map((item) => {
        'product_id': item.productId,
        'brand_name': item.name,
        'quantity': item.quantity,
        'rate': item.price,
        'amount': item.price * item.quantity,
        if (item.ocrText != null) 'ocr_text': item.ocrText,
      }).toList();

      debugPrint('[SalesSummary] Sending ${applyItems.length} items to /apply');

      final response = await service.applySmartSale(
        shopId: widget.shopId!,
        date: widget.saleDate!,
        category: widget.saleCategory!,
        size: widget.saleSize,
        items: applyItems,
      );

      debugPrint('[SalesSummary] /apply response: success=${response.success}, error=${response.error}');

      if (!mounted) return;

      if (response.success) {
        if (widget.onSubmitItems != null) {
          widget.onSubmitItems!(_items);
        }
      } else {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.error ?? 'Failed to submit sale'), backgroundColor: const Color(0xFFD84315)),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[SalesSummary] /apply exception: $e');
      debugPrint('[SalesSummary] stackTrace: $stackTrace');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFD84315)),
      );
    }
  }

  void _handleSubmit() {
    if (widget.isAIMode && widget.shopId != null && widget.saleDate != null && widget.authService != null) {
      _submitViaApply();
    } else if (widget.onSubmitItems != null) {
      widget.onSubmitItems!(_items);
    } else if (widget.onSubmit != null) {
      widget.onSubmit!();
    }
  }

  // ── Edit item (bottom sheet) ──

  void _editItem(int index) {
    final item = _items[index];
    final controller = TextEditingController(text: item.quantity.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text(_cleanName(item.name),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1D26))),
              const SizedBox(height: 4),
              Text('Stock: ${item.stock}  •  MRP: ₹${item.mrp.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Quantity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
                  const Spacer(),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      return Row(
                        children: [
                          _stepBtn('−', () {
                            final cur = int.tryParse(controller.text) ?? 0;
                            if (cur > 0) { controller.text = '${cur - 1}'; setLocalState(() {}); }
                          }),
                          Container(
                            width: 56, height: 40,
                            decoration: const BoxDecoration(
                              border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFD0D5DD))),
                              color: Colors.white,
                            ),
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26)),
                              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10), isDense: true),
                              onChanged: (_) => setLocalState(() {}),
                            ),
                          ),
                          _stepBtn('+', () {
                            final cur = int.tryParse(controller.text) ?? 0;
                            if (cur < item.stock) { controller.text = '${cur + 1}'; setLocalState(() {}); }
                          }),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () { Navigator.pop(ctx); setState(() => _items.removeAt(index)); },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD84315)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Remove', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD84315))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final newQty = int.tryParse(controller.text) ?? 0;
                        Navigator.pop(ctx);
                        if (newQty <= 0) {
                          setState(() => _items.removeAt(index));
                        } else {
                          setState(() { item.quantity = newQty; item.closingStock = item.stock - newQty; });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2962FF), foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0,
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    final isMinus = label == '−';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isMinus ? Colors.white : const Color(0xFF2962FF),
          borderRadius: BorderRadius.horizontal(
            left: isMinus ? const Radius.circular(8) : Radius.zero,
            right: isMinus ? Radius.zero : const Radius.circular(8),
          ),
          border: isMinus ? Border.all(color: const Color(0xFFD0D5DD)) : null,
        ),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isMinus ? const Color(0xFF555555) : Colors.white))),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          _header(context),
          const Divider(height: 1, color: Color(0xFFE8EAF0)),

          // AI summary header (NEW enhancement)
          if (widget.isAIMode) _buildAISummary(),

          // Skipped items (enhanced: collapsible with details)
          if (widget.isAIMode && _effectiveSkippedCount > 0) _buildSkippedSection(),

          // Original item list
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFCCCCCC)),
                        const SizedBox(height: 12),
                        const Text('No items', style: TextStyle(color: Color(0xFF999999), fontSize: 14)),
                        const SizedBox(height: 16),
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _items.length + 1 + (_allProducts.length > _items.length ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i < _items.length) return _row(i, _items[i]);
                      // Add Missing section before Grand Total
                      if (_allProducts.length > _items.length && i == _items.length) return _buildAddMissingSection();
                      return _total();
                    },
                  ),
          ),

          // Original bottom bar — hidden in read-only mode (no onSubmit/onSubmitItems)
          if (_items.isNotEmpty && (widget.onSubmit != null || widget.onSubmitItems != null))
            BottomActionBar(
              label: _isSubmitting ? 'Submitting...' : 'Submit',
              onPressed: _isSubmitting ? null : _handleSubmit,
            ),
        ],
      ),
    );
  }

  // ── Header (original) ──

  Widget _header(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Row(
          children: [
            InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38, height: 38,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3366CC)),
                child: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
              ),
            ),
            Expanded(
              child: Text('Sales Summary',
                textAlign: TextAlign.center,
                style: _heading(size: 18)),
            ),
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE8EEF8),
                border: Border.all(color: const Color(0xFFD0D8E8), width: 1),
              ),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI Summary Header (NEW) ──

  Widget _buildAISummary() {
    final matched = _items.length;
    final totalBottles = _totalQty;
    final categoryLabel = widget.saleCategory == 'beer' ? 'Beer' : 'Whisky';
    final sizeLabel = widget.saleSize ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFF0F4FF), Color(0xFFE8EEFF)]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0D9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF3855B3)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI detected $matched products · $totalBottles btl',
                  style: _bodyText(size: 13, weight: FontWeight.w700, color: const Color(0xFF3855B3)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: [
              _statChip('$matched matched', const Color(0xFF4CAF50)),
              if (_effectiveSkippedCount > 0)
                _statChip('$_effectiveSkippedCount missed', const Color(0xFFE53935)),
              if (sizeLabel.isNotEmpty)
                _statChip('$categoryLabel · $sizeLabel', const Color(0xFF2E7D32)),
              if (widget.processingTime != null)
                _statChip('${widget.processingTime!.toStringAsFixed(1)}s · Fomoa AI', const Color(0xFF888888)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: _bodyText(size: 10, weight: FontWeight.w700, color: color)),
    );
  }

  // ── Skipped Items Section (NEW: collapsible with details) ──

  Widget _buildSkippedSection() {
    final hasDetails = widget.skippedItems.isNotEmpty;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: hasDetails ? () => setState(() => _skippedExpanded = !_skippedExpanded) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFF57C00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_effectiveSkippedCount item${_effectiveSkippedCount > 1 ? 's' : ''} could not be matched and were skipped',
                      style: _bodyText(size: 12, weight: FontWeight.w600, color: const Color(0xFF8D6E00)),
                    ),
                  ),
                  if (hasDetails)
                    Icon(_skippedExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: const Color(0xFF8D6E00)),
                ],
              ),
            ),
          ),
          if (hasDetails && _skippedExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                children: widget.skippedItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 26),
                      Expanded(
                        child: Text('"${item.ocrName}"',
                          style: _bodyText(size: 12, weight: FontWeight.w600, color: const Color(0xFF5D4037)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (item.quantity > 0)
                        Text('Qty: ${item.quantity}',
                          style: _bodyText(size: 12, weight: FontWeight.w700, color: const Color(0xFFF57C00))),
                      if (item.rate > 0) ...[
                        const SizedBox(width: 8),
                        Text('₹${item.rate.toStringAsFixed(0)}',
                          style: _bodyText(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
                      ],
                    ],
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Original Row (preserved) ──

  Widget _row(int idx, SalesSummaryItem it) {
    final clr = it.stock > 20 ? const Color(0xFF2E7D32) : const Color(0xFFD84315);
    final cleaned = _cleanName(it.name);
    final size = _extractSize(it.name);
    final isManual = it.isManuallyAdded;
    final hasReview = it.needsReview && !isManual;
    final hasAlts = it.alternativeMatches.isNotEmpty;

    // Background color based on status
    Color? bgColor;
    if (isManual) {
      bgColor = const Color(0xFFF0FDF4); // green tint
    } else if (hasReview) {
      bgColor = const Color(0xFFFFF8F0); // orange tint
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: Color(0xFFECEEF2))),
        color: bgColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // name + price
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${idx + 1}  ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                  color: isManual ? const Color(0xFF10B981) : const Color(0xFF3366CC))),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(cleaned.isNotEmpty ? cleaned : it.name,
                            style: _bodyText(size: 14, weight: FontWeight.w700),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 4),
                        if (isManual)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('ADDED',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF10B981))),
                          )
                        else if (hasReview)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF57C00).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('REVIEW',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFFF57C00))),
                          ),
                      ],
                    ),
                    if (it.ocrText != null)
                      Text('OCR: ${it.ocrText}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF999999)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text('₹ ${_fmt(it.price * it.quantity)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
            ],
          ),

          // Review reason banner
          if (hasReview && it.reviewReason != null)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFFE0B2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 12, color: Color(0xFFF57C00)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(it.reviewReason!,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFE65100)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            ),

          // Alternative matches (pick a different product)
          if (hasAlts && hasReview)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Did you mean:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF888888))),
                  const SizedBox(height: 3),
                  ...it.alternativeMatches.map((alt) => GestureDetector(
                    onTap: () => _pickAlternative(idx, alt),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD0D9F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(alt.brandName,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3855B3)),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Text('₹${alt.sellingPrice.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3855B3).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('${(alt.confidence * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFF3855B3))),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF3855B3)),
                        ],
                      ),
                    ),
                  )),
                ],
              ),
            ),

          const SizedBox(height: 6),

          // pills
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Row(
              children: [
                SvgPicture.asset('assets/icons/inventory_green_sm2.svg', width: 10, height: 10),
                const SizedBox(width: 2),
                Text('${it.stock} in stock',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: clr)),
                const SizedBox(width: 6),
                _pill('Qyt - ${it.quantity}'),
                const SizedBox(width: 5),
                _pill('MRP - ${it.mrp.toStringAsFixed(0)}'),
                const SizedBox(width: 6),
                SvgPicture.asset('assets/icons/box_closing.svg', width: 10, height: 10,
                  colorFilter: const ColorFilter.mode(Color(0xFF8A8E99), BlendMode.srcIn)),
                const SizedBox(width: 2),
                Text('${it.closingStock} closing stock',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF8A8E99))),
              ],
            ),
          ),
          const SizedBox(height: 5),

          // Edit + Remove (for manual) + size badge
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _editItem(idx),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Text('Edit  \u25B8',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1D26))),
                  ),
                ),
                if (isManual) ...[
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _items.removeAt(idx);
                        _addedCount = (_addedCount - 1).clamp(0, 999);
                      });
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 2),
                      child: Text('Remove',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD84315))),
                    ),
                  ),
                ],
                const Spacer(),
                if (size.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE8F0FE), borderRadius: BorderRadius.circular(4)),
                    child: Text(size,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF3366CC))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Swap current item with an alternative match
  void _pickAlternative(int idx, AlternativeMatch alt) {
    setState(() {
      final item = _items[idx];
      item.productId = alt.productId;
      item.name = alt.brandName;
      item.price = alt.sellingPrice;
      item.mrp = alt.sellingPrice;
      item.closingStock = item.stock - item.quantity;
    });
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5),
      ),
      child: Text(text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
    );
  }

  // ── Add Missing Section (NEW) ──

  Widget _buildAddMissingSection() {
    return GestureDetector(
      onTap: _showAddItemSheet,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 3, height: 16,
              decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text('Add Missing Brands', style: _bodyText(size: 13, weight: FontWeight.w700, color: const Color(0xFF374151))),
            const Spacer(),
            Text('$_addedCount added',
              style: _bodyText(size: 11, weight: FontWeight.w600, color: const Color(0xFF10B981))),
          ],
        ),
      ),
    );
  }

  void _showAddItemSheet() {
    // Dynamically build available list from master list minus current summary items
    final currentIds = _items.map((i) => i.productId).toSet();
    final available = _allProducts
        .where((p) => !currentIds.contains(p.productId))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All products for this size are already added'), duration: Duration(seconds: 2)),
      );
      return;
    }

    final sizeLabel = widget.saleSize ?? '';
    final categoryLabel = widget.saleCategory == 'beer' ? 'Beer' : 'Whisky';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddItemSheet(
        available: available,
        cleanName: _cleanName,
        extractSize: _extractSize,
        sizeLabel: sizeLabel,
        categoryLabel: categoryLabel,
        onAdd: (product, qty) {
          Navigator.pop(ctx);
          setState(() {
            _items.add(SalesSummaryItem(
              productId: product.productId,
              name: product.name,
              price: product.price,
              quantity: qty,
              mrp: product.mrp,
              stock: product.stock,
              closingStock: product.stock - qty,
              isManuallyAdded: true,
            ));
            _addedCount++;
          });
        },
      ),
    );
  }

  // ── Grand Total (original) ──

  Widget _total() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2E8C4)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grand Total', style: _heading(size: 16)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5),
                ),
                child: Text('Total Quantity - $_totalQty',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF777777))),
              ),
            ],
          ),
          const Spacer(),
          Text('₹ ${_fmt(_grandTotal)}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1D26))),
        ],
      ),
    );
  }

  String _fmt(double v) {
    final s = v.toInt().toString();
    if (s.length <= 3) return s;
    final l3 = s.substring(s.length - 3);
    var r = s.substring(0, s.length - 3);
    final p = <String>[];
    while (r.length > 2) { p.insert(0, r.substring(r.length - 2)); r = r.substring(0, r.length - 2); }
    if (r.isNotEmpty) p.insert(0, r);
    return '${p.join(",")},${l3}';
  }
}

// ── Add Item Bottom Sheet ──

class _AddItemSheet extends StatefulWidget {
  final List<SalesSummaryItem> available;
  final String Function(String) cleanName;
  final String Function(String) extractSize;
  final void Function(SalesSummaryItem product, int quantity) onAdd;
  final String sizeLabel;
  final String categoryLabel;

  const _AddItemSheet({
    required this.available,
    required this.cleanName,
    required this.extractSize,
    required this.onAdd,
    this.sizeLabel = '',
    this.categoryLabel = '',
  });

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _searchController = TextEditingController();
  List<SalesSummaryItem> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.available;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.available
          : widget.available.where((p) => p.name.toLowerCase().contains(q)).toList();
    });
  }

  void _selectProduct(SalesSummaryItem product) {
    final qtyController = TextEditingController(text: '1');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(widget.cleanName(product.name),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1D26))),
              const SizedBox(height: 4),
              Text('Stock: ${product.stock}  •  MRP: ₹${product.mrp.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Quantity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
                  const Spacer(),
                  StatefulBuilder(
                    builder: (context, setLocalState) {
                      return Row(
                        children: [
                          _stepBtn('−', () {
                            final cur = int.tryParse(qtyController.text) ?? 0;
                            if (cur > 1) { qtyController.text = '${cur - 1}'; setLocalState(() {}); }
                          }),
                          Container(
                            width: 56, height: 40,
                            decoration: const BoxDecoration(
                              border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFD0D5DD))),
                              color: Colors.white,
                            ),
                            child: TextField(
                              controller: qtyController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26)),
                              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10), isDense: true),
                              onChanged: (_) => setLocalState(() {}),
                            ),
                          ),
                          _stepBtn('+', () {
                            final cur = int.tryParse(qtyController.text) ?? 0;
                            if (cur < product.stock) { qtyController.text = '${cur + 1}'; setLocalState(() {}); }
                          }),
                        ],
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final qty = int.tryParse(qtyController.text) ?? 0;
                    if (qty <= 0) return;
                    Navigator.pop(ctx);
                    widget.onAdd(product, qty);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2962FF), foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0,
                  ),
                  child: const Text('Add Item', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    final isMinus = label == '−';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isMinus ? Colors.white : const Color(0xFF2962FF),
          borderRadius: BorderRadius.horizontal(
            left: isMinus ? const Radius.circular(8) : Radius.zero,
            right: isMinus ? Radius.zero : const Radius.circular(8),
          ),
          border: isMinus ? Border.all(color: const Color(0xFFD0D5DD)) : null,
        ),
        child: Center(child: Text(label,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isMinus ? const Color(0xFF555555) : Colors.white))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasContext = widget.sizeLabel.isNotEmpty || widget.categoryLabel.isNotEmpty;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              // Title + context chips
              Row(
                children: [
                  Text('Add Missing Item', style: _heading(size: 16, weight: FontWeight.w700)),
                  const Spacer(),
                  if (hasContext)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD0D9F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_alt_outlined, size: 12, color: Color(0xFF3855B3)),
                          const SizedBox(width: 4),
                          Text(
                            [widget.categoryLabel, widget.sizeLabel].where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF3855B3)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Search
              TextField(
                controller: _searchController,
                onChanged: _onSearch,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by brand name...',
                  hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                  prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF888888)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: Color(0xFF888888)),
                          onPressed: () { _searchController.clear(); _onSearch(''); },
                        )
                      : null,
                  filled: true, fillColor: const Color(0xFFF5F7FA),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3855B3), width: 1.5)),
                ),
              ),
              const SizedBox(height: 8),
              Text('${_filtered.length} products available',
                style: _bodyText(size: 12, color: const Color(0xFF999999))),
              const SizedBox(height: 4),
              // Product list
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off, size: 40, color: Color(0xFFCCCCCC)),
                            const SizedBox(height: 8),
                            Text('No matching products', style: _bodyText(size: 14, color: const Color(0xFF999999))),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F2)),
                        itemBuilder: (_, i) {
                          final p = _filtered[i];
                          final cleaned = widget.cleanName(p.name);
                          final outOfStock = p.stock <= 0;
                          return Opacity(
                            opacity: outOfStock ? 0.45 : 1.0,
                            child: InkWell(
                              onTap: outOfStock ? null : () => _selectProduct(p),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(cleaned.isNotEmpty ? cleaned : p.name,
                                            style: _bodyText(size: 14, weight: FontWeight.w700),
                                            maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Icon(Icons.inventory_2_rounded, size: 10,
                                                color: outOfStock ? const Color(0xFFD84315) : const Color(0xFF10B981)),
                                              const SizedBox(width: 3),
                                              Text(outOfStock ? 'Out of stock' : '${p.stock} in stock',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                                  color: outOfStock ? const Color(0xFFD84315) : const Color(0xFF10B981))),
                                              const SizedBox(width: 10),
                                              Text('₹${p.mrp.toStringAsFixed(0)}',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF555555))),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!outOfStock)
                                      Container(
                                        width: 32, height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3855B3).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.add, size: 18, color: Color(0xFF3855B3)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

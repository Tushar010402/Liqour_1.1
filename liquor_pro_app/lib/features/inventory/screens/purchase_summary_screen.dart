import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/models/ai_feedback_model.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/widgets/ai_feedback_bottom_sheet.dart';
import '../../../shared/widgets/bottom_action_bar.dart';
import '../models/stock_purchase.dart';
import '../providers/stock_purchase_provider.dart';
import '../services/stock_purchase_service.dart';
import '../../finance/providers/vendor_provider.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Purchase item for summary
class PurchaseSummaryItem {
  final String productId;
  final String name;
  final String? brandName;
  final String size;
  final double costPrice;
  final double sellingPrice;
  final double dutyFee;
  int quantity;
  final int stock;

  PurchaseSummaryItem({
    required this.productId,
    required this.name,
    this.brandName,
    required this.size,
    required this.costPrice,
    required this.sellingPrice,
    this.dutyFee = 0.0,
    required this.quantity,
    required this.stock,
  });

  double get totalAmount => costPrice * quantity;
}

/// Full-screen Purchase Summary — mirrors SalesSummaryScreen.
/// Shows item list, vendor selection, receipt upload, TCS, and submit.
class PurchaseSummaryScreen extends StatefulWidget {
  final List<PurchaseSummaryItem> items;
  final DateTime selectedDate;
  final bool readOnly;

  const PurchaseSummaryScreen({
    super.key,
    required this.items,
    required this.selectedDate,
    this.readOnly = false,
  });

  @override
  State<PurchaseSummaryScreen> createState() => _PurchaseSummaryScreenState();
}

class _PurchaseSummaryScreenState extends State<PurchaseSummaryScreen> {
  late List<PurchaseSummaryItem> _items;
  String? _selectedVendorId;
  String? _selectedVendorName;
  final _receiptController = TextEditingController();
  final _notesController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<File> _billImages = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VendorProvider>().loadVendors();
    });
  }

  @override
  void dispose() {
    _receiptController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _subtotal => _items.fold(0.0, (s, i) => s + i.totalAmount);
  double get _tcs => _subtotal * 0.02; // TCS 2% (Tax Collected at Source)
  double get _roundOff {
    final afterTcs = _subtotal + _tcs;
    return afterTcs.round().toDouble() - afterTcs;
  }
  double get _total => _subtotal + _tcs + _roundOff;
  int get _totalQty => _items.fold(0, (s, i) => s + i.quantity);

  String _fmt(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return NumberFormat('#,##,###').format(v.toInt());
    return v.toStringAsFixed(0);
  }

  String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'\s*-\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .trim();
  }

  // ── Image picking ──
  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Add Bill / Receipt', style: _heading(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF3855B3)),
              title: Text('Camera', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF3855B3)),
              title: Text('Gallery', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(imageQuality: 85);
        if (picked.isNotEmpty && mounted) {
          setState(() { for (final xf in picked) { if (_billImages.length < 5) _billImages.add(File(xf.path)); } });
        }
      } else {
        final picked = await _picker.pickImage(source: source, imageQuality: 85);
        if (picked != null && mounted) {
          setState(() { if (_billImages.length < 5) _billImages.add(File(picked.path)); });
        }
      }
    } catch (e) { debugPrint('[PurchaseSummary] Pick error: $e'); }
  }

  // ── Vendor selection ──
  void _showVendorPicker() {
    final vendorProvider = context.read<VendorProvider>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (_, scrollController) => Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Select Vendor', style: _heading(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              Expanded(
                child: vendorProvider.vendors.isEmpty
                    ? Center(child: Text('No vendors found', style: _body(color: const Color(0xFF888888))))
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: vendorProvider.vendors.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final vendor = vendorProvider.vendors[i];
                          final isSelected = _selectedVendorId == vendor.id;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isSelected ? const Color(0xFF0D47A1) : const Color(0xFFF0F1F5),
                              child: Icon(Icons.store, size: 20, color: isSelected ? Colors.white : const Color(0xFF888888)),
                            ),
                            title: Text(vendor.name, style: _body(size: 14, weight: isSelected ? FontWeight.w800 : FontWeight.w600)),
                            trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF0D47A1), size: 22) : null,
                            onTap: () {
                              setState(() { _selectedVendorId = vendor.id; _selectedVendorName = vendor.name; });
                              Navigator.pop(ctx);
                            },
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

  // ── Edit item ──
  void _editItem(int index) {
    final item = _items[index];
    final controller = TextEditingController(text: item.quantity.toString());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(_cleanName(item.name), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Cost: \u20B9${item.costPrice.toStringAsFixed(0)}  •  Stock: ${item.stock}', style: const TextStyle(fontSize: 12, color: Color(0xFF888888))),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Quantity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
                const Spacer(),
                StatefulBuilder(
                  builder: (context, setLocal) => Row(
                    children: [
                      _stepBtn('\u2212', () { final c = int.tryParse(controller.text) ?? 0; if (c > 0) { controller.text = '${c - 1}'; setLocal(() {}); } }),
                      Container(
                        width: 56, height: 40,
                        decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFD0D5DD))), color: Colors.white),
                        child: TextField(controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 10), isDense: true),
                          onChanged: (_) => setLocal(() {})),
                      ),
                      _stepBtn('+', () { final c = int.tryParse(controller.text) ?? 0; controller.text = '${c + 1}'; setLocal(() {}); }),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: OutlinedButton(
                  onPressed: () { Navigator.pop(ctx); setState(() => _items.removeAt(index)); },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFD84315)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Remove', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD84315))),
                )),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: ElevatedButton(
                  onPressed: () {
                    final newQty = int.tryParse(controller.text) ?? 0;
                    Navigator.pop(ctx);
                    if (newQty <= 0) { setState(() => _items.removeAt(index)); } else { setState(() => item.quantity = newQty); }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 12), elevation: 0),
                  child: const Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn(String label, VoidCallback onTap) {
    final isMinus = label == '\u2212';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: isMinus ? Colors.white : const Color(0xFF2962FF),
          borderRadius: BorderRadius.horizontal(left: isMinus ? const Radius.circular(8) : Radius.zero, right: isMinus ? Radius.zero : const Radius.circular(8)),
          border: isMinus ? Border.all(color: const Color(0xFFD0D5DD)) : null,
        ),
        child: Center(child: Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isMinus ? const Color(0xFF555555) : Colors.white))),
      ),
    );
  }

  // ── Submit ──
  Future<void> _submit() async {
    if (_isSubmitting) return;

    // Validate vendor selection
    if (_selectedVendorId == null) {
      SnackbarHelper.showWarning(context, 'Please select a vendor first');
      return;
    }

    setState(() => _isSubmitting = true);

    final shopId = context.read<ShopSelectionProvider>().selectedShopId;
    if (shopId == null) {
      SnackbarHelper.showError(context, 'No shop selected');
      setState(() => _isSubmitting = false);
      return;
    }

    // Upload receipt image
    String? receiptImageUrl;
    if (_billImages.isNotEmpty) {
      try {
        final service = StockPurchaseService(context.read());
        final resp = await service.uploadReceiptImage(_billImages.first);
        if (resp.success && resp.data != null) receiptImageUrl = resp.data;
      } catch (_) {}
    }

    if (!mounted) return;

    final purchaseItems = _items.map((e) => StockPurchaseItem.fromSelection(
      productId: e.productId,
      productName: e.name,
      brandName: e.brandName,
      size: e.size,
      quantity: e.quantity,
      costPrice: e.costPrice,
      dutyFee: e.dutyFee,
    )).toList();

    final provider = context.read<StockPurchaseProvider>();
    final success = await provider.submitPurchaseRequest(
      shopId: shopId,
      vendorId: _selectedVendorId ?? '',
      items: purchaseItems,
      notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
      receiptNumber: _receiptController.text.trim().isNotEmpty ? _receiptController.text.trim() : null,
      receiptDate: widget.selectedDate,
      receiptImageUrl: receiptImageUrl,
    );

    if (!mounted) return;

    if (success) {
      HapticFeedbackUtil.success();
      SnackbarHelper.showSuccess(context, 'Purchase submitted for approval');
      await AIFeedbackBottomSheet.show(
        context,
        flowType: AIFlowType.purchaseEntry,
        successMessage: 'Purchase submitted for approval',
      );
      if (!mounted) return;
      Navigator.pop(context, 'submitted');
    } else {
      SnackbarHelper.showError(context, provider.errorMessage ?? 'Failed to submit');
      setState(() => _isSubmitting = false);
    }
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header
          SafeArea(
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
                  Expanded(child: Text('Purchase Summary', textAlign: TextAlign.center, style: _heading(size: 18))),
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE8EEF8), border: Border.all(color: const Color(0xFFD0D8E8), width: 1)),
                    child: Center(child: SizedBox(width: 18, height: 18, child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain))),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EAF0)),

          // Date + Vendor bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFFF8F9FB),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Color(0xFF2962FF)),
                const SizedBox(width: 6),
                Text(DateFormat('dd MMM yyyy').format(widget.selectedDate), style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF2962FF))),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: _showVendorPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedVendorId != null ? const Color(0xFFE8F5E9) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _selectedVendorId != null ? const Color(0xFF2E7D32) : const Color(0xFFD0D5DD)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.store, size: 14, color: _selectedVendorId != null ? const Color(0xFF2E7D32) : const Color(0xFF888888)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _selectedVendorName ?? 'Select Vendor',
                              style: _body(size: 12, weight: FontWeight.w600, color: _selectedVendorId != null ? const Color(0xFF2E7D32) : const Color(0xFF888888)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, size: 18, color: _selectedVendorId != null ? const Color(0xFF2E7D32) : const Color(0xFF888888)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: _items.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFCCCCCC)),
                    const SizedBox(height: 12),
                    const Text('No items', style: TextStyle(color: Color(0xFF999999))),
                    const SizedBox(height: 16),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _items.length + 2, // +1 for receipt/notes, +1 for totals
                    itemBuilder: (_, i) {
                      if (i < _items.length) return _itemRow(i, _items[i]);
                      if (i == _items.length) return _receiptSection();
                      return _totalsCard();
                    },
                  ),
          ),

          // Submit button — hidden in read-only mode
          if (_items.isNotEmpty && !widget.readOnly)
            BottomActionBar(
              label: _isSubmitting ? 'Submitting...' : 'Submit for Approval',
              onPressed: _isSubmitting ? null : _submit,
            ),
        ],
      ),
    );
  }

  Widget _itemRow(int idx, PurchaseSummaryItem item) {
    final cleaned = _cleanName(item.name);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFECEEF2)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + total
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${idx + 1}  ', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF3366CC))),
              Expanded(child: Text(cleaned.isNotEmpty ? cleaned : item.name, style: _body(size: 14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Text('\u20B9 ${_fmt(item.totalAmount)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
            ],
          ),
          const SizedBox(height: 6),
          // Pills
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Row(
              children: [
                _pill('Qty - ${item.quantity}'),
                const SizedBox(width: 5),
                _pill('Cost - \u20B9${item.costPrice.toStringAsFixed(0)}'),
                if (item.sellingPrice > 0 && item.sellingPrice != item.costPrice) ...[
                  const SizedBox(width: 5),
                  _pill('MRP - \u20B9${item.sellingPrice.toStringAsFixed(0)}'),
                ],
                const SizedBox(width: 6),
                Text('Stock: ${item.stock}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: item.stock > 0 ? const Color(0xFF2E7D32) : const Color(0xFFD84315))),
              ],
            ),
          ),
          const SizedBox(height: 5),
          // Edit + size badge
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _editItem(idx),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 2), child: Text('Edit  \u25B8', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1D26)))),
                ),
                const Spacer(),
                if (item.size.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE8F0FE), borderRadius: BorderRadius.circular(4)),
                    child: Text(item.size.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF3366CC))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5)),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF555555))),
    );
  }

  Widget _receiptSection() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8EAF0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Receipt & Notes', style: _body(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _receiptController,
                  style: _body(size: 13),
                  decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'Receipt #', hintStyle: _body(size: 12, color: const Color(0xFFAAAAAA)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD0D5DD))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD0D5DD)))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _notesController,
                  style: _body(size: 13),
                  decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    hintText: 'Notes', hintStyle: _body(size: 12, color: const Color(0xFFAAAAAA)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD0D5DD))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD0D5DD)))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bill images
          Row(
            children: [
              if (_billImages.isNotEmpty) ...[
                ..._billImages.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(e.value, width: 48, height: 48, fit: BoxFit.cover)),
                      Positioned(top: -2, right: -2, child: GestureDetector(
                        onTap: () => setState(() => _billImages.removeAt(e.key)),
                        child: Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 10, color: Colors.white)),
                      )),
                    ],
                  ),
                )),
              ],
              if (_billImages.length < 5)
                GestureDetector(
                  onTap: _showImageSourceSheet,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFD0D9F0))),
                    child: const Icon(Icons.add_a_photo_rounded, size: 20, color: Color(0xFF3855B3)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalsCard() {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(color: const Color(0xFFFFFAE8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF2E8C4))),
      child: Column(
        children: [
          _totalRow('Subtotal', _subtotal),
          _totalRow('TCS (2%)', _tcs),
          if (_roundOff.abs() > 0.001) _totalRow('Round Off', _roundOff),
          const Divider(height: 16),
          Row(
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Grand Total', style: _heading(size: 16)),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(6)),
                  child: Text('$_totalQty items', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF555555))),
                ),
              ]),
              const Spacer(),
              Text('\u20B9 ${_fmt(_total)}', style: _heading(size: 24, weight: FontWeight.w900, color: const Color(0xFF0D47A1))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: _body(size: 13, weight: FontWeight.w500, color: const Color(0xFF888888))),
          Text('\u20B9${amount.toStringAsFixed(2)}', style: _body(size: 13, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

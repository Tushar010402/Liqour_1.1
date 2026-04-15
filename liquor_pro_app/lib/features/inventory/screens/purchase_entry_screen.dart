import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../models/product.dart' as models;
import '../models/ai_purchase_models.dart';
import 'purchase_summary_screen.dart';

/// Font helpers — identical to DailySalesEntryScreen
TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Purchase Entry Screen — product grid matching DailySalesEntryScreen exactly.
/// Same card UI with product image, MRP badge, stock badge, pill-style stepper.
class PurchaseEntryScreen extends StatefulWidget {
  final String category; // 'English' or 'Beer'
  final DateTime selectedDate;
  final List<models.Product> allProducts;
  final Map<String, models.Stock> stockMap;
  /// Optional: AI-prefilled quantities (productId → quantity)
  final Map<String, int>? prefillQuantities;
  /// If true, show "AI-filled" banner
  final bool isAIMode;
  /// Optional: AI metadata per product (productId → meta)
  final Map<String, AIPurchaseItemMeta>? aiItemMeta;

  const PurchaseEntryScreen({
    super.key,
    required this.category,
    required this.selectedDate,
    required this.allProducts,
    required this.stockMap,
    this.prefillQuantities,
    this.isAIMode = false,
    this.aiItemMeta,
  });

  @override
  State<PurchaseEntryScreen> createState() => _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends State<PurchaseEntryScreen> {
  final Map<String, TextEditingController> _qtyControllers = {};
  final ValueNotifier<int> _filledCount = ValueNotifier(0);

  // Search & filter state
  String _searchQuery = '';
  String _sortBy = 'brand';
  bool _sortAscending = true;
  String? _selectedSize; // Size filter
  bool _isFiltersVisible = false; // Toggle for size filters (like DailySalesEntry)

  // Bill/receipt image state
  final ImagePicker _picker = ImagePicker();
  final List<File> _billImages = [];

  late List<models.Product> _products;
  late List<String> _availableSizes;

  @override
  void initState() {
    super.initState();
    _products = widget.allProducts.where((p) {
      final catName = (p.category?.name ?? '').toLowerCase();
      if (widget.category == 'Beer') return catName.contains('beer');
      return !catName.contains('beer');
    }).toList();

    // Extract available sizes from products
    final sizeSet = <String>{};
    for (var p in _products) {
      if (p.size.isNotEmpty) sizeSet.add(p.size.toUpperCase());
    }
    _availableSizes = sizeSet.toList()..sort((a, b) {
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });

    // Pre-fill quantities from AI if provided
    if (widget.prefillQuantities != null) {
      for (final entry in widget.prefillQuantities!.entries) {
        final c = _getController(entry.key);
        c.text = entry.value.toString();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.removeListener(_updateFilledCount);
      c.dispose();
    }
    _filledCount.dispose();
    super.dispose();
  }

  TextEditingController _getController(String productId) {
    if (!_qtyControllers.containsKey(productId)) {
      final c = TextEditingController();
      c.addListener(_updateFilledCount);
      _qtyControllers[productId] = c;
    }
    return _qtyControllers[productId]!;
  }

  void _updateFilledCount() {
    int count = 0;
    for (final c in _qtyControllers.values) {
      final qty = int.tryParse(c.text) ?? 0;
      if (qty > 0) count++;
    }
    _filledCount.value = count;
  }

  List<models.Product> _getFilteredProducts() {
    var filtered = List<models.Product>.from(_products);

    // Size filter
    if (_selectedSize != null) {
      filtered = filtered.where((p) => p.size.toUpperCase() == _selectedSize).toList();
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((p) {
        return p.name.toLowerCase().contains(q) ||
               (p.brand?.name ?? '').toLowerCase().contains(q) ||
               p.size.toLowerCase().contains(q);
      }).toList();
    }

    // Sort
    filtered.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'price':
          cmp = a.costPrice.compareTo(b.costPrice);
          break;
        case 'size':
          cmp = a.size.compareTo(b.size);
          break;
        case 'stock':
          final stockA = widget.stockMap[a.id]?.quantity ?? 0;
          final stockB = widget.stockMap[b.id]?.quantity ?? 0;
          cmp = stockA.compareTo(stockB);
          break;
        case 'name':
          cmp = a.name.compareTo(b.name);
          break;
        default: // brand
          cmp = (a.brand?.name ?? '').compareTo(b.brand?.name ?? '');
          if (cmp == 0) cmp = a.size.compareTo(b.size);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return filtered;
  }

  List<_EntryItem> _getFilledItems() {
    final items = <_EntryItem>[];
    for (final product in _products) {
      final c = _qtyControllers[product.id];
      if (c == null) continue;
      final qty = int.tryParse(c.text) ?? 0;
      if (qty <= 0) continue;
      items.add(_EntryItem(product: product, quantity: qty));
    }
    return items;
  }

  double _getSubtotal(List<_EntryItem> items) {
    return items.fold(0.0, (sum, e) => sum + (e.product.costPrice * e.quantity));
  }

  String get _categoryTitle => widget.category == 'Beer' ? 'Beer' : 'Whisky';

  String _extractProductSize(models.Product product) {
    if (product.size.isNotEmpty) return ProductConstants.normalizeSize(product.size);
    final nameRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML|ltr|LTR|L)', caseSensitive: false);
    final nameMatch = nameRegex.firstMatch(product.name);
    if (nameMatch != null) return ProductConstants.normalizeSize(nameMatch.group(0)!);
    return '';
  }

  String _cleanProductName(String name) {
    // Remove size info from name for cleaner display
    return name.replaceAll(RegExp(r'\s*\d+\s*(?:ml|ML|ltr|LTR|L)\s*', caseSensitive: false), ' ').trim();
  }

  // ── Bill image picking ──

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
            Text('Add Bill / Receipt Image', style: _heading(size: 16, weight: FontWeight.w700)),
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
          setState(() {
            for (final xf in picked) {
              if (_billImages.length < 5) _billImages.add(File(xf.path));
            }
          });
        }
      } else {
        final picked = await _picker.pickImage(source: source, imageQuality: 85);
        if (picked != null && mounted) {
          setState(() {
            if (_billImages.length < 5) _billImages.add(File(picked.path));
          });
        }
      }
    } catch (e) {
      debugPrint('[PurchaseEntry] Pick error: $e');
    }
  }

  void _removeImage(int index) {
    HapticFeedbackUtil.light();
    setState(() => _billImages.removeAt(index));
  }

  void _previewImage(File imageFile) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Bill Preview'),
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  void _showReviewSheet() {
    final items = _getFilledItems();
    if (items.isEmpty) {
      SnackbarHelper.showWarning(context, 'Enter at least one product quantity');
      return;
    }
    if (_billImages.isEmpty) {
      SnackbarHelper.showWarning(context, 'Please upload bill / receipt image to proceed');
      return;
    }
    HapticFeedbackUtil.medium();

    // Build summary items — use AI duty fee if available (more accurate from gate pass)
    final summaryItems = items.map((e) {
      final aiMeta = widget.aiItemMeta?[e.product.id];
      final dutyFee = (aiMeta != null && aiMeta.dutyFee > 0) ? aiMeta.dutyFee : e.product.dutyFee;
      return PurchaseSummaryItem(
        productId: e.product.id,
        name: e.product.name,
        brandName: e.product.brand?.name,
        size: e.product.size,
        costPrice: e.product.costPrice,
        sellingPrice: e.product.sellingPrice,
        dutyFee: dutyFee,
        quantity: e.quantity,
        stock: widget.stockMap[e.product.id]?.quantity ?? 0,
      );
    }).toList();

    // Navigate to full-screen summary (like Sales Summary)
    Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseSummaryScreen(
          items: summaryItems,
          selectedDate: widget.selectedDate,
        ),
      ),
    ).then((result) {
      if (result == 'submitted' && mounted) {
        Navigator.pop(context, 'submitted');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredProducts();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ═══ PINNED HEADER (matches DailySalesEntry exactly) ═══
            SliverAppBar(
              pinned: true,
              elevation: 0,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: 48,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: const Color(0xFFEAEDF1)),
              ),
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 38, height: 38,
                        decoration: const BoxDecoration(color: Color(0xFF1349B8), shape: BoxShape.circle),
                        child: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Purchase Entry',
                            style: GoogleFonts.montserratAlternates(
                              fontSize: 19, fontWeight: FontWeight.w600,
                              color: const Color(0xFF18181B), letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '$_categoryTitle \u2022 ${DateFormat('dd MMM yyyy').format(widget.selectedDate)}',
                            style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFF888888)),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 38, height: 38,
                      decoration: const BoxDecoration(color: Color(0xFFEBF1FA), shape: BoxShape.circle),
                      child: Center(
                        child: SizedBox(
                          width: 17, height: 17,
                          child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ═══ SEARCH BAR + FILTER ICON (same as DailySalesEntry) ═══
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0E3EA)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                onChanged: (v) => setState(() => _searchQuery = v),
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                                decoration: const InputDecoration(
                                  hintText: 'Search products...',
                                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Filter icon (toggles size chips)
                    GestureDetector(
                      onTap: () => setState(() => _isFiltersVisible = !_isFiltersVisible),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF1FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD0D8E8)),
                        ),
                        child: Icon(Icons.tune, size: 20,
                          color: _selectedSize != null ? const Color(0xFF1A73E8) : const Color(0xFF6B7280)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ═══ SIZE FILTER CHIPS (toggled via filter button) ═══
            if (_isFiltersVisible && _availableSizes.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      // "All" chip
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () { HapticFeedbackUtil.selection(); setState(() => _selectedSize = null); },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedSize == null ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: _selectedSize == null ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            ),
                            child: Text('All', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                              color: _selectedSize == null ? Colors.white : Theme.of(context).colorScheme.onSurface)),
                          ),
                        ),
                      ),
                      // Size chips
                      ..._availableSizes.map((size) {
                        final isSelected = _selectedSize == size;
                        final count = _products.where((p) => p.size.toUpperCase() == size).length;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () { HapticFeedbackUtil.selection(); setState(() => _selectedSize = isSelected ? null : size); },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                                border: isSelected ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                              ),
                              child: Text('$size ($count)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface)),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

            // ═══ SHOW COUNT + CLEAR FILTERS (like DailySalesEntry) ═══
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Text('\u2014\u2014 ', style: TextStyle(color: const Color(0xFF1A73E8).withValues(alpha: 0.3))),
                    Text('Show ${filtered.length} Entry\'s',
                      style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF1A73E8))),
                    const Spacer(),
                    if (_selectedSize != null || _searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() { _selectedSize = null; _searchQuery = ''; }),
                        child: Text('Clear filters',
                          style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFFE53935))),
                      ),
                  ],
                ),
              ),
            ),

            // ═══ UPLOAD PURCHASE BILL (matches DailySalesEntry "Upload Sales Bill" exactly) ═══
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: _showImageSourceSheet,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _billImages.isEmpty ? const Color(0xFFD0D5DD) : const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _billImages.isEmpty ? const Color(0xFFF0F4FF) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _billImages.isEmpty ? Icons.cloud_upload_outlined : Icons.check_circle,
                          size: 22,
                          color: _billImages.isEmpty ? const Color(0xFF3855B3) : const Color(0xFF2E7D32),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _billImages.isEmpty ? 'Upload Purchase Bill' : '${_billImages.length} Bill Image${_billImages.length > 1 ? 's' : ''} Attached',
                              style: _body(size: 14, weight: FontWeight.w700,
                                color: _billImages.isEmpty ? const Color(0xFF1A1D26) : const Color(0xFF2E7D32)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _billImages.isEmpty ? 'Attach Invoice Image or PDF' : 'Tap to add more (${_billImages.length}/5)',
                              style: _body(size: 11, weight: FontWeight.w500, color: const Color(0xFF888888)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.camera_alt_outlined, size: 22,
                        color: _billImages.isEmpty ? const Color(0xFF888888) : const Color(0xFF2E7D32)),
                    ],
                  ),
                ),
              ),
            ),

            // ═══ BILL IMAGE THUMBNAILS (if uploaded) ═══
            if (_billImages.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: SizedBox(
                    height: 64,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _billImages.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _previewImage(_billImages[i]),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(_billImages[i], width: 64, height: 64, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 2, right: 2,
                                child: GestureDetector(
                                  onTap: () => _removeImage(i),
                                  child: Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // ═══ AI BANNER (when pre-filled by AI) ═══
            if (widget.isAIMode)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC8E6C9)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AI auto-filled quantities from receipt.',
                          style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ═══ PRODUCT LIST (same card UI as DailySalesEntry) ═══
            filtered.isEmpty
                ? SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('No products found', style: _body(color: const Color(0xFF888888))),
                        ],
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = filtered[index];
                        final stock = widget.stockMap[product.id];
                        final stockQty = stock?.quantity ?? 0;
                        final controller = _getController(product.id);
                        return _buildProductCard(
                          product: product,
                          stockQty: stockQty,
                          controller: controller,
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),

            // Bottom padding
            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// Product card — pixel-matched to DailySalesEntryScreen._buildProductRow
  Widget _buildProductCard({
    required models.Product product,
    required int stockQty,
    required TextEditingController controller,
  }) {
    final sizeML = _extractProductSize(product);
    final categoryName = product.category?.name.toUpperCase() ?? 'CUSTOM';
    final bool isGoodStock = stockQty > 10;
    final int purchaseQty = int.tryParse(controller.text) ?? 0;
    final aiMeta = widget.aiItemMeta?[product.id];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0F0F2), width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // AI confidence dot — top-right corner
          if (widget.isAIMode && aiMeta != null)
            Positioned(
              top: 0, right: 0,
              child: Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: aiMeta.confidence >= 0.8
                      ? const Color(0xFF4CAF50)
                      : aiMeta.confidence >= 0.5
                          ? const Color(0xFFFFA726)
                          : const Color(0xFFE53935),
                ),
              ),
            ),
          Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ LEFT: Product Image (80x80) with Cost Price badge ═══
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xFF0D1A30), Color(0xFF1A1030), Color(0xFF3A1A10), Color(0xFFD4700A)],
                stops: [0.0, 0.4, 0.7, 1.0],
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: product.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          memCacheHeight: 200,
                          placeholder: (context, url) => const SizedBox(),
                          errorWidget: (context, url, error) => Center(
                            child: Icon(Icons.liquor, size: 30, color: Colors.white.withValues(alpha: 0.3)),
                          ),
                        )
                      : Center(
                          child: Icon(Icons.liquor, size: 30, color: Colors.white.withValues(alpha: 0.3)),
                        ),
                ),
                // MRP badge — top-left (same as DailySalesEntry)
                if (product.sellingPrice > 0)
                  Positioned(
                    top: 0, left: 0,
                    child: Container(
                      padding: const EdgeInsets.only(left: 5, right: 6, top: 2, bottom: 3),
                      decoration: const BoxDecoration(
                        color: Color(0xE60A1736),
                        borderRadius: BorderRadius.only(bottomRight: Radius.circular(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('MRP', style: TextStyle(fontSize: 7, color: Color(0xDDFFFFFF), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          Text('\u20B9 ${product.sellingPrice.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ═══ RIGHT: Product Info ═══
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Name
                Text(
                  _cleanProductName(product.name),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Color(0xFF141F39), height: 1.2),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),

                // Row 2: Category pill + stock badge
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '$categoryName - $sizeML',
                          style: const TextStyle(fontSize: 8.5, color: Color(0xFF6B7280), fontWeight: FontWeight.w700, letterSpacing: 0.3),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SvgPicture.asset(
                      isGoodStock ? 'assets/icons/inventory_green_sm.svg' : 'assets/icons/inventory_amber_sm.svg',
                      width: 12, height: 12),
                    const SizedBox(width: 3),
                    Text(
                      '$stockQty',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isGoodStock ? const Color(0xFF10B981) : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Row 3: Price + purchase qty info + stepper
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cost Price + MRP on same line, truncate-safe
                          Row(
                            children: [
                              Text(
                                '\u20B9${product.costPrice > 0 ? product.costPrice.toStringAsFixed(0) : "--"}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0B1536)),
                              ),
                              if (product.sellingPrice > 0 && product.sellingPrice != product.costPrice) ...[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '\u20B9${product.sellingPrice.toStringAsFixed(0)} mrp',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              SvgPicture.asset('assets/icons/box_closing.svg', width: 11, height: 11,
                                colorFilter: const ColorFilter.mode(Color(0xFF6B7280), BlendMode.srcIn)),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  purchaseQty > 0
                                      ? 'Buying $purchaseQty'
                                      : 'Stock: $stockQty',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: purchaseQty > 0 ? const Color(0xFF1A73E8) : const Color(0xFF6B7280),
                                    fontWeight: purchaseQty > 0 ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // ═══ Rectangular quantity stepper (wider for 4-5 digit numbers) ═══
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Minus
                          GestureDetector(
                            onTap: () {
                              final current = int.tryParse(controller.text) ?? 0;
                              if (current > 0) {
                                controller.text = '${current - 1}';
                                controller.selection = TextSelection.collapsed(offset: controller.text.length);
                                HapticFeedbackUtil.light();
                              }
                              if (controller.text == '0') controller.clear();
                            },
                            child: Container(
                              width: 28, height: 30,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(color: const Color(0xFFE0E3EA), width: 0.5),
                              ),
                              child: const Center(child: Icon(Icons.remove, size: 15, color: Color(0xFF6B7280))),
                            ),
                          ),
                          const SizedBox(width: 2),
                          // Rectangular quantity input — fits up to 5 digits
                          Container(
                            width: 56, height: 30,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: const Color(0xFFD0D5DD)),
                            ),
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF141F39)),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 6),
                                isDense: true,
                                hintText: '0',
                                hintStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFCCCCCC)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          // Plus (blue button)
                          GestureDetector(
                            onTap: () {
                              final current = int.tryParse(controller.text) ?? 0;
                              controller.text = '${current + 1}';
                              controller.selection = TextSelection.collapsed(offset: controller.text.length);
                              HapticFeedbackUtil.light();
                            },
                            child: Container(
                              width: 28, height: 30,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A73E8),
                                borderRadius: BorderRadius.circular(7),
                                boxShadow: [BoxShadow(color: const Color(0xFF1A73E8).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                              ),
                              child: const Center(child: Icon(Icons.add, size: 15, color: Colors.white)),
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
        ],
      ),
      // AI rate warning row
      if (widget.isAIMode && aiMeta != null && aiMeta.warnings.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 12, color: Color(0xFFF57C00)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  aiMeta.warnings.first,
                  style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFFF57C00)),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      // AI badge on prefilled fields
      if (widget.isAIMode && aiMeta != null && purchaseQty > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('AI', style: _body(size: 8, weight: FontWeight.w800, color: const Color(0xFF1565C0))),
          ),
        ),
        ],
      ),
    );
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Sort By', style: _heading(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...[
              ('brand', 'Brand Name', Icons.sort_by_alpha),
              ('name', 'Product Name', Icons.abc),
              ('price', 'Cost Price', Icons.currency_rupee),
              ('size', 'Size', Icons.straighten),
              ('stock', 'Stock Level', Icons.inventory_2),
            ].map((item) => ListTile(
              leading: Icon(item.$3, size: 20, color: _sortBy == item.$1 ? const Color(0xFF1A73E8) : const Color(0xFF6B7280)),
              title: Text(item.$2, style: TextStyle(
                fontWeight: _sortBy == item.$1 ? FontWeight.w700 : FontWeight.w500,
                color: _sortBy == item.$1 ? const Color(0xFF1A73E8) : const Color(0xFF141F39),
              )),
              trailing: _sortBy == item.$1
                  ? Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: const Color(0xFF1A73E8))
                  : null,
              onTap: () {
                setState(() {
                  if (_sortBy == item.$1) {
                    _sortAscending = !_sortAscending;
                  } else {
                    _sortBy = item.$1;
                    _sortAscending = true;
                  }
                });
                Navigator.pop(context);
              },
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final filtered = _getFilteredProducts();
    final totalProducts = filtered.length;

    return ValueListenableBuilder<int>(
      valueListenable: _filledCount,
      builder: (context, count, _) {
        final items = _getFilledItems();
        final subtotal = _getSubtotal(items);
        final progress = totalProducts > 0 ? count / totalProducts : 0.0;

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress bar (like DailySalesEntry)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE8EAF0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              count > 0 ? const Color(0xFF1A73E8) : const Color(0xFFE8EAF0)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('$count/$totalProducts',
                        style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF555555))),
                    ],
                  ),
                ),
                // Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: count > 0 && _billImages.isNotEmpty ? _showReviewSheet : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      disabledBackgroundColor: const Color(0xFFE0E3EA),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          count > 0
                              ? 'Review Purchase ($count items \u00b7 \u20B9${subtotal.toStringAsFixed(0)})'
                              : 'Review Purchase',
                          style: _body(size: 15, weight: FontWeight.w800, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lightweight data holder for a filled entry
class _EntryItem {
  final models.Product product;
  final int quantity;
  _EntryItem({required this.product, required this.quantity});
}

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/constants/size_range_constants.dart';
import '../../../core/models/ai_feedback_model.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/widgets/ai_feedback_bottom_sheet.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../models/ai_stock_models.dart';
import '../models/product.dart' as models;
import '../providers/product_provider.dart';
import '../services/brand_edit_service.dart';
import '../services/smart_stock_service.dart';

/// Lightweight product class that unifies products from backend allProducts and local cache.
/// Supports editable fields for user correction during review.
class _ReviewProduct {
  String id; // mutable so alt picker can swap the backing product
  String name;
  String brandName;
  String? matchedFullName;
  final String size;
  double mrp;
  double rate; // cost rate from register, used when building apply payload
  final int currentStock;
  final int rowNumber;
  final bool needsReview;
  final String? reviewReason;
  final bool autoCreated;
  final String rawBrandName; // Original OCR text

  // Status carried through from SmartStockItem
  String status; // matched | low_confidence | ambiguous | not_found | auto_create | missing

  // Register audit columns (sent to backend on apply for stock_setup_history)
  final int opening;
  final int receipt;
  final int sale;
  final int closingStock;

  // Authoritative "excise" name from saas_brands — shown as subtitle so users
  // see both what their catalog calls it AND what excise records call it.
  String? exciseName;

  // Alternative picker + correction tracking
  final List<StockAlternativeMatch> alternatives;
  // Master brand suggestions (saas_brands) for auto_create rows — lets the user
  // attach to an authoritative brand instead of creating a brand-new tenant record.
  final List<MasterBrandSuggestion> masterBrandSuggestions;
  bool wasCorrected = false;
  String? originalProductId;

  // Warnings from backend (e.g., "Closing (10) ≠ Total (0) - Sale (1)")
  final List<String> warnings;

  // Official brand name (persisted in apply payload)
  String? officialBrandName;

  // Track the initial display name so we only send edited_name when user actually changed it
  final String initialName;

  _ReviewProduct({
    required this.id,
    required this.name,
    this.brandName = '',
    this.matchedFullName,
    this.size = '',
    this.mrp = 0.0,
    this.rate = 0.0,
    this.currentStock = 0,
    this.rowNumber = 0,
    this.needsReview = false,
    this.reviewReason,
    this.autoCreated = false,
    this.rawBrandName = '',
    this.status = 'matched',
    this.opening = 0,
    this.receipt = 0,
    this.sale = 0,
    this.closingStock = 0,
    this.alternatives = const [],
    this.masterBrandSuggestions = const [],
    this.exciseName,
    this.warnings = const [],
    this.officialBrandName,
    String? initialName,
  }) : initialName = initialName ?? name;

  bool get isMissing => status == 'missing';
  bool get isNotFound => status == 'not_found';
  bool get isAutoCreate => status == 'auto_create' || autoCreated;
  bool get isLowConfidence => status == 'low_confidence' || status == 'ambiguous';
  bool get nameEdited => name.trim() != initialName.trim();
}

/// Manual entry for brands not detected by AI.
class _ManualEntry {
  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  final String id; // unique key

  _ManualEntry()
      : id = 'manual_${DateTime.now().microsecondsSinceEpoch}',
        nameController = TextEditingController(),
        qtyController = TextEditingController(),
        priceController = TextEditingController();

  bool get isEmpty => nameController.text.trim().isEmpty && qtyController.text.trim().isEmpty;
  bool get hasName => nameController.text.trim().isNotEmpty;
  bool get hasQty => (int.tryParse(qtyController.text) ?? 0) > 0;

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    priceController.dispose();
  }
}

/// Which field the edit sheet should autofocus when opened.
enum _EditFocus { name, price }

/// Asset paths (reuse sales images)
class _StockAssets {
  static const whiskyCard = 'assets/images/sales/whisky_card.png';
  static const beerCard = 'assets/images/sales/beer_card.png';
  static const whiskyHero = 'assets/images/sales/whisky_hero.png';
}

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// AI Stock Setup Screen — multi-step wizard flow (mirrors Sales Entry Setup).
/// Step 0: Select category → Step 1: Select size → Step 2: Upload images →
/// Step 3: AI processing → Step 4: Review editable product grid → Submit.
class AiStockSetupScreen extends StatefulWidget {
  const AiStockSetupScreen({super.key});

  @override
  State<AiStockSetupScreen> createState() => _AiStockSetupScreenState();
}

class _AiStockSetupScreenState extends State<AiStockSetupScreen> with TickerProviderStateMixin {
  // ── Step tracking ──
  // 0=Category, 1=Size, 2=StockColumn, 3=Upload, 4=Processing, 5=Review
  int _currentStep = 0;

  // ── Category/Size/StockColumn ──
  String? _selectedCategoryName;
  bool _isEnglishFilterSelected = false;
  String? _selectedSize;
  String _selectedStockColumn = 'opening'; // "opening", "total", "closing"
  String? _resolvedCategoryId; // Exact category UUID for backend scoping

  // ── Products (cached locally like Daily Sales Entry) ──
  List<models.Product> _allProducts = [];
  Map<String, models.Stock> _stockMap = {};
  bool _isLoadingData = true;

  // ── Image + Processing ──
  final ImagePicker _picker = ImagePicker();
  final List<File> _images = [];
  String _progressStatus = '';
  double _progressValue = 0.0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _cancelled = false;

  // ── AI Result + Review ──
  SmartStockResult? _result;
  // ignore: unused_field
  String _errorMessage = '';
  final Map<String, TextEditingController> _quantityControllers = {};
  final Map<String, TextEditingController> _priceControllers = {};
  Set<String> _aiDetectedProductIds = {};
  Map<String, int> _aiDetectedQuantities = {};
  List<SmartStockItem> _notFoundItems = [];
  String _searchQuery = '';
  bool _isSaving = false;
  List<_ReviewProduct> _reviewProducts = [];

  // Manual product entries (user-added brands not detected by AI)
  final List<_ManualEntry> _manualEntries = [];
  bool _notFoundExpanded = false;
  bool _missingExpanded = false;

  // SaaS category sizes (fallback when tenant has no products yet)
  // Maps category name (lowercase) → list of size names
  Map<String, List<String>> _saasCategorySizes = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    for (final c in _quantityControllers.values) {
      c.dispose();
    }
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    for (final e in _manualEntries) {
      e.dispose();
    }
    super.dispose();
  }

  // ── Helpers ──

  String get _shopName {
    try {
      return context.read<ShopSelectionProvider>().selectedShopName ?? 'Shop';
    } catch (_) {
      return 'Shop';
    }
  }

  String? get _shopId {
    try {
      return context.read<ShopSelectionProvider>().selectedShopId;
    } catch (_) {
      return null;
    }
  }

  String get _categoryLabel {
    if (_isEnglishFilterSelected) return 'Whisky';
    return _selectedCategoryName ?? '';
  }

  String get _categoryKey {
    if (_isEnglishFilterSelected) return 'English';
    final name = (_selectedCategoryName ?? '').toLowerCase();
    if (name.contains('beer')) return 'Beer';
    return 'English';
  }

  // ── Data loading (same pattern as SalesEntrySetupScreen) ──

  Future<void> _loadData() async {
    if (!mounted) return;
    final shopProvider = context.read<ShopSelectionProvider>();
    final productProvider = context.read<ProductProvider>();
    final shopId = shopProvider.selectedShopId;

    if (shopId == null) {
      setState(() => _isLoadingData = false);
      return;
    }

    try {
      // Save filters to restore after loading (avoid clobbering inventory screen)
      final savedCatId = productProvider.selectedCategoryId;
      final savedCatName = productProvider.selectedCategoryName;
      final savedSize = productProvider.selectedSize;

      productProvider.clearAllFilters();
      await productProvider.loadProducts(shopId: null, limit: 500, categoryId: null, size: null);
      await productProvider.loadStock(shopId: shopId);
      if (!mounted) return;

      // Deep copy into local cache immediately
      _allProducts = List<models.Product>.from(productProvider.products);
      _stockMap = {
        for (final entry in productProvider.stockByProductId.entries)
          entry.key: entry.value.copyWith(),
      };

      debugPrint('[AiStockSetup] Loaded ${_allProducts.length} products, ${_stockMap.length} stock entries');

      // Fetch SaaS category sizes (needed when tenant has no products yet)
      await _loadSaasCategorySizes();

      // Restore provider state so inventory screen isn't affected
      if (savedCatId != null) {
        productProvider.setSelectedCategory(savedCatId, savedCatName);
      }
      if (savedSize != null) {
        productProvider.setSelectedSize(savedSize);
      }

      if (mounted) setState(() => _isLoadingData = false);
    } catch (e) {
      debugPrint('[AiStockSetup] Error: $e');
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  /// Fetch predefined sizes from SaaS category-sizes API.
  /// Groups them by category name so we can look up sizes even when
  /// the tenant has no products onboarded yet.
  Future<void> _loadSaasCategorySizes() async {
    try {
      final authService = context.read<AuthService>();
      final brandEditService = BrandEditService(authService: authService);
      // Fetch ALL SaaS category sizes (no filter)
      final allSizes = await brandEditService.getCategorySizesRaw();
      debugPrint('[AiStockSetup] Loaded ${allSizes.length} SaaS category sizes');
      if (allSizes.isEmpty) return;

      // Group sizes by SaaS category_id
      final sizesByCatId = <String, List<String>>{};
      for (final sizeObj in allSizes) {
        final sizeName = sizeObj['size_name']?.toString() ?? '';
        final catId = sizeObj['category_id']?.toString() ?? '';
        if (sizeName.isEmpty || catId.isEmpty) continue;
        sizesByCatId.putIfAbsent(catId, () => []);
        if (!sizesByCatId[catId]!.contains(sizeName)) {
          sizesByCatId[catId]!.add(sizeName);
        }
      }

      // Map SaaS category_id → tenant category name.
      // Beer sizes are unique (330ML, 500ML, 650ML), so detect Beer by content.
      // All other categories (Whisky, Rum, Vodka) share the same sizes
      // (90ML, 180ML, 375ML, 750ML, 1L) — assign them to each category name.
      final grouped = <String, List<String>>{};
      for (final entry in sizesByCatId.entries) {
        final sizes = entry.value;
        final isBeer = sizes.any((s) =>
            s.contains('330') || s.contains('650'));
        if (isBeer) {
          grouped['beer'] = sizes;
        } else {
          // These sizes apply to Whisky, Rum, and Vodka equally
          for (final name in ['whisky', 'rum', 'vodka']) {
            grouped.putIfAbsent(name, () => List<String>.from(sizes));
          }
        }
      }

      _saasCategorySizes = grouped;
      debugPrint('[AiStockSetup] SaaS sizes: ${grouped.map((k, v) => MapEntry(k, v.join(", ")))}');
    } catch (e) {
      debugPrint('[AiStockSetup] Error loading SaaS category sizes: $e');
    }
  }

  /// Always show both categories for AI Stock Setup — user needs to set stock for all
  List<String> _getUniqueCategories() {
    return ['English', 'Beer'];
  }

  List<models.Product> _getProductsForCategory(String category) {
    return _allProducts.where((p) {
      final catName = (p.category?.name ?? '').toLowerCase();
      if (category == 'Beer') return catName.contains('beer');
      if (category == 'English') return catName.isNotEmpty && !catName.contains('beer');
      return (p.category?.name ?? '') == category;
    }).toList();
  }

  int _getTotalStock(String category) {
    int total = 0;
    for (var p in _getProductsForCategory(category)) {
      final stock = _stockMap[p.id];
      if (stock != null) total += stock.quantity;
    }
    return total;
  }

  double _getTotalValue(String category) {
    double total = 0;
    for (var p in _getProductsForCategory(category)) {
      final stock = _stockMap[p.id];
      if (stock != null && stock.quantity > 0) {
        total += p.sellingPrice * stock.quantity;
      }
    }
    return total;
  }

  String _formatValue(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  String _extractProductSize(models.Product product) {
    if (product.size.isNotEmpty) return ProductConstants.normalizeSize(product.size);
    final nameRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML|ltr|LTR|L)', caseSensitive: false);
    final nameMatch = nameRegex.firstMatch(product.name);
    if (nameMatch != null) {
      String sizeStr = nameMatch.group(0)!;
      if (sizeStr.toLowerCase().contains('ltr') ||
          (sizeStr.toLowerCase().contains('l') && !sizeStr.toLowerCase().contains('ml'))) {
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(sizeStr);
        if (numMatch != null) {
          final liters = double.tryParse(numMatch.group(0)!) ?? 0;
          return '${(liters * 1000).toInt()}ML';
        }
      }
      return ProductConstants.normalizeSize(sizeStr);
    }
    return '';
  }

  // ── Size stats — grouped by ranges ──

  Map<String, _SizeStats> _getSizeStats() {
    final products = _getProductsForCategory(_categoryKey);
    final ranges = SizeRangeConstants.rangesFor(_categoryKey);
    final stats = <String, _SizeStats>{};

    // Initialize ranges
    for (final range in ranges) {
      stats[range.label] = _SizeStats(size: range.label);
    }

    // Bucket products into ranges
    for (var p in products) {
      final size = _extractProductSize(p);
      if (size.isEmpty) continue;
      final rangeLabel = SizeRangeConstants.getRangeLabel(size, _categoryKey);
      if (rangeLabel == null) continue;
      final stock = _stockMap[p.id];
      final qty = stock?.quantity ?? 0;
      stats[rangeLabel]!.totalStock += qty;
      stats[rangeLabel]!.totalValue += (p.mrp > 0 ? p.mrp : p.sellingPrice) * qty;
    }

    // AI Stock Setup: Show ALL size ranges so user can set stock for any size
    // Don't remove empty ranges — the whole point is to set opening stock

    return stats;
  }

  // ── Image picking ──

  Future<void> _showImageSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
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
            Text('Add Stock Register Image', style: _heading(size: 16, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF3855B3)),
              title: Text('Camera', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF3855B3)),
              title: Text('Gallery', style: _body(size: 15, weight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (source != null && mounted) {
      _pickImage(source);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final picked = await _picker.pickMultiImage(imageQuality: 90);
        if (picked.isNotEmpty && mounted) {
          setState(() {
            for (final xf in picked) {
              if (_images.length < 5) _images.add(File(xf.path));
            }
          });
        }
      } else {
        final picked = await _picker.pickImage(source: source, imageQuality: 90);
        if (picked != null && mounted) {
          setState(() {
            if (_images.length < 5) _images.add(File(picked.path));
          });
        }
      }
    } catch (e) {
      debugPrint('[AiStockSetup] Pick error: $e');
    }
  }

  void _removeImage(int index) {
    HapticFeedbackUtil.light();
    setState(() => _images.removeAt(index));
  }

  void _showImagePreview(int initialIndex) {
    final pageController = PageController(initialPage: initialIndex);
    Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, _, __) => StatefulBuilder(
          builder: (context, setDialogState) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  // Swipeable image pages
                  PageView.builder(
                    controller: pageController,
                    itemCount: _images.length,
                    itemBuilder: (_, i) => InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Center(
                        child: Image.file(_images[i], fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  // Top bar: close + page indicator
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16, right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: pageController,
                          builder: (_, __) {
                            final current = pageController.hasClients
                                ? (pageController.page?.round() ?? initialIndex) + 1
                                : initialIndex + 1;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                              child: Text('$current / ${_images.length}',
                                style: _body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                            );
                          },
                        ),
                        const SizedBox(width: 36), // Balance
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    ).then((_) => pageController.dispose());
  }

  // ── Process confirmation popup ──

  Future<void> _showProcessPopup() async {
    HapticFeedbackUtil.medium();
    final shouldProcess = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 36, height: 4, decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 16),
                Text('Process with AI', style: _heading(size: 18, weight: FontWeight.w700)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    _infoPill(Icons.image_outlined, '${_images.length} image${_images.length > 1 ? 's' : ''}'),
                    _infoPill(Icons.category_outlined, _categoryLabel),
                    if (_selectedSize != null) _infoPill(Icons.straighten_outlined, _selectedSize!),
                    _infoPill(Icons.store_outlined, _shopName),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Extract with AI', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: _body(size: 14, weight: FontWeight.w600, color: const Color(0xFF888888))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Defer to next frame so the bottom sheet's InheritedWidgets are fully
    // deactivated before _startProcessing calls setState.
    if (shouldProcess == true && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startProcessing();
      });
    }
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _infoPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD0D9F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF3855B3)),
          const SizedBox(width: 5),
          Text(text, style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF3855B3))),
        ],
      ),
    );
  }

  // ── Processing ──

  Future<void> _startProcessing() async {
    if (!mounted) return;
    final shopId = _shopId;
    final authService = context.read<AuthService>();

    if (shopId == null) {
      if (mounted) SnackbarHelper.showError(context, 'No shop selected');
      return;
    }

    setState(() {
      _currentStep = 4; // Processing step
      _progressStatus = 'Preparing images...';
      _progressValue = 0.0;
      _cancelled = false;
    });

    // Keep screen awake during AI processing
    try { await WakelockPlus.enable(); } catch (_) {}

    try {
      final service = SmartStockService(authService);

      String? categoryHint;
      if (_categoryKey == 'Beer') {
        categoryHint = 'beer';
      } else {
        categoryHint = 'non_beer';
      }

      // Find exact category ID for scoped matching
      String? exactCategoryId;
      final provider = context.read<ProductProvider>();
      for (final cat in provider.categories) {
        if (cat.name == _categoryKey) {
          exactCategoryId = cat.id;
          break;
        }
      }

      _resolvedCategoryId = exactCategoryId;

      final response = await service.extractFromStockRegister(
        images: List<File>.from(_images),
        shopId: shopId,
        category: categoryHint,
        categoryId: exactCategoryId,
        size: _selectedSize,
        stockColumn: _selectedStockColumn,
        onProgress: (current, total, status) {
          if (!mounted || _cancelled) return;
          setState(() {
            _progressStatus = status;
            _progressValue = total > 0 ? current / total : 0;
          });
        },
      );

      if (_cancelled || !mounted) return;

      if (response.success && response.data != null) {
        final result = response.data!;
        if (result.items.isEmpty) {
          setState(() => _currentStep = 3);
          if (mounted) {
            SnackbarHelper.showError(context,
                result.message.isNotEmpty ? result.message : 'No items could be extracted. Try a clearer image.');
          }
          return;
        }

        _result = result;
        _mergeAiResultsWithProducts();
        setState(() => _currentStep = 5);
      } else {
        setState(() => _currentStep = 3);
        if (mounted) SnackbarHelper.showError(context, response.message ?? 'Failed to process stock register');
      }
    } catch (e) {
      if (_cancelled || !mounted) return;
      setState(() => _currentStep = 3);
      if (mounted) SnackbarHelper.showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      try { await WakelockPlus.disable(); } catch (_) {}
    }
  }

  void _cancelProcessing() {
    _cancelled = true;
    try { WakelockPlus.disable(); } catch (_) {}
    setState(() => _currentStep = 3); // Back to upload step
  }

  // ── Merge AI results with product list ──

  void _mergeAiResultsWithProducts() {
    final items = _result?.items ?? [];

    _aiDetectedProductIds = {};
    _aiDetectedQuantities = {};
    _notFoundItems = [];

    for (final c in _quantityControllers.values) {
      c.dispose();
    }
    _quantityControllers.clear();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    _priceControllers.clear();

    // Controllers are created on-demand for AI-matched items in the loop below.
    // Do NOT pre-create controllers for all shop products — only show AI items.

    // Match AI items to controllers
    for (final item in items) {
      if (item.isNotFound && !item.autoCreated) {
        _notFoundItems.add(item);
        continue;
      }

      var productId = item.resolvedProductId;

      // Auto-create items may have product_id: null — use a synthetic ID
      // so they appear in the review list with an edit option.
      if ((productId == null || productId.isEmpty) && item.autoCreated) {
        productId = 'auto_${item.rowNumber}_${item.brandName.hashCode}';
      } else if (productId == null || productId.isEmpty) {
        _notFoundItems.add(item);
        continue;
      }

      // Create controller on the fly if it doesn't exist yet
      // (handles auto-created products not in allProducts)
      if (!_quantityControllers.containsKey(productId)) {
        _quantityControllers[productId] = TextEditingController();
      }

      _quantityControllers[productId]!.text =
          item.stockQuantity > 0 ? item.stockQuantity.toString() : '';
      _aiDetectedProductIds.add(productId);
      _aiDetectedQuantities[productId] = item.stockQuantity;
    }

    // Cache review products once so edits persist across rebuilds
    _reviewProducts = _buildReviewProductList();

    // Pre-populate manual entries with one empty row so the build never needs to schedule setState
    _manualEntries.add(_ManualEntry());
  }

  List<models.Product> _getFilteredProductsForReview() {
    return _allProducts.where((p) {
      // Category filter
      final catName = (p.category?.name ?? '').toLowerCase();
      if (_categoryKey == 'Beer') {
        if (!catName.contains('beer')) return false;
      } else {
        if (catName.contains('beer')) return false;
      }

      // Size filter — supports range labels
      if (_selectedSize != null) {
        if (!SizeRangeConstants.sizeMatchesRange(p.size, _selectedSize!, _categoryKey)) return false;
      }

      return true;
    }).toList();
  }

  List<_ReviewProduct> _buildReviewProductList() {
    // ONLY show items that were AI-detected — do NOT merge in all shop products.
    // This keeps the review screen focused on what the AI extracted.
    final allBackend = _result?.allProducts ?? [];
    final aiItems = _result?.items ?? [];
    final Map<String, _ReviewProduct> productMap = {};

    // Index backend allProducts by ID for enrichment (stock, MRP, etc.)
    final Map<String, StockSetupProductInfo> backendById = {};
    for (final p in allBackend) {
      backendById[p.productId] = p;
    }

    // Index local cache products by ID for enrichment fallback
    final Map<String, models.Product> localById = {};
    for (final p in _getFilteredProductsForReview()) {
      localById[p.id] = p;
    }

    // Build review list from AI-detected items ONLY
    for (final item in aiItems) {
      // Route "missing" items (DB products not on register) down the missing path below.
      if (item.isMissing) continue;
      // Truly not-found items without a product are shown in the dedicated not-found section; skip here.
      if (item.isNotFound && !item.autoCreated) continue;

      // Determine the ID used in _quantityControllers
      var pid = item.resolvedProductId;
      if ((pid == null || pid.isEmpty) && item.autoCreated) {
        pid = 'auto_${item.rowNumber}_${item.brandName.hashCode}';
      }
      if (pid == null || pid.isEmpty) continue;
      if (productMap.containsKey(pid)) continue;

      // Enrich from backend allProducts or local cache if available
      final backend = backendById[pid];
      final local = localById[pid];

      // Prefer backend's clean display name; fall back to official/backend/local/raw
      final displayName = item.matchedDisplayName
          ?? item.officialBrandName
          ?? backend?.name
          ?? local?.name
          ?? item.brandName;

      productMap[pid] = _ReviewProduct(
        id: pid,
        name: displayName,
        brandName: backend?.brandName ?? local?.brand?.name ?? item.brandName,
        matchedFullName: item.matchedFullName,
        exciseName: item.exciseName,
        size: item.size.isNotEmpty
            ? item.size
            : (backend?.size ?? local?.size ?? _selectedSize ?? ''),
        mrp: (backend?.mrp ?? 0) > 0
            ? backend!.mrp
            : (local?.sellingPrice ?? 0) > 0
                ? local!.sellingPrice
                : item.rate,
        rate: item.rate,
        currentStock: backend?.currentStock ?? _stockMap[pid]?.quantity ?? 0,
        rowNumber: item.rowNumber,
        needsReview: item.needsReview,
        reviewReason: item.reviewReason,
        autoCreated: item.autoCreated,
        rawBrandName: item.brandName,
        status: item.status,
        opening: item.opening,
        receipt: item.receipt,
        sale: item.sale,
        closingStock: item.closingStock,
        alternatives: item.alternativeMatches,
        masterBrandSuggestions: item.masterBrandSuggestions,
        warnings: item.warnings,
        officialBrandName: item.officialBrandName,
      );
    }

    // Synthesize rows for items the backend flagged as "missing"
    // (DB products not on the register) so the user can explicitly zero them out.
    for (final item in aiItems.where((i) => i.isMissing)) {
      final pid = item.productId;
      if (pid == null || pid.isEmpty) continue;
      if (productMap.containsKey(pid)) continue;
      final backend = backendById[pid];
      final local = localById[pid];
      final displayName = item.matchedDisplayName
          ?? item.officialBrandName
          ?? backend?.name
          ?? local?.name
          ?? item.brandName;
      productMap[pid] = _ReviewProduct(
        id: pid,
        name: displayName,
        brandName: backend?.brandName ?? local?.brand?.name ?? item.brandName,
        matchedFullName: item.matchedFullName,
        exciseName: item.exciseName,
        size: item.size.isNotEmpty ? item.size : (backend?.size ?? local?.size ?? ''),
        mrp: (backend?.mrp ?? 0) > 0 ? backend!.mrp : (local?.sellingPrice ?? 0),
        currentStock: backend?.currentStock ?? _stockMap[pid]?.quantity ?? 0,
        rowNumber: item.rowNumber,
        rawBrandName: item.brandName,
        status: 'missing',
        warnings: item.warnings,
        officialBrandName: item.officialBrandName,
      );
    }

    return productMap.values.toList();
  }

  List<_ReviewProduct> _getFilteredReviewProducts() {
    var products = List<_ReviewProduct>.from(_reviewProducts);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      products = products.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.brandName.toLowerCase().contains(q)
      ).toList();
    }

    // Sort: AI-detected first (by row number), then rest alphabetically
    products.sort((a, b) {
      final ad = _aiDetectedProductIds.contains(a.id);
      final bd = _aiDetectedProductIds.contains(b.id);
      if (ad && !bd) return -1;
      if (!ad && bd) return 1;
      if (ad && bd && a.rowNumber != b.rowNumber) return a.rowNumber.compareTo(b.rowNumber);
      return a.name.compareTo(b.name);
    });

    return products;
  }

  // ── Review helpers ──

  int get _productsWithQtyCount {
    int count = 0;
    for (final entry in _quantityControllers.entries) {
      final qty = int.tryParse(entry.value.text) ?? 0;
      if (qty > 0) count++;
    }
    // Include filled manual entries
    for (final e in _manualEntries) {
      if (e.hasName && e.hasQty) count++;
    }
    return count;
  }

  int get _totalBottles {
    int total = 0;
    for (final entry in _quantityControllers.entries) {
      total += int.tryParse(entry.value.text) ?? 0;
    }
    for (final e in _manualEntries) {
      total += int.tryParse(e.qtyController.text) ?? 0;
    }
    return total;
  }

  TextEditingController _getOrCreateController(String productId) {
    if (!_quantityControllers.containsKey(productId)) {
      _quantityControllers[productId] = TextEditingController();
    }
    return _quantityControllers[productId]!;
  }

  // ── Save opening stock ──

  Future<void> _setOpeningStock() async {
    if (!mounted) return;
    final shopId = _shopId;

    if (shopId == null) {
      SnackbarHelper.showError(context, 'No shop selected');
      return;
    }

    final applyItems = <Map<String, dynamic>>[];
    for (final entry in _quantityControllers.entries) {
      final qty = int.tryParse(entry.value.text) ?? 0;
      if (qty <= 0) continue;

      final product = _reviewProducts.cast<_ReviewProduct?>().firstWhere(
        (p) => p?.id == entry.key, orElse: () => null,
      );
      if (product == null) continue;

      final isAutoCreate = entry.key.startsWith('auto_') || product.isAutoCreate;
      final productId = isAutoCreate ? '' : entry.key;
      final officialName = product.officialBrandName ?? product.name;
      final editedName = product.nameEdited ? product.name : '';

      applyItems.add({
        'product_id'         : productId,
        'quantity'           : qty,
        'brand_name'         : product.name,
        'size'               : product.size.isNotEmpty ? product.size : (_selectedSize ?? ''),
        if (product.rate > 0) 'rate': product.rate,
        if (product.mrp > 0)  'mrp' : product.mrp,
        'opening_stock'      : product.opening,
        'receipt'            : product.receipt,
        'sale'               : product.sale,
        'closing_stock'      : product.closingStock,
        'official_brand_name': officialName,
        'category_name'      : _categoryLabel,
        'edited_name'        : editedName,
        'ocr_text'           : product.rawBrandName,
        'was_corrected'      : product.wasCorrected,
        'original_product_id': product.originalProductId ?? '',
      });
    }

    // Include manual entries (no backend OCR context — just brand + qty + price).
    for (final e in _manualEntries) {
      if (e.hasName && e.hasQty) {
        final price = double.tryParse(e.priceController.text) ?? 0;
        final name = e.nameController.text.trim();
        applyItems.add({
          'product_id'         : '',
          'brand_name'         : name,
          'official_brand_name': name,
          'edited_name'        : name,
          'category_name'      : _categoryLabel,
          'size'               : _selectedSize ?? '',
          'quantity'           : int.tryParse(e.qtyController.text) ?? 0,
          if (price > 0) 'mrp' : price,
          if (price > 0) 'rate': price,
          'was_corrected'      : true,
          'original_product_id': '',
          'ocr_text'           : '',
          'opening_stock'      : 0,
          'receipt'            : 0,
          'sale'               : 0,
          'closing_stock'      : 0,
        });
      }
    }

    if (applyItems.isEmpty) {
      SnackbarHelper.showError(context, 'No products to set stock for');
      return;
    }

    final hasExistingStock = applyItems.any((item) {
      final stock = _stockMap[item['product_id']];
      return stock != null && stock.quantity > 0;
    });

    if (hasExistingStock) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Overwrite Existing Stock?', style: _heading(size: 16, weight: FontWeight.w700)),
          content: Text(
            'Some products already have stock. Setting opening stock will REPLACE their current values.',
            style: _body(size: 14, color: const Color(0xFF555555)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: _body(size: 14, color: const Color(0xFF888888))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3855B3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Overwrite', style: _body(size: 14, weight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      // Wait one frame for the dialog's InheritedWidgets to fully deactivate
      await Future.delayed(Duration.zero);
      if (!mounted) return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final authService = context.read<AuthService>();
      final service = SmartStockService(authService);

      final response = await service.applyStockSetup(
        shopId: shopId,
        items: applyItems,
        notes: 'Set via AI Stock Setup - ${applyItems.length} products ($_categoryLabel · ${_selectedSize ?? "All"})',
        categoryId: _resolvedCategoryId,
        size: _selectedSize,
        stockColumn: _selectedStockColumn,
        sessionId: _result?.sessionId,
        imageUrls: _result?.imageUrls.isNotEmpty == true ? _result!.imageUrls : null,
      );

      if (!mounted) return;

      if (response.success) {
        final data = response.data;
        final setCount = data?['products_set'] ?? data?['items_applied'] ?? applyItems.length;
        final cleanedUp = data?['cleaned_up'] ?? 0;
        HapticFeedbackUtil.success();
        final msg = cleanedUp > 0
            ? 'Stock set for $setCount product${setCount > 1 ? 's' : ''}, $cleanedUp unused removed'
            : 'Stock set for $setCount product${setCount > 1 ? 's' : ''}';
        SnackbarHelper.showSuccess(context, msg);

        // Refresh products + stock BEFORE popping so parent has fresh data
        try {
          final productProvider = context.read<ProductProvider>();
          await productProvider.loadProducts(shopId: shopId);
        } catch (_) {
          // Non-fatal — parent will also try to refresh
        }

        if (!mounted) return;
        await AIFeedbackBottomSheet.show(
          context,
          flowType: AIFlowType.stockSetup,
          successMessage: msg,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
        return; // Don't fall through — widget is being removed from tree
      } else {
        if (mounted) setState(() => _isSaving = false);
        SnackbarHelper.showError(context, response.message ?? 'Failed to set stock.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      SnackbarHelper.showError(context, 'Error: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  // ── Back navigation ──

  Future<bool> _onWillPop() async {
    switch (_currentStep) {
      case 0:
        return true;
      case 1:
        setState(() => _currentStep = 0);
        return false;
      case 2:
        setState(() => _currentStep = 1);
        return false;
      case 3:
        setState(() => _currentStep = 2);
        return false;
      case 4:
        _cancelProcessing();
        return false;
      case 5:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Go Back?', style: _heading(size: 16, weight: FontWeight.w700)),
            content: Text('You will lose the AI results. Re-upload to process again.',
                style: _body(size: 14, color: const Color(0xFF555555))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Stay', style: _body(size: 14, color: const Color(0xFF888888))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3855B3), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Go Back', style: _body(size: 14, weight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _currentStep = 3);
          });
        }
        return false;
      default:
        return true;
    }
  }

  void _handleBack() {
    switch (_currentStep) {
      case 0:
        Navigator.pop(context);
      case 1:
        setState(() => _currentStep = 0);
      case 2:
        setState(() => _currentStep = 1);
      case 3:
        setState(() => _currentStep = 2);
      case 4:
        _cancelProcessing();
      case 5:
        _onWillPop();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titles = ['Type of liquor', 'Type of capacity', 'Stock Column', 'AI Stock Setup', 'AI Stock Setup', 'Review & Edit'];
    final title = titles[_currentStep.clamp(0, 5)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _handleBack,
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
              child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
            ),
          ),
          Expanded(
            child: Text(title, textAlign: TextAlign.center,
                style: _heading(size: 17, weight: FontWeight.w600)),
          ),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE8EEF8),
              border: Border.all(color: const Color(0xFFD0D8E8), width: 1),
            ),
            child: Center(
              child: SizedBox(
                width: 20, height: 20,
                child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return switch (_currentStep) {
      0 => _buildCategoryStep(),
      1 => _buildSizeStep(),
      2 => _buildStockColumnStep(),
      3 => _buildUploadStep(),
      4 => _buildProcessingStep(),
      5 => _buildReviewStep(),
      _ => const SizedBox(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // Step 0: Select Category (same style as SalesEntrySetupScreen)
  // ═══════════════════════════════════════════════════════════

  Widget _buildCategoryStep() {
    return Column(
      children: [
        // Context bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF2962FF)),
                const SizedBox(width: 8),
                Text('AI Stock Setup · $_shopName',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      ..._getUniqueCategories().map((cat) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildCategoryCard(
                          category: cat,
                          title: cat == 'English' ? 'Whisky & Spirits' : cat,
                          subtitle: cat == 'English'
                              ? 'Whisky, Vodka, Rum, Gin & more \u2022 ${_getProductsForCategory(cat).length} products'
                              : '${_getProductsForCategory(cat).length} products',
                          imageAsset: cat == 'Beer' ? _StockAssets.beerCard : _StockAssets.whiskyCard,
                          icon: cat == 'Beer' ? Icons.sports_bar : Icons.liquor,
                        ),
                      )),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard({
    required String category,
    required String title,
    required String subtitle,
    required String imageAsset,
    required IconData icon,
  }) {
    final totalStock = _getTotalStock(category);
    final totalValue = _getTotalValue(category);

    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.medium();
        setState(() {
          if (category == 'Beer') {
            _isEnglishFilterSelected = false;
            _selectedCategoryName = 'Beer';
          } else {
            _isEnglishFilterSelected = true;
            _selectedCategoryName = 'Whisky';
          }
          _selectedSize = null;
          // Beer: skip size selection, go directly to image upload
          _currentStep = (category == 'Beer') ? 3 : 1;
        });
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFD0D4DC), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image area ──
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 120,
                      child: Image.asset(
                        imageAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1A1A2E),
                          child: Center(child: Icon(icon, size: 50, color: Colors.white24)),
                        ),
                      ),
                    ),
                  ),
                  // AI badge
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF2962FF), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('AI', style: _body(size: 11, weight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Text area ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _body(size: 16, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: _body(size: 12, weight: FontWeight.w500, color: const Color(0xFF333333)), maxLines: 2),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SvgPicture.asset('assets/icons/cart_stock.svg', width: 16, height: 16,
                          colorFilter: const ColorFilter.mode(Color(0xFF555555), BlendMode.srcIn)),
                      const SizedBox(width: 4),
                      Text('$totalStock', style: _body(size: 14, weight: FontWeight.w700)),
                      const SizedBox(width: 16),
                      SvgPicture.asset('assets/icons/wallet_income.svg', width: 16, height: 16,
                          colorFilter: const ColorFilter.mode(Color(0xFF555555), BlendMode.srcIn)),
                      const SizedBox(width: 4),
                      Text(_formatValue(totalValue), style: _body(size: 14, weight: FontWeight.w700)),
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

  // ═══════════════════════════════════════════════════════════
  // Step 1: Select Size (same style as _SalesCapacityScreen)
  // ═══════════════════════════════════════════════════════════

  Widget _buildSizeStep() {
    // Guard: if products aren't loaded yet, show spinner
    if (_allProducts.isEmpty && _isLoadingData) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final sizeStats = _getSizeStats();

    return Column(
      children: [
        // ── Context bar with category badge ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF2962FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('AI Stock Setup · $_shopName',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF))),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_categoryLabel,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Hero image ──
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD0D4DC), width: 1.2),
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: 120,
              child: Image.asset(
                _categoryKey == 'Beer' ? _StockAssets.beerCard : _StockAssets.whiskyHero,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF1A1A2E),
                  child: Center(child: Icon(
                    _categoryKey == 'Beer' ? Icons.sports_bar : Icons.liquor,
                    size: 50, color: Colors.white24,
                  )),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Size list ──
        Expanded(
          child: sizeStats.isEmpty
              ? Center(child: Text('No sizes available', style: _body(size: 14, color: const Color(0xFF888888))))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: sizeStats.length,
                  separatorBuilder: (_, __) => Divider(height: 1, thickness: 0.5, color: Colors.grey.withValues(alpha: 0.15)),
                  itemBuilder: (context, index) {
                    final stat = sizeStats.values.elementAt(index);
                    return _buildSizeRow(stat);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSizeRow(_SizeStats stat) {
    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.medium();
        setState(() {
          _selectedSize = stat.size;
          _currentStep = 2; // Go to stock column selection
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left: bottle icon
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F1F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _categoryKey == 'Beer' ? Icons.sports_bar_rounded : Icons.liquor_rounded,
                size: 18, color: const Color(0xFF888888),
              ),
            ),
            const SizedBox(width: 12),
            // Middle: name + stats
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stat.size.replaceAll("ML", "ml")} $_categoryLabel',
                    style: _body(size: 15, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SvgPicture.asset('assets/icons/cart_stock.svg', width: 13, height: 13,
                          colorFilter: const ColorFilter.mode(Color(0xFF999999), BlendMode.srcIn)),
                      const SizedBox(width: 5),
                      Text('${stat.totalStock}', style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF999999))),
                      const SizedBox(width: 16),
                      SvgPicture.asset('assets/icons/wallet_income.svg', width: 13, height: 13,
                          colorFilter: const ColorFilter.mode(Color(0xFF999999), BlendMode.srcIn)),
                      const SizedBox(width: 5),
                      Text(_formatValue(stat.totalValue), style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF999999))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: View button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD0D5DD)),
              ),
              child: Text('View', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Step 2: Stock Column Selection
  // ═══════════════════════════════════════════════════════════

  Widget _buildStockColumnStep() {
    final columns = [
      _StockColumnOption(
        key: 'opening',
        title: 'Opening Stock',
        subtitle: 'Use the Opening column — best for initial stock setup',
        icon: Icons.inventory_2_outlined,
        recommended: true,
      ),
      _StockColumnOption(
        key: 'total',
        title: 'Total Stock',
        subtitle: 'Opening + Receipts — use when receipts are included',
        icon: Icons.summarize_outlined,
        recommended: false,
      ),
      _StockColumnOption(
        key: 'closing',
        title: 'Closing Stock',
        subtitle: 'End of day stock — after all sales deducted',
        icon: Icons.nightlight_outlined,
        recommended: false,
      ),
    ];

    return Column(
      children: [
        // Context bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF2962FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$_categoryLabel · ${_selectedSize ?? ""} · $_shopName',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('Which stock column to use?', style: _heading(size: 18, weight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Choose which register column the AI should read for stock quantities',
            style: _body(size: 13, color: const Color(0xFF888888)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: columns.length,
            itemBuilder: (context, index) {
              final col = columns[index];
              final isSelected = _selectedStockColumn == col.key;
              return GestureDetector(
                onTap: () {
                  HapticFeedbackUtil.selection();
                  setState(() => _selectedStockColumn = col.key);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF3855B3) : const Color(0xFFE0E0E0),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? const Color(0xFF3855B3) : Colors.transparent,
                          border: Border.all(
                            color: isSelected ? const Color(0xFF3855B3) : const Color(0xFFBBBBBB),
                            width: 2,
                          ),
                        ),
                        child: isSelected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 14),
                      Icon(col.icon, size: 22, color: isSelected ? const Color(0xFF3855B3) : const Color(0xFF888888)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(col.title, style: _body(
                                  size: 15,
                                  weight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? const Color(0xFF3855B3) : const Color(0xFF1A1D26),
                                )),
                                if (col.recommended) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('Recommended',
                                        style: _body(size: 9, weight: FontWeight.w700, color: const Color(0xFF2E7D32))),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(col.subtitle, style: _body(size: 12, color: const Color(0xFF888888))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Next button
        Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF3855B3)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedbackUtil.selection();
                  setState(() => _currentStep = 3); // Go to upload
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.arrow_forward_rounded, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Text('Next', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Step 3: Upload Images
  // ═══════════════════════════════════════════════════════════

  Widget _buildUploadStep() {
    return Column(
      children: [
        // Context bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD0D9F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF3855B3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_categoryLabel · ${_selectedSize ?? ""} · $_shopName',
                    style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF3855B3)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _images.isEmpty ? _buildEmptyImageState() : _buildImageGrid(),
        ),
        if (_images.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFFE8EAF0)),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).padding.bottom + 18),
            child: SizedBox(
              width: double.infinity, height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  onPressed: _showProcessPopup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Process with AI', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyImageState() {
    return Center(
      child: GestureDetector(
        onTap: _showImageSourceSheet,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD0D9F0), width: 1.5),
              ),
              child: const Icon(Icons.add_a_photo_rounded, size: 36, color: Color(0xFF3855B3)),
            ),
            const SizedBox(height: 14),
            Text('Upload Stock Register', style: _heading(size: 16, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Take a photo or select from gallery', style: _body(size: 13, color: const Color(0xFF888888))),
            const SizedBox(height: 4),
            Text('Up to 5 images', style: _body(size: 12, color: const Color(0xFFAAAAAA))),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_images.length}/5 images attached', style: _body(size: 13, color: const Color(0xFF888888))),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85,
              ),
              itemCount: _images.length + (_images.length < 5 ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == _images.length) {
                  return GestureDetector(
                    onTap: _showImageSourceSheet,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7FA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD0D5DD), width: 1),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 28, color: Color(0xFF888888)),
                          SizedBox(height: 4),
                          Text('Add', style: TextStyle(fontSize: 11, color: Color(0xFF888888), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () => _showImagePreview(i),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.expand(child: Image.file(_images[i], fit: BoxFit.cover)),
                      ),
                      // Page number badge
                      Positioned(
                        bottom: 4, left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: Text('${i + 1}', style: _body(size: 10, weight: FontWeight.w700, color: Colors.white)),
                        ),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => _removeImage(i),
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Step 3: AI Processing
  // ═══════════════════════════════════════════════════════════

  Widget _buildProcessingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: const Color(0xFF2962FF).withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 2)],
                ),
                child: const Icon(Icons.auto_awesome, size: 40, color: Colors.white),
              ),
            ),
            const SizedBox(height: 28),
            Text('Processing Stock Register...', style: _heading(size: 20, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                _progressStatus,
                key: ValueKey(_progressStatus),
                style: _body(size: 14, color: const Color(0xFF888888)),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progressValue > 0 ? _progressValue : null,
                minHeight: 6,
                backgroundColor: const Color(0xFFE8EAF0),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2962FF)),
              ),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: _cancelProcessing,
              child: Text('Cancel', style: _body(size: 14, weight: FontWeight.w600, color: const Color(0xFFD84315))),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // Step 4: Review & Edit Product Grid
  // ═══════════════════════════════════════════════════════════

  Widget _buildReviewStep() {
    final products = _getFilteredReviewProducts();
    final aiCount = _aiDetectedProductIds.length;
    final aiBottles = _aiDetectedQuantities.values.fold<int>(0, (sum, q) => sum + q);
    final validation = _result?.validation;
    final autoCreated = validation?.autoCreatedItems ?? 0;
    final processing = _result?.processingDetails;
    final reviewCount = products.where((p) => p.needsReview).length;

    return Column(
      children: [
        // AI summary header with stats
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                      'AI detected $aiCount products · $aiBottles btl',
                      style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF3855B3)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6, runSpacing: 4,
                children: [
                  _statChip('${validation?.matchedItems ?? aiCount} matched', const Color(0xFF4CAF50)),
                  if (autoCreated > 0) _statChip('$autoCreated new', const Color(0xFF2962FF)),
                  if (reviewCount > 0) _statChip('$reviewCount review', const Color(0xFFF57C00)),
                  if (_notFoundItems.isNotEmpty) _statChip('${_notFoundItems.length} missed', const Color(0xFFE53935)),
                  _statChip('$_categoryLabel · ${_selectedSize ?? ""}', const Color(0xFF2E7D32)),
                  if (processing != null)
                    _statChip('${processing.formattedTime} · ${processing.aiModel ?? "AI"}', const Color(0xFF888888)),
                ],
              ),
            ],
          ),
        ),

        // Stock column suggestion banner
        if (_result?.suggestedStockColumn != null &&
            _result!.suggestedStockColumn != _selectedStockColumn)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFF57C00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Suggestion: Use "${_result!.suggestedStockColumn}" column instead',
                    style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFFF57C00)),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedStockColumn = _result!.suggestedStockColumn!;
                      // Recalculate quantities for all AI items
                      for (final item in _result!.items) {
                        final pid = item.resolvedProductId;
                        if (pid != null && _quantityControllers.containsKey(pid)) {
                          final newQty = item.getStockForColumn(_selectedStockColumn);
                          if (newQty > 0) {
                            _quantityControllers[pid]!.text = newQty.toString();
                            _aiDetectedQuantities[pid] = newQty;
                          }
                        }
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF57C00),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Apply', style: _body(size: 11, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),

        // Not found warning
        if (_notFoundItems.isNotEmpty) _buildNotFoundSection(),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: _body(size: 14, color: const Color(0xFFAAAAAA)),
              prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF888888)),
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3855B3), width: 1.5)),
            ),
            style: _body(size: 14),
          ),
        ),

        // Product list + manual entries
        Expanded(
          child: Builder(builder: (_) {
            final mainProducts = products.where((p) => !p.isMissing).toList();
            final missingProducts = products.where((p) => p.isMissing).toList();
            if (mainProducts.isEmpty && missingProducts.isEmpty && _manualEntries.isEmpty) {
              return Center(child: Text('No products found', style: _body(size: 14, color: const Color(0xFF888888))));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                ...mainProducts.map((p) => _buildProductRow(p)),
                if (missingProducts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildMissingSection(missingProducts),
                ],
                const SizedBox(height: 12),
                _buildManualAddSection(),
              ],
            );
          }),
        ),

        // Bottom bar
        _buildReviewBottomBar(),
      ],
    );
  }

  Widget _buildNotFoundSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _notFoundExpanded = !_notFoundExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFF57C00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_notFoundItems.length} item${_notFoundItems.length > 1 ? 's' : ''} not matched',
                      style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFFF57C00)),
                    ),
                  ),
                  Icon(_notFoundExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFFF57C00)),
                ],
              ),
            ),
          ),
          if (_notFoundExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                children: _notFoundItems.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 26),
                      Expanded(
                        child: Text('${item.brandName} ${item.size}',
                            style: _body(size: 12, color: const Color(0xFF666666)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text('Qty: ${item.quantity}',
                          style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFFF57C00))),
                    ],
                  ),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // Collapsible "Products in DB but not on register" — the `missing` bucket.
  // Users can explicitly zero out these counts so stock takes settle to 0.
  Widget _buildMissingSection(List<_ReviewProduct> missing) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E6EE)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _missingExpanded = !_missingExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.inventory_rounded, size: 18, color: Color(0xFF6B7280)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${missing.length} product${missing.length > 1 ? 's' : ''} in DB but not on register',
                          style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF374151)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Confirm stock or leave as 0',
                          style: _body(size: 11, color: const Color(0xFF8A93A6), weight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  Icon(_missingExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: const Color(0xFF6B7280)),
                ],
              ),
            ),
          ),
          if (_missingExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: missing.map(_buildProductRow).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ── Status color palette (single source of truth) ──
  // Keeps border/bg tone aligned with meaning everywhere in the screen.
  ({Color border, Color bg, Color accent, String label}) _statusTheme(_ReviewProduct p) {
    if (p.isMissing) {
      return (
        border: const Color(0xFFD0D5DD), bg: const Color(0xFFFAFBFC),
        accent: const Color(0xFF6B7280), label: 'Not on register',
      );
    }
    if (p.isNotFound) {
      return (
        border: const Color(0xFFE53935), bg: const Color(0xFFFFF5F5),
        accent: const Color(0xFFE53935), label: 'Not found',
      );
    }
    if (p.isAutoCreate) {
      return (
        border: const Color(0xFF2962FF), bg: const Color(0xFFF5F8FF),
        accent: const Color(0xFF2962FF), label: 'Will create',
      );
    }
    if (p.isLowConfidence || p.needsReview) {
      return (
        border: const Color(0xFFF57C00), bg: const Color(0xFFFFF8F0),
        accent: const Color(0xFFF57C00), label: 'Review',
      );
    }
    // matched
    return (
      border: const Color(0xFFD0D9F0), bg: const Color(0xFFF5F8FF),
      accent: const Color(0xFF2962FF), label: 'Matched',
    );
  }

  Widget _buildProductRow(_ReviewProduct product) {
    final isAiDetected = _aiDetectedProductIds.contains(product.id);
    final controller = _getOrCreateController(product.id);
    final currentStockQty = product.currentStock;
    final qty = int.tryParse(controller.text) ?? 0;
    final sizeML = ProductConstants.normalizeSize(product.size);
    final theme = _statusTheme(product);
    final hasReviewBanner = product.needsReview && (product.reviewReason?.isNotEmpty ?? false);
    // Prefer authoritative excise name; fall back to catalog full name.
    final subtitle = (product.exciseName != null && product.exciseName!.trim().isNotEmpty
            && product.exciseName!.trim() != product.name.trim())
        ? product.exciseName
        : (product.matchedFullName != null
                && product.matchedFullName!.trim().isNotEmpty
                && product.matchedFullName!.trim() != product.name.trim()
            ? product.matchedFullName
            : null);
    final subtitleIsExcise = subtitle != null && subtitle == product.exciseName;
    final showFullName = subtitle != null;
    final showOcr = product.rawBrandName.isNotEmpty
        && product.rawBrandName != product.name
        && product.rawBrandName != subtitle;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.border, width: product.needsReview || product.isNotFound ? 1.2 : 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: row# + names + status/badges ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.rowNumber > 0)
                Container(
                  width: 24, height: 24,
                  margin: const EdgeInsets.only(right: 8, top: 1),
                  decoration: BoxDecoration(
                    color: isAiDetected ? theme.accent : const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Center(
                    child: Text('${product.rowNumber}',
                      style: _body(size: 10, weight: FontWeight.w800, color: isAiDetected ? Colors.white : const Color(0xFF666666))),
                  ),
                ),
              // Name column (tappable → unified edit sheet)
              Expanded(
                child: GestureDetector(
                  onTap: () => _showEditProductSheet(product),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF141F39), height: 1.2),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_outlined, size: 12, color: Color(0xFFBBBBBB)),
                        ],
                      ),
                      if (showFullName) ...[
                        const SizedBox(height: 2),
                        RichText(
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF8A93A6), height: 1.25),
                            children: [
                              TextSpan(
                                text: product.isAutoCreate
                                    ? 'Will create as: '
                                    : (subtitleIsExcise ? 'Excise: ' : 'Catalog: '),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: product.isAutoCreate
                                      ? const Color(0xFF2962FF)
                                      : (subtitleIsExcise ? const Color(0xFF1565C0) : const Color(0xFF6B7280)),
                                ),
                              ),
                              TextSpan(text: subtitle),
                            ],
                          ),
                        ),
                      ],
                      if (showOcr) ...[
                        const SizedBox(height: 2),
                        Text(
                          'OCR: ${product.rawBrandName}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFFAAAAAA), fontStyle: FontStyle.italic),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Status badge cluster
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (product.isAutoCreate)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF2962FF), borderRadius: BorderRadius.circular(6)),
                      child: Text('NEW', style: _body(size: 8, weight: FontWeight.w800, color: Colors.white)),
                    )
                  else if (product.isNotFound)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(6)),
                      child: Text('MISSING', style: _body(size: 8, weight: FontWeight.w800, color: Colors.white)),
                    )
                  else if (product.isMissing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF6B7280), borderRadius: BorderRadius.circular(6)),
                      child: Text('DB ONLY', style: _body(size: 8, weight: FontWeight.w800, color: Colors.white)),
                    )
                  else if (isAiDetected)
                    const Icon(Icons.auto_awesome, size: 15, color: Color(0xFF2962FF)),
                  // Confidence % chip when we have one
                  if (!product.isMissing && !product.isNotFound) ...[
                    const SizedBox(height: 3),
                    _confidenceChip(product),
                  ],
                ],
              ),
            ],
          ),

          // ── Review reason banner ──
          if (hasReviewBanner) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE0B2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFF57C00)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      product.reviewReason!,
                      style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFFE65100)),
                      maxLines: 3, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Warnings (comma-free row of yellow chips) ──
          if (product.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4, runSpacing: 4,
              children: product.warnings.map(_warningChip).toList(),
            ),
          ],

          // ── Not-found CTAs ──
          if (product.isNotFound) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showNotFoundPickerSheet(product),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE53935)),
                      foregroundColor: const Color(0xFFE53935),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.search, size: 14),
                    label: Text('Pick existing', style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFFE53935))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _convertToAutoCreate(product),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2962FF)),
                      foregroundColor: const Color(0xFF2962FF),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: Text('Add new', style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF2962FF))),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 8),

          // ── Row: chips + stepper ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Size tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3)),
                child: Text(sizeML,
                    style: const TextStyle(fontSize: 8.5, color: Color(0xFF6B7280), fontWeight: FontWeight.w700, letterSpacing: 0.3)),
              ),
              const SizedBox(width: 6),

              // Price (tappable to edit)
              GestureDetector(
                onTap: () => _showEditProductSheet(product, focus: _EditFocus.price),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₹${product.mrp > 0 ? product.mrp.toStringAsFixed(0) : "--"}',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900,
                        color: product.mrp > 0 ? const Color(0xFF0B1536) : const Color(0xFFE53935),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.edit_outlined, size: 10,
                      color: product.mrp > 0 ? const Color(0xFFBBBBBB) : const Color(0xFFE53935)),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Current stock
              Icon(Icons.inventory_2_rounded, size: 11,
                  color: currentStockQty > 0 ? const Color(0xFF10B981) : const Color(0xFFBBBBBB)),
              const SizedBox(width: 2),
              Text(
                '$currentStockQty',
                style: TextStyle(fontSize: 10, color: currentStockQty > 0 ? const Color(0xFF10B981) : const Color(0xFFBBBBBB), fontWeight: FontWeight.w600),
              ),

              // Master brand suggestions chip — auto_create rows with saas_brands candidates.
              // Takes precedence over generic alts/search because this is the primary action
              // for rows like "1965 Ram" where backend surfaced 5 real master brands.
              if (product.isAutoCreate && product.masterBrandSuggestions.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showMasterBrandSuggestionsSheet(product),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8EAF6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF9FA8DA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.style_outlined, size: 10, color: Color(0xFF3F51B5)),
                        const SizedBox(width: 2),
                        Text('Pick brand (${product.masterBrandSuggestions.length})',
                            style: _body(size: 9.5, weight: FontWeight.w800, color: const Color(0xFF3F51B5))),
                      ],
                    ),
                  ),
                ),
              ]
              // Alternatives chip — always show when present, even on matched rows for transparency
              else if (product.alternatives.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showAlternativesPickerSheet(product),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFFCC80)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horiz, size: 10, color: Color(0xFFE65100)),
                        const SizedBox(width: 2),
                        Text('Alts (${product.alternatives.length})',
                            style: _body(size: 9.5, weight: FontWeight.w800, color: const Color(0xFFE65100))),
                      ],
                    ),
                  ),
                ),
              ]
              // Fallback: when no alternatives but row still wants review, let the user
              // search the catalog manually to correct the match.
              else if (product.isAutoCreate || product.isLowConfidence) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showNotFoundPickerSheet(product),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF90CAF9)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search, size: 10, color: Color(0xFF1565C0)),
                        const SizedBox(width: 2),
                        Text('Search catalog',
                            style: _body(size: 9.5, weight: FontWeight.w800, color: const Color(0xFF1565C0))),
                      ],
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Quantity stepper
              Container(
                decoration: BoxDecoration(
                  color: qty > 0 ? const Color(0xFFE8F0FE) : const Color(0xFFF4F7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        final current = int.tryParse(controller.text) ?? 0;
                        if (current > 0) {
                          setState(() {
                            controller.text = (current - 1).toString();
                          });
                          HapticFeedbackUtil.light();
                        }
                      },
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                        child: const Center(child: Icon(Icons.remove, size: 14, color: Color(0xFF6B7280))),
                      ),
                    ),
                    SizedBox(
                      width: 38, height: 26,
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800,
                          color: qty > 0 ? const Color(0xFF2962FF) : const Color(0xFF141F39),
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                          isDense: true,
                          hintText: '0',
                          hintStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFFCCCCCC)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        final current = int.tryParse(controller.text) ?? 0;
                        setState(() {
                          controller.text = (current + 1).toString();
                        });
                        HapticFeedbackUtil.light();
                      },
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A73E8),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: const Color(0xFF1A73E8).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: const Center(child: Icon(Icons.add, size: 14, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _confidenceChip(_ReviewProduct p) {
    // Use the best available confidence: the resolved alt's confidence, or the
    // AI's original confidence (stored on the source SmartStockItem).
    final item = _result?.items.firstWhere(
      (i) => i.rowNumber == p.rowNumber,
      orElse: () => SmartStockItem(brandName: '', size: ''),
    );
    final conf = item == null || item.matchConfidence == 0 ? null : item.matchConfidence;
    if (conf == null || conf <= 0) return const SizedBox.shrink();
    final pct = (conf * 100).round();
    final color = pct >= 90
        ? const Color(0xFF10B981)
        : pct >= 70
            ? const Color(0xFFF57C00)
            : const Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text('$pct%', style: _body(size: 9, weight: FontWeight.w800, color: color)),
    );
  }

  Widget _warningChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.info_outline, size: 10, color: Color(0xFFB8860B)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              text,
              style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFF8A6D00)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // Convert a not_found row into an auto-create row locally so the apply payload
  // sends brand_name (product_id empty) and the backend creates it.
  void _convertToAutoCreate(_ReviewProduct product) {
    HapticFeedbackUtil.light();
    setState(() {
      final newId = 'auto_${product.rowNumber}_${DateTime.now().microsecondsSinceEpoch}';
      // Re-bind the controller to the new id so the stepper keeps its value
      final ctrl = _quantityControllers.remove(product.id);
      if (ctrl != null) _quantityControllers[newId] = ctrl;
      product.originalProductId ??= product.id;
      product.id = newId;
      product.status = 'auto_create';
      product.wasCorrected = true;
    });
    SnackbarHelper.showSuccess(context, 'Will create "${product.name}" on save');
  }

  // ── Modern edit sheet (replaces both name + price AlertDialogs) ──

  Future<void> _showEditProductSheet(
    _ReviewProduct product, {
    _EditFocus focus = _EditFocus.name,
  }) async {
    final nameCtrl = TextEditingController(text: product.name);
    final mrpCtrl = TextEditingController(
      text: product.mrp > 0 ? product.mrp.toStringAsFixed(product.mrp.truncateToDouble() == product.mrp ? 0 : 2) : '',
    );
    final qtyCtrl = TextEditingController(
      text: (_quantityControllers[product.id]?.text ?? '0'),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: StatefulBuilder(builder: (ctx, setLocal) {
                final nameValid = nameCtrl.text.trim().isNotEmpty;
                final mrp = double.tryParse(mrpCtrl.text.trim()) ?? 0;
                final mrpValid = mrp > 0;
                final canSave = nameValid && mrpValid;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grab handle
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Title + OCR subtitle
                    Text('Edit Product', style: _heading(size: 17, weight: FontWeight.w800)),
                    if (product.rawBrandName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('OCR: ${product.rawBrandName}',
                          style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500)),
                    ],
                    if (product.matchedFullName != null && product.matchedFullName!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('Catalog: ${product.matchedFullName}',
                          style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500)),
                    ],
                    const SizedBox(height: 18),

                    _sheetLabel('Display name'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      autofocus: focus == _EditFocus.name,
                      textCapitalization: TextCapitalization.words,
                      style: _body(size: 15, weight: FontWeight.w700),
                      onChanged: (_) => setLocal(() {}),
                      decoration: _sheetFieldDecoration(
                        hint: 'e.g. 8 PM Special Rare Whisky',
                        error: !nameValid ? 'Name cannot be empty' : null,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _sheetLabel('MRP (₹)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: mrpCtrl,
                      autofocus: focus == _EditFocus.price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                      style: _body(size: 15, weight: FontWeight.w700),
                      onChanged: (_) => setLocal(() {}),
                      decoration: _sheetFieldDecoration(
                        hint: '0',
                        prefix: '₹ ',
                        error: !mrpValid ? 'Price must be greater than 0' : null,
                      ),
                    ),
                    const SizedBox(height: 14),

                    _sheetLabel('Quantity (optional)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: _body(size: 15, weight: FontWeight.w700),
                      decoration: _sheetFieldDecoration(hint: '0'),
                    ),

                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity, height: 52,
                      child: ElevatedButton(
                        onPressed: canSave ? () {
                          final newName = nameCtrl.text.trim();
                          final newMrp = double.tryParse(mrpCtrl.text.trim()) ?? 0;
                          final newQty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                          if (newName != product.name) product.wasCorrected = true;
                          product.name = newName;
                          product.mrp = newMrp;
                          _getOrCreateController(product.id).text = newQty > 0 ? newQty.toString() : '';
                          Navigator.pop(ctx);
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2962FF),
                          disabledBackgroundColor: const Color(0xFFCFD9F3),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Save changes', style: _body(size: 15, weight: FontWeight.w800, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel', style: _body(size: 14, weight: FontWeight.w600, color: const Color(0xFF8A93A6))),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
    // Do NOT dispose controllers here — see prior note; let GC handle.
    if (mounted) setState(() {});
  }

  Widget _sheetLabel(String text) => Text(
        text,
        style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF666F87)),
      );

  InputDecoration _sheetFieldDecoration({required String hint, String? prefix, String? error}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: _body(size: 15, weight: FontWeight.w600, color: const Color(0xFFBCC4D4)),
      prefixText: prefix,
      prefixStyle: _body(size: 15, weight: FontWeight.w800),
      errorText: error,
      errorStyle: _body(size: 11, color: const Color(0xFFE53935), weight: FontWeight.w600),
      filled: true,
      fillColor: const Color(0xFFF5F7FB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error != null ? const Color(0xFFE53935) : Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: error != null ? const Color(0xFFE53935) : const Color(0xFF2962FF), width: 1.5),
      ),
    );
  }

  // ── Alternatives picker bottom sheet ──

  Future<void> _showAlternativesPickerSheet(_ReviewProduct product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Pick the right product', style: _heading(size: 17, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('OCR: ${product.rawBrandName}',
                    style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500)),
                const SizedBox(height: 14),
                // AI's current pick — small dimmed card
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E6EE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF8A93A6)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current pick', style: _body(size: 10, weight: FontWeight.w800, color: const Color(0xFF8A93A6))),
                            const SizedBox(height: 2),
                            Text(product.name, style: _body(size: 13, weight: FontWeight.w700)),
                            if (product.matchedFullName != null && product.matchedFullName != product.name)
                              Text(product.matchedFullName!,
                                  style: _body(size: 11, color: const Color(0xFF8A93A6), weight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text('Alternatives (${product.alternatives.length})',
                    style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF666F87))),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: product.alternatives.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final alt = product.alternatives[i];
                      final pct = (alt.confidence * 100).round();
                      final pctColor = pct >= 90
                          ? const Color(0xFF10B981)
                          : pct >= 70
                              ? const Color(0xFFF57C00)
                              : const Color(0xFFE53935);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _pickAlternative(ctx, product, alt),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E6EE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(alt.effectiveDisplayName,
                                        style: _body(size: 14, weight: FontWeight.w800)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: pctColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text('$pct%', style: _body(size: 10, weight: FontWeight.w800, color: pctColor)),
                                  ),
                                ],
                              ),
                              if (alt.exciseSubtitle != null) ...[
                                const SizedBox(height: 2),
                                RichText(
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF8A93A6)),
                                    children: [
                                      TextSpan(
                                        text: alt.exciseDisplayName != null || alt.exciseBrandName != null ? 'Excise: ' : 'Catalog: ',
                                        style: TextStyle(fontWeight: FontWeight.w800,
                                            color: alt.exciseDisplayName != null || alt.exciseBrandName != null
                                                ? const Color(0xFF1565C0) : const Color(0xFF6B7280)),
                                      ),
                                      TextSpan(text: alt.exciseSubtitle),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  if (alt.size.isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3)),
                                      child: Text(alt.size,
                                          style: _body(size: 9, weight: FontWeight.w800, color: const Color(0xFF6B7280))),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (alt.mrp > 0)
                                    Text('₹${alt.mrp.toStringAsFixed(0)}',
                                        style: _body(size: 12, weight: FontWeight.w800, color: const Color(0xFF0B1536))),
                                  if (alt.currentStock != null && alt.currentStock! > 0) ...[
                                    const SizedBox(width: 10),
                                    const Icon(Icons.inventory_2_rounded, size: 11, color: Color(0xFF10B981)),
                                    const SizedBox(width: 2),
                                    Text('${alt.currentStock}',
                                        style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFF10B981))),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showNotFoundPickerSheet(product);
                    },
                    icon: const Icon(Icons.search, size: 16, color: Color(0xFF8A93A6)),
                    label: Text('None of these match — search catalog',
                        style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF8A93A6))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _pickAlternative(BuildContext ctx, _ReviewProduct product, StockAlternativeMatch alt) {
    HapticFeedbackUtil.medium();
    setState(() {
      // Rebind stepper controller under new id
      final oldCtrl = _quantityControllers.remove(product.id);
      if (oldCtrl != null) _quantityControllers[alt.productId] = oldCtrl;
      product.originalProductId ??= product.id;
      product.id = alt.productId;
      product.name = alt.effectiveDisplayName;
      product.matchedFullName = alt.fullName;
      product.exciseName = alt.exciseSubtitle;
      if (alt.mrp > 0) product.mrp = alt.mrp;
      product.status = 'matched';
      product.wasCorrected = true;
    });
    Navigator.pop(ctx);
    SnackbarHelper.showSuccess(context, 'Switched to "${alt.effectiveDisplayName}"');
  }

  // ── Master brand suggestions bottom sheet (auto_create path) ──

  Future<void> _showMasterBrandSuggestionsSheet(_ReviewProduct product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text('Pick an authoritative brand', style: _heading(size: 17, weight: FontWeight.w800)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFE8EAF6), borderRadius: BorderRadius.circular(6)),
                      child: Text('Excise', style: _body(size: 10, weight: FontWeight.w800, color: const Color(0xFF3F51B5))),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Suggested from the master brand catalog based on the OCR text. Picking one will create the product under that authoritative brand.',
                  style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
                Text('OCR: ${product.rawBrandName}',
                    style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500)),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: product.masterBrandSuggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = product.masterBrandSuggestions[i];
                      final pct = (s.confidence * 100).round();
                      final pctColor = pct >= 90
                          ? const Color(0xFF10B981)
                          : pct >= 70
                              ? const Color(0xFFF57C00)
                              : const Color(0xFF6B7280);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _pickMasterBrand(ctx, product, s),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E6EE)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(s.effectiveDisplayName,
                                        style: _body(size: 14, weight: FontWeight.w800)),
                                  ),
                                  if (pct > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: pctColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Text('$pct%', style: _body(size: 10, weight: FontWeight.w800, color: pctColor)),
                                    ),
                                ],
                              ),
                              if (s.brandName.isNotEmpty && s.brandName != s.effectiveDisplayName) ...[
                                const SizedBox(height: 2),
                                Text(s.brandName,
                                    style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                              if (s.mrp > 0 || (s.size?.isNotEmpty ?? false)) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (s.size != null && s.size!.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3)),
                                        child: Text(s.size!,
                                            style: _body(size: 9, weight: FontWeight.w800, color: const Color(0xFF6B7280))),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (s.mrp > 0)
                                      Text('₹${s.mrp.toStringAsFixed(0)}',
                                          style: _body(size: 12, weight: FontWeight.w800, color: const Color(0xFF0B1536))),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showNotFoundPickerSheet(product);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF8A93A6)),
                          foregroundColor: const Color(0xFF8A93A6),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.search, size: 14),
                        label: Text('Search full catalog', style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF8A93A6))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2962FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add, size: 14),
                        label: Text('Keep "${product.name}"',
                            style: _body(size: 12, weight: FontWeight.w700, color: Colors.white),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _pickMasterBrand(BuildContext ctx, _ReviewProduct product, MasterBrandSuggestion s) {
    HapticFeedbackUtil.medium();
    setState(() {
      // Stays auto_create — backend will create the tenant product under this
      // authoritative brand name on apply.
      product.name = s.effectiveDisplayName;
      product.officialBrandName = s.brandName.isNotEmpty ? s.brandName : s.effectiveDisplayName;
      product.exciseName = s.brandName != s.effectiveDisplayName ? s.brandName : null;
      if (s.mrp > 0) product.mrp = s.mrp;
      product.wasCorrected = true;
    });
    Navigator.pop(ctx);
    SnackbarHelper.showSuccess(context, 'Will create under "${s.effectiveDisplayName}"');
  }

  // ── Not-found / manual-resolve bottom sheet ──

  Future<void> _showNotFoundPickerSheet(_ReviewProduct product) async {
    // Pre-fill with the product name so the catalog search shows likely matches
    // right away. For not_found items we use OCR text as the starting point.
    final seed = product.isNotFound && product.rawBrandName.isNotEmpty
        ? product.rawBrandName
        : product.name;
    final searchCtrl = TextEditingController(text: seed);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.98),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: StatefulBuilder(builder: (ctx, setLocal) {
                final q = searchCtrl.text.trim().toLowerCase();
                final matches = _getFilteredProductsForReview().where((p) {
                  if (q.isEmpty) return true;
                  return p.name.toLowerCase().contains(q) ||
                      (p.brand?.name.toLowerCase().contains(q) ?? false);
                }).take(50).toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('Resolve "${product.name}"', style: _heading(size: 16, weight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (product.rawBrandName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('OCR: ${product.rawBrandName}',
                          style: _body(size: 11.5, color: const Color(0xFF8A93A6), weight: FontWeight.w500)),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      onChanged: (_) => setLocal(() {}),
                      decoration: _sheetFieldDecoration(
                        hint: 'Search catalog…',
                      ).copyWith(prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF8A93A6))),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: matches.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text('No products match "${searchCtrl.text}"',
                                    style: _body(size: 13, color: const Color(0xFF8A93A6))),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: matches.length,
                              separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F2)),
                              itemBuilder: (_, i) {
                                final p = matches[i];
                                return InkWell(
                                  onTap: () => _pickCatalogProduct(ctx, product, p),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(p.name, style: _body(size: 14, weight: FontWeight.w700),
                                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                                              const SizedBox(height: 2),
                                              Text(
                                                [if (p.size.isNotEmpty) p.size, if (p.sellingPrice > 0) '₹${p.sellingPrice.toStringAsFixed(0)}'].join(' · '),
                                                style: _body(size: 11, color: const Color(0xFF8A93A6), weight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBCC4D4)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _convertToAutoCreate(product);
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF2962FF)),
                        foregroundColor: const Color(0xFF2962FF),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text('Create new: "${product.name}"',
                          style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF2962FF)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _pickCatalogProduct(BuildContext ctx, _ReviewProduct product, models.Product p) {
    HapticFeedbackUtil.medium();
    setState(() {
      final oldCtrl = _quantityControllers.remove(product.id);
      if (oldCtrl != null) _quantityControllers[p.id] = oldCtrl;
      product.originalProductId ??= product.id;
      product.id = p.id;
      product.name = p.name;
      product.matchedFullName = null;
      if (p.sellingPrice > 0) product.mrp = p.sellingPrice;
      product.status = 'matched';
      product.wasCorrected = true;
    });
    Navigator.pop(ctx);
    SnackbarHelper.showSuccess(context, 'Matched to "${p.name}"');
  }

  // ── Manual Add Section ──

  Widget _buildManualAddSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 3, height: 16,
                decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text('Add Missing Brands', style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF374151))),
              const Spacer(),
              Text('${_manualEntries.where((e) => e.hasName).length} added',
                style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFF10B981))),
            ],
          ),
        ),
        // Entry rows
        ...List.generate(_manualEntries.length, (i) => _buildManualEntryRow(i)),
      ],
    );
  }

  Widget _buildManualEntryRow(int index) {
    final entry = _manualEntries[index];
    final isLast = index == _manualEntries.length - 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: entry.hasName ? const Color(0xFFF0FDF4) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.hasName ? const Color(0xFFA7F3D0) : const Color(0xFFE5E7EB),
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Brand name input
          Expanded(
            flex: 5,
            child: TextField(
              controller: entry.nameController,
              style: _body(size: 13, weight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: isLast ? 'Brand name...' : 'Brand name',
                hintStyle: _body(size: 13, color: const Color(0xFFBBBBBB)),
                prefixIcon: Icon(
                  entry.hasName ? Icons.check_circle : Icons.add_circle_outline,
                  size: 18,
                  color: entry.hasName ? const Color(0xFF10B981) : const Color(0xFFCCCCCC),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) {
                setState(() {
                  // Auto-add new empty row when user starts typing in last row
                  if (isLast && entry.hasName) {
                    _manualEntries.add(_ManualEntry());
                  }
                });
              },
            ),
          ),

          // Price input
          SizedBox(
            width: 55,
            child: TextField(
              controller: entry.priceController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: _body(size: 12, weight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: '₹',
                hintStyle: _body(size: 12, color: const Color(0xFFCCCCCC)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Quantity stepper
          Container(
            decoration: BoxDecoration(
              color: entry.hasQty ? const Color(0xFFE8F0FE) : const Color(0xFFF4F7FB),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    final current = int.tryParse(entry.qtyController.text) ?? 0;
                    if (current > 0) {
                      setState(() {
                        entry.qtyController.text = (current - 1).toString();
                      });
                      HapticFeedbackUtil.light();
                    }
                  },
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
                    child: const Center(child: Icon(Icons.remove, size: 14, color: Color(0xFF6B7280))),
                  ),
                ),
                SizedBox(
                  width: 32, height: 24,
                  child: TextField(
                    controller: entry.qtyController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: entry.hasQty ? const Color(0xFF2962FF) : const Color(0xFF141F39),
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      isDense: true,
                      hintText: '0',
                      hintStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFCCCCCC)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    final current = int.tryParse(entry.qtyController.text) ?? 0;
                    setState(() {
                      entry.qtyController.text = (current + 1).toString();
                    });
                    HapticFeedbackUtil.light();
                  },
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(child: Icon(Icons.add, size: 14, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),

          // Delete button (not for last empty row)
          if (!isLast && entry.hasName)
            GestureDetector(
              onTap: () {
                setState(() {
                  _manualEntries[index].dispose();
                  _manualEntries.removeAt(index);
                  // Ensure there's always one empty row at the bottom
                  if (_manualEntries.isEmpty || !_manualEntries.last.isEmpty) {
                    _manualEntries.add(_ManualEntry());
                  }
                });
                HapticFeedbackUtil.light();
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 16, color: Colors.red.withValues(alpha: 0.5)),
              ),
            )
          else
            const SizedBox(width: 20),
        ],
      ),
    );
  }

  Widget _buildReviewBottomBar() {
    final count = _productsWithQtyCount;
    final bottles = _totalBottles;
    final canSubmit = count > 0 && !_isSaving;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
      ),
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).padding.bottom + 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$count product${count != 1 ? 's' : ''} · $bottles bottle${bottles != 1 ? 's' : ''}',
                style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF888888)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity, height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: canSubmit
                    ? const LinearGradient(colors: [Color(0xFF3855B3), Color(0xFF2962FF)])
                    : const LinearGradient(colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: canSubmit ? _setOpeningStock : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_rounded, size: 20, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Set Opening Stock', style: _body(size: 16, weight: FontWeight.w700, color: Colors.white)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SizeStats {
  final String size;
  int totalStock;
  double totalValue;
  _SizeStats({required this.size}) : totalStock = 0, totalValue = 0;
}

class _StockColumnOption {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool recommended;
  const _StockColumnOption({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.recommended = false,
  });
}

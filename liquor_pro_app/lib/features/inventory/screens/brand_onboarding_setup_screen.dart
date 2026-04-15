import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../models/saas_brand.dart';
import '../services/brand_onboarding_service.dart';

/// Font helpers — same as SalesEntrySetupScreen
TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Local asset paths — same as sales setup
class _Assets {
  static const whiskyCard = 'assets/images/sales/whisky_card.png';
  static const beerCard = 'assets/images/sales/beer_card.png';
  static const whiskyHero = 'assets/images/sales/whisky_hero.png';
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 1: "Type of liquor" — Select category (Whisky / Beer)
// Same layout as SalesEntrySetupScreen
// ═══════════════════════════════════════════════════════════════
class BrandOnboardingSetupScreen extends StatefulWidget {
  const BrandOnboardingSetupScreen({super.key});

  @override
  State<BrandOnboardingSetupScreen> createState() => _BrandOnboardingSetupScreenState();
}

class _BrandOnboardingSetupScreenState extends State<BrandOnboardingSetupScreen> {
  bool _isLoading = true;
  List<SaasBrand> _allBrands = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final apiService = context.read<DioApiService>();
      final shopProvider = context.read<ShopSelectionProvider>();
      final service = BrandOnboardingService(apiService);
      final response = await service.getAvailableBrands(shopId: shopProvider.selectedShopId);
      if (response.success && response.data != null) {
        _allBrands = response.data!;
      }
    } catch (e) {
      debugPrint('[BrandOnboarding] Load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Extract unique categories from loaded brands
  List<_CategoryInfo> get _categories {
    final catMap = <String, _CategoryInfo>{};
    for (final brand in _allBrands) {
      final catName = brand.categoryNameFromVariant ?? 'Other';
      catMap.putIfAbsent(catName, () => _CategoryInfo(name: catName));
      catMap[catName]!.brandCount++;
      if (brand.hasAllVariantsOnboarded) catMap[catName]!.onboardedCount++;
    }
    // Sort by brand count descending
    final sorted = catMap.values.toList()..sort((a, b) => b.brandCount.compareTo(a.brandCount));
    return sorted;
  }

  IconData _iconForCategory(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('beer')) return Icons.sports_bar_rounded;
    if (cat.contains('wine')) return Icons.wine_bar_rounded;
    if (cat.contains('rum')) return Icons.liquor_rounded;
    if (cat.contains('vodka')) return Icons.local_bar_rounded;
    if (cat.contains('whisky')) return Icons.liquor_rounded;
    if (cat.contains('gin')) return Icons.local_bar_rounded;
    if (cat.contains('brandy')) return Icons.liquor_rounded;
    if (cat.contains('tequila')) return Icons.local_bar_rounded;
    if (cat.contains('country')) return Icons.local_drink_rounded;
    return Icons.liquor_rounded;
  }

  String _imageForCategory(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('beer')) return _Assets.beerCard;
    return _Assets.whiskyCard;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader('Brand Onboarding'),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator.adaptive()))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        ..._categories.map((cat) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildCategoryCard(
                            category: cat.name,
                            title: cat.name,
                            subtitle: '${cat.brandCount} brands${cat.onboardedCount > 0 ? ' \u2022 ${cat.onboardedCount} added' : ''}',
                            imageUrl: _imageForCategory(cat.name),
                            icon: _iconForCategory(cat.name),
                          ),
                        )),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
              child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
            ),
          ),
          Expanded(
            child: Text(title, textAlign: TextAlign.center, style: _heading(size: 17, weight: FontWeight.w600)),
          ),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: const Color(0xFFE8EEF8),
              border: Border.all(color: const Color(0xFFD0D8E8), width: 1),
            ),
            child: Center(
              child: SizedBox(width: 20, height: 20,
                child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String category, required String title, required String subtitle,
    required String imageUrl, required IconData icon,
  }) {
    final categoryBrands = _allBrands.where((b) => (b.categoryNameFromVariant ?? '') == category).toList();
    final totalBrands = categoryBrands.length;
    final onboarded = categoryBrands.where((b) => b.hasAllVariantsOnboarded).length;

    return GestureDetector(
      onTap: () async {
        HapticFeedbackUtil.medium();
        if (category.toLowerCase().contains('beer')) {
          // Beer: skip size selection — go directly to brand selection with all sizes
          final result = await Navigator.push<bool>(context, MaterialPageRoute(
            builder: (_) => _BrandSelectionScreen(
              category: category, size: '', allBrands: _allBrands,
            ),
          ));
          if (result == true) _loadData();
        } else {
          await Navigator.push(context, MaterialPageRoute(
            builder: (_) => _BrandCapacityScreen(
              category: category, allBrands: _allBrands, onRefresh: _loadData,
            ),
          ));
          _loadData();
        }
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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity, height: 120,
                      child: Image.asset(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1A1A2E),
                          child: Center(child: Icon(icon, size: 50, color: Colors.white24)),
                        ),
                      ),
                    ),
                  ),
                  // Brand count badge
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8)),
                      child: Text('$totalBrands brands', style: _body(size: 11, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _body(size: 16, weight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: _body(size: 12, weight: FontWeight.w500, color: const Color(0xFF333333))),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.local_bar, size: 14, color: const Color(0xFF3855B3)),
                      const SizedBox(width: 4),
                      Text('$totalBrands brands', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF555555))),
                      const SizedBox(width: 16),
                      if (onboarded > 0) ...[
                        Icon(Icons.check_circle, size: 14, color: const Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text('$onboarded added', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                      ],
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
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 2: "Type of capacity" — Select size
// Same layout as _SalesCapacityScreen
// ═══════════════════════════════════════════════════════════════
class _BrandCapacityScreen extends StatelessWidget {
  final String category;
  final List<SaasBrand> allBrands;
  final VoidCallback onRefresh;

  const _BrandCapacityScreen({required this.category, required this.allBrands, required this.onRefresh});

  String get _categoryLabel => category;

  List<SaasBrand> get _categoryBrands {
    return allBrands.where((b) {
      return (b.categoryNameFromVariant ?? '') == category;
    }).toList();
  }

  /// Size range definitions
  static const _beerRanges = [
    _SizeRange(label: '330ml & Below', minMl: 0, maxMl: 400, sort: 1),
    _SizeRange(label: '500ml', minMl: 401, maxMl: 550, sort: 2),
    _SizeRange(label: '650ml', minMl: 551, maxMl: 999, sort: 3),
    _SizeRange(label: 'Keg/Bulk', minMl: 1000, maxMl: 999999, sort: 4),
  ];

  static const _nonBeerRanges = [
    _SizeRange(label: '90ml (Nip)', minMl: 0, maxMl: 100, sort: 1),
    _SizeRange(label: '180ml (Quarter)', minMl: 101, maxMl: 250, sort: 2),
    _SizeRange(label: '375ml (Half)', minMl: 251, maxMl: 400, sort: 3),
    _SizeRange(label: '750ml (Full)', minMl: 401, maxMl: 999, sort: 4),
    _SizeRange(label: '1L+ (Large)', minMl: 1000, maxMl: 999999, sort: 5),
  ];

  int _extractMl(String size) {
    final numStr = size.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(numStr) ?? 0;
    // Handle "1L" = 1000ml
    if (size.toUpperCase().contains('L') && !size.toUpperCase().contains('ML') && num < 100) {
      return num * 1000;
    }
    return num;
  }

  List<_SizeRange> get _ranges => category.toLowerCase().contains('beer') ? _beerRanges : _nonBeerRanges;

  Map<String, _SizeInfo> get _sizeStats {
    final ranges = _ranges;
    final stats = <String, _SizeInfo>{};
    for (final range in ranges) {
      stats[range.label] = _SizeInfo(size: range.label);
    }
    for (final brand in _categoryBrands) {
      for (final v in brand.variants) {
        if (v.size.isEmpty) continue;
        final ml = _extractMl(v.size);
        for (final range in ranges) {
          if (ml >= range.minMl && ml <= range.maxMl) {
            stats[range.label]!.totalBrands++;
            if (v.isOnboarded == true) stats[range.label]!.onboarded++;
            break;
          }
        }
      }
    }
    // Remove ranges with 0 brands
    stats.removeWhere((_, v) => v.totalBrands == 0);
    return stats;
  }

  /// Get unique actual sizes within a range label (for display)
  List<String> _actualSizesInRange(String rangeLabel) {
    final sizes = <String>{};
    final ranges = _ranges;
    for (final brand in _categoryBrands) {
      for (final v in brand.variants) {
        if (v.size.isEmpty) continue;
        final ml = _extractMl(v.size);
        for (final range in ranges) {
          if (range.label == rangeLabel && ml >= range.minMl && ml <= range.maxMl) {
            sizes.add(v.size.toUpperCase());
            break;
          }
        }
      }
    }
    final sorted = sizes.toList()..sort((a, b) {
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _sizeStats;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header — same as SalesCapacityScreen
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
                      child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                    ),
                  ),
                  Expanded(child: Text('Type of capacity', textAlign: TextAlign.center, style: _heading(size: 17, weight: FontWeight.w600))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8)),
                    child: Text(_categoryLabel, style: _body(size: 11, weight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
            ),
            // Hero image — same as SalesCapacityScreen
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
                  width: double.infinity, height: 120,
                  child: Image.asset(
                    category.toLowerCase().contains('beer') ? _Assets.beerCard : _Assets.whiskyHero,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF1A1A2E),
                      child: Center(child: Icon(
                        category.toLowerCase().contains('beer') ? Icons.sports_bar : Icons.liquor,
                        size: 50, color: Colors.white24,
                      )),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Size list — same as SalesCapacityScreen
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                itemCount: stats.length,
                separatorBuilder: (_, __) => Divider(height: 0.5, color: Colors.grey.withValues(alpha: 0.15)),
                itemBuilder: (context, index) {
                  final info = stats.values.elementAt(index);
                  final allOnboarded = info.onboarded >= info.totalBrands && info.totalBrands > 0;
                  final actualSizes = _actualSizesInRange(info.size);
                  return GestureDetector(
                    onTap: () async {
                      HapticFeedbackUtil.medium();
                      final result = await Navigator.push<bool>(context, MaterialPageRoute(
                        builder: (_) => _BrandSelectionScreen(
                          category: category, size: info.size, allBrands: allBrands,
                        ),
                      ));
                      if (result == true) onRefresh();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 34, height: 34,
                            decoration: BoxDecoration(
                              color: allOnboarded ? const Color(0xFFE8F5E9) : const Color(0xFFF0F1F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              category.toLowerCase().contains('beer') ? Icons.sports_bar_rounded : Icons.liquor_rounded,
                              size: 18, color: allOnboarded ? const Color(0xFF2E7D32) : const Color(0xFF888888),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(info.size, style: _body(size: 15, weight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                // Show actual sizes covered
                                Text(
                                  actualSizes.join(', '),
                                  style: _body(size: 11, weight: FontWeight.w500, color: const Color(0xFF999999)),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Text('${info.totalBrands} brands', style: _body(size: 12, weight: FontWeight.w500, color: const Color(0xFF888888))),
                                    if (info.onboarded > 0) ...[
                                      const SizedBox(width: 8),
                                      Icon(Icons.check_circle, size: 12, color: const Color(0xFF2E7D32)),
                                      const SizedBox(width: 3),
                                      Text('${info.onboarded} added', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (allOnboarded)
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 18),
                              const SizedBox(width: 4),
                              Text('All Added', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                            ])
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFFD0D5DD)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Select', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SizeInfo {
  final String size;
  int totalBrands = 0;
  int onboarded = 0;
  _SizeInfo({required this.size});
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 3: Brand Selection — checklist for a specific size
// Shows brand image + full name + MRP + inline stepper
// ═══════════════════════════════════════════════════════════════
class _BrandSelectionScreen extends StatefulWidget {
  final String category;
  final String size;
  final List<SaasBrand> allBrands;

  const _BrandSelectionScreen({required this.category, required this.size, required this.allBrands});

  @override
  State<_BrandSelectionScreen> createState() => _BrandSelectionScreenState();
}

class _BrandSelectionScreenState extends State<_BrandSelectionScreen> {
  final _searchController = TextEditingController();
  final _selectedVariantIds = <String>{};
  final _variantStockQuantities = <String, int>{};
  final _qtyControllers = <String, TextEditingController>{};
  final _qtyFocusNodes = <String, FocusNode>{};
  bool _isOnboarding = false;
  // Track stock updates for onboarded items
  final _onboardedStockEdits = <String, int>{}; // variantId -> new qty
  final _onboardedQtyControllers = <String, TextEditingController>{};
  final _onboardedQtyFocusNodes = <String, FocusNode>{};
  bool _showOnboarded = true;
  String _searchQuery = '';

  int _extractMl(String size) {
    final numStr = size.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(numStr) ?? 0;
    if (size.toUpperCase().contains('L') && !size.toUpperCase().contains('ML') && num < 100) {
      return num * 1000;
    }
    return num;
  }

  bool _sizeMatchesRange(String variantSize) {
    // Empty size = show all sizes (used for Beer which skips size selection)
    if (widget.size.isEmpty) return true;
    final ml = _extractMl(variantSize);
    final isBeer = widget.category.toLowerCase().contains('beer');
    final ranges = isBeer ? _BrandCapacityScreen._beerRanges : _BrandCapacityScreen._nonBeerRanges;
    for (final range in ranges) {
      if (range.label == widget.size && ml >= range.minMl && ml <= range.maxMl) {
        return true;
      }
    }
    return false;
  }

  List<_BrandVariantInfo> get _allVariants {
    final list = <_BrandVariantInfo>[];
    for (final brand in widget.allBrands) {
      final isMatch = (brand.categoryNameFromVariant ?? '') == widget.category;
      if (!isMatch) continue;
      for (final v in brand.variants) {
        if (!_sizeMatchesRange(v.size)) continue;
        if (_searchQuery.isNotEmpty && !brand.name.toLowerCase().contains(_searchQuery.toLowerCase()) && !(brand.description.isNotEmpty && brand.description.toLowerCase().contains(_searchQuery.toLowerCase()))) continue;
        list.add(_BrandVariantInfo(brand: brand, variant: v));
      }
    }
    list.sort((a, b) => a.variant.mrp.compareTo(b.variant.mrp));
    return list;
  }

  List<_BrandVariantInfo> get _availableVariants => _allVariants.where((bv) => bv.variant.isOnboarded != true).toList();
  List<_BrandVariantInfo> get _onboardedVariants => _allVariants.where((bv) => bv.variant.isOnboarded == true).toList();
  int get _newSelections => _selectedVariantIds.length;

  TextEditingController _getQtyController(String variantId) {
    return _qtyControllers.putIfAbsent(variantId, () {
      final qty = _variantStockQuantities[variantId] ?? 0;
      return TextEditingController(text: qty > 0 ? '$qty' : '0');
    });
  }

  FocusNode _getQtyFocusNode(String variantId) {
    return _qtyFocusNodes.putIfAbsent(variantId, () => FocusNode());
  }

  void _deselectVariant(String variantId) {
    _selectedVariantIds.remove(variantId);
    _variantStockQuantities.remove(variantId);
    _qtyControllers.remove(variantId)?.dispose();
    _qtyFocusNodes.remove(variantId)?.dispose();
  }

  void _selectAll() {
    final available = _availableVariants;
    if (_selectedVariantIds.length == available.length) {
      setState(() { for (final bv in available) { _deselectVariant(bv.variant.id); } });
    } else {
      setState(() {
        for (final bv in available) {
          if (!_selectedVariantIds.contains(bv.variant.id)) {
            _selectedVariantIds.add(bv.variant.id);
            _variantStockQuantities[bv.variant.id] = 0;
          }
        }
      });
    }
    HapticFeedbackUtil.selection();
  }

  TextEditingController _getOnboardedQtyController(String variantId, int currentStock) {
    return _onboardedQtyControllers.putIfAbsent(variantId, () {
      return TextEditingController(text: '$currentStock');
    });
  }

  FocusNode _getOnboardedQtyFocusNode(String variantId) {
    return _onboardedQtyFocusNodes.putIfAbsent(variantId, () => FocusNode());
  }

  int get _pendingStockUpdates => _onboardedStockEdits.length;

  Future<void> _submitStockUpdates() async {
    debugPrint('[StockUpdate] Submit called with ${_onboardedStockEdits.length} edits: $_onboardedStockEdits');
    if (_onboardedStockEdits.isEmpty) return;
    setState(() => _isOnboarding = true);

    final apiService = context.read<DioApiService>();
    final shopProvider = context.read<ShopSelectionProvider>();
    final shopId = shopProvider.selectedShopId;
    if (shopId == null) {
      setState(() => _isOnboarding = false);
      return;
    }

    int submitted = 0;
    int failed = 0;
    final entries = Map<String, int>.from(_onboardedStockEdits);

    for (final entry in entries.entries) {
      final variantId = entry.key;
      final newQty = entry.value;
      final bv = _onboardedVariants.where((v) => v.variant.id == variantId).firstOrNull;
      if (bv == null) continue;

      try {
        // Use stock adjustment API — sets stock directly
        final response = await apiService.post('/api/inventory/stock-update-requests', body: {
          'shop_id': shopId,
          'product_id': variantId,
          'requested_qty': newQty,
          'adjustment_type': 'set',
          'reason': 'Stock update from brand onboarding',
          'notes': '${bv.brand.name} - ${bv.variant.size}: set to $newQty',
          'brand_name': bv.brand.name,
          'size': bv.variant.size,
        });
        if (response.success) {
          submitted++;
          _onboardedStockEdits.remove(variantId);
        } else {
          debugPrint('[StockUpdate] FAILED for ${bv.brand.name}: ${response.message} ${response.error}');
          failed++;
        }
      } catch (e) {
        debugPrint('[StockUpdate] Error for ${bv.brand.name}: $e');
        failed++;
      }
    }

    if (!mounted) return;
    if (submitted > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('$submitted request${submitted > 1 ? 's' : ''} sent for approval${failed > 0 ? ', $failed failed' : ''}'),
        ]),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
    } else if (failed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$failed update${failed > 1 ? 's' : ''} failed — check product IDs'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
    setState(() => _isOnboarding = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _qtyControllers.values) { c.dispose(); }
    for (final f in _qtyFocusNodes.values) { f.dispose(); }
    for (final c in _onboardedQtyControllers.values) { c.dispose(); }
    for (final f in _onboardedQtyFocusNodes.values) { f.dispose(); }
    super.dispose();
  }

  Future<void> _onboard() async {
    if (_selectedVariantIds.isEmpty) return;
    setState(() => _isOnboarding = true);
    try {
      final apiService = context.read<DioApiService>();
      final shopProvider = context.read<ShopSelectionProvider>();
      final service = BrandOnboardingService(apiService);
      final brandIds = <String>{};
      for (final bv in _allVariants) {
        if (_selectedVariantIds.contains(bv.variant.id)) brandIds.add(bv.brand.id);
      }
      final response = await service.onboardBrands(
        brandIds: brandIds.toList(), variantIds: _selectedVariantIds.toList(),
        shopId: shopProvider.selectedShopId,
        variantStockQuantities: _variantStockQuantities.isNotEmpty ? _variantStockQuantities : null,
      );
      if (!mounted) return;
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${response.data?.productsCreated ?? _newSelections} brands added to shop'),
          backgroundColor: AppColors.success,
        ));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(response.message ?? 'Failed to onboard'), backgroundColor: AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    }
    if (mounted) setState(() => _isOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    final available = _availableVariants;
    final onboarded = _onboardedVariants;
    final categoryLabel = widget.category;
    final allSelected = available.isNotEmpty && _selectedVariantIds.length == available.length;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
                      child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
                    ),
                  ),
                  Expanded(child: Text('Select Brands', textAlign: TextAlign.center, style: _heading(size: 17, weight: FontWeight.w600))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF3855B3).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text('${widget.size} $categoryLabel', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
                  ),
                ],
              ),
            ),
            // Search + Select All
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search brands...',
                        hintStyle: _body(size: 13, weight: FontWeight.w500, color: const Color(0xFFAAAAAA)),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF888888)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(onTap: () => setState(() { _searchController.clear(); _searchQuery = ''; }),
                                child: const Icon(Icons.close, size: 18, color: Color(0xFF888888)))
                            : null,
                        filled: true, fillColor: const Color(0xFFF5F6FA),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  if (available.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _selectAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: allSelected ? const Color(0xFF3855B3) : const Color(0xFFF5F6FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(allSelected ? 'Deselect' : 'All', style: _body(size: 12, weight: FontWeight.w700, color: allSelected ? Colors.white : const Color(0xFF3855B3))),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Counts
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Text('${available.length} available', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
                  if (onboarded.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('\u2022', style: _body(size: 12, color: const Color(0xFFCCCCCC))),
                    const SizedBox(width: 8),
                    Text('${onboarded.length} added', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                  ],
                  if (_newSelections > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF3855B3), borderRadius: BorderRadius.circular(10)),
                      child: Text('$_newSelections selected', style: _body(size: 11, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Brand list — same card style as daily sales entry
            Expanded(
              child: (available.isEmpty && onboarded.isEmpty)
                  ? Center(child: Text('No brands found', style: _body(size: 14, color: const Color(0xFF888888))))
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        if (available.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                            child: Row(children: [
                              const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF3855B3)),
                              const SizedBox(width: 6),
                              Text('Available Brands', style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF3855B3).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text('${available.length}', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF3855B3))),
                              ),
                            ]),
                          ),
                          ...available.map((bv) => _buildBrandCard(bv, isOnboarded: false)),
                        ],
                        if (onboarded.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => setState(() => _showOnboarded = !_showOnboarded),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                              decoration: BoxDecoration(color: const Color(0xFFF5F9F5), borderRadius: BorderRadius.circular(10)),
                              child: Row(children: [
                                const Icon(Icons.check_circle, size: 16, color: Color(0xFF2E7D32)),
                                const SizedBox(width: 6),
                                Text('Already in Your Shop', style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF2E7D32))),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                  child: Text('${onboarded.length}', style: _body(size: 11, weight: FontWeight.w700, color: const Color(0xFF2E7D32))),
                                ),
                                const Spacer(),
                                Icon(_showOnboarded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 20, color: const Color(0xFF2E7D32)),
                              ]),
                            ),
                          ),
                          if (_showOnboarded) ...onboarded.map((bv) => _buildBrandCard(bv, isOnboarded: true)),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
            ),
            // Bottom bar
            if (_newSelections > 0 || _pendingStockUpdates > 0)
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
                ),
                child: Row(
                  children: [
                    if (_pendingStockUpdates > 0)
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isOnboarding ? null : _submitStockUpdates,
                            icon: _isOnboarding
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.update, size: 18),
                            label: Text(
                              'Update $_pendingStockUpdates Stock',
                              style: _body(size: 13, weight: FontWeight.w700, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                            ),
                          ),
                        ),
                      ),
                    if (_pendingStockUpdates > 0 && _newSelections > 0) const SizedBox(width: 8),
                    if (_newSelections > 0)
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _isOnboarding ? null : _onboard,
                            icon: _isOnboarding
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.add_circle_outline, size: 18),
                            label: Text(
                              'Add $_newSelections Brand${_newSelections > 1 ? 's' : ''}',
                              style: _body(size: 13, weight: FontWeight.w700, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3855B3), foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Brand card — same layout as daily sales entry product card
  /// Shows product image, full name (no truncation), MRP, category pill, stepper
  Widget _buildBrandCard(_BrandVariantInfo bv, {required bool isOnboarded}) {
    final isSelected = _selectedVariantIds.contains(bv.variant.id);
    final stockQty = _variantStockQuantities[bv.variant.id];
    final categoryLabel = widget.category.toUpperCase();
    final sizeLabel = widget.size;
    // Use variant picture if available, otherwise null
    final imageUrl = bv.variant.picture.isNotEmpty ? bv.variant.picture : null;

    return GestureDetector(
      onTap: isOnboarded ? null : () {
        HapticFeedbackUtil.selection();
        if (isSelected) {
          setState(() => _deselectVariant(bv.variant.id));
        } else {
          setState(() {
            _selectedVariantIds.add(bv.variant.id);
            _variantStockQuantities[bv.variant.id] = 0;
          });
          Future.delayed(const Duration(milliseconds: 100), () {
            _getQtyFocusNode(bv.variant.id).requestFocus();
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isOnboarded ? const Color(0xFFF8FFF8) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF3855B3).withValues(alpha: 0.4) : isOnboarded ? const Color(0xFF2E7D32).withValues(alpha: 0.2) : const Color(0xFFF0F0F2),
            width: isSelected ? 1.5 : 0.5,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT: Product image (80x80) with MRP badge
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
                  // Product image or placeholder
                  if (imageUrl != null)
                    Positioned.fill(
                      child: Image.network(imageUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(widget.category.toLowerCase().contains('beer') ? Icons.sports_bar : Icons.liquor, size: 30, color: Colors.white.withValues(alpha: 0.3)),
                        ),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: Center(
                        child: Icon(widget.category.toLowerCase().contains('beer') ? Icons.sports_bar : Icons.liquor, size: 30, color: Colors.white.withValues(alpha: 0.3)),
                      ),
                    ),
                  // MRP badge
                  if (bv.variant.mrp > 0)
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
                            Text('\u20B9 ${bv.variant.mrp.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ),
                  // Checkbox overlay
                  if (!isOnboarded)
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF3855B3) : Colors.white.withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(10)),
                        ),
                        child: Icon(isSelected ? Icons.check : Icons.add, size: 16,
                          color: isSelected ? Colors.white : const Color(0xFF6B7280)),
                      ),
                    ),
                  if (isOnboarded)
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 26, height: 26,
                        decoration: const BoxDecoration(color: Color(0xFF2E7D32), borderRadius: BorderRadius.only(topLeft: Radius.circular(10))),
                        child: const Icon(Icons.check, size: 16, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // RIGHT: Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand display name (or official name if no display name)
                  Text(
                    bv.brand.description.isNotEmpty ? bv.brand.description : bv.brand.name,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF141F39), height: 1.25),
                  ),
                  const SizedBox(height: 3),
                  // Category pill + status
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(3)),
                        child: Text('${categoryLabel.toUpperCase()} - ${bv.variant.size}',
                          style: const TextStyle(fontSize: 8.5, color: Color(0xFF6B7280), fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                      ),
                      const SizedBox(width: 6),
                      if (isOnboarded) ...[
                        const Icon(Icons.check_circle, size: 12, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 3),
                        const Text('In Shop', style: TextStyle(fontSize: 10.5, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                      ] else if (isSelected) ...[
                        const Icon(Icons.check_circle, size: 12, color: Color(0xFF3855B3)),
                        const SizedBox(width: 3),
                        const Text('Selected', style: TextStyle(fontSize: 10.5, color: Color(0xFF3855B3), fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Price + stepper
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('\u20B9 ${bv.variant.mrp > 0 ? bv.variant.mrp.toStringAsFixed(0) : "--"}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0B1536))),
                            if (isSelected)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text('Opening: ${stockQty ?? 0}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF3855B3), fontWeight: FontWeight.w600)),
                              ),
                            if (isOnboarded)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text('Stock: ${bv.variant.currentStock}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                      if (isOnboarded)
                        _buildOnboardedStepper(bv)
                      else
                        _buildStepper(bv),
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

  Widget _buildStepper(_BrandVariantInfo bv) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF4F7FB), borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              final controller = _getQtyController(bv.variant.id);
              final current = int.tryParse(controller.text) ?? 0;
              if (current > 0) {
                controller.text = '${current - 1}';
                controller.selection = TextSelection.collapsed(offset: controller.text.length);
                _variantStockQuantities[bv.variant.id] = current - 1;
                setState(() {}); HapticFeedbackUtil.light();
              } else if (_selectedVariantIds.contains(bv.variant.id)) {
                HapticFeedbackUtil.light();
                setState(() => _deselectVariant(bv.variant.id));
              }
            },
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              child: const Center(child: Icon(Icons.remove, size: 14, color: Color(0xFF6B7280))),
            ),
          ),
          SizedBox(
            width: 44, height: 26,
            child: TextField(
              controller: _getQtyController(bv.variant.id),
              focusNode: _getQtyFocusNode(bv.variant.id),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF141F39)),
              decoration: const InputDecoration(
                border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 4),
                isDense: true, hintText: '0',
                hintStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFFCCCCCC)),
              ),
              onTap: () {
                if (!_selectedVariantIds.contains(bv.variant.id)) {
                  setState(() { _selectedVariantIds.add(bv.variant.id); _variantStockQuantities[bv.variant.id] = 0; });
                }
              },
              onChanged: (text) {
                final qty = int.tryParse(text) ?? 0;
                _variantStockQuantities[bv.variant.id] = qty;
                if (qty > 0 && !_selectedVariantIds.contains(bv.variant.id)) {
                  setState(() => _selectedVariantIds.add(bv.variant.id));
                } else { setState(() {}); }
              },
            ),
          ),
          GestureDetector(
            onTap: () {
              final controller = _getQtyController(bv.variant.id);
              final current = int.tryParse(controller.text) ?? 0;
              controller.text = '${current + 1}';
              controller.selection = TextSelection.collapsed(offset: controller.text.length);
              _variantStockQuantities[bv.variant.id] = current + 1;
              if (!_selectedVariantIds.contains(bv.variant.id)) { setState(() => _selectedVariantIds.add(bv.variant.id)); }
              else { setState(() {}); }
              HapticFeedbackUtil.light();
              _getQtyFocusNode(bv.variant.id).requestFocus();
            },
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8), borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: const Color(0xFF1A73E8).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Center(child: Icon(Icons.add, size: 14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildOnboardedStepper(_BrandVariantInfo bv) {
    final currentStock = bv.variant.currentStock;
    final controller = _getOnboardedQtyController(bv.variant.id, currentStock);
    final hasEdit = _onboardedStockEdits.containsKey(bv.variant.id);

    return Container(
      decoration: BoxDecoration(
        color: hasEdit ? const Color(0xFFE8F5E9) : const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(12),
        border: hasEdit ? Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)) : null,
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              final current = int.tryParse(controller.text) ?? 0;
              if (current > 0) {
                controller.text = '${current - 1}';
                controller.selection = TextSelection.collapsed(offset: controller.text.length);
                _onboardedStockEdits[bv.variant.id] = current - 1;
                setState(() {});
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
            width: 44, height: 26,
            child: TextField(
              controller: controller,
              focusNode: _getOnboardedQtyFocusNode(bv.variant.id),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: hasEdit ? const Color(0xFF2E7D32) : const Color(0xFF141F39)),
              decoration: const InputDecoration(
                border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 4),
                isDense: true,
              ),
              onChanged: (text) {
                final qty = int.tryParse(text) ?? 0;
                if (qty != currentStock) {
                  _onboardedStockEdits[bv.variant.id] = qty;
                } else {
                  _onboardedStockEdits.remove(bv.variant.id);
                }
                setState(() {});
              },
            ),
          ),
          GestureDetector(
            onTap: () {
              final current = int.tryParse(controller.text) ?? 0;
              controller.text = '${current + 1}';
              controller.selection = TextSelection.collapsed(offset: controller.text.length);
              _onboardedStockEdits[bv.variant.id] = current + 1;
              setState(() {});
              HapticFeedbackUtil.light();
              _getOnboardedQtyFocusNode(bv.variant.id).requestFocus();
            },
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: const Center(child: Icon(Icons.add, size: 14, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandVariantInfo {
  final SaasBrand brand;
  final SaasBrandVariant variant;
  _BrandVariantInfo({required this.brand, required this.variant});
}

class _CategoryInfo {
  final String name;
  int brandCount = 0;
  int onboardedCount = 0;
  _CategoryInfo({required this.name});
}

class _SizeRange {
  final String label;
  final int minMl;
  final int maxMl;
  final int sort;
  const _SizeRange({required this.label, required this.minMl, required this.maxMl, required this.sort});
}

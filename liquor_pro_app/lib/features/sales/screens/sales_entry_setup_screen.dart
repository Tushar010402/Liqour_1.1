import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../inventory/models/product.dart' as models;
import '../../inventory/providers/product_provider.dart';
import '../providers/daily_sales_provider.dart';
import 'ai_sales_entry_screen.dart';
import 'daily_sales_entry_screen.dart';

/// Local asset paths for sales setup images
class _SalesAssets {
  static const whiskyCard = 'assets/images/sales/whisky_card.png';
  static const beerCard = 'assets/images/sales/beer_card.png';
  static const whiskyHero = 'assets/images/sales/whisky_hero.png';
}

/// Font helpers — Nunito for body, Montserrat Alternates for headings
TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Entry mode: AI auto-fill or Manual entry
enum SalesEntryMode { ai, manual }

// ═══════════════════════════════════════════════════════════════
// SCREEN 1: "Type of liquor" — Select category (Whisky / Beer)
// ═══════════════════════════════════════════════════════════════
class SalesEntrySetupScreen extends StatefulWidget {
  /// Optional initial date — when passed from dashboard, this date is pre-selected
  final DateTime? initialDate;
  final String? initialDateLabel;

  const SalesEntrySetupScreen({super.key, this.initialDate, this.initialDateLabel});

  @override
  State<SalesEntrySetupScreen> createState() => _SalesEntrySetupScreenState();
}

class _SalesEntrySetupScreenState extends State<SalesEntrySetupScreen> {
  SalesEntryMode _mode = SalesEntryMode.manual;
  late String _selectedDateLabel;
  late DateTime _selectedDate;
  bool _isLoadingProducts = true;

  /// When user selects Last 7 Days / Last Month, show date strip
  String? _activeRangeLabel; // 'Last 7 Days' or 'Last Month'
  /// Specific date picked from the date strip (null = show all in range)
  DateTime? _stripSelectedDate;

  List<models.Product> _allProducts = [];
  Map<String, models.Stock> _stockMap = {};

  // Submitted sizes from backend records (e.g. {"750ML", "375ML"})
  Set<String> _submittedSizes = {};
  // Submitted category groups (e.g. {"English", "Beer"})
  Set<String> _submittedCategories = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now().subtract(const Duration(days: 1));
    _selectedDateLabel = widget.initialDateLabel ?? 'Yesterday';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final shopProvider = context.read<ShopSelectionProvider>();
    final productProvider = context.read<ProductProvider>();
    final shopId = shopProvider.selectedShopId;

    if (shopId == null) {
      setState(() => _isLoadingProducts = false);
      return;
    }

    try {
      productProvider.clearAllFilters();
      await productProvider.loadProducts(shopId: null, limit: 500, categoryId: null, size: null);
      await productProvider.loadStock(shopId: shopId);
      if (!mounted) return;

      _allProducts = List<models.Product>.from(productProvider.products);
      _stockMap = Map<String, models.Stock>.from(productProvider.stockByProductId);

      // Fetch submitted records for this date from backend
      await _loadSubmittedRecords(shopId);

      if (mounted) setState(() => _isLoadingProducts = false);
    } catch (e) {
      debugPrint('[SetupScreen] Error: $e');
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  /// Fetch records from backend for the selected date + shop to determine
  /// which category+size combos are already submitted/pending.
  Future<void> _loadSubmittedRecords(String shopId) async {
    try {
      final salesProvider = context.read<DailySalesProvider>();
      await salesProvider.fetchRecords(
        shopId: shopId,
        startDate: _selectedDate,
        endDate: _selectedDate,
      );

      final records = salesProvider.records;
      final sizes = <String>{};
      final categoryGroups = <String>{};

      for (final record in records) {
        if (record.status.toLowerCase() == 'rejected') continue;

        for (final item in record.items) {
          final size = item.size ?? '';
          if (size.isNotEmpty) {
            sizes.add(ProductConstants.normalizeSize(size));
          }

          final catName = (item.categoryName ?? '').toLowerCase();
          if (catName.contains('beer')) {
            categoryGroups.add('Beer');
          } else if (catName.isNotEmpty) {
            categoryGroups.add('English');
          }
        }
      }

      _submittedSizes = sizes;
      _submittedCategories = categoryGroups;
      debugPrint('[SetupScreen] Submitted for ${DateFormat('dd MMM').format(_selectedDate)}: sizes=$sizes, categories=$categoryGroups');
    } catch (e) {
      debugPrint('[SetupScreen] Error loading records: $e');
    }
  }

  List<models.Product> _getProductsForCategory(String category) {
    return _allProducts.where((p) {
      final catName = (p.category?.name ?? '').toLowerCase();
      if (category == 'Beer') return catName.contains('beer');
      return !catName.contains('beer');
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

  void _onDatePillTapped(String label) async {
    HapticFeedbackUtil.selection();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (label == 'Today') {
      setState(() {
        _selectedDateLabel = label;
        _selectedDate = today;
        _activeRangeLabel = null;
        _stripSelectedDate = null;
      });
    } else if (label == 'Yesterday') {
      setState(() {
        _selectedDateLabel = label;
        _selectedDate = today.subtract(const Duration(days: 1));
        _activeRangeLabel = null;
        _stripSelectedDate = null;
      });
    } else if (label == 'Last 7 Days' || label == 'Last Month') {
      // Show date strip — default to yesterday
      setState(() {
        _selectedDateLabel = label;
        _selectedDate = today.subtract(const Duration(days: 1));
        _activeRangeLabel = label;
        _stripSelectedDate = null;
      });
    } else if (label == 'Custom') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: today.subtract(const Duration(days: 90)),
        lastDate: today,
        helpText: 'Select custom date',
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: const Color(0xFF2962FF)),
          ),
          child: child!,
        ),
      );
      if (picked == null) return;
      setState(() {
        _selectedDateLabel = label;
        _selectedDate = picked;
        _activeRangeLabel = null;
        _stripSelectedDate = null;
      });
    }

    // Reload submitted records for the new date
    if (!mounted) return;
    final shopId = context.read<ShopSelectionProvider>().selectedShopId;
    if (shopId != null) await _loadSubmittedRecords(shopId);
    if (mounted) setState(() {});
  }

  void _onStripDateTapped(DateTime date) async {
    HapticFeedbackUtil.selection();
    setState(() {
      _stripSelectedDate = date;
      _selectedDate = date;
    });
    // Reload submitted records
    if (!mounted) return;
    final shopId = context.read<ShopSelectionProvider>().selectedShopId;
    if (shopId != null) await _loadSubmittedRecords(shopId);
    if (mounted) setState(() {});
  }

  /// Check if a size within a category is already submitted
  bool _isSizeSubmitted(String category, String size) {
    // Check if this exact size exists in submitted records
    final normalizedSize = ProductConstants.normalizeSize(size);
    return _submittedSizes.contains(normalizedSize);
  }

  void _onCategoryTapped(String category) async {
    // Check if entire category already submitted
    if (_submittedCategories.contains(category)) {
      // Check if ALL sizes are submitted
      final products = _getProductsForCategory(category);
      final sizes = _extractSizesFromProducts(products);
      final allSubmitted = sizes.isNotEmpty && sizes.every((s) => _submittedSizes.contains(s));
      if (allSubmitted) {
        SnackbarHelper.showInfo(context, '$category sales already submitted for ${DateFormat('dd MMM').format(_selectedDate)}');
        return;
      }
    }

    HapticFeedbackUtil.medium();

    final products = _getProductsForCategory(category);
    final sizes = _extractSizesFromProducts(products);

    if (sizes.isEmpty) {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => _mode == SalesEntryMode.ai
              ? AISalesEntryScreen(
                  category: category,
                  selectedDate: _selectedDate,
                )
              : DailySalesEntryScreen(
                  showHeader: true,
                  initialCategoryName: category,
                  selectedDate: _selectedDate,
                ),
        ),
      );
      if (result == 'submitted' && mounted) {
        final shopId = context.read<ShopSelectionProvider>().selectedShopId;
        if (shopId != null) await _loadSubmittedRecords(shopId);
        setState(() {});
      }
    } else {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => _SalesCapacityScreen(
            category: category,
            mode: _mode,
            selectedDate: _selectedDate,
            selectedDateLabel: _selectedDateLabel,
            activeRangeLabel: _activeRangeLabel,
            stripSelectedDate: _stripSelectedDate,
            allProducts: _allProducts,
            stockMap: _stockMap,
            submittedSizes: _submittedSizes,
          ),
        ),
      );
      if (result == 'submitted' && mounted) {
        // Refresh from backend
        final shopId = context.read<ShopSelectionProvider>().selectedShopId;
        if (shopId != null) await _loadSubmittedRecords(shopId);
        setState(() {});
      }
    }
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
    if (product.subcategory?.name != null) {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML)', caseSensitive: false).firstMatch(product.subcategory!.name);
      if (match != null) return ProductConstants.normalizeSize(match.group(0)!);
    }
    return '';
  }

  List<String> _extractSizesFromProducts(List<models.Product> products) {
    final sizes = <String>{};
    for (var p in products) {
      final size = _extractProductSize(p);
      if (size.isNotEmpty) sizes.add(size);
    }
    final sorted = sizes.toList()..sort((a, b) {
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });
    return sorted;
  }

  String _formatValue(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader('Type of liquor'),
            _buildModeToggle(),
            const SizedBox(height: 14),
            _buildDatePills(),
            // Date strip for Last 7 Days / Last Month
            if (_activeRangeLabel != null) ...[
              const SizedBox(height: 8),
              _buildDateStrip(),
            ],
            // Show selected date below
            const SizedBox(height: 8),
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
                    const Icon(Icons.calendar_today, size: 16, color: Color(0xFF2962FF)),
                    const SizedBox(width: 8),
                    Text(
                      'Sales date: ${DateFormat('dd MMM yyyy, EEEE').format(_selectedDate)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoadingProducts
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _buildCategoryCard(
                            category: 'English',
                            title: 'Whisky',
                            subtitle: 'Whisky category performance overview. Tracking volume and total value',
                            imageUrl: _SalesAssets.whiskyCard,
                            icon: Icons.liquor,
                          ),
                          const SizedBox(height: 16),
                          _buildCategoryCard(
                            category: 'Beer',
                            title: 'Beer',
                            subtitle: 'Beer category performance overview. Tracking volume and total value',
                            imageUrl: _SalesAssets.beerCard,
                            icon: Icons.sports_bar,
                          ),
                          const SizedBox(height: 20),
                        ],
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
            child: Text(title, textAlign: TextAlign.center,
              style: _heading(size: 17, weight: FontWeight.w600)),
          ),
          // Bell notification icon — light bg
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

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 42,
        decoration: BoxDecoration(color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            _buildModeTab('Manual Entry', SalesEntryMode.manual),
            _buildModeTab('Entry With AI', SalesEntryMode.ai),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab(String label, SalesEntryMode mode) {
    final isSelected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedbackUtil.selection(); setState(() => _mode = mode); },
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3855B3) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: _body(
            size: 14, weight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF888888),
          )),
        ),
      ),
    );
  }

  Widget _buildDateStrip() {
    final isLast7 = _activeRangeLabel == 'Last 7 Days';
    final dayCount = isLast7 ? 7 : 30;
    final today = DateTime.now();
    final dates = List.generate(dayCount, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: i)));

    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = _stripSelectedDate != null &&
              _stripSelectedDate!.year == date.year &&
              _stripSelectedDate!.month == date.month &&
              _stripSelectedDate!.day == date.day;
          final isToday = date.year == today.year && date.month == today.month && date.day == today.day;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onStripDateTapped(date),
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF3855B3)
                      : isToday
                          ? const Color(0xFFE8F0FE)
                          : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3855B3)
                        : isToday
                            ? const Color(0xFF3855B3).withValues(alpha: 0.3)
                            : const Color(0xFFD0D5DD),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('EEE').format(date),
                      style: _body(size: 9, weight: FontWeight.w600,
                        color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                    const SizedBox(height: 1),
                    Text('${date.day}',
                      style: _body(size: 16, weight: FontWeight.w900,
                        color: isSelected ? Colors.white : const Color(0xFF1A1D26))),
                    Text(DateFormat('MMM').format(date),
                      style: _body(size: 8, weight: FontWeight.w600,
                        color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDatePills() {
    final labels = ['Today', 'Yesterday', 'Last 7 Days', 'Last Month', 'Custom'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        itemBuilder: (context, index) {
          final label = labels[index];
          final isSelected = _selectedDateLabel == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onDatePillTapped(label),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3855B3) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? const Color(0xFF3855B3) : const Color(0xFFD0D5DD)),
                ),
                child: Text(label, style: _body(
                  size: 12, weight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF888888),
                )),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryCard({
    required String category,
    required String title,
    required String subtitle,
    required String imageUrl,
    required IconData icon,
  }) {
    final totalStock = _getTotalStock(category);
    final totalValue = _getTotalValue(category);
    // Check if ALL sizes in this category are submitted
    final catProducts = _getProductsForCategory(category);
    final catSizes = _extractSizesFromProducts(catProducts);
    final isSubmitted = catSizes.isNotEmpty && catSizes.every((s) => _submittedSizes.contains(s));
    final isPartiallySubmitted = _submittedCategories.contains(category) && !isSubmitted;

    return GestureDetector(
      onTap: () => _onCategoryTapped(category),
      child: Opacity(
        opacity: isSubmitted ? 0.45 : 1.0,
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
              // ── Image area with inner padding + rounded corners ──
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
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF1A1A2E),
                            child: Center(child: Icon(icon, size: 50, color: Colors.white24)),
                          ),
                        ),
                      ),
                    ),
                    // Date badge
                    Positioned(
                      top: 8, right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF2E7D32), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        DateFormat('dd MMM').format(_selectedDate),
                        style: _body(size: 11, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                  // Submitted badge
                  if (isSubmitted)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.white, size: 20),
                              const SizedBox(width: 6),
                              Text('Submitted', style: _body(size: 14, weight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (isPartiallySubmitted)
                    Positioned(
                      top: 10, left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFF8F00), borderRadius: BorderRadius.circular(6)),
                        child: Text('Partial', style: _body(size: 10, weight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Text area (bottom) on white background ──
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
                        SvgPicture.asset('assets/icons/cart_stock.svg', width: 16, height: 16, colorFilter: const ColorFilter.mode(Color(0xFF555555), BlendMode.srcIn)),
                        const SizedBox(width: 4),
                        Text('$totalStock', style: _body(size: 14, weight: FontWeight.w700)),
                        const SizedBox(width: 16),
                        SvgPicture.asset('assets/icons/wallet_income.svg', width: 16, height: 16, colorFilter: const ColorFilter.mode(Color(0xFF555555), BlendMode.srcIn)),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SCREEN 2: "Type of capacity" — Select size
// ═══════════════════════════════════════════════════════════════
class _SalesCapacityScreen extends StatefulWidget {
  final String category;
  final SalesEntryMode mode;
  final DateTime selectedDate;
  final String selectedDateLabel;
  final String? activeRangeLabel;
  final DateTime? stripSelectedDate;
  final List<models.Product> allProducts;
  final Map<String, models.Stock> stockMap;
  final Set<String> submittedSizes;

  const _SalesCapacityScreen({
    required this.category,
    required this.mode,
    required this.selectedDate,
    required this.selectedDateLabel,
    this.activeRangeLabel,
    this.stripSelectedDate,
    required this.allProducts,
    required this.stockMap,
    required this.submittedSizes,
  });

  @override
  State<_SalesCapacityScreen> createState() => _SalesCapacityScreenState();
}

class _SalesCapacityScreenState extends State<_SalesCapacityScreen> {
  late SalesEntryMode _currentMode;
  late String _selectedDateLabel;
  late DateTime _selectedDate;
  String? _activeRangeLabel;
  DateTime? _stripSelectedDate;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
    _selectedDate = widget.selectedDate;
    _selectedDateLabel = widget.selectedDateLabel;
    _activeRangeLabel = widget.activeRangeLabel;
    _stripSelectedDate = widget.stripSelectedDate;
  }

  String get _category => widget.category;
  String get _categoryLabel => _category == 'Beer' ? 'Beer' : 'Whisky';

  List<models.Product> _getProductsForCategory() {
    return widget.allProducts.where((p) {
      final catName = (p.category?.name ?? '').toLowerCase();
      if (_category == 'Beer') return catName.contains('beer');
      return !catName.contains('beer');
    }).toList();
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
    if (product.subcategory?.name != null) {
      final match = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML)', caseSensitive: false).firstMatch(product.subcategory!.name);
      if (match != null) return ProductConstants.normalizeSize(match.group(0)!);
    }
    return '';
  }

  Map<String, _SizeStats> _getSizeStats() {
    final products = _getProductsForCategory();
    final stats = <String, _SizeStats>{};
    for (var p in products) {
      final size = _extractProductSize(p);
      if (size.isEmpty) continue;
      final stock = widget.stockMap[p.id];
      final qty = stock?.quantity ?? 0;
      if (!stats.containsKey(size)) stats[size] = _SizeStats(size: size);
      stats[size]!.totalStock += qty;
      stats[size]!.totalValue += p.sellingPrice * qty;
    }
    final sorted = stats.values.toList()
      ..sort((a, b) {
        final aNum = int.tryParse(a.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        final bNum = int.tryParse(b.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        return aNum.compareTo(bNum);
      });
    return {for (var s in sorted) s.size: s};
  }

  String _formatValue(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(0)}K';
    return value.toStringAsFixed(0);
  }

  void _onDatePillTapped(String label) async {
    HapticFeedbackUtil.selection();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (label == 'Today') {
      setState(() {
        _selectedDateLabel = label; _selectedDate = today;
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    } else if (label == 'Yesterday') {
      setState(() {
        _selectedDateLabel = label; _selectedDate = today.subtract(const Duration(days: 1));
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    } else if (label == 'Last 7 Days' || label == 'Last Month') {
      setState(() {
        _selectedDateLabel = label; _selectedDate = today.subtract(const Duration(days: 1));
        _activeRangeLabel = label; _stripSelectedDate = null;
      });
    } else if (label == 'Custom') {
      final picked = await showDatePicker(
        context: context, initialDate: _selectedDate,
        firstDate: today.subtract(const Duration(days: 90)), lastDate: today,
        helpText: 'Select custom date',
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: Theme.of(c).colorScheme.copyWith(primary: const Color(0xFF3855B3))), child: child!),
      );
      if (picked == null) return;
      setState(() {
        _selectedDateLabel = label; _selectedDate = picked;
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    }
  }

  void _onStripDateTapped(DateTime date) {
    HapticFeedbackUtil.selection();
    setState(() { _stripSelectedDate = date; _selectedDate = date; });
  }

  Widget _buildDateStrip() {
    final isLast7 = _activeRangeLabel == 'Last 7 Days';
    final dayCount = isLast7 ? 7 : 30;
    final today = DateTime.now();
    final dates = List.generate(dayCount, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: i)));

    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = _stripSelectedDate != null &&
              _stripSelectedDate!.year == date.year &&
              _stripSelectedDate!.month == date.month &&
              _stripSelectedDate!.day == date.day;
          final isToday = date.year == today.year && date.month == today.month && date.day == today.day;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onStripDateTapped(date),
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF3855B3)
                      : isToday ? const Color(0xFFE8F0FE) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3855B3)
                        : isToday ? const Color(0xFF3855B3).withValues(alpha: 0.3) : const Color(0xFFD0D5DD)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('EEE').format(date),
                      style: _body(size: 9, weight: FontWeight.w600,
                        color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                    const SizedBox(height: 1),
                    Text('${date.day}',
                      style: _body(size: 16, weight: FontWeight.w900,
                        color: isSelected ? Colors.white : const Color(0xFF1A1D26))),
                    Text(DateFormat('MMM').format(date),
                      style: _body(size: 8, weight: FontWeight.w600,
                        color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDatePills() {
    final labels = ['Today', 'Yesterday', 'Last 7 Days', 'Last Month', 'Custom'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        itemBuilder: (context, index) {
          final label = labels[index];
          final isActive = _selectedDateLabel == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onDatePillTapped(label),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF3855B3) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isActive ? const Color(0xFF3855B3) : const Color(0xFFD0D5DD)),
                ),
                child: Text(label, style: _body(
                  size: 12, weight: FontWeight.w600,
                  color: isActive ? Colors.white : const Color(0xFF888888),
                )),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sizeStats = _getSizeStats();
    final isAI = _currentMode == SalesEntryMode.ai;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
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
                  Expanded(
                    child: Text('Type of capacity', textAlign: TextAlign.center,
                      style: _heading(size: 17, weight: FontWeight.w600)),
                  ),
                  Container(
                    width: 36, height: 36,
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

            // ── Mode toggle (functional) ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    _modeTab('Manual Entry', SalesEntryMode.manual, isAI),
                    _modeTab('Entry With AI', SalesEntryMode.ai, isAI),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Date pills (same as Screen 1, stays in sync) ──
            _buildDatePills(),
            if (_activeRangeLabel != null) ...[
              const SizedBox(height: 8),
              _buildDateStrip(),
            ],
            const SizedBox(height: 8),
            // ── Date display with category badge ──
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
                    const Icon(Icons.calendar_today, size: 16, color: Color(0xFF2962FF)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sales date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF)),
                      ),
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
                    _category == 'Beer' ? _SalesAssets.beerCard : _SalesAssets.whiskyHero,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFF1A1A2E),
                      child: Center(child: Icon(
                        _category == 'Beer' ? Icons.sports_bar : Icons.liquor,
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
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                itemCount: sizeStats.length,
                separatorBuilder: (_, __) => Divider(height: 1, thickness: 0.5, color: Colors.grey.withOpacity(0.15)),
                itemBuilder: (context, index) {
                  final stat = sizeStats.values.elementAt(index);
                  return _buildSizeRow(stat);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTab(String label, SalesEntryMode tabMode, bool isAI) {
    final isSelected = _currentMode == tabMode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedbackUtil.selection();
          setState(() => _currentMode = tabMode);
        },
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF3855B3) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: _body(
            size: 14, weight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF888888),
          )),
        ),
      ),
    );
  }

  Widget _buildSizeRow(_SizeStats stat) {
    final isSubmitted = widget.submittedSizes.contains(stat.size);

    return GestureDetector(
      onTap: isSubmitted ? () {
        SnackbarHelper.showInfo(context, '${stat.size} $_categoryLabel already submitted');
      } : () async {
        HapticFeedbackUtil.medium();
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => _currentMode == SalesEntryMode.ai
                ? AISalesEntryScreen(
                    category: _category,
                    size: stat.size,
                    selectedDate: _selectedDate,
                  )
                : DailySalesEntryScreen(
                    showHeader: true,
                    initialCategoryName: _category,
                    initialSize: stat.size,
                    selectedDate: _selectedDate,
                  ),
          ),
        );
        if (result == 'submitted' && mounted) {
          Navigator.pop(context, 'submitted');
        }
      },
      child: Opacity(
        opacity: isSubmitted ? 0.45 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: bottle icon in grey circle
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _category == 'Beer' ? Icons.sports_bar_rounded : Icons.liquor_rounded,
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
                    if (!isSubmitted) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SvgPicture.asset('assets/icons/cart_stock.svg', width: 13, height: 13, colorFilter: const ColorFilter.mode(Color(0xFF999999), BlendMode.srcIn)),
                          const SizedBox(width: 5),
                          Text('${stat.totalStock}', style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF999999))),
                          const SizedBox(width: 16),
                          SvgPicture.asset('assets/icons/wallet_income.svg', width: 13, height: 13, colorFilter: const ColorFilter.mode(Color(0xFF999999), BlendMode.srcIn)),
                          const SizedBox(width: 5),
                          Text(_formatValue(stat.totalValue), style: _body(size: 13, weight: FontWeight.w600, color: const Color(0xFF999999))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right: View button or Submitted
              if (!isSubmitted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD0D5DD)),
                  ),
                  child: Text('View', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text('Submitted', style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF2E7D32))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeStats {
  final String size;
  int totalStock;
  double totalValue;
  _SizeStats({required this.size, this.totalStock = 0, this.totalValue = 0});
}


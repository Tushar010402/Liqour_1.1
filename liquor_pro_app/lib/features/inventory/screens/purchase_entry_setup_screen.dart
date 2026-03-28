import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../inventory/models/product.dart' as models;
import '../../inventory/providers/product_provider.dart';
import 'ai_purchase_entry_screen.dart';
import 'purchase_entry_screen.dart';

/// Font helpers — identical to SalesEntrySetupScreen
TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Entry mode — mirrors SalesEntryMode
enum PurchaseEntryMode { manual, ai }

/// Purchase Entry Setup — mirrors SalesEntrySetupScreen exactly.
/// Shows AI/Manual toggle, date pills, and category cards (Whisky / Beer).
class PurchaseEntrySetupScreen extends StatefulWidget {
  const PurchaseEntrySetupScreen({super.key});

  @override
  State<PurchaseEntrySetupScreen> createState() => _PurchaseEntrySetupScreenState();
}

class _PurchaseEntrySetupScreenState extends State<PurchaseEntrySetupScreen> {
  PurchaseEntryMode _mode = PurchaseEntryMode.manual;
  String _selectedDateLabel = 'Yesterday';
  DateTime _selectedDate = DateTime.now().subtract(const Duration(days: 1));
  bool _isLoadingProducts = true;

  /// Date strip state (like home page)
  String? _activeRangeLabel;
  DateTime? _stripSelectedDate;

  List<models.Product> _allProducts = [];
  Map<String, models.Stock> _stockMap = {};

  @override
  void initState() {
    super.initState();
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

      if (mounted) setState(() => _isLoadingProducts = false);
    } catch (e) {
      debugPrint('[PurchaseSetup] Error: $e');
      if (mounted) setState(() => _isLoadingProducts = false);
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
        total += p.costPrice * stock.quantity;
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
        _selectedDateLabel = label; _selectedDate = picked;
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    }
  }

  void _onStripDateTapped(DateTime date) {
    HapticFeedbackUtil.selection();
    setState(() { _stripSelectedDate = date; _selectedDate = date; });
  }

  void _onCategoryTapped(String category) async {
    HapticFeedbackUtil.medium();

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _mode == PurchaseEntryMode.ai
            ? AIPurchaseEntryScreen(
                category: category,
                selectedDate: _selectedDate,
                allProducts: _allProducts,
                stockMap: _stockMap,
              )
            : PurchaseEntryScreen(
                category: category,
                selectedDate: _selectedDate,
                allProducts: _allProducts,
                stockMap: _stockMap,
              ),
      ),
    );

    if (result == 'submitted' && mounted) {
      Navigator.pop(context, 'submitted');
    } else if (result == 'switch_manual' && mounted) {
      // AI failed, user wants manual — switch mode and re-tap
      setState(() => _mode = PurchaseEntryMode.manual);
      _onCategoryTapped(category);
    }
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
            _buildHeader('Add Purchase'),
            _buildModeToggle(),
            const SizedBox(height: 14),
            _buildDatePills(),
            if (_activeRangeLabel != null) ...[
              const SizedBox(height: 8),
              _buildDateStrip(),
            ],
            ...[
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
                        'Purchase date: ${DateFormat('dd MMM yyyy, EEEE').format(_selectedDate)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
                            imageUrl: 'assets/images/sales/whisky_card.png',
                            icon: Icons.liquor,
                          ),
                          const SizedBox(height: 16),
                          _buildCategoryCard(
                            category: 'Beer',
                            title: 'Beer',
                            subtitle: 'Beer category performance overview. Tracking volume and total value',
                            imageUrl: 'assets/images/sales/beer_card.png',
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
            _buildModeTab('Manual Entry', PurchaseEntryMode.manual),
            _buildModeTab('Entry With AI', PurchaseEntryMode.ai),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab(String label, PurchaseEntryMode mode) {
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

    return GestureDetector(
      onTap: () => _onCategoryTapped(category),
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
    );
  }
}

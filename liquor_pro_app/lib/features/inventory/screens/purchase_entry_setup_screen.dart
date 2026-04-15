import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../inventory/models/product.dart' as models;
import '../../inventory/models/stock_purchase.dart';
import '../../inventory/providers/product_provider.dart';
import '../../inventory/services/stock_purchase_service.dart';
import 'ai_purchase_entry_screen.dart';
import 'purchase_entry_screen.dart';
import 'purchase_summary_screen.dart';
import 'purchase_summary_view_screen.dart';

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
  final DateTime? initialDate;
  final String? initialDateLabel;
  final String? initialRangeLabel;

  const PurchaseEntrySetupScreen({super.key, this.initialDate, this.initialDateLabel, this.initialRangeLabel});

  @override
  State<PurchaseEntrySetupScreen> createState() => _PurchaseEntrySetupScreenState();
}

class _PurchaseEntrySetupScreenState extends State<PurchaseEntrySetupScreen> {
  PurchaseEntryMode _mode = PurchaseEntryMode.ai;
  late String _selectedDateLabel;
  late DateTime _selectedDate;
  bool _isLoadingProducts = true;

  /// Date strip state (like home page)
  String? _activeRangeLabel;
  DateTime? _stripSelectedDate;

  List<models.Product> _allProducts = [];
  Map<String, models.Stock> _stockMap = {};
  List<StockPurchase> _submittedPurchases = [];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now().subtract(const Duration(days: 1));
    if (widget.initialRangeLabel != null) {
      _selectedDateLabel = widget.initialRangeLabel!;
      _activeRangeLabel = widget.initialRangeLabel;
      _stripSelectedDate = _selectedDate;
    } else {
      _selectedDateLabel = widget.initialDateLabel ?? 'Yesterday';
    }
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

      // Load submitted purchases for this date
      await _loadSubmittedPurchases(shopId);

      if (mounted) setState(() => _isLoadingProducts = false);
    } catch (e) {
      debugPrint('[PurchaseSetup] Error: $e');
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _loadSubmittedPurchases(String shopId) async {
    try {
      final apiService = context.read<DioApiService>();
      final purchaseService = StockPurchaseService(apiService);
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final response = await purchaseService.getPurchaseHistory(
        shopId: shopId,
        fromDate: startOfDay,
        toDate: endOfDay,
      );
      if (response.success && response.data != null) {
        _submittedPurchases = response.data!.purchases
            .where((p) => p.status != StockPurchaseStatus.rejected)
            .toList();
      } else {
        _submittedPurchases = [];
      }
    } catch (e) {
      debugPrint('[PurchaseSetup] Error loading purchases: $e');
      _submittedPurchases = [];
    }
  }

  bool _hasPurchasesForDate() => _submittedPurchases.isNotEmpty;

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
    // Reload purchases for new date
    if (!mounted) return;
    final shopId = context.read<ShopSelectionProvider>().selectedShopId;
    if (shopId != null) await _loadSubmittedPurchases(shopId);
    if (mounted) setState(() {});
  }

  void _onStripDateTapped(DateTime date) async {
    HapticFeedbackUtil.selection();
    setState(() { _stripSelectedDate = date; _selectedDate = date; });
    if (!mounted) return;
    final shopId = context.read<ShopSelectionProvider>().selectedShopId;
    if (shopId != null) await _loadSubmittedPurchases(shopId);
    if (mounted) setState(() {});
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
                          // Show submitted purchases for this date
                          if (_submittedPurchases.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                const Icon(Icons.check_circle, size: 16, color: Color(0xFF2E7D32)),
                                const SizedBox(width: 6),
                                Text('Purchases on ${DateFormat('dd MMM').format(_selectedDate)}',
                                  style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF2E7D32))),
                                const Spacer(),
                                Text('${_submittedPurchases.length} ${_submittedPurchases.length == 1 ? 'entry' : 'entries'}',
                                  style: _body(size: 12, weight: FontWeight.w600, color: const Color(0xFF888888))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ..._submittedPurchases.map((purchase) => _buildPurchaseHistoryCard(purchase)),
                          ],
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
    final isAI = mode == PurchaseEntryMode.ai;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedbackUtil.selection(); setState(() => _mode = mode); },
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: isSelected
                ? (isAI ? const Color(0xFF1A1A2E) : const Color(0xFF3855B3))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            gradient: isSelected && isAI ? const LinearGradient(
              colors: [Color(0xFF1A1A2E), Color(0xFF2D1B69)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ) : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAI) ...[
                Icon(Icons.workspace_premium, size: 16,
                  color: isSelected ? const Color(0xFFFFD700) : const Color(0xFFBBBBBB)),
                const SizedBox(width: 5),
              ],
              Text(label, style: _body(
                size: 14, weight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFF888888),
              )),
            ],
          ),
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

  Widget _buildPurchaseHistoryCard(StockPurchase purchase) {
    final itemCount = purchase.items.length;
    final statusColor = purchase.status == StockPurchaseStatus.approved
        ? const Color(0xFF2E7D32)
        : purchase.status == StockPurchaseStatus.pending
            ? const Color(0xFFE65100)
            : const Color(0xFF888888);
    final statusLabel = purchase.status.name.toUpperCase();

    return GestureDetector(
      onTap: () {
        HapticFeedbackUtil.medium();
        // Convert purchase items to PurchaseSummaryItems and show read-only summary
        final items = purchase.items.map((item) => PurchaseSummaryItem(
          productId: item.productId,
          name: item.productName,
          brandName: item.brandName,
          size: item.size,
          costPrice: item.costPrice,
          sellingPrice: 0,
          quantity: item.quantity,
          stock: 0,
        )).toList();
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => PurchaseSummaryScreen(
            items: items,
            selectedDate: _selectedDate,
            readOnly: true,
          ),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.shopping_cart_rounded, size: 18, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(purchase.vendorName.isNotEmpty ? purchase.vendorName : 'Purchase',
                    style: _body(size: 14, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$itemCount items \u2022 \u20B9${purchase.totalAmount.toStringAsFixed(0)}',
                    style: _body(size: 12, weight: FontWeight.w500, color: const Color(0xFF888888))),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(statusLabel, style: _body(size: 9, weight: FontWeight.w700, color: statusColor)),
                ),
                const SizedBox(height: 4),
                Text('View Summary', style: _body(size: 11, weight: FontWeight.w600, color: const Color(0xFF3855B3))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

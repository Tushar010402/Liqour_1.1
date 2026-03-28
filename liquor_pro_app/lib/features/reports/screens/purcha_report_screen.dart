import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../models/purcha_report_models.dart';
import '../providers/purcha_report_provider.dart';
import '../services/purcha_report_service.dart';
import '../services/purcha_pdf_generator.dart';
import '../../../core/services/dio_api_service.dart';

/// Purcha Report Screen - Clean UI matching PDF format
class PurchaReportScreen extends StatefulWidget {
  const PurchaReportScreen({super.key});

  @override
  State<PurchaReportScreen> createState() => _PurchaReportScreenState();
}

class _PurchaReportScreenState extends State<PurchaReportScreen>
    with TickerProviderStateMixin {
  late PurchaReportProvider _provider;
  TabController? _tabController;
  final ScrollController _scrollController = ScrollController();
  bool _isInitialized = false;
  int _currentTabLength = 0;
  bool _isDownloading = false;
  bool _isSharing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeProvider();
      _isInitialized = true;
    }
  }

  void _initializeProvider() {
    final apiService = context.read<DioApiService>();
    final shopProvider = context.read<ShopSelectionProvider>();

    _provider = PurchaReportProvider(PurchaReportService(apiService));
    _provider.setViewMode(PurchaViewMode.flat);

    if (shopProvider.selectedShopId != null) {
      _provider.setSelectedShop(shopProvider.selectedShopId);
      _loadReport();
    }
  }

  Future<void> _loadReport() async {
    await _provider.loadReport();
    _updateTabController();
  }

  void _updateTabController() {
    final sizes = _provider.availableSizes;
    if (sizes.isNotEmpty && sizes.length != _currentTabLength) {
      _tabController?.dispose();
      _currentTabLength = sizes.length;
      _tabController = TabController(length: sizes.length, vsync: this);
      _tabController!.addListener(() {
        if (!_tabController!.indexIsChanging && mounted) {
          _provider.setSelectedSize(sizes[_tabController!.index]);
        }
      });
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatValue(int value) => value == 0 ? '' : '$value';

  String _formatAmount(double amount) {
    if (amount == 0) return '';
    return amount.toStringAsFixed(0);
  }

  String _formatRate(double rate) => rate.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          title: Consumer<PurchaReportProvider>(
            builder: (context, provider, _) {
              final size = provider.selectedSize ?? '';
              return Text(
                size.isNotEmpty ? 'SALE RECEIPT - $size' : 'Purcha Report',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              );
            },
          ),
          actions: [
            Consumer<PurchaReportProvider>(
              builder: (context, provider, _) {
                final isEnabled = !_isDownloading &&
                                   !provider.isLoading &&
                                   provider.hasData;
                return TextButton.icon(
                  onPressed: isEnabled ? () => _downloadPdf(provider) : null,
                  style: TextButton.styleFrom(
                    foregroundColor: isEnabled ? iOSDesignTokens.primary : cs.onSurfaceVariant,
                  ),
                  icon: _isDownloading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: iOSDesignTokens.primary,
                          ),
                        )
                      : Icon(
                          Icons.download_rounded,
                          size: 20,
                          color: isEnabled ? iOSDesignTokens.primary : cs.onSurfaceVariant,
                        ),
                  label: Text(
                    'PDF',
                    style: TextStyle(
                      color: isEnabled ? iOSDesignTokens.primary : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
            Consumer<PurchaReportProvider>(
              builder: (context, provider, _) {
                final isEnabled = !_isSharing &&
                                   !provider.isLoading &&
                                   provider.hasData;
                return IconButton(
                  onPressed: isEnabled ? () => _sharePdf(provider) : null,
                  icon: _isSharing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: iOSDesignTokens.primary,
                          ),
                        )
                      : Icon(
                          Icons.share_rounded,
                          color: isEnabled ? iOSDesignTokens.primary : cs.onSurfaceVariant,
                        ),
                );
              },
            ),
          ],
        ),
        body: Consumer<PurchaReportProvider>(
          builder: (context, provider, _) {
            return Column(
              children: [
                _buildFiltersSection(provider),
                const Divider(height: 1),
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : provider.error != null
                          ? _buildErrorState(provider)
                          : !provider.hasData
                              ? _buildEmptyState()
                              : _buildReportBody(provider),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFiltersSection(PurchaReportProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<ShopSelectionProvider>(
      builder: (context, shopProvider, _) {
        final shopName = shopProvider.selectedShop?.name ?? 'Select Shop';
        final hasShops = shopProvider.shops.isNotEmpty;

        return Container(
          color: cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            children: [
              // Row 1: Shop Selector and Date
              Row(
                children: [
                  // Shop Selector - Tappable
                  Expanded(
                    child: InkWell(
                      onTap: hasShops ? () => _showShopPicker(shopProvider, provider) : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: iOSDesignTokens.primary.withValues(alpha: 0.5)),
                          borderRadius: BorderRadius.circular(8),
                          color: iOSDesignTokens.primary.withValues(alpha: 0.05),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.store, size: 16, color: iOSDesignTokens.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                shopName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: iOSDesignTokens.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 20,
                              color: iOSDesignTokens.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Date Picker
                  InkWell(
                    onTap: () => _selectDate(provider),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd/MM/yyyy').format(provider.selectedDate),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: Category Filter (All/Beer/Non-Beer)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: PurchaCategoryFilter.values.map((filter) {
                          final isSelected = provider.categoryFilter == filter;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                provider.setCategoryFilter(filter);
                                _loadReport();
                              },
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected ? iOSDesignTokens.primary : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  filter.displayName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.white : cs.onSurface,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Row 3: View Mode (Flat/Category) and Opening Toggle
              Row(
                children: [
                  // View Mode Toggle (Flat / Category)
                  Expanded(
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: PurchaViewMode.values.map((mode) {
                          final isSelected = provider.viewMode == mode;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                provider.setViewMode(mode);
                                _loadReport();
                              },
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.blue.shade700 : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  mode == PurchaViewMode.flat ? 'Flat' : 'Category',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? Colors.white : cs.onSurface,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Opening Toggle - Controls visibility of Opening column
                  // Data is always fetched, toggle only controls UI display
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      provider.setShowOpening(!provider.showOpening);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: provider.showOpening ? Colors.green.shade600 : Colors.orange.shade400,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: provider.showOpening ? Colors.green.shade50 : Colors.orange.shade50,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            provider.showOpening ? Icons.visibility : Icons.visibility_off_outlined,
                            size: 18,
                            color: provider.showOpening ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Opening',
                            style: TextStyle(
                              fontSize: 12,
                              color: provider.showOpening ? Colors.green.shade800 : Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Show ON/OFF indicator
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: provider.showOpening ? Colors.green.shade600 : Colors.orange.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              provider.showOpening ? 'ON' : 'OFF',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  /// Show shop picker bottom sheet
  void _showShopPicker(ShopSelectionProvider shopProvider, PurchaReportProvider reportProvider) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.store, color: iOSDesignTokens.primary),
                    const SizedBox(width: 12),
                    const Text(
                      'Select Shop',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Shop list
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: shopProvider.shops.length,
                  itemBuilder: (context, index) {
                    final shop = shopProvider.shops[index];
                    final isSelected = shop.id == shopProvider.selectedShopId;

                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? iOSDesignTokens.primary.withValues(alpha: 0.15)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.store,
                          color: isSelected ? iOSDesignTokens.primary : cs.onSurfaceVariant,
                        ),
                      ),
                      title: Text(
                        shop.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? iOSDesignTokens.primary : cs.onSurface,
                        ),
                      ),
                      subtitle: shop.address.isNotEmpty
                          ? Text(
                              shop.address,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: iOSDesignTokens.primary)
                          : null,
                      onTap: () async {
                        await shopProvider.selectShop(shop);
                        reportProvider.setSelectedShop(shop.id);
                        if (mounted) {
                          Navigator.pop(context);
                          _loadReport();
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReportBody(PurchaReportProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Size Tabs
        if (provider.availableSizes.isNotEmpty &&
            _tabController != null &&
            _tabController!.length == provider.availableSizes.length)
          Container(
            color: cs.surfaceContainerHighest,
            child: TabBar(
              controller: _tabController,
              isScrollable: provider.availableSizes.length > 4,
              labelColor: Colors.white,
              unselectedLabelColor: cs.onSurface,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              indicator: BoxDecoration(
                color: iOSDesignTokens.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              dividerColor: Colors.transparent,
              tabs: provider.availableSizes.map((size) => Tab(text: size)).toList(),
            ),
          ),
        // Table Header
        _buildTableHeader(provider.showOpening),
        // Table Content
        Expanded(
          child: _buildTableContent(provider),
        ),
        // Grand Total
        _buildGrandTotalRow(provider),
      ],
    );
  }

  Widget _buildTableHeader(bool showOpening) {
    final cs = Theme.of(context).colorScheme;
    // ALWAYS show all 9 columns - headers are always visible
    return Container(
      color: cs.outlineVariant,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          _headerCell('No', width: 24),
          _headerCell('Brand Name', flex: 1),
          _headerCell('Open', width: 42),
          _headerCell('Rcpt', width: 38),
          _headerCell('Total', width: 40),
          _headerCell('Sale', width: 40),
          _headerCell('Rate', width: 42),
          _headerCell('Amt', width: 52),
          _headerCell('Close', width: 42),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {double? width, int? flex}) {
    final cs = Theme.of(context).colorScheme;
    final child = Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: cs.onSurface,
      ),
      textAlign: TextAlign.center,
    );

    if (flex != null) {
      return Expanded(flex: flex, child: child);
    }
    return SizedBox(width: width, child: Center(child: child));
  }

  Widget _buildTableContent(PurchaReportProvider provider) {
    final page = provider.currentPage;
    if (page == null) return const SizedBox.shrink();

    // Build list with category headers if in category mode
    final List<Widget> rows = [];
    int serialNo = 0;

    for (final category in page.categories) {
      // Filter items to only show those with actual stock activity
      // AND sort by PRICE (rate) ascending - matching Daily Sales Entry
      final activeItems = category.items
          .where(_hasStockActivity)
          .toList()
        ..sort((a, b) {
          // Sort by rate (price) ascending - same as Daily Sales Entry
          final priceComparison = a.rate.compareTo(b.rate);
          if (priceComparison != 0) return priceComparison;
          // If same price, sort by brand name
          return a.brandName.compareTo(b.brandName);
        });

      // Skip category if no active items
      if (activeItems.isEmpty) continue;

      // Add category header if in category mode
      if (provider.viewMode == PurchaViewMode.category) {
        rows.add(_buildCategoryHeader(category.categoryName, activeItems.length));
      }

      // Add items
      for (final item in activeItems) {
        serialNo++;
        rows.add(_buildTableRow(item, provider.showOpening, serialNo));
      }
    }

    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      children: rows,
    );
  }

  /// Check if item has any stock activity (not all zeros)
  bool _hasStockActivity(PurchaReportItem item) {
    return item.openingStock > 0 ||
           item.receipt > 0 ||
           item.sale > 0 ||
           item.closingStock > 0 ||
           item.total > 0 ||
           item.amount > 0;
  }

  Widget _buildCategoryHeader(String categoryName, int itemCount) {
    return Container(
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.category, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              categoryName.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$itemCount items',
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(PurchaReportItem item, bool showOpening, int index) {
    final cs = Theme.of(context).colorScheme;
    final isEven = index % 2 == 0;
    // ALWAYS show all 9 columns - Opening/Total/Closing show empty when showOpening is false
    return Container(
      decoration: BoxDecoration(
        color: isEven ? cs.surface : cs.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          // S.No
          SizedBox(
            width: 24,
            child: Text(
              '$index',
              style: _cellStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Brand Name - takes remaining space
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                item.brandName,
                style: _cellStyle().copyWith(fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Opening - ALWAYS show column, empty value when showOpening is false
          SizedBox(
            width: 42,
            child: Text(
              showOpening ? _formatValue(item.openingStock) : '',
              style: _cellStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Receipt
          SizedBox(
            width: 38,
            child: Text(
              _formatValue(item.receipt),
              style: _cellStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Total - ALWAYS show column, empty value when showOpening is false
          SizedBox(
            width: 40,
            child: Text(
              showOpening ? _formatValue(item.total) : '',
              style: _cellStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Sale
          SizedBox(
            width: 40,
            child: Text(
              _formatValue(item.sale),
              style: _cellStyle().copyWith(
                fontWeight: item.sale > 0 ? FontWeight.bold : FontWeight.normal,
                color: item.sale > 0 ? Colors.blue.shade800 : cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Rate
          SizedBox(
            width: 42,
            child: Text(
              _formatRate(item.rate),
              style: _cellStyle().copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          // Amount
          SizedBox(
            width: 52,
            child: Text(
              _formatAmount(item.amount),
              style: _cellStyle().copyWith(
                fontWeight: item.amount > 0 ? FontWeight.bold : FontWeight.normal,
                color: item.amount > 0 ? Colors.green.shade800 : cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Closing - ALWAYS show column, empty value when showOpening is false
          SizedBox(
            width: 42,
            child: Text(
              showOpening ? _formatValue(item.closingStock) : '',
              style: _cellStyle(),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _cellStyle() {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(fontSize: 11, color: cs.onSurface);
  }

  Widget _buildGrandTotalRow(PurchaReportProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final stats = provider.currentPageStats;
    final showOpening = provider.showOpening;

    // ALWAYS show all 9 columns - Opening/Total/Closing show empty when showOpening is false
    return Container(
      color: cs.outlineVariant,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              'GRAND TOTAL',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
          ),
          // Opening - ALWAYS show column, empty value when showOpening is false
          SizedBox(
            width: 42,
            child: Text(
              showOpening ? _formatValue(stats['opening'] as int) : '',
              style: _totalStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Receipt - always shown
          SizedBox(
            width: 38,
            child: Text(
              _formatValue(stats['receipt'] as int),
              style: _totalStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Total - ALWAYS show column, empty value when showOpening is false
          SizedBox(
            width: 40,
            child: Text(
              showOpening ? _formatValue(stats['total'] as int) : '',
              style: _totalStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          // Sale - always shown
          SizedBox(
            width: 40,
            child: Text(
              _formatValue(stats['sale'] as int),
              style: _totalStyle().copyWith(color: Colors.blue.shade900),
              textAlign: TextAlign.center,
            ),
          ),
          // Rate - empty space, always shown
          const SizedBox(width: 42),
          // Amount - always shown
          SizedBox(
            width: 52,
            child: Text(
              _formatAmount(stats['amount'] as double),
              style: _totalStyle().copyWith(color: Colors.green.shade900),
              textAlign: TextAlign.center,
            ),
          ),
          // Closing - ALWAYS show column, empty value when showOpening is false
          SizedBox(
            width: 42,
            child: Text(
              showOpening ? _formatValue(stats['closing'] as int) : '',
              style: _totalStyle(),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _totalStyle() {
    final cs = Theme.of(context).colorScheme;
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: cs.onSurface,
    );
  }

  Widget _buildErrorState(PurchaReportProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text(
              'Unable to Load Report',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              provider.error ?? 'An error occurred',
              style: TextStyle(fontSize: 14, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'No Data Available',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'No report data found for the selected date.',
              style: TextStyle(fontSize: 14, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate(PurchaReportProvider provider) async {
    final date = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      provider.setSelectedDate(date);
      _loadReport();
    }
  }

  Future<void> _downloadPdf(PurchaReportProvider provider) async {
    if (provider.report == null || _isDownloading) return;

    setState(() => _isDownloading = true);
    HapticFeedback.mediumImpact();

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text('Generating PDF${provider.showOpening ? '' : ' (compact view)'}...'),
          ],
        ),
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      // Pass showOpening to respect the toggle setting
      final file = await PurchaPdfGenerator.generateAndSave(
        provider.report!,
        showOpening: provider.showOpening,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved: ${file.path.split('/').last}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'SHARE',
              textColor: Colors.white,
              onPressed: () async {
                await Share.shareXFiles([XFile(file.path)]);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _sharePdf(PurchaReportProvider provider) async {
    if (provider.report == null || _isSharing) return;

    setState(() => _isSharing = true);
    HapticFeedback.mediumImpact();

    try {
      final shopProvider = context.read<ShopSelectionProvider>();
      final shopName = shopProvider.selectedShop?.name ?? 'Shop';
      final dateStr = DateFormat('dd-MM-yyyy').format(provider.selectedDate);

      // Generate file first, then share
      // Don't await the share - it may not complete properly on cancel
      final file = await PurchaPdfGenerator.generateAndSave(
        provider.report!,
        showOpening: provider.showOpening,
      );

      // Reset state before showing share sheet
      // This allows the button to be tapped again after share sheet is dismissed
      if (mounted) {
        setState(() => _isSharing = false);
      }

      // Share without awaiting - the share sheet handles its own lifecycle
      Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Purcha Report - $shopName - $dateStr',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSharing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share PDF: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

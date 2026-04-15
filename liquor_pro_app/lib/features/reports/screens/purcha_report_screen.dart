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
              // Row 3: Stock Manage toggle (show/hide Opening & Closing data)
              Row(
                children: [
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      provider.setShowOpening(!provider.showOpening);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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
                            'Stock Manage',
                            style: TextStyle(
                              fontSize: 12,
                              color: provider.showOpening ? Colors.green.shade800 : Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: provider.showOpening ? Colors.green.shade600 : Colors.orange.shade600,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              provider.showOpening ? 'ON' : 'OFF',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
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
        // 2-Column A4 Layout
        Expanded(
          child: _buildTwoColumnLayout(provider),
        ),
        // Grand Total
        _buildGrandTotalRow(provider),
      ],
    );
  }

  /// Flatten and sort all items from current page
  List<PurchaReportItem> _getFlatItems(PurchaReportProvider provider) {
    final page = provider.currentPage;
    if (page == null) return [];
    final items = <PurchaReportItem>[];
    for (final cat in page.categories) {
      items.addAll(cat.items);
    }
    items.sort((a, b) {
      final p = a.rate.compareTo(b.rate);
      if (p != 0) return p;
      return a.brandName.compareTo(b.brandName);
    });
    return items;
  }

  /// 2-column A4-style layout: left half (items 1-28), right half (items 29-56)
  Widget _buildTwoColumnLayout(PurchaReportProvider provider) {
    final items = _getFlatItems(provider);
    final showOpening = provider.showOpening;
    const rowsPerCol = 20;

    // Pad to at least 28 so left column is always full
    final totalSlots = items.length <= rowsPerCol ? rowsPerCol : ((items.length - 1) ~/ rowsPerCol + 1) * rowsPerCol;
    final leftCount = totalSlots >= rowsPerCol ? rowsPerCol : totalSlots;
    final rightCount = totalSlots > rowsPerCol ? totalSlots - rowsPerCol : 0;

    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column
          Expanded(child: _buildHalfTable(items, 0, leftCount, showOpening)),
          const SizedBox(width: 4),
          // Right column
          if (rightCount > 0 || items.length > rowsPerCol)
            Expanded(child: _buildHalfTable(items, rowsPerCol, rightCount > 0 ? rightCount : rowsPerCol, showOpening))
          else
            Expanded(child: _buildHalfTable(items, rowsPerCol, rowsPerCol, showOpening)),
        ],
      ),
    );
  }

  Widget _buildHalfTable(List<PurchaReportItem> allItems, int startIdx, int count, bool showOpening) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant, width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Header
          Container(
            color: cs.outlineVariant,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: Row(
              children: [
                _hCell('No', 24),
                Expanded(child: Text('Brand (\u20B9MRP)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurface))),
                _hCell('Open', 36),
                _hCell('Sale', 36),
                _hCell('Close', 36),
              ],
            ),
          ),
          // Rows
          for (int i = 0; i < count; i++)
            _buildA4Row(
              startIdx + i + 1,
              startIdx + i < allItems.length ? allItems[startIdx + i] : null,
              showOpening,
              i % 2 == 0,
            ),
        ],
      ),
    );
  }

  Widget _hCell(String text, double width) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurface)),
    );
  }

  Widget _buildA4Row(int serialNo, PurchaReportItem? item, bool showOpening, bool isEven) {
    final cs = Theme.of(context).colorScheme;
    final dName = item != null && item.displayName.isNotEmpty ? item.displayName : (item?.brandName ?? '');
    final brandText = item != null
        ? (item.rate > 0 ? '$dName (\u20B9${item.rate.toStringAsFixed(0)})' : dName)
        : '';

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: isEven ? cs.surface : cs.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.3)),
      ),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('$serialNo', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface))),
          Expanded(
            child: Text(brandText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 36, child: Text(
            item != null && showOpening ? _formatValue(item.openingStock) : '',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface),
          )),
          SizedBox(width: 36, child: Text(
            item != null ? _formatValue(item.sale) : '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: item != null && item.sale > 0 ? FontWeight.bold : FontWeight.normal, color: item != null && item.sale > 0 ? Colors.blue.shade800 : cs.onSurface),
          )),
          SizedBox(width: 36, child: Text(
            item != null && showOpening ? _formatValue(item.closingStock) : '',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface),
          )),
        ],
      ),
    );
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
    // Brand Name with MRP: "Royal Stag (₹94)" — use display_name if available
    final displayName = item.displayName.isNotEmpty ? item.displayName : item.brandName;
    final brandWithMrp = item.rate > 0
        ? '$displayName (\u20B9${_formatRate(item.rate)})'
        : displayName;

    return Container(
      decoration: BoxDecoration(
        color: isEven ? cs.surface : cs.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$index', style: _cellStyle(), textAlign: TextAlign.center),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                brandWithMrp,
                style: _cellStyle().copyWith(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              showOpening ? _formatValue(item.openingStock) : '',
              style: _cellStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              _formatValue(item.sale),
              style: _cellStyle().copyWith(
                fontWeight: item.sale > 0 ? FontWeight.bold : FontWeight.normal,
                color: item.sale > 0 ? Colors.blue.shade800 : cs.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 48,
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

    return Container(
      color: cs.outlineVariant,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Row(
        children: [
          const SizedBox(width: 28),
          Expanded(
            child: Text(
              'GRAND TOTAL',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
          ),
          // Empty boxes for manual writing
          SizedBox(
            width: 48,
            child: Container(
              height: 24,
              decoration: BoxDecoration(border: Border.all(color: cs.outline, width: 0.5)),
            ),
          ),
          SizedBox(
            width: 48,
            child: Container(
              height: 24,
              decoration: BoxDecoration(border: Border.all(color: cs.outline, width: 0.5)),
            ),
          ),
          SizedBox(
            width: 48,
            child: Container(
              height: 24,
              decoration: BoxDecoration(border: Border.all(color: cs.outline, width: 0.5)),
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

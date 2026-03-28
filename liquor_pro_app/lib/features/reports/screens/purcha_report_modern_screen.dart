import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../models/purcha_report_models.dart';
import '../providers/purcha_report_provider.dart';
import '../services/purcha_report_service.dart';
import '../services/purcha_pdf_generator.dart';
import '../../../core/services/dio_api_service.dart';

/// Modern Purcha Report Screen — iOS-style design
class PurchaReportModernScreen extends StatefulWidget {
  const PurchaReportModernScreen({super.key});

  @override
  State<PurchaReportModernScreen> createState() =>
      _PurchaReportModernScreenState();
}

class _PurchaReportModernScreenState extends State<PurchaReportModernScreen>
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

  final _currFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  String _fmtQty(int v) => v == 0 ? '-' : '$v';
  String _fmtRate(double v) => v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChangeNotifierProvider.value(
      value: _provider,
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        body: Consumer<PurchaReportProvider>(
          builder: (context, provider, _) {
            return CustomScrollView(
              controller: _scrollController,
              slivers: [
                // ─── App Bar ───
                _buildSliverAppBar(cs, provider),

                // ─── Filter Section ───
                SliverToBoxAdapter(child: _buildFilterCard(cs, provider)),

                // ─── Content ───
                if (provider.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (provider.error != null)
                  SliverFillRemaining(child: _buildErrorState(cs, provider))
                else if (!provider.hasData)
                  SliverFillRemaining(child: _buildEmptyState(cs))
                else ...[
                  // Summary cards
                  SliverToBoxAdapter(child: _buildSummaryCards(cs, provider)),
                  // Size tabs
                  SliverToBoxAdapter(child: _buildSizeTabs(cs, provider)),
                  // Table
                  SliverToBoxAdapter(child: _buildDataTable(cs, provider)),
                  // Bottom spacing
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // App Bar
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSliverAppBar(ColorScheme cs, PurchaReportProvider provider) {
    final size = provider.selectedSize ?? '';
    return SliverAppBar(
      pinned: true,
      backgroundColor: cs.surface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cs.onSurface),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Purchase Report',
            style: AppTextStyles.h6.copyWith(color: cs.onSurface),
          ),
          if (size.isNotEmpty)
            Text(
              size,
              style: AppTextStyles.caption.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
      actions: [
        _buildActionButton(
          icon: _isDownloading ? null : Icons.download_rounded,
          isLoading: _isDownloading,
          enabled: !_isDownloading && !provider.isLoading && provider.hasData,
          onTap: () => _downloadPdf(provider),
          cs: cs,
        ),
        _buildActionButton(
          icon: _isSharing ? null : Icons.ios_share_rounded,
          isLoading: _isSharing,
          enabled: !_isSharing && !provider.isLoading && provider.hasData,
          onTap: () => _sharePdf(provider),
          cs: cs,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    required bool isLoading,
    required bool enabled,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            child: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: iOSDesignTokens.primary,
                    ),
                  )
                : Icon(
                    icon,
                    size: 21,
                    color: enabled
                        ? iOSDesignTokens.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Filter Card
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildFilterCard(ColorScheme cs, PurchaReportProvider provider) {
    return Consumer<ShopSelectionProvider>(
      builder: (context, shopProvider, _) {
        final shopName = shopProvider.selectedShop?.name ?? 'Select Shop';
        final hasShops = shopProvider.shops.isNotEmpty;

        return Container(
          margin: EdgeInsets.fromLTRB(
            iOSDesignTokens.space16,
            iOSDesignTokens.space8,
            iOSDesignTokens.space16,
            iOSDesignTokens.space4,
          ),
          padding: EdgeInsets.all(iOSDesignTokens.space12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Row 1: Shop + Date
              Row(
                children: [
                  // Shop selector
                  Expanded(
                    child: _buildFilterPill(
                      icon: Icons.store_rounded,
                      label: shopName,
                      color: iOSDesignTokens.primary,
                      onTap: hasShops
                          ? () => _showShopPicker(shopProvider, provider)
                          : null,
                    ),
                  ),
                  SizedBox(width: iOSDesignTokens.space8),
                  // Date picker
                  _buildFilterPill(
                    icon: Icons.calendar_today_rounded,
                    label: DateFormat('dd MMM yyyy').format(provider.selectedDate),
                    color: AppColors.info,
                    onTap: () => _selectDate(provider),
                  ),
                ],
              ),

              SizedBox(height: iOSDesignTokens.space10),

              // Row 2: Category filter segmented control
              _buildSegmentedControl<PurchaCategoryFilter>(
                values: PurchaCategoryFilter.values,
                selected: provider.categoryFilter,
                labelOf: (f) => f.displayName,
                onSelect: (f) {
                  HapticFeedback.selectionClick();
                  provider.setCategoryFilter(f);
                  _loadReport();
                },
                activeColor: iOSDesignTokens.primary,
              ),

              SizedBox(height: iOSDesignTokens.space8),

              // Row 3: View mode + Opening toggle
              Row(
                children: [
                  Expanded(
                    child: _buildSegmentedControl<PurchaViewMode>(
                      values: PurchaViewMode.values,
                      selected: provider.viewMode,
                      labelOf: (m) =>
                          m == PurchaViewMode.flat ? 'Flat' : 'Category',
                      onSelect: (m) {
                        HapticFeedback.selectionClick();
                        provider.setViewMode(m);
                        _loadReport();
                      },
                      activeColor: AppColors.info,
                    ),
                  ),
                  SizedBox(width: iOSDesignTokens.space8),
                  // Opening toggle
                  _buildOpeningToggle(cs, provider),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterPill({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: iOSDesignTokens.space10,
            vertical: iOSDesignTokens.space8,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              SizedBox(width: iOSDesignTokens.space6),
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: iOSDesignTokens.space4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl<T>({
    required List<T> values,
    required T selected,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelect,
    required Color activeColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: values.map((v) {
          final isActive = v == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(v),
              child: AnimatedContainer(
                duration: iOSDesignTokens.durationFast,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive ? activeColor : Colors.transparent,
                  borderRadius:
                      BorderRadius.circular(iOSDesignTokens.radiusSmall - 1),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  labelOf(v),
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.white : cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOpeningToggle(ColorScheme cs, PurchaReportProvider provider) {
    final isOn = provider.showOpening;
    final color = isOn ? AppColors.success : AppColors.warning;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        provider.setShowOpening(!isOn);
      },
      child: AnimatedContainer(
        duration: iOSDesignTokens.durationFast,
        height: 34,
        padding: EdgeInsets.symmetric(horizontal: iOSDesignTokens.space10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOn ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              size: 16,
              color: color,
            ),
            SizedBox(width: iOSDesignTokens.space4),
            Text(
              'Stock',
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 11,
              ),
            ),
            SizedBox(width: iOSDesignTokens.space4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isOn ? 'ON' : 'OFF',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Summary Cards
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSummaryCards(ColorScheme cs, PurchaReportProvider provider) {
    final stats = provider.currentPageStats;
    final saleQty = stats['sale'] as int;
    final saleAmt = stats['amount'] as double;
    final rcptQty = stats['receipt'] as int;
    final closeQty = stats['closing'] as int;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: iOSDesignTokens.space16,
        vertical: iOSDesignTokens.space8,
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard(
              label: 'Sale Qty',
              value: '$saleQty',
              icon: Icons.shopping_bag_rounded,
              color: AppColors.success,
            ),
          ),
          SizedBox(width: iOSDesignTokens.space8),
          Expanded(
            child: _summaryCard(
              label: 'Sale Amount',
              value: _currFmt.format(saleAmt),
              icon: Icons.currency_rupee_rounded,
              color: iOSDesignTokens.primary,
            ),
          ),
          SizedBox(width: iOSDesignTokens.space8),
          Expanded(
            child: _summaryCard(
              label: 'Receipt',
              value: '$rcptQty',
              icon: Icons.inventory_2_rounded,
              color: AppColors.warning,
            ),
          ),
          if (provider.showOpening) ...[
            SizedBox(width: iOSDesignTokens.space8),
            Expanded(
              child: _summaryCard(
                label: 'Closing',
                value: '$closeQty',
                icon: Icons.lock_rounded,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(iOSDesignTokens.space10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          SizedBox(height: iOSDesignTokens.space6),
          Text(
            value,
            style: AppTextStyles.h6.copyWith(
              color: cs.onSurface,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Size Tabs
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSizeTabs(ColorScheme cs, PurchaReportProvider provider) {
    if (provider.availableSizes.isEmpty ||
        _tabController == null ||
        _tabController!.length != provider.availableSizes.length) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: iOSDesignTokens.space16,
        vertical: iOSDesignTokens.space4,
      ),
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: provider.availableSizes.length,
        separatorBuilder: (_, __) => SizedBox(width: iOSDesignTokens.space6),
        itemBuilder: (context, index) {
          final size = provider.availableSizes[index];
          final isSelected = provider.selectedSize == size;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              _tabController!.animateTo(index);
              provider.setSelectedSize(size);
            },
            child: AnimatedContainer(
              duration: iOSDesignTokens.durationFast,
              padding: EdgeInsets.symmetric(
                horizontal: iOSDesignTokens.space16,
                vertical: iOSDesignTokens.space8,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? iOSDesignTokens.primary
                    : cs.surfaceContainerHighest,
                borderRadius:
                    BorderRadius.circular(iOSDesignTokens.radiusSmall),
                border: isSelected
                    ? null
                    : Border.all(color: cs.outline.withValues(alpha: 0.15)),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color:
                              iOSDesignTokens.primary.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  size,
                  style: AppTextStyles.captionBold.copyWith(
                    color: isSelected ? Colors.white : cs.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Data Table
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDataTable(ColorScheme cs, PurchaReportProvider provider) {
    final page = provider.currentPage;
    if (page == null) return const SizedBox.shrink();

    final showOpening = provider.showOpening;

    // Collect rows
    final List<_TableRow> rows = [];
    int serial = 0;

    for (final category in page.categories) {
      final activeItems = category.items.where(_hasActivity).toList()
        ..sort((a, b) {
          final pc = a.rate.compareTo(b.rate);
          return pc != 0 ? pc : a.brandName.compareTo(b.brandName);
        });

      if (activeItems.isEmpty) continue;

      if (provider.viewMode == PurchaViewMode.category) {
        rows.add(_TableRow.header(category.categoryName, activeItems.length));
      }

      for (final item in activeItems) {
        serial++;
        rows.add(_TableRow.data(serial, item));
      }
    }

    return Container(
      margin: EdgeInsets.fromLTRB(
        iOSDesignTokens.space16,
        iOSDesignTokens.space8,
        iOSDesignTokens.space16,
        0,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          _buildTableHeaderRow(cs, showOpening),
          // Rows
          ...rows.map((r) => r.isHeader
              ? _buildCategoryHeaderRow(cs, r.categoryName!, r.itemCount!)
              : _buildDataRow(cs, r.serial!, r.item!, showOpening)),
          // Grand Total
          _buildGrandTotalRow(cs, provider),
        ],
      ),
    );
  }

  Widget _buildTableHeaderRow(ColorScheme cs, bool showOpening) {
    return Container(
      color: iOSDesignTokens.primary.withValues(alpha: 0.08),
      padding: EdgeInsets.symmetric(
        horizontal: iOSDesignTokens.space8,
        vertical: iOSDesignTokens.space10,
      ),
      child: Row(
        children: [
          _hdrCell('#', 26),
          _hdrCellFlex('Brand Name'),
          if (showOpening) _hdrCell('Open', 38),
          _hdrCell('Rcpt', 36),
          if (showOpening) _hdrCell('Total', 38),
          _hdrCell('Sale', 38),
          _hdrCell('Rate', 42),
          _hdrCell('Amt', 54),
          if (showOpening) _hdrCell('Close', 38),
        ],
      ),
    );
  }

  Widget _hdrCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: AppTextStyles.overline.copyWith(
          color: iOSDesignTokens.primary,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _hdrCellFlex(String text) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(
          text,
          style: AppTextStyles.overline.copyWith(
            color: iOSDesignTokens.primary,
            fontWeight: FontWeight.w700,
            fontSize: 9,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryHeaderRow(
      ColorScheme cs, String name, int count) {
    return Container(
      color: AppColors.info.withValues(alpha: 0.06),
      padding: EdgeInsets.symmetric(
        horizontal: iOSDesignTokens.space10,
        vertical: iOSDesignTokens.space6,
      ),
      child: Row(
        children: [
          Icon(Icons.category_rounded, size: 13, color: AppColors.info),
          SizedBox(width: iOSDesignTokens.space6),
          Expanded(
            child: Text(
              name.toUpperCase(),
              style: AppTextStyles.overline.copyWith(
                color: AppColors.info,
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.info,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(
      ColorScheme cs, int serial, PurchaReportItem item, bool showOpening) {
    final isEven = serial % 2 == 0;
    final hasSale = item.sale > 0;

    return Container(
      decoration: BoxDecoration(
        color: isEven
            ? cs.surfaceContainerHighest.withValues(alpha: 0.3)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.06)),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: iOSDesignTokens.space8,
        vertical: iOSDesignTokens.space6,
      ),
      child: Row(
        children: [
          // Serial
          SizedBox(
            width: 26,
            child: Text(
              '$serial',
              style: _cellTextStyle(cs).copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Brand name
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                item.brandName,
                style: _cellTextStyle(cs).copyWith(fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Opening
          if (showOpening)
            SizedBox(
              width: 38,
              child: Text(_fmtQty(item.openingStock),
                  style: _cellTextStyle(cs), textAlign: TextAlign.center),
            ),
          // Receipt
          SizedBox(
            width: 36,
            child: Text(
              _fmtQty(item.receipt),
              style: _cellTextStyle(cs).copyWith(
                color: item.receipt > 0 ? AppColors.warning : cs.onSurfaceVariant,
                fontWeight: item.receipt > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Total
          if (showOpening)
            SizedBox(
              width: 38,
              child: Text(_fmtQty(item.total),
                  style: _cellTextStyle(cs), textAlign: TextAlign.center),
            ),
          // Sale
          SizedBox(
            width: 38,
            child: Container(
              padding: hasSale
                  ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
                  : null,
              decoration: hasSale
                  ? BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                _fmtQty(item.sale),
                style: _cellTextStyle(cs).copyWith(
                  fontWeight: hasSale ? FontWeight.w700 : FontWeight.normal,
                  color: hasSale ? AppColors.success : cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Rate
          SizedBox(
            width: 42,
            child: Text(
              _fmtRate(item.rate),
              style: _cellTextStyle(cs).copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          // Amount
          SizedBox(
            width: 54,
            child: Text(
              item.amount == 0 ? '-' : item.amount.toStringAsFixed(0),
              style: _cellTextStyle(cs).copyWith(
                fontWeight: item.amount > 0 ? FontWeight.w700 : FontWeight.normal,
                color: item.amount > 0
                    ? iOSDesignTokens.primary
                    : cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Closing
          if (showOpening)
            SizedBox(
              width: 38,
              child: Text(_fmtQty(item.closingStock),
                  style: _cellTextStyle(cs), textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  TextStyle _cellTextStyle(ColorScheme cs) {
    return TextStyle(
      fontSize: 11,
      color: cs.onSurface,
    );
  }

  Widget _buildGrandTotalRow(ColorScheme cs, PurchaReportProvider provider) {
    final stats = provider.currentPageStats;
    final showOpening = provider.showOpening;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: iOSDesignTokens.space8,
        vertical: iOSDesignTokens.space10,
      ),
      decoration: BoxDecoration(
        color: iOSDesignTokens.primary.withValues(alpha: 0.06),
        border: Border(
          top: BorderSide(
            color: iOSDesignTokens.primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 26),
          Expanded(
            child: Text(
              'GRAND TOTAL',
              style: AppTextStyles.captionBold.copyWith(
                color: iOSDesignTokens.primary,
                fontSize: 11,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (showOpening)
            SizedBox(
              width: 38,
              child: Text(
                _fmtQty(stats['opening'] as int),
                style: _totalTextStyle(),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 36,
            child: Text(
              _fmtQty(stats['receipt'] as int),
              style: _totalTextStyle(),
              textAlign: TextAlign.center,
            ),
          ),
          if (showOpening)
            SizedBox(
              width: 38,
              child: Text(
                _fmtQty(stats['total'] as int),
                style: _totalTextStyle(),
                textAlign: TextAlign.center,
              ),
            ),
          SizedBox(
            width: 38,
            child: Text(
              _fmtQty(stats['sale'] as int),
              style: _totalTextStyle().copyWith(color: AppColors.success),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 42),
          SizedBox(
            width: 54,
            child: Text(
              (stats['amount'] as double) == 0
                  ? '-'
                  : (stats['amount'] as double).toStringAsFixed(0),
              style: _totalTextStyle().copyWith(color: iOSDesignTokens.primary),
              textAlign: TextAlign.center,
            ),
          ),
          if (showOpening)
            SizedBox(
              width: 38,
              child: Text(
                _fmtQty(stats['closing'] as int),
                style: _totalTextStyle(),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  TextStyle _totalTextStyle() {
    return const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
    );
  }

  bool _hasActivity(PurchaReportItem item) {
    return item.openingStock > 0 ||
        item.receipt > 0 ||
        item.sale > 0 ||
        item.closingStock > 0 ||
        item.total > 0 ||
        item.amount > 0;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Empty / Error States
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(iOSDesignTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.inbox_rounded,
                  size: 32, color: cs.onSurfaceVariant),
            ),
            SizedBox(height: iOSDesignTokens.space16),
            Text(
              'No Data Available',
              style: AppTextStyles.h5.copyWith(color: cs.onSurface),
            ),
            SizedBox(height: iOSDesignTokens.space8),
            Text(
              'Select a shop and date to view the purchase report.',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(ColorScheme cs, PurchaReportProvider provider) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(iOSDesignTokens.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  Icon(Icons.error_outline_rounded, size: 32, color: AppColors.error),
            ),
            SizedBox(height: iOSDesignTokens.space16),
            Text(
              'Unable to Load Report',
              style: AppTextStyles.h5.copyWith(color: cs.onSurface),
            ),
            SizedBox(height: iOSDesignTokens.space8),
            Text(
              provider.error ?? 'An error occurred',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: iOSDesignTokens.space20),
            FilledButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: iOSDesignTokens.primary,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(iOSDesignTokens.radiusSmall),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Shop Picker
  // ═══════════════════════════════════════════════════════════════════════

  void _showShopPicker(
      ShopSelectionProvider shopProvider, PurchaReportProvider reportProvider) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(iOSDesignTokens.radiusSheet),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Title
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: iOSDesignTokens.space16,
                    vertical: iOSDesignTokens.space8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: iOSDesignTokens.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.store_rounded,
                            size: 18, color: iOSDesignTokens.primary),
                      ),
                      SizedBox(width: iOSDesignTokens.space12),
                      Text(
                        'Select Shop',
                        style: AppTextStyles.h5.copyWith(color: cs.onSurface),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 18, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: cs.outline.withValues(alpha: 0.1)),
                // List
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(
                      horizontal: iOSDesignTokens.space12,
                      vertical: iOSDesignTokens.space8,
                    ),
                    itemCount: shopProvider.shops.length,
                    itemBuilder: (context, index) {
                      final shop = shopProvider.shops[index];
                      final isSelected =
                          shop.id == shopProvider.selectedShopId;

                      return Padding(
                        padding: EdgeInsets.only(
                            bottom: iOSDesignTokens.space6),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                                iOSDesignTokens.radiusMedium),
                            onTap: () async {
                              await shopProvider.selectShop(shop);
                              reportProvider.setSelectedShop(shop.id);
                              if (mounted) {
                                Navigator.pop(ctx);
                                _loadReport();
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.all(iOSDesignTokens.space12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? iOSDesignTokens.primary
                                        .withValues(alpha: 0.08)
                                    : cs.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(
                                    iOSDesignTokens.radiusMedium),
                                border: isSelected
                                    ? Border.all(
                                        color: iOSDesignTokens.primary
                                            .withValues(alpha: 0.3))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? iOSDesignTokens.primary
                                              .withValues(alpha: 0.15)
                                          : cs.surfaceContainerHighest,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.store_rounded,
                                      color: isSelected
                                          ? iOSDesignTokens.primary
                                          : cs.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: iOSDesignTokens.space12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shop.name,
                                          style: AppTextStyles.bodyMedium
                                              .copyWith(
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? iOSDesignTokens.primary
                                                : cs.onSurface,
                                          ),
                                        ),
                                        if (shop.address.isNotEmpty)
                                          Text(
                                            shop.address,
                                            style: AppTextStyles.caption
                                                .copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded,
                                        color: iOSDesignTokens.primary,
                                        size: 22),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: iOSDesignTokens.space16),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Date Picker
  // ═══════════════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════════════
  // PDF Download / Share
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _downloadPdf(PurchaReportProvider provider) async {
    if (provider.report == null || _isDownloading) return;

    setState(() => _isDownloading = true);
    HapticFeedback.mediumImpact();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                  'Generating PDF${provider.showOpening ? '' : ' (compact)'}...'),
            ],
          ),
          duration: const Duration(seconds: 30),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    try {
      final file = await PurchaPdfGenerator.generateAndSave(
        provider.report!,
        showOpening: provider.showOpening,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF saved: ${file.path.split('/').last}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
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
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
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

      final file = await PurchaPdfGenerator.generateAndSave(
        provider.report!,
        showOpening: provider.showOpening,
      );

      if (mounted) setState(() => _isSharing = false);

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
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Internal row model for the table
// ═══════════════════════════════════════════════════════════════════════

class _TableRow {
  final bool isHeader;
  final String? categoryName;
  final int? itemCount;
  final int? serial;
  final PurchaReportItem? item;

  _TableRow._({
    required this.isHeader,
    this.categoryName,
    this.itemCount,
    this.serial,
    this.item,
  });

  factory _TableRow.header(String name, int count) =>
      _TableRow._(isHeader: true, categoryName: name, itemCount: count);

  factory _TableRow.data(int serial, PurchaReportItem item) =>
      _TableRow._(isHeader: false, serial: serial, item: item);
}

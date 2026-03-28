import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../models/batch_ocr_models.dart';
import '../providers/batch_ocr_provider.dart';
import '../widgets/ocr_review_cards.dart';
import 'batch_ocr_success_screen.dart';


/// Modern, consolidated Review & Accept screen
///
/// Replaces: BatchOCRAcceptScreen + SmartMatchingReviewScreen
///
/// Features:
/// - Tab-based filtering (With Stock/Matched/New/All)
/// - Compact stats header with gradient cards
/// - Virtualized list with modern card design
/// - Inline quantity editing
/// - Bulk operations (select all, accept all)
/// - Accept/Reject tracking
/// - Confidence-based color coding
/// - Smooth animations
class SingleModernReviewScreen extends ConsumerStatefulWidget {
  final String shopId;

  const SingleModernReviewScreen({
    super.key,
    required this.shopId,
  });

  @override
  ConsumerState<SingleModernReviewScreen> createState() =>
      _SingleModernReviewScreenState();
}

class _SingleModernReviewScreenState
    extends ConsumerState<SingleModernReviewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<String> _selectedItemIds = {};
  final Map<String, int> _editedQuantities = {};
  final Map<String, String> _editedBrandNames = {}; // Track edited brand names
  final Map<String, double> _editedPrices = {}; // Track edited selling prices

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: 3, // Start with "All" tab to show all extracted items
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kDebugMode) {
        final state = ref.read(batchOCRProvider(widget.shopId));
        final allItems = state.deduplicatedItems ?? [];
        final filteredItems = state.filteredDeduplicatedItems ?? allItems;
        debugPrint('[ReviewScreen] ${filteredItems.length}/${allItems.length} items to display');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(batchOCRProvider(widget.shopId));
    final notifier = ref.read(batchOCRProvider(widget.shopId).notifier);

    final items = state.filteredDeduplicatedItems ?? state.deduplicatedItems ?? [];
    final receiptType = state.receiptType;

    if (items.isEmpty) {
      return _buildEmptyState(cs);
    }

    final filteredItems = _getFilteredItems(items);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.primary,
        title: const Text(
          'Review & Accept',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(receiptType != null ? 198 : 148),
          child: Column(
            children: [
              // Receipt Type Header (if available)
              if (receiptType != null) _buildReceiptTypeHeader(receiptType),
              _buildStatsHeader(items, state),
              _buildTabBar(cs),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildItemsList(_getWithStockItems(items), notifier, cs),
          _buildItemsList(_getMatchedItems(items), notifier, cs),
          _buildItemsList(_getNewItems(items), notifier, cs),
          _buildItemsList(items, notifier, cs),
        ],
      ),
      bottomNavigationBar: _buildBottomActions(notifier, items, cs),
    );
  }

  Widget _buildReceiptTypeHeader(String receiptType) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.9),
            cs.primary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_long,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Receipt Type',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(
    List<DeduplicatedItem> items,
    BatchOCRState state,
  ) {
    final cs = Theme.of(context).colorScheme;
    final accepted = state.acceptedCount;
    final rejected = state.rejectedCount;
    final pending = state.pendingCount;
    final total = items.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary,
            cs.primary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          _buildStatCard(
            label: 'Total',
            value: total.toString(),
            icon: Icons.inventory_2_rounded,
            color: Colors.white,
            gradient: [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.15)],
          ),
          const SizedBox(width: 10),
          _buildStatCard(
            label: 'Accepted',
            value: accepted.toString(),
            icon: Icons.check_circle_rounded,
            color: Colors.greenAccent.shade100,
            gradient: [AppColors.success.withValues(alpha: 0.3), AppColors.success.withValues(alpha: 0.15)],
          ),
          const SizedBox(width: 10),
          _buildStatCard(
            label: 'Rejected',
            value: rejected.toString(),
            icon: Icons.cancel_rounded,
            color: Colors.redAccent.shade100,
            gradient: [AppColors.error.withValues(alpha: 0.3), AppColors.error.withValues(alpha: 0.15)],
          ),
          const SizedBox(width: 10),
          _buildStatCard(
            label: 'Pending',
            value: pending.toString(),
            icon: Icons.pending_rounded,
            color: Colors.amberAccent.shade100,
            gradient: [AppColors.warning.withValues(alpha: 0.3), AppColors.warning.withValues(alpha: 0.15)],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required List<Color> gradient,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: int.tryParse(value) ?? 0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, animatedValue, child) {
                return Text(
                  animatedValue.toString(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: -0.5,
                    height: 1.0,
                  ),
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.95),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: cs.primary,
        unselectedLabelColor: cs.onSurfaceVariant.withValues(alpha: 0.7),
        indicatorColor: cs.primary,
        indicatorWeight: 4,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        tabs: const [
          Tab(text: 'With Stock'),
          Tab(text: 'Matched'),
          Tab(text: 'New'),
          Tab(text: 'All'),
        ],
      ),
    );
  }

  Widget _buildItemsList(
    List<DeduplicatedItem> items,
    BatchOCRNotifier notifier,
    ColorScheme cs,
  ) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No items in this category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Build acceptance and rejection states maps
    final state = ref.watch(batchOCRProvider(widget.shopId));
    final Map<String, bool> acceptanceStates = {};
    final Map<String, bool> rejectionStates = {};

    for (final item in items) {
      final itemId = item.sourceItemIds.isNotEmpty ? item.sourceItemIds.first : '';
      if (itemId.isNotEmpty) {
        final acceptanceState = state.getAcceptanceState(itemId);
        acceptanceStates[itemId] = acceptanceState == ItemAcceptanceState.accepted;
        rejectionStates[itemId] = acceptanceState == ItemAcceptanceState.rejected;
      }
    }

    // Get receipt type from state for proper grouping
    final receiptType = state.receiptType;

    // Use card-based layout
    return OCRReviewCards(
      items: items,
      receiptType: receiptType, // Pass receipt type for proper grouping
      selectedItemIds: _selectedItemIds,
      editedQuantities: _editedQuantities,
      editedBrandNames: _editedBrandNames,
      editedPrices: _editedPrices,
      acceptanceStates: acceptanceStates,
      rejectionStates: rejectionStates,
      onItemSelected: (itemId) {
        setState(() {
          if (_selectedItemIds.contains(itemId)) {
            _selectedItemIds.remove(itemId);
          } else {
            _selectedItemIds.add(itemId);
          }
        });
      },
      onQuantityChanged: (itemId, quantity) {
        setState(() {
          _editedQuantities[itemId] = quantity;
        });
        // Auto-accept when user edits quantity
        if (acceptanceStates[itemId] != true) {
          notifier.acceptItem(itemId);
        }
      },
      onBrandNameChanged: (itemId, brandName) {
        setState(() {
          _editedBrandNames[itemId] = brandName;
        });
      },
      onPriceChanged: (itemId, price) {
        setState(() {
          _editedPrices[itemId] = price;
        });
      },
    );
  }

  Widget _buildBottomActions(
    BatchOCRNotifier notifier,
    List<DeduplicatedItem> items,
    ColorScheme cs,
  ) {
    final state = ref.watch(batchOCRProvider(widget.shopId));
    final hasAccepted = state.hasAcceptedItems;
    final isSelectionMode = _selectedItemIds.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: isSelectionMode
              ? _buildSelectionModeActions(notifier, cs)
              : _buildDefaultActions(notifier, items, hasAccepted, state, cs),
        ),
      ),
    );
  }

  Widget _buildSelectionModeActions(BatchOCRNotifier notifier, ColorScheme cs) {
    final selectedCount = _selectedItemIds.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Info row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '$selectedCount items selected',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Action buttons
        Row(
          children: [
            // Clear button
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedItemIds.clear();
                  });
                },
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                  side: BorderSide(color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Accept button
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Accept all selected items
                  for (final itemId in _selectedItemIds) {
                    notifier.acceptItem(itemId);
                  }

                  // Show success message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Accepted $selectedCount items'),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  // Clear selection
                  setState(() {
                    _selectedItemIds.clear();
                  });
                },
                icon: const Icon(Icons.check, size: 20),
                label: Text('Accept ($selectedCount)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDefaultActions(
    BatchOCRNotifier notifier,
    List<DeduplicatedItem> items,
    bool hasAccepted,
    dynamic state,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        // Select All button
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _selectedItemIds.clear();
              for (final item in items) {
                if (item.sourceItemIds.isNotEmpty) {
                  _selectedItemIds.add(item.sourceItemIds.first);
                }
              }
            });
          },
          icon: const Icon(Icons.select_all, size: 18),
          label: const Text('Select All'),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.primary,
            side: BorderSide(color: cs.primary),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),

        const Spacer(),

        // Create Brands button - Works with one click, auto-accepts all items
        ElevatedButton.icon(
          onPressed: (state.deduplicatedItems?.isNotEmpty ?? false)
              ? () => _handleQuickCreateBrands(notifier, state)
              : null,
          icon: Icon(
            (state.deduplicatedItems?.isNotEmpty ?? false) ? Icons.auto_awesome : Icons.info_outline,
            size: 20,
          ),
          label: Text(
            (state.deduplicatedItems?.isNotEmpty ?? false)
                ? 'Create All Brands (${state.deduplicatedItems?.length ?? 0})'
                : 'No Items Available',
            style: const TextStyle(fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: (state.deduplicatedItems?.isNotEmpty ?? false) ? AppColors.success : cs.onSurfaceVariant,
            foregroundColor: Colors.white,
            disabledBackgroundColor: cs.outlineVariant,
            disabledForegroundColor: cs.onSurfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cs.primary,
        title: const Text('Review & Accept'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        size: 80,
                        color: cs.primary.withValues(alpha: 0.4),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              Text(
                'No items to review',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Process invoice images first to\nextract items for review',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleQuickCreateBrands(BatchOCRNotifier notifier, BatchOCRState state) {
    final cs = Theme.of(context).colorScheme;
    // Auto-accept all items and create brands in one click
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.rocket_launch,
                color: AppColors.success,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Quick Create Brands',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will automatically create brand variants and initialize stock for all ${state.deduplicatedItems?.length ?? 0} items.',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.flash_on,
                    color: AppColors.info,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'One-click process: Auto-accepts all items and creates brands',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Updates stock for existing brands automatically',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Cache context references BEFORE async operation and dialog close
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              navigator.pop(); // Close dialog

              // First, auto-accept all items
              if (state.deduplicatedItems != null) {
                for (final item in state.deduplicatedItems!) {
                  final itemKey = '${item.brandText}_${item.sizeText}';
                  notifier.acceptItem(itemKey);
                }
              }

              // Then create brands immediately
              final result = await notifier.acceptAndCreateAll(
                skipZeroStock: false, // Include all items since user wants one-click
              );

              if (result != null && mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(result.summaryMessage),
                    backgroundColor: result.successCount > 0 ? AppColors.success : AppColors.warning,
                    duration: const Duration(seconds: 5),
                  ),
                );

                // Navigate to success screen if any brands were created
                if (result.successCount > 0 && mounted) {
                  navigator.pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => BatchOCRSuccessScreen(
                        result: result,
                        shopName: 'Current Shop', // Shop name can be fetched from auth provider if needed
                      ),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.rocket_launch, size: 18),
            label: const Text('Create All Brands'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateBrandsDialog(BatchOCRNotifier notifier) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.auto_awesome,
                color: AppColors.success,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Create Brands',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will create brand variants and initialize stock for all accepted items.',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zero stock items will be skipped',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              // Cache context references BEFORE async operation and dialog close
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              navigator.pop(); // Close dialog

              final result = await notifier.acceptAndCreateAll(
                skipZeroStock: true,
              );

              if (result != null && mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(result.summaryMessage),
                    backgroundColor: AppColors.success,
                  ),
                );

                // Navigate back or to success screen
                if (mounted) {
                  navigator.pop();
                }
              }
            },
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Create'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Show dialog to edit brand name
  void _showEditBrandNameDialog(
    BuildContext context,
    DeduplicatedItem item,
    String itemId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final currentName = _editedBrandNames[itemId] ?? item.brandText;
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.edit,
                color: cs.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Edit Brand Name',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Original: ${item.brandText}',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Brand Name',
                hintText: 'Enter corrected brand name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.local_drink, color: cs.primary),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != item.brandText) {
                setState(() {
                  _editedBrandNames[itemId] = newName;
                });
              }
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Show dialog to edit selling price
  void _showEditPriceDialog(
    BuildContext context,
    DeduplicatedItem item,
    String itemId,
  ) {
    final cs = Theme.of(context).colorScheme;
    final currentPrice = _editedPrices[itemId] ?? item.sellingPrice;
    final controller = TextEditingController(
      text: currentPrice?.toStringAsFixed(0) ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.currency_rupee,
                color: AppColors.success,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Edit Selling Price',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.sellingPrice != null)
              Text(
                'Original: ₹${item.sellingPrice!.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Selling Price',
                hintText: 'Enter corrected price',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: Icon(Icons.currency_rupee, color: AppColors.success),
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final newPriceText = controller.text.trim();
              if (newPriceText.isNotEmpty) {
                final newPrice = double.tryParse(newPriceText);
                if (newPrice != null && newPrice > 0) {
                  setState(() {
                    _editedPrices[itemId] = newPrice;
                  });
                  Navigator.pop(context);
                } else {
                  // Show error
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter a valid price'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods

  List<DeduplicatedItem> _getFilteredItems(List<DeduplicatedItem> items) {
    switch (_tabController.index) {
      case 0:
        return _getWithStockItems(items);
      case 1:
        return _getMatchedItems(items);
      case 2:
        return _getNewItems(items);
      case 3:
        return items; // All
      default:
        return items;
    }
  }

  List<DeduplicatedItem> _getWithStockItems(List<DeduplicatedItem> items) {
    return items.where((item) => item.totalStock > 0).toList();
  }

  List<DeduplicatedItem> _getMatchedItems(List<DeduplicatedItem> items) {
    return items.where((item) => item.matchedBrandId != null).toList();
  }

  List<DeduplicatedItem> _getNewItems(List<DeduplicatedItem> items) {
    return items.where((item) => item.matchedBrandId == null).toList();
  }
}

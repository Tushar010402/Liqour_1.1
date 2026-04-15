/// Smart Sale Screen
///
/// Modern, interactive screen for quick sale entry with:
/// - Beer / Non-Beer category selection
/// - Date picker
/// - Shop selector
/// - Size options (for Non-Beer only)
/// - Scan Purchase button for capturing purchase images
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/theme/ios_design_tokens.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../admin/providers/shop_provider.dart';
import '../../admin/models/shop_model.dart';
import '../services/smart_sale_service.dart';
import '../services/smart_sale_draft_service.dart';
import '../models/smart_sale_models.dart';
import '../models/expense_header.dart';

/// Category type for smart sale
enum SaleCategory {
  beer,
  nonBeer,
}

/// Smart Sale Screen with modern interactive UI
class SmartSaleScreen extends StatefulWidget {
  const SmartSaleScreen({super.key});

  @override
  State<SmartSaleScreen> createState() => _SmartSaleScreenState();
}

class _SmartSaleScreenState extends State<SmartSaleScreen> with WidgetsBindingObserver {
  // Selection state
  SaleCategory _selectedCategory = SaleCategory.nonBeer;
  DateTime _selectedDate = DateTime.now();
  Shop? _selectedShop;
  String? _selectedSize; // Single size selection for non-beer

  // Captured images (up to 5)
  final List<File> _capturedImages = [];

  // Loading state
  bool _isLoading = false;
  String _processingStatus = '';

  // Image picker instance
  final ImagePicker _picker = ImagePicker();

  // Smart Sale service
  late SmartSaleService _smartSaleService;

  // Draft persistence service
  final SmartSaleDraftService _draftService = SmartSaleDraftService.instance;

  // === CACHING STATE ===
  // Cached result to avoid re-processing same images
  SmartSaleResult? _cachedResult;

  // Hash of images that were processed (to detect changes)
  String? _processedImagesHash;

  // Draft payment data (persisted across page navigations)
  Map<String, dynamic>? _draftPaymentData;

  // Draft edited quantities
  Map<int, int>? _draftEditedQuantities;

  // Last result for display (legacy - kept for compatibility)
  SmartSaleResult? _lastResult;

  // Current user ID for draft key
  String? _currentUserId;

  // Available drafts for this user
  List<SmartSaleDraft> _availableDrafts = [];

  // Flag to show draft notification
  bool _showDraftNotification = false;

  @override
  void initState() {
    super.initState();
    // Add lifecycle observer for app state changes
    WidgetsBinding.instance.addObserver(this);
    // Initialize service
    _smartSaleService = SmartSaleService(context.read<AuthService>());
    // Initialize draft service FIRST (sets _currentUserId), then load shops
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeDraftService();
      _loadShops();
    });
  }

  /// Initialize draft service and load existing drafts
  Future<void> _initializeDraftService() async {
    try {
      await _draftService.initialize();
      // Get current user ID
      final authService = context.read<AuthService>();
      _currentUserId = await authService.getUserId();

      if (_currentUserId != null) {
        // Load available drafts for this user
        _availableDrafts = await _draftService.getDraftsForUser(_currentUserId!);
        if (_availableDrafts.isNotEmpty && mounted) {
          setState(() => _showDraftNotification = true);
          debugPrint('📦 SmartSale: Found ${_availableDrafts.length} saved drafts');
        }
      }
    } catch (e) {
      debugPrint('⚠️ SmartSale: Draft service initialization error: $e');
    }
  }

  /// Handle app lifecycle changes - auto-save on pause/inactive
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Auto-save draft when app goes to background
      _autoSaveDraft();
    }
  }

  /// Auto-save current state as draft
  Future<void> _autoSaveDraft() async {
    if (_selectedShop == null || _currentUserId == null) return;

    // Only save if we have meaningful data
    if (_cachedResult == null &&
        _draftPaymentData == null &&
        _draftEditedQuantities == null) {
      return;
    }

    try {
      final draft = SmartSaleDraftExtension.fromScreenState(
        userId: _currentUserId!,
        shopId: _selectedShop!.id,
        shopName: _selectedShop!.name,
        saleDate: _selectedDate,
        category: _selectedCategory == SaleCategory.beer ? 'beer' : 'non_beer',
        size: _selectedSize,
        result: _cachedResult,
        currentStep: _draftPaymentData?['current_step'] ?? 0,
        cashAmount: (_draftPaymentData?['cash_amount'] as num?)?.toDouble() ?? 0,
        cardAmount: (_draftPaymentData?['card_amount'] as num?)?.toDouble() ?? 0,
        upiAmount: (_draftPaymentData?['upi_amount'] as num?)?.toDouble() ?? 0,
        creditAmount: (_draftPaymentData?['credit_amount'] as num?)?.toDouble() ?? 0,
        editedQuantities: _draftEditedQuantities,
        expenses: (_draftPaymentData?['expenses'] as List?)?.cast<Map<String, dynamic>>(),
        notes: _draftPaymentData?['notes'] as String? ?? '',
        imagePaths: _capturedImages.map((f) => f.path).toList(),
      );

      await _draftService.saveDraft(draft);
      debugPrint('💾 SmartSale: Auto-saved draft for ${_selectedShop!.name}');
      // Refresh the available drafts list so UI updates
      _refreshAvailableDrafts();
    } catch (e) {
      debugPrint('⚠️ SmartSale: Failed to auto-save draft: $e');
    }
  }

  /// Refresh the available drafts list from storage
  Future<void> _refreshAvailableDrafts() async {
    if (_currentUserId == null) return;
    try {
      final drafts = await _draftService.getDraftsForUser(_currentUserId!);
      if (mounted) {
        setState(() => _availableDrafts = drafts);
      }
    } catch (_) {}
  }

  /// Load draft for current shop and date
  Future<void> _loadDraftForCurrentSelection() async {
    if (_selectedShop == null || _currentUserId == null) return;

    try {
      final draft = await _draftService.getDraftForShopAndDate(
        _currentUserId!,
        _selectedShop!.id,
        _selectedDate,
      );

      if (draft != null && draft.hasData && mounted) {
        // Restore from draft
        setState(() {
          _cachedResult = draft.cachedResult;
          _draftPaymentData = {
            'cash_amount': draft.cashAmount,
            'card_amount': draft.cardAmount,
            'upi_amount': draft.upiAmount,
            'credit_amount': draft.creditAmount,
            'expenses': draft.expenses,
            'notes': draft.notes,
            'current_step': draft.currentStep,
          };
          _draftEditedQuantities = draft.editedQuantitiesAsIntKeys;
          _selectedSize = draft.size;
          _selectedCategory = draft.category == 'beer'
              ? SaleCategory.beer
              : SaleCategory.nonBeer;
        });

        debugPrint('📂 SmartSale: Restored draft for ${_selectedShop!.name}');

        // Show notification about restored draft
        if (mounted) {
          SnackbarHelper.showSuccess(
            context,
            'Previous draft restored for ${_selectedShop!.name}',
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ SmartSale: Failed to load draft: $e');
    }
  }

  Future<void> _loadShops() async {
    final shopProvider = context.read<ShopProvider>();
    if (shopProvider.shops.isEmpty) {
      await shopProvider.loadShops();
    }
    if (mounted && shopProvider.shops.isNotEmpty && _selectedShop == null) {
      setState(() {
        _selectedShop = shopProvider.selectedShop ?? shopProvider.shops.first;
      });
      // Load any existing draft for the auto-selected shop
      _loadDraftForCurrentSelection();
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Auto-save before dispose
    _autoSaveDraft();
    super.dispose();
  }

  /// Handle shop change - load draft for new shop
  void _onShopChanged(Shop? newShop) {
    if (newShop == null || newShop.id == _selectedShop?.id) return;

    // Auto-save current draft before switching
    _autoSaveDraft();

    setState(() {
      _selectedShop = newShop;
      // Clear in-memory cache (will load from draft if available)
      _cachedResult = null;
      _processedImagesHash = null;
      _draftPaymentData = null;
      _draftEditedQuantities = null;
      _capturedImages.clear();
    });

    // Load draft for new shop
    _loadDraftForCurrentSelection();
  }

  /// Handle date change - load draft for new date
  void _onDateChanged(DateTime newDate) {
    if (newDate == _selectedDate) return;

    // Auto-save current draft before switching
    _autoSaveDraft();

    setState(() {
      _selectedDate = newDate;
      // Clear in-memory cache (will load from draft if available)
      _cachedResult = null;
      _processedImagesHash = null;
      _draftPaymentData = null;
      _draftEditedQuantities = null;
      _capturedImages.clear();
    });

    // Load draft for new date
    _loadDraftForCurrentSelection();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: const CustomAppBar(title: 'Smart Sale'),
      body: Column(
        children: [
          // Main content
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(iOSDesignTokens.space16),
              children: [
                // Category Selection (Beer / Non-Beer)
                _buildCategorySelection(),
                SizedBox(height: iOSDesignTokens.space20),

                // Date Selection
                _buildDateSelection(),
                SizedBox(height: iOSDesignTokens.space6),

                // Shop Selection
                _buildShopSelection(),

                // Size Selection (only for Non-Beer)
                if (_selectedCategory == SaleCategory.nonBeer) ...[
                  SizedBox(height: iOSDesignTokens.space20),
                  _buildSizeSelection(),
                ],

                // Captured Images Preview
                if (_capturedImages.isNotEmpty) ...[
                  SizedBox(height: iOSDesignTokens.space20),
                  _buildCapturedImagesSection(),
                ],

                // Continue Review Card (if there's a cached result)
                if (_hasCachedResult()) ...[
                  SizedBox(height: iOSDesignTokens.space20),
                  _buildContinueReviewCard(),
                ],

                // Saved Drafts Section (if user has drafts for other shops/dates)
                if (_availableDrafts.isNotEmpty) ...[
                  SizedBox(height: iOSDesignTokens.space20),
                  _buildSavedDraftsSection(),
                ],

                const SizedBox(height: 100), // Space for bottom button
              ],
            ),
          ),

          // Scan Purchase Button
          _buildScanButton(),
        ],
      ),
    );
  }

  /// Build captured images section showing current images
  Widget _buildCapturedImagesSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.photo_library_outlined,
          title: 'Captured Images',
          subtitle: '${_capturedImages.length}/5 images selected',
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Container(
          padding: EdgeInsets.all(iOSDesignTokens.space12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _capturedImages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: EdgeInsets.only(right: index < _capturedImages.length - 1 ? 8 : 0),
                      child: _buildMiniImageCard(_capturedImages[index], index),
                    );
                  },
                ),
              ),
              SizedBox(height: iOSDesignTokens.space8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap image to view, X to remove',
                      style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _capturedImages.clear();
                        _cachedResult = null;
                        _processedImagesHash = null;
                        _draftPaymentData = null;
                        _draftEditedQuantities = null;
                      });
                      HapticFeedback.mediumImpact();
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // State for showing all drafts
  bool _showAllDrafts = false;

  /// Build Saved Drafts section showing all available drafts for this user
  Widget _buildSavedDraftsSection() {
    final cs = Theme.of(context).colorScheme;
    // Filter out the current shop/date combination (shown in Continue Review card)
    final otherDrafts = _availableDrafts.where((draft) {
      final currentKey = _selectedShop != null
          ? SmartSaleDraft.createKey(_currentUserId!, _selectedShop!.id, _selectedDate)
          : '';
      return draft.key != currentKey;
    }).toList();

    if (otherDrafts.isEmpty) return const SizedBox.shrink();

    // Determine which drafts to show based on _showAllDrafts state
    final draftsToShow = _showAllDrafts ? otherDrafts : otherDrafts.take(3).toList();
    final hasMoreDrafts = otherDrafts.length > 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: CupertinoIcons.doc_on_doc_fill,
          title: 'Saved Drafts',
          subtitle: '${otherDrafts.length} pending ${otherDrafts.length == 1 ? 'draft' : 'drafts'}',
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              ...draftsToShow.map((draft) => _buildDraftItem(draft)),
              // Show "See All" / "Show Less" button if there are more than 3 drafts
              if (hasMoreDrafts)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _showAllDrafts = !_showAllDrafts);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _showAllDrafts ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                          size: 14,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showAllDrafts ? 'Show Less' : 'See All ${otherDrafts.length} Drafts',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Calculate total amount for a draft (considering edited quantities)
  double _calculateDraftTotal(SmartSaleDraft draft) {
    final result = draft.cachedResult;
    if (result == null) return 0;

    // If no items, use stored total
    if (result.extractedItems.isEmpty) {
      return result.totalAmount;
    }

    // Calculate from items with edited quantities
    final editedQty = draft.editedQuantitiesAsIntKeys;
    double total = 0;

    for (int i = 0; i < result.extractedItems.length; i++) {
      final item = result.extractedItems[i];
      final qty = editedQty[i] ?? item.quantity;
      // Use inventory rate (system rate) if available, otherwise use extracted rate
      final rate = item.inventoryRate ?? item.rate;
      if (rate > 0 && qty > 0) {
        total += qty * rate;
      }
    }

    // Fallback to stored total if calculation yields 0
    return total > 0 ? total : result.totalAmount;
  }

  /// Build a single draft item in the saved drafts list
  Widget _buildDraftItem(SmartSaleDraft draft) {
    final cs = Theme.of(context).colorScheme;
    final dateStr = DateFormat('dd MMM').format(draft.saleDate);
    final stepName = ['Items', 'Payment', 'Review'][draft.currentStep.clamp(0, 2)];
    final itemCount = draft.cachedResult?.extractedItems.length ?? 0;
    final total = _calculateDraftTotal(draft);
    final categoryDisplay = draft.category == 'beer' ? 'Beer' : 'Liquor';
    final sizeDisplay = draft.size ?? '';
    final isBeer = draft.category == 'beer';

    return GestureDetector(
      onTap: () => _loadAndNavigateToDraft(draft),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            // Shop icon with category color
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isBeer ? Colors.amber.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                CupertinoIcons.building_2_fill,
                color: isBeer ? Colors.amber[700] : Colors.blue[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Draft info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop name
                  Text(
                    draft.shopName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Date, items, total
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(' • ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text(
                        '$itemCount items',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      if (total > 0) ...[
                        Text(' • ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text(
                          '₹${total.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Category and Size tags
                  Row(
                    children: [
                      // Category tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isBeer ? Colors.amber.withValues(alpha: 0.15) : Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          categoryDisplay,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isBeer ? Colors.amber[800] : Colors.purple[700],
                          ),
                        ),
                      ),
                      if (sizeDisplay.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        // Size tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            sizeDisplay,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.teal[700],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Step badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                stepName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange[700],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 16),
          ],
        ),
      ),
    );
  }

  /// Load a draft and navigate to its result page
  Future<void> _loadAndNavigateToDraft(SmartSaleDraft draft) async {
    // Find the shop for this draft
    final shopProvider = context.read<ShopProvider>();
    final shop = shopProvider.shops.firstWhere(
      (s) => s.id == draft.shopId,
      orElse: () => Shop(
        id: draft.shopId,
        name: draft.shopName,
        address: '',
        phone: '',
        licenseNumber: '',
        isActive: true,
      ),
    );

    // Update current selection
    setState(() {
      _selectedShop = shop;
      _selectedDate = draft.saleDate;
      _selectedCategory = draft.category == 'beer' ? SaleCategory.beer : SaleCategory.nonBeer;
      _selectedSize = draft.size;
      _cachedResult = draft.cachedResult;
      _draftPaymentData = {
        'cash_amount': draft.cashAmount,
        'card_amount': draft.cardAmount,
        'upi_amount': draft.upiAmount,
        'credit_amount': draft.creditAmount,
        'expenses': draft.expenses,
        'notes': draft.notes,
        'current_step': draft.currentStep,
      };
      _draftEditedQuantities = draft.editedQuantitiesAsIntKeys;
    });

    // Navigate to result page if we have a cached result
    if (draft.cachedResult != null) {
      _navigateToResultPage(draft.cachedResult!);
    }
  }

  /// Build Continue Review card when there's a cached result
  Widget _buildContinueReviewCard() {
    if (_cachedResult == null) return const SizedBox.shrink();

    final stepName = _draftPaymentData != null
        ? (_draftPaymentData!['current_step'] == 1
            ? 'Payment'
            : _draftPaymentData!['current_step'] == 2
                ? 'Final Review'
                : 'Items Review')
        : 'Items Review';

    return GestureDetector(
      onTap: () => _navigateToResultPage(_cachedResult!),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.withValues(alpha: 0.1), Colors.green.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(CupertinoIcons.arrow_right_circle_fill, color: Colors.green[700], size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Continue Review',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Draft Saved',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_cachedResult!.extractedItems.length} items • ₹${_cachedResult!.totalAmount.toStringAsFixed(0)} • Step: $stepName',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: Colors.green[700], size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniImageCard(File imageFile, int index) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showFullImagePreview(imageFile),
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                imageFile,
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Image number
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Remove button
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _capturedImages.removeAt(index);
                });
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImagePreview(File imageFile) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Stack(
              children: [
                // Image with zoom
                Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.file(
                      imageFile,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                // Close button
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.close, size: 24),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Header is now handled by CustomAppBar in build()

  Widget _buildCategorySelection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.label_outlined,
          title: 'Category',
          subtitle: 'Select product category',
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: cs.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildCategorySegment(
                category: SaleCategory.beer,
                label: 'Beer',
              ),
              _buildCategorySegment(
                category: SaleCategory.nonBeer,
                label: 'Non-Beer',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySegment({
    required SaleCategory category,
    required String label,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedCategory == category;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            _selectedCategory = category;
            if (category == SaleCategory.beer) {
              _selectedSize = null;
            }
          });
        },
        child: AnimatedContainer(
          duration: iOSDesignTokens.durationMedium,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? cs.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelection() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showDatePicker,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: iOSDesignTokens.space12,
              vertical: iOSDesignTokens.space12,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.primary.withValues(alpha: 0.06),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.calendar_today_outlined, color: cs.primary, size: 20),
                ),
                SizedBox(width: iOSDesignTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('dd MMMM, yyyy').format(_selectedDate),
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('EEEE').format(_selectedDate),
                        style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShopSelection() {
    final cs = Theme.of(context).colorScheme;
    return Consumer<ShopProvider>(
      builder: (context, shopProvider, child) {
        return Padding(
          padding: EdgeInsets.only(bottom: iOSDesignTokens.space6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showShopPicker(shopProvider.shops),
              borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: iOSDesignTokens.space12,
                  vertical: iOSDesignTokens.space12,
                ),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.primary.withValues(alpha: 0.15),
                            cs.primary.withValues(alpha: 0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.store_outlined, color: cs.primary, size: 20),
                    ),
                    SizedBox(width: iOSDesignTokens.space12),
                    Expanded(
                      child: shopProvider.isLoading
                          ? Text(
                              'Loading shops...',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedShop?.name ?? 'Tap to select shop',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _selectedShop != null
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Selected Shop',
                                  style: AppTextStyles.caption.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ],
                            ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSizeSelection() {
    final cs = Theme.of(context).colorScheme;
    final sizes = ProductConstants.spiritSizes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          icon: Icons.straighten_outlined,
          title: 'Size',
          subtitle: 'Select bottle size',
        ),
        SizedBox(height: iOSDesignTokens.space8),
        Container(
          padding: EdgeInsets.all(iOSDesignTokens.space12),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(iOSDesignTokens.radiusMedium),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sizes.map((size) => _buildSizeChip(size)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSizeChip(String size) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _selectedSize == size;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedSize = isSelected ? null : size;
        });
      },
      child: AnimatedContainer(
        duration: iOSDesignTokens.durationMedium,
        width: 85,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? cs.primary : cs.surface,
          borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
          border: Border.all(
            color: isSelected ? cs.primary : cs.outline.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            size,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: iOSDesignTokens.space8),
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildScanButton() {
    final cs = Theme.of(context).colorScheme;
    final isReady = _selectedShop != null;
    final hasImages = _capturedImages.isNotEmpty;
    final canAddMore = _capturedImages.length < 5;

    return Container(
      padding: EdgeInsets.all(iOSDesignTokens.space16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outline.withValues(alpha: 0.1))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Summary row
            if (isReady)
              Container(
                padding: EdgeInsets.all(iOSDesignTokens.space10),
                margin: EdgeInsets.only(bottom: iOSDesignTokens.space10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.primary, size: 16),
                    SizedBox(width: iOSDesignTokens.space8),
                    Expanded(
                      child: Text(
                        '${_selectedCategory == SaleCategory.beer ? "Beer" : "Non-Beer"} \u2022 ${DateFormat('dd/MM').format(_selectedDate)} \u2022 ${_selectedShop?.name ?? ""}${_selectedSize != null ? " \u2022 $_selectedSize" : ""}',
                        style: AppTextStyles.caption.copyWith(color: cs.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // If has images, show submit button prominently
            if (hasImages) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: !_isLoading ? _submitImages : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    disabledBackgroundColor: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    disabledForegroundColor: cs.onSurfaceVariant,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            ),
                            if (_processingStatus.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Text(
                                _processingStatus,
                                style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                              ),
                            ],
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.send_outlined, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Submit ${_capturedImages.length} Image${_capturedImages.length > 1 ? 's' : ''}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              if (canAddMore) ...[
                SizedBox(height: iOSDesignTokens.space8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: !_isLoading ? _openCamera : null,
                          icon: Icon(Icons.camera_alt_outlined, size: 18, color: cs.primary),
                          label: Text('Camera', style: AppTextStyles.bodySmall.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall)),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: iOSDesignTokens.space8),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: !_isLoading ? _pickFromGallery : null,
                          icon: Icon(Icons.photo_library_outlined, size: 18, color: cs.primary),
                          label: Text('Gallery', style: AppTextStyles.bodySmall.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusSmall)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ] else ...[
              // Camera and Gallery buttons when no images
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: isReady && !_isLoading ? _openCamera : null,
                        icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
                        label: Text(
                          'Scan',
                          style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                          disabledBackgroundColor: cs.onSurfaceVariant.withValues(alpha: 0.2),
                          disabledForegroundColor: cs.onSurfaceVariant,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(iOSDesignTokens.radiusButton)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: iOSDesignTokens.space8),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: isReady && !_isLoading ? _pickFromGallery : null,
                        icon: Icon(Icons.photo_library_outlined, size: 20, color: isReady ? cs.primary : cs.onSurfaceVariant),
                        label: Text(
                          'Gallery',
                          style: AppTextStyles.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isReady ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isReady ? cs.primary : cs.outlineVariant,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            if (!isReady)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Please select a shop to continue',
                  style: TextStyle(fontSize: 12, color: Colors.red[400]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDatePicker() async {
    final cs = Theme.of(context).colorScheme;
    HapticFeedback.selectionClick();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: cs.copyWith(
              primary: cs.primary,
              onPrimary: cs.onPrimary,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      _onDateChanged(picked);
    }
  }

  void _showShopPicker(List<Shop> shops) {
    final cs = Theme.of(context).colorScheme;
    HapticFeedback.selectionClick();
    if (shops.isEmpty) {
      SnackbarHelper.showWarning(context, 'No shops available');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Shop',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Shop list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: shops.length,
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  final isSelected = _selectedShop?.id == shop.id;

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                      // Use the new handler that loads drafts
                      _onShopChanged(shop);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary.withValues(alpha: 0.1)
                            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? cs.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primary
                                  : Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.store,
                              color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shop.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurface,
                                  ),
                                ),
                                if (shop.address.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    shop.address,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              ),
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

  /// Open camera to capture a single image
  Future<void> _openCamera() async {
    if (_selectedShop == null) {
      SnackbarHelper.showWarning(context, 'Please select a shop first');
      return;
    }

    if (_capturedImages.length >= 5) {
      SnackbarHelper.showWarning(context, 'Maximum 5 images allowed');
      return;
    }

    HapticFeedback.mediumImpact();

    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 1920,
      );

      if (!mounted) return;

      if (image != null) {
        setState(() {
          _capturedImages.add(File(image.path));
        });
        HapticFeedback.lightImpact();
        SnackbarHelper.showSuccess(context, 'Image captured (${_capturedImages.length}/5)');
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Camera error: $e');
      }
    }
  }

  /// Pick images from gallery
  Future<void> _pickFromGallery() async {
    if (_selectedShop == null) {
      SnackbarHelper.showWarning(context, 'Please select a shop first');
      return;
    }

    if (_capturedImages.length >= 5) {
      SnackbarHelper.showWarning(context, 'Maximum 5 images allowed');
      return;
    }

    HapticFeedback.mediumImpact();

    try {
      final int remainingSlots = 5 - _capturedImages.length;

      final List<XFile> pickedFiles = await _picker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 1920,
        limit: remainingSlots,
      );

      if (!mounted) return;

      if (pickedFiles.isNotEmpty) {
        final newImages = pickedFiles.map((xFile) => File(xFile.path)).toList();

        // Add only up to the limit
        final int canAdd = 5 - _capturedImages.length;
        final imagesToAdd = newImages.take(canAdd).toList();

        setState(() {
          _capturedImages.addAll(imagesToAdd);
        });

        HapticFeedback.lightImpact();
        SnackbarHelper.showSuccess(
          context,
          '${imagesToAdd.length} image${imagesToAdd.length > 1 ? 's' : ''} added (${_capturedImages.length}/5)',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Gallery error: $e');
      }
    }
  }

  /// Submit captured images to backend
  Future<void> _submitImages() async {
    final cs = Theme.of(context).colorScheme;
    if (_capturedImages.isEmpty) {
      SnackbarHelper.showWarning(context, 'Please capture at least one image');
      return;
    }

    if (_selectedShop == null) {
      SnackbarHelper.showWarning(context, 'Please select a shop');
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(CupertinoIcons.paperplane_fill, color: cs.primary),
            const SizedBox(width: 12),
            const Text('Submit Images?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are about to submit ${_capturedImages.length} image${_capturedImages.length > 1 ? 's' : ''} for processing.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildConfirmRow('Category', _selectedCategory == SaleCategory.beer ? 'Beer' : 'Non-Beer'),
                  const SizedBox(height: 8),
                  _buildConfirmRow('Date', DateFormat('dd MMM, yyyy').format(_selectedDate)),
                  const SizedBox(height: 8),
                  _buildConfirmRow('Shop', _selectedShop?.name ?? '-'),
                  if (_selectedSize != null) ...[
                    const SizedBox(height: 8),
                    _buildConfirmRow('Size', _selectedSize!),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Submit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _submitImagesToBackend(_capturedImages);
  }

  Widget _buildConfirmRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  /// Compute a hash of images to detect if they've changed
  String _computeImagesHash(List<File> images) {
    // Use file paths and modification times to create a hash
    final paths = images.map((f) => '${f.path}:${f.lengthSync()}').join('|');
    return paths.hashCode.toString();
  }

  /// Check if we have a valid cached result for the current images
  bool _hasCachedResult() {
    if (_cachedResult == null || _processedImagesHash == null) return false;
    final currentHash = _computeImagesHash(_capturedImages);
    return currentHash == _processedImagesHash;
  }

  Future<void> _submitImagesToBackend(List<File> images) async {
    if (_selectedShop == null) {
      SnackbarHelper.showError(context, 'Please select a shop');
      return;
    }

    // Check if we have a cached result for the same images
    final currentHash = _computeImagesHash(images);
    if (_cachedResult != null && _processedImagesHash == currentHash) {
      debugPrint('📦 Smart Sale - Using cached result (images unchanged)');
      _navigateToResultPage(_cachedResult!);
      return;
    }

    setState(() {
      _isLoading = true;
      _processingStatus = 'Starting...';
    });

    // Keep screen awake during AI processing
    try { await WakelockPlus.enable(); } catch (_) {}

    try {
      debugPrint('📤 Smart Sale - Processing ${images.length} images');

      final result = await _smartSaleService.processSmartSale(
        images: images,
        shopId: _selectedShop!.id,
        shopName: _selectedShop!.name,
        date: _selectedDate,
        category: _selectedCategory == SaleCategory.beer ? 'beer' : 'non_beer',
        size: _selectedSize,
        onProgress: (current, total, status) {
          if (mounted) {
            setState(() => _processingStatus = status);
          }
        },
      );

      if (!mounted) return;

      if (result.success && result.data != null) {
        final smartResult = result.data!;
        setState(() {
          _lastResult = smartResult;
          // Cache the result
          _cachedResult = smartResult;
          _processedImagesHash = currentHash;
        });

        // Auto-save draft immediately so it persists
        _autoSaveDraft();

        // Navigate to result page
        _navigateToResultPage(smartResult);
      } else {
        SnackbarHelper.showError(context, result.error ?? 'Processing failed');
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.showError(context, 'Error: $e');
      }
    } finally {
      try { await WakelockPlus.disable(); } catch (_) {}
      if (mounted) {
        setState(() {
          _isLoading = false;
          _processingStatus = '';
        });
      }
    }
  }

  /// Navigate to full-page result screen
  void _navigateToResultPage(SmartSaleResult result) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SmartSaleResultPage(
          result: result,
          selectedSize: _selectedSize,
          shopId: _selectedShop?.id ?? '',
          shopName: _selectedShop?.name ?? '',
          selectedDate: _selectedDate,
          smartSaleService: _smartSaleService,
          // Pass draft data if available
          initialPaymentData: _draftPaymentData,
          initialEditedQuantities: _draftEditedQuantities,
          // Callback to save draft
          onDraftSaved: (paymentData, editedQuantities) {
            setState(() {
              _draftPaymentData = paymentData;
              _draftEditedQuantities = editedQuantities;
            });
          },
        ),
      ),
    ).then((success) {
      // If sale was submitted successfully, clear everything
      if (success == true) {
        // Delete the draft from persistent storage
        if (_currentUserId != null && _selectedShop != null) {
          final key = SmartSaleDraft.createKey(
            _currentUserId!, _selectedShop!.id, _selectedDate,
          );
          _draftService.deleteDraft(key);
        }
        setState(() {
          _capturedImages.clear();
          _cachedResult = null;
          _processedImagesHash = null;
          _draftPaymentData = null;
          _draftEditedQuantities = null;
          _selectedSize = null;
        });
        // Refresh available drafts list
        _refreshAvailableDrafts();
      }
    });
  }

}

/// Full-page widget for Smart Sale Result with editable sale quantities
/// and multi-step review & submit flow (Items → Payment → Review → Submit)
class SmartSaleResultPage extends StatefulWidget {
  final SmartSaleResult result;
  final String? selectedSize;
  final String shopId;
  final String shopName;
  final DateTime selectedDate;
  final SmartSaleService smartSaleService;

  // Draft data for persistence across navigations
  final Map<String, dynamic>? initialPaymentData;
  final Map<int, int>? initialEditedQuantities;

  // Callback to save draft data when user navigates back
  final void Function(Map<String, dynamic> paymentData, Map<int, int> editedQuantities)? onDraftSaved;

  const SmartSaleResultPage({
    super.key,
    required this.result,
    this.selectedSize,
    required this.shopId,
    required this.shopName,
    required this.selectedDate,
    required this.smartSaleService,
    this.initialPaymentData,
    this.initialEditedQuantities,
    this.onDraftSaved,
  });

  @override
  State<SmartSaleResultPage> createState() => _SmartSaleResultPageState();
}

class _SmartSaleResultPageState extends State<SmartSaleResultPage> with WidgetsBindingObserver {
  // Editable sale quantities map: index -> quantity
  late Map<int, int> _editedQuantities;
  late Map<int, TextEditingController> _quantityControllers;

  // Scroll controller for the page
  final ScrollController _scrollController = ScrollController();

  // Step navigation: 0=items, 1=payment, 2=review
  int _currentStep = 0;

  // Payment breakdown
  double _cashAmount = 0;
  double _cardAmount = 0;
  double _upiAmount = 0;
  double _creditAmount = 0;

  // Payment text controllers
  late TextEditingController _cashController;
  late TextEditingController _cardController;
  late TextEditingController _upiController;
  late TextEditingController _creditController;

  // Expenses
  List<Map<String, dynamic>> _expenses = [];
  String _notes = '';
  late TextEditingController _notesController;

  // Expense form controllers (for adding new expense)
  late TextEditingController _expenseHeaderController;
  late TextEditingController _expenseAmountController;
  final FocusNode _expenseAmountFocusNode = FocusNode();

  // Submission
  bool _isSubmitting = false;

  // Draft persistence service
  final SmartSaleDraftService _draftService = SmartSaleDraftService.instance;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    // Add lifecycle observer for app state changes
    WidgetsBinding.instance.addObserver(this);

    // Initialize quantity controllers from initial data or defaults
    _editedQuantities = widget.initialEditedQuantities != null
        ? Map<int, int>.from(widget.initialEditedQuantities!)
        : {};
    _quantityControllers = {};

    for (int i = 0; i < widget.result.extractedItems.length; i++) {
      final item = widget.result.extractedItems[i];
      // Use initial edited quantity if available, otherwise use item quantity
      _editedQuantities[i] = _editedQuantities[i] ?? item.quantity;
      _quantityControllers[i] = TextEditingController(text: '${_editedQuantities[i]}');
    }

    // Initialize payment data from saved draft or defaults
    if (widget.initialPaymentData != null) {
      _cashAmount = (widget.initialPaymentData!['cash_amount'] as num?)?.toDouble() ?? 0;
      _cardAmount = (widget.initialPaymentData!['card_amount'] as num?)?.toDouble() ?? 0;
      _upiAmount = (widget.initialPaymentData!['upi_amount'] as num?)?.toDouble() ?? 0;
      _creditAmount = (widget.initialPaymentData!['credit_amount'] as num?)?.toDouble() ?? 0;
      _expenses = (widget.initialPaymentData!['expenses'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _notes = widget.initialPaymentData!['notes'] as String? ?? '';
      _currentStep = widget.initialPaymentData!['current_step'] as int? ?? 0;
    }

    // Initialize payment controllers with saved values
    _cashController = TextEditingController(text: _cashAmount > 0 ? _cashAmount.toStringAsFixed(0) : '');
    _cardController = TextEditingController(text: _cardAmount > 0 ? _cardAmount.toStringAsFixed(0) : '');
    _upiController = TextEditingController(text: _upiAmount > 0 ? _upiAmount.toStringAsFixed(0) : '');
    _creditController = TextEditingController(text: _creditAmount > 0 ? _creditAmount.toStringAsFixed(0) : '');
    _notesController = TextEditingController(text: _notes);
    _expenseHeaderController = TextEditingController();
    _expenseAmountController = TextEditingController();

    // Get user ID for draft persistence
    _initializeUserId();
  }

  /// Initialize user ID for draft persistence
  Future<void> _initializeUserId() async {
    try {
      final authService = context.read<AuthService>();
      _currentUserId = await authService.getUserId();
    } catch (e) {
      debugPrint('⚠️ SmartSaleResultPage: Failed to get user ID: $e');
    }
  }

  /// Handle app lifecycle changes - auto-save on pause/inactive
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Auto-save draft when app goes to background
      _saveDraftToPersistentStorage();
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    _cashController.dispose();
    _cardController.dispose();
    _upiController.dispose();
    _creditController.dispose();
    _notesController.dispose();
    _expenseHeaderController.dispose();
    _expenseAmountController.dispose();
    _expenseAmountFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Save draft data to in-memory state (callback to parent)
  void _saveDraft() {
    widget.onDraftSaved?.call(
      {
        'cash_amount': _cashAmount,
        'card_amount': _cardAmount,
        'upi_amount': _upiAmount,
        'credit_amount': _creditAmount,
        'expenses': _expenses,
        'notes': _notes,
        'current_step': _currentStep,
      },
      _editedQuantities,
    );
  }

  /// Save draft to persistent storage (survives app close)
  Future<void> _saveDraftToPersistentStorage() async {
    if (_currentUserId == null || widget.shopId.isEmpty) return;

    try {
      final draft = SmartSaleDraftExtension.fromScreenState(
        userId: _currentUserId!,
        shopId: widget.shopId,
        shopName: widget.shopName,
        saleDate: widget.selectedDate,
        category: widget.result.extractedItems.isNotEmpty
            ? widget.result.extractedItems.first.category
            : 'non_beer',
        size: widget.selectedSize ?? widget.result.detectedSize,
        result: widget.result,
        currentStep: _currentStep,
        cashAmount: _cashAmount,
        cardAmount: _cardAmount,
        upiAmount: _upiAmount,
        creditAmount: _creditAmount,
        editedQuantities: _editedQuantities,
        expenses: _expenses,
        notes: _notes,
      );

      await _draftService.saveDraft(draft);
      debugPrint('💾 SmartSaleResultPage: Draft saved to persistent storage');
    } catch (e) {
      debugPrint('⚠️ SmartSaleResultPage: Failed to save draft: $e');
    }
  }

  /// Handle back navigation with draft saving
  void _handleBack() {
    _saveDraft();
    _saveDraftToPersistentStorage();
    Navigator.of(context).pop();
  }

  // Helper to check if an item matches the selected size
  bool _itemMatchesSelectedSize(SmartSaleExtractedItem item) {
    final selectedSize = widget.selectedSize ?? widget.result.detectedSize;
    if (selectedSize == null || selectedSize.trim().isEmpty) return true; // No size filter, include all

    final itemSize = item.size?.toUpperCase().replaceAll(' ', '');
    final targetSize = selectedSize.toUpperCase().replaceAll(' ', '');
    // Treat null or empty size as "no size info" → include the item
    return itemSize == null || itemSize.isEmpty || itemSize == targetSize;
  }

  // Calculate total amount based on edited quantities (only for matching size)
  double get _totalAmount {
    double total = 0;
    for (int i = 0; i < widget.result.extractedItems.length; i++) {
      final item = widget.result.extractedItems[i];
      if (!_itemMatchesSelectedSize(item)) continue; // Skip non-matching sizes

      final qty = _editedQuantities[i] ?? item.quantity;
      if (qty <= 0) continue; // Skip 0 quantity items

      // Use system/inventory rate if available, otherwise use OCR rate
      final rate = item.inventoryRate ?? item.rate;
      total += qty * rate;
    }
    return total;
  }

  // Calculate total sale quantity (only for matching size)
  int get _totalSaleQty {
    int total = 0;
    for (int i = 0; i < widget.result.extractedItems.length; i++) {
      final item = widget.result.extractedItems[i];
      if (!_itemMatchesSelectedSize(item)) continue; // Skip non-matching sizes

      final qty = _editedQuantities[i] ?? item.quantity;
      if (qty > 0) total += qty;
    }
    return total;
  }

  // Count items that will be submitted (matching size with qty > 0)
  int get _submittableItemCount {
    int count = 0;
    for (int i = 0; i < widget.result.extractedItems.length; i++) {
      final item = widget.result.extractedItems[i];
      if (!_itemMatchesSelectedSize(item)) continue;

      final qty = _editedQuantities[i] ?? item.quantity;
      if (qty > 0) count++;
    }
    return count;
  }

  // Count items matching the selected size filter (for header display)
  int get _filteredItemCount {
    return widget.result.extractedItems
        .where((item) => _itemMatchesSelectedSize(item))
        .length;
  }

  // Calculate total payment
  double get _totalPayment => _cashAmount + _cardAmount + _upiAmount + _creditAmount;

  // Calculate total expenses
  double get _totalExpenses {
    return _expenses.fold(0.0, (sum, exp) => sum + (exp['amount'] as double? ?? 0));
  }

  // Calculate net amount (total minus expenses = what needs to be accounted via payment)
  double get _netAmount => _totalAmount - _totalExpenses;

  // Calculate balance (how much more needs to be paid after expenses)
  double get _balanceDue => _netAmount - _totalPayment;

  // Check if payment is balanced
  bool get _isPaymentBalanced => (_balanceDue).abs() < 0.01;

  // Auto-distribute remaining amount to cash (accounts for expenses)
  void _autoDistributePayment() {
    final remaining = _netAmount - (_cardAmount + _upiAmount + _creditAmount);
    setState(() {
      _cashAmount = remaining > 0 ? remaining : 0;
      _cashController.text = _cashAmount > 0 ? _cashAmount.toStringAsFixed(0) : '';
    });
    HapticFeedback.mediumImpact();
  }

  // Add expense
  void _addExpense() {
    final header = _expenseHeaderController.text.trim();
    final amountText = _expenseAmountController.text.trim();

    if (header.isEmpty || amountText.isEmpty) {
      SnackbarHelper.showError(context, 'Please enter expense header and amount');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      SnackbarHelper.showError(context, 'Please enter a valid amount');
      return;
    }

    setState(() {
      // Use header_id (snake_case) and header_name for backend compatibility
      final headerId = header.toLowerCase().replaceAll(' ', '_');
      final expenseEntry = {
        'header_id': headerId,
        'header_name': header,
        'amount': amount,
      };
      debugPrint('💰 [AddExpense] Adding: $expenseEntry');
      _expenses.add(expenseEntry);
      _expenseHeaderController.clear();
      _expenseAmountController.clear();
    });
    HapticFeedback.lightImpact();
  }

  // Remove expense
  void _removeExpense(int index) {
    setState(() {
      _expenses.removeAt(index);
    });
    HapticFeedback.lightImpact();
  }

  // Handle next step
  void _handleNextStep() {
    if (_currentStep == 0) {
      // Moving from Items to Payment
      setState(() => _currentStep = 1);
      HapticFeedback.mediumImpact();
    } else if (_currentStep == 1) {
      // Validate payment before moving to Review
      if (!_isPaymentBalanced) {
        SnackbarHelper.showError(
          context,
          'Payment does not match total. Balance: ₹${_balanceDue.toStringAsFixed(0)}',
        );
        return;
      }
      setState(() => _currentStep = 2);
      HapticFeedback.mediumImpact();
    } else if (_currentStep == 2) {
      // Submit
      _submitSale();
    }
  }

  // Get button label for current step
  String _getNextButtonLabel() {
    switch (_currentStep) {
      case 0:
        return 'Continue to Payment';
      case 1:
        return 'Review & Submit';
      case 2:
        return 'Submit Sale';
      default:
        return 'Next';
    }
  }

  // Submit sale to backend
  Future<void> _submitSale() async {
    setState(() => _isSubmitting = true);

    try {
      final selectedSize = widget.selectedSize ?? widget.result.detectedSize;

      // Debug: Log ALL extracted items before filtering
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('📋 ALL EXTRACTED ITEMS: ${widget.result.extractedItems.length} total');
      debugPrint('   Selected Size: $selectedSize');
      for (int i = 0; i < widget.result.extractedItems.length; i++) {
        final item = widget.result.extractedItems[i];
        final qty = _editedQuantities[i] ?? item.quantity;
        debugPrint('   [$i] ${item.brandName} | size="${item.size}" | qty=$qty | matchesSize=${_itemMatchesSelectedSize(item)}');
      }
      debugPrint('═══════════════════════════════════════════════════');

      // Build items list — include ALL items that pass the same filter as display
      final items = <Map<String, dynamic>>[];
      int skippedZeroQty = 0;
      int skippedSizeMismatch = 0;

      for (int idx = 0; idx < widget.result.extractedItems.length; idx++) {
        final item = widget.result.extractedItems[idx];
        final editedQty = _editedQuantities[idx] ?? item.quantity;

        // Skip items with 0 quantity
        if (editedQty <= 0) {
          skippedZeroQty++;
          continue;
        }

        // Use the SAME size filter as display — ensures what user sees = what gets submitted
        if (!_itemMatchesSelectedSize(item)) {
          debugPrint('⚠️ Skipping item [$idx] "${item.brandName}" - size "${item.size}" does not match "$selectedSize"');
          skippedSizeMismatch++;
          continue;
        }

        // Use system/inventory rate if available, otherwise use OCR rate
        // This matches what the user sees in the items step display
        final resolvedRate = item.inventoryRate ?? item.rate;

        items.add({
          'product_id': item.productId,
          'brand_name': item.brandName,
          'size': (item.size != null && item.size!.isNotEmpty) ? item.size : selectedSize,
          'category': item.category,
          'quantity': editedQty,
          'rate': resolvedRate,
          'amount': editedQty * resolvedRate,
          'opening_stock': item.opening,
          'receipt': item.receiptQty,
          'total_stock': item.total,
          'closing_stock': item.total - editedQty,
          // Alias learning fields — backend uses these to improve future matching
          'ocr_text': item.ocrText ?? item.brandName,
          'was_corrected': false, // Flutter doesn't have alternative selection UI yet
        });
      }

      debugPrint('📦 Items: ${items.length} included, $skippedZeroQty zero-qty, $skippedSizeMismatch size-mismatch');

      // Calculate actual items total from submitted items
      double actualItemsTotal = 0;
      for (final item in items) {
        actualItemsTotal += (item['amount'] as num).toDouble();
      }

      debugPrint('📦 Submitting ${items.length} items (skipped $skippedZeroQty zero-qty, $skippedSizeMismatch size-mismatch)');
      debugPrint('📦 Actual items total: ₹$actualItemsTotal');

      // Calculate totals for submission
      // Backend expects: cash + card + upi + credit == total_amount
      // Since backend doesn't deduct expenses, we add expenses to cash for validation
      final totalExpensesAmount = _totalExpenses;

      // Adjust payment: add expenses to cash so backend validation passes
      // Backend sees: cash_amount includes expenses paid out
      // Business logic: Cash collected = user entered cash + expenses paid
      final adjustedCashAmount = _cashAmount + totalExpensesAmount;

      final request = {
        'shop_id': widget.shopId,
        'shop_name': widget.shopName,
        'date': DateFormat('yyyy-MM-dd').format(widget.selectedDate),
        'items': items,
        'total_amount': actualItemsTotal,       // Backend validates: sum(items) == this
        'gross_amount': actualItemsTotal,       // Same as total_amount
        'total_expense_amount': totalExpensesAmount,  // Backend field name for expenses
        'net_amount': _cashAmount + _cardAmount + _upiAmount + _creditAmount, // User's entered payment
        'cash_amount': adjustedCashAmount,      // Cash + expenses (for backend validation)
        'card_amount': _cardAmount,
        'upi_amount': _upiAmount,
        'credit_amount': _creditAmount,
        'expenses': _expenses,                  // Itemized expenses list
        'notes': _notes.trim(),
        'smart_sale_id': widget.result.saleRecordId,
        'size': widget.selectedSize ?? widget.result.detectedSize,
      };

      final userEnteredPayment = _cashAmount + _cardAmount + _upiAmount + _creditAmount;
      final backendPayment = adjustedCashAmount + _cardAmount + _upiAmount + _creditAmount;

      debugPrint('📤 Submitting finalized sale:');
      debugPrint('   Items Total: ₹$actualItemsTotal');
      debugPrint('   Expenses: ₹$totalExpensesAmount (${_expenses.length} items)');
      // Debug: Log each expense entry to verify format
      for (var i = 0; i < _expenses.length; i++) {
        debugPrint('   💰 Expense[$i]: ${_expenses[i]}');
      }
      debugPrint('   ─────────────────────────────────');
      debugPrint('   User Entered: Cash=₹$_cashAmount, Card=₹$_cardAmount, UPI=₹$_upiAmount, Credit=₹$_creditAmount = ₹$userEnteredPayment');
      debugPrint('   Backend Sees: Cash=₹$adjustedCashAmount (includes ₹$totalExpensesAmount expenses)');
      debugPrint('   Backend Total: ₹$backendPayment');
      debugPrint('   ─────────────────────────────────');
      debugPrint('   Backend Validation: payment($backendPayment) == total_amount($actualItemsTotal) ${backendPayment == actualItemsTotal ? "✓" : "✗"}');

      final result = await widget.smartSaleService.submitFinalizedSale(request);

      if (result.success) {
        if (mounted) {
          Navigator.pop(context, true); // Return success
          SnackbarHelper.showSuccess(context, 'Sale submitted successfully!');
        }
      } else {
        if (mounted) {
          SnackbarHelper.showError(context, result.error ?? 'Submission failed');
        }
      }
    } catch (e) {
      debugPrint('❌ Submit error: $e');
      if (mounted) {
        SnackbarHelper.showError(context, 'Error submitting sale: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(CupertinoIcons.chevron_back, color: cs.onSurface),
            onPressed: _handleBack,
          ),
          title: Text(
            _getAppBarTitle(),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
          actions: [
            // Show draft saved indicator
            if (_currentStep > 0 || _editedQuantities.values.any((q) => q > 0))
              Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.checkmark_circle_fill, size: 14, color: Colors.green[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Auto-saved',
                      style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            // Header with step context
            _buildHeader(),

            // Step indicator
            _buildStepIndicator(),

            const Divider(height: 1),

            // Step content
            Expanded(
              child: _currentStep == 0
                  ? _buildItemsStep()
                  : _currentStep == 1
                      ? _buildPaymentStep()
                      : _buildReviewStep(),
            ),

            // Bottom actions
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentStep) {
      case 0:
        return 'Review Items';
      case 1:
        return 'Payment';
      case 2:
        return 'Confirm Sale';
      default:
        return 'Smart Sale';
    }
  }

  /// Build header based on current step
  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    String title;
    String subtitle;
    IconData icon;
    Color iconColor;

    switch (_currentStep) {
      case 0:
        title = 'Review Items';
        subtitle = '${widget.shopName} • $_filteredItemCount items • ₹${_totalAmount.toStringAsFixed(0)}';
        icon = CupertinoIcons.doc_text_search;
        iconColor = cs.primary;
        break;
      case 1:
        title = 'Payment Breakdown';
        subtitle = '${widget.shopName} • Total: ₹${_totalAmount.toStringAsFixed(0)}';
        icon = CupertinoIcons.creditcard;
        iconColor = Colors.green;
        break;
      case 2:
        title = 'Final Review';
        subtitle = '${widget.shopName} • Confirm and submit';
        icon = CupertinoIcons.checkmark_seal;
        iconColor = Colors.blue;
        break;
      default:
        title = 'Smart Sale';
        subtitle = '';
        icon = CupertinoIcons.sparkles;
        iconColor = cs.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Show detected size from AI or user-selected size
          if (widget.result.detectedSize != null || widget.selectedSize != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.result.detectedSize != null
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.result.detectedSize != null)
                    Icon(CupertinoIcons.sparkles, size: 12, color: Colors.green[700]),
                  if (widget.result.detectedSize != null)
                    const SizedBox(width: 4),
                  Text(
                    widget.result.detectedSize ?? widget.selectedSize!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.result.detectedSize != null ? Colors.green[700] : Colors.blue[700],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Build step indicator (Items → Payment → Review)
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildStepDot(0, 'Items'),
          _buildStepLine(0),
          _buildStepDot(1, 'Payment'),
          _buildStepLine(1),
          _buildStepDot(2, 'Review'),
        ],
      ),
    );
  }

  Widget _buildStepDot(int step, String label) {
    final cs = Theme.of(context).colorScheme;
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isActive ? cs.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: isCurrent ? Border.all(color: cs.primary, width: 2) : null,
              boxShadow: isCurrent
                  ? [BoxShadow(color: cs.primary.withValues(alpha: 0.3), blurRadius: 8)]
                  : null,
            ),
            child: Center(
              child: isActive && !isCurrent
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isActive ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? cs.primary : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(int afterStep) {
    final cs = Theme.of(context).colorScheme;
    final isCompleted = _currentStep > afterStep;

    return Container(
      height: 2,
      width: 30,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isCompleted ? cs.primary : Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  /// Build Items Step (Step 0)
  Widget _buildItemsStep() {
    // Filter items to only show size-matching items
    final filteredEntries = <MapEntry<int, SmartSaleExtractedItem>>[];
    int excludedCount = 0;
    for (int i = 0; i < widget.result.extractedItems.length; i++) {
      final item = widget.result.extractedItems[i];
      if (_itemMatchesSelectedSize(item)) {
        filteredEntries.add(MapEntry(i, item));
      } else {
        excludedCount++;
      }
    }

    return Column(
      children: [
        // Validation Warnings Section (Yellow banner for discrepancies)
        if (widget.result.validation != null && widget.result.validation!.hasWarnings)
          _buildValidationWarningsSection(),

        // Size filter exclusion notice
        if (excludedCount > 0)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.info_circle_fill, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$excludedCount items hidden (different size than ${widget.selectedSize ?? widget.result.detectedSize})',
                    style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

        // Items List (only size-matching items)
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: filteredEntries.length + 1, // +1 for total row
            itemBuilder: (context, index) {
              if (index == filteredEntries.length) {
                return _buildTotalCard();
              }
              final entry = filteredEntries[index];
              return _buildItemCard(entry.key, entry.value);
            },
          ),
        ),
      ],
    );
  }

  /// Build Payment Step (Step 1)
  Widget _buildPaymentStep() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Amount Card (read-only)
          _buildTotalAmountCard(),

          const SizedBox(height: 20),

          // Payment Grid
          Text(
            'Payment Breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),

          // 2x2 Payment Grid
          Row(
            children: [
              Expanded(child: _buildPaymentField('Cash', _cashController, (v) {
                setState(() => _cashAmount = double.tryParse(v) ?? 0);
              }, CupertinoIcons.money_dollar)),
              const SizedBox(width: 12),
              Expanded(child: _buildPaymentField('Card', _cardController, (v) {
                setState(() => _cardAmount = double.tryParse(v) ?? 0);
              }, CupertinoIcons.creditcard)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildPaymentField('UPI', _upiController, (v) {
                setState(() => _upiAmount = double.tryParse(v) ?? 0);
              }, CupertinoIcons.device_phone_portrait)),
              const SizedBox(width: 12),
              Expanded(child: _buildPaymentField('Credit', _creditController, (v) {
                setState(() => _creditAmount = double.tryParse(v) ?? 0);
              }, CupertinoIcons.person_crop_circle)),
            ],
          ),

          const SizedBox(height: 16),

          // Balance indicator
          _buildBalanceStatus(),

          const SizedBox(height: 12),

          // Auto-distribute button
          Center(
            child: TextButton.icon(
              onPressed: _autoDistributePayment,
              icon: const Icon(CupertinoIcons.wand_stars, size: 18),
              label: const Text('Auto-fill Cash'),
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Expenses section (collapsible)
          _buildExpensesSection(),

          const SizedBox(height: 24),

          // Notes field
          Text(
            'Notes (Optional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add any notes for this sale...',
              hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.primary),
              ),
            ),
            onChanged: (v) => _notes = v,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildTotalAmountCard() {
    final cs = Theme.of(context).colorScheme;
    final hasExpenses = _totalExpenses > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary.withValues(alpha: 0.1), cs.primary.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(CupertinoIcons.cart_fill, color: cs.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasExpenses ? 'Net Amount (after expenses)' : 'Total Amount',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${_netAmount.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$_filteredItemCount',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Items',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          // Show breakdown when expenses exist
          if (hasExpenses) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(CupertinoIcons.equal, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        '₹${_totalAmount.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        ' (sales)',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(CupertinoIcons.minus, size: 14, color: Colors.red[400]),
                      const SizedBox(width: 6),
                      Text(
                        '₹${_totalExpenses.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.red[600],
                        ),
                      ),
                      Text(
                        ' (exp)',
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build sale items list in invoice format with opening and closing stock
  Widget _buildSaleItemsList({bool initiallyExpanded = true}) {
    final cs = Theme.of(context).colorScheme;
    final selectedSize = widget.selectedSize ?? widget.result.detectedSize;

    // Filter items with quantity > 0 AND matching size
    final saleItems = <MapEntry<int, SmartSaleExtractedItem>>[];
    final sizeMismatchItems = <MapEntry<int, SmartSaleExtractedItem>>[];

    for (int i = 0; i < widget.result.extractedItems.length; i++) {
      final item = widget.result.extractedItems[i];
      final qty = _editedQuantities[i] ?? item.quantity;

      if (qty > 0) {
        if (_itemMatchesSelectedSize(item)) {
          saleItems.add(MapEntry(i, item));
        } else {
          sizeMismatchItems.add(MapEntry(i, item));
        }
      }
    }

    debugPrint('📋 _buildSaleItemsList: Found ${saleItems.length} items matching size, ${sizeMismatchItems.length} size mismatches (total: ${widget.result.extractedItems.length})');

    if (saleItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No items with sale quantity. Go back to add quantities.',
                style: TextStyle(fontSize: 13, color: Colors.orange[800]),
              ),
            ),
          ],
        ),
      );
    }

    // Calculate totals for all columns (only matching items)
    int totalOpening = 0;
    int totalSale = 0;
    int totalClosing = 0;
    double totalAmount = 0;

    for (final itemEntry in saleItems) {
      final item = itemEntry.value;
      final itemIndex = itemEntry.key;
      final qty = _editedQuantities[itemIndex] ?? item.quantity;
      final closingStock = item.total - qty;
      // Use system/inventory rate if available, matching items step display
      final resolvedRate = item.inventoryRate ?? item.rate;

      totalOpening += item.opening;
      totalSale += qty;
      totalClosing += closingStock;
      totalAmount += qty * resolvedRate;
    }

    return Column(
      children: [
        // Size mismatch warning
        if (sizeMismatchItems.isNotEmpty && selectedSize != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange[700], size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${sizeMismatchItems.length} items excluded (different size than $selectedSize)',
                    style: TextStyle(fontSize: 12, color: Colors.orange[800], fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

        // Items list
        Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.1), cs.primary.withValues(alpha: 0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(CupertinoIcons.doc_text_fill, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Sale Items',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${saleItems.length} items',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Table header: # | Brand | Open | Sale | Rate | Amount | Close
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                ),
                Expanded(
                  child: Text('Brand Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                ),
                SizedBox(
                  width: 38,
                  child: Text('Open', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.blue[700])),
                ),
                SizedBox(
                  width: 38,
                  child: Text('Sale', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.orange[700])),
                ),
                SizedBox(
                  width: 48,
                  child: Text('Rate', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                ),
                SizedBox(
                  width: 70,
                  child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.green[700])),
                ),
                SizedBox(
                  width: 38,
                  child: Text('Close', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.purple[700])),
                ),
              ],
            ),
          ),
          // Items list: Open → Sale → Rate → Amount → Close
          ...saleItems.asMap().entries.map((entry) {
            final index = entry.key;
            final itemEntry = entry.value;
            final itemIndex = itemEntry.key;
            final item = itemEntry.value;
            final qty = _editedQuantities[itemIndex] ?? item.quantity;
            // Use system/inventory rate if available, matching items step display
            final itemResolvedRate = item.inventoryRate ?? item.rate;
            final amount = qty * itemResolvedRate;

            // Calculate opening and closing stock
            final openingStock = item.opening;
            final closingStock = item.total - qty;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: index.isEven ? Theme.of(context).colorScheme.surface : Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // #
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                  // Brand - allow 2 lines for full name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.brandName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.size != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.size!,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Opening Stock
                  SizedBox(
                    width: 38,
                    child: Text(
                      '$openingStock',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                  // Sale Quantity
                  SizedBox(
                    width: 38,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '$qty',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ),
                  // Rate (uses system/inventory rate if available)
                  SizedBox(
                    width: 48,
                    child: Text(
                      '₹${itemResolvedRate.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  // Amount
                  SizedBox(
                    width: 70,
                    child: Text(
                      '₹${amount.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green[700]),
                    ),
                  ),
                  // Closing Stock
                  SizedBox(
                    width: 38,
                    child: Text(
                      '$closingStock',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: closingStock < 0 ? Colors.red[700] : Colors.purple[700],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          // Total row with all column totals
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.withValues(alpha: 0.15), Colors.green.withValues(alpha: 0.05)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border(
                top: BorderSide(color: Colors.green.withValues(alpha: 0.4), width: 2),
              ),
            ),
            child: Row(
              children: [
                // # (empty)
                const SizedBox(width: 26),
                // TOTAL label
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(CupertinoIcons.sum, size: 12, color: Colors.green[700]),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'TOTAL',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                    ],
                  ),
                ),
                // Opening Total
                SizedBox(
                  width: 38,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$totalOpening',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ),
                ),
                // Sale Total
                SizedBox(
                  width: 38,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$totalSale',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[800],
                      ),
                    ),
                  ),
                ),
                // Rate (dash)
                SizedBox(
                  width: 48,
                  child: Text(
                    '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                // Amount Total
                SizedBox(
                  width: 70,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '₹${totalAmount.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ),
                ),
                // Closing Total
                SizedBox(
                  width: 38,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '$totalClosing',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: totalClosing < 0 ? Colors.red[800] : Colors.purple[800],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ), // End of Container (items list)
      ], // End of Column (wrapper with warning)
    ); // End of return Column
  }

  Widget _buildPaymentField(String label, TextEditingController controller, Function(String) onChanged, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    // Check if field has value for styling
    final hasValue = controller.text.isNotEmpty && controller.text != '0';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasValue ? cs.primary.withValues(alpha: 0.5) : Theme.of(context).colorScheme.outlineVariant,
          width: hasValue ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: hasValue
                ? cs.primary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon and label
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: hasValue
                      ? cs.primary.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: hasValue ? cs.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: hasValue ? cs.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Input field with underline
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Text(
                  '₹',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: hasValue ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: hasValue ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) {
                      onChanged(v);
                      // Trigger rebuild for styling
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceStatus() {
    final isBalanced = _isPaymentBalanced;
    final balance = _balanceDue;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isBalanced
            ? Colors.green.withValues(alpha: 0.1)
            : balance > 0
                ? Colors.orange.withValues(alpha: 0.1)
                : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBalanced
              ? Colors.green.withValues(alpha: 0.5)
              : balance > 0
                  ? Colors.orange.withValues(alpha: 0.5)
                  : Colors.red.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isBalanced
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.exclamationmark_circle_fill,
            color: isBalanced ? Colors.green : balance > 0 ? Colors.orange : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isBalanced
                  ? 'Payment Balanced'
                  : balance > 0
                      ? 'Remaining: ₹${balance.toStringAsFixed(0)}'
                      : 'Overpaid: ₹${(-balance).toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isBalanced ? Colors.green[700] : balance > 0 ? Colors.orange[700] : Colors.red[700],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${_totalPayment.toStringAsFixed(0)} / ₹${_netAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (_totalExpenses > 0)
                Text(
                  '(₹${_totalAmount.toStringAsFixed(0)} - ₹${_totalExpenses.toStringAsFixed(0)} exp)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpensesSection() {
    final cs = Theme.of(context).colorScheme;
    // Get predefined expense headers
    final defaultHeaders = ExpenseHeader.defaultHeaders.where((h) => h.isActive).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.minus_circle, color: Colors.red[600], size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Expenses',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              if (_expenses.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '₹${_totalExpenses.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[700],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Quick Select Expense Headers - Compact Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: defaultHeaders.map((header) {
              // Check if this header is already added (support both old 'header' and new 'header_name')
              final isAdded = _expenses.any(
                (e) => ((e['header_name'] ?? e['header']) as String).toLowerCase() == header.name.toLowerCase(),
              );

              return GestureDetector(
                onTap: isAdded
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _expenseHeaderController.text = header.name;
                        setState(() {}); // Update UI to show selected state
                        // Focus on expense amount field (not payment boxes)
                        _expenseAmountFocusNode.requestFocus();
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAdded
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : _expenseHeaderController.text == header.name
                            ? cs.primary.withValues(alpha: 0.1)
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isAdded
                          ? Theme.of(context).colorScheme.outlineVariant
                          : _expenseHeaderController.text == header.name
                              ? cs.primary.withValues(alpha: 0.5)
                              : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getExpenseIcon(header.id),
                        size: 14,
                        color: isAdded
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : _expenseHeaderController.text == header.name
                                ? cs.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        header.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isAdded
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : _expenseHeaderController.text == header.name
                                  ? cs.primary
                                  : Theme.of(context).colorScheme.onSurface,
                          decoration: isAdded ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (isAdded) ...[
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.checkmark_circle_fill, size: 12, color: Colors.green[400]),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Expense list
          if (_expenses.isNotEmpty) ...[
            ...List.generate(_expenses.length, (index) {
              final expense = _expenses[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.doc_text, color: Colors.red[400], size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (expense['header_name'] ?? expense['header']) as String,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${(expense['amount'] as double).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.red[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _removeExpense(index),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(CupertinoIcons.xmark, color: Colors.red[600], size: 16),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],

          // Add expense form - compact
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                // Description input
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _expenseHeaderController,
                    decoration: InputDecoration(
                      hintText: 'Expense name',
                      hintStyle: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                // Amount input
                Expanded(
                  child: TextField(
                    controller: _expenseAmountController,
                    focusNode: _expenseAmountFocusNode,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '₹0',
                      hintStyle: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: cs.primary),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                // Add button
                GestureDetector(
                  onTap: _addExpense,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(CupertinoIcons.plus, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Get icon for expense header
  IconData _getExpenseIcon(String headerId) {
    switch (headerId) {
      case 'godam_charges':
        return CupertinoIcons.cube_box;
      case 'transport':
        return CupertinoIcons.car_detailed;
      case 'license_fee':
        return CupertinoIcons.doc_text;
      case 'staff_salary':
        return CupertinoIcons.person_2;
      case 'shop_rent':
        return CupertinoIcons.house;
      case 'utilities':
        return CupertinoIcons.bolt;
      case 'breakage':
        return CupertinoIcons.bandage;
      default:
        return CupertinoIcons.tag;
    }
  }

  /// Build Review Step (Step 2)
  Widget _buildReviewStep() {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Invoice Header
          _buildInvoiceHeader(),

          const SizedBox(height: 16),

          // Sale Items List (expanded by default on review page)
          _buildSaleItemsList(initiallyExpanded: true),

          const SizedBox(height: 16),

          // Payment Breakdown Card
          _buildPaymentSummaryCard(),

          // Expenses Card (if any)
          if (_expenses.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildExpensesSummaryCard(),
          ],

          // Notes (if any)
          if (_notes.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildNotesSummaryCard(),
          ],

          // Validation Warnings (if any)
          if (widget.result.validation?.hasWarnings == true) ...[
            const SizedBox(height: 16),
            _buildValidationWarningSummary(),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.building_2_fill, color: cs.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.shopName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      DateFormat('EEEE, dd MMM yyyy').format(widget.selectedDate),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (widget.selectedSize != null || widget.result.detectedSize != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.result.detectedSize ?? widget.selectedSize!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSummaryCard() {
    // Calculate totals only for items matching the selected size filter
    final filteredItems = widget.result.extractedItems.where((item) => _itemMatchesSelectedSize(item)).toList();
    final totalOpening = filteredItems.fold<int>(0, (sum, item) => sum + item.opening);
    final totalClosing = totalOpening - _totalSaleQty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.cube_box, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Items Summary',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryCell('Items', '${filteredItems.length}'),
              _buildSummaryCell('Opening', '$totalOpening'),
              _buildSummaryCell('Sale Qty', '$_totalSaleQty', isHighlight: true),
              _buildSummaryCell('Closing', '$totalClosing', isNegative: totalClosing < 0),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Sale Amount',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '₹${_totalAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCell(String label, String value, {bool isHighlight = false, bool isNegative = false}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isHighlight
                  ? cs.primary.withValues(alpha: 0.1)
                  : isNegative
                      ? Colors.red.withValues(alpha: 0.1)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isHighlight ? cs.primary : isNegative ? Colors.red : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.creditcard, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Payment Breakdown',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_cashAmount > 0) _buildPaymentRow('Cash', _cashAmount, CupertinoIcons.money_dollar),
          if (_cardAmount > 0) _buildPaymentRow('Card', _cardAmount, CupertinoIcons.creditcard),
          if (_upiAmount > 0) _buildPaymentRow('UPI', _upiAmount, CupertinoIcons.device_phone_portrait),
          if (_creditAmount > 0) _buildPaymentRow('Credit', _creditAmount, CupertinoIcons.person_crop_circle),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Payment',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                '₹${_totalPayment.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(String label, double amount, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildExpensesSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.minus_circle, color: Colors.red[400], size: 18),
              const SizedBox(width: 8),
              const Text(
                'Expenses',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '₹${_totalExpenses.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.red[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_expenses.length, (index) {
            final expense = _expenses[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    (expense['header_name'] ?? expense['header']) as String,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  Text(
                    '₹${(expense['amount'] as double).toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 13, color: Colors.red[600], fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNotesSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.doc_text, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _notes,
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationWarningSummary() {
    final validation = widget.result.validation!;
    final warnings = <String>[];

    if (validation.stockDiscrepancies > 0) {
      warnings.add('${validation.stockDiscrepancies} stock discrepancies');
    }
    if (validation.amountMismatches > 0) {
      warnings.add('${validation.amountMismatches} amount mismatches');
    }
    if (!validation.shopNameMatch && validation.detectedShopName != null) {
      warnings.add('Shop name mismatch');
    }
    if (!validation.dateMatch && validation.detectedDate != null) {
      warnings.add('Date mismatch');
    }

    if (warnings.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.amber[700], size: 18),
              const SizedBox(width: 8),
              Text(
                'Warnings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...warnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.amber[700],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      w,
                      style: TextStyle(fontSize: 13, color: Colors.amber[800]),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// Build bottom actions with step navigation
  Widget _buildBottomActions() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Left button: Close/Back
            if (_currentStep > 0)
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => setState(() => _currentStep--),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.chevron_left, size: 16, color: Theme.of(context).colorScheme.onSurface),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _handleBack,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ),
              ),

            const SizedBox(width: 12),

            // Right button: Next/Submit
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleNextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentStep == 2 ? Colors.green : cs.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _getNextButtonLabel(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            if (_currentStep < 2) ...[
                              const SizedBox(width: 4),
                              const Icon(CupertinoIcons.chevron_right, size: 16, color: Colors.white),
                            ] else ...[
                              const SizedBox(width: 6),
                              const Icon(CupertinoIcons.checkmark, size: 16, color: Colors.white),
                            ],
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

  /// Build 2-row card for each item
  Widget _buildItemCard(int index, SmartSaleExtractedItem item) {
    final cs = Theme.of(context).colorScheme;
    // USE SYSTEM VALUES AS PRIMARY (fall back to OCR if system not available)
    final systemOpening = item.dbStock; // System opening stock
    final ocrOpening = item.opening; // OCR opening (from image)
    final systemRate = item.inventoryRate; // System rate from database
    final ocrRate = item.rate; // OCR rate (from image)

    // Use system value if available, otherwise fall back to OCR
    final opening = systemOpening ?? ocrOpening;
    final rate = systemRate ?? ocrRate; // Use system rate if available
    final receipt = item.receiptQty; // Receipt from API
    final total = opening + receipt; // Calculate total from system opening + receipt

    final saleQty = _editedQuantities[index] ?? item.quantity;
    final closing = total - saleQty;
    final amount = saleQty * rate; // Use the resolved rate
    final hasError = !item.isValid || item.errors.isNotEmpty || closing < 0;
    final hasDiscrepancy = item.hasStockDiscrepancy || item.hasRateMismatch;
    final hasWarning = hasDiscrepancy || item.hasWarnings || item.warnings.isNotEmpty;
    final hasIssue = hasError || hasWarning;

    // Debug logging for first few items
    if (index < 3) {
      debugPrint('📦 Item $index: ${item.brandName} | SysOpen:$systemOpening | OCROpen:$ocrOpening | SysRate:$systemRate | OCRRate:$ocrRate | Rcpt:$receipt | Total:$total | Sale:$saleQty | Close:$closing | Discrepancy:$hasDiscrepancy');
    }

    // Build list of discrepancy warnings (only show in yellow section if NOT tappable)
    final List<String> discrepancyWarnings = [];

    // Stock discrepancy - now handled by tappable cell, only show detailed warning for Amount
    // if (item.hasStockDiscrepancy) {
    //   final diff = item.stockDifference;
    //   discrepancyWarnings.add('Stock: Image shows ${item.openingStock}, DB has ${item.dbStock} (${diff > 0 ? '+' : ''}$diff)');
    // }

    // Amount mismatch (OCR amount vs Rate × Qty)
    if (item.hasAmountMismatch) {
      discrepancyWarnings.add('Amount: Image shows ₹${item.amount.toStringAsFixed(0)}, Expected ₹${item.expectedAmount!.toStringAsFixed(0)}');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? Colors.red.withValues(alpha: 0.5)
              : hasWarning
                  ? Colors.amber.withValues(alpha: 0.6)
                  : cs.outlineVariant,
          width: hasIssue ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1: Serial Number + Brand Name + Size + Warning indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: hasError
                  ? Colors.red.withValues(alpha: 0.08)
                  : hasWarning
                      ? Colors.amber.withValues(alpha: 0.1)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                // Serial Number Badge
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: hasError
                        ? Colors.red.withValues(alpha: 0.1)
                        : hasWarning
                            ? Colors.amber.withValues(alpha: 0.2)
                            : cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: hasWarning && !hasError
                        ? Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 14, color: Colors.amber[700])
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: hasError ? Colors.red : cs.primary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                // Brand Name
                Expanded(
                  child: Text(
                    item.brandName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasError ? Colors.red[800] : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Size Badge
                if (item.size != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.size!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Row 2: Open, Rcpt, Total, Sale (editable), Rate, Amount, Close
          // Shows SYSTEM values as primary, with color-coded discrepancy indicators
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                // Opening: Shows system value, tappable if OCR differs
                _buildDataCellWithDiscrepancy('Open', '$ocrOpening', systemOpening, flex: 1),
                _buildDataCell('Rcpt', '$receipt', flex: 1, isGrey: true),
                _buildDataCell('Total', '$total', flex: 1),
                _buildEditableSaleCell(index, saleQty),
                // Rate: Shows system rate, tappable if OCR differs
                _buildRateCellWithDiscrepancy('Rate', ocrRate, systemRate, flex: 2),
                _buildAmountCellWithDiscrepancy(amount, item.expectedAmount, item.amount, flex: 2),
                _buildCloseCell(closing),
              ],
            ),
          ),

          // Discrepancy Warnings (Yellow)
          if (discrepancyWarnings.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                border: Border(
                  top: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: discrepancyWarnings.map((w) => _buildIssueRow(w, Colors.amber)).toList(),
              ),
            ),

          // Backend Warnings (Orange)
          if (item.warnings.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border(
                  top: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: item.warnings.map((w) => _buildIssueRow(w.replaceAll('⚠️ ', ''), Colors.orange)).toList(),
              ),
            ),

          // Errors (Red)
          if (item.errors.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(11),
                  bottomRight: Radius.circular(11),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: item.errors.map((e) => _buildIssueRow(e, Colors.red)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  /// Build data cell with stock discrepancy indicator
  /// Build data cell showing SYSTEM value as primary, with discrepancy indicator
  /// On tap, shows tooltip with OCR value when there's a mismatch
  Widget _buildDataCellWithDiscrepancy(String label, String ocrValue, int? systemValue, {int flex = 1}) {
    // If we have system value, use it; otherwise fall back to OCR
    final displayValue = systemValue != null ? '$systemValue' : ocrValue;
    final hasDiscrepancy = systemValue != null && ocrValue != '$systemValue';
    final ocrInt = int.tryParse(ocrValue) ?? 0;
    final diff = systemValue != null ? ocrInt - systemValue : 0;

    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: hasDiscrepancy ? () {
          // Show tooltip with OCR value on tap
          _showDiscrepancyTooltip(
            context,
            'Stock Discrepancy',
            'System: $systemValue\nImage (OCR): $ocrValue\nDifference: ${diff > 0 ? '+' : ''}$diff',
          );
        } : null,
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Container(
              padding: hasDiscrepancy ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : null,
              decoration: hasDiscrepancy
                  ? BoxDecoration(
                      color: diff > 0
                          ? Colors.orange.withValues(alpha: 0.15)
                          : Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: diff > 0
                            ? Colors.orange.withValues(alpha: 0.6)
                            : Colors.amber.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasDiscrepancy
                          ? (diff > 0 ? Colors.orange : Colors.amber)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (hasDiscrepancy) ...[
                    const SizedBox(width: 2),
                    Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      size: 10,
                      color: diff > 0 ? Colors.orange : Colors.amber,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build rate cell showing SYSTEM rate as primary, with discrepancy indicator
  /// On tap, shows tooltip with OCR rate when there's a mismatch
  Widget _buildRateCellWithDiscrepancy(String label, double ocrRate, double? systemRate, {int flex = 2}) {
    // If we have system rate, use it; otherwise fall back to OCR
    final displayRate = systemRate ?? ocrRate;
    final hasDiscrepancy = systemRate != null && (ocrRate - systemRate).abs() > 0.01;
    final diff = hasDiscrepancy ? ocrRate - systemRate : 0.0;

    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: hasDiscrepancy ? () {
          // Show tooltip with OCR rate on tap
          _showDiscrepancyTooltip(
            context,
            'Rate Discrepancy',
            'System: ₹${systemRate.toStringAsFixed(0)}\nImage (OCR): ₹${ocrRate.toStringAsFixed(0)}\nDifference: ${diff > 0 ? '+' : ''}₹${diff.toStringAsFixed(0)}',
          );
        } : null,
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Container(
              padding: hasDiscrepancy ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : null,
              decoration: hasDiscrepancy
                  ? BoxDecoration(
                      // Color based on discrepancy direction
                      color: diff > 0
                          ? Colors.orange.withValues(alpha: 0.15) // OCR > System (overpriced in image)
                          : Colors.amber.withValues(alpha: 0.15), // OCR < System (underpriced in image)
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: diff > 0
                            ? Colors.orange.withValues(alpha: 0.6)
                            : Colors.amber.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '₹${displayRate.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasDiscrepancy
                          ? (diff > 0 ? Colors.orange : Colors.amber)
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (hasDiscrepancy) ...[
                    const SizedBox(width: 2),
                    Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      size: 10,
                      color: diff > 0 ? Colors.orange : Colors.amber,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show discrepancy tooltip as a modal popup
  void _showDiscrepancyTooltip(BuildContext context, String title, String message) {
    HapticFeedback.lightImpact();
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.amber, size: 18),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            message,
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Build amount cell with expected amount discrepancy
  /// Shows calculated amount (Rate × Qty), tappable to see OCR amount if different
  Widget _buildAmountCellWithDiscrepancy(double displayAmount, double? expectedAmount, double ocrAmount, {int flex = 2}) {
    final hasDiscrepancy = expectedAmount != null && (expectedAmount - ocrAmount).abs() > 0.01;
    final diff = ocrAmount - displayAmount;

    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: hasDiscrepancy ? () {
          _showDiscrepancyTooltip(
            context,
            'Amount Discrepancy',
            'Calculated: ₹${displayAmount.toStringAsFixed(0)}\nImage (OCR): ₹${ocrAmount.toStringAsFixed(0)}\nDifference: ${diff > 0 ? '+' : ''}₹${diff.toStringAsFixed(0)}',
          );
        } : null,
        child: Column(
          children: [
            Text(
              'Amt',
              style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Container(
              padding: hasDiscrepancy ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2) : null,
              decoration: hasDiscrepancy
                  ? BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 1.5),
                    )
                  : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '₹${displayAmount.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasDiscrepancy ? Colors.amber : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (hasDiscrepancy) ...[
                    const SizedBox(width: 2),
                    Icon(
                      CupertinoIcons.exclamationmark_circle_fill,
                      size: 10,
                      color: Colors.amber,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataCell(String label, String value, {int flex = 1, bool isGrey = false, bool isBold = false}) {
    return Expanded(
      flex: flex,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isGrey ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableSaleCell(int index, int currentQty) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          Text('Sale', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          SizedBox(
            width: 50,
            height: 32,
            child: TextField(
              controller: _quantityControllers[index],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                filled: true,
                fillColor: cs.primary.withValues(alpha: 0.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (value) {
                final newQty = int.tryParse(value) ?? 0;
                setState(() {
                  _editedQuantities[index] = newQty;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseCell(int closing) {
    final isNegative = closing < 0;
    return Expanded(
      flex: 1,
      child: Column(
        children: [
          Text('Close', style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: isNegative
                ? BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: Text(
              '$closing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isNegative ? FontWeight.bold : FontWeight.w500,
                color: isNegative ? Colors.red : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueRow(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(CupertinoIcons.exclamationmark_circle, color: color, size: 12),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 10, color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Build validation warnings section (shop, date, size mismatches)
  Widget _buildValidationWarningsSection() {
    final validation = widget.result.validation!;
    final List<Widget> warningWidgets = [];

    // Shop name mismatch
    if (!validation.shopNameMatch && validation.detectedShopName != null) {
      warningWidgets.add(_buildValidationWarningChip(
        icon: CupertinoIcons.building_2_fill,
        label: 'Shop Mismatch',
        expected: validation.expectedShopName ?? 'Unknown',
        detected: validation.detectedShopName!,
      ));
    }

    // Date mismatch
    if (!validation.dateMatch && validation.detectedDate != null) {
      warningWidgets.add(_buildValidationWarningChip(
        icon: CupertinoIcons.calendar,
        label: 'Date Mismatch',
        expected: validation.expectedDate ?? 'Unknown',
        detected: validation.detectedDate!,
      ));
    }

    // Size mismatch
    if (!validation.sizeMatch && validation.detectedSize != null) {
      warningWidgets.add(_buildValidationWarningChip(
        icon: CupertinoIcons.resize,
        label: 'Size Mismatch',
        expected: validation.expectedSize ?? 'Unknown',
        detected: validation.detectedSize!,
      ));
    }

    // Add any additional warnings from backend
    for (final warning in validation.warnings) {
      if (!warning.contains('Shop name') && !warning.contains('Date') && !warning.contains('Size')) {
        warningWidgets.add(_buildGenericWarning(warning));
      }
    }

    // Show stock discrepancies count
    if (validation.stockDiscrepancies > 0) {
      warningWidgets.add(_buildValidationStatChip(
        icon: CupertinoIcons.cube_box,
        label: 'Stock Discrepancies',
        value: '${validation.stockDiscrepancies}',
        color: Colors.orange,
      ));
    }

    // Show amount mismatches count
    if (validation.amountMismatches > 0) {
      warningWidgets.add(_buildValidationStatChip(
        icon: CupertinoIcons.money_dollar_circle,
        label: 'Amount Mismatches',
        value: '${validation.amountMismatches}',
        color: Colors.orange,
      ));
    }

    if (warningWidgets.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.amber, size: 16),
              const SizedBox(width: 8),
              Text(
                'Validation Warnings',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: warningWidgets,
          ),
        ],
      ),
    );
  }

  Widget _buildValidationWarningChip({
    required IconData icon,
    required String label,
    required String expected,
    required String detected,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.amber),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Expected: $expected',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          Text(
            'Detected: $detected',
            style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$value $label',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericWarning(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.exclamationmark_circle, size: 12, color: Colors.amber),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text.replaceAll('⚠️ ', ''),
              style: TextStyle(fontSize: 10, color: Colors.amber),
            ),
          ),
        ],
      ),
    );
  }

  /// Build total card at the bottom
  Widget _buildTotalCard() {
    // Calculate totals only for items matching the selected size filter
    final filteredItems = widget.result.extractedItems.where((item) => _itemMatchesSelectedSize(item)).toList();
    final totalOpening = filteredItems.fold<int>(0, (sum, item) => sum + item.opening);
    final totalClosing = totalOpening - _totalSaleQty;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.withValues(alpha: 0.12), Colors.green.withValues(alpha: 0.06)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              Text(
                '₹${_totalAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTotalDataCell('Items', '${filteredItems.length}'),
              _buildTotalDataCell('Open', '$totalOpening'),
              _buildTotalDataCell('Sale', '$_totalSaleQty', isHighlight: true),
              _buildTotalDataCell('Close', '$totalClosing', isNegative: totalClosing < 0),
            ],
          ),
          // Show hint when all sales are 0
          if (_totalSaleQty == 0 && filteredItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(CupertinoIcons.lightbulb, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap on Sale field to enter quantities manually',
                      style: TextStyle(fontSize: 11, color: Colors.amber),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalDataCell(String label, String value, {bool isHighlight = false, bool isNegative = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isHighlight
                  ? Colors.green
                  : isNegative
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isHighlight ? Colors.white : isNegative ? Colors.red : Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

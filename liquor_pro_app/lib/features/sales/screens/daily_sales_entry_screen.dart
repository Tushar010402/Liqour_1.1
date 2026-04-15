import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/services/document_scanner_service.dart';
import '../../../core/services/debug_log_service.dart';
import '../../../core/services/image_preprocessing_service.dart';
import '../../inventory/widgets/image_quality_indicator.dart';
// Industrial-grade scanning imports
import '../models/scan_quality_models.dart';
import '../services/real_time_quality_service.dart';
import '../widgets/live_camera_scanner_widget.dart';
import '../widgets/scan_quality_feedback_modal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/product_constants.dart';
import '../../../core/constants/size_range_constants.dart';
import '../../../core/models/ai_feedback_model.dart';
import '../../../core/widgets/ai_feedback_bottom_sheet.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/widgets/shop_selector_widget.dart';
import '../../inventory/providers/product_provider.dart';
import '../../inventory/models/product.dart' as models;
import '../../inventory/widgets/ios_search_bar.dart';
import '../../inventory/widgets/filter_chip_row.dart';
import '../providers/daily_sales_provider.dart';
import '../providers/expense_header_provider.dart';
import '../models/expense_header.dart';
import 'quick_sale_ocr_screen.dart';
import 'sales_summary_screen.dart';
import '../../../shared/widgets/bottom_action_bar.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/config/api_config.dart';
import '../services/daily_sales_service.dart';
import '../models/daily_sales_models.dart';
import '../models/daily_sales_draft.dart'; // For DraftProductItem
import '../../auth/providers/auth_provider.dart';
// OCR Processing
import '../services/ocr_service.dart';
import '../models/ocr_models.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/logger.dart';

/// Daily Sales Entry Screen - Multi-step wizard for UP Liquor Shop Bulk Entry
class DailySalesEntryScreen extends StatefulWidget {
  /// When true, shows its own header with back button (standalone mode)
  /// When false, assumes parent provides the header (tab mode)
  final bool showHeader;

  /// Optional: Pass existing record for edit mode (salesman editing pending request)
  final DailySalesRecord? editRecord;

  /// Pre-selected category name from the entry mode selector
  final String? initialCategoryName;

  /// Pre-selected size from the entry mode selector
  final String? initialSize;

  /// Pre-selected date from setup screen (null = use provider default/yesterday)
  final DateTime? selectedDate;

  const DailySalesEntryScreen({
    super.key,
    this.showHeader = false,
    this.editRecord,
    this.initialCategoryName,
    this.initialSize,
    this.selectedDate,
  });

  /// Check if in edit mode
  bool get isEditMode => editRecord != null;

  @override
  State<DailySalesEntryScreen> createState() => _DailySalesEntryScreenState();
}

class _DailySalesEntryScreenState extends State<DailySalesEntryScreen> {
  int _currentStep = 0; // 0 = Products, 1 = Payment

  // Provider reference for safe dispose (avoid deactivated widget ancestor lookup)
  DailySalesProvider? _salesProvider;

  // Controllers for quantity inputs (dynamic, created per product)
  final Map<String, TextEditingController> _quantityControllers = {};

  // ValueNotifier for progress count — avoids full setState on every keystroke
  // which would cause TextFields inside SliverList to lose focus
  final ValueNotifier<int> _filledCountNotifier = ValueNotifier<int>(0);

  // Guard against double-push of Sales Summary
  bool _isSummaryShowing = false;

  /// Get or create a quantity controller for a product, with a listener
  /// to update the progress bar in real-time.
  TextEditingController _getOrCreateQtyController(String productId) {
    if (!_quantityControllers.containsKey(productId)) {
      final controller = TextEditingController();
      controller.addListener(_onQuantityChanged);
      _quantityControllers[productId] = controller;
    }
    return _quantityControllers[productId]!;
  }

  void _onQuantityChanged() {
    if (!mounted) return;
    // Only update the progress notifier — do NOT call setState here
    // setState would rebuild the SliverList and make TextFields lose focus
    _updateProgressCount();
  }

  /// Recalculate filled count and update progress notifier + auto-navigate
  void _updateProgressCount() {
    final allProductsWithStock = _cachedProducts.where((product) {
      final stock = _cachedStockMap[product.id];
      return stock != null && stock.quantity > 0;
    }).toList();
    final filteredProducts = _getFilteredAndSortedProducts(allProductsWithStock);
    final totalCount = filteredProducts.length;

    int filledCount = 0;
    for (final product in filteredProducts) {
      final controller = _quantityControllers[product.id];
      if (controller != null && controller.text.isNotEmpty) {
        filledCount++;
      }
    }

    _filledCountNotifier.value = filledCount;
  }

  /// Dispose all quantity controllers and clear the map
  void _clearQuantityControllers() {
    for (final controller in _quantityControllers.values) {
      controller.removeListener(_onQuantityChanged);
      controller.dispose();
    }
    _quantityControllers.clear();
  }

  // Stock validation state
  final Map<String, bool> _quantityValidationErrors = {}; // productId -> hasError
  final Map<String, String> _validationErrorMessages = {}; // productId -> error message

  // Payment controllers
  final _cashController = TextEditingController();
  final _cardController = TextEditingController();
  final _upiController = TextEditingController();
  final _creditController = TextEditingController();
  final _expenseController = TextEditingController(); // Legacy - kept for backward compatibility
  final _notesController = TextEditingController();

  // Expense header controllers (NEW - Expense Table Feature)
  final Map<String, TextEditingController> _expenseControllers = {};

  bool _isLoadingProducts = false;
  bool _isDraftRestoreInProgress = false;
  String _loadingMessage = 'Loading...'; // Message shown during loading overlay

  // ========== SAVED INVENTORY FILTER STATE ==========
  // Save ProductProvider's filter state before clearing, restore on dispose
  // This prevents Daily Sales Entry from destroying the inventory screen's filters
  String? _savedCategoryId;
  String? _savedCategoryName;
  String? _savedSize;

  // ========== LOCAL PRODUCTS CACHE (ISOLATED FROM ProductProvider) ==========
  // CRITICAL: Store our own copy of products to prevent ProductsGridScreen from overwriting
  // ProductsGridScreen runs in background and can reload provider with filtered products
  List<models.Product> _cachedProducts = [];
  Map<String, models.Stock> _cachedStockMap = {};
  List<models.Category> _cachedCategories = [];

  // ========== IMAGE ATTACHMENT STATE (MANDATORY) ==========
  final List<File> _attachedImages = [];
  final Set<String> _attachedImageHashes = {}; // SHA256 content hashes for deduplication
  final Map<String, BlurScoreResult> _imageQualityScores = {}; // path -> blur score
  final ImagePreprocessingService _imagePreprocessingService = ImagePreprocessingService();
  final RealTimeQualityService _qualityService = RealTimeQualityService(); // Industrial-grade quality assessment
  bool _isUploadingImages = false;
  bool _isScanningInProgress = false; // Debounce flag to prevent double-tap
  bool _isSubmitInProgress = false; // CRITICAL: Prevents double-submit race condition
  bool _wasSubmittedSuccessfully = false; // CRITICAL: Prevents draft re-save on dispose after successful submission
  late final DocumentScannerService _documentScanner;

  // ========== UPLOAD PROGRESS STATE (Compression + Upload) ==========
  String _uploadProgressMessage = ''; // Shows "Compressing 1/3..." or "Uploading 2/3..."
  int _compressionCurrent = 0;
  int _compressionTotal = 0;
  int _uploadCurrent = 0;
  int _uploadTotal = 0;

  // ========== OCR PROCESSING STATE ==========
  bool _isOcrProcessing = false;
  String _ocrProgressMessage = '';
  int _ocrMatchedCount = 0;

  // ========== EDIT MODE STATE ==========
  // Track original date for detecting date changes (for changeDailySalesRecordDate API)
  DateTime? _originalRecordDate;

  // ========== FILTER STATE (Single Selection - Best Practice) ==========
  String _searchQuery = '';
  String _sortBy = 'price'; // price, size, name, brand, stock - Price first for sales entry
  bool _sortAscending = true; // Ascending - low to high prices (most common sales first)
  String? _selectedCategoryId;    // Single category selection (ID)
  String? _selectedCategoryName;  // Category name for display
  String? _selectedSize;          // Single size selection
  bool _hasSetDefaultCategory = false; // Track if default category was set
  bool _hasSetDefaultSize = false;     // Track if default size was set
  bool _isSearchExpanded = false; // Search expands inline in header when tapped
  bool _isFiltersVisible = false; // Category/size filters hidden by default, toggled via filter button

  // Priority order for categories (Whisky first, then Beer, etc.)
  static const List<String> _categoryPriority = ['whisky', 'beer', 'rum', 'vodka', 'wine', 'gin', 'brandy'];

  // Combined category groups - "English" = Whisky + Rum + Vodka
  // Note: Include both 'whisky' and 'whiskey' spellings for compatibility
  static const String _englishGroupName = 'English';
  static const List<String> _englishCategories = ['whisky', 'whiskey', 'rum', 'vodka'];

  // Track if combined "English" filter is selected
  bool _isEnglishFilterSelected = false;
  List<String> _selectedCategoryIds = []; // For combined category filtering

  // Scroll controller for collapsing search bar
  final ScrollController _scrollController = ScrollController();
  bool _isSearchBarVisible = true;
  double _lastScrollOffset = 0;


  @override
  void initState() {
    super.initState();

    // Initialize document scanner service
    _documentScanner = DocumentScannerService();

    // Apply pre-selected size from entry mode selector
    // Category is applied after products load (needs _cachedCategories for English group)
    if (widget.initialSize != null) {
      _selectedSize = widget.initialSize;
      _hasSetDefaultSize = true; // Prevent auto-override
    }
    if (widget.initialCategoryName != null) {
      _hasSetDefaultCategory = true; // Prevent auto-override
    }

    // Listen to scroll for collapsing search bar
    _scrollController.addListener(_handleScroll);

    // OPTIMIZED: Removed decorative banner and condensed logging
    if (kDebugMode) {
      Logger.info('DailySalesEntry: Screen opened');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shopProvider = context.read<ShopSelectionProvider>();
      final productProvider = context.read<ProductProvider>();
      final salesProvider = context.read<DailySalesProvider>();

      // Store provider reference for safe dispose
      _salesProvider = salesProvider;

      // Apply pre-selected date from setup screen
      if (widget.selectedDate != null) {
        salesProvider.setRecordDate(widget.selectedDate!);
        if (kDebugMode) {
          Logger.info('DailySalesEntry: Date set from setup screen: ${widget.selectedDate}');
        }
      }

      // Refresh shops to get newly created ones
      await shopProvider.refreshShops();

      // Wait for shop loading to complete
      while (shopProvider.isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final shopId = shopProvider.selectedShopId;
      if (kDebugMode) {
        Logger.info('DailySalesEntry: Shop selected: $shopId (${shopProvider.shops.length} shops available)');
      }

      // Pre-select shop in sales provider if available
      if (shopId != null) {
        // Use sync version for initial load (no previous shop to save)
        salesProvider.setShopSync(shopId);
        await _loadProducts(shopId);

        // Apply pre-selected category from setup screen AFTER products are loaded
        // (needs _cachedCategories to resolve "English" group → actual category IDs)
        if (widget.initialCategoryName != null && mounted) {
          if (widget.initialCategoryName == _englishGroupName) {
            final englishCategoryIds = _getEnglishCategoryIds(_cachedCategories);
            if (englishCategoryIds.isNotEmpty) {
              setState(() {
                _isEnglishFilterSelected = true;
                _selectedCategoryName = _englishGroupName;
                _selectedCategoryIds = englishCategoryIds;
              });
            }
          } else {
            // "Beer" or other direct category name
            final cat = _cachedCategories.firstWhere(
              (c) => c.name.toLowerCase().contains(widget.initialCategoryName!.toLowerCase()),
              orElse: () => models.Category(id: '', name: widget.initialCategoryName!, description: '', isActive: true, sortOrder: 0),
            );
            setState(() {
              _selectedCategoryId = cat.id.isNotEmpty ? cat.id : null;
              _selectedCategoryName = widget.initialCategoryName;
            });
          }
        }

        // ═══════════════════════════════════════════════════
        // EDIT MODE: Pre-fill from existing record
        // ═══════════════════════════════════════════════════
        if (widget.editRecord != null) {
          if (kDebugMode) {
            Logger.info('DailySalesEntry: Edit mode - Loading record ${widget.editRecord!.id}');
          }
          await _prePopulateFromRecord(widget.editRecord!, salesProvider);
        } else {
          // ═══════════════════════════════════════════════════
          // NEW MODE: Clear ALL stale provider state before draft check
          // The provider might have images/items/payment from a previous session
          // (especially from edit mode which sets payment amounts)
          // ═══════════════════════════════════════════════════
          salesProvider.clearImageUrls();
          salesProvider.clearItems();
          _clearQuantityControllers(); // Fresh state — no stale quantities

          // CRITICAL: Also clear payment amounts from previous session
          // Edit mode sets these, and they persist in the provider singleton
          salesProvider.setCashAmount(0);
          salesProvider.setCardAmount(0);
          salesProvider.setUpiAmount(0);
          salesProvider.setCreditAmount(0);
          salesProvider.setExpenseAmount(0);

          // Also clear the local payment controllers
          _cashController.clear();
          _cardController.clear();
          _upiController.clear();
          _creditController.clear();
          _expenseController.clear();

          if (kDebugMode) {
            Logger.info('DailySalesEntry: NEW MODE - Cleared ALL stale provider state (items, images, payment)');
          }

          // DRAFT RECOVERY DISABLED — fresh state every time
          // User requested no auto-save/restore behavior
        }

        // AI Scan mode now navigates directly to QuickSaleOCRScreen from setup screen
      }
    });
  }

  /// Check for draft and restore (Modern UX with loading overlay)
  ///
  /// CRITICAL FIX: Now restores complete product items from provider.loadDraft()
  /// The provider's loadDraft() now populates _items with full product details
  Future<void> _checkAndRestoreDraft(DailySalesProvider provider) async {
    if (!mounted) return;
    try {
      Logger.debug('[DailySalesEntry] Checking for draft...');

      // Show loading overlay immediately
      if (mounted) {
        setState(() {
          _isDraftRestoreInProgress = true;
          _loadingMessage = 'Checking for saved draft...';
        });
      }

      final draft = await provider.getDraft();

      // CRITICAL: Check mounted after async operation
      if (!mounted) return;

      if (draft != null && draft.isNotEmpty) {
        Logger.info('[DailySalesEntry] Draft found! (${draft.ageText})');
        Logger.info('   - Product items: ${draft.productItems.length}');
        Logger.info('   - Legacy quantities: ${draft.productQuantities.length}');
        Logger.info('   - Payment: ₹${draft.totalPayment}');

        // ═══════════════════════════════════════════════════════════════════════
        // POLLUTED DRAFT DETECTION: Multiple scenarios where draft is invalid
        // 1. No products but has payment (ghost draft from edit mode)
        // 2. Payment significantly exceeds product total (mismatched edit data)
        // ═══════════════════════════════════════════════════════════════════════
        final hasNoProducts = draft.productItems.isEmpty && draft.productQuantities.isEmpty;
        final hasPayment = draft.totalPayment > 0;
        final productTotal = draft.totalProductsAmount;

        // Case 1: Ghost draft - no products but has payment
        final isGhostDraft = hasNoProducts && hasPayment;

        // Case 2: Mismatched draft - payment is significantly higher than products
        // This happens when edit mode saved payment from original record but products were different
        // Threshold: payment is more than 5x the product total (clearly mismatched)
        final isMismatchedDraft = productTotal > 0 &&
            draft.totalPayment > 0 &&
            draft.totalPayment > productTotal * 5;

        if (isGhostDraft || isMismatchedDraft) {
          if (isGhostDraft) {
            Logger.warning('[DailySalesEntry] GHOST DRAFT DETECTED: No products but payment ₹${draft.totalPayment}');
          } else {
            Logger.warning('[DailySalesEntry] MISMATCHED DRAFT DETECTED:');
            Logger.warning('   - Product total: ₹$productTotal');
            Logger.warning('   - Payment saved: ₹${draft.totalPayment}');
            Logger.warning('   - Ratio: ${(draft.totalPayment / productTotal).toStringAsFixed(1)}x (threshold: 5x)');
          }
          Logger.warning('   - This is leftover data from edit mode. Clearing...');

          // Clear the polluted draft from both local and backend
          await provider.clearDraft();

          // Also reset form state in provider to clear stale payment amounts and images
          provider.clearForm();

          // Reset payment controllers to empty state
          _cashController.clear();
          _cardController.clear();
          _upiController.clear();
          _creditController.clear();
          _expenseController.clear();
          _notesController.clear();

          // Clear local attached images as well
          _attachedImages.clear();
          _attachedImageHashes.clear();

          if (mounted) {
            setState(() {
              _isDraftRestoreInProgress = false;
            });
          }

          // Enable auto-save for fresh entry
          _enableAutoSave(provider);

          Logger.info('[DailySalesEntry] Polluted draft cleared, starting fresh');
          return;
        }

        // Update loading message
        if (mounted) {
          setState(() {
            _loadingMessage = 'Restoring ${draft.productItems.length} products...';
          });
        }

        // ═══════════════════════════════════════════════════════════════
        // CRITICAL FIX: provider.loadDraft() now restores COMPLETE products
        // to provider._items list, including name, brand, category, size, etc.
        // ═══════════════════════════════════════════════════════════════
        final restored = await provider.loadDraft();

        // CRITICAL: Check mounted after async operation
        if (!mounted) return;

        if (restored) {
          // Update loading message for final step
          if (mounted) {
            setState(() {
              _loadingMessage = 'Setting up your entry...';
            });
          }

          // ═══════════════════════════════════════════════════════════════════════
          // INDUSTRIAL-GRADE FIX: DON'T restore payment from draft
          // Payment values in drafts can be polluted from edit mode sessions.
          // Products are the source of truth - payment should be entered fresh
          // on Step 2 based on actual cart total.
          //
          // This matches the natural workflow:
          // - Step 1: User selects products and quantities (saved in draft)
          // - Step 2: User enters payment breakdown (entered fresh each time)
          // ═══════════════════════════════════════════════════════════════════════
          // DO NOT restore: _cashController, _cardController, _upiController, _creditController
          // DO NOT restore: provider payment amounts (they will be set when user proceeds to Step 2)

          // Only restore notes (user's text input)
          _notesController.text = draft.notes;

          // ═══════════════════════════════════════════════════════════════
          // CRITICAL FIX: Sync quantity controllers from restored provider items
          // The provider._items now contains complete product data
          // ═══════════════════════════════════════════════════════════════
          for (var item in provider.items) {
            _getOrCreateQtyController(item.productId).text = item.quantity.toString();
          }

          // Also clear payment amounts in provider to ensure fresh start
          provider.setCashAmount(0);
          provider.setCardAmount(0);
          provider.setUpiAmount(0);
          provider.setCreditAmount(0);

          // Also restore expense breakdown controllers if draft has them
          if (draft.expenses.isNotEmpty) {
            for (var entry in draft.expenses.entries) {
              final headerId = entry.key;
              final amount = entry.value;
              if (!_expenseControllers.containsKey(headerId)) {
                _expenseControllers[headerId] = TextEditingController();
              }
              _expenseControllers[headerId]!.text = amount > 0 ? amount.toString() : '';
            }
          }

          // Small delay for smooth transition
          await Future.delayed(const Duration(milliseconds: 300));

          if (mounted) {
            setState(() {
              _isDraftRestoreInProgress = false;
            });
          }

          // Enable auto-save
          _enableAutoSave(provider);

          // Show detailed recovery banner (Swiggy/Zomato style - non-intrusive)
          if (mounted) {
            final productCount = provider.items.length;
            final totalAmount = provider.totalItemsAmount;
            final message = productCount > 0
                ? 'Restored $productCount products (₹${totalAmount.toStringAsFixed(0)}) from ${draft.ageText}'
                : 'Draft restored from ${draft.ageText}';
            SnackbarHelper.showSuccess(context, message);
          }

          Logger.info('[DailySalesEntry] Draft restored with ${provider.items.length} products');
        } else {
          // Restore failed, hide overlay
          if (mounted) {
            setState(() {
              _isDraftRestoreInProgress = false;
            });
          }
          _enableAutoSave(provider);
        }
      } else {
        Logger.info('[DailySalesEntry] No draft found, starting fresh');

        // Hide loading overlay
        if (mounted) {
          setState(() {
            _isDraftRestoreInProgress = false;
          });
        }

        // Enable auto-save for new entry
        _enableAutoSave(provider);
      }
    } catch (e) {
      Logger.error('[DailySalesEntry] Draft restore error: $e');
      if (mounted) {
        setState(() {
          _isDraftRestoreInProgress = false;
        });
        SnackbarHelper.showError(context, 'Failed to restore draft');
      }
    }
  }

  /// Enable auto-save (called after draft restore or new entry)
  /// CRITICAL FIX: Now saves COMPLETE product items from controllers + cached products
  /// This ensures products from ALL size filters are saved, not just visible ones
  void _enableAutoSave(DailySalesProvider provider) {
    // Auto-save disabled — fresh state every time per user request
    return;
    // ignore: dead_code
    provider.enableAutoSaveWithProductItems(
      getProductQuantities: () {
        // Build product quantities map from ALL controllers (includes all sizes)
        final quantities = <String, int>{};
        for (var entry in _quantityControllers.entries) {
          final text = entry.value.text;
          if (text.isNotEmpty) {
            final qty = int.tryParse(text);
            if (qty != null && qty > 0) {
              quantities[entry.key] = qty;
            }
          }
        }
        return quantities;
      },
      getProductItems: () {
        // Build COMPLETE product items from controllers + cached products
        // This enables full restoration without needing to match product IDs
        final productItems = <DraftProductItem>[];

        for (var entry in _quantityControllers.entries) {
          final productId = entry.key;
          final text = entry.value.text;

          if (text.isEmpty) continue;
          final qty = int.tryParse(text);
          if (qty == null || qty <= 0) continue;

          // Find product in cached products (includes ALL sizes, not just visible)
          // Using try-catch with firstWhere to handle not found case cleanly
          models.Product? product;
          try {
            product = _cachedProducts.firstWhere((p) => p.id == productId);
          } catch (_) {
            // Product not in cache - skip (shouldn't happen normally)
            Logger.warning('[AutoSave] Product $productId not found in cache, skipping');
            continue;
          }

          // Build complete DraftProductItem
          // Note: Product model uses sellingPrice (no separate mrp field)
          productItems.add(DraftProductItem(
            productId: productId,
            productName: product.name,
            brandName: product.brand?.name ?? '',
            categoryName: product.category?.name ?? '',
            subcategoryName: product.subcategory?.name ?? '',
            size: product.size,
            quantity: qty,
            unitPrice: product.sellingPrice,
            mrp: product.sellingPrice, // Using sellingPrice as MRP
            totalAmount: product.sellingPrice * qty,
          ));
        }

        return productItems;
      },
    );
    Logger.info('[DailySalesEntry] Auto-save enabled (with complete product items)');
  }

  /// Pre-populate form from existing record (Edit mode)
  /// Used when salesman edits a pending sales record
  Future<void> _prePopulateFromRecord(DailySalesRecord record, DailySalesProvider provider) async {
    if (!mounted) return;

    try {
      // ═══════════════════════════════════════════════════════════════════════
      // CRITICAL: Enable EDIT MODE in provider FIRST
      // This prevents ALL draft saving operations during edit mode:
      // - triggerInstantSave() will skip
      // - saveDraft() will skip
      // - forceSaveDraft() will skip
      // - enableAutoSave() will skip
      // This is the primary mechanism to prevent draft pollution from edit mode
      // ═══════════════════════════════════════════════════════════════════════
      provider.setEditMode(true);

      if (kDebugMode) {
        Logger.debug('[DailySalesEntry] Pre-populating from record: ${record.id}');
        Logger.debug('   Provider hashCode: ${provider.hashCode}');
        Logger.debug('   Provider isEditMode: ${provider.isEditMode}');  // Should be true
        Logger.debug('   Record Date: ${record.recordDate}');
        Logger.debug('   Items: ${record.items.length}');
        Logger.debug('   Cash: ${record.totalCashAmount}');
        Logger.debug('   Card: ${record.totalCardAmount}');
        Logger.debug('   UPI: ${record.totalUpiAmount}');
        Logger.debug('   Credit: ${record.totalCreditAmount}');
        Logger.debug('   Images: ${record.imageUrls.length}');
        Logger.debug('   Image URLs: ${record.imageUrls}');
      }

      // ═══════════════════════════════════════════════════════════════════════
      // CRITICAL: Clear any existing draft for this date IMMEDIATELY
      // This prevents draft pollution - edit mode data should NOT pollute
      // the draft system. We're editing an existing record, not a draft.
      // ═══════════════════════════════════════════════════════════════════════
      if (kDebugMode) {
        Logger.info('[DailySalesEntry] EDIT MODE: Clearing any existing draft to prevent pollution...');
      }
      await provider.clearDraft();
      if (kDebugMode) {
        Logger.info('[DailySalesEntry] Draft cleared for edit mode');
      }

      // 0. Set record date from existing record (CRITICAL for edit mode)
      provider.setRecordDate(record.recordDate);
      // Store original date for detecting changes later
      _originalRecordDate = record.recordDate;
      if (kDebugMode) {
        Logger.debug('[DailySalesEntry] Set record date to: ${record.recordDate}');
        Logger.debug('[DailySalesEntry] Stored original date: $_originalRecordDate');
      }

      // 1. Set payment amounts (controllers + provider)
      _cashController.text = record.totalCashAmount > 0 ? record.totalCashAmount.toStringAsFixed(0) : '';
      _cardController.text = record.totalCardAmount > 0 ? record.totalCardAmount.toStringAsFixed(0) : '';
      _upiController.text = record.totalUpiAmount > 0 ? record.totalUpiAmount.toStringAsFixed(0) : '';
      _creditController.text = record.totalCreditAmount > 0 ? record.totalCreditAmount.toStringAsFixed(0) : '';

      // Update provider payment amounts using individual setters
      provider.setCashAmount(record.totalCashAmount);
      provider.setCardAmount(record.totalCardAmount);
      provider.setUpiAmount(record.totalUpiAmount);
      provider.setCreditAmount(record.totalCreditAmount);

      // 2. Set notes
      _notesController.text = record.notes;
      provider.setNotes(record.notes);

      // 3. Set product quantities from items
      // The controllers are the source of truth - they will be read on submit
      for (final item in record.items) {
        if (item.productId.isNotEmpty && item.quantity > 0) {
          _getOrCreateQtyController(item.productId).text = item.quantity.toString();
        }
      }

      // 4. Set existing image URLs from record (Edit mode doesn't need re-upload)
      if (record.imageUrls.isNotEmpty) {
        provider.setImageUrls(record.imageUrls);
        if (kDebugMode) {
          Logger.info('[DailySalesEntry] Pre-populated ${record.imageUrls.length} existing image URLs');
          Logger.debug('   Verification - provider.imageUrls: ${provider.imageUrls}');
          Logger.debug('   Verification - provider.imageUrls.length: ${provider.imageUrls.length}');
        }
      } else {
        if (kDebugMode) {
          Logger.warning('[DailySalesEntry] No image URLs in record to pre-populate');
        }
      }

      // ========== CLEAR VALIDATION ERRORS FOR APPROVED RECORD EDITS ==========
      // For approved records, the pre-populated quantities are valid because
      // the backend will return stock before deducting new quantities.
      // Clear any stale validation errors to prevent false blocking.
      if (record.status.toLowerCase() == 'approved') {
        _quantityValidationErrors.clear();
        _validationErrorMessages.clear();
        if (kDebugMode) {
          Logger.info('[DailySalesEntry] Cleared validation errors for approved record edit');
        }
      }

      if (mounted) {
        setState(() {});
      }

      // Show subtle notification
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('Editing record from ${DateFormat('dd MMM').format(record.recordDate)}'),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }

      if (kDebugMode) {
        Logger.info('[DailySalesEntry] Pre-population complete');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DailySalesEntry] Pre-population error: $e');
      }
    }
  }

  @override
  void dispose() {
    // Dispose progress notifier
    _filledCountNotifier.dispose();

    // Dispose document scanner service
    _documentScanner.dispose();

    // Dispose image preprocessing service
    _imagePreprocessingService.dispose();

    // Dispose quality service
    _qualityService.dispose();

    // Dispose scroll controller
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();

    // ═══════════════════════════════════════════════════════════════
    // INDUSTRIAL-GRADE DISPOSE ORDER (prevents race conditions):
    // 1. FIRST: Disable auto-save timer to prevent new callbacks
    // 2. THEN: Reset edit mode flag (so next new entry works properly)
    // 3. THEN: Build data from controllers while still valid
    // 4. THEN: Force save (fire-and-forget, non-blocking) - ONLY FOR NEW ENTRIES
    // 5. FINALLY: Dispose controllers
    // ═══════════════════════════════════════════════════════════════
    if (_salesProvider != null) {
      // Disable auto-save timer
      _salesProvider!.disableAutoSave();
      // Clear provider state silently (no draft save — fresh state every time)
      _salesProvider!.clearFormSilent();
    }

    // STEP 4: Dispose all controllers AFTER data is built
    for (var controller in _quantityControllers.values) {
      controller.removeListener(_onQuantityChanged);
      controller.dispose();
    }
    for (var controller in _expenseControllers.values) {
      controller.dispose();
    }
    _cashController.dispose();
    _cardController.dispose();
    _upiController.dispose();
    _creditController.dispose();
    _expenseController.dispose();
    _notesController.dispose();

    // CRITICAL: Restore inventory filter state that was saved before clearAllFilters()
    // This ensures the inventory screen's filters are preserved across Daily Sales navigation
    if (_savedCategoryId != null || _savedSize != null) {
      try {
        final provider = context.read<ProductProvider>();
        provider.setSelectedCategory(_savedCategoryId, _savedCategoryName);
        provider.setSelectedSize(_savedSize);
        Logger.info('[DailySalesEntry] Restored inventory filters on dispose: category=$_savedCategoryName, size=$_savedSize');
      } catch (e) {
        // Provider might not be accessible during tree disposal - safe to ignore
        Logger.debug('[DailySalesEntry] Could not restore filters on dispose: $e');
      }
    }

    super.dispose();
  }

  /// Handle scroll to show/hide search bar
  /// NOTE: Keyboard dismissal removed - it was causing auto-close on last product
  /// when system auto-scrolls to reveal the input field. Keyboard dismissal is
  /// now only handled by GestureDetector tap-outside (best practice).
  void _handleScroll() {
    final currentOffset = _scrollController.offset;
    final delta = currentOffset - _lastScrollOffset;

    // Scrolling down (delta > 0) = hide search bar
    // Scrolling up (delta < 0) = show search bar
    if (delta > 10 && _isSearchBarVisible && currentOffset > 50) {
      setState(() => _isSearchBarVisible = false);
    } else if (delta < -10 && !_isSearchBarVisible) {
      setState(() => _isSearchBarVisible = true);
    }

    _lastScrollOffset = currentOffset;

    // DO NOT dismiss keyboard on scroll - causes issues with last product input
    // The system auto-scrolls to reveal input fields, which would dismiss keyboard
  }

  /// Dismiss keyboard when tapping outside input fields
  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Higher limit constant for Daily Sales Entry
  /// We need all products to match with stock entries, so we load more than normal pagination
  static const int kDailySalesProductLimit = 500;

  /// Load products for a shop with optional force reselect of category/size
  /// [forceReselect] - When true (e.g., shop change), forces smart reselection of category & size
  Future<void> _loadProducts(String shopId, {bool forceReselect = false}) async{
    if (!mounted) return;
    setState(() {
      _isLoadingProducts = true;
      _loadingMessage = 'Loading products...';
    });
    try {
      final provider = context.read<ProductProvider>();

      // CRITICAL: Save inventory filter state before clearing (restored on dispose)
      // This prevents Daily Sales from permanently destroying the inventory screen's filters
      _savedCategoryId = provider.selectedCategoryId;
      _savedCategoryName = provider.selectedCategoryName;
      _savedSize = provider.selectedSize;

      // Clear filters so Daily Sales sees ALL products for all category/size filters
      provider.clearAllFilters();  // Reset stored filters (doesn't trigger reload)

      // ═══════════════════════════════════════════════════════════════════════════════
      // CRITICAL FIX: Products are TENANT-WIDE (shared across all shops)
      // Stock is SHOP-SPECIFIC
      //
      // Previously we passed shopId to loadProducts which caused backend to filter products
      // by shop_id - returning only products "owned" by that shop (e.g., 5 products)
      // But we have 141 stock entries for products from the TENANT's product catalog!
      //
      // The fix: Load products WITHOUT shop_id filter (gets ALL tenant products)
      // Then load stock WITH shop_id filter (gets shop-specific stock)
      // The matching happens client-side: product.id matches stockMap[product.id]
      // ═══════════════════════════════════════════════════════════════════════════════
      await provider.loadProducts(
        shopId: null,  // DON'T filter products by shop - products are tenant-wide!
        limit: kDailySalesProductLimit,
        categoryId: null,  // Explicitly clear - load ALL categories
        size: null,        // Explicitly clear - load ALL sizes (filter client-side)
      );

      // Now load stock for this specific shop (stock IS shop-specific)
      await provider.loadStock(shopId: shopId);

      // ═══════════════════════════════════════════════════════════════════
      // CRITICAL: Cache products locally to prevent ProductsGridScreen from
      // overwriting our data when it loads filtered products in background
      // ═══════════════════════════════════════════════════════════════════
      // NOTE: Products are tenant-wide (shared), but stock is shop-specific
      // We create DEEP copies of Stock objects to prevent reference sharing
      _cachedProducts = List.from(provider.products);

      // ═══════════════════════════════════════════════════════════════════
      // CRITICAL FIX: Create DEEP copy of stock map (not shallow copy)
      // This prevents stale stock from showing if ProductProvider reloads
      // for a different shop in the background
      // ═══════════════════════════════════════════════════════════════════
      _cachedStockMap = {
        for (final entry in provider.stockByProductId.entries)
          entry.key: entry.value.copyWith()  // Deep copy each Stock object
      };
      // CRITICAL FIX: Extract categories FROM products, NOT from provider.categories
      // Daily Sales Entry doesn't call loadCategories(), so provider.categories is empty
      // But each product has embedded category info, so we extract unique categories from products
      final categoryMap = <String, models.Category>{};
      for (final product in _cachedProducts) {
        if (product.category != null && product.category!.id.isNotEmpty) {
          categoryMap[product.category!.id] = product.category!;
        }
      }
      _cachedCategories = categoryMap.values.toList();

      if (kDebugMode) {
        Logger.debug('DailySalesEntry: Extracted ${_cachedCategories.length} unique categories from products');
        for (final cat in _cachedCategories) {
          Logger.debug('   - ${cat.name} (${cat.id})');
        }
      }

      if (kDebugMode) {
        // Verify shop context of cached stock
        final sampleStock = _cachedStockMap.values.firstOrNull;
        if (sampleStock != null) {
          Logger.debug('DailySalesEntry: Stock loaded for shop: ${sampleStock.shopId} (requested: $shopId)');
          Logger.debug('DailySalesEntry: Total ${_cachedProducts.length} products, ${_cachedStockMap.length} stock entries');
          if (sampleStock.shopId != shopId) {
            Logger.warning('WARNING: Stock shopId mismatch! Loaded: ${sampleStock.shopId}, Expected: $shopId');
          }
        }
      }

      // OPTIMIZED: Removed verbose per-product logging, condensed to summary
      if (kDebugMode) {
        // Count products with stock
        int withStock = 0;
        int withoutStock = 0;
        for (var product in _cachedProducts) {
          final stock = _cachedStockMap[product.id];
          if (stock != null && stock.quantity > 0) {
            withStock++;
          } else {
            withoutStock++;
          }
        }
        Logger.debug('DailySalesEntry: Cached ${_cachedProducts.length} products ($withStock with stock, $withoutStock without)');
      }

    } catch (e) {
      if (kDebugMode) {
        Logger.error('DailySalesEntry: Error loading products: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingProducts = false);

        // SMART AUTO-SELECT: Always select best category & size after loading
        // forceReselect=true on shop change ensures fresh selection for new shop
        if (forceReselect || !_hasSetDefaultCategory) {
          _setDefaultCategory(forceReselect: forceReselect);
        }
      }
    }
  }

  /// Sort categories with priority: Whisky first, then Beer, then others alphabetically
  List<models.Category> _getSortedCategories(List<models.Category> categories) {
    final activeCategories = categories.where((c) => c.isActive).toList();

    activeCategories.sort((a, b) {
      final aIndex = _categoryPriority.indexWhere(
        (p) => a.name.toLowerCase().contains(p),
      );
      final bIndex = _categoryPriority.indexWhere(
        (p) => b.name.toLowerCase().contains(p),
      );

      // If both are in priority list, sort by priority
      if (aIndex >= 0 && bIndex >= 0) return aIndex.compareTo(bIndex);
      // If only a is in priority list, a comes first
      if (aIndex >= 0) return -1;
      // If only b is in priority list, b comes first
      if (bIndex >= 0) return 1;
      // Otherwise sort alphabetically
      return a.name.compareTo(b.name);
    });

    return activeCategories;
  }

  /// Get category IDs for the "English" combined filter (Whisky + Rum + Vodka)
  List<String> _getEnglishCategoryIds(List<models.Category> categories) {
    return categories
        .where((c) => _englishCategories.any((e) => c.name.toLowerCase().contains(e)))
        .map((c) => c.id)
        .toList();
  }

  /// Get total product count for "English" combined categories
  int _getEnglishProductCount(List<models.Category> categories) {
    return categories
        .where((c) => _englishCategories.any((e) => c.name.toLowerCase().contains(e)))
        .fold(0, (sum, c) => sum + (c.productCount ?? 0));
  }

  /// Check if a category is part of the "English" group
  bool _isEnglishCategory(models.Category category) {
    return _englishCategories.any((e) => category.name.toLowerCase().contains(e));
  }

  /// Get default category with smart selection:
  /// 1. First try priority order (Whisky > Beer > Rum > etc.) BUT only if category has stock
  /// 2. If no priority category has stock, pick any category with stock
  /// 3. If no categories have stock, fall back to first priority category
  /// 4. If nothing else, return first available category
  models.Category? _getDefaultCategory(List<models.Category> categories) {
    final sorted = _getSortedCategories(categories);
    if (sorted.isEmpty) return null;

    // Use CACHED products/stock - not provider (which can be overwritten by other screens)
    final products = _cachedProducts;
    final stockMap = _cachedStockMap;

    // Helper to get actual stock for a product (from stockMap, not product.stock)
    int getProductStock(models.Product product) {
      final stock = stockMap[product.id];
      return stock?.quantity ?? 0;
    }

    // Helper to check if a category has products with stock > 0
    bool categoryHasStock(models.Category category) {
      return products.any((p) =>
          p.category?.id == category.id &&
          getProductStock(p) > 0);
    }

    // Helper to count products with stock in a category
    int getCategoryStockCount(models.Category category) {
      return products.where((p) =>
          p.category?.id == category.id &&
          getProductStock(p) > 0).length;
    }

    // Log category stock analysis in debug mode
    if (kDebugMode) {
      Logger.debug('Category stock analysis:');
      for (final cat in sorted) {
        final count = getCategoryStockCount(cat);
        final total = products.where((p) => p.category?.id == cat.id).length;
        Logger.debug('   ${cat.name}: $count/$total with stock');
      }
    }

    // 1. Try to find a priority category that has stock
    for (final category in sorted) {
      if (categoryHasStock(category)) {
        if (kDebugMode) {
          Logger.info('Default category: ${category.name} (has ${getCategoryStockCount(category)} products with stock)');
        }
        return category;
      }
    }

    // 2. No category has stock - fall back to first in priority order
    // (This handles the case where stock is zero everywhere)
    if (kDebugMode) {
      Logger.warning('No categories have stock, defaulting to: ${sorted.first.name}');
    }
    return sorted.first;
  }

  /// Set default category on initial load or shop change
  /// Uses smart selection: prioritizes categories with stock available
  /// BEST PRACTICE: Always ensures one category is selected (never empty state)
  void _setDefaultCategory({bool forceReselect = false}) {
    if (!mounted) return;

    if (kDebugMode) {
      Logger.debug('_setDefaultCategory called: forceReselect=$forceReselect, _hasSetDefaultCategory=$_hasSetDefaultCategory');
    }

    // If forcing reselect (e.g., shop change), reset the flags
    if (forceReselect) {
      _hasSetDefaultCategory = false;
      _hasSetDefaultSize = false;
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _selectedSize = null;
      if (kDebugMode) {
        Logger.debug('   Flags reset for fresh selection');
      }
    }

    // Use CACHED categories - not provider (which can be overwritten by other screens)
    final defaultCategory = _getDefaultCategory(_cachedCategories);

    if (defaultCategory != null) {
      if (kDebugMode) {
        Logger.debug('   Found default category: ${defaultCategory.name} (id: ${defaultCategory.id})');
      }
      setState(() {
        _selectedCategoryId = defaultCategory.id;
        _selectedCategoryName = defaultCategory.name;
        _hasSetDefaultCategory = true;
      });
      if (kDebugMode) {
        Logger.debug('   setState complete: _selectedCategoryName=$_selectedCategoryName');
      }

      // Load sizes for this category and auto-select the best one
      _loadSizesForCategoryAndAutoSelect(defaultCategory.id);

      if (kDebugMode) {
        Logger.info('DailySalesEntry: Auto-selected category: ${defaultCategory.name}');
      }
    } else {
      // FALLBACK: If no categories with stock, still select first available category
      // This ensures we NEVER have an empty category state (best UX practice)
      final sortedCategories = _getSortedCategories(_cachedCategories);
      if (sortedCategories.isNotEmpty) {
        final fallbackCategory = sortedCategories.first;
        setState(() {
          _selectedCategoryId = fallbackCategory.id;
          _selectedCategoryName = fallbackCategory.name;
          _hasSetDefaultCategory = true;
        });
        _loadSizesForCategoryAndAutoSelect(fallbackCategory.id);
        if (kDebugMode) {
          Logger.warning('DailySalesEntry: No categories with stock, fallback to: ${fallbackCategory.name}');
        }
      } else {
        if (kDebugMode) {
          Logger.warning('DailySalesEntry: No categories available at all');
        }
      }
    }
  }

  /// Get sorted category names as strings (for filter delegate)
  List<String> _getSortedCategoryNames(List<models.Category> categories) {
    return _getSortedCategories(categories).map((c) => c.name).toList();
  }

  /// Sort category name strings by priority (Whisky first, then Beer, etc.)
  List<String> _sortCategoryNamesByPriority(List<String> categoryNames) {
    final sorted = List<String>.from(categoryNames);
    sorted.sort((a, b) {
      final aIndex = _categoryPriority.indexWhere(
        (p) => a.toLowerCase().contains(p),
      );
      final bIndex = _categoryPriority.indexWhere(
        (p) => b.toLowerCase().contains(p),
      );

      // If both are in priority list, sort by priority
      if (aIndex >= 0 && bIndex >= 0) return aIndex.compareTo(bIndex);
      // If only a is in priority list, a comes first
      if (aIndex >= 0) return -1;
      // If only b is in priority list, b comes first
      if (bIndex >= 0) return 1;
      // Otherwise sort alphabetically
      return a.compareTo(b);
    });
    return sorted;
  }

  /// Load available sizes for selected category and SMART auto-select
  /// BEST PRACTICE: Always ensures one size is selected for better UX
  /// Prioritizes sizes that have products with actual stock
  void _loadSizesForCategoryAndAutoSelect(String? categoryId) {
    if (!mounted) return;

    final productProvider = context.read<ProductProvider>();
    final shopProvider = context.read<ShopSelectionProvider>();

    if (kDebugMode) {
      Logger.debug('DailySalesEntry: Loading sizes for categoryId=$categoryId, shopId=${shopProvider.selectedShopId}');
    }

    // Load sizes from backend with category filter
    productProvider.loadAvailableSizes(
      shopId: shopProvider.selectedShopId,
      categoryId: categoryId,
    ).then((_) {
      // CRITICAL: Check mounted before setState in async callback
      if (!mounted) {
        if (kDebugMode) Logger.debug('DailySalesEntry: Widget not mounted, skipping size auto-select');
        return;
      }

      final availableSizes = productProvider.availableSizesWithCounts;
      if (kDebugMode) {
        Logger.debug('DailySalesEntry: Loaded ${availableSizes.length} sizes: ${availableSizes.map((s) => s.size).join(", ")}');
      }

      if (availableSizes.isEmpty) {
        if (kDebugMode) {
          Logger.warning('DailySalesEntry: No sizes available for category $categoryId');
        }
        return;
      }

      // SMART SIZE SELECTION: Find size with most products that have stock
      String? bestSize;
      int maxStockCount = 0;

      for (final sizeWithCount in availableSizes) {
        // Count products with this size AND stock > 0
        // Use categoryName match instead of categoryId for consistency with UI filter
        // BEST PRACTICE: Normalize sizes for comparison to handle case differences
        final normalizedFilterSize = ProductConstants.normalizeSize(sizeWithCount.size);
        final productsWithSizeAndStock = _cachedProducts.where((p) {
          if (_selectedCategoryName != null && p.category?.name != _selectedCategoryName) return false;
          final productSize = ProductConstants.normalizeSize(p.size);
          if (productSize != normalizedFilterSize) return false;
          final stock = _cachedStockMap[p.id];
          return stock != null && stock.quantity > 0;
        }).length;

        if (kDebugMode) {
          Logger.debug('   Size ${sizeWithCount.size}: $productsWithSizeAndStock products with stock');
        }

        if (productsWithSizeAndStock > maxStockCount) {
          maxStockCount = productsWithSizeAndStock;
          bestSize = sizeWithCount.size;
        }
      }

      // If no size has stock, just pick the first available size
      // CRITICAL: This ensures we ALWAYS have a size selected
      if (bestSize == null && availableSizes.isNotEmpty) {
        bestSize = availableSizes.first.size;
        if (kDebugMode) {
          Logger.debug('DailySalesEntry: No size with stock found, using first: $bestSize');
        }
      }

      if (bestSize != null) {
        // CRITICAL: Normalize to ensure consistent format with chip IDs
        final normalizedBestSize = ProductConstants.normalizeSize(bestSize!);
        setState(() {
          _selectedSize = normalizedBestSize;
          _hasSetDefaultSize = true;
        });

        if (kDebugMode) {
          Logger.info('DailySalesEntry: Auto-selected size: $_selectedSize (has $maxStockCount products with stock)');
        }
      } else {
        if (kDebugMode) {
          Logger.error('DailySalesEntry: Could not auto-select any size!');
        }
      }
    }).catchError((error) {
      if (kDebugMode) {
        Logger.error('DailySalesEntry: Error loading sizes: $error');
      }
    });
  }

  /// Handle category selection change
  /// BEST PRACTICE: Always keeps one category selected (no deselection allowed)
  void _onCategoryChanged(String? categoryId, String? categoryName) {
    if (!mounted) return;

    // BEST PRACTICE: Don't allow deselection - one category must always be selected
    // If user taps same category, just ignore (keeps current selection)
    if (!_isEnglishFilterSelected && _selectedCategoryId == categoryId) {
      // Already selected, do nothing (prevents empty state)
      return;
    }

    // Select new category (clears English filter)
    setState(() {
      _isEnglishFilterSelected = false; // Clear English filter
      _selectedCategoryId = categoryId;
      _selectedCategoryName = categoryName;
      _selectedCategoryIds = categoryId != null ? [categoryId] : [];
      _selectedSize = null;
      _hasSetDefaultSize = false;
    });

    // Reload sizes for new category and SMART auto-select
    _loadSizesForCategoryAndAutoSelect(categoryId);

    HapticFeedbackUtil.selection();
  }

  /// Handle "English" combined filter selection (Whisky + Rum + Vodka)
  void _onEnglishFilterSelected(List<String> categoryIds) async {
    if (!mounted) return;

    // Already selected, do nothing
    if (_isEnglishFilterSelected) {
      return;
    }

    // Select English combined filter
    setState(() {
      _isEnglishFilterSelected = true;
      _selectedCategoryId = null; // Clear single category
      _selectedCategoryName = _englishGroupName;
      _selectedCategoryIds = categoryIds;
      _selectedSize = null;
      _hasSetDefaultSize = false;
    });

    if (kDebugMode) {
      Logger.info('DailySalesEntry: English filter selected (${categoryIds.length} categories)');
    }

    // Reload sizes for combined categories and auto-select
    _loadSizesForEnglishAndAutoSelect(categoryIds);

    HapticFeedbackUtil.selection();
  }

  /// Load sizes for English combined categories (Whisky + Rum + Vodka)
  Future<void> _loadSizesForEnglishAndAutoSelect(List<String> categoryIds) async {
    if (!mounted) return;

    final shopProvider = context.read<ShopSelectionProvider>();
    final productProvider = context.read<ProductProvider>();

    // Load sizes for combined categories
    await productProvider.loadAvailableSizes(
      shopId: shopProvider.selectedShopId,
      categoryIds: categoryIds,
    );

    if (!mounted) return;

    // SMART SIZE SELECTION: Pick size with most products that have stock
    final availableSizes = productProvider.availableSizesWithCounts;
    if (availableSizes.isEmpty) {
      if (kDebugMode) {
        Logger.warning('DailySalesEntry: No sizes available for English categories');
      }
      return;
    }

    // Find size with most products that have stock in English categories
    String? bestSize;
    int maxStockCount = 0;

    for (final sizeWithCount in availableSizes) {
      // Count products with this size that have stock
      // BEST PRACTICE: Normalize sizes for comparison to handle case differences
      final normalizedFilterSize = ProductConstants.normalizeSize(sizeWithCount.size);
      final productsWithSizeAndStock = _cachedProducts.where((p) {
        // Must be in one of English categories
        if (p.category == null) return false;
        if (!_englishCategories.any((e) => p.category!.name.toLowerCase().contains(e))) return false;
        // Must match size (normalized)
        final productSize = ProductConstants.normalizeSize(p.size);
        if (productSize != normalizedFilterSize) return false;
        // Must have stock
        final stock = _cachedStockMap[p.id];
        return stock != null && stock.quantity > 0;
      }).length;

      if (productsWithSizeAndStock > maxStockCount) {
        maxStockCount = productsWithSizeAndStock;
        bestSize = sizeWithCount.size;
      }
    }

    // Fall back to first available size if none have stock
    bestSize ??= availableSizes.first.size;

    if (mounted) {
      // CRITICAL: Normalize to ensure consistent format with chip IDs
      final normalizedBestSize = ProductConstants.normalizeSize(bestSize!);
      setState(() {
        _selectedSize = normalizedBestSize;
        _hasSetDefaultSize = true;
      });
      if (kDebugMode) {
        Logger.info('DailySalesEntry: English auto-selected size: $normalizedBestSize');
      }
    }
  }

  /// Handle size selection change
  /// BEST PRACTICE: Always keeps one size selected (no deselection allowed)
  void _onSizeChanged(String? size) {
    if (!mounted) return;

    // CRITICAL: Normalize to ensure consistent format with chip IDs
    final normalizedSize = size != null ? ProductConstants.normalizeSize(size) : null;

    // BEST PRACTICE: Don't allow deselection - one size must always be selected
    if (_selectedSize == normalizedSize) {
      // Already selected, do nothing (prevents empty state)
      return;
    }

    setState(() {
      _selectedSize = normalizedSize;
    });

    HapticFeedbackUtil.selection();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, child) {
        // ═══════════════════════════════════════════════════════════════
        // PopScope for silent auto-save on exit (Swiggy/Zomato style)
        // CRITICAL FIX: Now saves complete product items, not just quantities
        // ═══════════════════════════════════════════════════════════════
        Widget content = PopScope(
          canPop: true, // Allow swipe-back gesture (iOS edge swipe)
          onPopInvokedWithResult: (bool didPop, dynamic result) async {
            // Draft save disabled — fresh state every time
          },
          child: Stack(
            children: [
              // Main content
              _currentStep == 0 ? _buildStep1Products() : _buildStep2Payment(),

              // ═══════════════════════════════════════════════════════════════
              // LOADING OVERLAY (Modern UX - shows during draft restore or OCR)
              // ═══════════════════════════════════════════════════════════════
              if (_isDraftRestoreInProgress || _isLoadingProducts || _isOcrProcessing)
                _buildLoadingOverlay(),
            ],
          ),
        );

        // When in standalone mode (showHeader: true), wrap in Scaffold
        // This provides Material ancestor required for TextField widgets
        if (widget.showHeader) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: content,
          );
        }

        return content;
      },
    );
  }

  /// Build modern loading overlay with message
  Widget _buildLoadingOverlay() {
    return Container(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated loading indicator
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Loading message (use OCR message if OCR is processing)
            Text(
              _isOcrProcessing ? _ocrProgressMessage : _loadingMessage,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            Text(
              _isOcrProcessing ? 'Extracting items from receipts...' : 'Please wait...',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Get current product quantities as map (for draft saving)
  Map<String, int> _getProductQuantitiesMap() {
    final quantities = <String, int>{};
    for (var entry in _quantityControllers.entries) {
      final text = entry.value.text;
      if (text.isNotEmpty) {
        final qty = int.tryParse(text);
        if (qty != null && qty > 0) {
          quantities[entry.key] = qty;
        }
      }
    }
    return quantities;
  }

  // ========== STEP 1: PRODUCTS & QUANTITIES ==========

  Widget _buildStep1Products() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, child) {
        final shopProvider = context.watch<ShopSelectionProvider>();
        // Note: We watch ProductProvider but use our CACHED data for display
        // to prevent ProductsGridScreen from affecting our UI
        context.watch<ProductProvider>();

        // Use CACHED products/stock - not provider (which can be overwritten)
        final allProducts = _cachedProducts;
        final stockMap = _cachedStockMap;

        // Get products with stock > 0
        var productsWithStock = allProducts.where((product) {
          final stock = stockMap[product.id];
          return stock != null && stock.quantity > 0;
        }).toList();

        // Apply filters and sorting
        productsWithStock = _getFilteredAndSortedProducts(productsWithStock);

        // Calculate filter data
        final allProductsWithStock = allProducts.where((product) {
          final stock = stockMap[product.id];
          return stock != null && stock.quantity > 0;
        }).toList();

        final categories = _getUniqueCategories(allProductsWithStock);

        // DYNAMIC: Sizes from products filtered by selected category/categories
        final productsForSizeFilter = allProductsWithStock.where((product) {
          // Handle "English" combined filter (multiple categories)
          if (_isEnglishFilterSelected && _selectedCategoryIds.isNotEmpty) {
            return _selectedCategoryIds.contains(product.category?.id);
          }
          // Handle single category selection
          if (_selectedCategoryName != null && _selectedCategoryName != _englishGroupName &&
              product.category?.name != _selectedCategoryName) {
            return false;
          }
          return true;
        }).toList();
        final sizes = _getAvailableSizes(productsForSizeFilter);

        // Calculate dynamic filter height (compact - search moved to header)
        double filterHeight = 8.0; // Top padding only (search removed)
        if (categories.isNotEmpty) filterHeight += 48.0; // Category row
        if (sizes.isNotEmpty) filterHeight += 48.0; // Size row

        // GestureDetector to dismiss keyboard on tap outside input fields
        return GestureDetector(
          onTap: _dismissKeyboard,
          behavior: HitTestBehavior.translucent,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // NOTE: Removed keyboard dismissal on scroll - it was causing
              // auto-close on last product when system scrolls to reveal input
              // Keyboard is dismissed only via GestureDetector tap-outside
              return false; // Allow notification to propagate
            },
            child: Stack(
              children: [
                CustomScrollView(
                  // Use primary scroll controller for NestedScrollView coordination
                  primary: true,
                  slivers: [
                // JSX-matched header: centered title with back/hamburger
                SliverAppBar(
                  pinned: true,
                  elevation: 0,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  toolbarHeight: 48,
                  automaticallyImplyLeading: false,
                  titleSpacing: 0,
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(height: 1, color: const Color(0xFFEAEDF1)),
                  ),
                  title: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        // Back button — blue circle with chevron (JSX: w-10 h-10 bg-[#1349B8])
                        if (widget.showHeader)
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1349B8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () => _showShopDatePickerModal(provider, shopProvider),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: const BoxDecoration(
                                color: Color(0xFF1349B8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.person, color: Colors.white, size: 18),
                            ),
                          ),
                        // Centered title (JSX: font-heading 19px semibold)
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _showShopDatePickerModal(provider, shopProvider),
                            onLongPress: () {
                              HapticFeedback.heavyImpact();
                              _showClearAllConfirmation();
                            },
                            child: Text(
                              'Sales Entry',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserratAlternates(
                                fontSize: 19,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF18181B),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                        // Bell icon (JSX: bg-[#EBF1FA] with notification dot)
                        GestureDetector(
                          onTap: _openQuickSale,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEBF1FA),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 17, height: 17,
                                child: SvgPicture.asset('assets/icons/bell_notification.svg', fit: BoxFit.contain),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ═══ Search bar + Filter toggle button (JSX-matched) ═══
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                    child: Row(
                      children: [
                        // Search input — white bg with border + shadow
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 16, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search, color: Color(0xFFBBBBBB), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _isSearchExpanded
                                    ? TextField(
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          hintText: 'Search products...',
                                          hintStyle: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB), fontWeight: FontWeight.w500),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                                        onChanged: (query) => setState(() => _searchQuery = query.toLowerCase()),
                                      )
                                    : GestureDetector(
                                        onTap: () {
                                          setState(() => _isSearchExpanded = true);
                                          HapticFeedbackUtil.selection();
                                        },
                                        child: const Text('Search products...', style: TextStyle(fontSize: 14, color: Color(0xFFBBBBBB), fontWeight: FontWeight.w500)),
                                      ),
                                ),
                                if (_isSearchExpanded)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() { _isSearchExpanded = false; _searchQuery = ''; });
                                      HapticFeedbackUtil.selection();
                                    },
                                    child: const Icon(Icons.close, size: 18, color: Color(0xFF999999)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Filter toggle button
                        GestureDetector(
                          onTap: () {
                            setState(() => _isFiltersVisible = !_isFiltersVisible);
                            HapticFeedbackUtil.selection();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _isFiltersVisible ? const Color(0xFF1E40AF) : const Color(0xFFE3EBF5),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.filter_list_rounded,
                                color: _isFiltersVisible ? Colors.white : const Color(0xFF0E2C6A),
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ═══ Category & Size filters (collapsible — hidden by default) ═══
                if (_isFiltersVisible)
                  SliverPersistentHeader(
                    pinned: true,
                    floating: false,
                    delegate: _FilterHeaderDelegate(
                      height: filterHeight,
                      selectedCategoryName: _selectedCategoryName,
                      selectedSize: _selectedSize,
                      categories: [_englishGroupName, ..._sortCategoryNamesByPriority(categories)],
                      sizes: sizes,
                      onCategoryChanged: (categoryName) {
                        if (categoryName == _englishGroupName) {
                          final englishCategoryIds = _getEnglishCategoryIds(_cachedCategories);
                          _onEnglishFilterSelected(englishCategoryIds);
                          return;
                        }
                        final providerCategories = _cachedCategories;
                        final cat = providerCategories.firstWhere(
                          (c) => c.name == categoryName,
                          orElse: () => providerCategories.isNotEmpty
                              ? providerCategories.first
                              : models.Category(
                                  id: '',
                                  name: categoryName,
                                  description: '',
                                  isActive: true,
                                  sortOrder: 0,
                                ),
                        );
                        _onCategoryChanged(cat.id, categoryName);
                      },
                      onSizeChanged: (size) {
                        _onSizeChanged(size);
                      },
                      productsCount: productsWithStock.length,
                    ),
                  ),

                // ═══ Show entry count (JSX-matched) — ABOVE upload bill ═══
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Row(
                      children: [
                        Container(width: 20, height: 2, decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(1))),
                        const SizedBox(width: 8),
                        Text(
                          'Show ${productsWithStock.length} Entry\'s',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1B63E2)),
                        ),
                        if (_selectedCategoryName != null || _selectedSize != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCategoryId = null;
                                _selectedCategoryName = null;
                                _selectedSize = null;
                                _isEnglishFilterSelected = false;
                                _selectedCategoryIds = [];
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Clear filters', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE65100))),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // ═══ Upload Sales Bill card (JSX-matched — dashed border) ═══
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                    child: GestureDetector(
                      onTap: _showImagePickerOptions,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _attachedImages.isEmpty ? const Color(0xFFEFF6FF) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _attachedImages.isEmpty ? const Color(0xFF8EAEF5) : const Color(0xFF66BB6A),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: _attachedImages.isEmpty ? const Color(0xFFE1EDFA) : const Color(0xFFC8E6C9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: _attachedImages.isEmpty
                                    ? SizedBox(
                                        width: 18, height: 18,
                                        child: SvgPicture.asset('assets/icons/upload_bill.svg', fit: BoxFit.contain),
                                      )
                                    : const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32), size: 18),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Upload Sales Bill',
                                    style: GoogleFonts.montserratAlternates(
                                      fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF141F39),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _attachedImages.isEmpty
                                        ? 'Attach Invoice Image or PDF'
                                        : '${_attachedImages.length} image${_attachedImages.length > 1 ? "s" : ""} attached',
                                    style: TextStyle(
                                      fontSize: 10.5, fontWeight: FontWeight.w500,
                                      color: _attachedImages.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF2E7D32),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_attachedImages.isNotEmpty)
                              const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20)
                            else
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 18, height: 18,
                                    child: SvgPicture.asset('assets/icons/camera_viewfinder.svg', fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Product Rows (Card-based layout - no header needed)
                if (shopProvider.selectedShopId == null)
                  SliverFillRemaining(
                    child: _buildEmptyState(
                      icon: CupertinoIcons.building_2_fill,
                      title: 'Select a Shop',
                      subtitle: 'Choose a shop from the header above to view products',
                    ),
                  )
                else if (productsWithStock.isEmpty)
                  SliverFillRemaining(
                    child: _buildEmptyState(
                      icon: CupertinoIcons.cube_box,
                      title: 'No Products Available',
                      subtitle: 'No products with stock found in selected shop',
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final product = productsWithStock[index];
                        final stock = stockMap[product.id];
                        final stockQty = stock?.quantity ?? 0;

                        // Get or create controller with progress listener
                        final controller = _getOrCreateQtyController(product.id);

                        return KeyedSubtree(
                          key: ValueKey(product.id),
                          child: _buildProductRow(
                            product: product,
                            stockQty: stockQty,
                            controller: controller,
                            isEven: index % 2 == 0,
                          ),
                        );
                      },
                      childCount: productsWithStock.length,
                    ),
                  ),

                // Bottom Padding - Extra space for keyboard visibility
                const SliverToBoxAdapter(
                  child: SizedBox(height: 200),
                ),
              ],
            ),

              // Fixed Next Button at Bottom - Keyboard Aware
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).viewInsets.bottom,
                child: _buildStep1NextButton(provider),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  Widget _buildFilterRow(DailySalesProvider provider) {
    // Use CACHED products/stock - not provider (which can be overwritten by ProductsGridScreen)
    // Get all products with stock > 0
    final productsWithStock = _cachedProducts.where((product) {
      final stock = _cachedStockMap[product.id];
      return stock != null && stock.quantity > 0;
    }).toList();

    // Filter products by selected category (for dynamic size options) - single selection
    final productsForSizeFilter = productsWithStock.where((product) {
      // Apply category filter (single-select)
      if (_selectedCategoryName != null &&
          product.category?.name != _selectedCategoryName) {
        return false;
      }
      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final matchesSearch = product.name.toLowerCase().contains(_searchQuery) ||
            (product.brand?.name.toLowerCase().contains(_searchQuery) ?? false) ||
            product.sku.toLowerCase().contains(_searchQuery) ||
            (product.category?.name.toLowerCase().contains(_searchQuery) ?? false);
        if (!matchesSearch) return false;
      }
      return true;
    }).toList();

    final categories = _getUniqueCategories(productsWithStock);
    // DYNAMIC: Sizes from products filtered by selected categories
    final sizes = _getAvailableSizes(productsForSizeFilter);

    return Column(
      children: [
        // Header with Shop, Date, Quick Sale, Sort
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              // Shop Selector
              Expanded(
                flex: 2,
                child: ShopSelectorWidget(
                  padding: EdgeInsets.zero,
                  showLabel: false,
                  onShopChanged: (shopId) async {
                    if (shopId != null) {
                      // ═══════════════════════════════════════════════════════════
                      // SHOP CHANGE HANDLER - Proper isolation of shop-specific data
                      // ═══════════════════════════════════════════════════════════
                      if (kDebugMode) {
                        Logger.info('[DailySalesEntry] SHOP CHANGE: switching to $shopId');
                        Logger.debug('   Old cached stock: ${_cachedStockMap.length} items');
                      }

                      // CRITICAL: Save old shop draft, clear items, then switch
                      await provider.setShop(shopId);

                      // Clear local quantity controllers for fresh start
                      _clearQuantityControllers();
                      _quantityValidationErrors.clear();
                      _validationErrorMessages.clear();

                      // CRITICAL: Clear local stock cache BEFORE loading new shop
                      _cachedStockMap.clear();

                      // Force reselect category/size for new shop (smart selection)
                      await _loadProducts(shopId, forceReselect: true);

                      if (kDebugMode) {
                        Logger.debug('   New cached stock: ${_cachedStockMap.length} items');
                        final sampleStock = _cachedStockMap.values.firstOrNull;
                        if (sampleStock != null) {
                          Logger.debug('   Sample stock shopId: ${sampleStock.shopId}');
                        }
                      }

                      // Check for draft in new shop and restore if exists
                      await _checkAndRestoreDraft(provider);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Date Picker
              InkWell(
                onTap: () => _selectDate(provider),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.calendar, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        Formatters.date(provider.recordDate),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Quick Sale
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _openQuickSale,
                child: Icon(
                  CupertinoIcons.camera_fill,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),

              // Sort
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _showSortOptions,
                child: Icon(
                  CupertinoIcons.sort_down,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
            ],
          ),
        ),

        // Search Bar (iOS Style) - Collapsible on scroll
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: _isSearchBarVisible ? 56 : 0,
          clipBehavior: Clip.hardEdge,
          decoration: const BoxDecoration(),
          child: IOSSearchBar(
            hint: 'Search products...',
            onSearch: (query) => setState(() => _searchQuery = query.toLowerCase()),
            onClear: () => setState(() => _searchQuery = ''),
          ),
        ),

        // === CATEGORY FILTER CHIPS (Single Selection, Whisky First) ===
        // NOTE: We use Consumer to trigger rebuilds but use CACHED categories
        Consumer<ProductProvider>(
          builder: (context, productProvider, _) {
            final sortedCategories = _getSortedCategories(_cachedCategories);

            // Calculate English product count BEFORE early return
            final englishProductCount = _getEnglishProductCount(_cachedCategories);
            final englishCategoryIds = _getEnglishCategoryIds(_cachedCategories);

            // Debug logging for English filter - ALWAYS print to diagnose issue
            if (kDebugMode) {
              Logger.debug('[DailySalesEntry] English filter debug:');
              Logger.debug('   _cachedCategories: ${_cachedCategories.length} items');
              Logger.debug('   sortedCategories: ${sortedCategories.length} items (isActive filter applied)');
              Logger.debug('   Raw categories: ${_cachedCategories.map((c) => '${c.name}(active:${c.isActive})').toList()}');
              Logger.debug('   englishCategoryIds: $englishCategoryIds (${englishCategoryIds.length} matches)');
              Logger.debug('   englishProductCount: $englishProductCount');
              Logger.debug('   Will show English chip: ${englishCategoryIds.isNotEmpty}');
            }

            if (sortedCategories.isEmpty) return const SizedBox.shrink();

            return Container(
              height: 44,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // ═══════════════════════════════════════════════════════════════
                  // "ENGLISH" COMBINED CHIP - Shows Whisky + Rum + Vodka together
                  // First chip, always visible at the start
                  // ═══════════════════════════════════════════════════════════════
                  if (englishCategoryIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _onEnglishFilterSelected(englishCategoryIds),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isEnglishFilterSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: _isEnglishFilterSelected ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('🥃', style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 4),
                              Text(
                                englishProductCount > 0 ? '$_englishGroupName ($englishProductCount)' : _englishGroupName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _isEnglishFilterSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // ═══════════════════════════════════════════════════════════════
                  // INDIVIDUAL CATEGORY CHIPS - Whisky first, then Beer, etc.
                  // ═══════════════════════════════════════════════════════════════
                  ...sortedCategories.map((category) {
                    final isSelected = !_isEnglishFilterSelected && _selectedCategoryId == category.id;
                    final productCount = category.productCount;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _onCategoryChanged(category.id, category.name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                            border: isSelected ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _getCategoryEmoji(category.name),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (productCount ?? 0) > 0 ? '${category.name} ($productCount)' : category.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),

        // === SIZE FILTER CHIPS (Single Selection, Auto-selected) ===
        Consumer<ProductProvider>(
          builder: (context, productProvider, _) {
            final rawSizesWithCounts = productProvider.availableSizesWithCounts;
            if (rawSizesWithCounts.isEmpty) return const SizedBox.shrink();

            // BEST PRACTICE: Deduplicate sizes by normalizing to uppercase ML format
            // This handles cases where backend returns both "180ML" and "180ml"
            final Map<String, int> normalizedSizeCounts = {};
            for (final sizeWithCount in rawSizesWithCounts) {
              final normalizedSize = ProductConstants.normalizeSize(sizeWithCount.size);
              normalizedSizeCounts[normalizedSize] =
                  (normalizedSizeCounts[normalizedSize] ?? 0) + sizeWithCount.productCount;
            }

            // Convert back to list and sort by size value (90ML, 180ML, 375ML, etc.)
            final sizesWithCounts = normalizedSizeCounts.entries
                .map((e) => (size: e.key, productCount: e.value))
                .toList()
              ..sort((a, b) {
                final sizeA = int.tryParse(a.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                final sizeB = int.tryParse(b.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                return sizeA.compareTo(sizeB);
              });

            // CRITICAL FIX: Auto-select first size if none selected but sizes are available
            // This defensive check ensures we NEVER show products without a size filter
            // Handles race conditions where loadAvailableSizes completes before _loadSizesForCategoryAndAutoSelect
            if (_selectedSize == null && sizesWithCounts.isNotEmpty && !_hasSetDefaultSize) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedSize == null) {
                  // CRITICAL: Normalize to ensure consistent format with chip IDs
                  final normalizedSize = ProductConstants.normalizeSize(sizesWithCounts.first.size);
                  setState(() {
                    _selectedSize = normalizedSize;
                    _hasSetDefaultSize = true;
                  });
                  if (kDebugMode) {
                    Logger.debug('DailySalesEntry: FALLBACK auto-selected size: $_selectedSize');
                  }
                }
              });
            }

            return Container(
              height: 40,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // Size chips with counts (deduplicated and normalized)
                  ...sizesWithCounts.map((sizeWithCount) {
                    // Compare sizes for selection — case-insensitive for range labels
                    final isSelected = _selectedSize != null &&
                        (_selectedSize == sizeWithCount.size ||
                         _selectedSize!.toLowerCase() == sizeWithCount.size.toLowerCase());
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: GestureDetector(
                        onTap: () => _onSizeChanged(sizeWithCount.size),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: isSelected ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          child: Text(
                            '${sizeWithCount.size} (${sizeWithCount.productCount})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 4),
      ],
    );
  }

  String _getCategoryEmoji(String categoryName) {
    final lower = categoryName.toLowerCase();
    switch (lower) {
      case 'beer':
        return '🍺';
      case 'whiskey':
      case 'whisky':
        return '🥃';
      case 'wine':
        return '🍷';
      case 'vodka':
        return '🍸';
      case 'rum':
        return '🥃';
      case 'gin':
        return '🍸';
      case 'brandy':
        return '🍾';
      case 'tequila':
        return '🌵';
      default:
        return '🍾';
    }
  }




  Widget _buildProductsTable(DailySalesProvider provider) {
    final shopProvider = context.watch<ShopSelectionProvider>();

    if (shopProvider.selectedShopId == null) {
      return _buildEmptyState(
        icon: CupertinoIcons.building_2_fill,
        title: 'Select a Shop',
        subtitle: 'Choose a shop from the filter above to view products',
      );
    }

    if (_isLoadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }

    // Note: We watch ProductProvider for rebuild triggers but use CACHED data
    context.watch<ProductProvider>();

    // Use CACHED products/stock - not provider (which can be overwritten by ProductsGridScreen)
    final allProducts = _cachedProducts;
    final stockMap = _cachedStockMap;

    // 🔍 DEBUG: Detailed product-stock matching analysis
    if (kDebugMode) {
      Logger.debug('\n========== PRODUCT-STOCK MATCHING DEBUG ==========');
      Logger.debug('Total CACHED products: ${allProducts.length}');
      Logger.debug('Total CACHED stock entries: ${stockMap.length}');

      // Show all product IDs
      if (allProducts.isNotEmpty) {
        Logger.debug('\nProduct IDs loaded:');
        for (var product in allProducts) {
          Logger.debug('   - ${product.id} - ${product.name}');
        }
      } else {
        Logger.warning('   NO PRODUCTS LOADED!');
      }

      // Show all stock productIds
      if (stockMap.isNotEmpty) {
        Logger.debug('\nStock productIds in map:');
        for (var entry in stockMap.entries) {
          Logger.debug('   - ${entry.key} - Quantity: ${entry.value.quantity}');
        }
      } else {
        Logger.warning('   NO STOCK ENTRIES!');
      }
    }

    // Show ONLY products with stock > 0 (user requirement)
    // Filter products to only show those with stock available
    var productsWithStock = allProducts.where((product) {
      final stock = stockMap[product.id];
      return stock != null && stock.quantity > 0;
    }).toList();

    if (kDebugMode) {
      Logger.debug('\nFILTERING FOR STOCK > 0:');
      Logger.debug('   Total products loaded: ${allProducts.length}');
      Logger.debug('   Total stock entries: ${stockMap.length}');
      Logger.debug('   Products with stock > 0: ${productsWithStock.length}');
    }

    // Apply filters and sorting to products with stock
    productsWithStock = _getFilteredAndSortedProducts(productsWithStock);

    if (kDebugMode) {
      Logger.debug('   After filters applied: ${productsWithStock.length}');
      Logger.debug('========================================\n');
    }

    if (productsWithStock.isEmpty) {
      return _buildEmptyState(
        icon: CupertinoIcons.cube_box,
        title: 'No Products With Stock',
        subtitle: 'No products with stock > 0 found for this shop',
      );
    }

    return Column(
      children: [
        // Compact Table Header - Optimized for mobile
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Optimized padding
          child: Row(
            children: [
              // Space for avatar (32px - reduced)
              const SizedBox(width: 32),
              const SizedBox(width: 4), // Reduced spacing

              // Product name - using Expanded for maximum space
              Expanded(
                child: Text(
                  'Product',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4), // Reduced spacing

              // Size - optimized width
              SizedBox(
                width: 48,
                child: Text(
                  'Size',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4), // Reduced spacing

              // Stock - optimized width
              SizedBox(
                width: 38,
                child: Text(
                  'Stk',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4), // Reduced spacing

              // Price - optimized width
              SizedBox(
                width: 48,
                child: Text(
                  'Price',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 4), // Reduced spacing

              // Qty - optimized width
              SizedBox(
                width: 60,
                child: Text(
                  'Qty',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Table Body
        Expanded(
          child: ListView.builder(
            controller: _scrollController, // For collapsing search bar
            padding: const EdgeInsets.only(bottom: 120), // Extra space for button
            itemCount: productsWithStock.length,
            itemBuilder: (context, index) {
              final product = productsWithStock[index];
              final stock = stockMap[product.id];
              final stockQty = stock?.quantity ?? 0;

              // Get or create controller with progress listener
              final controller = _getOrCreateQtyController(product.id);

              return KeyedSubtree(
                key: ValueKey(product.id),
                child: _buildProductRow(
                  product: product,
                  stockQty: stockQty,
                  controller: controller,
                  isEven: index % 2 == 0,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// JSX-matched product card — rounded card with image, info, quantity stepper
  Widget _buildProductRow({
    required models.Product product,
    required int stockQty,
    required TextEditingController controller,
    required bool isEven,
  }) {
    String sizeML = _extractProductSize(product);
    final categoryName = product.category?.name.toUpperCase() ?? 'CUSTOM';
    final bool isGoodStock = stockQty > 10;
    int saleQty = int.tryParse(controller.text) ?? 0;
    int closingStock = stockQty - saleQty;
    final hasValidationError = _quantityValidationErrors[product.id] == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0F0F2), width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 14, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ LEFT: Product Image (80x80) with MRP badge ═══
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D1A30), Color(0xFF1A1030), Color(0xFF3A1A10), Color(0xFFD4700A)],
                stops: [0.0, 0.4, 0.7, 1.0],
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: product.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          memCacheHeight: 200,
                          placeholder: (context, url) => const SizedBox(),
                          errorWidget: (context, url, error) => Center(
                            child: Icon(Icons.liquor, size: 30, color: Colors.white.withValues(alpha: 0.3)),
                          ),
                        )
                      : Center(
                          child: Icon(Icons.liquor, size: 30, color: Colors.white.withValues(alpha: 0.3)),
                        ),
                ),
                // MRP badge — top-left dark overlay (JSX: bg-[#0A1736]/90 rounded-br)
                if (product.mrp > 0 || product.sellingPrice > 0)
                  Positioned(
                    top: 0,
                    left: 0,
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
                          Text('₹ ${product.mrp > 0 ? product.mrp.toStringAsFixed(0) : product.sellingPrice.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // ═══ RIGHT: Product Info ═══
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Name + 3-dot menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.cleanName,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF141F39), height: 1.25),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Row 2: Category tag + stock badge
                Row(
                  children: [
                    // Category pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        '$categoryName - $sizeML',
                        style: const TextStyle(fontSize: 8.5, color: Color(0xFF6B7280), fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Stock badge
                    SvgPicture.asset(
                      isGoodStock ? 'assets/icons/inventory_green_sm.svg' : 'assets/icons/inventory_amber_sm.svg',
                      width: 12, height: 12),
                    const SizedBox(width: 3),
                    Text(
                      '$stockQty in stock',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isGoodStock ? const Color(0xFF10B981) : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Row 3: Price + closing stock + quantity stepper
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Left: Price + closing stock
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹ ${product.mrp > 0 ? product.mrp.toStringAsFixed(0) : product.sellingPrice > 0 ? product.sellingPrice.toStringAsFixed(0) : "--"}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0B1536)),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              SvgPicture.asset('assets/icons/box_closing.svg', width: 11, height: 11,
                                colorFilter: const ColorFilter.mode(Color(0xFF6B7280), BlendMode.srcIn)),
                              const SizedBox(width: 3),
                              Text(
                                '$closingStock closing stock',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: closingStock < 0 ? AppColors.error : const Color(0xFF6B7280),
                                  fontWeight: closingStock < 0 ? FontWeight.w700 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Right: Pill-style quantity stepper (JSX: bg-[#F4F7FB] rounded-xl)
                    Container(
                      decoration: BoxDecoration(
                        color: hasValidationError ? AppColors.error.withValues(alpha: 0.08) : const Color(0xFFF4F7FB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Minus
                          GestureDetector(
                            onTap: () {
                              final current = int.tryParse(controller.text) ?? 0;
                              if (current > 0) {
                                controller.text = '${current - 1}';
                                controller.selection = TextSelection.collapsed(offset: controller.text.length);
                                _validateQuantity(product.id, controller.text, stockQty);
                                context.read<DailySalesProvider>().triggerInstantSave();
                                HapticFeedbackUtil.light();
                              }
                            },
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(child: Icon(Icons.remove, size: 14, color: Color(0xFF6B7280))),
                            ),
                          ),
                          // Inline quantity input
                          SizedBox(
                            width: 28,
                            height: 26,
                            child: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: hasValidationError ? AppColors.error : const Color(0xFF141F39),
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                                isDense: true,
                                hintText: '0',
                                hintStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFFCCCCCC)),
                              ),
                              onChanged: (text) {
                                _validateQuantity(product.id, text, stockQty);
                                context.read<DailySalesProvider>().triggerInstantSave();
                              },
                            ),
                          ),
                          // Plus
                          GestureDetector(
                            onTap: () {
                              final current = int.tryParse(controller.text) ?? 0;
                              controller.text = '${current + 1}';
                              controller.selection = TextSelection.collapsed(offset: controller.text.length);
                              _validateQuantity(product.id, controller.text, stockQty);
                              context.read<DailySalesProvider>().triggerInstantSave();
                              HapticFeedbackUtil.light();
                            },
                            child: Container(
                              width: 26,
                              height: 26,
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
          ),
        ],
      ),
    );
  }


  /// Helper: Build placeholder image for products without images
  Widget _buildImagePlaceholder(models.Product product) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.15),
            Theme.of(context).colorScheme.primary.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.liquor,
              size: 32,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
            ),
            const SizedBox(height: 4),
            Text(
              (product.brand?.name ?? product.name).substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to extract size from product
  // BEST PRACTICE: Always returns uppercase ML format (e.g., '180ML', '750ML')
  // to match ProductConstants and backend database format
  String _extractProductSize(models.Product product) {
    // Try to get size from product size field
    if (product.size.isNotEmpty) {
      // Use ProductConstants to ensure consistent uppercase ML format
      return ProductConstants.normalizeSize(product.size);
    }

    // Try to extract from product name
    final nameRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML|ltr|LTR|L)', caseSensitive: false);
    final nameMatch = nameRegex.firstMatch(product.name);
    if (nameMatch != null) {
      String sizeStr = nameMatch.group(0)!;
      // Handle liters -> ML conversion
      if (sizeStr.toLowerCase().contains('ltr') ||
          (sizeStr.toLowerCase().contains('l') && !sizeStr.toLowerCase().contains('ml'))) {
        final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(sizeStr);
        if (numMatch != null) {
          final liters = double.tryParse(numMatch.group(0)!) ?? 0;
          return '${(liters * 1000).toInt()}ML';
        }
      }
      // Normalize to uppercase ML format
      return ProductConstants.normalizeSize(sizeStr);
    }

    // Try subcategory name
    if (product.subcategory?.name != null) {
      final sizeRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML)', caseSensitive: false);
      final match = sizeRegex.firstMatch(product.subcategory!.name);
      if (match != null) {
        return ProductConstants.normalizeSize(match.group(0)!);
      }
    }

    // Default
    return '-';
  }

  // Helper method to extract size as numeric value (ML) for sorting
  int _extractSizeValue(models.Product product) {
    // Try to get size from product size field
    if (product.size.isNotEmpty) {
      final numMatch = RegExp(r'(\d+)').firstMatch(product.size);
      if (numMatch != null) {
        return int.tryParse(numMatch.group(0)!) ?? 0;
      }
    }

    // Try to extract from product name
    final nameRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML|ltr|LTR|L)', caseSensitive: false);
    final nameMatch = nameRegex.firstMatch(product.name);
    if (nameMatch != null) {
      String sizeStr = nameMatch.group(1)!;
      double size = double.tryParse(sizeStr) ?? 0;
      // Convert liters to ML if needed
      if (nameMatch.group(0)!.toLowerCase().contains('ltr') ||
          nameMatch.group(0)!.toLowerCase().contains('l')) {
        size = size * 1000;
      }
      return size.toInt();
    }

    return 0; // Default for products without size
  }

  // Helper method to clean product name by removing size
  String _cleanProductName(String name) {
    // Remove size patterns like "- 330ML", "- 500ml", "- 650 ML", "- 1LTR"
    String cleanName = name
        .replaceAll(RegExp(r'\s*-\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\d+(?:\.\d+)?\s*(?:ml|ML|ltr|LTR|L)\b', caseSensitive: false), '')
        .trim();

    // Remove trailing dash if present
    if (cleanName.endsWith('-')) {
      cleanName = cleanName.substring(0, cleanName.length - 1).trim();
    }

    return cleanName.isNotEmpty ? cleanName : name;
  }

  /// Calculate summary data for the bottom display
  Map<String, dynamic> _calculateSummary() {
    // Use CACHED products/stock - not provider (which can be overwritten by ProductsGridScreen)
    int totalStock = 0;
    int itemsCount = 0;
    int totalQuantity = 0;
    double totalAmount = 0.0;

    // Calculate total stock from CACHED data
    for (var stock in _cachedStockMap.values) {
      totalStock += stock.quantity;
    }

    // Calculate items being sold and total amount
    for (var entry in _quantityControllers.entries) {
      final productId = entry.key;
      final qty = int.tryParse(entry.value.text) ?? 0;
      if (qty > 0) {
        // Find product to get price - skip if not found (use CACHED products)
        final productIndex = _cachedProducts.indexWhere((p) => p.id == productId);
        if (productIndex == -1) continue; // Skip products not in current shop

        itemsCount++;
        totalQuantity += qty;

        final product = _cachedProducts[productIndex];
        totalAmount += (product.sellingPrice) * qty;
      }
    }

    return {
      'totalStock': totalStock,
      'itemsCount': itemsCount,
      'totalQuantity': totalQuantity,
      'totalAmount': totalAmount,
    };
  }

  /// Build the summary row widget
  Widget _buildSummaryRow() {
    final data = _calculateSummary();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem(
            'Stock',
            '${data['totalStock']}',
            CupertinoIcons.cube_box,
            Theme.of(context).colorScheme.primary,
          ),
          Container(width: 1, height: 30, color: Theme.of(context).colorScheme.outlineVariant),
          _buildSummaryItem(
            'Qty',
            '${data['totalQuantity']}',
            CupertinoIcons.cart_fill,
            Theme.of(context).colorScheme.primary,
          ),
          Container(width: 1, height: 30, color: Theme.of(context).colorScheme.outlineVariant),
          _buildSummaryItem(
            'Total',
            '₹${data['totalAmount'].toStringAsFixed(0)}',
            CupertinoIcons.money_dollar,
            Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1NextButton(DailySalesProvider provider) {
    // Count total products with stock (filtered view)
    final allProductsWithStock = _cachedProducts.where((product) {
      final stock = _cachedStockMap[product.id];
      return stock != null && stock.quantity > 0;
    }).toList();
    final filteredProducts = _getFilteredAndSortedProducts(allProductsWithStock);
    final totalCount = filteredProducts.length;

    // Use ValueListenableBuilder so only the bottom bar rebuilds on progress change
    // (NOT the entire widget tree which would cause TextFields to lose focus)
    return ValueListenableBuilder<int>(
      valueListenable: _filledCountNotifier,
      builder: (context, filledCount, _) {
        final allFilled = totalCount > 0 && filledCount >= totalCount;

        if (allFilled) {
          return BottomActionBar(
            label: 'Review',
            onPressed: () => _showSalesSummary(provider),
          );
        } else {
          return BottomActionBar(
            progressText: '$filledCount/$totalCount',
            progressFilled: filledCount,
            progressTotal: totalCount,
          );
        }
      },
    );
  }

  /// Navigate to Sales Summary screen as a review step before payment
  void _showSalesSummary(DailySalesProvider provider) {
    if (_isSummaryShowing) return; // Prevent double-push
    _isSummaryShowing = true;

    // Check mandatory image attachment
    if (_attachedImages.isEmpty) {
      _isSummaryShowing = false;
      SnackbarHelper.showError(context, 'Please upload Sales Bill before proceeding');
      return;
    }

    // Validate quantities
    if (_hasValidationErrors()) {
      _isSummaryShowing = false;
      final errorCount = _getValidationErrorCount();
      SnackbarHelper.showError(
        context,
        '$errorCount product(s) have invalid quantities - please fix errors shown in red',
      );
      return;
    }

    // Build summary items from filled products with qty > 0
    // (0 = not sold, accounted for — only show sold items in summary)
    final items = <SalesSummaryItem>[];
    bool hasAnySale = false;

    // Use filtered products (same order as displayed list)
    final allProductsWithStock = _cachedProducts.where((product) {
      final stock = _cachedStockMap[product.id];
      return stock != null && stock.quantity > 0;
    }).toList();
    final filteredProducts = _getFilteredAndSortedProducts(allProductsWithStock);

    for (final product in filteredProducts) {
      final controller = _quantityControllers[product.id];
      if (controller == null || controller.text.isEmpty) continue;
      final qty = int.tryParse(controller.text) ?? 0;
      if (qty > 0) hasAnySale = true;
      if (qty <= 0) continue; // Don't show 0-qty items in summary

      final stock = _cachedStockMap[product.id];
      final stockQty = stock?.quantity ?? 0;

      items.add(SalesSummaryItem(
        productId: product.id,
        name: product.name,
        price: product.sellingPrice,
        quantity: qty,
        mrp: product.sellingPrice,
        stock: stockQty,
        closingStock: stockQty - qty,
      ));
    }

    if (!hasAnySale) {
      _isSummaryShowing = false;
      SnackbarHelper.showError(context, 'Enter quantity for at least one product');
      return;
    }

    // Build available products list for "Add Missing Item" feature
    final availableForMissing = <SalesSummaryItem>[];
    final addedIds = items.map((i) => i.productId).toSet();
    for (final product in _cachedProducts) {
      if (addedIds.contains(product.id)) continue;

      // Match category — same logic as product display filter
      final catName = (product.category?.name ?? '').toLowerCase();
      if (_isEnglishFilterSelected) {
        if (catName.contains('beer')) continue; // English = non-beer
      } else if (_selectedCategoryName != null) {
        if (product.category?.name != _selectedCategoryName) continue;
      }

      // Match size range
      if (_selectedSize != null) {
        if (!SizeRangeConstants.sizeMatchesRange(product.size, _selectedSize!, _selectedCategoryName ?? 'Whisky')) continue;
      }

      final stock = _cachedStockMap[product.id];
      availableForMissing.add(SalesSummaryItem(
        productId: product.id,
        name: product.cleanName,
        price: product.mrp > 0 ? product.mrp : product.sellingPrice,
        quantity: 0,
        mrp: product.mrp > 0 ? product.mrp : product.sellingPrice,
        stock: stock?.quantity ?? 0,
        closingStock: stock?.quantity ?? 0,
      ));
    }

    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SalesSummaryScreen(
          items: items,
          availableProducts: availableForMissing,
          isAIMode: true, // Enable "Add Missing" feature
          saleCategory: _selectedCategoryName,
          saleSize: _selectedSize,
          onSubmitItems: (finalItems) {
            Navigator.pop(context); // Pop summary screen
            _submitFromSummaryItems(provider, finalItems);
          },
        ),
      ),
    ).then((_) {
      // Reset guard when Summary is popped (back button or programmatic)
      _isSummaryShowing = false;
    });
  }

  Widget _buildInlineStat({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // Show modal bottom sheet for shop and date selection
  void _showShopDatePickerModal(DailySalesProvider salesProvider, ShopSelectionProvider shopProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Shop & Date Selection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Shop Selector
            Text('Shop', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: shopProvider.selectedShopId,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  items: shopProvider.shops.map((shop) {
                    return DropdownMenuItem(
                      value: shop.id,
                      child: Text(shop.name, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (shopId) async {
                    if (shopId != null) {
                      // ═══════════════════════════════════════════════════════════
                      // SHOP CHANGE (MODAL) - Same isolation as main handler
                      // ═══════════════════════════════════════════════════════════
                      if (kDebugMode) {
                        Logger.info('[DailySalesEntry] SHOP CHANGE (modal): switching to $shopId');
                      }

                      final shop = shopProvider.shops.firstWhere((s) => s.id == shopId);
                      await shopProvider.selectShop(shop);

                      // CRITICAL: Save old shop draft, clear items, then switch
                      await salesProvider.setShop(shopId);

                      // Clear local controllers
                      _clearQuantityControllers();
                      _quantityValidationErrors.clear();
                      _validationErrorMessages.clear();

                      // CRITICAL: Clear local stock cache BEFORE loading new shop
                      _cachedStockMap.clear();

                      await _loadProducts(shopId, forceReselect: true);

                      // Check for draft in new shop and restore if exists
                      await _checkAndRestoreDraft(salesProvider);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Date Selector
            Text('Date', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                Navigator.pop(context); // Close modal first
                // IMPORTANT: Users cannot select today's date - only past dates
                // This prevents confusion with current day's ongoing sales
                final yesterday = DateTime.now().subtract(const Duration(days: 1));
                final initialDate = salesProvider.recordDate.isAfter(yesterday)
                    ? yesterday
                    : salesProvider.recordDate;
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: initialDate,
                  firstDate: DateTime(2020),
                  lastDate: yesterday, // Block today's date
                );
                if (pickedDate != null) {
                  salesProvider.setRecordDate(pickedDate);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      _formatDateLong(salesProvider.recordDate),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // Format date for header (short format)
  String _formatDateShort(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // Format date for modal (long format)
  String _formatDateLong(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // Check if two dates are the same day (ignoring time)
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }

  // Open quick sale (OCR) screen
  void _openQuickSale() {
    final shopProvider = context.read<ShopSelectionProvider>();
    final shopId = shopProvider.selectedShopId;

    if (shopId == null) {
      SnackbarHelper.showError(context, 'Please select a shop first');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuickSaleOCRScreen(shopId: shopId),
      ),
    );
  }

  /// Show Clear All confirmation dialog
  void _showClearAllConfirmation() {
    final provider = context.read<DailySalesProvider>();
    final itemCount = provider.items.length;

    if (itemCount == 0) {
      SnackbarHelper.showInfo(context, 'No items to clear');
      return;
    }

showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Clear All Items?'),
        content: Text(
          'This will remove all $itemCount items and reset payment amounts.\n\n'
          'The draft for this shop will also be deleted.',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Clear All'),
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllItems();
            },
          ),
        ],
      ),
    );
  }

  /// Clear all items, payments, and delete draft
  Future<void> _clearAllItems() async {
    final provider = context.read<DailySalesProvider>();

    // Clear items in provider
    provider.clearItems();

    // Reset payment amounts
    provider.setCashAmount(0);
    provider.setCardAmount(0);
    provider.setUpiAmount(0);
    provider.setCreditAmount(0);
    provider.setExpenseAmount(0);
    provider.setNotes('');

    // Clear local controllers
    _clearQuantityControllers();
    _quantityValidationErrors.clear();
    _validationErrorMessages.clear();
    _cashController.clear();
    _cardController.clear();
    _upiController.clear();
    _creditController.clear();
    _notesController.clear();
    _attachedImages.clear();
    _attachedImageHashes.clear(); // Clear content hashes for deduplication

    // Delete draft from storage (local + backend)
    await provider.clearDraft();

    // Reset to step 0
    if (mounted) {
      setState(() {
        _currentStep = 0;
      });
    }

    SnackbarHelper.showSuccess(context, 'All items cleared');
    if (kDebugMode) {
      Logger.info('[DailySalesEntry] All items cleared and draft deleted');
    }
  }

  /// Submit directly from Sales Summary — uses the edited items list.
  void _submitFromSummaryItems(DailySalesProvider provider, List<SalesSummaryItem> finalItems) {
    provider.clearItems();

    for (final summaryItem in finalItems) {
      if (summaryItem.quantity <= 0) continue;
      // Find matching product by ID (reliable) or name (fallback)
      final idx = summaryItem.productId.isNotEmpty
          ? _cachedProducts.indexWhere((p) => p.id == summaryItem.productId)
          : _cachedProducts.indexWhere((p) => p.name == summaryItem.name);
      if (idx == -1) continue;
      provider.addItem(_cachedProducts[idx], quantity: summaryItem.quantity);
    }

    if (provider.items.isEmpty) {
      SnackbarHelper.showError(context, 'No items to submit');
      return;
    }

    // Auto-fill payment: entire total as cash
    final total = provider.totalItemsAmount;
    provider.setCashAmount(total);
    provider.setCardAmount(0);
    provider.setUpiAmount(0);
    provider.setCreditAmount(0);
    provider.setExpenseAmount(0);

    // Submit directly
    _submitRecord(provider);
  }

  void _proceedToPayment(DailySalesProvider provider) {
    Logger.info('[DailySalesEntry] ========== PROCEED TO PAYMENT ==========');
    Logger.debug('[DailySalesEntry] Provider hashCode: ${provider.hashCode}');
    Logger.debug('[DailySalesEntry] Provider imageUrls BEFORE clearItems: ${provider.imageUrls}');

    // ✅ CHECK FOR VALIDATION ERRORS FIRST
    if (_hasValidationErrors()) {
      final errorCount = _getValidationErrorCount();
      Logger.error('[DailySalesEntry] Found $errorCount validation error(s) - cannot proceed');
      SnackbarHelper.showError(
        context,
        '$errorCount product(s) have invalid quantities - please fix errors shown in red',
      );
      return;
    }
    Logger.info('[DailySalesEntry] All quantities validated successfully');

    Logger.debug('[DailySalesEntry] Collecting quantities from ${_quantityControllers.length} products');

    // Collect products with quantities > 0 (use CACHED data)
    final allProducts = _cachedProducts;
    Logger.debug('[DailySalesEntry] Total CACHED products available: ${allProducts.length}');

    provider.clearItems();
    Logger.debug('[DailySalesEntry] Cleared existing items in provider');
    Logger.debug('[DailySalesEntry] Provider imageUrls AFTER clearItems: ${provider.imageUrls}');

    int addedCount = 0;
    for (var product in allProducts) {
      final controller = _quantityControllers[product.id];
      if (controller != null && controller.text.isNotEmpty) {
        final quantity = int.tryParse(controller.text);
        Logger.debug('   ${product.name}: Quantity = ${controller.text} (parsed: $quantity)');
        if (quantity != null && quantity > 0) {
          provider.addItem(product, quantity: quantity);
          addedCount++;
          Logger.debug('      Added to cart - Price: ₹${product.sellingPrice}, Total: ₹${product.sellingPrice * quantity}');
        } else {
          Logger.warning('      Skipped (invalid quantity)');
        }
      }
    }

    Logger.info('[DailySalesEntry] Total items added: $addedCount');
    Logger.info('[DailySalesEntry] Cart total amount: ₹${provider.totalItemsAmount}');

    if (addedCount == 0) {
      Logger.error('[DailySalesEntry] No items added - showing error');
      SnackbarHelper.showError(context, 'Please enter quantities for at least one product');
      return;
    }

    // ========== EDIT MODE: Auto-update payment when cart total changes ==========
    // When editing a record, if user changes quantities, auto-update cash to match new total
    // This provides better UX than leaving old payment amounts that don't match
    if (widget.editRecord != null) {
      final newTotal = provider.totalItemsAmount;
      final currentPayment = provider.cashAmount + provider.cardAmount +
                             provider.upiAmount + provider.creditAmount;

      // If payment doesn't match new total, auto-fill cash with new total
      // (preserving the original payment ratio: all cash by default for simplicity)
      if ((currentPayment - newTotal).abs() > 0.01) {
        Logger.info('[DailySalesEntry] EDIT MODE: Cart total changed, updating payment');
        Logger.debug('   Old payment: ₹$currentPayment → New total: ₹$newTotal');

        // Set cash to new total, clear other payment methods
        _cashController.text = newTotal.toStringAsFixed(0);
        _cardController.text = '';
        _upiController.text = '';
        _creditController.text = '';

        provider.setCashAmount(newTotal);
        provider.setCardAmount(0);
        provider.setUpiAmount(0);
        provider.setCreditAmount(0);

        Logger.info('   Auto-filled cash with new total: ₹$newTotal');
      }
    }

    // NOTE: Cash autofill removed for NEW entries - user enters Cash and UPI amounts manually each day
    Logger.info('[DailySalesEntry] Proceeding to payment step');
    setState(() {
      _currentStep = 1;
    });
    Logger.info('[DailySalesEntry] ========== PAYMENT STEP ACTIVE ==========');
  }

  // ========== STEP 2: PAYMENT BREAKDOWN ==========

  Widget _buildStep2Payment() {
    return Consumer<DailySalesProvider>(
      builder: (context, provider, child) {
        return Column(
          children: [
            Expanded(
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // JSX-matched Sales Summary cards
                    _buildJsxInvoiceSummary(provider),
                    const SizedBox(height: 16),

                    // Mandatory Image Attachment
                    _buildImageAttachmentCard(),
                    const SizedBox(height: 16),

                    // Payment Breakdown
                    _buildPaymentBreakdownCard(provider),
                    const SizedBox(height: 16),

                    // Expense Table
                    _buildExpenseTableCard(provider),
                    const SizedBox(height: 16),

                    // Notes
                    _buildNotesCard(provider),
                  ],
                ),
                ),
              ),
            ),

            // Bottom Buttons
            _buildStep2BottomButtons(provider),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(DailySalesProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Summary',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),

            // Items Count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Products',
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Text(
                  '${provider.totalItemsCount}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Total Quantity
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Quantity',
                  style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                Text(
                  '${provider.items.fold(0, (sum, item) => sum + item.quantity)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Gradient Divider
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.outlineVariant, Theme.of(context).colorScheme.surfaceContainerHighest!, Theme.of(context).colorScheme.outlineVariant],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Total Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Amount',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  Formatters.currency(provider.totalItemsAmount),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========== INVOICE-STYLE TABLE (NEW) ==========

  /// Groups items by size and returns a sorted map
  /// Items within each size group are sorted by Price (low→high), then Brand (alphabetical)
  /// Consistent with Daily Sales Entry product list sorting
  Map<String, List<dynamic>> _groupItemsBySize(List<dynamic> items) {
    final Map<String, List<dynamic>> grouped = {};

    for (final item in items) {
      final size = (item.size ?? 'Other').toString().toUpperCase();
      grouped.putIfAbsent(size, () => []);
      grouped[size]!.add(item);
    }

    // Sort sizes by numeric value (180ML, 375ML, 750ML, etc.)
    final sortedKeys = grouped.keys.toList()..sort((a, b) {
      final aNum = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;
      final bNum = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 9999;
      return aNum.compareTo(bNum);
    });

    // Sort items within each size group by Price (low→high), then Brand (alphabetical)
    for (final key in sortedKeys) {
      grouped[key]!.sort((a, b) {
        // Primary: Price (low to high)
        final priceA = (a.unitPrice ?? 0.0) as double;
        final priceB = (b.unitPrice ?? 0.0) as double;
        if (priceA != priceB) {
          return priceA.compareTo(priceB);
        }
        // Secondary: Brand/Product name (alphabetical)
        final nameA = (a.brandName ?? a.productName ?? '').toString().toLowerCase();
        final nameB = (b.brandName ?? b.productName ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    }

    return Map.fromEntries(sortedKeys.map((k) => MapEntry(k, grouped[k]!)));
  }

  /// JSX-matched invoice summary — same design as SalesSummaryScreen
  /// #FAFBFD cards with #ECEEF2 border, numbered items, stock/qty/mrp pills,
  /// Grand Total in cream #FFF9E6 card
  Widget _buildJsxInvoiceSummary(DailySalesProvider provider) {
    final items = provider.items;
    final grandTotal = provider.totalItemsAmount;
    final totalQty = items.fold<int>(0, (sum, item) => sum + (item.quantity ?? 0));

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFD),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFECEEF2)),
        ),
        child: const Center(
          child: Text('No items added yet', style: TextStyle(color: Color(0xFF999999), fontSize: 14)),
        ),
      );
    }

    return Column(
      children: [
        // Item cards
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final qty = item.quantity ?? 0;
          final price = item.unitPrice ?? 0.0;
          final total = price * qty;
          final stock = _cachedStockMap[item.productId]?.quantity ?? 0;
          final closingStock = stock - qty;

          return Container(
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFECEEF2), width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Number + Name + Price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${index + 1}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF0D47A1)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _cleanProductName(item.productName ?? ''),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF1A1A2E)),
                      ),
                    ),
                    Text(
                      '\u20B9 ${total.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF1A1A2E)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Info pills
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Stock
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_rounded, size: 14, color: stock > 20 ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F)),
                          const SizedBox(width: 4),
                          Text(
                            '$stock in stock',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: stock > 20 ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F)),
                          ),
                        ],
                      ),
                      // Qty pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECEEF3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Qty - $qty',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF555555)),
                        ),
                      ),
                      // MRP pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECEEF3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'MRP - ${price.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Color(0xFF888888)),
                        ),
                      ),
                      // Closing stock
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF888888)),
                          const SizedBox(width: 4),
                          Text(
                            '$closingStock closing stock',
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF888888)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Edit link — go back to products step
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: GestureDetector(
                    onTap: () => setState(() => _currentStep = 0),
                    child: const Text(
                      'Edit \u25B6',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1A1A2E)),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        // Grand Total card — cream background
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9E6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF0E6C0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Grand Total',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: Color(0xFF1A1A2E)),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECEEF3),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'Total Quantity - $totalQty',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF888888)),
                    ),
                  ),
                ],
              ),
              Text(
                '\u20B9 ${_formatIndianAmount(grandTotal)}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 28, color: Color(0xFF1A1A2E)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Indian number formatting (1,23,456)
  String _formatIndianAmount(double amount) {
    final intPart = amount.toInt();
    final str = intPart.toString();
    if (str.length > 3) {
      final last3 = str.substring(str.length - 3);
      var rest = str.substring(0, str.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      return '${parts.join(",")},${last3}';
    }
    return amount.toStringAsFixed(0);
  }

  Widget _buildInvoiceTable(DailySalesProvider provider) {
    final groupedItems = _groupItemsBySize(provider.items);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Invoice Header
          _buildInvoiceHeader(provider),

          // Product Line Items grouped by size
          if (provider.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    'No items added yet',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
                  ),
                ],
              ),
            )
          else
            ...groupedItems.entries.map((sizeGroup) =>
              _buildSizeGroupSection(sizeGroup.key, sizeGroup.value, provider)
            ),

          // Invoice Footer (Grand Totals)
          _buildInvoiceFooter(provider),
        ],
      ),
    );
  }

  /// Builds a section for each size group with header and product rows
  Widget _buildSizeGroupSection(String size, List<dynamic> items, DailySalesProvider provider) {
    // Calculate totals for this size group
    final totalQty = items.fold<int>(0, (sum, item) => sum + (item.quantity ?? 0) as int);
    final totalAmount = items.fold<double>(0.0, (sum, item) {
      final qty = item.quantity ?? 0;
      final price = item.unitPrice ?? 0.0;
      return sum + (qty * price);
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Size Divider Header (like receipt_table_widget)
        _buildSizeDividerHeader(size),

        // Product rows for this size (long-press to delete)
        ...items.asMap().entries.map((entry) =>
          _buildCompactInvoiceRow(entry.key + 1, entry.value, provider)
        ),

        // Size group summary footer
        _buildSizeGroupFooter(items.length, totalQty, totalAmount),
      ],
    );
  }

  /// Size divider with centered text (matches receipt_table_widget style)
  Widget _buildSizeDividerHeader(String size) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Expanded(child: Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.35), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              size,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.85),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(child: Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.35), thickness: 1)),
        ],
      ),
    );
  }

  /// Summary footer for each size group (Products, Qty, Total)
  Widget _buildSizeGroupFooter(int productCount, int totalQty, double totalAmount) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Products count
          _buildFooterStat(
            icon: Icons.inventory_2_outlined,
            label: 'Products',
            value: '$productCount',
          ),
          Container(width: 1, height: 28, color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
          // Total Qty
          _buildFooterStat(
            icon: Icons.numbers,
            label: 'Qty',
            value: '$totalQty',
          ),
          Container(width: 1, height: 28, color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
          // Total Amount
          _buildFooterStat(
            icon: Icons.currency_rupee,
            label: 'Total',
            value: '₹${totalAmount.toStringAsFixed(0)}',
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  /// Individual stat item for size group footer
  Widget _buildFooterStat({
    required IconData icon,
    required String label,
    required String value,
    bool isPrimary = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: isPrimary ? 14 : 13,
            fontWeight: FontWeight.w700,
            color: isPrimary ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.primary.withOpacity(0.9),
          ),
        ),
      ],
    );
  }

  /// Builds the size group header with size badge and summary
  Widget _buildSizeGroupHeader(String size, int productCount, int totalQty, double totalAmount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.12),
            Theme.of(context).colorScheme.primary.withOpacity(0.05),
          ],
        ),
      ),
      child: Row(
        children: [
          // Size Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              size,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Summary Stats
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Products count
                _buildSizeSummaryChip(
                  icon: Icons.inventory_2_outlined,
                  label: 'Products',
                  value: '$productCount',
                ),
                const SizedBox(width: 10),

                // Total Qty
                _buildSizeSummaryChip(
                  icon: Icons.numbers,
                  label: 'Qty',
                  value: '$totalQty',
                ),
                const SizedBox(width: 10),

                // Total Amount
                _buildSizeSummaryChip(
                  icon: Icons.currency_rupee,
                  label: 'Total',
                  value: '₹${totalAmount.toStringAsFixed(0)}',
                  isPrimary: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Summary chip for size group header
  Widget _buildSizeSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    bool isPrimary = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPrimary ? Theme.of(context).colorScheme.primary.withOpacity(0.15) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isPrimary ? Theme.of(context).colorScheme.primary.withOpacity(0.3) : Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isPrimary ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isPrimary ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// Text style for table headers
  TextStyle get _invoiceHeaderStyle => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: Theme.of(context).colorScheme.onSurface,
    letterSpacing: 0.3,
  );

  /// Compact table header for size groups (without Size column since it's in header)
  Widget _buildCompactTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('#', style: _invoiceHeaderStyle, textAlign: TextAlign.center),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 5,
            child: Text('Product', style: _invoiceHeaderStyle),
          ),
          Expanded(
            flex: 1,
            child: Text('Qty', style: _invoiceHeaderStyle, textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: Text('MRP', style: _invoiceHeaderStyle, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 2,
            child: Text('Amount', style: _invoiceHeaderStyle, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  /// Compact invoice row (without Size column)
  /// Long-press to delete item with confirmation
  Widget _buildCompactInvoiceRow(int index, dynamic item, DailySalesProvider provider) {
    final isEven = index % 2 == 0;
    final fullProductName = item.productName ?? 'Unknown Product';
    final size = item.size ?? '-';
    final quantity = item.quantity ?? 0;
    final unitPrice = item.unitPrice ?? 0.0;
    final totalAmount = item.totalAmount ?? (quantity * unitPrice);

    // Remove size from product name if it appears at the end
    String productName = fullProductName;
    if (size != '-' && size.toString().isNotEmpty) {
      final sizePatterns = [' - $size', ' -$size', '- $size', ' $size', '-$size'];
      for (final pattern in sizePatterns) {
        if (productName.toUpperCase().endsWith(pattern.toUpperCase())) {
          productName = productName.substring(0, productName.length - pattern.length).trim();
          break;
        }
      }
    }

    return GestureDetector(
      onLongPress: () => _showDeleteInvoiceItemConfirmation(item, productName, provider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isEven ? Theme.of(context).colorScheme.surfaceContainerHighest : Theme.of(context).colorScheme.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Index Number
            SizedBox(
              width: 24,
              child: Text(
                '$index',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 6),

            // Product Name
            Expanded(
              flex: 5,
              child: Text(
                productName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Quantity
            Expanded(
              flex: 1,
              child: Text(
                '$quantity',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // Unit Price
            Expanded(
              flex: 2,
              child: Text(
                '₹${unitPrice.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.right,
              ),
            ),

            // Total Amount
            Expanded(
              flex: 2,
              child: Text(
                '₹${totalAmount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show iOS-style confirmation dialog to delete item from invoice
  void _showDeleteInvoiceItemConfirmation(dynamic item, String productName, DailySalesProvider provider) {
    HapticFeedback.heavyImpact();

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Remove Item'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Remove "$productName" from invoice?',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);

              // Find the item index in provider's items list
              final itemIndex = provider.items.indexWhere((i) =>
                i.productId == item.productId
              );

              if (itemIndex >= 0) {
                // Also clear the quantity controller for this product
                final productId = item.productId;
                if (_quantityControllers.containsKey(productId)) {
                  _quantityControllers[productId]?.text = '';
                }

                provider.removeItem(itemIndex);
                HapticFeedback.mediumImpact();

                SnackbarHelper.showInfo(
                  context,
                  '$productName removed from invoice',
                );

                // If no items left, go back to products step
                if (provider.items.isEmpty) {
                  setState(() {
                    _currentStep = 0;
                  });
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceHeader(DailySalesProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.12),
            Theme.of(context).colorScheme.primary.withOpacity(0.06),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SALES INVOICE',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Date: ${DateFormat('dd MMM yyyy').format(provider.recordDate)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.receipt_long,
              size: 28,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceFooter(DailySalesProvider provider) {
    final totalQuantity = provider.items.fold(0, (sum, item) => sum + (item.quantity ?? 0));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          // Total Items Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Items',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${provider.totalItemsCount}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Total Quantity Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Quantity',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '$totalQuantity',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Gradient Divider
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Grand Total Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GRAND TOTAL',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.85),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  Formatters.currency(provider.totalItemsAmount),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ========== MANDATORY IMAGE ATTACHMENT (NEW) ==========

  Widget _buildImageAttachmentCard() {
    // Get provider for existing URLs in edit mode
    final provider = context.read<DailySalesProvider>();
    final existingUrls = provider.imageUrls;
    final hasExistingImages = existingUrls.isNotEmpty;
    final hasNewImages = _attachedImages.isNotEmpty;
    final hasAnyImages = hasExistingImages || hasNewImages;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: !hasAnyImages
            ? Border.all(color: AppColors.warning.withOpacity(0.3), width: 1.5)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with mandatory indicator
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.attach_file_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Attach Receipt/Image',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 12, color: AppColors.error),
                      const SizedBox(width: 4),
                      Text(
                        'Required',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Show existing images from provider (Edit mode - already uploaded)
            if (hasExistingImages) ...[
              // Label for existing images
              Row(
                children: [
                  Icon(Icons.cloud_done_outlined, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    '${existingUrls.length} existing image${existingUrls.length > 1 ? 's' : ''} (already uploaded)',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: existingUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) =>
                      _buildExistingImageThumbnail(existingUrls[index]),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Show newly attached images (local files)
            if (hasNewImages) ...[
              if (hasExistingImages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${_attachedImages.length} new image${_attachedImages.length > 1 ? 's' : ''} to upload',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                height: 110,  // Larger for better visibility
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachedImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _buildImageThumbnail(index, _attachedImages[index]),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Add Image Buttons - Professional Document Scanner
            Row(
              children: [
                Expanded(
                  child: _buildAddImageButton(
                    Icons.document_scanner_rounded,
                    'Scan Receipt',
                    _scanReceiptsWithValidation,  // Real-time validation scanner
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAddImageButton(
                    Icons.photo_library_rounded,
                    'Import & Scan',
                    _importAndScan,
                  ),
                ),
              ],
            ),

            // Validation warning - only show if NO images at all
            if (!hasAnyImages) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'At least one image is required to submit',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Show success indicator with total count
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    '${existingUrls.length + _attachedImages.length} total image${(existingUrls.length + _attachedImages.length) > 1 ? 's' : ''} ready',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(int index, File image) {
    final qualityScore = _imageQualityScores[image.path];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Tappable thumbnail - opens full preview
        GestureDetector(
          onTap: () => _showImagePreview(index, image),
          child: Container(
            width: 100,  // Larger for better visibility
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: qualityScore != null
                    ? Color(qualityScore.quality.colorValue).withOpacity(0.5)
                    : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    image,
                    fit: BoxFit.cover,
                    cacheWidth: 300,  // Optimize memory
                    cacheHeight: 300,
                  ),
                  // Premium gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                        ],
                      ),
                    ),
                  ),
                  // Tap to view hint
                  const Positioned(
                    bottom: 6,
                    right: 6,
                    child: Icon(
                      Icons.zoom_in_rounded,
                      size: 18,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Quality badge - shows blur quality
        if (qualityScore != null)
          Positioned(
            top: 4,
            right: 4,
            child: ImageQualityBadge(
              quality: qualityScore.quality,
              size: 20,
            ),
          ),
        // Delete button - Modern style
        Positioned(
          top: -8,
          left: -8,
          child: GestureDetector(
            onTap: () => _confirmRemoveImage(index),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
        // Image index badge - Modern pill style
        Positioned(
          bottom: 6,
          left: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Analyze blur quality of an attached image
  Future<void> _analyzeImageQuality(File imageFile) async {
    try {
      DebugLogService.info('DailySales', 'Analyzing quality for: ${imageFile.path}');
      final result = await _imagePreprocessingService.calculateBlurScoreFromFile(imageFile);

      if (mounted) {
        setState(() {
          _imageQualityScores[imageFile.path] = result;
        });
        DebugLogService.info('DailySales', 'Quality: ${result.quality.name} (${result.score.toStringAsFixed(1)})');
      }
    } catch (e) {
      DebugLogService.error('DailySales', 'Quality analysis error: $e');
    }
  }

  /// Build thumbnail for existing images (from provider URLs - already uploaded)
  /// These are shown in edit mode for records that already have images
  Widget _buildExistingImageThumbnail(String imageUrl) {
    // Construct full URL if relative path
    final fullUrl = imageUrl.startsWith('http')
        ? imageUrl
        : '${ApiConfig.baseUrl}$imageUrl';

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: fullUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Icon(Icons.broken_image, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            // Cloud icon overlay to indicate already uploaded
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Icon(
                  Icons.cloud_done,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show full-screen image preview with zoom and delete option
  /// Best practice: Consistent with camera preview UX
  void _showImagePreview(int index, File image) {
    HapticFeedback.lightImpact();

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _ImagePreviewPage(
          image: image,
          index: index,
          totalImages: _attachedImages.length,
          onDelete: () {
            Navigator.pop(context);
            _confirmRemoveImage(index);
          },
        ),
      ),
    );
  }

  /// Confirm before removing image - best practice for destructive actions
  void _confirmRemoveImage(int index) {
    HapticFeedback.lightImpact();

    showCupertinoModalPopup<void>(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Remove Image'),
        message: Text('Remove image ${index + 1} from receipt?'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              HapticFeedback.mediumImpact();

              // Remove the hash and quality score of the image being deleted
              final imageToRemove = _attachedImages[index];
              try {
                final hash = await _computeImageHash(imageToRemove);
                _attachedImageHashes.remove(hash);
                DebugLogService.debug('DailySales', 'Removed hash for deleted image: ${hash.substring(0, 8)}...');
              } catch (e) {
                DebugLogService.warning('DailySales', 'Could not compute hash for removal: $e');
              }

              // Remove quality score for this image
              _imageQualityScores.remove(imageToRemove.path);

              if (mounted) {
                setState(() => _attachedImages.removeAt(index));
                SnackbarHelper.showSuccess(context, 'Image removed');
              }
            },
            child: const Text('Remove'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildAddImageButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isUploadingImages ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: _isUploadingImages ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _isUploadingImages ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compute SHA256 hash of image file content for deduplication
  ///
  /// This ensures we detect duplicate images even if they have different file paths.
  Future<String> _computeImageHash(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  /// Add images with content-based deduplication (SHA256 hash)
  ///
  /// Returns the number of unique images actually added (excluding duplicates).
  Future<int> _addImagesWithDeduplication(List<File> newImages) async {
    int addedCount = 0;

    for (final newImage in newImages) {
      try {
        final hash = await _computeImageHash(newImage);

        if (_attachedImageHashes.contains(hash)) {
          // Duplicate content detected - skip
          DebugLogService.warning(
            'DailySales',
            'Duplicate image detected (same content hash), skipping: ${newImage.path.split('/').last}',
          );
          continue;
        }

        // Unique image - add it
        _attachedImageHashes.add(hash);
        _attachedImages.add(newImage);
        addedCount++;

        // Analyze blur quality in background
        _analyzeImageQuality(newImage);

        DebugLogService.debug(
          'DailySales',
          'Added unique image: ${newImage.path.split('/').last} (hash: ${hash.substring(0, 8)}...)',
        );
      } catch (e) {
        DebugLogService.error('DailySales', 'Failed to hash image: ${newImage.path}', error: e);
        // If hashing fails, add anyway to avoid losing images
        _attachedImages.add(newImage);
        addedCount++;
        // Still analyze quality
        _analyzeImageQuality(newImage);
      }
    }

    return addedCount;
  }

  /// Scan receipts using professional document scanner
  ///
  /// Features:
  /// - CamScanner-style edge detection
  /// - Auto-capture when document stable
  /// - Image enhancement (contrast, sharpen, denoise)
  /// - Direct attachment (no preview step)
  Future<void> _scanReceipts() async {
    // Early exit if widget is disposed
    if (!mounted) return;

    // DEBOUNCE: Prevent double-tap
    if (_isScanningInProgress) {
      DebugLogService.warning('DailySales', 'Scan already in progress - ignoring tap');
      return;
    }

    DebugLogService.info('DailySales', 'Scan Receipts button tapped');

    try {
      setState(() => _isScanningInProgress = true);
      HapticFeedback.mediumImpact();

      DebugLogService.debug('DailySales', 'Calling CamScanner-style professional scanner...');
      // Use CamScanner-style professional scanner for best experience:
      // - Live camera preview with frame guide
      // - Manual corner adjustment for perfect alignment
      // - Perspective correction (straightens tilted documents)
      // - Professional document enhancement
      final shopSelectionProvider = Provider.of<ShopSelectionProvider>(context, listen: false);
      final result = await _documentScanner.scanWithCamScannerStyle(
        context: context,
        shopId: shopSelectionProvider.selectedShopId,
        maxPages: 10,  // Allow up to 10 images
        onProgress: (step) {
          DebugLogService.debug('DailySales', 'Scanner progress: $step');
        },
      );

      // CRITICAL: Check mounted after async operation
      if (!mounted) {
        DebugLogService.warning('DailySales', 'Widget disposed after scan');
        return;
      }

      DebugLogService.info('DailySales', 'Scan result - success: ${result.success}, cancelled: ${result.cancelled}, images: ${result.processedImages.length}, error: ${result.error}');

      if (result.success && result.processedImages.isNotEmpty) {
        // Direct attachment - no preview step
        HapticFeedback.lightImpact();

        DebugLogService.debug('DailySales', 'Processing ${result.processedImages.length} scanned images for deduplication...');

        // Log each image before deduplication
        for (int i = 0; i < result.processedImages.length; i++) {
          final file = result.processedImages[i];
          DebugLogService.debug('DailySales', 'Scanned image ${i + 1}: ${file.path.split('/').last}, exists: ${file.existsSync()}');
        }

        // CONTENT-BASED DEDUPLICATION: Use SHA256 hash to detect duplicate images
        final addedCount = await _addImagesWithDeduplication(result.processedImages);

        // Check mounted after async hash computation
        if (!mounted) return;

        if (addedCount == 0) {
          DebugLogService.warning('DailySales', 'All scanned images were duplicates (content hash match) - skipping');
          SnackbarHelper.showInfo(context, 'Images already attached');
          return;
        }

        setState(() {}); // Trigger rebuild after images added

        DebugLogService.success('DailySales', 'Added $addedCount unique scanned image(s). Total attached: ${_attachedImages.length}');

        // Process OCR to extract items and auto-fill quantities
        await _processOcrFromImages(result.processedImages);
      } else if (result.error != null && !result.cancelled) {
        DebugLogService.error('DailySales', 'Scan error: ${result.error}');
        SnackbarHelper.showError(context, result.error!);
      } else if (result.cancelled) {
        DebugLogService.info('DailySales', 'Scan cancelled by user');
      }
    } catch (e, stackTrace) {
      DebugLogService.error('DailySales', 'Scanner exception', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackbarHelper.showError(context, 'Scanner error: $e');
      }
    } finally {
      // CRITICAL: Always reset debounce flag
      if (mounted) {
        setState(() => _isScanningInProgress = false);
      } else {
        _isScanningInProgress = false;
      }
    }
  }

  /// Process scanned images through OCR and auto-fill quantities
  ///
  /// Flow:
  /// 1. Send images to backend OCR service
  /// 2. Poll for results until processing completes
  /// 3. Match extracted items to products by brand name and size
  /// 4. Auto-fill quantity controllers with matched results
  Future<void> _processOcrFromImages(List<File> images) async {
    if (!mounted || images.isEmpty) return;

    final shopProvider = Provider.of<ShopSelectionProvider>(context, listen: false);
    final shopId = shopProvider.selectedShopId;

    if (shopId == null || shopId.isEmpty) {
      DebugLogService.warning('DailySales', 'No shop selected for OCR processing');
      return;
    }

    try {
      setState(() {
        _isOcrProcessing = true;
        _ocrProgressMessage = 'Processing receipts...';
        _ocrMatchedCount = 0;
      });

      DebugLogService.info('DailySales', 'Starting OCR processing for ${images.length} image(s)');

      // Get DioApiService from Provider
      final apiService = Provider.of<DioApiService>(context, listen: false);
      final ocrService = OCRService(apiService: apiService);

      // Process each image
      List<OCRExtractedItem> allExtractedItems = [];

      for (int i = 0; i < images.length; i++) {
        if (!mounted) return;

        setState(() {
          _ocrProgressMessage = 'Analyzing receipt ${i + 1}/${images.length}...';
        });

        final imagePath = images[i].path;
        DebugLogService.debug('DailySales', 'Processing image ${i + 1}: $imagePath');

        try {
          // Create OCR session
          final sessionResponse = await ocrService.createSession(
            imagePath: imagePath,
            shopId: shopId,
            sessionType: 'daily_sales',
          );

          if (!sessionResponse.success || sessionResponse.data == null) {
            DebugLogService.warning('DailySales', 'Failed to create OCR session for image ${i + 1}: ${sessionResponse.message}');
            continue;
          }

          final sessionId = sessionResponse.data!.id;
          DebugLogService.info('DailySales', 'OCR session created: $sessionId');

          // Poll for results with timeout
          const maxPolls = 30;
          const pollInterval = Duration(seconds: 2);

          for (int poll = 0; poll < maxPolls; poll++) {
            if (!mounted) return;

            await Future.delayed(pollInterval);

            setState(() {
              _ocrProgressMessage = 'Extracting items from receipt ${i + 1}...';
            });

            final statusResponse = await ocrService.getSession(sessionId);

            if (statusResponse.success && statusResponse.data != null) {
              final status = statusResponse.data!.session.status;
              DebugLogService.debug('DailySales', 'OCR session status: $status');

              if (status == 'completed' || status == 'processed') {
                // Extract items from session
                allExtractedItems.addAll(statusResponse.data!.extractedItems);
                DebugLogService.success('DailySales', 'Extracted ${statusResponse.data!.extractedItems.length} items from receipt ${i + 1}');
                break;
              } else if (status == 'failed' || status == 'error') {
                DebugLogService.warning('DailySales', 'OCR processing failed for image ${i + 1}');
                break;
              }
              // Continue polling for 'pending' or 'processing' status
            }
          }
        } catch (e) {
          DebugLogService.error('DailySales', 'Error processing image ${i + 1}', error: e);
        }
      }

      if (!mounted) return;

      if (allExtractedItems.isEmpty) {
        setState(() {
          _isOcrProcessing = false;
          _ocrProgressMessage = '';
        });
        SnackbarHelper.showInfo(context, 'No items extracted from receipts');
        return;
      }

      // Match extracted items to products and auto-fill quantities
      setState(() {
        _ocrProgressMessage = 'Matching items to products...';
      });

      int matchedCount = 0;

      for (final item in allExtractedItems) {
        final matchResult = _matchOcrItemToProduct(item);

        if (matchResult != null) {
          final productId = matchResult['productId'] as String;
          final quantity = matchResult['quantity'] as int;

          // Initialize controller if needed (with progress listener)
          final ctrl = _getOrCreateQtyController(productId);

          // Get existing quantity and add the new quantity
          final existingText = ctrl.text;
          final existingQty = int.tryParse(existingText) ?? 0;
          final newQty = existingQty + quantity;

          ctrl.text = newQty.toString();
          matchedCount++;

          DebugLogService.debug('DailySales', 'Auto-filled: ${item.brandText ?? item.extractedText} -> Product $productId, qty: $newQty');
        }
      }

      setState(() {
        _isOcrProcessing = false;
        _ocrProgressMessage = '';
        _ocrMatchedCount = matchedCount;
      });

      if (matchedCount > 0) {
        HapticFeedback.heavyImpact();
        SnackbarHelper.showSuccess(
          context,
          '$matchedCount item(s) auto-filled from receipts',
        );
      } else {
        SnackbarHelper.showInfo(context, 'No matching products found in receipts');
      }

      DebugLogService.success('DailySales', 'OCR processing complete: $matchedCount/${allExtractedItems.length} items matched');

    } catch (e, stackTrace) {
      DebugLogService.error('DailySales', 'OCR processing failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _isOcrProcessing = false;
          _ocrProgressMessage = '';
        });
        SnackbarHelper.showError(context, 'Failed to process receipts');
      }
    }
  }

  /// Match an OCR extracted item to a product in the cached products list
  /// Returns { productId, quantity } if match found, null otherwise
  Map<String, dynamic>? _matchOcrItemToProduct(OCRExtractedItem item) {
    // If backend already matched a product, use that
    if (item.matchedProductId != null && item.matchedProductId!.isNotEmpty) {
      final quantity = item.parsedQuantity ?? item.closingStock ?? 1;
      return {
        'productId': item.matchedProductId!,
        'quantity': quantity,
      };
    }

    // Manual matching by brand name and size
    final brandText = (item.brandText ?? item.extractedText ?? '').toLowerCase().trim();
    final sizeText = (item.sizeText ?? item.parsedSize ?? '').toLowerCase().trim();

    if (brandText.isEmpty) return null;

    for (final product in _cachedProducts) {
      final productBrand = (product.brand?.name ?? product.name).toLowerCase();
      final productSize = product.size.toLowerCase();

      // Check if brand matches (fuzzy match)
      bool brandMatches = false;
      if (productBrand.contains(brandText) || brandText.contains(productBrand)) {
        brandMatches = true;
      } else {
        // Try word-by-word matching
        final brandWords = brandText.split(RegExp(r'\s+'));
        final productWords = productBrand.split(RegExp(r'\s+'));
        final matchedWords = brandWords.where((w) =>
          productWords.any((pw) => pw.contains(w) || w.contains(pw))
        ).length;
        brandMatches = matchedWords >= (brandWords.length * 0.6); // 60% word match
      }

      if (!brandMatches) continue;

      // Check size match if provided
      if (sizeText.isNotEmpty) {
        // Normalize sizes for comparison
        final normalizedOcrSize = _normalizeSize(sizeText);
        final normalizedProductSize = _normalizeSize(productSize);

        if (normalizedOcrSize != normalizedProductSize) continue;
      }

      // Found a match
      final quantity = item.parsedQuantity ?? item.closingStock ?? 1;
      return {
        'productId': product.id,
        'quantity': quantity,
      };
    }

    return null;
  }

  /// Normalize size strings for comparison
  /// Converts various formats to a standard form: "750ml", "180ml", "q", "h", etc.
  String _normalizeSize(String size) {
    String normalized = size.toLowerCase().trim();

    // Remove common suffixes/prefixes
    normalized = normalized.replaceAll('ml', '');
    normalized = normalized.replaceAll('litre', 'l');
    normalized = normalized.replaceAll('liter', 'l');

    // Map common abbreviations
    final sizeMap = {
      '180': '180',
      '375': '375',
      '750': '750',
      '1000': '1000',
      '1': '1000', // 1L
      'q': 'q',      // Quarter
      'quarter': 'q',
      'qtr': 'q',
      'h': 'h',      // Half
      'half': 'h',
      'f': 'f',      // Full
      'full': 'f',
      'p': 'p',      // Pint
      'pint': 'p',
      'nip': 'nip',
    };

    // Check exact matches first
    if (sizeMap.containsKey(normalized)) {
      return sizeMap[normalized]!;
    }

    // Extract numeric part
    final numMatch = RegExp(r'(\d+)').firstMatch(normalized);
    if (numMatch != null) {
      return numMatch.group(1)!;
    }

    return normalized;
  }

  /// Industrial-grade scanning with live validation
  ///
  /// Features:
  /// - Real-time blur and edge detection
  /// - Live OCR validation (date, shop, sizes)
  /// - Validation checklist during camera preview
  /// - Quality feedback with retry tips
  /// - Adaptive image enhancement (preserves text)
  Future<void> _scanReceiptsWithValidation() async {
    if (!mounted) return;

    // DEBOUNCE: Prevent double-tap
    if (_isScanningInProgress) {
      DebugLogService.warning('DailySales', 'Scan already in progress - ignoring tap');
      return;
    }

    DebugLogService.info('DailySales', 'Industrial-grade scan initiated');

    final shopProvider = Provider.of<ShopSelectionProvider>(context, listen: false);
    final shopName = shopProvider.selectedShopName ?? 'Shop';
    final shopId = shopProvider.selectedShopId;

    try {
      setState(() => _isScanningInProgress = true);
      HapticFeedback.mediumImpact();

      // Open live camera scanner with validation overlay
      final result = await Navigator.push<_ScanResult>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (context) => LiveCameraScannerWidget(
            shopName: shopName,
            shopId: shopId,
            onImageCaptured: (imageFile) async {
              // Assess image quality (content validation done on backend)
              final qualityResult = await _qualityService.assessImage(
                await imageFile.readAsBytes(),
              );

              Navigator.pop(context, _ScanResult(
                imageFile: imageFile,
                quality: qualityResult,
              ));
            },
            onCancel: () => Navigator.pop(context),
          ),
        ),
      );

      if (!mounted) return;

      if (result == null) {
        DebugLogService.info('DailySales', 'Scan cancelled by user');
        return;
      }

      // Check quality and show feedback if poor
      if (!result.quality.isAcceptable) {
        await ScanQualityFeedbackModal.show(
          context: context,
          imageFile: result.imageFile,
          qualityResult: result.quality,
          onRetry: () {
            // Recursive call to retry scanning
            _scanReceiptsWithValidation();
          },
          onUseAnyway: () async {
            // User chose to use anyway - proceed with preprocessing
            await _processAndAddImage(result.imageFile);
            // Process OCR to extract items and auto-fill quantities
            await _processOcrFromImages([result.imageFile]);
          },
          onCancel: () {
            DebugLogService.info('DailySales', 'User cancelled after quality check');
          },
        );
        return;
      }

      // Quality is acceptable - process and add image
      await _processAndAddImage(result.imageFile);

      // Process OCR to extract items and auto-fill quantities
      await _processOcrFromImages([result.imageFile]);

    } catch (e, stackTrace) {
      DebugLogService.error('DailySales', 'Industrial scan error', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackbarHelper.showError(context, 'Scanner error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isScanningInProgress = false);
      } else {
        _isScanningInProgress = false;
      }
    }
  }

  /// Process captured image with adaptive enhancement and add to attachments
  Future<void> _processAndAddImage(File imageFile) async {
    if (!mounted) return;

    try {
      DebugLogService.debug('DailySales', 'Processing image with adaptive enhancement...');

      // Apply document enhancement (uses new adaptive algorithm)
      final enhancedFile = await _imagePreprocessingService.applyDocumentEnhancement(imageFile);
      final fileToAdd = enhancedFile ?? imageFile;

      // Add with deduplication
      final addedCount = await _addImagesWithDeduplication([fileToAdd]);

      if (!mounted) return;

      if (addedCount == 0) {
        DebugLogService.warning('DailySales', 'Image was duplicate - skipping');
        SnackbarHelper.showInfo(context, 'Image already attached');
        return;
      }

      setState(() {}); // Trigger rebuild

      DebugLogService.success('DailySales', 'Added processed image. Total attached: ${_attachedImages.length}');
      SnackbarHelper.showSuccess(context, 'Receipt added');

    } catch (e) {
      DebugLogService.error('DailySales', 'Image processing error: $e');
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to process image');
      }
    }
  }

  /// Import and scan from gallery
  ///
  /// Opens gallery to select images, applies enhancement, attaches directly.
  /// Show bottom sheet with Camera + Gallery options for uploading sales bill
  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD0D5DD), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Upload Sales Bill',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 4),
              Text('${_attachedImages.length} image${_attachedImages.length != 1 ? "s" : ""} attached',
                style: TextStyle(fontSize: 13, color: _attachedImages.isEmpty ? const Color(0xFF999999) : const Color(0xFF2E7D32))),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildPickerOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () { Navigator.pop(ctx); _captureFromCamera(); },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildPickerOption(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      subtitle: 'Multiple',
                      onTap: () { Navigator.pop(ctx); _pickMultipleFromGallery(); },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildPickerOption(
                      icon: Icons.document_scanner_rounded,
                      label: 'Scan',
                      onTap: () { Navigator.pop(ctx); _importAndScan(); },
                    ),
                  ),
                ],
              ),
              // Show attached images preview if any
              if (_attachedImages.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 70,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachedImages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(_attachedImages[i], width: 70, height: 70, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _attachedImages.removeAt(i);
                                // Also remove hash if exists
                                if (i < _attachedImageHashes.length) {
                                  _attachedImageHashes.clear(); // Reset hashes
                                }
                              });
                              Navigator.pop(ctx);
                              _showImagePickerOptions(); // Reopen to refresh
                            },
                            child: Container(
                              width: 20, height: 20,
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white, size: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickerOption({required IconData icon, required String label, String? subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E3EA)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF2962FF), size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            if (subtitle != null)
              Text(subtitle, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF888888))),
          ],
        ),
      ),
    );
  }

  /// Capture single image from camera
  Future<void> _captureFromCamera() async {
    if (_isScanningInProgress) return;
    try {
      setState(() => _isScanningInProgress = true);
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (picked != null && mounted) {
        final addedCount = await _addImagesWithDeduplication([File(picked.path)]);
        if (mounted && addedCount > 0) {
          setState(() {});
          SnackbarHelper.showSuccess(context, 'Image captured');
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Camera error: $e');
    } finally {
      if (mounted) setState(() => _isScanningInProgress = false);
      else _isScanningInProgress = false;
    }
  }

  /// Pick multiple images from gallery
  Future<void> _pickMultipleFromGallery() async {
    if (_isScanningInProgress) return;
    try {
      setState(() => _isScanningInProgress = true);
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(imageQuality: 85);
      if (picked.isNotEmpty && mounted) {
        final files = picked.map((xf) => File(xf.path)).toList();
        final addedCount = await _addImagesWithDeduplication(files);
        if (mounted) {
          setState(() {});
          if (addedCount > 0) {
            SnackbarHelper.showSuccess(context, '$addedCount image${addedCount > 1 ? "s" : ""} added');
          } else {
            SnackbarHelper.showInfo(context, 'Images already attached');
          }
        }
      }
    } catch (e) {
      if (mounted) SnackbarHelper.showError(context, 'Gallery error: $e');
    } finally {
      if (mounted) setState(() => _isScanningInProgress = false);
      else _isScanningInProgress = false;
    }
  }

  Future<void> _importAndScan() async {
    // Early exit if widget is disposed
    if (!mounted) return;

    // DEBOUNCE: Prevent double-tap (uses same flag as scan)
    if (_isScanningInProgress) {
      DebugLogService.warning('DailySales', 'Import already in progress - ignoring tap');
      return;
    }

    DebugLogService.info('DailySales', 'Import & Scan button tapped');

    try {
      setState(() => _isScanningInProgress = true);
      HapticFeedback.lightImpact();

      DebugLogService.debug('DailySales', 'Calling documentScanner.importFromGallery()...');
      final result = await _documentScanner.importFromGallery(
        config: DocumentScannerService.receiptConfig,
        context: context,
      );

      // CRITICAL: Check mounted after async operation
      if (!mounted) {
        DebugLogService.warning('DailySales', 'Widget disposed after import');
        return;
      }

      DebugLogService.info('DailySales', 'Import result - success: ${result.success}, cancelled: ${result.cancelled}, images: ${result.processedImages.length}, error: ${result.error}');

      if (result.success && result.processedImages.isNotEmpty) {
        DebugLogService.debug('DailySales', 'Processing ${result.processedImages.length} imported images for deduplication...');

        // Log each image before deduplication
        for (int i = 0; i < result.processedImages.length; i++) {
          final file = result.processedImages[i];
          DebugLogService.debug('DailySales', 'Imported image ${i + 1}: ${file.path.split('/').last}, exists: ${file.existsSync()}');
        }

        // CONTENT-BASED DEDUPLICATION: Use SHA256 hash to detect duplicate images
        final addedCount = await _addImagesWithDeduplication(result.processedImages);

        // Check mounted after async hash computation
        if (!mounted) return;

        if (addedCount == 0) {
          DebugLogService.warning('DailySales', 'All imported images were duplicates (content hash match) - skipping');
          SnackbarHelper.showInfo(context, 'Images already attached');
          return;
        }

        setState(() {}); // Trigger rebuild after images added

        DebugLogService.success('DailySales', 'Added $addedCount unique imported image(s). Total attached: ${_attachedImages.length}');

        SnackbarHelper.showSuccess(
          context,
          '$addedCount image(s) added',
        );
      } else if (result.error != null && !result.cancelled) {
        DebugLogService.error('DailySales', 'Import error: ${result.error}');
        SnackbarHelper.showError(context, result.error!);
      } else if (result.cancelled) {
        DebugLogService.info('DailySales', 'Import cancelled by user');
      }
    } catch (e, stackTrace) {
      DebugLogService.error('DailySales', 'Import exception', error: e, stackTrace: stackTrace);
      if (mounted) {
        SnackbarHelper.showError(context, 'Import error: $e');
      }
    } finally {
      // CRITICAL: Always reset debounce flag
      if (mounted) {
        setState(() => _isScanningInProgress = false);
      } else {
        _isScanningInProgress = false;
      }
    }
  }

  Widget _buildPaymentBreakdownCard(DailySalesProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 20),

            // ========== PAYMENT 2x2 GRID ==========
            Row(
              children: [
                Expanded(
                  child: _buildCompactPaymentField(
                    controller: _cashController,
                    label: 'Cash',
                    onChanged: (value) {
                      provider.setCashAmount(double.tryParse(value) ?? 0);
                      provider.triggerInstantSave();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactPaymentField(
                    controller: _upiController,
                    label: 'UPI',
                    onChanged: (value) {
                      provider.setUpiAmount(double.tryParse(value) ?? 0);
                      provider.triggerInstantSave();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCompactPaymentField(
                    controller: _cardController,
                    label: 'Card',
                    onChanged: (value) {
                      provider.setCardAmount(double.tryParse(value) ?? 0);
                      provider.triggerInstantSave();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactPaymentField(
                    controller: _creditController,
                    label: 'Credit',
                    onChanged: (value) {
                      provider.setCreditAmount(double.tryParse(value) ?? 0);
                      provider.triggerInstantSave();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Total Payment & Balance - Modern Card Style
            Builder(
              builder: (context) {
                // Determine validation state
                final isBalanced = provider.totalPaymentAmount == provider.totalItemsAmount;
                final needsExpenseNotes = provider.expenseAmount > 0 && provider.notes.trim().isEmpty;

                // Color coding: Green (balanced) → Orange (needs expense notes) → Red (not balanced)
                Color indicatorColor;
                IconData icon;
                String statusText;

                if (isBalanced && !needsExpenseNotes) {
                  indicatorColor = AppColors.success;
                  icon = CupertinoIcons.check_mark_circled_solid;
                  statusText = 'Balanced';
                } else if (needsExpenseNotes) {
                  indicatorColor = AppColors.warning;
                  icon = CupertinoIcons.exclamationmark_triangle_fill;
                  statusText = 'Notes required for expenses';
                } else {
                  indicatorColor = AppColors.error;
                  icon = CupertinoIcons.xmark_circle_fill;
                  statusText = 'Difference: ${Formatters.currency((provider.totalItemsAmount - provider.totalPaymentAmount).abs())}';
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: indicatorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: indicatorColor.withOpacity(0.3), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total Payment Entered',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            Formatters.currency(provider.totalPaymentAmount),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: indicatorColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 16, color: indicatorColor),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: indicatorColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Compact payment field for 2x2 grid layout
  Widget _buildCompactPaymentField({
    required TextEditingController controller,
    required String label,
    required Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              border: InputBorder.none,
              prefixText: '₹ ',
              prefixStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  /// Payment input with text label (legacy - kept for backward compatibility)
  Widget _buildPaymentInputWithLabel({
    required TextEditingController controller,
    required String label,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
          ),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              border: InputBorder.none,
              prefixText: '₹ ',
              prefixStyle: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// LEGACY: Payment input with icon (kept for backward compatibility)
  Widget _buildPaymentInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required Color color,
    required Function(String) onChanged,
  }) {
    return Row(
      children: [
        // Modern Icon Container with Gradient
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        // Modern Glass-style TextField
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
            ),
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                hintText: label,
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                prefixText: '₹ ',
                prefixStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesCard(DailySalesProvider provider) {
    final isRequired = provider.expenseAmount > 0;
    final hasError = isRequired && provider.notes.trim().isEmpty;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasError ? AppColors.warning : Theme.of(context).colorScheme.outlineVariant,
          width: hasError ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isRequired ? 'Notes (Required)' : 'Notes (Optional)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: hasError ? AppColors.warning : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (isRequired)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      '*',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            if (isRequired)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Required when expenses are entered',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.warning,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: isRequired
                    ? 'Explain the expense (required)...'
                    : 'Add any notes about today\'s sales...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.warning : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.warning : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: hasError ? AppColors.warning : Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (value) {
                provider.setNotes(value);
                provider.triggerInstantSave(); // Auto-save after 500ms
              },
            ),
            // ==================== LOCATION CAPTURE (Optional) ====================
            const SizedBox(height: 16),
            _buildLocationCaptureButton(provider),
          ],
        ),
      ),
    );
  }

  /// Build optional location capture button
  Widget _buildLocationCaptureButton(DailySalesProvider provider) {
    final hasLocation = provider.hasLocation;
    final isCapturing = provider.isCapturingLocation;
    final location = provider.location;

    return Container(
      decoration: BoxDecoration(
        color: hasLocation ? AppColors.success.withOpacity(0.08) : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasLocation ? AppColors.success.withOpacity(0.3) : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: hasLocation ? AppColors.success.withOpacity(0.15) : Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: isCapturing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  hasLocation ? Icons.location_on : Icons.location_off_outlined,
                  color: hasLocation ? AppColors.success : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
        ),
        title: Text(
          hasLocation ? 'Location Captured' : 'Add Location (Optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: hasLocation ? AppColors.success : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        subtitle: hasLocation && location != null
            ? Text(
                'Accuracy: ${location.accuracy.toStringAsFixed(0)}m',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
                ),
              )
            : Text(
                'Tap to capture your current location',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: hasLocation
            ? IconButton(
                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () => provider.clearLocation(),
                tooltip: 'Remove location',
              )
            : Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        onTap: isCapturing
            ? null
            : () async {
                await provider.captureLocation();
                if (mounted && provider.hasLocation) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Location captured successfully'),
                        ],
                      ),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              },
      ),
    );
  }

  Widget _buildStep2BottomButtons(DailySalesProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        child: Row(
          children: [
            // Back Button
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _currentStep = 0;
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Theme.of(context).colorScheme.onSurfaceVariant!),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.arrow_left, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Submit Button
            Expanded(
              flex: 2,
              child: ElevatedButton(
                // CRITICAL: Check BOTH provider.isSubmitting AND local _isSubmitInProgress
                // to prevent double-submission during image upload phase
                onPressed: provider.isSubmitting || _isSubmitInProgress || !provider.isValid
                    ? null
                    : () => _submitRecord(provider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  disabledBackgroundColor: Theme.of(context).colorScheme.outlineVariant,
                ),
                // Show spinner + progress during either local submit or provider submit
                child: (provider.isSubmitting || _isSubmitInProgress)
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          if (_uploadProgressMessage.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            Text(
                              _uploadProgressMessage,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(CupertinoIcons.check_mark_circled, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Submit for Approval',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== HELPER METHODS ==========

  /// Validates quantity in real-time against available stock
  /// For APPROVED record edits: adds back original quantity to available stock
  /// (because backend will return original stock before deducting new quantities)
  void _validateQuantity(String productId, String value, int availableStock) {
    setState(() {
      if (value.isEmpty) {
        // Empty is valid (user can clear the field)
        _quantityValidationErrors[productId] = false;
        _validationErrorMessages.remove(productId);
        return;
      }

      final enteredQty = int.tryParse(value);
      if (enteredQty == null || enteredQty < 0) {
        // Invalid number (0 is allowed — means "not sold, accounted for")
        _quantityValidationErrors[productId] = true;
        _validationErrorMessages[productId] = 'Invalid qty';
        return;
      }

      // ========== APPROVED RECORD EDIT ADJUSTMENT ==========
      // For approved records, the stock was already deducted. The backend will:
      // 1. Return the original quantity to stock
      // 2. Then deduct the new quantity
      // So effective available = current stock + original quantity from record
      int effectiveAvailableStock = availableStock;

      if (widget.editRecord != null &&
          widget.editRecord!.status.toLowerCase() == 'approved') {
        // Find original quantity for this product in the edit record
        final originalItem = widget.editRecord!.items.firstWhere(
          (item) => item.productId == productId,
          orElse: () => DailySalesItem(
            productId: productId,
            productName: '',
            quantity: 0,
            unitPrice: 0,
            totalAmount: 0,
            cashAmount: 0,
            cardAmount: 0,
            upiAmount: 0,
            creditAmount: 0,
          ),
        );
        effectiveAvailableStock = availableStock + originalItem.quantity;
      }

      if (enteredQty > effectiveAvailableStock) {
        // Exceeds stock
        _quantityValidationErrors[productId] = true;
        _validationErrorMessages[productId] = 'Max: $effectiveAvailableStock';
      } else {
        // Valid quantity
        _quantityValidationErrors[productId] = false;
        _validationErrorMessages.remove(productId);
      }
    });
  }

  /// Checks if any quantity validation errors exist
  bool _hasValidationErrors() {
    return _quantityValidationErrors.values.any((hasError) => hasError == true);
  }

  /// Counts how many products have validation errors
  int _getValidationErrorCount() {
    return _quantityValidationErrors.values.where((hasError) => hasError == true).length;
  }

  /// Show sort options in a bottom sheet
  void _showSortOptions() async {
    await HapticFeedbackUtil.lightImpact();

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.sort_down, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Sort By',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Sort Options
              _buildSortOption('name', 'Name (A-Z)', CupertinoIcons.textformat),
              _buildSortOption('brand', 'Brand', CupertinoIcons.building_2_fill),
              _buildSortOption('price', 'Price', CupertinoIcons.money_dollar),
              _buildSortOption('stock', 'Stock Level', CupertinoIcons.cube_box),
            ],
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        if (_sortBy == result) {
          _sortAscending = !_sortAscending;
        } else {
          _sortBy = result;
          _sortAscending = true;
        }
      });
    }
  }

  Widget _buildSortOption(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      trailing: isSelected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _sortAscending
                      ? CupertinoIcons.arrow_up
                      : CupertinoIcons.arrow_down,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.check_mark_circled_solid,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ],
            )
          : null,
      onTap: () => Navigator.pop(context, value),
    );
  }

  bool _hasActiveFilters() {
    return _searchQuery.isNotEmpty ||
           _selectedCategoryId != null ||
           _selectedSize != null;
  }

  void _clearAllFilters() {
    HapticFeedbackUtil.lightImpact();
    setState(() {
      _searchQuery = '';
      _sortBy = 'name';
      _sortAscending = true;
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _selectedSize = null;
      _hasSetDefaultCategory = false;
      _hasSetDefaultSize = false;
    });
  }

  List<models.Product> _getFilteredAndSortedProducts(List<models.Product> products) {
    var filtered = products.where((product) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesSearch = product.name.toLowerCase().contains(_searchQuery) ||
            (product.brand?.name.toLowerCase().contains(_searchQuery) ?? false) ||
            product.sku.toLowerCase().contains(_searchQuery) ||
            (product.category?.name.toLowerCase().contains(_searchQuery) ?? false);
        if (!matchesSearch) return false;
      }

      // Category filter - support combined "English" filter (Whisky + Rum + Vodka)
      if (_isEnglishFilterSelected) {
        // Must be in one of English categories (Whisky, Rum, or Vodka)
        if (product.category == null) return false;
        final categoryName = product.category!.name.toLowerCase();
        if (!_englishCategories.any((e) => categoryName.contains(e))) {
          return false;
        }
      } else if (_selectedCategoryName != null && product.category?.name != _selectedCategoryName) {
        // Single category selection
        return false;
      }

      // Size filter — supports range labels and exact sizes
      if (_selectedSize != null) {
        final isRange = _selectedSize!.contains('(') || _selectedSize!.contains('Below') || _selectedSize!.contains('Bulk');
        if (isRange) {
          final category = _selectedCategoryName ?? '';
          if (!SizeRangeConstants.sizeMatchesRange(product.size, _selectedSize!, category)) {
            return false;
          }
        } else {
          final productSize = ProductConstants.normalizeSize(product.size);
          final filterSize = ProductConstants.normalizeSize(_selectedSize!);
          if (productSize != filterSize) return false;
        }
      }

      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'size':
          // Sort by size (ML) - extract numeric value
          final sizeA = _extractSizeValue(a);
          final sizeB = _extractSizeValue(b);
          comparison = sizeA.compareTo(sizeB);
          // If same size, sort by brand name
          if (comparison == 0) {
            comparison = (a.brand?.name ?? '').compareTo(b.brand?.name ?? '');
          }
          break;
        case 'brand':
          comparison = (a.brand?.name ?? '').compareTo(b.brand?.name ?? '');
          break;
        case 'price':
          comparison = a.sellingPrice.compareTo(b.sellingPrice);
          // If same price, sort by brand name for consistency
          if (comparison == 0) {
            comparison = (a.brand?.name ?? '').compareTo(b.brand?.name ?? '');
          }
          // If same brand, sort by size (larger first)
          if (comparison == 0) {
            final sizeA = _extractSizeValue(a);
            final sizeB = _extractSizeValue(b);
            comparison = sizeB.compareTo(sizeA); // Larger size first
          }
          break;
        case 'stock':
          final stockA = context.read<ProductProvider>().stockByProductId[a.id]?.quantity ?? 0;
          final stockB = context.read<ProductProvider>().stockByProductId[b.id]?.quantity ?? 0;
          comparison = stockA.compareTo(stockB);
          break;
        case 'name':
        default:
          comparison = a.name.compareTo(b.name);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return filtered;
  }

  Future<void> _selectDate(DailySalesProvider provider) async {
    // IMPORTANT: Users cannot select today's date - only past dates
    // This prevents confusion with current day's ongoing sales
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final initialDate = provider.recordDate.isAfter(yesterday)
        ? yesterday
        : provider.recordDate;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: yesterday, // Block today's date
    );
    if (date != null) {
      provider.setRecordDate(date);
    }
  }

  Future<void> _submitRecord(DailySalesProvider provider) async {
    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL FIX: Prevent double-submit race condition
    // This guard MUST be at the very beginning to prevent:
    // 1. Multiple concurrent image uploads (causes RangeError)
    // 2. Double form submission (creates duplicate records)
    // 3. List modification during iteration (crashes app)
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isSubmitInProgress) {
      Logger.warning('[DailySalesEntry] BLOCKED: Submit already in progress - preventing double submission');
      return;
    }

    // Set the lock IMMEDIATELY before any async operation
    setState(() => _isSubmitInProgress = true);

    Logger.info('[DailySalesEntry] ========== SUBMIT RECORD ==========');
    Logger.debug('[DailySalesEntry] Edit mode: ${widget.isEditMode}');
    Logger.debug('[DailySalesEntry] Provider hashCode: ${provider.hashCode}');
    Logger.debug('[DailySalesEntry] Provider imageUrls: ${provider.imageUrls}');
    Logger.debug('[DailySalesEntry] Provider imageUrls.length: ${provider.imageUrls.length}');
    Logger.debug('[DailySalesEntry] Local _attachedImages.length: ${_attachedImages.length}');

    // ========== IMAGE HANDLING ==========
    // In edit mode, we may already have image URLs from the existing record
    // Only require new images if no existing URLs are present
    final hasExistingImages = provider.imageUrls.isNotEmpty;
    final hasNewImages = _attachedImages.isNotEmpty;

    Logger.debug('[DailySalesEntry] hasExistingImages: $hasExistingImages');
    Logger.debug('[DailySalesEntry] hasNewImages: $hasNewImages');

    if (!hasExistingImages && !hasNewImages) {
      Logger.error('[DailySalesEntry] No images attached - submission blocked');
      SnackbarHelper.showError(context, 'Please attach at least one image before submitting');
      // CRITICAL: Release the lock on early return
      if (mounted) setState(() => _isSubmitInProgress = false);
      return;
    }

    // If we have new images to upload, upload them
    if (hasNewImages) {
      // ═══════════════════════════════════════════════════════════════════════
      // CRITICAL FIX: Copy images to local list BEFORE starting async upload
      // This prevents RangeError if _attachedImages is modified during upload
      // ═══════════════════════════════════════════════════════════════════════
      final imagesToUpload = List<File>.from(_attachedImages);
      Logger.info('[DailySalesEntry] Uploading ${imagesToUpload.length} new image(s) to backend...');
      setState(() {
        _isUploadingImages = true;
        _compressionTotal = imagesToUpload.length;
        _uploadTotal = imagesToUpload.length;
        _compressionCurrent = 0;
        _uploadCurrent = 0;
        _uploadProgressMessage = 'Compressing images...';
      });

      try {
        final authService = context.read<AuthService>();
        final dailySalesService = DailySalesService(authService);

        // Use the COPIED list, not _attachedImages
        // Now with progress callbacks for compression and upload phases
        final uploadResult = await dailySalesService.uploadSalesImages(
          imagesToUpload,
          onCompressionProgress: (current, total, fileName) {
            if (mounted) {
              setState(() {
                _compressionCurrent = current;
                _compressionTotal = total;
                _uploadProgressMessage = 'Compressing $current/$total...';
              });
            }
          },
          onUploadProgress: (current, total, fileName) {
            if (mounted) {
              setState(() {
                _uploadCurrent = current;
                _uploadTotal = total;
                _uploadProgressMessage = 'Uploading $current/$total...';
              });
            }
          },
        );

        if (uploadResult.success && uploadResult.data != null && uploadResult.data!.isNotEmpty) {
          final newImageUrls = uploadResult.data!;
          Logger.info('[DailySalesEntry] Images uploaded successfully: ${newImageUrls.length} URLs');

          // ═══════════════════════════════════════════════════════════════════════
          // PARTIAL UPLOAD WARNING: Inform user if some images failed but continue
          // ═══════════════════════════════════════════════════════════════════════
          if (newImageUrls.length < imagesToUpload.length) {
            final failedCount = imagesToUpload.length - newImageUrls.length;
            Logger.warning('[DailySalesEntry] PARTIAL UPLOAD: ${newImageUrls.length}/${imagesToUpload.length} succeeded ($failedCount failed)');
            if (mounted) {
              SnackbarHelper.showWarning(context, '$failedCount/${imagesToUpload.length} images failed to upload. Proceeding with ${newImageUrls.length} uploaded images.');
            }
          }

          // Combine existing URLs with new ones (if in edit mode with new attachments)
          if (hasExistingImages) {
            // CRITICAL: Deduplicate combined URLs to prevent duplicates
            final combinedUrls = {...provider.imageUrls, ...newImageUrls}.toList();
            provider.setImageUrls(combinedUrls);
            Logger.info('[DailySalesEntry] Combined with existing: ${combinedUrls.length} total URLs (deduplicated)');
          } else {
            // Already deduplicated from service, but ensure uniqueness
            final uniqueUrls = newImageUrls.toSet().toList();
            provider.setImageUrls(uniqueUrls);
          }

          // ✅ CRITICAL FIX: Clear attached images after successful upload
          // This prevents re-uploading the same images if validation fails later
          // and the user retries submit
          Logger.info('[DailySalesEntry] Clearing _attachedImages after successful upload to prevent re-upload on retry');
          _attachedImages.clear();
          _attachedImageHashes.clear();
        } else {
          Logger.error('[DailySalesEntry] Image upload failed: ${uploadResult.error}');
          if (mounted) {
            SnackbarHelper.showError(context, uploadResult.error ?? 'Failed to upload images');
            // CRITICAL: Release both locks on error
            setState(() {
              _isUploadingImages = false;
              _isSubmitInProgress = false;
            });
          }
          return;
        }
      } catch (e) {
        Logger.error('[DailySalesEntry] Image upload exception: $e');
        if (mounted) {
          SnackbarHelper.showError(context, 'Error uploading images: $e');
          // CRITICAL: Release both locks on exception
          setState(() {
            _isUploadingImages = false;
            _isSubmitInProgress = false;
          });
        }
        return;
      } finally {
        if (mounted) {
          setState(() {
            _isUploadingImages = false;
            _uploadProgressMessage = '';
            _compressionCurrent = 0;
            _uploadCurrent = 0;
          });
        }
      }
    } else {
      Logger.info('[DailySalesEntry] Using ${provider.imageUrls.length} existing image(s) from record');
    }

    // ✅ Log payment state (no auto-adjustment - user's values are respected)
    final cartTotal = provider.totalItemsAmount;
    final currentPayment = provider.cashAmount + provider.cardAmount + provider.upiAmount + provider.creditAmount;

    Logger.debug('[DailySalesEntry] Current payment state:');
    Logger.debug('   - Cart total: ₹$cartTotal');
    Logger.debug('   - Cash: ₹${provider.cashAmount}');
    Logger.debug('   - Card: ₹${provider.cardAmount}');
    Logger.debug('   - UPI: ₹${provider.upiAmount}');
    Logger.debug('   - Credit: ₹${provider.creditAmount}');
    Logger.debug('   - Payment sum: ₹$currentPayment');

    // Log difference but DO NOT auto-adjust - user knows what they entered
    // Credit sales (payment < cart) and overpayments are valid scenarios
    final paymentDiff = currentPayment - cartTotal;
    if (paymentDiff.abs() > 0.01) {
      if (paymentDiff < 0) {
        Logger.info('[DailySalesEntry] Payment is less than cart total by ₹${paymentDiff.abs().toStringAsFixed(0)} (possible credit sale)');
      } else {
        Logger.info('[DailySalesEntry] Payment exceeds cart total by ₹${paymentDiff.toStringAsFixed(0)}');
      }
    } else {
      Logger.info('[DailySalesEntry] Payment matches cart total');
    }

    Logger.debug('[DailySalesEntry] Auto-distributing payment breakdown across items...');

    // Distribute overall payment breakdown across items proportionally
    provider.autoDistributePayment();
    Logger.info('[DailySalesEntry] Payment distributed across ${provider.items.length} items');

    Logger.debug('[DailySalesEntry] Validating form data...');

    final validationError = provider.validate();
    if (validationError != null) {
      Logger.error('[DailySalesEntry] Validation failed: $validationError');
      SnackbarHelper.showError(context, validationError);
      // CRITICAL: Release the lock on validation failure
      if (mounted) setState(() => _isSubmitInProgress = false);
      return;
    }
    Logger.info('[DailySalesEntry] Validation passed');

    // ========== BATCH VALIDATION WITH BACKEND ==========
    // SKIP validation for APPROVED record edits - backend handles stock adjustment
    // (returns original stock before deducting new quantities)
    final isApprovedRecordEdit = widget.editRecord != null &&
        widget.editRecord!.status.toLowerCase() == 'approved';

    if (isApprovedRecordEdit) {
      Logger.info('[DailySalesEntry] SKIPPING batch validation for approved record edit');
      Logger.debug('   Backend will handle stock adjustment (return original → deduct new)');
    } else if (provider.selectedShopId != null && provider.items.isNotEmpty) {
      Logger.debug('[DailySalesEntry] Running backend batch validation...');
      try {
        final authService = context.read<AuthService>();
        final dailySalesService = DailySalesService(authService);

        // Build validation items from provider items
        final validationItems = provider.items.map((item) => BatchValidationItem(
          productId: item.productId,
          quantity: item.quantity,
        )).toList();

        final validationResult = await dailySalesService.validateProductsBatch(
          shopId: provider.selectedShopId!,
          items: validationItems,
        );

        if (validationResult.success && validationResult.data != null) {
          final result = validationResult.data!;

          if (!result.isValid && result.invalidCount > 0) {
            Logger.warning('[DailySalesEntry] Backend validation found ${result.invalidCount} issues');

            // Show validation issues dialog
            final proceed = await _showValidationIssuesDialog(result);
            if (proceed != true) {
              Logger.info('[DailySalesEntry] User cancelled due to validation issues');
              // CRITICAL: Release the lock when user cancels
              if (mounted) setState(() => _isSubmitInProgress = false);
              return;
            }
            Logger.info('[DailySalesEntry] User chose to proceed despite issues');
          } else {
            Logger.info('[DailySalesEntry] Backend validation passed - all items valid');
          }
        } else if (validationResult.error != null) {
          Logger.warning('[DailySalesEntry] Backend validation failed: ${validationResult.error}');
          // Continue anyway - backend validation is optional
        }
      } catch (e) {
        Logger.error('[DailySalesEntry] Backend validation error: $e');
        // Continue anyway - don't block submission if backend validation fails
      }
    }

    Logger.debug('[DailySalesEntry] Showing confirmation dialog...');

    // Get shop name from ShopSelectionProvider
    final shopProvider = context.read<ShopSelectionProvider>();
    final selectedShop = shopProvider.shops.firstWhere(
      (shop) => shop.id == provider.selectedShopId,
      orElse: () => shopProvider.shops.first,
    );

    // Determine dialog title and message based on mode
    final isEditMode = widget.editRecord != null;
    final isRejectedRecord = widget.editRecord?.status.toLowerCase() == 'rejected';
    final dialogTitle = isEditMode
        ? (isRejectedRecord ? 'Create New Record?' : 'Update Daily Sales?')
        : 'Submit Daily Sales?';
    final dialogMessage = isEditMode
        ? (isRejectedRecord
            ? 'This will create a new record from the rejected entry.'
            : 'This will update the existing record.')
        : 'This will be sent to manager for approval.';
    final buttonText = isEditMode
        ? (isRejectedRecord ? 'Create' : 'Update')
        : 'Submit';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please review before submitting:'),
              const SizedBox(height: 12),
              Text('Date: ${Formatters.date(provider.recordDate)}'),
              Text('Shop: ${selectedShop.name}'),
              Text('Products: ${provider.totalItemsCount}'),
              Text('Total Amount: ${Formatters.currency(provider.totalItemsAmount)}'),
              const SizedBox(height: 12),
              Text(
                dialogMessage,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
              child: Text(buttonText),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      Logger.info('[DailySalesEntry] User confirmed submission');

      // ═══════════════════════════════════════════════════════════════════════════
      // CRITICAL: Lock draft operations BEFORE submission starts
      // This prevents the race condition where:
      // 1. Auto-save timer fires during submission
      // 2. POST request is sent to create draft
      // 3. DELETE request (from clearDraft) completes
      // 4. POST completes AFTER DELETE → draft is re-created!
      //
      // With this lock, all draft saves are blocked once submission starts
      // ═══════════════════════════════════════════════════════════════════════════
      provider.lockForSubmission();
      Logger.info('[DailySalesEntry] Draft operations LOCKED for submission');

      bool success;
      String successMessage;

      // ========== EDIT MODE HANDLING ==========
      // If editing a non-rejected record, update it
      // If editing a rejected record or creating new, create a new record
      final isEditMode = widget.editRecord != null;
      final isRejectedRecord = widget.editRecord?.status.toLowerCase() == 'rejected';

      if (isEditMode && !isRejectedRecord) {
        // Update existing record (pending/approved status)
        // Backend handles:
        //   - Stock adjustment (returns original stock → deducts new quantities)
        //   - Date update (record_date is now included in update)
        //   - Cash holdings adjustment
        final recordId = widget.editRecord!.id ?? '';
        if (recordId.isEmpty) {
          provider.setError('Cannot update: Record ID is missing');
          success = false;
          successMessage = '';
        } else {
          Logger.info('[DailySalesEntry] EDIT MODE: Updating record ID: $recordId');
          Logger.debug('   Status: ${widget.editRecord!.status}');
          final authService = context.read<AuthService>();
          final dailySalesService = DailySalesService(authService);

          // Check if date was changed (for logging purposes)
          final dateWasChanged = _originalRecordDate != null &&
              !_isSameDay(_originalRecordDate!, provider.recordDate);
          if (dateWasChanged) {
            Logger.info('[DailySalesEntry] Date changed: $_originalRecordDate → ${provider.recordDate}');
          }

          // Build the update request from provider data (includes record_date)
          final request = provider.buildRequest();
          Logger.debug('[DailySalesEntry] Sending update request with ${request.items.length} items');

          final result = await dailySalesService.updateDailySalesRecord(recordId, request);

          success = result.success;
          if (!success) {
            provider.setError(result.error ?? 'Failed to update record');
            Logger.error('[DailySalesEntry] Update failed: ${result.error}');
          } else {
            Logger.info('[DailySalesEntry] Update successful');
          }
          successMessage = dateWasChanged
              ? 'Record date and details updated successfully!'
              : 'Daily sales record updated successfully!';
        }
      } else {
        // Create new record (new entry or copy from rejected)
        if (isRejectedRecord) {
          Logger.info('[DailySalesEntry] REJECTED RECORD: Creating new copy (original ID: ${widget.editRecord!.id})');
        } else {
          Logger.info('[DailySalesEntry] NEW RECORD: Calling provider.createRecord()...');
        }
        // ═══════════════════════════════════════════════════════════════════════
        // CRITICAL: Save shop+date BEFORE createRecord() because createRecord()
        // internally calls clearForm() which resets _recordDate to DateTime.now()
        // We need the original date for markAsJustSubmitted() later
        // ═══════════════════════════════════════════════════════════════════════
        final savedShopId = provider.selectedShopId;
        final savedRecordDate = provider.recordDate;

        success = await provider.createRecord();
        successMessage = isRejectedRecord
            ? 'New record created from rejected entry!'
            : 'Daily sales record submitted successfully!';
        Logger.debug('[DailySalesEntry] createRecord returned: $success');

        // Restore saved values for later use (markAsJustSubmitted uses these)
        // NOTE: createRecord() already handles clearDraft() internally with correct date
        if (success && savedShopId != null) {
          provider.markAsJustSubmitted(savedShopId, savedRecordDate);
          Logger.info('[DailySalesEntry] Marked shop+date as just submitted: $savedShopId / $savedRecordDate');
        }
      }

      if (mounted) {
        if (success) {
          Logger.info('[DailySalesEntry] Record ${isEditMode && !isRejectedRecord ? "updated" : "created"} successfully!');
          SnackbarHelper.showSuccess(context, successMessage);

          // ✅ REFRESH STOCK - Reload products to show updated quantities
          // FIXED: Use kDailySalesProductLimit (500) instead of default (30) to load all products
          Logger.debug('[DailySalesEntry] Refreshing product provider to show updated stock...');
          final productProvider = context.read<ProductProvider>();
          if (provider.selectedShopId != null) {
            await productProvider.loadProducts(
              shopId: provider.selectedShopId,
              limit: kDailySalesProductLimit,  // Use 500, not default 30
            );
            Logger.info('[DailySalesEntry] Stock refreshed - updated quantities now visible');
          }

          // ========== EDIT MODE: Navigate back after successful update ==========
          if (isEditMode) {
            Logger.info('[DailySalesEntry] Edit mode: Navigating back after successful ${isRejectedRecord ? "create" : "update"}');
            // CRITICAL: Set success flag to prevent draft re-save on dispose
            _wasSubmittedSuccessfully = true;

            // CRITICAL: Mark this shop+date as "just submitted"
            // For edit mode, we need to save the date BEFORE any potential reset
            // But since updateRecord doesn't call clearForm, we can use current values
            // However, for rejected records (which call createRecord), the date is already saved above
            if (!isRejectedRecord) {
              final shopId = provider.selectedShopId;
              final recordDate = provider.recordDate;
              if (shopId != null) {
                provider.markAsJustSubmitted(shopId, recordDate);
                Logger.info('[DailySalesEntry] Edit mode: Marked shop+date as just submitted (60s block)');
              }
            }
            // For rejected records, markAsJustSubmitted was already called in the create block above

            // CRITICAL: Release the lock before navigating back
            if (mounted) {
              setState(() => _isSubmitInProgress = false);
              Navigator.pop(context);
            }
            return;
          }

          // ═══════════════════════════════════════════════════════════════════════
          // CRITICAL: Set success flag to prevent dispose() from re-saving draft
          // NOTE: createRecord() already handles clearDraft() internally with correct date
          // NOTE: markAsJustSubmitted() already called above with saved date
          // ═══════════════════════════════════════════════════════════════════════
          _wasSubmittedSuccessfully = true;
          Logger.info('[DailySalesEntry] Success flag set - dispose() will skip draft re-save');

          // ═══════════════════════════════════════════════════════════════════════
          // BEST PRACTICE UX: Navigate back after successful submission
          // Modern apps (Swiggy/Zomato) navigate back to list after submission
          // so user can see their submitted record in the list.
          // This also prevents stale state issues on the entry screen.
          // ═══════════════════════════════════════════════════════════════════════
          Logger.info('[DailySalesEntry] Navigating back after successful submission...');
          // CRITICAL: Release the lock before navigating back
          if (mounted) {
            setState(() => _isSubmitInProgress = false);
            await AIFeedbackBottomSheet.show(
              context,
              flowType: AIFlowType.dailySales,
              successMessage: successMessage,
            );
            if (!mounted) return;
            Navigator.pop(context, 'submitted'); // Signal success to setup screen
          }
          return;
        } else {
          Logger.error('[DailySalesEntry] Record creation failed: ${provider.errorMessage}');
          // Show detailed error dialog
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error_outline, color: AppColors.error, size: 28),
                  SizedBox(width: 12),
                  Text('Submission Failed'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Unable to submit daily sales record:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            provider.errorMessage ?? 'Unknown error occurred',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.error,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Please check the error message above and try again.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } else {
      Logger.info('[DailySalesEntry] User cancelled submission');
      // CRITICAL: Release the lock when user cancels confirmation dialog
      if (mounted) setState(() => _isSubmitInProgress = false);
    }

    // CRITICAL: Always release the lock at the end of successful flow
    // This is a safety net in case any path forgot to release
    if (mounted && _isSubmitInProgress) {
      setState(() => _isSubmitInProgress = false);
    }
    Logger.info('[DailySalesEntry] ========== SUBMIT COMPLETE ==========');
  }

  /// Shows validation issues dialog with iOS-style design
  /// Returns true if user wants to proceed, false otherwise
  Future<bool?> _showValidationIssuesDialog(BatchValidationResult result) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: AppColors.warning,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Stock Validation Issues',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.info_circle_fill, color: AppColors.warning, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${result.invalidCount} of ${result.validCount + result.invalidCount} products have issues',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Issues list (scrollable, max 4 items visible)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: result.results.where((r) => !r.isValid).length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final invalidItems = result.results.where((r) => !r.isValid).toList();
                      final item = invalidItems[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              item.isStockIssue
                                  ? CupertinoIcons.cube_box
                                  : CupertinoIcons.xmark_circle_fill,
                              color: AppColors.error,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    item.isStockIssue
                                        ? 'Requested: ${item.requestedQuantity}, Available: ${item.availableStock}'
                                        : item.errorMessage ?? 'Validation error',
                                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Warning text
                Text(
                  'Proceeding may result in stock issues. Do you want to continue?',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Proceed Anyway'),
            ),
          ],
        );
      },
    );
  }


  // Helper methods to get unique categories, subcategories, and sizes (matching brand catalog)
  List<String> _getUniqueCategories(List<models.Product> products) {
    final categories = <String>{};
    for (var product in products) {
      if (product.category != null && product.category!.name.isNotEmpty) {
        categories.add(product.category!.name);
      }
    }
    return categories.toList()..sort();
  }

  List<String> _getUniqueSubcategories(
    List<models.Product> products,
    String categoryName,
  ) {
    final subcategories = <String>{};
    for (var product in products) {
      if (product.category?.name == categoryName) {
        if (product.subcategory != null && product.subcategory!.name.isNotEmpty) {
          subcategories.add(product.subcategory!.name);
        }
      }
    }
    return subcategories.toList()..sort();
  }

  /// Get unique sizes from products, normalized to uppercase ML format
  /// BEST PRACTICE: Deduplicates "180ML" and "180ml" to single "180ML" entry
  List<String> _getAvailableSizes(List<models.Product> products) {
    // Group individual sizes into ranges
    final category = _selectedCategoryName ?? '';
    final ranges = SizeRangeConstants.rangesFor(category);
    final rangesWithProducts = <String>{};
    for (var product in products) {
      if (product.size.isEmpty) continue;
      final rangeLabel = SizeRangeConstants.getRangeLabel(product.size, category);
      if (rangeLabel != null) rangesWithProducts.add(rangeLabel);
    }
    // Return ranges in sort order, only those with products
    return ranges
        .where((r) => rangesWithProducts.contains(r.label))
        .map((r) => r.label)
        .toList();
  }

  // ========== EXPENSE TABLE METHODS (NEW - Expense Table Feature) ==========

  /// Check if current user is Salesman or Executive (limited expense view)
  bool _isLimitedExpenseRole(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final role = authProvider.currentUser?.role.toLowerCase() ?? '';
    return role == 'salesman' || role == 'executive';
  }

  /// Get expense headers filtered by user role
  /// - Admin/Manager/Assistant Manager: License Fee, Staff Salary, Shop Rent, Godam Charges
  /// - Salesman/Executive: Transport, Utilities, Breakage
  List<ExpenseHeader> _getExpenseHeadersForRole(BuildContext context) {
    final isLimited = _isLimitedExpenseRole(context);

    if (isLimited) {
      // Salesman/Executive - limited options
      return [
        ExpenseHeader(id: 'transport', name: 'Transport', isDefault: true, isActive: true),
        ExpenseHeader(id: 'utilities', name: 'Utilities', isDefault: true, isActive: true),
        ExpenseHeader(id: 'breakage', name: 'Breakage', isDefault: true, isActive: true),
      ];
    } else {
      // Admin/Manager/Assistant Manager - full options
      return [
        ExpenseHeader(id: 'license_fee', name: 'License Fee', isDefault: true, isActive: true),
        ExpenseHeader(id: 'staff_salary', name: 'Staff Salary', isDefault: true, isActive: true),
        ExpenseHeader(id: 'shop_rent', name: 'Shop Rent', isDefault: true, isActive: true),
        ExpenseHeader(id: 'godam_charges', name: 'Godam Charges', isDefault: true, isActive: true),
      ];
    }
  }

  /// Get or create expense controller for a header
  TextEditingController _getExpenseController(String headerId, DailySalesProvider provider) {
    if (!_expenseControllers.containsKey(headerId)) {
      final controller = TextEditingController();
      // Initialize with saved value if exists
      final savedAmount = provider.getExpenseForHeader(headerId);
      if (savedAmount > 0) {
        controller.text = savedAmount.toStringAsFixed(0);
      }
      _expenseControllers[headerId] = controller;
    }
    return _expenseControllers[headerId]!;
  }

  /// Build the expense table card with role-based 2x2 grid
  Widget _buildExpenseTableCard(DailySalesProvider salesProvider) {
    final isLimitedRole = _isLimitedExpenseRole(context);
    final expenseHeaders = _getExpenseHeadersForRole(context);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with total
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'EXPENSES',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Total: ${Formatters.currency(salesProvider.totalExpenseFromHeaders)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Expense 2x2 Grid (role-based options) using Rows for better sizing
            if (expenseHeaders.length >= 2) ...[
              Row(
                children: [
                  Expanded(child: _buildCompactExpenseField(expenseHeaders[0], salesProvider)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildCompactExpenseField(expenseHeaders[1], salesProvider)),
                ],
              ),
            ],
            if (expenseHeaders.length >= 3) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildCompactExpenseField(expenseHeaders[2], salesProvider)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: expenseHeaders.length >= 4
                        ? _buildCompactExpenseField(expenseHeaders[3], salesProvider)
                        : const SizedBox(), // Empty space if only 3 items
                  ),
                ],
              ),
            ],

            // Add custom expense button - ONLY for Admin/Manager/Assistant Manager
            if (!isLimitedRole) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () => _showAddCustomExpenseDialog(salesProvider),
                  icon: const Icon(CupertinoIcons.add_circled, size: 18),
                  label: const Text('Add Custom Expense'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact expense field for 2x2 grid layout
  Widget _buildCompactExpenseField(ExpenseHeader header, DailySalesProvider provider) {
    final controller = _getExpenseController(header.id, provider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            header.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              border: InputBorder.none,
              prefixText: '₹ ',
              prefixStyle: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              contentPadding: EdgeInsets.zero,
              isDense: true,
            ),
            onChanged: (value) {
              provider.setExpenseForHeader(header.id, double.tryParse(value) ?? 0);
              provider.triggerInstantSave();
            },
          ),
        ],
      ),
    );
  }

  /// Build a single expense row
  Widget _buildExpenseRow(ExpenseHeader header, DailySalesProvider provider) {
    final controller = _getExpenseController(header.id, provider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              header.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1),
              ),
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onChanged: (value) {
                  provider.setExpenseForHeader(header.id, double.tryParse(value) ?? 0);
                  provider.triggerInstantSave();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show dialog to add a custom expense on-the-fly
  void _showAddCustomExpenseDialog(DailySalesProvider salesProvider) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Custom Expense',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Expense name',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  hintText: 'Amount',
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter amount';
                  }
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final headerProvider = context.read<ExpenseHeaderProvider>();
                final name = nameController.text.trim();
                final amount = double.parse(amountController.text);

                // Add to provider
                final success = await headerProvider.addCustomHeader(name);
                if (success) {
                  // Get the new header and set its amount
                  final newHeader = headerProvider.customHeaders.lastOrNull;
                  if (newHeader != null) {
                    salesProvider.setExpenseForHeader(newHeader.id, amount);
                    // Create controller for the new header
                    _expenseControllers[newHeader.id] = TextEditingController(
                      text: amount.toStringAsFixed(0),
                    );
                    salesProvider.triggerInstantSave();
                  }
                }

                if (mounted) {
                  Navigator.pop(context);
                  if (success) {
                    SnackbarHelper.showSuccess(context, 'Custom expense added');
                  } else {
                    SnackbarHelper.showError(context, 'Expense with this name already exists');
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ========== SLIVER DELEGATES ==========

/// Filter Header Delegate (Category/size filters - single-select, always visible)
class _FilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final String? selectedCategoryName;
  final String? selectedSize;
  final List<String> categories;
  final List<String> sizes;
  final Function(String) onCategoryChanged;
  final Function(String) onSizeChanged;
  final int productsCount;

  _FilterHeaderDelegate({
    required this.height,
    required this.selectedCategoryName,
    required this.selectedSize,
    required this.categories,
    required this.sizes,
    required this.onCategoryChanged,
    required this.onSizeChanged,
    required this.productsCount,
  });

  @override
  double get minExtent => height; // Always show full height

  @override
  double get maxExtent => height; // Always show full height

  @override
  bool shouldRebuild(covariant _FilterHeaderDelegate oldDelegate) {
    // CRITICAL FIX: Compare sizes/categories by content, not just length
    // Prevents stale filter chip rendering when content changes but count stays same
    final sizesChanged = oldDelegate.sizes.length != sizes.length ||
        !_listEquals(oldDelegate.sizes, sizes);
    final categoriesChanged = oldDelegate.categories.length != categories.length ||
        !_listEquals(oldDelegate.categories, categories);

    return oldDelegate.selectedCategoryName != selectedCategoryName ||
        oldDelegate.selectedSize != selectedSize ||
        categoriesChanged ||
        sizesChanged ||
        oldDelegate.productsCount != productsCount;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final elevation = overlapsContent ? 2.0 : 0.0;

    return Material(
      elevation: elevation,
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: height,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            children: [
              // Category Filter (single-select)
              if (categories.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: FilterChipRow(
                    title: '', // Hidden title for compact mobile view
                    chips: categories.map((cat) => FilterChipData(
                      id: cat,
                      label: cat,
                    )).toList(),
                    selectedChipId: selectedCategoryName,
                    onChipSelected: onCategoryChanged,
                    showCounts: false,
                  ),
                ),

              // Size Filter (single-select)
              if (sizes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: FilterChipRow(
                    title: '', // Hidden title for compact mobile view
                    chips: sizes.map((size) => FilterChipData(
                      id: size,
                      label: size,
                    )).toList(),
                    selectedChipId: selectedSize,
                    onChipSelected: onSizeChanged,
                    showCounts: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen image preview page with zoom capability
/// Consistent with camera preview UX - best practice implementation
class _ImagePreviewPage extends StatelessWidget {
  final File image;
  final int index;
  final int totalImages;
  final VoidCallback onDelete;

  const _ImagePreviewPage({
    required this.image,
    required this.index,
    required this.totalImages,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Receipt ${index + 1} of $totalImages',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          // Delete button in app bar
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: onDelete,
            tooltip: 'Remove image',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Zoomable image
            Expanded(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.file(
                    image,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            // Bottom action bar
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black,
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Pinch to zoom hint
                    Row(
                      children: [
                        Icon(
                          Icons.pinch_outlined,
                          color: Colors.white.withOpacity(0.6),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Pinch to zoom',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    // Delete button
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                      label: Text(
                        'Remove',
                        style: TextStyle(color: AppColors.error, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper class to hold scan result with quality info
class _ScanResult {
  final File imageFile;
  final ScanQualityResult quality;

  _ScanResult({
    required this.imageFile,
    required this.quality,
  });
}

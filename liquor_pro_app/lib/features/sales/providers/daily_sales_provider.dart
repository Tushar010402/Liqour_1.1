import 'package:flutter/foundation.dart';
import '../../inventory/models/product.dart';
import '../models/daily_sales_models.dart';
import '../models/daily_sales_draft.dart';
import '../models/expense_header.dart';
import '../services/daily_sales_service.dart';
import '../services/daily_sales_draft_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/utils/logger.dart';

/// Daily Sales Provider - Manages daily sales entry form state
/// OPTIMIZED: Added kDebugMode guards and reduced logging verbosity
/// ENHANCED: Industrial-grade auto-save with draft persistence
class DailySalesProvider with ChangeNotifier {
  final DailySalesService _dailySalesService;
  final DailySalesDraftService _draftService;

  DailySalesProvider(this._dailySalesService, this._draftService);

  // Form state
  DateTime _recordDate = DateTime.now().subtract(const Duration(days: 1)); // Default to yesterday (best practice for daily sales entry)
  String? _selectedShopId;
  String? _selectedSalesmanId;
  String _notes = '';

  // Payment amounts
  double _cashAmount = 0.0;
  double _cardAmount = 0.0;
  double _upiAmount = 0.0;
  double _creditAmount = 0.0;
  double _expenseAmount = 0.0; // Legacy - sum of all expenses

  // Expense breakdown by header (NEW - Expense Table Feature)
  Map<String, double> _expenses = {};

  // Items
  final List<DailySalesItem> _items = [];

  // Loading states
  bool _isLoading = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Records list
  List<DailySalesRecord> _records = [];
  DailySalesRecord? _currentRecord;

  // Pagination state (Instagram-style infinite scroll)
  int _currentPage = 1;
  bool _hasMoreRecords = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 20;

  // Draft state (for auto-save)
  DateTime? _lastSavedAt;
  bool _isDraftRestored = false;

  // CRITICAL: Track shops where draft was explicitly cleared by user
  // This prevents sync from restoring backend data after explicit clear
  final Set<String> _draftClearedForShops = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // EDIT MODE FLAG: When true, draft saving is disabled to prevent pollution
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;
  void setEditMode(bool value) {
    _isEditMode = value;
    if (kDebugMode) {
      Logger.info('[Provider] Edit mode set to: $value (draft saving ${value ? "DISABLED" : "enabled"})');
    }
  }

  // CRITICAL: Stored callbacks for forceSaveDraft and saveDraft
  // These are set when enableAutoSaveWithProductItems is called
  // This ensures dispose() saves ALL data from UI controllers, not just provider's _items
  Map<String, int> Function()? _getProductQuantitiesCallback;
  List<DraftProductItem> Function()? _getProductItemsCallback;

  // Location state (optional - for monitoring/analytics)
  LocationData? _location;
  bool _isCapturingLocation = false;

  // Getters
  DateTime get recordDate => _recordDate;
  String? get selectedShopId => _selectedShopId;
  String? get selectedSalesmanId => _selectedSalesmanId;
  String get notes => _notes;
  double get cashAmount => _cashAmount;
  double get cardAmount => _cardAmount;
  double get upiAmount => _upiAmount;
  double get creditAmount => _creditAmount;
  double get expenseAmount => _expenseAmount;
  Map<String, double> get expenses => _expenses;
  List<DailySalesItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  List<DailySalesRecord> get records => _records;
  DailySalesRecord? get currentRecord => _currentRecord;

  // Pagination getters
  bool get hasMoreRecords => _hasMoreRecords;
  bool get isLoadingMore => _isLoadingMore;
  int get currentPage => _currentPage;

  // Draft getters
  DateTime? get lastSavedAt => _lastSavedAt;
  bool get isDraftRestored => _isDraftRestored;
  bool get hasDraftData => _items.isNotEmpty || _cashAmount > 0 || _cardAmount > 0 || _upiAmount > 0 || _creditAmount > 0 || _expenseAmount > 0 || _notes.isNotEmpty;

  // Location getters
  LocationData? get location => _location;
  bool get isCapturingLocation => _isCapturingLocation;
  bool get hasLocation => _location != null;

  // Image URLs state (uploaded to backend)
  List<String> _imageUrls = [];
  List<String> get imageUrls => _imageUrls;

  // Calculated totals
  double get totalPaymentAmount => _cashAmount + _cardAmount + _upiAmount + _creditAmount + _expenseAmount;
  double get totalItemsAmount => _items.fold(0.0, (sum, item) => sum + item.totalAmount);
  int get totalItemsCount => _items.length;
  bool get isValid => _items.isNotEmpty && _selectedShopId != null;

  /// Set record date
  /// IMPORTANT: Today's date is NOT allowed - only past dates
  /// This prevents users from entering sales for a day that is still ongoing
  void setRecordDate(DateTime date) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    // Block today's date - users can only enter past dates
    if (dateOnly.isAtSameMomentAs(todayOnly) || dateOnly.isAfter(todayOnly)) {
      // Set to yesterday instead
      _recordDate = todayOnly.subtract(const Duration(days: 1));
      if (kDebugMode) {
        Logger.warning('[Provider] Blocked today/future date selection, using yesterday');
      }
    } else {
      _recordDate = date;
    }
    notifyListeners();
  }

  /// Set selected shop
  /// CRITICAL FIX: When switching shops, save draft for old shop and clear items
  /// This prevents data from different shops from mixing together
  Future<void> setShop(String shopId) async {
    // If same shop, no action needed
    if (_selectedShopId == shopId) {
      return;
    }

    final oldShopId = _selectedShopId;

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 1: Save draft for OLD shop (if there are items to save)
    // CRITICAL: Don't save if draft was explicitly cleared for this shop
    // ═══════════════════════════════════════════════════════════════════════
    if (oldShopId != null && _items.isNotEmpty) {
      final oldClearKey = '${oldShopId}_${_formatDate(_recordDate)}';
      final wasCleared = _draftClearedForShops.contains(oldClearKey);

      if (wasCleared) {
        if (kDebugMode) {
          Logger.info('[Provider] Shop switch: NOT saving - draft was explicitly cleared for $oldClearKey');
        }
      } else {
        if (kDebugMode) {
          Logger.info('[Provider] Shop switch: Saving ${_items.length} items for old shop $oldShopId');
        }
        try {
          final draft = DailySalesDraft(
            shopId: oldShopId,
            recordDate: _recordDate,
            productItems: _items.map((item) => DraftProductItem(
              productId: item.productId,
              productName: item.productName ?? '',
              brandName: item.brandName ?? '',
              categoryName: item.categoryName ?? '',
              size: item.size ?? '',
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              mrp: item.unitPrice,
              totalAmount: item.totalAmount,
            )).toList(),
            productQuantities: Map.fromEntries(_items.map((item) => MapEntry(item.productId, item.quantity))),
            cashAmount: _cashAmount,
            cardAmount: _cardAmount,
            upiAmount: _upiAmount,
            creditAmount: _creditAmount,
            expenseAmount: _expenseAmount,
            expenses: Map<String, double>.from(_expenses),
            notes: _notes,
            currentStep: 0,
            savedAt: DateTime.now(),
          );
          await _draftService.saveDraft(oldShopId, _recordDate, draft);
        } catch (e) {
          if (kDebugMode) {
            Logger.error('[Provider] Failed to save draft for old shop: $e');
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 2: Clear all sale-related data for fresh start
    // ═══════════════════════════════════════════════════════════════════════
    if (kDebugMode) {
      Logger.info('[Provider] Shop switch: Clearing items for new shop $shopId');
    }
    _items.clear();
    _cashAmount = 0.0;
    _cardAmount = 0.0;
    _upiAmount = 0.0;
    _creditAmount = 0.0;
    _expenseAmount = 0.0;
    _expenses.clear();
    _notes = '';
    _isDraftRestored = false;

    // ═══════════════════════════════════════════════════════════════════════
    // STEP 3: Set the new shop ID
    // ═══════════════════════════════════════════════════════════════════════
    _selectedShopId = shopId;

    if (kDebugMode) {
      Logger.info('[Provider] Shop switched from $oldShopId to $shopId (items cleared)');
    }

    notifyListeners();
  }

  /// Set selected shop (synchronous version for initial load - no draft save needed)
  void setShopSync(String shopId) {
    if (_selectedShopId == shopId) return;
    _selectedShopId = shopId;
    notifyListeners();
  }

  /// Set selected salesman
  void setSalesman(String? salesmanId) {
    _selectedSalesmanId = salesmanId;
    notifyListeners();
  }

  /// Set notes
  void setNotes(String notes) {
    _notes = notes;
    notifyListeners();
  }

  /// Set payment amounts (auto-distributes to items)
  void setCashAmount(double amount) {
    _cashAmount = amount;
    _autoDistributePaymentInternal();
    notifyListeners();
  }

  void setCardAmount(double amount) {
    _cardAmount = amount;
    _autoDistributePaymentInternal();
    notifyListeners();
  }

  void setUpiAmount(double amount) {
    _upiAmount = amount;
    _autoDistributePaymentInternal();
    notifyListeners();
  }

  void setCreditAmount(double amount) {
    _creditAmount = amount;
    _autoDistributePaymentInternal();
    notifyListeners();
  }

  void setExpenseAmount(double amount) {
    _expenseAmount = amount;
    // Note: Expenses are NOT auto-distributed to items
    notifyListeners();
  }

  /// Set expense for a specific header (Expense Table Feature)
  void setExpenseForHeader(String headerId, double amount) {
    if (amount > 0) {
      _expenses[headerId] = amount;
    } else {
      _expenses.remove(headerId);
    }
    // Update legacy _expenseAmount for backward compatibility
    _expenseAmount = totalExpenseFromHeaders;
    notifyListeners();
  }

  /// Get expense for a specific header
  double getExpenseForHeader(String headerId) {
    return _expenses[headerId] ?? 0.0;
  }

  /// Total expense from all headers
  double get totalExpenseFromHeaders =>
      _expenses.values.fold(0.0, (sum, amount) => sum + amount);

  /// Clear all expenses
  void clearExpenses() {
    _expenses.clear();
    _expenseAmount = 0.0;
    notifyListeners();
  }

  /// Get expense breakdown as formatted text (for notes / backend compatibility)
  String get expenseBreakdownText {
    if (_expenses.isEmpty) return '';
    final lines = _expenses.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}: ₹${e.value.toStringAsFixed(2)}')
        .join(', ');
    return lines.isNotEmpty ? 'Expenses: $lines' : '';
  }

  /// Get expense entries list (for backend submission)
  List<ExpenseEntry> get expenseEntries {
    return _expenses.entries
        .where((e) => e.value > 0)
        .map((e) => ExpenseEntry(
              headerId: e.key,
              headerName: e.key.replaceAll('_', ' ').split(' ').map((w) =>
                  w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w).join(' '),
              amount: e.value,
            ))
        .toList();
  }

  // ==================== LOCATION METHODS ====================

  /// Capture current location (optional - never blocks workflow)
  Future<void> captureLocation() async {
    _isCapturingLocation = true;
    notifyListeners();

    try {
      final locationService = LocationService();
      final locationData = await locationService.getCurrentLocation();
      _location = locationData;

      if (kDebugMode) {
        if (_location != null) {
          Logger.info('DailySalesProvider: Location captured - $_location');
        } else {
          Logger.info('DailySalesProvider: Location not available (permission denied or disabled)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('DailySalesProvider: Location capture error - $e');
      }
      _location = null;
    } finally {
      _isCapturingLocation = false;
      notifyListeners();
    }
  }

  /// Clear captured location
  void clearLocation() {
    _location = null;
    notifyListeners();
  }

  /// Set location directly (from external source)
  void setLocation(LocationData? location) {
    _location = location;
    notifyListeners();
  }

  /// Set image URLs (uploaded to backend before submission)
  ///
  /// Automatically deduplicates URLs to prevent duplicate images in storage.
  void setImageUrls(List<String> urls) {
    // DEDUPLICATION: Remove any duplicate URLs returned from backend
    final uniqueUrls = urls.toSet().toList();
    final duplicatesRemoved = urls.length - uniqueUrls.length;

    _imageUrls = uniqueUrls;

    if (kDebugMode) {
      Logger.debug('DailySalesProvider: Set ${uniqueUrls.length} unique image URLs (removed $duplicatesRemoved duplicates)');
      for (int i = 0; i < uniqueUrls.length; i++) {
        Logger.debug('   Image ${i + 1}: ${uniqueUrls[i]}');
      }
    }
    notifyListeners();
  }

  /// Clear image URLs
  void clearImageUrls() {
    if (kDebugMode) {
      Logger.debug('[DailySalesProvider] clearImageUrls() called');
      Logger.debug('   Stack trace:');
      Logger.debug(StackTrace.current.toString().split('\n').take(10).join('\n'));
    }
    _imageUrls = [];
    notifyListeners();
  }

  /// Internal auto-distribute (doesn't notify)
  void _autoDistributePaymentInternal() {
    if (_items.isEmpty) return;

    final totalAmount = totalItemsAmount;
    if (totalAmount == 0) return;

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final ratio = item.totalAmount / totalAmount;

      _items[i] = item.copyWith(
        cashAmount: _cashAmount * ratio,
        cardAmount: _cardAmount * ratio,
        upiAmount: _upiAmount * ratio,
        creditAmount: _creditAmount * ratio,
      );
    }
  }

  /// Add item from product
  void addItem(Product product, {int quantity = 1}) {
    // CRITICAL: Reset "cleared" flag when user adds items
    // This allows auto-save to work properly after user starts fresh entry
    _resetClearedFlagForCurrentShop();

    final item = DailySalesItem(
      productId: product.id,
      productName: product.name,
      brandName: product.brand?.name,
      categoryName: product.category?.name,
      size: product.size,
      quantity: quantity,
      unitPrice: product.sellingPrice,
      totalAmount: product.sellingPrice * quantity,
    );
    _items.add(item);
    notifyListeners();
  }

  /// Internal helper to reset cleared flag for current shop+date
  void _resetClearedFlagForCurrentShop() {
    if (_selectedShopId == null) return;
    final clearKey = '${_selectedShopId}_${_formatDate(_recordDate)}';
    if (_draftClearedForShops.contains(clearKey)) {
      _draftClearedForShops.remove(clearKey);
      if (kDebugMode) {
        Logger.info('[Provider] Draft cleared flag auto-reset for: $clearKey (user adding items)');
      }
    }
  }

  /// Update item quantity
  void updateItemQuantity(int index, int quantity) {
    if (index >= 0 && index < _items.length) {
      final item = _items[index];
      final newTotalAmount = item.unitPrice * quantity;
      _items[index] = item.copyWith(
        quantity: quantity,
        totalAmount: newTotalAmount,
      );
      notifyListeners();
    }
  }

  /// Update item payment breakdown
  void updateItemPayment(
    int index, {
    double? cashAmount,
    double? cardAmount,
    double? upiAmount,
    double? creditAmount,
  }) {
    if (index >= 0 && index < _items.length) {
      _items[index] = _items[index].copyWith(
        cashAmount: cashAmount ?? _items[index].cashAmount,
        cardAmount: cardAmount ?? _items[index].cardAmount,
        upiAmount: upiAmount ?? _items[index].upiAmount,
        creditAmount: creditAmount ?? _items[index].creditAmount,
      );
      notifyListeners();
    }
  }

  /// Remove item
  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  /// Clear all items
  void clearItems() {
    _items.clear();
    notifyListeners();
  }

  /// Auto-distribute payment across items (simple equal distribution)
  void autoDistributePayment() {
    if (_items.isEmpty) return;

    final totalAmount = totalItemsAmount;
    if (totalAmount == 0) return;

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      final ratio = item.totalAmount / totalAmount;

      _items[i] = item.copyWith(
        cashAmount: _cashAmount * ratio,
        cardAmount: _cardAmount * ratio,
        upiAmount: _upiAmount * ratio,
        creditAmount: _creditAmount * ratio,
      );
    }

    notifyListeners();
  }

  /// Validate form
  /// FIXED: Allow partial payments, removed per-item validation (mathematically incompatible)
  String? validate() {
    if (_selectedShopId == null) {
      return 'Please select a shop';
    }

    if (_items.isEmpty) {
      return 'Please add at least one product';
    }

    // Validate expense notes requirement
    if (_expenseAmount > 0 && _notes.trim().isEmpty) {
      return 'Notes are required when expense amount is entered';
    }

    // Payment for products = cash + card + upi + credit (NOT expenses)
    // Expenses are operational costs, not product payments
    final productPayment = _cashAmount + _cardAmount + _upiAmount + _creditAmount;

    // Allow partial payments - any shortfall is implicitly credit/receivable
    // Only reject if no payment at all
    if (productPayment <= 0 && totalItemsAmount > 0) {
      return 'Please enter payment amount';
    }

    // Note: Per-item payment validation removed because:
    // 1. It's mathematically incompatible with partial payments
    // 2. autoDistributePayment() already handles proportional distribution
    // 3. The backend doesn't require exact per-item matching

    return null;
  }

  /// Build request object from current state
  /// Used by both createRecord and updateRecord operations
  DailySalesRecordRequest buildRequest() {
    return DailySalesRecordRequest(
      recordDate: _recordDate,
      shopId: _selectedShopId!,
      salesmanId: _selectedSalesmanId,
      totalSalesAmount: totalItemsAmount,
      totalCashAmount: _cashAmount,
      totalCardAmount: _cardAmount,
      totalUpiAmount: _upiAmount,
      totalCreditAmount: _creditAmount,
      totalExpenseAmount: totalExpenseFromHeaders,
      expenses: expenseEntries,
      notes: _notes,
      items: _items.map((item) {
        return DailySalesItemRequest(
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          totalAmount: item.totalAmount,
          cashAmount: item.cashAmount,
          cardAmount: item.cardAmount,
          upiAmount: item.upiAmount,
          creditAmount: item.creditAmount,
        );
      }).toList(),
      latitude: _location?.latitude,
      longitude: _location?.longitude,
      locationAccuracy: _location?.accuracy.toStringAsFixed(1),
      imageUrls: _imageUrls,
    );
  }

  /// Set error message (used by external update calls)
  void setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// Create daily sales record
  /// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
  Future<bool> createRecord() async {
    final validationError = validate();
    if (validationError != null) {
      if (kDebugMode) Logger.error('DailySalesProvider: Validation failed - $validationError');
      _errorMessage = validationError;
      notifyListeners();
      return false;
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        Logger.info('DailySalesProvider: Creating record - Shop: $_selectedShopId, Items: ${_items.length}, Total: $totalItemsAmount');
        Logger.debug('DailySalesProvider: Payment breakdown:');
        Logger.debug('   - Cash: $_cashAmount');
        Logger.debug('   - Card: $_cardAmount');
        Logger.debug('   - UPI: $_upiAmount');
        Logger.debug('   - Credit: $_creditAmount');
        Logger.debug('   - Sum: ${_cashAmount + _cardAmount + _upiAmount + _creditAmount}');
        Logger.debug('   - Expected: $totalItemsAmount');
      }

      if (kDebugMode) {
        Logger.debug('DailySalesProvider: Expense breakdown:');
        Logger.debug('   - Total Expense: $totalExpenseFromHeaders');
        Logger.debug('   - Expense Entries: ${expenseEntries.length}');
        for (var entry in expenseEntries) {
          Logger.debug('   - ${entry.headerName}: ${entry.amount}');
        }
      }

      // Build request using the shared helper method
      final request = buildRequest();

      final response = await _dailySalesService.createDailySalesRecord(request);

      if (response.success && response.data != null) {
        if (kDebugMode) Logger.info('DailySalesProvider: Record created - ID: ${response.data!.id}');
        _currentRecord = response.data;

        // ═══════════════════════════════════════════════════════════════
        // INDUSTRIAL-GRADE: Verify record exists on backend before clearing draft
        // This prevents data loss if backend submission silently failed
        // ═══════════════════════════════════════════════════════════════
        final recordId = response.data!.id;

        if (recordId != null && recordId.isNotEmpty) {
          final verified = await _dailySalesService.verifyRecordExistsWithRetry(
            recordId,
            maxRetries: 3,
            initialDelayMs: 500,
          );

          if (verified) {
            // ═══════════════════════════════════════════════════════════════
            // CRITICAL FIX: clearDraft() MUST be called BEFORE clearForm()
            // clearForm() resets _recordDate to DateTime.now(), which would
            // cause clearDraft() to delete the wrong date's draft!
            // ═══════════════════════════════════════════════════════════════
            await clearDraft();  // Uses correct _recordDate
            clearForm();         // Now safe to reset _recordDate
            if (kDebugMode) {
              Logger.info('DailySalesProvider: Record VERIFIED on backend - draft cleared safely');
            }
          } else {
            // Record not verified - DON'T clear draft (data safety)
            if (kDebugMode) {
              Logger.warning('DailySalesProvider: Record NOT verified on backend - keeping draft for safety');
            }
            // Still clear form but keep draft in case user needs to retry
            clearForm();
          }
        } else {
          // No ID returned - something went wrong, keep draft for safety
          if (kDebugMode) {
            Logger.warning('DailySalesProvider: No record ID returned - keeping draft for safety');
          }
          clearForm();
        }

        return true;
      } else {
        if (kDebugMode) Logger.error('DailySalesProvider: Failed - ${response.error}');
        _errorMessage = response.error ?? 'Failed to create daily sales record';
        return false;
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesProvider: Exception - $e');
      _errorMessage = 'Error creating daily sales record: $e';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Fetch daily sales records (first page - resets pagination)
  /// OPTIMIZED: Reduced logging verbosity with kDebugMode guards
  Future<void> fetchRecords({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    // Reset pagination state
    _currentPage = 1;
    _hasMoreRecords = true;
    notifyListeners();

    try {
      final response = await _dailySalesService.getDailySalesRecords(
        shopId: shopId,
        startDate: startDate,
        endDate: endDate,
        status: status,
        page: 1,
        pageSize: _pageSize,
      );

      if (response.success && response.data != null) {
        _records = response.data!;
        // Check if we got less than pageSize - means no more data
        _hasMoreRecords = response.data!.length >= _pageSize;
        if (kDebugMode) {
          Logger.debug('DailySalesProvider: Loaded ${_records.length} records (page 1, hasMore: $_hasMoreRecords)');
          // Debug: Check which records have location data
          final recordsWithLocation = _records.where((r) => r.hasLocation).toList();
          Logger.debug('DailySalesProvider: ${recordsWithLocation.length} records have location data');
        }
      } else {
        if (kDebugMode) Logger.error('DailySalesProvider: Fetch failed - ${response.error}');
        _errorMessage = response.error ?? 'Failed to fetch daily sales records';
        _records = [];
        _hasMoreRecords = false;
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesProvider: Exception - $e');
      _errorMessage = 'Error fetching daily sales records: $e';
      _records = [];
      _hasMoreRecords = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load more records (next page) - Instagram-style infinite scroll
  Future<void> loadMoreRecords({
    String? shopId,
    DateTime? startDate,
    DateTime? endDate,
    String? status,
  }) async {
    // Don't load more if already loading or no more data
    if (_isLoadingMore || !_hasMoreRecords) {
      if (kDebugMode) {
        Logger.debug('DailySalesProvider: Skip loadMore - isLoadingMore: $_isLoadingMore, hasMore: $_hasMoreRecords');
      }
      return;
    }

    _isLoadingMore = true;
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      if (kDebugMode) {
        Logger.debug('DailySalesProvider: Loading page $nextPage...');
      }

      final response = await _dailySalesService.getDailySalesRecords(
        shopId: shopId,
        startDate: startDate,
        endDate: endDate,
        status: status,
        page: nextPage,
        pageSize: _pageSize,
      );

      if (response.success && response.data != null) {
        final newRecords = response.data!;

        // Append new records (avoid duplicates by checking IDs)
        final existingIds = _records.map((r) => r.id).toSet();
        final uniqueNewRecords = newRecords.where((r) => !existingIds.contains(r.id)).toList();

        _records.addAll(uniqueNewRecords);
        _currentPage = nextPage;
        _hasMoreRecords = newRecords.length >= _pageSize;

        if (kDebugMode) {
          Logger.debug('DailySalesProvider: Loaded ${uniqueNewRecords.length} new records (page $nextPage, total: ${_records.length}, hasMore: $_hasMoreRecords)');
        }
      } else {
        if (kDebugMode) Logger.error('DailySalesProvider: Load more failed - ${response.error}');
        _hasMoreRecords = false;
      }
    } catch (e) {
      if (kDebugMode) Logger.error('DailySalesProvider: Load more exception - $e');
      _hasMoreRecords = false;
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Fetch record by ID
  Future<void> fetchRecordById(String id) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dailySalesService.getDailySalesRecordById(id);

      if (response.success && response.data != null) {
        _currentRecord = response.data;
      } else {
        _errorMessage = response.error ?? 'Failed to fetch daily sales record';
        _currentRecord = null;
      }
    } catch (e) {
      _errorMessage = 'Error fetching daily sales record: $e';
      _currentRecord = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Approve record (Manager only)
  Future<bool> approveRecord(String id) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dailySalesService.approveDailySalesRecord(id);

      if (response.success && response.data != null) {
        _currentRecord = response.data;
        // Update in list if exists
        final index = _records.indexWhere((r) => r.id == id);
        if (index != -1) {
          _records[index] = response.data!;
        }
        return true;
      } else {
        _errorMessage = response.error ?? 'Failed to approve daily sales record';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error approving daily sales record: $e';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Reject record (Manager only)
  Future<bool> rejectRecord(String id, String reason) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _dailySalesService.rejectDailySalesRecord(id, reason);

      if (response.success) {
        // Refresh record
        await fetchRecordById(id);
        return true;
      } else {
        _errorMessage = response.error ?? 'Failed to reject daily sales record';
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error rejecting daily sales record: $e';
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Clear form - resets ALL form state including images
  /// Also resets edit mode flag to ensure fresh state for next entry
  void clearForm() {
    // IMPORTANT: Default to yesterday, NOT today
    // Users should not enter today's sales as the day is still ongoing
    _recordDate = DateTime.now().subtract(const Duration(days: 1));
    _notes = '';
    _cashAmount = 0.0;
    _cardAmount = 0.0;
    _upiAmount = 0.0;
    _creditAmount = 0.0;
    _expenseAmount = 0.0;
    _expenses.clear();
    _items.clear();
    _imageUrls = []; // CRITICAL: Clear attached images from previous sessions
    _errorMessage = null;

    // ═══════════════════════════════════════════════════════════════════════════
    // CRITICAL: Reset edit mode flag on clearForm
    // This is a safety net to ensure edit mode doesn't persist between sessions
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      _isEditMode = false;
      if (kDebugMode) {
        Logger.info('[Provider] Edit mode reset in clearForm()');
      }
    }

    notifyListeners();
  }

  /// Clear form silently - resets ALL form state WITHOUT notifying listeners
  /// CRITICAL: Use this in dispose() to avoid "setState() called when widget tree was locked" error
  /// This is safe because the widget is being disposed anyway, so no UI update is needed
  void clearFormSilent() {
    // IMPORTANT: Default to yesterday, NOT today
    _recordDate = DateTime.now().subtract(const Duration(days: 1));
    _notes = '';
    _cashAmount = 0.0;
    _cardAmount = 0.0;
    _upiAmount = 0.0;
    _creditAmount = 0.0;
    _expenseAmount = 0.0;
    _expenses.clear();
    _items.clear();
    _imageUrls = [];
    _errorMessage = null;
    _isEditMode = false;

    if (kDebugMode) {
      Logger.info('[Provider] Form cleared silently (no notifyListeners - for dispose)');
    }
    // NOTE: No notifyListeners() - this is intentional for dispose() usage
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════
  // DRAFT AUTO-SAVE METHODS (Industrial-Grade Persistence)
  // ═══════════════════════════════════════════════════════════════

  /// Build current draft from provider state
  /// Used by auto-save timer to capture form state
  ///
  /// CRITICAL FIX: Now stores complete product items, not just quantities
  /// This enables full UI restoration when user returns to the screen
  DailySalesDraft _buildCurrentDraft({
    Map<String, int>? productQuantities,
    List<DraftProductItem>? productItems,
  }) {
    // Build complete product items from provider's _items list
    final completeProductItems = productItems ?? _items.map((item) => DraftProductItem(
      productId: item.productId,
      productName: item.productName ?? '',
      brandName: item.brandName ?? '',
      categoryName: item.categoryName ?? '',
      subcategoryName: '', // Not tracked in DailySalesItem
      size: item.size ?? '',
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      mrp: item.unitPrice, // Use unitPrice as MRP if not available
      totalAmount: item.totalAmount,
    )).toList();

    // Build legacy quantities map for backward compatibility
    final quantities = productQuantities ?? {
      for (var item in _items) item.productId: item.quantity
    };

    return DailySalesDraft(
      productQuantities: quantities,
      productItems: completeProductItems, // NEW: Complete product data
      cashAmount: _cashAmount,
      cardAmount: _cardAmount,
      upiAmount: _upiAmount,
      creditAmount: _creditAmount,
      expenseAmount: _expenseAmount,
      expenses: Map<String, double>.from(_expenses),
      notes: _notes,
      recordDate: _recordDate,
      shopId: _selectedShopId ?? '',
      currentStep: 0, // Will be updated from screen
      savedAt: DateTime.now(),
    );
  }

  /// Enable auto-save for current shop + date
  /// Call this when entering the form screen
  ///
  /// CRITICAL FIX: Now auto-saves complete product items from _items list
  /// No need to pass callback - uses provider's internal state directly
  ///
  /// CRITICAL: Skips enabling in edit mode to prevent draft pollution
  void enableAutoSave([Map<String, int> Function()? getProductQuantities]) {
    // ═══════════════════════════════════════════════════════════════════════════
    // EDIT MODE GUARD: Don't enable auto-save when editing existing records
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      if (kDebugMode) {
        Logger.info('[Provider] enableAutoSave SKIPPED - edit mode active');
      }
      return;
    }

    if (_selectedShopId == null) {
      Logger.warning('[Provider] Cannot enable auto-save: shop not selected');
      return;
    }

    _draftService.enableAutoSave(
      shopId: _selectedShopId!,
      recordDate: _recordDate,
      getCurrentDraft: () {
        // If callback provided, use it for quantities (backward compat)
        // Otherwise, build complete draft from _items
        if (getProductQuantities != null) {
          return _buildCurrentDraft(productQuantities: getProductQuantities());
        } else {
          return _buildCurrentDraft();
        }
      },
      interval: const Duration(seconds: 5), // Auto-save every 5 seconds
    );

    Logger.info('[Provider] Auto-save enabled for shop: $_selectedShopId, date: $_recordDate');
  }

  /// Enable auto-save with COMPLETE product items
  /// CRITICAL: This version saves full product details (name, brand, category, size, price)
  /// ensuring drafts can be restored without needing to match product IDs to cached products
  ///
  /// This is the RECOMMENDED method for Daily Sales Entry screen
  ///
  /// CRITICAL: Skips enabling in edit mode to prevent draft pollution
  void enableAutoSaveWithProductItems({
    required Map<String, int> Function() getProductQuantities,
    required List<DraftProductItem> Function() getProductItems,
  }) {
    // ═══════════════════════════════════════════════════════════════════════════
    // EDIT MODE GUARD: Don't enable auto-save when editing existing records
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      if (kDebugMode) {
        Logger.info('[Provider] enableAutoSaveWithProductItems SKIPPED - edit mode active');
      }
      return;
    }

    if (_selectedShopId == null) {
      Logger.warning('[Provider] Cannot enable auto-save: shop not selected');
      return;
    }

    // CRITICAL FIX: Store callbacks so forceSaveDraft and saveDraft can use them
    // This ensures dispose() saves ALL data from UI controllers, not just provider's _items
    _getProductQuantitiesCallback = getProductQuantities;
    _getProductItemsCallback = getProductItems;

    _draftService.enableAutoSave(
      shopId: _selectedShopId!,
      recordDate: _recordDate,
      getCurrentDraft: () {
        final quantities = getProductQuantities();
        final items = getProductItems();
        Logger.debug('[Provider] Auto-save: ${quantities.length} quantities, ${items.length} complete items');
        return _buildCurrentDraft(
          productQuantities: quantities,
          productItems: items,
        );
      },
      interval: const Duration(seconds: 5),
    );

    Logger.info('[Provider] Auto-save (with product items) enabled for shop: $_selectedShopId');
  }

  /// Disable auto-save
  /// Call this when leaving the form screen
  void disableAutoSave() {
    _draftService.disableAutoSave();
    // Clear stored callbacks (they reference disposed controllers after screen dispose)
    _getProductQuantitiesCallback = null;
    _getProductItemsCallback = null;
    Logger.info('[Provider] Auto-save disabled');
  }

  /// Lock draft operations before submission starts
  /// CRITICAL: Call this BEFORE createRecord() or updateRecord() to prevent race condition
  /// where auto-save POST re-creates draft after DELETE
  void lockForSubmission() {
    _draftService.lockForSubmission();
  }

  /// Unlock draft operations after submission completes
  /// Call this after navigation away from the screen
  void unlockAfterSubmission() {
    _draftService.unlockAfterSubmission();
  }

  /// Mark a shop+date as just submitted
  /// This prevents draft restoration from backend for 60 seconds
  /// CRITICAL: Call this after successful submission to handle the race condition
  /// where stale backend draft (from POST winning against DELETE) would be restored
  void markAsJustSubmitted(String shopId, DateTime recordDate) {
    _draftService.markAsJustSubmitted(shopId, recordDate);
  }

  /// Trigger instant save (debounced 500ms) - Swiggy/Zomato style
  /// Call this on every onChange event for seamless UX
  ///
  /// CRITICAL: Skips saving in edit mode to prevent draft pollution
  void triggerInstantSave() {
    // ═══════════════════════════════════════════════════════════════════════════
    // EDIT MODE GUARD: Don't save drafts when editing existing records
    // This prevents edit mode data from polluting drafts for new entries
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      if (kDebugMode) {
        Logger.info('[Provider] triggerInstantSave SKIPPED - edit mode active');
      }
      return;
    }
    _draftService.saveDraftDebounced();
  }

  /// Manually save draft (for "Save & Exit" button)
  ///
  /// CRITICAL FIX: Now uses stored callbacks to get CURRENT data from UI controllers
  /// Optional productQuantities for backward compatibility
  ///
  /// CRITICAL: Skips saving in edit mode to prevent draft pollution
  Future<void> saveDraft([Map<String, int>? productQuantities]) async {
    // ═══════════════════════════════════════════════════════════════════════════
    // EDIT MODE GUARD: Don't save drafts when editing existing records
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      if (kDebugMode) {
        Logger.info('[Provider] saveDraft SKIPPED - edit mode active');
      }
      return;
    }

    if (_selectedShopId == null) {
      Logger.warning('[Provider] Cannot save draft: shop not selected');
      return;
    }

    // CRITICAL FIX: Use stored callbacks if available and no explicit quantities passed
    Map<String, int>? quantities = productQuantities;
    List<DraftProductItem>? productItems;

    if (quantities == null && _getProductQuantitiesCallback != null && _getProductItemsCallback != null) {
      quantities = _getProductQuantitiesCallback!();
      productItems = _getProductItemsCallback!();
      Logger.debug('[Provider] Manual save using callbacks: ${quantities.length} quantities, ${productItems.length} items');
    }

    final draft = _buildCurrentDraft(
      productQuantities: quantities,
      productItems: productItems,
    );
    await _draftService.saveDraft(_selectedShopId!, _recordDate, draft);

    _lastSavedAt = DateTime.now();
    notifyListeners();
    Logger.info('[Provider] Draft saved manually (${draft.productItems.length} products)');
  }

  /// Force save draft (for dispose() - critical to prevent data loss)
  /// This is a synchronous-style call that ensures draft is saved
  ///
  /// CRITICAL FIX: Now uses stored callbacks to get CURRENT data from UI controllers
  /// Previously it was using provider's _items which was stale (only from draft restore)
  ///
  /// CRITICAL: Skips saving in edit mode to prevent draft pollution
  Future<void> forceSaveDraft() async {
    // ═══════════════════════════════════════════════════════════════════════════
    // EDIT MODE GUARD: Don't save drafts when editing existing records
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      if (kDebugMode) {
        Logger.info('[Provider] forceSaveDraft SKIPPED - edit mode active');
      }
      return;
    }

    if (_selectedShopId == null) return;

    try {
      // CRITICAL FIX: Use stored callbacks if available (from enableAutoSaveWithProductItems)
      // These callbacks read directly from UI controllers, getting the LATEST data
      Map<String, int>? quantities;
      List<DraftProductItem>? productItems;

      if (_getProductQuantitiesCallback != null && _getProductItemsCallback != null) {
        quantities = _getProductQuantitiesCallback!();
        productItems = _getProductItemsCallback!();
        Logger.debug('[Provider] Force save using callbacks: ${quantities.length} quantities, ${productItems.length} items');
      } else if (_items.isEmpty) {
        // No callbacks and no items - nothing to save
        Logger.warning('[Provider] Force save skipped: no callbacks and no items');
        return;
      }

      final draft = _buildCurrentDraft(
        productQuantities: quantities,
        productItems: productItems,
      );
      await _draftService.saveDraft(_selectedShopId!, _recordDate, draft);
      Logger.info('[Provider] FORCE SAVE: ${draft.productItems.length} products saved');
    } catch (e) {
      Logger.error('[Provider] Force save failed: $e');
    }
  }

  /// Force save draft with explicit data (for dispose() - prevents data loss)
  /// CRITICAL: Called from screen's dispose with data built while controllers are still valid
  ///
  /// This method is the most reliable way to save data on dispose because:
  /// 1. The screen builds quantities and productItems SYNCHRONOUSLY while controllers exist
  /// 2. The data is passed directly - no callbacks that might reference disposed objects
  ///
  /// CRITICAL: Skips saving in edit mode to prevent draft pollution
  Future<void> forceSaveDraftWithData(
    Map<String, int> quantities,
    List<DraftProductItem> productItems,
  ) async {
    // ═══════════════════════════════════════════════════════════════════════════
    // EDIT MODE GUARD: Don't save drafts when editing existing records
    // ═══════════════════════════════════════════════════════════════════════════
    if (_isEditMode) {
      if (kDebugMode) {
        Logger.info('[Provider] forceSaveDraftWithData SKIPPED - edit mode active');
      }
      return;
    }

    if (_selectedShopId == null) {
      Logger.warning('[Provider] Cannot force save: shop not selected');
      return;
    }

    if (quantities.isEmpty && productItems.isEmpty) {
      Logger.warning('[Provider] Force save skipped: no data provided');
      return;
    }

    try {
      Logger.debug('[Provider] Force save with explicit data: ${quantities.length} quantities, ${productItems.length} items');
      final draft = _buildCurrentDraft(
        productQuantities: quantities,
        productItems: productItems,
      );
      await _draftService.saveDraft(_selectedShopId!, _recordDate, draft);
      Logger.info('[Provider] FORCE SAVE (explicit data): ${draft.productItems.length} products saved');
    } catch (e) {
      Logger.error('[Provider] Force save (explicit data) failed: $e');
    }
  }

  /// Load draft for shop + date
  /// Returns true if draft was restored, false otherwise
  ///
  /// CRITICAL FIX: Now restores complete product items to _items list
  /// This enables full UI restoration with product names, brands, etc.
  Future<bool> loadDraft() async {
    if (_selectedShopId == null) {
      Logger.warning('[Provider] Cannot load draft: shop not selected');
      return false;
    }

    // CRITICAL: Check if draft was explicitly cleared for this shop
    // If so, only load from local (which should be empty after clear)
    final clearKey = '${_selectedShopId}_${_formatDate(_recordDate)}';
    DailySalesDraft? draft;

    if (_draftClearedForShops.contains(clearKey)) {
      if (kDebugMode) {
        Logger.info('[Provider] loadDraft: Skipping sync - draft was explicitly cleared for $clearKey');
      }
      // Only check local, don't sync with backend
      draft = await _draftService.loadDraft(_selectedShopId!, _recordDate);
    } else {
      // CRITICAL FIX: Use syncWithBackend to fetch from backend if local is empty
      // This ensures drafts persist even after app restart
      draft = await _draftService.syncWithBackend(_selectedShopId!, _recordDate);
    }

    if (draft == null || draft.isEmpty) {
      Logger.info('[Provider] No draft found (local or backend)');
      return false;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INDUSTRIAL-GRADE FIX: DON'T restore payment amounts from draft
    // Payment values in drafts can be polluted from edit mode sessions.
    // Products are the source of truth - payment should be entered fresh
    // on Step 2 based on actual cart total.
    //
    // What we DO restore:
    // - Products and quantities (the main purpose of draft)
    // - Notes (user's text input)
    // - Expenses breakdown (if present)
    //
    // What we DON'T restore:
    // - Cash/Card/UPI/Credit amounts (can be polluted, entered on Step 2)
    // ═══════════════════════════════════════════════════════════════════════════
    // Reset payment amounts to 0 (user will enter on Step 2)
    _cashAmount = 0;
    _cardAmount = 0;
    _upiAmount = 0;
    _creditAmount = 0;

    // Restore expenses breakdown (these are legitimate user inputs)
    _expenseAmount = draft.expenseAmount;
    _expenses = Map<String, double>.from(draft.expenses);
    _notes = draft.notes;
    _lastSavedAt = draft.savedAt;
    _isDraftRestored = true;

    if (kDebugMode) {
      Logger.debug('[Provider] Draft loading: SKIPPING payment restoration (pollution prevention)');
      Logger.debug('   - Draft had: Cash=₹${draft.cashAmount}, Card=₹${draft.cardAmount}, UPI=₹${draft.upiAmount}, Credit=₹${draft.creditAmount}');
      Logger.debug('   - Setting to: Cash=₹0, Card=₹0, UPI=₹0, Credit=₹0 (user enters on Step 2)');
    }

    // CRITICAL FIX: Restore complete product items to _items list
    if (draft.productItems.isNotEmpty) {
      _items.clear();
      for (final draftItem in draft.productItems) {
        _items.add(DailySalesItem(
          productId: draftItem.productId,
          productName: draftItem.productName,
          brandName: draftItem.brandName,
          categoryName: draftItem.categoryName,
          size: draftItem.size,
          quantity: draftItem.quantity,
          unitPrice: draftItem.unitPrice,
          totalAmount: draftItem.totalAmount,
          // Auto-distribute payments to restored items
          cashAmount: 0,
          cardAmount: 0,
          upiAmount: 0,
          creditAmount: 0,
        ));
      }
      // NOTE: No longer calling _autoDistributePaymentInternal() here
      // Payment amounts are 0 after draft restore - user enters them on Step 2
      // This prevents polluted payment values from edit mode sessions

      Logger.info('[Provider] Draft restored with COMPLETE PRODUCT DATA:');
      Logger.debug('   - Products: ${_items.length}');
      Logger.debug('   - Total items amount: ₹$totalItemsAmount');
      Logger.debug('   - Payment: ₹0 (user enters on Step 2)');
    } else {
      Logger.info('[Provider] Draft restored (legacy format - no product items)');
      Logger.debug('   - Product quantities: ${draft.productQuantities.length}');
    }

    notifyListeners();

    Logger.debug('[Provider] Draft age: ${draft.ageText}');
    Logger.debug('   - Total payment: ₹${draft.totalPayment}');

    return true;
  }

  /// Check if draft exists
  Future<bool> hasDraft() async {
    if (_selectedShopId == null) return false;
    return await _draftService.hasDraft(_selectedShopId!, _recordDate);
  }

  /// Get draft for display purposes (checks backend too if local is empty)
  /// CRITICAL: If draft was explicitly cleared for this shop, skip backend sync
  Future<DailySalesDraft?> getDraft() async {
    if (_selectedShopId == null) return null;

    // CRITICAL: If user explicitly cleared draft for this shop+date, skip sync
    // This prevents backend from restoring data user just cleared
    final clearKey = '${_selectedShopId}_${_formatDate(_recordDate)}';
    if (_draftClearedForShops.contains(clearKey)) {
      if (kDebugMode) {
        Logger.info('[Provider] getDraft: Skipping sync - draft was explicitly cleared for $clearKey');
      }
      // Only check local, don't sync with backend
      return await _draftService.loadDraft(_selectedShopId!, _recordDate);
    }

    // Normal case: sync with backend
    return await _draftService.syncWithBackend(_selectedShopId!, _recordDate);
  }

  /// Clear draft after successful submission (deletes from both local and backend)
  /// CRITICAL: Also marks shop as "cleared" to prevent backend restore
  Future<void> clearDraft() async {
    if (_selectedShopId == null) return;

    // CRITICAL: Mark this shop+date as explicitly cleared
    // This prevents backend sync from restoring data
    final clearKey = '${_selectedShopId}_${_formatDate(_recordDate)}';
    _draftClearedForShops.add(clearKey);

    // Use deleteDraftWithSync to delete from both local and backend
    await _draftService.deleteDraftWithSync(_selectedShopId!, _recordDate);
    _lastSavedAt = null;
    _isDraftRestored = false;
    notifyListeners();

    if (kDebugMode) {
      Logger.info('[Provider] Draft cleared (local + backend) - shop marked as cleared: $clearKey');
    }
  }

  /// Helper to format date for clear key
  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Clear the "draft cleared" flag for a shop (call when user starts adding items again)
  void resetDraftClearedFlag() {
    if (_selectedShopId == null) return;
    final clearKey = '${_selectedShopId}_${_formatDate(_recordDate)}';
    _draftClearedForShops.remove(clearKey);
    if (kDebugMode) {
      Logger.info('[Provider] Draft cleared flag reset for: $clearKey');
    }
  }

  /// Update last saved time (called by screen when save completes)
  void updateLastSavedTime() {
    _lastSavedAt = DateTime.now();
    notifyListeners();
  }

  /// Reset draft restored flag (called when user dismisses banner)
  void resetDraftRestoredFlag() {
    _isDraftRestored = false;
    notifyListeners();
  }

  /// Reset provider state (called on logout)
  /// Clears all cached data so new user starts fresh
  void reset() {
    // Reset form state
    _recordDate = DateTime.now().subtract(const Duration(days: 1));
    _selectedShopId = null;
    _selectedSalesmanId = null;
    _notes = '';
    _cashAmount = 0.0;
    _cardAmount = 0.0;
    _upiAmount = 0.0;
    _creditAmount = 0.0;
    _expenseAmount = 0.0;
    _expenses.clear();
    _items.clear();

    // Reset loading states
    _isLoading = false;
    _isSubmitting = false;
    _errorMessage = null;

    // Reset records
    _records = [];
    _currentRecord = null;

    // Reset pagination
    _currentPage = 1;
    _hasMoreRecords = true;
    _isLoadingMore = false;

    // Reset draft state
    _lastSavedAt = null;
    _isDraftRestored = false;
    _draftClearedForShops.clear(); // Clear all "draft cleared" flags on logout

    // Reset edit mode flag (CRITICAL for preventing state leakage)
    _isEditMode = false;

    // Reset location
    _location = null;
    _isCapturingLocation = false;

    // Reset images
    _imageUrls = [];

    // Disable auto-save
    disableAutoSave();

    notifyListeners();
    if (kDebugMode) {
      Logger.info('[DailySalesProvider] State reset for logout');
    }
  }
}

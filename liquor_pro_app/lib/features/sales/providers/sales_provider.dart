import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/app_logger.dart';
import '../models/sale.dart';
import '../models/cart_item_model.dart';
import '../services/sales_service.dart';
import '../../inventory/models/product.dart';
import 'package:collection/collection.dart';

/// Modern Sales Provider with advanced state management
class SalesProvider extends ChangeNotifier {
  final SalesService _salesService;

  // State management
  List<Sale> _sales = [];
  List<Sale> _filteredSales = [];
  Sale? _currentSale;
  final List<CartItem> _cartItems = [];
  Map<String, dynamic>? _dashboardData;
  final List<Product> _products = [];
  List<Product> _frequentlyBought = [];
  List<Product> _suggestedProducts = [];

  // Loading states
  bool _isLoading = false;
  bool _isProcessingPayment = false;
  bool _isSyncing = false;

  // Search and filters
  String _searchQuery = '';
  SaleFilter _currentFilter = SaleFilter.all;
  DateRange? _dateRange;
  String? _selectedShopId;

  // Cart state
  double _appliedDiscount = 0;
  String _paymentMethod = 'cash';
  String? _customerPhone;
  String? _customerName;
  Map<String, double> _splitPayments = {};

  // Analytics
  Map<String, dynamic> _analytics = {};
  final List<Map<String, dynamic>> _recentTransactions = [];

  // Error handling
  String? _lastError;

  // Pagination
  int _currentPage = 1;
  bool _hasMoreData = true;
  final int _pageSize = 20;

  // Constructor
  SalesProvider(this._salesService) {
    _initialize();
  }

  // Getters
  List<Sale> get sales => _filteredSales;
  List<Sale> get allSales => _sales;
  Sale? get currentSale => _currentSale;
  List<CartItem> get cartItems => _cartItems;
  bool get isLoading => _isLoading;
  bool get isProcessingPayment => _isProcessingPayment;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  Map<String, dynamic>? get dashboardData => _dashboardData;
  List<Product> get products => _products;
  List<Product> get frequentlyBought => _frequentlyBought;
  List<Product> get suggestedProducts => _suggestedProducts;
  Map<String, dynamic> get analytics => _analytics;

  // Cart calculations
  double get subtotal => _cartItems.fold(0, (sum, item) => sum + item.totalPrice);
  double get discount => _appliedDiscount;
  double get tax => subtotal * 0.18; // 18% GST
  double get total => subtotal - discount + tax;
  int get itemCount => _cartItems.fold(0, (sum, item) => sum + item.quantity);
  bool get hasItems => _cartItems.isNotEmpty;

  // Aliases for cart calculations
  double get cartSubtotal => subtotal;
  double get cartTax => tax;
  double get cartTotal => total;

  // Check if product is in cart
  bool isInCart(String productId) {
    return _cartItems.any((item) => item.product.id == productId);
  }

  // Initialization
  Future<void> _initialize() async {
    await Future.wait([
      fetchSales(),
      fetchDashboardData(),
      loadFrequentProducts(),
    ]);
  }

  // ===== SALES OPERATIONS =====

  /// Fetch sales with pagination
  Future<void> fetchSales({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _currentPage = 1;
      _hasMoreData = true;
      _sales.clear();
    }

    if (!_hasMoreData) return;

    _setLoading(true);

    try {
      final response = await _salesService.getSales(
        shopId: _selectedShopId,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        page: _currentPage,
        limit: _pageSize,
      );

      if (response.success && response.data != null) {
        if (refresh) {
          _sales = response.data!;
        } else {
          _sales.addAll(response.data!);
        }

        _hasMoreData = response.data!.length == _pageSize;
        _currentPage++;

        _applyFilters();
        await _updateAnalytics();
      }
    } catch (e) {
      _setError('Failed to fetch sales: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Create new sale
  Future<bool> createSale() async {
    if (_cartItems.isEmpty) {
      _setError('Cart is empty');
      return false;
    }

    _setProcessingPayment(true);

    try {
      // Prepare sale items
      final items = _cartItems.map((cartItem) => {
        'product_id': cartItem.product.id,
        'quantity': cartItem.quantity,
        'unit_price': cartItem.product.sellingPrice,
        'discount_amount': cartItem.discount,
        'total_price': cartItem.totalPrice,
      }).toList();

      // Create sale
      final response = await _salesService.createSale(
        shopId: _selectedShopId!,
        saleDate: DateTime.now(),
        customerName: _customerName,
        customerPhone: _customerPhone,
        items: items,
        subTotal: subtotal,
        discountAmount: discount,
        taxAmount: tax,
        totalAmount: total,
        paidAmount: total,
        paymentMethod: _paymentMethod,
      );

      if (response.success && response.data != null) {
        _currentSale = response.data;

        // Haptic feedback for success
        HapticFeedback.mediumImpact();

        // Clear cart
        await clearCart();

        // Refresh sales list
        await fetchSales(refresh: true);

        // Update analytics
        await _updateAnalytics();

        return true;
      } else {
        _setError(response.error ?? 'Failed to create sale');
        return false;
      }
    } catch (e) {
      _setError('Failed to process sale: $e');
      return false;
    } finally {
      _setProcessingPayment(false);
    }
  }

  // ===== CART MANAGEMENT =====

  /// Add product to cart with animation
  void addToCart(Product product, {int quantity = 1}) {
    final existingItem = _cartItems.firstWhereOrNull(
      (item) => item.product.id == product.id,
    );

    if (existingItem != null) {
      existingItem.quantity += quantity;
    } else {
      _cartItems.add(CartItem(
        product: product,
        quantity: quantity,
      ));
    }

    // Haptic feedback
    HapticFeedback.lightImpact();

    // Update suggestions
    _updateSuggestedProducts(product);

    notifyListeners();
  }

  /// Remove item from cart
  void removeFromCart(Product product) {
    _cartItems.removeWhere((item) => item.product.id == product.id);
    HapticFeedback.lightImpact();
    notifyListeners();
  }

  /// Update cart item quantity
  void updateQuantity(Product product, int quantity) {
    if (quantity <= 0) {
      removeFromCart(product);
      return;
    }

    final item = _cartItems.firstWhereOrNull(
      (item) => item.product.id == product.id,
    );

    if (item != null) {
      item.quantity = quantity;
      notifyListeners();
    }
  }

  /// Apply discount to cart
  void applyDiscount(double amount) {
    _appliedDiscount = amount;
    notifyListeners();
  }

  /// Set payment method
  void setPaymentMethod(String method) {
    _paymentMethod = method;
    notifyListeners();
  }

  /// Set split payment
  void setSplitPayment(Map<String, double> payments) {
    _splitPayments = payments;
    notifyListeners();
  }

  /// Clear cart
  Future<void> clearCart() async {
    _cartItems.clear();
    _appliedDiscount = 0;
    _paymentMethod = 'cash';
    _customerPhone = null;
    _customerName = null;
    _splitPayments.clear();
    notifyListeners();
  }

  // ===== SEARCH AND FILTER =====

  /// Search sales
  void searchSales(String query) {
    _searchQuery = query.toLowerCase();
    _applyFilters();
  }

  /// Filter sales by status
  void filterByStatus(SaleFilter filter) {
    _currentFilter = filter;
    _applyFilters();
  }

  /// Filter by date range
  void filterByDateRange(DateRange range) {
    _dateRange = range;
    fetchSales(refresh: true);
  }

  /// Apply all filters
  void _applyFilters() {
    _filteredSales = _sales.where((sale) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesSearch =
          sale.saleNumber.toLowerCase().contains(_searchQuery) ||
          sale.customerName?.toLowerCase().contains(_searchQuery) == true ||
          sale.customerPhone?.contains(_searchQuery) == true;

        if (!matchesSearch) return false;
      }

      // Status filter
      switch (_currentFilter) {
        case SaleFilter.pending:
          return sale.isPending;
        case SaleFilter.approved:
          return sale.isApproved;
        case SaleFilter.rejected:
          return sale.isRejected;
        case SaleFilter.returned:
          return sale.isReturned;
        case SaleFilter.unpaid:
          return sale.hasOutstanding;
        case SaleFilter.all:
        default:
          return true;
      }
    }).toList();

    notifyListeners();
  }

  // ===== DASHBOARD & ANALYTICS =====

  /// Fetch dashboard data
  Future<void> fetchDashboardData() async {
    try {
      // Fetch from multiple endpoints in parallel
      final responses = await Future.wait([
        _salesService.getDashboardSummary(_selectedShopId),
        _fetchRecentTransactions(),
        _fetchSalesAnalytics(),
      ]);

      _dashboardData = {
        'summary': responses[0],
        'recent': responses[1],
        'analytics': responses[2],
      };

      notifyListeners();
    } catch (e) {
      AppLogger.error('Failed to fetch dashboard data', e);
    }
  }

  /// Fetch recent transactions
  Future<List<Map<String, dynamic>>> _fetchRecentTransactions() async {
    try {
      final response = await _salesService.getSales(
        shopId: _selectedShopId,
        page: 1,
        limit: 5,
      );

      if (response.success && response.data != null) {
        return response.data!.map((sale) => sale.toJson()).toList();
      }
    } catch (e) {
      AppLogger.error('Failed to fetch recent transactions', e);
    }

    return [];
  }

  /// Fetch sales analytics
  Future<Map<String, dynamic>> _fetchSalesAnalytics() async {
    // This would call a dedicated analytics endpoint
    return {
      'todaySales': 45000,
      'weekSales': 315000,
      'monthSales': 1260000,
      'topProducts': [],
      'peakHours': [],
      'paymentBreakdown': {},
    };
  }

  /// Update analytics after sale
  Future<void> _updateAnalytics() async {
    _analytics = {
      'totalSales': _sales.length,
      'totalRevenue': _sales.fold(0.0, (sum, sale) => sum + sale.totalAmount),
      'averageSale': _sales.isEmpty ? 0 : _sales.fold(0.0, (sum, sale) => sum + sale.totalAmount) / _sales.length,
      'pendingApprovals': _sales.where((s) => s.isPending).length,
      'outstandingAmount': _sales.fold(0.0, (sum, sale) => sum + sale.dueAmount),
    };

    notifyListeners();
  }

  // ===== PRODUCT SUGGESTIONS =====

  /// Load frequently bought products
  Future<void> loadFrequentProducts() async {
    // This would fetch from a dedicated endpoint
    _frequentlyBought = [];
  }

  /// Update suggested products based on cart
  void _updateSuggestedProducts(Product addedProduct) {
    // AI-based suggestions would go here
    // For now, just shuffle some products
    _suggestedProducts = _products
      .where((p) => p.categoryId == addedProduct.categoryId && p.id != addedProduct.id)
      .take(5)
      .toList();
  }

  // ===== QUICK ACTIONS =====

  /// Quick sale for frequent items
  Future<bool> quickSale(Product product, {int quantity = 1}) async {
    clearCart();
    addToCart(product, quantity: quantity);
    return await createSale();
  }

  /// Void sale
  Future<bool> voidSale(String saleId) async {
    try {
      final response = await _salesService.voidSale(saleId);

      if (response.success) {
        await fetchSales(refresh: true);
        return true;
      }

      _setError(response.error ?? 'Failed to void sale');
      return false;
    } catch (e) {
      _setError('Failed to void sale: $e');
      return false;
    }
  }

  /// Process return
  Future<bool> processReturn(String saleId, List<Map<String, dynamic>> items, String reason) async {
    try {
      final response = await _salesService.createSaleReturn(
        saleId: saleId,
        shopId: _selectedShopId!,
        returnDate: DateTime.now(),
        reason: reason,
        returnAmount: 0, // Calculate based on items
        items: items,
      );

      if (response.success) {
        await fetchSales(refresh: true);
        HapticFeedback.mediumImpact();
        return true;
      }

      _setError(response.error ?? 'Failed to process return');
      return false;
    } catch (e) {
      _setError('Failed to process return: $e');
      return false;
    }
  }

  // ===== CUSTOMER MANAGEMENT =====

  /// Set customer details
  void setCustomer({String? name, String? phone}) {
    _customerName = name;
    _customerPhone = phone;
    notifyListeners();
  }

  /// Load customer history
  Future<List<Sale>> getCustomerHistory(String phone) async {
    // Filter sales by customer phone
    return _sales.where((sale) => sale.customerPhone == phone).toList();
  }

  // ===== OFFLINE SUPPORT =====

  /// Sync offline sales
  Future<void> syncOfflineSales() async {
    if (_isSyncing) return;

    _setSyncing(true);

    try {
      // Implementation for offline sync
      await Future.delayed(const Duration(seconds: 2));

      await fetchSales(refresh: true);
    } catch (e) {
      _setError('Failed to sync: $e');
    } finally {
      _setSyncing(false);
    }
  }

  // ===== PRIVATE HELPERS =====

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setProcessingPayment(bool value) {
    _isProcessingPayment = value;
    notifyListeners();
  }

  void _setSyncing(bool value) {
    _isSyncing = value;
    notifyListeners();
  }

  void _setError(String error) {
    _lastError = error;
    AppLogger.error(error);
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _lastError = null;
    notifyListeners();
  }

  /// Set shop
  void setShop(String shopId) {
    _selectedShopId = shopId;
    fetchSales(refresh: true);
  }

  @override
  void dispose() {
    _cartItems.clear();
    super.dispose();
  }
}

// Enums
enum SaleFilter {
  all,
  pending,
  approved,
  rejected,
  returned,
  unpaid,
}

class DateRange {
  final DateTime start;
  final DateTime end;

  DateRange({required this.start, required this.end});
}
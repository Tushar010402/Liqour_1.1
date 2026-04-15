import 'package:flutter/foundation.dart';
import '../models/vendor_model.dart';
import '../services/vendor_service.dart';

/// Vendor Provider - State management for vendor operations
/// OPTIMIZED: Added kDebugMode guards to reduce logging overhead
///
/// Provides centralized state management for:
/// - Vendor list with caching
/// - CRUD operations
/// - Transaction history
/// - Search and filtering
/// - Financial calculations
class VendorProvider with ChangeNotifier {
  final VendorService _vendorService;

  List<Vendor> _vendors = [];
  Vendor? _selectedVendor;
  List<VendorTransaction> _selectedVendorTransactions = [];
  bool _isLoading = false;
  bool _isLoadingTransactions = false;
  String? _errorMessage;

  VendorProvider(this._vendorService);

  // Getters
  List<Vendor> get vendors => _vendors;
  Vendor? get selectedVendor => _selectedVendor;
  List<VendorTransaction> get selectedVendorTransactions =>
      _selectedVendorTransactions;
  bool get isLoading => _isLoading;
  bool get isLoadingTransactions => _isLoadingTransactions;
  String? get errorMessage => _errorMessage;

  // Computed properties
  double get totalOutstanding {
    return _vendors.fold(0.0, (sum, vendor) => sum + vendor.outstandingBalance);
  }

  int get activeVendorCount {
    return _vendors.where((vendor) => vendor.isActive).length;
  }

  int get vendorCount => _vendors.length;

  List<Vendor> get vendorsWithOutstanding {
    return _vendors
        .where((vendor) => vendor.hasOutstanding)
        .toList()
      ..sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
  }

  List<Vendor> get topVendorsByPurchases {
    return [..._vendors]
      ..sort((a, b) => b.totalPurchases.compareTo(a.totalPurchases))
      ..take(5);
  }

  // Load all vendors
  Future<void> loadVendors({
    bool includeInactive = false,
    bool forceRefresh = false,
  }) async {
    if (kDebugMode) print('🏪 VendorProvider: Loading vendors (forceRefresh: $forceRefresh)...');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final response = await _vendorService.getVendors(
      includeInactive: includeInactive,
      forceRefresh: forceRefresh,
    );

    if (response.success && response.data != null) {
      _vendors = response.data!;
      _errorMessage = null;
      if (kDebugMode) print('✅ VendorProvider: Loaded ${_vendors.length} vendors');
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Load failed - $_errorMessage');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Create new vendor
  Future<bool> createVendor(VendorRequest request) async {
    if (kDebugMode) print('🏪 VendorProvider: Creating vendor - ${request.name}');

    final response = await _vendorService.createVendor(request);

    if (response.success) {
      if (kDebugMode) print('✅ VendorProvider: Vendor created - forcing cache refresh');
      // Force refresh to bypass all caches and get updated list from backend
      await loadVendors(forceRefresh: true);
      return true;
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Create failed - $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Update existing vendor
  Future<bool> updateVendor(String id, VendorRequest request) async {
    if (kDebugMode) print('🏪 VendorProvider: Updating vendor - $id');

    final response = await _vendorService.updateVendor(id, request);

    if (response.success) {
      if (kDebugMode) print('✅ VendorProvider: Vendor updated - forcing cache refresh');
      // Force refresh to bypass all caches and get updated list from backend
      await loadVendors(forceRefresh: true);

      // Update selected vendor if it's the one being edited
      if (_selectedVendor?.id == id) {
        await selectVendor(id);
      }

      return true;
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Update failed - $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Delete vendor
  Future<bool> deleteVendor(String id) async {
    if (kDebugMode) print('🏪 VendorProvider: Deleting vendor - $id');

    final response = await _vendorService.deleteVendor(id);

    if (response.success) {
      if (kDebugMode) print('✅ VendorProvider: Vendor deleted - forcing cache refresh');

      // Clear selection if deleted vendor was selected
      if (_selectedVendor?.id == id) {
        clearSelection();
      }

      // Force refresh to bypass all caches and get updated list from backend
      await loadVendors(forceRefresh: true);
      return true;
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Delete failed - $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Select vendor and load details
  Future<void> selectVendor(String id) async {
    if (kDebugMode) print('🏪 VendorProvider: Selecting vendor - $id');
    _isLoading = true;
    notifyListeners();

    final response = await _vendorService.getVendorById(id);

    if (response.success && response.data != null) {
      _selectedVendor = response.data;
      if (kDebugMode) print('✅ VendorProvider: Vendor selected - ${_selectedVendor!.name}');

      // Load transactions for selected vendor
      await loadVendorTransactions(id);
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Selection failed - $_errorMessage');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Load transaction history for selected vendor
  Future<void> loadVendorTransactions(String vendorId) async {
    if (kDebugMode) print('💰 VendorProvider: Loading transactions - $vendorId');
    _isLoadingTransactions = true;
    notifyListeners();

    final response = await _vendorService.getVendorTransactions(vendorId);

    if (response.success && response.data != null) {
      _selectedVendorTransactions = response.data!;
      if (kDebugMode) print('✅ VendorProvider: Loaded ${_selectedVendorTransactions.length} transactions');
    } else {
      if (kDebugMode) print('❌ VendorProvider: Transaction load failed - ${response.error}');
      _selectedVendorTransactions = [];
    }

    _isLoadingTransactions = false;
    notifyListeners();
  }

  // Record payment to vendor
  Future<bool> recordPayment({
    required String vendorId,
    required double amount,
    required String paymentMethod,
    String? referenceNo,
    String? description,
  }) async {
    if (kDebugMode) print('💸 VendorProvider: Recording payment - $vendorId, ₹$amount');

    final response = await _vendorService.recordPayment(
      vendorId: vendorId,
      amount: amount,
      paymentMethod: paymentMethod,
      referenceNo: referenceNo,
      description: description,
    );

    if (response.success) {
      if (kDebugMode) print('✅ VendorProvider: Payment recorded - forcing cache refresh');

      // Refresh vendor details
      await selectVendor(vendorId);

      // Refresh main list to update outstanding balances (force refresh)
      await loadVendors(forceRefresh: true);

      return true;
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Payment failed - $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Add bank account to vendor
  Future<bool> addBankAccount(
    String vendorId,
    VendorBankAccountRequest request,
  ) async {
    if (kDebugMode) print('🏦 VendorProvider: Adding bank account - $vendorId');

    final response = await _vendorService.addBankAccount(vendorId, request);

    if (response.success) {
      if (kDebugMode) print('✅ VendorProvider: Bank account added');

      // Refresh vendor details
      await selectVendor(vendorId);

      return true;
    } else {
      _errorMessage = response.error;
      if (kDebugMode) print('❌ VendorProvider: Bank account add failed - $_errorMessage');
      notifyListeners();
      return false;
    }
  }

  // Clear selected vendor
  void clearSelection() {
    if (kDebugMode) print('🏪 VendorProvider: Clearing selection');
    _selectedVendor = null;
    _selectedVendorTransactions = [];
    notifyListeners();
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Get vendor by ID from cached list
  Vendor? getVendorById(String id) {
    try {
      return _vendors.firstWhere((vendor) => vendor.id == id);
    } catch (e) {
      if (kDebugMode) print('⚠️ VendorProvider: Vendor not found in cache - $id');
      return null;
    }
  }

  // Search vendors (client-side filtering)
  List<Vendor> searchVendors(String query) {
    if (query.isEmpty) return _vendors;

    final lowerQuery = query.toLowerCase();

    return _vendors.where((vendor) {
      return vendor.name.toLowerCase().contains(lowerQuery) ||
          (vendor.contactPerson?.toLowerCase().contains(lowerQuery) ?? false) ||
          (vendor.phone?.contains(query) ?? false) ||
          (vendor.email?.toLowerCase().contains(lowerQuery) ?? false);
    }).toList();
  }

  // Filter active vendors
  List<Vendor> get activeVendors {
    return _vendors.where((vendor) => vendor.isActive).toList();
  }

  // Filter inactive vendors
  List<Vendor> get inactiveVendors {
    return _vendors.where((vendor) => !vendor.isActive).toList();
  }

  // Get purchase transactions for selected vendor
  List<VendorTransaction> get purchaseTransactions {
    return _selectedVendorTransactions
        .where((transaction) => transaction.isPurchase)
        .toList();
  }

  // Get payment transactions for selected vendor
  List<VendorTransaction> get paymentTransactions {
    return _selectedVendorTransactions
        .where((transaction) => transaction.isPayment)
        .toList();
  }

  // Calculate total purchases for selected vendor
  double get selectedVendorTotalPurchases {
    return purchaseTransactions.fold(
      0.0,
      (sum, transaction) => sum + transaction.amount,
    );
  }

  // Calculate total payments for selected vendor
  double get selectedVendorTotalPayments {
    return paymentTransactions.fold(
      0.0,
      (sum, transaction) => sum + transaction.amount,
    );
  }

  // Check if vendor has pending transactions
  bool hasRecentTransactions(String vendorId) {
    final vendor = getVendorById(vendorId);
    if (vendor == null) return false;

    final daysSinceUpdate = DateTime.now().difference(vendor.updatedAt).inDays;
    return daysSinceUpdate <= 30;
  }

  // Get vendors needing payment (high outstanding balance)
  List<Vendor> get vendorsNeedingPayment {
    return _vendors
        .where((vendor) =>
            vendor.hasOutstanding &&
            vendor.outstandingBalance > vendor.creditLimit * 0.8)
        .toList()
      ..sort((a, b) => b.outstandingBalance.compareTo(a.outstandingBalance));
  }

  // Refresh current state
  Future<void> refresh() async {
    if (kDebugMode) print('🔄 VendorProvider: Refreshing vendor data (forcing cache bypass)');
    // Always force refresh when user explicitly requests refresh
    await loadVendors(forceRefresh: true);

    if (_selectedVendor != null) {
      await selectVendor(_selectedVendor!.id);
    }
  }

  /// Reset all state — called on logout to prevent stale data
  void reset() {
    _vendors = [];
    _selectedVendor = null;
    _selectedVendorTransactions = [];
    _isLoading = false;
    _isLoadingTransactions = false;
    _errorMessage = null;
    notifyListeners();
  }
}

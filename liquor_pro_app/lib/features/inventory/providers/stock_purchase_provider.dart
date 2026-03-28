/// Stock Purchase Provider - Industrial Grade State Management
///
/// Manages stock purchase operations with approval workflow.
/// Follows best practices from modern platforms like Swiggy/Zomato.
library;

import 'package:flutter/foundation.dart';
import '../services/stock_purchase_service.dart';
import '../models/stock_purchase.dart';

/// Stock Purchase Provider - ChangeNotifier for stock purchase state
class StockPurchaseProvider extends ChangeNotifier {
  final StockPurchaseService _service;

  StockPurchaseProvider(this._service);

  // State
  List<StockPurchase> _pendingApprovals = [];
  List<StockPurchase> _purchaseHistory = [];
  StockPurchase? _selectedPurchase;
  bool _isLoading = false;
  String? _errorMessage;
  int _pendingCount = 0;

  // Pagination state
  int _currentPage = 1;
  int _totalItems = 0;
  bool _hasMore = true;

  // Getters
  List<StockPurchase> get pendingApprovals => _pendingApprovals;
  List<StockPurchase> get purchaseHistory => _purchaseHistory;
  StockPurchase? get selectedPurchase => _selectedPurchase;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get pendingCount => _pendingCount;
  bool get hasMore => _hasMore;
  int get totalItems => _totalItems;

  // Helper getters
  bool get hasPendingApprovals => _pendingApprovals.isNotEmpty;

  /// Submit a new stock purchase request
  ///
  /// Returns true if successful, false otherwise.
  /// For Admin/Manager: Auto-approved
  /// For others: Creates pending request
  Future<bool> submitPurchaseRequest({
    required String shopId,
    required String vendorId,
    required List<StockPurchaseItem> items,
    String? notes,
    double? roundOff, // Round-off adjustment (auto-calculated or manual)
    // Receipt Information
    String? receiptNumber,
    DateTime? receiptDate,
    String? receiptImageUrl,
    String? receiptNotes,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.submitPurchaseRequest()');
      debugPrint('   - Shop: $shopId');
      debugPrint('   - Vendor: $vendorId');
      debugPrint('   - Items: ${items.length}');
      if (roundOff != null) debugPrint('   - Round Off: $roundOff');
      if (receiptNumber != null) debugPrint('   - Receipt #: $receiptNumber');
      if (receiptImageUrl != null) debugPrint('   - Receipt Image: ✓');

      final response = await _service.createPurchaseRequest(
        shopId: shopId,
        vendorId: vendorId,
        items: items,
        notes: notes,
        roundOff: roundOff,
        receiptNumber: receiptNumber,
        receiptDate: receiptDate,
        receiptImageUrl: receiptImageUrl,
        receiptNotes: receiptNotes,
      );

      if (response.success && response.data != null) {
        final purchase = response.data!;
        debugPrint('✅ Purchase request created: ${purchase.id}');
        debugPrint('   - Status: ${purchase.status.displayName}');

        // If it was auto-approved, refresh history
        if (purchase.status.isApproved) {
          await loadPurchaseHistory(shopId: shopId, refresh: true);
        }

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _errorMessage = response.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ Error submitting purchase request: $e');
      _errorMessage = 'Failed to submit purchase request: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Load pending approvals (for managers)
  Future<void> loadPendingApprovals({
    String? shopId,
    bool refresh = false,
  }) async {
    if (_isLoading && !refresh) return;

    if (refresh) {
      _currentPage = 1;
      _pendingApprovals = [];
      _hasMore = true;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.loadPendingApprovals()');

      final response = await _service.getPendingApprovals(
        shopId: shopId,
        page: _currentPage,
      );

      if (response.success && response.data != null) {
        final data = response.data!;

        if (refresh) {
          _pendingApprovals = data.purchases;
        } else {
          _pendingApprovals.addAll(data.purchases);
        }

        _totalItems = data.total;
        _pendingCount = data.total;
        _hasMore = data.hasMore;
        _currentPage++;

        debugPrint('✅ Loaded ${data.purchases.length} pending approvals');
        debugPrint('   - Total pending: $_pendingCount');
      } else {
        _errorMessage = response.message;
      }
    } catch (e) {
      debugPrint('❌ Error loading pending approvals: $e');
      _errorMessage = 'Failed to load pending approvals: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Approve a stock purchase
  Future<bool> approvePurchase(String purchaseId, {String? notes}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.approvePurchase($purchaseId)');

      final response = await _service.approvePurchase(
        purchaseId: purchaseId,
        notes: notes,
      );

      if (response.success) {
        // Remove from pending list
        _pendingApprovals.removeWhere((p) => p.id == purchaseId);
        _pendingCount = _pendingApprovals.length;

        debugPrint('✅ Purchase approved successfully');

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _errorMessage = response.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ Error approving purchase: $e');
      _errorMessage = 'Failed to approve purchase: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Reject a stock purchase
  Future<bool> rejectPurchase(String purchaseId, String reason) async {
    if (reason.trim().isEmpty) {
      _errorMessage = 'Rejection reason is required';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.rejectPurchase($purchaseId)');
      debugPrint('   - Reason: $reason');

      final response = await _service.rejectPurchase(
        purchaseId: purchaseId,
        reason: reason,
      );

      if (response.success) {
        // Remove from pending list
        _pendingApprovals.removeWhere((p) => p.id == purchaseId);
        _pendingCount = _pendingApprovals.length;

        debugPrint('✅ Purchase rejected successfully');

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _errorMessage = response.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ Error rejecting purchase: $e');
      _errorMessage = 'Failed to reject purchase: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Load purchase history
  Future<void> loadPurchaseHistory({
    String? shopId,
    String? vendorId,
    StockPurchaseStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
    bool refresh = false,
  }) async {
    if (_isLoading && !refresh) return;

    if (refresh) {
      _currentPage = 1;
      _purchaseHistory = [];
      _hasMore = true;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.loadPurchaseHistory()');

      final response = await _service.getPurchaseHistory(
        shopId: shopId,
        vendorId: vendorId,
        status: status,
        fromDate: fromDate,
        toDate: toDate,
        page: _currentPage,
      );

      if (response.success && response.data != null) {
        final data = response.data!;

        if (refresh) {
          _purchaseHistory = data.purchases;
        } else {
          _purchaseHistory.addAll(data.purchases);
        }

        _totalItems = data.total;
        _hasMore = data.hasMore;
        _currentPage++;

        debugPrint('✅ Loaded ${data.purchases.length} purchase history items');
      } else {
        _errorMessage = response.message;
      }
    } catch (e) {
      debugPrint('❌ Error loading purchase history: $e');
      _errorMessage = 'Failed to load purchase history: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load more history (pagination)
  Future<void> loadMoreHistory({
    String? shopId,
    String? vendorId,
    StockPurchaseStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    if (!_hasMore || _isLoading) return;

    await loadPurchaseHistory(
      shopId: shopId,
      vendorId: vendorId,
      status: status,
      fromDate: fromDate,
      toDate: toDate,
    );
  }

  /// Select a purchase for detail view
  Future<void> selectPurchase(String purchaseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.selectPurchase($purchaseId)');

      final response = await _service.getPurchase(purchaseId);

      if (response.success && response.data != null) {
        _selectedPurchase = response.data;
        debugPrint('✅ Loaded purchase details');
      } else {
        _errorMessage = response.message;
      }
    } catch (e) {
      debugPrint('❌ Error loading purchase details: $e');
      _errorMessage = 'Failed to load purchase details: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Clear selected purchase
  void clearSelectedPurchase() {
    _selectedPurchase = null;
    notifyListeners();
  }

  /// Cancel a pending purchase (only by creator)
  Future<bool> cancelPurchase(String purchaseId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      debugPrint('📦 StockPurchaseProvider.cancelPurchase($purchaseId)');

      final response = await _service.cancelPurchase(purchaseId);

      if (response.success) {
        // Remove from pending list
        _pendingApprovals.removeWhere((p) => p.id == purchaseId);
        _pendingCount = _pendingApprovals.length;

        debugPrint('✅ Purchase cancelled successfully');

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _errorMessage = response.message;
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('❌ Error cancelling purchase: $e');
      _errorMessage = 'Failed to cancel purchase: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset all state
  void reset() {
    _pendingApprovals = [];
    _purchaseHistory = [];
    _selectedPurchase = null;
    _isLoading = false;
    _errorMessage = null;
    _pendingCount = 0;
    _currentPage = 1;
    _totalItems = 0;
    _hasMore = true;
    notifyListeners();
  }

  /// Get purchase by ID from local cache
  StockPurchase? getPurchaseFromCache(String purchaseId) {
    // Check pending approvals
    final pending = _pendingApprovals.where((p) => p.id == purchaseId);
    if (pending.isNotEmpty) return pending.first;

    // Check history
    final history = _purchaseHistory.where((p) => p.id == purchaseId);
    if (history.isNotEmpty) return history.first;

    return null;
  }

  /// Check if current user can approve a purchase
  bool canApprove(StockPurchase purchase, String currentUserRole) {
    return purchase.canBeApprovedBy(currentUserRole);
  }

  /// Get pending approvals count badge
  String get pendingBadge {
    if (_pendingCount == 0) return '';
    if (_pendingCount > 99) return '99+';
    return _pendingCount.toString();
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/app_logger.dart';
import '../models/cash_models.dart';
import '../services/cash_service.dart';

/// Provider for managing cash collection approval workflow
class CashApprovalProvider with ChangeNotifier {
  final CashService _cashService;

  List<CashCollection> _pendingCollections = [];
  bool _isLoading = false;
  String? _error;
  Timer? _refreshTimer;

  CashApprovalProvider(DioApiService apiService)
      : _cashService = CashService(apiService);

  List<CashCollection> get pendingCollections => _pendingCollections;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Get count of pending collections
  int get pendingCount => _pendingCollections.length;

  /// Get count of expiring soon (< 3 minutes remaining)
  int get expiringSoonCount => _pendingCollections
      .where((c) => c.timeRemaining != null && c.timeRemaining!.inMinutes < 3)
      .length;

  /// Load pending collections for a shop
  Future<void> loadPendingCollections(String shopId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _pendingCollections = await _cashService.getPendingCollections(
        shopId: shopId,
      );

      // Remove any expired collections from the list
      _pendingCollections.removeWhere((c) => c.hasExpired);

      _error = null;
      AppLogger.info('Loaded ${_pendingCollections.length} pending collections');
    } catch (e) {
      _error = e.toString();
      AppLogger.error('Failed to load pending collections: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Approve a collection request
  Future<bool> approveCollection(String collectionId) async {
    try {
      await _cashService.approveCollection(collectionId);

      // Remove from pending list
      _pendingCollections.removeWhere((c) => c.id == collectionId);

      AppLogger.info('Collection approved: $collectionId');
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      AppLogger.error('Failed to approve collection: $e');
      notifyListeners();
      return false;
    }
  }

  /// Reject a collection request with reason
  Future<bool> rejectCollection(String collectionId, String reason) async {
    try {
      await _cashService.rejectCollection(collectionId, reason);

      // Remove from pending list
      _pendingCollections.removeWhere((c) => c.id == collectionId);

      AppLogger.info('Collection rejected: $collectionId - Reason: $reason');
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      AppLogger.error('Failed to reject collection: $e');
      notifyListeners();
      return false;
    }
  }

  /// Start auto-refresh timer (refreshes every 10 seconds)
  void startAutoRefresh(String shopId) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      loadPendingCollections(shopId);
    });
  }

  /// Stop auto-refresh timer
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// Remove expired collections from the list
  void removeExpiredCollections() {
    final before = _pendingCollections.length;
    _pendingCollections.removeWhere((c) => c.hasExpired);

    if (_pendingCollections.length != before) {
      AppLogger.info('Removed ${before - _pendingCollections.length} expired collections');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

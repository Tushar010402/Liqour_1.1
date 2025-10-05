import 'package:flutter/material.dart';
import '../models/dashboard_summary.dart';
import '../services/dashboard_service.dart';
import '../../../core/utils/logger.dart';

/// Dashboard Provider - Manages dashboard state
class DashboardProvider with ChangeNotifier {
  final DashboardService _dashboardService;

  DashboardProvider(this._dashboardService);

  DashboardSummary? _summary;
  bool _isLoading = false;
  String? _errorMessage;
  String? _selectedShopId;

  // Getters
  DashboardSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get selectedShopId => _selectedShopId;

  /// Load dashboard summary
  Future<void> loadDashboard({String? shopId}) async {
    Logger.debug('📊 DashboardProvider.loadDashboard() called');
    _isLoading = true;
    _errorMessage = null;
    _selectedShopId = shopId;
    notifyListeners();

    try {
      Logger.debug('📊 DashboardProvider: Calling _dashboardService.getDashboardSummary()');
      final response = await _dashboardService.getDashboardSummary(
        shopId: shopId,
      );

      Logger.debug('📊 DashboardProvider: Response received - success: ${response.success}');

      if (response.success && response.data != null) {
        _summary = response.data;
        _errorMessage = null;
        Logger.debug('📊 DashboardProvider: Loaded dashboard successfully');
      } else {
        _errorMessage = response.message ?? 'Failed to load dashboard';
        _summary = null;
        Logger.debug('📊 DashboardProvider: Error - $_errorMessage');
      }
    } catch (e) {
      _errorMessage = 'Error loading dashboard: $e';
      _summary = null;
      Logger.debug('📊 DashboardProvider: Exception - $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh dashboard
  Future<void> refreshDashboard() async {
    return loadDashboard(shopId: _selectedShopId);
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}

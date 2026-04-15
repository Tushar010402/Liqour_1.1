import 'package:flutter/material.dart';
import '../models/dashboard_metrics.dart';
import '../models/dashboard_summary.dart';
import '../services/dashboard_service.dart';
import '../services/day_closing_service.dart';

/// Dashboard Provider - Manages dashboard state
class DashboardProvider with ChangeNotifier {
  final DashboardService _dashboardService;
  DayClosingService? _dayClosingService;

  DashboardProvider(this._dashboardService);

  /// Inject day-closing service (set from main.dart or lazily)
  set dayClosingService(DayClosingService service) => _dayClosingService = service;

  // Original summary state
  DashboardSummary? _summary;

  // Local day-closing overrides (shown immediately, persisted via API)
  double? _localCashTotal; // raw cash counted (before expense deduction)
  double? _localUpiAmount;
  double? _localExpenseAmount;

  // Full breakdown data for sending to backend AND populating sheets on reopen
  Map<int, int>? _lastCashDenominations;
  Map<String, double>? _lastUpiBreakdown;
  Map<String, double>? _lastExpenses;

  // Public getters for populating sheets with saved data
  Map<int, int>? get lastCashDenominations => _lastCashDenominations;
  Map<String, double>? get lastUpiBreakdown => _lastUpiBreakdown;
  Map<String, double>? get lastExpenses => _lastExpenses;

  /// Cash in hand = totalSales - UPI - expenses (auto-calculated)
  double get effectiveCashAmount {
    final totalSales = _summary?.totalRevenue ?? 0;
    final upi = _localUpiAmount ?? _summary?.upiAmount ?? 0;
    final expense = _localExpenseAmount ?? _summary?.expenseAmount ?? 0;
    final cash = totalSales - upi - expense;
    return cash < 0 ? 0 : cash;
  }
  double get effectiveUpiAmount => _localUpiAmount ?? _summary?.upiAmount ?? 0;
  double get effectiveExpenseAmount => _localExpenseAmount ?? _summary?.expenseAmount ?? 0;
  bool _isLoading = false;
  String? _errorMessage;
  String? _selectedShopId;

  // Manager/Admin metrics state
  DashboardMetrics? _metrics;
  bool _isMetricsLoading = false;
  String? _metricsError;
  DateFilterOption _dateFilter = DateFilterOption.yesterday;
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Getters - Original
  DashboardSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get selectedShopId => _selectedShopId;

  // Getters - Metrics
  DashboardMetrics? get metrics => _metrics;
  bool get isMetricsLoading => _isMetricsLoading;
  String? get metricsError => _metricsError;
  DateFilterOption get dateFilter => _dateFilter;
  DateTime? get customStartDate => _customStartDate;
  DateTime? get customEndDate => _customEndDate;

  /// Load dashboard summary — single API call for all dashboard data.
  /// Both the 4 summary cards and the detail sections (payment breakdown,
  /// team status, alerts, recent activity) are populated from one response.
  Future<void> loadDashboard() async {
    _isLoading = true;
    _isMetricsLoading = true;
    _errorMessage = null;
    _metricsError = null;
    notifyListeners();

    try {
      final response = await _dashboardService.getDashboardSummary(
        dateFilter: _dateFilter.value,
        shopId: _selectedShopId,
        startDate: _dateFilter == DateFilterOption.custom ? _customStartDate : null,
        endDate: _dateFilter == DateFilterOption.custom ? _customEndDate : null,
      );

      if (response.success && response.data != null) {
        _summary = response.data;
        _errorMessage = null;
        _metricsError = null;
        // Clear local overrides and breakdowns — will be populated from day-closing fetch
        _localCashTotal = null;
        _localUpiAmount = null;
        _localExpenseAmount = null;
        _lastCashDenominations = null;
        _lastUpiBreakdown = null;
        _lastExpenses = null;
        debugPrint('[Dashboard] Loaded: '
            'filter=$_dateFilter, '
            'totalRevenue=${_summary!.totalRevenue}, '
            'purchaseAmount=${_summary!.purchaseAmount}, '
            'todaySales.totalAmount=${_summary!.todaysSales.totalAmount}, '
            'todaySales.totalSales=${_summary!.todaysSales.totalSales}, '
            'shops=${_summary!.shopSummaries.length}, '
            'shopFilter=$_selectedShopId');
        // Load day-closing data for this date (UPI, Cash, Expenses)
        _loadDayClosingData();
      } else {
        final msg = response.message ?? 'Failed to load dashboard';
        _errorMessage = msg;
        _metricsError = msg;
        _summary = null;
      }
    } catch (e) {
      final msg = 'Error loading dashboard: $e';
      _errorMessage = msg;
      _metricsError = msg;
      _summary = null;
    } finally {
      _isLoading = false;
      _isMetricsLoading = false;
      notifyListeners();
    }
  }

  /// Refresh dashboard
  Future<void> refreshDashboard() async {
    return loadDashboard();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ========== Manager/Admin Metrics Methods ==========

  /// Load metrics — delegates to loadDashboard (same API endpoint).
  /// The summary data provides all metrics needed for the 4 cards.
  Future<void> loadMetrics({String? shopId}) async {
    if (shopId != null) {
      _selectedShopId = shopId;
    }
    return loadDashboard();
  }

  /// Set date filter and reload dashboard
  void setDateFilter(DateFilterOption filter) {
    final changed = _dateFilter != filter;
    _dateFilter = filter;
    // Clear custom dates when switching away from custom
    if (filter != DateFilterOption.custom) {
      _customStartDate = null;
      _customEndDate = null;
    }
    notifyListeners();
    // Always reload — user may be returning from a custom single-day pick
    if (changed || filter != DateFilterOption.custom) {
      loadDashboard();
    }
  }

  /// Set custom date range and reload dashboard
  void setCustomDateRange(DateTime start, DateTime end) {
    _customStartDate = start;
    _customEndDate = end;
    _dateFilter = DateFilterOption.custom;
    notifyListeners();
    loadDashboard();
  }

  /// Set selected shop filter and reload dashboard
  void setSelectedShop(String? shopId) {
    if (_selectedShopId != shopId) {
      _selectedShopId = shopId;
      notifyListeners();
      loadDashboard();
    }
  }

  /// Refresh metrics
  Future<void> refreshMetrics() async {
    return loadMetrics();
  }

  /// Clear metrics error
  void clearMetricsError() {
    _metricsError = null;
    notifyListeners();
  }

  /// Get display label for current date filter
  String get dateFilterLabel {
    switch (_dateFilter) {
      case DateFilterOption.today:
        return 'Today';
      case DateFilterOption.yesterday:
        return 'Yesterday';
      case DateFilterOption.last7Days:
        return 'Last 7 Days';
      case DateFilterOption.last30Days:
        return 'Last 30 Days';
      case DateFilterOption.thisMonth:
        return 'This Month';
      case DateFilterOption.custom:
        if (_customStartDate != null && _customEndDate != null) {
          return '${_formatDate(_customStartDate!)} - ${_formatDate(_customEndDate!)}';
        }
        return 'Custom';
    }
  }

  /// Get the date corresponding to the active filter (for day-closing saves)
  DateTime _getSelectedDate() {
    switch (_dateFilter) {
      case DateFilterOption.today:
        return DateTime.now();
      case DateFilterOption.yesterday:
        return DateTime.now().subtract(const Duration(days: 1));
      case DateFilterOption.custom:
        return _customStartDate ?? DateTime.now();
      default:
        // For ranges (last7, last30, thisMonth), default to today
        return DateTime.now();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // ========== Day Closing Methods ==========

  /// Update cash amount locally and save to backend
  void updateCashAmount(Map<int, int> denominations, double total) {
    _localCashTotal = total;
    _lastCashDenominations = denominations;
    notifyListeners();
    _saveDayClosingToBackend(cashDenominations: denominations, cashTotal: total);
  }

  /// Update UPI amount locally and save to backend
  void updateUpiAmount(Map<String, double> breakdown, double total) {
    _localUpiAmount = total;
    _lastUpiBreakdown = breakdown;
    notifyListeners();
    _saveDayClosingToBackend(upiBreakdown: breakdown, upiTotal: total);
  }

  /// Update expense amount locally and save to backend
  void updateExpenseAmount(Map<String, double> expenses, double total) {
    _localExpenseAmount = total;
    _lastExpenses = expenses;
    notifyListeners();
    _saveDayClosingToBackend(expenses: expenses, expenseTotal: total);
  }

  /// Save day-closing data to backend, then refresh dashboard.
  /// Always sends ALL breakdowns to prevent the backend from overwriting
  /// previously saved sections with empty data.
  Future<void> _saveDayClosingToBackend({
    Map<int, int>? cashDenominations,
    double? cashTotal,
    Map<String, double>? upiBreakdown,
    double? upiTotal,
    Map<String, double>? expenses,
    double? expenseTotal,
  }) async {
    if (_dayClosingService == null || _selectedShopId == null) return;
    try {
      final targetDate = _getSelectedDate();
      final date = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      // Merge: use new values if provided, otherwise use last saved values
      final effectiveCashDenom = cashDenominations ?? _lastCashDenominations;
      final effectiveCashTotal = cashTotal ?? _localCashTotal;
      final effectiveUpi = upiBreakdown ?? _lastUpiBreakdown;
      final effectiveUpiTotal = upiTotal ?? _localUpiAmount;
      final effectiveExpenses = expenses ?? _lastExpenses;
      final effectiveExpenseTotal = expenseTotal ?? _localExpenseAmount;

      final response = await _dayClosingService!.saveDayClosing(
        shopId: _selectedShopId!,
        date: date,
        cashDenominations: effectiveCashDenom,
        cashTotal: effectiveCashTotal,
        upiBreakdown: effectiveUpi,
        upiTotal: effectiveUpiTotal,
        expenses: effectiveExpenses,
        expenseTotal: effectiveExpenseTotal,
      );
      debugPrint('[DayClosing] Saved: success=${response.success}');
      // Refresh dashboard to get backend-calculated values
      await loadDashboard();
    } catch (e) {
      debugPrint('[DayClosing] Save failed: $e');
    }
  }

  /// Load existing day-closing data for the active date
  /// Populates UPI, Cash, Expenses from backend so they persist across app reopens
  Future<void> _loadDayClosingData() async {
    if (_dayClosingService == null || _selectedShopId == null) return;
    // Only load for single-day filters (today/yesterday/custom single day)
    if (_dateFilter != DateFilterOption.today &&
        _dateFilter != DateFilterOption.yesterday &&
        _dateFilter != DateFilterOption.custom) return;

    try {
      final targetDate = _getSelectedDate();
      final date = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      final response = await _dayClosingService!.getDayClosing(
        shopId: _selectedShopId!,
        date: date,
      );

      if (response.success && response.data != null) {
        final data = response.data!;
        final cashTotal = (data['cash_total'] ?? 0).toDouble();
        final upiTotal = (data['upi_total'] ?? 0).toDouble();
        final expenseTotal = (data['expense_total'] ?? 0).toDouble();

        // Restore breakdown data so sheets show previously entered values
        final upiBreakdown = data['upi_breakdown'];
        if (upiBreakdown != null && upiBreakdown is Map && upiBreakdown.isNotEmpty) {
          _lastUpiBreakdown = Map<String, double>.from(
            upiBreakdown.map((k, v) => MapEntry(k.toString(), (v ?? 0).toDouble())),
          );
          // Recompute UPI total from breakdown (more reliable than upi_total field)
          final breakdownSum = _lastUpiBreakdown!.values.fold(0.0, (s, v) => s + v);
          if (breakdownSum > 0) _localUpiAmount = breakdownSum;
        } else if (upiTotal > 0) {
          _localUpiAmount = upiTotal;
        }

        final cashDenoms = data['cash_denominations'];
        if (cashDenoms != null && cashDenoms is Map && cashDenoms.isNotEmpty) {
          _lastCashDenominations = Map<int, int>.from(
            cashDenoms.map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, v is int ? v : (v ?? 0).toInt())),
          );
          // Recompute cash total from denominations
          final denomSum = _lastCashDenominations!.entries.fold(0.0, (s, e) => s + e.key * e.value);
          if (denomSum > 0) _localCashTotal = denomSum;
        } else if (cashTotal > 0) {
          _localCashTotal = cashTotal;
        }

        final expenses = data['expenses'];
        if (expenses != null && expenses is Map && expenses.isNotEmpty) {
          _lastExpenses = Map<String, double>.from(
            expenses.map((k, v) => MapEntry(k.toString(), (v ?? 0).toDouble())),
          );
          // Recompute expense total from breakdown
          final expSum = _lastExpenses!.values.fold(0.0, (s, v) => s + v);
          if (expSum > 0) _localExpenseAmount = expSum;
        } else if (expenseTotal > 0) {
          _localExpenseAmount = expenseTotal;
        }

        debugPrint('[DayClosing] Loaded for $date: cash=$cashTotal, upi=$upiTotal, expense=$expenseTotal');
        debugPrint('[DayClosing] Breakdowns: upi_breakdown=${data['upi_breakdown']}, cash_denominations=${data['cash_denominations']}, expenses=${data['expenses']}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[DayClosing] Load failed: $e');
    }
  }

  /// Reset provider state (called on logout)
  /// Clears all cached data so new user starts fresh
  void reset() {
    // Reset original summary state
    _summary = null;
    _isLoading = false;
    _errorMessage = null;
    _selectedShopId = null;
    _localCashTotal = null;
    _localUpiAmount = null;
    _localExpenseAmount = null;
    _lastCashDenominations = null;
    _lastUpiBreakdown = null;
    _lastExpenses = null;

    // Reset metrics state
    _metrics = null;
    _isMetricsLoading = false;
    _metricsError = null;
    _dateFilter = DateFilterOption.yesterday;
    _customStartDate = null;
    _customEndDate = null;

    notifyListeners();
    debugPrint('🔄 [DashboardProvider] State reset for logout');
  }
}

import 'package:flutter/foundation.dart';
import '../models/excise_models.dart';
import '../services/excise_api_service.dart';

class ExciseProvider with ChangeNotifier {
  final ExciseApiService _apiService;

  ExciseProvider(this._apiService);

  // ==================== STATE ====================

  // Loading states
  bool _isLoading = false;
  bool _isDashboardLoading = false;
  bool _isLicensesLoading = false;
  bool _isReportsLoading = false;
  bool _isCodesLoading = false;

  // Data
  ComplianceDashboard? _dashboard;
  List<ExciseLicense> _licenses = [];
  List<ExciseDailyReport> _dailyReports = [];
  List<SecurityCode> _securityCodes = [];
  SecurityCodeStats? _codeStats;
  List<ComplianceLog> _complianceLogs = [];

  // Error handling
  String? _error;

  // Selected items
  ExciseLicense? _selectedLicense;
  ExciseDailyReport? _selectedReport;
  String? _selectedShopId;

  // ==================== GETTERS ====================

  bool get isLoading => _isLoading;
  bool get isDashboardLoading => _isDashboardLoading;
  bool get isLicensesLoading => _isLicensesLoading;
  bool get isReportsLoading => _isReportsLoading;
  bool get isCodesLoading => _isCodesLoading;

  ComplianceDashboard? get dashboard => _dashboard;
  List<ExciseLicense> get licenses => _licenses;
  List<ExciseDailyReport> get dailyReports => _dailyReports;
  List<SecurityCode> get securityCodes => _securityCodes;
  SecurityCodeStats? get codeStats => _codeStats;
  List<ComplianceLog> get complianceLogs => _complianceLogs;

  String? get error => _error;

  ExciseLicense? get selectedLicense => _selectedLicense;
  ExciseDailyReport? get selectedReport => _selectedReport;
  String? get selectedShopId => _selectedShopId;

  // Filtered getters
  List<ExciseLicense> get expiringLicenses =>
      _licenses.where((l) => l.isExpiringSoon).toList();

  List<ExciseLicense> get expiredLicenses =>
      _licenses.where((l) => l.isExpired).toList();

  List<ExciseDailyReport> get pendingReports =>
      _dailyReports.where((r) => !r.uploadedToPortal).toList();

  List<SecurityCode> get availableCodes =>
      _securityCodes.where((c) => c.status == SecurityCodeStatus.inStock).toList();

  // ==================== SETTERS ====================

  void setSelectedShop(String? shopId) {
    _selectedShopId = shopId;
    notifyListeners();
    // Reload data for new shop
    loadDashboard();
    loadLicenses();
    loadDailyReports();
  }

  void setSelectedLicense(ExciseLicense? license) {
    _selectedLicense = license;
    notifyListeners();
  }

  void setSelectedReport(ExciseDailyReport? report) {
    _selectedReport = report;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ==================== COMPLIANCE DASHBOARD ====================

  Future<void> loadDashboard() async {
    _isDashboardLoading = true;
    _error = null;
    notifyListeners();

    try {
      _dashboard = await _apiService.getComplianceDashboard(shopId: _selectedShopId);
    } catch (e) {
      _error = 'Failed to load dashboard: ${e.toString()}';
      debugPrint(_error);
    } finally {
      _isDashboardLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadComplianceLogs({DateTime? startDate, DateTime? endDate}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _complianceLogs = await _apiService.getComplianceLogs(
        shopId: _selectedShopId,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _error = 'Failed to load compliance logs: ${e.toString()}';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ==================== LICENSE MANAGEMENT ====================

  Future<void> loadLicenses() async {
    _isLicensesLoading = true;
    _error = null;
    notifyListeners();

    try {
      _licenses = await _apiService.getLicenses();

      // Filter by shop if selected
      if (_selectedShopId != null) {
        _licenses = _licenses.where((l) => l.shopId == _selectedShopId).toList();
      }
    } catch (e) {
      _error = 'Failed to load licenses: ${e.toString()}';
      debugPrint(_error);
    } finally {
      _isLicensesLoading = false;
      notifyListeners();
    }
  }

  Future<ExciseLicense?> createLicense({
    required String shopId,
    required String licenseNumber,
    required LicenseType licenseType,
    required DateTime issueDate,
    required DateTime expiryDate,
    required String issuingAuthority,
    required double monthlyFee,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final license = await _apiService.createLicense(
        shopId: shopId,
        licenseNumber: licenseNumber,
        licenseType: licenseType,
        issueDate: issueDate,
        expiryDate: expiryDate,
        issuingAuthority: issuingAuthority,
        monthlyFee: monthlyFee,
      );

      _licenses.add(license);
      _isLoading = false;
      notifyListeners();
      return license;
    } catch (e) {
      _error = 'Failed to create license: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateLicense({
    required String id,
    String? licenseNumber,
    DateTime? expiryDate,
    String? issuingAuthority,
    double? monthlyFee,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _apiService.updateLicense(
        id: id,
        licenseNumber: licenseNumber,
        expiryDate: expiryDate,
        issuingAuthority: issuingAuthority,
        monthlyFee: monthlyFee,
      );

      final index = _licenses.indexWhere((l) => l.id == id);
      if (index != -1) {
        _licenses[index] = updated;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to update license: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> renewLicense({
    required String id,
    required DateTime newExpiryDate,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final renewed = await _apiService.renewLicense(
        id: id,
        newExpiryDate: newExpiryDate,
      );

      final index = _licenses.indexWhere((l) => l.id == id);
      if (index != -1) {
        _licenses[index] = renewed;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to renew license: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> payLicenseFee({
    required String licenseId,
    required double amount,
    required String paymentMethod,
    required String transactionRef,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.payLicenseFee(
        licenseId: licenseId,
        amount: amount,
        paymentMethod: paymentMethod,
        transactionRef: transactionRef,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to pay license fee: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<List<ExciseLicense>> getExpiringLicenses({int days = 30}) async {
    try {
      return await _apiService.getExpiringLicenses(days: days);
    } catch (e) {
      _error = 'Failed to load expiring licenses: ${e.toString()}';
      debugPrint(_error);
      return [];
    }
  }

  // ==================== DAILY REPORTS ====================

  Future<void> loadDailyReports({DateTime? startDate, DateTime? endDate}) async {
    _isReportsLoading = true;
    _error = null;
    notifyListeners();

    try {
      _dailyReports = await _apiService.getDailyReports(
        shopId: _selectedShopId,
        startDate: startDate,
        endDate: endDate,
      );
    } catch (e) {
      _error = 'Failed to load daily reports: ${e.toString()}';
      debugPrint(_error);
    } finally {
      _isReportsLoading = false;
      notifyListeners();
    }
  }

  /// AUTO-GENERATE DAILY REPORT - ZERO MANUAL ENTRY!
  Future<ExciseDailyReport?> autoGenerateReport({
    required String shopId,
    required DateTime reportDate,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final report = await _apiService.autoGenerateDailyReport(
        shopId: shopId,
        reportDate: reportDate,
      );

      // Add to list if not exists
      final existingIndex = _dailyReports.indexWhere(
        (r) => r.shopId == shopId &&
               r.reportDate.day == reportDate.day &&
               r.reportDate.month == reportDate.month &&
               r.reportDate.year == reportDate.year,
      );

      if (existingIndex != -1) {
        _dailyReports[existingIndex] = report;
      } else {
        _dailyReports.add(report);
      }

      _isLoading = false;
      notifyListeners();
      return report;
    } catch (e) {
      _error = 'Failed to auto-generate report: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<ExciseDailyReport?> getReportByDate({
    required String shopId,
    required DateTime date,
  }) async {
    try {
      return await _apiService.getDailyReportByDate(shopId: shopId, date: date);
    } catch (e) {
      _error = 'Failed to load report: ${e.toString()}';
      debugPrint(_error);
      return null;
    }
  }

  Future<bool> uploadReportToPortal(String reportId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _apiService.uploadReportToPortal(reportId);

      final index = _dailyReports.indexWhere((r) => r.id == reportId);
      if (index != -1) {
        _dailyReports[index] = updated;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to upload report: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> retryReportUpload(String reportId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _apiService.retryReportUpload(reportId);

      final index = _dailyReports.indexWhere((r) => r.id == reportId);
      if (index != -1) {
        _dailyReports[index] = updated;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to retry upload: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // ==================== SECURITY CODES ====================

  Future<void> loadSecurityCodes({
    String? shopId,
    String? productId,
    SecurityCodeStatus? status,
  }) async {
    _isCodesLoading = true;
    _error = null;
    notifyListeners();

    try {
      _securityCodes = await _apiService.searchSecurityCodes(
        shopId: shopId ?? _selectedShopId,
        productId: productId,
        status: status,
      );
    } catch (e) {
      _error = 'Failed to load security codes: ${e.toString()}';
      debugPrint(_error);
    } finally {
      _isCodesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadSecurityCodeStats({String? shopId}) async {
    try {
      _codeStats = await _apiService.getSecurityCodeStats(
        shopId: shopId ?? _selectedShopId,
      );
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load security code stats: ${e.toString()}';
      debugPrint(_error);
    }
  }

  Future<SecurityCode?> validateSecurityCode(String code) async {
    try {
      return await _apiService.validateSecurityCode(code);
    } catch (e) {
      _error = 'Invalid security code: ${e.toString()}';
      debugPrint(_error);
      return null;
    }
  }

  Future<SecurityCode?> getSecurityCode(String code) async {
    try {
      return await _apiService.getSecurityCode(code);
    } catch (e) {
      _error = 'Failed to get security code: ${e.toString()}';
      debugPrint(_error);
      return null;
    }
  }

  Future<bool> bulkAddSecurityCodes({
    required String shopId,
    required String productId,
    required List<String> codes,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.bulkAddSecurityCodes(
        shopId: shopId,
        productId: productId,
        codes: codes,
      );

      _isLoading = false;
      notifyListeners();

      // Reload codes
      await loadSecurityCodes();

      return true;
    } catch (e) {
      _error = 'Failed to add security codes: ${e.toString()}';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> markCodesAsSold({
    required List<String> codes,
    required String saleId,
  }) async {
    try {
      await _apiService.markSecurityCodesAsSold(codes: codes, saleId: saleId);

      // Update local state
      for (final code in codes) {
        final index = _securityCodes.indexWhere((c) => c.code == code);
        if (index != -1) {
          // Create updated code (would need to update SecurityCode model to be mutable or use copyWith)
          // For now, just reload
          await loadSecurityCodes();
          break;
        }
      }

      return true;
    } catch (e) {
      _error = 'Failed to mark codes as sold: ${e.toString()}';
      debugPrint(_error);
      return false;
    }
  }

  Future<bool> markCodesAsDamaged({
    required List<String> codes,
    required String reason,
  }) async {
    try {
      await _apiService.markSecurityCodesAsDamaged(codes: codes, reason: reason);

      // Reload codes
      await loadSecurityCodes();

      return true;
    } catch (e) {
      _error = 'Failed to mark codes as damaged: ${e.toString()}';
      debugPrint(_error);
      return false;
    }
  }

  // ==================== UTILITY METHODS ====================

  Future<void> refreshAll() async {
    await Future.wait([
      loadDashboard(),
      loadLicenses(),
      loadDailyReports(),
      loadSecurityCodeStats(),
    ]);
  }

  void reset() {
    _dashboard = null;
    _licenses = [];
    _dailyReports = [];
    _securityCodes = [];
    _codeStats = null;
    _complianceLogs = [];
    _error = null;
    _selectedLicense = null;
    _selectedReport = null;
    _selectedShopId = null;
    notifyListeners();
  }
}

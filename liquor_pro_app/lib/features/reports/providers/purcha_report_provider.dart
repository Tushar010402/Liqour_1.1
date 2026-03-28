import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/purcha_report_models.dart';
import '../services/purcha_report_service.dart';

/// Purcha Report Provider
/// Manages state for Purcha Report preview and PDF operations
class PurchaReportProvider with ChangeNotifier {
  final PurchaReportService _service;

  PurchaReportProvider(this._service);

  // ==================== STATE ====================

  // Loading states
  bool _isLoading = false;
  bool _isPdfDownloading = false;
  bool _isPdfSharing = false;

  // Data
  PurchaReport? _report;
  File? _downloadedPdf;
  Uint8List? _pdfBytes;

  // Filters
  String? _selectedShopId;
  DateTime _selectedDate = DateTime.now();
  PurchaViewMode _viewMode = PurchaViewMode.flat;
  PurchaCategoryFilter _categoryFilter = PurchaCategoryFilter.nonBeer;
  bool _showOpening = true;
  String? _selectedSize; // For page navigation

  // Error handling
  String? _error;

  // ==================== GETTERS ====================

  bool get isLoading => _isLoading;
  bool get isPdfDownloading => _isPdfDownloading;
  bool get isPdfSharing => _isPdfSharing;
  bool get hasData => _report?.hasData ?? false;

  PurchaReport? get report => _report;
  File? get downloadedPdf => _downloadedPdf;
  Uint8List? get pdfBytes => _pdfBytes;

  String? get selectedShopId => _selectedShopId;
  DateTime get selectedDate => _selectedDate;
  PurchaViewMode get viewMode => _viewMode;
  PurchaCategoryFilter get categoryFilter => _categoryFilter;
  bool get showOpening => _showOpening;
  String? get selectedSize => _selectedSize;

  String? get error => _error;

  // Computed getters
  List<String> get availableSizes => _report?.availableSizes ?? [];

  PurchaReportPage? get currentPage {
    if (_report == null || _report!.pages.isEmpty) return null;
    if (_selectedSize == null) return _report!.pages.first;
    return _report!.pages.firstWhere(
      (p) => p.size == _selectedSize,
      orElse: () => _report!.pages.first,
    );
  }

  int get totalItems => _report?.pages.fold<int>(
        0,
        (sum, page) => sum + page.categories.fold<int>(
          0,
          (catSum, cat) => catSum + cat.items.length,
        ),
      ) ?? 0;

  // ==================== SETTERS ====================

  void setSelectedShop(String? shopId) {
    if (_selectedShopId != shopId) {
      _selectedShopId = shopId;
      _report = null; // Clear old data
      notifyListeners();
    }
  }

  void setSelectedDate(DateTime date) {
    if (_selectedDate != date) {
      _selectedDate = date;
      notifyListeners();
    }
  }

  void setViewMode(PurchaViewMode mode) {
    if (_viewMode != mode) {
      _viewMode = mode;
      notifyListeners();
    }
  }

  void setCategoryFilter(PurchaCategoryFilter filter) {
    if (_categoryFilter != filter) {
      _categoryFilter = filter;
      notifyListeners();
    }
  }

  void setShowOpening(bool show) {
    if (_showOpening != show) {
      _showOpening = show;
      notifyListeners();
    }
  }

  void setSelectedSize(String? size) {
    if (_selectedSize != size) {
      _selectedSize = size;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _report = null;
    _downloadedPdf = null;
    _pdfBytes = null;
    _error = null;
    _selectedSize = null;
    notifyListeners();
  }

  // ==================== REPORT LOADING ====================

  /// Load report preview with current filters
  /// Note: Always fetches with showOpening=true to get all data.
  /// The showOpening toggle only controls UI visibility, not data fetching.
  Future<bool> loadReport() async {
    if (_selectedShopId == null) {
      _error = 'Please select a shop first';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final report = await _service.getReportPreview(
        shopId: _selectedShopId!,
        date: _selectedDate,
        viewMode: _viewMode,
        categoryFilter: _categoryFilter,
        showOpening: true, // Always fetch opening data - toggle controls UI display only
      );

      if (report != null) {
        _report = report;
        // Auto-select first size if not set
        if (_selectedSize == null && report.pages.isNotEmpty) {
          _selectedSize = report.pages.first.size;
        }
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = 'Failed to load report';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Error loading report: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Reload report with updated filters
  Future<bool> refreshReport() async {
    _report = null;
    _downloadedPdf = null;
    _pdfBytes = null;
    return loadReport();
  }

  // ==================== PDF OPERATIONS ====================

  /// Download PDF and save to file
  /// Uses current showOpening setting for PDF generation
  Future<File?> downloadPdf({String? customFileName}) async {
    if (_selectedShopId == null) {
      _error = 'Please select a shop first';
      notifyListeners();
      return null;
    }

    _isPdfDownloading = true;
    _error = null;
    notifyListeners();

    try {
      final file = await _service.downloadPdf(
        shopId: _selectedShopId!,
        date: _selectedDate,
        viewMode: _viewMode,
        categoryFilter: _categoryFilter,
        showOpening: _showOpening, // PDF respects the toggle setting
        customFileName: customFileName,
      );

      _downloadedPdf = file;
      _isPdfDownloading = false;
      notifyListeners();
      return file;
    } catch (e) {
      _error = 'Error downloading PDF: $e';
      _isPdfDownloading = false;
      notifyListeners();
      return null;
    }
  }

  /// Get PDF bytes for sharing/printing
  Future<Uint8List?> getPdfForSharing() async {
    if (_selectedShopId == null) {
      _error = 'Please select a shop first';
      notifyListeners();
      return null;
    }

    _isPdfSharing = true;
    _error = null;
    notifyListeners();

    try {
      final bytes = await _service.getPdfBytes(
        shopId: _selectedShopId!,
        date: _selectedDate,
        viewMode: _viewMode,
        categoryFilter: _categoryFilter,
        showOpening: _showOpening,
      );

      _pdfBytes = bytes;
      _isPdfSharing = false;
      notifyListeners();
      return bytes;
    } catch (e) {
      _error = 'Error preparing PDF: $e';
      _isPdfSharing = false;
      notifyListeners();
      return null;
    }
  }

  // ==================== HELPER METHODS ====================

  /// Get category filter display name
  String get categoryFilterDisplayName => _categoryFilter.displayName;

  /// Get view mode display name
  String get viewModeDisplayName {
    switch (_viewMode) {
      case PurchaViewMode.category:
        return 'By Category';
      case PurchaViewMode.flat:
        return 'Flat List';
    }
  }

  /// Format amount with currency symbol
  String formatAmount(double amount) {
    if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amount.toStringAsFixed(0)}';
  }

  /// Get summary stats for current page
  Map<String, dynamic> get currentPageStats {
    final page = currentPage;
    if (page == null) {
      return {
        'opening': 0,
        'receipt': 0,
        'total': 0,
        'sale': 0,
        'amount': 0.0,
        'closing': 0,
      };
    }
    return {
      'opening': page.grandOpening,
      'receipt': page.grandReceipt,
      'total': page.grandTotal,
      'sale': page.grandSale,
      'amount': page.grandAmount,
      'closing': page.grandClosing,
    };
  }

  /// Get grand totals across all pages
  Map<String, dynamic> get grandTotals {
    if (_report == null) {
      return {
        'opening': 0,
        'receipt': 0,
        'total': 0,
        'sale': 0,
        'amount': 0.0,
        'closing': 0,
      };
    }
    return {
      'opening': _report!.totalOpening,
      'receipt': _report!.totalReceipt,
      'total': _report!.totalTotal,
      'sale': _report!.totalSale,
      'amount': _report!.totalAmount,
      'closing': _report!.totalClosing,
    };
  }
}

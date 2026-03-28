import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/dio_api_service.dart';
import '../models/purcha_report_models.dart';

/// Purcha Report Service
/// Handles API calls for Purcha Report preview and PDF generation
///
/// API Endpoints:
/// - GET /api/reports/purcha/preview - JSON preview data
/// - GET /api/reports/purcha/pdf - PDF download
class PurchaReportService {
  final DioApiService _apiService;

  PurchaReportService(this._apiService);

  /// Fetch Purcha Report preview data (JSON)
  Future<PurchaReport?> getReportPreview({
    required String shopId,
    DateTime? date,
    PurchaViewMode viewMode = PurchaViewMode.category,
    PurchaCategoryFilter categoryFilter = PurchaCategoryFilter.nonBeer,
    bool showOpening = true,
  }) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());

      final queryParams = {
        'shop_id': shopId,
        'date': dateStr,
        'view_mode': viewMode.toApiString(),
        'category_filter': categoryFilter.toApiString(),
        'show_opening': showOpening.toString(),
      };

      if (kDebugMode) {
        print('📊 [PurchaReport] Fetching preview: $queryParams');
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        '/api/reports/purcha/preview',
        queryParams: queryParams,
        fromJson: (json) => json as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final report = PurchaReport.fromJson(response.data!);
        if (kDebugMode) {
          print('✅ [PurchaReport] Loaded: ${report.pages.length} pages, ${report.totalSale} total sale');
        }
        return report;
      } else {
        if (kDebugMode) {
          print('❌ [PurchaReport] Failed: ${response.message}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [PurchaReport] Error: $e');
      }
      return null;
    }
  }

  /// Download PDF report and save to file
  Future<File?> downloadPdf({
    required String shopId,
    DateTime? date,
    PurchaViewMode viewMode = PurchaViewMode.category,
    PurchaCategoryFilter categoryFilter = PurchaCategoryFilter.nonBeer,
    bool showOpening = true,
    String? customFileName,
  }) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date ?? DateTime.now());

      final queryParams = {
        'shop_id': shopId,
        'date': dateStr,
        'view_mode': viewMode.toApiString(),
        'category_filter': categoryFilter.toApiString(),
        'show_opening': showOpening.toString(),
      };

      if (kDebugMode) {
        print('📥 [PurchaReport] Downloading PDF: $queryParams');
      }

      // Build query string manually
      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final directory = await getApplicationDocumentsDirectory();
      final fileName = customFileName ??
          'purcha_report_${shopId.substring(0, 8)}_$dateStr.pdf';
      final savePath = '${directory.path}/$fileName';

      final response = await _apiService.downloadFile(
        '/api/reports/purcha/pdf?$queryString',
        savePath,
      );

      if (response.success && response.data != null) {
        if (kDebugMode) {
          print('✅ [PurchaReport] PDF saved: ${response.data}');
        }
        return File(response.data!);
      } else {
        if (kDebugMode) {
          print('❌ [PurchaReport] PDF download failed: ${response.message}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [PurchaReport] PDF download error: $e');
      }
      return null;
    }
  }

  /// Get PDF bytes directly (for sharing/printing without saving)
  Future<Uint8List?> getPdfBytes({
    required String shopId,
    DateTime? date,
    PurchaViewMode viewMode = PurchaViewMode.category,
    PurchaCategoryFilter categoryFilter = PurchaCategoryFilter.nonBeer,
    bool showOpening = true,
  }) async {
    try {
      // Download to temp file first, then read bytes
      final tempFile = await downloadPdf(
        shopId: shopId,
        date: date,
        viewMode: viewMode,
        categoryFilter: categoryFilter,
        showOpening: showOpening,
        customFileName: 'temp_purcha_report.pdf',
      );

      if (tempFile != null && await tempFile.exists()) {
        final bytes = await tempFile.readAsBytes();
        // Clean up temp file
        await tempFile.delete();
        return bytes;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ [PurchaReport] Get PDF bytes error: $e');
      }
      return null;
    }
  }
}

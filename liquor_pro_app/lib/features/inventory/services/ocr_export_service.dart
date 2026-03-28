import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../../../core/models/deduplicated_item.dart';

/// OCR Export Service
///
/// PHASE 5.3: Export Functionality
/// Export OCR review results to CSV and PDF formats
///
/// FEATURES:
/// - CSV export with all item details
/// - PDF export with formatted tables
/// - Filtering by acceptance status
/// - Metadata (timestamp, totals, shop info)
/// - Share functionality
/// - Professional formatting
///
/// USAGE:
/// ```dart
/// final exportService = OCRExportService();
///
/// // Export to CSV
/// await exportService.exportToCSV(
///   items: deduplicatedItems,
///   acceptedIds: acceptedIds,
///   rejectedIds: rejectedIds,
///   shopId: shopId,
/// );
///
/// // Export to PDF
/// await exportService.exportToPDF(
///   items: deduplicatedItems,
///   acceptedIds: acceptedIds,
///   rejectedIds: rejectedIds,
///   shopId: shopId,
/// );
/// ```

enum ExportFilter {
  all,
  acceptedOnly,
  rejectedOnly,
  pendingOnly,
}

class OCRExportService {
  // ==========================================
  // CSV EXPORT
  // ==========================================

  /// Export OCR results to CSV format
  Future<File?> exportToCSV({
    required List<DeduplicatedItem> items,
    required Set<String> acceptedIds,
    required Set<String> rejectedIds,
    String? shopId,
    ExportFilter filter = ExportFilter.all,
  }) async {
    try {
      // Filter items based on selection
      final filteredItems = _filterItems(items, acceptedIds, rejectedIds, filter);

      if (filteredItems.isEmpty) {
        if (kDebugMode) {
          print('⚠️  No items to export with filter: $filter');
        }
        return null;
      }

      // Generate CSV data
      final csvData = _generateCSVData(filteredItems, acceptedIds, rejectedIds);

      // Convert to CSV string
      const converter = ListToCsvConverter();
      final csvString = converter.convert(csvData);

      // Save to file
      final file = await _saveToFile(
        content: csvString,
        filename: _generateFilename('ocr_export', 'csv', shopId),
      );

      if (kDebugMode) {
        print('✅ CSV exported: ${file.path}');
      }

      return file;
    } catch (e) {
      if (kDebugMode) {
        print('❌ CSV export failed: $e');
      }
      return null;
    }
  }

  /// Share CSV export
  Future<bool> shareCSV({
    required List<DeduplicatedItem> items,
    required Set<String> acceptedIds,
    required Set<String> rejectedIds,
    String? shopId,
    ExportFilter filter = ExportFilter.all,
  }) async {
    try {
      final file = await exportToCSV(
        items: items,
        acceptedIds: acceptedIds,
        rejectedIds: rejectedIds,
        shopId: shopId,
        filter: filter,
      );

      if (file == null) return false;

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'OCR Review Results',
        text: 'OCR review results exported on ${_formatDate(DateTime.now())}',
      );

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ CSV share failed: $e');
      }
      return false;
    }
  }

  // ==========================================
  // PDF EXPORT
  // ==========================================

  /// Export OCR results to PDF format
  Future<File?> exportToPDF({
    required List<DeduplicatedItem> items,
    required Set<String> acceptedIds,
    required Set<String> rejectedIds,
    String? shopId,
    ExportFilter filter = ExportFilter.all,
  }) async {
    try {
      // Filter items
      final filteredItems = _filterItems(items, acceptedIds, rejectedIds, filter);

      if (filteredItems.isEmpty) {
        if (kDebugMode) {
          print('⚠️  No items to export with filter: $filter');
        }
        return null;
      }

      // Generate PDF document
      final pdf = await _generatePDF(
        items: filteredItems,
        acceptedIds: acceptedIds,
        rejectedIds: rejectedIds,
        shopId: shopId,
        filter: filter,
      );

      // Save to file
      final file = await _savePDFToFile(
        pdf: pdf,
        filename: _generateFilename('ocr_export', 'pdf', shopId),
      );

      if (kDebugMode) {
        print('✅ PDF exported: ${file.path}');
      }

      return file;
    } catch (e) {
      if (kDebugMode) {
        print('❌ PDF export failed: $e');
      }
      return null;
    }
  }

  /// Share PDF export
  Future<bool> sharePDF({
    required List<DeduplicatedItem> items,
    required Set<String> acceptedIds,
    required Set<String> rejectedIds,
    String? shopId,
    ExportFilter filter = ExportFilter.all,
  }) async {
    try {
      final file = await exportToPDF(
        items: items,
        acceptedIds: acceptedIds,
        rejectedIds: rejectedIds,
        shopId: shopId,
        filter: filter,
      );

      if (file == null) return false;

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'OCR Review Results',
        text: 'OCR review results exported on ${_formatDate(DateTime.now())}',
      );

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ PDF share failed: $e');
      }
      return false;
    }
  }

  // ==========================================
  // CSV GENERATION
  // ==========================================

  List<List<dynamic>> _generateCSVData(
    List<DeduplicatedItem> items,
    Set<String> acceptedIds,
    Set<String> rejectedIds,
  ) {
    final data = <List<dynamic>>[];

    // Header row
    data.add([
      'Brand Name',
      'Category',
      'Subcategory',
      'Size',
      'MRP',
      'Status',
      'Confidence',
      'Match Type',
      'Source',
      'Timestamp',
    ]);

    // Data rows
    for (final item in items) {
      final status = _getItemStatus(item.id!, acceptedIds, rejectedIds);
      data.add([
        item.brandName ?? '',
        item.inferredCategory ?? '',
        item.inferredSubcategory ?? '',
        item.inferredSize ?? '',
        item.inferredMrp?.toString() ?? '',
        status,
        '${((item.confidence ?? 0.0) * 100).toStringAsFixed(0)}%',
        item.matchedSaaSBrandId != null ? 'Found in DB' : 'New Brand',
        'OCR',
        _formatDate(DateTime.now()),
      ]);
    }

    return data;
  }

  // ==========================================
  // PDF GENERATION
  // ==========================================

  Future<pw.Document> _generatePDF({
    required List<DeduplicatedItem> items,
    required Set<String> acceptedIds,
    required Set<String> rejectedIds,
    String? shopId,
    required ExportFilter filter,
  }) async {
    final pdf = pw.Document();

    // Calculate statistics
    final stats = _calculateStatistics(items, acceptedIds, rejectedIds);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // Header
          _buildPDFHeader(),
          pw.SizedBox(height: 20),

          // Metadata
          _buildPDFMetadata(shopId, filter, stats),
          pw.SizedBox(height: 20),

          // Statistics Summary
          _buildPDFStatistics(stats),
          pw.SizedBox(height: 20),

          // Items Table
          _buildPDFTable(items, acceptedIds, rejectedIds),
        ],
      ),
    );

    return pdf;
  }

  pw.Widget _buildPDFHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'OCR Review Export',
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated on ${_formatDate(DateTime.now())}',
          style: const pw.TextStyle(
            fontSize: 12,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPDFMetadata(
    String? shopId,
    ExportFilter filter,
    Map<String, int> stats,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (shopId != null)
            pw.Text('Shop ID: $shopId', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            'Filter: ${_getFilterDisplayName(filter)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            'Total Items: ${stats['total']}',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPDFStatistics(Map<String, int> stats) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('Accepted', stats['accepted']!, PdfColors.green),
          _buildStatColumn('Rejected', stats['rejected']!, PdfColors.red),
          _buildStatColumn('Pending', stats['pending']!, PdfColors.orange),
        ],
      ),
    );
  }

  pw.Widget _buildStatColumn(String label, int value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value.toString(),
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildPDFTable(
    List<DeduplicatedItem> items,
    Set<String> acceptedIds,
    Set<String> rejectedIds,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FlexColumnWidth(2.5), // Brand Name
        1: const pw.FlexColumnWidth(1.5), // Category
        2: const pw.FlexColumnWidth(1), // Size
        3: const pw.FlexColumnWidth(1), // MRP
        4: const pw.FlexColumnWidth(1), // Status
        5: const pw.FlexColumnWidth(1), // Confidence
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildTableCell('Brand Name', isHeader: true),
            _buildTableCell('Category', isHeader: true),
            _buildTableCell('Size', isHeader: true),
            _buildTableCell('MRP', isHeader: true),
            _buildTableCell('Status', isHeader: true),
            _buildTableCell('Conf.', isHeader: true),
          ],
        ),
        // Data rows
        ...items.map((item) {
          final status = _getItemStatus(item.id!, acceptedIds, rejectedIds);
          return pw.TableRow(
            children: [
              _buildTableCell(item.brandName ?? '—'),
              _buildTableCell(item.inferredCategory ?? '—'),
              _buildTableCell(item.inferredSize ?? '—'),
              _buildTableCell(
                item.inferredMrp != null ? '₹${item.inferredMrp}' : '—',
              ),
              _buildTableCell(status),
              _buildTableCell(
                '${((item.confidence ?? 0.0) * 100).toStringAsFixed(0)}%',
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================

  List<DeduplicatedItem> _filterItems(
    List<DeduplicatedItem> items,
    Set<String> acceptedIds,
    Set<String> rejectedIds,
    ExportFilter filter,
  ) {
    switch (filter) {
      case ExportFilter.all:
        return items;
      case ExportFilter.acceptedOnly:
        return items.where((item) => acceptedIds.contains(item.id)).toList();
      case ExportFilter.rejectedOnly:
        return items.where((item) => rejectedIds.contains(item.id)).toList();
      case ExportFilter.pendingOnly:
        return items
            .where((item) =>
                !acceptedIds.contains(item.id) &&
                !rejectedIds.contains(item.id))
            .toList();
    }
  }

  String _getItemStatus(
    String itemId,
    Set<String> acceptedIds,
    Set<String> rejectedIds,
  ) {
    if (acceptedIds.contains(itemId)) return 'Accepted';
    if (rejectedIds.contains(itemId)) return 'Rejected';
    return 'Pending';
  }

  Map<String, int> _calculateStatistics(
    List<DeduplicatedItem> items,
    Set<String> acceptedIds,
    Set<String> rejectedIds,
  ) {
    return {
      'total': items.length,
      'accepted': items.where((item) => acceptedIds.contains(item.id)).length,
      'rejected': items.where((item) => rejectedIds.contains(item.id)).length,
      'pending': items
          .where((item) =>
              !acceptedIds.contains(item.id) && !rejectedIds.contains(item.id))
          .length,
    };
  }

  String _generateFilename(String prefix, String extension, String? shopId) {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final shopSuffix = shopId != null ? '_shop_$shopId' : '';
    return '$prefix${shopSuffix}_$timestamp.$extension';
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy HH:mm').format(date);
  }

  String _getFilterDisplayName(ExportFilter filter) {
    switch (filter) {
      case ExportFilter.all:
        return 'All Items';
      case ExportFilter.acceptedOnly:
        return 'Accepted Only';
      case ExportFilter.rejectedOnly:
        return 'Rejected Only';
      case ExportFilter.pendingOnly:
        return 'Pending Only';
    }
  }

  Future<File> _saveToFile({
    required String content,
    required String filename,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    await file.writeAsString(content);
    return file;
  }

  Future<File> _savePDFToFile({
    required pw.Document pdf,
    required String filename,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$filename');
    final bytes = await pdf.save();
    await file.writeAsBytes(bytes);
    return file;
  }
}

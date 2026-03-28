import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/purcha_report_models.dart';

/// PDF Generator for Purcha Report
/// Generates PDF exactly matching the reference format:
/// - SALE RECEIPT - {SIZE} title
/// - Shop name | ओपन रसी टोटल | Date fields
/// - Table with: S.No | Brand Name | Opening | Receipt | Total | Sale | Rate | Amount | Closing
/// - Empty rows shown with serial numbers
/// - GRAND TOTAL row at bottom
///
/// When showOpening is false:
/// - ALWAYS shows all 9 columns with headers visible
/// - Opening, Total, and Closing VALUES are shown as empty (blank)
/// - This ensures consistent layout regardless of toggle state
class PurchaPdfGenerator {
  // Column widths for FULL view (with Opening)
  static const double _colSNo = 30;
  static const double _colBrandName = 200;
  static const double _colOpening = 45;
  static const double _colReceipt = 45;
  static const double _colTotal = 40;
  static const double _colSale = 40;
  static const double _colRate = 45;
  static const double _colAmount = 55;
  static const double _colClosing = 45;

  // NOTE: Compact view constants removed - we ALWAYS show all 9 columns now
  // Opening, Total, Closing show empty values when showOpening is false

  // Font sizes
  static const double _titleFontSize = 16;
  static const double _headerFontSize = 10;
  static const double _cellFontSize = 10;
  static const double _brandNameFontSize = 10;

  // Row heights
  static const double _headerRowHeight = 22;
  static const double _dataRowHeight = 20;
  static const double _multiLineRowHeight = 32;

  /// Generate PDF document from report data
  /// When showOpening is false, hides Opening, Total, and Closing columns
  static Future<pw.Document> generatePdf(PurchaReport report, {bool showOpening = true}) async {
    final pdf = pw.Document();

    // Load font (use default Helvetica for clean look)
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    // Debug: Show how many pages will be generated
    debugPrint('📄 [PurchaPDF] Generating PDF for ${report.pages.length} sizes (showOpening: $showOpening)');
    for (final p in report.pages) {
      final count = _flattenPageItems(p).length;
      debugPrint('   - ${p.size}: $count items');
    }

    // Generate a SEPARATE page for each size
    // Each size gets its own PDF page(s)
    for (final page in report.pages) {
      final items = _flattenPageItems(page);

      // Skip empty pages
      if (items.isEmpty) {
        debugPrint('   ⚠️ Skipping ${page.size} - no items');
        continue;
      }

      debugPrint('   ✅ Adding page for ${page.size} with ${items.length} items');

      final emptyRowsNeeded = _calculateEmptyRows(items.length);

      // Calculate rows per page (approximately 35 rows per A4 page)
      const int rowsPerPage = 35;
      final totalRows = items.length + emptyRowsNeeded + 1; // +1 for grand total

      if (totalRows <= rowsPerPage) {
        // Single page for this size
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Title
                _buildTitle(page.size, fontBold),
                pw.SizedBox(height: 8),
                // Header row (Shop | text | Date)
                _buildHeaderRow(report.shopName, font, fontBold, showOpening),
                pw.SizedBox(height: 12),
                // Table
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                  columnWidths: _getColumnWidths(showOpening),
                  children: [
                    _buildTableHeader(fontBold, showOpening),
                    ...items.asMap().entries.map((entry) =>
                      _buildDataRow(entry.key + 1, entry.value, font, fontBold, showOpening)
                    ),
                    ...List.generate(emptyRowsNeeded, (index) =>
                      _buildEmptyRow(items.length + index + 1, font, showOpening)
                    ),
                    _buildGrandTotalRow(page, font, fontBold, showOpening),
                  ],
                ),
              ],
            ),
          ),
        );
      } else {
        // Multiple pages needed for this size - use MultiPage
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(30),
            header: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildTitle(page.size, fontBold),
                pw.SizedBox(height: 8),
                _buildHeaderRow(report.shopName, font, fontBold, showOpening),
                pw.SizedBox(height: 12),
              ],
            ),
            build: (context) => [
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                columnWidths: _getColumnWidths(showOpening),
                children: [
                  _buildTableHeader(fontBold, showOpening),
                  ...items.asMap().entries.map((entry) =>
                    _buildDataRow(entry.key + 1, entry.value, font, fontBold, showOpening)
                  ),
                  ...List.generate(emptyRowsNeeded, (index) =>
                    _buildEmptyRow(items.length + index + 1, font, showOpening)
                  ),
                  _buildGrandTotalRow(page, font, fontBold, showOpening),
                ],
              ),
            ],
          ),
        );
      }
    }

    return pdf;
  }

  /// Get column widths map - ALWAYS returns 9 columns
  /// showOpening parameter kept for API compatibility but no longer affects column count
  static Map<int, pw.TableColumnWidth> _getColumnWidths(bool showOpening) {
    // ALWAYS show all 9 columns: S.No | Brand | Open | Rcpt | Total | Sale | Rate | Amt | Close
    // When showOpening is false, the values are empty but columns remain visible
    return {
      0: const pw.FixedColumnWidth(_colSNo),
      1: const pw.FixedColumnWidth(_colBrandName),
      2: const pw.FixedColumnWidth(_colOpening),
      3: const pw.FixedColumnWidth(_colReceipt),
      4: const pw.FixedColumnWidth(_colTotal),
      5: const pw.FixedColumnWidth(_colSale),
      6: const pw.FixedColumnWidth(_colRate),
      7: const pw.FixedColumnWidth(_colAmount),
      8: const pw.FixedColumnWidth(_colClosing),
    };
  }

  /// Build title: "SALE RECEIPT - {SIZE}"
  static pw.Widget _buildTitle(String size, pw.Font fontBold) {
    return pw.Center(
      child: pw.Text(
        'SALE RECEIPT - $size',
        style: pw.TextStyle(
          font: fontBold,
          fontSize: _titleFontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// Build header row: Shop name | Open Rcpt Total | Date: ___/___/______
  static pw.Widget _buildHeaderRow(String shopName, pw.Font font, pw.Font fontBold, bool showOpening) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Shop: $shopName',
          style: pw.TextStyle(font: font, fontSize: 11),
        ),
        if (showOpening)
          pw.Text(
            'Open  Rcpt  Total',
            style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey600),
          )
        else
          pw.Text(
            'Rcpt  Sale',
            style: pw.TextStyle(font: font, fontSize: 11, color: PdfColors.grey600),
          ),
        pw.Text(
          'Date: ___/___/______',
          style: pw.TextStyle(font: font, fontSize: 11),
        ),
      ],
    );
  }

  /// Build the main table
  static pw.Widget _buildTable(
    List<PurchaReportItem> items,
    int emptyRowsNeeded,
    PurchaReportPage page,
    pw.Font font,
    pw.Font fontBold, {
    bool showOpening = true,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: _getColumnWidths(showOpening),
      children: [
        // Header row
        _buildTableHeader(fontBold, showOpening),

        // Data rows
        ...items.asMap().entries.map((entry) =>
          _buildDataRow(entry.key + 1, entry.value, font, fontBold, showOpening)
        ),

        // Empty rows
        ...List.generate(emptyRowsNeeded, (index) =>
          _buildEmptyRow(items.length + index + 1, font, showOpening)
        ),

        // Grand total row
        _buildGrandTotalRow(page, font, fontBold, showOpening),
      ],
    );
  }

  /// Build table header row
  /// ALWAYS shows all columns (Opening, Total, Closing) - values are empty when showOpening is false
  static pw.TableRow _buildTableHeader(pw.Font fontBold, bool showOpening) {
    // Always show ALL columns - Opening, Total, Closing are always visible
    return pw.TableRow(
      children: [
        _headerCell('S.No', fontBold),
        _headerCell('Brand Name', fontBold, alignment: pw.Alignment.centerLeft),
        _headerCell('Opening', fontBold),
        _headerCell('Receipt', fontBold),
        _headerCell('Total', fontBold),
        _headerCell('Sale', fontBold),
        _headerCell('Rate', fontBold),
        _headerCell('Amount', fontBold),
        _headerCell('Closing', fontBold),
      ],
    );
  }

  /// Header cell
  static pw.Widget _headerCell(String text, pw.Font fontBold, {pw.Alignment alignment = pw.Alignment.center}) {
    return pw.Container(
      height: _headerRowHeight,
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: _headerFontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// Build data row with product information
  /// ALWAYS shows all columns - Opening, Total, Closing show empty when showOpening is false
  static pw.TableRow _buildDataRow(int serialNo, PurchaReportItem item, pw.Font font, pw.Font fontBold, bool showOpening) {
    final needsMultiLine = item.brandName.length > 28;
    final rowHeight = needsMultiLine ? _multiLineRowHeight : _dataRowHeight;

    // Always show ALL columns - Opening, Total, Closing are empty when showOpening is false
    return pw.TableRow(
      children: [
        _dataCell('$serialNo', font, height: rowHeight),
        _brandNameCell(item.brandName, fontBold, height: rowHeight),
        _dataCell(showOpening ? _formatValue(item.openingStock) : '', font, height: rowHeight),
        _dataCell(_formatValue(item.receipt), font, height: rowHeight),
        _dataCell(showOpening ? _formatValue(item.total) : '', font, height: rowHeight),
        _dataCell(_formatValue(item.sale), font, height: rowHeight),
        _dataCell(_formatRate(item.rate), fontBold, height: rowHeight),
        _dataCell(_formatAmount(item.amount), font, height: rowHeight),
        _dataCell(showOpening ? _formatValue(item.closingStock) : '', font, height: rowHeight),
      ],
    );
  }

  /// Build empty row (with serial number only)
  /// ALWAYS shows all 9 columns
  static pw.TableRow _buildEmptyRow(int serialNo, pw.Font font, bool showOpening) {
    // Always show ALL 9 columns
    return pw.TableRow(
      children: [
        _dataCell('$serialNo', font),
        _dataCell('', font),
        _dataCell('', font),
        _dataCell('', font),
        _dataCell('', font),
        _dataCell('', font),
        _dataCell('', font),
        _dataCell('', font),
        _dataCell('', font),
      ],
    );
  }

  /// Build grand total row
  /// ALWAYS shows all 9 columns - Opening, Total, Closing show empty when showOpening is false
  static pw.TableRow _buildGrandTotalRow(PurchaReportPage page, pw.Font font, pw.Font fontBold, bool showOpening) {
    // Always show ALL 9 columns - Opening, Total, Closing totals are empty when showOpening is false
    return pw.TableRow(
      children: [
        _dataCell('', font),
        _grandTotalLabelCell('GRAND TOTAL', fontBold),
        _dataCell(showOpening ? _formatValue(page.grandOpening) : '', font),
        _dataCell(_formatValue(page.grandReceipt), font),
        _dataCell(showOpening ? _formatValue(page.grandTotal) : '', font),
        _dataCell(_formatValue(page.grandSale), font),
        _dataCell('', font),
        _dataCell(_formatAmount(page.grandAmount), font),
        _dataCell(showOpening ? _formatValue(page.grandClosing) : '', font),
      ],
    );
  }

  /// Regular data cell
  static pw.Widget _dataCell(String text, pw.Font font, {double height = _dataRowHeight}) {
    return pw.Container(
      height: height,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: _cellFontSize),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Brand name cell (left aligned, bold, may wrap)
  static pw.Widget _brandNameCell(String text, pw.Font fontBold, {double height = _dataRowHeight}) {
    return pw.Container(
      height: height,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: _brandNameFontSize,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.left,
        maxLines: 2,
      ),
    );
  }

  /// Grand total label cell
  static pw.Widget _grandTotalLabelCell(String text, pw.Font fontBold) {
    return pw.Container(
      height: _dataRowHeight,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: _cellFontSize,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  /// Flatten page items from categories
  /// Only includes items that have actual stock data (not all zeros)
  /// Sorted by price (rate) ascending - matching Daily Sales Entry order
  static List<PurchaReportItem> _flattenPageItems(PurchaReportPage page) {
    final List<PurchaReportItem> items = [];
    for (final category in page.categories) {
      // Filter to only include items with actual stock activity
      final activeItems = category.items.where((item) => _hasStockActivity(item));
      items.addAll(activeItems);
    }

    // Sort by price (rate) ascending - same order as Daily Sales Entry
    items.sort((a, b) {
      final priceComparison = a.rate.compareTo(b.rate);
      if (priceComparison != 0) return priceComparison;
      // If same price, sort by brand name alphabetically
      return a.brandName.compareTo(b.brandName);
    });

    return items;
  }

  /// Check if item has any stock activity (not all zeros)
  static bool _hasStockActivity(PurchaReportItem item) {
    return item.openingStock > 0 ||
           item.receipt > 0 ||
           item.sale > 0 ||
           item.closingStock > 0 ||
           item.total > 0 ||
           item.amount > 0;
  }

  /// Calculate empty rows needed to fill page nicely
  /// Always adds at least 4 empty rows for consistency
  static int _calculateEmptyRows(int dataRows) {
    // Target around 40-45 rows per page for A4
    const targetRows = 40;
    const minEmptyRows = 4; // Always show at least 4 empty rows
    const maxEmptyRows = 10; // Cap at 10 empty rows

    final emptyNeeded = targetRows - dataRows - 1; // -1 for grand total

    if (emptyNeeded <= 0) {
      // Page is already full or overflowing, but still add minimum empty rows
      return minEmptyRows;
    } else if (emptyNeeded > maxEmptyRows) {
      // Don't add too many empty rows
      return maxEmptyRows;
    }
    return emptyNeeded;
  }

  /// Format integer value (empty for 0)
  static String _formatValue(int value) {
    return value == 0 ? '' : '$value';
  }

  /// Format rate (always show, bold)
  static String _formatRate(double rate) {
    return rate > 0 ? rate.toStringAsFixed(0) : '';
  }

  /// Format amount (empty for 0)
  static String _formatAmount(double amount) {
    return amount == 0 ? '' : amount.toStringAsFixed(0);
  }

  // ==================== PUBLIC METHODS ====================

  /// Generate PDF and save to file
  static Future<File> generateAndSave(
    PurchaReport report, {
    String? customFileName,
    bool showOpening = true,
  }) async {
    final pdf = await generatePdf(report, showOpening: showOpening);
    final bytes = await pdf.save();

    final directory = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(report.reportDate);
    final fileName = customFileName ??
        'purcha_report_${report.shopName.replaceAll(' ', '_')}_$dateStr.pdf';
    final file = File('${directory.path}/$fileName');

    await file.writeAsBytes(bytes);
    return file;
  }

  /// Generate PDF bytes for sharing
  static Future<Uint8List> generateBytes(PurchaReport report, {bool showOpening = true}) async {
    final pdf = await generatePdf(report, showOpening: showOpening);
    return pdf.save();
  }

  /// Generate and share PDF
  static Future<void> generateAndShare(
    PurchaReport report, {
    String? subject,
    bool showOpening = true,
  }) async {
    final file = await generateAndSave(report, showOpening: showOpening);
    final dateStr = DateFormat('dd-MM-yyyy').format(report.reportDate);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject ?? 'Purcha Report - ${report.shopName} - $dateStr',
    );
  }

  /// Generate PDF for a single size page
  static Future<pw.Document> generateSingleSizePdf(
    PurchaReport report,
    String size, {
    bool showOpening = true,
  }) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final page = report.pages.firstWhere(
      (p) => p.size == size,
      orElse: () => report.pages.first,
    );

    final items = _flattenPageItems(page);
    final emptyRowsNeeded = _calculateEmptyRows(items.length);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _buildTitle(page.size, fontBold),
            pw.SizedBox(height: 8),
            _buildHeaderRow(report.shopName, font, fontBold, showOpening),
            pw.SizedBox(height: 12),
            _buildTable(items, emptyRowsNeeded, page, font, fontBold, showOpening: showOpening),
          ],
        ),
      ),
    );

    return pdf;
  }
}

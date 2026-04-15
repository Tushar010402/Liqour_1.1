import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/purcha_report_models.dart';

/// PDF Generator for Purcha Report — 2-column A4 layout
/// Each column: S.No | Brand Name (#MRP) | Open | Sale | Close
/// 28 rows per column = 56 items per page
class PurchaPdfGenerator {
  static const double _cellFontSize = 11;
  static const double _brandFontSize = 10;
  static const double _headerFontSize = 11;
  static const double _rowHeight = 24;
  static const int _rowsPerColumn = 28;

  // Column widths for each half (5 columns) — fills A4 width (555pt usable)
  static const double _colNo = 24;
  static const double _colBrand = 145;
  static const double _colOpen = 38;
  static const double _colSale = 38;
  static const double _colClose = 38;

  static Future<pw.Document> generatePdf(PurchaReport report, {bool showOpening = true}) async {
    final pdf = pw.Document();
    final font = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    for (final page in report.pages) {
      final items = _flattenPageItems(page);
      if (items.isEmpty) continue;

      // Pad to multiple of 56 with empty slots
      final totalSlots = (((items.length - 1) ~/ (_rowsPerColumn * 2)) + 1) * _rowsPerColumn * 2;

      // Generate PDF pages (56 items each)
      for (int pageStart = 0; pageStart < totalSlots; pageStart += _rowsPerColumn * 2) {
        final leftItems = <PurchaReportItem?>[];
        final rightItems = <PurchaReportItem?>[];

        for (int i = 0; i < _rowsPerColumn; i++) {
          final leftIdx = pageStart + i;
          final rightIdx = pageStart + _rowsPerColumn + i;
          leftItems.add(leftIdx < items.length ? items[leftIdx] : null);
          rightItems.add(rightIdx < items.length ? items[rightIdx] : null);
        }

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Title
                pw.Center(
                  child: pw.Text(
                    'SALE RECEIPT - ${page.size}',
                    style: pw.TextStyle(font: fontBold, fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 4),
                // Shop + Date row
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Shop: ${report.shopName}', style: pw.TextStyle(font: font, fontSize: 11)),
                    pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(report.reportDate)}', style: pw.TextStyle(font: font, fontSize: 11)),
                  ],
                ),
                pw.SizedBox(height: 8),
                // 2-column table
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Left column
                    pw.Expanded(
                      child: _buildHalfTable(leftItems, pageStart, font, fontBold, showOpening),
                    ),
                    pw.SizedBox(width: 4),
                    // Right column
                    pw.Expanded(
                      child: _buildHalfTable(rightItems, pageStart + _rowsPerColumn, font, fontBold, showOpening),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                // Grand total (only on last page)
                if (pageStart + _rowsPerColumn * 2 >= totalSlots)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('GRAND TOTAL', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                        pw.Text(
                          'Open: ${showOpening ? page.grandOpening : ""}'
                          '  Sale: ${page.grandSale}'
                          '  Close: ${showOpening ? page.grandClosing : ""}',
                          style: pw.TextStyle(font: fontBold, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    return pdf;
  }

  static pw.Widget _buildHalfTable(
    List<PurchaReportItem?> items, int startIndex,
    pw.Font font, pw.Font fontBold, bool showOpening,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(_colNo),
        1: const pw.FixedColumnWidth(_colBrand),
        2: const pw.FixedColumnWidth(_colOpen),
        3: const pw.FixedColumnWidth(_colSale),
        4: const pw.FixedColumnWidth(_colClose),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('No', fontBold, _headerFontSize, bold: true),
            _cellLeft('Brand (#MRP)', fontBold, _headerFontSize, bold: true),
            _cell('Open', fontBold, _headerFontSize, bold: true),
            _cell('Sale', fontBold, _headerFontSize, bold: true),
            _cell('Close', fontBold, _headerFontSize, bold: true),
          ],
        ),
        // Data rows
        for (int i = 0; i < items.length; i++)
          pw.TableRow(
            children: items[i] != null
                ? [
                    _cell('${startIndex + i + 1}', font, _cellFontSize),
                    _cellLeft(
                      items[i]!.rate > 0
                          ? '${items[i]!.brandName} (#${items[i]!.rate.toStringAsFixed(0)})'
                          : items[i]!.brandName,
                      font, _brandFontSize,
                    ),
                    _cell(showOpening ? _fmtVal(items[i]!.openingStock) : '', font, _cellFontSize),
                    _cell(_fmtVal(items[i]!.sale), font, _cellFontSize),
                    _cell(showOpening ? _fmtVal(items[i]!.closingStock) : '', font, _cellFontSize),
                  ]
                : [
                    _cell('${startIndex + i + 1}', font, _cellFontSize),
                    _cellLeft('', font, _brandFontSize),
                    _cell('', font, _cellFontSize),
                    _cell('', font, _cellFontSize),
                    _cell('', font, _cellFontSize),
                  ],
          ),
      ],
    );
  }

  static pw.Widget _cell(String text, pw.Font font, double fontSize, {bool bold = false}) {
    return pw.Container(
      height: _rowHeight,
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _cellLeft(String text, pw.Font font, double fontSize, {bool bold = false}) {
    return pw.Container(
      height: _rowHeight,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: fontSize, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: pw.TextAlign.left, maxLines: 2),
    );
  }

  static String _fmtVal(int v) => v == 0 ? '' : '$v';

  static List<PurchaReportItem> _flattenPageItems(PurchaReportPage page) {
    final items = <PurchaReportItem>[];
    for (final cat in page.categories) {
      items.addAll(cat.items);
    }
    items.sort((a, b) {
      final p = a.rate.compareTo(b.rate);
      if (p != 0) return p;
      return a.brandName.compareTo(b.brandName);
    });
    return items;
  }

  // ==================== PUBLIC METHODS ====================

  static Future<File> generateAndSave(PurchaReport report, {String? customFileName, bool showOpening = true}) async {
    final pdf = await generatePdf(report, showOpening: showOpening);
    final bytes = await pdf.save();
    final directory = await getApplicationDocumentsDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(report.reportDate);
    final fileName = customFileName ?? 'purcha_${report.shopName.replaceAll(' ', '_')}_$dateStr.pdf';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<Uint8List> generateBytes(PurchaReport report, {bool showOpening = true}) async {
    final pdf = await generatePdf(report, showOpening: showOpening);
    return pdf.save();
  }

  static Future<void> generateAndShare(PurchaReport report, {String? subject, bool showOpening = true}) async {
    final file = await generateAndSave(report, showOpening: showOpening);
    final dateStr = DateFormat('dd-MM-yyyy').format(report.reportDate);
    await Share.shareXFiles([XFile(file.path)], subject: subject ?? 'Purcha Report - ${report.shopName} - $dateStr');
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../models/daily_sales_models.dart';
import '../providers/daily_sales_provider.dart';

/// Font helpers — matching SalesEntrySetupScreen
TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

/// Indian number formatting (1,23,456)
String _fmt(double v) {
  final s = v.toInt().toString();
  if (s.length <= 3) return s;
  final l3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final buf = StringBuffer();
  while (rest.length > 2) {
    buf.write('${rest.substring(0, rest.length - 2)},');
    rest = rest.substring(rest.length - 2);
  }
  buf.write(rest);
  return '${buf.toString()},$l3';
}

/// Sales Summary View — read-only view of submitted sales for a date.
/// Opened from home screen Sales Summary card tap.
class SalesSummaryViewScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialDateLabel;
  /// If user came from a range filter (Last 7 Days / Last Month), pass it to show date strip
  final String? initialRangeLabel;
  /// Optional category filter (e.g. 'English' or 'Beer') — when set, only show items matching this category
  final String? filterCategory;
  /// Optional size filter (e.g. '750ML') — when set, only show items matching this size
  final String? filterSize;

  const SalesSummaryViewScreen({super.key, this.initialDate, this.initialDateLabel, this.initialRangeLabel, this.filterCategory, this.filterSize});

  @override
  State<SalesSummaryViewScreen> createState() => _SalesSummaryViewScreenState();
}

class _SalesSummaryViewScreenState extends State<SalesSummaryViewScreen> {
  late String _selectedDateLabel;
  late DateTime _selectedDate;
  String? _activeRangeLabel;
  DateTime? _stripSelectedDate;

  bool _isLoading = true;
  List<DailySalesRecord> _records = [];
  String? _error;

  /// Tracks which record cards are expanded (by index)
  final Set<int> _expandedRecords = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now().subtract(const Duration(days: 1));
    // If came from a range filter, highlight that pill and show date strip
    if (widget.initialRangeLabel != null) {
      _selectedDateLabel = widget.initialRangeLabel!;
      _activeRangeLabel = widget.initialRangeLabel;
      _stripSelectedDate = _selectedDate;
    } else {
      _selectedDateLabel = widget.initialDateLabel ?? 'Yesterday';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _error = null; _expandedRecords.clear(); });

    try {
      final shopProvider = context.read<ShopSelectionProvider>();
      final salesProvider = context.read<DailySalesProvider>();
      final shopId = shopProvider.selectedShopId;

      final startDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endDate = startDate.add(const Duration(days: 1));

      await salesProvider.fetchRecords(
        shopId: shopId,
        startDate: startDate,
        endDate: endDate, // next day — backend uses < (exclusive)
      );

      if (!mounted) return;
      setState(() {
        _records = List.from(salesProvider.records);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  /// Whether this screen is filtered by category/size (came from setup screen)
  bool get _isFiltered => widget.filterCategory != null || widget.filterSize != null;

  /// All items from all records for the selected date, optionally filtered
  List<DailySalesItem> get _allItems {
    var items = <DailySalesItem>[];
    for (final r in _records) {
      items.addAll(r.items);
    }

    // Apply category filter if set
    if (widget.filterCategory != null) {
      final fc = widget.filterCategory!.toLowerCase();
      items = items.where((i) {
        final cat = (i.categoryName ?? '').toLowerCase();
        if (fc == 'beer') return cat.contains('beer');
        return !cat.contains('beer');
      }).toList();
    }

    // Apply size filter if set
    if (widget.filterSize != null) {
      final fs = widget.filterSize!.toUpperCase();
      items = items.where((i) {
        final size = (i.size ?? '').toUpperCase();
        return size == fs;
      }).toList();
    }

    // Sort by rate ascending (matching daily sales entry pattern)
    items.sort((a, b) {
      final catCmp = (a.categoryName ?? '').compareTo(b.categoryName ?? '');
      if (catCmp != 0) return catCmp;
      return a.unitPrice.compareTo(b.unitPrice);
    });
    return items;
  }

  double get _grandTotal => _records.fold(0.0, (s, r) => s + r.totalSalesAmount);
  int get _totalQty => _allItems.fold(0, (s, i) => s + i.quantity);

  String get _dominantStatus {
    if (_records.isEmpty) return '';
    final statuses = _records.map((r) => r.status).toSet();
    if (statuses.contains('approved')) return 'approved';
    if (statuses.contains('pending')) return 'pending';
    if (statuses.contains('rejected')) return 'rejected';
    return _records.first.status;
  }

  // ── Date filter handlers ──

  void _onDatePillTapped(String label) async {
    HapticFeedbackUtil.selection();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (label == 'Today') {
      setState(() {
        _selectedDateLabel = label; _selectedDate = today;
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    } else if (label == 'Yesterday') {
      setState(() {
        _selectedDateLabel = label; _selectedDate = today.subtract(const Duration(days: 1));
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    } else if (label == 'Last 7 Days' || label == 'Last Month') {
      setState(() {
        _selectedDateLabel = label; _selectedDate = today.subtract(const Duration(days: 1));
        _activeRangeLabel = label; _stripSelectedDate = null;
      });
    } else if (label == 'Custom') {
      final picked = await showDatePicker(
        context: context, initialDate: _selectedDate,
        firstDate: today.subtract(const Duration(days: 90)), lastDate: today,
        helpText: 'Select date',
        builder: (c, child) => Theme(
          data: Theme.of(c).copyWith(colorScheme: Theme.of(c).colorScheme.copyWith(primary: const Color(0xFF3855B3))),
          child: child!,
        ),
      );
      if (picked == null) return;
      setState(() {
        _selectedDateLabel = label; _selectedDate = picked;
        _activeRangeLabel = null; _stripSelectedDate = null;
      });
    }
    _loadData();
  }

  void _onStripDateTapped(DateTime date) {
    HapticFeedbackUtil.selection();
    setState(() { _stripSelectedDate = date; _selectedDate = date; });
    _loadData();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (!_isFiltered) ...[
              _buildDatePills(),
              if (_activeRangeLabel != null) ...[
                const SizedBox(height: 8),
                _buildDateStrip(),
              ],
            ] else ...[
              // Show filter badge when coming from setup screen
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3855B3).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${widget.filterSize ?? ''} ${widget.filterCategory == 'Beer' ? 'Beer' : 'Whisky'}',
                        style: _body(size: 12, weight: FontWeight.w700, color: const Color(0xFF3855B3)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd MMM yyyy').format(_selectedDate),
                      style: _body(size: 12, weight: FontWeight.w500, color: const Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            _buildDateInfoBox(),
            if (_dominantStatus.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildStatusBadge(),
            ],
            const SizedBox(height: 4),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3855B3)),
              child: const Icon(Icons.chevron_left, color: Colors.white, size: 26),
            ),
          ),
          Expanded(
            child: Text('Sales Summary', textAlign: TextAlign.center,
              style: _heading(size: 17, weight: FontWeight.w600)),
          ),
          const SizedBox(width: 40), // balance
        ],
      ),
    );
  }

  Widget _buildDatePills() {
    final labels = ['Today', 'Yesterday', 'Last 7 Days', 'Last Month', 'Custom'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        itemBuilder: (context, index) {
          final label = labels[index];
          final isSelected = _selectedDateLabel == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onDatePillTapped(label),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3855B3) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isSelected ? const Color(0xFF3855B3) : const Color(0xFFD0D5DD)),
                ),
                child: Text(label, style: _body(
                  size: 12, weight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF888888),
                )),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateStrip() {
    final isLast7 = _activeRangeLabel == 'Last 7 Days';
    final dayCount = isLast7 ? 7 : 30;
    final today = DateTime.now();
    final dates = List.generate(dayCount, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: i)));

    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final isSelected = _stripSelectedDate != null &&
              _stripSelectedDate!.year == date.year &&
              _stripSelectedDate!.month == date.month &&
              _stripSelectedDate!.day == date.day;
          final isToday = date.year == today.year && date.month == today.month && date.day == today.day;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onStripDateTapped(date),
              child: Container(
                width: 48,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3855B3) : isToday ? const Color(0xFFE8F0FE) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF3855B3) : isToday ? const Color(0xFF3855B3).withValues(alpha: 0.3) : const Color(0xFFD0D5DD)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('EEE').format(date),
                      style: _body(size: 9, weight: FontWeight.w600, color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                    const SizedBox(height: 1),
                    Text('${date.day}',
                      style: _body(size: 16, weight: FontWeight.w900, color: isSelected ? Colors.white : const Color(0xFF1A1D26))),
                    Text(DateFormat('MMM').format(date),
                      style: _body(size: 8, weight: FontWeight.w600, color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDateInfoBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4FF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD0D9F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF2962FF)),
            const SizedBox(width: 8),
            Text(
              'Sales date: ${DateFormat('dd MMM yyyy, EEEE').format(_selectedDate)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final status = _dominantStatus;
    final Color color;
    final Color bg;
    final String label;
    final IconData icon;

    switch (status) {
      case 'approved':
        color = const Color(0xFF2E7D32); bg = const Color(0xFFE8F5E9);
        label = 'APPROVED'; icon = Icons.check_circle_rounded;
      case 'rejected':
        color = const Color(0xFFD32F2F); bg = const Color(0xFFFFEBEE);
        label = 'REJECTED'; icon = Icons.cancel_rounded;
      default:
        color = const Color(0xFFE65100); bg = const Color(0xFFFFF3E0);
        label = 'PENDING'; icon = Icons.schedule_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
            const SizedBox(width: 8),
            Text('${_records.length} record${_records.length != 1 ? 's' : ''}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFD84315)),
              const SizedBox(height: 16),
              Text('Failed to load', style: _heading(size: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: _body(size: 13, color: const Color(0xFF888888)), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_records.isEmpty) {
      return _buildEmptyState();
    }
    return _buildRecordCards();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: const Color(0xFFD0D5DD)),
            const SizedBox(height: 16),
            Text('No Sales Recorded', style: _heading(size: 17)),
            const SizedBox(height: 8),
            Text(
              'No sales data found for ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
              style: _body(size: 13, color: const Color(0xFF888888)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCards() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        // Each sale record as an expandable card
        for (int i = 0; i < _records.length; i++) ...[
          _buildRecordCard(i, _records[i]),
          const SizedBox(height: 10),
        ],
        // Grand total across all records
        _buildGrandTotal(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildRecordCard(int index, DailySalesRecord record) {
    final isExpanded = _expandedRecords.contains(index);
    final items = List<DailySalesItem>.from(record.items)
      ..sort((a, b) => a.unitPrice.compareTo(b.unitPrice));
    final totalQty = items.fold(0, (s, i) => s + i.quantity);

    // Status colors
    final Color statusColor;
    final Color statusBg;
    final String statusLabel;
    switch (record.status) {
      case 'approved':
        statusColor = const Color(0xFF2E7D32); statusBg = const Color(0xFFE8F5E9); statusLabel = 'Approved';
      case 'rejected':
        statusColor = const Color(0xFFD32F2F); statusBg = const Color(0xFFFFEBEE); statusLabel = 'Rejected';
      default:
        statusColor = const Color(0xFFE65100); statusBg = const Color(0xFFFFF3E0); statusLabel = 'Pending';
    }

    // Extract size/category info from items
    final sizes = items.map((i) => i.size ?? '').where((s) => s.isNotEmpty).toSet();
    final categories = items.map((i) => i.categoryName ?? '').where((c) => c.isNotEmpty).toSet();
    final sizeLabel = sizes.isNotEmpty ? sizes.join(', ') : '';
    final catLabel = categories.isNotEmpty ? categories.join(', ') : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isExpanded ? const Color(0xFF3855B3).withValues(alpha: 0.3) : const Color(0xFFE0E3EA)),
        boxShadow: [
          if (isExpanded)
            BoxShadow(color: const Color(0xFF3855B3).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Card header — always visible, tappable to expand/collapse
          GestureDetector(
            onTap: () {
              HapticFeedbackUtil.selection();
              setState(() {
                if (isExpanded) {
                  _expandedRecords.remove(index);
                } else {
                  _expandedRecords.add(index);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              decoration: BoxDecoration(
                color: isExpanded ? const Color(0xFFF8FAFF) : Colors.white,
                borderRadius: isExpanded
                    ? const BorderRadius.vertical(top: Radius.circular(14))
                    : BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  // Category icon
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3855B3).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      catLabel.contains('Beer') ? Icons.sports_bar : Icons.liquor,
                      color: const Color(0xFF3855B3), size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                catLabel.isNotEmpty ? catLabel : 'Sale Record',
                                style: _body(size: 14, weight: FontWeight.w700),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('\u20B9 ${_fmt(record.totalSalesAmount)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (sizeLabel.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3855B3).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(sizeLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF3855B3))),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text('${items.length} items', style: _body(size: 11, weight: FontWeight.w500, color: const Color(0xFF888888))),
                            const SizedBox(width: 8),
                            Text('Qty: $totalQty', style: _body(size: 11, weight: FontWeight.w500, color: const Color(0xFF888888))),
                            const Spacer(),
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                              child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Expand/collapse arrow
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFAAAAAA), size: 24),
                  ),
                ],
              ),
            ),
          ),
          // Expanded items
          if (isExpanded) ...[
            const Divider(height: 1, color: Color(0xFFECEEF2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  for (int j = 0; j < items.length; j++)
                    _buildItemRow(j, items[j]),
                ],
              ),
            ),
            // Record subtotal
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFF),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Text('Subtotal', style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF555555))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Qty: $totalQty', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF777777))),
                  ),
                  const Spacer(),
                  Text('\u20B9 ${_fmt(record.totalSalesAmount)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(int idx, DailySalesItem item) {
    final stockColor = item.openingStock > 20 ? const Color(0xFF2E7D32) : const Color(0xFFD84315);
    final brandName = item.brandName ?? item.productName ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${idx + 1}  ',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF3366CC))),
              Expanded(
                child: Text(brandName,
                  style: _body(size: 13, weight: FontWeight.w700),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Text('\u20B9 ${_fmt(item.totalAmount)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (item.openingStock > 0)
                _pill(Icons.inventory_2_outlined, '${item.openingStock} stock', stockColor),
              _pill(Icons.shopping_bag_outlined, 'Qty ${item.quantity}', const Color(0xFF555555)),
              _pill(Icons.sell_outlined, 'MRP ${item.unitPrice.toStringAsFixed(0)}', const Color(0xFF555555)),
              _pill(Icons.archive_outlined, '${item.closingStock} closing', const Color(0xFF555555)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6FA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildGrandTotal() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2E8C4)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grand Total', style: _heading(size: 16)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F1F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5),
                ),
                child: Text('Total Quantity - $_totalQty',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF777777))),
              ),
            ],
          ),
          const Spacer(),
          Text('\u20B9 ${_fmt(_grandTotal)}',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1D26))),
        ],
      ),
    );
  }

}

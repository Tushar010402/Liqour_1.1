import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/haptic_feedback.dart';
import '../models/stock_purchase.dart';
import '../services/stock_purchase_service.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

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

/// Purchase Summary View — read-only view of purchases for a date.
/// Same pattern as SalesSummaryViewScreen.
class PurchaseSummaryViewScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialDateLabel;
  final String? initialRangeLabel;

  const PurchaseSummaryViewScreen({super.key, this.initialDate, this.initialDateLabel, this.initialRangeLabel});

  @override
  State<PurchaseSummaryViewScreen> createState() => _PurchaseSummaryViewScreenState();
}

class _PurchaseSummaryViewScreenState extends State<PurchaseSummaryViewScreen> {
  late String _selectedDateLabel;
  late DateTime _selectedDate;
  String? _activeRangeLabel;
  DateTime? _stripSelectedDate;

  bool _isLoading = true;
  List<StockPurchase> _purchases = [];
  String? _error;
  final Set<int> _expandedRecords = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now().subtract(const Duration(days: 1));
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
      final apiService = context.read<DioApiService>();
      final purchaseService = StockPurchaseService(apiService);
      final shopId = shopProvider.selectedShopId;

      final startDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endDate = startDate.add(const Duration(days: 1));

      final response = await purchaseService.getPurchaseHistory(
        shopId: shopId,
        fromDate: startDate,
        toDate: endDate,
        limit: 50,
      );

      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _purchases = response.data!.purchases;
          _isLoading = false;
        });
      } else {
        setState(() { _purchases = []; _isLoading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  double get _grandTotal => _purchases.fold(0.0, (s, p) => s + p.totalAmount);
  int get _totalItems => _purchases.fold(0, (s, p) => s + p.items.fold(0, (si, i) => si + i.quantity));

  // ── Date filter handlers ──

  void _onDatePillTapped(String label) async {
    HapticFeedbackUtil.selection();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (label == 'Today') {
      setState(() { _selectedDateLabel = label; _selectedDate = today; _activeRangeLabel = null; _stripSelectedDate = null; });
    } else if (label == 'Yesterday') {
      setState(() { _selectedDateLabel = label; _selectedDate = today.subtract(const Duration(days: 1)); _activeRangeLabel = null; _stripSelectedDate = null; });
    } else if (label == 'Last 7 Days' || label == 'Last Month') {
      setState(() { _selectedDateLabel = label; _selectedDate = today.subtract(const Duration(days: 1)); _activeRangeLabel = label; _stripSelectedDate = null; });
    } else if (label == 'Custom') {
      final picked = await showDatePicker(
        context: context, initialDate: _selectedDate,
        firstDate: today.subtract(const Duration(days: 90)), lastDate: today,
        builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: Theme.of(c).colorScheme.copyWith(primary: const Color(0xFF3855B3))), child: child!),
      );
      if (picked == null) return;
      setState(() { _selectedDateLabel = label; _selectedDate = picked; _activeRangeLabel = null; _stripSelectedDate = null; });
    }
    _loadData();
  }

  void _onStripDateTapped(DateTime date) {
    HapticFeedbackUtil.selection();
    setState(() { _stripSelectedDate = date; _selectedDate = date; });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildDatePills(),
            if (_activeRangeLabel != null) ...[const SizedBox(height: 8), _buildDateStrip()],
            const SizedBox(height: 8),
            _buildDateInfoBox(),
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
          Expanded(child: Text('Purchase Summary', textAlign: TextAlign.center, style: _heading(size: 17, weight: FontWeight.w600))),
          const SizedBox(width: 40),
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
                child: Text(label, style: _body(size: 12, weight: FontWeight.w600, color: isSelected ? Colors.white : const Color(0xFF888888))),
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
          final isSelected = _stripSelectedDate != null && _stripSelectedDate!.year == date.year && _stripSelectedDate!.month == date.month && _stripSelectedDate!.day == date.day;
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
                  border: Border.all(color: isSelected ? const Color(0xFF3855B3) : isToday ? const Color(0xFF3855B3).withValues(alpha: 0.3) : const Color(0xFFD0D5DD)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat('EEE').format(date), style: _body(size: 9, weight: FontWeight.w600, color: isSelected ? Colors.white70 : const Color(0xFF888888))),
                    const SizedBox(height: 1),
                    Text('${date.day}', style: _body(size: 16, weight: FontWeight.w900, color: isSelected ? Colors.white : const Color(0xFF1A1D26))),
                    Text(DateFormat('MMM').format(date), style: _body(size: 8, weight: FontWeight.w600, color: isSelected ? Colors.white70 : const Color(0xFF888888))),
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
        decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFD0D9F0))),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF2962FF)),
            const SizedBox(width: 8),
            Text('Purchase date: ${DateFormat('dd MMM yyyy, EEEE').format(_selectedDate)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2962FF))),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator.adaptive());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: Color(0xFFD84315)),
          const SizedBox(height: 16),
          Text('Failed to load', style: _heading(size: 16)),
          const SizedBox(height: 8),
          Text(_error!, style: _body(size: 13, color: const Color(0xFF888888)), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ]),
      ));
    }
    if (_purchases.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_cart_outlined, size: 56, color: const Color(0xFFD0D5DD)),
          const SizedBox(height: 16),
          Text('No Purchases', style: _heading(size: 17)),
          const SizedBox(height: 8),
          Text('No purchase data for ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
            style: _body(size: 13, color: const Color(0xFF888888)), textAlign: TextAlign.center),
        ]),
      ));
    }
    return _buildRecordCards();
  }

  Widget _buildRecordCards() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        for (int i = 0; i < _purchases.length; i++) ...[
          _buildPurchaseCard(i, _purchases[i]),
          const SizedBox(height: 10),
        ],
        _buildGrandTotal(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPurchaseCard(int index, StockPurchase purchase) {
    final isExpanded = _expandedRecords.contains(index);
    final totalQty = purchase.items.fold(0, (s, i) => s + i.quantity);

    final Color statusColor;
    final Color statusBg;
    final String statusLabel;
    switch (purchase.status) {
      case StockPurchaseStatus.approved:
        statusColor = const Color(0xFF2E7D32); statusBg = const Color(0xFFE8F5E9); statusLabel = 'Approved';
      case StockPurchaseStatus.rejected:
        statusColor = const Color(0xFFD32F2F); statusBg = const Color(0xFFFFEBEE); statusLabel = 'Rejected';
      case StockPurchaseStatus.cancelled:
        statusColor = const Color(0xFF757575); statusBg = const Color(0xFFF5F5F5); statusLabel = 'Cancelled';
      default:
        statusColor = const Color(0xFFE65100); statusBg = const Color(0xFFFFF3E0); statusLabel = 'Pending';
    }

    final sizes = purchase.items.map((i) => i.size).where((s) => s.isNotEmpty).toSet();
    final sizeLabel = sizes.isNotEmpty ? sizes.join(', ') : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isExpanded ? const Color(0xFFE53935).withValues(alpha: 0.3) : const Color(0xFFE0E3EA)),
        boxShadow: [
          if (isExpanded)
            BoxShadow(color: const Color(0xFFE53935).withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Header — tappable
          GestureDetector(
            onTap: () {
              HapticFeedbackUtil.selection();
              setState(() {
                if (isExpanded) _expandedRecords.remove(index);
                else _expandedRecords.add(index);
              });
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
              decoration: BoxDecoration(
                color: isExpanded ? const Color(0xFFFFF8F8) : Colors.white,
                borderRadius: isExpanded ? const BorderRadius.vertical(top: Radius.circular(14)) : BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.shopping_cart_rounded, color: Color(0xFFE53935), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(
                              purchase.vendorName.isNotEmpty ? purchase.vendorName : 'Purchase',
                              style: _body(size: 14, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis,
                            )),
                            Text('\u20B9 ${_fmt(purchase.totalAmount)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (sizeLabel.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                                child: Text(sizeLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFE53935))),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text('${purchase.items.length} items', style: _body(size: 11, weight: FontWeight.w500, color: const Color(0xFF888888))),
                            const SizedBox(width: 8),
                            Text('Qty: $totalQty', style: _body(size: 11, weight: FontWeight.w500, color: const Color(0xFF888888))),
                            const Spacer(),
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
                  for (int j = 0; j < purchase.items.length; j++)
                    _buildItemRow(j, purchase.items[j]),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF8F8),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Text('Subtotal', style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFF555555))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(4)),
                    child: Text('Qty: $totalQty', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF777777))),
                  ),
                  const Spacer(),
                  Text('\u20B9 ${_fmt(purchase.totalAmount)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(int idx, StockPurchaseItem item) {
    final brandName = item.brandName ?? item.productName;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F1F5)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${idx + 1}  ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFE53935))),
              Expanded(child: Text(brandName, style: _body(size: 13, weight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Text('\u20B9 ${_fmt(item.totalAmount)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6, runSpacing: 4,
            children: [
              _pill(Icons.shopping_bag_outlined, 'Qty ${item.quantity}', const Color(0xFF555555)),
              _pill(Icons.sell_outlined, 'Cost ${item.costPrice.toStringAsFixed(0)}', const Color(0xFF555555)),
              if (item.size.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                  child: Text(item.size, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFE53935))),
                ),
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
        color: const Color(0xFFF5F6FA), borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 12, color: color), const SizedBox(width: 4), Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color))],
      ),
    );
  }

  Widget _buildGrandTotal() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAE8), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2E8C4)),
      ),
      child: Row(
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Grand Total', style: _heading(size: 16)),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFF0F1F5), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFE2E4EA), width: 0.5)),
              child: Text('Total Quantity - $_totalItems', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF777777))),
            ),
          ]),
          const Spacer(),
          Text('\u20B9 ${_fmt(_grandTotal)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A1D26))),
        ],
      ),
    );
  }
}

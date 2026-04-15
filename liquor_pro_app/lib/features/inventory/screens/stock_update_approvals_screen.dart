import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/haptic_feedback.dart';

TextStyle _heading({double size = 18, FontWeight weight = FontWeight.w800, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.montserratAlternates(fontSize: size, fontWeight: weight, color: color);
}

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w600, Color color = const Color(0xFF1A1D26)}) {
  return GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color);
}

class StockUpdateApprovalsScreen extends StatefulWidget {
  const StockUpdateApprovalsScreen({super.key});

  @override
  State<StockUpdateApprovalsScreen> createState() => _StockUpdateApprovalsScreenState();
}

class _StockUpdateApprovalsScreenState extends State<StockUpdateApprovalsScreen> {
  bool _isLoading = true;
  List<dynamic> _requests = [];
  String _filterStatus = 'pending';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final apiService = context.read<DioApiService>();
      final shopId = context.read<ShopSelectionProvider>().selectedShopId;
      final response = await apiService.get<Map<String, dynamic>>(
        '/api/inventory/stock-update-requests',
        queryParams: {
          if (shopId != null) 'shop_id': shopId,
          'status': _filterStatus,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );
      if (response.success && response.data != null) {
        _requests = (response.data!['data'] as List?) ?? [];
      }
    } catch (e) {
      debugPrint('[StockApprovals] Error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _approve(String requestId) async {
    try {
      final apiService = context.read<DioApiService>();
      await apiService.put('/api/inventory/stock-update-requests/$requestId/approve');
      HapticFeedbackUtil.medium();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stock update approved'), backgroundColor: Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.error,
        ));
      }
    }
  }

  Future<void> _reject(String requestId) async {
    try {
      final apiService = context.read<DioApiService>();
      await apiService.put('/api/inventory/stock-update-requests/$requestId/reject',
        body: {'reason': 'Rejected by manager'},
      );
      HapticFeedbackUtil.medium();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Stock update rejected'), backgroundColor: Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
        ));
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: AppColors.error,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Stock Update Requests', style: _heading(size: 17, weight: FontWeight.w700)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Status filter pills
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                _buildFilterPill('Pending', 'pending'),
                const SizedBox(width: 8),
                _buildFilterPill('Approved', 'approved'),
                const SizedBox(width: 8),
                _buildFilterPill('Rejected', 'rejected'),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                            const SizedBox(height: 8),
                            Text('No $_filterStatus requests', style: _body(size: 14, color: const Color(0xFF888888))),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) => _buildRequestCard(_requests[index]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String status) {
    final isActive = _filterStatus == status;
    return GestureDetector(
      onTap: () {
        setState(() => _filterStatus = status);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3855B3) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? const Color(0xFF3855B3) : const Color(0xFFD0D5DD)),
        ),
        child: Text(label, style: _body(size: 13, weight: FontWeight.w600, color: isActive ? Colors.white : const Color(0xFF888888))),
      ),
    );
  }

  Widget _buildRequestCard(dynamic request) {
    final product = request['product'];
    final productName = product != null ? (product['name'] ?? 'Unknown') : 'Unknown Product';
    final currentQty = request['current_qty'] ?? 0;
    final requestedQty = request['requested_qty'] ?? 0;
    final reason = request['reason'] ?? '';
    final notes = request['notes'] ?? '';
    final status = request['status'] ?? 'pending';
    final requestId = request['id'] ?? '';
    final isPending = status == 'pending';

    final statusColor = status == 'approved'
        ? const Color(0xFF2E7D32)
        : status == 'rejected'
            ? const Color(0xFFE53935)
            : const Color(0xFFFF8F00);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPending ? const Color(0xFFFF8F00).withValues(alpha: 0.3) : const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.inventory_2_rounded, size: 18, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(productName, style: _body(size: 14, weight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(status.toUpperCase(), style: _body(size: 10, weight: FontWeight.w700, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Stock change
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(children: [
                  Text('Current', style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFF888888))),
                  const SizedBox(height: 2),
                  Text('$currentQty', style: _heading(size: 20, weight: FontWeight.w800, color: const Color(0xFF1A1D26))),
                ]),
                const Icon(Icons.arrow_forward, size: 20, color: Color(0xFF3855B3)),
                Column(children: [
                  Text('Requested', style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFF888888))),
                  const SizedBox(height: 2),
                  Text('$requestedQty', style: _heading(size: 20, weight: FontWeight.w800, color: const Color(0xFF3855B3))),
                ]),
                Column(children: [
                  Text('Change', style: _body(size: 10, weight: FontWeight.w600, color: const Color(0xFF888888))),
                  const SizedBox(height: 2),
                  Text('${requestedQty - currentQty >= 0 ? '+' : ''}${requestedQty - currentQty}',
                    style: _heading(size: 20, weight: FontWeight.w800, color: requestedQty >= currentQty ? const Color(0xFF2E7D32) : const Color(0xFFE53935))),
                ]),
              ],
            ),
          ),
          if (reason.isNotEmpty || notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (reason.isNotEmpty)
              Text(reason, style: _body(size: 12, weight: FontWeight.w500, color: const Color(0xFF666666))),
            if (notes.isNotEmpty)
              Text(notes, style: _body(size: 11, weight: FontWeight.w400, color: const Color(0xFF999999))),
          ],
          // Action buttons for pending
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _reject(requestId),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text('Reject', style: _body(size: 13, weight: FontWeight.w700, color: const Color(0xFFE53935))),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE53935),
                      side: const BorderSide(color: Color(0xFFE53935)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () => _approve(requestId),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text('Approve', style: _body(size: 13, weight: FontWeight.w700, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

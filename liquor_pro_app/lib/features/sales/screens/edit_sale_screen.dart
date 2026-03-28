import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/dio_api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/sales_service.dart';

/// Edit Sale Screen
/// Supports editing sales and resubmitting rejected sales
class EditSaleScreen extends StatefulWidget {
  final Map<String, dynamic> sale;

  const EditSaleScreen({
    super.key,
    required this.sale,
  });

  @override
  State<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends State<EditSaleScreen> {
  late SalesService _salesService;
  final _formKey = GlobalKey<FormState>();

  // Controllers for basic info
  late TextEditingController _customerNameController;
  late TextEditingController _customerPhoneController;
  late TextEditingController _notesController;

  // Controllers for payment amounts
  late TextEditingController _cashAmountController;
  late TextEditingController _cardAmountController;
  late TextEditingController _upiAmountController;
  late TextEditingController _creditAmountController;

  // Item quantity controllers
  final Map<String, TextEditingController> _quantityControllers = {};

  // State variables
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _items = [];
  double _totalAmount = 0.0;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _salesService = SalesService(context.read<DioApiService>());
    _initializeControllers();
    _loadSaleData();
  }

  void _initializeControllers() {
    // Initialize basic info controllers
    _customerNameController = TextEditingController(
      text: widget.sale['customer'] ?? 'Walk-in',
    );
    _customerPhoneController = TextEditingController(
      text: widget.sale['customer_phone'] ?? '',
    );
    _notesController = TextEditingController(
      text: widget.sale['notes'] ?? '',
    );

    // Initialize payment controllers
    _cashAmountController = TextEditingController(
      text: widget.sale['cash_amount']?.toString() ?? '0',
    );
    _cardAmountController = TextEditingController(
      text: widget.sale['card_amount']?.toString() ?? '0',
    );
    _upiAmountController = TextEditingController(
      text: widget.sale['upi_amount']?.toString() ?? '0',
    );
    _creditAmountController = TextEditingController(
      text: widget.sale['credit_amount']?.toString() ?? '0',
    );

    // Initialize status
    _selectedStatus = widget.sale['status'] ?? 'pending';
  }

  void _loadSaleData() {
    // Load items from the sale
    _items = List<Map<String, dynamic>>.from(widget.sale['items'] ?? []);

    // Initialize quantity controllers for each item
    for (var item in _items) {
      final key = item['product_id'] ?? item['id'] ?? '';
      _quantityControllers[key] = TextEditingController(
        text: item['quantity'].toString(),
      );
    }

    _calculateTotal();
  }

  void _calculateTotal() {
    double total = 0.0;

    for (var item in _items) {
      final key = item['product_id'] ?? item['id'] ?? '';
      final quantity = int.tryParse(_quantityControllers[key]?.text ?? '0') ?? 0;
      final price = (item['price'] ?? 0).toDouble();
      total += quantity * price;
    }

    setState(() {
      _totalAmount = total;
    });
  }

  Future<void> _saveSale() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      // Prepare items array in the correct format for backend
      final updatedItems = _items.map((item) {
        final key = item['product_id'] ?? item['id'] ?? '';
        final quantity = int.tryParse(_quantityControllers[key]?.text ?? '0') ?? 0;
        return {
          'product_id': item['product_id'] ?? item['id'],
          'quantity': quantity,
          'unit_price': (item['price'] ?? 0).toDouble(),
          'discount_amount': item['discount_amount'] ?? 0.0,
          'discount_reason': item['discount_reason'] ?? '',
        };
      }).where((item) => (item['quantity'] as int) > 0).toList();

      // Call the real API
      final response = await _salesService.updateSale(
        saleId: widget.sale['id'],
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim().isEmpty
            ? null
            : _customerPhoneController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        items: updatedItems,
      );

      if (response.success) {
        if (mounted) {
          final isRejected = widget.sale['status'] == 'rejected';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isRejected
                    ? 'Sale resubmitted successfully! Status changed to pending.'
                    : 'Sale updated successfully!',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(response.error ?? 'Failed to update sale');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update sale: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _notesController.dispose();
    _cashAmountController.dispose();
    _cardAmountController.dispose();
    _upiAmountController.dispose();
    _creditAmountController.dispose();
    for (var controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.currentUser;
    final isManager = ['admin', 'manager', 'assistant_manager']
        .contains(currentUser?.role);
    final status = widget.sale['status'] ?? 'pending';
    final isRejected = status.toLowerCase() == 'rejected';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          isRejected ? 'Edit & Resubmit Sale' : 'Edit Sale',
          style: AppTextStyles.h4,
        ),
        centerTitle: true,
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isSubmitting)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sale Info Card
                    Card(
                      elevation: 0,
                      color: cs.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Invoice #${widget.sale['id'] ?? 'N/A'}',
                                  style: AppTextStyles.h5,
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(status).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Date: ${widget.sale['date'] ?? 'N/A'}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'Shop: ${widget.sale['shop_name'] ?? 'Unknown Shop'}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Rejection Reason (if rejected)
                    if (isRejected && widget.sale['rejection_reason'] != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.error.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Rejection Reason',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.sale['rejection_reason'] ?? '',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Customer Information
                    Text(
                      'Customer Information',
                      style: AppTextStyles.h5,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customerNameController,
                      decoration: InputDecoration(
                        labelText: 'Customer Name',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Customer name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customerPhoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Items Section
                    Text(
                      'Items',
                      style: AppTextStyles.h5,
                    ),
                    const SizedBox(height: 12),
                    ..._items.map((item) {
                      final key = item['product_id'] ?? item['id'] ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: cs.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] ?? 'Unknown Product',
                                      style: AppTextStyles.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Price: ${Formatters.currency(item['price'] ?? 0)}',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: _quantityControllers[key],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  onChanged: (_) => _calculateTotal(),
                                  decoration: InputDecoration(
                                    labelText: 'Qty',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Required';
                                    }
                                    final qty = int.tryParse(value);
                                    if (qty == null || qty < 0) {
                                      return 'Invalid';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 20),

                    // Payment Details
                    Text(
                      'Payment Details',
                      style: AppTextStyles.h5,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cashAmountController,
                            decoration: InputDecoration(
                              labelText: 'Cash',
                              prefixIcon: const Icon(Icons.money),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _cardAmountController,
                            decoration: InputDecoration(
                              labelText: 'Card',
                              prefixIcon: const Icon(Icons.credit_card),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _upiAmountController,
                            decoration: InputDecoration(
                              labelText: 'UPI',
                              prefixIcon: const Icon(Icons.qr_code),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _creditAmountController,
                            decoration: InputDecoration(
                              labelText: 'Credit',
                              prefixIcon: const Icon(Icons.schedule),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Notes
                    Text(
                      'Notes',
                      style: AppTextStyles.h5,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      decoration: InputDecoration(
                        labelText: 'Additional Notes',
                        prefixIcon: const Icon(Icons.note_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),

                    // Status (only for managers)
                    if (isManager && !isRejected) ...[
                      Text(
                        'Status',
                        style: AppTextStyles.h5,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outline),
                        ),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedStatus,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                          items: ['pending', 'approved', 'rejected']
                              .map((status) => DropdownMenuItem(
                                    value: status,
                                    child: Text(
                                      status[0].toUpperCase() + status.substring(1),
                                      style: AppTextStyles.bodyMedium,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedStatus = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),

            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Total Amount
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: AppTextStyles.h5,
                      ),
                      Text(
                        Formatters.currency(_totalAmount),
                        style: AppTextStyles.h4.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _saveSale,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRejected ? AppColors.warning : cs.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _isSubmitting
                            ? 'Saving...'
                            : isRejected
                                ? 'Resubmit Sale'
                                : 'Save Changes',
                        style: AppTextStyles.button,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return AppColors.success;
      case 'rejected':
        return AppColors.error;
      case 'pending':
        return AppColors.warning;
      case 'returned':
        return AppColors.info;
      default:
        return AppColors.info;
    }
  }
}
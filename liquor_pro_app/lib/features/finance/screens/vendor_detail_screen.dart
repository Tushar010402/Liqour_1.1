import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/date_time_helper.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/vendor_provider.dart';
import '../models/vendor_model.dart';
import 'vendor_form_screen.dart';

/// Vendor Detail Screen - Rich Information Display
///
/// Features:
/// - Header with vendor info and status
/// - Financial summary cards
/// - Quick action buttons
/// - Bank accounts section
/// - Transaction history with tabs
/// - Pull-to-refresh
class VendorDetailScreen extends StatefulWidget {
  final String vendorId;

  const VendorDetailScreen({
    super.key,
    required this.vendorId,
  });

  @override
  State<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends State<VendorDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVendorDetails();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVendorDetails() async {
    final provider = context.read<VendorProvider>();
    await provider.selectVendor(widget.vendorId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      appBar: AppBar(
        title: const Text('Godam Details'),
        elevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _navigateToEdit(),
          ),
        ],
      ),
      body: Consumer<VendorProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.selectedVendor == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final vendor = provider.selectedVendor;
          if (vendor == null) {
            return _buildErrorState();
          }

          return RefreshIndicator(
            onRefresh: _loadVendorDetails,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card
                  _buildHeaderCard(vendor),

                  // Financial Summary
                  _buildFinancialSummary(vendor),

                  // Quick Actions
                  _buildQuickActions(vendor, provider),

                  // Bank Accounts
                  if (vendor.bankAccounts.isNotEmpty)
                    _buildBankAccounts(vendor.bankAccounts),

                  // Transaction History
                  _buildTransactionHistory(provider),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderCard(Vendor vendor) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: vendor.isActive
                      ? cs.primary.withValues(alpha: 0.1)
                      : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business,
                  color: vendor.isActive ? cs.primary : cs.onSurfaceVariant,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      style: AppTextStyles.h2.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: vendor.isActive ? Colors.green[50] : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        vendor.statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: vendor.isActive ? Colors.green[700] : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Contact Information
          if (vendor.contactPerson != null) ...[
            _buildInfoRow(Icons.person_outline, 'Contact Person', vendor.contactPerson!),
            const SizedBox(height: 12),
          ],
          if (vendor.phone != null) ...[
            _buildInfoRow(Icons.phone_outlined, 'Phone', vendor.phone!),
            const SizedBox(height: 12),
          ],
          if (vendor.email != null) ...[
            _buildInfoRow(Icons.email_outlined, 'Email', vendor.email!),
            const SizedBox(height: 12),
          ],
          if (vendor.address != null || vendor.city != null) ...[
            _buildInfoRow(Icons.location_on_outlined, 'Address', vendor.displayAddress),
            const SizedBox(height: 12),
          ],
          if (vendor.taxId != null) ...[
            _buildInfoRow(Icons.receipt_outlined, 'Tax ID', vendor.taxId!),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialSummary(Vendor vendor) {
    final cs = Theme.of(context).colorScheme;
    final utilizationPercent = vendor.creditLimit > 0
        ? (vendor.outstandingBalance / vendor.creditLimit * 100).clamp(0, 100)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Financial Summary',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildFinancialCard(
                  'Total Purchases',
                  Formatters.currency(vendor.totalPurchases),
                  Icons.shopping_cart_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFinancialCard(
                  'Outstanding',
                  Formatters.currency(vendor.outstandingBalance),
                  Icons.account_balance_wallet_outlined,
                  isWarning: vendor.hasOutstanding,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFinancialCard(
                  'Credit Limit',
                  Formatters.currency(vendor.creditLimit),
                  Icons.credit_card_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFinancialCard(
                  'Payment Terms',
                  vendor.paymentTerms ?? 'Not Set',
                  Icons.schedule_outlined,
                ),
              ),
            ],
          ),
          if (vendor.creditLimit > 0) ...[
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Credit Utilization',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${utilizationPercent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: utilizationPercent / 100,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      utilizationPercent > 80 ? Colors.orange : Colors.green,
                    ),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinancialCard(String label, String value, IconData icon,
      {bool isWarning = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isWarning ? Colors.orange[300] : Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(Vendor vendor, VendorProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  'Record Payment',
                  Icons.payment,
                  cs.primary,
                  () => _showPaymentDialog(vendor, provider),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  'Add Bank Account',
                  Icons.account_balance,
                  Colors.blue,
                  () => _showBankAccountDialog(vendor, provider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
      String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBankAccounts(List<VendorBankAccount> accounts) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bank Accounts',
            style: AppTextStyles.bodyLarge.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...accounts.map((account) => _buildBankAccountCard(account)),
        ],
      ),
    );
  }

  Widget _buildBankAccountCard(VendorBankAccount account) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.account_balance, color: Colors.blue[700], size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      account.bankName,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (account.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Default',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  account.accountHolder,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  account.maskedAccountNumber,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(VendorProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Transaction History',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorColor: cs.primary,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Purchases'),
              Tab(text: 'Payments'),
            ],
          ),
          SizedBox(
            height: 400,
            child: provider.isLoadingTransactions
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTransactionList(provider.selectedVendorTransactions),
                      _buildTransactionList(provider.purchaseTransactions),
                      _buildTransactionList(provider.paymentTransactions),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<VendorTransaction> transactions) {
    if (transactions.isEmpty) {
      return _buildEmptyTransactionState();
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: transactions.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final transaction = transactions[index];
        return _buildTransactionTile(transaction);
      },
    );
  }

  /// Modern empty state for transaction history
  /// Follows iOS/Material best practices with helpful guidance
  Widget _buildEmptyTransactionState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular icon container
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            // Title
            Text(
              'No Transactions Yet',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            // Helpful subtitle
            Text(
              'Record a payment to see transaction history',
              style: AppTextStyles.bodySmall.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(VendorTransaction transaction) {
    final cs = Theme.of(context).colorScheme;
    final isPurchase = transaction.isPurchase;
    final color = isPurchase ? Colors.orange[700]! : Colors.green[700]!;
    final icon = isPurchase ? Icons.shopping_bag_outlined : Icons.payment;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showTransactionDetails(transaction),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isPurchase ? Colors.orange[50] : Colors.green[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction.description,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              transaction.typeDisplay,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (transaction.referenceNo != null) ...[
                              Text(' • ', style: TextStyle(color: cs.onSurfaceVariant)),
                              Flexible(
                                child: Text(
                                  transaction.referenceNo!,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        // IST time display
                        Text(
                          DateTimeHelper.formatIST(transaction.createdAt),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isPurchase ? '+' : '-'}${Formatters.currency(transaction.amount)}',
                        style: AppTextStyles.bodyLarge.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      // Receipt indicator
                      if (transaction.hasReceipt) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_outlined, size: 12, color: Colors.blue[700]),
                              const SizedBox(width: 4),
                              Text(
                                'Receipt',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Chevron indicator
                      const SizedBox(height: 4),
                      Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show full screen receipt image
  void _showReceiptImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            // Full screen image
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined, size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load image',
                            style: AppTextStyles.bodyMedium.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  /// Show transaction details popup (like Stock Purchases History)
  void _showTransactionDetails(VendorTransaction transaction) {
    final isPurchase = transaction.isPurchase;
    final statusColor = isPurchase ? Colors.green : Colors.blue;
    final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isPurchase ? Icons.shopping_bag : Icons.payment,
                        color: statusColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.vendorName.isNotEmpty
                                ? transaction.vendorName
                                : (isPurchase ? 'Stock Purchase' : 'Payment'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (transaction.shopName != null) ...[
                            Text(
                              'Shop: ${transaction.shopName}',
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        transaction.displayStatus,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Summary Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          _buildSummaryItemWithIcon(
                            'Items',
                            '${transaction.items.length}',
                            Icons.inventory_2,
                          ),
                          Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.2)),
                          _buildSummaryItemWithIcon(
                            'Total Qty',
                            '${transaction.totalItemCount}',
                            Icons.numbers,
                          ),
                          Container(width: 1, height: 40, color: cs.primary.withValues(alpha: 0.2)),
                          _buildSummaryItemWithIcon(
                            'Amount',
                            currencyFormat.format(transaction.amount),
                            Icons.currency_rupee,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Items Table (for purchase transactions with items)
                    if (transaction.items.isNotEmpty) ...[
                      const Text('Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // Table Header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(flex: 3, child: Text('Product', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant))),
                                  Expanded(flex: 1, child: Text('Size', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant))),
                                  Expanded(flex: 1, child: Center(child: Text('Qty', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant)))),
                                  Expanded(flex: 1, child: Text('Total', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                                ],
                              ),
                            ),
                            // Table Rows
                            ...transaction.items.map((item) => _buildTransactionItemRow(item, currencyFormat)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Price Breakdown
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildPriceRow('Subtotal', transaction.calculatedSubtotal, currencyFormat),
                          const SizedBox(height: 8),
                          _buildPriceRow('TDS (1%)', transaction.calculatedTds, currencyFormat),
                          const Divider(height: 20),
                          _buildPriceRow('Total Amount', transaction.amount, currencyFormat, isBold: true),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Audit Trail
                    const Text('Audit Trail', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildAuditRow(
                      Icons.person,
                      'Created by',
                      transaction.createdByDisplay,
                      DateTimeHelper.formatIST(transaction.createdAt),
                    ),

                    // Receipt Section (if available)
                    if (transaction.hasReceipt) ...[
                      const SizedBox(height: 20),
                      const Text('Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      _buildReceiptDetailCard(transaction),
                    ],

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildSummaryItemWithIcon(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: cs.primary, size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItemRow(VendorTransactionItem item, NumberFormat currencyFormat) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.brandName != null &&
                    item.brandName!.toLowerCase() != item.displayName.toLowerCase())
                  Text(
                    item.brandName!,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(item.size, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'x${item.quantity}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.primary),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              currencyFormat.format(item.totalAmount),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, NumberFormat currencyFormat, {bool isBold = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 14 : 12,
            color: isBold ? cs.onSurface : cs.onSurfaceVariant,
          ),
        ),
        Text(
          currencyFormat.format(amount),
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 14 : 12,
            color: isBold ? cs.primary : cs.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildAuditRow(IconData icon, String label, String value, String timestamp) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.blue[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                if (timestamp.isNotEmpty)
                  Text(timestamp, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptDetailCard(VendorTransaction transaction) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Receipt Image (if available)
          if (transaction.receiptImageUrl != null) ...[
            GestureDetector(
              onTap: () => _showReceiptImage(transaction.receiptImageUrl!),
              child: Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        transaction.receiptImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) => Container(
                          color: cs.outlineVariant,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 32),
                              const SizedBox(height: 4),
                              Text('Failed to load', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
                            ],
                          ),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: cs.surfaceContainerHighest,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                      // Tap to view indicator
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: cs.onSurfaceVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.zoom_in, size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Tap to view', style: TextStyle(fontSize: 10, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Receipt Details
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Receipt Number
                    if (transaction.receiptNumber != null && transaction.receiptNumber!.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.receipt_long, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Invoice Number',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          transaction.receiptNumber!,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Receipt Date
                    if (transaction.receiptDate != null) ...[
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text(
                            'Receipt Date',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: Text(
                          DateTimeHelper.formatIST(transaction.receiptDate!),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Godam Not Found',
              style: AppTextStyles.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentDialog(Vendor vendor, VendorProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final parentContext = context; // Capture parent context for use after dialog closes
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final descriptionController = TextEditingController();
    String paymentMethod = 'Cash';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount *',
                  prefixText: '₹',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                ),
                items: ['Cash', 'Bank Transfer', 'Cheque', 'UPI', 'Credit Card']
                    .map((method) => DropdownMenuItem(
                          value: method,
                          child: Text(method),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) paymentMethod = value;
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'Reference No (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) {
                SnackbarHelper.showError(context, 'Please enter a valid amount');
                return;
              }

              Navigator.pop(context);

              final success = await provider.recordPayment(
                vendorId: vendor.id,
                amount: amount,
                paymentMethod: paymentMethod,
                referenceNo: referenceController.text.isNotEmpty
                    ? referenceController.text
                    : null,
                description: descriptionController.text.isNotEmpty
                    ? descriptionController.text
                    : null,
              );

              if (success && mounted) {
                SnackbarHelper.showSuccess(parentContext, 'Payment recorded successfully');
              } else if (mounted) {
                SnackbarHelper.showError(
                    parentContext, provider.errorMessage ?? 'Failed to record payment');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );
  }

  void _showBankAccountDialog(Vendor vendor, VendorProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final parentContext = context; // Capture parent context for use after dialog closes
    final bankNameController = TextEditingController();
    final accountNumberController = TextEditingController();
    final accountHolderController = TextEditingController();
    final branchCodeController = TextEditingController();
    bool isDefault = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Bank Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: bankNameController,
                  decoration: const InputDecoration(
                    labelText: 'Bank Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: accountNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Account Number *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: accountHolderController,
                  decoration: const InputDecoration(
                    labelText: 'Account Holder *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: branchCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Branch Code (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Set as Default'),
                  value: isDefault,
                  onChanged: (value) {
                    setState(() {
                      isDefault = value ?? false;
                    });
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (bankNameController.text.isEmpty ||
                    accountNumberController.text.isEmpty ||
                    accountHolderController.text.isEmpty) {
                  SnackbarHelper.showError(context, 'Please fill all required fields');
                  return;
                }

                Navigator.pop(context);

                final request = VendorBankAccountRequest(
                  bankName: bankNameController.text,
                  accountNumber: accountNumberController.text,
                  accountHolder: accountHolderController.text,
                  branchCode: branchCodeController.text.isNotEmpty
                      ? branchCodeController.text
                      : null,
                  isDefault: isDefault,
                );

                final success = await provider.addBankAccount(vendor.id, request);

                if (success && mounted) {
                  SnackbarHelper.showSuccess(parentContext, 'Bank account added successfully');
                } else if (mounted) {
                  SnackbarHelper.showError(
                      parentContext, provider.errorMessage ?? 'Failed to add bank account');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Account'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEdit() {
    final vendor = context.read<VendorProvider>().selectedVendor;
    if (vendor != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VendorFormScreen(vendor: vendor),
        ),
      ).then((_) => _loadVendorDetails());
    }
  }
}

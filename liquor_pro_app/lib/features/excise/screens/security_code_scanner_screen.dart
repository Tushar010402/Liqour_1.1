import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../models/excise_models.dart';
import '../providers/excise_provider.dart';

class SecurityCodeScannerScreen extends StatefulWidget {
  const SecurityCodeScannerScreen({super.key});

  @override
  State<SecurityCodeScannerScreen> createState() => _SecurityCodeScannerScreenState();
}

class _SecurityCodeScannerScreenState extends State<SecurityCodeScannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ExciseProvider>();
      provider.loadSecurityCodes();
      provider.loadSecurityCodeStats();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Security Codes',
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Scanner'),
            Tab(text: 'All Codes'),
            Tab(text: 'Statistics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScannerTab(),
          _buildCodesListTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  Widget _buildScannerTab() {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scanner Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 80,
                      color: Colors.purple[700],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Scan or Enter Security Code',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan QR code or manually enter bottle security code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      // Open camera scanner
                      _showCameraScanner();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Scan with Camera'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Manual Entry
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manual Entry',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: 'Security Code',
                      hintText: 'Enter code',
                      prefixIcon: const Icon(Icons.numbers),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_circle),
                        onPressed: () => _validateCode(_codeController.text),
                      ),
                    ),
                    onSubmitted: _validateCode,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Quick Actions
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.add_box,
                  label: 'Bulk Add',
                  color: Colors.blue,
                  onTap: () => _showBulkAddDialog(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionButton(
                  icon: Icons.broken_image,
                  label: 'Mark Damaged',
                  color: Colors.red,
                  onTap: () => _showMarkDamagedDialog(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCodesListTab() {
    return Consumer<ExciseProvider>(
      builder: (context, provider, child) {
        final cs = Theme.of(context).colorScheme;
        if (provider.isCodesLoading && provider.securityCodes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.securityCodes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code, size: 64, color: cs.outlineVariant),
                const SizedBox(height: 16),
                Text(
                  'No security codes found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadSecurityCodes(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.securityCodes.length,
            itemBuilder: (context, index) {
              final code = provider.securityCodes[index];
              return _SecurityCodeCard(code: code);
            },
          ),
        );
      },
    );
  }

  Widget _buildStatsTab() {
    return Consumer<ExciseProvider>(
      builder: (context, provider, child) {
        final stats = provider.codeStats;

        if (stats == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadSecurityCodeStats(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Total Codes Card
                Card(
                  elevation: 0,
                  color: Colors.purple[700],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.qr_code,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Total Security Codes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stats.totalCodes.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Status Grid
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.3,
                  children: [
                    _buildStatCard(
                      'In Stock',
                      stats.totalInStock,
                      Icons.inventory,
                      Colors.green,
                    ),
                    _buildStatCard(
                      'Sold',
                      stats.totalSold,
                      Icons.shopping_cart,
                      Colors.blue,
                    ),
                    _buildStatCard(
                      'Damaged',
                      stats.totalDamaged,
                      Icons.broken_image,
                      Colors.red,
                    ),
                    _buildStatCard(
                      'Missing',
                      stats.totalMissing,
                      Icons.help_outline,
                      Colors.orange,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Consideration Fees
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.currency_rupee, color: Colors.green[700]),
                            const SizedBox(width: 8),
                            Text(
                              'Consideration Fees',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        _buildInfoRow('Bottles Sold', stats.totalSold.toString()),
                        _buildInfoRow('Fee per Bottle', '₹50'),
                        const Divider(height: 16),
                        _buildInfoRow(
                          'Total Fees',
                          '₹${(stats.totalSold * 50).toStringAsFixed(0)}',
                          valueColor: Colors.green[700],
                          isTotal: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int value, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 12),
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool isTotal = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              color: isTotal ? null : cs.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  void _showCameraScanner() {
    // TODO: Implement camera scanner (requires camera package)
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Camera Scanner'),
        content: const Text(
          'Camera scanner requires additional setup.\n\n'
          'Add the following package to pubspec.yaml:\n'
          '- mobile_scanner: ^3.5.5\n\n'
          'For now, use manual entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _validateCode(String code) async {
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a code'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final provider = context.read<ExciseProvider>();
    final securityCode = await provider.validateSecurityCode(code);

    if (securityCode != null && mounted) {
      _showCodeDetailDialog(securityCode);
      _codeController.clear();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Invalid security code'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showCodeDetailDialog(SecurityCode code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(code.statusIcon, color: code.statusColor),
            const SizedBox(width: 8),
            const Text('Security Code'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogRow('Code', code.code),
            _buildDialogRow('Status', code.statusText),
            _buildDialogRow('Product', code.productId),
            _buildDialogRow('Shop', code.shopId),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showBulkAddDialog() {
    final codesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
        title: const Text('Bulk Add Security Codes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codesController,
              decoration: const InputDecoration(
                labelText: 'Security Codes',
                hintText: 'Enter codes (one per line)',
                border: OutlineInputBorder(),
              ),
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter one code per line',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final codes = codesController.text
                  .split('\n')
                  .where((c) => c.trim().isNotEmpty)
                  .toList();

              if (codes.isEmpty) {
                return;
              }

              Navigator.pop(context);

              final provider = context.read<ExciseProvider>();
              final success = await provider.bulkAddSecurityCodes(
                shopId: provider.selectedShopId ?? '33333333-3333-3333-3333-333333333333',
                productId: 'product-id', // TODO: Select product
                codes: codes,
              );

              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added ${codes.length} security codes'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      );
      },
    );
  }

  void _showMarkDamagedDialog() {
    final codeController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Codes as Damaged'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'Security Codes',
                hintText: 'Enter codes (one per line)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final codes = codeController.text
                  .split('\n')
                  .where((c) => c.trim().isNotEmpty)
                  .toList();

              if (codes.isEmpty || reasonController.text.isEmpty) {
                return;
              }

              Navigator.pop(context);

              final provider = context.read<ExciseProvider>();
              final success = await provider.markCodesAsDamaged(
                codes: codes,
                reason: reasonController.text,
              );

              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Codes marked as damaged'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('Mark Damaged'),
          ),
        ],
      ),
    );
  }
}

class _SecurityCodeCard extends StatelessWidget {
  final SecurityCode code;

  const _SecurityCodeCard({required this.code});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: code.statusColor.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                code.statusIcon,
                color: code.statusColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code.code,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    code.statusText,
                    style: TextStyle(
                      fontSize: 13,
                      color: code.statusColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

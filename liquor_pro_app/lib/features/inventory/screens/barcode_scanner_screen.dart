import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';

/// Barcode Scanner Screen - For scanning product barcodes
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  String? _scannedCode;
  bool _isScanning = false;
  final TextEditingController _manualBarcodeController = TextEditingController();

  @override
  void dispose() {
    _manualBarcodeController.dispose();
    super.dispose();
  }

  Future<void> _startScanning() async {
    setState(() => _isScanning = true);

    // TODO: Implement actual barcode scanning
    // For now, simulate scanning after 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _scannedCode = '1234567890123'; // Simulated barcode
        _isScanning = false;
      });
      _lookupProduct(_scannedCode!);
    }
  }

  Future<void> _lookupProduct(String barcode) async {
    // TODO: Lookup product by barcode - GET /api/inventory/products/by-barcode/:barcode

    // Simulate API call
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Product Found'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Barcode: $barcode'),
              const SizedBox(height: 8),
              const Text('Product: Sample Product'),
              const SizedBox(height: 8),
              const Text('Price: ₹500.00'),
              const SizedBox(height: 8),
              const Text('Stock: 25 units'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _scannedCode = null);
              },
              child: const Text('Scan Another'),
            ),
            ElevatedButton(
              onPressed: () {
                // TODO: Navigate to product details or add to sale
                Navigator.pop(context);
                Navigator.pop(context, barcode); // Return barcode to caller
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('View Details'),
            ),
          ],
        ),
      );
    }
  }

  void _handleManualEntry() {
    final barcode = _manualBarcodeController.text.trim();
    if (barcode.isNotEmpty) {
      setState(() => _scannedCode = barcode);
      _lookupProduct(barcode);
      _manualBarcodeController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Barcode Scanner',
      ),
      body: Column(
        children: [
          // Scanner Area
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isScanning ? AppColors.primary : AppColors.textSecondary.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: _isScanning
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 200,
                          height: 200,
                          child: Stack(
                            children: [
                              // Scanner frame corners
                              Positioned(
                                top: 0,
                                left: 0,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: AppColors.primary, width: 4),
                                      left: BorderSide(color: AppColors.primary, width: 4),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: AppColors.primary, width: 4),
                                      right: BorderSide(color: AppColors.primary, width: 4),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: AppColors.primary, width: 4),
                                      left: BorderSide(color: AppColors.primary, width: 4),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: AppColors.primary, width: 4),
                                      right: BorderSide(color: AppColors.primary, width: 4),
                                    ),
                                  ),
                                ),
                              ),
                              // Scanning line animation
                              Center(
                                child: Container(
                                  width: 180,
                                  height: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Scanning...',
                          style: AppTextStyles.h5.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Point camera at barcode',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 100,
                          color: AppColors.primary.withOpacity(0.3),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Ready to Scan',
                          style: AppTextStyles.h4,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the button below to start scanning',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_scannedCode != null) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Last Scanned: $_scannedCode',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),

          // Manual Entry Section
          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Manual Entry',
                    style: AppTextStyles.h5,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Enter barcode number manually',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualBarcodeController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: 'Enter barcode',
                            prefixIcon: const Icon(Icons.numbers),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) => _handleManualEntry(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _handleManualEntry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                        child: const Text('Lookup'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Scan Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isScanning ? null : _startScanning,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        disabledBackgroundColor: AppColors.textSecondary,
                      ),
                      icon: Icon(_isScanning ? Icons.stop : Icons.qr_code_scanner),
                      label: Text(
                        _isScanning ? 'Scanning...' : 'Start Scanning',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.1),
              border: Border(
                top: BorderSide(
                  color: AppColors.info.withOpacity(0.3),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.info,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Scanning Tips',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Hold device steady and ensure good lighting\n'
                  '• Keep barcode centered in the frame\n'
                  '• Clean camera lens for better accuracy\n'
                  '• Use manual entry if barcode is damaged',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

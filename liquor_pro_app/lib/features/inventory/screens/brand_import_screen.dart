import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../providers/brand_onboarding_provider.dart';
import '../services/brand_onboarding_service.dart';
import '../widgets/brand_import_success_dialog.dart';
import '../widgets/shop_selector_widget.dart';
import '../../admin/models/shop_model.dart';
import '../../admin/services/shop_service.dart';
import '../../../core/services/dio_api_service.dart';

/// Brand Import Screen - Bulk import brands from Excel with shop-specific stock
class BrandImportScreen extends StatefulWidget {
  const BrandImportScreen({super.key});

  @override
  State<BrandImportScreen> createState() => _BrandImportScreenState();
}

class _BrandImportScreenState extends State<BrandImportScreen> {
  bool _isUploading = false;
  BrandImportResult? _importResult;
  String? _selectedFilePath;
  Shop? _selectedShop;
  bool _isLoadingShops = true;

  @override
  void initState() {
    super.initState();
    _autoSelectShop();
  }

  Future<void> _autoSelectShop() async {
    setState(() => _isLoadingShops = true);

    try {
      final shopService = ShopService(context.read<DioApiService>());
      final response = await shopService.getShops();

      if (response.success && response.data != null && response.data!.isNotEmpty) {
        final shops = response.data!;

        // Auto-select logic:
        // 1. If only one shop, auto-select it
        // 2. Otherwise, select first active shop
        setState(() {
          _selectedShop = shops.first;
          _isLoadingShops = false;
        });

        print('✅ [BrandImport] Auto-selected shop: ${_selectedShop!.name}');
      } else {
        setState(() => _isLoadingShops = false);
      }
    } catch (e) {
      print('❌ [BrandImport] Error loading shops: $e');
      setState(() => _isLoadingShops = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Brand Import'),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildShopSelectionCard(),
            const SizedBox(height: 24),
            _buildInstructionCard(),
            const SizedBox(height: 24),
            _buildDownloadTemplateSection(),
            const SizedBox(height: 32),
            _buildUploadSection(),
            if (_importResult != null) ...[
              const SizedBox(height: 32),
              _buildResultsSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShopSelectionCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _selectedShop != null
                        ? AppColors.success.withValues(alpha: 0.1)
                        : AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.store,
                    color: _selectedShop != null ? AppColors.success : AppColors.warning,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Step 1: Target Shop',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _isLoadingShops
                  ? 'Loading your shops...'
                  : _selectedShop != null
                      ? 'Brands will be imported to ${_selectedShop!.name}'
                      : 'Choose which shop will receive the imported brand stock',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoadingShops)
              const Center(
                child: CircularProgressIndicator(),
              )
            else
              ShopSelectorWidget(
                selectedShop: _selectedShop,
                onShopSelected: (shop) {
                  setState(() {
                    _selectedShop = shop;
                    // Clear previous import results when shop changes
                    _importResult = null;
                  });
                },
                hint: 'Tap to change shop',
                isRequired: true,
                showShopDetails: true,
              ),
            if (_selectedShop != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Stock will be imported to: ${_selectedShop!.name}',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline, color: AppColors.info, size: 28),
                SizedBox(width: 12),
                Text(
                  'How to Import Brands',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInstructionStep(
              '1',
              'Shop auto-selected',
              '${_selectedShop?.name ?? "Your shop"} is ready to receive brands',
            ),
            const SizedBox(height: 12),
            _buildInstructionStep(
              '2',
              'Download the Excel template',
              'Get the pre-formatted template with sample data',
            ),
            const SizedBox(height: 12),
            _buildInstructionStep(
              '3',
              'Fill in your brand data',
              'Add brands with stock quantities in the Excel file',
            ),
            const SizedBox(height: 12),
            _buildInstructionStep(
              '4',
              'Upload and import',
              'Upload the file to add brands to ${_selectedShop?.name ?? "your shop"}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadTemplateSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 2: Download Template',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedShop != null
                  ? 'Download the Excel template for ${_selectedShop!.name}'
                  : 'Select a shop first, then download the template.',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedShop != null ? _downloadTemplate : null,
                icon: const Icon(Icons.download),
                label: Text(_selectedShop != null
                    ? 'Download Template for ${_selectedShop!.name}'
                    : 'Select Shop First'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 3: Upload Completed File',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedFilePath != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _selectedFilePath!.split('/').last,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _selectedFilePath = null),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_selectedFilePath == null
                        ? 'Select Excel File'
                        : 'Change File'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _selectedFilePath == null || _isUploading || _selectedShop == null
                        ? null
                        : _uploadFile,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload),
                    label: Text(_isUploading
                        ? 'Uploading...'
                        : _selectedShop == null
                            ? 'Select Shop First'
                            : 'Upload & Import to ${_selectedShop!.name}'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection() {
    final result = _importResult!;
    final hasErrors = result.errorCount > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasErrors ? Icons.warning_amber : Icons.check_circle,
                  color: hasErrors ? AppColors.warning : AppColors.success,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Import Results',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildResultRow('Total Rows', result.totalRows.toString()),
            _buildResultRow('Successful', result.successCount.toString(),
                color: AppColors.success),
            _buildResultRow('Errors', result.errorCount.toString(),
                color: hasErrors ? AppColors.error : null),
            if (result.errors.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Error Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 8),
              ...result.errors.map((error) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Row ${error.row}:',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error.message)),
                      ],
                    ),
                  )),
            ],
            if (result.importedBrands.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Successfully Imported Brands',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(height: 8),
              ...result.importedBrands
                  .take(5)
                  .map((brand) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 16, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${brand.brandName} - ${brand.size}ml',
                                style: const TextStyle(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ))
                  ,
              if (result.importedBrands.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '... and ${result.importedBrands.length - 5} more',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    try {
      final provider = context.read<BrandOnboardingProvider>();

      // Show loading indicator
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 16),
              Text('Downloading template...'),
            ],
          ),
          duration: Duration(seconds: 10),
        ),
      );

      final result = await provider.downloadBrandTemplate();

      if (!mounted) return;

      // Clear loading snackbar
      ScaffoldMessenger.of(context).clearSnackBars();

      if (result.success && result.data != null) {
        // Open iOS share sheet to save/share the file
        final filePath = result.data!;
        await Share.shareXFiles(
          [XFile(filePath)],
          subject: 'Brand Import Template',
          text: 'Use this template to import brands into Liquor Pro',
        );

        if (!mounted) return;
        SnackbarHelper.showSuccess(
          context,
          'Template ready! Use the share sheet to save or send.',
        );
      } else {
        SnackbarHelper.showError(
            context, result.message ?? 'Failed to download template');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      SnackbarHelper.showError(context, 'Error downloading template: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFilePath = result.files.single.path!;
          _importResult = null; // Clear previous results
        });
      }
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'Error selecting file: $e');
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFilePath == null || _selectedShop == null) return;

    setState(() => _isUploading = true);

    try {
      final provider = context.read<BrandOnboardingProvider>();
      final result = await provider.uploadBrandExcel(
        _selectedFilePath!,
        shopId: _selectedShop!.id,
        shopName: _selectedShop!.name,
      );

      if (!mounted) return;

      setState(() {
        _isUploading = false;
        if (result.success && result.data != null) {
          _importResult = result.data!;

          // Show the new animated success dialog with shop info
          BrandImportSuccessDialog.show(
            context,
            _importResult!,
            shopName: _selectedShop!.name,
          );

          // Clear the selected file after successful import
          _selectedFilePath = null;
        } else {
          SnackbarHelper.showError(
              context, result.message ?? 'Failed to import brands to ${_selectedShop!.name}');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      SnackbarHelper.showError(context, 'Error uploading file: $e');
    }
  }
}

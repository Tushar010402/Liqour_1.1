import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/snackbar_helper.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/custom_buttons.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/providers/service_providers.dart' show apiServiceProvider;
import '../providers/ocr_provider.dart';
import '../models/ocr_models.dart';

/// Multi-Photo Stock OCR Screen - Upload multiple photos to auto-create stock
class MultiPhotoStockOCRScreen extends ConsumerStatefulWidget {
  final String shopId;

  const MultiPhotoStockOCRScreen({super.key, required this.shopId});

  @override
  ConsumerState<MultiPhotoStockOCRScreen> createState() => _MultiPhotoStockOCRScreenState();
}

class _MultiPhotoStockOCRScreenState extends ConsumerState<MultiPhotoStockOCRScreen>
    with TickerProviderStateMixin {

  static const int MAX_PHOTOS = 10;

  final ImagePicker _picker = ImagePicker();
  final List<File> _selectedImages = [];
  bool _isProcessing = false;

  // Processing state
  int _currentPhotoIndex = 0;
  int _totalItemsProcessed = 0;
  int _totalItemsAdded = 0;
  int _totalItemsFailed = 0;
  List<Map<String, dynamic>> _processedResults = [];

  // Progress tracking
  String _processingStatus = '';
  double _processingProgress = 0.0;
  String _processingSubStatus = '';

  // Animation controllers
  late AnimationController _scanAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _scanAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanAnimationController, curve: Curves.linear),
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    _pulseAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text('Auto Stock from Photos', style: AppTextStyles.h5),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isProcessing) {
      return _buildProcessingOverlay();
    }

    if (_selectedImages.isNotEmpty) {
      return _buildPhotoPreviewScreen();
    }

    return _buildUploadScreen();
  }

  Widget _buildUploadScreen() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: 0.1),
            cs.surface,
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 40),
              _buildUploadOptions(),
              const Spacer(),
              _buildTipsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.inventory, size: 50, color: cs.primary),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Smart Stock Entry',
          style: AppTextStyles.h4,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Upload up to $MAX_PHOTOS photos of receipts\nAI will automatically create stock entries',
          style: AppTextStyles.bodyMedium.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildUploadOptions() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildUploadCard(
          icon: Icons.camera_alt,
          title: 'Take Photos',
          subtitle: 'Capture up to $MAX_PHOTOS receipts',
          color: cs.primary,
          onTap: _captureMultiplePhotos,
        ),
        const SizedBox(height: 16),
        _buildUploadCard(
          icon: Icons.photo_library,
          title: 'Choose from Gallery',
          subtitle: 'Select multiple receipt images',
          color: AppColors.info,
          onTap: _selectMultipleFromGallery,
        ),
      ],
    );
  }

  Widget _buildUploadCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                'Automatic Stock Creation',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTip('• Upload multiple receipt photos at once'),
          _buildTip('• AI extracts products automatically'),
          _buildTip('• Stock quantities added instantly'),
          _buildTip('• No manual data entry required'),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildPhotoPreviewScreen() {
    return Column(
      children: [
        // Preview grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedImages.length + (_selectedImages.length < MAX_PHOTOS ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < _selectedImages.length) {
                return _buildPhotoThumbnail(_selectedImages[index], index);
              } else {
                return _buildAddMoreButton();
              }
            },
          ),
        ),

        // Action bar
        Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''} selected (max $MAX_PHOTOS)',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      text: 'Cancel',
                      onPressed: _clearAllPhotos,
                      backgroundColor: AppColors.neutral,
                      textColor: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      text: 'Process & Add Stock',
                      onPressed: _processAllPhotos,
                      icon: Icons.auto_awesome,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoThumbnail(File imageFile, int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            imageFile,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: () => _removePhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddMoreButton() {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _addMorePhotos,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate, color: cs.primary, size: 32),
            const SizedBox(height: 4),
            Text(
              'Add More',
              style: AppTextStyles.bodySmall.copyWith(color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.primary.withValues(alpha: 0.1),
            cs.surface,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated icon
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.2),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.auto_awesome, size: 60, color: cs.primary),
                            AnimatedBuilder(
                              animation: _scanAnimation,
                              builder: (context, child) {
                                return Transform.rotate(
                                  angle: _scanAnimation.value * 2 * 3.14159,
                                  child: Container(
                                    width: 100,
                                    height: 2,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          cs.primary,
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Main status
                    Text(
                      _processingStatus.isEmpty ? 'Processing...' : _processingStatus,
                      style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),

                    // Sub-status
                    if (_processingSubStatus.isNotEmpty)
                      Text(
                        _processingSubStatus,
                        style: AppTextStyles.bodyMedium.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 24),

                    // Progress bar
                    Container(
                      width: 250,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppColors.neutral,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          width: 250 * _processingProgress,
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                cs.primary,
                                cs.primary.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Progress percentage
                    Text(
                      '${(_processingProgress * 100).toInt()}%',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats container
            Container(
              padding: const EdgeInsets.all(20),
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildStatRow('Photos', '$_currentPhotoIndex / ${_selectedImages.length}', cs.primary),
                  const Divider(height: 16),
                  _buildStatRow('Items Found', '$_totalItemsProcessed', AppColors.info),
                  const Divider(height: 16),
                  _buildStatRow('Added to Stock', '$_totalItemsAdded', AppColors.success),
                  if (_totalItemsFailed > 0) ...[
                    const Divider(height: 16),
                    _buildStatRow('Failed', '$_totalItemsFailed', AppColors.error),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  // Actions

  Future<void> _captureMultiplePhotos() async {
    for (int i = _selectedImages.length; i < MAX_PHOTOS; i++) {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (photo != null) {
        setState(() {
          _selectedImages.add(File(photo.path));
        });

        if (_selectedImages.length < MAX_PHOTOS) {
          final shouldContinue = await _showContinueCaptureDialog();
          if (!shouldContinue) break;
        } else {
          SnackbarHelper.showInfo(context, 'Maximum $MAX_PHOTOS photos reached');
          break;
        }
      } else {
        break;
      }
    }
  }

  Future<void> _selectMultipleFromGallery() async {
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 90,
      maxWidth: 1920,
    );

    if (images.isNotEmpty) {
      setState(() {
        final remainingSlots = MAX_PHOTOS - _selectedImages.length;
        final imagesToAdd = images.take(remainingSlots).toList();
        _selectedImages.addAll(imagesToAdd.map((xFile) => File(xFile.path)));

        if (images.length > remainingSlots) {
          SnackbarHelper.showWarning(
            context,
            'Added ${imagesToAdd.length} photos (max $MAX_PHOTOS)',
          );
        }
      });
    }
  }

  Future<void> _addMorePhotos() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add More Photos'),
        content: const Text('How would you like to add more photos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'camera'),
            child: const Text('Camera'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'gallery'),
            child: const Text('Gallery'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice == 'camera') {
      await _captureMultiplePhotos();
    } else if (choice == 'gallery') {
      await _selectMultipleFromGallery();
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _clearAllPhotos() {
    setState(() {
      _selectedImages.clear();
    });
  }

  Future<bool> _showContinueCaptureDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Continue Capturing?'),
        content: Text('You have ${_selectedImages.length} photo${_selectedImages.length > 1 ? 's' : ''}. Capture another?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Done'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Capture More'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _processAllPhotos() async {
    if (_selectedImages.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _currentPhotoIndex = 0;
      _totalItemsProcessed = 0;
      _totalItemsAdded = 0;
      _totalItemsFailed = 0;
      _processedResults = [];
      _processingProgress = 0.0;
    });

    try {
      final ocrService = ref.read(ocrServiceProvider);
      final apiService = ref.read(apiServiceProvider);

      for (int i = 0; i < _selectedImages.length; i++) {
        setState(() {
          _currentPhotoIndex = i + 1;
          _processingStatus = 'Processing Photo ${i + 1} of ${_selectedImages.length}';
          _processingSubStatus = 'Preparing image...';
          _processingProgress = (i / _selectedImages.length) * 0.9;
        });

        try {
          // Compress image
          final compressedBytes = await _compressImage(_selectedImages[i]);
          final base64Image = base64Encode(compressedBytes);

          setState(() {
            _processingSubStatus = 'Uploading and extracting...';
          });

          // Create OCR session
          final session = await ocrService.createOCRSession(
            imageData: base64Image,
            imageType: 'jpeg',
            sessionType: 'quick_sale',
            shopId: widget.shopId,
          );

          // Poll for completion
          final response = await _pollForCompletion(ocrService, session.id, i);

          if (response != null && response.extractedItems.isNotEmpty) {
            setState(() {
              _processingSubStatus = 'Adding ${response.extractedItems.length} items to stock...';
              _totalItemsProcessed += response.extractedItems.length;
            });

            // Add items to stock
            int addedCount = await _addItemsToStock(apiService, response.extractedItems);

            setState(() {
              _totalItemsAdded += addedCount;
              _totalItemsFailed += (response.extractedItems.length - addedCount);
            });

            _processedResults.add({
              'photo_index': i + 1,
              'items_found': response.extractedItems.length,
              'items_added': addedCount,
              'items_failed': response.extractedItems.length - addedCount,
            });
          }

        } catch (e) {
          AppLogger.error('Failed to process photo ${i + 1}', e);
          _processedResults.add({
            'photo_index': i + 1,
            'error': e.toString(),
          });
        }
      }

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = 'Complete!';
        _processingSubStatus = 'Added $_totalItemsAdded items to stock';
      });

      // Show results
      await Future.delayed(const Duration(seconds: 2));
      _showCompletionDialog();

    } catch (e) {
      AppLogger.error('Multi-photo processing failed', e);
      SnackbarHelper.showError(context, 'Processing failed: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<Uint8List> _compressImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    const maxDimension = 1920;
    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        image = img.copyResize(image, width: maxDimension);
      } else {
        image = img.copyResize(image, height: maxDimension);
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 85));
  }

  Future<OCRSessionResponse?> _pollForCompletion(
    dynamic ocrProvider,
    String sessionId,
    int photoIndex,
  ) async {
    int attempts = 0;
    const maxAttempts = 30;

    while (attempts < maxAttempts) {
      await Future.delayed(const Duration(seconds: 1));

      try {
        final response = await ocrProvider.getOCRSession(sessionId);

        if (response.session.status == 'completed') {
          return response;
        } else if (response.session.status == 'failed') {
          throw Exception(response.session.errorMessage ?? 'Processing failed');
        }

        attempts++;
      } catch (e) {
        if (attempts >= maxAttempts - 1) {
          throw Exception('Processing timeout for photo ${photoIndex + 1}');
        }
      }
    }

    throw Exception('Timeout processing photo ${photoIndex + 1}');
  }

  Future<int> _addItemsToStock(DioApiService apiService, List<OCRExtractedItem> items) async {
    int successCount = 0;

    for (final item in items) {
      if (item.matchedProductId == null) {
        AppLogger.warning('Skipping unmatched item: ${item.extractedText}');
        continue;
      }

      try {
        final quantity = item.parsedQuantity ?? 1;

        AppLogger.info('Adding item to stock: ${item.extractedText} (qty: $quantity)');

        // Add stock via API using DioApiService
        final response = await apiService.post(
          '/api/inventory/stock/adjust',
          body: {
            'product_id': item.matchedProductId,
            'shop_id': widget.shopId,
            'quantity_change': quantity,
            'adjustment_type': 'purchase',
            'notes': 'Auto-added via OCR from receipt (${item.extractedText})',
          },
        );

        if (response.success) {
          successCount++;
          AppLogger.info('✅ Added $quantity units of product ${item.matchedProductId} to stock');
        } else {
          AppLogger.error('❌ Failed to add stock: ${response.message}');
        }
      } catch (e, stackTrace) {
        AppLogger.error('Failed to add item to stock: ${item.extractedText}', e, stackTrace);
      }
    }

    return successCount;
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 28),
            const SizedBox(width: 12),
            const Text('Processing Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildResultRow('Photos Processed', '${_selectedImages.length}', Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            _buildResultRow('Items Found', '$_totalItemsProcessed', AppColors.info),
            const SizedBox(height: 8),
            _buildResultRow('Added to Stock', '$_totalItemsAdded', AppColors.success),
            if (_totalItemsFailed > 0) ...[
              const SizedBox(height: 8),
              _buildResultRow('Failed', '$_totalItemsFailed', AppColors.error),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context, {
                'photos_processed': _selectedImages.length,
                'items_added': _totalItemsAdded,
                'items_failed': _totalItemsFailed,
              }); // Return to previous screen
            },
            child: const Text('Done'),
          ),
          if (_totalItemsAdded > 0)
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _clearAllPhotos(); // Clear photos for another batch
              },
              child: const Text('Process More'),
            ),
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How It Works'),
        content: SingleChildScrollView(
          child: Text(
            '1. Upload up to $MAX_PHOTOS receipt photos\n\n'
            '2. AI automatically extracts product information\n\n'
            '3. Stock quantities are added automatically\n\n'
            '4. No manual entry required!\n\n'
            'Tips:\n'
            '• Good lighting improves accuracy\n'
            '• Keep receipts flat and clear\n'
            '• Process multiple receipts at once\n'
            '• Matched products are added instantly',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

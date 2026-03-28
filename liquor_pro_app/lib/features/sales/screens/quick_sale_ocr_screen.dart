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
import '../providers/ocr_provider.dart';
import '../models/ocr_models.dart';
import '../widgets/ocr_item_review_card.dart';
import '../widgets/receipt_preview_widget.dart';

/// Quick Sale OCR Screen - Automated receipt scanning for sales entry
class QuickSaleOCRScreen extends ConsumerStatefulWidget {
  final String shopId;

  const QuickSaleOCRScreen({super.key, required this.shopId});

  @override
  ConsumerState<QuickSaleOCRScreen> createState() => _QuickSaleOCRScreenState();
}

class _QuickSaleOCRScreenState extends ConsumerState<QuickSaleOCRScreen>
    with TickerProviderStateMixin {

  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  bool _isProcessing = false;
  OCRSession? _currentSession;
  List<OCRExtractedItem> _extractedItems = [];

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

    // Initialize animations
    _scanAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scanAnimationController,
      curve: Curves.linear,
    ));

    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseAnimationController,
      curve: Curves.easeInOut,
    ));
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
        title: Text('Quick Sale', style: AppTextStyles.h5),
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
      return _buildEnhancedProcessingOverlay();
    }

    if (_extractedItems.isNotEmpty) {
      return _buildReviewScreen();
    }

    if (_selectedImage != null) {
      return _buildImagePreview();
    }

    return _buildCaptureScreen();
  }

  /// Build enhanced processing overlay with detailed progress
  Widget _buildEnhancedProcessingOverlay() {
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
                      Icon(
                        Icons.document_scanner,
                        size: 60,
                        color: cs.primary,
                      ),
                      // Rotating scanner line
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

              // Status text
              Text(
                _processingStatus.isEmpty ? 'Processing...' : _processingStatus,
                style: AppTextStyles.h5.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),

              // Sub-status text
              if (_processingSubStatus.isNotEmpty)
                Text(
                  _processingSubStatus,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
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

              const SizedBox(height: 40),

              // Cancel button
              TextButton(
                onPressed: _cancelProcessing,
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the initial capture screen
  Widget _buildCaptureScreen() {
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
              _buildCaptureOptions(),
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.receipt_long,
              size: 40,
              color: cs.primary,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Scan Receipt for Quick Sale',
          style: AppTextStyles.h4,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Take a photo of your purchase receipt\nto automatically fill product details',
          style: AppTextStyles.bodyMedium.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCaptureOptions() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        _buildCaptureCard(
          icon: Icons.camera_alt,
          title: 'Take Photo',
          subtitle: 'Use camera to capture receipt',
          color: cs.primary,
          onTap: _captureFromCamera,
        ),
        const SizedBox(height: 16),
        _buildCaptureCard(
          icon: Icons.photo_library,
          title: 'Choose from Gallery',
          subtitle: 'Select existing receipt image',
          color: AppColors.info,
          onTap: _selectFromGallery,
        ),
      ],
    );
  }

  Widget _buildCaptureCard({
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
          border: Border.all(
            color: color.withValues(alpha: 0.2),
            width: 1,
          ),
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
                    style: AppTextStyles.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.info.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppColors.info,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Tips for Best Results',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTip('• Ensure good lighting'),
          _buildTip('• Keep receipt flat and straight'),
          _buildTip('• Include all product items in frame'),
          _buildTip('• Avoid shadows and reflections'),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Build image preview screen
  Widget _buildImagePreview() {
    return Stack(
      children: [
        // Image preview
        ReceiptPreviewWidget(
          imageFile: _selectedImage!,
          onRetake: _resetImage,
        ),

        // Bottom action bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    text: 'Retake',
                    onPressed: _resetImage,
                    backgroundColor: AppColors.neutral,
                    textColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: PrimaryButton(
                    text: 'Process Receipt',
                    onPressed: _processImage,
                    icon: Icons.auto_awesome,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Build review screen for extracted items
  Widget _buildReviewScreen() {
    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extraction Complete',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_extractedItems.length} items found',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _resetImage,
                child: const Text('Scan Another'),
              ),
            ],
          ),
        ),

        // Extracted items list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _extractedItems.length,
            itemBuilder: (context, index) {
              return OCRItemReviewCard(
                item: _extractedItems[index],
                onConfirm: () => _confirmItem(index),
                onEdit: () => _editItem(index),
                onReject: () => _rejectItem(index),
              );
            },
          ),
        ),

        // Action buttons
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
              // Stats row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatChip(
                    'Matched',
                    _extractedItems.where((i) => i.matchedProductId != null).length,
                    AppColors.success,
                  ),
                  _buildStatChip(
                    'Unmatched',
                    _extractedItems.where((i) => i.matchedProductId == null).length,
                    AppColors.warning,
                  ),
                  _buildStatChip(
                    'Total',
                    _extractedItems.length,
                    Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      text: 'Cancel',
                      onPressed: () => Navigator.pop(context),
                      backgroundColor: AppColors.neutral,
                      textColor: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      text: 'Create Sale',
                      onPressed: _createSale,
                      icon: Icons.point_of_sale,
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

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: AppTextStyles.h6.copyWith(color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  // Action methods

  Future<void> _captureFromCamera() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (photo != null) {
      setState(() {
        _selectedImage = File(photo.path);
      });
    }
  }

  Future<void> _selectFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  void _resetImage() {
    setState(() {
      _selectedImage = null;
      _extractedItems = [];
      _currentSession = null;
      _isProcessing = false;
    });
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Preparing image...';
      _processingProgress = 0.1;
      _processingSubStatus = 'Optimizing for OCR';
    });

    try {
      // Compress image before sending
      AppLogger.info('Compressing image for OCR...');
      final compressedBytes = await _compressImage(_selectedImage!);

      // Log compression results
      final originalSize = await _selectedImage!.length();
      final compressedSize = compressedBytes.length;
      final compressionRatio = ((originalSize - compressedSize) / originalSize * 100).toStringAsFixed(1);
      AppLogger.info('Image compressed: ${originalSize ~/ 1024}KB -> ${compressedSize ~/ 1024}KB ($compressionRatio% reduction)');

      setState(() {
        _processingStatus = 'Uploading image...';
        _processingProgress = 0.25;
        _processingSubStatus = 'Size: ${compressedSize ~/ 1024}KB';
      });

      // Convert to base64
      final base64Image = base64Encode(compressedBytes);

      // Create OCR session
      final ocrProvider = ref.read(ocrServiceProvider);
      final session = await ocrProvider.createOCRSession(
        imageData: base64Image,
        imageType: 'jpeg',
        sessionType: 'quick_sale',
        shopId: widget.shopId,
      );

      setState(() {
        _currentSession = session;
        _processingStatus = 'Processing receipt...';
        _processingProgress = 0.4;
        _processingSubStatus = 'Extracting text from image';
      });

      // Poll for processing completion
      await _pollForCompletion(session.id);

    } catch (e) {
      AppLogger.error('OCR processing failed', e);
      SnackbarHelper.showError(context, 'Failed to process image: $e');
      setState(() {
        _isProcessing = false;
        _processingStatus = '';
        _processingProgress = 0.0;
        _processingSubStatus = '';
      });
    }
  }

  /// Compress image to reduce size before OCR processing
  Future<Uint8List> _compressImage(File imageFile) async {
    // Read image bytes
    final bytes = await imageFile.readAsBytes();

    // Decode image
    img.Image? image = img.decodeImage(bytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Calculate new dimensions (max 1920px on longest side)
    const maxDimension = 1920;
    int newWidth = image.width;
    int newHeight = image.height;

    if (image.width > maxDimension || image.height > maxDimension) {
      if (image.width > image.height) {
        newWidth = maxDimension;
        newHeight = (image.height * maxDimension / image.width).round();
      } else {
        newHeight = maxDimension;
        newWidth = (image.width * maxDimension / image.height).round();
      }

      // Resize image
      image = img.copyResize(image, width: newWidth, height: newHeight);
      AppLogger.info('Image resized: ${image.width}x${image.height}');
    }

    // Encode as JPEG with 85% quality
    final compressedBytes = img.encodeJpg(image, quality: 85);

    return Uint8List.fromList(compressedBytes);
  }

  Future<void> _pollForCompletion(String sessionId) async {
    int attempts = 0;
    const maxAttempts = 30; // 30 seconds timeout
    bool isCancelled = false;

    while (attempts < maxAttempts && !isCancelled) {
      await Future.delayed(const Duration(seconds: 1));

      // Check if cancelled
      if (!_isProcessing) {
        isCancelled = true;
        break;
      }

      try {
        final ocrProvider = ref.read(ocrServiceProvider);
        final response = await ocrProvider.getOCRSession(sessionId);

        // Update progress based on attempts
        final progress = 0.4 + (attempts / maxAttempts * 0.5);
        setState(() {
          _processingProgress = progress.clamp(0.4, 0.9);

          // Update status messages
          if (attempts < 5) {
            _processingStatus = 'Extracting text...';
            _processingSubStatus = 'Reading receipt content';
          } else if (attempts < 10) {
            _processingStatus = 'Identifying products...';
            _processingSubStatus = 'Matching with inventory';
          } else if (attempts < 15) {
            _processingStatus = 'Analyzing quantities...';
            _processingSubStatus = 'Processing ${attempts * 3}%';
          } else {
            _processingStatus = 'Finalizing results...';
            _processingSubStatus = 'Almost ready';
          }
        });

        if (response.session.status == 'completed') {
          setState(() {
            _processingProgress = 1.0;
            _processingStatus = 'Success!';
            _processingSubStatus = 'Found ${response.extractedItems.length} items';
          });

          // Brief delay to show success
          await Future.delayed(const Duration(milliseconds: 500));

          setState(() {
            _extractedItems = response.extractedItems;
            _isProcessing = false;
            _processingStatus = '';
            _processingProgress = 0.0;
            _processingSubStatus = '';
          });

          // Show success message
          if (mounted) {
            SnackbarHelper.showSuccess(
              context,
              'Found ${response.extractedItems.length} items',
            );
          }
          return;
        } else if (response.session.status == 'failed') {
          throw Exception(response.session.errorMessage ?? 'Processing failed');
        }

        attempts++;
      } catch (e) {
        if (attempts >= maxAttempts - 1) {
          throw Exception('Processing timeout');
        }
      }
    }

    if (isCancelled) {
      AppLogger.info('OCR processing cancelled by user');
    } else {
      throw Exception('Processing timeout');
    }
  }

  void _cancelProcessing() {
    setState(() {
      _isProcessing = false;
      _processingStatus = '';
      _processingProgress = 0.0;
      _processingSubStatus = '';
    });

    AppLogger.info('User cancelled OCR processing');
    SnackbarHelper.showInfo(context, 'Processing cancelled');
  }

  void _confirmItem(int index) {
    setState(() {
      _extractedItems[index] = _extractedItems[index].copyWith(
        isConfirmed: true,
      );
    });
  }

  void _editItem(int index) {
    // Show edit dialog
    _showEditItemDialog(index);
  }

  void _rejectItem(int index) {
    setState(() {
      _extractedItems[index] = _extractedItems[index].copyWith(
        isRejected: true,
      );
    });
  }

  Future<void> _createSale() async {
    // Filter confirmed items
    final confirmedItems = _extractedItems
        .where((item) => item.isConfirmed && !item.isRejected)
        .toList();

    if (confirmedItems.isEmpty) {
      SnackbarHelper.showError(context, 'No items confirmed');
      return;
    }

    try {
      // Convert OCRExtractedItem to OCRItemConfirmation
      final confirmations = confirmedItems.map((item) => OCRItemConfirmation(
        itemId: item.id,
        isConfirmed: true,
        productId: item.userCorrectedProductId ?? item.matchedProductId,
        quantity: item.userCorrectedQuantity ?? item.parsedQuantity ?? 1,
      )).toList();

      // Confirm items with backend
      final ocrProvider = ref.read(ocrServiceProvider);
      await ocrProvider.confirmOCRItems(
        sessionId: _currentSession!.id,
        items: confirmations,
      );

      // Create sale
      final sale = await ocrProvider.createQuickSaleFromOCR(
        sessionId: _currentSession!.id,
        paymentMethod: 'cash',
      );

      // Show success and navigate
      if (mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Sale created successfully!',
        );
        Navigator.pop(context, sale);
      }
    } catch (e) {
      SnackbarHelper.showError(context, 'Failed to create sale: $e');
    }
  }

  String _getProcessingMessage() {
    final messages = [
      'Analyzing receipt...',
      'Extracting text...',
      'Identifying products...',
      'Matching with inventory...',
      'Almost done...',
    ];

    // Cycle through messages based on time
    final index = (DateTime.now().second ~/ 3) % messages.length;
    return messages[index];
  }

  void _showEditItemDialog(int index) {
    // Implementation for edit dialog
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit Item', style: AppTextStyles.h5),
                const SizedBox(height: 20),
                // Add edit form fields here
                Text('Edit functionality coming soon...'),
                const SizedBox(height: 20),
                PrimaryButton(
                  text: 'Save',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('How Quick Sale Works'),
          content: const SingleChildScrollView(
            child: Text(
              '1. Take a clear photo of your purchase receipt\n\n'
              '2. Our AI will automatically extract product information\n\n'
              '3. Review and confirm the extracted items\n\n'
              '4. Make corrections if needed\n\n'
              '5. Create sale with a single tap\n\n'
              'Tips:\n'
              '• Ensure good lighting for better accuracy\n'
              '• Keep receipt flat and avoid shadows\n'
              '• Include all items in the frame',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }
}
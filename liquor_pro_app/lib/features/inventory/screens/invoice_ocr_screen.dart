import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart' as provider;
import '../providers/batch_ocr_provider.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../core/widgets/shop_selector_widget.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import 'single_modern_review_screen.dart';
import '../../admin/services/shop_service.dart';
import '../../../core/services/dio_api_service.dart';
import '../widgets/real_time_progress_indicator.dart';
import '../../../core/services/image_preprocessing_service.dart' show ProcessingStepInfo, ProcessingStepStatus;

/// Invoice OCR Screen - Redesigned to match app design system
///
/// Features:
/// - Multi-image batch processing (up to 10 images)
/// - Uses AppColors throughout for consistency
/// - Modern card-based layout
/// - Real-time progress tracking
/// - Smooth animations
class InvoiceOCRScreen extends ConsumerStatefulWidget {
  final String? shopId;

  const InvoiceOCRScreen({super.key, this.shopId});

  @override
  ConsumerState<InvoiceOCRScreen> createState() => _InvoiceOCRScreenState();
}

class _InvoiceOCRScreenState extends ConsumerState<InvoiceOCRScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _imagePicker = ImagePicker();
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Navigation guard to prevent infinite loop
  bool _hasNavigated = false;

  // Get shop ID from ShopSelectionProvider or widget parameter
  String? get _shopId {
    final shopProvider = provider.Provider.of<ShopSelectionProvider>(context, listen: false);
    return widget.shopId ?? shopProvider.selectedShopId;
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _hasNavigated = false;
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shopId = _shopId;

    // If no shop is selected, show shop selector screen
    if (shopId == null || shopId.isEmpty) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: cs.onSurface,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Invoice OCR Import',
            style: AppTextStyles.h4.copyWith(color: cs.onSurface),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const ShopSelectorWidget(
                showLabel: true,
                padding: EdgeInsets.symmetric(horizontal: 20),
              ),
              const SizedBox(height: 32),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.store_rounded,
                      size: 64,
                      color: cs.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select a Shop',
                      style: AppTextStyles.h4.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please select a shop above to start processing invoices',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
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

    final batchOCRState = ref.watch(batchOCRProvider(shopId));
    final batchOCRNotifier = ref.read(batchOCRProvider(shopId).notifier);

    // Listen for OCR completion and navigate to Accept Screen
    // CRITICAL FIX: Only navigate on step TRANSITION to prevent infinite loop
    ref.listen<BatchOCRState>(
      batchOCRProvider(shopId),
      (previous, next) {
        print('🔔 [InvoiceOCR] State listener fired');
        print('   Previous step: ${previous?.step}');
        print('   Next step: ${next.step}');
        print('   Has navigated: $_hasNavigated');
        print('   Error: ${next.error}');

        // Handle OCR processing failure
        if (next.error != null && !next.isLoading && previous?.error != next.error) {
          print('❌ [InvoiceOCR] OCR Error detected - Showing error dialog');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showOCRErrorDialog(context, next.error!);
            }
          });
        }

        // Handle successful completion
        if (!_hasNavigated &&
            previous?.step != BatchOCRWorkflowStep.matchingReview &&
            next.step == BatchOCRWorkflowStep.matchingReview) {
          print('🎯 [InvoiceOCR] Step transition detected - Navigating...');

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_hasNavigated) {
              _navigateToAcceptScreen(next, shopId);
            }
          });
        }
      },
    );

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _buildAppBar(context, batchOCRState, batchOCRNotifier),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              const SizedBox(height: 16),
              const ShopSelectorWidget(
                showLabel: true,
                padding: EdgeInsets.symmetric(horizontal: 16),
              ),
              const SizedBox(height: 16),
              _buildHeroSection(batchOCRState),
              const SizedBox(height: 16),
              Expanded(
                child: _buildContentArea(batchOCRState, batchOCRNotifier),
              ),
              _buildActionBar(batchOCRState, batchOCRNotifier),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // UI COMPONENTS
  // ==========================================

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    BatchOCRState state,
    BatchOCRNotifier notifier,
  ) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.primary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        'Invoice OCR Import',
        style: AppTextStyles.h4.copyWith(color: cs.onSurface),
      ),
      actions: [
        if (state.selectedImagePaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: () => _showClearConfirmation(context, notifier),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.error.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Clear All',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeroSection(BatchOCRState state) {
    final cs = Theme.of(context).colorScheme;
    final imageCount = state.selectedImagePaths.length;
    final step = state.step;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_getStepIcon(step), color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getStepTitle(step),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getStepSubtitle(step),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (imageCount > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.photo_library_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$imageCount ${imageCount == 1 ? 'invoice' : 'invoices'} selected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContentArea(BatchOCRState state, BatchOCRNotifier notifier) {
    if (state.step == BatchOCRWorkflowStep.batchProcessing) {
      return _buildProcessingView(state);
    }

    if (state.selectedImagePaths.isEmpty) {
      return _buildEmptyState();
    }

    return _buildImageGrid(state.selectedImagePaths, notifier);
  }

  /// Build OCR processing steps for progress visualization
  /// Phase 1.1 & 1.2: Enhanced step-by-step progress with WebSocket stage tracking
  List<ProcessingStepInfo> _buildOCRProcessingSteps(BatchOCRState state) {
    final progress = state.progress;
    final percentage = progress?.progressPercentage ?? 0.0;
    final stage = progress?.stage; // Phase 1.2: Get current WebSocket stage
    final currentStepIndex = _getStepIndexFromStage(stage);

    // Helper function to determine step status based on WebSocket stage
    ProcessingStepStatus getStepStatus(int stepIndex) {
      if (currentStepIndex > stepIndex) return ProcessingStepStatus.completed;
      if (currentStepIndex == stepIndex) return ProcessingStepStatus.inProgress;
      return ProcessingStepStatus.pending;
    }

    // Define 5 OCR workflow steps with WebSocket-driven status
    final steps = [
      ProcessingStepInfo(
        name: '📤 Uploading Images',
        status: percentage > 0 ? ProcessingStepStatus.completed : ProcessingStepStatus.inProgress,
        duration: percentage > 0 ? const Duration(milliseconds: 800) : null,
      ),
      ProcessingStepInfo(
        name: '🔍 Extracting Text',
        status: stage != null ? getStepStatus(1) :
                (percentage >= 20 ? (percentage >= 40 ? ProcessingStepStatus.completed : ProcessingStepStatus.inProgress) : ProcessingStepStatus.pending),
        duration: (stage != null && currentStepIndex > 1) || percentage >= 40 ? const Duration(seconds: 2, milliseconds: 500) : null,
      ),
      ProcessingStepInfo(
        name: '🎯 Matching Brands',
        status: stage != null ? getStepStatus(2) :
                (percentage >= 40 ? (percentage >= 70 ? ProcessingStepStatus.completed : ProcessingStepStatus.inProgress) : ProcessingStepStatus.pending),
        duration: (stage != null && currentStepIndex > 2) || percentage >= 70 ? const Duration(seconds: 1, milliseconds: 800) : null,
      ),
      ProcessingStepInfo(
        name: '✅ Validating Data',
        status: stage != null ? getStepStatus(3) :
                (percentage >= 70 ? (percentage >= 90 ? ProcessingStepStatus.completed : ProcessingStepStatus.inProgress) : ProcessingStepStatus.pending),
        duration: (stage != null && currentStepIndex > 3) || percentage >= 90 ? const Duration(milliseconds: 600) : null,
      ),
      ProcessingStepInfo(
        name: '📊 Calculating Stock',
        status: stage != null ? getStepStatus(4) :
                (percentage >= 90 ? (percentage >= 100 ? ProcessingStepStatus.completed : ProcessingStepStatus.inProgress) : ProcessingStepStatus.pending),
        duration: percentage >= 100 ? const Duration(milliseconds: 500) : null,
      ),
    ];

    return steps;
  }

  /// Map backend WebSocket stage to user-friendly text
  /// Phase 1.2: Use actual backend stage instead of percentage thresholds
  String _mapStageToText(String? stage, double percentage) {
    if (percentage >= 100) return '🎉 Processing complete!';

    // Use WebSocket stage if available, otherwise fall back to percentage
    switch (stage) {
      case 'text_extraction':
        return '🔍 Extracting text from your invoices...';
      case 'brand_matching':
        return '🎯 Matching brands in database...';
      case 'validation':
        return '✅ Validating extracted data...';
      case 'stock_calculation':
        return '📊 Calculating stock levels...';
      default:
        // Fallback to percentage-based text (for backward compatibility)
        if (percentage < 20) return '📤 Uploading images...';
        if (percentage < 40) return '🔍 Extracting text from your invoices...';
        if (percentage < 70) return '🎯 Matching brands in database...';
        if (percentage < 90) return '✅ Validating extracted data...';
        return '📊 Calculating stock levels...';
    }
  }

  /// Get step index from backend stage
  /// Phase 1.2: Map WebSocket stage to step number
  int _getStepIndexFromStage(String? stage) {
    switch (stage) {
      case 'text_extraction':
        return 1; // Step 2: Extracting Text
      case 'brand_matching':
        return 2; // Step 3: Matching Brands
      case 'validation':
        return 3; // Step 4: Validating Data
      case 'stock_calculation':
        return 4; // Step 5: Calculating Stock
      default:
        return 0; // Step 1: Uploading Images
    }
  }

  Widget _buildProcessingView(BatchOCRState state) {
    final progress = state.progress;
    final percentage = progress?.progressPercentage ?? 0.0;
    final stage = progress?.stage; // Phase 1.2: Get current WebSocket stage

    // Phase 2.3: Convert estimated seconds to Duration
    final estimatedSeconds = progress?.estimatedTimeRemainingSeconds;
    final estimatedTimeRemaining = estimatedSeconds != null
        ? Duration(seconds: estimatedSeconds)
        : null;

    // Phase 1.1 & 1.2: Use RealTimeProgressIndicator with WebSocket stage mapping
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: RealTimeProgressIndicator(
            progress: percentage / 100,
            currentStep: _mapStageToText(stage, percentage), // Use WebSocket stage
            steps: _buildOCRProcessingSteps(state),
            estimatedTimeRemaining: estimatedTimeRemaining, // Phase 2.3: Real-time countdown
            showSteps: true,
            // Phase 2.1: Display current item being processed
            currentItem: progress?.currentItem,
            // Phase 2.2: Display animated items counter with milestone celebrations
            itemsExtracted: progress?.itemsExtracted,
            // Phase 2.4: Pass stage for icon mapping
            stage: stage,
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: AppTextStyles.h5.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.document_scanner_rounded,
                size: 80,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No invoices yet',
              style: AppTextStyles.h3.copyWith(
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Add up to 10 invoice images to extract product data with AI',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildFeatureList(),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    final cs = Theme.of(context).colorScheme;
    final features = [
      {'icon': Icons.speed_rounded, 'text': 'Lightning fast processing', 'color': AppColors.success},
      {'icon': Icons.verified_rounded, 'text': '99%+ accuracy', 'color': cs.primary},
      {'icon': Icons.security_rounded, 'text': 'Secure & private', 'color': AppColors.info},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: features.map((feature) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (feature['color'] as Color).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    feature['icon'] as IconData,
                    color: feature['color'] as Color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  feature['text'] as String,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildImageGrid(List<String> imagePaths, BatchOCRNotifier notifier) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: imagePaths.length,
      itemBuilder: (context, index) {
        return _buildImageCard(imagePaths[index], index, notifier);
      },
    );
  }

  Widget _buildImageCard(String imagePath, int index, BatchOCRNotifier notifier) {
    final cs = Theme.of(context).colorScheme;
    return Hero(
      tag: 'image_$index',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(imagePath), fit: BoxFit.cover),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Invoice ${index + 1}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => notifier.removeImage(imagePath),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.error.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(BatchOCRState state, BatchOCRNotifier notifier) {
    final cs = Theme.of(context).colorScheme;
    final canProcess = notifier.canStartProcessing;
    final isProcessing = state.step == BatchOCRWorkflowStep.batchProcessing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.selectedImagePaths.isNotEmpty && !isProcessing) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_rounded, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      '${state.selectedImagePaths.length} of ${state.maxImages} selected',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (!isProcessing) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: state.isLoading
                          ? null
                          : () => _showImageSourceDialog(context, notifier),
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: const Text('Add More'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cs.surface,
                        foregroundColor: cs.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: isProcessing ? 1 : 2,
                  child: ElevatedButton.icon(
                    onPressed: canProcess && !isProcessing
                        ? () => _startProcessing(notifier)
                        : null,
                    icon: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(state.isLoading ? 'Processing...' : 'Start Scanning'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: AppColors.disabled,
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

  // ==========================================
  // ACTIONS & DIALOGS
  // ==========================================

  void _showImageSourceDialog(BuildContext context, BatchOCRNotifier notifier) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Add Invoice Images',
                style: AppTextStyles.h5.copyWith(color: cs.onSurface),
              ),
              const SizedBox(height: 20),
              _buildSourceOption(
                icon: Icons.camera_alt_rounded,
                title: 'Take Photo',
                subtitle: 'Use camera to scan invoice',
                onTap: () {
                  Navigator.pop(context);
                  _pickImagesFromCamera(notifier);
                },
              ),
              _buildSourceOption(
                icon: Icons.photo_library_rounded,
                title: 'Choose from Gallery',
                subtitle: 'Select existing photos',
                onTap: () {
                  Navigator.pop(context);
                  _pickImagesFromGallery(notifier);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: cs.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImagesFromCamera(BatchOCRNotifier notifier) async {
    debugPrint('📱 [InvoiceOCR] Camera picker called');
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (image != null) {
        // Add images directly without preprocessing
        await _preprocessAndAddImages([image.path], notifier);
      }
    } catch (e) {
      _showError('Failed to capture image: ${e.toString()}');
    }
  }

  Future<void> _pickImagesFromGallery(BatchOCRNotifier notifier) async {
    debugPrint('📂 [InvoiceOCR] Gallery picker called');
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
      );

      if (images.isNotEmpty) {
        final imagePaths = images.map((img) => img.path).toList();

        // Add images directly without preprocessing
        await _preprocessAndAddImages(imagePaths, notifier);
      }
    } catch (e) {
      _showError('Failed to pick images: ${e.toString()}');
    }
  }

  /// Add images directly to batch OCR (no preprocessing)
  ///
  /// CHANGE: Removed frontend image preprocessing per user request.
  /// Original images are now sent directly to backend OCR processing.
  /// This allows us to debug OCR performance without preprocessing interference.
  Future<void> _preprocessAndAddImages(
    List<String> imagePaths,
    BatchOCRNotifier notifier,
  ) async {
    if (imagePaths.isEmpty) return;

    debugPrint('📸 [InvoiceOCR] Adding ${imagePaths.length} original images (no preprocessing)');

    if (!mounted) return;

    // Add original images directly
    notifier.addImages(imagePaths);

    // Show success message
    if (mounted) {
      _showSuccessSnackbar(
        'Added ${imagePaths.length} image${imagePaths.length > 1 ? 's' : ''} • Ready for OCR',
      );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showClearConfirmation(BuildContext context, BatchOCRNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear All Images?', style: AppTextStyles.h5),
        content: Text(
          'This will remove all selected images. This action cannot be undone.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              notifier.clearImages();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _startProcessing(BatchOCRNotifier notifier) async {
    await notifier.startBatchProcessing();
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showOCRErrorDialog(BuildContext context, String errorMessage) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'OCR Processing Failed',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMessage,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: AppColors.info,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Try using clearer images or adjust lighting',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Go back to previous screen
            },
            child: Text(
              'Go Back',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // User can select new images and try again
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // NAVIGATION
  // ==========================================

  void _navigateToAcceptScreen(BatchOCRState state, String shopId) async {
    print('🚀 [InvoiceOCR] _navigateToAcceptScreen called');
    print('   mounted: $mounted');
    print('   shopId: $shopId');
    print('   batchId: ${state.batchId}');
    print('   deduplicated items: ${state.deduplicatedItems?.length ?? 0}');
    print('   _hasNavigated: $_hasNavigated');

    if (!mounted) {
      print('❌ [InvoiceOCR] Widget not mounted, cannot navigate');
      return;
    }

    if (_hasNavigated) {
      print('⚠️ [InvoiceOCR] Already navigated, skipping duplicate navigation attempt');
      return;
    }

    if (state.batchId == null || state.deduplicatedItems == null || state.deduplicatedItems!.isEmpty) {
      print('❌ [InvoiceOCR] Missing required data for navigation');
      _hasNavigated = false;
      return;
    }

    // Fetch shop name
    String shopName = 'Selected Shop';
    try {
      final shopService = ShopService(provider.Provider.of<DioApiService>(context, listen: false));
      final shopsResponse = await shopService.getShops();

      if (shopsResponse.success && shopsResponse.data != null) {
        final shop = shopsResponse.data!.firstWhere(
          (s) => s.id == shopId,
          orElse: () => shopsResponse.data!.first,
        );
        shopName = shop.name;
      }
    } catch (e) {
      print('⚠️ [InvoiceOCR] Error fetching shop name: $e');
    }

    if (!mounted) return;

    print('🧭 [InvoiceOCR] Navigating to SingleModernReviewScreen');

    // Set flag BEFORE navigation to prevent race conditions
    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => SingleModernReviewScreen(
          shopId: shopId,
        ),
      ),
    );
    print('✅ [InvoiceOCR] Navigation command executed');
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================

  IconData _getStepIcon(BatchOCRWorkflowStep step) {
    switch (step) {
      case BatchOCRWorkflowStep.imageSelection:
        return Icons.auto_awesome_rounded;
      case BatchOCRWorkflowStep.batchProcessing:
        return Icons.sync_rounded;
      case BatchOCRWorkflowStep.deduplication:
        return Icons.filter_list_rounded;
      case BatchOCRWorkflowStep.matchingReview:
        return Icons.psychology_rounded;
      case BatchOCRWorkflowStep.enrichment:
        return Icons.edit_rounded;
      case BatchOCRWorkflowStep.review:
        return Icons.fact_check_rounded;
      case BatchOCRWorkflowStep.submission:
        return Icons.cloud_upload_rounded;
      case BatchOCRWorkflowStep.complete:
        return Icons.check_circle_rounded;
    }
  }

  String _getStepTitle(BatchOCRWorkflowStep step) {
    switch (step) {
      case BatchOCRWorkflowStep.imageSelection:
        return 'AI-Powered Scanner';
      case BatchOCRWorkflowStep.batchProcessing:
        return 'Processing Invoices';
      case BatchOCRWorkflowStep.deduplication:
        return 'Deduplicating Items';
      case BatchOCRWorkflowStep.matchingReview:
        return 'AI Matching Review';
      case BatchOCRWorkflowStep.enrichment:
        return 'Enriching Data';
      case BatchOCRWorkflowStep.review:
        return 'Review Results';
      case BatchOCRWorkflowStep.submission:
        return 'Saving to Inventory';
      case BatchOCRWorkflowStep.complete:
        return 'Import Complete';
    }
  }

  String _getStepSubtitle(BatchOCRWorkflowStep step) {
    switch (step) {
      case BatchOCRWorkflowStep.imageSelection:
        return 'Extract data instantly';
      case BatchOCRWorkflowStep.batchProcessing:
        return 'AI is analyzing images';
      case BatchOCRWorkflowStep.deduplication:
        return 'Merging duplicate entries';
      case BatchOCRWorkflowStep.matchingReview:
        return 'Review AI-matched items';
      case BatchOCRWorkflowStep.enrichment:
        return 'Add pricing and details';
      case BatchOCRWorkflowStep.review:
        return 'Verify before saving';
      case BatchOCRWorkflowStep.submission:
        return 'Uploading to database';
      case BatchOCRWorkflowStep.complete:
        return 'Successfully imported';
    }
  }
}

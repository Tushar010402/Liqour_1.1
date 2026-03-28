import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/batch_ocr_models.dart';
import '../models/brand_creation_result.dart';
import '../services/batch_ocr_service.dart';
import '../services/batch_brand_creation_service.dart';
import '../utils/brand_name_filter.dart';
import '../utils/undo_redo_manager.dart';
import '../services/ocr_state_storage_service.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/logger.dart';

// ==========================================
// SERVICE PROVIDERS
// ==========================================

/// Global API service provider (should be overridden in main.dart)
/// This references the global DioApiService instance that's properly initialized
final apiServiceProvider = Provider<DioApiService>((ref) {
  throw UnimplementedError('apiServiceProvider must be overridden in main.dart');
});

/// Global Auth service provider (should be overridden in main.dart)
/// This references the global AuthService instance
final authServiceProvider = Provider<AuthService?>((ref) {
  // Return null by default - will be overridden if auth is available
  return null;
});

/// Batch OCR service provider
/// Uses the global API service that's already initialized with AuthService
final batchOCRServiceProvider = Provider<BatchOCRService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return BatchOCRService(apiService: apiService);
});

// ==========================================
// STATE NOTIFIER FOR BATCH OCR WORKFLOW
// ==========================================

/// State for batch OCR workflow
class BatchOCRState {
  // Current workflow step
  final BatchOCRWorkflowStep step;

  // Image selection
  final List<String> selectedImagePaths;
  final int maxImages;

  // Batch processing
  final String? batchId;
  final String? sessionId; // Session ID for state persistence
  final BatchOCRProgress? progress;

  // Deduplicated items
  final List<DeduplicatedItem>? deduplicatedItems;
  final String? receiptType; // Receipt type from OCR (e.g., "SALE RECEIPT QUATER")

  // Filtered items (garbage filtering applied)
  final List<DeduplicatedItem>? filteredDeduplicatedItems; // Clean items only
  final List<DeduplicatedItem>? filteredGarbageItems;      // Filtered garbage
  final String? filterSummary;                              // Filtering summary

  // Rejected items (brand validation filtering)
  final List<RejectedItem>? rejectedItems;                  // Items filtered by validation
  final int? totalRejected;                                 // Total rejected count
  final bool showRejectedItems;                             // Toggle to show/hide rejected items

  // Raw OCR text and statistics
  final Map<String, String>? rawTexts;                      // Complete raw OCR text per session
  final int? totalItems;                                    // Total deduplicated items
  final int? duplicatesRemoved;                             // Number of duplicates merged

  // Enrichment workflow
  final EnrichmentWorkflowState? enrichmentState;

  // Stock initialization result
  final InitializeStockResponse? initializeResult;

  // Acceptance tracking - NEW
  final Set<String> acceptedItemIds;
  final Set<String> rejectedItemIds;

  // Phase 4: Error handling & timeout
  final List<FailedImage>? failedImages;
  final ProcessingTimeout? timeout;

  // Phase 4.2: Network status
  final NetworkStatus networkStatus;
  final DateTime? lastConnectionTime;
  final int connectionRetryCount;

  // UI state
  final bool isLoading;
  final String? error;
  final String? successMessage;

  const BatchOCRState({
    this.step = BatchOCRWorkflowStep.imageSelection,
    this.selectedImagePaths = const [],
    this.maxImages = 10,
    this.batchId,
    this.sessionId,
    this.progress,
    this.deduplicatedItems,
    this.receiptType,
    this.filteredDeduplicatedItems,
    this.filteredGarbageItems,
    this.filterSummary,
    this.rejectedItems,
    this.totalRejected,
    this.showRejectedItems = false,
    this.rawTexts,
    this.totalItems,
    this.duplicatesRemoved,
    this.enrichmentState,
    this.initializeResult,
    this.acceptedItemIds = const {},
    this.rejectedItemIds = const {},
    this.failedImages,
    this.timeout,
    this.networkStatus = NetworkStatus.connected,
    this.lastConnectionTime,
    this.connectionRetryCount = 0,
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  BatchOCRState copyWith({
    BatchOCRWorkflowStep? step,
    List<String>? selectedImagePaths,
    int? maxImages,
    String? batchId,
    String? sessionId,
    BatchOCRProgress? progress,
    List<DeduplicatedItem>? deduplicatedItems,
    String? receiptType,
    List<DeduplicatedItem>? filteredDeduplicatedItems,
    List<DeduplicatedItem>? filteredGarbageItems,
    String? filterSummary,
    Map<String, String>? rawTexts,
    int? totalItems,
    int? duplicatesRemoved,
    EnrichmentWorkflowState? enrichmentState,
    InitializeStockResponse? initializeResult,
    Set<String>? acceptedItemIds,
    Set<String>? rejectedItemIds,
    List<FailedImage>? failedImages,
    ProcessingTimeout? timeout,
    NetworkStatus? networkStatus,
    DateTime? lastConnectionTime,
    int? connectionRetryCount,
    bool? isLoading,
    String? error,
    String? successMessage,
    List<RejectedItem>? rejectedItems,
    int? totalRejected,
    bool? showRejectedItems,
  }) {
    return BatchOCRState(
      step: step ?? this.step,
      selectedImagePaths: selectedImagePaths ?? this.selectedImagePaths,
      maxImages: maxImages ?? this.maxImages,
      batchId: batchId ?? this.batchId,
      sessionId: sessionId ?? this.sessionId,
      progress: progress ?? this.progress,
      deduplicatedItems: deduplicatedItems ?? this.deduplicatedItems,
      receiptType: receiptType ?? this.receiptType,
      filteredDeduplicatedItems: filteredDeduplicatedItems ?? this.filteredDeduplicatedItems,
      filteredGarbageItems: filteredGarbageItems ?? this.filteredGarbageItems,
      filterSummary: filterSummary ?? this.filterSummary,
      rawTexts: rawTexts ?? this.rawTexts,
      totalItems: totalItems ?? this.totalItems,
      duplicatesRemoved: duplicatesRemoved ?? this.duplicatesRemoved,
      enrichmentState: enrichmentState ?? this.enrichmentState,
      initializeResult: initializeResult ?? this.initializeResult,
      acceptedItemIds: acceptedItemIds ?? this.acceptedItemIds,
      rejectedItemIds: rejectedItemIds ?? this.rejectedItemIds,
      failedImages: failedImages ?? this.failedImages,
      timeout: timeout ?? this.timeout,
      networkStatus: networkStatus ?? this.networkStatus,
      lastConnectionTime: lastConnectionTime ?? this.lastConnectionTime,
      connectionRetryCount: connectionRetryCount ?? this.connectionRetryCount,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
      rejectedItems: rejectedItems ?? this.rejectedItems,
      totalRejected: totalRejected ?? this.totalRejected,
      showRejectedItems: showRejectedItems ?? this.showRejectedItems,
    );
  }

  // Clear error and success messages
  BatchOCRState clearMessages() {
    return copyWith(error: null, successMessage: null);
  }

  // ==========================================
  // ACCEPTANCE STATE HELPERS
  // ==========================================

  /// Get acceptance state for an item
  ItemAcceptanceState getAcceptanceState(String itemId) {
    if (acceptedItemIds.contains(itemId)) {
      return ItemAcceptanceState.accepted;
    } else if (rejectedItemIds.contains(itemId)) {
      return ItemAcceptanceState.rejected;
    } else {
      return ItemAcceptanceState.pending;
    }
  }

  /// Get count of accepted items
  int get acceptedCount => acceptedItemIds.length;

  /// Get count of rejected items
  int get rejectedCount => rejectedItemIds.length;

  /// Get count of pending items (neither accepted nor rejected)
  int get pendingCount {
    if (deduplicatedItems == null) return 0;
    return deduplicatedItems!.length - acceptedCount - rejectedCount;
  }

  /// Get total items count
  int get totalItemsCount => deduplicatedItems?.length ?? 0;

  /// Check if at least one item is accepted
  bool get hasAcceptedItems => acceptedItemIds.isNotEmpty;

  /// Check if all items are reviewed (accepted or rejected)
  bool get allItemsReviewed {
    if (deduplicatedItems == null || deduplicatedItems!.isEmpty) return false;
    return (acceptedCount + rejectedCount) == deduplicatedItems!.length;
  }

  /// Get acceptance progress percentage (0-100)
  double get acceptanceProgress {
    if (totalItemsCount == 0) return 0.0;
    return ((acceptedCount + rejectedCount) / totalItemsCount) * 100;
  }

  /// Get list of accepted items
  List<DeduplicatedItem> get acceptedItems {
    if (deduplicatedItems == null) return [];
    return deduplicatedItems!
        .where((item) => item.sourceItemIds.isNotEmpty && acceptedItemIds.contains(item.sourceItemIds.first))
        .toList();
  }

  /// Get list of manually rejected items (user-rejected during review)
  List<DeduplicatedItem> get manuallyRejectedItems {
    if (deduplicatedItems == null) return [];
    return deduplicatedItems!
        .where((item) => item.sourceItemIds.isNotEmpty && rejectedItemIds.contains(item.sourceItemIds.first))
        .toList();
  }

  /// Get list of pending items
  List<DeduplicatedItem> get pendingItems {
    if (deduplicatedItems == null) return [];
    return deduplicatedItems!
        .where((item) =>
            item.sourceItemIds.isNotEmpty &&
            !acceptedItemIds.contains(item.sourceItemIds.first) &&
            !rejectedItemIds.contains(item.sourceItemIds.first))
        .toList();
  }
}

/// Item acceptance state enum
enum ItemAcceptanceState {
  accepted,
  rejected,
  pending,
}

/// Phase 4.2: Network status for real-time monitoring
enum NetworkStatus {
  connected,      // WebSocket connected, backend reachable
  disconnected,   // WebSocket disconnected
  reconnecting,   // Attempting to reconnect
  unstable,       // Connection unstable (frequent disconnects)
}

/// Workflow steps for batch OCR
enum BatchOCRWorkflowStep {
  imageSelection,
  batchProcessing,
  deduplication,
  matchingReview,  // NEW: Smart matching review with confidence scores
  enrichment,
  review,
  submission,
  complete,
}

/// Batch OCR workflow state notifier
class BatchOCRNotifier extends StateNotifier<BatchOCRState> {
  final BatchOCRService _service;
  final DioApiService _apiService;
  WebSocketService? _wsService; // Made nullable for lazy loading
  final AuthService? _authService;
  final String _shopId;
  bool _wsInitialized = false;
  StreamSubscription<Map<String, dynamic>>? _ocrProgressSubscription;

  // Phase 2.3: Time estimation tracking
  DateTime? _processingStartTime;
  int _previousCompletedImages = 0;
  final List<Duration> _imageCompletionTimes = [];
  DateTime? _lastCompletionTime;

  // Phase 4.1: Undo/Redo system
  final UndoRedoManager<AcceptanceSnapshot> _undoRedoManager = UndoRedoManager(maxHistorySize: 10);

  // Phase 4.2: Checkpoint system
  AcceptanceSnapshot? _checkpoint;

  // Phase 4.3: Offline caching system
  final OCRStateStorageService _storageService = OCRStateStorageService();
  DateTime? _lastAutoSaveTime;
  bool _isStorageInitialized = false;

  BatchOCRNotifier({
    required BatchOCRService service,
    required DioApiService apiService,
    WebSocketService? wsService,  // Now optional for lazy loading
    AuthService? authService,
    required String shopId,
  })  : _service = service,
        _apiService = apiService,
        _wsService = wsService,
        _authService = authService,
        _shopId = shopId,
        super(const BatchOCRState()) {
    // WebSocket initialization removed - will be done lazily when OCR is accessed
    // This improves app startup performance and reduces unnecessary connections

    // Phase 4.3: Initialize storage on creation
    _initializeStorage();
  }

  /// Lazily initialize WebSocket when OCR is accessed
  Future<void> _ensureWebSocketConnected() async {
    // Skip if already initialized
    if (_wsInitialized || _wsService == null || _authService == null) {
      return;
    }

    try {
      if (kDebugMode) {
        Logger.debug('🔌 [BatchOCR] Initializing WebSocket connection for OCR...');
      }

      // Create WebSocket service if not provided
      _wsService ??= WebSocketService();

      // Initialize WebSocket with auth support
      _wsService!.initialize(
        authService: _authService,
        onAuthRequired: () {
          if (kDebugMode) {
            Logger.warning('🔐 [BatchOCR] WebSocket auth expired, re-authentication required');
          }
        },
      );

      // Get auth tokens
      final token = await _authService.getToken();
      final tenantId = await _authService.getTenantId();

      if (token != null) {
        // Connect to WebSocket
        await _wsService!.connect(token: token, tenantId: tenantId);
        _wsInitialized = true;

        if (kDebugMode) {
          Logger.info('✅ [BatchOCR] WebSocket connected successfully');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('⚠️ [BatchOCR] Failed to connect WebSocket: $e');
        Logger.info('📊 Will use polling fallback for OCR progress updates');
      }
      // Don't fail OCR if WebSocket fails - polling fallback will work
    }
  }

  @override
  void dispose() {
    // BEST PRACTICE: Clean up all subscriptions and timers to prevent memory leaks
    _ocrProgressSubscription?.cancel();
    _ocrProgressSubscription = null;

    // Clean up polling timer
    _pollingTimer?.cancel();
    _pollingTimer = null;

    // Clear time estimation data
    _processingStartTime = null;
    _lastCompletionTime = null;
    _imageCompletionTimes.clear();
    _previousCompletedImages = 0;
    _pollCount = 0;

    // Phase 4.1: Clean up undo/redo history
    _undoRedoManager.clear();

    // Phase 4.3: Disable auto-save and dispose storage
    _storageService.disableAutoSave();
    _storageService.dispose();

    if (kDebugMode) {
      Logger.debug('🧹 BatchOCRNotifier disposed - all resources cleaned up');
    }

    super.dispose();
  }

  // ==========================================
  // PHASE 2.3: TIME ESTIMATION
  // ==========================================

  /// Calculate estimated time remaining based on processing speed
  /// Returns estimated seconds remaining, or null if not enough data
  int? _calculateEstimatedTimeRemaining({
    required int totalImages,
    required int completedImages,
    required double progressPercentage,
  }) {
    // Need at least 2 images completed to calculate average
    if (_imageCompletionTimes.length < 2) {
      return null;
    }

    // Need some progress to estimate
    if (completedImages == 0 || progressPercentage < 5) {
      return null;
    }

    // Calculate average time per image from completed images
    final totalTime = _imageCompletionTimes.fold<Duration>(
      Duration.zero,
      (sum, duration) => sum + duration,
    );
    final avgTimePerImage = totalTime ~/ _imageCompletionTimes.length;

    // Remaining images = total - completed
    final remainingImages = totalImages - completedImages;

    // Handle edge case: if no remaining images but progress < 100%
    // This means current image is still processing
    if (remainingImages <= 0 && progressPercentage < 100) {
      // Estimate based on current image progress
      final currentImageProgress = progressPercentage % (100 / totalImages);
      final estimatedCurrentImageCompletion = avgTimePerImage.inSeconds * (1 - currentImageProgress / 100);
      return estimatedCurrentImageCompletion.round();
    }

    // Standard case: calculate remaining time
    final estimatedRemaining = avgTimePerImage * remainingImages;

    // Add buffer for current image if in progress (not at exact percentage boundary)
    final progressPerImage = 100.0 / totalImages;
    final isInBetweenImages = progressPercentage % progressPerImage > 1;

    if (isInBetweenImages) {
      // Add partial time for current image
      final currentImageProgress = (progressPercentage % progressPerImage) / progressPerImage;
      final currentImageRemaining = avgTimePerImage * (1 - currentImageProgress);
      return (estimatedRemaining + currentImageRemaining).inSeconds;
    }

    return estimatedRemaining.inSeconds;
  }

  /// Reset time estimation tracking (called when starting new batch)
  void _resetTimeEstimation() {
    _processingStartTime = null;
    _previousCompletedImages = 0;
    _imageCompletionTimes.clear();
    _lastCompletionTime = null;
  }

  /// Reset OCR results to clear old data
  void _resetOCRData() {
    if (kDebugMode) {
      Logger.debug('🗑️  [BatchOCR] Clearing old OCR data');
      Logger.debug('   Previous items: ${state.deduplicatedItems?.length ?? 0}');
      Logger.debug('   Previous filtered: ${state.filteredDeduplicatedItems?.length ?? 0}');
    }

    state = BatchOCRState(
      // Keep current selections
      selectedImagePaths: state.selectedImagePaths,
      maxImages: state.maxImages,
      step: state.step,
      // Clear all OCR results
      batchId: null,
      sessionId: null,
      progress: null,
      deduplicatedItems: null,
      receiptType: null,
      filteredDeduplicatedItems: null,
      filteredGarbageItems: null,
      filterSummary: null,
      rawTexts: null,
      totalItems: null,
      duplicatesRemoved: null,
      enrichmentState: null,
      initializeResult: null,
      acceptedItemIds: const {},
      rejectedItemIds: const {},
      failedImages: null,
      timeout: null,
      rejectedItems: null,
      totalRejected: null,
      showRejectedItems: false,
      networkStatus: state.networkStatus,
      lastConnectionTime: state.lastConnectionTime,
      connectionRetryCount: state.connectionRetryCount,
      isLoading: false,
      error: null,
      successMessage: null,
    );

    if (kDebugMode) {
      Logger.info('✅ [BatchOCR] OCR data cleared - starting fresh');
    }
  }

  // ==========================================
  // IMAGE SELECTION
  // ==========================================

  /// Add images to selection
  void addImages(List<String> imagePaths) {
    final currentPaths = state.selectedImagePaths;
    final totalImages = currentPaths.length + imagePaths.length;

    if (totalImages > state.maxImages) {
      state = state.copyWith(
        error: 'Maximum ${state.maxImages} images allowed. '
            'You already have ${currentPaths.length} images selected.',
      );
      return;
    }

    state = state.copyWith(
      selectedImagePaths: [...currentPaths, ...imagePaths],
      error: null,
    );

    if (kDebugMode) {
      Logger.info('📸 Added ${imagePaths.length} images. Total: ${state.selectedImagePaths.length}');
    }
  }

  /// Remove image from selection
  void removeImage(String imagePath) {
    final updatedPaths = state.selectedImagePaths.where((path) => path != imagePath).toList();
    state = state.copyWith(selectedImagePaths: updatedPaths);

    if (kDebugMode) {
      Logger.info('🗑️ Removed image. Remaining: ${updatedPaths.length}');
    }
  }

  /// Clear all selected images
  void clearImages() {
    state = state.copyWith(selectedImagePaths: []);
    if (kDebugMode) Logger.info('🗑️ Cleared all images');
  }

  /// Check if ready to start processing
  bool get canStartProcessing {
    return state.selectedImagePaths.isNotEmpty && !state.isLoading;
  }

  // ==========================================
  // BATCH PROCESSING
  // ==========================================

  /// Start batch OCR processing
  Future<void> startBatchProcessing() async {
    if (state.selectedImagePaths.isEmpty) {
      state = state.copyWith(error: 'No images selected');
      return;
    }

    try {
      // Lazily connect WebSocket when OCR is needed
      await _ensureWebSocketConnected();

      // Clear all old OCR data to prevent stale data display
      _resetOCRData();

      // Set processing state
      state = state.copyWith(
        isLoading: true,
        error: null,
        step: BatchOCRWorkflowStep.batchProcessing,
      );

      // Phase 2.3: Reset time estimation for new batch
      _resetTimeEstimation();

      if (kDebugMode) {
        Logger.info('🚀 Starting batch processing for ${state.selectedImagePaths.length} images');
      }

      // Convert images to base64
      final images = await BatchOCRService.imageFilesToBase64(state.selectedImagePaths);

      if (images.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to process images. Please try again.',
        );
        return;
      }

      // Create batch session FIRST
      final response = await _service.createBatchSession(
        images: images,
        shopId: _shopId,
        sessionType: 'stock_initialization',
      );

      if (!response.success || response.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? 'Failed to create batch session',
        );
        return;
      }

      final batchId = response.data!.id;

      // ⚡ CRITICAL: Set batchId and initialize progress IMMEDIATELY
      // This must happen BEFORE subscribing to WebSocket to avoid race condition
      // Phase 4.3: Initialize timeout tracking (5 minutes max for OCR processing)
      final timeout = ProcessingTimeout(
        startTime: DateTime.now(),
        maxDuration: const Duration(minutes: 5),
        currentStage: 'upload',
      );

      state = state.copyWith(
        batchId: batchId,
        sessionId: batchId, // Use batchId as sessionId for persistence
        progress: BatchOCRProgress(
          batchId: batchId,
          totalImages: state.selectedImagePaths.length,
          completedImages: 0,
          failedImages: 0,
          progressPercentage: 0,
          status: BatchStatus.processing,
        ),
        timeout: timeout,
        failedImages: [], // Phase 4.1: Initialize empty failed images list
      );

      if (kDebugMode) {
        Logger.info('✅ Batch session created: $batchId');
        Logger.debug('📊 Initial progress: 0%');
        Logger.debug('📡 Subscribing to WebSocket for real-time updates...');
      }

      // NOW subscribe to WebSocket AFTER batchId is set in state
      _subscribeToOCRProgress();

      if (kDebugMode) Logger.debug('⏳ Waiting for real-time progress via WebSocket...');

      // Start polling fallback in case WebSocket doesn't work
      // This ensures OCR completes even if WebSocket is unavailable
      _startPollingFallback();
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Batch processing error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Batch processing failed: ${e.toString()}',
      );
    }
  }

  /// Subscribe to OCR progress updates via WebSocket
  void _subscribeToOCRProgress() {
    // Cancel existing subscription if any
    _ocrProgressSubscription?.cancel();

    // Phase 4.2: Check WebSocket connection status (handle nullable)
    if (_wsService != null && _wsService!.isConnected) {
      _wsService!.subscribe(WebSocketChannels.ocrProgress);

      // Phase 4.2: Update network status to connected
      state = state.copyWith(
        networkStatus: NetworkStatus.connected,
        lastConnectionTime: DateTime.now(),
        connectionRetryCount: 0,
      );

      // Listen to OCR progress stream
      _ocrProgressSubscription = _wsService!.ocrProgressStream.listen(
        _handleOCRProgressUpdate,
        onError: (error) {
          if (kDebugMode) Logger.error('❌ WebSocket OCR progress error: $error');

          // Phase 4.2: Update network status on error
          _handleNetworkError();
        },
      );

      if (kDebugMode) {
        Logger.info('📡 Subscribed to OCR progress channel');
        Logger.info('🌐 Network status: Connected');
      }
    } else {
      if (kDebugMode) Logger.warning('⚠️ WebSocket not connected, attempting reconnection...');

      // Phase 4.2: Update network status to disconnected
      state = state.copyWith(networkStatus: NetworkStatus.disconnected);

      // Attempt reconnection
      _attemptReconnection();
    }
  }

  /// Start polling fallback for OCR progress (when WebSocket unavailable)
  Timer? _pollingTimer;
  int _pollCount = 0;

  void _startPollingFallback() async {
    // Poll every 3 seconds, up to 60 times (3 minutes total)
    _pollCount = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      _pollCount++;

      if (_pollCount > 60) {
        _pollingTimer?.cancel();
        if (kDebugMode) Logger.warning('⏱️ Polling timeout - stopping');
        return;
      }

      // Only poll if we haven't received WebSocket updates and processing isn't complete
      if (state.batchId != null &&
          state.progress != null &&
          state.progress!.progressPercentage < 100) {

        if (kDebugMode && _pollCount % 5 == 0) {
          Logger.debug('🔄 Polling OCR status ($_pollCount/60)...');
        }

        try {
          final response = await _service.getBatchSessionStatus(state.batchId!);

          if (response.success && response.data != null) {
            final session = response.data!;

            // Check if completed
            if (session.status == BatchStatus.completed) {
              _pollingTimer?.cancel();
              if (kDebugMode) Logger.info('✅ OCR completed via polling!');

              // Update progress to 100% and move to deduplication
              state = state.copyWith(
                progress: state.progress?.copyWith(
                  progressPercentage: 100.0,
                  status: BatchStatus.completed,
                ),
              );

              await _deduplicateItems();
            }
          }
        } catch (e) {
          if (kDebugMode) Logger.warning('⚠️ Poll error: $e');
        }
      } else {
        // Processing complete, stop polling
        _pollingTimer?.cancel();
      }
    });
  }

  // ==========================================
  // PHASE 4.2: NETWORK STATUS MONITORING
  // ==========================================

  /// Handle network error and update status
  void _handleNetworkError() {
    final currentRetries = state.connectionRetryCount;

    if (currentRetries >= 5) {
      // Too many retries - mark as unstable
      state = state.copyWith(
        networkStatus: NetworkStatus.unstable,
        connectionRetryCount: currentRetries + 1,
      );

      if (kDebugMode) {
        Logger.warning('⚠️ Network connection unstable (${currentRetries + 1} failures)');
      }
    } else {
      // Mark as disconnected and attempt reconnection
      state = state.copyWith(
        networkStatus: NetworkStatus.disconnected,
        connectionRetryCount: currentRetries + 1,
      );

      if (kDebugMode) {
        Logger.warning('🔌 Network disconnected (attempt ${currentRetries + 1}/5)');
      }

      _attemptReconnection();
    }
  }

  /// Attempt to reconnect to WebSocket
  void _attemptReconnection() async {
    if (state.networkStatus == NetworkStatus.unstable) {
      if (kDebugMode) Logger.warning('⚠️ Skipping reconnection - network unstable');
      return;
    }

    // Stop reconnection attempts after max retries
    if (state.connectionRetryCount >= 5) {
      if (kDebugMode) Logger.warning('⚠️ Max reconnection attempts reached - WebSocket unavailable');
      state = state.copyWith(
        networkStatus: NetworkStatus.disconnected,
        error: null, // Clear error - this is expected when WebSocket isn't available
      );
      return;
    }

    state = state.copyWith(networkStatus: NetworkStatus.reconnecting);

    if (kDebugMode) {
      Logger.debug('🔄 Attempting to reconnect... (retry ${state.connectionRetryCount}/5)');
    }

    // Wait before reconnecting (exponential backoff)
    final delaySeconds = [1, 2, 4, 8, 16][state.connectionRetryCount.clamp(0, 4)];
    await Future.delayed(Duration(seconds: delaySeconds));

    // Check if WebSocket reconnected (handle nullable)
    if (_wsService != null && _wsService!.isConnected) {
      state = state.copyWith(
        networkStatus: NetworkStatus.connected,
        lastConnectionTime: DateTime.now(),
        connectionRetryCount: 0,
      );

      if (kDebugMode) Logger.info('✅ Reconnected successfully!');

      // Resubscribe to progress updates
      _subscribeToOCRProgress();
    } else {
      if (kDebugMode) Logger.error('❌ Reconnection failed');
      _handleNetworkError();
    }
  }

  /// Check current network status
  bool get isNetworkConnected => state.networkStatus == NetworkStatus.connected;

  /// Check if network is having issues
  bool get hasNetworkIssues =>
      state.networkStatus == NetworkStatus.disconnected ||
      state.networkStatus == NetworkStatus.reconnecting ||
      state.networkStatus == NetworkStatus.unstable;

  /// Get network status message for UI
  String get networkStatusMessage {
    switch (state.networkStatus) {
      case NetworkStatus.connected:
        return 'Connected';
      case NetworkStatus.disconnected:
        // Don't show error if we've stopped retrying
        if (state.connectionRetryCount >= 5) {
          return 'Processing (real-time updates unavailable)';
        }
        return 'Disconnected - Retrying...';
      case NetworkStatus.reconnecting:
        return 'Reconnecting... (${state.connectionRetryCount}/5)';
      case NetworkStatus.unstable:
        return 'Connection unstable - Check your internet';
    }
  }

  /// Reset network status (useful after resolving issues)
  void resetNetworkStatus() {
    state = state.copyWith(
      networkStatus: NetworkStatus.connected,
      connectionRetryCount: 0,
      lastConnectionTime: DateTime.now(),
    );

    if (kDebugMode) Logger.info('🔄 Network status reset');
  }

  // ==========================================
  // PHASE 4.4: ERROR RECOVERY MECHANISMS
  // ==========================================

  /// Save current processing state for recovery
  /// Returns a map that can be used to restore state later
  Map<String, dynamic>? saveProcessingState() {
    if (state.batchId == null || state.progress == null) {
      if (kDebugMode) Logger.warning('⚠️ No active processing to save');
      return null;
    }

    final stateData = {
      'batch_id': state.batchId,
      'shop_id': _shopId,
      'step': state.step.toString(),
      'selected_images': state.selectedImagePaths,
      'progress': {
        'percentage': state.progress!.progressPercentage,
        'completed_images': state.progress!.completedImages,
        'total_images': state.progress!.totalImages,
        'items_extracted': state.progress!.itemsExtracted,
      },
      'failed_images': state.failedImages
          ?.map((f) => {
                'path': f.imagePath,
                'error': f.errorMessage,
                'retry_count': f.retryCount,
                'error_code': f.errorCode,
              })
          .toList(),
      'timeout': state.timeout != null
          ? {
              'start_time': state.timeout!.startTime.toIso8601String(),
              'max_duration_minutes': state.timeout!.maxDuration.inMinutes,
              'current_stage': state.timeout!.currentStage,
            }
          : null,
      'saved_at': DateTime.now().toIso8601String(),
    };

    if (kDebugMode) {
      Logger.info('💾 Processing state saved:');
      Logger.debug('   Batch ID: ${state.batchId}');
      Logger.debug('   Progress: ${state.progress!.progressPercentage}%');
      Logger.debug('   Failed images: ${state.failedImages?.length ?? 0}');
    }

    return stateData;
  }

  /// Restore processing state from saved data
  /// Returns true if restore was successful
  Future<bool> restoreProcessingState(Map<String, dynamic> savedState) async {
    try {
      final batchId = savedState['batch_id'] as String?;
      if (batchId == null) {
        if (kDebugMode) Logger.error('❌ Invalid saved state: missing batch_id');
        return false;
      }

      if (kDebugMode) {
        Logger.debug('🔄 Restoring processing state...');
        Logger.debug('   Batch ID: $batchId');
      }

      // Restore basic state
      final progressData = savedState['progress'] as Map<String, dynamic>?;
      final failedImagesData = savedState['failed_images'] as List<dynamic>?;
      final timeoutData = savedState['timeout'] as Map<String, dynamic>?;

      // Restore failed images
      final failedImages = failedImagesData?.map((f) {
        return FailedImage(
          imagePath: f['path'] as String,
          errorMessage: f['error'] as String,
          failedAt: DateTime.now(), // Use current time as we don't save exact time
          retryCount: (f['retry_count'] as num?)?.toInt() ?? 0,
          errorCode: f['error_code'] as String?,
        );
      }).toList();

      // Restore timeout
      final timeout = timeoutData != null
          ? ProcessingTimeout(
              startTime: DateTime.parse(timeoutData['start_time'] as String),
              maxDuration: Duration(
                minutes: (timeoutData['max_duration_minutes'] as num).toInt(),
              ),
              currentStage: timeoutData['current_stage'] as String?,
            )
          : null;

      // Check if the batch is still processing on backend
      final batchResponse = await _service.getBatchSessionStatus(batchId);

      if (!batchResponse.success) {
        state = state.copyWith(
          error: 'Failed to restore: Batch session not found',
        );
        return false;
      }

      final batchSession = batchResponse.data!;

      // Restore progress
      state = state.copyWith(
        batchId: batchId,
        sessionId: batchId, // Use batchId as sessionId for persistence
        progress: BatchOCRProgress(
          batchId: batchId,
          totalImages: (progressData?['total_images'] as num?)?.toInt() ?? 1,
          completedImages: (progressData?['completed_images'] as num?)?.toInt() ?? 0,
          failedImages: failedImages?.length ?? 0,
          progressPercentage: (progressData?['percentage'] as num?)?.toDouble() ?? 0.0,
          status: batchSession.status == BatchStatus.completed
              ? BatchStatus.completed
              : BatchStatus.processing,
          itemsExtracted: (progressData?['items_extracted'] as num?)?.toInt(),
        ),
        failedImages: failedImages,
        timeout: timeout,
        step: batchSession.status == BatchStatus.completed
            ? BatchOCRWorkflowStep.deduplication
            : BatchOCRWorkflowStep.batchProcessing,
      );

      if (kDebugMode) {
        Logger.info('✅ Processing state restored successfully');
        Logger.debug('   Status: ${batchSession.status}');
        Logger.debug('   Progress: ${state.progress!.progressPercentage}%');
      }

      // If processing is complete, move to deduplication
      if (batchSession.status == BatchStatus.completed) {
        await _deduplicateItems();
      } else {
        // Resume WebSocket monitoring
        _subscribeToOCRProgress();
      }

      return true;
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Error restoring state: $e');
      state = state.copyWith(
        error: 'Failed to restore processing: ${e.toString()}',
      );
      return false;
    }
  }

  /// Auto-resume processing after network recovery
  Future<void> autoResumeAfterNetworkRecovery() async {
    if (state.batchId == null) {
      if (kDebugMode) Logger.warning('⚠️ No batch to resume');
      return;
    }

    if (state.networkStatus != NetworkStatus.connected) {
      if (kDebugMode) Logger.warning('⚠️ Network not connected, cannot resume');
      return;
    }

    if (kDebugMode) {
      Logger.debug('🔄 Auto-resuming processing after network recovery...');
      Logger.debug('   Batch ID: ${state.batchId}');
    }

    try {
      // Check batch status on backend
      final batchResponse = await _service.getBatchSessionStatus(state.batchId!);

      if (!batchResponse.success) {
        state = state.copyWith(
          error: 'Failed to resume: Batch session not found',
        );
        return;
      }

      final batchSession = batchResponse.data!;

      if (kDebugMode) {
        Logger.debug('   Backend status: ${batchSession.status}');
        Logger.debug('   Progress: ${batchSession.totalItemsExtracted} items');
      }

      if (batchSession.status == BatchStatus.completed) {
        // Processing completed while offline - move to deduplication
        if (kDebugMode) Logger.info('✅ Batch completed while offline, moving to deduplication');

        state = state.copyWith(
          progress: state.progress?.copyWith(
            progressPercentage: 100.0,
            status: BatchStatus.completed,
          ),
          isLoading: false,
        );

        await _deduplicateItems();
      } else if (batchSession.status == BatchStatus.processing) {
        // Still processing - resubscribe to WebSocket
        if (kDebugMode) Logger.debug('🔄 Batch still processing, resuming monitoring');

        _subscribeToOCRProgress();
      } else {
        // Failed or unknown status
        state = state.copyWith(
          error: 'Batch processing failed: ${batchSession.status}',
          isLoading: false,
        );
      }
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Error auto-resuming: $e');
      state = state.copyWith(
        error: 'Failed to auto-resume: ${e.toString()}',
      );
    }
  }

  /// Check if current processing can be recovered
  bool get canRecoverProcessing {
    return state.batchId != null &&
        state.progress != null &&
        state.progress!.progressPercentage < 100 &&
        state.networkStatus == NetworkStatus.connected;
  }

  /// Handle OCR progress update from WebSocket
  Future<void> _handleOCRProgressUpdate(Map<String, dynamic> data) async {
    try {
      final batchId = data['batch_id'] as String?;
      final progressData = data['progress'] as Map<String, dynamic>?;

      if (batchId == null || progressData == null) {
        if (kDebugMode) Logger.warning('⚠️ Invalid OCR progress data');
        return;
      }

      // Only process updates for our current batch
      if (batchId != state.batchId) {
        if (kDebugMode) Logger.debug('🔄 Ignoring progress for different batch: $batchId');
        return;
      }

      // Phase 4.3: Check for timeout
      if (state.timeout != null && state.timeout!.isTimedOut) {
        if (kDebugMode) {
          Logger.warning('⏱️ Processing timeout detected!');
          Logger.warning('   Max duration: ${state.timeout!.maxDuration.inMinutes} minutes');
          Logger.warning('   Elapsed: ${DateTime.now().difference(state.timeout!.startTime).inMinutes} minutes');
        }

        state = state.copyWith(
          isLoading: false,
          error: 'Processing timeout: Took longer than ${state.timeout!.maxDuration.inMinutes} minutes',
        );
        _ocrProgressSubscription?.cancel();
        return;
      }

      final stage = progressData['stage'] as String?;
      final progressPercent = (progressData['progress'] as num?)?.toInt() ?? 0;
      final status = progressData['status'] as String?;
      final itemsExtracted = (progressData['items_extracted'] as num?)?.toInt() ?? 0;
      final sessionComplete = progressData['session_complete'] as bool? ?? false;
      final currentItem = progressData['current_item'] as String?; // Phase 2.1

      // Phase 4.1: Track failed images
      final failedImagePath = progressData['failed_image'] as String?;
      final errorMessage = progressData['error_message'] as String?;
      final errorCode = progressData['error_code'] as String?;

      if (kDebugMode) {
        Logger.debug('📊 OCR Progress Update:');
        Logger.debug('   Batch ID: $batchId');
        Logger.debug('   Stage: $stage');
        Logger.debug('   Progress: ${state.progress?.progressPercentage ?? 0}% → $progressPercent%');
        Logger.debug('   Status: $status');
        Logger.debug('   Items extracted: $itemsExtracted');
        if (currentItem != null) Logger.debug('   Current item: $currentItem'); // Phase 2.1
        Logger.debug('   Session complete: $sessionComplete');
        if (failedImagePath != null) {
          Logger.error('   ❌ Failed image: $failedImagePath');
          Logger.error('   Error: $errorMessage');
          Logger.error('   Error code: $errorCode');
        }
      }

      // Phase 4.1: Handle failed image
      if (failedImagePath != null && errorMessage != null) {
        final failedImage = FailedImage(
          imagePath: failedImagePath,
          errorMessage: errorMessage,
          failedAt: DateTime.now(),
          retryCount: 0,
          errorCode: errorCode,
        );

        final List<FailedImage> updatedFailedImages = [
          ...(state.failedImages ?? []),
          failedImage,
        ];

        state = state.copyWith(failedImages: updatedFailedImages);

        if (kDebugMode) {
          Logger.error('📝 Failed image tracked: ${updatedFailedImages.length} total failures');
        }
      }

      // Phase 4.3: Update timeout stage
      if (stage != null && state.timeout != null) {
        final updatedTimeout = ProcessingTimeout(
          startTime: state.timeout!.startTime,
          maxDuration: state.timeout!.maxDuration,
          currentStage: stage,
        );
        state = state.copyWith(timeout: updatedTimeout);
      }

      // Update progress state
      final currentProgress = state.progress ?? BatchOCRProgress(
        batchId: batchId,
        totalImages: 1,
        completedImages: 0,
        failedImages: 0,
        progressPercentage: 0,
        status: BatchStatus.processing,
      );

      // Phase 2.3: Track processing start time
      if (_processingStartTime == null && progressPercent > 0) {
        _processingStartTime = DateTime.now();
        _lastCompletionTime = DateTime.now();
        if (kDebugMode) Logger.debug('⏱️ Processing started at $_processingStartTime');
      }

      // Phase 2.3: Track image completions for time estimation
      final progressPerImage = 100.0 / currentProgress.totalImages;
      final currentCompletedImages = (progressPercent / progressPerImage).floor();

      if (currentCompletedImages > _previousCompletedImages && _lastCompletionTime != null) {
        // An image just completed - record the time it took
        final now = DateTime.now();
        final timeSinceLastCompletion = now.difference(_lastCompletionTime!);
        _imageCompletionTimes.add(timeSinceLastCompletion);
        _lastCompletionTime = now;
        _previousCompletedImages = currentCompletedImages;

        if (kDebugMode) {
          Logger.info('✅ Image #$currentCompletedImages completed in ${timeSinceLastCompletion.inSeconds}s');
          Logger.debug('   Average time per image: ${_imageCompletionTimes.isEmpty ? 0 : _imageCompletionTimes.fold<Duration>(Duration.zero, (sum, d) => sum + d).inSeconds ~/ _imageCompletionTimes.length}s');
        }
      }

      // Phase 2.3: Calculate estimated time remaining
      final estimatedSecondsRemaining = _calculateEstimatedTimeRemaining(
        totalImages: currentProgress.totalImages,
        completedImages: currentCompletedImages,
        progressPercentage: progressPercent.toDouble(),
      );

      if (kDebugMode && estimatedSecondsRemaining != null) {
        Logger.debug('⏱️ Estimated time remaining: ${estimatedSecondsRemaining}s');
      }

      // Phase 1.2 & 1.3: Enhanced progress tracking with stage and items
      // Phase 2.1 & 2.2: Add current item display and items counter
      // Phase 2.3: Add time estimation
      final updatedProgress = BatchOCRProgress(
        batchId: batchId,
        totalImages: currentProgress.totalImages,
        completedImages: currentCompletedImages,
        failedImages: status == 'failed' ? 1 : 0,
        progressPercentage: progressPercent.toDouble(),
        status: status == 'completed' ? BatchStatus.completed :
                status == 'failed' ? BatchStatus.failed : BatchStatus.processing,
        stage: stage, // WebSocket stage: "text_extraction", "brand_matching", etc.
        itemsExtracted: itemsExtracted, // Real-time items count from backend
        currentItem: currentItem, // Phase 2.1: Current item being processed
        estimatedTimeRemainingSeconds: estimatedSecondsRemaining, // Phase 2.3: Time estimation
      );

      state = state.copyWith(progress: updatedProgress);

      if (kDebugMode) {
        Logger.debug('✅ Progress updated: ${updatedProgress.progressPercentage}%');
      }

      // When session is complete, close WebSocket and move to deduplication
      if (sessionComplete || (status == 'completed' && progressPercent == 100)) {
        if (kDebugMode) {
          Logger.info('✅ Batch processing complete via WebSocket!');
          Logger.debug('   Total items extracted: $itemsExtracted');
          Logger.debug('   Session complete flag: $sessionComplete');
        }

        state = state.copyWith(isLoading: false);

        // BEST PRACTICE: Clean up all resources when processing completes
        _ocrProgressSubscription?.cancel();
        _ocrProgressSubscription = null;
        _pollingTimer?.cancel();
        _pollingTimer = null;

        if (kDebugMode) Logger.info('🔌 Closing WebSocket connection - OCR session complete');
        if (kDebugMode) Logger.debug('🧹 Cleaned up subscriptions and timers');

        // Automatically move to deduplication
        await _deduplicateItems();
      } else if (status == 'failed') {
        // Extract error message from progress data for detailed error reporting
        final errorMessage = progressData['error_message'] as String?;
        final errorDetails = errorMessage ?? 'OCR processing failed';

        if (kDebugMode) {
          Logger.error('❌ Batch processing failed');
          Logger.error('   Error: $errorDetails');
        }

        state = state.copyWith(
          isLoading: false,
          error: errorDetails,
        );

        // BEST PRACTICE: Clean up resources on failure too
        _ocrProgressSubscription?.cancel();
        _ocrProgressSubscription = null;
        _pollingTimer?.cancel();
        _pollingTimer = null;
      }
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Error handling OCR progress: $e');
    }
  }

  // ==========================================
  // PHASE 4.1: RETRY MECHANISM FOR FAILED IMAGES
  // ==========================================

  /// Retry processing for failed images
  /// Returns true if retry was successful, false otherwise
  Future<bool> retryFailedImages() async {
    if (state.failedImages == null || state.failedImages!.isEmpty) {
      if (kDebugMode) Logger.warning('⚠️ No failed images to retry');
      return false;
    }

    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
      );

      if (kDebugMode) {
        Logger.info('🔄 Retrying ${state.failedImages!.length} failed images...');
      }

      // Extract image paths from failed images
      final imagePaths = state.failedImages!.map((f) => f.imagePath).toList();

      // Convert images to base64
      final images = await BatchOCRService.imageFilesToBase64(imagePaths);

      if (images.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to process retry images. Please try again.',
        );
        return false;
      }

      // Create new batch session for retry
      final response = await _service.createBatchSession(
        images: images,
        shopId: _shopId,
        sessionType: 'stock_initialization_retry',
      );

      if (!response.success || response.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? 'Failed to retry batch session',
        );
        return false;
      }

      final batchId = response.data!.id;

      // Initialize new timeout for retry
      final timeout = ProcessingTimeout(
        startTime: DateTime.now(),
        maxDuration: const Duration(minutes: 5),
        currentStage: 'upload',
      );

      // Set new batchId and reset failed images (will be repopulated if they fail again)
      state = state.copyWith(
        batchId: batchId,
        sessionId: batchId, // Use batchId as sessionId for persistence
        progress: BatchOCRProgress(
          batchId: batchId,
          totalImages: imagePaths.length,
          completedImages: 0,
          failedImages: 0,
          progressPercentage: 0,
          status: BatchStatus.processing,
        ),
        timeout: timeout,
        failedImages: [], // Clear for retry - will repopulate if failures occur
        step: BatchOCRWorkflowStep.batchProcessing,
      );

      if (kDebugMode) {
        Logger.info('✅ Retry batch session created: $batchId');
        Logger.debug('📊 Retrying ${imagePaths.length} images');
      }

      // Subscribe to WebSocket for retry progress
      _subscribeToOCRProgress();

      // Reset time estimation for retry
      _resetTimeEstimation();

      return true;
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Retry failed images error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Retry failed: ${e.toString()}',
      );
      return false;
    }
  }

  /// Retry a specific failed image
  /// Returns true if retry was successful, false otherwise
  Future<bool> retrySpecificImage(String imagePath) async {
    final failedImage = state.failedImages?.firstWhere(
      (f) => f.imagePath == imagePath,
      orElse: () => throw Exception('Failed image not found'),
    );

    if (failedImage == null) {
      if (kDebugMode) Logger.warning('⚠️ Failed image not found: $imagePath');
      return false;
    }

    // Check retry count limit (max 3 retries)
    if (failedImage.retryCount >= 3) {
      state = state.copyWith(
        error: 'Maximum retry attempts (3) reached for this image',
      );
      return false;
    }

    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
      );

      if (kDebugMode) {
        Logger.info('🔄 Retrying specific image: $imagePath');
        Logger.debug('   Retry count: ${failedImage.retryCount + 1}/3');
      }

      // Remove this image from failed list temporarily
      final remainingFailedImages = state.failedImages!
          .where((f) => f.imagePath != imagePath)
          .toList();

      state = state.copyWith(failedImages: remainingFailedImages);

      // Convert single image to base64
      final images = await BatchOCRService.imageFilesToBase64([imagePath]);

      if (images.isEmpty) {
        // Add back to failed list
        state = state.copyWith(
          isLoading: false,
          error: 'Failed to process image. Please try again.',
          failedImages: [...remainingFailedImages, failedImage],
        );
        return false;
      }

      // Create new single-image batch session
      final response = await _service.createBatchSession(
        images: images,
        shopId: _shopId,
        sessionType: 'stock_initialization_single_retry',
      );

      if (!response.success || response.data == null) {
        // Add back to failed list
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? 'Failed to retry image',
          failedImages: [...remainingFailedImages, failedImage],
        );
        return false;
      }

      final batchId = response.data!.id;

      // Initialize timeout for single retry
      final timeout = ProcessingTimeout(
        startTime: DateTime.now(),
        maxDuration: const Duration(minutes: 2), // Shorter timeout for single image
        currentStage: 'upload',
      );

      state = state.copyWith(
        batchId: batchId,
        sessionId: batchId, // Use batchId as sessionId for persistence
        progress: BatchOCRProgress(
          batchId: batchId,
          totalImages: 1,
          completedImages: 0,
          failedImages: 0,
          progressPercentage: 0,
          status: BatchStatus.processing,
        ),
        timeout: timeout,
        step: BatchOCRWorkflowStep.batchProcessing,
      );

      if (kDebugMode) {
        Logger.info('✅ Single image retry batch created: $batchId');
      }

      // Subscribe to WebSocket
      _subscribeToOCRProgress();
      _resetTimeEstimation();

      return true;
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Retry specific image error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Retry failed: ${e.toString()}',
      );
      return false;
    }
  }

  /// Remove a failed image from the list (give up on it)
  void removeFailedImage(String imagePath) {
    if (state.failedImages == null) return;

    final updatedFailedImages = state.failedImages!
        .where((f) => f.imagePath != imagePath)
        .toList();

    state = state.copyWith(failedImages: updatedFailedImages);

    if (kDebugMode) {
      Logger.info('🗑️ Removed failed image: $imagePath');
      Logger.debug('   Remaining failed: ${updatedFailedImages.length}');
    }
  }

  /// Clear all failed images
  void clearFailedImages() {
    state = state.copyWith(failedImages: []);
    if (kDebugMode) Logger.info('🗑️ Cleared all failed images');
  }

  // ==========================================
  // DEDUPLICATION
  // ==========================================

  /// Deduplicate items from batch sessions
  Future<void> _deduplicateItems() async {
    if (state.progress == null || state.progress!.batchId.isEmpty) {
      state = state.copyWith(error: 'No batch session found');
      return;
    }

    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        step: BatchOCRWorkflowStep.deduplication,
      );

      if (kDebugMode) Logger.debug('🔄 Deduplicating items...');

      // Fetch full batch session to get individual OCR session IDs
      final batchResponse = await _service.getBatchSessionStatus(state.progress!.batchId);

      if (!batchResponse.success || batchResponse.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: batchResponse.message ?? 'Failed to fetch batch session',
        );
        return;
      }

      final batchSession = batchResponse.data!;
      final sessionIds = batchSession.sessionIds;

      if (kDebugMode) {
        Logger.debug('📋 Batch session details:');
        Logger.debug('   ID: ${batchSession.id}');
        Logger.debug('   Status: ${batchSession.status}');
        Logger.debug('   Total items: ${batchSession.totalItemsExtracted}');
        Logger.debug('   Session IDs count: ${sessionIds.length}');
        Logger.debug('   Session IDs: $sessionIds');
      }

      if (sessionIds.isEmpty) {
        if (kDebugMode) {
          Logger.warning('⚠️ WARNING: Backend did not return session_ids!');
          Logger.warning('   This is a backend API issue that needs to be fixed.');
          Logger.warning('   For now, skipping deduplication and going directly to enrichment.');
        }

        // WORKAROUND: Skip deduplication if session_ids are missing
        // Create mock deduplicated items to proceed
        // TODO: Fix backend to return session_ids in batch session response
        state = state.copyWith(
          isLoading: false,
          error: 'Backend API issue: session_ids not returned. '
              'The backend needs to be updated to include session_ids in the batch session response. '
              'Deduplication step cannot proceed.',
        );
        return;
      }

      if (kDebugMode) {
        Logger.debug('📋 Found ${sessionIds.length} OCR sessions for deduplication');
        Logger.debug('   Session IDs: $sessionIds');
      }

      // Call deduplication endpoint with OCR session IDs
      final response = await _service.getDeduplicatedItems(sessionIds: sessionIds);

      if (!response.success || response.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? 'Failed to deduplicate items',
        );
        return;
      }

      // Extract receipt type, items, and raw OCR data from response
      final receiptType = response.data!['receipt_type'] as String?;
      final dedupItems = response.data!['items'] as List<DeduplicatedItem>;
      final rawTexts = response.data!['raw_texts'] as Map<String, String>?;
      final totalItems = response.data!['total_items'] as int?;
      final duplicatesRemoved = response.data!['duplicates_removed'] as int?;

      // Extract rejected items from brand validation filtering
      final rejectedItemsJson = response.data!['rejected_items'] as List<dynamic>?;
      final rejectedItems = rejectedItemsJson
          ?.map((json) => RejectedItem.fromJson(json as Map<String, dynamic>))
          .toList();
      final totalRejected = response.data!['total_rejected'] as int? ?? rejectedItems?.length ?? 0;

      if (kDebugMode) {
        Logger.info('✅ Deduplication complete: ${dedupItems.length} unique items');
        if (receiptType != null) {
          Logger.info('   Receipt Type: $receiptType');
        }
        if (rawTexts != null) {
          Logger.debug('   📝 Raw texts collected: ${rawTexts.length} sessions');
        }
        if (totalItems != null) {
          Logger.debug('   📊 Total items: $totalItems');
        }
        if (duplicatesRemoved != null) {
          Logger.debug('   🔀 Duplicates removed: $duplicatesRemoved');
        }
        if (rejectedItems != null && rejectedItems.isNotEmpty) {
          Logger.warning('🗑️  [OCR] $totalRejected rejected items stored for batch');
          for (final item in rejectedItems) {
            Logger.warning('   - ${item.brandText}: ${item.rejectionReason}');
            if (item.confidence != null) {
              final confidencePercent = (item.confidence! * 100).toStringAsFixed(1);
              if (item.confidence! < 0.5) {
                Logger.warning('     ⚠️ [Confidence] LOW confidence ($confidencePercent%) - needs review');
              }
            }
          }
        }
      }

      // Apply garbage filtering to remove obvious non-brand items
      final filterResult = BrandNameFilter.filterItems(dedupItems);
      final cleanItems = filterResult['clean'] as List<DeduplicatedItem>;
      final garbageItems = filterResult['garbage'] as List<DeduplicatedItem>;
      final filterSummary = filterResult['summary'] as String;

      if (kDebugMode) {
        Logger.debug('🔍 [BrandFilter] Filtering applied:');
        Logger.debug('   Original: ${dedupItems.length} items');
        Logger.debug('   Clean: ${cleanItems.length} items');
        Logger.debug('   Filtered: ${garbageItems.length} items');
        Logger.debug('   Summary: $filterSummary');
      }

      // Create enrichment workflow state with filtered items
      final enrichmentState = EnrichmentWorkflowState.initial(
        batchId: state.progress!.batchId,
        sessionIds: sessionIds,
        deduplicatedItems: cleanItems, // Use filtered clean items
      );

      state = state.copyWith(
        deduplicatedItems: dedupItems,                      // Keep original for reference
        receiptType: receiptType,                           // Receipt type from OCR
        filteredDeduplicatedItems: cleanItems,              // Clean items only
        filteredGarbageItems: garbageItems,                 // Filtered garbage
        filterSummary: filterSummary,                       // Filtering summary
        rawTexts: rawTexts,                                 // Complete raw OCR text per session
        totalItems: totalItems,                             // Total deduplicated items
        duplicatesRemoved: duplicatesRemoved,               // Number of duplicates merged
        rejectedItems: rejectedItems,                       // Items filtered by brand validation
        totalRejected: totalRejected,                       // Count of rejected items
        enrichmentState: enrichmentState,
        isLoading: false,
        step: BatchOCRWorkflowStep.matchingReview, // Changed: Navigate to smart matching review
      );

      if (kDebugMode) {
        Logger.debug('');
        Logger.debug('🔍 [Provider] State updated with raw texts:');
        Logger.debug('   rawTexts: ${state.rawTexts?.length ?? 0} sessions');
        Logger.debug('   totalItems: ${state.totalItems}');
        Logger.debug('   duplicatesRemoved: ${state.duplicatesRemoved}');
        if (state.rawTexts != null && state.rawTexts!.isNotEmpty) {
          state.rawTexts!.forEach((sessionId, text) {
            Logger.debug('   - Session ${sessionId.substring(0, 8)}: ${text.length} chars stored');
          });
        } else {
          Logger.warning('   ⚠️ WARNING: No raw texts in state after update!');
        }
        Logger.debug('');
      }

      if (kDebugMode) {
        Logger.info('🎯 [BatchOCRProvider] State updated to matchingReview');
        Logger.debug('   Step: ${state.step}');
        Logger.debug('   Clean items: ${state.filteredDeduplicatedItems?.length}');
        Logger.debug('   Garbage filtered: ${state.filteredGarbageItems?.length}');
      }
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Deduplication error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Deduplication failed: ${e.toString()}',
      );
    }
  }

  // ==========================================
  // ENRICHMENT
  // ==========================================

  /// Update enrichment for current item
  void updateCurrentEnrichment(EnrichedStockItem updatedItem) {
    if (state.enrichmentState == null) return;

    final currentState = state.enrichmentState!;
    final updatedItems = List<EnrichedStockItem>.from(currentState.enrichedItems);
    updatedItems[currentState.currentItemIndex] = updatedItem;

    state = state.copyWith(
      enrichmentState: currentState.copyWith(enrichedItems: updatedItems),
    );
  }

  /// Move to next item in enrichment workflow
  void nextEnrichmentItem() {
    if (state.enrichmentState == null) return;

    final currentState = state.enrichmentState!;
    final nextIndex = currentState.currentItemIndex + 1;

    if (nextIndex < currentState.enrichedItems.length) {
      state = state.copyWith(
        enrichmentState: currentState.copyWith(currentItemIndex: nextIndex),
      );
    } else {
      // All items enriched, move to review
      state = state.copyWith(
        step: BatchOCRWorkflowStep.review,
        enrichmentState: currentState.copyWith(
          currentStep: EnrichmentStep.review,
        ),
      );
    }
  }

  /// Move to previous item in enrichment workflow
  void previousEnrichmentItem() {
    if (state.enrichmentState == null) return;

    final currentState = state.enrichmentState!;
    final prevIndex = currentState.currentItemIndex - 1;

    if (prevIndex >= 0) {
      state = state.copyWith(
        enrichmentState: currentState.copyWith(currentItemIndex: prevIndex),
      );
    }
  }

  /// Skip current item
  void skipCurrentItem() {
    if (state.enrichmentState == null) return;

    final currentState = state.enrichmentState!;
    final currentItem = currentState.currentItem;

    if (currentItem != null) {
      final skippedItem = currentItem.copyWith(
        enrichmentStatus: EnrichmentStatus.skipped,
      );
      updateCurrentEnrichment(skippedItem);
      nextEnrichmentItem();
    }
  }

  /// Update enriched item at any index
  void updateEnrichedItem(EnrichedStockItem updatedItem) {
    if (state.enrichmentState == null) return;

    final currentState = state.enrichmentState!;
    final updatedItems = List<EnrichedStockItem>.from(currentState.enrichedItems);

    // Find and update the item by ocrItemId
    final index = updatedItems.indexWhere(
      (item) => item.ocrItemId == updatedItem.ocrItemId,
    );

    if (index != -1) {
      updatedItems[index] = updatedItem;
      state = state.copyWith(
        enrichmentState: currentState.copyWith(enrichedItems: updatedItems),
      );
    }
  }

  /// Move to next item (alias for nextEnrichmentItem for compatibility)
  void moveToNextItem() {
    nextEnrichmentItem();
  }

  /// Set current item index
  void setCurrentItemIndex(int index) {
    if (state.enrichmentState == null) return;

    final currentState = state.enrichmentState!;
    if (index >= 0 && index < currentState.enrichedItems.length) {
      state = state.copyWith(
        enrichmentState: currentState.copyWith(currentItemIndex: index),
      );
    }
  }

  // ==========================================
  // SUBMISSION
  // ==========================================

  /// Submit enriched items for stock initialization
  Future<void> submitStockInitialization({required String reason}) async {
    if (state.enrichmentState == null) {
      state = state.copyWith(error: 'No enrichment data found');
      return;
    }

    final enrichmentState = state.enrichmentState!;

    if (!enrichmentState.isReadyForSubmission) {
      state = state.copyWith(error: 'Not all items are enriched');
      return;
    }

    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        step: BatchOCRWorkflowStep.submission,
      );

      if (kDebugMode) {
        Logger.info('📦 Submitting ${enrichmentState.itemsForSubmission.length} items for stock initialization');
      }

      final response = await _service.initializeStockFromOCR(
        sessionIds: enrichmentState.sessionIds,
        shopId: _shopId,
        reason: reason,
        items: enrichmentState.itemsForSubmission,
      );

      if (!response.success || response.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? 'Failed to initialize stock',
        );
        return;
      }

      final result = response.data!;

      if (kDebugMode) {
        Logger.info('✅ Stock initialization complete: ${result.itemsCreated}/${result.itemsProcessed} items created');
      }

      state = state.copyWith(
        initializeResult: result,
        isLoading: false,
        step: BatchOCRWorkflowStep.complete,
        successMessage: result.message,
      );
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Stock initialization error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Stock initialization failed: ${e.toString()}',
      );
    }
  }

  // ==========================================
  // ACCEPTANCE TRACKING
  // ==========================================

  /// Accept an item - Mark for inclusion in stock
  void acceptItem(String itemId) {
    // Phase 4.1: Record state before making changes (for undo)
    _recordStateForUndo();

    final newAccepted = Set<String>.from(state.acceptedItemIds)..add(itemId);
    final newRejected = Set<String>.from(state.rejectedItemIds)..remove(itemId);

    state = state.copyWith(
      acceptedItemIds: newAccepted,
      rejectedItemIds: newRejected,
    );

    if (kDebugMode) {
      Logger.info('✅ Item accepted: $itemId (Undo available: ${_undoRedoManager.canUndo})');
      Logger.debug('   Accepted: ${newAccepted.length}, Rejected: ${newRejected.length}');
    }

    // Also mark the enriched item as complete (for backward compatibility)
    if (state.enrichmentState != null) {
      final enrichedItem = state.enrichmentState!.enrichedItems.firstWhere(
        (item) => item.ocrItemId == itemId,
        orElse: () => state.enrichmentState!.enrichedItems.first,
      );
      if (enrichedItem.ocrItemId == itemId) {
        updateEnrichedItem(
          enrichedItem.copyWith(enrichmentStatus: EnrichmentStatus.complete),
        );
      }
    }
  }

  /// Reject an item - Exclude from stock
  void rejectItem(String itemId) {
    // Phase 4.1: Record state before making changes (for undo)
    _recordStateForUndo();

    final newRejected = Set<String>.from(state.rejectedItemIds)..add(itemId);
    final newAccepted = Set<String>.from(state.acceptedItemIds)..remove(itemId);

    state = state.copyWith(
      acceptedItemIds: newAccepted,
      rejectedItemIds: newRejected,
    );

    if (kDebugMode) {
      Logger.info('❌ Item rejected: $itemId (Undo available: ${_undoRedoManager.canUndo})');
      Logger.debug('   Accepted: ${newAccepted.length}, Rejected: ${newRejected.length}');
    }

    // Also mark the enriched item as skipped (for backward compatibility)
    if (state.enrichmentState != null) {
      final enrichedItem = state.enrichmentState!.enrichedItems.firstWhere(
        (item) => item.ocrItemId == itemId,
        orElse: () => state.enrichmentState!.enrichedItems.first,
      );
      if (enrichedItem.ocrItemId == itemId) {
        updateEnrichedItem(
          enrichedItem.copyWith(enrichmentStatus: EnrichmentStatus.skipped),
        );
      }
    }
  }

  /// Toggle item acceptance state
  void toggleItemAcceptance(String itemId) {
    final currentState = state.getAcceptanceState(itemId);
    if (currentState == ItemAcceptanceState.accepted) {
      rejectItem(itemId);
    } else {
      acceptItem(itemId);
    }
  }

  /// Accept multiple items at once
  void acceptItems(List<String> itemIds) {
    final newAccepted = Set<String>.from(state.acceptedItemIds)..addAll(itemIds);
    final newRejected = Set<String>.from(state.rejectedItemIds)
      ..removeAll(itemIds);

    state = state.copyWith(
      acceptedItemIds: newAccepted,
      rejectedItemIds: newRejected,
    );

    if (kDebugMode) {
      Logger.info('✅ ${itemIds.length} items accepted in bulk');
      Logger.debug('   Total Accepted: ${newAccepted.length}, Rejected: ${newRejected.length}');
    }

    // Mark enriched items as complete
    if (state.enrichmentState != null) {
      for (final itemId in itemIds) {
        final enrichedItem = state.enrichmentState!.enrichedItems.firstWhere(
          (item) => item.ocrItemId == itemId,
          orElse: () => state.enrichmentState!.enrichedItems.first,
        );
        if (enrichedItem.ocrItemId == itemId) {
          updateEnrichedItem(
            enrichedItem.copyWith(enrichmentStatus: EnrichmentStatus.complete),
          );
        }
      }
    }
  }

  /// Accept all pending items
  void acceptAllPendingItems() {
    final pendingItems = state.pendingItems;
    final itemIds = pendingItems
        .where((item) => item.sourceItemIds.isNotEmpty)
        .map((item) => item.sourceItemIds.first)
        .toList();
    acceptItems(itemIds);

    if (kDebugMode) {
      Logger.info('✅ All ${itemIds.length} pending items accepted');
    }
  }

  /// Clear all acceptance state
  void clearAcceptanceState() {
    state = state.copyWith(
      acceptedItemIds: const {},
      rejectedItemIds: const {},
    );
    if (kDebugMode) Logger.info('🔄 Acceptance state cleared');
  }

  // ==========================================
  // PHASE 4.1: UNDO/REDO SYSTEM
  // ==========================================

  /// Record current state for undo (before making changes)
  void _recordStateForUndo() {
    final snapshot = AcceptanceSnapshot.fromSets(
      state.acceptedItemIds,
      state.rejectedItemIds,
    );
    _undoRedoManager.record(snapshot);
  }

  /// Undo last action
  void undo() {
    if (!canUndo) return;

    // Get current state and push to redo stack
    final currentSnapshot = AcceptanceSnapshot.fromSets(
      state.acceptedItemIds,
      state.rejectedItemIds,
    );
    _undoRedoManager.pushToRedo(currentSnapshot);

    // Get previous state
    final previousSnapshot = _undoRedoManager.undo();
    if (previousSnapshot != null) {
      state = state.copyWith(
        acceptedItemIds: previousSnapshot.acceptedIds,
        rejectedItemIds: previousSnapshot.rejectedIds,
      );

      if (kDebugMode) {
        Logger.info('↩️  Undo: Restored to previous state');
        Logger.debug('   Accepted: ${previousSnapshot.acceptedIds.length}, Rejected: ${previousSnapshot.rejectedIds.length}');
        Logger.debug('   Undo available: ${_undoRedoManager.canUndo}, Redo available: ${_undoRedoManager.canRedo}');
      }
    }
  }

  /// Redo previously undone action
  void redo() {
    if (!canRedo) return;

    // Record current state before redo
    final currentSnapshot = AcceptanceSnapshot.fromSets(
      state.acceptedItemIds,
      state.rejectedItemIds,
    );
    _undoRedoManager.record(currentSnapshot);

    // Get next state
    final nextSnapshot = _undoRedoManager.redo();
    if (nextSnapshot != null) {
      state = state.copyWith(
        acceptedItemIds: nextSnapshot.acceptedIds,
        rejectedItemIds: nextSnapshot.rejectedIds,
      );

      if (kDebugMode) {
        Logger.info('↪️  Redo: Restored to next state');
        Logger.debug('   Accepted: ${nextSnapshot.acceptedIds.length}, Rejected: ${nextSnapshot.rejectedIds.length}');
        Logger.debug('   Undo available: ${_undoRedoManager.canUndo}, Redo available: ${_undoRedoManager.canRedo}');
      }
    }
  }

  /// Check if undo is available
  bool get canUndo => _undoRedoManager.canUndo;

  /// Check if redo is available
  bool get canRedo => _undoRedoManager.canRedo;

  /// Get number of available undo steps
  int get undoCount => _undoRedoManager.undoCount;

  /// Get number of available redo steps
  int get redoCount => _undoRedoManager.redoCount;

  /// Clear undo/redo history
  void clearUndoRedoHistory() {
    _undoRedoManager.clear();
    if (kDebugMode) Logger.info('🗑️  Undo/redo history cleared');
  }

  // ==========================================
  // PHASE 4.2: CHECKPOINT & RESET SYSTEM
  // ==========================================

  /// Save current state as checkpoint
  void saveCheckpoint() {
    _checkpoint = AcceptanceSnapshot.fromSets(
      state.acceptedItemIds,
      state.rejectedItemIds,
    );

    if (kDebugMode) {
      Logger.info('💾 Checkpoint saved');
      Logger.debug('   Accepted: ${_checkpoint!.acceptedIds.length}, Rejected: ${_checkpoint!.rejectedIds.length}');
    }
  }

  /// Restore from saved checkpoint
  void restoreCheckpoint() {
    if (_checkpoint == null) {
      if (kDebugMode) Logger.warning('❌ No checkpoint to restore');
      return;
    }

    // Record current state for undo before restoring
    _recordStateForUndo();

    state = state.copyWith(
      acceptedItemIds: _checkpoint!.acceptedIds,
      rejectedItemIds: _checkpoint!.rejectedIds,
    );

    if (kDebugMode) {
      Logger.info('📥 Checkpoint restored');
      Logger.debug('   Accepted: ${_checkpoint!.acceptedIds.length}, Rejected: ${_checkpoint!.rejectedIds.length}');
    }
  }

  /// Check if checkpoint is available
  bool get hasCheckpoint => _checkpoint != null;

  /// Clear saved checkpoint
  void clearCheckpoint() {
    _checkpoint = null;
    if (kDebugMode) Logger.info('🗑️  Checkpoint cleared');
  }

  /// Reset all acceptances to initial state
  void resetAllAcceptances({bool saveToCheckpoint = false}) {
    // Optionally save current state before reset
    if (saveToCheckpoint) {
      saveCheckpoint();
    }

    // Record for undo
    _recordStateForUndo();

    state = state.copyWith(
      acceptedItemIds: const {},
      rejectedItemIds: const {},
    );

    if (kDebugMode) {
      Logger.info('🔄 All acceptances reset');
      if (saveToCheckpoint) {
        Logger.debug('   Previous state saved to checkpoint');
      }
    }
  }

  /// Accept all items (bulk action)
  void acceptAllItems() {
    // Record for undo
    _recordStateForUndo();

    final allItemIds = (state.filteredDeduplicatedItems ?? state.deduplicatedItems ?? [])
        .where((item) => item.id != null)
        .map((item) => item.id!)
        .toSet();

    state = state.copyWith(
      acceptedItemIds: allItemIds,
      rejectedItemIds: const {},
    );

    if (kDebugMode) {
      Logger.info('✅ All ${allItemIds.length} items accepted');
    }
  }

  /// Reject all items (bulk action)
  void rejectAllItems() {
    // Record for undo
    _recordStateForUndo();

    final allItemIds = (state.filteredDeduplicatedItems ?? state.deduplicatedItems ?? [])
        .where((item) => item.id != null)
        .map((item) => item.id!)
        .toSet();

    state = state.copyWith(
      acceptedItemIds: const {},
      rejectedItemIds: allItemIds,
    );

    if (kDebugMode) {
      Logger.info('❌ All ${allItemIds.length} items rejected');
    }
  }

  // ==========================================
  // PHASE 4.3: OFFLINE CACHING & AUTO-SAVE
  // ==========================================

  /// Initialize storage service and attempt recovery
  Future<void> _initializeStorage() async {
    try {
      await _storageService.initialize();
      _isStorageInitialized = true;

      // Attempt to recover saved state
      await _attemptRecovery();

      // Enable auto-save (every 30 seconds)
      _enableAutoSave();

      if (kDebugMode) {
        Logger.info('💾 Storage initialized for shop: $_shopId');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('⚠️  Storage initialization failed: $e');
      }
      _isStorageInitialized = false;
    }
  }

  /// Attempt to recover saved state from storage
  Future<void> _attemptRecovery() async {
    if (!_isStorageInitialized) return;

    try {
      final savedState = await _storageService.loadState(_shopId);

      if (savedState != null &&
          (savedState.acceptedIds.isNotEmpty || savedState.rejectedIds.isNotEmpty)) {

        // Update state with recovered data
        state = state.copyWith(
          acceptedItemIds: savedState.acceptedIds,
          rejectedItemIds: savedState.rejectedIds,
        );

        if (kDebugMode) {
          Logger.info('📂 Recovered OCR state from storage:');
          Logger.debug('   Accepted: ${savedState.acceptedIds.length}');
          Logger.debug('   Rejected: ${savedState.rejectedIds.length}');
          Logger.debug('   Saved at: ${savedState.savedAt}');
        }

        // Note: Don't automatically show a recovery dialog here
        // Let the UI decide based on hasRecoverableState getter
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('⚠️  Recovery failed: $e');
      }
    }
  }

  /// Enable auto-save every 30 seconds
  void _enableAutoSave() {
    if (!_isStorageInitialized) return;

    _storageService.enableAutoSave(
      shopId: _shopId,
      getCurrentState: () {
        return OCRStateDraft.fromState(
          acceptedIds: state.acceptedItemIds,
          rejectedIds: state.rejectedItemIds,
          sessionId: state.sessionId,
        );
      },
      interval: const Duration(seconds: 30),
    );

    if (kDebugMode) {
      Logger.info('🔄 Auto-save enabled (30s intervals)');
    }
  }

  /// Manually save current state
  Future<bool> saveCurrentState() async {
    if (!_isStorageInitialized) {
      if (kDebugMode) Logger.warning('⚠️  Storage not initialized');
      return false;
    }

    final draft = OCRStateDraft.fromState(
      acceptedIds: state.acceptedItemIds,
      rejectedIds: state.rejectedItemIds,
      sessionId: state.sessionId,
    );

    final success = await _storageService.saveState(_shopId, draft);

    if (success) {
      _lastAutoSaveTime = DateTime.now();

      if (kDebugMode) {
        Logger.info('💾 Manual save successful');
      }
    }

    return success;
  }

  /// Load saved state (manual recovery)
  Future<bool> loadSavedState() async {
    if (!_isStorageInitialized) return false;

    try {
      final savedState = await _storageService.loadState(_shopId);

      if (savedState != null) {
        // Record current state for undo
        _recordStateForUndo();

        state = state.copyWith(
          acceptedItemIds: savedState.acceptedIds,
          rejectedItemIds: savedState.rejectedIds,
        );

        if (kDebugMode) {
          Logger.info('📂 Loaded saved state');
        }

        return true;
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('❌ Failed to load saved state: $e');
      }
      return false;
    }
  }

  /// Clear saved draft
  Future<bool> clearSavedState() async {
    if (!_isStorageInitialized) return false;

    final success = await _storageService.deleteState(_shopId);

    if (success) {
      _lastAutoSaveTime = null;

      if (kDebugMode) {
        Logger.info('🗑️  Saved state cleared');
      }
    }

    return success;
  }

  /// Check if there's a saved state available
  bool get hasRecoverableState {
    return _isStorageInitialized && _storageService.hasSavedState(_shopId);
  }

  /// Get last auto-save time
  DateTime? get lastAutoSaveTime => _lastAutoSaveTime;

  /// Get storage statistics
  StorageStats? get storageStats {
    return _isStorageInitialized ? _storageService.getStats() : null;
  }

  // ==========================================
  // BRAND CREATION FROM OCR
  // ==========================================

  /// Accept and create all brands from deduplicated items
  Future<BrandCreationResult?> acceptAndCreateAll({
    bool skipZeroStock = true,
  }) async {
    // Use filtered items (garbage already removed)
    final itemsToProcess = state.filteredDeduplicatedItems ?? state.deduplicatedItems;

    if (itemsToProcess == null || itemsToProcess.isEmpty) {
      state = state.copyWith(error: 'No items to create');
      return null;
    }

    try {
      state = state.copyWith(
        isLoading: true,
        error: null,
        step: BatchOCRWorkflowStep.submission,
      );

      if (kDebugMode) {
        Logger.info('🚀 Creating brands from ${itemsToProcess.length} OCR items (filtered)');
        Logger.debug('   Skip zero stock: $skipZeroStock');
        if (state.filteredGarbageItems != null && state.filteredGarbageItems!.isNotEmpty) {
          Logger.debug('   Garbage filtered: ${state.filteredGarbageItems!.length} items');
        }
      }

      // Create brand creation service with apiService
      final BatchBrandCreationService service = BatchBrandCreationService(_apiService);

      final response = await service.createBrandsFromOCR(
        items: itemsToProcess,
        shopId: _shopId,
        skipZeroStock: skipZeroStock,
      );

      if (!response.success || response.data == null) {
        state = state.copyWith(
          isLoading: false,
          error: response.message ?? 'Failed to create brands',
        );
        return null;
      }

      final result = response.data!;

      if (kDebugMode) {
        Logger.info('✅ Brand creation complete:');
        Logger.info('   Success: ${result.successCount}');
        Logger.info('   Failed: ${result.failureCount}');
        Logger.info('   Total stock: ${result.totalStockCreated}');
      }

      state = state.copyWith(
        isLoading: false,
        step: BatchOCRWorkflowStep.complete,
        successMessage: result.summaryMessage,
      );

      return result;
    } catch (e) {
      if (kDebugMode) Logger.error('❌ Brand creation error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Brand creation failed: ${e.toString()}',
      );
      return null;
    }
  }

  // ==========================================
  // WORKFLOW CONTROL
  // ==========================================

  /// Reset workflow to start
  void resetWorkflow() {
    // BEST PRACTICE: Clean up resources before resetting
    _ocrProgressSubscription?.cancel();
    _ocrProgressSubscription = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;

    // Clear time estimation data
    _resetTimeEstimation();

    // Reset state
    state = const BatchOCRState();

    if (kDebugMode) Logger.info('🔄 Workflow reset - all resources cleaned up');
  }

  /// Clear selected images to free memory
  /// Call this after processing is complete or when starting a new batch
  void clearSelectedImages() {
    state = state.copyWith(selectedImagePaths: []);
    if (kDebugMode) Logger.debug('🧹 Selected images cleared to free memory');
  }

  /// Go to specific step (for navigation)
  void goToStep(BatchOCRWorkflowStep step) {
    state = state.copyWith(step: step, error: null);
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Clear success message
  void clearSuccessMessage() {
    state = state.copyWith(successMessage: null);
  }

  // ==========================================
  // REJECTED ITEMS MANAGEMENT
  // ==========================================

  /// Toggle visibility of rejected items in the review screen
  void toggleRejectedItemsVisibility() {
    state = state.copyWith(showRejectedItems: !state.showRejectedItems);

    if (kDebugMode) {
      Logger.debug('🔄 [BatchOCR] Toggled rejected items visibility: ${state.showRejectedItems}');
    }
  }

  /// Recover a wrongly rejected item and add it to the regular items list
  ///
  /// This allows users to recover items that were incorrectly filtered
  /// by the backend's brand validation logic
  Future<void> recoverRejectedItem(String itemId) async {
    if (state.rejectedItems == null || state.rejectedItems!.isEmpty) {
      if (kDebugMode) {
        Logger.warning('⚠️ [BatchOCR] No rejected items to recover');
      }
      return;
    }

    // Find the rejected item
    final rejectedItem = state.rejectedItems!.firstWhere(
      (item) => item.id == itemId,
      orElse: () => throw Exception('Rejected item not found: $itemId'),
    );

    if (!rejectedItem.canRecover) {
      if (kDebugMode) {
        Logger.warning('⚠️ [BatchOCR] Item cannot be recovered: ${rejectedItem.brandText}');
      }
      state = state.copyWith(
        error: 'This item cannot be recovered: ${rejectedItem.rejectionReason}',
      );
      return;
    }

    if (kDebugMode) {
      Logger.info('♻️ [BatchOCR] Recovering rejected item:');
      Logger.debug('   Brand: ${rejectedItem.brandText}');
      Logger.debug('   Reason: ${rejectedItem.rejectionReason}');
    }

    // Convert RejectedItem to DeduplicatedItem
    final recoveredItem = DeduplicatedItem(
      id: rejectedItem.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      brandText: rejectedItem.brandText,
      sizeText: rejectedItem.sizeText ?? '',
      totalStock: rejectedItem.totalStock,
      sellingPrice: rejectedItem.sellingPrice,
      confidence: rejectedItem.confidence,
      sourceSessionIds: rejectedItem.sourceSessionId != null
          ? [rejectedItem.sourceSessionId!]
          : [],
    );

    // Add to filtered deduplicated items (the clean list)
    final updatedCleanItems = [
      ...?state.filteredDeduplicatedItems,
      recoveredItem,
    ];

    // Remove from rejected items
    final updatedRejectedItems = state.rejectedItems!
        .where((item) => item.id != itemId)
        .toList();

    // Update state
    state = state.copyWith(
      filteredDeduplicatedItems: updatedCleanItems,
      rejectedItems: updatedRejectedItems,
      totalRejected: updatedRejectedItems.length,
      successMessage: 'Recovered "${rejectedItem.brandText}" successfully',
    );

    // Clear success message after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        clearSuccessMessage();
      }
    });

    if (kDebugMode) {
      Logger.info('✅ [BatchOCR] Item recovered successfully');
      Logger.debug('   Clean items now: ${state.filteredDeduplicatedItems?.length}');
      Logger.debug('   Rejected items now: ${state.rejectedItems?.length}');
    }
  }
}

// ==========================================
// PROVIDER
// ==========================================

/// Batch OCR workflow provider
///
/// Requires shopId as parameter. Use like:
/// ```dart
/// final batchOCR = ref.watch(batchOCRProvider(shopId));
/// ```
final batchOCRProvider = StateNotifierProvider.family<BatchOCRNotifier, BatchOCRState, String>(
  (ref, shopId) {
    final service = ref.watch(batchOCRServiceProvider);
    final apiService = ref.watch(apiServiceProvider);
    final authService = ref.watch(authServiceProvider);
    // WebSocket will be initialized lazily when OCR is accessed
    // This improves app startup performance and reduces unnecessary connections
    return BatchOCRNotifier(
      service: service,
      apiService: apiService,
      wsService: null,  // Will be created lazily when needed for OCR
      authService: authService,
      shopId: shopId,
    );
  },
);

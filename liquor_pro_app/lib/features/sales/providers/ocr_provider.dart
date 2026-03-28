import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/service_providers.dart' show apiServiceProvider;
import '../models/ocr_models.dart';
import '../services/ocr_service.dart';

/// Provider for OCR Service
final ocrServiceProvider = Provider<OCRService>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return OCRService(apiService: apiService);
});

/// Provider for current OCR session
final currentOCRSessionProvider = StateNotifierProvider<OCRSessionNotifier, AsyncValue<OCRSession?>>((ref) {
  return OCRSessionNotifier(ref);
});

/// State notifier for OCR session
class OCRSessionNotifier extends StateNotifier<AsyncValue<OCRSession?>> {
  final Ref _ref;

  OCRSessionNotifier(this._ref) : super(const AsyncValue.data(null));

  /// Create a new OCR session
  Future<OCRSession> createSession({
    required String imageData,
    required String imageType,
    required String sessionType,
    required String shopId,
  }) async {
    state = const AsyncValue.loading();

    try {
      final ocrService = _ref.read(ocrServiceProvider);
      final session = await ocrService.createOCRSession(
        imageData: imageData,
        imageType: imageType,
        sessionType: sessionType,
        shopId: shopId,
      );

      state = AsyncValue.data(session);
      return session;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  /// Get session status and details
  Future<OCRSessionResponse> getSessionDetails(String sessionId) async {
    try {
      final ocrService = _ref.read(ocrServiceProvider);
      final response = await ocrService.getOCRSession(sessionId);

      // Update current session
      state = AsyncValue.data(response.session);

      return response;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  /// Clear current session
  void clearSession() {
    state = const AsyncValue.data(null);
  }
}

/// Provider for extracted OCR items
final ocrExtractedItemsProvider = StateNotifierProvider<OCRExtractedItemsNotifier, List<OCRExtractedItem>>((ref) {
  return OCRExtractedItemsNotifier(ref);
});

/// State notifier for extracted OCR items
class OCRExtractedItemsNotifier extends StateNotifier<List<OCRExtractedItem>> {
  final Ref _ref;

  OCRExtractedItemsNotifier(this._ref) : super([]);

  /// Set extracted items
  void setItems(List<OCRExtractedItem> items) {
    state = items;
  }

  /// Update item at index
  void updateItem(int index, OCRExtractedItem item) {
    if (index >= 0 && index < state.length) {
      state = [
        ...state.sublist(0, index),
        item,
        ...state.sublist(index + 1),
      ];
    }
  }

  /// Confirm item
  void confirmItem(int index) {
    if (index >= 0 && index < state.length) {
      final item = state[index];
      updateItem(index, item.copyWith(
        isConfirmed: true,
        isRejected: false,
      ));
    }
  }

  /// Reject item
  void rejectItem(int index) {
    if (index >= 0 && index < state.length) {
      final item = state[index];
      updateItem(index, item.copyWith(
        isConfirmed: false,
        isRejected: true,
      ));
    }
  }

  /// Edit item quantity
  void editItemQuantity(int index, int newQuantity) {
    if (index >= 0 && index < state.length) {
      final item = state[index];
      updateItem(index, item.copyWith(
        userCorrectedQuantity: newQuantity,
        isConfirmed: true,
      ));
    }
  }

  /// Edit item product
  void editItemProduct(int index, String productId) {
    if (index >= 0 && index < state.length) {
      final item = state[index];
      updateItem(index, item.copyWith(
        userCorrectedProductId: productId,
        isConfirmed: true,
      ));
    }
  }

  /// Get confirmed items
  List<OCRExtractedItem> getConfirmedItems() {
    return state.where((item) => item.isConfirmed && !item.isRejected).toList();
  }

  /// Get unmatched items
  List<OCRExtractedItem> getUnmatchedItems() {
    return state.where((item) => item.matchedProductId == null).toList();
  }

  /// Clear all items
  void clearItems() {
    state = [];
  }
}

/// Provider for OCR processing status
final ocrProcessingStatusProvider = StateProvider<OCRProcessingStatus>((ref) {
  return OCRProcessingStatus.idle;
});

/// OCR Processing Status enum
enum OCRProcessingStatus {
  idle,
  uploading,
  processing,
  extracting,
  matching,
  completed,
  failed,
}

/// Provider for OCR configuration
final ocrConfigProvider = FutureProvider<OCRMatchingConfig>((ref) async {
  final ocrService = ref.watch(ocrServiceProvider);
  return await ocrService.getOCRConfig();
});

/// Provider for brand aliases
final brandAliasesProvider = StateNotifierProvider.family<BrandAliasesNotifier, AsyncValue<List<BrandAlias>>, String>(
  (ref, brandId) {
    return BrandAliasesNotifier(ref, brandId);
  },
);

/// State notifier for brand aliases
class BrandAliasesNotifier extends StateNotifier<AsyncValue<List<BrandAlias>>> {
  final Ref _ref;
  final String brandId;

  BrandAliasesNotifier(this._ref, this.brandId) : super(const AsyncValue.loading()) {
    loadAliases();
  }

  /// Load brand aliases
  Future<void> loadAliases() async {
    try {
      final ocrService = _ref.read(ocrServiceProvider);
      final aliases = await ocrService.getBrandAliases(brandId);
      state = AsyncValue.data(aliases);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Add new alias
  Future<void> addAlias({
    required String aliasText,
    required String aliasType,
  }) async {
    try {
      final ocrService = _ref.read(ocrServiceProvider);
      final newAlias = await ocrService.createBrandAlias(
        brandId: brandId,
        aliasText: aliasText,
        aliasType: aliasType,
      );

      // Update state with new alias
      state.whenData((aliases) {
        state = AsyncValue.data([newAlias, ...aliases]);
      });
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }
}

/// Provider for OCR statistics
final ocrStatsProvider = Provider<OCRStats>((ref) {
  final items = ref.watch(ocrExtractedItemsProvider);

  return OCRStats(
    totalItems: items.length,
    matchedItems: items.where((i) => i.matchedProductId != null).length,
    unmatchedItems: items.where((i) => i.matchedProductId == null).length,
    confirmedItems: items.where((i) => i.isConfirmed).length,
    rejectedItems: items.where((i) => i.isRejected).length,
    averageConfidence: items.isEmpty
        ? 0
        : items.map((i) => i.matchConfidence).reduce((a, b) => a + b) / items.length,
  );
});

/// OCR Statistics model
class OCRStats {
  final int totalItems;
  final int matchedItems;
  final int unmatchedItems;
  final int confirmedItems;
  final int rejectedItems;
  final double averageConfidence;

  OCRStats({
    required this.totalItems,
    required this.matchedItems,
    required this.unmatchedItems,
    required this.confirmedItems,
    required this.rejectedItems,
    required this.averageConfidence,
  });

  bool get requiresReview => unmatchedItems > 0 || averageConfidence < 95;

  double get matchRate => totalItems > 0 ? matchedItems / totalItems * 100 : 0;
}
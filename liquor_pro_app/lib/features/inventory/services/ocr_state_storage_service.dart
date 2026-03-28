import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Offline Storage Service for OCR Review State
///
/// FEATURES:
/// - Hive-based persistent storage
/// - Auto-save drafts (configurable interval)
/// - Crash recovery
/// - Manual save/load/delete operations
/// - Storage management (clear old drafts)
/// - Last saved timestamp tracking
///
/// USAGE:
/// ```dart
/// final storage = OCRStateStorageService();
/// await storage.initialize();
///
/// // Auto-save
/// storage.enableAutoSave(
///   shopId: 'shop-123',
///   getCurrentState: () => myCurrentState,
///   interval: Duration(seconds: 30),
/// );
///
/// // Manual save
/// await storage.saveState('shop-123', myState);
///
/// // Recover on startup
/// final recovered = await storage.loadState('shop-123');
/// if (recovered != null) {
///   // Restore state
/// }
///
/// // Clean up
/// storage.dispose();
/// ```
class OCRStateStorageService {
  static const String _boxName = 'ocr_review_drafts';
  static const String _metadataKey = 'metadata';

  Box<String>? _box;
  Timer? _autoSaveTimer;
  bool _isInitialized = false;

  /// Initialize Hive and open the storage box
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize Hive (if not already done)
      if (!Hive.isAdapterRegistered(0)) {
        await Hive.initFlutter();
      }

      // Open box for OCR drafts
      _box = await Hive.openBox<String>(_boxName);
      _isInitialized = true;

      if (kDebugMode) {
        print('💾 OCR State Storage initialized');
        print('   Box: $_boxName');
        print('   Stored drafts: ${_box?.length ?? 0}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize OCR storage: $e');
      }
    }
  }

  /// Save OCR state to persistent storage
  Future<bool> saveState(
    String shopId,
    OCRStateDraft state,
  ) async {
    if (!_isInitialized || _box == null) {
      if (kDebugMode) print('⚠️  Storage not initialized');
      return false;
    }

    try {
      final key = _getDraftKey(shopId);
      final json = state.toJson();
      final jsonString = jsonEncode(json);

      await _box!.put(key, jsonString);

      // Update metadata
      await _updateMetadata(shopId, state);

      if (kDebugMode) {
        print('💾 OCR state saved for shop: $shopId');
        print('   Accepted: ${state.acceptedIds.length}');
        print('   Rejected: ${state.rejectedIds.length}');
        print('   Size: ${jsonString.length} bytes');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to save OCR state: $e');
      }
      return false;
    }
  }

  /// Load OCR state from persistent storage
  Future<OCRStateDraft?> loadState(String shopId) async {
    if (!_isInitialized || _box == null) {
      if (kDebugMode) print('⚠️  Storage not initialized');
      return null;
    }

    try {
      final key = _getDraftKey(shopId);
      final jsonString = _box!.get(key);

      if (jsonString == null) {
        if (kDebugMode) print('ℹ️  No saved state for shop: $shopId');
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      final state = OCRStateDraft.fromJson(json);

      if (kDebugMode) {
        print('📂 OCR state loaded for shop: $shopId');
        print('   Accepted: ${state.acceptedIds.length}');
        print('   Rejected: ${state.rejectedIds.length}');
        print('   Saved at: ${state.savedAt}');
      }

      return state;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to load OCR state: $e');
      }
      return null;
    }
  }

  /// Delete saved state for a shop
  Future<bool> deleteState(String shopId) async {
    if (!_isInitialized || _box == null) return false;

    try {
      final key = _getDraftKey(shopId);
      await _box!.delete(key);

      if (kDebugMode) {
        print('🗑️  OCR state deleted for shop: $shopId');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to delete OCR state: $e');
      }
      return false;
    }
  }

  /// Check if saved state exists for a shop
  bool hasSavedState(String shopId) {
    if (!_isInitialized || _box == null) return false;
    final key = _getDraftKey(shopId);
    return _box!.containsKey(key);
  }

  /// Get last saved timestamp for a shop
  DateTime? getLastSavedTime(String shopId) {
    if (!_isInitialized || _box == null) return null;

    try {
      final metadataString = _box!.get(_metadataKey);
      if (metadataString == null) return null;

      final metadata = jsonDecode(metadataString) as Map<String, dynamic>;
      final shopMetadata = metadata[shopId] as Map<String, dynamic>?;
      if (shopMetadata == null) return null;

      final timestamp = shopMetadata['lastSaved'] as String?;
      return timestamp != null ? DateTime.parse(timestamp) : null;
    } catch (e) {
      return null;
    }
  }

  /// Enable auto-save with configurable interval
  void enableAutoSave({
    required String shopId,
    required OCRStateDraft Function() getCurrentState,
    Duration interval = const Duration(seconds: 30),
  }) {
    // Cancel existing timer
    _autoSaveTimer?.cancel();

    // Create new periodic timer
    _autoSaveTimer = Timer.periodic(interval, (timer) async {
      final state = getCurrentState();

      // Only save if there are accepted or rejected items
      if (state.acceptedIds.isEmpty && state.rejectedIds.isEmpty) {
        if (kDebugMode) {
          print('⏭️  Auto-save skipped (no changes)');
        }
        return;
      }

      final success = await saveState(shopId, state);

      if (kDebugMode && success) {
        print('⚡ Auto-saved OCR state for shop: $shopId');
      }
    });

    if (kDebugMode) {
      print('🔄 Auto-save enabled for shop: $shopId');
      print('   Interval: ${interval.inSeconds}s');
    }
  }

  /// Disable auto-save
  void disableAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    if (kDebugMode) {
      print('⏸️  Auto-save disabled');
    }
  }

  /// Get all saved shop IDs
  List<String> getSavedShopIds() {
    if (!_isInitialized || _box == null) return [];

    try {
      final keys = _box!.keys
          .where((key) => key.toString().startsWith('draft_'))
          .map((key) => key.toString().replaceFirst('draft_', ''))
          .toList();

      return keys;
    } catch (e) {
      return [];
    }
  }

  /// Clear all saved drafts
  Future<void> clearAll() async {
    if (!_isInitialized || _box == null) return;

    try {
      await _box!.clear();

      if (kDebugMode) {
        print('🗑️  All OCR drafts cleared');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to clear drafts: $e');
      }
    }
  }

  /// Clear old drafts (older than specified duration)
  Future<int> clearOldDrafts({
    Duration maxAge = const Duration(days: 7),
  }) async {
    if (!_isInitialized || _box == null) return 0;

    try {
      final now = DateTime.now();
      final cutoff = now.subtract(maxAge);
      int deletedCount = 0;

      final shopIds = getSavedShopIds();

      for (final shopId in shopIds) {
        final lastSaved = getLastSavedTime(shopId);
        if (lastSaved != null && lastSaved.isBefore(cutoff)) {
          await deleteState(shopId);
          deletedCount++;
        }
      }

      if (kDebugMode) {
        print('🗑️  Cleared $deletedCount old drafts (older than ${maxAge.inDays} days)');
      }

      return deletedCount;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to clear old drafts: $e');
      }
      return 0;
    }
  }

  /// Get storage statistics
  StorageStats getStats() {
    if (!_isInitialized || _box == null) {
      return StorageStats(
        totalDrafts: 0,
        totalSizeBytes: 0,
        shopIds: [],
      );
    }

    try {
      final shopIds = getSavedShopIds();
      int totalSize = 0;

      for (final shopId in shopIds) {
        final key = _getDraftKey(shopId);
        final data = _box!.get(key);
        if (data != null) {
          totalSize += data.length;
        }
      }

      return StorageStats(
        totalDrafts: shopIds.length,
        totalSizeBytes: totalSize,
        shopIds: shopIds,
      );
    } catch (e) {
      return StorageStats(
        totalDrafts: 0,
        totalSizeBytes: 0,
        shopIds: [],
      );
    }
  }

  /// Dispose resources
  void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;

    if (kDebugMode) {
      print('🔌 OCR State Storage disposed');
    }
  }

  // Private helpers

  String _getDraftKey(String shopId) => 'draft_$shopId';

  Future<void> _updateMetadata(String shopId, OCRStateDraft state) async {
    try {
      final metadataString = _box!.get(_metadataKey);
      Map<String, dynamic> metadata = {};

      if (metadataString != null) {
        metadata = jsonDecode(metadataString) as Map<String, dynamic>;
      }

      metadata[shopId] = {
        'lastSaved': state.savedAt.toIso8601String(),
        'acceptedCount': state.acceptedIds.length,
        'rejectedCount': state.rejectedIds.length,
      };

      await _box!.put(_metadataKey, jsonEncode(metadata));
    } catch (e) {
      if (kDebugMode) {
        print('⚠️  Failed to update metadata: $e');
      }
    }
  }
}

/// Draft state for OCR review (lightweight for storage)
class OCRStateDraft {
  final Set<String> acceptedIds;
  final Set<String> rejectedIds;
  final DateTime savedAt;
  final String? sessionId;

  OCRStateDraft({
    required this.acceptedIds,
    required this.rejectedIds,
    DateTime? savedAt,
    this.sessionId,
  }) : savedAt = savedAt ?? DateTime.now();

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'acceptedIds': acceptedIds.toList(),
      'rejectedIds': rejectedIds.toList(),
      'savedAt': savedAt.toIso8601String(),
      'sessionId': sessionId,
    };
  }

  /// Create from JSON
  factory OCRStateDraft.fromJson(Map<String, dynamic> json) {
    return OCRStateDraft(
      acceptedIds: (json['acceptedIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          {},
      rejectedIds: (json['rejectedIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          {},
      savedAt: json['savedAt'] != null
          ? DateTime.parse(json['savedAt'] as String)
          : DateTime.now(),
      sessionId: json['sessionId'] as String?,
    );
  }

  /// Create from current state
  factory OCRStateDraft.fromState({
    required Set<String> acceptedIds,
    required Set<String> rejectedIds,
    String? sessionId,
  }) {
    return OCRStateDraft(
      acceptedIds: Set<String>.from(acceptedIds),
      rejectedIds: Set<String>.from(rejectedIds),
      sessionId: sessionId,
    );
  }

  @override
  String toString() {
    return 'OCRStateDraft(accepted: ${acceptedIds.length}, '
        'rejected: ${rejectedIds.length}, savedAt: $savedAt)';
  }
}

/// Storage statistics
class StorageStats {
  final int totalDrafts;
  final int totalSizeBytes;
  final List<String> shopIds;

  StorageStats({
    required this.totalDrafts,
    required this.totalSizeBytes,
    required this.shopIds,
  });

  /// Get human-readable size
  String get sizeFormatted {
    if (totalSizeBytes < 1024) {
      return '$totalSizeBytes B';
    } else if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  @override
  String toString() {
    return 'StorageStats(drafts: $totalDrafts, size: $sizeFormatted)';
  }
}

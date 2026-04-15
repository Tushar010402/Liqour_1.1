import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/config/debug_performance_config.dart';
import '../../../core/utils/logger.dart';
import '../models/daily_sales_draft.dart';
import 'draft_api_service.dart';

/// Daily Sales Draft Storage Service
/// Provides industrial-grade auto-save functionality for Daily Sales Entry
///
/// Architecture: OFFLINE-FIRST with BACKGROUND SYNC
/// - Local Hive storage is primary (fast, always available)
/// - Backend sync happens in background (cross-device support)
/// - Conflict resolution: Last-write-wins based on savedAt timestamp
///
/// Features:
/// - Hive-based local persistence (fast, reliable)
/// - Auto-save with debouncing (5 seconds)
/// - Per shop + date draft management
/// - Auto-cleanup of old drafts (3 days TTL)
/// - Metadata tracking (last saved time)
/// - Background sync to backend (cross-device recovery)
///
/// Usage:
/// ```dart
/// final service = DailySalesDraftService();
/// await service.initialize();
///
/// // Auto-save
/// service.enableAutoSave(
///   shopId: 'shop-123',
///   recordDate: DateTime.now(),
///   getCurrentDraft: () => buildCurrentDraft(),
/// );
///
/// // Manual save
/// await service.saveDraft(shopId, date, draft);
///
/// // Load on screen open
/// final draft = await service.loadDraft(shopId, date);
/// ```
class DailySalesDraftService {
  static const String _boxName = 'daily_sales_drafts';
  static const int _draftTTLDays = 3; // Keep drafts for 3 days

  Box<Map>? _box;
  Timer? _autoSaveTimer;
  Timer? _debounceTimer; // For debounced onChange saves
  Timer? _syncTimer; // For periodic backend sync
  DailySalesDraft Function()? _getDraftCallback;
  String? _currentShopId;
  DateTime? _currentRecordDate;
  String? _lastDraftHash; // Track if draft changed to avoid redundant saves

  // Backend API service for cross-device sync (optional - set via setApiService)
  DraftApiService? _apiService;
  bool _isSyncing = false;
  bool _isSaving = false; // Lock to prevent concurrent saves (race condition fix)

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBMISSION LOCK - Prevents ALL draft saves after submission starts
  // This fixes the race condition where:
  // 1. User submits record successfully
  // 2. clearDraft() is called (DELETE request sent)
  // 3. Auto-save timer fires and sends POST (re-creates draft!)
  //
  // With this lock:
  // - lockForSubmission() is called BEFORE submission starts
  // - All saveDraft/pushToBackend calls are blocked
  // - unlockAfterSubmission() is called after navigation completes
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isLockedForSubmission = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // RECENTLY SUBMITTED TRACKER - Prevents draft restoration after submission
  // This handles the case where:
  // 1. Record submitted → DELETE sent to backend
  // 2. But POST (from auto-save) completes AFTER DELETE (race condition)
  // 3. User navigates back to Daily Sales Entry
  // 4. syncWithBackend() finds stale draft on backend
  //
  // With this tracker:
  // - markAsJustSubmitted(shopId, date) records the submission
  // - syncWithBackend() checks this before restoring from backend
  // - Entries expire after 60 seconds (safety window)
  // ═══════════════════════════════════════════════════════════════════════════
  final Map<String, DateTime> _recentlySubmittedKeys = {};
  static const Duration _submissionBlockWindow = Duration(seconds: 60);

  /// Mark a shop+date as just submitted
  /// This prevents draft restoration from backend for 60 seconds
  void markAsJustSubmitted(String shopId, DateTime recordDate) {
    final key = _generateKey(shopId, recordDate);
    _recentlySubmittedKeys[key] = DateTime.now();
    if (kDebugMode) {
      Logger.info('[DraftService] Marked as just submitted: $key (blocked for ${_submissionBlockWindow.inSeconds}s)');
    }
  }

  /// Check if a shop+date was recently submitted
  bool _wasRecentlySubmitted(String shopId, DateTime recordDate) {
    final key = _generateKey(shopId, recordDate);
    final submittedAt = _recentlySubmittedKeys[key];
    if (submittedAt == null) return false;

    final elapsed = DateTime.now().difference(submittedAt);
    if (elapsed > _submissionBlockWindow) {
      // Expired - remove from tracker
      _recentlySubmittedKeys.remove(key);
      return false;
    }

    if (kDebugMode) {
      final remaining = _submissionBlockWindow - elapsed;
      Logger.info('[DraftService] Draft blocked (recently submitted): $key (${remaining.inSeconds}s remaining)');
    }
    return true;
  }

  /// Clear expired entries from tracker
  void _cleanupExpiredSubmissions() {
    final now = DateTime.now();
    _recentlySubmittedKeys.removeWhere((key, submittedAt) {
      return now.difference(submittedAt) > _submissionBlockWindow;
    });
  }

  /// Lock draft operations before submission starts
  /// Call this BEFORE calling createRecord() or updateRecord()
  void lockForSubmission() {
    _isLockedForSubmission = true;
    // Also cancel any pending timers
    _autoSaveTimer?.cancel();
    _debounceTimer?.cancel();
    if (kDebugMode) {
      Logger.info('[DraftService] LOCKED for submission - all draft saves blocked');
    }
  }

  /// Unlock draft operations after submission completes
  /// Call this after navigation away from the screen
  void unlockAfterSubmission() {
    _isLockedForSubmission = false;
    if (kDebugMode) {
      Logger.info('[DraftService] UNLOCKED after submission');
    }
  }

  /// Check if drafts are locked for submission
  bool get isLockedForSubmission => _isLockedForSubmission;

  /// Initialize Hive box
  /// Call this once during app startup or before first use
  Future<void> initialize() async {
    if (_box != null && _box!.isOpen) {
      Logger.info('[DraftService] Already initialized');
      return;
    }

    try {
      _box = await Hive.openBox<Map>(_boxName);
      Logger.info('[DraftService] Initialized - ${_box!.length} drafts stored');

      // Auto-cleanup old drafts on init
      await clearOldDrafts();
    } catch (e) {
      Logger.error('[DraftService] Initialization failed: $e');
      rethrow;
    }
  }

  /// Generate storage key for shop + date combination
  String _generateKey(String shopId, DateTime recordDate) {
    final dateKey = recordDate.toLocal().toString().split(' ')[0]; // YYYY-MM-DD
    return 'draft_${shopId}_$dateKey';
  }

  /// Save draft to storage (local first, then background sync to backend)
  Future<void> saveDraft(
    String shopId,
    DateTime recordDate,
    DailySalesDraft draft,
  ) async {
    // ═══════════════════════════════════════════════════════════════════════
    // CRITICAL: Check submission lock BEFORE any save operation
    // This prevents draft re-creation after submission deletes it
    // ═══════════════════════════════════════════════════════════════════════
    if (_isLockedForSubmission) {
      if (kDebugMode) {
        Logger.info('[DraftService] saveDraft BLOCKED - submission in progress');
      }
      return;
    }

    await _ensureInitialized();

    try {
      final key = _generateKey(shopId, recordDate);
      final json = draft.toJson();

      // Save locally first (fast, reliable)
      await _box!.put(key, json);
      if (kDebugMode) {
        Logger.debug('[DraftService] Saved draft: $key (${draft.productCount} products, ₹${draft.totalPayment})');
      }

      // Push to backend in background (non-blocking, fire-and-forget)
      if (_apiService != null) {
        pushToBackend(draft); // Don't await - background sync
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftService] Save failed: $e');
      }
      rethrow;
    }
  }

  /// Load draft from storage
  Future<DailySalesDraft?> loadDraft(
    String shopId,
    DateTime recordDate,
  ) async {
    await _ensureInitialized();

    try {
      final key = _generateKey(shopId, recordDate);
      final json = _box!.get(key);

      if (json == null) {
        Logger.debug('[DraftService] No draft found: $key');
        return null;
      }

      final draft = DailySalesDraft.fromJson(Map<String, dynamic>.from(json));

      // Check if draft is expired
      if (draft.age.inDays > _draftTTLDays) {
        Logger.info('[DraftService] Draft expired (${draft.age.inDays} days old), deleting: $key');
        await deleteDraft(shopId, recordDate);
        return null;
      }

      Logger.debug('[DraftService] Loaded draft: $key (${draft.ageText})');
      return draft;
    } catch (e) {
      Logger.error('[DraftService] Load failed: $e');
      return null;
    }
  }

  /// Delete specific draft
  Future<void> deleteDraft(String shopId, DateTime recordDate) async {
    await _ensureInitialized();

    try {
      final key = _generateKey(shopId, recordDate);
      await _box!.delete(key);
      Logger.info('[DraftService] Deleted draft: $key');
    } catch (e) {
      Logger.error('[DraftService] Delete failed: $e');
    }
  }

  /// Check if draft exists
  Future<bool> hasDraft(String shopId, DateTime recordDate) async {
    await _ensureInitialized();

    final key = _generateKey(shopId, recordDate);
    return _box!.containsKey(key);
  }

  /// Get last saved time for a draft
  Future<DateTime?> getLastSavedTime(String shopId, DateTime recordDate) async {
    final draft = await loadDraft(shopId, recordDate);
    return draft?.savedAt;
  }

  /// Enable auto-save with debouncing
  /// Automatically saves draft every [interval] seconds after data changes
  ///
  /// Example:
  /// ```dart
  /// service.enableAutoSave(
  ///   shopId: 'shop-123',
  ///   recordDate: DateTime.now(),
  ///   getCurrentDraft: () {
  ///     return DailySalesDraft(
  ///       productQuantities: {...},
  ///       cashAmount: cashController.text,
  ///       // ... other fields
  ///     );
  ///   },
  ///   interval: Duration(seconds: 2),
  /// );
  /// ```
  void enableAutoSave({
    required String shopId,
    required DateTime recordDate,
    required DailySalesDraft Function() getCurrentDraft,
    Duration interval = const Duration(seconds: 5), // Increased from 2s to 5s
  }) {
    // Store current context
    _currentShopId = shopId;
    _currentRecordDate = recordDate;
    _getDraftCallback = getCurrentDraft;
    _lastDraftHash = null; // Reset hash tracking for new session

    // Cancel existing timer
    _autoSaveTimer?.cancel();

    // Start new auto-save timer
    _autoSaveTimer = Timer.periodic(interval, (timer) async {
      await _performAutoSave();
    });

    Logger.info('[DraftService] Auto-save enabled (every ${interval.inSeconds}s)');
  }

  /// Disable auto-save
  void disableAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _getDraftCallback = null;
    _currentShopId = null;
    _currentRecordDate = null;
    _lastDraftHash = null; // Reset hash tracking
    Logger.info('[DraftService] Auto-save disabled');
  }

  /// Perform auto-save (called by timer)
  /// INDUSTRIAL-GRADE: Uses lock to prevent concurrent saves (race condition fix)
  Future<void> _performAutoSave() async {
    // CRITICAL: Check if already saving to prevent race conditions
    if (_isSaving) {
      return;
    }

    if (_getDraftCallback == null || _currentShopId == null || _currentRecordDate == null) {
      return;
    }

    _isSaving = true;
    try {
      final draft = _getDraftCallback!();

      // Skip if draft is truly empty (no items AND no payments)
      // Fixed: Previously skipped payment-only entries
      if (draft.isEmpty && draft.totalPayment == 0) {
        return;
      }

      // Generate a comprehensive hash to detect ALL changes
      // Fixed: Previously missing card, credit, expense, notes
      final currentHash = [
        draft.productCount,
        draft.totalPayment.toStringAsFixed(0),
        draft.cashAmount.toStringAsFixed(0),
        draft.cardAmount.toStringAsFixed(0),
        draft.upiAmount.toStringAsFixed(0),
        draft.creditAmount.toStringAsFixed(0),
        draft.expenseAmount.toStringAsFixed(0),
        draft.notes.hashCode,
      ].join('_');

      if (currentHash == _lastDraftHash) {
        // Draft hasn't changed, skip save to reduce log spam
        return;
      }
      _lastDraftHash = currentHash;

      await saveDraft(_currentShopId!, _currentRecordDate!, draft);
    } catch (e) {
      Logger.error('[DraftService] Auto-save error: $e');
    } finally {
      _isSaving = false;
    }
  }

  /// Manually trigger a save (useful for "Save & Exit" scenarios)
  Future<void> manualSave() async {
    await _performAutoSave();
  }

  /// Debounced save (Swiggy/Zomato style) - saves 500ms after last change
  /// Call this on every onChange event for instant UX feel
  ///
  /// Example:
  /// ```dart
  /// TextField(
  ///   onChanged: (value) {
  ///     provider.updateCash(value);
  ///     service.saveDraftDebounced(); // Saves after 500ms of no changes
  ///   },
  /// )
  /// ```
  void saveDraftDebounced() {
    // Cancel existing timer
    _debounceTimer?.cancel();

    // Start new timer - saves 500ms after user stops typing
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      await _performAutoSave();
    });
  }

  /// Cancel any pending debounced save
  void cancelDebouncedSave() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  /// Clear all drafts (for testing or user-requested data wipe)
  Future<void> clearAllDrafts() async {
    await _ensureInitialized();

    try {
      final count = _box!.length;
      await _box!.clear();
      Logger.info('[DraftService] Cleared all drafts ($count deleted)');
    } catch (e) {
      Logger.error('[DraftService] Clear all failed: $e');
    }
  }

  /// Clear drafts older than TTL (3 days)
  /// Called automatically on initialization
  Future<void> clearOldDrafts() async {
    await _ensureInitialized();

    try {
      final now = DateTime.now();
      final keysToDelete = <String>[];

      for (final key in _box!.keys) {
        final json = _box!.get(key);
        if (json == null) continue;

        try {
          final draft = DailySalesDraft.fromJson(Map<String, dynamic>.from(json));
          final ageInDays = now.difference(draft.savedAt).inDays;

          if (ageInDays > _draftTTLDays) {
            keysToDelete.add(key.toString());
          }
        } catch (e) {
          // Invalid draft, mark for deletion
          keysToDelete.add(key.toString());
        }
      }

      if (keysToDelete.isNotEmpty) {
        for (final key in keysToDelete) {
          await _box!.delete(key);
        }
        Logger.info('[DraftService] Cleaned up ${keysToDelete.length} old drafts');
      } else {
        Logger.info('[DraftService] No old drafts to clean');
      }
    } catch (e) {
      Logger.error('[DraftService] Cleanup failed: $e');
    }
  }

  /// Get all stored drafts (for debugging/admin UI)
  Future<List<DailySalesDraft>> getAllDrafts() async {
    await _ensureInitialized();

    final drafts = <DailySalesDraft>[];

    for (final value in _box!.values) {
      try {
        final draft = DailySalesDraft.fromJson(Map<String, dynamic>.from(value));
        drafts.add(draft);
      } catch (e) {
        Logger.warning('[DraftService] Skipped invalid draft: $e');
      }
    }

    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt)); // Newest first
    return drafts;
  }

  /// Get draft count
  Future<int> getDraftCount() async {
    await _ensureInitialized();
    return _box!.length;
  }

  /// Close service and cleanup
  Future<void> dispose() async {
    disableAutoSave();
    cancelDebouncedSave();
    _syncTimer?.cancel();
    _syncTimer = null;
    // Don't close box - it's shared across app
    if (kDebugMode) {
      Logger.info('[DraftService] Disposed');
    }
  }

  /// Ensure box is initialized
  Future<void> _ensureInitialized() async {
    if (_box == null || !_box!.isOpen) {
      await initialize();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // BACKEND SYNC METHODS (Offline-First Pattern)
  // ═══════════════════════════════════════════════════════════════

  /// Set the API service for backend sync (call during app initialization)
  void setApiService(DraftApiService apiService) {
    _apiService = apiService;
    if (kDebugMode) {
      Logger.info('[DraftService] Backend sync enabled');
    }
  }

  /// Start periodic background sync.
  /// Interval is relaxed in debug mode to reduce simulator CPU load.
  void startBackgroundSync() {
    _syncTimer?.cancel();
    final interval = DebugPerformanceConfig.draftSyncInterval;
    _syncTimer = Timer.periodic(interval, (timer) async {
      await _performBackgroundSync();
    });
    if (kDebugMode) {
      Logger.info('[DraftService] Background sync started (every ${interval.inSeconds}s)');
    }
  }

  /// Stop background sync
  void stopBackgroundSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    if (kDebugMode) {
      Logger.info('[DraftService] Background sync stopped');
    }
  }

  /// Perform background sync of all local drafts to backend
  Future<void> _performBackgroundSync() async {
    if (_apiService == null || _isSyncing) return;

    _isSyncing = true;
    try {
      final localDrafts = await getAllDrafts();

      for (final draft in localDrafts) {
        if (draft.shopId.isNotEmpty) {
          await _apiService!.saveDraft(draft);
        }
      }

      if (kDebugMode && localDrafts.isNotEmpty) {
        Logger.info('[DraftService] Synced ${localDrafts.length} drafts to backend');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('[DraftService] Background sync error: $e');
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync specific draft with backend (call on load to get latest)
  /// Returns the draft with more content (CONTENT-AWARE conflict resolution)
  ///
  /// CRITICAL: This ensures drafts saved to backend persist even after app restart
  /// by preferring drafts with MORE data over empty drafts.
  ///
  /// BEST PRACTICE - THREE-LAYER VALIDATION:
  /// 1. Check if submission is actively in progress (local lock)
  /// 2. Check if recently submitted (local 60-second cache)
  /// 3. CHECK BACKEND if record exists (SINGLE SOURCE OF TRUTH - PERMANENT)
  ///
  /// The backend check is the PERMANENT solution - even if app restarts,
  /// the backend knows if a record was submitted and will block draft restore.
  Future<DailySalesDraft?> syncWithBackend(String shopId, DateTime recordDate) async {
    // Clean up expired submission blocks
    _cleanupExpiredSubmissions();

    // ═══════════════════════════════════════════════════════════════════════
    // CHECK 1: Skip if submission is actively in progress (local lock)
    // ═══════════════════════════════════════════════════════════════════════
    if (_isLockedForSubmission) {
      if (kDebugMode) {
        Logger.info('[DraftService] syncWithBackend BLOCKED - submission in progress');
      }
      return null;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CHECK 2: Skip if this shop+date was recently submitted (local cache)
    // This is a fast local check for immediate post-submission navigation
    // ═══════════════════════════════════════════════════════════════════════
    if (_wasRecentlySubmitted(shopId, recordDate)) {
      if (kDebugMode) {
        Logger.info('[DraftService] syncWithBackend BLOCKED - recently submitted (local cache)');
      }
      return null;
    }

    if (_apiService == null) {
      // No API service - just return local
      return loadDraft(shopId, recordDate);
    }

    try {
      // ═══════════════════════════════════════════════════════════════════════
      // CHECK 3: SINGLE SOURCE OF TRUTH - Ask backend if record exists
      // This is the PERMANENT solution that works even after app restart
      // ═══════════════════════════════════════════════════════════════════════
      final recordCheck = await _apiService!.checkRecordExists(shopId, recordDate);

      if (recordCheck.shouldBlockDraftRestore) {
        if (kDebugMode) {
          Logger.info('[DraftService] BACKEND says record exists (status: ${recordCheck.status}) - PERMANENTLY blocking draft');
        }

        // Delete local draft since record is already submitted
        await deleteDraft(shopId, recordDate);

        // Also try to delete from backend draft storage (cleanup)
        try {
          await _apiService!.deleteDraft(shopId, recordDate);
        } catch (_) {
          // Ignore cleanup errors
        }

        return null;
      }

      if (kDebugMode) {
        Logger.info('[DraftService] Backend check passed - no blocking record exists');
      }

      // Now proceed with normal draft sync
      final localDraft = await loadDraft(shopId, recordDate);

      if (kDebugMode) {
        Logger.debug('[DraftService] syncWithBackend: local has ${localDraft?.productCount ?? 0} items');
      }

      // syncDraft now uses content-aware resolution (prefers more items)
      final syncedDraft = await _apiService!.syncDraft(shopId, recordDate, localDraft);

      // If synced draft has more content than local, save it locally
      // This is CRITICAL for recovering data after app restart
      if (syncedDraft != null) {
        final syncedItems = syncedDraft.productCount;
        final localItems = localDraft?.productCount ?? 0;

        if (syncedItems > localItems) {
          // Backend had more data - save locally (don't await - non-blocking)
          _saveLocalOnly(shopId, recordDate, syncedDraft);
          if (kDebugMode) {
            Logger.info('[DraftService] Downloaded draft from backend: $syncedItems items');
          }
        } else if (localDraft == null && syncedDraft.isNotEmpty) {
          // No local but have remote with data - save locally
          _saveLocalOnly(shopId, recordDate, syncedDraft);
          if (kDebugMode) {
            Logger.info('[DraftService] Downloaded new draft from backend: $syncedItems items');
          }
        }
      }

      return syncedDraft ?? localDraft;
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('[DraftService] Sync error, using local: $e');
      }
      return loadDraft(shopId, recordDate);
    }
  }

  /// Save draft to local Hive only (no backend sync)
  /// Used for updating local cache from backend without triggering re-sync
  Future<void> _saveLocalOnly(String shopId, DateTime recordDate, DailySalesDraft draft) async {
    await _ensureInitialized();
    try {
      final key = _generateKey(shopId, recordDate);
      final json = draft.toJson();
      await _box!.put(key, json);
      if (kDebugMode) {
        Logger.debug('[DraftService] Saved locally (from backend): $key');
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftService] Local save failed: $e');
      }
    }
  }

  /// Push local draft to backend immediately (call on save)
  /// INDUSTRIAL-GRADE: Uses Future.microtask for true non-blocking execution
  /// This prevents UI lag during network operations
  void pushToBackend(DailySalesDraft draft) {
    // ═══════════════════════════════════════════════════════════════════════
    // CRITICAL: Check submission lock BEFORE pushing to backend
    // This is the KEY fix for the race condition where:
    // - Submission starts → DELETE sent to delete draft
    // - But pushToBackend fires (from auto-save) → POST re-creates draft!
    // ═══════════════════════════════════════════════════════════════════════
    if (_isLockedForSubmission) {
      if (kDebugMode) {
        Logger.info('[DraftService] pushToBackend BLOCKED - submission in progress');
      }
      return;
    }

    if (_apiService == null) return;

    // Fire-and-forget with microtask isolation
    // This ensures the network call doesn't block the current event loop
    Future.microtask(() async {
      // Double-check lock inside microtask (submission may have started while waiting)
      if (_isLockedForSubmission) {
        if (kDebugMode) {
          Logger.info('[DraftService] pushToBackend BLOCKED (in microtask) - submission in progress');
        }
        return;
      }

      try {
        await _apiService!.saveDraft(draft);
      } catch (e) {
        if (kDebugMode) {
          Logger.warning('[DraftService] Push to backend failed: $e');
        }
        // Silently fail - local is primary, backend is secondary
      }
    });
  }

  /// Delete draft from both local and backend
  Future<void> deleteDraftWithSync(String shopId, DateTime recordDate) async {
    // Delete locally first (fast)
    await deleteDraft(shopId, recordDate);

    // Then delete from backend (background)
    if (_apiService != null) {
      try {
        await _apiService!.deleteDraft(shopId, recordDate);
      } catch (e) {
        if (kDebugMode) {
          Logger.warning('[DraftService] Backend delete failed: $e');
        }
      }
    }
  }
}

import 'package:flutter/foundation.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/utils/date_time_helper.dart';
import '../../../core/utils/logger.dart';
import '../models/daily_sales_draft.dart';

/// Response model for record existence check
/// SINGLE SOURCE OF TRUTH from backend for draft management
class RecordExistsResponse {
  final bool exists;
  final bool canSubmit;
  final String status;
  final String? recordId;
  final int recordCount;

  RecordExistsResponse({
    required this.exists,
    required this.canSubmit,
    required this.status,
    this.recordId,
    required this.recordCount,
  });

  /// Returns true if a finalized record exists that blocks draft restoration
  /// (i.e., record is approved or pending)
  bool get shouldBlockDraftRestore => exists && !canSubmit;

  @override
  String toString() =>
      'RecordExistsResponse(exists: $exists, canSubmit: $canSubmit, status: $status, count: $recordCount)';
}

/// Draft API Service - Syncs drafts with backend server
///
/// Architecture: Offline-first with background sync
/// - Local Hive storage is primary (fast, always available)
/// - Backend sync happens in background (cross-device support)
/// - Conflict resolution: Last-write-wins based on savedAt timestamp
///
/// Backend Endpoints:
/// - GET    /api/sales/daily-sales/draft?shop_id=xxx&record_date=YYYY-MM-DD - Load draft
/// - POST   /api/sales/daily-sales/draft - Save/update draft
/// - DELETE /api/sales/daily-sales/draft?shop_id=xxx&record_date=YYYY-MM-DD - Delete draft
/// - GET    /api/sales/daily-sales/drafts - List all user drafts
/// - POST   /api/sales/daily-sales/draft/submit - Submit draft for approval
/// - GET    /api/sales/daily-sales/exists?shop_id=xxx&record_date=YYYY-MM-DD - Check if record exists (SINGLE SOURCE OF TRUTH)
class DraftApiService {
  final DioApiService _apiService;

  DraftApiService(this._apiService);

  /// Save draft to backend
  /// Returns true if successful, false otherwise
  Future<bool> saveDraft(DailySalesDraft draft) async {
    try {
      final response = await _apiService.post(
        '/api/sales/daily-sales/draft',
        body: _draftToApiJson(draft),
      );

      if (response.success) {
        if (kDebugMode) {
          Logger.info('[DraftAPI] Draft synced to backend: ${draft.shopId}/${_formatDate(draft.recordDate)}');
        }
        return true;
      } else {
        if (kDebugMode) {
          Logger.warning('[DraftAPI] Sync failed: ${response.error}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftAPI] Save error: $e');
      }
      return false;
    }
  }

  /// Load draft from backend
  /// Returns null if no draft found or error
  Future<DailySalesDraft?> loadDraft(String shopId, DateTime recordDate) async {
    try {
      final dateStr = _formatDate(recordDate);
      final endpoint = '/api/sales/daily-sales/draft?shop_id=$shopId&record_date=$dateStr';

      final response = await _apiService.get<Map<String, dynamic>>(
        endpoint,
        fromJson: (json) => json as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        if (kDebugMode) {
          Logger.info('[DraftAPI] Draft loaded from backend: $shopId/$dateStr');
        }
        return _draftFromApiJson(response.data!, shopId, recordDate);
      } else {
        if (kDebugMode) {
          Logger.debug('[DraftAPI] No draft on backend: $shopId/$dateStr');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftAPI] Load error: $e');
      }
      return null;
    }
  }

  /// Delete draft from backend
  Future<bool> deleteDraft(String shopId, DateTime recordDate) async {
    try {
      final dateStr = _formatDate(recordDate);
      final endpoint = '/api/sales/daily-sales/draft?shop_id=$shopId&record_date=$dateStr';

      final response = await _apiService.delete(endpoint);

      if (response.success) {
        if (kDebugMode) {
          Logger.info('[DraftAPI] Draft deleted from backend: $shopId/$dateStr');
        }
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftAPI] Delete error: $e');
      }
      return false;
    }
  }

  /// Get all drafts for current user (for sync/recovery)
  Future<List<DailySalesDraft>> getAllDrafts() async {
    try {
      final response = await _apiService.get<List<dynamic>>(
        '/api/sales/daily-sales/drafts',
        fromJson: (json) => json as List<dynamic>,
      );

      if (response.success && response.data != null) {
        return response.data!
            .map((json) {
              final map = Map<String, dynamic>.from(json);
              final shopId = map['shop_id'] ?? '';
              // Use DateTimeHelper to properly parse UTC to local time
              final recordDate = map['record_date'] != null
                  ? DateTimeHelper.parseIsoToLocal(map['record_date']) ?? DateTime.now()
                  : DateTime.now();
              return _draftFromApiJson(map, shopId, recordDate);
            })
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftAPI] GetAll error: $e');
      }
      return [];
    }
  }

  /// Submit draft for approval (converts draft to actual record)
  Future<bool> submitDraft(String shopId, DateTime recordDate) async {
    try {
      final response = await _apiService.post(
        '/api/sales/daily-sales/draft/submit',
        body: {
          'shop_id': shopId,
          'record_date': _toRfc3339(recordDate),
        },
      );

      if (response.success) {
        if (kDebugMode) {
          Logger.info('[DraftAPI] Draft submitted for approval: $shopId/${_formatDate(recordDate)}');
        }
        return true;
      } else {
        if (kDebugMode) {
          Logger.warning('[DraftAPI] Submit failed: ${response.error}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.error('[DraftAPI] Submit error: $e');
      }
      return false;
    }
  }

  /// Check if a finalized record exists for shop+date on backend
  /// SINGLE SOURCE OF TRUTH - Backend is authoritative for record existence
  ///
  /// Returns a map with:
  /// - exists: true if record exists
  /// - can_submit: false if approved/pending record exists (blocks new submission)
  /// - status: "pending", "approved", "rejected" or empty
  /// - record_id: UUID of latest record if exists
  ///
  /// Best Practice: Call this BEFORE restoring drafts to prevent stale data
  Future<RecordExistsResponse> checkRecordExists(String shopId, DateTime recordDate) async {
    try {
      final dateStr = _formatDate(recordDate);
      final endpoint = '/api/sales/daily-sales/exists?shop_id=$shopId&record_date=$dateStr';

      if (kDebugMode) {
        Logger.debug('[DraftAPI] Checking record existence: $shopId/$dateStr');
      }

      final response = await _apiService.get<Map<String, dynamic>>(
        endpoint,
        fromJson: (json) => json as Map<String, dynamic>,
      );

      if (response.success && response.data != null) {
        final data = response.data!;
        final result = RecordExistsResponse(
          exists: data['exists'] ?? false,
          canSubmit: data['can_submit'] ?? true,
          status: data['status'] ?? '',
          recordId: data['record_id'],
          recordCount: data['record_count'] ?? 0,
        );

        if (kDebugMode) {
          Logger.info('[DraftAPI] Record check: exists=${result.exists}, canSubmit=${result.canSubmit}, status=${result.status}');
        }

        return result;
      }

      // API call succeeded but no data - assume no record exists
      return RecordExistsResponse(exists: false, canSubmit: true, status: '', recordCount: 0);
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('[DraftAPI] Record check error (assuming no record): $e');
      }
      // On error, assume no record exists (fail-safe for draft restoration)
      return RecordExistsResponse(exists: false, canSubmit: true, status: '', recordCount: 0);
    }
  }

  /// Sync local draft with backend (offline-first pattern)
  /// Returns the draft with the most content (CONTENT-AWARE conflict resolution)
  ///
  /// CRITICAL: We prefer drafts with MORE data over empty drafts, regardless of timestamp.
  /// This prevents data loss when app restarts with empty local storage.
  Future<DailySalesDraft?> syncDraft(
    String shopId,
    DateTime recordDate,
    DailySalesDraft? localDraft,
  ) async {
    try {
      // Get remote draft
      final remoteDraft = await loadDraft(shopId, recordDate);

      if (kDebugMode) {
        Logger.debug('[DraftAPI] Sync: local=${localDraft?.productCount ?? 0} items, remote=${remoteDraft?.productCount ?? 0} items');
      }

      // No local draft - use remote
      if (localDraft == null || localDraft.isEmpty) {
        if (remoteDraft != null && remoteDraft.isNotEmpty) {
          if (kDebugMode) {
            Logger.debug('[DraftAPI] Using remote (local empty/null): ${remoteDraft.productCount} items');
          }
        }
        return remoteDraft;
      }

      // No remote draft - push local to backend (only if local has content)
      if (remoteDraft == null || remoteDraft.isEmpty) {
        if (localDraft.isNotEmpty) {
          await saveDraft(localDraft);
          if (kDebugMode) {
            Logger.debug('[DraftAPI] Pushed local to backend (remote empty/null): ${localDraft.productCount} items');
          }
        }
        return localDraft;
      }

      // Both exist with content - use CONTENT-AWARE conflict resolution
      // Prefer the draft with MORE product items (data loss prevention)
      final localItems = localDraft.productCount;
      final remoteItems = remoteDraft.productCount;

      // CRITICAL: Check for rich data (productItems with actual product info)
      // Remote from backend will have parsed productItems, local may only have legacy
      final localHasRichData = localDraft.productItems.isNotEmpty;
      final remoteHasRichData = remoteDraft.productItems.isNotEmpty;

      if (kDebugMode) {
        Logger.debug('[DraftAPI] Local: $localItems items, richData=$localHasRichData');
        Logger.debug('[DraftAPI] Remote: $remoteItems items, richData=$remoteHasRichData');
      }

      if (localItems > remoteItems) {
        // Local has more content - push to backend
        await saveDraft(localDraft);
        if (kDebugMode) {
          Logger.debug('[DraftAPI] Local wins (more items: $localItems vs $remoteItems) - pushed to backend');
        }
        return localDraft;
      } else if (remoteItems > localItems) {
        // Remote has more content - use it (DON'T overwrite with less data)
        if (kDebugMode) {
          Logger.debug('[DraftAPI] Remote wins (more items: $remoteItems vs $localItems) - using backend version');
        }
        return remoteDraft;
      } else {
        // Same item count - prefer RICH data (productItems with full details)
        // This handles the case where local only has legacy productQuantities
        // but remote has full productItems with name, brand, etc.
        if (remoteHasRichData && !localHasRichData) {
          if (kDebugMode) {
            Logger.debug('[DraftAPI] Remote wins (has rich productItems data) - using backend version');
          }
          return remoteDraft;
        } else if (localHasRichData && !remoteHasRichData) {
          await saveDraft(localDraft);
          if (kDebugMode) {
            Logger.debug('[DraftAPI] Local wins (has rich productItems data) - pushed to backend');
          }
          return localDraft;
        } else {
          // Both have same richness - fall back to timestamp (last-write-wins)
          if (localDraft.savedAt.isAfter(remoteDraft.savedAt)) {
            await saveDraft(localDraft);
            if (kDebugMode) {
              Logger.debug('[DraftAPI] Local wins (same items, newer timestamp) - pushed to backend');
            }
            return localDraft;
          } else {
            if (kDebugMode) {
              Logger.debug('[DraftAPI] Remote wins (same items, newer timestamp) - using backend version');
            }
            return remoteDraft;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        Logger.warning('[DraftAPI] Sync error (using local): $e');
      }
      // On error, prefer local (offline-first)
      return localDraft;
    }
  }

  // ==================== Helper Methods ====================

  /// Format date for API endpoint (YYYY-MM-DD) - uses LOCAL date for business day
  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// Format DateTime to RFC3339 format (Go backend expects this)
  String _toRfc3339(DateTime date) {
    return '${date.toUtc().toIso8601String().split('.')[0]}Z';
  }

  /// Convert draft to API JSON format (matches backend schema)
  Map<String, dynamic> _draftToApiJson(DailySalesDraft draft) {
    // CRITICAL: Build items list from productItems (new format) OR productQuantities (legacy)
    // This ensures we always send actual data to backend, not empty arrays
    List<Map<String, dynamic>> itemsList = [];

    if (draft.productItems.isNotEmpty) {
      // New format: use productItems directly
      itemsList = draft.productItems.map((item) => <String, dynamic>{
        'product_id': item.productId,
        'product_name': item.productName,
        'brand_name': item.brandName,
        'category_name': item.categoryName,
        'subcategory_name': item.subcategoryName,
        'size': item.size,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'mrp': item.mrp,
        'total_amount': item.totalAmount,
        // Payment distribution (proportional)
        'cash_amount': _calculateProportionalAmount(item.totalAmount, draft.totalProductsAmount, draft.cashAmount),
        'card_amount': _calculateProportionalAmount(item.totalAmount, draft.totalProductsAmount, draft.cardAmount),
        'upi_amount': _calculateProportionalAmount(item.totalAmount, draft.totalProductsAmount, draft.upiAmount),
        'credit_amount': _calculateProportionalAmount(item.totalAmount, draft.totalProductsAmount, draft.creditAmount),
      }).toList();
    } else if (draft.productQuantities.isNotEmpty) {
      // Legacy format: convert productQuantities to items
      // This ensures we don't lose data when syncing older drafts
      itemsList = draft.productQuantities.entries.map((entry) => <String, dynamic>{
        'product_id': entry.key,
        'product_name': '', // Not available in legacy format
        'brand_name': '',
        'category_name': '',
        'subcategory_name': '',
        'size': '',
        'quantity': entry.value,
        'unit_price': 0.0,
        'mrp': 0.0,
        'total_amount': 0.0,
        'cash_amount': 0.0,
        'card_amount': 0.0,
        'upi_amount': 0.0,
        'credit_amount': 0.0,
      }).toList();

      if (kDebugMode) {
        Logger.warning('[DraftAPI] Converting ${draft.productQuantities.length} legacy items to new format');
      }
    }

    if (kDebugMode) {
      Logger.debug('[DraftAPI] Sending ${itemsList.length} items to backend');
    }

    // CRITICAL: Create UTC midnight from LOCAL date components
    // This ensures if user is on Jan 3 local time, backend stores Jan 3 (not Jan 2)
    // Same pattern as DailySalesRecordRequest in daily_sales_models.dart
    final utcDateOnly = DateTime.utc(
      draft.recordDate.year,
      draft.recordDate.month,
      draft.recordDate.day,
    );

    return {
      'shop_id': draft.shopId,
      'record_date': utcDateOnly.toIso8601String(),
      'draft_data': {
        'total_sales_amount': draft.totalProductsAmount,
        'total_cash_amount': draft.cashAmount,
        'total_card_amount': draft.cardAmount,
        'total_upi_amount': draft.upiAmount,
        'total_credit_amount': draft.creditAmount,
        'total_expense_amount': draft.expenseAmount,
        'notes': draft.notes,
        'items': itemsList,
        'expenses': draft.expenses.entries.map((e) => <String, dynamic>{
          'header_id': e.key,
          'amount': e.value,
        }).toList(),
        // UI state for restoration
        'current_step': draft.currentStep,
        'search_query': draft.searchQuery,
        'selected_category_name': draft.selectedCategoryName,
        'selected_subcategory_name': draft.selectedSubcategoryName,
        'last_saved_at': _toRfc3339(draft.savedAt),
        'version': draft.version,
      },
    };
  }

  /// Calculate proportional payment amount for item
  double _calculateProportionalAmount(double itemTotal, double grandTotal, double paymentAmount) {
    if (grandTotal == 0) return 0;
    return (itemTotal / grandTotal) * paymentAmount;
  }

  /// Convert API JSON to draft
  DailySalesDraft _draftFromApiJson(Map<String, dynamic> json, String shopId, DateTime recordDate) {
    if (kDebugMode) {
      Logger.debug('[DraftAPI] Raw API response keys: ${json.keys.toList()}');
    }

    // Backend returns multiple formats - handle them all:
    // Format 1: { "draft": { "draft_data": {...} }, "success": true }
    // Format 2: { "draft": { "items": [...], ... }, "success": true } (draft_data unpacked)
    // Format 3: { "draft_data": {...} }
    // Format 4: { "items": [...], ... } (direct draft content)
    Map<String, dynamic> draftData;

    if (json['draft'] != null && json['draft'] is Map) {
      final draftWrapper = json['draft'] as Map<String, dynamic>;
      if (kDebugMode) {
        Logger.debug('[DraftAPI] draft wrapper keys: ${draftWrapper.keys.toList()}');
      }

      // Check if draft_data exists inside draft wrapper
      if (draftWrapper['draft_data'] != null && draftWrapper['draft_data'] is Map) {
        draftData = draftWrapper['draft_data'] as Map<String, dynamic>;
        if (kDebugMode) {
          Logger.debug('[DraftAPI] Found draft_data inside draft wrapper');
        }
      }
      // Check if items exists directly in draft wrapper (backend unpacked draft_data)
      else if (draftWrapper['items'] != null || draftWrapper['total_sales_amount'] != null) {
        draftData = draftWrapper;
        if (kDebugMode) {
          Logger.debug('[DraftAPI] Using draft wrapper directly (has items/sales data)');
        }
      }
      // Fallback: use draft wrapper as-is
      else {
        draftData = draftWrapper;
        if (kDebugMode) {
          Logger.debug('[DraftAPI] Using draft wrapper as fallback');
        }
      }
    } else if (json['draft_data'] != null && json['draft_data'] is Map) {
      // Old format: { "draft_data": {...} }
      draftData = json['draft_data'] as Map<String, dynamic>;
      if (kDebugMode) {
        Logger.debug('[DraftAPI] Using draft_data directly from response');
      }
    } else if (json['items'] != null || json['total_sales_amount'] != null) {
      // Direct format: response is the draft content itself
      draftData = json;
      if (kDebugMode) {
        Logger.debug('[DraftAPI] Using response as draft data directly');
      }
    } else {
      // Last resort: treat entire json as draft data
      draftData = json;
      if (kDebugMode) {
        Logger.debug('[DraftAPI] Using entire response as fallback');
      }
    }

    if (kDebugMode) {
      Logger.debug('[DraftAPI] Final draftData keys: ${draftData.keys.toList()}');
      if (draftData['items'] != null) {
        Logger.debug('[DraftAPI] items count: ${(draftData['items'] as List?)?.length ?? 0}');
      } else {
        Logger.debug('[DraftAPI] NO items key found in draftData');
      }
    }

    // Parse expenses
    Map<String, double> expenses = {};
    if (draftData['expenses'] != null) {
      final rawExpenses = draftData['expenses'] as List<dynamic>;
      for (var expense in rawExpenses) {
        final map = Map<String, dynamic>.from(expense);
        final headerId = map['header_id'] ?? '';
        final amount = (map['amount'] ?? 0).toDouble();
        if (headerId.isNotEmpty && amount > 0) {
          expenses[headerId] = amount;
        }
      }
    }

    // Parse product items
    List<DraftProductItem> productItems = [];
    if (draftData['items'] != null) {
      final rawItems = draftData['items'] as List<dynamic>;
      productItems = rawItems.map((item) {
        final map = Map<String, dynamic>.from(item);
        return DraftProductItem(
          productId: map['product_id'] ?? '',
          productName: map['product_name'] ?? '',
          brandName: map['brand_name'] ?? '',
          categoryName: map['category_name'] ?? '',
          subcategoryName: map['subcategory_name'] ?? '',
          size: map['size'] ?? '',
          quantity: map['quantity'] ?? 0,
          unitPrice: (map['unit_price'] ?? 0).toDouble(),
          mrp: (map['mrp'] ?? map['unit_price'] ?? 0).toDouble(),
          totalAmount: (map['total_amount'] ?? 0).toDouble(),
        );
      }).toList();
    }

    // Build legacy product quantities map for backward compatibility
    Map<String, int> productQuantities = {};
    for (var item in productItems) {
      productQuantities[item.productId] = item.quantity;
    }

    return DailySalesDraft(
      productQuantities: productQuantities,
      productItems: productItems,
      cashAmount: (draftData['total_cash_amount'] ?? 0).toDouble(),
      cardAmount: (draftData['total_card_amount'] ?? 0).toDouble(),
      upiAmount: (draftData['total_upi_amount'] ?? 0).toDouble(),
      creditAmount: (draftData['total_credit_amount'] ?? 0).toDouble(),
      expenseAmount: (draftData['total_expense_amount'] ?? 0).toDouble(),
      expenses: expenses,
      notes: draftData['notes'] ?? '',
      recordDate: recordDate,
      shopId: shopId,
      currentStep: draftData['current_step'] ?? 0,
      searchQuery: draftData['search_query'] ?? '',
      selectedCategoryName: draftData['selected_category_name'],
      selectedSubcategoryName: draftData['selected_subcategory_name'],
      // Use DateTimeHelper to properly parse UTC timestamp to local time
      savedAt: draftData['last_saved_at'] != null
          ? DateTimeHelper.parseIsoToLocal(draftData['last_saved_at']) ?? DateTime.now()
          : DateTime.now(),
      version: draftData['version'] ?? 2,
    );
  }
}

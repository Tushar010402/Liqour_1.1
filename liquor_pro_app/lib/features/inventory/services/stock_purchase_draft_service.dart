import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/dio_api_service.dart';

/// Model for a stock purchase draft item
class StockPurchaseDraftItem {
  final String productId;
  final String productName;
  final String? brandName;
  final String size;
  final int quantity;
  final double costPrice;

  StockPurchaseDraftItem({
    required this.productId,
    required this.productName,
    this.brandName,
    required this.size,
    required this.quantity,
    required this.costPrice,
  });

  double get total => costPrice * quantity;

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'product_name': productName,
    'brand_name': brandName,
    'size': size,
    'quantity': quantity,
    'cost_price': costPrice,
  };

  factory StockPurchaseDraftItem.fromJson(Map<String, dynamic> json) {
    return StockPurchaseDraftItem(
      productId: json['product_id'] ?? '',
      productName: json['product_name'] ?? '',
      brandName: json['brand_name'],
      size: json['size'] ?? '',
      quantity: json['quantity'] ?? 1,
      costPrice: (json['cost_price'] ?? 0).toDouble(),
    );
  }

  StockPurchaseDraftItem copyWith({int? quantity}) {
    return StockPurchaseDraftItem(
      productId: productId,
      productName: productName,
      brandName: brandName,
      size: size,
      quantity: quantity ?? this.quantity,
      costPrice: costPrice,
    );
  }
}

/// Model for a complete stock purchase draft
class StockPurchaseDraft {
  final String id;
  final String shopId;
  final String userId;
  final String shopName;
  final List<StockPurchaseDraftItem> items;
  final String? vendorId;
  final String? receiptUrl;
  final String? receiptNumber;
  final DateTime? receiptDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? deviceId;
  final int version;
  final bool isSynced;

  StockPurchaseDraft({
    required this.id,
    required this.shopId,
    required this.userId,
    required this.shopName,
    required this.items,
    this.vendorId,
    this.receiptUrl,
    this.receiptNumber,
    this.receiptDate,
    required this.createdAt,
    required this.updatedAt,
    this.deviceId,
    this.version = 1,
    this.isSynced = false,
  });

  double get totalAmount => items.fold(0, (sum, item) => sum + item.total);
  int get itemCount => items.length;
  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);

  /// Unique key for local storage (shop + user combination)
  String get storageKey => 'stock_draft_${shopId}_$userId';

  Map<String, dynamic> toJson() => {
    'id': id,
    'shop_id': shopId,
    'user_id': userId,
    'shop_name': shopName,
    'items': items.map((i) => i.toJson()).toList(),
    'vendor_id': vendorId,
    'receipt_url': receiptUrl,
    'receipt_number': receiptNumber,
    'receipt_date': receiptDate?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'device_id': deviceId,
    'version': version,
    'is_synced': isSynced,
  };

  factory StockPurchaseDraft.fromJson(Map<String, dynamic> json) {
    return StockPurchaseDraft(
      id: json['id'] ?? '',
      shopId: json['shop_id'] ?? '',
      userId: json['user_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      items: (json['items'] as List?)
          ?.map((i) => StockPurchaseDraftItem.fromJson(i))
          .toList() ?? [],
      vendorId: json['vendor_id'],
      receiptUrl: json['receipt_url'],
      receiptNumber: json['receipt_number'],
      receiptDate: json['receipt_date'] != null
          ? DateTime.tryParse(json['receipt_date'])
          : null,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      deviceId: json['device_id'],
      version: json['version'] ?? 1,
      isSynced: json['is_synced'] ?? false,
    );
  }

  StockPurchaseDraft copyWith({
    List<StockPurchaseDraftItem>? items,
    String? vendorId,
    String? receiptUrl,
    String? receiptNumber,
    DateTime? receiptDate,
    DateTime? updatedAt,
    int? version,
    bool? isSynced,
  }) {
    return StockPurchaseDraft(
      id: id,
      shopId: shopId,
      userId: userId,
      shopName: shopName,
      items: items ?? this.items,
      vendorId: vendorId ?? this.vendorId,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      receiptDate: receiptDate ?? this.receiptDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId,
      version: version ?? this.version,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

/// Service for managing stock purchase drafts with local storage and server sync
class StockPurchaseDraftService {
  final DioApiService _apiService;
  static const String _allDraftsKey = 'all_stock_drafts_keys';
  static const String _deviceIdKey = 'device_unique_id';

  StockPurchaseDraftService(this._apiService);

  /// Get or create device ID for conflict resolution
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = DateTime.now().millisecondsSinceEpoch.toString();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }

  /// Save draft to local storage (auto-save)
  Future<void> saveDraftLocally(StockPurchaseDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save draft data
      final draftJson = jsonEncode(draft.toJson());
      await prefs.setString(draft.storageKey, draftJson);

      // Track all draft keys
      final allKeys = prefs.getStringList(_allDraftsKey) ?? [];
      if (!allKeys.contains(draft.storageKey)) {
        allKeys.add(draft.storageKey);
        await prefs.setStringList(_allDraftsKey, allKeys);
      }

      debugPrint('📦 Draft saved locally: ${draft.storageKey} (${draft.itemCount} items, ₹${draft.totalAmount.toStringAsFixed(0)})');
    } catch (e) {
      debugPrint('❌ Error saving draft locally: $e');
    }
  }

  /// Load draft from local storage
  Future<StockPurchaseDraft?> loadDraftLocally({
    required String shopId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'stock_draft_${shopId}_$userId';
      final draftJson = prefs.getString(key);

      if (draftJson != null) {
        final draft = StockPurchaseDraft.fromJson(jsonDecode(draftJson));
        debugPrint('📦 Draft loaded locally: $key (${draft.itemCount} items)');
        return draft;
      }
    } catch (e) {
      debugPrint('❌ Error loading draft locally: $e');
    }
    return null;
  }

  /// Delete draft from local storage
  Future<void> deleteDraftLocally({
    required String shopId,
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'stock_draft_${shopId}_$userId';

      await prefs.remove(key);

      // Remove from tracked keys
      final allKeys = prefs.getStringList(_allDraftsKey) ?? [];
      allKeys.remove(key);
      await prefs.setStringList(_allDraftsKey, allKeys);

      debugPrint('🗑️ Draft deleted locally: $key');
    } catch (e) {
      debugPrint('❌ Error deleting draft locally: $e');
    }
  }

  /// Get all locally saved drafts
  Future<List<StockPurchaseDraft>> getAllLocalDrafts() async {
    final drafts = <StockPurchaseDraft>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getStringList(_allDraftsKey) ?? [];

      for (final key in allKeys) {
        final draftJson = prefs.getString(key);
        if (draftJson != null) {
          drafts.add(StockPurchaseDraft.fromJson(jsonDecode(draftJson)));
        }
      }
    } catch (e) {
      debugPrint('❌ Error getting all local drafts: $e');
    }
    return drafts;
  }

  /// Get drafts for a specific shop
  Future<List<StockPurchaseDraft>> getDraftsForShop(String shopId) async {
    final allDrafts = await getAllLocalDrafts();
    return allDrafts.where((d) => d.shopId == shopId).toList();
  }

  /// Sync draft to server
  Future<bool> syncDraftToServer(StockPurchaseDraft draft) async {
    try {
      final deviceId = await _getDeviceId();
      final response = await _apiService.post(
        '/api/inventory/drafts/stock-purchase',
        body: {
          ...draft.toJson(),
          'device_id': deviceId,
        },
      );

      if (response.success) {
        // Update local draft as synced
        final syncedDraft = draft.copyWith(
          isSynced: true,
          updatedAt: DateTime.now(),
        );
        await saveDraftLocally(syncedDraft);
        debugPrint('✅ Draft synced to server: ${draft.storageKey}');
        return true;
      }
    } catch (e) {
      debugPrint('❌ Error syncing draft to server: $e');
    }
    return false;
  }

  /// Load draft from server (for sync on app start)
  Future<StockPurchaseDraft?> loadDraftFromServer({
    required String shopId,
    required String userId,
  }) async {
    try {
      final response = await _apiService.get(
        '/api/inventory/drafts/stock-purchase',
        queryParams: {
          'shop_id': shopId,
          'user_id': userId,
        },
      );

      if (response.success && response.data != null) {
        final data = response.data is Map ? response.data['data'] ?? response.data : response.data;
        if (data != null && data is Map<String, dynamic>) {
          return StockPurchaseDraft.fromJson(data);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading draft from server: $e');
    }
    return null;
  }

  /// Sync all unsynced drafts to server
  Future<int> syncAllDraftsToServer() async {
    int syncedCount = 0;
    try {
      final allDrafts = await getAllLocalDrafts();
      final unsyncedDrafts = allDrafts.where((d) => !d.isSynced).toList();

      for (final draft in unsyncedDrafts) {
        if (await syncDraftToServer(draft)) {
          syncedCount++;
        }
      }

      debugPrint('✅ Synced $syncedCount/${unsyncedDrafts.length} drafts to server');
    } catch (e) {
      debugPrint('❌ Error syncing all drafts: $e');
    }
    return syncedCount;
  }

  /// Merge local and server drafts (conflict resolution)
  Future<StockPurchaseDraft?> mergeDrafts({
    required String shopId,
    required String userId,
  }) async {
    final localDraft = await loadDraftLocally(shopId: shopId, userId: userId);
    final serverDraft = await loadDraftFromServer(shopId: shopId, userId: userId);

    if (localDraft == null && serverDraft == null) {
      return null;
    }

    if (localDraft == null) {
      // Only server draft exists, save locally
      await saveDraftLocally(serverDraft!);
      return serverDraft;
    }

    if (serverDraft == null) {
      // Only local draft exists
      return localDraft;
    }

    // Both exist - use the one with latest update time
    // (More sophisticated conflict resolution can be added)
    if (serverDraft.updatedAt.isAfter(localDraft.updatedAt)) {
      await saveDraftLocally(serverDraft);
      return serverDraft;
    } else {
      // Local is newer, sync to server
      await syncDraftToServer(localDraft);
      return localDraft;
    }
  }

  /// Delete draft from server
  Future<bool> deleteDraftFromServer({
    required String shopId,
    required String userId,
  }) async {
    try {
      final response = await _apiService.delete(
        '/api/inventory/drafts/stock-purchase?shop_id=$shopId&user_id=$userId',
      );
      return response.success;
    } catch (e) {
      debugPrint('❌ Error deleting draft from server: $e');
    }
    return false;
  }

  /// Create a new draft from selected products
  Future<StockPurchaseDraft> createDraft({
    required String shopId,
    required String userId,
    required String shopName,
    required List<StockPurchaseDraftItem> items,
  }) async {
    final deviceId = await _getDeviceId();
    final now = DateTime.now();

    return StockPurchaseDraft(
      id: '${shopId}_${userId}_${now.millisecondsSinceEpoch}',
      shopId: shopId,
      userId: userId,
      shopName: shopName,
      items: items,
      createdAt: now,
      updatedAt: now,
      deviceId: deviceId,
      version: 1,
      isSynced: false,
    );
  }

  /// Update item quantity in draft
  StockPurchaseDraft updateItemQuantity(
    StockPurchaseDraft draft,
    String productId,
    int newQuantity,
  ) {
    final updatedItems = draft.items.map((item) {
      if (item.productId == productId) {
        return item.copyWith(quantity: newQuantity);
      }
      return item;
    }).toList();

    return draft.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
  }

  /// Add item to draft
  StockPurchaseDraft addItem(
    StockPurchaseDraft draft,
    StockPurchaseDraftItem item,
  ) {
    final updatedItems = [...draft.items, item];
    return draft.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
  }

  /// Remove item from draft
  StockPurchaseDraft removeItem(
    StockPurchaseDraft draft,
    String productId,
  ) {
    final updatedItems = draft.items.where((i) => i.productId != productId).toList();
    return draft.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now(),
      isSynced: false,
    );
  }
}

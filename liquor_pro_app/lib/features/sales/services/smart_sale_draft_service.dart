/// Smart Sale Draft Service
///
/// Industrial-grade auto-save and persistence service for Smart Sale.
/// Provides:
/// - User-specific, shop-wise draft storage
/// - Auto-save on navigation away
/// - Background-safe persistence (survives app close)
/// - TTL-based expiration (drafts expire after 24 hours)
/// - Efficient storage using Hive
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/smart_sale_models.dart';

/// Draft data model for persistence
class SmartSaleDraft {
  /// Unique key: user_id:shop_id:date
  final String key;

  /// User ID (tenant user)
  final String userId;

  /// Shop ID
  final String shopId;

  /// Shop name (for display)
  final String shopName;

  /// Sale date
  final DateTime saleDate;

  /// Category: 'beer' or 'non_beer'
  final String category;

  /// Selected size (for non-beer)
  final String? size;

  /// Cached result JSON (serialized SmartSaleResult)
  final Map<String, dynamic>? resultJson;

  /// Current step: 0=items, 1=payment, 2=review
  final int currentStep;

  /// Payment breakdown
  final double cashAmount;
  final double cardAmount;
  final double upiAmount;
  final double creditAmount;

  /// Edited quantities map: index -> quantity
  final Map<String, int> editedQuantities;

  /// Expenses list
  final List<Map<String, dynamic>> expenses;

  /// Notes
  final String notes;

  /// Created timestamp
  final DateTime createdAt;

  /// Last updated timestamp
  final DateTime updatedAt;

  /// Image paths (for reference, not actual images)
  final List<String> imagePaths;

  /// Processing status
  final String status; // 'draft', 'processing', 'ready', 'submitted'

  SmartSaleDraft({
    required this.key,
    required this.userId,
    required this.shopId,
    required this.shopName,
    required this.saleDate,
    required this.category,
    this.size,
    this.resultJson,
    this.currentStep = 0,
    this.cashAmount = 0,
    this.cardAmount = 0,
    this.upiAmount = 0,
    this.creditAmount = 0,
    this.editedQuantities = const {},
    this.expenses = const [],
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.imagePaths = const [],
    this.status = 'draft',
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// Create draft key from components
  static String createKey(String userId, String shopId, DateTime date) {
    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return '$userId:$shopId:$dateStr';
  }

  /// Parse SmartSaleResult from stored JSON
  SmartSaleResult? get cachedResult {
    if (resultJson == null) return null;
    try {
      return SmartSaleResult.fromJson(resultJson!);
    } catch (e) {
      debugPrint('⚠️ SmartSaleDraft: Failed to parse cached result: $e');
      return null;
    }
  }

  /// Convert editedQuantities from String keys to int keys
  Map<int, int> get editedQuantitiesAsIntKeys {
    return editedQuantities.map((k, v) => MapEntry(int.tryParse(k) ?? 0, v));
  }

  /// Check if draft is expired (older than 24 hours)
  bool get isExpired {
    final age = DateTime.now().difference(updatedAt);
    return age.inHours > 24;
  }

  /// Check if draft has meaningful data
  bool get hasData {
    return resultJson != null ||
           cashAmount > 0 ||
           cardAmount > 0 ||
           upiAmount > 0 ||
           creditAmount > 0 ||
           editedQuantities.isNotEmpty ||
           expenses.isNotEmpty ||
           notes.isNotEmpty;
  }

  /// Create a copy with updated fields
  SmartSaleDraft copyWith({
    String? key,
    String? userId,
    String? shopId,
    String? shopName,
    DateTime? saleDate,
    String? category,
    String? size,
    Map<String, dynamic>? resultJson,
    int? currentStep,
    double? cashAmount,
    double? cardAmount,
    double? upiAmount,
    double? creditAmount,
    Map<String, int>? editedQuantities,
    List<Map<String, dynamic>>? expenses,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? imagePaths,
    String? status,
  }) {
    return SmartSaleDraft(
      key: key ?? this.key,
      userId: userId ?? this.userId,
      shopId: shopId ?? this.shopId,
      shopName: shopName ?? this.shopName,
      saleDate: saleDate ?? this.saleDate,
      category: category ?? this.category,
      size: size ?? this.size,
      resultJson: resultJson ?? this.resultJson,
      currentStep: currentStep ?? this.currentStep,
      cashAmount: cashAmount ?? this.cashAmount,
      cardAmount: cardAmount ?? this.cardAmount,
      upiAmount: upiAmount ?? this.upiAmount,
      creditAmount: creditAmount ?? this.creditAmount,
      editedQuantities: editedQuantities ?? this.editedQuantities,
      expenses: expenses ?? this.expenses,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      imagePaths: imagePaths ?? this.imagePaths,
      status: status ?? this.status,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'user_id': userId,
      'shop_id': shopId,
      'shop_name': shopName,
      'sale_date': saleDate.toIso8601String(),
      'category': category,
      'size': size,
      'result_json': resultJson,
      'current_step': currentStep,
      'cash_amount': cashAmount,
      'card_amount': cardAmount,
      'upi_amount': upiAmount,
      'credit_amount': creditAmount,
      'edited_quantities': editedQuantities,
      'expenses': expenses,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'image_paths': imagePaths,
      'status': status,
    };
  }

  /// Create from JSON
  factory SmartSaleDraft.fromJson(Map<String, dynamic> json) {
    return SmartSaleDraft(
      key: json['key'] ?? '',
      userId: json['user_id'] ?? '',
      shopId: json['shop_id'] ?? '',
      shopName: json['shop_name'] ?? '',
      saleDate: DateTime.tryParse(json['sale_date'] ?? '') ?? DateTime.now(),
      category: json['category'] ?? 'non_beer',
      size: json['size'],
      resultJson: json['result_json'] as Map<String, dynamic>?,
      currentStep: json['current_step'] ?? 0,
      cashAmount: (json['cash_amount'] ?? 0).toDouble(),
      cardAmount: (json['card_amount'] ?? 0).toDouble(),
      upiAmount: (json['upi_amount'] ?? 0).toDouble(),
      creditAmount: (json['credit_amount'] ?? 0).toDouble(),
      editedQuantities: (json['edited_quantities'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v as int)) ?? {},
      expenses: (json['expenses'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList() ?? [],
      notes: json['notes'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? ''),
      imagePaths: (json['image_paths'] as List?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      status: json['status'] ?? 'draft',
    );
  }
}

/// Service for managing Smart Sale drafts
class SmartSaleDraftService {
  static const String _boxName = 'smart_sale_drafts';
  static SmartSaleDraftService? _instance;

  Box<String>? _box;
  bool _initialized = false;

  SmartSaleDraftService._();

  /// Get singleton instance
  static SmartSaleDraftService get instance {
    _instance ??= SmartSaleDraftService._();
    return _instance!;
  }

  /// Initialize the service (call once at app startup)
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Initialize Hive if not already done
      if (!Hive.isBoxOpen(_boxName)) {
        _box = await Hive.openBox<String>(_boxName);
      } else {
        _box = Hive.box<String>(_boxName);
      }
      _initialized = true;

      if (kDebugMode) {
        print('✅ SmartSaleDraftService: Initialized with ${_box?.length ?? 0} drafts');
      }

      // Clean up expired drafts on startup
      await _cleanupExpiredDrafts();
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Initialization failed: $e');
      rethrow;
    }
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Save a draft
  Future<void> saveDraft(SmartSaleDraft draft) async {
    await _ensureInitialized();

    try {
      final jsonStr = jsonEncode(draft.toJson());
      await _box?.put(draft.key, jsonStr);

      if (kDebugMode) {
        print('💾 SmartSaleDraftService: Saved draft ${draft.key}');
        print('   Shop: ${draft.shopName}');
        print('   Date: ${draft.saleDate.toIso8601String().split('T')[0]}');
        print('   Step: ${draft.currentStep}');
        print('   Has result: ${draft.resultJson != null}');
      }
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Failed to save draft: $e');
      rethrow;
    }
  }

  /// Get a specific draft by key
  Future<SmartSaleDraft?> getDraft(String key) async {
    await _ensureInitialized();

    try {
      final jsonStr = _box?.get(key);
      if (jsonStr == null) return null;

      final draft = SmartSaleDraft.fromJson(jsonDecode(jsonStr));

      // Check if expired
      if (draft.isExpired) {
        await deleteDraft(key);
        return null;
      }

      if (kDebugMode) {
        print('📂 SmartSaleDraftService: Retrieved draft $key');
      }

      return draft;
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Failed to get draft: $e');
      return null;
    }
  }

  /// Get draft by components
  Future<SmartSaleDraft?> getDraftForShopAndDate(
    String userId,
    String shopId,
    DateTime date,
  ) async {
    final key = SmartSaleDraft.createKey(userId, shopId, date);
    return getDraft(key);
  }

  /// Get all drafts for a user
  Future<List<SmartSaleDraft>> getDraftsForUser(String userId) async {
    await _ensureInitialized();

    final drafts = <SmartSaleDraft>[];

    try {
      for (final key in _box?.keys ?? []) {
        if (key.toString().startsWith('$userId:')) {
          final jsonStr = _box?.get(key);
          if (jsonStr != null) {
            final draft = SmartSaleDraft.fromJson(jsonDecode(jsonStr));
            if (!draft.isExpired && draft.hasData) {
              drafts.add(draft);
            }
          }
        }
      }

      // Sort by updatedAt descending (most recent first)
      drafts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (kDebugMode) {
        print('📂 SmartSaleDraftService: Found ${drafts.length} drafts for user $userId');
      }

      return drafts;
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Failed to get user drafts: $e');
      return [];
    }
  }

  /// Get all drafts for a specific shop
  Future<List<SmartSaleDraft>> getDraftsForShop(String userId, String shopId) async {
    await _ensureInitialized();

    final drafts = <SmartSaleDraft>[];
    final keyPrefix = '$userId:$shopId:';

    try {
      for (final key in _box?.keys ?? []) {
        if (key.toString().startsWith(keyPrefix)) {
          final jsonStr = _box?.get(key);
          if (jsonStr != null) {
            final draft = SmartSaleDraft.fromJson(jsonDecode(jsonStr));
            if (!draft.isExpired && draft.hasData) {
              drafts.add(draft);
            }
          }
        }
      }

      // Sort by saleDate descending
      drafts.sort((a, b) => b.saleDate.compareTo(a.saleDate));

      if (kDebugMode) {
        print('📂 SmartSaleDraftService: Found ${drafts.length} drafts for shop $shopId');
      }

      return drafts;
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Failed to get shop drafts: $e');
      return [];
    }
  }

  /// Delete a specific draft
  Future<void> deleteDraft(String key) async {
    await _ensureInitialized();

    try {
      await _box?.delete(key);

      if (kDebugMode) {
        print('🗑️ SmartSaleDraftService: Deleted draft $key');
      }
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Failed to delete draft: $e');
    }
  }

  /// Delete all drafts for a user
  Future<void> deleteAllDraftsForUser(String userId) async {
    await _ensureInitialized();

    try {
      final keysToDelete = <dynamic>[];

      for (final key in _box?.keys ?? []) {
        if (key.toString().startsWith('$userId:')) {
          keysToDelete.add(key);
        }
      }

      for (final key in keysToDelete) {
        await _box?.delete(key);
      }

      if (kDebugMode) {
        print('🗑️ SmartSaleDraftService: Deleted ${keysToDelete.length} drafts for user $userId');
      }
    } catch (e) {
      debugPrint('❌ SmartSaleDraftService: Failed to delete user drafts: $e');
    }
  }

  /// Clean up expired drafts
  Future<void> _cleanupExpiredDrafts() async {
    try {
      final keysToDelete = <dynamic>[];

      for (final key in _box?.keys ?? []) {
        final jsonStr = _box?.get(key);
        if (jsonStr != null) {
          final draft = SmartSaleDraft.fromJson(jsonDecode(jsonStr));
          if (draft.isExpired) {
            keysToDelete.add(key);
          }
        }
      }

      for (final key in keysToDelete) {
        await _box?.delete(key);
      }

      if (keysToDelete.isNotEmpty && kDebugMode) {
        print('🧹 SmartSaleDraftService: Cleaned up ${keysToDelete.length} expired drafts');
      }
    } catch (e) {
      debugPrint('⚠️ SmartSaleDraftService: Failed to cleanup expired drafts: $e');
    }
  }

  /// Check if a draft exists for the given parameters
  Future<bool> hasDraft(String userId, String shopId, DateTime date) async {
    final draft = await getDraftForShopAndDate(userId, shopId, date);
    return draft != null && draft.hasData;
  }

  /// Get draft count for user
  Future<int> getDraftCount(String userId) async {
    final drafts = await getDraftsForUser(userId);
    return drafts.length;
  }
}

/// Extension for easy draft creation from screen state
extension SmartSaleDraftExtension on SmartSaleDraft {
  /// Create a draft from current screen state
  static SmartSaleDraft fromScreenState({
    required String userId,
    required String shopId,
    required String shopName,
    required DateTime saleDate,
    required String category,
    String? size,
    SmartSaleResult? result,
    int currentStep = 0,
    double cashAmount = 0,
    double cardAmount = 0,
    double upiAmount = 0,
    double creditAmount = 0,
    Map<int, int>? editedQuantities,
    List<Map<String, dynamic>>? expenses,
    String notes = '',
    List<String>? imagePaths,
  }) {
    final key = SmartSaleDraft.createKey(userId, shopId, saleDate);

    // Convert int keys to string keys for JSON serialization
    final editedQtyMap = editedQuantities?.map(
      (k, v) => MapEntry(k.toString(), v),
    ) ?? {};

    return SmartSaleDraft(
      key: key,
      userId: userId,
      shopId: shopId,
      shopName: shopName,
      saleDate: saleDate,
      category: category,
      size: size,
      resultJson: result != null ? _resultToJson(result) : null,
      currentStep: currentStep,
      cashAmount: cashAmount,
      cardAmount: cardAmount,
      upiAmount: upiAmount,
      creditAmount: creditAmount,
      editedQuantities: editedQtyMap,
      expenses: expenses ?? [],
      notes: notes,
      imagePaths: imagePaths ?? [],
      status: result != null ? 'ready' : 'draft',
    );
  }

  /// Convert SmartSaleResult to JSON for storage
  static Map<String, dynamic> _resultToJson(SmartSaleResult result) {
    return {
      'status': result.status,
      'message': result.message,
      'extracted_items': result.extractedItems.map((item) => {
        'product_id': item.productId,
        'brand_name': item.brandName,
        'size': item.size,
        'category': item.category,
        'quantity': item.quantity,
        'rate': item.rate,
        'amount': item.amount,
        'is_valid': item.isValid,
        'validation_status': item.validationStatus,
        'available_stock': item.availableStock,
        'opening_stock': item.openingStock,
        'receipt': item.receipt,
        'total_stock': item.totalStock,
        'closing_stock': item.closingStock,
        'db_stock': item.dbStock,
        'expected_amount': item.expectedAmount,
        'inventory_rate': item.inventoryRate,
        'confidence': item.confidence,
        'warnings': item.warnings,
        'errors': item.errors,
        'serial_number': item.serialNumber,
      }).toList(),
      'total_amount': result.totalAmount,
      'sale_record_id': result.saleRecordId,
      'validation': result.validation != null ? {
        'shop_name_match': result.validation!.shopNameMatch,
        'date_match': result.validation!.dateMatch,
        'size_match': result.validation!.sizeMatch,
        'is_valid': result.validation!.isValid,
        'total_items': result.validation!.totalItems,
        'valid_items': result.validation!.validItems,
        'stock_discrepancies': result.validation!.stockDiscrepancies,
        'amount_mismatches': result.validation!.amountMismatches,
        'stock_issues': result.validation!.stockIssues,
        'rate_mismatches': result.validation!.rateMismatches,
        'not_found_items': result.validation!.notFoundItems,
        'warnings': result.validation!.warnings,
        'messages': result.validation!.messages,
      } : null,
      'processing_details': result.processingDetails != null ? {
        'ocr_time_ms': result.processingDetails!.ocrTimeMs,
        'validation_time_ms': result.processingDetails!.validationTimeMs,
        'creation_time_ms': result.processingDetails!.creationTimeMs,
        'total_time_ms': result.processingDetails!.totalTimeMs,
        'avg_confidence': result.processingDetails!.avgConfidence,
        'ai_model': result.processingDetails!.aiModel,
        'images_processed': result.processingDetails!.imagesProcessed,
      } : null,
      'error_details': result.errorDetails,
      'image_urls': result.imageUrls,
      'detected_shop_name': result.detectedShopName,
      'detected_size': result.detectedSize,
      'detected_size_ml': result.detectedSizeML,
    };
  }
}

import '../constants/api_endpoints.dart';
import '../models/api_response.dart';
import 'api_service.dart';

class StockIntegrationService {
  final ApiService _apiService;

  StockIntegrationService(this._apiService);

  // Initialize stock for newly added brands
  Future<ApiResponse<void>> initializeStockForBrands({
    required String tenantId,
    required List<String> brandIds,
    required List<String> variantIds,
    int defaultStockLevel = 0,
  }) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.initializeTenantStock,
        data: {
          'tenant_id': tenantId,
          'brand_ids': brandIds,
          'variant_ids': variantIds,
          'default_stock_level': defaultStockLevel,
          'action': 'initialize_from_saas',
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Failed to initialize stock');
    } catch (e) {
      return ApiResponse<void>.error('Failed to initialize stock: $e');
    }
  }

  // Get stock status for tenant brands
  Future<ApiResponse<Map<String, dynamic>>> getTenantStockStatus(String tenantId) async {
    try {
      final response = await _apiService.get(
        ApiEndpoints.tenantStockStatus(tenantId),
      );

      if (response.success && response.data != null) {
        return ApiResponse<Map<String, dynamic>>.success(response.data);
      }

      return ApiResponse<Map<String, dynamic>>.error(
        response.message ?? 'Failed to get stock status',
      );
    } catch (e) {
      return ApiResponse<Map<String, dynamic>>.error('Failed to get stock status: $e');
    }
  }

  // Bulk update stock levels for multiple products
  Future<ApiResponse<void>> bulkUpdateStock({
    required String tenantId,
    required Map<String, int> variantStockLevels,
    String? notes,
  }) async {
    try {
      final response = await _apiService.put(
        ApiEndpoints.bulkUpdateTenantStock(tenantId),
        data: {
          'stock_updates': variantStockLevels.entries.map((entry) => {
            'variant_id': entry.key,
            'stock_level': entry.value,
          }).toList(),
          'notes': notes,
          'updated_by': 'saas_admin',
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Failed to update stock');
    } catch (e) {
      return ApiResponse<void>.error('Failed to update stock: $e');
    }
  }

  // Get suggested stock levels based on package type and business size
  Map<String, int> getSuggestedStockLevels({
    required String packageType,
    required List<String> variantIds,
    String businessSize = 'medium',
  }) {
    final suggestions = <String, int>{};

    // Base stock levels by package type
    int baseStock;
    switch (packageType) {
      case 'starter':
        baseStock = businessSize == 'small' ? 5 : 10;
        break;
      case 'premium':
        baseStock = businessSize == 'small' ? 8 : businessSize == 'medium' ? 15 : 25;
        break;
      case 'full':
        baseStock = businessSize == 'small' ? 12 : businessSize == 'medium' ? 20 : 35;
        break;
      default:
        baseStock = 10;
    }

    // Apply base stock to all variants
    for (final variantId in variantIds) {
      suggestions[variantId] = baseStock;
    }

    return suggestions;
  }

  // Generate stock optimization recommendations
  Future<ApiResponse<List<StockRecommendation>>> getStockRecommendations({
    required String tenantId,
    int lookbackDays = 30,
  }) async {
    try {
      final response = await _apiService.get(
        '${ApiEndpoints.tenantStockRecommendations(tenantId)}?lookback_days=$lookbackDays',
      );

      if (response.success && response.data != null) {
        final List<dynamic> recommendationsJson = response.data['recommendations'] ?? [];
        final recommendations = recommendationsJson
            .map((json) => StockRecommendation.fromJson(json))
            .toList();
        return ApiResponse<List<StockRecommendation>>.success(recommendations);
      }

      return ApiResponse<List<StockRecommendation>>.error(
        response.message ?? 'Failed to get recommendations',
      );
    } catch (e) {
      return ApiResponse<List<StockRecommendation>>.error('Failed to get recommendations: $e');
    }
  }

  // Notify inventory service about brand assignment completion
  Future<ApiResponse<void>> notifyBrandAssignmentComplete({
    required String tenantId,
    required List<String> brandIds,
    required List<String> variantIds,
    required String assignmentType, // 'package' or 'custom'
  }) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.notifyInventoryBrandAssignment,
        data: {
          'tenant_id': tenantId,
          'brand_ids': brandIds,
          'variant_ids': variantIds,
          'assignment_type': assignmentType,
          'timestamp': DateTime.now().toIso8601String(),
          'source': 'saas_marketplace',
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(
        response.message ?? 'Failed to notify inventory service',
      );
    } catch (e) {
      return ApiResponse<void>.error('Failed to notify inventory service: $e');
    }
  }

  // Check if tenant has completed stock setup
  Future<ApiResponse<bool>> hasCompletedStockSetup(String tenantId) async {
    try {
      final response = await _apiService.get(
        ApiEndpoints.tenantStockSetupStatus(tenantId),
      );

      if (response.success && response.data != null) {
        final isComplete = response.data['setup_complete'] as bool? ?? false;
        return ApiResponse<bool>.success(isComplete);
      }

      return ApiResponse<bool>.error(
        response.message ?? 'Failed to check stock setup status',
      );
    } catch (e) {
      return ApiResponse<bool>.error('Failed to check stock setup status: $e');
    }
  }
}

// Stock recommendation model
class StockRecommendation {
  final String variantId;
  final String variantName;
  final String brandName;
  final int currentStock;
  final int recommendedStock;
  final String reason;
  final double confidence;
  final String priority; // 'high', 'medium', 'low'

  const StockRecommendation({
    required this.variantId,
    required this.variantName,
    required this.brandName,
    required this.currentStock,
    required this.recommendedStock,
    required this.reason,
    required this.confidence,
    required this.priority,
  });

  factory StockRecommendation.fromJson(Map<String, dynamic> json) {
    return StockRecommendation(
      variantId: json['variant_id'] as String,
      variantName: json['variant_name'] as String,
      brandName: json['brand_name'] as String,
      currentStock: json['current_stock'] as int,
      recommendedStock: json['recommended_stock'] as int,
      reason: json['reason'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      priority: json['priority'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'variant_id': variantId,
      'variant_name': variantName,
      'brand_name': brandName,
      'current_stock': currentStock,
      'recommended_stock': recommendedStock,
      'reason': reason,
      'confidence': confidence,
      'priority': priority,
    };
  }

  int get stockDifference => recommendedStock - currentStock;
  bool get needsRestock => stockDifference > 0;
  bool get hasOverstock => stockDifference < 0;
}
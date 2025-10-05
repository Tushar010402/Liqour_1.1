import '../../../core/models/api_response.dart';
import '../../../core/services/api_service.dart';
import '../models/shop_model.dart';
import '../../../core/utils/logger.dart';

/// Shop Management Service
class ShopService {
  final ApiService _apiService;

  ShopService(this._apiService);

  /// Get all shops for the current tenant
  Future<ApiResponse<List<Shop>>> getShops() async {
    Logger.debug('🏪 ShopService.getShops() called');
    final response = await _apiService.get<List<Shop>>(
      '/api/admin/shops',
      fromJson: (data) {
        Logger.debug('🏪 ShopService: Parsing response data: $data');
        if (data is List) {
          return data.map((json) => Shop.fromJson(json as Map<String, dynamic>)).toList();
        }
        return [];
      },
    );

    Logger.debug('🏪 ShopService: Returning response');
    return response;
  }

  /// Get shop by ID
  Future<ApiResponse<Shop>> getShopById(String shopId) async {
    final response = await _apiService.get<Shop>(
      '/api/admin/shops/$shopId',
      fromJson: (data) => Shop.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Create new shop
  Future<ApiResponse<Shop>> createShop({
    required String name,
    required String address,
    required String phone,
    String? email,
    required String licenseNumber,
    String? licenseFile,
    double? latitude,
    double? longitude,
  }) async {
    final response = await _apiService.post<Shop>(
      '/api/admin/shops',
      body: {
        'name': name,
        'address': address,
        'phone': phone,
        if (email != null) 'email': email,
        'license_number': licenseNumber,
        if (licenseFile != null) 'license_file': licenseFile,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      fromJson: (data) => Shop.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }

  /// Update shop
  Future<ApiResponse<Shop>> updateShop({
    required String shopId,
    required String name,
    required String address,
    required String phone,
    String? email,
    required String licenseNumber,
    String? licenseFile,
    double? latitude,
    double? longitude,
    required bool isActive,
  }) async {
    final response = await _apiService.put<Shop>(
      '/api/admin/shops/$shopId',
      body: {
        'name': name,
        'address': address,
        'phone': phone,
        if (email != null) 'email': email,
        'license_number': licenseNumber,
        if (licenseFile != null) 'license_file': licenseFile,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'is_active': isActive,
      },
      fromJson: (data) => Shop.fromJson(data as Map<String, dynamic>),
    );

    return response;
  }
}

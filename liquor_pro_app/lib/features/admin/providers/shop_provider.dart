import 'package:flutter/material.dart';
import '../models/shop_model.dart';
import '../services/shop_service.dart';
import '../../../core/utils/logger.dart';

/// Shop Provider - Manages shop state
class ShopProvider with ChangeNotifier {
  final ShopService _shopService;

  ShopProvider(this._shopService);

  List<Shop> _shops = [];
  Shop? _selectedShop;
  bool _isLoading = false;
  String? _errorMessage;

  List<Shop> get shops => _shops;
  Shop? get selectedShop => _selectedShop;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Load all shops
  Future<void> loadShops() async {
    Logger.debug('🏪 ShopProvider.loadShops() called');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      Logger.debug('🏪 ShopProvider: Calling _shopService.getShops()');
      final response = await _shopService.getShops();
      Logger.debug('🏪 ShopProvider: Response received - success: ${response.success}, data: ${response.data}');

      if (response.success && response.data != null) {
        _shops = response.data!;
        _errorMessage = null;
        Logger.debug('🏪 ShopProvider: Loaded ${_shops.length} shops');
      } else {
        _errorMessage = response.message ?? 'Failed to load shops';
        _shops = [];
        Logger.debug('🏪 ShopProvider: Error - $_errorMessage');
      }
    } catch (e) {
      _errorMessage = 'Error loading shops: $e';
      _shops = [];
      Logger.debug('🏪 ShopProvider: Exception - $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load shop by ID
  Future<void> loadShopById(String shopId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _shopService.getShopById(shopId);

      if (response.success && response.data != null) {
        _selectedShop = response.data;
        _errorMessage = null;
      } else {
        _errorMessage = response.message ?? 'Failed to load shop';
        _selectedShop = null;
      }
    } catch (e) {
      _errorMessage = 'Error loading shop: $e';
      _selectedShop = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create new shop
  Future<bool> createShop({
    required String name,
    required String address,
    required String phone,
    String? email,
    required String licenseNumber,
    String? licenseFile,
    double? latitude,
    double? longitude,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _shopService.createShop(
        name: name,
        address: address,
        phone: phone,
        email: email,
        licenseNumber: licenseNumber,
        licenseFile: licenseFile,
        latitude: latitude,
        longitude: longitude,
      );

      if (response.success && response.data != null) {
        _shops.add(response.data!);
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to create shop';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error creating shop: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Update shop
  Future<bool> updateShop({
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
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _shopService.updateShop(
        shopId: shopId,
        name: name,
        address: address,
        phone: phone,
        email: email,
        licenseNumber: licenseNumber,
        licenseFile: licenseFile,
        latitude: latitude,
        longitude: longitude,
        isActive: isActive,
      );

      if (response.success && response.data != null) {
        final index = _shops.indexWhere((s) => s.id == shopId);
        if (index != -1) {
          _shops[index] = response.data!;
        }
        _selectedShop = response.data;
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = response.message ?? 'Failed to update shop';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error updating shop: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear selected shop
  void clearSelectedShop() {
    _selectedShop = null;
    notifyListeners();
  }
}

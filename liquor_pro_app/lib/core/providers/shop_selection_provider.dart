import 'package:flutter/foundation.dart';
import '../../features/admin/models/shop_model.dart';
import '../../features/admin/services/shop_service.dart';
import '../services/preferences_service.dart';

/// Global Shop Selection Provider
/// Manages the currently selected shop across the entire app
class ShopSelectionProvider extends ChangeNotifier {
  final ShopService _shopService;
  final UserPreferences _prefsService;

  Shop? _selectedShop;
  List<Shop> _shops = [];
  bool _isLoading = false;
  String? _errorMessage;

  ShopSelectionProvider({
    required ShopService shopService,
    required UserPreferences prefsService,
  })  : _shopService = shopService,
        _prefsService = prefsService {
    _loadSavedShop();
  }

  // Getters
  Shop? get selectedShop => _selectedShop;
  String? get selectedShopId => _selectedShop?.id;
  String? get selectedShopName => _selectedShop?.name;
  List<Shop> get shops => _shops;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasSelectedShop => _selectedShop != null;

  /// Load saved shop from preferences on app start
  Future<void> _loadSavedShop() async {
    final savedShopId = _prefsService.getSelectedShopId();
    final savedShopName = _prefsService.getSelectedShopName();

    if (savedShopId != null && savedShopName != null) {
      _selectedShop = Shop(
        id: savedShopId,
        name: savedShopName,
        address: '',
        phone: '',
        licenseNumber: '',
      );
      notifyListeners();
    }

    // Load full shop list in background
    await loadShops();
  }

  /// Load all shops for the current tenant
  Future<void> loadShops() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _shopService.getShops();

      if (response.success && response.data != null) {
        // Remove duplicates by ID
        final seenIds = <String>{};
        _shops = response.data!.where((shop) {
          if (seenIds.contains(shop.id)) {
            return false;
          }
          seenIds.add(shop.id);
          return true;
        }).toList();

        // If we have a saved shop ID, find and set the full shop object
        if (_selectedShop != null) {
          try {
            final fullShop = _shops.firstWhere(
              (shop) => shop.id == _selectedShop!.id,
            );
            _selectedShop = fullShop;
          } catch (e) {
            // Saved shop doesn't exist anymore, clear it and select first shop
            _selectedShop = null;
            await _prefsService.clearSelectedShop();
            if (_shops.isNotEmpty) {
              await selectShop(_shops.first);
            }
          }
        } else if (_shops.isNotEmpty) {
          // Auto-select first shop if none selected
          await selectShop(_shops.first);
        }
      } else {
        _errorMessage = response.message ?? 'Failed to load shops';
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load shops: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select a shop
  Future<void> selectShop(Shop shop) async {
    _selectedShop = shop;

    // Save to preferences
    await _prefsService.saveSelectedShop(shop.id, shop.name);

    notifyListeners();
  }

  /// Clear selected shop
  Future<void> clearSelection() async {
    _selectedShop = null;
    await _prefsService.clearSelectedShop();
    notifyListeners();
  }

  /// Refresh shops list
  Future<void> refreshShops() async {
    await loadShops();
  }

  /// Add a newly created shop to the list and auto-select it
  /// This provides instant feedback without requiring manual refresh
  Future<void> addShop(Shop shop) async {
    // Check for duplicates before adding
    final existingIndex = _shops.indexWhere((s) => s.id == shop.id);

    if (existingIndex == -1) {
      // Add new shop to the list
      _shops.add(shop);

      // Auto-select the newly created shop
      await selectShop(shop);

      notifyListeners();
    } else {
      // Shop already exists, just select it
      await selectShop(shop);
    }
  }

  /// Update an existing shop in the list
  /// Used when a shop is edited to keep the UI in sync
  Future<void> updateShopInList(Shop updatedShop) async {
    final index = _shops.indexWhere((s) => s.id == updatedShop.id);

    if (index != -1) {
      _shops[index] = updatedShop;

      // If this is the currently selected shop, update it
      if (_selectedShop?.id == updatedShop.id) {
        await selectShop(updatedShop);
      }

      notifyListeners();
    }
  }

  /// Remove a shop from the list (for delete operations)
  Future<void> removeShop(String shopId) async {
    _shops.removeWhere((s) => s.id == shopId);

    // If the removed shop was selected, clear selection or select first available
    if (_selectedShop?.id == shopId) {
      if (_shops.isNotEmpty) {
        await selectShop(_shops.first);
      } else {
        await clearSelection();
      }
    }

    notifyListeners();
  }

  /// Reset provider state (called on logout)
  /// Clears all data so new user starts fresh
  Future<void> reset() async {
    _selectedShop = null;
    _shops = [];
    _isLoading = false;
    _errorMessage = null;
    await _prefsService.clearSelectedShop();
    notifyListeners();
    if (kDebugMode) {
      print('🔄 [ShopSelectionProvider] State reset for logout');
    }
  }
}

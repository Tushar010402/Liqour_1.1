import 'package:flutter/foundation.dart';
import '../../../core/models/brand_package_model.dart';
import '../../../core/models/brand_model.dart';
import '../../../core/services/marketplace_service.dart';
import '../../../core/services/brand_service.dart';
import '../../../core/services/stock_integration_service.dart';

class MarketplaceProvider extends ChangeNotifier {
  final MarketplaceService _marketplaceService;
  final BrandService _brandService;
  final StockIntegrationService _stockService;

  MarketplaceProvider(
    this._marketplaceService,
    this._brandService,
    this._stockService,
  );

  // State variables
  List<BrandPackage> _packages = [];
  List<Brand> _customBrands = [];
  List<BrandCategory> _categories = [];
  MarketplaceFilter _currentFilter = const MarketplaceFilter();

  bool _isLoading = false;
  String? _error;

  // Selection state
  BrandPackage? _selectedPackage;
  final Set<String> _selectedBrandIds = {};
  final Set<String> _selectedVariantIds = {};
  String _onboardingMode = 'package'; // 'package' or 'custom'

  // Getters
  List<BrandPackage> get packages => _packages;
  List<Brand> get customBrands => _customBrands;
  List<BrandCategory> get categories => _categories;
  MarketplaceFilter get currentFilter => _currentFilter;

  bool get isLoading => _isLoading;
  String? get error => _error;

  BrandPackage? get selectedPackage => _selectedPackage;
  Set<String> get selectedBrandIds => _selectedBrandIds;
  Set<String> get selectedVariantIds => _selectedVariantIds;
  String get onboardingMode => _onboardingMode;

  bool get hasSelection =>
      (_onboardingMode == 'package' && _selectedPackage != null) ||
      (_onboardingMode == 'custom' && _selectedBrandIds.isNotEmpty);

  int get totalSelectedBrands =>
      _onboardingMode == 'package'
          ? _selectedPackage?.brandCount ?? 0
          : _selectedBrandIds.length;

  int get totalSelectedVariants =>
      _onboardingMode == 'package'
          ? _selectedPackage?.variantCount ?? 0
          : _selectedVariantIds.length;

  double get totalPrice =>
      _onboardingMode == 'package'
          ? _selectedPackage?.finalPrice ?? 0.0
          : _calculateCustomPrice();

  // Initialize marketplace data
  Future<void> initialize() async {
    await Future.wait([
      loadPackages(),
      loadCategories(),
    ]);
  }

  // Load brand packages
  Future<void> loadPackages() async {
    try {
      _setLoading(true);
      final response = await _marketplaceService.getBrandPackages(
        filter: _currentFilter,
      );

      if (response.success && response.data != null) {
        _packages = response.data!;
        _clearError();
      } else {
        _setError(response.message ?? 'Failed to load packages');
      }
    } catch (e) {
      _setError('Error loading packages: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Load categories for filtering
  Future<void> loadCategories() async {
    try {
      final response = await _brandService.getBrandCategories();

      if (response.success && response.data != null) {
        _categories = response.data!;
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  // Load custom brands for custom selection
  Future<void> loadCustomBrands({int page = 1}) async {
    try {
      if (page == 1) {
        _setLoading(true);
        _customBrands.clear();
      }

      final response = await _marketplaceService.getMarketplaceBrands(
        filter: _currentFilter,
        page: page,
        limit: 20,
      );

      if (response.success && response.data != null) {
        if (page == 1) {
          _customBrands = response.data!;
        } else {
          _customBrands.addAll(response.data!);
        }
        _clearError();
      } else {
        _setError(response.message ?? 'Failed to load brands');
      }
    } catch (e) {
      _setError('Error loading brands: $e');
    } finally {
      if (page == 1) {
        _setLoading(false);
      }
    }
  }

  // Filter operations
  void updateFilter(MarketplaceFilter filter) {
    _currentFilter = filter;
    notifyListeners();

    if (_onboardingMode == 'package') {
      loadPackages();
    } else {
      loadCustomBrands();
    }
  }

  void clearFilters() {
    _currentFilter = const MarketplaceFilter();
    notifyListeners();

    if (_onboardingMode == 'package') {
      loadPackages();
    } else {
      loadCustomBrands();
    }
  }

  // Selection operations
  void setOnboardingMode(String mode) {
    if (_onboardingMode != mode) {
      _onboardingMode = mode;
      _clearSelections();

      if (mode == 'custom' && _customBrands.isEmpty) {
        loadCustomBrands();
      }

      notifyListeners();
    }
  }

  void selectPackage(BrandPackage package) {
    _selectedPackage = package;
    _clearCustomSelections();
    notifyListeners();
  }

  void clearPackageSelection() {
    _selectedPackage = null;
    notifyListeners();
  }

  void toggleBrandSelection(String brandId) {
    if (_selectedBrandIds.contains(brandId)) {
      _selectedBrandIds.remove(brandId);
      // Remove all variants of this brand
      final brand = _customBrands.firstWhere((b) => b.id == brandId);
      if (brand.brandVariants != null) {
        for (final variant in brand.brandVariants!) {
          _selectedVariantIds.remove(variant.id);
        }
      }
    } else {
      _selectedBrandIds.add(brandId);
      // Auto-select all variants of this brand
      final brand = _customBrands.firstWhere((b) => b.id == brandId);
      if (brand.brandVariants != null) {
        for (final variant in brand.brandVariants!) {
          _selectedVariantIds.add(variant.id);
        }
      }
    }
    notifyListeners();
  }

  void toggleVariantSelection(String variantId) {
    if (_selectedVariantIds.contains(variantId)) {
      _selectedVariantIds.remove(variantId);
    } else {
      _selectedVariantIds.add(variantId);
    }
    notifyListeners();
  }

  // Complete onboarding
  Future<bool> completeOnboarding(String tenantId) async {
    try {
      _setLoading(true);

      final brandIds = _onboardingMode == 'package'
          ? _selectedPackage?.allBrandIds ?? []
          : _selectedBrandIds.toList();
      final variantIds = _onboardingMode == 'package'
          ? _selectedPackage?.allVariantIds ?? []
          : _selectedVariantIds.toList();

      final request = TenantOnboardingRequest(
        tenantId: tenantId,
        packageId: _selectedPackage?.id,
        selectedBrandIds: brandIds,
        selectedVariantIds: variantIds,
        onboardingType: _onboardingMode,
      );

      // Step 1: Complete marketplace onboarding (assign brands)
      final onboardingResponse = await _marketplaceService.completeTenantOnboarding(request);

      if (!onboardingResponse.success) {
        _setError(onboardingResponse.message ?? 'Failed to complete onboarding');
        return false;
      }

      // Step 2: Initialize stock management for assigned brands
      final suggestedStockLevels = _stockService.getSuggestedStockLevels(
        packageType: _selectedPackage?.type ?? 'custom',
        variantIds: variantIds,
        businessSize: 'medium', // Could be made configurable
      );

      final stockResponse = await _stockService.initializeStockForBrands(
        tenantId: tenantId,
        brandIds: brandIds,
        variantIds: variantIds,
        defaultStockLevel: 0, // Start with 0, tenant will set up manually
      );

      // Step 3: Notify inventory service about brand assignment
      final notificationResponse = await _stockService.notifyBrandAssignmentComplete(
        tenantId: tenantId,
        brandIds: brandIds,
        variantIds: variantIds,
        assignmentType: _onboardingMode,
      );

      // Note: We don't fail the entire process if stock initialization fails
      // The brands are assigned successfully, stock can be set up later
      if (!stockResponse.success) {
        debugPrint('Stock initialization warning: ${stockResponse.message}');
      }

      if (!notificationResponse.success) {
        debugPrint('Inventory notification warning: ${notificationResponse.message}');
      }

      _clearSelections();
      _clearError();
      return true;

    } catch (e) {
      _setError('Error completing onboarding: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Helper methods
  void _clearSelections() {
    _selectedPackage = null;
    _clearCustomSelections();
  }

  void _clearCustomSelections() {
    _selectedBrandIds.clear();
    _selectedVariantIds.clear();
  }

  double _calculateCustomPrice() {
    // Mock pricing calculation for custom selection
    // In production, this would come from the API
    return _selectedBrandIds.length * 500.0; // ₹500 per brand
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
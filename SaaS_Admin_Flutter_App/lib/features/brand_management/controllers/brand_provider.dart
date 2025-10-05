import 'package:flutter/material.dart';
import '../../../core/models/brand_model.dart';
import '../../../core/services/brand_service.dart';

class BrandProvider extends ChangeNotifier {
  final BrandService _brandService;

  BrandProvider(this._brandService);

  // State variables
  List<Brand> _brands = [];
  List<BrandCategory> _categories = [];
  List<BrandSubcategory> _subcategories = [];
  List<BrandVariant> _currentBrandVariants = [];

  Brand? _selectedBrand;
  String? _selectedCategoryId;
  String? _selectedTenantId;

  bool _isLoading = false;
  bool _isCreating = false;
  bool _isUpdating = false;
  bool _isDeleting = false;

  String? _error;
  String? _searchQuery;

  // Getters
  List<Brand> get brands => _brands;
  List<BrandCategory> get categories => _categories;
  List<BrandSubcategory> get subcategories => _subcategories;
  List<BrandVariant> get currentBrandVariants => _currentBrandVariants;

  Brand? get selectedBrand => _selectedBrand;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get selectedTenantId => _selectedTenantId;

  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isUpdating => _isUpdating;
  bool get isDeleting => _isDeleting;

  String? get error => _error;
  String? get searchQuery => _searchQuery;

  // View mode and sorting
  bool _isGridView = true;
  String _sortBy = 'name';
  bool _sortAscending = true;
  String? _selectedCategory;

  bool get isGridView => _isGridView;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;
  String? get selectedCategory => _selectedCategory;

  // Filtered brands based on search and category
  List<Brand> get filteredBrands {
    var filtered = _brands;

    // Apply search filter
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      filtered = filtered.where((brand) {
        return brand.name.toLowerCase().contains(_searchQuery!.toLowerCase()) ||
            brand.description
                .toLowerCase()
                .contains(_searchQuery!.toLowerCase());
      }).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      filtered =
          filtered.where((brand) => brand.isActive == _statusFilter).toList();
    }

    // Apply category filter
    if (_selectedCategoryId != null) {
      filtered = filtered.where((brand) {
        return brand.brandVariants
                ?.any((variant) => variant.categoryId == _selectedCategoryId) ??
            false;
      }).toList();
    }

    return filtered;
  }

  // Get subcategories for selected category
  List<BrandSubcategory> get filteredSubcategories {
    if (_selectedCategoryId == null) return _subcategories;
    return _subcategories
        .where((sub) => sub.categoryId == _selectedCategoryId)
        .toList();
  }

  // Brand Operations
  Future<void> loadBrands({
    bool includeVariants = true,
    bool showLoading = true,
    bool activeOnly = false, // Default to showing all brands for admin management
  }) async {
    if (showLoading) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final response = await _brandService.getAllBrands(
        includeVariants: includeVariants,
        activeOnly: activeOnly,
      );

      if (response.success && response.data != null) {
        _brands = response.data!;
        _error = null;
      } else {
        _error = response.message;
      }
    } catch (e) {
      _error = 'Failed to load brands: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createBrand(CreateBrandRequest request) async {
    _isCreating = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.createBrand(request);

      if (response.success && response.data != null) {
        _brands.add(response.data!);
        _error = null;
        // Reload brands to get updated list from server
        await loadBrands(showLoading: false);
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to create brand: $e';
      notifyListeners();
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  Future<bool> createBrandWithVariants(CreateBrandWithVariantsRequest request) async {
    _isCreating = true;
    _error = null;
    notifyListeners();

    try {
      // Create the brand first
      final brandRequest = CreateBrandRequest(
        name: request.name,
        description: request.description,
        picture: request.picture,
        isActive: request.isActive,
        sortOrder: request.sortOrder,
      );

      final brandResponse = await _brandService.createBrand(brandRequest);

      if (!brandResponse.success || brandResponse.data == null) {
        _error = brandResponse.message;
        notifyListeners();
        return false;
      }

      final brand = brandResponse.data!;

      // Create all variants for this brand
      final List<BrandVariant> createdVariants = [];

      for (final variantRequest in request.variants) {
        final variantRequestWithBrandId = CreateBrandVariantRequest(
          brandId: brand.id,
          categoryId: variantRequest.categoryId,
          subcategoryId: variantRequest.subcategoryId,
          size: variantRequest.size,
          alcoholContent: variantRequest.alcoholContent,
          picture: variantRequest.picture,
          governmentDuty: variantRequest.governmentDuty,
          buyingPrice: variantRequest.buyingPrice,
          sellingPrice: variantRequest.sellingPrice,
          mrp: variantRequest.mrp,
          description: variantRequest.description,
          barcode: variantRequest.barcode,
          hsnCode: variantRequest.hsnCode,
          isActive: variantRequest.isActive,
          sortOrder: variantRequest.sortOrder,
        );

        final variantResponse = await _brandService.createBrandVariant(variantRequestWithBrandId);

        if (variantResponse.success && variantResponse.data != null) {
          createdVariants.add(variantResponse.data!);
        } else {
          // If any variant fails, we still return success for the brand creation
          // but log the error
          debugPrint('Failed to create variant: ${variantResponse.message}');
        }
      }

      // Update the brand with its variants and add to list
      final updatedBrand = brand.copyWith(brandVariants: createdVariants);
      _brands.add(updatedBrand);

      _error = null;
      notifyListeners();
      return true;

    } catch (e) {
      _error = 'Failed to create brand with variants: $e';
      notifyListeners();
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  Future<bool> updateBrand(String brandId, CreateBrandRequest request) async {
    _isUpdating = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.updateBrand(brandId, request);

      if (response.success && response.data != null) {
        final index = _brands.indexWhere((b) => b.id == brandId);
        if (index != -1) {
          _brands[index] = response.data!;
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to update brand: $e';
      notifyListeners();
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> deleteBrand(String brandId) async {
    _isDeleting = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.deleteBrand(brandId);

      if (response.success) {
        _brands.removeWhere((b) => b.id == brandId);
        if (_selectedBrand?.id == brandId) {
          _selectedBrand = null;
        }
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to delete brand: $e';
      notifyListeners();
      return false;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  // Brand Variant Operations
  Future<void> loadBrandVariants(String brandId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.getBrandVariants(brandId);

      if (response.success && response.data != null) {
        _currentBrandVariants = response.data!;
        _error = null;
      } else {
        _error = response.message;
        _currentBrandVariants = [];
      }
    } catch (e) {
      _error = 'Failed to load brand variants: $e';
      _currentBrandVariants = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createBrandVariant(CreateBrandVariantRequest request) async {
    _isCreating = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.createBrandVariant(request);

      if (response.success && response.data != null) {
        _currentBrandVariants.add(response.data!);

        // Update the brand's variants if it's in the brands list
        final brandIndex = _brands.indexWhere((b) => b.id == request.brandId);
        if (brandIndex != -1) {
          final updatedVariants =
              List<BrandVariant>.from(_brands[brandIndex].brandVariants ?? []);
          updatedVariants.add(response.data!);
          _brands[brandIndex] =
              _brands[brandIndex].copyWith(brandVariants: updatedVariants);
        }

        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to create brand variant: $e';
      notifyListeners();
      return false;
    } finally {
      _isCreating = false;
      notifyListeners();
    }
  }

  Future<bool> updateBrandVariant(String variantId, CreateBrandVariantRequest request) async {
    _isUpdating = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.updateBrandVariant(variantId, request);

      if (response.success && response.data != null) {
        // Update the variant in the current brand variants list
        final index = _currentBrandVariants.indexWhere((v) => v.id == variantId);
        if (index != -1) {
          _currentBrandVariants[index] = response.data!;
        }

        // Update the variant in the brands list if it exists
        for (int i = 0; i < _brands.length; i++) {
          if (_brands[i].brandVariants != null) {
            final variantIndex = _brands[i].brandVariants!.indexWhere((v) => v.id == variantId);
            if (variantIndex != -1) {
              final updatedVariants = List<BrandVariant>.from(_brands[i].brandVariants!);
              updatedVariants[variantIndex] = response.data!;
              _brands[i] = _brands[i].copyWith(brandVariants: updatedVariants);
              break;
            }
          }
        }

        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to update brand variant: $e';
      notifyListeners();
      return false;
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> deleteBrandVariant(String variantId) async {
    _isDeleting = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.deleteBrandVariant(variantId);

      if (response.success) {
        // Remove the variant from the current brand variants list
        _currentBrandVariants.removeWhere((v) => v.id == variantId);

        // Remove the variant from the brands list if it exists
        for (int i = 0; i < _brands.length; i++) {
          if (_brands[i].brandVariants != null) {
            final variantIndex = _brands[i].brandVariants!.indexWhere((v) => v.id == variantId);
            if (variantIndex != -1) {
              final updatedVariants = List<BrandVariant>.from(_brands[i].brandVariants!);
              updatedVariants.removeAt(variantIndex);
              _brands[i] = _brands[i].copyWith(brandVariants: updatedVariants);
              break;
            }
          }
        }

        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to delete brand variant: $e';
      notifyListeners();
      return false;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }

  // Category Operations
  Future<void> loadBrandCategories() async {
    try {
      final response = await _brandService.getBrandCategories();

      if (response.success && response.data != null) {
        _categories = response.data!;
        notifyListeners();
      }
    } catch (e) {
      // Silent error for categories - not critical
      debugPrint('Failed to load brand categories: $e');
    }
  }

  Future<bool> createBrandCategory(CreateBrandCategoryRequest request) async {
    try {
      final response = await _brandService.createBrandCategory(request);

      if (response.success && response.data != null) {
        _categories.add(response.data!);
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to create brand category: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> loadBrandSubcategories({String? categoryId}) async {
    try {
      final response =
          await _brandService.getBrandSubcategories(categoryId: categoryId);

      if (response.success && response.data != null) {
        _subcategories = response.data!;
        notifyListeners();
      }
    } catch (e) {
      // Silent error for subcategories - not critical
      debugPrint('Failed to load brand subcategories: $e');
    }
  }

  Future<bool> createBrandSubcategory(
      CreateBrandSubcategoryRequest request) async {
    try {
      final response = await _brandService.createBrandSubcategory(request);

      if (response.success && response.data != null) {
        _subcategories.add(response.data!);
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to create brand subcategory: $e';
      notifyListeners();
      return false;
    }
  }

  // Tenant Brand Operations
  Future<bool> assignBrandsToTenant(
      TenantBrandAssignmentRequest request) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _brandService.assignBrandsToTenant(request);

      if (response.success) {
        _error = null;
        notifyListeners();
        return true;
      } else {
        _error = response.message;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to assign brands to tenant: $e';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Brand>> loadTenantBrands(String tenantId) async {
    try {
      final response = await _brandService.getTenantBrands(tenantId);

      if (response.success && response.data != null) {
        return response.data!;
      } else {
        _error = response.message;
        notifyListeners();
        return [];
      }
    } catch (e) {
      _error = 'Failed to load tenant brands: $e';
      notifyListeners();
      return [];
    }
  }

  // UI State Management
  void selectBrand(Brand? brand) {
    _selectedBrand = brand;
    if (brand != null) {
      _currentBrandVariants = brand.brandVariants ?? [];
      // Also load variants from API to get the most up-to-date data
      loadBrandVariants(brand.id);
    } else {
      _currentBrandVariants = [];
    }
    notifyListeners();
  }

  void selectCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }

  void selectTenant(String? tenantId) {
    _selectedTenantId = tenantId;
    notifyListeners();
  }

  void setSearchQuery(String? query) {
    _searchQuery = query;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearSelection() {
    _selectedBrand = null;
    _selectedCategoryId = null;
    _currentBrandVariants = [];
    notifyListeners();
  }

  // Search functionality
  Future<void> searchBrands(String query) async {
    setSearchQuery(query);

    if (query.isEmpty) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final response = await _brandService.searchBrands(
        query: query,
        includeVariants: true,
        categoryId: _selectedCategoryId,
      );

      if (response.success && response.data != null) {
        // Don't replace _brands, just let filteredBrands handle the filtering
        _error = null;
      } else {
        _error = response.message;
      }
    } catch (e) {
      _error = 'Failed to search brands: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Initialize data
  Future<void> initialize() async {
    await Future.wait([
      loadBrands(),
      loadBrandCategories(),
      loadBrandSubcategories(),
    ]);
  }

  // Refresh all data
  Future<void> refresh() async {
    await initialize();
  }

  // View mode and sorting methods
  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void setSortBy(String sortBy) {
    _sortBy = sortBy;
    notifyListeners();
  }

  void setSortAscending(bool ascending) {
    _sortAscending = ascending;
    notifyListeners();
  }

  void applySorting() {
    // Sort the brands list based on current sort criteria
    _brands.sort((a, b) {
      int comparison;
      switch (_sortBy) {
        case 'name':
          comparison = a.name.compareTo(b.name);
          break;
        case 'description':
          comparison = (a.description ?? '').compareTo(b.description ?? '');
          break;
        case 'createdAt':
          comparison = (a.createdAt ?? '').compareTo(b.createdAt ?? '');
          break;
        case 'updatedAt':
          comparison = (a.updatedAt ?? '').compareTo(b.updatedAt ?? '');
          break;
        default:
          comparison = a.name.compareTo(b.name);
      }
      return _sortAscending ? comparison : -comparison;
    });
    notifyListeners();
  }

  // Filtering methods
  bool? _statusFilter;

  void setStatusFilter(bool? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void clearFilters() {
    _statusFilter = null;
    _searchQuery = null;
    _selectedCategory = null;
    notifyListeners();
  }
}

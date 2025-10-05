import 'package:flutter/foundation.dart' hide Category;
import '../../../core/models/category_model.dart';
import '../../../core/services/category_service.dart';

enum CategoryState {
  initial,
  loading,
  loaded,
  error,
}

class CategoryProvider with ChangeNotifier {
  final CategoryService _categoryService;

  CategoryProvider(this._categoryService);

  // State management
  CategoryState _state = CategoryState.initial;
  String? _errorMessage;
  DateTime? _lastUpdated;

  // Data
  List<Category> _categories = [];
  List<Subcategory> _subcategories = [];
  Map<String, dynamic> _statistics = {};

  // Filters and UI state
  CategoryFilter _filter = CategoryFilter();
  bool _isGridView = true;
  String _selectedCategoryId = '';
  Category? _selectedCategory;
  List<String> _selectedCategoryIds = [];
  List<String> _selectedSubcategoryIds = [];

  // Getters
  CategoryState get state => _state;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;
  List<Category> get categories => _filteredCategories;
  List<Subcategory> get subcategories => _filteredSubcategories;
  Map<String, dynamic> get statistics => _statistics;
  CategoryFilter get filter => _filter;
  bool get isGridView => _isGridView;
  String get selectedCategoryId => _selectedCategoryId;
  Category? get selectedCategory => _selectedCategory;
  List<String> get selectedCategoryIds => _selectedCategoryIds;
  List<String> get selectedSubcategoryIds => _selectedSubcategoryIds;

  bool get isLoading => _state == CategoryState.loading;
  bool get hasError => _state == CategoryState.error;
  bool get hasData => _categories.isNotEmpty;
  bool get isSelectionMode =>
      _selectedCategoryIds.isNotEmpty || _selectedSubcategoryIds.isNotEmpty;
  int get selectedCategoryCount => _selectedCategoryIds.length;
  int get selectedSubcategoryCount => _selectedSubcategoryIds.length;

  // Filtered data
  List<Category> get _filteredCategories {
    List<Category> filtered = List.from(_categories);

    // Apply search filter
    if (_filter.searchTerm != null && _filter.searchTerm!.isNotEmpty) {
      final searchTerm = _filter.searchTerm!.toLowerCase();
      filtered = filtered
          .where((category) =>
              category.name.toLowerCase().contains(searchTerm) ||
              category.description.toLowerCase().contains(searchTerm))
          .toList();
    }

    // Apply status filter
    if (_filter.isActive != null) {
      filtered = filtered
          .where((category) => category.isActive == _filter.isActive)
          .toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      final asc = _filter.sortAscending ? 1 : -1;

      switch (_filter.sortBy) {
        case 'name':
          return a.name.compareTo(b.name) * asc;
        case 'created_at':
          return a.createdAt.compareTo(b.createdAt) * asc;
        case 'updated_at':
          return a.updatedAt.compareTo(b.updatedAt) * asc;
        case 'sort_order':
          return a.sortOrder.compareTo(b.sortOrder) * asc;
        default:
          return a.name.compareTo(b.name) * asc;
      }
    });

    return filtered;
  }

  List<Subcategory> get _filteredSubcategories {
    List<Subcategory> filtered = List.from(_subcategories);

    // Filter by selected category if any
    if (_selectedCategoryId.isNotEmpty) {
      filtered = filtered
          .where((subcategory) => subcategory.categoryId == _selectedCategoryId)
          .toList();
    }

    // Apply search filter
    if (_filter.searchTerm != null && _filter.searchTerm!.isNotEmpty) {
      final searchTerm = _filter.searchTerm!.toLowerCase();
      filtered = filtered
          .where((subcategory) =>
              subcategory.name.toLowerCase().contains(searchTerm) ||
              subcategory.description.toLowerCase().contains(searchTerm))
          .toList();
    }

    // Apply status filter
    if (_filter.isActive != null) {
      filtered = filtered
          .where((subcategory) => subcategory.isActive == _filter.isActive)
          .toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      final asc = _filter.sortAscending ? 1 : -1;

      switch (_filter.sortBy) {
        case 'name':
          return a.name.compareTo(b.name) * asc;
        case 'created_at':
          return a.createdAt.compareTo(b.createdAt) * asc;
        case 'updated_at':
          return a.updatedAt.compareTo(b.updatedAt) * asc;
        case 'sort_order':
          return a.sortOrder.compareTo(b.sortOrder) * asc;
        default:
          return a.name.compareTo(b.name) * asc;
      }
    });

    return filtered;
  }

  // Load categories
  Future<void> loadCategories() async {
    _setState(CategoryState.loading);

    try {
      final response = await _categoryService.getCategories(
        searchTerm: _filter.searchTerm,
        isActive: _filter.isActive,
        sortBy: _filter.sortBy,
        sortAscending: _filter.sortAscending,
      );

      if (response.isSuccess && response.data != null) {
        _categories = response.data!;
        _lastUpdated = DateTime.now();
        _setState(CategoryState.loaded);
        await _loadSubcategories();
        await _loadStatistics();
      } else {
        _setError(response.error ?? 'Failed to load categories');
      }
    } catch (e) {
      _setError('Failed to load categories: ${e.toString()}');
    }
  }

  // Load subcategories
  Future<void> _loadSubcategories() async {
    try {
      final response = await _categoryService.getSubcategories();
      if (response.isSuccess && response.data != null) {
        _subcategories = response.data!;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load subcategories: $e');
    }
  }

  // Load statistics
  Future<void> _loadStatistics() async {
    try {
      final response = await _categoryService.getCategoryStatistics();
      if (response.isSuccess && response.data != null) {
        _statistics = response.data!;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load statistics: $e');
    }
  }

  // Refresh all data
  Future<void> refresh() async {
    await loadCategories();
  }

  // Create category
  Future<bool> createCategory(CreateCategoryRequest request) async {
    _setState(CategoryState.loading);

    try {
      final response = await _categoryService.createCategory(request);

      if (response.isSuccess && response.data != null) {
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        _setError(response.error ?? 'Failed to create category');
        return false;
      }
    } catch (e) {
      _setError('Failed to create category: ${e.toString()}');
      return false;
    }
  }

  // Update category
  Future<bool> updateCategory(
      String categoryId, CreateCategoryRequest request) async {
    _setState(CategoryState.loading);

    try {
      final response =
          await _categoryService.updateCategory(categoryId, request);

      if (response.isSuccess && response.data != null) {
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        _setError(response.error ?? 'Failed to update category');
        return false;
      }
    } catch (e) {
      _setError('Failed to update category: ${e.toString()}');
      return false;
    }
  }

  // Delete category
  Future<bool> deleteCategory(String categoryId) async {
    print('DEBUG: CategoryProvider.deleteCategory called with ID: $categoryId');
    _setState(CategoryState.loading);

    try {
      print('DEBUG: Calling categoryService.deleteCategory($categoryId)');
      final response = await _categoryService.deleteCategory(categoryId);
      print('DEBUG: CategoryService response: ${response.isSuccess}');
      print('DEBUG: CategoryService error: ${response.error}');

      if (response.isSuccess) {
        print('DEBUG: Delete successful, reloading categories');
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        print('DEBUG: Delete failed with error: ${response.error}');
        _setError(response.error ?? 'Failed to delete category');
        return false;
      }
    } catch (e) {
      print('DEBUG: Delete threw exception: $e');
      _setError('Failed to delete category: ${e.toString()}');
      return false;
    }
  }

  // Create subcategory
  Future<bool> createSubcategory(CreateSubcategoryRequest request) async {
    _setState(CategoryState.loading);

    try {
      final response = await _categoryService.createSubcategory(request);

      if (response.isSuccess && response.data != null) {
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        _setError(response.error ?? 'Failed to create subcategory');
        return false;
      }
    } catch (e) {
      _setError('Failed to create subcategory: ${e.toString()}');
      return false;
    }
  }

  // Update subcategory
  Future<bool> updateSubcategory(
      String subcategoryId, CreateSubcategoryRequest request) async {
    _setState(CategoryState.loading);

    try {
      final response =
          await _categoryService.updateSubcategory(subcategoryId, request);

      if (response.isSuccess && response.data != null) {
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        _setError(response.error ?? 'Failed to update subcategory');
        return false;
      }
    } catch (e) {
      _setError('Failed to update subcategory: ${e.toString()}');
      return false;
    }
  }

  // Delete subcategory
  Future<bool> deleteSubcategory(String subcategoryId) async {
    print(
        'DEBUG: CategoryProvider.deleteSubcategory called with ID: $subcategoryId');
    _setState(CategoryState.loading);

    try {
      print('DEBUG: Calling categoryService.deleteSubcategory($subcategoryId)');
      final response = await _categoryService.deleteSubcategory(subcategoryId);
      print('DEBUG: SubcategoryService response: ${response.isSuccess}');
      print('DEBUG: SubcategoryService error: ${response.error}');

      if (response.isSuccess) {
        print('DEBUG: Subcategory delete successful, reloading categories');
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        print('DEBUG: Subcategory delete failed with error: ${response.error}');
        _setError(response.error ?? 'Failed to delete subcategory');
        return false;
      }
    } catch (e) {
      print('DEBUG: Subcategory delete threw exception: $e');
      _setError('Failed to delete subcategory: ${e.toString()}');
      return false;
    }
  }

  // Bulk operations
  Future<bool> bulkUpdateCategoryStatus(
      List<String> categoryIds, bool isActive) async {
    _setState(CategoryState.loading);

    try {
      final response = await _categoryService.bulkUpdateCategoryStatus(
          categoryIds, isActive);

      if (response.isSuccess) {
        clearSelection();
        await loadCategories(); // Reload to get updated list
        return true;
      } else {
        _setError(response.error ?? 'Failed to bulk update categories');
        return false;
      }
    } catch (e) {
      _setError('Failed to bulk update categories: ${e.toString()}');
      return false;
    }
  }

  // UI state methods
  void toggleViewMode() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void setFilter(CategoryFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void updateSearchTerm(String searchTerm) {
    _filter = _filter.copyWith(searchTerm: searchTerm);
    notifyListeners();
  }

  void updateStatusFilter(bool? isActive) {
    _filter = _filter.copyWith(isActive: isActive);
    notifyListeners();
  }

  void updateSortBy(String sortBy) {
    _filter = _filter.copyWith(sortBy: sortBy);
    notifyListeners();
  }

  void toggleSortOrder() {
    _filter = _filter.copyWith(sortAscending: !_filter.sortAscending);
    notifyListeners();
  }

  void selectCategory(String categoryId) {
    _selectedCategoryId = categoryId;
    _selectedCategory = _categories.firstWhere((c) => c.id == categoryId);
    notifyListeners();
  }

  void clearCategorySelection() {
    _selectedCategoryId = '';
    _selectedCategory = null;
    notifyListeners();
  }

  // Selection methods
  void toggleCategorySelection(String categoryId) {
    if (_selectedCategoryIds.contains(categoryId)) {
      _selectedCategoryIds.remove(categoryId);
    } else {
      _selectedCategoryIds.add(categoryId);
    }
    notifyListeners();
  }

  void toggleSubcategorySelection(String subcategoryId) {
    if (_selectedSubcategoryIds.contains(subcategoryId)) {
      _selectedSubcategoryIds.remove(subcategoryId);
    } else {
      _selectedSubcategoryIds.add(subcategoryId);
    }
    notifyListeners();
  }

  void selectAllCategories() {
    _selectedCategoryIds =
        _filteredCategories.map((c) => c.id).cast<String>().toList();
    notifyListeners();
  }

  void selectAllSubcategories() {
    _selectedSubcategoryIds =
        _filteredSubcategories.map((s) => s.id).cast<String>().toList();
    notifyListeners();
  }

  void clearSelection() {
    _selectedCategoryIds.clear();
    _selectedSubcategoryIds.clear();
    notifyListeners();
  }

  // Get category by ID
  Category? getCategoryById(String categoryId) {
    try {
      return _categories.firstWhere((category) => category.id == categoryId);
    } catch (e) {
      return null;
    }
  }

  // Get subcategory by ID
  Subcategory? getSubcategoryById(String subcategoryId) {
    try {
      return _subcategories
          .firstWhere((subcategory) => subcategory.id == subcategoryId);
    } catch (e) {
      return null;
    }
  }

  // Get subcategories for category
  List<Subcategory> getSubcategoriesForCategory(String categoryId) {
    return _subcategories
        .where((subcategory) => subcategory.categoryId == categoryId)
        .toList();
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    if (_state == CategoryState.error) {
      _setState(CategoryState.initial);
    }
  }

  // Private methods
  void _setState(CategoryState state) {
    _state = state;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _state = CategoryState.error;
    notifyListeners();
  }
}

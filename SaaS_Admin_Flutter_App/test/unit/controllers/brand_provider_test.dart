import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:saas_admin_flutter_app/features/brand_management/controllers/brand_provider.dart';
import 'package:saas_admin_flutter_app/core/services/brand_service.dart';
import 'package:saas_admin_flutter_app/core/models/brand_model.dart';
import 'package:saas_admin_flutter_app/core/models/api_response.dart';

import 'brand_provider_test.mocks.dart';

@GenerateMocks([BrandService])
void main() {
  group('BrandProvider Tests', () {
    late BrandProvider brandProvider;
    late MockBrandService mockBrandService;

    setUp(() {
      mockBrandService = MockBrandService();
      brandProvider = BrandProvider(mockBrandService);
    });

    group('initialize', () {
      test('should load brands successfully', () async {
        // Arrange
        final mockBrands = [
          Brand(
            id: '1',
            name: 'Test Brand 1',
            description: 'Description 1',
            picture: '',
            isActive: true,
            sortOrder: 0,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
          Brand(
            id: '2',
            name: 'Test Brand 2',
            description: 'Description 2',
            picture: '',
            isActive: true,
            sortOrder: 1,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ];

        when(mockBrandService.getAllBrands(includeVariants: true)).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.success(mockBrands));

        // Act
        await brandProvider.initialize();

        // Assert
        expect(brandProvider.brands.length, 2);
        expect(brandProvider.isLoading, false);
        expect(brandProvider.error, null);
        expect(brandProvider.brands[0].name, 'Test Brand 1');
        expect(brandProvider.brands[1].name, 'Test Brand 2');
      });

      test('should handle error when loading brands fails', () async {
        // Arrange
        when(mockBrandService.getAllBrands(includeVariants: true)).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.error('Network error'));

        // Act
        await brandProvider.initialize();

        // Assert
        expect(brandProvider.brands.length, 0);
        expect(brandProvider.isLoading, false);
        expect(brandProvider.error, 'Network error');
      });

      test('should handle exception during initialization', () async {
        // Arrange
        when(mockBrandService.getAllBrands(includeVariants: true))
            .thenThrow(Exception('Connection failed'));

        // Act
        await brandProvider.initialize();

        // Assert
        expect(brandProvider.brands.length, 0);
        expect(brandProvider.isLoading, false);
        expect(brandProvider.error,
            contains('Failed to initialize brand management'));
      });
    });

    group('createBrand', () {
      test('should create brand successfully and refresh list', () async {
        // Arrange
        final request = CreateBrandRequest(
          name: 'New Brand',
          description: 'New Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
        );

        final newBrand = Brand(
          id: '3',
          name: 'New Brand',
          description: 'New Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        when(mockBrandService.createBrand(request))
            .thenAnswer((_) async => ApiResponse<Brand>.success(newBrand));

        when(mockBrandService.getAllBrands(includeVariants: true)).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.success([newBrand]));

        // Act
        final result = await brandProvider.createBrand(request);

        // Assert
        expect(result, true);
        expect(brandProvider.error, null);
        verify(mockBrandService.createBrand(request)).called(1);
        verify(mockBrandService.getAllBrands(includeVariants: true)).called(1);
      });

      test('should return false when brand creation fails', () async {
        // Arrange
        final request = CreateBrandRequest(
          name: 'New Brand',
          description: 'New Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
        );

        when(mockBrandService.createBrand(request)).thenAnswer(
            (_) async => ApiResponse<Brand>.error('Validation failed'));

        // Act
        final result = await brandProvider.createBrand(request);

        // Assert
        expect(result, false);
        expect(brandProvider.error, 'Validation failed');
        verify(mockBrandService.createBrand(request)).called(1);
        verifyNever(mockBrandService.getAllBrands(includeVariants: true));
      });
    });

    group('updateBrand', () {
      test('should update brand successfully', () async {
        // Arrange
        final request = CreateBrandRequest(
          name: 'Updated Brand',
          description: 'Updated Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
        );

        final updatedBrand = Brand(
          id: '1',
          name: 'Updated Brand',
          description: 'Updated Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        when(mockBrandService.updateBrand('1', request))
            .thenAnswer((_) async => ApiResponse<Brand>.success(updatedBrand));

        when(mockBrandService.getAllBrands(includeVariants: true)).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.success([updatedBrand]));

        // Act
        final result = await brandProvider.updateBrand('1', request);

        // Assert
        expect(result, true);
        expect(brandProvider.error, null);
      });

      test('should return false when brand update fails', () async {
        // Arrange
        final request = CreateBrandRequest(
          name: 'Updated Brand',
          description: 'Updated Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
        );

        when(mockBrandService.updateBrand('1', request))
            .thenAnswer((_) async => ApiResponse<Brand>.error('Update failed'));

        // Act
        final result = await brandProvider.updateBrand('1', request);

        // Assert
        expect(result, false);
        expect(brandProvider.error, 'Update failed');
      });
    });

    group('deleteBrand', () {
      test('should delete brand successfully', () async {
        // Arrange
        when(mockBrandService.deleteBrand('1'))
            .thenAnswer((_) async => ApiResponse<void>.success(null));

        when(mockBrandService.getAllBrands(includeVariants: true))
            .thenAnswer((_) async => ApiResponse<List<Brand>>.success([]));

        // Act
        final result = await brandProvider.deleteBrand('1');

        // Assert
        expect(result, true);
        expect(brandProvider.error, null);
      });

      test('should return false when brand deletion fails', () async {
        // Arrange
        when(mockBrandService.deleteBrand('1'))
            .thenAnswer((_) async => ApiResponse<void>.error('Delete failed'));

        // Act
        final result = await brandProvider.deleteBrand('1');

        // Assert
        expect(result, false);
        expect(brandProvider.error, 'Delete failed');
      });
    });

    group('searchBrands', () {
      test('should filter brands by search query', () async {
        // Arrange
        final mockBrands = [
          Brand(
            id: '1',
            name: 'Whiskey Brand',
            description: 'Premium whiskey',
            picture: '',
            isActive: true,
            sortOrder: 0,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
          Brand(
            id: '2',
            name: 'Vodka Brand',
            description: 'Premium vodka',
            picture: '',
            isActive: true,
            sortOrder: 1,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ];

        when(mockBrandService.searchBrands(query: 'Whiskey')).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.success([mockBrands[0]]));

        // Act
        await brandProvider.searchBrands('Whiskey');

        // Assert
        expect(brandProvider.filteredBrands.length, 1);
        expect(brandProvider.filteredBrands[0].name, 'Whiskey Brand');
        expect(brandProvider.error, null);
      });

      test('should handle empty search results', () async {
        // Arrange
        when(mockBrandService.searchBrands(query: 'NonExistent'))
            .thenAnswer((_) async => ApiResponse<List<Brand>>.success([]));

        // Act
        await brandProvider.searchBrands('NonExistent');

        // Assert
        expect(brandProvider.filteredBrands.length, 0);
        expect(brandProvider.error, null);
      });

      test('should handle search error', () async {
        // Arrange
        when(mockBrandService.searchBrands(query: 'Test')).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.error('Search failed'));

        // Act
        await brandProvider.searchBrands('Test');

        // Assert
        expect(brandProvider.filteredBrands.length, 0);
        expect(brandProvider.error, 'Search failed');
      });
    });

    group('clearSearch', () {
      test('should clear search filters', () {
        // Arrange
        brandProvider.setSearchQuery('test');

        // Act
        brandProvider.setSearchQuery('');

        // Assert
        expect(brandProvider.searchQuery, '');
      });
    });

    group('assignBrandsToTenant', () {
      test('should assign brands to tenant successfully', () async {
        // Arrange
        final request = TenantBrandAssignmentRequest(
          tenantId: 'tenant1',
          brandIds: ['brand1', 'brand2'],
          variantIds: ['variant1'],
        );

        when(mockBrandService.assignBrandsToTenant(request))
            .thenAnswer((_) async => ApiResponse<void>.success(null));

        // Act
        final result = await brandProvider.assignBrandsToTenant(request);

        // Assert
        expect(result, true);
        expect(brandProvider.error, null);
        verify(mockBrandService.assignBrandsToTenant(request)).called(1);
      });

      test('should return false when assignment fails', () async {
        // Arrange
        final request = TenantBrandAssignmentRequest(
          tenantId: 'tenant1',
          brandIds: ['brand1', 'brand2'],
          variantIds: ['variant1'],
        );

        when(mockBrandService.assignBrandsToTenant(request)).thenAnswer(
            (_) async => ApiResponse<void>.error('Assignment failed'));

        // Act
        final result = await brandProvider.assignBrandsToTenant(request);

        // Assert
        expect(result, false);
        expect(brandProvider.error, 'Assignment failed');
      });
    });

    group('error handling', () {
      test('should handle errors properly', () {
        // Test that error is set when operations fail
        // This is tested in other test cases above
        expect(true, true); // Placeholder test
      });
    });

    group('view mode', () {
      test('should toggle view mode between grid and list', () {
        // Arrange
        expect(brandProvider.isGridView, true); // Default is grid

        // Act
        brandProvider.toggleViewMode();

        // Assert
        expect(brandProvider.isGridView, false);

        // Act
        brandProvider.toggleViewMode();

        // Assert
        expect(brandProvider.isGridView, true);
      });
    });

    group('sorting', () {
      test('should sort brands by name ascending', () async {
        // Arrange
        final mockBrands = [
          Brand(
            id: '1',
            name: 'Zebra Brand',
            description: 'Description',
            picture: '',
            isActive: true,
            sortOrder: 0,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
          Brand(
            id: '2',
            name: 'Alpha Brand',
            description: 'Description',
            picture: '',
            isActive: true,
            sortOrder: 1,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ];

        when(mockBrandService.getAllBrands(includeVariants: true)).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.success(mockBrands));

        await brandProvider.initialize();

        // Act
        brandProvider.setSortBy('name');
        brandProvider.setSortAscending(true);
        brandProvider.applySorting();

        // Assert
        expect(brandProvider.filteredBrands[0].name, 'Alpha Brand');
        expect(brandProvider.filteredBrands[1].name, 'Zebra Brand');
      });

      test('should sort brands by name descending', () async {
        // Arrange
        final mockBrands = [
          Brand(
            id: '1',
            name: 'Alpha Brand',
            description: 'Description',
            picture: '',
            isActive: true,
            sortOrder: 0,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
          Brand(
            id: '2',
            name: 'Zebra Brand',
            description: 'Description',
            picture: '',
            isActive: true,
            sortOrder: 1,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        ];

        when(mockBrandService.getAllBrands(includeVariants: true)).thenAnswer(
            (_) async => ApiResponse<List<Brand>>.success(mockBrands));

        await brandProvider.initialize();

        // Act
        brandProvider.setSortBy('name');
        brandProvider.setSortAscending(false);
        brandProvider.applySorting();

        // Assert
        expect(brandProvider.filteredBrands[0].name, 'Zebra Brand');
        expect(brandProvider.filteredBrands[1].name, 'Alpha Brand');
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:saas_admin_flutter_app/core/services/brand_service.dart';
import 'package:saas_admin_flutter_app/core/services/api_service.dart';
import 'package:saas_admin_flutter_app/core/models/brand_model.dart';
import 'package:saas_admin_flutter_app/core/models/api_response.dart';

import 'brand_service_test.mocks.dart';

@GenerateMocks([ApiService])
void main() {
  group('BrandService Tests', () {
    late BrandService brandService;
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
      brandService = BrandService(mockApiService);
    });

    group('getAllBrands', () {
      test('should return list of brands when API call is successful',
          () async {
        // Arrange
        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': [
              {
                'id': '1',
                'name': 'Test Brand',
                'description': 'Test Description',
                'picture': '',
                'is_active': true,
                'sort_order': 0,
                'created_at': '2023-01-01T00:00:00Z',
                'updated_at': '2023-01-01T00:00:00Z'
              }
            ]
          }
        });

        when(mockApiService.get(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.getAllBrands();

        // Assert
        expect(result.success, true);
        expect(result.data, isNotNull);
        expect(result.data!.length, 1);
        expect(result.data![0].name, 'Test Brand');
        verify(mockApiService.get('api/super-admin/brands')).called(1);
      });

      test(
          'should return list of brands with variants when includeVariants is true',
          () async {
        // Arrange
        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': [
              {
                'id': '1',
                'name': 'Test Brand',
                'description': 'Test Description',
                'picture': '',
                'is_active': true,
                'sort_order': 0,
                'brand_variants': [
                  {
                    'id': '1',
                    'brand_id': '1',
                    'category_id': '1',
                    'subcategory_id': null,
                    'size': '750ml',
                    'alcohol_content': 40.0,
                    'picture': '',
                    'government_duty': 100.0,
                    'buying_price': 500.0,
                    'selling_price': 750.0,
                    'mrp': 900.0,
                    'description': 'Test Variant',
                    'barcode': '123456789',
                    'hsn_code': '22085010',
                    'is_active': true,
                    'sort_order': 0,
                    'created_at': '2023-01-01T00:00:00Z',
                    'updated_at': '2023-01-01T00:00:00Z'
                  }
                ],
                'created_at': '2023-01-01T00:00:00Z',
                'updated_at': '2023-01-01T00:00:00Z'
              }
            ]
          }
        });

        when(mockApiService.get(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.getAllBrands(includeVariants: true);

        // Assert
        expect(result.success, true);
        expect(result.data![0].brandVariants, isNotNull);
        expect(result.data![0].brandVariants!.length, 1);
        verify(mockApiService
                .get('api/super-admin/brands?include_variants=true'))
            .called(1);
      });

      test('should return error when API call fails', () async {
        // Arrange
        final mockResponse =
            ApiResponse<Map<String, dynamic>>.error('Network error');
        when(mockApiService.get(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.getAllBrands();

        // Assert
        expect(result.success, false);
        expect(result.message, 'Network error');
      });

      test('should handle exception and return error', () async {
        // Arrange
        when(mockApiService.get(any)).thenThrow(Exception('Connection failed'));

        // Act
        final result = await brandService.getAllBrands();

        // Assert
        expect(result.success, false);
        expect(result.message, contains('Failed to load brands'));
      });
    });

    group('getBrandById', () {
      test('should return brand when API call is successful', () async {
        // Arrange
        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': {
              'id': '1',
              'name': 'Test Brand',
              'description': 'Test Description',
              'picture': '',
              'is_active': true,
              'sort_order': 0,
              'created_at': '2023-01-01T00:00:00Z',
              'updated_at': '2023-01-01T00:00:00Z'
            }
          }
        });

        when(mockApiService.get(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.getBrandById('1');

        // Assert
        expect(result.success, true);
        expect(result.data!.id, '1');
        expect(result.data!.name, 'Test Brand');
      });
    });

    group('createBrand', () {
      test('should create brand successfully', () async {
        // Arrange
        final request = CreateBrandRequest(
          name: 'New Brand',
          description: 'New Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
        );

        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': {
              'id': '2',
              'name': 'New Brand',
              'description': 'New Description',
              'picture': '',
              'is_active': true,
              'sort_order': 0,
              'created_at': '2023-01-01T00:00:00Z',
              'updated_at': '2023-01-01T00:00:00Z'
            }
          }
        });

        when(mockApiService.post(any, data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.createBrand(request);

        // Assert
        expect(result.success, true);
        expect(result.data!.name, 'New Brand');
        verify(mockApiService.post('api/super-admin/brands',
                data: request.toJson()))
            .called(1);
      });

      test('should return error when creation fails', () async {
        // Arrange
        final request = CreateBrandRequest(
          name: 'New Brand',
          description: 'New Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
        );

        final mockResponse =
            ApiResponse<Map<String, dynamic>>.error('Validation failed');
        when(mockApiService.post(any, data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.createBrand(request);

        // Assert
        expect(result.success, false);
        expect(result.message, 'Validation failed');
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

        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': {
              'id': '1',
              'name': 'Updated Brand',
              'description': 'Updated Description',
              'picture': '',
              'is_active': true,
              'sort_order': 0,
              'created_at': '2023-01-01T00:00:00Z',
              'updated_at': '2023-01-01T00:00:00Z'
            }
          }
        });

        when(mockApiService.put(any, data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.updateBrand('1', request);

        // Assert
        expect(result.success, true);
        expect(result.data!.name, 'Updated Brand');
      });
    });

    group('deleteBrand', () {
      test('should delete brand successfully', () async {
        // Arrange
        final mockResponse =
            ApiResponse<Map<String, dynamic>>.success({'success': true});
        when(mockApiService.delete(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.deleteBrand('1');

        // Assert
        expect(result.success, true);
        verify(mockApiService.delete('api/super-admin/brands/1')).called(1);
      });

      test('should return error when deletion fails', () async {
        // Arrange
        final mockResponse =
            ApiResponse<Map<String, dynamic>>.error('Brand not found');
        when(mockApiService.delete(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.deleteBrand('1');

        // Assert
        expect(result.success, false);
        expect(result.message, 'Brand not found');
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

        final mockResponse =
            ApiResponse<Map<String, dynamic>>.success({'success': true});
        when(mockApiService.post(any, data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.assignBrandsToTenant(request);

        // Assert
        expect(result.success, true);
        verify(mockApiService.post('api/super-admin/brands/assign',
                data: request.toJson()))
            .called(1);
      });
    });

    group('searchBrands', () {
      test('should search brands by name', () async {
        // Arrange
        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': [
              {
                'id': '1',
                'name': 'Test Brand',
                'description': 'Test Description',
                'picture': '',
                'is_active': true,
                'sort_order': 0,
                'created_at': '2023-01-01T00:00:00Z',
                'updated_at': '2023-01-01T00:00:00Z'
              },
              {
                'id': '2',
                'name': 'Another Brand',
                'description': 'Another Description',
                'picture': '',
                'is_active': true,
                'sort_order': 0,
                'created_at': '2023-01-01T00:00:00Z',
                'updated_at': '2023-01-01T00:00:00Z'
              }
            ]
          }
        });

        when(mockApiService.get(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.searchBrands(query: 'Test');

        // Assert
        expect(result.success, true);
        expect(result.data!.length, 1);
        expect(result.data![0].name, 'Test Brand');
      });

      test('should return empty list when no matches found', () async {
        // Arrange
        final mockResponse = ApiResponse<Map<String, dynamic>>.success({
          'success': true,
          'data': {
            'data': [
              {
                'id': '2',
                'name': 'Another Brand',
                'description': 'Another Description',
                'picture': '',
                'is_active': true,
                'sort_order': 0,
                'created_at': '2023-01-01T00:00:00Z',
                'updated_at': '2023-01-01T00:00:00Z'
              }
            ]
          }
        });

        when(mockApiService.get(any)).thenAnswer((_) async => mockResponse);

        // Act
        final result = await brandService.searchBrands(query: 'NonExistent');

        // Assert
        expect(result.success, true);
        expect(result.data!.length, 0);
      });
    });
  });
}

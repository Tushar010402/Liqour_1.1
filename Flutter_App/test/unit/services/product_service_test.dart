import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:dio/dio.dart';

import '../../../lib/data/services/product_service.dart';
import '../../../lib/data/models/product_model.dart';
import '../../../lib/data/models/api_response_model.dart';
import '../../../lib/core/api/api_client.dart';
import '../../../lib/core/api/api_exceptions.dart';
import '../../helpers/test_helpers.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  group('ProductService Tests', () {
    late ProductService productService;
    late MockApiClient mockApiClient;

    setUp(() async {
      await TestHelpers.initializeTestEnvironment();
      mockApiClient = MockApiClient();
      productService = ProductService();
    });

    tearDown(() async {
      await TestHelpers.cleanupTestEnvironment();
    });

    group('Product Fetching', () {
      test('should fetch products successfully', () async {
        // Arrange
        final mockProducts = TestDataGenerators.generateProductList(10);
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: mockProducts),
        );

        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getProducts();

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.data, hasLength(10));
        
        verify(mockApiClient.get('/api/products', queryParameters: {
          'page': 1,
          'limit': 20,
        })).called(1);
      });

      test('should fetch products with filters', () async {
        // Arrange
        final mockProducts = TestDataGenerators.generateProductList(5);
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: mockProducts),
        );

        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getProducts(
          page: 2,
          limit: 10,
          search: 'whiskey',
          category: 'spirits',
          minPrice: 50.0,
          maxPrice: 200.0,
          inStock: true,
          sortBy: 'price',
          sortOrder: 'asc',
          tags: ['premium', 'aged'],
        );

        // Assert
        expect(result.isSuccessful, isTrue);
        
        verify(mockApiClient.get('/api/products', queryParameters: {
          'page': 2,
          'limit': 10,
          'search': 'whiskey',
          'category': 'spirits',
          'min_price': 50.0,
          'max_price': 200.0,
          'in_stock': true,
          'sort_by': 'price',
          'sort_order': 'asc',
          'tags': 'premium,aged',
        })).called(1);
      });

      test('should handle empty product list', () async {
        // Arrange
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: <Map<String, dynamic>>[]),
        );

        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getProducts();

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.data, isEmpty);
      });

      test('should handle network errors', () async {
        // Arrange
        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenThrow(NetworkException('No internet connection'));

        // Act & Assert
        expect(
          () => productService.getProducts(),
          throwsA(isA<UnknownException>()),
        );
      });
    });

    group('Single Product Fetching', () {
      test('should fetch single product successfully', () async {
        // Arrange
        const productId = 'product-1';
        final mockProduct = TestHelpers.createTestProduct(id: productId);
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': mockProduct,
        });

        when(mockApiClient.get('/api/products/$productId'))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getProduct(productId);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.id, productId);
        
        verify(mockApiClient.get('/api/products/$productId')).called(1);
      });

      test('should handle product not found', () async {
        // Arrange
        const productId = 'non-existent-product';

        when(mockApiClient.get('/api/products/$productId'))
            .thenThrow(NotFoundException('Product not found'));

        // Act & Assert
        expect(
          () => productService.getProduct(productId),
          throwsA(isA<NotFoundException>()),
        );
      });

      test('should validate product ID format', () async {
        // Arrange
        const invalidProductId = '';

        // Act & Assert
        expect(
          () => productService.getProduct(invalidProductId),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Product Categories', () {
      test('should fetch categories successfully', () async {
        // Arrange
        final mockCategories = [
          {
            'id': 'cat-1',
            'name': 'Whiskey',
            'slug': 'whiskey',
            'description': 'Premium whiskey collection',
            'is_active': true,
            'sort_order': 1,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
          {
            'id': 'cat-2',
            'name': 'Wine',
            'slug': 'wine',
            'description': 'Fine wine selection',
            'is_active': true,
            'sort_order': 2,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
        ];

        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': mockCategories,
        });

        when(mockApiClient.get('/api/products/categories'))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getCategories();

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, hasLength(2));
        expect(result.data?[0].name, 'Whiskey');
        expect(result.data?[1].name, 'Wine');

        verify(mockApiClient.get('/api/products/categories')).called(1);
      });

      test('should handle empty categories list', () async {
        // Arrange
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': <Map<String, dynamic>>[],
        });

        when(mockApiClient.get('/api/products/categories'))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getCategories();

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, isEmpty);
      });
    });

    group('Product Search', () {
      test('should search products successfully', () async {
        // Arrange
        const query = 'single malt';
        final mockProducts = TestDataGenerators.generateProductList(3);
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: mockProducts),
        );

        when(mockApiClient.get('/api/products/search', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.searchProducts(query: query);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, hasLength(3));

        verify(mockApiClient.get('/api/products/search', queryParameters: {
          'q': query,
          'page': 1,
          'limit': 20,
        })).called(1);
      });

      test('should search with advanced filters', () async {
        // Arrange
        const query = 'whiskey';
        final mockProducts = TestDataGenerators.generateProductList(5);
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: mockProducts),
        );

        when(mockApiClient.get('/api/products/search', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.searchProducts(
          query: query,
          categories: ['whiskey', 'bourbon'],
          tags: ['premium'],
          minPrice: 100.0,
          maxPrice: 500.0,
          inStock: true,
          sortBy: 'rating',
          sortOrder: 'desc',
        );

        // Assert
        expect(result.isSuccessful, isTrue);

        verify(mockApiClient.get('/api/products/search', queryParameters: {
          'q': query,
          'page': 1,
          'limit': 20,
          'categories': 'whiskey,bourbon',
          'tags': 'premium',
          'min_price': 100.0,
          'max_price': 500.0,
          'in_stock': true,
          'sort_by': 'rating',
          'sort_order': 'desc',
        })).called(1);
      });

      test('should handle empty search query', () async {
        // Arrange
        const query = '';

        // Act & Assert
        expect(
          () => productService.searchProducts(query: query),
          throwsA(isA<Exception>()),
        );
      });

      test('should handle search with no results', () async {
        // Arrange
        const query = 'nonexistent product';
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: <Map<String, dynamic>>[]),
        );

        when(mockApiClient.get('/api/products/search', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.searchProducts(query: query);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, isEmpty);
      });
    });

    group('Featured Products', () {
      test('should fetch featured products successfully', () async {
        // Arrange
        final mockProducts = TestDataGenerators.generateProductList(5);
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': mockProducts,
        });

        when(mockApiClient.get('/api/products/featured', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getFeaturedProducts(limit: 5);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, hasLength(5));

        verify(mockApiClient.get('/api/products/featured', queryParameters: {
          'limit': 5,
        })).called(1);
      });

      test('should handle no featured products', () async {
        // Arrange
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': <Map<String, dynamic>>[],
        });

        when(mockApiClient.get('/api/products/featured', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getFeaturedProducts();

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, isEmpty);
      });
    });

    group('Product Recommendations', () {
      test('should fetch recommendations for product', () async {
        // Arrange
        const productId = 'product-1';
        final mockProducts = TestDataGenerators.generateProductList(4);
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': mockProducts,
        });

        when(mockApiClient.get('/api/products/recommendations', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getRecommendations(
          productId: productId,
          limit: 4,
        );

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, hasLength(4));

        verify(mockApiClient.get('/api/products/recommendations', queryParameters: {
          'limit': 4,
          'product_id': productId,
        })).called(1);
      });

      test('should fetch recommendations for user', () async {
        // Arrange
        const userId = 'user-1';
        final mockProducts = TestDataGenerators.generateProductList(6);
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': mockProducts,
        });

        when(mockApiClient.get('/api/products/recommendations', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getRecommendations(
          userId: userId,
          limit: 6,
        );

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, hasLength(6));

        verify(mockApiClient.get('/api/products/recommendations', queryParameters: {
          'limit': 6,
          'user_id': userId,
        })).called(1);
      });
    });

    group('Product Availability', () {
      test('should check product availability successfully', () async {
        // Arrange
        const productId = 'product-1';
        const quantity = 2;
        const location = 'warehouse-1';

        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': {
            'available': true,
            'available_quantity': 10,
            'estimated_restock_date': null,
            'available_locations': ['warehouse-1', 'warehouse-2'],
            'message': 'Product is available',
          },
        });

        when(mockApiClient.post('/api/products/$productId/availability', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.checkAvailability(
          productId: productId,
          quantity: quantity,
          location: location,
        );

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.available, isTrue);
        expect(result.data?.availableQuantity, 10);

        verify(mockApiClient.post('/api/products/$productId/availability', data: {
          'quantity': quantity,
          'location': location,
        })).called(1);
      });

      test('should handle out of stock product', () async {
        // Arrange
        const productId = 'product-1';
        const quantity = 5;

        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': {
            'available': false,
            'available_quantity': 0,
            'estimated_restock_date': DateTime.now().add(const Duration(days: 7)).toIso8601String(),
            'available_locations': <String>[],
            'message': 'Product is out of stock',
          },
        });

        when(mockApiClient.post('/api/products/$productId/availability', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.checkAvailability(
          productId: productId,
          quantity: quantity,
        );

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.available, isFalse);
        expect(result.data?.availableQuantity, 0);
        expect(result.data?.estimatedRestockDate, isNotNull);
      });
    });

    group('Product Reviews', () {
      test('should fetch product reviews successfully', () async {
        // Arrange
        const productId = 'product-1';
        final mockReviews = [
          {
            'id': 'review-1',
            'product_id': productId,
            'user_id': 'user-1',
            'user_name': 'John Doe',
            'rating': 5,
            'comment': 'Excellent product!',
            'is_verified_purchase': true,
            'helpful_count': 10,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          },
        ];

        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: mockReviews),
        );

        when(mockApiClient.get('/api/products/$productId/reviews', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getReviews(productId: productId);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.data, hasLength(1));
        expect(result.data?.data[0].rating, 5);

        verify(mockApiClient.get('/api/products/$productId/reviews', queryParameters: {
          'page': 1,
          'limit': 20,
        })).called(1);
      });

      test('should create product review successfully', () async {
        // Arrange
        const productId = 'product-1';
        const rating = 4;
        const comment = 'Good product, fast delivery';

        final mockReview = {
          'id': 'review-1',
          'product_id': productId,
          'user_id': 'user-1',
          'rating': rating,
          'comment': comment,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };

        final mockResponse = TestHelpers.createMockResponse(
          data: {
            'success': true,
            'data': mockReview,
          },
          statusCode: 201,
        );

        when(mockApiClient.post('/api/products/$productId/reviews', data: anyNamed('data')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.createReview(
          productId: productId,
          rating: rating,
          comment: comment,
        );

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data?.rating, rating);
        expect(result.data?.comment, comment);

        verify(mockApiClient.post('/api/products/$productId/reviews', data: {
          'rating': rating,
          'comment': comment,
        })).called(1);
      });

      test('should validate review data', () async {
        // Arrange
        const productId = 'product-1';
        const invalidRating = 0; // Rating should be 1-5
        const comment = 'Test comment';

        when(mockApiClient.post('/api/products/$productId/reviews', data: anyNamed('data')))
            .thenThrow(ValidationException('Invalid rating', {'rating': ['Rating must be between 1 and 5']}));

        // Act & Assert
        expect(
          () => productService.createReview(
            productId: productId,
            rating: invalidRating,
            comment: comment,
          ),
          throwsA(isA<ValidationException>()),
        );
      });
    });

    group('Favorites Management', () {
      test('should add product to favorites successfully', () async {
        // Arrange
        const productId = 'product-1';

        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': {'favorited': true},
        });

        when(mockApiClient.post('/api/products/$productId/favorite'))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.addToFavorites(productId);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, isTrue);

        verify(mockApiClient.post('/api/products/$productId/favorite')).called(1);
      });

      test('should remove product from favorites successfully', () async {
        // Arrange
        const productId = 'product-1';

        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': {'favorited': false},
        });

        when(mockApiClient.delete('/api/products/$productId/favorite'))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.removeFromFavorites(productId);

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, isTrue);

        verify(mockApiClient.delete('/api/products/$productId/favorite')).called(1);
      });

      test('should fetch user favorites successfully', () async {
        // Arrange
        final mockProducts = TestDataGenerators.generateProductList(3);
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(data: mockProducts),
        );

        when(mockApiClient.get('/api/products/favorites', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async => mockResponse);

        // Act
        final result = await productService.getFavorites();

        // Assert
        expect(result.isSuccessful, isTrue);
        expect(result.data, hasLength(3));

        verify(mockApiClient.get('/api/products/favorites', queryParameters: {
          'page': 1,
          'limit': 20,
        })).called(1);
      });
    });

    group('Performance Tests', () {
      test('should handle large product lists efficiently', () async {
        // Arrange
        final mockProducts = TestDataGenerators.generateProductList(1000);
        final mockResponse = TestHelpers.createMockResponse(
          data: TestHelpers.createPaginatedResponse(
            data: mockProducts.take(50).toList(),
            total: 1000,
            perPage: 50,
          ),
        );

        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenAnswer((_) async {
              await TestHelpers.mockNetworkDelay(const Duration(milliseconds: 100));
              return mockResponse;
            });

        // Act & Assert
        await TestHelpers.testPerformance(
          'Large Product List Performance',
          () async {
            final result = await productService.getProducts(limit: 50);
            expect(result.isSuccessful, isTrue);
            expect(result.data?.data, hasLength(50));
          },
        );
      });

      test('should handle concurrent product requests', () async {
        // Arrange
        final mockProduct = TestHelpers.createTestProduct();
        final mockResponse = TestHelpers.createMockResponse(data: {
          'success': true,
          'data': mockProduct,
        });

        when(mockApiClient.get('/api/products/product-1'))
            .thenAnswer((_) async => mockResponse);

        // Act
        final futures = List.generate(10, (index) => 
          productService.getProduct('product-1'),
        );

        final results = await Future.wait(futures);

        // Assert
        expect(results.length, 10);
        for (final result in results) {
          expect(result.isSuccessful, isTrue);
          expect(result.data?.id, 'product-1');
        }
      });
    });

    group('Error Handling', () {
      test('should handle validation errors', () async {
        // Arrange
        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenThrow(ValidationException('Invalid parameters', {
              'page': ['Page must be positive integer'],
              'limit': ['Limit must be between 1 and 100'],
            }));

        // Act & Assert
        expect(
          () => productService.getProducts(page: -1, limit: 0),
          throwsA(isA<ValidationException>()),
        );
      });

      test('should handle rate limiting', () async {
        // Arrange
        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenThrow(RateLimitException('Too many requests', retryAfter: 60));

        // Act & Assert
        expect(
          () => productService.getProducts(),
          throwsA(isA<RateLimitException>()),
        );
      });

      test('should handle server maintenance', () async {
        // Arrange
        when(mockApiClient.get('/api/products', queryParameters: anyNamed('queryParameters')))
            .thenThrow(ServerException('Service under maintenance', statusCode: 503));

        // Act & Assert
        expect(
          () => productService.getProducts(),
          throwsA(isA<ServerException>()),
        );
      });
    });
  });
}
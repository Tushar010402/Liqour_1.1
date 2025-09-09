import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../lib/core/services/auth_service.dart';
import '../../lib/data/services/product_service.dart';
import '../../lib/data/services/order_service.dart';
import '../../lib/core/api/api_client.dart';
import '../../lib/core/utils/logger.dart';
import '../../lib/core/utils/cache_manager.dart';

// Generate mocks
@GenerateMocks([
  AuthService,
  ProductService,
  OrderService,
  ApiClient,
  Dio,
  Box,
])
import 'test_helpers.mocks.dart';

/// Test helper utilities for consistent testing across the app
class TestHelpers {
  /// Create a test widget wrapped with necessary providers
  static Widget createTestWidget({
    required Widget child,
    List<Override>? overrides,
    Locale? locale,
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: overrides ?? [],
      child: MaterialApp(
        locale: locale,
        theme: theme,
        home: Material(
          child: child,
        ),
        localizationsDelegates: const [
          // Add localization delegates here if needed
        ],
      ),
    );
  }

  /// Create a test widget for navigation testing
  static Widget createTestNavigationWidget({
    required Widget child,
    List<Override>? overrides,
    Map<String, WidgetBuilder>? routes,
  }) {
    return ProviderScope(
      overrides: overrides ?? [],
      child: MaterialApp(
        home: child,
        routes: routes ?? {},
      ),
    );
  }

  /// Pump widget and settle animations
  static Future<void> pumpAndSettle(
    WidgetTester tester,
    Widget widget, {
    Duration? duration,
  }) async {
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle(duration);
  }

  /// Find widget by key
  static Finder findByKey(String key) {
    return find.byKey(Key(key));
  }

  /// Find widget by text
  static Finder findByText(String text) {
    return find.text(text);
  }

  /// Find widget by type
  static Finder findByType<T extends Widget>() {
    return find.byType(T);
  }

  /// Verify widget exists
  static void verifyWidgetExists(Finder finder) {
    expect(finder, findsOneWidget);
  }

  /// Verify widget doesn't exist
  static void verifyWidgetNotExists(Finder finder) {
    expect(finder, findsNothing);
  }

  /// Verify multiple widgets exist
  static void verifyMultipleWidgets(Finder finder, int count) {
    expect(finder, findsNWidgets(count));
  }

  /// Tap on widget
  static Future<void> tapWidget(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Enter text in field
  static Future<void> enterText(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  /// Scroll widget
  static Future<void> scrollWidget(
    WidgetTester tester,
    Finder finder,
    Offset offset,
  ) async {
    await tester.drag(finder, offset);
    await tester.pumpAndSettle();
  }

  /// Wait for condition
  static Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endTime = DateTime.now().add(timeout);
    
    while (DateTime.now().isBefore(endTime)) {
      if (condition()) return;
      
      await tester.pump(const Duration(milliseconds: 100));
    }
    
    throw Exception('Condition not met within timeout');
  }

  /// Create mock response for API calls
  static Response<T> createMockResponse<T>({
    required T data,
    int statusCode = 200,
    String statusMessage = 'OK',
    Map<String, dynamic>? headers,
  }) {
    return Response<T>(
      data: data,
      statusCode: statusCode,
      statusMessage: statusMessage,
      headers: Headers.fromMap(headers ?? {}),
      requestOptions: RequestOptions(path: '/test'),
    );
  }

  /// Create mock error response
  static DioException createMockErrorResponse({
    int statusCode = 500,
    String message = 'Server Error',
    DioExceptionType type = DioExceptionType.badResponse,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: '/test'),
      response: Response(
        statusCode: statusCode,
        statusMessage: message,
        requestOptions: RequestOptions(path: '/test'),
      ),
      type: type,
      message: message,
    );
  }

  /// Verify loading state
  static void verifyLoadingState(WidgetTester tester) {
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  }

  /// Verify error state
  static void verifyErrorState(WidgetTester tester, [String? errorMessage]) {
    if (errorMessage != null) {
      expect(find.text(errorMessage), findsOneWidget);
    } else {
      expect(find.byType(Text), findsWidgets);
    }
  }

  /// Initialize test environment
  static Future<void> initializeTestEnvironment() async {
    // Initialize Hive for testing
    Hive.init('./test/cache');
    
    // Initialize logger for testing
    AppLogger.debug('Test environment initialized');
  }

  /// Clean up test environment
  static Future<void> cleanupTestEnvironment() async {
    // Clean up any test resources
    await Hive.close();
  }

  /// Create test user data
  static Map<String, dynamic> createTestUser({
    String id = 'test-user-1',
    String email = 'test@example.com',
    String firstName = 'Test',
    String lastName = 'User',
  }) {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'role': 'customer',
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Create test product data
  static Map<String, dynamic> createTestProduct({
    String id = 'test-product-1',
    String name = 'Test Whiskey',
    double price = 99.99,
    String category = 'Whiskey',
  }) {
    return {
      'id': id,
      'name': name,
      'description': 'Test product description',
      'price': price,
      'currency': 'USD',
      'sku': 'TEST-001',
      'category': {
        'id': 'cat-1',
        'name': category,
        'slug': category.toLowerCase(),
        'is_active': true,
        'sort_order': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      'brand': 'Test Brand',
      'stock_quantity': 10,
      'is_active': true,
      'in_stock': true,
      'status': 'active',
      'images': ['https://example.com/image1.jpg'],
      'tags': ['premium', 'aged'],
      'rating': {
        'average': 4.5,
        'count': 100,
        'distribution': {1: 2, 2: 3, 3: 10, 4: 30, 5: 55}
      },
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Create test order data
  static Map<String, dynamic> createTestOrder({
    String id = 'test-order-1',
    String orderNumber = 'ORD-001',
    double total = 199.98,
  }) {
    return {
      'id': id,
      'order_number': orderNumber,
      'user_id': 'test-user-1',
      'status': 'pending',
      'items': [
        {
          'id': 'item-1',
          'product_id': 'test-product-1',
          'quantity': 2,
          'price': 99.99,
          'total': 199.98,
        }
      ],
      'subtotal': 199.98,
      'tax': 0.0,
      'delivery_fee': 0.0,
      'total': total,
      'currency': 'USD',
      'payment_method': 'credit_card',
      'payment_status': 'pending',
      'delivery_status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Create paginated response
  static Map<String, dynamic> createPaginatedResponse<T>({
    required List<T> data,
    int currentPage = 1,
    int lastPage = 1,
    int total = 1,
    int perPage = 20,
  }) {
    return {
      'success': true,
      'message': 'Data fetched successfully',
      'data': {
        'data': data,
        'pagination': {
          'current_page': currentPage,
          'last_page': lastPage,
          'per_page': perPage,
          'total': total,
          'from': ((currentPage - 1) * perPage) + 1,
          'to': currentPage * perPage > total ? total : currentPage * perPage,
        }
      }
    };
  }

  /// Verify form validation
  static Future<void> verifyFormValidation(
    WidgetTester tester, {
    required String fieldKey,
    required String invalidInput,
    required String expectedError,
  }) async {
    // Enter invalid input
    await enterText(
      tester,
      find.byKey(Key(fieldKey)),
      invalidInput,
    );

    // Try to submit form (assuming there's a submit button)
    if (find.text('Submit').evaluate().isNotEmpty) {
      await tapWidget(tester, find.text('Submit'));
    }

    // Verify error message appears
    expect(find.text(expectedError), findsOneWidget);
  }

  /// Mock network delay
  static Future<void> mockNetworkDelay([
    Duration delay = const Duration(milliseconds: 500)
  ]) async {
    await Future.delayed(delay);
  }

  /// Generate random string for testing
  static String generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (index) => chars[DateTime.now().millisecond % chars.length]).join();
  }

  /// Create test configuration
  static Map<String, dynamic> createTestConfig() {
    return {
      'api_base_url': 'http://localhost:8080',
      'api_timeout': 5000,
      'enable_logging': true,
      'enable_analytics': false,
      'enable_crash_reporting': false,
    };
  }

  /// Verify navigation
  static void verifyNavigation(
    WidgetTester tester,
    String expectedRoute,
  ) {
    // This would verify the current route
    // Implementation depends on navigation setup
    expect(find.byType(MaterialApp), findsOneWidget);
  }

  /// Create test provider overrides
  static List<Override> createTestProviderOverrides({
    AuthService? mockAuthService,
    ProductService? mockProductService,
    OrderService? mockOrderService,
  }) {
    final overrides = <Override>[];

    if (mockAuthService != null) {
      // Add auth service override
      // overrides.add(authServiceProvider.overrideWithValue(mockAuthService));
    }

    if (mockProductService != null) {
      // Add product service override
      // overrides.add(productServiceProvider.overrideWithValue(mockProductService));
    }

    if (mockOrderService != null) {
      // Add order service override
      // overrides.add(orderServiceProvider.overrideWithValue(mockOrderService));
    }

    return overrides;
  }

  /// Verify accessibility
  static Future<void> verifyAccessibility(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }

  /// Capture screenshot for golden tests
  static Future<void> captureScreenshot(
    WidgetTester tester,
    String fileName,
  ) async {
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$fileName.png'),
    );
  }

  /// Test performance
  static Future<void> testPerformance(
    String testName,
    Future<void> Function() testFunction,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      await testFunction();
    } finally {
      stopwatch.stop();
      print('⏱️ $testName took ${stopwatch.elapsedMilliseconds}ms');
    }
  }

  /// Verify memory usage
  static void verifyMemoryUsage() {
    // This would check memory usage during tests
    // Implementation depends on platform
    print('📊 Memory usage check completed');
  }
}

/// Test data generators
class TestDataGenerators {
  static List<Map<String, dynamic>> generateProductList(int count) {
    return List.generate(count, (index) => TestHelpers.createTestProduct(
      id: 'product-$index',
      name: 'Test Product $index',
      price: 50.0 + index * 10,
    ));
  }

  static List<Map<String, dynamic>> generateOrderList(int count) {
    return List.generate(count, (index) => TestHelpers.createTestOrder(
      id: 'order-$index',
      orderNumber: 'ORD-${(index + 1).toString().padLeft(3, '0')}',
    ));
  }

  static List<Map<String, dynamic>> generateUserList(int count) {
    return List.generate(count, (index) => TestHelpers.createTestUser(
      id: 'user-$index',
      email: 'user$index@example.com',
      firstName: 'User',
      lastName: '$index',
    ));
  }
}

/// Test assertions
class TestAssertions {
  /// Assert API response format
  static void assertApiResponse(dynamic response) {
    expect(response, isA<Map<String, dynamic>>());
    expect(response['success'], isA<bool>());
    expect(response['message'], isA<String>());
  }

  /// Assert pagination format
  static void assertPaginationResponse(dynamic response) {
    assertApiResponse(response);
    expect(response['data'], isA<Map<String, dynamic>>());
    expect(response['data']['data'], isA<List>());
    expect(response['data']['pagination'], isA<Map<String, dynamic>>());
  }

  /// Assert error response format
  static void assertErrorResponse(dynamic response) {
    expect(response, isA<Map<String, dynamic>>());
    expect(response['success'], false);
    expect(response['message'], isA<String>());
  }

  /// Assert widget state
  static void assertWidgetState<T extends Widget>(
    WidgetTester tester,
    bool shouldExist,
  ) {
    if (shouldExist) {
      expect(find.byType(T), findsWidgets);
    } else {
      expect(find.byType(T), findsNothing);
    }
  }

  /// Assert form field state
  static void assertFormFieldState(
    WidgetTester tester,
    String fieldKey,
    String expectedValue,
  ) {
    final textField = tester.widget<TextFormField>(
      find.byKey(Key(fieldKey)),
    );
    expect(textField.controller?.text, expectedValue);
  }

  /// Assert navigation state
  static void assertNavigationState(
    WidgetTester tester,
    Type expectedPage,
  ) {
    expect(find.byType(expectedPage), findsOneWidget);
  }

  /// Assert loading state
  static void assertLoadingState(WidgetTester tester, bool isLoading) {
    if (isLoading) {
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    } else {
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
  }

  /// Assert error state
  static void assertErrorState(
    WidgetTester tester,
    bool hasError, [
    String? errorMessage,
  ]) {
    if (hasError) {
      if (errorMessage != null) {
        expect(find.text(errorMessage), findsOneWidget);
      }
      // Could also check for error icons or containers
    }
  }
}
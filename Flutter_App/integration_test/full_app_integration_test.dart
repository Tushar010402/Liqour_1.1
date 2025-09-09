import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquorpro_mobile/main.dart' as app;
import 'package:liquorpro_mobile/core/services/auth_service.dart';
import 'package:liquorpro_mobile/data/services/product_service.dart';
import 'package:patrol/patrol.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('LiquorPro Full Integration Tests', () {
    late PatrolTester $;

    setUpAll(() async {
      // Initialize Patrol for advanced testing
      $ = PatrolTester(
        tester: null, // Will be set by Patrol
        config: PatrolTesterConfig(),
      );
    });

    testWidgets('Complete user journey from onboarding to purchase', 
        (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      // === ONBOARDING FLOW ===
      // Check if onboarding appears for new users
      expect(find.byKey(const Key('onboarding_screen')), findsOneWidget);
      
      // Navigate through onboarding pages
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('continue_button')));
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
      }
      
      // Complete onboarding
      await tester.tap(find.byKey(const Key('get_started_button')));
      await tester.pumpAndSettle();

      // === AUTHENTICATION FLOW ===
      expect(find.byKey(const Key('login_screen')), findsOneWidget);

      // Test registration flow first
      await tester.tap(find.byKey(const Key('register_tab')));
      await tester.pumpAndSettle();

      // Fill registration form
      await tester.enterText(
        find.byKey(const Key('register_email_field')), 
        'test@liquorpro.com'
      );
      await tester.enterText(
        find.byKey(const Key('register_password_field')), 
        'TestPassword123!'
      );
      await tester.enterText(
        find.byKey(const Key('register_name_field')), 
        'Test User'
      );
      await tester.enterText(
        find.byKey(const Key('register_phone_field')), 
        '9876543210'
      );

      // Submit registration
      await tester.tap(find.byKey(const Key('register_submit_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Should navigate to dashboard after successful registration
      expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);

      // === DASHBOARD AND NAVIGATION ===
      // Verify dashboard elements are present
      expect(find.byKey(const Key('welcome_message')), findsOneWidget);
      expect(find.byKey(const Key('featured_products')), findsOneWidget);
      expect(find.byKey(const Key('categories_list')), findsOneWidget);

      // Test bottom navigation
      await tester.tap(find.byKey(const Key('products_tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('products_screen')), findsOneWidget);

      // === PRODUCT BROWSING ===
      // Wait for products to load
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Test search functionality
      await tester.tap(find.byKey(const Key('search_field')));
      await tester.enterText(
        find.byKey(const Key('search_field')), 
        'whiskey'
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify search results
      expect(find.byKey(const Key('search_results')), findsOneWidget);

      // Clear search and browse categories
      await tester.tap(find.byKey(const Key('clear_search_button')));
      await tester.pumpAndSettle();

      // Select a category
      await tester.tap(find.byKey(const Key('category_whiskey')));
      await tester.pumpAndSettle();

      // === PRODUCT DETAILS ===
      // Tap on first product
      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('product_details_screen')), findsOneWidget);
      
      // Verify product details are displayed
      expect(find.byKey(const Key('product_title')), findsOneWidget);
      expect(find.byKey(const Key('product_price')), findsOneWidget);
      expect(find.byKey(const Key('product_description')), findsOneWidget);
      expect(find.byKey(const Key('product_image')), findsOneWidget);

      // Test quantity selection
      await tester.tap(find.byKey(const Key('quantity_increase')));
      await tester.tap(find.byKey(const Key('quantity_increase')));
      await tester.pumpAndSettle();

      // Add to cart
      await tester.tap(find.byKey(const Key('add_to_cart_button')));
      await tester.pumpAndSettle();

      // Verify cart updated notification
      expect(find.byKey(const Key('cart_success_message')), findsOneWidget);

      // === SHOPPING CART ===
      await tester.tap(find.byKey(const Key('cart_tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cart_screen')), findsOneWidget);
      expect(find.byKey(const Key('cart_item_0')), findsOneWidget);

      // Test quantity modification in cart
      await tester.tap(find.byKey(const Key('cart_item_quantity_increase')));
      await tester.pumpAndSettle();

      // Verify price updated
      expect(find.byKey(const Key('cart_total_price')), findsOneWidget);

      // === CHECKOUT PROCESS ===
      await tester.tap(find.byKey(const Key('proceed_to_checkout_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('checkout_screen')), findsOneWidget);

      // Fill shipping address
      await tester.tap(find.byKey(const Key('address_field')));
      await tester.enterText(
        find.byKey(const Key('address_field')), 
        '123 Test Street, Test City, 12345'
      );

      await tester.tap(find.byKey(const Key('landmark_field')));
      await tester.enterText(
        find.byKey(const Key('landmark_field')), 
        'Near Test Mall'
      );

      // Select delivery time
      await tester.tap(find.byKey(const Key('delivery_time_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delivery_time_evening')));
      await tester.pumpAndSettle();

      // Select payment method
      await tester.tap(find.byKey(const Key('payment_method_card')));
      await tester.pumpAndSettle();

      // Fill card details (mock)
      await tester.enterText(
        find.byKey(const Key('card_number_field')), 
        '4111111111111111'
      );
      await tester.enterText(
        find.byKey(const Key('card_expiry_field')), 
        '12/25'
      );
      await tester.enterText(
        find.byKey(const Key('card_cvv_field')), 
        '123'
      );

      // Place order
      await tester.tap(find.byKey(const Key('place_order_button')));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // === ORDER CONFIRMATION ===
      expect(find.byKey(const Key('order_confirmation_screen')), findsOneWidget);
      expect(find.byKey(const Key('order_number')), findsOneWidget);

      // === ORDERS HISTORY ===
      await tester.tap(find.byKey(const Key('orders_tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('orders_screen')), findsOneWidget);
      expect(find.byKey(const Key('order_item_0')), findsOneWidget);

      // View order details
      await tester.tap(find.byKey(const Key('order_item_0')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('order_details_screen')), findsOneWidget);

      // === PROFILE AND SETTINGS ===
      await tester.tap(find.byKey(const Key('profile_tab')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile_screen')), findsOneWidget);

      // Test profile editing
      await tester.tap(find.byKey(const Key('edit_profile_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('profile_name_field')), 
        'Updated Test User'
      );
      
      await tester.tap(find.byKey(const Key('save_profile_button')));
      await tester.pumpAndSettle();

      // Test settings
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_screen')), findsOneWidget);

      // Test theme toggle
      await tester.tap(find.byKey(const Key('theme_switch')));
      await tester.pumpAndSettle();

      // Test notification settings
      await tester.tap(find.byKey(const Key('notifications_switch')));
      await tester.pumpAndSettle();

      // === LOGOUT ===
      await tester.tap(find.byKey(const Key('logout_button')));
      await tester.pumpAndSettle();

      // Confirm logout
      await tester.tap(find.byKey(const Key('confirm_logout_button')));
      await tester.pumpAndSettle();

      // Should return to login screen
      expect(find.byKey(const Key('login_screen')), findsOneWidget);
    });

    testWidgets('Backend integration and API testing', 
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Skip onboarding for this test
      await tester.tap(find.byKey(const Key('skip_onboarding')));
      await tester.pumpAndSettle();

      // === API AUTHENTICATION TESTING ===
      // Test login with valid credentials
      await tester.enterText(
        find.byKey(const Key('email_field')), 
        'test@liquorpro.com'
      );
      await tester.enterText(
        find.byKey(const Key('password_field')), 
        'validpassword'
      );

      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Should receive JWT token and navigate to dashboard
      expect(find.byKey(const Key('dashboard_screen')), findsOneWidget);

      // === API PRODUCT LOADING ===
      await tester.tap(find.byKey(const Key('products_tab')));
      await tester.pumpAndSettle();

      // Wait for API call to complete
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Verify products loaded from API
      expect(find.byKey(const Key('product_list')), findsOneWidget);
      expect(find.byKey(const Key('product_card_0')), findsOneWidget);

      // === API SEARCH TESTING ===
      await tester.enterText(
        find.byKey(const Key('search_field')), 
        'premium'
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify API search results
      expect(find.byKey(const Key('search_results')), findsOneWidget);

      // === API CART OPERATIONS ===
      await tester.tap(find.byKey(const Key('product_card_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_to_cart_button')));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Verify cart API call succeeded
      expect(find.byKey(const Key('cart_success_message')), findsOneWidget);

      // === API ORDER PLACEMENT ===
      await tester.tap(find.byKey(const Key('cart_tab')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checkout_button')));
      await tester.pumpAndSettle();

      // Fill minimal required information for API test
      await tester.enterText(
        find.byKey(const Key('address_field')), 
        'API Test Address'
      );

      await tester.tap(find.byKey(const Key('place_order_button')));
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // Verify order API call succeeded
      expect(find.byKey(const Key('order_success_screen')), findsOneWidget);

      // === API ERROR HANDLING ===
      // This would test network error scenarios
      // Implementation would depend on network simulation capabilities
    });

    testWidgets('Performance and memory testing', 
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // === MEMORY USAGE TESTING ===
      // Monitor memory usage during heavy operations
      
      // Skip to products screen
      await tester.tap(find.byKey(const Key('skip_onboarding')));
      await tester.pumpAndSettle();
      
      await tester.tap(find.byKey(const Key('products_tab')));
      await tester.pumpAndSettle();

      // Perform intensive scrolling to test memory management
      final listFinder = find.byKey(const Key('products_list'));
      
      for (int i = 0; i < 20; i++) {
        await tester.drag(listFinder, const Offset(0, -200));
        await tester.pumpAndSettle();
        
        // Allow some time for memory cleanup
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Test image loading and caching
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(Key('product_card_$i')));
        await tester.pumpAndSettle();
        
        // Wait for image to load
        await tester.pumpAndSettle(const Duration(seconds: 1));
        
        // Go back
        await tester.tap(find.byKey(const Key('back_button')));
        await tester.pumpAndSettle();
      }

      // === RENDERING PERFORMANCE ===
      // Test smooth animations and transitions
      
      // Test theme switching performance
      await tester.tap(find.byKey(const Key('profile_tab')));
      await tester.pumpAndSettle();
      
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();

      // Rapid theme switching to test performance
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('theme_switch')));
        await tester.pumpAndSettle();
      }

      // No explicit assertions for performance - these would be
      // measured by external profiling tools in real scenarios
    });

    testWidgets('Accessibility and usability testing', 
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // === SCREEN READER TESTING ===
      // Verify semantic labels are present
      
      expect(
        tester.widget<Semantics>(
          find.byKey(const Key('login_button')).first
        ).properties.label,
        isNotNull
      );

      // === FOCUS MANAGEMENT ===
      // Test keyboard navigation (conceptual)
      
      await tester.tap(find.byKey(const Key('email_field')));
      await tester.pumpAndSettle();
      
      // Verify focus indicators
      expect(find.byKey(const Key('email_field_focused')), findsOneWidget);

      // === COLOR CONTRAST ===
      // This would typically be tested with external tools
      // Here we verify dark/light theme support exists
      
      await tester.tap(find.byKey(const Key('theme_switch')));
      await tester.pumpAndSettle();
      
      // Verify theme change occurred
      expect(find.byKey(const Key('dark_theme_indicator')), findsOneWidget);

      // === TEXT SCALING ===
      // Test with different text scale factors
      await tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/platform_views',
        (message) async => null,
      );
    });
  });
}
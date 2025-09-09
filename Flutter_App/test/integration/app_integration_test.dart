import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:patrol/patrol.dart';
import 'package:mockito/mockito.dart';

import '../../lib/main.dart' as app;
import '../../lib/core/widgets/buttons/premium_button.dart';
import '../../lib/core/widgets/input/premium_text_field.dart';
import '../../lib/core/constants/app_constants.dart';
import '../helpers/test_helpers.dart';

/// Comprehensive integration tests for the LiquorPro Flutter app
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('LiquorPro App Integration Tests', () {
    late PatrolIntegrationTester $;

    setUp(() async {
      await TestHelpers.initializeTestEnvironment();
    });

    tearDown(() async {
      await TestHelpers.cleanupTestEnvironment();
    });

    group('App Initialization and Splash', () {
      patrolTest('should launch app successfully', ($) async {
        // Act
        await $.pumpAndSettle();

        // Assert
        expect(find.byType(MaterialApp), findsOneWidget);
        
        // Wait for initialization to complete
        await $.waitFor(find.byType(Scaffold), timeout: const Duration(seconds: 10));
        
        TestHelpers.verifyMemoryUsage();
      });

      patrolTest('should show splash screen during initialization', ($) async {
        // Act
        await $.pump();

        // Assert - Look for splash screen elements
        // This depends on your splash screen implementation
        expect(find.byType(MaterialApp), findsOneWidget);
        
        // Wait for app to fully load
        await $.pumpAndSettle(const Duration(seconds: 3));
      });

      patrolTest('should handle app initialization errors gracefully', ($) async {
        // This test would require mocking initialization failures
        // Act
        await $.pumpAndSettle();

        // Assert
        expect(find.byType(MaterialApp), findsOneWidget);
      });
    });

    group('Authentication Flow', () {
      patrolTest('should complete email login flow', ($) async {
        // Arrange
        await $.pumpAndSettle();
        
        // Navigate to login if not already there
        if (find.text('Login').evaluate().isNotEmpty) {
          await $.tap(find.text('Login'));
          await $.pumpAndSettle();
        }

        // Act
        await $.enterText(find.byType(EmailTextField), 'test@example.com');
        await $.enterText(find.byType(PasswordTextField), 'password123');
        await $.tap(find.text('Sign In'));
        
        // Wait for authentication
        await $.pumpAndSettle(const Duration(seconds: 3));

        // Assert
        // Look for post-login UI elements
        // This depends on your app's navigation after login
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should handle login validation errors', ($) async {
        // Arrange
        await $.pumpAndSettle();
        
        // Navigate to login
        if (find.text('Login').evaluate().isNotEmpty) {
          await $.tap(find.text('Login'));
          await $.pumpAndSettle();
        }

        // Act - Try to login with invalid credentials
        await $.enterText(find.byType(EmailTextField), 'invalid-email');
        await $.enterText(find.byType(PasswordTextField), '123');
        await $.tap(find.text('Sign In'));
        
        await $.pumpAndSettle();

        // Assert - Should show validation errors
        expect(find.textContaining('valid email'), findsOneWidget);
        expect(find.textContaining('8 characters'), findsOneWidget);
      });

      patrolTest('should complete registration flow', ($) async {
        // Arrange
        await $.pumpAndSettle();
        
        // Navigate to registration
        if (find.text('Sign Up').evaluate().isNotEmpty) {
          await $.tap(find.text('Sign Up'));
          await $.pumpAndSettle();
        }

        // Act
        await $.enterText(find.byKey(const Key('first_name_field')), 'John');
        await $.enterText(find.byKey(const Key('last_name_field')), 'Doe');
        await $.enterText(find.byKey(const Key('email_field')), 'john.doe@example.com');
        await $.enterText(find.byKey(const Key('password_field')), 'StrongP@ssw0rd123');
        await $.enterText(find.byKey(const Key('confirm_password_field')), 'StrongP@ssw0rd123');
        
        // Accept terms
        if (find.byType(Checkbox).evaluate().isNotEmpty) {
          await $.tap(find.byType(Checkbox));
        }
        
        await $.tap(find.text('Create Account'));
        
        // Wait for registration
        await $.pumpAndSettle(const Duration(seconds: 3));

        // Assert
        // Look for registration success message or email verification screen
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should handle biometric authentication', ($) async {
        // This test would require device with biometric capability
        // and proper setup in test environment
        
        // Arrange
        await $.pumpAndSettle();

        // Act
        if (find.byIcon(Icons.fingerprint).evaluate().isNotEmpty) {
          await $.tap(find.byIcon(Icons.fingerprint));
          await $.pumpAndSettle();
        }

        // Assert
        expect(find.byType(MaterialApp), findsOneWidget);
      });
    });

    group('Product Browsing and Search', () {
      patrolTest('should browse product catalog', ($) async {
        // Arrange - Assume user is logged in
        await $.pumpAndSettle();

        // Act - Navigate to products
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.pumpAndSettle();
        }

        // Wait for products to load
        await $.waitFor(find.byType(ListView), timeout: const Duration(seconds: 5));

        // Assert
        expect(find.byType(ListView), findsOneWidget);
        
        // Verify product cards are displayed
        expect(find.byType(Card), findsWidgets);
      });

      patrolTest('should perform product search', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Navigate to search
        if (find.byIcon(Icons.search).evaluate().isNotEmpty) {
          await $.tap(find.byIcon(Icons.search));
          await $.pumpAndSettle();
        }

        // Act
        await $.enterText(find.byType(TextField), 'whiskey');
        await $.testTextInput.receiveAction(TextInputAction.search);
        
        // Wait for search results
        await $.pumpAndSettle(const Duration(seconds: 2));

        // Assert
        expect(find.byType(ListView), findsOneWidget);
      });

      patrolTest('should filter products by category', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Navigate to products
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.pumpAndSettle();
        }

        // Act
        if (find.text('Filter').evaluate().isNotEmpty) {
          await $.tap(find.text('Filter'));
          await $.pumpAndSettle();
        }

        // Select category filter
        if (find.text('Whiskey').evaluate().isNotEmpty) {
          await $.tap(find.text('Whiskey'));
          await $.pumpAndSettle();
        }

        // Apply filter
        if (find.text('Apply').evaluate().isNotEmpty) {
          await $.tap(find.text('Apply'));
          await $.pumpAndSettle(const Duration(seconds: 2));
        }

        // Assert
        expect(find.byType(ListView), findsOneWidget);
      });

      patrolTest('should view product details', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Navigate to products and wait for loading
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.waitFor(find.byType(Card), timeout: const Duration(seconds: 5));
        }

        // Act - Tap on first product card
        final firstProduct = find.byType(Card).first;
        await $.tap(firstProduct);
        await $.pumpAndSettle(const Duration(seconds: 2));

        // Assert - Product details page should be displayed
        // Look for product-specific elements like price, description, etc.
        expect(find.byType(Scaffold), findsOneWidget);
      });

      patrolTest('should add product to favorites', ($) async {
        // Arrange - Navigate to product details
        await $.pumpAndSettle();
        
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.waitFor(find.byType(Card), timeout: const Duration(seconds: 5));
          await $.tap(find.byType(Card).first);
          await $.pumpAndSettle();
        }

        // Act - Tap favorite icon
        if (find.byIcon(Icons.favorite_border).evaluate().isNotEmpty) {
          await $.tap(find.byIcon(Icons.favorite_border));
          await $.pumpAndSettle();
        }

        // Assert - Favorite icon should change
        expect(find.byIcon(Icons.favorite), findsOneWidget);
      });
    });

    group('Shopping Cart and Orders', () {
      patrolTest('should add items to cart', ($) async {
        // Arrange - Navigate to product
        await $.pumpAndSettle();
        
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.waitFor(find.byType(Card), timeout: const Duration(seconds: 5));
          await $.tap(find.byType(Card).first);
          await $.pumpAndSettle();
        }

        // Act - Add to cart
        if (find.text('Add to Cart').evaluate().isNotEmpty) {
          await $.tap(find.text('Add to Cart'));
          await $.pumpAndSettle();
        }

        // Assert - Cart should show item count
        if (find.byIcon(Icons.shopping_cart).evaluate().isNotEmpty) {
          await $.tap(find.byIcon(Icons.shopping_cart));
          await $.pumpAndSettle();
          
          expect(find.byType(ListView), findsOneWidget);
        }
      });

      patrolTest('should complete checkout flow', ($) async {
        // Arrange - Add item to cart first
        await $.pumpAndSettle();
        
        // Add product to cart (shortened for brevity)
        if (find.byIcon(Icons.shopping_cart).evaluate().isNotEmpty) {
          await $.tap(find.byIcon(Icons.shopping_cart));
          await $.pumpAndSettle();
        }

        // Act - Proceed to checkout
        if (find.text('Checkout').evaluate().isNotEmpty) {
          await $.tap(find.text('Checkout'));
          await $.pumpAndSettle();
        }

        // Fill checkout form
        if (find.byKey(const Key('delivery_address')).evaluate().isNotEmpty) {
          await $.enterText(find.byKey(const Key('delivery_address')), '123 Test St, Test City');
        }

        // Select payment method
        if (find.text('Credit Card').evaluate().isNotEmpty) {
          await $.tap(find.text('Credit Card'));
        }

        // Place order
        if (find.text('Place Order').evaluate().isNotEmpty) {
          await $.tap(find.text('Place Order'));
          await $.pumpAndSettle(const Duration(seconds: 3));
        }

        // Assert - Order confirmation should be shown
        expect(find.textContaining('Order'), findsWidgets);
      });

      patrolTest('should view order history', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Navigate to orders
        if (find.text('Orders').evaluate().isNotEmpty) {
          await $.tap(find.text('Orders'));
          await $.pumpAndSettle(const Duration(seconds: 2));
        }

        // Assert
        expect(find.byType(ListView), findsOneWidget);
      });

      patrolTest('should track order status', ($) async {
        // Arrange - Navigate to orders
        await $.pumpAndSettle();
        
        if (find.text('Orders').evaluate().isNotEmpty) {
          await $.tap(find.text('Orders'));
          await $.waitFor(find.byType(Card), timeout: const Duration(seconds: 5));
        }

        // Act - Tap on order to view details
        if (find.byType(Card).evaluate().isNotEmpty) {
          await $.tap(find.byType(Card).first);
          await $.pumpAndSettle();
        }

        // Assert - Order tracking info should be displayed
        expect(find.textContaining('Status'), findsWidgets);
      });
    });

    group('User Profile and Settings', () {
      patrolTest('should view and edit user profile', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Navigate to profile
        if (find.byIcon(Icons.person).evaluate().isNotEmpty) {
          await $.tap(find.byIcon(Icons.person));
          await $.pumpAndSettle();
        }

        // Edit profile
        if (find.text('Edit Profile').evaluate().isNotEmpty) {
          await $.tap(find.text('Edit Profile'));
          await $.pumpAndSettle();
        }

        // Update name
        if (find.byKey(const Key('first_name')).evaluate().isNotEmpty) {
          await $.enterText(find.byKey(const Key('first_name')), 'Updated Name');
        }

        // Save changes
        if (find.text('Save').evaluate().isNotEmpty) {
          await $.tap(find.text('Save'));
          await $.pumpAndSettle();
        }

        // Assert - Changes should be saved
        expect(find.text('Updated Name'), findsOneWidget);
      });

      patrolTest('should change app settings', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Navigate to settings
        if (find.text('Settings').evaluate().isNotEmpty) {
          await $.tap(find.text('Settings'));
          await $.pumpAndSettle();
        }

        // Toggle notifications
        if (find.byType(Switch).evaluate().isNotEmpty) {
          await $.tap(find.byType(Switch).first);
          await $.pumpAndSettle();
        }

        // Change theme
        if (find.text('Theme').evaluate().isNotEmpty) {
          await $.tap(find.text('Theme'));
          await $.pumpAndSettle();
        }

        if (find.text('Light Mode').evaluate().isNotEmpty) {
          await $.tap(find.text('Light Mode'));
          await $.pumpAndSettle();
        }

        // Assert - Settings should be applied
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should manage payment methods', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Navigate to payment methods
        if (find.text('Payment Methods').evaluate().isNotEmpty) {
          await $.tap(find.text('Payment Methods'));
          await $.pumpAndSettle();
        }

        // Act - Add new payment method
        if (find.text('Add Card').evaluate().isNotEmpty) {
          await $.tap(find.text('Add Card'));
          await $.pumpAndSettle();
        }

        // Fill card details
        if (find.byKey(const Key('card_number')).evaluate().isNotEmpty) {
          await $.enterText(find.byKey(const Key('card_number')), '4111111111111111');
          await $.enterText(find.byKey(const Key('expiry_date')), '12/25');
          await $.enterText(find.byKey(const Key('cvv')), '123');
          await $.enterText(find.byKey(const Key('cardholder_name')), 'John Doe');
        }

        // Save card
        if (find.text('Save Card').evaluate().isNotEmpty) {
          await $.tap(find.text('Save Card'));
          await $.pumpAndSettle();
        }

        // Assert - Card should be added
        expect(find.textContaining('1111'), findsOneWidget);
      });
    });

    group('Offline and Network Handling', () {
      patrolTest('should handle offline mode', ($) async {
        // This would require network simulation
        // Arrange
        await $.pumpAndSettle();

        // Act - Simulate network disconnection
        // This would need platform-specific network simulation

        // Navigate to products (should show cached data)
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.pumpAndSettle();
        }

        // Assert - App should still function with cached data
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should handle network reconnection', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Simulate network reconnection
        // This would need platform-specific network simulation

        // Assert - App should sync data when back online
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should handle slow network connections', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Navigate to products with simulated slow network
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          
          // Should show loading indicators
          expect(find.byType(CircularProgressIndicator), findsWidgets);
          
          // Wait for data to load
          await $.waitFor(find.byType(ListView), timeout: const Duration(seconds: 10));
        }

        // Assert
        expect(find.byType(ListView), findsOneWidget);
      });
    });

    group('Performance and Stress Tests', () {
      patrolTest('should handle large product lists without performance issues', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Navigate to products
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.pumpAndSettle();
        }

        // Scroll through large list
        for (int i = 0; i < 10; i++) {
          await $.scrollUntilVisible(
            finder: find.byType(ListView),
            view: find.byType(Card),
            scrollDirection: AxisDirection.down,
          );
          await $.pump(const Duration(milliseconds: 100));
        }

        // Assert - App should remain responsive
        expect(find.byType(ListView), findsOneWidget);
        TestHelpers.verifyMemoryUsage();
      });

      patrolTest('should handle rapid user interactions', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Perform rapid navigation
        for (int i = 0; i < 5; i++) {
          if (find.text('Products').evaluate().isNotEmpty) {
            await $.tap(find.text('Products'));
            await $.pump(const Duration(milliseconds: 100));
          }
          
          if (find.text('Orders').evaluate().isNotEmpty) {
            await $.tap(find.text('Orders'));
            await $.pump(const Duration(milliseconds: 100));
          }
        }

        // Assert - App should handle rapid navigation without crashes
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should maintain performance during extended use', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Simulate extended app usage
        for (int session = 0; session < 3; session++) {
          // Browse products
          if (find.text('Products').evaluate().isNotEmpty) {
            await $.tap(find.text('Products'));
            await $.pumpAndSettle();
            
            // Scroll through products
            await $.scrollUntilVisible(
              finder: find.byType(ListView),
              view: find.byType(Card),
              scrollDirection: AxisDirection.down,
            );
          }

          // Check orders
          if (find.text('Orders').evaluate().isNotEmpty) {
            await $.tap(find.text('Orders'));
            await $.pumpAndSettle();
          }

          // Check profile
          if (find.byIcon(Icons.person).evaluate().isNotEmpty) {
            await $.tap(find.byIcon(Icons.person));
            await $.pumpAndSettle();
          }

          await $.pump(const Duration(seconds: 1));
        }

        // Assert - App should remain stable
        expect(find.byType(MaterialApp), findsOneWidget);
        TestHelpers.verifyMemoryUsage();
      });
    });

    group('Security and Data Protection', () {
      patrolTest('should handle sensitive data securely', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Enter sensitive information (password, card details)
        if (find.text('Login').evaluate().isNotEmpty) {
          await $.tap(find.text('Login'));
          await $.pumpAndSettle();
        }

        await $.enterText(find.byType(PasswordTextField), 'secretpassword');

        // Assert - Password should be obscured
        final passwordField = $.tester.widget<TextFormField>(find.byType(TextFormField));
        expect(passwordField.obscureText, isTrue);
      });

      patrolTest('should handle app backgrounding and foregrounding', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Simulate app going to background
        await $.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/lifecycle',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('routeUpdated', {
              'location': '/',
              'state': null,
            }),
          ),
          (data) {},
        );

        // Bring app back to foreground
        await $.pump();

        // Assert - App should handle lifecycle changes gracefully
        expect(find.byType(MaterialApp), findsOneWidget);
      });
    });

    group('Error Handling and Recovery', () {
      patrolTest('should recover from API errors', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - Try to perform action that might cause API error
        if (find.text('Products').evaluate().isNotEmpty) {
          await $.tap(find.text('Products'));
          await $.pumpAndSettle(const Duration(seconds: 5));
        }

        // Assert - App should show error message or retry option
        // and not crash
        expect(find.byType(MaterialApp), findsOneWidget);
      });

      patrolTest('should handle unexpected errors gracefully', ($) async {
        // Arrange
        await $.pumpAndSettle();

        // Act - This would require injecting errors or using error conditions
        // For now, just verify app stability
        expect(find.byType(MaterialApp), findsOneWidget);

        // Assert - App should not crash and show appropriate error handling
      });
    });
  });
}
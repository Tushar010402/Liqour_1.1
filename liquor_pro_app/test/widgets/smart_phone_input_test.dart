import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquor_pro_app/core/widgets/smart_phone_input.dart';

void main() {
  group('SmartPhoneInput Widget Tests', () {
    late TextEditingController controller;

    setUp(() {
      controller = TextEditingController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('renders with default configuration', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
            ),
          ),
        ),
      );

      // Verify widget renders
      expect(find.byType(SmartPhoneInput), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays label when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              label: 'Phone Number',
            ),
          ),
        ),
      );

      expect(find.text('Phone Number'), findsOneWidget);
    });

    testWidgets('displays hint when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              hint: 'Enter your phone',
            ),
          ),
        ),
      );

      expect(find.text('Enter your phone'), findsOneWidget);
    });

    testWidgets('displays country code dropdown', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
            ),
          ),
        ),
      );

      // Country code dropdown should be present
      expect(find.text('+91'), findsOneWidget);
    });

    testWidgets('formats phone number as user types', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              defaultCountryCode: '+91',
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);

      // Type phone number
      await tester.enterText(textField, '9876543210');
      await tester.pump();

      // Verify formatting is applied (India format: XXXXX XXXXX)
      expect(controller.text, contains(' '));
    });

    testWidgets('calls onChanged callback when text changes', (WidgetTester tester) async {
      String? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onChanged: (value) {
                changedValue = value;
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '9876543210');
      await tester.pump();

      expect(changedValue, isNotNull);
      expect(changedValue, contains('+91'));
    });

    testWidgets('shows validation spinner when validating', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onValidate: (phone) async {
                // Simulate slow validation
                await Future.delayed(const Duration(milliseconds: 100));
                return const ValidationResult(
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '9876543210');

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 800));

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for validation to complete
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('shows success icon when phone is available', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onValidate: (phone) async {
                return const ValidationResult(
                  isAvailable: true,
                  message: 'Phone number available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '9876543210');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show success icon
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows error icon when phone is unavailable', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onValidate: (phone) async {
                return const ValidationResult(
                  isAvailable: false,
                  message: 'Phone number already registered',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '9876543210');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show error icon
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('shows helper text with validation message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onValidate: (phone) async {
                return const ValidationResult(
                  isAvailable: true,
                  message: 'Phone number available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '9876543210');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Phone number available'), findsOneWidget);
    });

    testWidgets('displays external error text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              errorText: 'Custom error message',
            ),
          ),
        ),
      );

      expect(find.text('Custom error message'), findsOneWidget);
    });

    testWidgets('can be disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              enabled: false,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('changes country code when dropdown is used', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              defaultCountryCode: '+91',
            ),
          ),
        ),
      );

      // Tap on country code dropdown
      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();

      // Select different country code (USA)
      await tester.tap(find.text('+1').last);
      await tester.pumpAndSettle();

      // Verify country code changed
      expect(find.text('+1'), findsWidgets);
    });

    testWidgets('validates only after debounce delay', (WidgetTester tester) async {
      int validationCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              validationDebounce: const Duration(milliseconds: 800),
              onValidate: (phone) async {
                validationCallCount++;
                return const ValidationResult(
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);

      // Type rapidly (should only trigger one validation)
      await tester.enterText(textField, '9');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(textField, '98');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(textField, '987');
      await tester.pump(const Duration(milliseconds: 100));

      // Validation should not have been called yet
      expect(validationCallCount, 0);

      // Wait for full debounce period
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      // Validation should have been called once
      expect(validationCallCount, 1);
    });

    testWidgets('caches validation results', (WidgetTester tester) async {
      int validationCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onValidate: (phone) async {
                validationCallCount++;
                return const ValidationResult(
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);

      // Enter same number twice
      await tester.enterText(textField, '9876543210');
      await tester.pump(const Duration(milliseconds: 900));

      expect(validationCallCount, 1);

      // Delete and re-enter same number
      await tester.enterText(textField, '987654321');
      await tester.pump(const Duration(milliseconds: 900));

      await tester.enterText(textField, '9876543210');
      await tester.pump(const Duration(milliseconds: 900));

      // Should still be 1 due to caching
      expect(validationCallCount, 1);
    });

    testWidgets('handles network errors gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartPhoneInput(
              controller: controller,
              onValidate: (phone) async {
                throw Exception('Network error');
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, '9876543210');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      // Should show network error message
      expect(find.text('Network error - please try again'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });
  });

  group('PhoneValidator Tests', () {
    test('validates correct phone formats', () {
      expect(PhoneValidator.isValid('9876543210'), isTrue);
      expect(PhoneValidator.isValid('1234567890'), isTrue);
    });

    test('rejects invalid phone formats', () {
      expect(PhoneValidator.isValid('123'), isFalse);
      expect(PhoneValidator.isValid('abc'), isFalse);
      expect(PhoneValidator.isValid(''), isFalse);
    });

    test('cleans phone numbers correctly', () {
      expect(PhoneValidator.clean('+91 98765 43210'), '919876543210');
      expect(PhoneValidator.clean('+1 (555) 123-4567'), '15551234567');
      expect(PhoneValidator.clean('  +91 98765 43210  '), '919876543210');
    });

    test('gets error messages for invalid phones', () {
      expect(PhoneValidator.getErrorMessage(''), 'Phone number is required');
      expect(PhoneValidator.getErrorMessage('123'), 'Please enter a valid phone number');
      expect(PhoneValidator.getErrorMessage('9876543210'), isNull);
    });
  });

  group('ValidationResult Tests', () {
    test('creates validation result correctly', () {
      const result = ValidationResult(
        isAvailable: true,
        message: 'Test message',
      );

      expect(result.isAvailable, isTrue);
      expect(result.message, 'Test message');
    });

    test('has checking constant', () {
      expect(ValidationResult.checking.isAvailable, isFalse);
      expect(ValidationResult.checking.message, 'Checking availability...');
    });

    test('has network error constant', () {
      expect(ValidationResult.networkError.isAvailable, isFalse);
      expect(ValidationResult.networkError.message, 'Network error - please try again');
    });
  });
}

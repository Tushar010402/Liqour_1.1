import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquor_pro_app/core/widgets/smart_email_input.dart';

void main() {
  group('SmartEmailInput Widget Tests', () {
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
            body: SmartEmailInput(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byType(SmartEmailInput), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays label when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              label: 'Email Address',
            ),
          ),
        ),
      );

      expect(find.text('Email Address'), findsOneWidget);
    });

    testWidgets('displays hint when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              hint: 'Enter your email',
            ),
          ),
        ),
      );

      expect(find.text('Enter your email'), findsOneWidget);
    });

    testWidgets('shows email icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.email), findsOneWidget);
    });

    testWidgets('has email keyboard type', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.keyboardType, TextInputType.emailAddress);
    });

    testWidgets('calls onChanged callback when text changes', (WidgetTester tester) async {
      String? changedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onChanged: (value) {
                changedValue = value;
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'test@example.com');
      await tester.pump();

      expect(changedValue, 'test@example.com');
    });

    testWidgets('shows validation spinner when validating', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                await Future.delayed(const Duration(milliseconds: 100));
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'test@example.com');

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 800));

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for validation to complete
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('shows success icon when email is available', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: true,
                  message: 'Email available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'test@example.com');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('shows error icon when email is unavailable', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: false,
                  message: 'Email already in use',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'taken@example.com');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('shows success message for available email', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: true,
                  message: 'Email available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'new@example.com');

      // Wait for debounce + validation
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Email available'), findsOneWidget);
    });

    testWidgets('shows error message when validation callback provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: false,
                  message: 'Email address already in use',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'taken@example.com');

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Email address already in use'), findsOneWidget);
    });

    testWidgets('displays external error text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
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
            body: SmartEmailInput(
              controller: controller,
              enabled: false,
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });

    testWidgets('validates only after debounce delay', (WidgetTester tester) async {
      int validationCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              validationDebounce: const Duration(milliseconds: 800),
              onValidate: (email) async {
                validationCallCount++;
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);

      // Type rapidly
      await tester.enterText(textField, 't');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(textField, 'te');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(textField, 'test@example.com');
      await tester.pump(const Duration(milliseconds: 100));

      // Validation should not have been called yet
      expect(validationCallCount, 0);

      // Wait for debounce
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      // Should be called once
      expect(validationCallCount, 1);
    });

    testWidgets('caches validation results', (WidgetTester tester) async {
      int validationCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                validationCallCount++;
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);

      // Enter same email twice
      await tester.enterText(textField, 'test@example.com');
      await tester.pump(const Duration(milliseconds: 900));

      expect(validationCallCount, 1);

      // Delete and re-enter
      await tester.enterText(textField, 'test@example.co');
      await tester.pump(const Duration(milliseconds: 900));

      await tester.enterText(textField, 'test@example.com');
      await tester.pump(const Duration(milliseconds: 900));

      // Should still be 1 due to caching
      expect(validationCallCount, 1);
    });

    testWidgets('only validates when format is valid', (WidgetTester tester) async {
      int validationCallCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                validationCallCount++;
                return const EmailValidationResult(
                  isValid: true,
                  isAvailable: true,
                  message: 'Available',
                );
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);

      // Enter invalid email
      await tester.enterText(textField, 'invalid-email');
      await tester.pump(const Duration(milliseconds: 900));

      // Should NOT have called validation (invalid format)
      expect(validationCallCount, 0);

      // Enter valid email
      await tester.enterText(textField, 'valid@example.com');
      await tester.pump(const Duration(milliseconds: 900));

      // Now should have called validation
      expect(validationCallCount, 1);
    });

    testWidgets('handles network errors gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
              onValidate: (email) async {
                throw Exception('Network error');
              },
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'test@example.com');

      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Network error - please try again'), findsOneWidget);
      expect(find.byIcon(Icons.error), findsOneWidget);
    });

    testWidgets('shows format hint when focused and empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SmartEmailInput(
              controller: controller,
            ),
          ),
        ),
      );

      // Tap to focus
      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(find.text('Example: user@example.com'), findsOneWidget);
    });
  });

  group('EmailValidator Tests', () {
    test('validates correct email formats', () {
      expect(EmailValidator.isValidFormat('user@example.com'), isTrue);
      expect(EmailValidator.isValidFormat('john.doe@company.co.uk'), isTrue);
      expect(EmailValidator.isValidFormat('test+tag@email.io'), isTrue);
    });

    test('rejects invalid email formats', () {
      expect(EmailValidator.isValidFormat('invalid'), isFalse);
      expect(EmailValidator.isValidFormat('no-at-sign.com'), isFalse);
      expect(EmailValidator.isValidFormat('@example.com'), isFalse);
      expect(EmailValidator.isValidFormat('user@'), isFalse);
      expect(EmailValidator.isValidFormat(''), isFalse);
    });

    test('cleans emails correctly', () {
      expect(EmailValidator.clean('  User@Example.COM  '), 'user@example.com');
      expect(EmailValidator.clean('TEST@TEST.COM'), 'test@test.com');
      expect(EmailValidator.clean('user@domain.com'), 'user@domain.com');
    });

    test('gets error messages for invalid emails', () {
      expect(EmailValidator.getErrorMessage(''), 'Email is required');
      expect(EmailValidator.getErrorMessage('invalid'), 'Please enter a valid email address');
      expect(EmailValidator.getErrorMessage('user@example.com'), isNull);
    });
  });

  group('EmailValidationResult Tests', () {
    test('creates result correctly', () {
      const result = EmailValidationResult(
        isValid: true,
        isAvailable: true,
        message: 'Test message',
      );

      expect(result.isValid, isTrue);
      expect(result.isAvailable, isTrue);
      expect(result.message, 'Test message');
    });

    test('has checking constant', () {
      expect(EmailValidationResult.checking.isValid, isTrue);
      expect(EmailValidationResult.checking.isAvailable, isFalse);
      expect(EmailValidationResult.checking.message, 'Checking availability...');
    });

    test('has network error constant', () {
      expect(EmailValidationResult.networkError.isValid, isTrue);
      expect(EmailValidationResult.networkError.isAvailable, isFalse);
      expect(EmailValidationResult.networkError.message, 'Network error - please try again');
    });
  });
}

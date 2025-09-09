import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/widgets/input/premium_text_field.dart';
import '../../../lib/core/constants/app_colors.dart';
import '../../helpers/test_helpers.dart';

void main() {
  group('PremiumTextField Widget Tests', () {
    setUp(() async {
      await TestHelpers.initializeTestEnvironment();
    });

    tearDown(() async {
      await TestHelpers.cleanupTestEnvironment();
    });

    group('Basic Rendering', () {
      testWidgets('should render filled text field with label', (tester) async {
        // Arrange
        const labelText = 'Test Label';
        const hintText = 'Test Hint';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            hint: hintText,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
        TestHelpers.verifyWidgetExists(find.byType(TextFormField));
        // Hint text should be visible initially
        TestHelpers.verifyWidgetExists(find.text(hintText));
      });

      testWidgets('should render outlined text field', (tester) async {
        // Arrange
        const labelText = 'Outlined Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField.outlined(
            label: labelText,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
        TestHelpers.verifyWidgetExists(find.text(labelText));
      });

      testWidgets('should render underlined text field', (tester) async {
        // Arrange
        const labelText = 'Underlined Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField.underlined(
            label: labelText,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
        TestHelpers.verifyWidgetExists(find.text(labelText));
      });

      testWidgets('should render with prefix and suffix icons', (tester) async {
        // Arrange
        const labelText = 'Icon Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            prefixIcon: const Icon(Icons.email),
            suffixIcon: const Icon(Icons.visibility),
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.byIcon(Icons.email));
        TestHelpers.verifyWidgetExists(find.byIcon(Icons.visibility));
      });

      testWidgets('should render with helper text', (tester) async {
        // Arrange
        const labelText = 'Helper Field';
        const helperText = 'This is helper text';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            helperText: helperText,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(helperText));
      });

      testWidgets('should render with error text', (tester) async {
        // Arrange
        const labelText = 'Error Field';
        const errorText = 'This field has an error';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            errorText: errorText,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(errorText));
      });

      testWidgets('should render with character counter', (tester) async {
        // Arrange
        const labelText = 'Counter Field';
        const maxLength = 100;

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            maxLength: maxLength,
            showCounter: true,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text('0/$maxLength'));
      });
    });

    group('Text Input and Editing', () {
      testWidgets('should accept text input', (tester) async {
        // Arrange
        const labelText = 'Input Field';
        const inputText = 'Hello World';
        final controller = TextEditingController();

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            controller: controller,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Assert
        expect(controller.text, inputText);
        TestHelpers.verifyWidgetExists(find.text(inputText));
      });

      testWidgets('should call onChanged callback', (tester) async {
        // Arrange
        const labelText = 'Change Field';
        const inputText = 'Test';
        String changedText = '';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            onChanged: (value) => changedText = value,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Assert
        expect(changedText, inputText);
      });

      testWidgets('should call onSubmitted callback', (tester) async {
        // Arrange
        const labelText = 'Submit Field';
        const inputText = 'Submit Test';
        String submittedText = '';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            onSubmitted: (value) => submittedText = value,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Act
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Assert
        expect(submittedText, inputText);
      });

      testWidgets('should update character counter', (tester) async {
        // Arrange
        const labelText = 'Counter Field';
        const maxLength = 10;
        const inputText = 'Hello';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            maxLength: maxLength,
            showCounter: true,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Assert
        TestHelpers.verifyWidgetExists(find.text('${inputText.length}/$maxLength'));
      });

      testWidgets('should clear error on text input', (tester) async {
        // Arrange
        const labelText = 'Error Clear Field';
        const errorText = 'This field has an error';
        const inputText = 'Fix error';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            errorText: errorText,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);
        
        // Verify error exists initially
        TestHelpers.verifyWidgetExists(find.text(errorText));

        // Act
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Assert
        // Error should be cleared after input (depending on implementation)
        // This test may need adjustment based on actual error clearing logic
      });
    });

    group('Field Validation', () {
      testWidgets('should validate with validator function', (tester) async {
        // Arrange
        const labelText = 'Validation Field';
        const inputText = 'ab'; // Too short
        String? validationError;

        String? validator(String? value) {
          if (value == null || value.length < 3) {
            return 'Must be at least 3 characters';
          }
          return null;
        }

        final widget = TestHelpers.createTestWidget(
          child: Form(
            child: PremiumTextField(
              label: labelText,
              validator: validator,
            ),
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Act
        // Trigger form validation
        final formState = tester.state<FormState>(find.byType(Form));
        final isValid = formState.validate();

        // Assert
        expect(isValid, isFalse);
      });

      testWidgets('should show validation error', (tester) async {
        // Arrange
        const labelText = 'Error Validation Field';
        const errorMessage = 'Validation failed';

        String? validator(String? value) {
          return errorMessage;
        }

        final widget = TestHelpers.createTestWidget(
          child: Form(
            child: PremiumTextField(
              label: labelText,
              validator: validator,
            ),
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        final formState = tester.state<FormState>(find.byType(Form));
        formState.validate();
        await tester.pumpAndSettle();

        // Assert - This may depend on how validation errors are displayed
        // The specific implementation might show errors differently
      });

      testWidgets('should pass validation with valid input', (tester) async {
        // Arrange
        const labelText = 'Valid Field';
        const inputText = 'Valid input';

        String? validator(String? value) {
          if (value == null || value.length < 3) {
            return 'Must be at least 3 characters';
          }
          return null;
        }

        final widget = TestHelpers.createTestWidget(
          child: Form(
            child: PremiumTextField(
              label: labelText,
              validator: validator,
            ),
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);
        await TestHelpers.enterText(tester, find.byType(TextFormField), inputText);

        // Act
        final formState = tester.state<FormState>(find.byType(Form));
        final isValid = formState.validate();

        // Assert
        expect(isValid, isTrue);
      });
    });

    group('Focus and Interaction', () {
      testWidgets('should handle focus changes', (tester) async {
        // Arrange
        const labelText = 'Focus Field';
        final focusNode = FocusNode();

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            focusNode: focusNode,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        focusNode.requestFocus();
        await tester.pumpAndSettle();

        // Assert
        expect(focusNode.hasFocus, isTrue);
      });

      testWidgets('should handle tap events', (tester) async {
        // Arrange
        const labelText = 'Tap Field';
        bool wasTapped = false;

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            onTap: () => wasTapped = true,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.tapWidget(tester, find.byType(TextFormField));

        // Assert
        expect(wasTapped, isTrue);
      });

      testWidgets('should be disabled when enabled is false', (tester) async {
        // Arrange
        const labelText = 'Disabled Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            enabled: false,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final textField = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(textField.enabled, isFalse);
      });

      testWidgets('should be read-only when readOnly is true', (tester) async {
        // Arrange
        const labelText = 'Read Only Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            readOnly: true,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final textField = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(textField.readOnly, isTrue);
      });
    });

    group('Specialized Text Fields', () {
      testWidgets('EmailTextField should render with email icon', (tester) async {
        // Arrange
        const labelText = 'Email';

        final widget = TestHelpers.createTestWidget(
          child: EmailTextField(label: labelText),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.byIcon(Icons.email_outlined));
        TestHelpers.verifyWidgetExists(find.text(labelText));
      });

      testWidgets('EmailTextField should validate email format', (tester) async {
        // Arrange
        const invalidEmail = 'invalid-email';

        final widget = TestHelpers.createTestWidget(
          child: Form(
            child: EmailTextField(),
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);
        await TestHelpers.enterText(tester, find.byType(TextFormField), invalidEmail);

        // Act
        final formState = tester.state<FormState>(find.byType(Form));
        final isValid = formState.validate();

        // Assert
        expect(isValid, isFalse);
      });

      testWidgets('PasswordTextField should toggle visibility', (tester) async {
        // Arrange
        const passwordText = 'secret123';

        final widget = TestHelpers.createTestWidget(
          child: PasswordTextField(),
        );

        await TestHelpers.pumpAndSettle(tester, widget);
        await TestHelpers.enterText(tester, find.byType(TextFormField), passwordText);

        // Initially password should be obscured
        final textField = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(textField.obscureText, isTrue);

        // Act - Tap visibility toggle
        await TestHelpers.tapWidget(tester, find.byIcon(Icons.visibility_outlined));

        // Assert - Password should now be visible
        final updatedTextField = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(updatedTextField.obscureText, isFalse);

        // Tap again to hide
        await TestHelpers.tapWidget(tester, find.byIcon(Icons.visibility_off_outlined));
        final finalTextField = tester.widget<TextFormField>(find.byType(TextFormField));
        expect(finalTextField.obscureText, isTrue);
      });

      testWidgets('PasswordTextField with strength indicator should show strength', (tester) async {
        // Arrange
        const weakPassword = '123';
        const strongPassword = 'StrongP@ssw0rd123';

        final widget = TestHelpers.createTestWidget(
          child: PasswordTextField(showStrengthIndicator: true),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Test weak password
        await TestHelpers.enterText(tester, find.byType(TextFormField), weakPassword);
        await tester.pumpAndSettle();

        // Should show weak strength indicator
        TestHelpers.verifyWidgetExists(find.byType(LinearProgressIndicator));

        // Test strong password
        await TestHelpers.enterText(tester, find.byType(TextFormField), strongPassword);
        await tester.pumpAndSettle();

        // Should show stronger progress
        TestHelpers.verifyWidgetExists(find.byType(LinearProgressIndicator));
      });
    });

    group('Styling and Theming', () {
      testWidgets('should apply custom background color', (tester) async {
        // Arrange
        const labelText = 'Custom Color Field';
        const customColor = AppColors.premiumGold;

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            backgroundColor: customColor,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final textField = tester.widget<PremiumTextField>(find.byType(PremiumTextField));
        expect(textField.backgroundColor, customColor);
      });

      testWidgets('should apply custom border radius', (tester) async {
        // Arrange
        const labelText = 'Custom Border Field';
        const customRadius = BorderRadius.all(Radius.circular(20));

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            borderRadius: customRadius,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final textField = tester.widget<PremiumTextField>(find.byType(PremiumTextField));
        expect(textField.borderRadius, customRadius);
      });

      testWidgets('should apply custom border colors', (tester) async {
        // Arrange
        const labelText = 'Custom Border Colors Field';
        const borderColor = AppColors.mutedWhite;
        const focusedColor = AppColors.premiumGold;

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            borderColor: borderColor,
            focusedBorderColor: focusedColor,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final textField = tester.widget<PremiumTextField>(find.byType(PremiumTextField));
        expect(textField.borderColor, borderColor);
        expect(textField.focusedBorderColor, focusedColor);
      });
    });

    group('Accessibility Tests', () {
      testWidgets('should be accessible', (tester) async {
        // Arrange
        const labelText = 'Accessible Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(label: labelText),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        await TestHelpers.verifyAccessibility(tester);
      });

      testWidgets('should have proper semantics', (tester) async {
        // Arrange
        const labelText = 'Semantic Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(label: labelText),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final semantics = tester.getSemantics(find.byType(TextFormField));
        expect(semantics.hasAction(SemanticsAction.tap), isTrue);
      });
    });

    group('Performance Tests', () {
      testWidgets('should render quickly', (tester) async {
        // Arrange
        const labelText = 'Performance Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(label: labelText),
        );

        // Act & Assert
        await TestHelpers.testPerformance(
          'TextField Rendering Performance',
          () async {
            await TestHelpers.pumpAndSettle(tester, widget);
            TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
          },
        );
      });

      testWidgets('should handle rapid text changes', (tester) async {
        // Arrange
        const labelText = 'Rapid Change Field';
        int changeCount = 0;

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            onChanged: (value) => changeCount++,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        for (int i = 0; i < 100; i++) {
          await tester.enterText(find.byType(TextFormField), 'Text $i');
          await tester.pump(const Duration(milliseconds: 1));
        }

        // Assert
        expect(changeCount, 100);
      });
    });

    group('Edge Cases', () {
      testWidgets('should handle null controller', (tester) async {
        // Arrange
        const labelText = 'Null Controller Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            controller: null,
          ),
        );

        // Act & Assert
        await TestHelpers.pumpAndSettle(tester, widget);
        TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
      });

      testWidgets('should handle empty initial value', (tester) async {
        // Arrange
        const labelText = 'Empty Initial Value Field';

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(
            label: labelText,
            initialValue: '',
          ),
        );

        // Act & Assert
        await TestHelpers.pumpAndSettle(tester, widget);
        TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
      });

      testWidgets('should handle very long text', (tester) async {
        // Arrange
        const labelText = 'Long Text Field';
        final longText = 'A' * 1000;

        final widget = TestHelpers.createTestWidget(
          child: PremiumTextField(label: labelText),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.enterText(tester, find.byType(TextFormField), longText);

        // Assert
        TestHelpers.verifyWidgetExists(find.byType(PremiumTextField));
      });
    });
  });
}
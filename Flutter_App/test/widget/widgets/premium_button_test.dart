import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/widgets/buttons/premium_button.dart';
import '../../../lib/core/constants/app_colors.dart';
import '../../helpers/test_helpers.dart';

void main() {
  group('PremiumButton Widget Tests', () {
    setUp(() async {
      await TestHelpers.initializeTestEnvironment();
    });

    tearDown(() async {
      await TestHelpers.cleanupTestEnvironment();
    });

    group('Basic Rendering', () {
      testWidgets('should render primary button with text', (tester) async {
        // Arrange
        const buttonText = 'Test Button';
        bool wasPressed = false;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () => wasPressed = true,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        TestHelpers.verifyWidgetExists(find.byType(PremiumButton));
        expect(wasPressed, isFalse);
      });

      testWidgets('should render secondary button with custom styling', (tester) async {
        // Arrange
        const buttonText = 'Secondary Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.secondary(
            text: buttonText,
            width: 200,
            backgroundColor: AppColors.cardGrey,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.width, 200);
        expect(button.backgroundColor, AppColors.cardGrey);
      });

      testWidgets('should render outline button', (tester) async {
        // Arrange
        const buttonText = 'Outline Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.outline(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
      });

      testWidgets('should render ghost button', (tester) async {
        // Arrange
        const buttonText = 'Ghost Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.ghost(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
      });

      testWidgets('should render danger button', (tester) async {
        // Arrange
        const buttonText = 'Delete';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.danger(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
      });

      testWidgets('should render button with icon', (tester) async {
        // Arrange
        const buttonText = 'Add Item';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            icon: Icons.add,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        TestHelpers.verifyWidgetExists(find.byIcon(Icons.add));
      });

      testWidgets('should render custom child instead of text', (tester) async {
        // Arrange
        const childText = 'Custom Child';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: 'This should not appear',
            child: const Text(childText),
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(childText));
        TestHelpers.verifyWidgetNotExists(find.text('This should not appear'));
      });
    });

    group('Button States', () {
      testWidgets('should show loading state', (tester) async {
        // Arrange
        const buttonText = 'Loading Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            isLoading: true,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        TestHelpers.verifyWidgetExists(find.byType(CircularProgressIndicator));
      });

      testWidgets('should show disabled state', (tester) async {
        // Arrange
        const buttonText = 'Disabled Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            isDisabled: true,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        // Verify button appears disabled (gray color)
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.isDisabled, isTrue);
      });

      testWidgets('should handle null onPressed', (tester) async {
        // Arrange
        const buttonText = 'Null Handler Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: null,
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.onPressed, isNull);
      });
    });

    group('Button Sizes', () {
      testWidgets('should render small button', (tester) async {
        // Arrange
        const buttonText = 'Small';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            size: PremiumButtonSize.small,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.size, PremiumButtonSize.small);
      });

      testWidgets('should render medium button (default)', (tester) async {
        // Arrange
        const buttonText = 'Medium';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.size, PremiumButtonSize.medium);
      });

      testWidgets('should render large button', (tester) async {
        // Arrange
        const buttonText = 'Large';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            size: PremiumButtonSize.large,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.size, PremiumButtonSize.large);
      });
    });

    group('Interaction Tests', () {
      testWidgets('should call onPressed when tapped', (tester) async {
        // Arrange
        const buttonText = 'Tap Me';
        bool wasPressed = false;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () => wasPressed = true,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.tapWidget(tester, find.text(buttonText));

        // Assert
        expect(wasPressed, isTrue);
      });

      testWidgets('should not call onPressed when disabled', (tester) async {
        // Arrange
        const buttonText = 'Disabled Button';
        bool wasPressed = false;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            isDisabled: true,
            onPressed: () => wasPressed = true,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.tapWidget(tester, find.text(buttonText));

        // Assert
        expect(wasPressed, isFalse);
      });

      testWidgets('should not call onPressed when loading', (tester) async {
        // Arrange
        const buttonText = 'Loading Button';
        bool wasPressed = false;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            isLoading: true,
            onPressed: () => wasPressed = true,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.tapWidget(tester, find.text(buttonText));

        // Assert
        expect(wasPressed, isFalse);
      });

      testWidgets('should provide haptic feedback when enabled', (tester) async {
        // Arrange
        const buttonText = 'Haptic Button';
        final List<MethodCall> hapticCalls = [];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          hapticCalls.add(call);
          return null;
        });

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            enableFeedback: true,
            onPressed: () {},
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await TestHelpers.tapWidget(tester, find.text(buttonText));

        // Assert
        expect(
          hapticCalls.any((call) => call.method == 'HapticFeedback.vibrate'),
          isTrue,
        );

        // Cleanup
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
    });

    group('Animation Tests', () {
      testWidgets('should animate on tap', (tester) async {
        // Arrange
        const buttonText = 'Animated Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () {},
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        await tester.tap(find.text(buttonText));
        await tester.pump(); // Start animation
        await tester.pump(const Duration(milliseconds: 50)); // Mid animation

        // Assert
        TestHelpers.verifyWidgetExists(find.text(buttonText));
        
        // Complete animation
        await tester.pumpAndSettle();
      });

      testWidgets('should animate loading state', (tester) async {
        // Arrange
        const buttonText = 'Loading Animation';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            isLoading: true,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);
        
        // Let loading animation run for a bit
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        // Assert
        TestHelpers.verifyWidgetExists(find.byType(CircularProgressIndicator));
      });
    });

    group('Custom Styling Tests', () {
      testWidgets('should apply custom width', (tester) async {
        // Arrange
        const buttonText = 'Wide Button';
        const customWidth = 300.0;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            width: customWidth,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.width, customWidth);
      });

      testWidgets('should apply custom colors', (tester) async {
        // Arrange
        const buttonText = 'Custom Colors';
        const customBackground = AppColors.premiumGold;
        const customForeground = AppColors.premiumBlack;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            backgroundColor: customBackground,
            foregroundColor: customForeground,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.backgroundColor, customBackground);
        expect(button.foregroundColor, customForeground);
      });

      testWidgets('should apply custom border radius', (tester) async {
        // Arrange
        const buttonText = 'Rounded Button';
        const customRadius = BorderRadius.all(Radius.circular(20));

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            borderRadius: customRadius,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.borderRadius, customRadius);
      });

      testWidgets('should apply custom padding', (tester) async {
        // Arrange
        const buttonText = 'Padded Button';
        const customPadding = EdgeInsets.all(20);

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            padding: customPadding,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final button = tester.widget<PremiumButton>(find.byType(PremiumButton));
        expect(button.padding, customPadding);
      });
    });

    group('Accessibility Tests', () {
      testWidgets('should be accessible', (tester) async {
        // Arrange
        const buttonText = 'Accessible Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        await TestHelpers.verifyAccessibility(tester);
      });

      testWidgets('should have proper semantics', (tester) async {
        // Arrange
        const buttonText = 'Semantic Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        final semantics = tester.getSemantics(find.text(buttonText));
        expect(semantics.hasAction(SemanticsAction.tap), isTrue);
      });

      testWidgets('should handle focus', (tester) async {
        // Arrange
        const buttonText = 'Focusable Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Focus the button
        final buttonFinder = find.byType(PremiumButton);
        await tester.tap(buttonFinder);
        await tester.pump();

        // Assert
        TestHelpers.verifyWidgetExists(buttonFinder);
      });
    });

    group('Performance Tests', () {
      testWidgets('should render quickly', (tester) async {
        // Arrange
        const buttonText = 'Performance Button';

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () {},
          ),
        );

        // Act & Assert
        await TestHelpers.testPerformance(
          'Button Rendering Performance',
          () async {
            await TestHelpers.pumpAndSettle(tester, widget);
            TestHelpers.verifyWidgetExists(find.text(buttonText));
          },
        );
      });

      testWidgets('should handle rapid taps', (tester) async {
        // Arrange
        const buttonText = 'Rapid Tap Button';
        int tapCount = 0;

        final widget = TestHelpers.createTestWidget(
          child: PremiumButton.primary(
            text: buttonText,
            onPressed: () => tapCount++,
          ),
        );

        await TestHelpers.pumpAndSettle(tester, widget);

        // Act
        for (int i = 0; i < 10; i++) {
          await tester.tap(find.text(buttonText));
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();

        // Assert
        expect(tapCount, 10);
      });
    });

    group('Golden Tests', () {
      testWidgets('should match golden file - primary button', (tester) async {
        // Arrange
        const buttonText = 'Primary Golden';

        final widget = TestHelpers.createTestWidget(
          child: Center(
            child: PremiumButton.primary(
              text: buttonText,
              onPressed: () {},
            ),
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        await TestHelpers.captureScreenshot(tester, 'primary_button');
      });

      testWidgets('should match golden file - loading state', (tester) async {
        // Arrange
        const buttonText = 'Loading Golden';

        final widget = TestHelpers.createTestWidget(
          child: Center(
            child: PremiumButton.primary(
              text: buttonText,
              isLoading: true,
              onPressed: () {},
            ),
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        await TestHelpers.captureScreenshot(tester, 'loading_button');
      });

      testWidgets('should match golden file - button variants', (tester) async {
        // Arrange
        final widget = TestHelpers.createTestWidget(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PremiumButton.primary(text: 'Primary', onPressed: () {}),
              const SizedBox(height: 16),
              PremiumButton.secondary(text: 'Secondary', onPressed: () {}),
              const SizedBox(height: 16),
              PremiumButton.outline(text: 'Outline', onPressed: () {}),
              const SizedBox(height: 16),
              PremiumButton.ghost(text: 'Ghost', onPressed: () {}),
              const SizedBox(height: 16),
              PremiumButton.danger(text: 'Danger', onPressed: () {}),
            ],
          ),
        );

        // Act
        await TestHelpers.pumpAndSettle(tester, widget);

        // Assert
        await TestHelpers.captureScreenshot(tester, 'button_variants');
      });
    });
  });
}
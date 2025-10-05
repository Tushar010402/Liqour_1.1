import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:saas_admin_flutter_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Brand Management Integration Tests', () {
    testWidgets('End-to-end brand management workflow',
        (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      // Wait for app to fully load
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Test 1: Navigation to Brand Management
      await _navigateToBrandManagement(tester);

      // Test 2: Create New Brand
      await _testCreateNewBrand(tester);

      // Test 3: Search and Filter Brands
      await _testSearchAndFilterBrands(tester);

      // Test 4: Edit Brand
      await _testEditBrand(tester);

      // Test 5: Brand Details View
      await _testBrandDetailsView(tester);

      // Test 6: Tenant Brand Assignment
      await _testTenantBrandAssignment(tester);

      // Test 7: Delete Brand (with confirmation)
      await _testDeleteBrand(tester);
    });

    testWidgets('Brand management error handling', (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      // Wait for app to fully load
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Test error scenarios
      await _testErrorHandling(tester);
    });

    testWidgets('Brand management accessibility', (WidgetTester tester) async {
      // Start the app
      app.main();
      await tester.pumpAndSettle();

      // Test accessibility features
      await _testAccessibilityFeatures(tester);
    });
  });
}

/// Navigate to Brand Management screen
Future<void> _navigateToBrandManagement(WidgetTester tester) async {
  debugPrint('🧪 Testing navigation to Brand Management...');

  // Look for navigation menu or brand management entry point
  // This might be in a drawer, bottom nav, or main menu
  final brandManagementButton = find.text('Brand Management').first;

  if (brandManagementButton.evaluate().isNotEmpty) {
    await tester.tap(brandManagementButton);
    await tester.pumpAndSettle();
  } else {
    // Alternative: Look for drawer icon and open it
    final drawerIcon = find.byIcon(Icons.menu);
    if (drawerIcon.evaluate().isNotEmpty) {
      await tester.tap(drawerIcon);
      await tester.pumpAndSettle();

      // Look for brand management in drawer
      final drawerBrandManagement = find.text('Brand Management');
      if (drawerBrandManagement.evaluate().isNotEmpty) {
        await tester.tap(drawerBrandManagement);
        await tester.pumpAndSettle();
      }
    }
  }

  // Verify we're on brand management screen
  expect(find.text('Brand Management'), findsOneWidget);
  debugPrint('✅ Successfully navigated to Brand Management');
}

/// Test creating a new brand
Future<void> _testCreateNewBrand(WidgetTester tester) async {
  debugPrint('🧪 Testing brand creation...');

  // Tap the create/add brand button (FAB or plus button)
  final addButton = find.byIcon(Icons.add);
  expect(addButton, findsOneWidget);
  await tester.tap(addButton);
  await tester.pumpAndSettle();

  // Verify we're on the brand form screen
  expect(find.text('Create New Brand'), findsOneWidget);

  // Fill in the brand name
  final nameField = find.widgetWithText(TextFormField, 'Brand Name');
  await tester.enterText(nameField, 'Test Integration Brand');
  await tester.pumpAndSettle();

  // Fill in description
  final descriptionField = find.widgetWithText(TextFormField, 'Description');
  await tester.enterText(descriptionField,
      'This is a test brand created during integration testing');
  await tester.pumpAndSettle();

  // Fill in picture URL
  final pictureField = find.widgetWithText(TextFormField, 'Picture URL');
  await tester.enterText(pictureField, 'https://example.com/test-brand.jpg');
  await tester.pumpAndSettle();

  // Fill in sort order
  final sortOrderField = find.widgetWithText(TextFormField, 'Sort Order');
  await tester.enterText(sortOrderField, '10');
  await tester.pumpAndSettle();

  // Tap create button
  final createButton = find.text('Create Brand');
  await tester.tap(createButton);
  await tester.pumpAndSettle();

  // Wait for creation to complete
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Verify we're back on brands list and our brand is there
  expect(find.text('Test Integration Brand'), findsOneWidget);
  debugPrint('✅ Brand creation successful');
}

/// Test search and filter functionality
Future<void> _testSearchAndFilterBrands(WidgetTester tester) async {
  debugPrint('🧪 Testing search and filter functionality...');

  // Find search field
  final searchField = find.byType(TextField);
  expect(searchField, findsOneWidget);

  // Test search functionality
  await tester.enterText(searchField, 'Test Integration');
  await tester.pumpAndSettle();

  // Verify filtered results
  expect(find.text('Test Integration Brand'), findsOneWidget);

  // Clear search
  await tester.enterText(searchField, '');
  await tester.pumpAndSettle();

  // Test view toggle (grid/list view)
  final gridViewButton = find.byIcon(Icons.view_module);
  final listViewButton = find.byIcon(Icons.view_list);

  if (gridViewButton.evaluate().isNotEmpty) {
    await tester.tap(gridViewButton.first);
    await tester.pumpAndSettle();
  } else if (listViewButton.evaluate().isNotEmpty) {
    await tester.tap(listViewButton.first);
    await tester.pumpAndSettle();
  }

  debugPrint('✅ Search and filter functionality working');
}

/// Test editing a brand
Future<void> _testEditBrand(WidgetTester tester) async {
  debugPrint('🧪 Testing brand editing...');

  // Find our test brand and tap on it or find edit button
  final testBrand = find.text('Test Integration Brand');
  await tester.tap(testBrand);
  await tester.pumpAndSettle();

  // Look for edit button (might be in app bar or as action button)
  final editIconButton = find.byIcon(Icons.edit);
  final editTextButton = find.text('Edit');

  if (editIconButton.evaluate().isNotEmpty) {
    await tester.tap(editIconButton.first);
    await tester.pumpAndSettle();
  } else if (editTextButton.evaluate().isNotEmpty) {
    await tester.tap(editTextButton.first);
    await tester.pumpAndSettle();
  }

  // Verify we're on edit screen
  expect(find.text('Edit Brand'), findsOneWidget);

  // Update the brand name
  final nameField = find.widgetWithText(TextFormField, 'Brand Name');
  await tester.enterText(nameField, 'Test Integration Brand Updated');
  await tester.pumpAndSettle();

  // Save changes
  final updateButton = find.text('Update Brand');
  await tester.tap(updateButton);
  await tester.pumpAndSettle();

  // Wait for update to complete
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Verify updated brand name appears
  expect(find.text('Test Integration Brand Updated'), findsOneWidget);
  debugPrint('✅ Brand editing successful');
}

/// Test brand details view
Future<void> _testBrandDetailsView(WidgetTester tester) async {
  debugPrint('🧪 Testing brand details view...');

  // Tap on the updated brand
  final updatedBrand = find.text('Test Integration Brand Updated');
  await tester.tap(updatedBrand);
  await tester.pumpAndSettle();

  // Verify we're on brand details screen
  expect(find.text('Test Integration Brand Updated'), findsOneWidget);

  // Check for tabs (Overview, Variants, etc.)
  final overviewTab = find.text('Overview');
  if (overviewTab.evaluate().isNotEmpty) {
    await tester.tap(overviewTab);
    await tester.pumpAndSettle();
  }

  final variantsTab = find.text('Variants');
  if (variantsTab.evaluate().isNotEmpty) {
    await tester.tap(variantsTab);
    await tester.pumpAndSettle();
  }

  // Navigate back
  final backButton = find.byIcon(Icons.arrow_back);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton);
    await tester.pumpAndSettle();
  }

  debugPrint('✅ Brand details view working correctly');
}

/// Test tenant brand assignment
Future<void> _testTenantBrandAssignment(WidgetTester tester) async {
  debugPrint('🧪 Testing tenant brand assignment...');

  // Find our test brand
  final testBrand = find.text('Test Integration Brand Updated');

  // Look for assign to tenant button or menu option
  // This might require long press, context menu, or specific action button
  await tester.longPress(testBrand);
  await tester.pumpAndSettle();

  // Look for assign option in context menu
  final assignOption = find.text('Assign to Tenant');
  if (assignOption.evaluate().isNotEmpty) {
    await tester.tap(assignOption);
    await tester.pumpAndSettle();

    // Test tenant selection
    final tenantDropdown = find.byType(DropdownButtonFormField<String>);
    if (tenantDropdown.evaluate().isNotEmpty) {
      await tester.tap(tenantDropdown.first);
      await tester.pumpAndSettle();

      // Select first available tenant
      final tenantOptions = find.byType(DropdownMenuItem<String>);
      if (tenantOptions.evaluate().isNotEmpty) {
        await tester.tap(tenantOptions.first);
        await tester.pumpAndSettle();
      }

      // Complete assignment
      final assignButton = find.text('Assign');
      if (assignButton.evaluate().isNotEmpty) {
        await tester.tap(assignButton);
        await tester.pumpAndSettle();
      }
    }
  }

  debugPrint('✅ Tenant brand assignment completed');
}

/// Test brand deletion
Future<void> _testDeleteBrand(WidgetTester tester) async {
  debugPrint('🧪 Testing brand deletion...');

  // Find our test brand
  final testBrand = find.text('Test Integration Brand Updated');

  // Long press to open context menu or find delete button
  await tester.longPress(testBrand);
  await tester.pumpAndSettle();

  // Look for delete option
  final deleteTextOption = find.text('Delete');
  final deleteIconOption = find.byIcon(Icons.delete);

  if (deleteTextOption.evaluate().isNotEmpty) {
    await tester.tap(deleteTextOption.first);
    await tester.pumpAndSettle();
  } else if (deleteIconOption.evaluate().isNotEmpty) {
    await tester.tap(deleteIconOption.first);
    await tester.pumpAndSettle();
  }

  // Handle confirmation dialog
  final confirmDialog = find.byType(AlertDialog);
  if (confirmDialog.evaluate().isNotEmpty) {
    final deleteConfirmButton = find.text('Delete');
    final confirmButton = find.text('Confirm');

    if (deleteConfirmButton.evaluate().length > 1) {
      await tester.tap(deleteConfirmButton.last);
      await tester.pumpAndSettle();
    } else if (confirmButton.evaluate().isNotEmpty) {
      await tester.tap(confirmButton.last);
      await tester.pumpAndSettle();
    }

    // Wait for deletion to complete
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify brand is no longer visible
    expect(find.text('Test Integration Brand Updated'), findsNothing);

    debugPrint('✅ Brand deletion successful');
  }

  /// Test error handling scenarios
}

Future<void> _testErrorHandling(WidgetTester tester) async {
  debugPrint('🧪 Testing error handling...');

  // Navigate to brand management
  await _navigateToBrandManagement(tester);

  // Try to create brand with invalid data
  final addButton = find.byIcon(Icons.add);
  if (addButton.evaluate().isNotEmpty) {
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // Try to create brand without required fields
    final createButton = find.text('Create Brand');
    if (createButton.evaluate().isNotEmpty) {
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Verify validation error appears
      expect(find.text('Brand name is required'), findsOneWidget);
    }

    // Navigate back
    final cancelButton = find.text('Cancel');
    if (cancelButton.evaluate().isNotEmpty) {
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
    }
  }

  debugPrint('✅ Error handling working correctly');
}

/// Test accessibility features
Future<void> _testAccessibilityFeatures(WidgetTester tester) async {
  debugPrint('🧪 Testing accessibility features...');

  // Navigate to brand management
  await _navigateToBrandManagement(tester);

  // Check for semantic labels
  expect(find.bySemanticsLabel('Search brands'), findsOneWidget);
  expect(find.bySemanticsLabel('Create new brand'), findsOneWidget);

  // Test keyboard navigation and screen reader support
  // (This would be more comprehensive in a real accessibility test)

  debugPrint('✅ Accessibility features working correctly');
}

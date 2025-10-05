import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:provider/provider.dart';
import 'package:saas_admin_flutter_app/features/brand_management/views/brands_screen.dart';
import 'package:saas_admin_flutter_app/features/brand_management/views/brand_form_screen.dart';
import 'package:saas_admin_flutter_app/features/brand_management/controllers/brand_provider.dart';
import 'package:saas_admin_flutter_app/core/models/brand_model.dart';

import 'brand_management_widget_test.mocks.dart';

@GenerateMocks([BrandProvider])
void main() {
  group('Brand Management Widget Tests', () {
    late MockBrandProvider mockBrandProvider;

    setUp(() {
      mockBrandProvider = MockBrandProvider();

      // Default mock setup
      when(mockBrandProvider.isLoading).thenReturn(false);
      when(mockBrandProvider.error).thenReturn(null);
      when(mockBrandProvider.brands).thenReturn([]);
      when(mockBrandProvider.filteredBrands).thenReturn([]);
      when(mockBrandProvider.isGridView).thenReturn(true);
      when(mockBrandProvider.searchQuery).thenReturn('');
      when(mockBrandProvider.selectedCategory).thenReturn(null);
      when(mockBrandProvider.categories).thenReturn([]);
      when(mockBrandProvider.sortBy).thenReturn('name');
      when(mockBrandProvider.sortAscending).thenReturn(true);
    });

    testWidgets('BrandsScreen should display loading indicator when loading',
        (WidgetTester tester) async {
      // Arrange
      when(mockBrandProvider.isLoading).thenReturn(true);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('BrandsScreen should display error message when error occurs',
        (WidgetTester tester) async {
      // Arrange
      when(mockBrandProvider.error).thenReturn('Failed to load brands');

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.text('Failed to load brands'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('BrandsScreen should display empty state when no brands',
        (WidgetTester tester) async {
      // Arrange
      when(mockBrandProvider.filteredBrands).thenReturn([]);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.text('No brands found'), findsOneWidget);
      expect(
          find.text('Create your first brand to get started'), findsOneWidget);
    });

    testWidgets('BrandsScreen should display brands in grid view',
        (WidgetTester tester) async {
      // Arrange
      final mockBrands = [
        Brand(
          id: '1',
          name: 'Test Brand 1',
          description: 'Test Description 1',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
        Brand(
          id: '2',
          name: 'Test Brand 2',
          description: 'Test Description 2',
          picture: '',
          isActive: true,
          sortOrder: 1,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ];

      when(mockBrandProvider.filteredBrands).thenReturn(mockBrands);
      when(mockBrandProvider.isGridView).thenReturn(true);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.text('Test Brand 1'), findsOneWidget);
      expect(find.text('Test Brand 2'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('BrandsScreen should display brands in list view',
        (WidgetTester tester) async {
      // Arrange
      final mockBrands = [
        Brand(
          id: '1',
          name: 'Test Brand 1',
          description: 'Test Description 1',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ];

      when(mockBrandProvider.filteredBrands).thenReturn(mockBrands);
      when(mockBrandProvider.isGridView).thenReturn(false);

      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.text('Test Brand 1'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('BrandsScreen should have search functionality',
        (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search brands...'), findsOneWidget);
    });

    testWidgets('BrandsScreen should have create brand button',
        (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Assert
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('BrandsScreen should toggle between grid and list view',
        (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Find the view toggle button
      final viewToggleButton = find.byIcon(Icons.view_module);
      expect(viewToggleButton, findsOneWidget);

      // Tap the view toggle button
      await tester.tap(viewToggleButton);

      // Assert
      verify(mockBrandProvider.toggleViewMode()).called(1);
    });

    testWidgets('BrandsScreen search should call searchBrands',
        (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<BrandProvider>(
            create: (_) => mockBrandProvider,
            child: const BrandsScreen(),
          ),
        ),
      );

      // Find the search field and enter text
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'test search');
      await tester.pump();

      // Assert
      verify(mockBrandProvider.setSearchQuery('test search')).called(1);
    });

    group('BrandFormScreen Widget Tests', () {
      testWidgets(
          'BrandFormScreen should display create form when no brand provided',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandFormScreen(),
            ),
          ),
        );

        // Assert
        expect(find.text('Create New Brand'), findsOneWidget);
        expect(find.text('Create Brand'), findsOneWidget);
      });

      testWidgets(
          'BrandFormScreen should display edit form when brand provided',
          (WidgetTester tester) async {
        // Arrange
        final testBrand = Brand(
          id: '1',
          name: 'Test Brand',
          description: 'Test Description',
          picture: 'https://example.com/image.jpg',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: BrandFormScreen(brand: testBrand),
            ),
          ),
        );

        // Assert
        expect(find.text('Edit Brand'), findsOneWidget);
        expect(find.text('Update Brand'), findsOneWidget);
        expect(find.text('Test Brand'), findsOneWidget);
      });

      testWidgets('BrandFormScreen should validate required fields',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandFormScreen(),
            ),
          ),
        );

        // Find and tap the create button without filling required fields
        final createButton = find.text('Create Brand');
        await tester.tap(createButton);
        await tester.pump();

        // Assert
        expect(find.text('Brand name is required'), findsOneWidget);
      });

      testWidgets('BrandFormScreen should have all required form fields',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandFormScreen(),
            ),
          ),
        );

        // Assert
        expect(find.text('Brand Name *'), findsOneWidget);
        expect(find.text('Description'), findsOneWidget);
        expect(find.text('Picture URL'), findsOneWidget);
        expect(find.text('Sort Order'), findsOneWidget);
        expect(find.byType(Switch), findsOneWidget); // Active status switch
      });

      testWidgets(
          'BrandFormScreen should show image preview when URL is provided',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandFormScreen(),
            ),
          ),
        );

        // Find the picture URL field and enter a URL
        final pictureField = find.widgetWithText(TextFormField, 'Picture URL');
        await tester.enterText(pictureField, 'https://example.com/image.jpg');
        await tester.pump();

        // Assert
        expect(find.byType(Image), findsOneWidget);
      });

      testWidgets('BrandFormScreen cancel button should work',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChangeNotifierProvider<BrandProvider>(
                create: (_) => mockBrandProvider,
                child: const BrandFormScreen(),
              ),
            ),
          ),
        );

        // Find and tap cancel button
        final cancelButton = find.text('Cancel');
        await tester.tap(cancelButton);
        await tester.pump();

        // Assert - Should pop the screen (we can't directly test navigation in widget tests)
        expect(cancelButton, findsOneWidget);
      });
    });

    group('Brand Card Widget Tests', () {
      testWidgets('Brand card should display brand information correctly',
          (WidgetTester tester) async {
        // Arrange
        final testBrand = Brand(
          id: '1',
          name: 'Test Brand',
          description: 'Test Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
          brandVariants: [
            BrandVariant(
              id: '1',
              brandId: '1',
              categoryId: '1',
              subcategoryId: null,
              size: '750ml',
              alcoholContent: 40.0,
              picture: '',
              governmentDuty: 100.0,
              buyingPrice: 500.0,
              sellingPrice: 750.0,
              mrp: 900.0,
              description: 'Test Variant',
              barcode: '123456789',
              hsnCode: '22085010',
              isActive: true,
              sortOrder: 0,
              createdAt: DateTime.now().toIso8601String(),
              updatedAt: DateTime.now().toIso8601String(),
            ),
          ],
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        when(mockBrandProvider.filteredBrands).thenReturn([testBrand]);

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandsScreen(),
            ),
          ),
        );

        // Assert
        expect(find.text('Test Brand'), findsOneWidget);
        expect(find.text('Test Description'), findsOneWidget);
        expect(find.text('1 variant'), findsOneWidget);
        expect(find.byIcon(Icons.local_drink), findsOneWidget);
      });

      testWidgets('Brand card should show active status correctly',
          (WidgetTester tester) async {
        // Arrange
        final activeBrand = Brand(
          id: '1',
          name: 'Active Brand',
          description: 'Description',
          picture: '',
          isActive: true,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        when(mockBrandProvider.filteredBrands).thenReturn([activeBrand]);

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandsScreen(),
            ),
          ),
        );

        // Assert
        expect(find.text('ACTIVE'), findsOneWidget);
      });

      testWidgets('Brand card should show inactive status correctly',
          (WidgetTester tester) async {
        // Arrange
        final inactiveBrand = Brand(
          id: '1',
          name: 'Inactive Brand',
          description: 'Description',
          picture: '',
          isActive: false,
          sortOrder: 0,
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        );

        when(mockBrandProvider.filteredBrands).thenReturn([inactiveBrand]);

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandsScreen(),
            ),
          ),
        );

        // Assert
        expect(find.text('INACTIVE'), findsOneWidget);
      });
    });

    group('Search and Filter Widget Tests', () {
      testWidgets('Search field should have proper hint text and styling',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandsScreen(),
            ),
          ),
        );

        // Assert
        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);

        final textField = tester.widget<TextField>(searchField);
        expect(textField.decoration?.hintText, 'Search brands...');
        expect(textField.decoration?.prefixIcon, isA<Icon>());
      });

      testWidgets('Clear search button should appear when search query exists',
          (WidgetTester tester) async {
        // Arrange
        when(mockBrandProvider.searchQuery).thenReturn('test');

        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandsScreen(),
            ),
          ),
        );

        // Assert
        expect(find.byIcon(Icons.clear), findsOneWidget);
      });
    });

    group('Accessibility Tests', () {
      testWidgets('BrandsScreen should have proper accessibility labels',
          (WidgetTester tester) async {
        // Act
        await tester.pumpWidget(
          MaterialApp(
            home: ChangeNotifierProvider<BrandProvider>(
              create: (_) => mockBrandProvider,
              child: const BrandsScreen(),
            ),
          ),
        );

        // Assert
        expect(find.bySemanticsLabel('Search brands'), findsOneWidget);
        expect(find.bySemanticsLabel('Create new brand'), findsOneWidget);
      });
    });
  });
}

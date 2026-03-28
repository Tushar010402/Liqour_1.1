import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:liquor_pro_app/features/sales/services/daily_sales_draft_service.dart';
import 'package:liquor_pro_app/features/sales/models/daily_sales_draft.dart';

void main() {
  late DailySalesDraftService service;
  late Directory testDir;

  setUpAll(() async {
    // Create temporary directory for Hive testing
    testDir = Directory.systemTemp.createTempSync('hive_test_');
    // Initialize Hive with temporary directory
    Hive.init(testDir.path);
  });

  tearDownAll(() async {
    // Clean up all boxes
    await Hive.close();
    // Delete temporary directory
    if (testDir.existsSync()) {
      testDir.deleteSync(recursive: true);
    }
  });

  setUp(() async {
    service = DailySalesDraftService();
    await service.initialize();
    // Clear any existing drafts before each test
    await service.clearAllDrafts();
  });

  tearDown(() async {
    await service.dispose();
  });

  group('DailySalesDraftService - Basic Operations', () {
    test('should initialize successfully', () async {
      expect(service, isNotNull);
      final count = await service.getDraftCount();
      expect(count, 0);
    });

    test('should save and load draft correctly', () async {
      final shopId = 'test-shop-123';
      final recordDate = DateTime.now();

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: recordDate,
        productQuantities: {'product-1': 10, 'product-2': 5},
        cashAmount: 1000.0,
        cardAmount: 500.0,
        upiAmount: 300.0,
        creditAmount: 0.0,
        expenseAmount: 50.0,
        notes: 'Test draft',
        savedAt: DateTime.now(),
        currentStep: 0,
      );

      // Save draft
      await service.saveDraft(shopId, recordDate, draft);

      // Load draft
      final loaded = await service.loadDraft(shopId, recordDate);

      // Verify
      expect(loaded, isNotNull);
      expect(loaded!.shopId, shopId);
      expect(loaded.productQuantities.length, 2);
      expect(loaded.productQuantities['product-1'], 10);
      expect(loaded.cashAmount, 1000.0);
      expect(loaded.cardAmount, 500.0);
      expect(loaded.notes, 'Test draft');
    });

    test('should return null for non-existent draft', () async {
      final loaded = await service.loadDraft('non-existent-shop', DateTime.now());
      expect(loaded, isNull);
    });

    test('should delete draft correctly', () async {
      final shopId = 'test-shop-delete';
      final recordDate = DateTime.now();

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: recordDate,
        productQuantities: {'product-1': 10},
        cashAmount: 1000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: '',
        savedAt: DateTime.now(),
        currentStep: 0,
      );

      // Save and verify it exists
      await service.saveDraft(shopId, recordDate, draft);
      expect(await service.hasDraft(shopId, recordDate), true);

      // Delete
      await service.deleteDraft(shopId, recordDate);

      // Verify it's gone
      expect(await service.hasDraft(shopId, recordDate), false);
      final loaded = await service.loadDraft(shopId, recordDate);
      expect(loaded, isNull);
    });

    test('should check draft existence correctly', () async {
      final shopId = 'test-shop-exists';
      final recordDate = DateTime.now();

      // Initially should not exist
      expect(await service.hasDraft(shopId, recordDate), false);

      // Save draft
      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: recordDate,
        productQuantities: {'product-1': 5},
        cashAmount: 500.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: '',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopId, recordDate, draft);

      // Should now exist
      expect(await service.hasDraft(shopId, recordDate), true);
    });
  });

  group('DailySalesDraftService - Shop Isolation', () {
    test('should maintain separate drafts per shop', () async {
      final shopA = 'shop-a';
      final shopB = 'shop-b';
      final date = DateTime.now();

      // Create draft for shop A
      final draftA = DailySalesDraft(
        shopId: shopA,
        recordDate: date,
        productQuantities: {'product-1': 10},
        cashAmount: 1000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'Shop A data',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopA, date, draftA);

      // Create draft for shop B
      final draftB = DailySalesDraft(
        shopId: shopB,
        recordDate: date,
        productQuantities: {'product-2': 20},
        cashAmount: 5000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'Shop B data',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopB, date, draftB);

      // Load and verify shop A data
      final loadedA = await service.loadDraft(shopA, date);
      expect(loadedA!.shopId, shopA);
      expect(loadedA.cashAmount, 1000.0);
      expect(loadedA.notes, 'Shop A data');

      // Load and verify shop B data
      final loadedB = await service.loadDraft(shopB, date);
      expect(loadedB!.shopId, shopB);
      expect(loadedB.cashAmount, 5000.0);
      expect(loadedB.notes, 'Shop B data');
    });

    test('should maintain separate drafts per date', () async {
      final shopId = 'test-shop';
      final date1 = DateTime(2025, 1, 1);
      final date2 = DateTime(2025, 1, 2);

      // Create draft for date 1
      final draft1 = DailySalesDraft(
        shopId: shopId,
        recordDate: date1,
        productQuantities: {'product-1': 10},
        cashAmount: 1000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'Date 1',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopId, date1, draft1);

      // Create draft for date 2
      final draft2 = DailySalesDraft(
        shopId: shopId,
        recordDate: date2,
        productQuantities: {'product-2': 20},
        cashAmount: 2000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'Date 2',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopId, date2, draft2);

      // Load and verify date 1 data
      final loaded1 = await service.loadDraft(shopId, date1);
      expect(loaded1!.cashAmount, 1000.0);
      expect(loaded1.notes, 'Date 1');

      // Load and verify date 2 data
      final loaded2 = await service.loadDraft(shopId, date2);
      expect(loaded2!.cashAmount, 2000.0);
      expect(loaded2.notes, 'Date 2');
    });
  });

  group('DailySalesDraftService - Data Fidelity', () {
    test('should preserve all payment fields', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {},
        cashAmount: 1234.56,
        cardAmount: 2345.67,
        upiAmount: 3456.78,
        creditAmount: 4567.89,
        expenseAmount: 567.89,
        notes: '',
        savedAt: DateTime.now(),
        currentStep: 1,
      );

      await service.saveDraft(shopId, date, draft);
      final loaded = await service.loadDraft(shopId, date);

      expect(loaded!.cashAmount, 1234.56);
      expect(loaded.cardAmount, 2345.67);
      expect(loaded.upiAmount, 3456.78);
      expect(loaded.creditAmount, 4567.89);
      expect(loaded.expenseAmount, 567.89);
      expect(loaded.currentStep, 1);
    });

    test('should preserve multiple products with quantities', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      final products = {
        'product-1': 10,
        'product-2': 20,
        'product-3': 30,
        'product-4': 5,
        'product-5': 15,
      };

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: products,
        cashAmount: 0.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: '',
        savedAt: DateTime.now(),
        currentStep: 0,
      );

      await service.saveDraft(shopId, date, draft);
      final loaded = await service.loadDraft(shopId, date);

      expect(loaded!.productQuantities.length, 5);
      expect(loaded.productQuantities['product-1'], 10);
      expect(loaded.productQuantities['product-2'], 20);
      expect(loaded.productQuantities['product-3'], 30);
      expect(loaded.productQuantities['product-4'], 5);
      expect(loaded.productQuantities['product-5'], 15);
    });

    test('should preserve long notes text', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      final longNotes = 'This is a very long note with multiple lines.\n'
          'Line 2: Additional information about the sale.\n'
          'Line 3: Special characters: @#\$%^&*()_+-=[]{}|;:,.<>?/~`\n'
          'Line 4: Unicode: 🚀 💾 ✅ 📝 🔄';

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {},
        cashAmount: 0.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: longNotes,
        savedAt: DateTime.now(),
        currentStep: 0,
      );

      await service.saveDraft(shopId, date, draft);
      final loaded = await service.loadDraft(shopId, date);

      expect(loaded!.notes, longNotes);
    });
  });

  group('DailySalesDraftService - Draft Cleanup', () {
    test('should clear all drafts', () async {
      // Create multiple drafts
      for (int i = 0; i < 5; i++) {
        final draft = DailySalesDraft(
          shopId: 'shop-$i',
          recordDate: DateTime.now(),
          productQuantities: {'product-1': i},
          cashAmount: i * 100.0,
          cardAmount: 0.0,
          upiAmount: 0.0,
          creditAmount: 0.0,
          expenseAmount: 0.0,
          notes: '',
          savedAt: DateTime.now(),
          currentStep: 0,
        );
        await service.saveDraft('shop-$i', DateTime.now(), draft);
      }

      // Verify we have drafts
      final countBefore = await service.getDraftCount();
      expect(countBefore, greaterThan(0));

      // Clear all
      await service.clearAllDrafts();

      // Verify all cleared
      final countAfter = await service.getDraftCount();
      expect(countAfter, 0);
    });

    test('should get all drafts sorted by newest first', () async {
      await service.clearAllDrafts();

      // Create drafts with different timestamps
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 100));

        final draft = DailySalesDraft(
          shopId: 'shop-$i',
          recordDate: DateTime.now(),
          productQuantities: {'product-1': i},
          cashAmount: i * 100.0,
          cardAmount: 0.0,
          upiAmount: 0.0,
          creditAmount: 0.0,
          expenseAmount: 0.0,
          notes: 'Draft $i',
          savedAt: DateTime.now(),
          currentStep: 0,
        );
        await service.saveDraft('shop-$i', DateTime.now(), draft);
      }

      final allDrafts = await service.getAllDrafts();
      expect(allDrafts.length, 3);

      // Verify sorting (newest first)
      for (int i = 0; i < allDrafts.length - 1; i++) {
        expect(
          allDrafts[i].savedAt.isAfter(allDrafts[i + 1].savedAt) ||
          allDrafts[i].savedAt.isAtSameMomentAs(allDrafts[i + 1].savedAt),
          true,
          reason: 'Drafts should be sorted newest first'
        );
      }
    });
  });

  group('DailySalesDraftService - Edge Cases', () {
    test('should handle empty product quantities', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {},
        cashAmount: 1000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'No products, only payment',
        savedAt: DateTime.now(),
        currentStep: 1,
      );

      await service.saveDraft(shopId, date, draft);
      final loaded = await service.loadDraft(shopId, date);

      expect(loaded!.productQuantities, isEmpty);
      expect(loaded.cashAmount, 1000.0);
    });

    test('should handle zero values', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {'product-1': 0}, // Zero quantity
        cashAmount: 0.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: '',
        savedAt: DateTime.now(),
        currentStep: 0,
      );

      await service.saveDraft(shopId, date, draft);
      final loaded = await service.loadDraft(shopId, date);

      expect(loaded!.productQuantities['product-1'], 0);
      expect(loaded.cashAmount, 0.0);
    });

    test('should handle empty notes', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      final draft = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {'product-1': 10},
        cashAmount: 1000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: '',
        savedAt: DateTime.now(),
        currentStep: 0,
      );

      await service.saveDraft(shopId, date, draft);
      final loaded = await service.loadDraft(shopId, date);

      expect(loaded!.notes, '');
    });

    test('should handle draft overwrite', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      // First draft
      final draft1 = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {'product-1': 10},
        cashAmount: 1000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'First version',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopId, date, draft1);

      // Overwrite with second draft
      final draft2 = DailySalesDraft(
        shopId: shopId,
        recordDate: date,
        productQuantities: {'product-2': 20},
        cashAmount: 2000.0,
        cardAmount: 0.0,
        upiAmount: 0.0,
        creditAmount: 0.0,
        expenseAmount: 0.0,
        notes: 'Second version',
        savedAt: DateTime.now(),
        currentStep: 0,
      );
      await service.saveDraft(shopId, date, draft2);

      // Should have second version
      final loaded = await service.loadDraft(shopId, date);
      expect(loaded!.cashAmount, 2000.0);
      expect(loaded.notes, 'Second version');
      expect(loaded.productQuantities['product-2'], 20);
      expect(loaded.productQuantities.containsKey('product-1'), false);
    });
  });

  group('DailySalesDraftService - Auto-Save', () {
    test('should enable and disable auto-save', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      var saveCount = 0;

      // Enable auto-save
      service.enableAutoSave(
        shopId: shopId,
        recordDate: date,
        getCurrentDraft: () {
          saveCount++;
          return DailySalesDraft(
            shopId: shopId,
            recordDate: date,
            productQuantities: {'product-1': saveCount},
            cashAmount: saveCount * 100.0,
            cardAmount: 0.0,
            upiAmount: 0.0,
            creditAmount: 0.0,
            expenseAmount: 0.0,
            notes: '',
            savedAt: DateTime.now(),
            currentStep: 0,
          );
        },
        interval: const Duration(milliseconds: 500), // Fast for testing
      );

      // Wait for at least one auto-save
      await Future.delayed(const Duration(milliseconds: 1000));

      // Disable auto-save
      service.disableAutoSave();

      // Verify at least one save occurred
      expect(saveCount, greaterThan(0));

      // Load draft
      final loaded = await service.loadDraft(shopId, date);
      expect(loaded, isNotNull);
    });

    test('should perform manual save', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      // Setup auto-save (but don't wait for timer)
      service.enableAutoSave(
        shopId: shopId,
        recordDate: date,
        getCurrentDraft: () {
          return DailySalesDraft(
            shopId: shopId,
            recordDate: date,
            productQuantities: {'product-1': 100},
            cashAmount: 5000.0,
            cardAmount: 0.0,
            upiAmount: 0.0,
            creditAmount: 0.0,
            expenseAmount: 0.0,
            notes: 'Manual save test',
            savedAt: DateTime.now(),
            currentStep: 0,
          );
        },
      );

      // Trigger manual save immediately
      await service.manualSave();

      // Verify it saved
      final loaded = await service.loadDraft(shopId, date);
      expect(loaded, isNotNull);
      expect(loaded!.cashAmount, 5000.0);
      expect(loaded.notes, 'Manual save test');

      service.disableAutoSave();
    });

    test('should not save empty drafts during auto-save', () async {
      final shopId = 'test-shop';
      final date = DateTime.now();

      // Enable auto-save with empty draft
      service.enableAutoSave(
        shopId: shopId,
        recordDate: date,
        getCurrentDraft: () {
          return DailySalesDraft(
            shopId: shopId,
            recordDate: date,
            productQuantities: {},
            cashAmount: 0.0,
            cardAmount: 0.0,
            upiAmount: 0.0,
            creditAmount: 0.0,
            expenseAmount: 0.0,
            notes: '',
            savedAt: DateTime.now(),
            currentStep: 0,
          );
        },
        interval: const Duration(milliseconds: 500),
      );

      // Wait for potential auto-save
      await Future.delayed(const Duration(milliseconds: 1000));

      // Disable auto-save
      service.disableAutoSave();

      // Verify no draft was saved
      final loaded = await service.loadDraft(shopId, date);
      expect(loaded, isNull);
    });
  });
}

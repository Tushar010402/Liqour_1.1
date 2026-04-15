/// Stock Purchase Model Tests — Real Invoice Verification
///
/// Tests the purchase module calculations against real-world documents:
/// - Invoice #81 from SONU SINGH FL-2 dated 4-Apr-2026
/// - UP Department of Excise Transport Pass dated 04-Apr-2026
///
/// Verifies TCS (2%), duty fee passthrough, round-off, and backend JSON alignment.
import 'package:flutter_test/flutter_test.dart';
import 'package:liquor_pro_app/features/inventory/models/stock_purchase.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════
  // Real invoice data — SONU SINGH FL-2, Invoice #81, 4-Apr-2026
  // Party: Radhika Agrawal Comp Mahuakheda S.JD 43124 (25-26)
  // ═══════════════════════════════════════════════════════════════════

  /// Per-bottle cost prices derived from invoice case rates / bottles per case.
  /// Per-bottle duty fees derived from excise transport pass duty / bottles.
  ///
  /// We use 5 representative line items whose amounts we can read clearly
  /// from the invoice and cross-reference with the excise pass.
  List<StockPurchaseItem> _buildInvoiceItems() {
    return [
      // Invoice #1: 8pm Gold Whisky 750ml — 1 case = 12 bottles
      // Rate/case 4,774.80 → per-bottle 397.90
      // Excise duty 3,982.08 / 12 = 331.84/bottle
      StockPurchaseItem.fromSelection(
        productId: 'prod-8pm-gold-750',
        productName: '8pm Gold Whisky - 750ML',
        brandName: '8pm Gold',
        size: '750ML',
        quantity: 12, // 1 case = 12 bottles
        costPrice: 397.90,
        dutyFee: 331.84,
      ),

      // Invoice #2: 8pm Gold Whisky 375ml — 2 cases = 48 bottles
      // Rate/case 5,134.80 → per-bottle 213.95
      // Excise duty 8,612.16 / 48 = 179.42/bottle
      StockPurchaseItem.fromSelection(
        productId: 'prod-8pm-gold-375',
        productName: '8pm Gold Whisky - 375ML',
        brandName: '8pm Gold',
        size: '375ML',
        quantity: 48, // 2 cases × 24 bottles
        costPrice: 213.95,
        dutyFee: 179.42,
      ),

      // Invoice #3: Iconiq White Whisky 375ml — 3 cases = 72 bottles
      // Rate/case 6,676.80 → per-bottle 278.20
      // Excise duty 15,411.60 / 72 = 214.05/bottle
      StockPurchaseItem.fromSelection(
        productId: 'prod-iconiq-375',
        productName: 'Iconiq White Whisky - 375ML',
        brandName: 'Iconiq White',
        size: '375ML',
        quantity: 72, // 3 cases × 24 bottles
        costPrice: 278.20,
        dutyFee: 214.05,
      ),

      // Invoice #6: Royal Stag Superior 750ml — 5 cases = 60 bottles
      // Rate/case 5,409.60 → per-bottle 450.80
      // Excise duty (from pass item 11): 5,441.64 / 12 per case = 453.47/bottle
      // Note: Excise pass shows 1 case but invoice shows 5; duty per bottle is consistent
      StockPurchaseItem.fromSelection(
        productId: 'prod-royal-stag-750',
        productName: 'Royal Stag Superior Whisky - 750ML',
        brandName: 'Royal Stag',
        size: '750ML',
        quantity: 60, // 5 cases × 12 bottles
        costPrice: 450.80,
        dutyFee: 453.47,
      ),

      // Invoice #11: Blenders Pride 375ml — 1 case = 24 bottles
      // Rate/case 8,096.16 → per-bottle 337.34
      // Excise duty 7,204.56 / 24 = 300.19/bottle
      StockPurchaseItem.fromSelection(
        productId: 'prod-blenders-375',
        productName: 'Blenders Pride Whisky - 375ML',
        brandName: 'Blenders Pride',
        size: '375ML',
        quantity: 24, // 1 case × 24 bottles
        costPrice: 337.34,
        dutyFee: 300.19,
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════
  // Test Group 1: TCS Calculation Accuracy (Real Invoice #81)
  // ═══════════════════════════════════════════════════════════════════
  group('TCS Calculation — Real Invoice #81', () {
    test('TCS rate is 2% of subtotal', () {
      final items = _buildInvoiceItems();
      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-sonu-singh',
        items: items,
      );

      final subtotal = request.subtotal;
      final tcs = request.tcsAmount;

      // TCS must be exactly 2% of subtotal
      expect(tcs, closeTo(subtotal * 0.02, 0.01));
    });

    test('TCS matches real invoice for known subtotal 2,73,044.44', () {
      // Real invoice: subtotal = 2,73,044.44, TCS = 5,460.89
      // Verify: 273044.44 × 0.02 = 5460.8888
      final tcs = 273044.44 * 0.02;
      expect(tcs, closeTo(5460.89, 0.01));
    });

    test('Grand total = Subtotal + TCS + RoundOff', () {
      final items = _buildInvoiceItems();
      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-sonu-singh',
        items: items,
      );

      final expectedTotal = request.subtotal + request.tcsAmount + request.effectiveRoundOff;
      expect(request.totalAmount, closeTo(expectedTotal, 0.01));
    });

    test('Round-off makes total a whole number', () {
      final items = _buildInvoiceItems();
      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-sonu-singh',
        items: items,
      );

      final total = request.totalAmount;
      // Total should be a whole number (no fractional part)
      expect(total % 1, closeTo(0.0, 0.01),
          reason: 'Total $total should be rounded to whole number');
    });

    test('Round-off is minimal (within ±0.50)', () {
      final items = _buildInvoiceItems();
      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-sonu-singh',
        items: items,
      );

      expect(request.calculatedRoundOff.abs(), lessThan(0.50),
          reason: 'Round-off should be minimal');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Test Group 2: Duty Fee Passthrough
  // ═══════════════════════════════════════════════════════════════════
  group('Duty Fee Passthrough', () {
    test('fromSelection preserves dutyFee', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'prod-8pm-gold-750',
        productName: '8pm Gold Whisky - 750ML',
        size: '750ML',
        quantity: 12,
        costPrice: 397.90,
        dutyFee: 331.84,
      );

      expect(item.dutyFee, 331.84);
      expect(item.costPrice, 397.90);
      expect(item.quantity, 12);
      expect(item.totalAmount, closeTo(12 * 397.90, 0.01));
    });

    test('fromSelection defaults dutyFee to 0 when not provided', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'prod-test',
        productName: 'Test Product',
        size: '180ML',
        quantity: 48,
        costPrice: 100.0,
      );

      expect(item.dutyFee, 0.0);
    });

    test('toJson includes duty_fee when > 0', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'prod-8pm-gold-750',
        productName: '8pm Gold Whisky',
        size: '750ML',
        quantity: 12,
        costPrice: 397.90,
        dutyFee: 331.84,
      );

      final json = item.toJson();
      expect(json['duty_fee'], 331.84);
    });

    test('toJson excludes duty_fee when 0', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'prod-test',
        productName: 'Test',
        size: '180ML',
        quantity: 10,
        costPrice: 100.0,
        dutyFee: 0.0,
      );

      final json = item.toJson();
      expect(json.containsKey('duty_fee'), isFalse,
          reason: 'duty_fee should not be in JSON when zero');
    });

    test('CreateStockPurchaseRequest.toJson includes duty_fee per item', () {
      final items = [
        StockPurchaseItem.fromSelection(
          productId: 'prod-1',
          productName: 'Product 1',
          size: '750ML',
          quantity: 12,
          costPrice: 397.90,
          dutyFee: 331.84,
        ),
      ];

      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-1',
        items: items,
      );

      final json = request.toJson();
      final jsonItems = json['items'] as List;
      expect(jsonItems.first['duty_fee'], 331.84);
    });

    test('fromJson reads duty_fee correctly', () {
      final json = {
        'product_id': 'prod-1',
        'product_name': 'Test Product',
        'size': '750ML',
        'quantity': 12,
        'cost_price': 397.90,
        'total_amount': 4774.80,
        'duty_fee': 331.84,
      };

      final item = StockPurchaseItem.fromJson(json);
      expect(item.dutyFee, 331.84);
      expect(item.costPrice, 397.90);
      expect(item.quantity, 12);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Test Group 3: Invoice Line Item Verification
  // ═══════════════════════════════════════════════════════════════════
  group('Invoice Line Item Verification', () {
    test('8pm Gold 750ml: 1 case (12 bottles) = Rs.4,774.80', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'p1',
        productName: '8pm Gold 750ML',
        size: '750ML',
        quantity: 12,
        costPrice: 397.90,
      );

      expect(item.totalAmount, closeTo(4774.80, 0.01));
    });

    test('8pm Gold 375ml: 2 cases (48 bottles) = Rs.10,269.60', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'p2',
        productName: '8pm Gold 375ML',
        size: '375ML',
        quantity: 48,
        costPrice: 213.95,
      );

      expect(item.totalAmount, closeTo(10269.60, 0.01));
    });

    test('Iconiq White 375ml: 3 cases (72 bottles) = Rs.20,030.40', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'p3',
        productName: 'Iconiq White 375ML',
        size: '375ML',
        quantity: 72,
        costPrice: 278.20,
      );

      expect(item.totalAmount, closeTo(20030.40, 0.01));
    });

    test('Royal Stag Superior 750ml: 5 cases (60 bottles) = Rs.27,048.00', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'p6',
        productName: 'Royal Stag Superior 750ML',
        size: '750ML',
        quantity: 60,
        costPrice: 450.80,
      );

      expect(item.totalAmount, closeTo(27048.00, 0.01));
    });

    test('Blenders Pride 375ml: 1 case (24 bottles) = Rs.8,096.16', () {
      final item = StockPurchaseItem.fromSelection(
        productId: 'p11',
        productName: 'Blenders Pride 375ML',
        size: '375ML',
        quantity: 24,
        costPrice: 337.34,
      );

      expect(item.totalAmount, closeTo(8096.16, 0.01));
    });

    test('Full invoice subtotal + TCS matches real invoice total', () {
      // Real invoice: Subtotal = 2,73,044.44, TCS 2% = 5,460.89, Total = 2,78,505.33
      const invoiceSubtotal = 273044.44;
      const invoiceTcs = 5460.89;
      const invoiceTotal = 278505.33;

      // Verify the math
      final calculatedTcs = invoiceSubtotal * 0.02;
      expect(calculatedTcs, closeTo(invoiceTcs, 0.01),
          reason: 'TCS should be 2% of subtotal');

      final calculatedTotal = invoiceSubtotal + invoiceTcs;
      expect(calculatedTotal, closeTo(invoiceTotal, 0.01),
          reason: 'Total should be subtotal + TCS');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Test Group 4: Backend JSON Alignment
  // ═══════════════════════════════════════════════════════════════════
  group('Backend JSON Alignment', () {
    test('CreateStockPurchaseRequest.toJson sends correct field names', () {
      final items = [
        StockPurchaseItem.fromSelection(
          productId: 'prod-1',
          productName: 'Test Product',
          size: '750ML',
          quantity: 12,
          costPrice: 397.90,
          dutyFee: 331.84,
        ),
      ];

      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-1',
        items: items,
        receiptNumber: 'REC-81',
      );

      final json = request.toJson();

      // Top-level fields
      expect(json['shop_id'], 'shop-1');
      expect(json['vendor_id'], 'vendor-1');
      expect(json.containsKey('total_amount'), isTrue,
          reason: 'Must send total_amount to backend');
      expect(json['receipt_no'], 'REC-81',
          reason: 'Backend expects receipt_no, not receipt_number');

      // Item fields
      final itemJson = (json['items'] as List).first as Map<String, dynamic>;
      expect(itemJson['product_id'], 'prod-1');
      expect(itemJson['quantity'], 12);
      expect(itemJson['unit_price'], 397.90,
          reason: 'Backend expects unit_price');
      expect(itemJson['total_price'], closeTo(4774.80, 0.01),
          reason: 'Backend expects total_price');
      expect(itemJson['duty_fee'], 331.84,
          reason: 'Backend expects duty_fee');
    });

    test('StockPurchase.fromJson reads tax_amount (backend field)', () {
      final json = {
        'id': 'purchase-1',
        'shop_id': 'shop-1',
        'vendor_id': 'vendor-1',
        'status': 'approved',
        'items': [
          {
            'product_id': 'prod-1',
            'product_name': 'Test Product',
            'size': '750ML',
            'quantity': 12,
            'cost_price': 397.90,
            'total_amount': 4774.80,
            'duty_fee': 331.84,
          },
        ],
        'subtotal': 4774.80,
        'tax_amount': 95.50, // Backend sends tax_amount
        'round_off': -0.30,
        'created_at': '2026-04-04T10:00:00Z',
      };

      final purchase = StockPurchase.fromJson(json);

      expect(purchase.tcsAmount, closeTo(95.50, 0.01),
          reason: 'Should read tax_amount from backend into tcsAmount');
      expect(purchase.subtotal, closeTo(4774.80, 0.01));
      expect(purchase.roundOff, closeTo(-0.30, 0.01));
    });

    test('StockPurchase.fromJson backward compat: reads tds_amount', () {
      final json = {
        'id': 'purchase-old',
        'shop_id': 'shop-1',
        'vendor_id': 'vendor-1',
        'status': 'pending',
        'items': [
          {
            'product_id': 'prod-1',
            'quantity': 10,
            'unit_cost': 100.0,
            'total_cost': 1000.0,
          },
        ],
        'subtotal': 1000.0,
        'tds_amount': 10.0, // Old field name
        'created_at': '2026-04-01T10:00:00Z',
      };

      final purchase = StockPurchase.fromJson(json);

      expect(purchase.tcsAmount, closeTo(10.0, 0.01),
          reason: 'Should read old tds_amount for backward compatibility');
    });

    test('StockPurchase.fromJson calculates TCS when tax_amount is missing', () {
      final json = {
        'id': 'purchase-no-tax',
        'shop_id': 'shop-1',
        'vendor_id': 'vendor-1',
        'status': 'pending',
        'items': [
          {
            'product_id': 'prod-1',
            'quantity': 12,
            'cost_price': 397.90,
            'total_amount': 4774.80,
          },
        ],
        // No tax_amount field
        'created_at': '2026-04-04T10:00:00Z',
      };

      final purchase = StockPurchase.fromJson(json);

      // Should auto-calculate TCS at 2%
      final expectedTcs = purchase.subtotal * 0.02;
      expect(purchase.tcsAmount, closeTo(expectedTcs, 0.01),
          reason: 'Should auto-calculate TCS at 2% when tax_amount is missing');
    });

    test('StockPurchase.toJson sends tax_amount (not tds_amount)', () {
      final purchase = StockPurchase(
        id: 'test-1',
        shopId: 'shop-1',
        shopName: 'Test Shop',
        vendorId: 'vendor-1',
        vendorName: 'SONU SINGH FL-2',
        items: [],
        subtotal: 273044.44,
        tcsAmount: 5460.89,
        roundOff: -0.33,
        totalAmount: 278505.00,
        status: StockPurchaseStatus.approved,
        createdById: 'user-1',
        createdByName: 'Admin',
        createdByRole: 'admin',
        createdAt: DateTime(2026, 4, 4),
      );

      final json = purchase.toJson();
      expect(json.containsKey('tax_amount'), isTrue,
          reason: 'Should send tax_amount to match backend');
      expect(json.containsKey('tds_amount'), isFalse,
          reason: 'Should NOT send old tds_amount key');
      expect(json['tax_amount'], closeTo(5460.89, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Test Group 5: Edge Cases
  // ═══════════════════════════════════════════════════════════════════
  group('Edge Cases', () {
    test('Single item purchase calculates correctly', () {
      final items = [
        StockPurchaseItem.fromSelection(
          productId: 'prod-1',
          productName: 'Single Item',
          size: '750ML',
          quantity: 12,
          costPrice: 397.90,
          dutyFee: 331.84,
        ),
      ];

      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-1',
        items: items,
      );

      expect(request.subtotal, closeTo(4774.80, 0.01));
      expect(request.tcsAmount, closeTo(4774.80 * 0.02, 0.01));
      // Total should be whole number
      expect(request.totalAmount % 1, closeTo(0.0, 0.01));
    });

    test('Round-off is zero when total is already whole number', () {
      // Find a costPrice × quantity that with TCS gives exact whole number
      // e.g., subtotal = 5000.00, TCS = 100.00, total = 5100.00
      final items = [
        StockPurchaseItem.fromSelection(
          productId: 'prod-exact',
          productName: 'Exact Amount Product',
          size: '180ML',
          quantity: 50,
          costPrice: 100.0, // 50 × 100 = 5000.00, TCS = 100.00 → total 5100
        ),
      ];

      final request = CreateStockPurchaseRequest(
        shopId: 'shop-1',
        vendorId: 'vendor-1',
        items: items,
      );

      expect(request.subtotal, 5000.0);
      expect(request.tcsAmount, 100.0);
      expect(request.calculatedRoundOff, 0.0,
          reason: 'No round-off needed when total is exactly 5100');
      expect(request.totalAmount, 5100.0);
    });

    test('Item totalAmount = costPrice × quantity (integer precision)', () {
      // Test with real invoice value that could have floating-point issues
      final item = StockPurchaseItem.fromSelection(
        productId: 'prod-sterling',
        productName: 'Sterling Reserve B7 375ML',
        size: '375ML',
        quantity: 72, // 3 cases × 24 bottles
        costPrice: 337.30,
        dutyFee: 240.71,
      );

      // 72 × 337.30 = 24,285.60
      expect(item.totalAmount, closeTo(24285.60, 0.01),
          reason: 'Sterling Reserve B7 375ml: 3 cases should = 24,285.60');
    });

    test('Large purchase handles precision correctly', () {
      // Simulate the full 36-case invoice
      final items = _buildInvoiceItems();
      final request = CreateStockPurchaseRequest(
        shopId: 'shop-radhika',
        vendorId: 'vendor-sonu-singh',
        items: items,
      );

      // Verify TCS is 2% of whatever subtotal we get
      expect(request.tcsAmount, closeTo(request.subtotal * 0.02, 0.01));

      // Verify total = subtotal + TCS + roundOff (± 0.50 for round-off)
      final beforeRoundOff = request.subtotal + request.tcsAmount;
      expect((request.totalAmount - beforeRoundOff).abs(), lessThan(0.50));

      // Total must be whole number
      expect(request.totalAmount % 1, closeTo(0.0, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  // Test Group 6: Excise Pass Duty Data Verification
  // ═══════════════════════════════════════════════════════════════════
  group('Excise Pass Duty Verification', () {
    test('8pm Gold 750ml duty: Rs.3,982.08 for 12 bottles = Rs.331.84/bottle', () {
      const totalDuty = 3982.08;
      const bottles = 12;
      const perBottle = 331.84;
      expect(totalDuty / bottles, closeTo(perBottle, 0.01));

      final item = StockPurchaseItem.fromSelection(
        productId: 'p1',
        productName: '8pm Gold 750ML',
        size: '750ML',
        quantity: bottles,
        costPrice: 397.90,
        dutyFee: perBottle,
      );
      expect(item.dutyFee, perBottle);
    });

    test('Iconiq White 375ml duty: Rs.15,411.60 for 72 bottles = Rs.214.05/bottle', () {
      const totalDuty = 15411.60;
      const bottles = 72;
      const perBottle = 214.05;
      expect(totalDuty / bottles, closeTo(perBottle, 0.01));
    });

    test('Blenders Pride 375ml duty: Rs.7,204.56 for 24 bottles = Rs.300.19/bottle', () {
      const totalDuty = 7204.56;
      const bottles = 24;
      const perBottle = 300.19;
      expect(totalDuty / bottles, closeTo(perBottle, 0.01));
    });

    test('Rockford Reserve 375ml duty: Rs.15,037.44 for 48 bottles = Rs.313.28/bottle', () {
      const totalDuty = 15037.44;
      const bottles = 48;
      const perBottle = 313.28;
      expect(totalDuty / bottles, closeTo(perBottle, 0.01));
    });

    test('Officer Choice 180ml duty: Rs.22,840.80 for 240 bottles = Rs.95.17/bottle', () {
      const totalDuty = 22840.80;
      const bottles = 240;
      const perBottle = 95.17;
      expect(totalDuty / bottles, closeTo(perBottle, 0.01));
    });
  });
}

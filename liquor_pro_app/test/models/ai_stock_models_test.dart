import 'package:flutter_test/flutter_test.dart';
import 'package:liquor_pro_app/features/inventory/models/ai_stock_models.dart';

void main() {
  group('SmartStockItem.fromJson', () {
    test('parses new display / full name fields', () {
      final item = SmartStockItem.fromJson(const {
        'row_number': 1,
        'brand_name': '8 PM Rare Whisky',
        'size': '750ML',
        'size_ml': 750,
        'opening': 0,
        'receipt': 12,
        'total': 12,
        'sale': 1,
        'closing_stock': 11,
        'stock_quantity': 12,
        'rate': 460,
        'amount': 470,
        'product_id': 'abc',
        'matched_brand_name': 'Legacy Alias',
        'matched_display_name': '8 PM Special Rare Whisky',
        'matched_full_name': '8 PM Special Rare Whisky - 750ML',
        'match_confidence': 0.96,
        'status': 'matched',
        'alternative_matches': <Map<String, dynamic>>[],
        'warnings': <String>[],
        'official_brand_name': '8 PM Special Rare Whisky',
        'needs_review': false,
        'current_stock': 48,
      });

      expect(item.matchedDisplayName, '8 PM Special Rare Whisky');
      expect(item.matchedFullName, '8 PM Special Rare Whisky - 750ML');
      expect(item.displayName, '8 PM Special Rare Whisky');
      expect(item.isMatched, isTrue);
      expect(item.needsReview, isFalse);
      expect(item.isAutoCreate, isFalse);
      expect(item.isMissing, isFalse);
      expect(item.opening, 0);
      expect(item.receipt, 12);
      expect(item.sale, 1);
      expect(item.closingStock, 11);
    });

    test('prefers matched_display_name over official / matched / raw', () {
      final item = SmartStockItem.fromJson(const {
        'brand_name': 'RAW_OCR',
        'size': '',
        'matched_brand_name': 'Matched Name',
        'matched_display_name': 'Display Name',
        'official_brand_name': 'Official Name',
      });
      expect(item.displayName, 'Display Name');
    });

    test('falls back through chain when display missing', () {
      final matchedOnly = SmartStockItem.fromJson(const {
        'brand_name': 'RAW',
        'size': '',
        'matched_brand_name': 'Matched',
      });
      expect(matchedOnly.displayName, 'Matched');

      final rawOnly = SmartStockItem.fromJson(const {
        'brand_name': 'RAW',
        'size': '',
      });
      expect(rawOnly.displayName, 'RAW');
    });

    test('recognizes new statuses', () {
      final auto = SmartStockItem.fromJson(const {
        'brand_name': 'X', 'size': '', 'status': 'auto_create',
      });
      expect(auto.isAutoCreate, isTrue);
      expect(auto.needsReview, isTrue); // auto_create still wants user ack

      final missing = SmartStockItem.fromJson(const {
        'brand_name': 'Y', 'size': '', 'status': 'missing',
      });
      expect(missing.isMissing, isTrue);
      expect(missing.isAutoCreate, isFalse);

      final lowConf = SmartStockItem.fromJson(const {
        'brand_name': 'Z', 'size': '', 'status': 'low_confidence',
      });
      expect(lowConf.needsReview, isTrue);

      final ambiguous = SmartStockItem.fromJson(const {
        'brand_name': 'W', 'size': '', 'status': 'ambiguous',
      });
      expect(ambiguous.needsReview, isTrue);
    });
  });

  group('StockAlternativeMatch.fromJson', () {
    test('parses new display_name / full_name / mrp / cost_price', () {
      final alt = StockAlternativeMatch.fromJson(const {
        'product_id': 'pid',
        'brand_name': 'Legacy',
        'display_name': '8 PM Gold Blend',
        'full_name': '8PM Gold Blend of Scotch & Indian Grain Whisky - 750ML',
        'size': '750ML',
        'mrp': 470,
        'cost_price': 460,
        'confidence': 0.92,
      });
      expect(alt.displayName, '8 PM Gold Blend');
      expect(alt.fullName, '8PM Gold Blend of Scotch & Indian Grain Whisky - 750ML');
      expect(alt.mrp, 470);
      expect(alt.costPrice, 460);
      expect(alt.effectiveDisplayName, '8 PM Gold Blend');
    });

    test('effectiveDisplayName falls back to brand_name', () {
      final alt = StockAlternativeMatch.fromJson(const {
        'product_id': 'pid',
        'brand_name': 'Legacy Only',
      });
      expect(alt.displayName, isNull);
      expect(alt.effectiveDisplayName, 'Legacy Only');
    });
  });

  group('Excise + master brand suggestions', () {
    test('SmartStockItem parses matched_excise_* fields and exposes exciseName', () {
      final item = SmartStockItem.fromJson(const {
        'brand_name': 'RAW',
        'size': '750ML',
        'matched_display_name': 'All Seasons Rare Reserve Whisky',
        'matched_full_name': 'All Seasons Rare Reserve Whisky - 750ML',
        'matched_excise_brand_name': 'All Seasons Rare Reserve Whisky',
        'matched_excise_display_name': 'All Seasons Rare Reserve',
        'status': 'matched',
      });
      expect(item.matchedExciseBrandName, 'All Seasons Rare Reserve Whisky');
      expect(item.matchedExciseDisplayName, 'All Seasons Rare Reserve');
      // exciseName prefers the shorter excise display when distinct from display
      expect(item.exciseName, 'All Seasons Rare Reserve');
    });

    test('exciseName returns null when excise fields are same as display', () {
      final item = SmartStockItem.fromJson(const {
        'brand_name': 'x', 'size': '',
        'matched_display_name': 'Same Name',
        'matched_excise_display_name': 'Same Name',
      });
      expect(item.exciseName, isNull);
    });

    test('StockAlternativeMatch parses excise fields', () {
      final alt = StockAlternativeMatch.fromJson(const {
        'product_id': 'p1',
        'brand_name': 'legacy',
        'display_name': '8 PM Premium Black',
        'full_name': '8 PM Premium Black - 750ML',
        'excise_brand_name': '8 PM Premium Black Whisky',
        'excise_display_name': '8 PM Premium Black',
        'mrp': 680,
        'cost_price': 670,
      });
      expect(alt.exciseBrandName, '8 PM Premium Black Whisky');
      expect(alt.exciseDisplayName, '8 PM Premium Black');
      // exciseSubtitle hides when display equals excise_display — falls through to excise_brand
      expect(alt.exciseSubtitle, '8 PM Premium Black Whisky');
      expect(alt.mrp, 680);
    });

    test('MasterBrandSuggestion parses from JSON', () {
      final s = MasterBrandSuggestion.fromJson(const {
        'brand_name': '1965 SPIRIT OF VICTORY PREMIUM XXX RUM',
        'display_name': '1965 Spirit of Victory',
        'mrp': 560,
        'confidence': 0.62,
        'size': '750ML',
      });
      expect(s.brandName, '1965 SPIRIT OF VICTORY PREMIUM XXX RUM');
      expect(s.effectiveDisplayName, '1965 Spirit of Victory');
      expect(s.mrp, 560);
      expect(s.confidence, closeTo(0.62, 1e-9));
    });

    test('SmartStockItem parses master_brand_suggestions for auto_create', () {
      final item = SmartStockItem.fromJson(const {
        'brand_name': '1965 Ram',
        'size': '750ML',
        'status': 'auto_create',
        'review_reason': 'Partial excise match — pick from 5 suggested brand(s) or add new',
        'master_brand_suggestions': [
          {'brand_name': '1965 SPIRIT OF VICTORY PREMIUM XXX RUM', 'display_name': '1965 Spirit of Victory', 'mrp': 560, 'confidence': 0.62},
          {'brand_name': '1965 RESERVE', 'display_name': '1965 Reserve', 'mrp': 600, 'confidence': 0.55},
        ],
      });
      expect(item.isAutoCreate, isTrue);
      expect(item.masterBrandSuggestions, hasLength(2));
      expect(item.masterBrandSuggestions.first.effectiveDisplayName, '1965 Spirit of Victory');
    });
  });

  group('SmartStockResult.fromJson', () {
    test('parses session_id and image_urls for apply reuse', () {
      final r = SmartStockResult.fromJson(const {
        'status': 'success',
        'message': 'ok',
        'session_id': 'abc-123',
        'image_urls': ['https://cdn/x.jpg', 'https://cdn/y.jpg'],
        'items': <Map<String, dynamic>>[],
      });
      expect(r.sessionId, 'abc-123');
      expect(r.imageUrls, hasLength(2));
      expect(r.imageUrls.first, 'https://cdn/x.jpg');
    });

    test('defaults when fields missing', () {
      final r = SmartStockResult.fromJson(const {'status': 'success', 'message': ''});
      expect(r.sessionId, isNull);
      expect(r.imageUrls, isEmpty);
    });
  });
}

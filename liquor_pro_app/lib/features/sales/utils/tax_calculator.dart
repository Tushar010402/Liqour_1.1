import 'package:flutter/material.dart';

/// Tax calculator for frontend since backend doesn't calculate taxes
/// Handles GST calculation for liquor sales in India
class TaxCalculator {
  // Default tax rates for liquor in India (configurable per state)
  static const Map<String, TaxRates> stateWiseTaxRates = {
    'default': TaxRates(
      cgst: 0.09,  // 9% CGST
      sgst: 0.09,  // 9% SGST
      igst: 0.18,  // 18% IGST (for inter-state)
      cess: 0.0,   // Additional cess if applicable
    ),
    'maharashtra': TaxRates(
      cgst: 0.09,
      sgst: 0.09,
      igst: 0.18,
      cess: 0.0,
    ),
    'delhi': TaxRates(
      cgst: 0.10,
      sgst: 0.10,
      igst: 0.20,
      cess: 0.0,
    ),
    'karnataka': TaxRates(
      cgst: 0.09,
      sgst: 0.09,
      igst: 0.18,
      cess: 0.02, // Additional cess
    ),
  };

  // Category-wise tax rates (some categories may have different rates)
  static const Map<String, double> categoryTaxRates = {
    'beer': 0.18,        // 18% total
    'wine': 0.18,        // 18% total
    'whisky': 0.28,      // 28% total (premium)
    'rum': 0.18,         // 18% total
    'vodka': 0.28,       // 28% total (premium)
    'gin': 0.28,         // 28% total (premium)
    'brandy': 0.28,      // 28% total (premium)
    'liqueur': 0.18,     // 18% total
    'rtd': 0.18,         // Ready to drink - 18%
    'default': 0.18,     // Default 18%
  };

  /// Calculate tax for a sale
  static TaxCalculation calculateTax({
    required double subtotal,
    double discount = 0,
    String state = 'default',
    bool isInterState = false,
    String? category,
    List<SaleItemForTax>? items,
  }) {
    final rates = stateWiseTaxRates[state.toLowerCase()] ?? stateWiseTaxRates['default']!;
    final taxableAmount = subtotal - discount;

    // If items provided, calculate item-wise tax
    if (items != null && items.isNotEmpty) {
      return _calculateItemWiseTax(items, rates, isInterState);
    }

    // Otherwise calculate on total
    double cgst = 0;
    double sgst = 0;
    double igst = 0;
    double cess = 0;

    if (isInterState) {
      igst = taxableAmount * rates.igst;
    } else {
      cgst = taxableAmount * rates.cgst;
      sgst = taxableAmount * rates.sgst;
    }

    if (rates.cess > 0) {
      cess = taxableAmount * rates.cess;
    }

    final totalTax = cgst + sgst + igst + cess;
    final grandTotal = taxableAmount + totalTax;

    return TaxCalculation(
      taxableAmount: taxableAmount,
      cgst: cgst,
      sgst: sgst,
      igst: igst,
      cess: cess,
      totalTax: totalTax,
      grandTotal: grandTotal,
      taxRate: _getEffectiveTaxRate(category, rates, isInterState),
      taxBreakdown: _generateTaxBreakdown(cgst, sgst, igst, cess, rates, isInterState),
    );
  }

  /// Calculate item-wise tax for detailed invoice
  static TaxCalculation _calculateItemWiseTax(
    List<SaleItemForTax> items,
    TaxRates rates,
    bool isInterState,
  ) {
    double totalTaxableAmount = 0;
    double totalCgst = 0;
    double totalSgst = 0;
    double totalIgst = 0;
    double totalCess = 0;

    final itemTaxDetails = <ItemTaxDetail>[];

    for (final item in items) {
      final itemTaxableAmount = (item.unitPrice * item.quantity) - (item.discount ?? 0);
      totalTaxableAmount += itemTaxableAmount;

      // Get category-specific tax rate
      final categoryRate = categoryTaxRates[item.category?.toLowerCase()] ??
                          categoryTaxRates['default']!;

      double itemCgst = 0;
      double itemSgst = 0;
      double itemIgst = 0;

      if (isInterState) {
        itemIgst = itemTaxableAmount * categoryRate;
        totalIgst += itemIgst;
      } else {
        itemCgst = itemTaxableAmount * (categoryRate / 2);
        itemSgst = itemTaxableAmount * (categoryRate / 2);
        totalCgst += itemCgst;
        totalSgst += itemSgst;
      }

      if (rates.cess > 0) {
        final itemCess = itemTaxableAmount * rates.cess;
        totalCess += itemCess;
      }

      itemTaxDetails.add(ItemTaxDetail(
        itemName: item.name,
        taxableAmount: itemTaxableAmount,
        cgst: itemCgst,
        sgst: itemSgst,
        igst: itemIgst,
        taxRate: categoryRate,
      ));
    }

    final totalTax = totalCgst + totalSgst + totalIgst + totalCess;
    final grandTotal = totalTaxableAmount + totalTax;

    return TaxCalculation(
      taxableAmount: totalTaxableAmount,
      cgst: totalCgst,
      sgst: totalSgst,
      igst: totalIgst,
      cess: totalCess,
      totalTax: totalTax,
      grandTotal: grandTotal,
      taxRate: totalTax / totalTaxableAmount,
      taxBreakdown: _generateTaxBreakdown(totalCgst, totalSgst, totalIgst, totalCess, rates, isInterState),
      itemTaxDetails: itemTaxDetails,
    );
  }

  /// Get effective tax rate based on category
  static double _getEffectiveTaxRate(String? category, TaxRates rates, bool isInterState) {
    if (category != null) {
      return categoryTaxRates[category.toLowerCase()] ?? categoryTaxRates['default']!;
    }
    return isInterState ? rates.igst : (rates.cgst + rates.sgst);
  }

  /// Generate human-readable tax breakdown
  static List<TaxBreakdownItem> _generateTaxBreakdown(
    double cgst,
    double sgst,
    double igst,
    double cess,
    TaxRates rates,
    bool isInterState,
  ) {
    final breakdown = <TaxBreakdownItem>[];

    if (isInterState) {
      if (igst > 0) {
        breakdown.add(TaxBreakdownItem(
          name: 'IGST',
          rate: rates.igst,
          amount: igst,
        ));
      }
    } else {
      if (cgst > 0) {
        breakdown.add(TaxBreakdownItem(
          name: 'CGST',
          rate: rates.cgst,
          amount: cgst,
        ));
      }
      if (sgst > 0) {
        breakdown.add(TaxBreakdownItem(
          name: 'SGST',
          rate: rates.sgst,
          amount: sgst,
        ));
      }
    }

    if (cess > 0) {
      breakdown.add(TaxBreakdownItem(
        name: 'Cess',
        rate: rates.cess,
        amount: cess,
      ));
    }

    return breakdown;
  }

  /// Validate GST number format
  static bool isValidGSTNumber(String gstNumber) {
    // GST number format: 15 characters
    // First 2 - State code
    // Next 10 - PAN number
    // 13th - Entity number
    // 14th - Z (default)
    // 15th - Check digit
    final gstRegex = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    return gstRegex.hasMatch(gstNumber.toUpperCase());
  }

  /// Get state code from GST number
  static String? getStateFromGST(String gstNumber) {
    if (!isValidGSTNumber(gstNumber)) return null;

    final stateCode = gstNumber.substring(0, 2);
    return _stateCodes[stateCode];
  }

  /// State codes for GST
  static const Map<String, String> _stateCodes = {
    '01': 'Jammu and Kashmir',
    '02': 'Himachal Pradesh',
    '03': 'Punjab',
    '04': 'Chandigarh',
    '05': 'Uttarakhand',
    '06': 'Haryana',
    '07': 'Delhi',
    '08': 'Rajasthan',
    '09': 'Uttar Pradesh',
    '10': 'Bihar',
    '11': 'Sikkim',
    '12': 'Arunachal Pradesh',
    '13': 'Nagaland',
    '14': 'Manipur',
    '15': 'Mizoram',
    '16': 'Tripura',
    '17': 'Meghalaya',
    '18': 'Assam',
    '19': 'West Bengal',
    '20': 'Jharkhand',
    '21': 'Odisha',
    '22': 'Chattisgarh',
    '23': 'Madhya Pradesh',
    '24': 'Gujarat',
    '26': 'Dadra and Nagar Haveli and Daman and Diu',
    '27': 'Maharashtra',
    '29': 'Karnataka',
    '30': 'Goa',
    '31': 'Lakshadweep',
    '32': 'Kerala',
    '33': 'Tamil Nadu',
    '34': 'Puducherry',
    '35': 'Andaman and Nicobar Islands',
    '36': 'Telangana',
    '37': 'Andhra Pradesh',
    '38': 'Ladakh',
  };

  /// Show tax calculation warning
  static void showTaxWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tax Calculation Notice'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Important:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Tax is calculated locally in the app'),
            Text('• Backend does not process tax calculations'),
            Text('• Rates may vary by state and category'),
            Text('• Please verify calculations manually'),
            SizedBox(height: 12),
            Text(
              'For accurate tax compliance, consult with a tax professional.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }
}

/// Tax rates structure
class TaxRates {
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;

  const TaxRates({
    required this.cgst,
    required this.sgst,
    required this.igst,
    this.cess = 0,
  });
}

/// Tax calculation result
class TaxCalculation {
  final double taxableAmount;
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;
  final double totalTax;
  final double grandTotal;
  final double taxRate;
  final List<TaxBreakdownItem> taxBreakdown;
  final List<ItemTaxDetail>? itemTaxDetails;

  const TaxCalculation({
    required this.taxableAmount,
    required this.cgst,
    required this.sgst,
    required this.igst,
    this.cess = 0,
    required this.totalTax,
    required this.grandTotal,
    required this.taxRate,
    required this.taxBreakdown,
    this.itemTaxDetails,
  });

  Map<String, dynamic> toJson() {
    return {
      'taxable_amount': taxableAmount,
      'cgst': cgst,
      'sgst': sgst,
      'igst': igst,
      'cess': cess,
      'total_tax': totalTax,
      'grand_total': grandTotal,
      'tax_rate': taxRate,
      'breakdown': taxBreakdown.map((e) => e.toJson()).toList(),
      if (itemTaxDetails != null)
        'item_details': itemTaxDetails!.map((e) => e.toJson()).toList(),
    };
  }
}

/// Tax breakdown item
class TaxBreakdownItem {
  final String name;
  final double rate;
  final double amount;

  const TaxBreakdownItem({
    required this.name,
    required this.rate,
    required this.amount,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'rate': rate,
      'amount': amount,
    };
  }
}

/// Item for tax calculation
class SaleItemForTax {
  final String name;
  final double unitPrice;
  final int quantity;
  final double? discount;
  final String? category;

  const SaleItemForTax({
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.discount,
    this.category,
  });
}

/// Item-wise tax detail
class ItemTaxDetail {
  final String itemName;
  final double taxableAmount;
  final double cgst;
  final double sgst;
  final double igst;
  final double taxRate;

  const ItemTaxDetail({
    required this.itemName,
    required this.taxableAmount,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.taxRate,
  });

  Map<String, dynamic> toJson() {
    return {
      'item_name': itemName,
      'taxable_amount': taxableAmount,
      'cgst': cgst,
      'sgst': sgst,
      'igst': igst,
      'tax_rate': taxRate,
    };
  }
}
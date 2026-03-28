import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/daily_sales_models.dart';

class ReceiptTableWidget extends StatelessWidget {
  final Sale sale;
  final bool showHeader;
  final bool showPaymentDetails;
  final bool groupBySize;
  /// Optional AI validation data for showing status indicators
  final AIValidationResult? aiValidation;
  /// Callback when user taps on an AI status indicator
  final Function(String productId, ItemInsight insight)? onAIStatusTap;

  const ReceiptTableWidget({
    super.key,
    required this.sale,
    this.showHeader = true,
    this.showPaymentDetails = true,
    this.groupBySize = false,
    this.aiValidation,
    this.onAIStatusTap,
  });

  // Compact currency formatter for large numbers
  static String formatCompactCurrency(double value) {
    if (value >= 10000000) {
      // 1 Crore+
      return '₹${(value / 10000000).toStringAsFixed(1)}Cr';
    } else if (value >= 100000) {
      // 1 Lakh+
      return '₹${(value / 100000).toStringAsFixed(1)}L';
    } else if (value >= 1000) {
      // 1000+
      return '₹${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return '₹${value.toStringAsFixed(0)}';
    }
  }

  // Standard currency formatter (no decimals for whole numbers)
  static String formatCurrency(double value) {
    if (value == value.truncate()) {
      return '₹${NumberFormat('#,##,###', 'en_IN').format(value.truncate())}';
    }
    return '₹${NumberFormat('#,##,###.##', 'en_IN').format(value)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    // Group items by Category (Beer vs Non-Beer), then sort by Size and Price
    List<SaleItem> beerItems = [];
    List<SaleItem> nonBeerItems = [];

    if (sale.items != null) {
      for (var item in sale.items!) {
        if (_isBeer(item)) {
          beerItems.add(item);
        } else {
          nonBeerItems.add(item);
        }
      }

      // Sort each group by Size (high→low), then Price (low→high)
      beerItems.sort(_sizeAndPriceComparator);
      nonBeerItems.sort(_sizeAndPriceComparator);
    }

    // Combined sorted items for fallback
    List<SaleItem> sortedItems = [...beerItems, ...nonBeerItems];

    // Group items by size if needed (for grouped display - legacy)
    Map<String, List<SaleItem>> groupedItems = {};
    if (groupBySize && sale.items != null) {
      for (var item in sortedItems) {
        String size = _extractSize(item) ?? 'Other';
        if (!groupedItems.containsKey(size)) {
          groupedItems[size] = [];
        }
        groupedItems[size]!.add(item);
      }
      // Sort sizes high to low
      var sortedSizes = groupedItems.keys.toList()
        ..sort((a, b) {
          int aVal = _getSizeValue(a);
          int bVal = _getSizeValue(b);
          return bVal.compareTo(aVal);
        });
      groupedItems = Map.fromEntries(
        sortedSizes.map((key) => MapEntry(key, groupedItems[key]!))
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Section
          if (showHeader) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'SALE RECEIPT',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          '#${sale.saleNumber}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        DateFormat('dd MMM yy, hh:mm a').format(sale.saleDate),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  if (sale.customerName != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 12),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            sale.customerName!,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (sale.customerPhone != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.phone_outlined, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            sale.customerPhone!,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
          ],

          // Table Section
          Container(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Responsive Table Header
                _buildTableHeader(theme),

                const SizedBox(height: 4),

                // Table Body - Grouped by Category (Beer vs Non-Beer)
                // Beer Section
                if (beerItems.isNotEmpty)
                  _buildCategorySection(
                    context: context,
                    title: 'BEER',
                    icon: Icons.sports_bar,
                    color: Colors.amber[700]!,
                    items: beerItems,
                  ),

                // Non-Beer Section (IMFL/Whiskey/etc.) with SIZE SUBHEADINGS
                if (nonBeerItems.isNotEmpty)
                  _buildCategorySection(
                    context: context,
                    title: 'WHISKEY / IMFL',
                    icon: Icons.local_bar,
                    color: Colors.brown[600]!,
                    items: nonBeerItems,
                    showSizeSubheadings: true,  // Enable size subheadings for IMFL
                  ),

                // Summary Section
                const SizedBox(height: 8),
                Container(height: 1, color: cs.outlineVariant),
                const SizedBox(height: 6),

                // Subtotal and calculations - Compact
                _buildCompactSummaryRow('Subtotal', formatCurrency(sale.subTotal)),
                if (sale.discountAmount > 0)
                  _buildCompactSummaryRow('Discount', '- ${formatCurrency(sale.discountAmount)}', isDiscount: true),
                if (sale.taxAmount > 0)
                  _buildCompactSummaryRow('Tax', formatCurrency(sale.taxAmount)),

                const SizedBox(height: 4),

                // Grand Total - Prominent
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Grand Total',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatCurrency(sale.totalAmount),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.primaryColor,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Payment Details - Compact
                if (showPaymentDetails) ...[
                  const SizedBox(height: 8),
                  _buildCompactPaymentDetails(context),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Responsive table header with readable fonts
  /// Layout: Product | Open | Qty | Price | Total | Close
  Widget _buildTableHeader(ThemeData theme) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Product - Flexible, takes most space
          Expanded(
            flex: 4,
            child: Text(
              'Product',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
          ),
          // Opening Stock - Fixed small width (green theme)
          SizedBox(
            width: 32,
            child: Center(
              child: Text(
                'Open',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.green[700],
                ),
              ),
            ),
          ),
          // Qty - Fixed small width
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                'Qty',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Price - Flexible for better responsiveness
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Price',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Total - Flexible for better responsiveness
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Closing Stock - Fixed small width (blue theme)
          SizedBox(
            width: 32,
            child: Center(
              child: Text(
                'Close',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.blue[700],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Get AI insight for a product
  /// Matches by productId first, then falls back to product name + size matching
  ItemInsight? _getItemInsight(String? productId, String? productName) {
    if (aiValidation == null) return null;

    // First: Try exact productId match
    if (productId != null && productId.isNotEmpty) {
      try {
        final exactMatch = aiValidation!.perItemInsights.firstWhere(
          (insight) => insight.productId == productId,
        );
        return exactMatch;
      } catch (_) {
        // No exact match, continue to name matching
      }
    }

    // Second: Try matching by full product name (including size)
    if (productName != null && productName.isNotEmpty) {
      final fullNameLower = productName.toLowerCase().trim();

      try {
        // Try exact full name match first (including size like "Brand - 90ML")
        final exactNameMatch = aiValidation!.perItemInsights.firstWhere(
          (insight) => insight.productName.toLowerCase().trim() == fullNameLower,
        );
        return exactNameMatch;
      } catch (_) {
        // Continue to cleaned name matching
      }

      // Third: Try matching by cleaned product name (without size)
      final cleanName = _cleanProductName(productName).toLowerCase();
      try {
        // Try cleaned name match
        final nameMatch = aiValidation!.perItemInsights.firstWhere(
          (insight) => _cleanProductName(insight.productName).toLowerCase() == cleanName,
        );
        return nameMatch;
      } catch (_) {
        // Try partial name match (contains)
        try {
          final partialMatch = aiValidation!.perItemInsights.firstWhere(
            (insight) {
              final insightName = _cleanProductName(insight.productName).toLowerCase();
              // Check if core brand name matches
              return insightName.contains(cleanName) || cleanName.contains(insightName);
            },
          );
          return partialMatch;
        } catch (_) {
          // No match found
        }
      }

      // Fourth: Try size-aware matching (extract size from name and match)
      final sizeFromName = _extractSizeFromName(productName);
      if (sizeFromName != null) {
        try {
          final sizeMatch = aiValidation!.perItemInsights.firstWhere(
            (insight) {
              final insightSize = _extractSizeFromName(insight.productName);
              final insightBrand = _cleanProductName(insight.productName).toLowerCase();
              // Both brand AND size must match
              return insightSize == sizeFromName &&
                     (insightBrand.contains(cleanName) || cleanName.contains(insightBrand));
            },
          );
          return sizeMatch;
        } catch (_) {
          // No match found
        }
      }
    }

    return null;
  }

  /// Extract size value from product name (e.g., "Brand - 90ML" -> "90")
  String? _extractSizeFromName(String name) {
    final sizeRegex = RegExp(r'(\d+)\s*(?:ml|ML|Ml)', caseSensitive: false);
    final match = sizeRegex.firstMatch(name);
    return match?.group(1);
  }

  /// Clean product name for comparison (remove size suffixes)
  String _cleanProductName(String name) {
    return name
        .replaceAll(RegExp(r'\s*-\s*\d+\s*(?:ml|ML|Ml|ltr|LTR|L)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+\d+\s*(?:ml|ML|Ml|ltr|LTR|L)\s*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'^\d+\s*(?:ml|ML|Ml|ltr|LTR|L)\s*-?\s*', caseSensitive: false), '')
        .trim();
  }

  /// Get AI validation status color
  Color _getAIStatusColor(ItemInsight? insight) {
    if (insight == null) return Colors.transparent;
    if (insight.isCritical) return const Color(0xFFFF3B30); // Red
    if (insight.isWarning) return const Color(0xFFFF9500); // Orange
    if (insight.isMatched) return const Color(0xFF34C759); // Green
    return Colors.transparent;
  }

  /// Responsive table row that handles large values
  /// Layout: Product | Open | Qty | Price | Total | Close
  Widget _buildResponsiveTableRow(BuildContext context, SaleItem item, bool isEven) {
    final theme = Theme.of(context);

    // Get AI insight for this item - try productId first, then product name
    final insight = _getItemInsight(item.productId, item.productName);
    final hasAIStatus = insight != null;
    final aiColor = _getAIStatusColor(insight);

    // Clean product name (max 30 chars displayed)
    String cleanProductName(String? name) {
      if (name == null) return 'Product';
      String cleaned = name
          .replaceAll(RegExp(r'\s*-\s*\d+\s*(?:ml|ML|Ml|ltr|LTR|L)\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s+\d+\s*(?:ml|ML|Ml|ltr|LTR|L)\s*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'^\d+\s*(?:ml|ML|Ml|ltr|LTR|L)\s*-?\s*', caseSensitive: false), '')
          .trim();
      return cleaned.isNotEmpty ? cleaned : name;
    }

    // Compact price format for cells
    String formatPriceCompact(double price) {
      if (price >= 100000) {
        return '₹${(price / 1000).toStringAsFixed(0)}K';
      } else if (price >= 10000) {
        return '₹${(price / 1000).toStringAsFixed(1)}K';
      } else {
        return '₹${price.toStringAsFixed(0)}';
      }
    }

    // Compact total format (handles up to 8 digits)
    String formatTotalCompact(double total) {
      if (total >= 10000000) {
        return '₹${(total / 10000000).toStringAsFixed(1)}Cr';
      } else if (total >= 100000) {
        return '₹${(total / 100000).toStringAsFixed(1)}L';
      } else if (total >= 10000) {
        return '₹${(total / 1000).toStringAsFixed(1)}K';
      } else {
        return '₹${total.toStringAsFixed(0)}';
      }
    }

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: isEven ? cs.surface : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        // Add left border for AI status
        border: hasAIStatus ? Border(
          left: BorderSide(color: aiColor, width: 3),
        ) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // AI Status Indicator (clickable dot)
          if (hasAIStatus)
            GestureDetector(
              onTap: () {
                if (onAIStatusTap != null) {
                  onAIStatusTap!(item.productId, insight);
                }
              },
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: aiColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: aiColor.withOpacity(0.4),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  insight.isMatched
                      ? Icons.check
                      : insight.isCritical
                          ? Icons.close
                          : Icons.priority_high,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),

          // Product Name - Flexible with ellipsis
          Expanded(
            flex: 4,
            child: Text(
              cleanProductName(item.productName),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Opening Stock - Fixed width badge (green theme)
          SizedBox(
            width: 32,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${item.openingStock}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Quantity - Fixed width (handles 4 digits)
          SizedBox(
            width: 28,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${item.quantity}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Price - Flexible with auto-scaling
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatPriceCompact(item.unitPrice),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),

          // Total - Flexible with auto-scaling
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatTotalCompact(item.totalPrice),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.green[700],
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),

          // Closing Stock - Fixed width badge (blue theme)
          SizedBox(
            width: 32,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${item.closingStock}',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact summary row
  Widget _buildCompactSummaryRow(String label, String value, {bool isDiscount = false}) {
    return Builder(builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDiscount ? Colors.green[700] : cs.onSurface,
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Compact payment details
  Widget _buildCompactPaymentDetails(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, size: 18, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'Payment',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _getPaymentColor(sale.paymentMethod, cs).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  sale.paymentMethod.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _getPaymentColor(sale.paymentMethod, cs),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Paid:',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              Text(
                formatCurrency(sale.paidAmount),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          if (sale.dueAmount > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Due:',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                Text(
                  formatCurrency(sale.dueAmount),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String? _extractSize(SaleItem item) {
    if (item.size != null && item.size!.isNotEmpty) {
      return item.size;
    }

    if (item.productName != null) {
      final sizeRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML|ltr|LTR|L)', caseSensitive: false);
      final match = sizeRegex.firstMatch(item.productName!);
      if (match != null) {
        String size = match.group(0)!.toUpperCase();
        if (size.contains('LTR') || size.endsWith('L')) {
          final numMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(size);
          if (numMatch != null) {
            final liters = double.tryParse(numMatch.group(0)!) ?? 0;
            return '${(liters * 1000).toInt()}ML';
          }
        }
        return size.replaceAll(RegExp(r'\s+'), '');
      }
    }

    if (item.categoryName != null) {
      final sizeRegex = RegExp(r'(\d+(?:\.\d+)?)\s*(?:ml|ML)', caseSensitive: false);
      final match = sizeRegex.firstMatch(item.categoryName!);
      if (match != null) {
        return match.group(0)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
      }
    }

    return null;
  }

  int _getSizeValue(String size) {
    final numMatch = RegExp(r'(\d+)').firstMatch(size);
    if (numMatch != null) {
      return int.tryParse(numMatch.group(0)!) ?? 0;
    }
    return 0;
  }

  Color _getPaymentColor(String method, [ColorScheme? cs]) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'card':
        return Colors.blue;
      case 'upi':
        return Colors.purple;
      case 'credit':
        return Colors.orange;
      default:
        return cs?.onSurfaceVariant ?? const Color(0xFF9E9E9E);
    }
  }

  /// Build a size subheading divider
  Widget _buildSizeSubheading(String size, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        children: [
          Expanded(child: Divider(color: color.withOpacity(0.35), thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              size,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color.withOpacity(0.85),
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(child: Divider(color: color.withOpacity(0.35), thickness: 1)),
        ],
      ),
    );
  }

  /// Build a category section with header and items
  /// Header shows: Category Name | Total Opening | Items Count | Total Closing
  Widget _buildCategorySection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required List<SaleItem> items,
    bool showSizeSubheadings = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    // Calculate totals for this category
    final totalOpening = items.fold<int>(0, (sum, item) => sum + item.openingStock);
    final totalClosing = items.fold<int>(0, (sum, item) => sum + item.closingStock);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category Header with Stock Totals - Fully Responsive
        Container(
          margin: const EdgeInsets.only(bottom: 8, top: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: color,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Badges row - using Wrap for responsiveness
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.start,
                children: [
                  // Total Opening Stock Badge (green)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.login, size: 10, color: Colors.green[700]),
                        const SizedBox(width: 3),
                        Text(
                          '$totalOpening',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Items count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${items.length} items',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  // Total Closing Stock Badge (blue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout, size: 10, color: Colors.blue[700]),
                        const SizedBox(width: 3),
                        Text(
                          '$totalClosing',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Items table - with or without size subheadings
        if (showSizeSubheadings)
          ..._buildItemsWithSizeSubheadings(context, items, color)
        else
          ...items.asMap().entries.map((entry) =>
            _buildResponsiveTableRow(context, entry.value, entry.key % 2 == 0)
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Build items grouped by size with subheadings
  /// Consistent with Daily Sales Entry: Size groups (high→low), items sorted by Price (low→high)
  List<Widget> _buildItemsWithSizeSubheadings(BuildContext context, List<SaleItem> items, Color color) {
    // Group items by size
    Map<String, List<SaleItem>> sizeGroups = {};
    for (var item in items) {
      String size = _extractSize(item) ?? 'Other';
      sizeGroups.putIfAbsent(size, () => []).add(item);
    }

    // Sort size groups (high→low) - Consistent with Daily Sales Entry
    var sortedSizes = sizeGroups.keys.toList()
      ..sort((a, b) => _getSizeValue(b).compareTo(_getSizeValue(a)));

    List<Widget> widgets = [];
    int rowIndex = 0;

    for (var size in sortedSizes) {
      // Sort items within each size group by Price (low→high), then Brand
      final sizeItems = sizeGroups[size]!
        ..sort((a, b) {
          // Primary: Price (low to high)
          if (a.unitPrice != b.unitPrice) {
            return a.unitPrice.compareTo(b.unitPrice);
          }
          // Secondary: Brand name (alphabetical)
          final brandA = (a.brandName ?? a.productName ?? '').toLowerCase();
          final brandB = (b.brandName ?? b.productName ?? '').toLowerCase();
          return brandA.compareTo(brandB);
        });

      // Add size subheading
      widgets.add(_buildSizeSubheading(size, color));

      // Add items for this size
      for (var item in sizeItems) {
        widgets.add(_buildResponsiveTableRow(context, item, rowIndex % 2 == 0));
        rowIndex++;
      }

      // Add size group summary (Products, Qty, Amount)
      widgets.add(_buildSizeGroupSummary(sizeItems, color));
    }

    return widgets;
  }

  /// Build summary row for each size group
  /// Shows: Products | Total Open | # Qty | ₹ Total | Total Close
  Widget _buildSizeGroupSummary(List<SaleItem> items, Color color) {
    final totalProducts = items.length;
    final totalQty = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final totalAmount = items.fold<double>(0.0, (sum, item) => sum + item.totalPrice);
    final totalOpening = items.fold<int>(0, (sum, item) => sum + item.openingStock);
    final totalClosing = items.fold<int>(0, (sum, item) => sum + item.closingStock);

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 8,
        runSpacing: 6,
        children: [
          // Products count
          _buildSummaryChip(
            icon: Icons.inventory_2_outlined,
            label: 'Products',
            value: '$totalProducts',
            color: color,
          ),
          // Total Opening Stock (green)
          _buildSummaryChip(
            icon: Icons.login,
            label: 'Open',
            value: '$totalOpening',
            color: Colors.green[700]!,
          ),
          // Total Qty
          _buildSummaryChip(
            icon: Icons.numbers,
            label: 'Qty',
            value: '$totalQty',
            color: color,
          ),
          // Total Amount
          _buildSummaryChip(
            icon: Icons.currency_rupee,
            label: 'Total',
            value: '₹${totalAmount.toStringAsFixed(0)}',
            color: color,
            isPrimary: true,
          ),
          // Total Closing Stock (blue)
          _buildSummaryChip(
            icon: Icons.logout,
            label: 'Close',
            value: '$totalClosing',
            color: Colors.blue[700]!,
          ),
        ],
      ),
    );
  }

  /// Build individual summary chip
  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool isPrimary = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color.withOpacity(0.7)),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w500,
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: isPrimary ? 11 : 10,
              fontWeight: FontWeight.w700,
              color: isPrimary ? color : color.withOpacity(0.9),
            ),
          ),
        ),
      ],
    );
  }

  /// Check if item is Beer based on category or product name
  bool _isBeer(SaleItem item) {
    final category = (item.categoryName ?? '').toLowerCase();
    final productName = (item.productName ?? '').toLowerCase();

    // Check category name
    if (category.contains('beer') ||
        category.contains('lager') ||
        category.contains('ale') ||
        category.contains('stout')) {
      return true;
    }

    // Fallback: Check product name for common beer brands
    final beerBrands = [
      'kingfisher', 'budweiser', 'heineken', 'corona', 'carlsberg',
      'tuborg', 'bira', 'amstel', 'foster', 'miller', 'stella',
      'hoegaarden', 'bro code', 'haywards', 'knockout', 'godfather',
      'kalyani', 'simba', 'white owl', 'medusa', 'breezer'
    ];
    return beerBrands.any((brand) => productName.contains(brand));
  }

  /// Comparator for sorting by Price (low→high), then Brand, then Size (high→low)
  /// Consistent with Daily Sales Entry screen sorting logic
  int _sizeAndPriceComparator(SaleItem a, SaleItem b) {
    // Primary: Price (low to high) - Most common sales first
    if (a.unitPrice != b.unitPrice) {
      return a.unitPrice.compareTo(b.unitPrice); // Low to high
    }

    // Secondary: Brand name (alphabetical)
    final brandA = (a.brandName ?? a.productName ?? '').toLowerCase();
    final brandB = (b.brandName ?? b.productName ?? '').toLowerCase();
    if (brandA != brandB) {
      return brandA.compareTo(brandB);
    }

    // Tertiary: Size (high to low) - Larger sizes first for same brand/price
    final sizeA = _getSizeValue(_extractSize(a) ?? '0');
    final sizeB = _getSizeValue(_extractSize(b) ?? '0');
    return sizeB.compareTo(sizeA); // High to low
  }
}

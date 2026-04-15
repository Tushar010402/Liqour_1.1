/// Size range grouping constants — used across inventory, sales, brand onboarding
/// Beer has different ranges than spirits (non-beer)
class SizeRangeConstants {
  SizeRangeConstants._();

  static const beerRanges = [
    SizeRange(label: '330ml & Below', minMl: 0, maxMl: 400, sort: 1),
    SizeRange(label: '500ml', minMl: 401, maxMl: 550, sort: 2),
    SizeRange(label: '650ml', minMl: 551, maxMl: 999, sort: 3),
    SizeRange(label: 'Keg/Bulk', minMl: 1000, maxMl: 999999, sort: 4),
  ];

  static const nonBeerRanges = [
    SizeRange(label: '90ml (Nip)', minMl: 0, maxMl: 100, sort: 1),
    SizeRange(label: '180ml (Quarter)', minMl: 101, maxMl: 250, sort: 2),
    SizeRange(label: '375ml (Half)', minMl: 251, maxMl: 400, sort: 3),
    SizeRange(label: '750ml (Full)', minMl: 401, maxMl: 999, sort: 4),
    SizeRange(label: '1L+ (Large)', minMl: 1000, maxMl: 999999, sort: 5),
  ];

  /// Get ranges for a category
  static List<SizeRange> rangesFor(String category) {
    return category.toLowerCase().contains('beer') ? beerRanges : nonBeerRanges;
  }

  /// Extract ml value from size string (e.g., "375ML" → 375, "1L" → 1000)
  static int extractMl(String size) {
    final numStr = size.replaceAll(RegExp(r'[^0-9]'), '');
    final num = int.tryParse(numStr) ?? 0;
    if (size.toUpperCase().contains('L') && !size.toUpperCase().contains('ML') && num < 100) {
      return num * 1000;
    }
    return num;
  }

  /// Get the range label for a given size and category
  static String? getRangeLabel(String size, String category) {
    final ml = extractMl(size);
    for (final range in rangesFor(category)) {
      if (ml >= range.minMl && ml <= range.maxMl) return range.label;
    }
    return null;
  }

  /// Check if a size falls within a specific range
  static bool sizeMatchesRange(String size, String rangeLabel, String category) {
    final ml = extractMl(size);
    for (final range in rangesFor(category)) {
      if (range.label == rangeLabel && ml >= range.minMl && ml <= range.maxMl) return true;
    }
    return false;
  }

  /// Get all actual sizes from a list that fall within a range
  static List<String> actualSizesInRange(String rangeLabel, String category, Iterable<String> allSizes) {
    final matching = <String>{};
    for (final size in allSizes) {
      if (sizeMatchesRange(size, rangeLabel, category)) matching.add(size.toUpperCase());
    }
    final sorted = matching.toList()..sort((a, b) => extractMl(a).compareTo(extractMl(b)));
    return sorted;
  }
}

class SizeRange {
  final String label;
  final int minMl;
  final int maxMl;
  final int sort;
  const SizeRange({required this.label, required this.minMl, required this.maxMl, required this.sort});
}

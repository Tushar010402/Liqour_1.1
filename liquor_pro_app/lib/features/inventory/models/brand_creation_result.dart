/// Result of batch brand creation from OCR
class BrandCreationResult {
  final int totalItems;
  final int successCount;
  final int failureCount;
  final List<String> createdBrandIds;
  final List<String> errors;
  final int totalStockCreated;

  BrandCreationResult({
    required this.totalItems,
    required this.successCount,
    required this.failureCount,
    required this.createdBrandIds,
    required this.errors,
    this.totalStockCreated = 0,
  });

  bool get hasErrors => errors.isNotEmpty;
  bool get isPartialSuccess => successCount > 0 && failureCount > 0;
  bool get isCompleteSuccess => successCount > 0 && failureCount == 0;
  bool get isCompleteFailed => successCount == 0 && failureCount > 0;

  String get summaryMessage {
    if (isCompleteSuccess) {
      return 'Successfully created $successCount brands with $totalStockCreated units';
    } else if (isPartialSuccess) {
      return 'Created $successCount brands, $failureCount failed';
    } else if (isCompleteFailed) {
      return 'Failed to create all $failureCount brands';
    }
    return 'No brands created';
  }
}

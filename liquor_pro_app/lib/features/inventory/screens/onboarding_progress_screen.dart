import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/services/dio_api_service.dart';
import '../../../core/providers/shop_selection_provider.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../services/brand_catalog_service.dart';
import '../providers/brand_selection_provider.dart';

/// Shows real-time progress of brand onboarding
/// Displays item-by-item status with success/error indicators
class OnboardingProgressScreen extends StatefulWidget {
  const OnboardingProgressScreen({super.key});

  @override
  State<OnboardingProgressScreen> createState() => _OnboardingProgressScreenState();
}

class _OnboardingProgressScreenState extends State<OnboardingProgressScreen> {
  late final BrandCatalogService _brandService;

  bool _isOnboarding = false;
  bool _isComplete = false;
  bool _hasError = false;

  double _progress = 0.0;
  String _currentStep = 'Preparing...';

  final List<OnboardingItem> _items = [];
  int _processedCount = 0;
  int _successCount = 0;
  int _errorCount = 0;

  @override
  void initState() {
    super.initState();
    _brandService = BrandCatalogService(context.read<DioApiService>());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startOnboarding();
    });
  }

  Future<void> _startOnboarding() async {
    final provider = context.read<BrandSelectionProvider>();
    final payload = provider.getOnboardingPayload();
    final brandIds = payload['brand_ids'] as List<String>;
    final variantIds = payload['variant_ids'] as List<String>;

    if (variantIds.isEmpty) {
      setState(() {
        _hasError = true;
        _isComplete = true;
        _currentStep = 'No variants selected';
      });
      return;
    }

    // Get current shop ID for stock creation
    final shopProvider = context.read<ShopSelectionProvider>();
    final shopId = shopProvider.selectedShopId;

    // Create default stock quantities (0 for all variants)
    // This ensures Stock records are created even with 0 quantity
    final variantStockQuantities = <String, int>{};
    for (var variantId in variantIds) {
      variantStockQuantities[variantId] = 0; // Default to 0 stock
    }

    setState(() {
      _isOnboarding = true;
      _currentStep = 'Preparing to onboard ${variantIds.length} variants from ${brandIds.length} brands...';

      // Create items list for tracking (one per variant)
      for (var i = 0; i < variantIds.length; i++) {
        _items.add(OnboardingItem(
          id: variantIds[i],
          name: 'Variant ${i + 1}',
          status: OnboardingStatus.pending,
        ));
      }
    });

    // Simulate progress updates (in real scenario, this would be streamed from backend)
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      setState(() {
        _currentStep = 'Onboarding ${variantIds.length} variants to ${shopProvider.selectedShopName ?? "shop"}...';
      });

      // Call the onboarding API with shop_id and initial stock
      final response = await _brandService.onboardBrands(
        brandIds: brandIds,
        variantIds: variantIds,
        shopId: shopId, // Pass current shop ID
        variantStockQuantities: variantStockQuantities, // Pass stock quantities
      );

      // Parse response and update items
      // Backend returns { onboarded_products, onboarded_brands, brand_details: [...] }
      final onboardedProducts = response['onboarded_products'] as int? ?? 0;
      final brandDetails = response['brand_details'] as List? ?? [];

      // Extract all product IDs from brand_details
      List<String> createdProductIds = [];
      for (var detail in brandDetails) {
        if (detail is Map<String, dynamic>) {
          final productIds = detail['product_ids'] as List? ?? [];
          for (var id in productIds) {
            createdProductIds.add(id.toString());
          }
        }
      }

      // Simulate item-by-item processing with animation
      for (var i = 0; i < _items.length; i++) {
        await Future.delayed(const Duration(milliseconds: 100));

        setState(() {
          // Mark as success if we have corresponding product
          final isSuccess = i < createdProductIds.length;

          // Update item ID to actual product ID if available
          final productId = isSuccess ? createdProductIds[i] : _items[i].id;

          _items[i] = _items[i].copyWith(
            id: productId,
            status: isSuccess ? OnboardingStatus.success : OnboardingStatus.error,
            message: isSuccess ? 'Successfully onboarded' : 'Failed to onboard',
          );

          _processedCount = i + 1;
          _progress = (_processedCount / _items.length);

          if (isSuccess) {
            _successCount++;
          } else {
            _errorCount++;
          }

          _currentStep = 'Processing... $_processedCount/${_items.length}';
        });
      }

      setState(() {
        _isOnboarding = false;
        _isComplete = true;
        _hasError = _errorCount > 0;
        _currentStep = _hasError
            ? 'Completed with errors'
            : 'Successfully onboarded all variants!';
      });

      // Clear selection on success
      if (_errorCount == 0) {
        provider.clearAll();
      }

    } catch (e) {
      setState(() {
        _isOnboarding = false;
        _isComplete = true;
        _hasError = true;
        _currentStep = 'Onboarding failed';

        // Mark all remaining items as error
        for (var i = 0; i < _items.length; i++) {
          if (_items[i].status == OnboardingStatus.pending) {
            _items[i] = _items[i].copyWith(
              status: OnboardingStatus.error,
              message: e.toString(),
            );
            _errorCount++;
          }
        }
      });
    }
  }

  List<String> _extractProductIds() {
    // Extract all product IDs from successful onboarding
    List<String> productIds = [];
    // Product IDs are stored in _items (would be set during processing)
    for (var item in _items) {
      if (item.status == OnboardingStatus.success) {
        productIds.add(item.id);
      }
    }
    return productIds;
  }

  void _finish() {
    // Get all successfully onboarded product IDs
    final productIds = _extractProductIds();

    // Navigate back and potentially show initial stock screen
    // For now, just pop back to main screen
    Navigator.of(context).popUntil((route) => route.isFirst);

    // TODO: Optionally navigate to initial stock screen with productIds
    // if (productIds.isNotEmpty) {
    //   Navigator.push(context, MaterialPageRoute(
    //     builder: (context) => InitialStockScreen(productIds: productIds),
    //   ));
    // }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _isComplete,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: CustomAppBar(
          title: 'Onboarding Progress',
          leading: _isComplete
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _finish,
                )
              : null,
        ),
        body: Column(
          children: [
            // Progress header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Status icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isComplete
                          ? (_hasError ? AppColors.error : AppColors.success)
                              .withValues(alpha:0.1)
                          : cs.primary.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: _isOnboarding
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          )
                        : Icon(
                            _isComplete
                                ? (_hasError ? Icons.error : Icons.check_circle)
                                : Icons.cloud_upload,
                            size: 48,
                            color: _isComplete
                                ? (_hasError ? AppColors.error : AppColors.success)
                                : cs.primary,
                          ),
                  ),

                  const SizedBox(height: 16),

                  // Current step
                  Text(
                    _currentStep,
                    style: AppTextStyles.h6,
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Progress stats
                  if (_items.isNotEmpty)
                    Text(
                      '$_processedCount of ${_items.length} items processed',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _hasError ? AppColors.error : cs.primary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Success/Error counts
                  if (_processedCount > 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_successCount > 0) ...[
                          Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_successCount Success',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (_successCount > 0 && _errorCount > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: cs.onSurfaceVariant,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        if (_errorCount > 0) ...[
                          Icon(
                            Icons.error,
                            size: 16,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_errorCount Failed',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Item list
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _items.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return _buildItemCard(_items[index], index);
                      },
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _isComplete
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _finish,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasError ? AppColors.error : AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _hasError ? 'Done (with errors)' : 'Done',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildItemCard(OnboardingItem item, int index) {
    final cs = Theme.of(context).colorScheme;
    Color statusColor;
    IconData statusIcon;

    switch (item.status) {
      case OnboardingStatus.pending:
        statusColor = cs.onSurfaceVariant;
        statusIcon = Icons.pending;
        break;
      case OnboardingStatus.processing:
        statusColor = cs.primary;
        statusIcon = Icons.sync;
        break;
      case OnboardingStatus.success:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
        break;
      case OnboardingStatus.error:
        statusColor = AppColors.error;
        statusIcon = Icons.error;
        break;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 20)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Card(
        child: ListTile(
          leading: item.status == OnboardingStatus.processing
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                )
              : Icon(
                  statusIcon,
                  color: statusColor,
                  size: 24,
                ),
          title: Text(
            item.name,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: item.message != null
              ? Text(
                  item.message!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: item.status == OnboardingStatus.error
                        ? AppColors.error
                        : cs.onSurfaceVariant,
                  ),
                )
              : null,
          trailing: item.status == OnboardingStatus.success
              ? Icon(Icons.check, color: AppColors.success)
              : item.status == OnboardingStatus.error
                  ? Icon(Icons.close, color: AppColors.error)
                  : null,
        ),
      ),
    );
  }
}

/// Status of an onboarding item
enum OnboardingStatus {
  pending,
  processing,
  success,
  error,
}

/// Represents a single item being onboarded
class OnboardingItem {
  final String id;
  final String name;
  final OnboardingStatus status;
  final String? message;

  OnboardingItem({
    required this.id,
    required this.name,
    required this.status,
    this.message,
  });

  OnboardingItem copyWith({
    String? id,
    String? name,
    OnboardingStatus? status,
    String? message,
  }) {
    return OnboardingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

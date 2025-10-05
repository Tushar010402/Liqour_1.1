import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../models/shop_model.dart';
import '../providers/shop_provider.dart';
import 'shop_form_screen.dart';
import '../../../core/utils/logger.dart';

/// Shops Management Screen
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});

  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  @override
  void initState() {
    super.initState();
    Logger.debug('🏪 ShopsScreen initState called');
    // Load shops when screen is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.debug('🏪 ShopsScreen: About to call loadShops()');
      context.read<ShopProvider>().loadShops();
    });
  }

  Future<void> _loadShops() async {
    await context.read<ShopProvider>().loadShops();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShopProvider>(
      builder: (context, shopProvider, _) {
        // Check for authentication errors
        if (shopProvider.errorMessage != null &&
            (shopProvider.errorMessage!.contains('Session expired') ||
             shopProvider.errorMessage!.contains('Authorization'))) {
          return Scaffold(
            appBar: const CustomAppBar(
              title: 'Manage Shops',
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Session Expired',
                      style: AppTextStyles.h3,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your session has expired. Please login again to continue.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () async {
                        await context.read<AuthProvider>().logout();
                        if (context.mounted) {
                          context.go('/phone-login');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Login Again',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: const CustomAppBar(
            title: 'Manage Shops',
          ),
          body: shopProvider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : shopProvider.errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Error',
                              style: AppTextStyles.h3,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              shopProvider.errorMessage!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loadShops,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                              ),
                              child: const Text(
                                'Retry',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : shopProvider.shops.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.store_outlined,
                          title: 'No Shops',
                          message: 'Add your first shop location to get started',
                        )
                      : RefreshIndicator(
                          onRefresh: _loadShops,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: shopProvider.shops.length,
                            itemBuilder: (context, index) {
                              final shop = shopProvider.shops[index];
                              return _buildShopCard(shop);
                            },
                          ),
                        ),
          floatingActionButton: shopProvider.errorMessage == null
              ? FloatingActionButton.extended(
                  heroTag: 'shops_fab',
                  onPressed: () async {
                    // Navigate to add shop screen
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ShopFormScreen(),
                      ),
                    );
                    // Reload shops if a shop was created
                    if (result == true && context.mounted) {
                      await context.read<ShopProvider>().loadShops();
                    }
                  },
                  backgroundColor: AppColors.primary,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Add Shop', style: TextStyle(color: Colors.white)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildShopCard(Shop shop) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        onTap: () async {
          // Navigate to edit shop screen
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ShopFormScreen(shop: shop),
            ),
          );
          // Reload shops if a shop was updated
          if (result == true && context.mounted) {
            await context.read<ShopProvider>().loadShops();
          }
        },
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: shop.isActive
                ? AppColors.primary.withOpacity(0.1)
                : AppColors.textSecondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.store,
            color: shop.isActive ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        title: Text(
          shop.name,
          style: AppTextStyles.bodyLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    shop.address,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.phone_outlined,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  shop.phone,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: shop.isActive
                    ? AppColors.success.withOpacity(0.1)
                    : AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                shop.isActive ? 'Active' : 'Inactive',
                style: AppTextStyles.bodySmall.copyWith(
                  color: shop.isActive ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

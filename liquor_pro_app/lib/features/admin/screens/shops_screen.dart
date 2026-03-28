import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state_widget.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/permissions/providers/permission_provider.dart';
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
    final cs = Theme.of(context).colorScheme;
    return Consumer2<ShopProvider, PermissionProvider>(
      builder: (context, shopProvider, permissions, _) {
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
                        color: cs.onSurfaceVariant,
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
                        backgroundColor: cs.primary,
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
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loadShops,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cs.primary,
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
                              return _buildShopCard(shop, permissions);
                            },
                          ),
                        ),
          // Permission-gated FAB - only show for admin/manager/saas_admin
          floatingActionButton: shopProvider.errorMessage == null && permissions.canAccessShopManagement
              ? FloatingActionButton.extended(
                  heroTag: 'shops_fab',
                  onPressed: () async {
                    // Navigate to add shop screen
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ShopFormScreen(),
                      ),
                    );
                    // Refresh local list to sync with global provider
                    if (context.mounted) {
                      await context.read<ShopProvider>().loadShops();
                    }
                  },
                  backgroundColor: cs.primary,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Add Shop', style: TextStyle(color: Colors.white)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildShopCard(Shop shop, PermissionProvider permissions) {
    final cs = Theme.of(context).colorScheme;
    final canManage = permissions.canAccessShopManagement;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        onTap: canManage
            ? () async {
                // Navigate to edit shop screen
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShopFormScreen(shop: shop),
                  ),
                );
                // Refresh local list to sync with global provider
                if (context.mounted) {
                  await context.read<ShopProvider>().loadShops();
                }
              }
            : null, // Read-only for non-admins
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: shop.isActive
                ? cs.primary.withValues(alpha: 0.1)
                : cs.onSurfaceVariant.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.store,
            color: shop.isActive ? cs.primary : cs.onSurfaceVariant,
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
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    shop.address,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: cs.onSurfaceVariant,
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
                Icon(
                  Icons.phone_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  shop.phone,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: shop.isActive
                    ? AppColors.success.withValues(alpha:0.1)
                    : AppColors.error.withValues(alpha:0.1),
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
            // Actions menu (only for users with shop management access)
            if (canManage)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      _navigateToEdit(shop);
                      break;
                    case 'toggle':
                      _toggleShopStatus(shop);
                      break;
                    case 'delete':
                      _showDeleteConfirmation(shop);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          shop.isActive ? Icons.block : Icons.check_circle,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(shop.isActive ? 'Deactivate' : 'Activate'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Navigate to edit shop screen
  Future<void> _navigateToEdit(Shop shop) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopFormScreen(shop: shop),
      ),
    );
    if (context.mounted) {
      await context.read<ShopProvider>().loadShops();
    }
  }

  /// Toggle shop active status
  Future<void> _toggleShopStatus(Shop shop) async {
    final shopProvider = context.read<ShopProvider>();
    final success = await shopProvider.updateShop(
      shopId: shop.id,
      name: shop.name,
      address: shop.address,
      phone: shop.phone,
      email: shop.email,
      licenseNumber: shop.licenseNumber,
      licenseFile: shop.licenseFile,
      latitude: shop.latitude,
      longitude: shop.longitude,
      isActive: !shop.isActive,
    );

    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shop ${shop.isActive ? 'deactivated' : 'activated'} successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(shopProvider.errorMessage ?? 'Failed to update shop'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(Shop shop) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Shop'),
        content: Text('Are you sure you want to delete "${shop.name}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final shopProvider = context.read<ShopProvider>();
              final success = await shopProvider.deleteShop(shop.id);

              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Shop deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(shopProvider.errorMessage ?? 'Failed to delete shop'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

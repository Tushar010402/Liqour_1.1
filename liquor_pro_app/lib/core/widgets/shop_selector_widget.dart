import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/shop_selection_provider.dart';

/// Reusable Shop Selector Widget
/// Can be placed in any screen to allow shop selection
class ShopSelectorWidget extends StatelessWidget {
  final bool showLabel;
  final EdgeInsetsGeometry? padding;
  final ValueChanged<String?>? onShopChanged;

  const ShopSelectorWidget({
    super.key,
    this.showLabel = true,
    this.padding,
    this.onShopChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<ShopSelectionProvider>(
      builder: (context, shopProvider, child) {
        if (shopProvider.isLoading && shopProvider.shops.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (shopProvider.shops.isEmpty) {
          return Padding(
            padding: padding ?? const EdgeInsets.all(16.0),
            child: Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No shops available. Please create a shop first.',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Find selected shop for address display
        final selectedShop = shopProvider.selectedShopId != null
            ? shopProvider.shops.firstWhere(
                (shop) => shop.id == shopProvider.selectedShopId,
                orElse: () => shopProvider.shops.first,
              )
            : null;

        return Padding(
          padding: padding ?? const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showLabel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.store,
                        size: 14,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Shop',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      // Refresh button with better tap target
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            await shopProvider.refreshShops();
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              Icons.refresh,
                              size: 18,
                              color: cs.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // Modern dropdown with flexible height
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                constraints: const BoxConstraints(
                  minHeight: 48, // Material Design minimum touch target
                  // No maxHeight - let Flutter's layout system determine height based on content
                ),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outline,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: shopProvider.selectedShopId,
                    isExpanded: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    isDense: false,
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: cs.primary,
                      size: 24,
                    ),
                    hint: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.store,
                            size: 18,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Choose a shop',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    selectedItemBuilder: (BuildContext context) {
                      // Remove duplicates for selected item display
                      final seenIds = <String>{};
                      final uniqueShops = shopProvider.shops.where((shop) {
                        if (seenIds.contains(shop.id)) return false;
                        seenIds.add(shop.id);
                        return true;
                      }).toList();

                      return uniqueShops.map((shop) {
                        return Row(
                          children: [
                            // Shop icon with colored background
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.store,
                                size: 18,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Shop name and address
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    shop.name,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  if (shop.address.isNotEmpty)
                                    Text(
                                      shop.address,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.onSurfaceVariant,
                                        height: 1.2,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                    items: () {
                      // Remove duplicate shops by ID
                      final seenIds = <String>{};
                      final uniqueShops = shopProvider.shops.where((shop) {
                        if (seenIds.contains(shop.id)) return false;
                        seenIds.add(shop.id);
                        return true;
                      }).toList();

                      return uniqueShops.map((shop) {
                        final isSelected = shopProvider.selectedShopId == shop.id;
                        return DropdownMenuItem<String>(
                          value: shop.id,
                          child: Row(
                            children: [
                              // Shop icon
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cs.primary.withValues(alpha: 0.15)
                                      : cs.onSurfaceVariant.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.store,
                                  size: 18,
                                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Shop details
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      shop.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        color: isSelected ? cs.primary : cs.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (shop.address.isNotEmpty)
                                      Text(
                                        shop.address,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                  ],
                                ),
                              ),
                              // Selection indicator
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: cs.primary,
                                  size: 20,
                                ),
                            ],
                          ),
                        );
                      }).toList();
                    }(),
                    onChanged: (String? newShopId) async {
                      if (newShopId != null) {
                        final shop = shopProvider.shops.firstWhere(
                          (s) => s.id == newShopId,
                        );
                        await shopProvider.selectShop(shop);

                        // Notify parent widget
                        if (onShopChanged != null) {
                          onShopChanged!(newShopId);
                        }
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

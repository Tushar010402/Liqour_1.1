import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../admin/models/shop_model.dart';
import '../../admin/services/shop_service.dart';
import '../../../core/services/dio_api_service.dart';

/// Professional Shop Selector Widget
/// Allows users to select one or multiple shops for inventory operations
class ShopSelectorWidget extends StatefulWidget {
  final Function(Shop?) onShopSelected;
  final Function(List<Shop>)? onMultipleShopsSelected;
  final bool allowMultiple;
  final Shop? selectedShop;
  final List<Shop>? selectedShops;
  final String? hint;
  final bool isRequired;
  final bool showShopDetails;

  const ShopSelectorWidget({
    super.key,
    required this.onShopSelected,
    this.onMultipleShopsSelected,
    this.allowMultiple = false,
    this.selectedShop,
    this.selectedShops,
    this.hint,
    this.isRequired = false,
    this.showShopDetails = true,
  });

  @override
  State<ShopSelectorWidget> createState() => _ShopSelectorWidgetState();
}

class _ShopSelectorWidgetState extends State<ShopSelectorWidget>
    with SingleTickerProviderStateMixin {
  late ShopService _shopService;
  List<Shop> _availableShops = [];
  bool _isLoading = true;
  String? _error;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _hasLoadedShops = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shopService = ShopService(context.read<DioApiService>());

    // Load shops once after service is initialized
    if (!_hasLoadedShops) {
      _hasLoadedShops = true;
      _loadShops();
    }
  }

  Future<void> _loadShops() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final response = await _shopService.getShops();

      if (response.success && response.data != null) {
        setState(() {
          _availableShops = response.data!;
          _isLoading = false;
        });
        _animationController.forward();
      } else {
        setState(() {
          _error = response.message ?? 'Failed to load shops';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading shops: $e';
        _isLoading = false;
      });
    }
  }

  void _showShopSelectionModal() {
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ShopSelectionModal(
        shops: _availableShops,
        selectedShop: widget.selectedShop,
        selectedShops: widget.selectedShops ?? [],
        allowMultiple: widget.allowMultiple,
        showShopDetails: widget.showShopDetails,
        onShopSelected: (shop) {
          widget.onShopSelected(shop);
          Navigator.pop(context);
        },
        onMultipleShopsSelected: widget.allowMultiple
            ? (shops) {
                widget.onMultipleShopsSelected?.call(shops);
                Navigator.pop(context);
              }
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(color: AppColors.error, fontSize: 14),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadShops,
              color: AppColors.error,
            ),
          ],
        ),
      );
    }

    final hasSelection = widget.allowMultiple
        ? (widget.selectedShops?.isNotEmpty ?? false)
        : widget.selectedShop != null;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: InkWell(
        onTap: _availableShops.isNotEmpty ? _showShopSelectionModal : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(
              color: hasSelection ? cs.primary : cs.outlineVariant,
              width: hasSelection ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: hasSelection
                ? [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasSelection
                      ? cs.primary.withValues(alpha: 0.1)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.store,
                  color: hasSelection ? cs.primary : cs.onSurfaceVariant,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasSelection) ...[
                      Text(
                        widget.hint ?? 'Select Shop${widget.allowMultiple ? "(s)" : ""}',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                      if (widget.isRequired)
                        Text(
                          'Required',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ] else ...[
                      if (widget.allowMultiple && widget.selectedShops != null) ...[
                        Text(
                          '${widget.selectedShops!.length} shop${widget.selectedShops!.length > 1 ? "s" : ""} selected',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.selectedShops!.map((s) => s.name).join(', '),
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ] else if (widget.selectedShop != null) ...[
                        Text(
                          widget.selectedShop!.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: cs.onSurface,
                          ),
                        ),
                        if (widget.showShopDetails) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.selectedShop!.address,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: hasSelection ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shop Selection Modal
class _ShopSelectionModal extends StatefulWidget {
  final List<Shop> shops;
  final Shop? selectedShop;
  final List<Shop> selectedShops;
  final bool allowMultiple;
  final bool showShopDetails;
  final Function(Shop) onShopSelected;
  final Function(List<Shop>)? onMultipleShopsSelected;

  const _ShopSelectionModal({
    required this.shops,
    this.selectedShop,
    required this.selectedShops,
    required this.allowMultiple,
    required this.showShopDetails,
    required this.onShopSelected,
    this.onMultipleShopsSelected,
  });

  @override
  State<_ShopSelectionModal> createState() => _ShopSelectionModalState();
}

class _ShopSelectionModalState extends State<_ShopSelectionModal> {
  late List<Shop> _tempSelectedShops;
  late TextEditingController _searchController;
  List<Shop> _filteredShops = [];

  @override
  void initState() {
    super.initState();
    _tempSelectedShops = List.from(widget.selectedShops);
    _searchController = TextEditingController();
    _filteredShops = widget.shops;
    _searchController.addListener(_filterShops);
  }

  void _filterShops() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredShops = widget.shops.where((shop) {
        return shop.name.toLowerCase().contains(query) ||
               shop.address.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * 0.75;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.allowMultiple ? 'Select Shops' : 'Select Shop',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                    if (widget.allowMultiple)
                      TextButton(
                        onPressed: _tempSelectedShops.isNotEmpty
                            ? () => widget.onMultipleShopsSelected?.call(_tempSelectedShops)
                            : null,
                        child: Text(
                          'Done (${_tempSelectedShops.length})',
                          style: TextStyle(
                            color: _tempSelectedShops.isNotEmpty
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Search field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search shops...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          // Shop list
          Flexible(
            child: _filteredShops.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: cs.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No shops found',
                          style: TextStyle(
                            fontSize: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredShops.length,
                    itemBuilder: (context, index) {
                      final shop = _filteredShops[index];
                      final isSelected = widget.allowMultiple
                          ? _tempSelectedShops.contains(shop)
                          : widget.selectedShop?.id == shop.id;

                      return ListTile(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (widget.allowMultiple) {
                            setState(() {
                              if (isSelected) {
                                _tempSelectedShops.remove(shop);
                              } else {
                                _tempSelectedShops.add(shop);
                              }
                            });
                          } else {
                            widget.onShopSelected(shop);
                          }
                        },
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSelected
                                  ? [cs.primary, cs.primary.withValues(alpha: 0.8)]
                                  : [cs.surfaceContainerHighest, cs.outlineVariant],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.store,
                            color: isSelected ? Colors.white : cs.onSurfaceVariant,
                            size: 24,
                          ),
                        ),
                        title: Text(
                          shop.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? cs.primary : cs.onSurface,
                          ),
                        ),
                        subtitle: widget.showShopDetails
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    shop.address,
                                    style: const TextStyle(fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    shop.phone,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                        trailing: widget.allowMultiple
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      _tempSelectedShops.add(shop);
                                    } else {
                                      _tempSelectedShops.remove(shop);
                                    }
                                  });
                                },
                                activeColor: cs.primary,
                              )
                            : isSelected
                                ? Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  )
                                : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

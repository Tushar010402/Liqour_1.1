import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/category_model.dart';
import '../../../core/utils/text_input_utils.dart';
import '../controllers/category_provider.dart';
import 'category_form_screen.dart';
import 'subcategory_form_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategoryFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Update FAB when tab changes
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: _buildAppBar(),
      body: Consumer<CategoryProvider>(
        builder: (context, provider, child) {
          return Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(child: _buildTabBarView(provider)),
            ],
          );
        },
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.primaryBlack,
      title: const Text(
        'Category Management',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          onPressed: () => context.read<CategoryProvider>().refresh(),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.white,
      child: Column(
        children: [
          _buildSearchBar(),
          const SizedBox(height: 12),
          _buildStatsRow(),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextInputUtils.buildTextField(
      controller: _searchController,
      hintText: 'Search categories...',
      prefixIcon: const Icon(Icons.search),
      decoration: InputDecoration(
        hintText: 'Search categories...',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: AppColors.lightGray,
      ),
      onChanged: (value) {
        context.read<CategoryProvider>().updateSearchTerm(value);
      },
    );
  }

  Widget _buildStatsRow() {
    return Consumer<CategoryProvider>(
      builder: (context, provider, child) {
        final stats = provider.statistics;
        return Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Categories',
                (stats['total_categories'] ?? 0).toString(),
                AppColors.primaryRed,
                Icons.category,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Subcategories',
                (stats['total_subcategories'] ?? 0).toString(),
                AppColors.primaryBlue,
                Icons.subdirectory_arrow_right,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Active',
                (stats['active_categories'] ?? 0).toString(),
                AppColors.success,
                Icons.check_circle,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.white,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppColors.primaryRed,
        labelColor: AppColors.primaryRed,
        unselectedLabelColor: AppColors.mediumGray,
        tabs: const [
          Tab(text: 'Categories'),
          Tab(text: 'Subcategories'),
        ],
      ),
    );
  }

  Widget _buildTabBarView(CategoryProvider provider) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildCategoriesTab(provider),
        Column(
          children: [
            _buildCategoryFilter(provider),
            Expanded(child: _buildSubcategoriesTab(provider)),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoriesTab(CategoryProvider provider) {
    if (provider.isLoading && provider.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.hasError) {
      return _buildErrorState(provider);
    }

    if (provider.categories.isEmpty) {
      return _buildEmptyState('No categories found', 'Add your first category');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: provider.categories.length,
      itemBuilder: (context, index) {
        final category = provider.categories[index];
        return _buildCategoryCard(category);
      },
    );
  }

  Widget _buildSubcategoriesTab(CategoryProvider provider) {
    if (provider.isLoading && provider.subcategories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.hasError) {
      return _buildErrorState(provider);
    }

    // Filter subcategories by selected category
    final filteredSubcategories = _selectedCategoryFilter == 'All'
        ? provider.subcategories
        : provider.subcategories.where((subcategory) {
            final parentCategory = provider.getCategoryById(subcategory.categoryId);
            return parentCategory?.name == _selectedCategoryFilter;
          }).toList();

    if (filteredSubcategories.isEmpty) {
      return _buildEmptyState(
          'No subcategories found',
          _selectedCategoryFilter == 'All'
              ? 'Add your first subcategory'
              : 'No subcategories in $_selectedCategoryFilter category');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredSubcategories.length,
      itemBuilder: (context, index) {
        final subcategory = filteredSubcategories[index];
        return _buildSubcategoryCard(subcategory, provider);
      },
    );
  }

  // Generate color for category based on name
  Color _getCategoryColor(String categoryName) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.lime,
    ];
    final hash = categoryName.hashCode;
    return colors[hash % colors.length];
  }

  Widget _buildCategoryFilter(CategoryProvider provider) {
    final categories = ['All', ...provider.categories.map((c) => c.name)];

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter by Category',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final categoryName = categories[index];
                final isSelected = _selectedCategoryFilter == categoryName;
                final categoryColor = categoryName == 'All'
                    ? AppColors.primaryRed
                    : _getCategoryColor(categoryName);

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(categoryName),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategoryFilter = categoryName;
                      });
                    },
                    backgroundColor: categoryColor.withValues(alpha: 0.1),
                    selectedColor: categoryColor.withValues(alpha: 0.2),
                    checkmarkColor: categoryColor,
                    labelStyle: TextStyle(
                      color: isSelected ? categoryColor : Colors.black87,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected ? categoryColor : categoryColor.withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(Category category) {
    final categoryColor = _getCategoryColor(category.name);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: categoryColor.withValues(alpha: 0.05),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: categoryColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: ListTile(
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: categoryColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: category.picture != null && category.picture!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      category.picture!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.category, color: categoryColor),
                    ),
                  )
                : Icon(Icons.category, color: categoryColor),
          ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          category.description.isNotEmpty
              ? category.description
              : 'No description',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusChip(category.isActive),
            const SizedBox(width: 8),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete, size: 16, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                print('DEBUG: PopupMenu onSelected called with value: $value');
                if (value == 'edit') {
                  print('DEBUG: Calling _editCategory');
                  _editCategory(category);
                } else if (value == 'delete') {
                  print('DEBUG: Calling _deleteCategory');
                  _deleteCategory(category);
                } else {
                  print('DEBUG: Unknown value: $value');
                }
              },
            ),
          ],
        ),
        onTap: () => _editCategory(category),
        ),
      ),
    );
  }

  Widget _buildSubcategoryCard(
      Subcategory subcategory, CategoryProvider provider) {
    final parentCategory = provider.getCategoryById(subcategory.categoryId);
    final categoryColor = parentCategory != null
        ? _getCategoryColor(parentCategory.name)
        : AppColors.primaryBlue;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: categoryColor.withValues(alpha: 0.03),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: categoryColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: ListTile(
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: categoryColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: subcategory.picture != null && subcategory.picture!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      subcategory.picture!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.subdirectory_arrow_right,
                          color: categoryColor),
                    ),
                  )
                : Icon(Icons.subdirectory_arrow_right,
                    color: categoryColor),
          ),
        title: Text(
          subcategory.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subcategory.description.isNotEmpty
                  ? subcategory.description
                  : 'No description',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: categoryColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                '${parentCategory?.name ?? 'Unknown'}',
                style: TextStyle(
                  color: categoryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusChip(subcategory.isActive),
            const SizedBox(width: 8),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete, size: 16, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                print(
                    'DEBUG: SubcategoryPopupMenu onSelected called with value: $value');
                if (value == 'edit') {
                  print('DEBUG: Calling _editSubcategory');
                  _editSubcategory(subcategory);
                } else if (value == 'delete') {
                  print('DEBUG: Calling _deleteSubcategory');
                  _deleteSubcategory(subcategory);
                } else {
                  print('DEBUG: Unknown value: $value');
                }
              },
            ),
          ],
        ),
        onTap: () => _editSubcategory(subcategory),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppColors.success : AppColors.error,
        ),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: isActive ? AppColors.success : AppColors.error,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildErrorState(CategoryProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          const Text(
            'Failed to Load Data',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            provider.errorMessage ?? 'Unknown error occurred',
            style: const TextStyle(color: AppColors.mediumGray),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => provider.refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.category_outlined,
              size: 64, color: AppColors.mediumGray),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.mediumGray),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    final isOnCategoriesTab = _tabController.index == 0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: FloatingActionButton(
        key: ValueKey(isOnCategoriesTab),
        onPressed: isOnCategoriesTab ? _createCategory : _createSubcategory,
        backgroundColor:
            isOnCategoriesTab ? AppColors.primaryRed : AppColors.primaryBlue,
        foregroundColor: AppColors.white,
        elevation: 8,
        splashColor: AppColors.white.withValues(alpha: 0.3),
        heroTag: "category_fab",
        child: const Icon(
          Icons.add,
          size: 24,
        ),
      ),
    );
  }

  void _createCategory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CategoryFormScreen(),
      ),
    );
  }

  void _createSubcategory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SubcategoryFormScreen(),
      ),
    );
  }

  void _editCategory(Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CategoryFormScreen(category: category),
      ),
    );
  }

  void _editSubcategory(Subcategory subcategory) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SubcategoryFormScreen(subcategory: subcategory),
      ),
    );
  }

  void _deleteCategory(Category category) {
    print('DEBUG: === DELETION FLOW START ===');
    print(
        'DEBUG: _deleteCategory called for category: ${category.name} (ID: ${category.id})');
    print('DEBUG: Category object: $category');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Are you sure you want to delete "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              print(
                  'DEBUG: Delete button pressed for category: ${category.name}');
              Navigator.of(context).pop();
              print(
                  'DEBUG: Calling CategoryProvider.deleteCategory(${category.id})');
              final provider = context.read<CategoryProvider>();
              final success = await provider.deleteCategory(category.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${category.name}" deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          provider.errorMessage ?? 'Failed to delete category'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteSubcategory(Subcategory subcategory) {
    print('DEBUG: === SUBCATEGORY DELETION FLOW START ===');
    print(
        'DEBUG: _deleteSubcategory called for subcategory: ${subcategory.name} (ID: ${subcategory.id})');
    print('DEBUG: Subcategory object: $subcategory');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subcategory'),
        content: Text('Are you sure you want to delete "${subcategory.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              print(
                  'DEBUG: Delete button pressed for subcategory: ${subcategory.name}');
              Navigator.of(context).pop();
              print(
                  'DEBUG: Calling CategoryProvider.deleteSubcategory(${subcategory.id})');
              final provider = context.read<CategoryProvider>();
              final success = await provider.deleteSubcategory(subcategory.id);
              if (mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Subcategory "${subcategory.name}" deleted successfully'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          provider.errorMessage ?? 'Failed to delete subcategory'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

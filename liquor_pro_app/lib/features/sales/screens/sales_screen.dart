import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import 'sales_history_screen.dart';
import 'daily_sales_screen.dart';
import 'returns_screen.dart';

/// Sales Screen - Manage sales, returns, daily sales
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Sales',
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'All Sales'),
            Tab(text: 'Daily Sales'),
            Tab(text: 'Returns'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAllSalesTab(),
          _buildDailySalesTab(),
          _buildReturnsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'sales_fab',
        onPressed: () {
          // TODO: Create new sale
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('New Sale'),
        elevation: 4,
      ),
    );
  }

  Widget _buildAllSalesTab() {
    return const SalesHistoryScreen();
  }

  Widget _buildDailySalesTab() {
    return const DailySalesScreen();
  }

  Widget _buildReturnsTab() {
    return const ReturnsScreen();
  }
}

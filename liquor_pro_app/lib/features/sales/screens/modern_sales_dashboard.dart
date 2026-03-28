import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../providers/sales_provider.dart';
import 'modern_pos_screen.dart';
import 'sales_history_modern.dart';

/// Modern iOS-style Sales Dashboard with beautiful animations
class ModernSalesDashboard extends StatefulWidget {
  const ModernSalesDashboard({super.key});

  @override
  State<ModernSalesDashboard> createState() => _ModernSalesDashboardState();
}

class _ModernSalesDashboardState extends State<ModernSalesDashboard>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  int _selectedTimeRange = 0; // 0: Today, 1: Week, 2: Month
  final PageController _pageController = PageController(viewportFraction: 0.9);

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadDashboard();
  }

  void _initAnimations() {
    // Fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Slide animation
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
        );

    // Scale animation
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );

    // Start animations
    _fadeController.forward();
    _slideController.forward();
    _scaleController.forward();
  }

  void _loadDashboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesProvider>().fetchDashboardData();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // Modern App Bar with Blur
          _buildModernAppBar(),

          // Refresh Indicator
          CupertinoSliverRefreshControl(
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              await context.read<SalesProvider>().fetchDashboardData();
            },
          ),

          // Dashboard Content
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // Quick Actions
                  _buildQuickActions(),

                  const SizedBox(height: 24),

                  // Revenue Cards with Animation
                  _buildRevenueCards(),

                  const SizedBox(height: 24),

                  // Sales Chart
                  _buildSalesChart(),

                  const SizedBox(height: 24),

                  // Recent Transactions
                  _buildRecentTransactions(),

                  const SizedBox(height: 24),

                  // Top Products
                  _buildTopProducts(),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),

      // Modern Floating Action Button
      floatingActionButton: _buildModernFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildModernAppBar() {
    return SliverAppBar(
      expandedHeight: 180,
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)],
            ),
          ),
          child: Stack(
            children: [
              // Background Pattern
              Positioned(
                right: -50,
                top: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),

              // Content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Good ${_getGreeting()}!',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sales Dashboard',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Formatters.date(DateTime.now()),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Notification Icon with Badge
        Stack(
          children: [
            IconButton(
              icon: const Icon(CupertinoIcons.bell, color: Colors.white),
              onPressed: () {
                HapticFeedback.lightImpact();
                // Navigate to notifications
              },
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        // Settings
        IconButton(
          icon: const Icon(CupertinoIcons.settings, color: Colors.white),
          onPressed: () {
            HapticFeedback.lightImpact();
            // Navigate to settings
          },
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {
        'icon': CupertinoIcons.cart_badge_plus,
        'label': 'New Sale',
        'color': Theme.of(context).colorScheme.primary,
      },
      {
        'icon': CupertinoIcons.qrcode_viewfinder,
        'label': 'Scan',
        'color': AppColors.accent,
      },
      {
        'icon': CupertinoIcons.doc_text,
        'label': 'Invoice',
        'color': AppColors.info,
      },
      {
        'icon': CupertinoIcons.arrow_turn_up_left,
        'label': 'Return',
        'color': AppColors.warning,
      },
    ];

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        itemBuilder: (context, index) {
          final action = actions[index];
          return ScaleTransition(
            scale: _scaleAnimation,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _QuickActionButton(
                icon: action['icon'] as IconData,
                label: action['label'] as String,
                color: action['color'] as Color,
                onTap: () => _handleQuickAction(index),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRevenueCards() {
    return Consumer<SalesProvider>(
      builder: (context, provider, _) {
        final analytics = provider.analytics;

        return SizedBox(
          height: 200,
          child: PageView(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildRevenueCard(
                title: "Today's Sales",
                amount: analytics['todaySales'] ?? 0,
                percentage: 12.5,
                isPositive: true,
                gradient: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ],
              ),
              _buildRevenueCard(
                title: "This Week",
                amount: analytics['weekSales'] ?? 0,
                percentage: 8.2,
                isPositive: true,
                gradient: [
                  AppColors.success,
                  AppColors.success.withValues(alpha: 0.7),
                ],
              ),
              _buildRevenueCard(
                title: "This Month",
                amount: analytics['monthSales'] ?? 0,
                percentage: -3.1,
                isPositive: false,
                gradient: [AppColors.info, AppColors.info.withValues(alpha: 0.7)],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRevenueCard({
    required String title,
    required double amount,
    required double percentage,
    required bool isPositive,
    required List<Color> gradient,
  }) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isPositive
                            ? CupertinoIcons.arrow_up_right
                            : CupertinoIcons.arrow_down_right,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${percentage.abs()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              Formatters.currency(amount),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.chart_bar,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'View Details',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                const Icon(
                  CupertinoIcons.arrow_right,
                  color: Colors.white54,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Sales Overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              _buildTimeRangeSelector(),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(height: 200, child: LineChart(_getSalesChartData())),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    final options = ['Today', 'Week', 'Month'];

    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(options.length, (index) {
          final isSelected = _selectedTimeRange == index;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedTimeRange = index);
              HapticFeedback.lightImpact();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                options[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  LineChartData _getSalesChartData() {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3), strokeWidth: 1);
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final titles = _selectedTimeRange == 0
                  ? ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM']
                  : _selectedTimeRange == 1
                  ? ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  : ['Week 1', 'Week 2', 'Week 3', 'Week 4'];

              if (value.toInt() < titles.length) {
                return Text(
                  titles[value.toInt()],
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
                );
              }
              return const SizedBox();
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 10000,
            getTitlesWidget: (value, meta) {
              return Text(
                '${(value / 1000).toInt()}k',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: _selectedTimeRange == 0
          ? 5
          : _selectedTimeRange == 1
          ? 6
          : 3,
      minY: 0,
      maxY: 50000,
      lineBarsData: [
        LineChartBarData(
          spots: _getSalesData(),
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: AppColors.primary,
              );
            },
          ),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.primary.withOpacity(0.1),
          ),
        ),
      ],
    );
  }

  List<FlSpot> _getSalesData() {
    // Mock data - replace with actual data
    if (_selectedTimeRange == 0) {
      return const [
        FlSpot(0, 15000),
        FlSpot(1, 25000),
        FlSpot(2, 35000),
        FlSpot(3, 28000),
        FlSpot(4, 42000),
        FlSpot(5, 38000),
      ];
    } else if (_selectedTimeRange == 1) {
      return const [
        FlSpot(0, 32000),
        FlSpot(1, 28000),
        FlSpot(2, 35000),
        FlSpot(3, 40000),
        FlSpot(4, 45000),
        FlSpot(5, 38000),
        FlSpot(6, 42000),
      ];
    } else {
      return const [
        FlSpot(0, 180000),
        FlSpot(1, 220000),
        FlSpot(2, 195000),
        FlSpot(3, 240000),
      ];
    }
  }

  Widget _buildRecentTransactions() {
    return Consumer<SalesProvider>(
      builder: (context, provider, _) {
        final recentSales = provider.sales.take(5).toList();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Transactionssss',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => const SalesHistoryModern(),
                        ),
                      );
                    },
                    child: const Text('See All'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (recentSales.isEmpty)
                _buildEmptyTransactions()
              else
                ...recentSales.map((sale) => _buildTransactionTile(sale)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTransactionTile(sale) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.lightImpact();
            // Navigate to sale details
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getStatusColor(sale.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getStatusIcon(sale.status),
                    color: _getStatusColor(sale.status),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sale.saleNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sale.customerName ?? 'Walk-in Customer',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.currency(sale.totalAmount),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Formatters.timeAgo(sale.createdAt),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTransactions() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(CupertinoIcons.cart, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No transactions yet',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start making sales to see them here',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProducts() {
    final products = [
      {'name': 'Johnnie Walker Black', 'sales': 45, 'revenue': 135000},
      {'name': 'Royal Challenge', 'sales': 38, 'revenue': 45600},
      {'name': 'Budweiser', 'sales': 32, 'revenue': 32000},
      {'name': 'Kingfisher', 'sales': 28, 'revenue': 22400},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top Products',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: products.map((product) {
                final index = products.indexOf(product);
                return Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${product['sales']} units sold',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Formatters.currency(
                            (product['revenue'] as num).toDouble(),
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    if (index < products.length - 1)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernFAB() {
    return Container(
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const ModernPOSScreen(),
                fullscreenDialog: true,
              ),
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                CupertinoIcons.plus_circle_fill,
                color: Colors.white,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'New Sale',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  void _handleQuickAction(int index) {
    HapticFeedback.mediumImpact();
    switch (index) {
      case 0: // New Sale
        Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => const ModernPOSScreen()),
        );
        break;
      case 1: // Scan
        // Navigate to scan
        break;
      case 2: // Invoice
        // Navigate to invoices
        break;
      case 3: // Return
        // Navigate to returns
        break;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'pending':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'approved':
        return CupertinoIcons.checkmark_circle_fill;
      case 'pending':
        return CupertinoIcons.clock_fill;
      case 'rejected':
        return CupertinoIcons.xmark_circle_fill;
      default:
        return CupertinoIcons.circle;
    }
  }
}

/// Quick Action Button Widget
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 75,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

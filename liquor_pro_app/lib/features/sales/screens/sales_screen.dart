import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:math' as math;
import '../../../shared/widgets/custom_app_bar.dart';
import 'sales_history_screen.dart'; // Updated to use the screen with edit functionality
import 'daily_sales_screen.dart';
import 'daily_sales_entry_screen.dart';
import 'smart_sale_screen.dart';
import 'modern_sales_dashboard.dart';
import '../../../core/utils/snackbar_helper.dart';

/// Sales Screen - Manage sales, returns, daily sales with semi-circle navigation
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isMenuOpen = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
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
    if (_selectedIndex == 0) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: CustomAppBar(
          title: _getPageTitle(),
          actions: [
            IconButton(
              icon: Icon(CupertinoIcons.info_circle, color: cs.primary),
              onPressed: () {
                Navigator.pushNamed(context, '/sales/limitations-info');
              },
              tooltip: 'System Information',
            ),
            IconButton(
              icon: Icon(CupertinoIcons.chart_bar_alt_fill, color: cs.primary),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ModernSalesDashboard(),
                  ),
                );
              },
              tooltip: 'Sales Dashboard',
            ),
          ],
        ),
        body: _buildDailyEntryTab(),
        floatingActionButton: _buildSemiCircleMenu(),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _buildBottomNavBar(),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: CustomAppBar(
        title: _getPageTitle(),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.info_circle, color: cs.primary),
            onPressed: () {
              Navigator.pushNamed(context, '/sales/limitations-info');
            },
            tooltip: 'System Information',
          ),
          IconButton(
            icon: Icon(CupertinoIcons.chart_bar_alt_fill, color: cs.primary),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ModernSalesDashboard(),
                ),
              );
            },
            tooltip: 'Sales Dashboard',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content with IndexedStack
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildDailyEntryTab(),
              _buildAllSalesTab(),
              _buildDailySalesTab(),
            ],
          ),
        ],
      ),
      floatingActionButton: _buildSemiCircleMenu(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: cs.outline.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Products & Quantity
          Expanded(
            child: InkWell(
              onTap: () => _navigateToIndex(0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.doc_text_fill,
                    color: _selectedIndex == 0
                        ? cs.primary
                        : cs.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Daily Entry',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _selectedIndex == 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _selectedIndex == 0
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Spacer for semi-circle menu
          const SizedBox(width: 80),
          // Payment Breakdown
          Expanded(
            child: InkWell(
              onTap: () => _navigateToIndex(1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.clock_fill,
                    color: _selectedIndex == 1
                        ? cs.primary
                        : cs.onSurfaceVariant,
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'History',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: _selectedIndex == 1
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: _selectedIndex == 1
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Daily Sales Entry';
      case 1:
        return 'Sales History';
      case 2:
        return 'Daily Reports';
      default:
        return 'Sales Management';
    }
  }

  void _openSmartSale() {
    // Close the menu first
    setState(() {
      _isMenuOpen = false;
    });
    _animationController.reverse();

    // Navigate to Smart Sale screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SmartSaleScreen(),
      ),
    );
  }

  void _navigateToIndex(int index) {
    setState(() {
      _selectedIndex = index;
      _isMenuOpen = false;
    });
    _animationController.reverse();
  }

  void _toggleMenu() {
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
    if (_isMenuOpen) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  Widget _buildSemiCircleMenu() {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Background overlay
        if (_isMenuOpen)
          GestureDetector(
            onTap: _toggleMenu,
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              color: Colors.transparent,
            ),
          ),
        // Semi-circle menu items
        ..._buildMenuItems(),
        // Main FAB
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary, cs.primary.withValues(alpha: 0.8)],
            ),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleMenu,
              customBorder: const CircleBorder(),
              child: AnimatedBuilder(
                animation: _animation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _animation.value * math.pi / 4,
                    child: Icon(
                      _isMenuOpen ? CupertinoIcons.xmark : CupertinoIcons.plus,
                      color: Colors.white,
                      size: 24,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMenuItems() {
    if (!_isMenuOpen) return [];

    final cs = Theme.of(context).colorScheme;
    final items = [
      {'icon': CupertinoIcons.calendar, 'label': 'Daily Report', 'index': 2, 'action': null},
      {
        'icon': CupertinoIcons.bolt_fill,
        'label': 'Smart Sale',
        'index': -1, // Special index for navigation
        'action': 'smart_sale',
      },
    ];

    return items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;

      // Calculate position in semi-circle
      final angle = math.pi / (items.length + 1) * (index + 1);
      final radius = 80.0;
      final x = radius * math.cos(angle);
      final y = -radius * math.sin(angle);

      return AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform(
            transform: Matrix4.identity()
              ..translate(x * _animation.value, y * _animation.value),
            alignment: Alignment.center,
            child: Opacity(
              opacity: _animation.value,
              child: ScaleTransition(
                scale: _animation,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surface,
                    boxShadow: [
                      BoxShadow(
                        color: cs.outline.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final action = item['action'] as String?;
                        if (action == 'smart_sale') {
                          _openSmartSale();
                        } else {
                          _navigateToIndex(item['index'] as int);
                        }
                      },
                      customBorder: const CircleBorder(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            color: cs.primary,
                            size: 20,
                          ),
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 8,
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  Widget _buildDailyEntryTab() {
    return const DailySalesEntryScreen();
  }

  Widget _buildAllSalesTab() {
    return const SalesHistoryScreen(); // Now using the screen with edit functionality
  }

  Widget _buildDailySalesTab() {
    return const DailySalesScreen();
  }

  void _generateDailyReport() {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(CupertinoIcons.doc_chart_fill, color: cs.primary),
            const SizedBox(width: 12),
            const Text('Generate Daily Report'),
          ],
        ),
        content: const Text(
          'This will generate a daily sales report for today. The report will include all sales, returns, and payment summaries.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Generate report logic
              SnackbarHelper.showInfo(
                context,
                'Daily report generation in progress...',
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: cs.primary),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

}

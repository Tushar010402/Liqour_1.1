import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/authentication/controllers/auth_provider.dart';
import '../core/constants/app_colors.dart';
import '../features/authentication/views/login_screen.dart';
import '../features/authentication/views/otp_screen.dart';
import '../features/dashboard/views/dashboard_screen.dart';
import '../features/plan_management/views/plan_list_screen.dart';
import '../features/plan_management/views/plan_details_screen.dart';
import '../features/plan_management/views/plan_form_screen.dart';
import '../features/tenant_management/views/tenants_screen.dart';
import '../features/subscription_management/views/subscriptions_screen.dart';
import '../features/analytics/views/analytics_screen.dart';
import '../features/usage_management/views/usage_screen.dart';
import '../features/discount_management/views/discounts_screen.dart';
import '../features/plan_transitions/views/plan_transitions_screen.dart';
import '../features/system_management/views/system_screen.dart';
import '../features/settings/views/settings_screen.dart';
import '../features/brand_management/views/brands_screen.dart';
import '../features/category_management/views/categories_screen.dart';
import '../core/widgets/loading_screen.dart';
import '../core/widgets/side_drawer.dart';

class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String otp = '/otp';
  static const String dashboard = '/dashboard';
  static const String plans = '/plans';
  static const String planDetails = '/plans/:id';
  static const String planForm = '/plans/form';
  static const String planEdit = '/plans/edit/:id';
  static const String tenants = '/tenants';
  static const String subscriptions = '/subscriptions';
  static const String analytics = '/analytics';
  static const String usage = '/usage';
  static const String discounts = '/discounts';
  static const String transitions = '/transitions';
  static const String brands = '/brands';
  static const String categories = '/categories';
  static const String system = '/system';
  static const String settings = '/settings';

  static final GoRouter router = GoRouter(
    initialLocation: splash,
    redirect: _redirect,
    routes: [
      // Splash/Loading Route
      GoRoute(
        path: splash,
        name: 'splash',
        builder: (context, state) => const LoadingScreen(),
      ),

      // Authentication Routes
      GoRoute(
        path: login,
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: otp,
        name: 'otp',
        builder: (context, state) {
          final encodedPhoneNumber = state.uri.queryParameters['phone'] ?? '';
          // Decode the URL-encoded phone number to restore the + character
          final phoneNumber = Uri.decodeComponent(encodedPhoneNumber);
          return OTPScreen(phoneNumber: phoneNumber);
        },
      ),

      // Main App Routes (Protected)
      ShellRoute(
        builder: (context, state, child) {
          return MainShell(child: child);
        },
        routes: [
          GoRoute(
            path: dashboard,
            name: 'dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: plans,
            name: 'plans',
            builder: (context, state) => const PlanListScreen(),
            routes: [
              GoRoute(
                path: 'form',
                name: 'plan-form',
                builder: (context, state) => const PlanFormScreen(),
              ),
              GoRoute(
                path: 'edit/:id',
                name: 'plan-edit',
                builder: (context, state) {
                  final planId = state.pathParameters['id']!;
                  return PlanFormScreen(planId: planId);
                },
              ),
              GoRoute(
                path: ':id',
                name: 'plan-details',
                builder: (context, state) {
                  final planId = state.pathParameters['id']!;
                  return PlanDetailsScreen(planId: planId);
                },
              ),
            ],
          ),
          GoRoute(
            path: tenants,
            name: 'tenants',
            builder: (context, state) => const TenantsScreen(),
          ),
          GoRoute(
            path: subscriptions,
            name: 'subscriptions',
            builder: (context, state) => const SubscriptionsScreen(),
          ),
          GoRoute(
            path: analytics,
            name: 'analytics',
            builder: (context, state) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: usage,
            name: 'usage',
            builder: (context, state) => const UsageScreen(),
          ),
          GoRoute(
            path: discounts,
            name: 'discounts',
            builder: (context, state) => const DiscountsScreen(),
          ),
          GoRoute(
            path: transitions,
            name: 'transitions',
            builder: (context, state) => const PlanTransitionsScreen(),
          ),
          GoRoute(
            path: brands,
            name: 'brands',
            builder: (context, state) => const BrandsScreen(),
          ),
          GoRoute(
            path: categories,
            name: 'categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: system,
            name: 'system',
            builder: (context, state) => const SystemScreen(),
          ),
          GoRoute(
            path: settings,
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );

  static String? _redirect(BuildContext context, GoRouterState state) {
    final authProvider = context.read<AuthProvider>();
    final isAuthenticated = authProvider.isAuthenticated;
    final isLoading = authProvider.isLoading;
    final currentLocation = state.uri.path;

    // If still loading, stay on splash
    if (isLoading && currentLocation == splash) {
      return null;
    }

    // If not authenticated and not on auth routes, redirect to login
    if (!isAuthenticated && !_isAuthRoute(currentLocation)) {
      return login;
    }

    // If authenticated and on auth routes, redirect to dashboard
    if (isAuthenticated && _isAuthRoute(currentLocation)) {
      return dashboard;
    }

    // If authenticated and on splash, redirect to dashboard
    if (isAuthenticated && currentLocation == splash) {
      return dashboard;
    }

    return null;
  }

  static bool _isAuthRoute(String route) {
    return route == login || route == otp || route == splash;
  }
}

// Main Shell for authenticated routes with drawer navigation
class MainShell extends StatelessWidget {
  final Widget child;

  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      drawer: const SideDrawer(),
      appBar: _buildAppBar(context),
      body: child,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      elevation: 0,
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.primaryBlack,
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(context).openDrawer(),
          tooltip: 'Open navigation menu',
        ),
      ),
      title: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final userData = authProvider.userData;
          final userName = userData?['name'] ?? 'Admin';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LiquorPro SaaS',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlack,
                    ),
              ),
              Text(
                'Welcome back, $userName',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.mediumGray,
                    ),
              ),
            ],
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () {},
          tooltip: 'Notifications',
        ),
        Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            final userData = authProvider.userData;
            final userName = userData?['name'] ?? 'Admin';
            final userInitial = userName.substring(0, 1).toUpperCase();

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primaryRed,
                child: Text(
                  userInitial,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

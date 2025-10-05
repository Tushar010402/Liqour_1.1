import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/models/subscription_model.dart';

enum SubscriptionState {
  initial,
  loading,
  loaded,
  error,
}

class SubscriptionProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  SubscriptionState _state = SubscriptionState.initial;
  SubscriptionAnalytics? _analytics;
  List<SubscriptionModel> _subscriptions = [];
  String? _errorMessage;
  DateTime? _lastUpdated;

  // Getters
  SubscriptionState get state => _state;
  SubscriptionAnalytics? get analytics => _analytics;
  List<SubscriptionModel> get subscriptions => _subscriptions;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;

  bool get isLoading => _state == SubscriptionState.loading;
  bool get hasError => _state == SubscriptionState.error;
  bool get hasData => _analytics != null;

  // Load subscription analytics
  Future<void> loadSubscriptionAnalytics() async {
    _setState(SubscriptionState.loading);

    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        ApiEndpoints.analyticsSubscriptions,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        _analytics = SubscriptionAnalytics.fromJson(response.data!);

        // Generate sample subscriptions for demonstration
        _generateSampleSubscriptions();

        _lastUpdated = DateTime.now();
        _setState(SubscriptionState.loaded);
      } else {
        _setError('Failed to load subscription analytics: ${response.error}');
      }
    } catch (e) {
      debugPrint('Failed to load subscription analytics: $e');
      _setError('Failed to load subscription analytics: ${e.toString()}');
    }
  }

  // Generate sample subscriptions for demonstration
  void _generateSampleSubscriptions() {
    if (_analytics != null && _analytics!.totalSubscriptions > 0) {
      _subscriptions =
          List.generate(_analytics!.totalSubscriptions.clamp(0, 15), (index) {
        final tenantNames = [
          'Liquor Mart Express',
          'Premium Wine Store',
          'City Spirits Shop',
          'Elite Beverage Center',
          'Royal Liquor Palace',
          'Corner Wine & Spirits',
          'Metro Drinks Hub',
          'Classic Liquor Store',
          'Golden Age Beverages',
          'Heritage Wine Shop',
          'Downtown Liquor Depot',
          'Vintage Wine Collection',
          'Urban Spirits Boutique',
          'Crossroads Wine & Beer',
          'Neighborhood Liquor Store'
        ];

        final statuses = [
          'active',
          'active',
          'active',
          'active',
          'active',
          'trial',
          'cancelled',
          'active'
        ];
        final billingCycles = [
          'monthly',
          'monthly',
          'monthly',
          'yearly',
          'monthly'
        ];
        final amounts = [49.99, 99.99, 199.99, 299.99, 16.66];

        final status = statuses[index % statuses.length];
        final planIndex = index % _analytics!.planPopularity.length;
        final planPopularity = _analytics!.planPopularity.isNotEmpty
            ? _analytics!.planPopularity[planIndex]
            : PlanPopularity(
                planName: 'Basic Plan',
                subscriptions: 1,
                averageRevenue: 49.99);

        return SubscriptionModel(
          id: 'sub_${index + 1}',
          tenantId: 'tenant_${index + 1}',
          tenantName: tenantNames[index % tenantNames.length],
          planId: 'plan_${planIndex + 1}',
          planName: planPopularity.planName,
          status: status,
          billingCycle: billingCycles[index % billingCycles.length],
          amount: amounts[index % amounts.length],
          startDate: DateTime.now().subtract(Duration(days: (index + 1) * 30)),
          nextBillingDate: status == 'active'
              ? DateTime.now().add(Duration(days: 30 - (index % 30)))
              : null,
          trialEndDate:
              status == 'trial' ? DateTime.now().add(Duration(days: 14)) : null,
          createdAt: DateTime.now().subtract(Duration(days: (index + 1) * 30)),
          updatedAt: DateTime.now().subtract(Duration(hours: index * 2)),
        );
      });
    }
  }

  // Refresh subscription data
  Future<void> refresh() async {
    await loadSubscriptionAnalytics();
  }

  // Filter subscriptions by status
  List<SubscriptionModel> getSubscriptionsByStatus(String status) {
    return _subscriptions
        .where((subscription) =>
            subscription.status.toLowerCase() == status.toLowerCase())
        .toList();
  }

  // Get subscriptions by plan
  List<SubscriptionModel> getSubscriptionsByPlan(String planName) {
    return _subscriptions
        .where((subscription) =>
            subscription.planName.toLowerCase() == planName.toLowerCase())
        .toList();
  }

  // Search subscriptions
  List<SubscriptionModel> searchSubscriptions(String query) {
    if (query.isEmpty) return _subscriptions;

    final lowerQuery = query.toLowerCase();
    return _subscriptions
        .where((subscription) =>
            subscription.tenantName.toLowerCase().contains(lowerQuery) ||
            subscription.planName.toLowerCase().contains(lowerQuery) ||
            subscription.id.toLowerCase().contains(lowerQuery))
        .toList();
  }

  // Get revenue statistics
  Map<String, double> getRevenueStats() {
    double totalRevenue = 0;
    double monthlyRevenue = 0;
    double yearlyRevenue = 0;

    for (final subscription in _subscriptions.where((s) => s.isActive)) {
      totalRevenue += subscription.amount;
      if (subscription.billingCycle == 'monthly') {
        monthlyRevenue += subscription.amount;
      } else if (subscription.billingCycle == 'yearly') {
        yearlyRevenue += subscription.amount;
      }
    }

    return {
      'total': totalRevenue,
      'monthly': monthlyRevenue,
      'yearly': yearlyRevenue,
    };
  }

  // Get subscription counts by status
  Map<String, int> getStatusCounts() {
    final counts = <String, int>{};
    for (final subscription in _subscriptions) {
      counts[subscription.status] = (counts[subscription.status] ?? 0) + 1;
    }
    return counts;
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    if (_state == SubscriptionState.error) {
      _setState(SubscriptionState.initial);
    }
  }

  // Private methods
  void _setState(SubscriptionState state) {
    _state = state;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _state = SubscriptionState.error;
    notifyListeners();
  }
}

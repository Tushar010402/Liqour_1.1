import 'package:flutter/foundation.dart';
import '../../../core/services/api_service.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/models/plan_model.dart';

enum PlanState {
  initial,
  loading,
  loaded,
  error,
}

class PlanProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  PlanState _state = PlanState.initial;
  List<PlanModel> _plans = [];
  List<PlanWithBillingOptions> _plansWithBilling = [];
  String? _errorMessage;
  DateTime? _lastUpdated;

  // Getters
  PlanState get state => _state;
  List<PlanModel> get plans => _plans;
  List<PlanWithBillingOptions> get plansWithBilling => _plansWithBilling;
  String? get errorMessage => _errorMessage;
  DateTime? get lastUpdated => _lastUpdated;

  bool get isLoading => _state == PlanState.loading;
  bool get hasError => _state == PlanState.error;
  bool get hasPlans => _plans.isNotEmpty;

  // Load all plans
  Future<void> loadPlans() async {
    _setState(PlanState.loading);

    try {
      final response = await _apiService.get<List<PlanModel>>(
        ApiEndpoints.plans,
        fromJson: (data) {
          if (data is List) {
            return data.map((item) => PlanModel.fromJson(item)).toList();
          }
          return <PlanModel>[];
        },
      );

      if (response.isSuccess && response.data != null) {
        _plans = response.data!;
        _lastUpdated = DateTime.now();
        _setState(PlanState.loaded);
      } else {
        _setError(response.error ?? 'Failed to load plans');
      }
    } catch (e) {
      _setError('Failed to load plans: ${e.toString()}');
    }
  }

  // Load public plans (for display purposes)
  Future<void> loadPublicPlans() async {
    try {
      final response = await _apiService.get<List<PlanModel>>(
        ApiEndpoints.publicPlans,
        fromJson: (data) {
          if (data is Map && data['plans'] is List) {
            return (data['plans'] as List)
                .map((item) => PlanModel.fromJson(item))
                .toList();
          } else if (data is List) {
            return data.map((item) => PlanModel.fromJson(item)).toList();
          }
          return <PlanModel>[];
        },
      );

      if (response.isSuccess && response.data != null) {
        _plans = response.data!;
        _lastUpdated = DateTime.now();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load public plans: $e');
    }
  }

  // Load plans with billing options
  Future<void> loadPlansWithBillingOptions() async {
    _setState(PlanState.loading);

    try {
      final response = await _apiService.get<List<PlanWithBillingOptions>>(
        ApiEndpoints.plansWithBillingOptions,
        fromJson: (data) {
          if (data is Map && data['data'] is List) {
            return (data['data'] as List)
                .map((item) => PlanWithBillingOptions.fromJson(item))
                .toList();
          } else if (data is List) {
            return data
                .map((item) => PlanWithBillingOptions.fromJson(item))
                .toList();
          }
          return <PlanWithBillingOptions>[];
        },
      );

      if (response.isSuccess && response.data != null) {
        _plansWithBilling = response.data!;
        // Extract plans from billing data
        _plans = _plansWithBilling.map((item) => item.plan).toList();
        _lastUpdated = DateTime.now();
        _setState(PlanState.loaded);
      } else {
        _setError(
            response.error ?? 'Failed to load plans with billing options');
      }
    } catch (e) {
      _setError('Failed to load plans with billing options: ${e.toString()}');
    }
  }

  // Get plan by ID
  PlanModel? getPlanById(String id) {
    try {
      return _plans.firstWhere((plan) => plan.id == id);
    } catch (e) {
      return null;
    }
  }

  // Create new plan
  Future<bool> createPlan(Map<String, dynamic> planData) async {
    try {
      final response = await _apiService.post<PlanModel>(
        ApiEndpoints.plans,
        data: planData,
        fromJson: (data) => PlanModel.fromJson(data),
      );

      if (response.isSuccess && response.data != null) {
        _plans.add(response.data!);
        notifyListeners();
        return true;
      } else {
        _setError(response.error ?? 'Failed to create plan');
        return false;
      }
    } catch (e) {
      _setError('Failed to create plan: ${e.toString()}');
      return false;
    }
  }

  // Update plan
  Future<bool> updatePlan(String planId, Map<String, dynamic> planData) async {
    try {
      final response = await _apiService.put<PlanModel>(
        ApiEndpoints.planById(planId),
        data: planData,
        fromJson: (data) => PlanModel.fromJson(data),
      );

      if (response.isSuccess && response.data != null) {
        final index = _plans.indexWhere((plan) => plan.id == planId);
        if (index != -1) {
          _plans[index] = response.data!;
          notifyListeners();
        }
        return true;
      } else {
        _setError(response.error ?? 'Failed to update plan');
        return false;
      }
    } catch (e) {
      _setError('Failed to update plan: ${e.toString()}');
      return false;
    }
  }

  // Delete plan
  Future<bool> deletePlan(String planId) async {
    try {
      final response = await _apiService.delete(
        ApiEndpoints.planById(planId),
      );

      if (response.isSuccess) {
        _plans.removeWhere((plan) => plan.id == planId);
        notifyListeners();
        return true;
      } else {
        _setError(response.error ?? 'Failed to delete plan');
        return false;
      }
    } catch (e) {
      _setError('Failed to delete plan: ${e.toString()}');
      return false;
    }
  }

  // Get plan features
  Future<List<String>> getPlanFeatures(String planId) async {
    try {
      final response = await _apiService.get<List<String>>(
        ApiEndpoints.planFeatures(planId),
        fromJson: (data) {
          if (data is Map && data['features'] is List) {
            return (data['features'] as List).cast<String>();
          } else if (data is List) {
            return data.cast<String>();
          }
          return <String>[];
        },
      );

      if (response.isSuccess && response.data != null) {
        return response.data!;
      } else {
        _setError(response.error ?? 'Failed to load plan features');
        return [];
      }
    } catch (e) {
      _setError('Failed to load plan features: ${e.toString()}');
      return [];
    }
  }

  // Update plan discounts
  Future<bool> updatePlanDiscounts(
      String planId, Map<String, dynamic> discountData) async {
    try {
      final response = await _apiService.put(
        ApiEndpoints.planDiscounts(planId),
        data: discountData,
      );

      if (response.isSuccess) {
        // Reload plans to get updated data
        await loadPlans();
        return true;
      } else {
        _setError(response.error ?? 'Failed to update plan discounts');
        return false;
      }
    } catch (e) {
      _setError('Failed to update plan discounts: ${e.toString()}');
      return false;
    }
  }

  // Validate plan limits
  Future<bool> validatePlanLimits(
      String planId, Map<String, dynamic> limits) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiEndpoints.planValidateLimits(planId),
        data: limits,
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return response.data!['valid'] ?? false;
      } else {
        _setError(response.error ?? 'Failed to validate plan limits');
        return false;
      }
    } catch (e) {
      _setError('Failed to validate plan limits: ${e.toString()}');
      return false;
    }
  }

  // Initialize default plans
  Future<bool> initializeDefaultPlans() async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.initializePlans,
        data: {},
      );

      if (response.isSuccess) {
        // Reload plans after initialization
        await loadPlans();
        return true;
      } else {
        _setError(response.error ?? 'Failed to initialize default plans');
        return false;
      }
    } catch (e) {
      _setError('Failed to initialize default plans: ${e.toString()}');
      return false;
    }
  }

  // Refresh plans
  Future<void> refresh() async {
    await loadPlans();
  }

  // Filter plans by criteria
  List<PlanModel> filterPlans({
    bool? popular,
    bool? enterprise,
    bool? active,
    String? billingCycle,
  }) {
    return _plans.where((plan) {
      if (popular != null && plan.popular != popular) return false;
      if (enterprise != null && plan.enterprise != enterprise) return false;
      if (active != null && plan.active != active) return false;
      if (billingCycle != null && plan.billingCycle != billingCycle)
        return false;
      return true;
    }).toList();
  }

  // Sort plans
  List<PlanModel> getSortedPlans({bool ascending = true}) {
    final sortedPlans = List<PlanModel>.from(_plans);
    sortedPlans.sort((a, b) {
      final comparison = a.sortOrder.compareTo(b.sortOrder);
      return ascending ? comparison : -comparison;
    });
    return sortedPlans;
  }

  // Get plans by type
  List<PlanModel> getPopularPlans() => filterPlans(popular: true);
  List<PlanModel> getEnterprisePlans() => filterPlans(enterprise: true);
  List<PlanModel> getActivePlans() => filterPlans(active: true);

  // Clear error
  void clearError() {
    _errorMessage = null;
    if (_state == PlanState.error) {
      _setState(PlanState.initial);
    }
  }

  // Private methods
  void _setState(PlanState state) {
    _state = state;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    _state = PlanState.error;
    notifyListeners();
  }
}

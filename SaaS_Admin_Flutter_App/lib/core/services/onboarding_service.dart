import '../constants/api_endpoints.dart';
import '../models/api_response.dart';
import 'api_service.dart';

class OnboardingService {
  final ApiService _apiService;

  OnboardingService(this._apiService);

  // Get onboarding progress for a tenant
  Future<ApiResponse<OnboardingProgress>> getTenantOnboardingProgress(String tenantId) async {
    try {
      final response = await _apiService.get(
        ApiEndpoints.tenantOnboardingProgress(tenantId),
      );

      if (response.success && response.data != null) {
        final progress = OnboardingProgress.fromJson(response.data);
        return ApiResponse<OnboardingProgress>.success(progress);
      }

      return ApiResponse<OnboardingProgress>.error(
        response.message ?? 'Failed to get onboarding progress',
      );
    } catch (e) {
      return ApiResponse<OnboardingProgress>.error('Failed to get onboarding progress: $e');
    }
  }

  // Update onboarding step completion
  Future<ApiResponse<void>> completeOnboardingStep({
    required String tenantId,
    required String stepName,
    Map<String, dynamic>? stepData,
  }) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.completeOnboardingStep,
        data: {
          'tenant_id': tenantId,
          'step_name': stepName,
          'step_data': stepData ?? {},
          'completed_at': DateTime.now().toIso8601String(),
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Failed to complete step');
    } catch (e) {
      return ApiResponse<void>.error('Failed to complete step: $e');
    }
  }

  // Get quick setup recommendations based on business type
  Future<ApiResponse<QuickSetupRecommendations>> getQuickSetupRecommendations({
    required String businessType,
    required String businessSize,
    String? location,
  }) async {
    try {
      final queryParams = [
        'business_type=$businessType',
        'business_size=$businessSize',
        if (location != null) 'location=$location',
      ].join('&');

      final response = await _apiService.get(
        '${ApiEndpoints.quickSetupRecommendations}?$queryParams',
      );

      if (response.success && response.data != null) {
        final recommendations = QuickSetupRecommendations.fromJson(response.data);
        return ApiResponse<QuickSetupRecommendations>.success(recommendations);
      }

      return ApiResponse<QuickSetupRecommendations>.error(
        response.message ?? 'Failed to get recommendations',
      );
    } catch (e) {
      return ApiResponse<QuickSetupRecommendations>.error('Failed to get recommendations: $e');
    }
  }

  // Save business profile during onboarding
  Future<ApiResponse<void>> saveBusinessProfile({
    required String tenantId,
    required BusinessProfile profile,
  }) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.saveBusinessProfile,
        data: {
          'tenant_id': tenantId,
          ...profile.toJson(),
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Failed to save business profile');
    } catch (e) {
      return ApiResponse<void>.error('Failed to save business profile: $e');
    }
  }

  // Complete full onboarding process
  Future<ApiResponse<void>> completeOnboarding(String tenantId) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.completeOnboarding,
        data: {
          'tenant_id': tenantId,
          'completed_at': DateTime.now().toIso8601String(),
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Failed to complete onboarding');
    } catch (e) {
      return ApiResponse<void>.error('Failed to complete onboarding: $e');
    }
  }

  // Skip onboarding (for advanced users)
  Future<ApiResponse<void>> skipOnboarding(String tenantId) async {
    try {
      final response = await _apiService.post(
        ApiEndpoints.skipOnboarding,
        data: {
          'tenant_id': tenantId,
          'skipped_at': DateTime.now().toIso8601String(),
          'reason': 'user_choice',
        },
      );

      if (response.success) {
        return ApiResponse<void>.success(null);
      }

      return ApiResponse<void>.error(response.message ?? 'Failed to skip onboarding');
    } catch (e) {
      return ApiResponse<void>.error('Failed to skip onboarding: $e');
    }
  }
}

// Onboarding progress model
class OnboardingProgress {
  final String tenantId;
  final int currentStep;
  final int totalSteps;
  final List<OnboardingStep> steps;
  final bool isCompleted;
  final DateTime? completedAt;
  final double progressPercentage;

  const OnboardingProgress({
    required this.tenantId,
    required this.currentStep,
    required this.totalSteps,
    required this.steps,
    required this.isCompleted,
    this.completedAt,
    required this.progressPercentage,
  });

  factory OnboardingProgress.fromJson(Map<String, dynamic> json) {
    return OnboardingProgress(
      tenantId: json['tenant_id'] as String,
      currentStep: json['current_step'] as int,
      totalSteps: json['total_steps'] as int,
      steps: (json['steps'] as List)
          .map((step) => OnboardingStep.fromJson(step))
          .toList(),
      isCompleted: json['is_completed'] as bool,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      progressPercentage: (json['progress_percentage'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tenant_id': tenantId,
      'current_step': currentStep,
      'total_steps': totalSteps,
      'steps': steps.map((step) => step.toJson()).toList(),
      'is_completed': isCompleted,
      'completed_at': completedAt?.toIso8601String(),
      'progress_percentage': progressPercentage,
    };
  }

  OnboardingStep? get currentStepData =>
      currentStep < steps.length ? steps[currentStep] : null;

  bool get canProceed => currentStepData?.isCompleted ?? false;
}

// Individual onboarding step
class OnboardingStep {
  final String name;
  final String title;
  final String description;
  final bool isCompleted;
  final bool isRequired;
  final DateTime? completedAt;
  final Map<String, dynamic>? stepData;

  const OnboardingStep({
    required this.name,
    required this.title,
    required this.description,
    required this.isCompleted,
    this.isRequired = true,
    this.completedAt,
    this.stepData,
  });

  factory OnboardingStep.fromJson(Map<String, dynamic> json) {
    return OnboardingStep(
      name: json['name'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      isCompleted: json['is_completed'] as bool,
      isRequired: json['is_required'] as bool? ?? true,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      stepData: json['step_data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'title': title,
      'description': description,
      'is_completed': isCompleted,
      'is_required': isRequired,
      'completed_at': completedAt?.toIso8601String(),
      'step_data': stepData,
    };
  }
}

// Quick setup recommendations
class QuickSetupRecommendations {
  final String recommendedPackage;
  final List<String> recommendedFeatures;
  final BusinessSetupTips tips;
  final List<QuickAction> quickActions;

  const QuickSetupRecommendations({
    required this.recommendedPackage,
    required this.recommendedFeatures,
    required this.tips,
    required this.quickActions,
  });

  factory QuickSetupRecommendations.fromJson(Map<String, dynamic> json) {
    return QuickSetupRecommendations(
      recommendedPackage: json['recommended_package'] as String,
      recommendedFeatures: List<String>.from(json['recommended_features']),
      tips: BusinessSetupTips.fromJson(json['tips']),
      quickActions: (json['quick_actions'] as List)
          .map((action) => QuickAction.fromJson(action))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recommended_package': recommendedPackage,
      'recommended_features': recommendedFeatures,
      'tips': tips.toJson(),
      'quick_actions': quickActions.map((action) => action.toJson()).toList(),
    };
  }
}

// Business setup tips
class BusinessSetupTips {
  final String inventoryTip;
  final String salesTip;
  final String customerTip;
  final List<String> bestPractices;

  const BusinessSetupTips({
    required this.inventoryTip,
    required this.salesTip,
    required this.customerTip,
    required this.bestPractices,
  });

  factory BusinessSetupTips.fromJson(Map<String, dynamic> json) {
    return BusinessSetupTips(
      inventoryTip: json['inventory_tip'] as String,
      salesTip: json['sales_tip'] as String,
      customerTip: json['customer_tip'] as String,
      bestPractices: List<String>.from(json['best_practices']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inventory_tip': inventoryTip,
      'sales_tip': salesTip,
      'customer_tip': customerTip,
      'best_practices': bestPractices,
    };
  }
}

// Quick action for onboarding
class QuickAction {
  final String id;
  final String title;
  final String description;
  final String actionType; // 'navigate', 'api_call', 'modal'
  final Map<String, dynamic> actionData;
  final bool isCompleted;

  const QuickAction({
    required this.id,
    required this.title,
    required this.description,
    required this.actionType,
    required this.actionData,
    this.isCompleted = false,
  });

  factory QuickAction.fromJson(Map<String, dynamic> json) {
    return QuickAction(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      actionType: json['action_type'] as String,
      actionData: json['action_data'] as Map<String, dynamic>,
      isCompleted: json['is_completed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'action_type': actionType,
      'action_data': actionData,
      'is_completed': isCompleted,
    };
  }
}

// Business profile model
class BusinessProfile {
  final String businessName;
  final String businessType;
  final String businessSize;
  final String? location;
  final String? phoneNumber;
  final String? email;
  final List<String> operatingHours;
  final Map<String, dynamic> preferences;

  const BusinessProfile({
    required this.businessName,
    required this.businessType,
    required this.businessSize,
    this.location,
    this.phoneNumber,
    this.email,
    required this.operatingHours,
    required this.preferences,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      businessName: json['business_name'] as String,
      businessType: json['business_type'] as String,
      businessSize: json['business_size'] as String,
      location: json['location'] as String?,
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
      operatingHours: List<String>.from(json['operating_hours']),
      preferences: json['preferences'] as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'business_name': businessName,
      'business_type': businessType,
      'business_size': businessSize,
      'location': location,
      'phone_number': phoneNumber,
      'email': email,
      'operating_hours': operatingHours,
      'preferences': preferences,
    };
  }
}
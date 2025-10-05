import 'package:json_annotation/json_annotation.dart';
import 'package:equatable/equatable.dart';

part 'plan_model.g.dart';

@JsonSerializable()
class PlanModel extends Equatable {
  final String id;
  final String name;
  @JsonKey(name: 'display_name')
  final String displayName;
  final String description;
  final double price;
  final String currency;
  @JsonKey(name: 'billing_cycle')
  final String billingCycle;
  @JsonKey(name: 'trial_days')
  final int trialDays;
  @JsonKey(name: 'max_locations')
  final int maxLocations;
  @JsonKey(name: 'max_users')
  final int maxUsers;
  @JsonKey(name: 'max_products')
  final int maxProducts;
  final List<String> features;
  @JsonKey(name: 'ai_features')
  final List<String>? aiFeatures;
  final bool popular;
  final bool enterprise;
  final bool active;
  @JsonKey(name: 'sort_order')
  final int sortOrder;
  @JsonKey(name: 'razorpay_plan_id')
  final String? razorpayPlanId;
  @JsonKey(name: 'yearly_discount')
  final double yearlyDiscount;
  @JsonKey(name: 'two_year_discount')
  final double? twoYearDiscount;
  @JsonKey(name: 'three_year_discount')
  final double? threeYearDiscount;
  @JsonKey(name: 'billing_term_months')
  final int billingTermMonths;
  @JsonKey(name: 'auto_create_variants')
  final bool autoCreateVariants;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;
  @JsonKey(name: 'deleted_at')
  final DateTime? deletedAt;

  const PlanModel({
    required this.id,
    required this.name,
    required this.displayName,
    required this.description,
    required this.price,
    required this.currency,
    required this.billingCycle,
    required this.trialDays,
    required this.maxLocations,
    required this.maxUsers,
    required this.maxProducts,
    required this.features,
    this.aiFeatures,
    required this.popular,
    required this.enterprise,
    required this.active,
    required this.sortOrder,
    this.razorpayPlanId,
    required this.yearlyDiscount,
    this.twoYearDiscount,
    this.threeYearDiscount,
    required this.billingTermMonths,
    required this.autoCreateVariants,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) =>
      _$PlanModelFromJson(json);
  Map<String, dynamic> toJson() => _$PlanModelToJson(this);

  @override
  List<Object?> get props => [
        id,
        name,
        displayName,
        description,
        price,
        currency,
        billingCycle,
        trialDays,
        maxLocations,
        maxUsers,
        maxProducts,
        features,
        aiFeatures,
        popular,
        enterprise,
        active,
        sortOrder,
        razorpayPlanId,
        yearlyDiscount,
        twoYearDiscount,
        threeYearDiscount,
        billingTermMonths,
        autoCreateVariants,
        createdAt,
        updatedAt,
        deletedAt,
      ];

  PlanModel copyWith({
    String? id,
    String? name,
    String? displayName,
    String? description,
    double? price,
    String? currency,
    String? billingCycle,
    int? trialDays,
    int? maxLocations,
    int? maxUsers,
    int? maxProducts,
    List<String>? features,
    List<String>? aiFeatures,
    bool? popular,
    bool? enterprise,
    bool? active,
    int? sortOrder,
    String? razorpayPlanId,
    double? yearlyDiscount,
    double? twoYearDiscount,
    double? threeYearDiscount,
    int? billingTermMonths,
    bool? autoCreateVariants,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return PlanModel(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      billingCycle: billingCycle ?? this.billingCycle,
      trialDays: trialDays ?? this.trialDays,
      maxLocations: maxLocations ?? this.maxLocations,
      maxUsers: maxUsers ?? this.maxUsers,
      maxProducts: maxProducts ?? this.maxProducts,
      features: features ?? this.features,
      aiFeatures: aiFeatures ?? this.aiFeatures,
      popular: popular ?? this.popular,
      enterprise: enterprise ?? this.enterprise,
      active: active ?? this.active,
      sortOrder: sortOrder ?? this.sortOrder,
      razorpayPlanId: razorpayPlanId ?? this.razorpayPlanId,
      yearlyDiscount: yearlyDiscount ?? this.yearlyDiscount,
      twoYearDiscount: twoYearDiscount ?? this.twoYearDiscount,
      threeYearDiscount: threeYearDiscount ?? this.threeYearDiscount,
      billingTermMonths: billingTermMonths ?? this.billingTermMonths,
      autoCreateVariants: autoCreateVariants ?? this.autoCreateVariants,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  // Helper getters
  String get formattedPrice => '₹${price.toStringAsFixed(0)}';
  bool get isUnlimited =>
      maxLocations == -1 || maxUsers == -1 || maxProducts == -1;
  String get maxLocationsText =>
      maxLocations == -1 ? 'Unlimited' : maxLocations.toString();
  String get maxUsersText => maxUsers == -1 ? 'Unlimited' : maxUsers.toString();
  String get maxProductsText =>
      maxProducts == -1 ? 'Unlimited' : maxProducts.toString();
}

@JsonSerializable()
class BillingOption extends Equatable {
  @JsonKey(name: 'term_months')
  final int termMonths;
  @JsonKey(name: 'term_name')
  final String termName;
  @JsonKey(name: 'base_price')
  final double basePrice;
  @JsonKey(name: 'discount_percent')
  final double discountPercent;
  @JsonKey(name: 'effective_price')
  final double effectivePrice;
  @JsonKey(name: 'total_savings')
  final double totalSavings;
  @JsonKey(name: 'recommended_tag')
  final String recommendedTag;
  @JsonKey(name: 'payment_schedule')
  final String paymentSchedule;
  @JsonKey(name: 'monthly_equivalent')
  final double monthlyEquivalent;

  const BillingOption({
    required this.termMonths,
    required this.termName,
    required this.basePrice,
    required this.discountPercent,
    required this.effectivePrice,
    required this.totalSavings,
    required this.recommendedTag,
    required this.paymentSchedule,
    required this.monthlyEquivalent,
  });

  factory BillingOption.fromJson(Map<String, dynamic> json) =>
      _$BillingOptionFromJson(json);
  Map<String, dynamic> toJson() => _$BillingOptionToJson(this);

  @override
  List<Object?> get props => [
        termMonths,
        termName,
        basePrice,
        discountPercent,
        effectivePrice,
        totalSavings,
        recommendedTag,
        paymentSchedule,
        monthlyEquivalent,
      ];

  // Helper getters
  String get formattedEffectivePrice => '₹${effectivePrice.toStringAsFixed(0)}';
  String get formattedSavings => '₹${totalSavings.toStringAsFixed(0)}';
  String get formattedMonthlyEquivalent =>
      '₹${monthlyEquivalent.toStringAsFixed(0)}';
  bool get hasRecommendedTag => recommendedTag.isNotEmpty;
  bool get hasDiscount => discountPercent > 0;
}

@JsonSerializable()
class PlanWithBillingOptions extends Equatable {
  final PlanModel plan;
  @JsonKey(name: 'billing_options')
  final List<BillingOption> billingOptions;

  const PlanWithBillingOptions({
    required this.plan,
    required this.billingOptions,
  });

  factory PlanWithBillingOptions.fromJson(Map<String, dynamic> json) =>
      _$PlanWithBillingOptionsFromJson(json);
  Map<String, dynamic> toJson() => _$PlanWithBillingOptionsToJson(this);

  @override
  List<Object?> get props => [plan, billingOptions];
}

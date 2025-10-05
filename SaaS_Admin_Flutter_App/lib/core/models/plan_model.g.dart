// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanModel _$PlanModelFromJson(Map<String, dynamic> json) => PlanModel(
      id: json['id'] as String,
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      description: json['description'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      billingCycle: json['billing_cycle'] as String,
      trialDays: (json['trial_days'] as num).toInt(),
      maxLocations: (json['max_locations'] as num).toInt(),
      maxUsers: (json['max_users'] as num).toInt(),
      maxProducts: (json['max_products'] as num).toInt(),
      features:
          (json['features'] as List<dynamic>).map((e) => e as String).toList(),
      aiFeatures: (json['ai_features'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      popular: json['popular'] as bool,
      enterprise: json['enterprise'] as bool,
      active: json['active'] as bool,
      sortOrder: (json['sort_order'] as num).toInt(),
      razorpayPlanId: json['razorpay_plan_id'] as String?,
      yearlyDiscount: (json['yearly_discount'] as num).toDouble(),
      twoYearDiscount: (json['two_year_discount'] as num?)?.toDouble(),
      threeYearDiscount: (json['three_year_discount'] as num?)?.toDouble(),
      billingTermMonths: (json['billing_term_months'] as num).toInt(),
      autoCreateVariants: json['auto_create_variants'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
    );

Map<String, dynamic> _$PlanModelToJson(PlanModel instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'display_name': instance.displayName,
      'description': instance.description,
      'price': instance.price,
      'currency': instance.currency,
      'billing_cycle': instance.billingCycle,
      'trial_days': instance.trialDays,
      'max_locations': instance.maxLocations,
      'max_users': instance.maxUsers,
      'max_products': instance.maxProducts,
      'features': instance.features,
      'ai_features': instance.aiFeatures,
      'popular': instance.popular,
      'enterprise': instance.enterprise,
      'active': instance.active,
      'sort_order': instance.sortOrder,
      'razorpay_plan_id': instance.razorpayPlanId,
      'yearly_discount': instance.yearlyDiscount,
      'two_year_discount': instance.twoYearDiscount,
      'three_year_discount': instance.threeYearDiscount,
      'billing_term_months': instance.billingTermMonths,
      'auto_create_variants': instance.autoCreateVariants,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
      'deleted_at': instance.deletedAt?.toIso8601String(),
    };

BillingOption _$BillingOptionFromJson(Map<String, dynamic> json) =>
    BillingOption(
      termMonths: (json['term_months'] as num).toInt(),
      termName: json['term_name'] as String,
      basePrice: (json['base_price'] as num).toDouble(),
      discountPercent: (json['discount_percent'] as num).toDouble(),
      effectivePrice: (json['effective_price'] as num).toDouble(),
      totalSavings: (json['total_savings'] as num).toDouble(),
      recommendedTag: json['recommended_tag'] as String,
      paymentSchedule: json['payment_schedule'] as String,
      monthlyEquivalent: (json['monthly_equivalent'] as num).toDouble(),
    );

Map<String, dynamic> _$BillingOptionToJson(BillingOption instance) =>
    <String, dynamic>{
      'term_months': instance.termMonths,
      'term_name': instance.termName,
      'base_price': instance.basePrice,
      'discount_percent': instance.discountPercent,
      'effective_price': instance.effectivePrice,
      'total_savings': instance.totalSavings,
      'recommended_tag': instance.recommendedTag,
      'payment_schedule': instance.paymentSchedule,
      'monthly_equivalent': instance.monthlyEquivalent,
    };

PlanWithBillingOptions _$PlanWithBillingOptionsFromJson(
        Map<String, dynamic> json) =>
    PlanWithBillingOptions(
      plan: PlanModel.fromJson(json['plan'] as Map<String, dynamic>),
      billingOptions: (json['billing_options'] as List<dynamic>)
          .map((e) => BillingOption.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PlanWithBillingOptionsToJson(
        PlanWithBillingOptions instance) =>
    <String, dynamic>{
      'plan': instance.plan,
      'billing_options': instance.billingOptions,
    };

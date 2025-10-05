class ApiEndpoints {
  ApiEndpoints._();

  // Base URLs
  static const String baseUrl = 'http://localhost:8095';
  static const String apiPrefix = '/api';

  // Authentication Endpoints
  static const String isAdmin = '$apiPrefix/saas-admin/is-admin';
  static const String sendOTP = '$apiPrefix/saas-admin/send-otp';
  static const String verifyOTP = '$apiPrefix/saas-admin/verify-otp';

  // Dashboard & Analytics - real analytics endpoints
  static const String analyticsDashboard =
      '$apiPrefix/super-admin/analytics/dashboard';
  static const String analyticsRevenue =
      '$apiPrefix/super-admin/analytics/revenue';
  static const String analyticsSubscriptions =
      '$apiPrefix/super-admin/analytics/subscriptions';
  static const String analyticsTenants =
      '$apiPrefix/super-admin/analytics/tenants';

  // Plan Management - using public endpoint temporarily
  static const String plans = '$apiPrefix/plans';
  static const String publicPlans = '$apiPrefix/plans';
  static const String plansWithBillingOptions =
      '$apiPrefix/plans/with-billing-options';
  static String planById(String id) => '$apiPrefix/super-admin/plans/$id';
  static String planFeatures(String id) =>
      '$apiPrefix/super-admin/plans/$id/features';
  static String planDiscounts(String id) =>
      '$apiPrefix/super-admin/plans/$id/discounts';
  static String planValidateLimits(String id) =>
      '$apiPrefix/super-admin/plans/$id/validate-limits';
  static const String initializePlans =
      '$apiPrefix/super-admin/plans/initialize';

  // Tenant Management
  static const String tenants = '$apiPrefix/super-admin/tenants';

  // Subscription Management
  static const String subscriptions = '$apiPrefix/super-admin/subscriptions';
  static String subscriptionById(String id) =>
      '$apiPrefix/super-admin/subscriptions/$id';
  static String subscriptionStatus(String id) =>
      '$apiPrefix/super-admin/subscriptions/$id/status';

  // Discount Management
  static const String discountConfigs =
      '$apiPrefix/super-admin/discounts/configs';
  static String discountConfigById(String id) =>
      '$apiPrefix/super-admin/discounts/configs/$id';
  static const String defaultDiscountConfig =
      '$apiPrefix/super-admin/discounts/configs/default';
  static const String planDiscountOverrides =
      '$apiPrefix/super-admin/discounts/plans/overrides';
  static String planOverrides(String planId) =>
      '$apiPrefix/super-admin/discounts/plans/$planId/overrides';
  static String activePlanOverride(String planId) =>
      '$apiPrefix/super-admin/discounts/plans/$planId/overrides/active';
  static String deactivateOverride(String id) =>
      '$apiPrefix/super-admin/discounts/overrides/$id';
  static const String billingTerms =
      '$apiPrefix/super-admin/discounts/billing-terms';
  static String billingTermById(int termMonths) =>
      '$apiPrefix/super-admin/discounts/billing-terms/$termMonths';
  static const String bulkUpdateDiscounts =
      '$apiPrefix/super-admin/discounts/bulk-update';
  static String applyDiscountTemplate(String templateId) =>
      '$apiPrefix/super-admin/discounts/templates/$templateId/apply';
  static const String discountAnalytics =
      '$apiPrefix/super-admin/discounts/analytics';
  static String effectiveDiscounts(String planId) =>
      '$apiPrefix/super-admin/discounts/plans/$planId/effective';
  static String discountHistory(String planId) =>
      '$apiPrefix/super-admin/discounts/plans/$planId/history';
  static const String initializeDiscounts =
      '$apiPrefix/super-admin/discounts/initialize';

  // Usage Monitoring
  static String trackUsage(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/track';
  static String currentUsage(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/current';
  static String usageMetrics(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/metrics';
  static String usageHistory(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/history';
  static String billingPeriodUsage(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/billing-period';
  static String exportUsage(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/export';
  static String resetUsage(String tenantId) =>
      '$apiPrefix/super-admin/usage/$tenantId/reset';
  static const String allTenantsUsage =
      '$apiPrefix/super-admin/usage/all-tenants';
  static const String usageAlerts = '$apiPrefix/super-admin/usage/alerts';

  // Plan Transitions
  static const String initiateTransition =
      '$apiPrefix/super-admin/transitions/initiate';
  static String transitionHistory(String subscriptionId) =>
      '$apiPrefix/super-admin/transitions/subscription/$subscriptionId/history';
  static String availableTransitions(String subscriptionId) =>
      '$apiPrefix/super-admin/transitions/subscription/$subscriptionId/available';
  static const String previewTransition =
      '$apiPrefix/super-admin/transitions/preview';
  static String transitionStatus(String transitionId) =>
      '$apiPrefix/super-admin/transitions/$transitionId/status';
  static String cancelTransition(String transitionId) =>
      '$apiPrefix/super-admin/transitions/$transitionId/cancel';
  static const String allTransitions = '$apiPrefix/super-admin/transitions/all';
  static const String bulkApproveTransitions =
      '$apiPrefix/super-admin/transitions/bulk-approve';

  // System Management - using working health endpoint
  static const String systemHealth = '/health';
  static const String auditLogs = '$apiPrefix/super-admin/system/audit-logs';
  static const String maintenanceMode =
      '$apiPrefix/super-admin/system/maintenance';

  // Payment Management
  static const String payments = '$apiPrefix/payments';
  static String paymentById(String id) => '$apiPrefix/payments/$id';
  static String refundPayment(String id) => '$apiPrefix/payments/$id/refund';

  // Invoice Management
  static const String invoices = '$apiPrefix/invoices';
  static String invoiceById(String id) => '$apiPrefix/invoices/$id';
  static String downloadInvoice(String id) =>
      '$apiPrefix/invoices/$id/download';

  // Webhooks
  static const String razorpayWebhook = '$apiPrefix/webhooks/razorpay';

  // Brand Management
  static const String brands = '$apiPrefix/super-admin/brands';
  static String brandById(String id) => '$apiPrefix/super-admin/brands/$id';
  static const String brandCategories =
      '$apiPrefix/super-admin/brands/categories';
  static String brandCategoryById(String id) =>
      '$apiPrefix/super-admin/brands/categories/$id';
  static const String brandSubcategories =
      '$apiPrefix/super-admin/brands/subcategories';
  static String brandSubcategoryById(String id) =>
      '$apiPrefix/super-admin/brands/subcategories/$id';
  static const String brandVariants = '$apiPrefix/super-admin/brands/variants';
  static String brandVariantById(String id) =>
      '$apiPrefix/super-admin/brands/variants/$id';
  static const String assignBrandsToTenant =
      '$apiPrefix/super-admin/brands/assign';
  static String tenantBrands(String tenantId) =>
      '$apiPrefix/super-admin/brands/tenants/$tenantId';
  static const String publicBrands = '$apiPrefix/brands/public';
  static const String bulkCreateBrands = '$apiPrefix/super-admin/brands/bulk';

  // Stock Integration Management
  static const String initializeTenantStock = '$apiPrefix/super-admin/stock/initialize';
  static String tenantStockStatus(String tenantId) =>
      '$apiPrefix/super-admin/stock/tenants/$tenantId/status';
  static String bulkUpdateTenantStock(String tenantId) =>
      '$apiPrefix/super-admin/stock/tenants/$tenantId/bulk-update';
  static String tenantStockRecommendations(String tenantId) =>
      '$apiPrefix/super-admin/stock/tenants/$tenantId/recommendations';
  static const String notifyInventoryBrandAssignment =
      '$apiPrefix/super-admin/stock/notify-brand-assignment';
  static String tenantStockSetupStatus(String tenantId) =>
      '$apiPrefix/super-admin/stock/tenants/$tenantId/setup-status';

  // Onboarding Management
  static String tenantOnboardingProgress(String tenantId) =>
      '$apiPrefix/super-admin/onboarding/tenants/$tenantId/progress';
  static const String completeOnboardingStep =
      '$apiPrefix/super-admin/onboarding/complete-step';
  static const String quickSetupRecommendations =
      '$apiPrefix/super-admin/onboarding/quick-setup-recommendations';
  static const String saveBusinessProfile =
      '$apiPrefix/super-admin/onboarding/business-profile';
  static const String completeOnboarding =
      '$apiPrefix/super-admin/onboarding/complete';
  static const String skipOnboarding =
      '$apiPrefix/super-admin/onboarding/skip';

  // Health Check
  static const String health = '/health';
}

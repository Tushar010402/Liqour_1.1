import 'environment_config.dart';

/// API Configuration for LiquorPro
/// Contains all API endpoints and configuration
class ApiConfig {
  // Base URL - Uses environment configuration
  static String get baseUrl => EnvironmentConfig.apiBaseUrl;

  // API Version
  static const String apiVersion = 'v1';

  // Timeout durations - Optimized for responsiveness
  // Connection timeout: 10 seconds (fast fail if server unreachable)
  // Send/Receive timeout: 20 seconds for regular API calls
  // Use uploadTimeout for OCR/file uploads (120 seconds)
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration sendTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 20);

  // Longer timeout for file uploads (OCR, images)
  static const Duration uploadTimeout = Duration(seconds: 120);

  // Security & Logging Configuration
  static bool get enableLogging => EnvironmentConfig.isDevelopment;
  static bool get isProduction => EnvironmentConfig.isProduction;
  static bool get enableCertificatePinning => EnvironmentConfig.isProduction;
  static String get userAgent => 'LiquorPro/$apiVersion (Flutter)';

  // Auth Endpoints
  static const String checkUser = '/api/auth/check-user';
  static const String sendOtp = '/api/auth/send-otp'; // For existing user login
  static const String sendOtpRegistration = '/api/auth/send-otp-registration'; // For new user registration
  static const String verifyOtp = '/api/auth/verify-otp';
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String refreshToken = '/api/auth/refresh';
  static const String logout = '/api/auth/logout';
  static const String forceLoginOtp = '/api/auth/force-login-otp'; // For device limit bypass

  // Session Management Endpoints
  static const String sessions = '/api/auth/sessions'; // GET: list sessions, DELETE: logout all others
  static const String sessionLogout = '/api/auth/sessions'; // DELETE /:id - logout specific device

  // Admin/Shop Endpoints
  static const String shops = '/api/admin/shops';
  static const String createShop = '/api/admin/shops';
  static const String updateShop = '/api/admin/shops'; // + /:id

  // Admin/User Management Endpoints
  static const String adminUsers = '/api/admin/users';
  static const String validatePhone = '/api/admin/validate/phone';
  static const String validateEmail = '/api/admin/validate/email';

  // Inventory Endpoints
  static const String categories = '/api/inventory/categories';
  static const String brands = '/api/inventory/brands';
  static const String products = '/api/inventory/products';
  static const String stocks = '/api/inventory/stocks';
  static const String stocksAdjust = '/api/inventory/stocks/adjust';
  static const String stocksTransfer = '/api/inventory/stocks/transfer';
  static const String stocksMovements = '/api/inventory/stocks/movements';

  // SaaS Brand Catalog Endpoints (NEW - from backend)
  static const String saasBrandsAvailable = '/api/inventory/saas-brands/available';
  static const String saasBrandsOnboard = '/api/inventory/saas-brands/onboard';
  static const String saasBrandVariants = '/api/inventory/saas-brands';  // /:id/variants

  // Brand Excel Import/Export Endpoints
  static const String brandTemplateDownload = '/api/super-admin/brands/template/download';
  static const String brandBulkImport = '/api/super-admin/brands/bulk-import';

  // Sales Endpoints
  static const String sales = '/api/sales';
  static const String salesReturns = '/api/sales/returns';
  static const String dailySales = '/api/sales/daily';
  static const String dailySalesRecords = '/api/sales/daily-sales';  // Correct endpoint
  static const String dailySalesApprove = '/api/sales/daily-sales'; // /:id/approve
  static const String salesDashboard = '/api/sales/dashboard';
  static const String salesDashboardSummary = '/api/sales/dashboard/summary';  // NEW

  // OCR Endpoints (NEW - from backend)
  static const String ocrBatchSessions = '/api/sales/ocr/batch/sessions';
  static const String ocrQuickSale = '/api/sales/ocr/batch/quick-sale';
  static const String ocrProcessImage = '/api/sales/ocr/batch/process';
  static const String ocrConfirmSale = '/api/sales/ocr/batch/confirm';  // /:session_id/confirm

  // Finance Endpoints
  static const String expenses = '/api/finance/expenses';
  static const String vendors = '/api/finance/vendors';
  static const String assistantManagers = '/api/finance/assistant-managers';

  // Cash Management Endpoints (NEW - from backend)
  static const String cashBalance = '/api/finance/cash/balance';
  static const String cashRequest = '/api/finance/cash/request';
  static const String cashRequestsReceived = '/api/finance/cash/requests/received';
  static const String cashRequestsSent = '/api/finance/cash/requests/sent';
  static const String cashRequestApprove = '/api/finance/cash/requests';  // /:id/approve
  static const String cashRequestReject = '/api/finance/cash/requests';  // /:id/reject
  static const String cashSubmit = '/api/finance/cash/submit';
  static const String cashSubmissions = '/api/finance/cash/submissions';
  static const String cashTransactions = '/api/finance/cash/transactions';
  static const String cashCollections = '/api/finance/cash/collections';

  // Notification Endpoints (server-side settings)
  static const String notifications = '/api/notifications';
  static const String notificationPreferences = '/api/notifications/preferences';
  static const String notificationUnreadCount = '/api/notifications/unread-count';
  static const String notificationMarkAllRead = '/api/notifications/mark-all-read';
  static const String notificationRegisterDevice = '/api/notifications/devices';
  static const String notificationUnregisterDevice = '/api/notifications/devices';
  static const String notificationSend = '/api/notifications/send';
  static const String notificationChannels = '/api/notifications/channels';
  static const String notificationRules = '/api/notification-rules';  // Admin only
  static const String notificationTest = '/api/notifications/test';

  // Gateway Endpoints (NEW - from backend)
  static const String gatewayVersion = '/gateway/version';
  static const String gatewayServices = '/gateway/services';
  static const String websocketStats = '/ws/stats';

  // Helper method to build full URL
  static String buildUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }

  // Helper method to replace path parameters
  static String buildUrlWithParams(String endpoint, Map<String, dynamic> params) {
    String url = endpoint;
    params.forEach((key, value) {
      url = url.replaceAll('{$key}', value.toString());
    });
    return '$baseUrl$url';
  }
}

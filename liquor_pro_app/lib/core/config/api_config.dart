import 'environment_config.dart';

/// API Configuration for LiquorPro
/// Contains all API endpoints and configuration
class ApiConfig {
  // Base URL - Uses environment configuration
  static String get baseUrl => EnvironmentConfig.apiBaseUrl;

  // API Version
  static const String apiVersion = 'v1';

  // Timeout durations - Uses environment configuration
  static Duration get connectionTimeout => EnvironmentConfig.apiTimeout;
  static Duration get receiveTimeout => EnvironmentConfig.apiTimeout;

  // Auth Endpoints
  static const String checkUser = '/api/auth/check-user';
  static const String sendOtp = '/api/auth/send-otp'; // For existing user login
  static const String sendOtpRegistration = '/api/auth/send-otp-registration'; // For new user registration
  static const String verifyOtp = '/api/auth/verify-otp';
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String refreshToken = '/api/auth/refresh';
  static const String logout = '/api/auth/logout';

  // Admin/Shop Endpoints
  static const String shops = '/api/admin/shops';
  static const String createShop = '/api/admin/shops';
  static const String updateShop = '/api/admin/shops'; // + /:id

  // Inventory Endpoints
  static const String categories = '/api/inventory/categories';
  static const String brands = '/api/inventory/brands';
  static const String products = '/api/inventory/products';
  static const String stocks = '/api/inventory/stocks';
  static const String stocksAdjust = '/api/inventory/stocks/adjust';
  static const String stocksTransfer = '/api/inventory/stocks/transfer';
  static const String stocksMovements = '/api/inventory/stocks/movements';

  // Sales Endpoints
  static const String sales = '/api/sales';
  static const String salesReturns = '/api/sales/returns';
  static const String dailySales = '/api/sales/daily';
  static const String salesDashboard = '/api/sales/dashboard';

  // Finance Endpoints
  static const String expenses = '/api/finance/expenses';
  static const String vendors = '/api/finance/vendors';
  static const String assistantManagers = '/api/finance/assistant-managers';

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

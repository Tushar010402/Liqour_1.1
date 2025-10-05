# Flutter Frontend - Backend Integration Guide

## Overview
This guide provides complete instructions for integrating the Flutter frontend with the SaaS Admin Backend service running on port 8095.

## Table of Contents
1. [Project Setup](#project-setup)
2. [API Service Configuration](#api-service-configuration)
3. [Authentication Implementation](#authentication-implementation)
4. [Data Models](#data-models)
5. [Service Classes](#service-classes)
6. [State Management](#state-management)
7. [UI Integration Examples](#ui-integration-examples)
8. [Error Handling](#error-handling)
9. [Testing](#testing)

---

## 1. Project Setup

### Dependencies
Add these to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0
  shared_preferences: ^2.2.0
  provider: ^6.0.5
  jwt_decoder: ^2.0.1
  dio: ^5.3.0  # Alternative to http for advanced features

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.0
  build_runner: ^2.4.0
```

### Directory Structure
```
lib/
├── config/
│   └── api_config.dart
├── models/
│   ├── user_model.dart
│   ├── plan_model.dart
│   ├── tenant_model.dart
│   ├── subscription_model.dart
│   └── api_response_model.dart
├── services/
│   ├── api_service.dart
│   ├── auth_service.dart
│   ├── plan_service.dart
│   ├── tenant_service.dart
│   └── subscription_service.dart
├── providers/
│   ├── auth_provider.dart
│   ├── plan_provider.dart
│   └── tenant_provider.dart
├── screens/
│   ├── auth/
│   ├── dashboard/
│   ├── plans/
│   └── tenants/
└── widgets/
    ├── common/
    └── forms/
```

---

## 2. API Service Configuration

### `lib/config/api_config.dart`
```dart
class ApiConfig {
  static const String baseUrl = 'http://localhost:8095';
  static const String apiVersion = '/api';

  // Endpoints
  static const String healthEndpoint = '/health';
  static const String authEndpoint = '/saas-admin';
  static const String superAdminEndpoint = '/super-admin';

  // Auth endpoints
  static const String isAdminEndpoint = '$authEndpoint/is-admin';
  static const String sendOtpEndpoint = '$authEndpoint/send-otp';
  static const String verifyOtpEndpoint = '$authEndpoint/verify-otp';

  // Super admin endpoints
  static const String tenantsEndpoint = '$superAdminEndpoint/tenants';
  static const String plansEndpoint = '$superAdminEndpoint/plans';
  static const String subscriptionsEndpoint = '$superAdminEndpoint/subscriptions';
  static const String brandsEndpoint = '$superAdminEndpoint/brands';
  static const String analyticsEndpoint = '$superAdminEndpoint/analytics';
  static const String systemEndpoint = '$superAdminEndpoint/system';

  // Public endpoints
  static const String publicPlansEndpoint = '/plans';
  static const String publicBrandsEndpoint = '/brands/public';

  // Request timeout
  static const Duration timeout = Duration(seconds: 30);

  // Demo credentials
  static const String demoMobile = '+918630668488';
  static const String demoOtp = '111111';
}
```

---

## 3. Authentication Implementation

### `lib/services/auth_service.dart`
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../models/api_response_model.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';

  // Check if mobile is registered as SaaS admin
  Future<ApiResponse<bool>> isAdmin(String mobile) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}${ApiConfig.isAdminEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mobile': mobile}),
      ).timeout(ApiConfig.timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data['is_saas_admin'] as bool);
      } else {
        return ApiResponse.error(data['error'] ?? 'Failed to check admin status');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Send OTP
  Future<ApiResponse<String>> sendOtp(String mobile) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}${ApiConfig.sendOtpEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mobile': mobile}),
      ).timeout(ApiConfig.timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data['message']);
      } else {
        return ApiResponse.error(data['error'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Verify OTP and login
  Future<ApiResponse<UserModel>> verifyOtpAndLogin(String mobile, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}${ApiConfig.verifyOtpEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'mobile': mobile, 'otp': otp}),
      ).timeout(ApiConfig.timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final token = data['token'];
        final userData = UserModel.fromJson(data['user']);

        await _storeAuthData(token, userData);
        return ApiResponse.success(userData);
      } else {
        return ApiResponse.error(data['error'] ?? 'Login failed');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Store auth data locally
  Future<void> _storeAuthData(String token, UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  // Get stored token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Get stored user data
  Future<UserModel?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString(_userKey);
    if (userData != null) {
      return UserModel.fromJson(jsonDecode(userData));
    }
    return null;
  }

  // Check if user is logged in and token is valid
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    if (token == null) return false;

    try {
      return !JwtDecoder.isExpired(token);
    } catch (e) {
      return false;
    }
  }

  // Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  // Get auth headers for API calls
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
```

### `lib/services/api_service.dart`
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/api_response_model.dart';
import 'auth_service.dart';

class ApiService {
  final AuthService _authService;

  ApiService(this._authService);

  // Generic GET request
  Future<ApiResponse<T>> get<T>(
    String endpoint,
    T Function(Map<String, dynamic>) fromJson, {
    Map<String, String>? queryParams,
    bool requireAuth = true,
  }) async {
    try {
      Uri uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }

      Map<String, String> headers = requireAuth
          ? await _authService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.get(uri, headers: headers).timeout(ApiConfig.timeout);

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Generic POST request
  Future<ApiResponse<T>> post<T>(
    String endpoint,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson, {
    bool requireAuth = true,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}$endpoint');

      Map<String, String> headers = requireAuth
          ? await _authService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(ApiConfig.timeout);

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Generic PUT request
  Future<ApiResponse<T>> put<T>(
    String endpoint,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson, {
    bool requireAuth = true,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}$endpoint');

      Map<String, String> headers = requireAuth
          ? await _authService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.put(
        uri,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(ApiConfig.timeout);

      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Generic DELETE request
  Future<ApiResponse<bool>> delete(
    String endpoint, {
    bool requireAuth = true,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiVersion}$endpoint');

      Map<String, String> headers = requireAuth
          ? await _authService.getAuthHeaders()
          : {'Content-Type': 'application/json'};

      final response = await http.delete(uri, headers: headers).timeout(ApiConfig.timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(true);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Delete operation failed');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }

  // Handle response
  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    try {
      final data = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse.success(fromJson(data));
      } else {
        return ApiResponse.error(data['error'] ?? 'Request failed');
      }
    } catch (e) {
      return ApiResponse.error('Failed to parse response: $e');
    }
  }

  // Health check
  Future<ApiResponse<Map<String, dynamic>>> healthCheck() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.healthEndpoint}'),
      ).timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        return ApiResponse.success(jsonDecode(response.body));
      } else {
        return ApiResponse.error('Service unhealthy');
      }
    } catch (e) {
      return ApiResponse.error('Network error: $e');
    }
  }
}
```

---

## 4. Data Models

### `lib/models/api_response_model.dart`
```dart
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? error;

  ApiResponse._({required this.success, this.data, this.error});

  factory ApiResponse.success(T data) {
    return ApiResponse._(success: true, data: data);
  }

  factory ApiResponse.error(String error) {
    return ApiResponse._(success: false, error: error);
  }
}
```

### `lib/models/user_model.dart`
```dart
class UserModel {
  final String id;
  final String name;
  final String firstName;
  final String lastName;
  final String email;
  final String mobile;
  final String role;
  final bool active;

  UserModel({
    required this.id,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.mobile,
    required this.role,
    required this.active,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      email: json['email'] ?? '',
      mobile: json['mobile'] ?? '',
      role: json['role'] ?? '',
      active: json['active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'mobile': mobile,
      'role': role,
      'active': active,
    };
  }
}
```

### `lib/models/plan_model.dart`
```dart
class PlanModel {
  final String id;
  final String name;
  final String displayName;
  final String description;
  final int price;
  final String currency;
  final String billingCycle;
  final int trialDays;
  final int yearlyDiscount;
  final int maxUsers;
  final int maxProducts;
  final int maxLocations;
  final List<String> features;
  final List<String>? aiFeatures;
  final bool popular;
  final bool enterprise;
  final int sortOrder;

  PlanModel({
    required this.id,
    required this.name,
    required this.displayName,
    required this.description,
    required this.price,
    required this.currency,
    required this.billingCycle,
    required this.trialDays,
    required this.yearlyDiscount,
    required this.maxUsers,
    required this.maxProducts,
    required this.maxLocations,
    required this.features,
    this.aiFeatures,
    required this.popular,
    required this.enterprise,
    required this.sortOrder,
  });

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      displayName: json['display_name'] ?? '',
      description: json['description'] ?? '',
      price: json['price'] ?? 0,
      currency: json['currency'] ?? 'INR',
      billingCycle: json['billing_cycle'] ?? 'monthly',
      trialDays: json['trial_days'] ?? 0,
      yearlyDiscount: json['yearly_discount'] ?? 0,
      maxUsers: json['max_users'] ?? 0,
      maxProducts: json['max_products'] ?? 0,
      maxLocations: json['max_locations'] ?? 0,
      features: List<String>.from(json['features'] ?? []),
      aiFeatures: json['ai_features'] != null ? List<String>.from(json['ai_features']) : null,
      popular: json['popular'] ?? false,
      enterprise: json['enterprise'] ?? false,
      sortOrder: json['sort_order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'display_name': displayName,
      'description': description,
      'price': price,
      'currency': currency,
      'billing_cycle': billingCycle,
      'trial_days': trialDays,
      'yearly_discount': yearlyDiscount,
      'max_users': maxUsers,
      'max_products': maxProducts,
      'max_locations': maxLocations,
      'features': features,
      'ai_features': aiFeatures,
      'popular': popular,
      'enterprise': enterprise,
      'sort_order': sortOrder,
    };
  }
}
```

### `lib/models/tenant_model.dart`
```dart
class TenantModel {
  final String id;
  final String name;
  final String email;
  final String status;
  final String subscriptionPlan;
  final DateTime createdAt;
  final DateTime lastActive;
  final int usersCount;
  final int locationsCount;
  final int productsCount;

  TenantModel({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.subscriptionPlan,
    required this.createdAt,
    required this.lastActive,
    required this.usersCount,
    required this.locationsCount,
    required this.productsCount,
  });

  factory TenantModel.fromJson(Map<String, dynamic> json) {
    return TenantModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      status: json['status'] ?? '',
      subscriptionPlan: json['subscription_plan'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      lastActive: DateTime.parse(json['last_active']),
      usersCount: json['users_count'] ?? 0,
      locationsCount: json['locations_count'] ?? 0,
      productsCount: json['products_count'] ?? 0,
    );
  }
}
```

---

## 5. Service Classes

### `lib/services/plan_service.dart`
```dart
import '../models/plan_model.dart';
import '../models/api_response_model.dart';
import '../config/api_config.dart';
import 'api_service.dart';

class PlanService {
  final ApiService _apiService;

  PlanService(this._apiService);

  // Get public plans
  Future<ApiResponse<List<PlanModel>>> getPublicPlans() async {
    final response = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.publicPlansEndpoint,
      (data) => data,
      requireAuth: false,
    );

    if (response.success && response.data != null) {
      final plans = (response.data!['plans'] as List)
          .map((plan) => PlanModel.fromJson(plan))
          .toList();
      return ApiResponse.success(plans);
    }

    return ApiResponse.error(response.error ?? 'Failed to fetch plans');
  }

  // Get all plans (admin)
  Future<ApiResponse<List<PlanModel>>> getAllPlans() async {
    final response = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.plansEndpoint,
      (data) => data,
    );

    if (response.success && response.data != null) {
      final plans = (response.data!['plans'] as List)
          .map((plan) => PlanModel.fromJson(plan))
          .toList();
      return ApiResponse.success(plans);
    }

    return ApiResponse.error(response.error ?? 'Failed to fetch plans');
  }

  // Create plan
  Future<ApiResponse<PlanModel>> createPlan(Map<String, dynamic> planData) async {
    final response = await _apiService.post<PlanModel>(
      ApiConfig.plansEndpoint,
      planData,
      (data) => PlanModel.fromJson(data['plan']),
    );

    return response;
  }

  // Update plan
  Future<ApiResponse<PlanModel>> updatePlan(String planId, Map<String, dynamic> planData) async {
    final response = await _apiService.put<PlanModel>(
      '${ApiConfig.plansEndpoint}/$planId',
      planData,
      (data) => PlanModel.fromJson(data['plan']),
    );

    return response;
  }

  // Delete plan
  Future<ApiResponse<bool>> deletePlan(String planId) async {
    return await _apiService.delete('${ApiConfig.plansEndpoint}/$planId');
  }
}
```

### `lib/services/tenant_service.dart`
```dart
import '../models/tenant_model.dart';
import '../models/api_response_model.dart';
import '../config/api_config.dart';
import 'api_service.dart';

class TenantService {
  final ApiService _apiService;

  TenantService(this._apiService);

  // Get all tenants
  Future<ApiResponse<List<TenantModel>>> getAllTenants() async {
    final response = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.tenantsEndpoint,
      (data) => data,
    );

    if (response.success && response.data != null) {
      final tenants = (response.data!['tenants'] as List)
          .map((tenant) => TenantModel.fromJson(tenant))
          .toList();
      return ApiResponse.success(tenants);
    }

    return ApiResponse.error(response.error ?? 'Failed to fetch tenants');
  }

  // Get tenant usage
  Future<ApiResponse<Map<String, dynamic>>> getTenantUsage(String tenantId) async {
    final response = await _apiService.get<Map<String, dynamic>>(
      '${ApiConfig.superAdminEndpoint}/usage/$tenantId/current',
      (data) => data,
    );

    return response;
  }
}
```

---

## 6. State Management with Provider

### `lib/providers/auth_provider.dart`
```dart
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService;

  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  AuthProvider(this._authService);

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  // Check admin status
  Future<bool> isAdmin(String mobile) async {
    _setLoading(true);
    final response = await _authService.isAdmin(mobile);
    _setLoading(false);

    if (response.success) {
      return response.data ?? false;
    } else {
      _setError(response.error);
      return false;
    }
  }

  // Send OTP
  Future<bool> sendOtp(String mobile) async {
    _setLoading(true);
    final response = await _authService.sendOtp(mobile);
    _setLoading(false);

    if (response.success) {
      _clearError();
      return true;
    } else {
      _setError(response.error);
      return false;
    }
  }

  // Login
  Future<bool> login(String mobile, String otp) async {
    _setLoading(true);
    final response = await _authService.verifyOtpAndLogin(mobile, otp);
    _setLoading(false);

    if (response.success) {
      _user = response.data;
      _clearError();
      notifyListeners();
      return true;
    } else {
      _setError(response.error);
      return false;
    }
  }

  // Check if user is logged in on app start
  Future<void> checkAuthStatus() async {
    _setLoading(true);
    final isLoggedIn = await _authService.isLoggedIn();

    if (isLoggedIn) {
      _user = await _authService.getUser();
    }

    _setLoading(false);
    notifyListeners();
  }

  // Logout
  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _clearError();
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}
```

### `lib/providers/plan_provider.dart`
```dart
import 'package:flutter/foundation.dart';
import '../models/plan_model.dart';
import '../services/plan_service.dart';

class PlanProvider with ChangeNotifier {
  final PlanService _planService;

  List<PlanModel> _plans = [];
  bool _isLoading = false;
  String? _error;

  PlanProvider(this._planService);

  List<PlanModel> get plans => _plans;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Load public plans
  Future<void> loadPublicPlans() async {
    _setLoading(true);
    final response = await _planService.getPublicPlans();

    if (response.success) {
      _plans = response.data ?? [];
      _clearError();
    } else {
      _setError(response.error);
    }

    _setLoading(false);
  }

  // Load all plans (admin)
  Future<void> loadAllPlans() async {
    _setLoading(true);
    final response = await _planService.getAllPlans();

    if (response.success) {
      _plans = response.data ?? [];
      _clearError();
    } else {
      _setError(response.error);
    }

    _setLoading(false);
  }

  // Create plan
  Future<bool> createPlan(Map<String, dynamic> planData) async {
    _setLoading(true);
    final response = await _planService.createPlan(planData);

    if (response.success) {
      await loadAllPlans(); // Reload plans
      _clearError();
      _setLoading(false);
      return true;
    } else {
      _setError(response.error);
      _setLoading(false);
      return false;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}
```

---

## 7. UI Integration Examples

### `lib/screens/auth/login_screen.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../config/api_config.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobileController = TextEditingController(text: ApiConfig.demoMobile);
  final _otpController = TextEditingController();
  bool _otpSent = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SaaS Admin Login')),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (authProvider.error != null)
                  Container(
                    padding: EdgeInsets.all(12),
                    margin: EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      authProvider.error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),

                TextField(
                  controller: _mobileController,
                  decoration: InputDecoration(
                    labelText: 'Mobile Number',
                    enabled: !_otpSent && !authProvider.isLoading,
                  ),
                  keyboardType: TextInputType.phone,
                ),

                SizedBox(height: 16),

                if (_otpSent)
                  TextField(
                    controller: _otpController,
                    decoration: InputDecoration(
                      labelText: 'OTP (Use: ${ApiConfig.demoOtp})',
                    ),
                    keyboardType: TextInputType.number,
                  ),

                SizedBox(height: 24),

                if (!_otpSent)
                  ElevatedButton(
                    onPressed: authProvider.isLoading ? null : _sendOtp,
                    child: authProvider.isLoading
                        ? CircularProgressIndicator()
                        : Text('Send OTP'),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: authProvider.isLoading ? null : _verifyOtp,
                          child: authProvider.isLoading
                              ? CircularProgressIndicator()
                              : Text('Login'),
                        ),
                      ),
                      SizedBox(width: 12),
                      TextButton(
                        onPressed: () => setState(() => _otpSent = false),
                        child: Text('Back'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _sendOtp() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // First check if mobile is admin
    final isAdmin = await authProvider.isAdmin(_mobileController.text);
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mobile number not registered as SaaS admin')),
      );
      return;
    }

    // Send OTP
    final success = await authProvider.sendOtp(_mobileController.text);
    if (success) {
      setState(() => _otpSent = true);
      _otpController.text = ApiConfig.demoOtp; // Pre-fill for demo
    }
  }

  Future<void> _verifyOtp() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.login(
      _mobileController.text,
      _otpController.text,
    );

    if (success) {
      Navigator.of(context).pushReplacementNamed('/dashboard');
    }
  }
}
```

### `lib/screens/dashboard/dashboard_screen.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/plan_provider.dart';
import '../plans/plans_screen.dart';
import '../tenants/tenants_screen.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    DashboardHome(),
    PlansScreen(),
    TenantsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('SaaS Admin Dashboard'),
        actions: [
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return Row(
                children: [
                  Text('Hello, ${authProvider.user?.name ?? 'Admin'}'),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.logout),
                    onPressed: () async {
                      await authProvider.logout();
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.layers), label: 'Plans'),
          BottomNavigationBarItem(icon: Icon(Icons.business), label: 'Tenants'),
        ],
      ),
    );
  }
}

class DashboardHome extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Welcome to SaaS Admin Dashboard', style: TextStyle(fontSize: 24)),
          SizedBox(height: 20),
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return Card(
                margin: EdgeInsets.all(16),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('User Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Name: ${authProvider.user?.name}'),
                      Text('Email: ${authProvider.user?.email}'),
                      Text('Mobile: ${authProvider.user?.mobile}'),
                      Text('Role: ${authProvider.user?.role}'),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

---

## 8. Error Handling

### Global Error Handler
```dart
class ErrorHandler {
  static void showErrorSnackBar(BuildContext context, String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  static Widget buildErrorWidget(String error, VoidCallback? onRetry) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(error, style: TextStyle(fontSize: 16)),
          if (onRetry != null) ...[
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
```

---

## 9. Testing

### Unit Tests Example
```dart
// test/services/auth_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;
import 'package:your_app/services/auth_service.dart';

class MockClient extends Mock implements http.Client {}

void main() {
  group('AuthService', () {
    late AuthService authService;
    late MockClient mockClient;

    setUp(() {
      mockClient = MockClient();
      authService = AuthService();
    });

    test('should return true when mobile is admin', () async {
      // Mock response
      when(mockClient.post(any, headers: anyNamed('headers'), body: anyNamed('body')))
          .thenAnswer((_) async => http.Response('{"is_saas_admin": true, "mobile": "+918630668488"}', 200));

      final result = await authService.isAdmin('+918630668488');

      expect(result.success, true);
      expect(result.data, true);
    });
  });
}
```

---

## Main App Setup

### `lib/main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/plan_service.dart';
import 'services/tenant_service.dart';
import 'providers/auth_provider.dart';
import 'providers/plan_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final apiService = ApiService(authService);

    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => authService),
        Provider<ApiService>(create: (_) => apiService),
        Provider<PlanService>(create: (_) => PlanService(apiService)),
        Provider<TenantService>(create: (_) => TenantService(apiService)),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(authService)..checkAuthStatus(),
        ),
        ChangeNotifierProvider<PlanProvider>(
          create: (_) => PlanProvider(PlanService(apiService)),
        ),
      ],
      child: MaterialApp(
        title: 'SaaS Admin App',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: Consumer<AuthProvider>(
          builder: (context, authProvider, child) {
            if (authProvider.isLoading) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            return authProvider.isLoggedIn ? DashboardScreen() : LoginScreen();
          },
        ),
        routes: {
          '/login': (context) => LoginScreen(),
          '/dashboard': (context) => DashboardScreen(),
        },
      ),
    );
  }
}
```

This comprehensive integration guide provides everything needed to connect your Flutter frontend with the SaaS Admin backend service. The code includes proper error handling, state management, and follows Flutter best practices for API integration.
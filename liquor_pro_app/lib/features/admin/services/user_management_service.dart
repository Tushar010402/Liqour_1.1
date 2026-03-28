import '../../../core/services/dio_api_service.dart';
import '../../../core/config/api_config.dart';
import '../../../core/exceptions/api_exception.dart';
import '../models/user_management_models.dart';

/// User Management Service - Handles all user management API calls
class UserManagementService {
  final DioApiService _apiService;

  UserManagementService(this._apiService);

  /// Get list of users with pagination
  /// GET /api/admin/users?page=1&page_size=20
  Future<UserListResponse?> getUsers({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '${ApiConfig.adminUsers}?page=$page&page_size=$pageSize',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        // Debug: Log raw API response to check shop_id
        final users = response.data!['users'] as List<dynamic>?;
        if (users != null && users.isNotEmpty) {
          print('📋 [UserService] RAW API Response - checking shop_id fields:');
          for (final user in users) {
            final firstName = user['first_name'] ?? '';
            final lastName = user['last_name'] ?? '';
            final shopId = user['shop_id'];
            final shopName = user['shop_name'];
            final role = user['role'];
            if (role == 'salesman') {
              print('   👤 $firstName $lastName (salesman):');
              print('      shop_id: "$shopId" (type: ${shopId?.runtimeType})');
              print('      shop_name: "$shopName"');
            }
          }
        }
        return UserListResponse.fromJson(response.data!);
      }

      return null;
    } catch (e) {
      print('Error getting users: $e');
      return null;
    }
  }

  /// Get user by ID
  /// GET /api/admin/users/:id
  Future<UserItem?> getUserById(String userId) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '${ApiConfig.adminUsers}/$userId',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return UserItem.fromJson(response.data!);
      }

      return null;
    } catch (e) {
      print('Error getting user by ID: $e');
      return null;
    }
  }

  /// Create new user
  /// POST /api/admin/users
  Future<UserItem?> createUser(CreateUserRequest request) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        ApiConfig.adminUsers,
        body: request.toJson(),
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return UserItem.fromJson(response.data!);
      }

      // Throw ApiException with actual backend error message
      throw ApiException.fromResponse(
        message: response.message ?? 'Failed to create user',
        statusCode: response.statusCode,
        errors: response.errors,
      );
    } catch (e) {
      print('Error creating user: $e');
      // Re-throw ApiException as-is, wrap other exceptions
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException.network(e.toString());
    }
  }

  /// Update user
  /// PUT /api/admin/users/:id
  Future<UserItem?> updateUser(String userId, UpdateUserRequest request) async {
    try {
      final response = await _apiService.put<Map<String, dynamic>>(
        '${ApiConfig.adminUsers}/$userId',
        body: request.toJson(),
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return UserItem.fromJson(response.data!);
      }

      // Throw ApiException with actual backend error message
      throw ApiException.fromResponse(
        message: response.message ?? 'Failed to update user',
        statusCode: response.statusCode,
        errors: response.errors,
      );
    } catch (e) {
      print('Error updating user: $e');
      // Re-throw ApiException as-is, wrap other exceptions
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException.network(e.toString());
    }
  }

  /// Delete user (admin only)
  /// DELETE /api/admin/users/:id
  Future<bool> deleteUser(String userId) async {
    try {
      final response = await _apiService.delete<Map<String, dynamic>>(
        '${ApiConfig.adminUsers}/$userId',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess) {
        return true;
      }

      // Throw ApiException with actual backend error message
      throw ApiException.fromResponse(
        message: response.message ?? 'Failed to delete user',
        statusCode: response.statusCode,
        errors: response.errors,
      );
    } catch (e) {
      print('Error deleting user: $e');
      // Re-throw ApiException as-is, wrap other exceptions
      if (e is ApiException) {
        rethrow;
      }
      throw ApiException.network(e.toString());
    }
  }

  /// Activate user
  Future<UserItem?> activateUser(String userId) async {
    return updateUser(userId, UpdateUserRequest(isActive: true));
  }

  /// Deactivate user
  Future<UserItem?> deactivateUser(String userId) async {
    return updateUser(userId, UpdateUserRequest(isActive: false));
  }

  /// Search users (client-side filtering for now)
  Future<List<UserItem>> searchUsers({
    required String query,
    String? roleFilter,
    int page = 1,
    int pageSize = 100,
  }) async {
    final response = await getUsers(page: page, pageSize: pageSize);

    if (response == null) return [];

    var users = response.users;

    // Filter by query
    if (query.isNotEmpty) {
      final lowerQuery = query.toLowerCase();
      users = users.where((user) {
        return user.firstName.toLowerCase().contains(lowerQuery) ||
            user.lastName.toLowerCase().contains(lowerQuery) ||
            user.username.toLowerCase().contains(lowerQuery) ||
            user.email.toLowerCase().contains(lowerQuery);
      }).toList();
    }

    // Filter by role
    if (roleFilter != null && roleFilter != 'all') {
      users = users.where((user) => user.role == roleFilter).toList();
    }

    return users;
  }

  /// Get users by role
  Future<List<UserItem>> getUsersByRole(String role) async {
    final response = await getUsers(page: 1, pageSize: 100);

    if (response == null) return [];

    return response.users.where((user) => user.role == role).toList();
  }

  /// Get user statistics
  Future<Map<String, int>> getUserStats() async {
    final response = await getUsers(page: 1, pageSize: 1000);

    if (response == null) {
      return {
        'total': 0,
        'active': 0,
        'inactive': 0,
        'admin': 0,
        'manager': 0,
        'executive': 0,
        'salesman': 0,
        'assistant_manager': 0,
      };
    }

    final users = response.users;

    return {
      'total': users.length,
      'active': users.where((u) => u.isActive).length,
      'inactive': users.where((u) => !u.isActive).length,
      'admin': users.where((u) => u.role == UserRole.admin).length,
      'manager': users.where((u) => u.role == UserRole.manager).length,
      'executive': users.where((u) => u.role == UserRole.executive).length,
      'salesman': users.where((u) => u.role == UserRole.salesman).length,
      'assistant_manager':
          users.where((u) => u.role == UserRole.assistantManager).length,
    };
  }

  /// Validate phone number availability
  /// GET /api/admin/validate/phone?phone=+919999888877
  /// Returns ValidationResponse with availability status
  Future<ValidationResponse> validatePhoneAvailability(String phone) async {
    try {
      // DEBUG: Log the validation attempt
      print('🔍 [UserManagement] Validating phone availability');
      print('   Phone: $phone');
      print('   Endpoint: ${ApiConfig.validatePhone}');
      print('   Full URL: ${ApiConfig.validatePhone}?phone=${Uri.encodeComponent(phone)}');

      final response = await _apiService.get<Map<String, dynamic>>(
        '${ApiConfig.validatePhone}?phone=${Uri.encodeComponent(phone)}',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      // DEBUG: Log the response
      print('📥 [UserManagement] Response received:');
      print('   Success: ${response.isSuccess}');
      print('   Status Code: ${response.statusCode}');
      print('   Message: ${response.message}');
      print('   Has Data: ${response.data != null}');
      print('   Raw Data: ${response.data}');

      if (response.isSuccess && response.data != null) {
        final validationResponse = ValidationResponse.fromJson(response.data!);
        print('✅ [UserManagement] Parsed ValidationResponse:');
        print('   Available: ${validationResponse.available}');
        print('   Message: ${validationResponse.message}');
        return validationResponse;
      }

      print('⚠️ [UserManagement] Validation failed - returning default error');
      return ValidationResponse(
        available: false,
        message: 'Failed to validate phone number',
      );
    } catch (e, stackTrace) {
      print('❌ [UserManagement] Error validating phone: $e');
      print('   Stack trace: $stackTrace');
      return ValidationResponse(
        available: false,
        message: 'Network error - please try again',
      );
    }
  }

  /// Validate email availability
  /// GET /api/admin/validate/email?email=test@example.com
  /// Returns ValidationResponse with availability status
  Future<ValidationResponse> validateEmailAvailability(String email) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '${ApiConfig.validateEmail}?email=${Uri.encodeComponent(email)}',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return ValidationResponse.fromJson(response.data!);
      }

      return ValidationResponse(
        available: false,
        message: 'Failed to validate email address',
      );
    } catch (e) {
      print('Error validating email: $e');
      return ValidationResponse(
        available: false,
        message: 'Network error - please try again',
      );
    }
  }
}

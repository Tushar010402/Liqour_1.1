import 'package:flutter/foundation.dart';
import '../../../core/exceptions/api_exception.dart';
import '../services/user_management_service.dart';
import '../models/user_management_models.dart';

/// User Management Provider - State management for user operations
class UserManagementProvider extends ChangeNotifier {
  final UserManagementService _service;

  List<UserItem> _users = [];
  Map<String, int> _stats = {};
  bool _isLoading = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  String _searchQuery = '';
  String _roleFilter = 'all';
  bool? _statusFilter; // null = all, true = active, false = inactive

  UserManagementProvider(this._service);

  // Getters
  List<UserItem> get users => _users;
  Map<String, int> get stats => _stats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  int get totalCount => _totalCount;
  String get searchQuery => _searchQuery;
  String get roleFilter => _roleFilter;
  bool? get statusFilter => _statusFilter;

  // Filtered users
  List<UserItem> get filteredUsers {
    var filtered = _users;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((user) {
        return user.firstName.toLowerCase().contains(query) ||
            user.lastName.toLowerCase().contains(query) ||
            user.username.toLowerCase().contains(query) ||
            user.email.toLowerCase().contains(query) ||
            (user.phone?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    // Apply role filter
    if (_roleFilter != 'all') {
      filtered = filtered.where((user) => user.role == _roleFilter).toList();
    }

    // Apply status filter
    if (_statusFilter != null) {
      filtered = filtered.where((user) => user.isActive == _statusFilter).toList();
    }

    return filtered;
  }

  // Set search query
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Set role filter
  void setRoleFilter(String role) {
    _roleFilter = role;
    _statusFilter = null; // Clear status filter when role changes
    notifyListeners();
  }

  // Set status filter (true = active, false = inactive, null = all)
  void setStatusFilter(bool? isActive) {
    _statusFilter = isActive;
    _roleFilter = 'all'; // Clear role filter when filtering by status
    notifyListeners();
  }

  // Clear filters
  void clearFilters() {
    _searchQuery = '';
    _roleFilter = 'all';
    _statusFilter = null;
    notifyListeners();
  }

  // Load users
  Future<void> loadUsers({int page = 1, bool showLoading = true}) async {
    if (showLoading) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final response = await _service.getUsers(page: page, pageSize: 20);

      if (response != null) {
        _users = response.users;
        _currentPage = response.page;
        _totalPages = response.totalPages;
        _totalCount = response.totalCount;
        _errorMessage = null;
      } else {
        _errorMessage = 'Failed to load users';
      }
    } catch (e) {
      _errorMessage = e.toString();
      print('Error loading users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Refresh users (for pull-to-refresh)
  Future<void> refreshUsers() async {
    await loadUsers(page: _currentPage, showLoading: false);
  }

  // Load more users (pagination)
  Future<void> loadMoreUsers() async {
    if (_currentPage < _totalPages && !_isLoading) {
      await loadUsers(page: _currentPage + 1, showLoading: true);
    }
  }

  // Create user
  Future<bool> createUser(CreateUserRequest request) async {
    _errorMessage = null;

    try {
      final user = await _service.createUser(request);

      if (user != null) {
        // Insert at beginning of list
        _users.insert(0, user);
        _totalCount++;

        // Reload stats
        await loadStats();

        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Failed to create user';
        notifyListeners();
        return false;
      }
    } on ApiException catch (e) {
      // Industrial-grade error message parsing for better UX
      String friendlyMessage = e.displayMessage;

      final lower = friendlyMessage.toLowerCase();
      if (lower.contains('uq_users_phone') || (lower.contains('phone') && lower.contains('duplicate'))) {
        friendlyMessage = 'This phone number is already registered. Delete the existing user first or use a different number.';
      } else if (lower.contains('users_username_key') || (lower.contains('username') && lower.contains('duplicate'))) {
        friendlyMessage = 'Username already exists. Please try again.';
      } else if (lower.contains('duplicate key') || lower.contains('constraint')) {
        friendlyMessage = 'A user with these details already exists. Please check and try again.';
      } else if (lower.contains('phone') && lower.contains('already')) {
        friendlyMessage = 'This phone number is already registered to another user';
      } else if (lower.contains('email') && lower.contains('already')) {
        friendlyMessage = 'This email address is already in use';
      } else if (lower.contains('shop') && lower.contains('not found')) {
        friendlyMessage = 'Selected shop not found - please refresh and try again';
      }

      _errorMessage = friendlyMessage;
      notifyListeners();
      return false;
    } catch (e) {
      // Fallback for unexpected errors
      _errorMessage = 'Unexpected error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Update user
  Future<bool> updateUser(String userId, UpdateUserRequest request) async {
    _errorMessage = null;

    try {
      final updatedUser = await _service.updateUser(userId, request);

      if (updatedUser != null) {
        // Update in list
        final index = _users.indexWhere((u) => u.id == userId);
        if (index != -1) {
          _users[index] = updatedUser;
        }

        // Reload stats if active status changed
        if (request.isActive != null) {
          await loadStats();
        }

        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Failed to update user';
        notifyListeners();
        return false;
      }
    } on ApiException catch (e) {
      // Extract user-friendly error message from ApiException
      _errorMessage = e.displayMessage;
      notifyListeners();
      return false;
    } catch (e) {
      // Fallback for unexpected errors
      _errorMessage = 'Unexpected error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Delete user
  Future<bool> deleteUser(String userId) async {
    _errorMessage = null;

    try {
      final success = await _service.deleteUser(userId);

      if (success) {
        // Remove from list
        _users.removeWhere((u) => u.id == userId);
        _totalCount--;

        // Reload stats
        await loadStats();

        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Failed to delete user';
        notifyListeners();
        return false;
      }
    } on ApiException catch (e) {
      // Extract user-friendly error message from ApiException
      _errorMessage = e.displayMessage;
      notifyListeners();
      return false;
    } catch (e) {
      // Fallback for unexpected errors
      _errorMessage = 'Unexpected error: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  // Activate user
  Future<bool> activateUser(String userId) async {
    return await updateUser(userId, UpdateUserRequest(isActive: true));
  }

  // Deactivate user
  Future<bool> deactivateUser(String userId) async {
    return await updateUser(userId, UpdateUserRequest(isActive: false));
  }

  // Toggle user active status
  Future<bool> toggleUserStatus(String userId, bool currentStatus) async {
    return await updateUser(
      userId,
      UpdateUserRequest(isActive: !currentStatus),
    );
  }

  // Load user statistics
  Future<void> loadStats() async {
    try {
      _stats = await _service.getUserStats();
      notifyListeners();
    } catch (e) {
      print('Error loading stats: $e');
      // Don't set error message for stats, it's not critical
    }
  }

  // Get user by ID
  Future<UserItem?> getUserById(String userId) async {
    try {
      return await _service.getUserById(userId);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  // Search users (server-side when implemented)
  Future<void> searchUsers(String query, {String? roleFilter}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await _service.searchUsers(
        query: query,
        roleFilter: roleFilter,
      );

      _users = results;
      _searchQuery = query;
      if (roleFilter != null) _roleFilter = roleFilter;
    } catch (e) {
      _errorMessage = e.toString();
      print('Error searching users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get users by role
  Future<void> loadUsersByRole(String role) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _users = await _service.getUsersByRole(role);
      _roleFilter = role;
    } catch (e) {
      _errorMessage = e.toString();
      print('Error loading users by role: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Reset provider state
  void reset() {
    _users = [];
    _stats = {};
    _isLoading = false;
    _errorMessage = null;
    _currentPage = 1;
    _totalPages = 1;
    _totalCount = 0;
    _searchQuery = '';
    _roleFilter = 'all';
    _statusFilter = null;
    notifyListeners();
  }
}

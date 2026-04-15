import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense_header.dart';

/// Provider for managing expense headers
/// Handles default headers and custom headers stored locally
class ExpenseHeaderProvider extends ChangeNotifier {
  static const String _customHeadersKey = 'custom_expense_headers';
  static const String _defaultHeadersStateKey = 'default_expense_headers_state';

  List<ExpenseHeader> _defaultHeaders = [];
  List<ExpenseHeader> _customHeaders = [];
  bool _isLoading = false;

  ExpenseHeaderProvider() {
    _initializeHeaders();
  }

  // Getters
  List<ExpenseHeader> get defaultHeaders => _defaultHeaders;
  List<ExpenseHeader> get customHeaders => _customHeaders;
  bool get isLoading => _isLoading;

  /// Get all active headers (default + custom)
  List<ExpenseHeader> get allActiveHeaders => [
        ..._defaultHeaders.where((h) => h.isActive),
        ..._customHeaders.where((h) => h.isActive),
      ];

  /// Get all headers (including inactive)
  List<ExpenseHeader> get allHeaders => [
        ..._defaultHeaders,
        ..._customHeaders,
      ];

  /// Initialize headers from storage
  Future<void> _initializeHeaders() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Load default headers with saved state
      _defaultHeaders = await _loadDefaultHeadersState();

      // Load custom headers
      _customHeaders = await _loadCustomHeaders();
    } catch (e) {
      debugPrint('Error initializing expense headers: $e');
      _defaultHeaders = ExpenseHeader.defaultHeaders;
      _customHeaders = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load default headers with their saved active state
  Future<List<ExpenseHeader>> _loadDefaultHeadersState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedState = prefs.getString(_defaultHeadersStateKey);

    final defaults = ExpenseHeader.defaultHeaders;

    if (savedState != null) {
      try {
        final Map<String, dynamic> stateMap = json.decode(savedState);
        for (var header in defaults) {
          if (stateMap.containsKey(header.id)) {
            header.isActive = stateMap[header.id] as bool;
          }
        }
      } catch (e) {
        debugPrint('Error parsing default headers state: $e');
      }
    }

    return defaults;
  }

  /// Load custom headers from SharedPreferences
  Future<List<ExpenseHeader>> _loadCustomHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final savedHeaders = prefs.getString(_customHeadersKey);

    if (savedHeaders != null) {
      try {
        final List<dynamic> headersList = json.decode(savedHeaders);
        return headersList
            .map((h) => ExpenseHeader.fromJson(h as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('Error parsing custom headers: $e');
        return [];
      }
    }

    return [];
  }

  /// Save default headers state to SharedPreferences
  Future<void> _saveDefaultHeadersState() async {
    final prefs = await SharedPreferences.getInstance();
    final stateMap = <String, bool>{};
    for (var header in _defaultHeaders) {
      stateMap[header.id] = header.isActive;
    }
    await prefs.setString(_defaultHeadersStateKey, json.encode(stateMap));
  }

  /// Save custom headers to SharedPreferences
  Future<void> _saveCustomHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final headersList = _customHeaders.map((h) => h.toJson()).toList();
    await prefs.setString(_customHeadersKey, json.encode(headersList));
  }

  /// Toggle a header's active state
  Future<void> toggleHeader(String id, bool isActive) async {
    // Check default headers first
    final defaultIndex = _defaultHeaders.indexWhere((h) => h.id == id);
    if (defaultIndex != -1) {
      _defaultHeaders[defaultIndex].isActive = isActive;
      await _saveDefaultHeadersState();
      notifyListeners();
      return;
    }

    // Check custom headers
    final customIndex = _customHeaders.indexWhere((h) => h.id == id);
    if (customIndex != -1) {
      _customHeaders[customIndex].isActive = isActive;
      await _saveCustomHeaders();
      notifyListeners();
    }
  }

  /// Add a new custom header
  Future<bool> addCustomHeader(String name) async {
    // Generate unique ID
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    // Check for duplicate names
    final nameExists = allHeaders.any(
      (h) => h.name.toLowerCase() == name.toLowerCase(),
    );

    if (nameExists) {
      return false; // Name already exists
    }

    final newHeader = ExpenseHeader(
      id: id,
      name: name,
      isDefault: false,
      isActive: true,
    );

    _customHeaders.add(newHeader);
    await _saveCustomHeaders();
    notifyListeners();
    return true;
  }

  /// Update a custom header name
  Future<bool> updateCustomHeader(String id, String newName) async {
    final index = _customHeaders.indexWhere((h) => h.id == id);
    if (index == -1) return false;

    // Check for duplicate names (excluding current)
    final nameExists = allHeaders.any(
      (h) => h.id != id && h.name.toLowerCase() == newName.toLowerCase(),
    );

    if (nameExists) {
      return false;
    }

    _customHeaders[index] = _customHeaders[index].copyWith(name: newName);
    await _saveCustomHeaders();
    notifyListeners();
    return true;
  }

  /// Delete a custom header
  Future<void> deleteCustomHeader(String id) async {
    _customHeaders.removeWhere((h) => h.id == id);
    await _saveCustomHeaders();
    notifyListeners();
  }

  /// Get header by ID
  ExpenseHeader? getHeaderById(String id) {
    try {
      return allHeaders.firstWhere((h) => h.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Refresh headers from storage
  Future<void> refresh() async {
    await _initializeHeaders();
  }

  /// Reset all headers to defaults
  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customHeadersKey);
    await prefs.remove(_defaultHeadersStateKey);
    await _initializeHeaders();
  }

  /// Reset all state — called on logout to prevent stale data
  void reset() {
    _defaultHeaders = [];
    _customHeaders = [];
    _isLoading = false;
    notifyListeners();
  }
}

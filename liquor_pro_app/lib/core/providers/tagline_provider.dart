import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/tagline_constants.dart';
import '../services/dio_api_service.dart';

/// Manages the user's selected tagline, persisted locally and synced to backend.
class TagLineProvider with ChangeNotifier {
  static const _key = 'selected_tagline';

  String _selectedTagLine = TagLineConstants.defaultTagLine;
  DioApiService? _apiService;

  String get selectedTagLine => _selectedTagLine;
  TagLineInfo get selectedInfo => TagLineConstants.getInfo(_selectedTagLine);

  TagLineProvider() {
    _load();
  }

  /// Inject API service for backend sync
  set apiService(DioApiService service) => _apiService = service;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key) ?? TagLineConstants.defaultTagLine;
    // Auto-migrate old English taglines to native script
    _selectedTagLine = TagLineConstants.migrateIfNeeded(saved);
    if (_selectedTagLine != saved) {
      await prefs.setString(_key, _selectedTagLine);
    }
    notifyListeners();
  }

  /// Called after login — sync tagline from user profile
  void syncFromUser(String? tagLine) {
    if (tagLine != null && tagLine.isNotEmpty) {
      _selectedTagLine = TagLineConstants.migrateIfNeeded(tagLine);
      notifyListeners();
      SharedPreferences.getInstance().then((prefs) => prefs.setString(_key, _selectedTagLine));
    }
  }

  /// Reset to default — called on logout
  void reset() {
    _selectedTagLine = TagLineConstants.defaultTagLine;
    notifyListeners();
  }

  /// Set tagline locally, persist, and sync to backend
  Future<void> setTagLine(String tagLine) async {
    _selectedTagLine = tagLine;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, tagLine);

    // Sync to backend profile
    if (_apiService != null) {
      try {
        await _apiService!.put('/api/auth/profile', body: {'tag_line': tagLine});
        debugPrint('[TagLine] Synced to backend: $tagLine');
      } catch (e) {
        debugPrint('[TagLine] Backend sync failed: $e');
      }
    }
  }
}

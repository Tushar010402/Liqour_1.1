import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../theme/app_theme.dart';

/// Global Theme Provider — manages the current theme and persists selection.
class ThemeProvider extends ChangeNotifier {
  final UserPreferences _prefs;
  late String _themeKey;

  ThemeProvider({required UserPreferences prefs}) : _prefs = prefs {
    _themeKey = _prefs.getTheme();
  }

  String get themeKey => _themeKey;

  ThemeData get themeData {
    switch (_themeKey) {
      case 'dark':
        return AppTheme.darkTheme;
      case 'light':
        return AppTheme.coolWhiteTheme;
      case 'warm_white':
      default:
        return AppTheme.warmWhiteTheme;
    }
  }

  ThemeMode get themeMode {
    if (_themeKey == 'dark') return ThemeMode.dark;
    return ThemeMode.light;
  }

  Future<void> setTheme(String key) async {
    _themeKey = key;
    await _prefs.setTheme(key);
    notifyListeners();
  }
}

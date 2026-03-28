import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local Storage for Notification Preferences
/// Stores user notification settings locally since backend doesn't have API
class LocalNotificationStorage {
  static const String _keyPushEnabled = 'notif_push_enabled';
  static const String _keyInAppEnabled = 'notif_in_app_enabled';
  static const String _keyQuietHoursEnabled = 'notif_quiet_hours_enabled';
  static const String _keyQuietHoursStart = 'notif_quiet_hours_start';
  static const String _keyQuietHoursEnd = 'notif_quiet_hours_end';
  static const String _keyReminders = 'notif_reminders';
  static const String _keyCategorySettings = 'notif_category_settings';

  /// Save push notification setting
  static Future<void> setPushEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPushEnabled, enabled);
  }

  /// Get push notification setting
  static Future<bool> getPushEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyPushEnabled) ?? true;
  }

  /// Save in-app notification setting
  static Future<void> setInAppEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyInAppEnabled, enabled);
  }

  /// Get in-app notification setting
  static Future<bool> getInAppEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyInAppEnabled) ?? true;
  }

  /// Save quiet hours enabled setting
  static Future<void> setQuietHoursEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyQuietHoursEnabled, enabled);
  }

  /// Get quiet hours enabled setting
  static Future<bool> getQuietHoursEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyQuietHoursEnabled) ?? false;
  }

  /// Save quiet hours start time
  static Future<void> setQuietHoursStart(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuietHoursStart, '${time.hour}:${time.minute}');
  }

  /// Get quiet hours start time
  static Future<TimeOfDay> getQuietHoursStart() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyQuietHoursStart);
    if (value != null) {
      final parts = value.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    return const TimeOfDay(hour: 22, minute: 0);
  }

  /// Save quiet hours end time
  static Future<void> setQuietHoursEnd(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyQuietHoursEnd, '${time.hour}:${time.minute}');
  }

  /// Get quiet hours end time
  static Future<TimeOfDay> getQuietHoursEnd() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyQuietHoursEnd);
    if (value != null) {
      final parts = value.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    return const TimeOfDay(hour: 7, minute: 0);
  }

  /// Save notification reminders
  static Future<void> setReminders(List<NotificationReminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = reminders.map((r) => r.toJson()).toList();
    await prefs.setString(_keyReminders, jsonEncode(jsonList));
  }

  /// Get notification reminders
  static Future<List<NotificationReminder>> getReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyReminders);
    if (value != null) {
      final List<dynamic> jsonList = jsonDecode(value);
      return jsonList.map((j) => NotificationReminder.fromJson(j)).toList();
    }
    // Return default reminders
    return [
      NotificationReminder(
        id: 'daily_sales',
        name: 'Daily Sales Reminder',
        description: 'Remind if daily sales not submitted',
        category: 'sales',
        enabled: true,
        time: const TimeOfDay(hour: 21, minute: 0),
        days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
      ),
      NotificationReminder(
        id: 'low_stock',
        name: 'Low Stock Alert',
        description: 'Alert when stock runs low',
        category: 'inventory',
        enabled: true,
        time: const TimeOfDay(hour: 9, minute: 0),
        days: ['daily'],
      ),
      NotificationReminder(
        id: 'cash_collection',
        name: 'Cash Collection Reminder',
        description: 'Remind about pending cash collection',
        category: 'finance',
        enabled: false,
        time: const TimeOfDay(hour: 18, minute: 0),
        days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
      ),
    ];
  }

  /// Save category settings
  static Future<void> setCategorySettings(Map<String, CategoryNotificationSetting> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = settings.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_keyCategorySettings, jsonEncode(jsonMap));
  }

  /// Get category settings
  static Future<Map<String, CategoryNotificationSetting>> getCategorySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyCategorySettings);
    if (value != null) {
      final Map<String, dynamic> jsonMap = jsonDecode(value);
      return jsonMap.map((key, value) => MapEntry(
        key,
        CategoryNotificationSetting.fromJson(value),
      ));
    }
    // Return defaults
    return {
      'sales': CategoryNotificationSetting(enabled: true, pushEnabled: true, soundEnabled: true),
      'inventory': CategoryNotificationSetting(enabled: true, pushEnabled: true, soundEnabled: true),
      'finance': CategoryNotificationSetting(enabled: true, pushEnabled: true, soundEnabled: false),
      'security': CategoryNotificationSetting(enabled: true, pushEnabled: true, soundEnabled: true),
      'system': CategoryNotificationSetting(enabled: true, pushEnabled: false, soundEnabled: false),
    };
  }

  /// Get all settings at once
  static Future<LocalNotificationSettings> getAllSettings() async {
    final pushEnabled = await getPushEnabled();
    final inAppEnabled = await getInAppEnabled();
    final quietHoursEnabled = await getQuietHoursEnabled();
    final quietHoursStart = await getQuietHoursStart();
    final quietHoursEnd = await getQuietHoursEnd();
    final reminders = await getReminders();
    final categorySettings = await getCategorySettings();

    return LocalNotificationSettings(
      pushEnabled: pushEnabled,
      inAppEnabled: inAppEnabled,
      quietHoursEnabled: quietHoursEnabled,
      quietHoursStart: quietHoursStart,
      quietHoursEnd: quietHoursEnd,
      reminders: reminders,
      categorySettings: categorySettings,
    );
  }

  /// Save all settings at once
  static Future<void> saveAllSettings(LocalNotificationSettings settings) async {
    await setPushEnabled(settings.pushEnabled);
    await setInAppEnabled(settings.inAppEnabled);
    await setQuietHoursEnabled(settings.quietHoursEnabled);
    await setQuietHoursStart(settings.quietHoursStart);
    await setQuietHoursEnd(settings.quietHoursEnd);
    await setReminders(settings.reminders);
    await setCategorySettings(settings.categorySettings);
  }
}

/// Complete notification settings model
class LocalNotificationSettings {
  final bool pushEnabled;
  final bool inAppEnabled;
  final bool quietHoursEnabled;
  final TimeOfDay quietHoursStart;
  final TimeOfDay quietHoursEnd;
  final List<NotificationReminder> reminders;
  final Map<String, CategoryNotificationSetting> categorySettings;

  LocalNotificationSettings({
    this.pushEnabled = true,
    this.inAppEnabled = true,
    this.quietHoursEnabled = false,
    this.quietHoursStart = const TimeOfDay(hour: 22, minute: 0),
    this.quietHoursEnd = const TimeOfDay(hour: 7, minute: 0),
    List<NotificationReminder>? reminders,
    Map<String, CategoryNotificationSetting>? categorySettings,
  })  : reminders = reminders ?? [],
        categorySettings = categorySettings ?? {};

  LocalNotificationSettings copyWith({
    bool? pushEnabled,
    bool? inAppEnabled,
    bool? quietHoursEnabled,
    TimeOfDay? quietHoursStart,
    TimeOfDay? quietHoursEnd,
    List<NotificationReminder>? reminders,
    Map<String, CategoryNotificationSetting>? categorySettings,
  }) {
    return LocalNotificationSettings(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      reminders: reminders ?? this.reminders,
      categorySettings: categorySettings ?? this.categorySettings,
    );
  }
}

/// Notification reminder model with time settings
class NotificationReminder {
  final String id;
  final String name;
  final String description;
  final String category;
  final bool enabled;
  final TimeOfDay time;
  final List<String> days; // ['mon', 'tue', 'wed', ...] or ['daily']

  NotificationReminder({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.enabled,
    required this.time,
    required this.days,
  });

  factory NotificationReminder.fromJson(Map<String, dynamic> json) {
    final timeStr = json['time'] as String? ?? '21:00';
    final timeParts = timeStr.split(':');
    return NotificationReminder(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? 'system',
      enabled: json['enabled'] ?? false,
      time: TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      ),
      days: List<String>.from(json['days'] ?? ['daily']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'enabled': enabled,
        'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        'days': days,
      };

  NotificationReminder copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    bool? enabled,
    TimeOfDay? time,
    List<String>? days,
  }) {
    return NotificationReminder(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      enabled: enabled ?? this.enabled,
      time: time ?? this.time,
      days: days ?? this.days,
    );
  }

  String get formattedTime {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${time.minute.toString().padLeft(2, '0')} $period';
  }

  String get formattedDays {
    if (days.contains('daily')) return 'Every day';
    if (days.length == 7) return 'Every day';
    if (days.length == 6 && !days.contains('sun')) return 'Weekdays + Sat';
    if (days.length == 5 && !days.contains('sun') && !days.contains('sat')) return 'Weekdays';
    return days.map((d) => d[0].toUpperCase() + d.substring(1, 3)).join(', ');
  }
}

/// Category notification settings
class CategoryNotificationSetting {
  final bool enabled;
  final bool pushEnabled;
  final bool soundEnabled;

  CategoryNotificationSetting({
    required this.enabled,
    required this.pushEnabled,
    required this.soundEnabled,
  });

  factory CategoryNotificationSetting.fromJson(Map<String, dynamic> json) {
    return CategoryNotificationSetting(
      enabled: json['enabled'] ?? true,
      pushEnabled: json['push_enabled'] ?? true,
      soundEnabled: json['sound_enabled'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'push_enabled': pushEnabled,
        'sound_enabled': soundEnabled,
      };

  CategoryNotificationSetting copyWith({
    bool? enabled,
    bool? pushEnabled,
    bool? soundEnabled,
  }) {
    return CategoryNotificationSetting(
      enabled: enabled ?? this.enabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
    );
  }
}

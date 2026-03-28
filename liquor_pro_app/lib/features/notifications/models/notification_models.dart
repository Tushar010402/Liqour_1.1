/// Notification Models - Core data structures for notification system
/// Multi-channel: In-app, Push (FCM), Email, SMS, WhatsApp
library;

import 'package:flutter/material.dart' show TimeOfDay;

/// Single notification item
class AppNotification {
  final String id;
  final String type; // 'sales', 'inventory', 'finance', 'audit', 'system', 'theft'
  final String title;
  final String message;
  final String? actionUrl;
  final String? actionLabel;
  final Map<String, dynamic>? metadata;
  final bool isRead;
  final DateTime createdAt;
  final String? imageUrl;
  final NotificationPriority priority;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.actionUrl,
    this.actionLabel,
    this.metadata,
    required this.isRead,
    required this.createdAt,
    this.imageUrl,
    this.priority = NotificationPriority.normal,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] ?? '',
      type: json['type'] ?? 'system',
      title: json['title'] ?? '',
      message: json['message'] ?? json['body'] ?? '',
      actionUrl: json['action_url'] ?? json['actionUrl'],
      actionLabel: json['action_label'] ?? json['actionLabel'],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      isRead: json['is_read'] ?? json['isRead'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : (json['createdAt'] != null
              ? DateTime.parse(json['createdAt'])
              : DateTime.now()),
      imageUrl: json['image_url'] ?? json['imageUrl'],
      priority: NotificationPriority.fromString(
          json['priority'] ?? json['severity'] ?? 'normal'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'message': message,
        'action_url': actionUrl,
        'action_label': actionLabel,
        'metadata': metadata,
        'is_read': isRead,
        'created_at': createdAt.toIso8601String(),
        'image_url': imageUrl,
        'priority': priority.name,
      };

  AppNotification copyWith({
    String? id,
    String? type,
    String? title,
    String? message,
    String? actionUrl,
    String? actionLabel,
    Map<String, dynamic>? metadata,
    bool? isRead,
    DateTime? createdAt,
    String? imageUrl,
    NotificationPriority? priority,
  }) {
    return AppNotification(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      actionUrl: actionUrl ?? this.actionUrl,
      actionLabel: actionLabel ?? this.actionLabel,
      metadata: metadata ?? this.metadata,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      priority: priority ?? this.priority,
    );
  }
}

/// Notification priority levels
enum NotificationPriority {
  low,
  normal,
  high,
  urgent;

  static NotificationPriority fromString(String value) {
    switch (value.toLowerCase()) {
      case 'low':
        return NotificationPriority.low;
      case 'high':
        return NotificationPriority.high;
      case 'urgent':
      case 'critical':
        return NotificationPriority.urgent;
      default:
        return NotificationPriority.normal;
    }
  }

  String get displayName {
    switch (this) {
      case NotificationPriority.low:
        return 'Low';
      case NotificationPriority.normal:
        return 'Normal';
      case NotificationPriority.high:
        return 'High';
      case NotificationPriority.urgent:
        return 'Urgent';
    }
  }
}

/// Notification type categories with icons and colors
enum NotificationType {
  sales,
  inventory,
  finance,
  audit,
  system,
  theft;

  static NotificationType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'sales':
        return NotificationType.sales;
      case 'inventory':
        return NotificationType.inventory;
      case 'finance':
        return NotificationType.finance;
      case 'audit':
        return NotificationType.audit;
      case 'theft':
        return NotificationType.theft;
      default:
        return NotificationType.system;
    }
  }

  String get displayName {
    switch (this) {
      case NotificationType.sales:
        return 'Sales';
      case NotificationType.inventory:
        return 'Inventory';
      case NotificationType.finance:
        return 'Finance';
      case NotificationType.audit:
        return 'Audit';
      case NotificationType.theft:
        return 'Security';
      case NotificationType.system:
        return 'System';
    }
  }
}

/// Channel settings for notifications (matches backend JSONB structure)
class ChannelSettings {
  final bool inApp;
  final bool push;
  final bool email;
  final bool sms;
  final bool whatsapp;

  const ChannelSettings({
    this.inApp = true,
    this.push = true,
    this.email = false,
    this.sms = false,
    this.whatsapp = false,
  });

  factory ChannelSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChannelSettings();
    return ChannelSettings(
      inApp: json['in_app'] ?? json['inApp'] ?? true,
      push: json['push'] ?? true,
      email: json['email'] ?? false,
      sms: json['sms'] ?? false,
      whatsapp: json['whatsapp'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'in_app': inApp,
        'push': push,
        'email': email,
        'sms': sms,
        'whatsapp': whatsapp,
      };

  ChannelSettings copyWith({
    bool? inApp,
    bool? push,
    bool? email,
    bool? sms,
    bool? whatsapp,
  }) {
    return ChannelSettings(
      inApp: inApp ?? this.inApp,
      push: push ?? this.push,
      email: email ?? this.email,
      sms: sms ?? this.sms,
      whatsapp: whatsapp ?? this.whatsapp,
    );
  }
}

/// Alert type settings (matches backend JSONB structure)
class AlertTypeSettings {
  final bool lowStock;
  final bool cashShortage;
  final bool salesTarget;
  final bool priceChange;
  final bool newOrder;
  final bool paymentDue;
  final bool systemAlert;

  const AlertTypeSettings({
    this.lowStock = true,
    this.cashShortage = true,
    this.salesTarget = true,
    this.priceChange = true,
    this.newOrder = true,
    this.paymentDue = true,
    this.systemAlert = true,
  });

  factory AlertTypeSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AlertTypeSettings();
    return AlertTypeSettings(
      lowStock: json['low_stock'] ?? json['lowStock'] ?? true,
      cashShortage: json['cash_shortage'] ?? json['cashShortage'] ?? true,
      salesTarget: json['sales_target'] ?? json['salesTarget'] ?? true,
      priceChange: json['price_change'] ?? json['priceChange'] ?? true,
      newOrder: json['new_order'] ?? json['newOrder'] ?? true,
      paymentDue: json['payment_due'] ?? json['paymentDue'] ?? true,
      systemAlert: json['system_alert'] ?? json['systemAlert'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'low_stock': lowStock,
        'cash_shortage': cashShortage,
        'sales_target': salesTarget,
        'price_change': priceChange,
        'new_order': newOrder,
        'payment_due': paymentDue,
        'system_alert': systemAlert,
      };

  AlertTypeSettings copyWith({
    bool? lowStock,
    bool? cashShortage,
    bool? salesTarget,
    bool? priceChange,
    bool? newOrder,
    bool? paymentDue,
    bool? systemAlert,
  }) {
    return AlertTypeSettings(
      lowStock: lowStock ?? this.lowStock,
      cashShortage: cashShortage ?? this.cashShortage,
      salesTarget: salesTarget ?? this.salesTarget,
      priceChange: priceChange ?? this.priceChange,
      newOrder: newOrder ?? this.newOrder,
      paymentDue: paymentDue ?? this.paymentDue,
      systemAlert: systemAlert ?? this.systemAlert,
    );
  }
}

/// Reminder settings for scheduled notifications (synced to backend)
class ReminderSettings {
  final String id;
  final String name;
  final String description;
  final String category; // sales, inventory, finance, security, system
  final bool enabled;
  final String time; // HH:mm format (e.g., "13:00" for 1 PM)
  final List<String> days; // ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] or ['daily']

  const ReminderSettings({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.enabled = true,
    this.time = '09:00',
    this.days = const ['daily'],
  });

  factory ReminderSettings.fromJson(Map<String, dynamic> json) {
    return ReminderSettings(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? 'system',
      enabled: json['enabled'] ?? true,
      time: json['time'] ?? '09:00',
      days: json['days'] != null ? List<String>.from(json['days']) : const ['daily'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'enabled': enabled,
        'time': time,
        'days': days,
      };

  ReminderSettings copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    bool? enabled,
    String? time,
    List<String>? days,
  }) {
    return ReminderSettings(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      enabled: enabled ?? this.enabled,
      time: time ?? this.time,
      days: days ?? this.days,
    );
  }

  // Helper to get TimeOfDay from time string
  TimeOfDay get timeOfDay {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  // Helper to format time for display
  String get formattedTime {
    final tod = timeOfDay;
    final hour = tod.hour > 12 ? tod.hour - 12 : (tod.hour == 0 ? 12 : tod.hour);
    final period = tod.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${tod.minute.toString().padLeft(2, '0')} $period';
  }

  // Helper to format days for display
  String get formattedDays {
    if (days.contains('daily')) return 'Every day';
    if (days.length == 7) return 'Every day';
    if (days.length == 6 && !days.contains('sun')) return 'Weekdays + Sat';
    if (days.length == 5 && !days.contains('sun') && !days.contains('sat')) return 'Weekdays';
    if (days.length == 2 && days.contains('sat') && days.contains('sun')) return 'Weekends';
    return days.map((d) => d[0].toUpperCase() + d.substring(1, 3)).join(', ');
  }

  // Default reminders
  static List<ReminderSettings> defaults() => [
        const ReminderSettings(
          id: 'daily_sales',
          name: 'Daily Sales Reminder',
          description: 'Remind if daily sales not submitted',
          category: 'sales',
          enabled: true,
          time: '21:00',
          days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
        ),
        const ReminderSettings(
          id: 'low_stock',
          name: 'Low Stock Alert',
          description: 'Alert when stock runs low',
          category: 'inventory',
          enabled: true,
          time: '09:00',
          days: ['daily'],
        ),
        const ReminderSettings(
          id: 'cash_collection',
          name: 'Cash Collection Reminder',
          description: 'Remind about pending cash collection',
          category: 'finance',
          enabled: false,
          time: '18:00',
          days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat'],
        ),
      ];
}

/// Category-specific notification settings (synced to backend)
class CategorySettings {
  final bool salesEnabled;
  final bool inventoryEnabled;
  final bool financeEnabled;
  final bool securityEnabled;
  final bool systemEnabled;

  const CategorySettings({
    this.salesEnabled = true,
    this.inventoryEnabled = true,
    this.financeEnabled = true,
    this.securityEnabled = true,
    this.systemEnabled = true,
  });

  factory CategorySettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CategorySettings();
    return CategorySettings(
      salesEnabled: json['sales'] ?? json['sales_enabled'] ?? true,
      inventoryEnabled: json['inventory'] ?? json['inventory_enabled'] ?? true,
      financeEnabled: json['finance'] ?? json['finance_enabled'] ?? true,
      securityEnabled: json['security'] ?? json['security_enabled'] ?? true,
      systemEnabled: json['system'] ?? json['system_enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'sales': salesEnabled,
        'inventory': inventoryEnabled,
        'finance': financeEnabled,
        'security': securityEnabled,
        'system': systemEnabled,
      };

  CategorySettings copyWith({
    bool? salesEnabled,
    bool? inventoryEnabled,
    bool? financeEnabled,
    bool? securityEnabled,
    bool? systemEnabled,
  }) {
    return CategorySettings(
      salesEnabled: salesEnabled ?? this.salesEnabled,
      inventoryEnabled: inventoryEnabled ?? this.inventoryEnabled,
      financeEnabled: financeEnabled ?? this.financeEnabled,
      securityEnabled: securityEnabled ?? this.securityEnabled,
      systemEnabled: systemEnabled ?? this.systemEnabled,
    );
  }
}

/// User notification preferences - COMPREHENSIVE model synced 100% with backend
class NotificationPreferences {
  final String? id;
  final String? tenantId;
  final String? userId;

  // Channel settings - which notification channels are enabled
  final ChannelSettings channels;

  // Alert type settings - which alert types are enabled
  final AlertTypeSettings alertTypes;

  // Category settings - which categories are enabled
  final CategorySettings categories;

  // Scheduled reminders with specific times
  final List<ReminderSettings> reminders;

  // General settings
  final String minimumSeverity; // 'info', 'warning', 'error', 'critical'
  final bool digestMode;
  final String digestFrequency; // 'daily', 'weekly', 'realtime'

  // Quiet hours / Do Not Disturb
  final bool quietHoursEnabled;
  final String? quietHoursStart; // HH:mm format
  final String? quietHoursEnd;   // HH:mm format

  // Timestamps
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Legacy support - computed getters for backward compatibility
  bool get inAppEnabled => channels.inApp;
  bool get pushEnabled => channels.push;
  bool get emailEnabled => channels.email;
  bool get smsEnabled => channels.sms;
  bool get whatsappEnabled => channels.whatsapp;

  NotificationPreferences({
    this.id,
    this.tenantId,
    this.userId,
    ChannelSettings? channels,
    AlertTypeSettings? alertTypes,
    CategorySettings? categories,
    List<ReminderSettings>? reminders,
    this.minimumSeverity = 'info',
    this.digestMode = false,
    this.digestFrequency = 'daily',
    this.quietHoursEnabled = false,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.createdAt,
    this.updatedAt,
  })  : channels = channels ?? const ChannelSettings(),
        alertTypes = alertTypes ?? const AlertTypeSettings(),
        categories = categories ?? const CategorySettings(),
        reminders = reminders ?? ReminderSettings.defaults();

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    // Parse channels
    ChannelSettings channels;
    if (json['channels'] != null && json['channels'] is Map) {
      channels = ChannelSettings.fromJson(json['channels'] as Map<String, dynamic>);
    } else {
      // Legacy format fallback
      channels = ChannelSettings(
        inApp: json['in_app_enabled'] ?? json['inAppEnabled'] ?? true,
        push: json['push_enabled'] ?? json['pushEnabled'] ?? true,
        email: json['email_enabled'] ?? json['emailEnabled'] ?? false,
        sms: json['sms_enabled'] ?? json['smsEnabled'] ?? false,
        whatsapp: json['whatsapp_enabled'] ?? json['whatsappEnabled'] ?? false,
      );
    }

    // Parse alert types
    AlertTypeSettings alertTypes;
    if (json['alert_types'] != null && json['alert_types'] is Map) {
      alertTypes = AlertTypeSettings.fromJson(json['alert_types'] as Map<String, dynamic>);
    } else {
      alertTypes = const AlertTypeSettings();
    }

    // Parse categories
    CategorySettings categories;
    if (json['categories'] != null && json['categories'] is Map) {
      categories = CategorySettings.fromJson(json['categories'] as Map<String, dynamic>);
    } else {
      categories = const CategorySettings();
    }

    // Parse reminders
    List<ReminderSettings> reminders;
    if (json['reminders'] != null && json['reminders'] is List) {
      reminders = (json['reminders'] as List)
          .map((r) => ReminderSettings.fromJson(r as Map<String, dynamic>))
          .toList();
    } else {
      reminders = ReminderSettings.defaults();
    }

    return NotificationPreferences(
      id: json['id']?.toString(),
      tenantId: json['tenant_id']?.toString(),
      userId: json['user_id']?.toString(),
      channels: channels,
      alertTypes: alertTypes,
      categories: categories,
      reminders: reminders,
      minimumSeverity: json['minimum_severity'] ?? json['minimumSeverity'] ?? 'info',
      digestMode: json['digest_mode'] ?? json['digestMode'] ?? false,
      digestFrequency: json['digest_frequency'] ?? json['digestFrequency'] ?? 'daily',
      quietHoursEnabled: json['quiet_hours_enabled'] ?? json['quietHoursEnabled'] ?? false,
      quietHoursStart: json['quiet_hours_start']?.toString(),
      quietHoursEnd: json['quiet_hours_end']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }

  static TimeOfDay _parseTimeOfDay(String? time) {
    if (time == null || time.isEmpty) return const TimeOfDay(hour: 9, minute: 0);
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  static String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // Helper getters for quiet hours as TimeOfDay
  TimeOfDay? get quietHoursStartTime => quietHoursStart != null ? _parseTimeOfDay(quietHoursStart) : null;
  TimeOfDay? get quietHoursEndTime => quietHoursEnd != null ? _parseTimeOfDay(quietHoursEnd) : null;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (tenantId != null) 'tenant_id': tenantId,
        if (userId != null) 'user_id': userId,
        'channels': channels.toJson(),
        'alert_types': alertTypes.toJson(),
        'categories': categories.toJson(),
        'reminders': reminders.map((r) => r.toJson()).toList(),
        'minimum_severity': minimumSeverity,
        'digest_mode': digestMode,
        'digest_frequency': digestFrequency,
        'quiet_hours_enabled': quietHoursEnabled,
        'quiet_hours_start': quietHoursStart,
        'quiet_hours_end': quietHoursEnd,
      };

  NotificationPreferences copyWith({
    String? id,
    String? tenantId,
    String? userId,
    ChannelSettings? channels,
    AlertTypeSettings? alertTypes,
    CategorySettings? categories,
    List<ReminderSettings>? reminders,
    String? minimumSeverity,
    bool? digestMode,
    String? digestFrequency,
    bool? quietHoursEnabled,
    String? quietHoursStart,
    String? quietHoursEnd,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NotificationPreferences(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      userId: userId ?? this.userId,
      channels: channels ?? this.channels,
      alertTypes: alertTypes ?? this.alertTypes,
      categories: categories ?? this.categories,
      reminders: reminders ?? this.reminders,
      minimumSeverity: minimumSeverity ?? this.minimumSeverity,
      digestMode: digestMode ?? this.digestMode,
      digestFrequency: digestFrequency ?? this.digestFrequency,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStart: quietHoursStart ?? this.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Helper to update a specific reminder
  NotificationPreferences updateReminder(int index, ReminderSettings updatedReminder) {
    final newReminders = List<ReminderSettings>.from(reminders);
    if (index >= 0 && index < newReminders.length) {
      newReminders[index] = updatedReminder;
    }
    return copyWith(reminders: newReminders);
  }

  // Legacy support - get category preferences as the old format
  Map<String, ChannelPreference> get categoryPreferences {
    return {
      'sales': ChannelPreference(
        inApp: channels.inApp && categories.salesEnabled,
        push: channels.push && categories.salesEnabled,
        email: channels.email && categories.salesEnabled,
        sms: channels.sms && categories.salesEnabled,
        whatsapp: channels.whatsapp && categories.salesEnabled,
      ),
      'inventory': ChannelPreference(
        inApp: channels.inApp && categories.inventoryEnabled,
        push: channels.push && categories.inventoryEnabled,
        email: channels.email && categories.inventoryEnabled,
        sms: channels.sms && categories.inventoryEnabled,
        whatsapp: channels.whatsapp && categories.inventoryEnabled,
      ),
      'finance': ChannelPreference(
        inApp: channels.inApp && categories.financeEnabled,
        push: channels.push && categories.financeEnabled,
        email: channels.email && categories.financeEnabled,
        sms: channels.sms && categories.financeEnabled,
        whatsapp: channels.whatsapp && categories.financeEnabled,
      ),
      'security': ChannelPreference(
        inApp: channels.inApp && categories.securityEnabled,
        push: channels.push && categories.securityEnabled,
        email: channels.email && categories.securityEnabled,
        sms: channels.sms && categories.securityEnabled,
        whatsapp: channels.whatsapp && categories.securityEnabled,
      ),
      'system': ChannelPreference(
        inApp: channels.inApp && categories.systemEnabled,
        push: channels.push && categories.systemEnabled,
        email: channels.email && categories.systemEnabled,
        sms: channels.sms && categories.systemEnabled,
        whatsapp: channels.whatsapp && categories.systemEnabled,
      ),
    };
  }
}

/// NotificationTimeOfDay helper for serialization
/// Use Flutter's TimeOfDay in screens, convert to this for JSON
class NotificationTimeOfDay {
  final int hour;
  final int minute;

  const NotificationTimeOfDay({required this.hour, required this.minute});

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Per-category channel preferences
class ChannelPreference {
  final bool inApp;
  final bool push;
  final bool email;
  final bool sms;
  final bool whatsapp;

  ChannelPreference({
    required this.inApp,
    required this.push,
    required this.email,
    required this.sms,
    required this.whatsapp,
  });

  factory ChannelPreference.defaults() {
    return ChannelPreference(
      inApp: true,
      push: true,
      email: false,
      sms: false,
      whatsapp: false,
    );
  }

  factory ChannelPreference.fromJson(Map<String, dynamic> json) {
    return ChannelPreference(
      inApp: json['in_app'] ?? json['inApp'] ?? true,
      push: json['push'] ?? true,
      email: json['email'] ?? false,
      sms: json['sms'] ?? false,
      whatsapp: json['whatsapp'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'in_app': inApp,
        'push': push,
        'email': email,
        'sms': sms,
        'whatsapp': whatsapp,
      };

  ChannelPreference copyWith({
    bool? inApp,
    bool? push,
    bool? email,
    bool? sms,
    bool? whatsapp,
  }) {
    return ChannelPreference(
      inApp: inApp ?? this.inApp,
      push: push ?? this.push,
      email: email ?? this.email,
      sms: sms ?? this.sms,
      whatsapp: whatsapp ?? this.whatsapp,
    );
  }
}

/// Notification channel status (Admin view)
class NotificationChannel {
  final String name;
  final String description;
  final bool isConfigured;
  final bool isEnabled;
  final String? lastError;
  final DateTime? lastSuccessAt;
  final int successCount;
  final int failureCount;

  NotificationChannel({
    required this.name,
    required this.description,
    required this.isConfigured,
    this.isEnabled = true,
    this.lastError,
    this.lastSuccessAt,
    this.successCount = 0,
    this.failureCount = 0,
  });

  factory NotificationChannel.fromJson(Map<String, dynamic> json) {
    return NotificationChannel(
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      isConfigured: json['is_configured'] ?? json['isConfigured'] ?? false,
      isEnabled: json['is_enabled'] ?? json['isEnabled'] ?? true,
      lastError: json['last_error'] ?? json['lastError'],
      lastSuccessAt: json['last_success_at'] != null
          ? DateTime.parse(json['last_success_at'])
          : null,
      successCount: json['success_count'] ?? json['successCount'] ?? 0,
      failureCount: json['failure_count'] ?? json['failureCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'is_configured': isConfigured,
        'is_enabled': isEnabled,
        'last_error': lastError,
        'last_success_at': lastSuccessAt?.toIso8601String(),
        'success_count': successCount,
        'failure_count': failureCount,
      };

  double get successRate {
    final total = successCount + failureCount;
    if (total == 0) return 100.0;
    return (successCount / total) * 100;
  }
}

/// Request to send a notification (Admin)
class SendNotificationRequest {
  final String title;
  final String message;
  final String type;
  final NotificationPriority priority;
  final List<String>? targetUserIds;
  final List<String>? targetRoles;
  final String? targetShopId;
  final List<String> channels;
  final Map<String, dynamic>? metadata;
  final DateTime? scheduledAt;

  SendNotificationRequest({
    required this.title,
    required this.message,
    this.type = 'system',
    this.priority = NotificationPriority.normal,
    this.targetUserIds,
    this.targetRoles,
    this.targetShopId,
    this.channels = const ['in_app', 'push'],
    this.metadata,
    this.scheduledAt,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'message': message,
        'type': type,
        'priority': priority.name,
        'target_user_ids': targetUserIds,
        'target_roles': targetRoles,
        'target_shop_id': targetShopId,
        'channels': channels,
        'metadata': metadata,
        'scheduled_at': scheduledAt?.toIso8601String(),
      };
}

/// Notification query parameters
class NotificationQuery {
  final String? type;
  final bool? unreadOnly;
  final int limit;
  final int offset;
  final DateTime? after;
  final DateTime? before;

  NotificationQuery({
    this.type,
    this.unreadOnly,
    this.limit = 50,
    this.offset = 0,
    this.after,
    this.before,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (type != null) params['type'] = type;
    if (unreadOnly != null) params['unread_only'] = unreadOnly.toString();
    if (after != null) params['after'] = after!.toIso8601String();
    if (before != null) params['before'] = before!.toIso8601String();
    return params;
  }
}

/// Paginated notifications response
class NotificationListResponse {
  final List<AppNotification> notifications;
  final int totalCount;
  final int unreadCount;
  final int page;
  final int pageSize;
  final bool hasMore;

  NotificationListResponse({
    required this.notifications,
    required this.totalCount,
    required this.unreadCount,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory NotificationListResponse.fromJson(Map<String, dynamic> json) {
    final notificationsData =
        (json['notifications'] ?? json['data'] ?? []) as List;
    return NotificationListResponse(
      notifications: notificationsData
          .map((n) => AppNotification.fromJson(n))
          .toList(),
      totalCount: json['total_count'] ?? json['totalCount'] ?? 0,
      unreadCount: json['unread_count'] ?? json['unreadCount'] ?? 0,
      page: json['page'] ?? 1,
      pageSize: json['page_size'] ?? json['pageSize'] ?? 50,
      hasMore: json['has_more'] ?? json['hasMore'] ?? false,
    );
  }
}

/// Device registration for FCM push notifications
/// Matches backend API: POST /api/notifications/devices
class DeviceRegistration {
  final String fcmToken;
  final String deviceId;
  final String platform; // 'ios', 'android'
  final String? deviceName;
  final String? appVersion;

  DeviceRegistration({
    required this.fcmToken,
    required this.deviceId,
    required this.platform,
    this.deviceName,
    this.appVersion,
  });

  /// Convert to JSON for backend API
  /// Backend expects: token, platform, device_name
  Map<String, dynamic> toJson() => {
        'token': fcmToken,           // Backend expects 'token' not 'fcm_token'
        'device_id': deviceId,
        'platform': platform,
        'device_name': deviceName ?? (platform == 'ios' ? 'iPhone' : 'Android Device'),
        'app_version': appVersion,
      };
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_session_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DeviceInfoImpl _$$DeviceInfoImplFromJson(Map<String, dynamic> json) =>
    _$DeviceInfoImpl(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      deviceType: json['device_type'] as String? ?? 'mobile',
      osName: json['os_name'] as String,
      osVersion: json['os_version'] as String,
      appVersion: json['app_version'] as String,
    );

Map<String, dynamic> _$$DeviceInfoImplToJson(_$DeviceInfoImpl instance) =>
    <String, dynamic>{
      'device_id': instance.deviceId,
      'device_name': instance.deviceName,
      'device_type': instance.deviceType,
      'os_name': instance.osName,
      'os_version': instance.osVersion,
      'app_version': instance.appVersion,
    };

_$DeviceSessionImpl _$$DeviceSessionImplFromJson(Map<String, dynamic> json) =>
    _$DeviceSessionImpl(
      id: _readSessionId(json, 'id') as String,
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? 'Unknown Device',
      deviceType: json['device_type'] as String? ?? 'mobile',
      osName: json['os_name'] as String? ?? '',
      osVersion: json['os_version'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      ipAddress: json['ip_address'] as String?,
      loginLocation: json['login_location'] as String?,
      lastActiveAt: json['last_active_at'] == null
          ? null
          : DateTime.parse(json['last_active_at'] as String),
      loginAt: json['login_at'] == null
          ? null
          : DateTime.parse(json['login_at'] as String),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      isCurrent: json['is_current'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );

Map<String, dynamic> _$$DeviceSessionImplToJson(_$DeviceSessionImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'device_id': instance.deviceId,
      'device_name': instance.deviceName,
      'device_type': instance.deviceType,
      'os_name': instance.osName,
      'os_version': instance.osVersion,
      'app_version': instance.appVersion,
      'ip_address': instance.ipAddress,
      'login_location': instance.loginLocation,
      'last_active_at': instance.lastActiveAt?.toIso8601String(),
      'login_at': instance.loginAt?.toIso8601String(),
      'created_at': instance.createdAt?.toIso8601String(),
      'is_current': instance.isCurrent,
      'is_active': instance.isActive,
    };

_$DeviceSessionsResponseImpl _$$DeviceSessionsResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$DeviceSessionsResponseImpl(
      sessions: (json['sessions'] as List<dynamic>?)
              ?.map((e) => DeviceSession.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      maxDevices: (json['max_devices'] as num?)?.toInt() ?? 2,
      activeCount: (json['active_count'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$$DeviceSessionsResponseImplToJson(
        _$DeviceSessionsResponseImpl instance) =>
    <String, dynamic>{
      'sessions': instance.sessions.map((e) => e.toJson()).toList(),
      'max_devices': instance.maxDevices,
      'active_count': instance.activeCount,
    };

_$DeviceLimitErrorImpl _$$DeviceLimitErrorImplFromJson(
        Map<String, dynamic> json) =>
    _$DeviceLimitErrorImpl(
      error: json['error'] as String? ?? 'device_limit_reached',
      message: json['message'] as String? ??
          'Maximum device limit reached. Please logout from another device to continue.',
      activeDevices: (_readActiveDevices(json, 'activeDevices')
                  as List<dynamic>?)
              ?.map((e) => DeviceSession.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      maxDevices: (json['max_devices'] as num?)?.toInt() ?? 2,
    );

Map<String, dynamic> _$$DeviceLimitErrorImplToJson(
        _$DeviceLimitErrorImpl instance) =>
    <String, dynamic>{
      'error': instance.error,
      'message': instance.message,
      'activeDevices': instance.activeDevices.map((e) => e.toJson()).toList(),
      'max_devices': instance.maxDevices,
    };

import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_session_models.freezed.dart';
part 'device_session_models.g.dart';

/// Device Info Model - Collected from device during login
/// Used to identify this device for session management
@freezed
class DeviceInfo with _$DeviceInfo {
  const factory DeviceInfo({
    @JsonKey(name: 'device_id') required String deviceId,
    @JsonKey(name: 'device_name') required String deviceName,
    @JsonKey(name: 'device_type') @Default('mobile') String deviceType,
    @JsonKey(name: 'os_name') required String osName,
    @JsonKey(name: 'os_version') required String osVersion,
    @JsonKey(name: 'app_version') required String appVersion,
  }) = _DeviceInfo;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);
}

/// Device Session Model - Represents a logged-in session
/// Each session corresponds to a unique device login
@freezed
class DeviceSession with _$DeviceSession {
  const factory DeviceSession({
    @JsonKey(readValue: _readSessionId) required String id,
    @JsonKey(name: 'device_id') @Default('') String deviceId,
    @JsonKey(name: 'device_name') @Default('Unknown Device') String deviceName,
    @JsonKey(name: 'device_type') @Default('mobile') String deviceType,
    @JsonKey(name: 'os_name') @Default('') String osName,
    @JsonKey(name: 'os_version') @Default('') String osVersion,
    @JsonKey(name: 'app_version') @Default('') String appVersion,
    @JsonKey(name: 'ip_address') String? ipAddress,
    @JsonKey(name: 'login_location') String? loginLocation,
    @JsonKey(name: 'last_active_at') DateTime? lastActiveAt,
    @JsonKey(name: 'login_at') DateTime? loginAt,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'is_current') @Default(false) bool isCurrent,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
  }) = _DeviceSession;

  factory DeviceSession.fromJson(Map<String, dynamic> json) =>
      _$DeviceSessionFromJson(json);
}

/// Helper function to read session_id or id from JSON
Object? _readSessionId(Map<dynamic, dynamic> json, String key) {
  return json['session_id'] ?? json['id'] ?? '';
}

/// Device Sessions Response - API response for GET /api/auth/sessions
@freezed
class DeviceSessionsResponse with _$DeviceSessionsResponse {
  const factory DeviceSessionsResponse({
    @Default([]) List<DeviceSession> sessions,
    @JsonKey(name: 'max_devices') @Default(2) int maxDevices,
    @JsonKey(name: 'active_count') @Default(0) int activeCount,
  }) = _DeviceSessionsResponse;

  factory DeviceSessionsResponse.fromJson(Map<String, dynamic> json) =>
      _$DeviceSessionsResponseFromJson(json);
}

/// Device Limit Error - Returned when login fails due to device limit
/// Contains list of active devices for user to choose which to logout
@freezed
class DeviceLimitError with _$DeviceLimitError {
  const factory DeviceLimitError({
    @Default('device_limit_reached') String error,
    @Default('Maximum device limit reached. Please logout from another device to continue.') String message,
    @JsonKey(readValue: _readActiveDevices) @Default([]) List<DeviceSession> activeDevices,
    @JsonKey(name: 'max_devices') @Default(2) int maxDevices,
  }) = _DeviceLimitError;

  factory DeviceLimitError.fromJson(Map<String, dynamic> json) =>
      _$DeviceLimitErrorFromJson(json);
}

/// Helper function to read active_sessions or active_devices from JSON
Object? _readActiveDevices(Map<dynamic, dynamic> json, String key) {
  return json['active_sessions'] ?? json['active_devices'] ?? [];
}

/// Exception thrown when device limit is reached during login
class DeviceLimitException implements Exception {
  final DeviceLimitError error;

  DeviceLimitException(this.error);

  @override
  String toString() => error.message;
}

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'device_session_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) {
  return _DeviceInfo.fromJson(json);
}

/// @nodoc
mixin _$DeviceInfo {
  @JsonKey(name: 'device_id')
  String get deviceId => throw _privateConstructorUsedError;
  @JsonKey(name: 'device_name')
  String get deviceName => throw _privateConstructorUsedError;
  @JsonKey(name: 'device_type')
  String get deviceType => throw _privateConstructorUsedError;
  @JsonKey(name: 'os_name')
  String get osName => throw _privateConstructorUsedError;
  @JsonKey(name: 'os_version')
  String get osVersion => throw _privateConstructorUsedError;
  @JsonKey(name: 'app_version')
  String get appVersion => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeviceInfoCopyWith<DeviceInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceInfoCopyWith<$Res> {
  factory $DeviceInfoCopyWith(
          DeviceInfo value, $Res Function(DeviceInfo) then) =
      _$DeviceInfoCopyWithImpl<$Res, DeviceInfo>;
  @useResult
  $Res call(
      {@JsonKey(name: 'device_id') String deviceId,
      @JsonKey(name: 'device_name') String deviceName,
      @JsonKey(name: 'device_type') String deviceType,
      @JsonKey(name: 'os_name') String osName,
      @JsonKey(name: 'os_version') String osVersion,
      @JsonKey(name: 'app_version') String appVersion});
}

/// @nodoc
class _$DeviceInfoCopyWithImpl<$Res, $Val extends DeviceInfo>
    implements $DeviceInfoCopyWith<$Res> {
  _$DeviceInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceId = null,
    Object? deviceName = null,
    Object? deviceType = null,
    Object? osName = null,
    Object? osVersion = null,
    Object? appVersion = null,
  }) {
    return _then(_value.copyWith(
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      deviceType: null == deviceType
          ? _value.deviceType
          : deviceType // ignore: cast_nullable_to_non_nullable
              as String,
      osName: null == osName
          ? _value.osName
          : osName // ignore: cast_nullable_to_non_nullable
              as String,
      osVersion: null == osVersion
          ? _value.osVersion
          : osVersion // ignore: cast_nullable_to_non_nullable
              as String,
      appVersion: null == appVersion
          ? _value.appVersion
          : appVersion // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceInfoImplCopyWith<$Res>
    implements $DeviceInfoCopyWith<$Res> {
  factory _$$DeviceInfoImplCopyWith(
          _$DeviceInfoImpl value, $Res Function(_$DeviceInfoImpl) then) =
      __$$DeviceInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'device_id') String deviceId,
      @JsonKey(name: 'device_name') String deviceName,
      @JsonKey(name: 'device_type') String deviceType,
      @JsonKey(name: 'os_name') String osName,
      @JsonKey(name: 'os_version') String osVersion,
      @JsonKey(name: 'app_version') String appVersion});
}

/// @nodoc
class __$$DeviceInfoImplCopyWithImpl<$Res>
    extends _$DeviceInfoCopyWithImpl<$Res, _$DeviceInfoImpl>
    implements _$$DeviceInfoImplCopyWith<$Res> {
  __$$DeviceInfoImplCopyWithImpl(
      _$DeviceInfoImpl _value, $Res Function(_$DeviceInfoImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? deviceId = null,
    Object? deviceName = null,
    Object? deviceType = null,
    Object? osName = null,
    Object? osVersion = null,
    Object? appVersion = null,
  }) {
    return _then(_$DeviceInfoImpl(
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      deviceType: null == deviceType
          ? _value.deviceType
          : deviceType // ignore: cast_nullable_to_non_nullable
              as String,
      osName: null == osName
          ? _value.osName
          : osName // ignore: cast_nullable_to_non_nullable
              as String,
      osVersion: null == osVersion
          ? _value.osVersion
          : osVersion // ignore: cast_nullable_to_non_nullable
              as String,
      appVersion: null == appVersion
          ? _value.appVersion
          : appVersion // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceInfoImpl implements _DeviceInfo {
  const _$DeviceInfoImpl(
      {@JsonKey(name: 'device_id') required this.deviceId,
      @JsonKey(name: 'device_name') required this.deviceName,
      @JsonKey(name: 'device_type') this.deviceType = 'mobile',
      @JsonKey(name: 'os_name') required this.osName,
      @JsonKey(name: 'os_version') required this.osVersion,
      @JsonKey(name: 'app_version') required this.appVersion});

  factory _$DeviceInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceInfoImplFromJson(json);

  @override
  @JsonKey(name: 'device_id')
  final String deviceId;
  @override
  @JsonKey(name: 'device_name')
  final String deviceName;
  @override
  @JsonKey(name: 'device_type')
  final String deviceType;
  @override
  @JsonKey(name: 'os_name')
  final String osName;
  @override
  @JsonKey(name: 'os_version')
  final String osVersion;
  @override
  @JsonKey(name: 'app_version')
  final String appVersion;

  @override
  String toString() {
    return 'DeviceInfo(deviceId: $deviceId, deviceName: $deviceName, deviceType: $deviceType, osName: $osName, osVersion: $osVersion, appVersion: $appVersion)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceInfoImpl &&
            (identical(other.deviceId, deviceId) ||
                other.deviceId == deviceId) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.deviceType, deviceType) ||
                other.deviceType == deviceType) &&
            (identical(other.osName, osName) || other.osName == osName) &&
            (identical(other.osVersion, osVersion) ||
                other.osVersion == osVersion) &&
            (identical(other.appVersion, appVersion) ||
                other.appVersion == appVersion));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, deviceId, deviceName, deviceType,
      osName, osVersion, appVersion);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceInfoImplCopyWith<_$DeviceInfoImpl> get copyWith =>
      __$$DeviceInfoImplCopyWithImpl<_$DeviceInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceInfoImplToJson(
      this,
    );
  }
}

abstract class _DeviceInfo implements DeviceInfo {
  const factory _DeviceInfo(
          {@JsonKey(name: 'device_id') required final String deviceId,
          @JsonKey(name: 'device_name') required final String deviceName,
          @JsonKey(name: 'device_type') final String deviceType,
          @JsonKey(name: 'os_name') required final String osName,
          @JsonKey(name: 'os_version') required final String osVersion,
          @JsonKey(name: 'app_version') required final String appVersion}) =
      _$DeviceInfoImpl;

  factory _DeviceInfo.fromJson(Map<String, dynamic> json) =
      _$DeviceInfoImpl.fromJson;

  @override
  @JsonKey(name: 'device_id')
  String get deviceId;
  @override
  @JsonKey(name: 'device_name')
  String get deviceName;
  @override
  @JsonKey(name: 'device_type')
  String get deviceType;
  @override
  @JsonKey(name: 'os_name')
  String get osName;
  @override
  @JsonKey(name: 'os_version')
  String get osVersion;
  @override
  @JsonKey(name: 'app_version')
  String get appVersion;
  @override
  @JsonKey(ignore: true)
  _$$DeviceInfoImplCopyWith<_$DeviceInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DeviceSession _$DeviceSessionFromJson(Map<String, dynamic> json) {
  return _DeviceSession.fromJson(json);
}

/// @nodoc
mixin _$DeviceSession {
  @JsonKey(readValue: _readSessionId)
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'device_id')
  String get deviceId => throw _privateConstructorUsedError;
  @JsonKey(name: 'device_name')
  String get deviceName => throw _privateConstructorUsedError;
  @JsonKey(name: 'device_type')
  String get deviceType => throw _privateConstructorUsedError;
  @JsonKey(name: 'os_name')
  String get osName => throw _privateConstructorUsedError;
  @JsonKey(name: 'os_version')
  String get osVersion => throw _privateConstructorUsedError;
  @JsonKey(name: 'app_version')
  String get appVersion => throw _privateConstructorUsedError;
  @JsonKey(name: 'ip_address')
  String? get ipAddress => throw _privateConstructorUsedError;
  @JsonKey(name: 'login_location')
  String? get loginLocation => throw _privateConstructorUsedError;
  @JsonKey(name: 'last_active_at')
  DateTime? get lastActiveAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'login_at')
  DateTime? get loginAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime? get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_current')
  bool get isCurrent => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_active')
  bool get isActive => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeviceSessionCopyWith<DeviceSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceSessionCopyWith<$Res> {
  factory $DeviceSessionCopyWith(
          DeviceSession value, $Res Function(DeviceSession) then) =
      _$DeviceSessionCopyWithImpl<$Res, DeviceSession>;
  @useResult
  $Res call(
      {@JsonKey(readValue: _readSessionId) String id,
      @JsonKey(name: 'device_id') String deviceId,
      @JsonKey(name: 'device_name') String deviceName,
      @JsonKey(name: 'device_type') String deviceType,
      @JsonKey(name: 'os_name') String osName,
      @JsonKey(name: 'os_version') String osVersion,
      @JsonKey(name: 'app_version') String appVersion,
      @JsonKey(name: 'ip_address') String? ipAddress,
      @JsonKey(name: 'login_location') String? loginLocation,
      @JsonKey(name: 'last_active_at') DateTime? lastActiveAt,
      @JsonKey(name: 'login_at') DateTime? loginAt,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'is_current') bool isCurrent,
      @JsonKey(name: 'is_active') bool isActive});
}

/// @nodoc
class _$DeviceSessionCopyWithImpl<$Res, $Val extends DeviceSession>
    implements $DeviceSessionCopyWith<$Res> {
  _$DeviceSessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? deviceId = null,
    Object? deviceName = null,
    Object? deviceType = null,
    Object? osName = null,
    Object? osVersion = null,
    Object? appVersion = null,
    Object? ipAddress = freezed,
    Object? loginLocation = freezed,
    Object? lastActiveAt = freezed,
    Object? loginAt = freezed,
    Object? createdAt = freezed,
    Object? isCurrent = null,
    Object? isActive = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      deviceType: null == deviceType
          ? _value.deviceType
          : deviceType // ignore: cast_nullable_to_non_nullable
              as String,
      osName: null == osName
          ? _value.osName
          : osName // ignore: cast_nullable_to_non_nullable
              as String,
      osVersion: null == osVersion
          ? _value.osVersion
          : osVersion // ignore: cast_nullable_to_non_nullable
              as String,
      appVersion: null == appVersion
          ? _value.appVersion
          : appVersion // ignore: cast_nullable_to_non_nullable
              as String,
      ipAddress: freezed == ipAddress
          ? _value.ipAddress
          : ipAddress // ignore: cast_nullable_to_non_nullable
              as String?,
      loginLocation: freezed == loginLocation
          ? _value.loginLocation
          : loginLocation // ignore: cast_nullable_to_non_nullable
              as String?,
      lastActiveAt: freezed == lastActiveAt
          ? _value.lastActiveAt
          : lastActiveAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      loginAt: freezed == loginAt
          ? _value.loginAt
          : loginAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isCurrent: null == isCurrent
          ? _value.isCurrent
          : isCurrent // ignore: cast_nullable_to_non_nullable
              as bool,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceSessionImplCopyWith<$Res>
    implements $DeviceSessionCopyWith<$Res> {
  factory _$$DeviceSessionImplCopyWith(
          _$DeviceSessionImpl value, $Res Function(_$DeviceSessionImpl) then) =
      __$$DeviceSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(readValue: _readSessionId) String id,
      @JsonKey(name: 'device_id') String deviceId,
      @JsonKey(name: 'device_name') String deviceName,
      @JsonKey(name: 'device_type') String deviceType,
      @JsonKey(name: 'os_name') String osName,
      @JsonKey(name: 'os_version') String osVersion,
      @JsonKey(name: 'app_version') String appVersion,
      @JsonKey(name: 'ip_address') String? ipAddress,
      @JsonKey(name: 'login_location') String? loginLocation,
      @JsonKey(name: 'last_active_at') DateTime? lastActiveAt,
      @JsonKey(name: 'login_at') DateTime? loginAt,
      @JsonKey(name: 'created_at') DateTime? createdAt,
      @JsonKey(name: 'is_current') bool isCurrent,
      @JsonKey(name: 'is_active') bool isActive});
}

/// @nodoc
class __$$DeviceSessionImplCopyWithImpl<$Res>
    extends _$DeviceSessionCopyWithImpl<$Res, _$DeviceSessionImpl>
    implements _$$DeviceSessionImplCopyWith<$Res> {
  __$$DeviceSessionImplCopyWithImpl(
      _$DeviceSessionImpl _value, $Res Function(_$DeviceSessionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? deviceId = null,
    Object? deviceName = null,
    Object? deviceType = null,
    Object? osName = null,
    Object? osVersion = null,
    Object? appVersion = null,
    Object? ipAddress = freezed,
    Object? loginLocation = freezed,
    Object? lastActiveAt = freezed,
    Object? loginAt = freezed,
    Object? createdAt = freezed,
    Object? isCurrent = null,
    Object? isActive = null,
  }) {
    return _then(_$DeviceSessionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      deviceId: null == deviceId
          ? _value.deviceId
          : deviceId // ignore: cast_nullable_to_non_nullable
              as String,
      deviceName: null == deviceName
          ? _value.deviceName
          : deviceName // ignore: cast_nullable_to_non_nullable
              as String,
      deviceType: null == deviceType
          ? _value.deviceType
          : deviceType // ignore: cast_nullable_to_non_nullable
              as String,
      osName: null == osName
          ? _value.osName
          : osName // ignore: cast_nullable_to_non_nullable
              as String,
      osVersion: null == osVersion
          ? _value.osVersion
          : osVersion // ignore: cast_nullable_to_non_nullable
              as String,
      appVersion: null == appVersion
          ? _value.appVersion
          : appVersion // ignore: cast_nullable_to_non_nullable
              as String,
      ipAddress: freezed == ipAddress
          ? _value.ipAddress
          : ipAddress // ignore: cast_nullable_to_non_nullable
              as String?,
      loginLocation: freezed == loginLocation
          ? _value.loginLocation
          : loginLocation // ignore: cast_nullable_to_non_nullable
              as String?,
      lastActiveAt: freezed == lastActiveAt
          ? _value.lastActiveAt
          : lastActiveAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      loginAt: freezed == loginAt
          ? _value.loginAt
          : loginAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isCurrent: null == isCurrent
          ? _value.isCurrent
          : isCurrent // ignore: cast_nullable_to_non_nullable
              as bool,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceSessionImpl implements _DeviceSession {
  const _$DeviceSessionImpl(
      {@JsonKey(readValue: _readSessionId) required this.id,
      @JsonKey(name: 'device_id') this.deviceId = '',
      @JsonKey(name: 'device_name') this.deviceName = 'Unknown Device',
      @JsonKey(name: 'device_type') this.deviceType = 'mobile',
      @JsonKey(name: 'os_name') this.osName = '',
      @JsonKey(name: 'os_version') this.osVersion = '',
      @JsonKey(name: 'app_version') this.appVersion = '',
      @JsonKey(name: 'ip_address') this.ipAddress,
      @JsonKey(name: 'login_location') this.loginLocation,
      @JsonKey(name: 'last_active_at') this.lastActiveAt,
      @JsonKey(name: 'login_at') this.loginAt,
      @JsonKey(name: 'created_at') this.createdAt,
      @JsonKey(name: 'is_current') this.isCurrent = false,
      @JsonKey(name: 'is_active') this.isActive = true});

  factory _$DeviceSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceSessionImplFromJson(json);

  @override
  @JsonKey(readValue: _readSessionId)
  final String id;
  @override
  @JsonKey(name: 'device_id')
  final String deviceId;
  @override
  @JsonKey(name: 'device_name')
  final String deviceName;
  @override
  @JsonKey(name: 'device_type')
  final String deviceType;
  @override
  @JsonKey(name: 'os_name')
  final String osName;
  @override
  @JsonKey(name: 'os_version')
  final String osVersion;
  @override
  @JsonKey(name: 'app_version')
  final String appVersion;
  @override
  @JsonKey(name: 'ip_address')
  final String? ipAddress;
  @override
  @JsonKey(name: 'login_location')
  final String? loginLocation;
  @override
  @JsonKey(name: 'last_active_at')
  final DateTime? lastActiveAt;
  @override
  @JsonKey(name: 'login_at')
  final DateTime? loginAt;
  @override
  @JsonKey(name: 'created_at')
  final DateTime? createdAt;
  @override
  @JsonKey(name: 'is_current')
  final bool isCurrent;
  @override
  @JsonKey(name: 'is_active')
  final bool isActive;

  @override
  String toString() {
    return 'DeviceSession(id: $id, deviceId: $deviceId, deviceName: $deviceName, deviceType: $deviceType, osName: $osName, osVersion: $osVersion, appVersion: $appVersion, ipAddress: $ipAddress, loginLocation: $loginLocation, lastActiveAt: $lastActiveAt, loginAt: $loginAt, createdAt: $createdAt, isCurrent: $isCurrent, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceSessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.deviceId, deviceId) ||
                other.deviceId == deviceId) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.deviceType, deviceType) ||
                other.deviceType == deviceType) &&
            (identical(other.osName, osName) || other.osName == osName) &&
            (identical(other.osVersion, osVersion) ||
                other.osVersion == osVersion) &&
            (identical(other.appVersion, appVersion) ||
                other.appVersion == appVersion) &&
            (identical(other.ipAddress, ipAddress) ||
                other.ipAddress == ipAddress) &&
            (identical(other.loginLocation, loginLocation) ||
                other.loginLocation == loginLocation) &&
            (identical(other.lastActiveAt, lastActiveAt) ||
                other.lastActiveAt == lastActiveAt) &&
            (identical(other.loginAt, loginAt) || other.loginAt == loginAt) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.isCurrent, isCurrent) ||
                other.isCurrent == isCurrent) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      deviceId,
      deviceName,
      deviceType,
      osName,
      osVersion,
      appVersion,
      ipAddress,
      loginLocation,
      lastActiveAt,
      loginAt,
      createdAt,
      isCurrent,
      isActive);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceSessionImplCopyWith<_$DeviceSessionImpl> get copyWith =>
      __$$DeviceSessionImplCopyWithImpl<_$DeviceSessionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceSessionImplToJson(
      this,
    );
  }
}

abstract class _DeviceSession implements DeviceSession {
  const factory _DeviceSession(
      {@JsonKey(readValue: _readSessionId) required final String id,
      @JsonKey(name: 'device_id') final String deviceId,
      @JsonKey(name: 'device_name') final String deviceName,
      @JsonKey(name: 'device_type') final String deviceType,
      @JsonKey(name: 'os_name') final String osName,
      @JsonKey(name: 'os_version') final String osVersion,
      @JsonKey(name: 'app_version') final String appVersion,
      @JsonKey(name: 'ip_address') final String? ipAddress,
      @JsonKey(name: 'login_location') final String? loginLocation,
      @JsonKey(name: 'last_active_at') final DateTime? lastActiveAt,
      @JsonKey(name: 'login_at') final DateTime? loginAt,
      @JsonKey(name: 'created_at') final DateTime? createdAt,
      @JsonKey(name: 'is_current') final bool isCurrent,
      @JsonKey(name: 'is_active') final bool isActive}) = _$DeviceSessionImpl;

  factory _DeviceSession.fromJson(Map<String, dynamic> json) =
      _$DeviceSessionImpl.fromJson;

  @override
  @JsonKey(readValue: _readSessionId)
  String get id;
  @override
  @JsonKey(name: 'device_id')
  String get deviceId;
  @override
  @JsonKey(name: 'device_name')
  String get deviceName;
  @override
  @JsonKey(name: 'device_type')
  String get deviceType;
  @override
  @JsonKey(name: 'os_name')
  String get osName;
  @override
  @JsonKey(name: 'os_version')
  String get osVersion;
  @override
  @JsonKey(name: 'app_version')
  String get appVersion;
  @override
  @JsonKey(name: 'ip_address')
  String? get ipAddress;
  @override
  @JsonKey(name: 'login_location')
  String? get loginLocation;
  @override
  @JsonKey(name: 'last_active_at')
  DateTime? get lastActiveAt;
  @override
  @JsonKey(name: 'login_at')
  DateTime? get loginAt;
  @override
  @JsonKey(name: 'created_at')
  DateTime? get createdAt;
  @override
  @JsonKey(name: 'is_current')
  bool get isCurrent;
  @override
  @JsonKey(name: 'is_active')
  bool get isActive;
  @override
  @JsonKey(ignore: true)
  _$$DeviceSessionImplCopyWith<_$DeviceSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DeviceSessionsResponse _$DeviceSessionsResponseFromJson(
    Map<String, dynamic> json) {
  return _DeviceSessionsResponse.fromJson(json);
}

/// @nodoc
mixin _$DeviceSessionsResponse {
  List<DeviceSession> get sessions => throw _privateConstructorUsedError;
  @JsonKey(name: 'max_devices')
  int get maxDevices => throw _privateConstructorUsedError;
  @JsonKey(name: 'active_count')
  int get activeCount => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeviceSessionsResponseCopyWith<DeviceSessionsResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceSessionsResponseCopyWith<$Res> {
  factory $DeviceSessionsResponseCopyWith(DeviceSessionsResponse value,
          $Res Function(DeviceSessionsResponse) then) =
      _$DeviceSessionsResponseCopyWithImpl<$Res, DeviceSessionsResponse>;
  @useResult
  $Res call(
      {List<DeviceSession> sessions,
      @JsonKey(name: 'max_devices') int maxDevices,
      @JsonKey(name: 'active_count') int activeCount});
}

/// @nodoc
class _$DeviceSessionsResponseCopyWithImpl<$Res,
        $Val extends DeviceSessionsResponse>
    implements $DeviceSessionsResponseCopyWith<$Res> {
  _$DeviceSessionsResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessions = null,
    Object? maxDevices = null,
    Object? activeCount = null,
  }) {
    return _then(_value.copyWith(
      sessions: null == sessions
          ? _value.sessions
          : sessions // ignore: cast_nullable_to_non_nullable
              as List<DeviceSession>,
      maxDevices: null == maxDevices
          ? _value.maxDevices
          : maxDevices // ignore: cast_nullable_to_non_nullable
              as int,
      activeCount: null == activeCount
          ? _value.activeCount
          : activeCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceSessionsResponseImplCopyWith<$Res>
    implements $DeviceSessionsResponseCopyWith<$Res> {
  factory _$$DeviceSessionsResponseImplCopyWith(
          _$DeviceSessionsResponseImpl value,
          $Res Function(_$DeviceSessionsResponseImpl) then) =
      __$$DeviceSessionsResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<DeviceSession> sessions,
      @JsonKey(name: 'max_devices') int maxDevices,
      @JsonKey(name: 'active_count') int activeCount});
}

/// @nodoc
class __$$DeviceSessionsResponseImplCopyWithImpl<$Res>
    extends _$DeviceSessionsResponseCopyWithImpl<$Res,
        _$DeviceSessionsResponseImpl>
    implements _$$DeviceSessionsResponseImplCopyWith<$Res> {
  __$$DeviceSessionsResponseImplCopyWithImpl(
      _$DeviceSessionsResponseImpl _value,
      $Res Function(_$DeviceSessionsResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessions = null,
    Object? maxDevices = null,
    Object? activeCount = null,
  }) {
    return _then(_$DeviceSessionsResponseImpl(
      sessions: null == sessions
          ? _value._sessions
          : sessions // ignore: cast_nullable_to_non_nullable
              as List<DeviceSession>,
      maxDevices: null == maxDevices
          ? _value.maxDevices
          : maxDevices // ignore: cast_nullable_to_non_nullable
              as int,
      activeCount: null == activeCount
          ? _value.activeCount
          : activeCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceSessionsResponseImpl implements _DeviceSessionsResponse {
  const _$DeviceSessionsResponseImpl(
      {final List<DeviceSession> sessions = const [],
      @JsonKey(name: 'max_devices') this.maxDevices = 2,
      @JsonKey(name: 'active_count') this.activeCount = 0})
      : _sessions = sessions;

  factory _$DeviceSessionsResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceSessionsResponseImplFromJson(json);

  final List<DeviceSession> _sessions;
  @override
  @JsonKey()
  List<DeviceSession> get sessions {
    if (_sessions is EqualUnmodifiableListView) return _sessions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sessions);
  }

  @override
  @JsonKey(name: 'max_devices')
  final int maxDevices;
  @override
  @JsonKey(name: 'active_count')
  final int activeCount;

  @override
  String toString() {
    return 'DeviceSessionsResponse(sessions: $sessions, maxDevices: $maxDevices, activeCount: $activeCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceSessionsResponseImpl &&
            const DeepCollectionEquality().equals(other._sessions, _sessions) &&
            (identical(other.maxDevices, maxDevices) ||
                other.maxDevices == maxDevices) &&
            (identical(other.activeCount, activeCount) ||
                other.activeCount == activeCount));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType,
      const DeepCollectionEquality().hash(_sessions), maxDevices, activeCount);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceSessionsResponseImplCopyWith<_$DeviceSessionsResponseImpl>
      get copyWith => __$$DeviceSessionsResponseImplCopyWithImpl<
          _$DeviceSessionsResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceSessionsResponseImplToJson(
      this,
    );
  }
}

abstract class _DeviceSessionsResponse implements DeviceSessionsResponse {
  const factory _DeviceSessionsResponse(
          {final List<DeviceSession> sessions,
          @JsonKey(name: 'max_devices') final int maxDevices,
          @JsonKey(name: 'active_count') final int activeCount}) =
      _$DeviceSessionsResponseImpl;

  factory _DeviceSessionsResponse.fromJson(Map<String, dynamic> json) =
      _$DeviceSessionsResponseImpl.fromJson;

  @override
  List<DeviceSession> get sessions;
  @override
  @JsonKey(name: 'max_devices')
  int get maxDevices;
  @override
  @JsonKey(name: 'active_count')
  int get activeCount;
  @override
  @JsonKey(ignore: true)
  _$$DeviceSessionsResponseImplCopyWith<_$DeviceSessionsResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

DeviceLimitError _$DeviceLimitErrorFromJson(Map<String, dynamic> json) {
  return _DeviceLimitError.fromJson(json);
}

/// @nodoc
mixin _$DeviceLimitError {
  String get error => throw _privateConstructorUsedError;
  String get message => throw _privateConstructorUsedError;
  @JsonKey(readValue: _readActiveDevices)
  List<DeviceSession> get activeDevices => throw _privateConstructorUsedError;
  @JsonKey(name: 'max_devices')
  int get maxDevices => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeviceLimitErrorCopyWith<DeviceLimitError> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceLimitErrorCopyWith<$Res> {
  factory $DeviceLimitErrorCopyWith(
          DeviceLimitError value, $Res Function(DeviceLimitError) then) =
      _$DeviceLimitErrorCopyWithImpl<$Res, DeviceLimitError>;
  @useResult
  $Res call(
      {String error,
      String message,
      @JsonKey(readValue: _readActiveDevices) List<DeviceSession> activeDevices,
      @JsonKey(name: 'max_devices') int maxDevices});
}

/// @nodoc
class _$DeviceLimitErrorCopyWithImpl<$Res, $Val extends DeviceLimitError>
    implements $DeviceLimitErrorCopyWith<$Res> {
  _$DeviceLimitErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? error = null,
    Object? message = null,
    Object? activeDevices = null,
    Object? maxDevices = null,
  }) {
    return _then(_value.copyWith(
      error: null == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      activeDevices: null == activeDevices
          ? _value.activeDevices
          : activeDevices // ignore: cast_nullable_to_non_nullable
              as List<DeviceSession>,
      maxDevices: null == maxDevices
          ? _value.maxDevices
          : maxDevices // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeviceLimitErrorImplCopyWith<$Res>
    implements $DeviceLimitErrorCopyWith<$Res> {
  factory _$$DeviceLimitErrorImplCopyWith(_$DeviceLimitErrorImpl value,
          $Res Function(_$DeviceLimitErrorImpl) then) =
      __$$DeviceLimitErrorImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String error,
      String message,
      @JsonKey(readValue: _readActiveDevices) List<DeviceSession> activeDevices,
      @JsonKey(name: 'max_devices') int maxDevices});
}

/// @nodoc
class __$$DeviceLimitErrorImplCopyWithImpl<$Res>
    extends _$DeviceLimitErrorCopyWithImpl<$Res, _$DeviceLimitErrorImpl>
    implements _$$DeviceLimitErrorImplCopyWith<$Res> {
  __$$DeviceLimitErrorImplCopyWithImpl(_$DeviceLimitErrorImpl _value,
      $Res Function(_$DeviceLimitErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? error = null,
    Object? message = null,
    Object? activeDevices = null,
    Object? maxDevices = null,
  }) {
    return _then(_$DeviceLimitErrorImpl(
      error: null == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      activeDevices: null == activeDevices
          ? _value._activeDevices
          : activeDevices // ignore: cast_nullable_to_non_nullable
              as List<DeviceSession>,
      maxDevices: null == maxDevices
          ? _value.maxDevices
          : maxDevices // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeviceLimitErrorImpl implements _DeviceLimitError {
  const _$DeviceLimitErrorImpl(
      {this.error = 'device_limit_reached',
      this.message =
          'Maximum device limit reached. Please logout from another device to continue.',
      @JsonKey(readValue: _readActiveDevices)
      final List<DeviceSession> activeDevices = const [],
      @JsonKey(name: 'max_devices') this.maxDevices = 2})
      : _activeDevices = activeDevices;

  factory _$DeviceLimitErrorImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeviceLimitErrorImplFromJson(json);

  @override
  @JsonKey()
  final String error;
  @override
  @JsonKey()
  final String message;
  final List<DeviceSession> _activeDevices;
  @override
  @JsonKey(readValue: _readActiveDevices)
  List<DeviceSession> get activeDevices {
    if (_activeDevices is EqualUnmodifiableListView) return _activeDevices;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_activeDevices);
  }

  @override
  @JsonKey(name: 'max_devices')
  final int maxDevices;

  @override
  String toString() {
    return 'DeviceLimitError(error: $error, message: $message, activeDevices: $activeDevices, maxDevices: $maxDevices)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceLimitErrorImpl &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.message, message) || other.message == message) &&
            const DeepCollectionEquality()
                .equals(other._activeDevices, _activeDevices) &&
            (identical(other.maxDevices, maxDevices) ||
                other.maxDevices == maxDevices));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, error, message,
      const DeepCollectionEquality().hash(_activeDevices), maxDevices);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceLimitErrorImplCopyWith<_$DeviceLimitErrorImpl> get copyWith =>
      __$$DeviceLimitErrorImplCopyWithImpl<_$DeviceLimitErrorImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeviceLimitErrorImplToJson(
      this,
    );
  }
}

abstract class _DeviceLimitError implements DeviceLimitError {
  const factory _DeviceLimitError(
          {final String error,
          final String message,
          @JsonKey(readValue: _readActiveDevices)
          final List<DeviceSession> activeDevices,
          @JsonKey(name: 'max_devices') final int maxDevices}) =
      _$DeviceLimitErrorImpl;

  factory _DeviceLimitError.fromJson(Map<String, dynamic> json) =
      _$DeviceLimitErrorImpl.fromJson;

  @override
  String get error;
  @override
  String get message;
  @override
  @JsonKey(readValue: _readActiveDevices)
  List<DeviceSession> get activeDevices;
  @override
  @JsonKey(name: 'max_devices')
  int get maxDevices;
  @override
  @JsonKey(ignore: true)
  _$$DeviceLimitErrorImplCopyWith<_$DeviceLimitErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

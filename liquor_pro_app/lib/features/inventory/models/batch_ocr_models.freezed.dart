// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'batch_ocr_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

BatchOCRSession _$BatchOCRSessionFromJson(Map<String, dynamic> json) {
  return _BatchOCRSession.fromJson(json);
}

/// @nodoc
mixin _$BatchOCRSession {
  String get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'tenant_id')
  String get tenantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'user_id')
  String get userId => throw _privateConstructorUsedError;
  @JsonKey(name: 'shop_id')
  String get shopId => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_type')
  String get sessionType => throw _privateConstructorUsedError;
  BatchStatus get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_images')
  int get totalImages => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_images')
  int get completedImages => throw _privateConstructorUsedError;
  @JsonKey(name: 'failed_images')
  int get failedImages => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_items_extracted')
  int get totalItemsExtracted => throw _privateConstructorUsedError;
  @JsonKey(name: 'created_at')
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'started_at')
  DateTime? get startedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds => throw _privateConstructorUsedError;
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BatchOCRSessionCopyWith<BatchOCRSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BatchOCRSessionCopyWith<$Res> {
  factory $BatchOCRSessionCopyWith(
          BatchOCRSession value, $Res Function(BatchOCRSession) then) =
      _$BatchOCRSessionCopyWithImpl<$Res, BatchOCRSession>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String tenantId,
      @JsonKey(name: 'user_id') String userId,
      @JsonKey(name: 'shop_id') String shopId,
      @JsonKey(name: 'session_type') String sessionType,
      BatchStatus status,
      @JsonKey(name: 'total_images') int totalImages,
      @JsonKey(name: 'completed_images') int completedImages,
      @JsonKey(name: 'failed_images') int failedImages,
      @JsonKey(name: 'total_items_extracted') int totalItemsExtracted,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'started_at') DateTime? startedAt,
      @JsonKey(name: 'completed_at') DateTime? completedAt,
      @JsonKey(name: 'session_ids') List<String> sessionIds,
      Map<String, dynamic>? metadata});
}

/// @nodoc
class _$BatchOCRSessionCopyWithImpl<$Res, $Val extends BatchOCRSession>
    implements $BatchOCRSessionCopyWith<$Res> {
  _$BatchOCRSessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = null,
    Object? userId = null,
    Object? shopId = null,
    Object? sessionType = null,
    Object? status = null,
    Object? totalImages = null,
    Object? completedImages = null,
    Object? failedImages = null,
    Object? totalItemsExtracted = null,
    Object? createdAt = null,
    Object? startedAt = freezed,
    Object? completedAt = freezed,
    Object? sessionIds = null,
    Object? metadata = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: null == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as BatchStatus,
      totalImages: null == totalImages
          ? _value.totalImages
          : totalImages // ignore: cast_nullable_to_non_nullable
              as int,
      completedImages: null == completedImages
          ? _value.completedImages
          : completedImages // ignore: cast_nullable_to_non_nullable
              as int,
      failedImages: null == failedImages
          ? _value.failedImages
          : failedImages // ignore: cast_nullable_to_non_nullable
              as int,
      totalItemsExtracted: null == totalItemsExtracted
          ? _value.totalItemsExtracted
          : totalItemsExtracted // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      startedAt: freezed == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      sessionIds: null == sessionIds
          ? _value.sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      metadata: freezed == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BatchOCRSessionImplCopyWith<$Res>
    implements $BatchOCRSessionCopyWith<$Res> {
  factory _$$BatchOCRSessionImplCopyWith(_$BatchOCRSessionImpl value,
          $Res Function(_$BatchOCRSessionImpl) then) =
      __$$BatchOCRSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(name: 'tenant_id') String tenantId,
      @JsonKey(name: 'user_id') String userId,
      @JsonKey(name: 'shop_id') String shopId,
      @JsonKey(name: 'session_type') String sessionType,
      BatchStatus status,
      @JsonKey(name: 'total_images') int totalImages,
      @JsonKey(name: 'completed_images') int completedImages,
      @JsonKey(name: 'failed_images') int failedImages,
      @JsonKey(name: 'total_items_extracted') int totalItemsExtracted,
      @JsonKey(name: 'created_at') DateTime createdAt,
      @JsonKey(name: 'started_at') DateTime? startedAt,
      @JsonKey(name: 'completed_at') DateTime? completedAt,
      @JsonKey(name: 'session_ids') List<String> sessionIds,
      Map<String, dynamic>? metadata});
}

/// @nodoc
class __$$BatchOCRSessionImplCopyWithImpl<$Res>
    extends _$BatchOCRSessionCopyWithImpl<$Res, _$BatchOCRSessionImpl>
    implements _$$BatchOCRSessionImplCopyWith<$Res> {
  __$$BatchOCRSessionImplCopyWithImpl(
      _$BatchOCRSessionImpl _value, $Res Function(_$BatchOCRSessionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? tenantId = null,
    Object? userId = null,
    Object? shopId = null,
    Object? sessionType = null,
    Object? status = null,
    Object? totalImages = null,
    Object? completedImages = null,
    Object? failedImages = null,
    Object? totalItemsExtracted = null,
    Object? createdAt = null,
    Object? startedAt = freezed,
    Object? completedAt = freezed,
    Object? sessionIds = null,
    Object? metadata = freezed,
  }) {
    return _then(_$BatchOCRSessionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      tenantId: null == tenantId
          ? _value.tenantId
          : tenantId // ignore: cast_nullable_to_non_nullable
              as String,
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as BatchStatus,
      totalImages: null == totalImages
          ? _value.totalImages
          : totalImages // ignore: cast_nullable_to_non_nullable
              as int,
      completedImages: null == completedImages
          ? _value.completedImages
          : completedImages // ignore: cast_nullable_to_non_nullable
              as int,
      failedImages: null == failedImages
          ? _value.failedImages
          : failedImages // ignore: cast_nullable_to_non_nullable
              as int,
      totalItemsExtracted: null == totalItemsExtracted
          ? _value.totalItemsExtracted
          : totalItemsExtracted // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      startedAt: freezed == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      completedAt: freezed == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      sessionIds: null == sessionIds
          ? _value._sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      metadata: freezed == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BatchOCRSessionImpl
    with DiagnosticableTreeMixin
    implements _BatchOCRSession {
  const _$BatchOCRSessionImpl(
      {required this.id,
      @JsonKey(name: 'tenant_id') required this.tenantId,
      @JsonKey(name: 'user_id') required this.userId,
      @JsonKey(name: 'shop_id') required this.shopId,
      @JsonKey(name: 'session_type') required this.sessionType,
      required this.status,
      @JsonKey(name: 'total_images') required this.totalImages,
      @JsonKey(name: 'completed_images') required this.completedImages,
      @JsonKey(name: 'failed_images') required this.failedImages,
      @JsonKey(name: 'total_items_extracted') required this.totalItemsExtracted,
      @JsonKey(name: 'created_at') required this.createdAt,
      @JsonKey(name: 'started_at') this.startedAt,
      @JsonKey(name: 'completed_at') this.completedAt,
      @JsonKey(name: 'session_ids') final List<String> sessionIds = const [],
      final Map<String, dynamic>? metadata})
      : _sessionIds = sessionIds,
        _metadata = metadata;

  factory _$BatchOCRSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$BatchOCRSessionImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey(name: 'tenant_id')
  final String tenantId;
  @override
  @JsonKey(name: 'user_id')
  final String userId;
  @override
  @JsonKey(name: 'shop_id')
  final String shopId;
  @override
  @JsonKey(name: 'session_type')
  final String sessionType;
  @override
  final BatchStatus status;
  @override
  @JsonKey(name: 'total_images')
  final int totalImages;
  @override
  @JsonKey(name: 'completed_images')
  final int completedImages;
  @override
  @JsonKey(name: 'failed_images')
  final int failedImages;
  @override
  @JsonKey(name: 'total_items_extracted')
  final int totalItemsExtracted;
  @override
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @override
  @JsonKey(name: 'started_at')
  final DateTime? startedAt;
  @override
  @JsonKey(name: 'completed_at')
  final DateTime? completedAt;
  final List<String> _sessionIds;
  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds {
    if (_sessionIds is EqualUnmodifiableListView) return _sessionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sessionIds);
  }

  final Map<String, dynamic>? _metadata;
  @override
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'BatchOCRSession(id: $id, tenantId: $tenantId, userId: $userId, shopId: $shopId, sessionType: $sessionType, status: $status, totalImages: $totalImages, completedImages: $completedImages, failedImages: $failedImages, totalItemsExtracted: $totalItemsExtracted, createdAt: $createdAt, startedAt: $startedAt, completedAt: $completedAt, sessionIds: $sessionIds, metadata: $metadata)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'BatchOCRSession'))
      ..add(DiagnosticsProperty('id', id))
      ..add(DiagnosticsProperty('tenantId', tenantId))
      ..add(DiagnosticsProperty('userId', userId))
      ..add(DiagnosticsProperty('shopId', shopId))
      ..add(DiagnosticsProperty('sessionType', sessionType))
      ..add(DiagnosticsProperty('status', status))
      ..add(DiagnosticsProperty('totalImages', totalImages))
      ..add(DiagnosticsProperty('completedImages', completedImages))
      ..add(DiagnosticsProperty('failedImages', failedImages))
      ..add(DiagnosticsProperty('totalItemsExtracted', totalItemsExtracted))
      ..add(DiagnosticsProperty('createdAt', createdAt))
      ..add(DiagnosticsProperty('startedAt', startedAt))
      ..add(DiagnosticsProperty('completedAt', completedAt))
      ..add(DiagnosticsProperty('sessionIds', sessionIds))
      ..add(DiagnosticsProperty('metadata', metadata));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BatchOCRSessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.tenantId, tenantId) ||
                other.tenantId == tenantId) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.shopId, shopId) || other.shopId == shopId) &&
            (identical(other.sessionType, sessionType) ||
                other.sessionType == sessionType) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.totalImages, totalImages) ||
                other.totalImages == totalImages) &&
            (identical(other.completedImages, completedImages) ||
                other.completedImages == completedImages) &&
            (identical(other.failedImages, failedImages) ||
                other.failedImages == failedImages) &&
            (identical(other.totalItemsExtracted, totalItemsExtracted) ||
                other.totalItemsExtracted == totalItemsExtracted) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            const DeepCollectionEquality()
                .equals(other._sessionIds, _sessionIds) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      tenantId,
      userId,
      shopId,
      sessionType,
      status,
      totalImages,
      completedImages,
      failedImages,
      totalItemsExtracted,
      createdAt,
      startedAt,
      completedAt,
      const DeepCollectionEquality().hash(_sessionIds),
      const DeepCollectionEquality().hash(_metadata));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BatchOCRSessionImplCopyWith<_$BatchOCRSessionImpl> get copyWith =>
      __$$BatchOCRSessionImplCopyWithImpl<_$BatchOCRSessionImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BatchOCRSessionImplToJson(
      this,
    );
  }
}

abstract class _BatchOCRSession implements BatchOCRSession {
  const factory _BatchOCRSession(
      {required final String id,
      @JsonKey(name: 'tenant_id') required final String tenantId,
      @JsonKey(name: 'user_id') required final String userId,
      @JsonKey(name: 'shop_id') required final String shopId,
      @JsonKey(name: 'session_type') required final String sessionType,
      required final BatchStatus status,
      @JsonKey(name: 'total_images') required final int totalImages,
      @JsonKey(name: 'completed_images') required final int completedImages,
      @JsonKey(name: 'failed_images') required final int failedImages,
      @JsonKey(name: 'total_items_extracted')
      required final int totalItemsExtracted,
      @JsonKey(name: 'created_at') required final DateTime createdAt,
      @JsonKey(name: 'started_at') final DateTime? startedAt,
      @JsonKey(name: 'completed_at') final DateTime? completedAt,
      @JsonKey(name: 'session_ids') final List<String> sessionIds,
      final Map<String, dynamic>? metadata}) = _$BatchOCRSessionImpl;

  factory _BatchOCRSession.fromJson(Map<String, dynamic> json) =
      _$BatchOCRSessionImpl.fromJson;

  @override
  String get id;
  @override
  @JsonKey(name: 'tenant_id')
  String get tenantId;
  @override
  @JsonKey(name: 'user_id')
  String get userId;
  @override
  @JsonKey(name: 'shop_id')
  String get shopId;
  @override
  @JsonKey(name: 'session_type')
  String get sessionType;
  @override
  BatchStatus get status;
  @override
  @JsonKey(name: 'total_images')
  int get totalImages;
  @override
  @JsonKey(name: 'completed_images')
  int get completedImages;
  @override
  @JsonKey(name: 'failed_images')
  int get failedImages;
  @override
  @JsonKey(name: 'total_items_extracted')
  int get totalItemsExtracted;
  @override
  @JsonKey(name: 'created_at')
  DateTime get createdAt;
  @override
  @JsonKey(name: 'started_at')
  DateTime? get startedAt;
  @override
  @JsonKey(name: 'completed_at')
  DateTime? get completedAt;
  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds;
  @override
  Map<String, dynamic>? get metadata;
  @override
  @JsonKey(ignore: true)
  _$$BatchOCRSessionImplCopyWith<_$BatchOCRSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

FailedImage _$FailedImageFromJson(Map<String, dynamic> json) {
  return _FailedImage.fromJson(json);
}

/// @nodoc
mixin _$FailedImage {
  String get imagePath => throw _privateConstructorUsedError;
  String get errorMessage => throw _privateConstructorUsedError;
  DateTime get failedAt => throw _privateConstructorUsedError;
  int get retryCount => throw _privateConstructorUsedError;
  String? get errorCode => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FailedImageCopyWith<FailedImage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FailedImageCopyWith<$Res> {
  factory $FailedImageCopyWith(
          FailedImage value, $Res Function(FailedImage) then) =
      _$FailedImageCopyWithImpl<$Res, FailedImage>;
  @useResult
  $Res call(
      {String imagePath,
      String errorMessage,
      DateTime failedAt,
      int retryCount,
      String? errorCode});
}

/// @nodoc
class _$FailedImageCopyWithImpl<$Res, $Val extends FailedImage>
    implements $FailedImageCopyWith<$Res> {
  _$FailedImageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imagePath = null,
    Object? errorMessage = null,
    Object? failedAt = null,
    Object? retryCount = null,
    Object? errorCode = freezed,
  }) {
    return _then(_value.copyWith(
      imagePath: null == imagePath
          ? _value.imagePath
          : imagePath // ignore: cast_nullable_to_non_nullable
              as String,
      errorMessage: null == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String,
      failedAt: null == failedAt
          ? _value.failedAt
          : failedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      errorCode: freezed == errorCode
          ? _value.errorCode
          : errorCode // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FailedImageImplCopyWith<$Res>
    implements $FailedImageCopyWith<$Res> {
  factory _$$FailedImageImplCopyWith(
          _$FailedImageImpl value, $Res Function(_$FailedImageImpl) then) =
      __$$FailedImageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String imagePath,
      String errorMessage,
      DateTime failedAt,
      int retryCount,
      String? errorCode});
}

/// @nodoc
class __$$FailedImageImplCopyWithImpl<$Res>
    extends _$FailedImageCopyWithImpl<$Res, _$FailedImageImpl>
    implements _$$FailedImageImplCopyWith<$Res> {
  __$$FailedImageImplCopyWithImpl(
      _$FailedImageImpl _value, $Res Function(_$FailedImageImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imagePath = null,
    Object? errorMessage = null,
    Object? failedAt = null,
    Object? retryCount = null,
    Object? errorCode = freezed,
  }) {
    return _then(_$FailedImageImpl(
      imagePath: null == imagePath
          ? _value.imagePath
          : imagePath // ignore: cast_nullable_to_non_nullable
              as String,
      errorMessage: null == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String,
      failedAt: null == failedAt
          ? _value.failedAt
          : failedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      retryCount: null == retryCount
          ? _value.retryCount
          : retryCount // ignore: cast_nullable_to_non_nullable
              as int,
      errorCode: freezed == errorCode
          ? _value.errorCode
          : errorCode // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FailedImageImpl with DiagnosticableTreeMixin implements _FailedImage {
  const _$FailedImageImpl(
      {required this.imagePath,
      required this.errorMessage,
      required this.failedAt,
      this.retryCount = 0,
      this.errorCode});

  factory _$FailedImageImpl.fromJson(Map<String, dynamic> json) =>
      _$$FailedImageImplFromJson(json);

  @override
  final String imagePath;
  @override
  final String errorMessage;
  @override
  final DateTime failedAt;
  @override
  @JsonKey()
  final int retryCount;
  @override
  final String? errorCode;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'FailedImage(imagePath: $imagePath, errorMessage: $errorMessage, failedAt: $failedAt, retryCount: $retryCount, errorCode: $errorCode)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'FailedImage'))
      ..add(DiagnosticsProperty('imagePath', imagePath))
      ..add(DiagnosticsProperty('errorMessage', errorMessage))
      ..add(DiagnosticsProperty('failedAt', failedAt))
      ..add(DiagnosticsProperty('retryCount', retryCount))
      ..add(DiagnosticsProperty('errorCode', errorCode));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FailedImageImpl &&
            (identical(other.imagePath, imagePath) ||
                other.imagePath == imagePath) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.failedAt, failedAt) ||
                other.failedAt == failedAt) &&
            (identical(other.retryCount, retryCount) ||
                other.retryCount == retryCount) &&
            (identical(other.errorCode, errorCode) ||
                other.errorCode == errorCode));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, imagePath, errorMessage, failedAt, retryCount, errorCode);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FailedImageImplCopyWith<_$FailedImageImpl> get copyWith =>
      __$$FailedImageImplCopyWithImpl<_$FailedImageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FailedImageImplToJson(
      this,
    );
  }
}

abstract class _FailedImage implements FailedImage {
  const factory _FailedImage(
      {required final String imagePath,
      required final String errorMessage,
      required final DateTime failedAt,
      final int retryCount,
      final String? errorCode}) = _$FailedImageImpl;

  factory _FailedImage.fromJson(Map<String, dynamic> json) =
      _$FailedImageImpl.fromJson;

  @override
  String get imagePath;
  @override
  String get errorMessage;
  @override
  DateTime get failedAt;
  @override
  int get retryCount;
  @override
  String? get errorCode;
  @override
  @JsonKey(ignore: true)
  _$$FailedImageImplCopyWith<_$FailedImageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ProcessingTimeout _$ProcessingTimeoutFromJson(Map<String, dynamic> json) {
  return _ProcessingTimeout.fromJson(json);
}

/// @nodoc
mixin _$ProcessingTimeout {
  DateTime get startTime => throw _privateConstructorUsedError;
  Duration get maxDuration => throw _privateConstructorUsedError;
  String? get currentStage => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ProcessingTimeoutCopyWith<ProcessingTimeout> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ProcessingTimeoutCopyWith<$Res> {
  factory $ProcessingTimeoutCopyWith(
          ProcessingTimeout value, $Res Function(ProcessingTimeout) then) =
      _$ProcessingTimeoutCopyWithImpl<$Res, ProcessingTimeout>;
  @useResult
  $Res call({DateTime startTime, Duration maxDuration, String? currentStage});
}

/// @nodoc
class _$ProcessingTimeoutCopyWithImpl<$Res, $Val extends ProcessingTimeout>
    implements $ProcessingTimeoutCopyWith<$Res> {
  _$ProcessingTimeoutCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? startTime = null,
    Object? maxDuration = null,
    Object? currentStage = freezed,
  }) {
    return _then(_value.copyWith(
      startTime: null == startTime
          ? _value.startTime
          : startTime // ignore: cast_nullable_to_non_nullable
              as DateTime,
      maxDuration: null == maxDuration
          ? _value.maxDuration
          : maxDuration // ignore: cast_nullable_to_non_nullable
              as Duration,
      currentStage: freezed == currentStage
          ? _value.currentStage
          : currentStage // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ProcessingTimeoutImplCopyWith<$Res>
    implements $ProcessingTimeoutCopyWith<$Res> {
  factory _$$ProcessingTimeoutImplCopyWith(_$ProcessingTimeoutImpl value,
          $Res Function(_$ProcessingTimeoutImpl) then) =
      __$$ProcessingTimeoutImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({DateTime startTime, Duration maxDuration, String? currentStage});
}

/// @nodoc
class __$$ProcessingTimeoutImplCopyWithImpl<$Res>
    extends _$ProcessingTimeoutCopyWithImpl<$Res, _$ProcessingTimeoutImpl>
    implements _$$ProcessingTimeoutImplCopyWith<$Res> {
  __$$ProcessingTimeoutImplCopyWithImpl(_$ProcessingTimeoutImpl _value,
      $Res Function(_$ProcessingTimeoutImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? startTime = null,
    Object? maxDuration = null,
    Object? currentStage = freezed,
  }) {
    return _then(_$ProcessingTimeoutImpl(
      startTime: null == startTime
          ? _value.startTime
          : startTime // ignore: cast_nullable_to_non_nullable
              as DateTime,
      maxDuration: null == maxDuration
          ? _value.maxDuration
          : maxDuration // ignore: cast_nullable_to_non_nullable
              as Duration,
      currentStage: freezed == currentStage
          ? _value.currentStage
          : currentStage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ProcessingTimeoutImpl extends _ProcessingTimeout
    with DiagnosticableTreeMixin {
  const _$ProcessingTimeoutImpl(
      {required this.startTime, required this.maxDuration, this.currentStage})
      : super._();

  factory _$ProcessingTimeoutImpl.fromJson(Map<String, dynamic> json) =>
      _$$ProcessingTimeoutImplFromJson(json);

  @override
  final DateTime startTime;
  @override
  final Duration maxDuration;
  @override
  final String? currentStage;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ProcessingTimeout(startTime: $startTime, maxDuration: $maxDuration, currentStage: $currentStage)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'ProcessingTimeout'))
      ..add(DiagnosticsProperty('startTime', startTime))
      ..add(DiagnosticsProperty('maxDuration', maxDuration))
      ..add(DiagnosticsProperty('currentStage', currentStage));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProcessingTimeoutImpl &&
            (identical(other.startTime, startTime) ||
                other.startTime == startTime) &&
            (identical(other.maxDuration, maxDuration) ||
                other.maxDuration == maxDuration) &&
            (identical(other.currentStage, currentStage) ||
                other.currentStage == currentStage));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, startTime, maxDuration, currentStage);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ProcessingTimeoutImplCopyWith<_$ProcessingTimeoutImpl> get copyWith =>
      __$$ProcessingTimeoutImplCopyWithImpl<_$ProcessingTimeoutImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ProcessingTimeoutImplToJson(
      this,
    );
  }
}

abstract class _ProcessingTimeout extends ProcessingTimeout {
  const factory _ProcessingTimeout(
      {required final DateTime startTime,
      required final Duration maxDuration,
      final String? currentStage}) = _$ProcessingTimeoutImpl;
  const _ProcessingTimeout._() : super._();

  factory _ProcessingTimeout.fromJson(Map<String, dynamic> json) =
      _$ProcessingTimeoutImpl.fromJson;

  @override
  DateTime get startTime;
  @override
  Duration get maxDuration;
  @override
  String? get currentStage;
  @override
  @JsonKey(ignore: true)
  _$$ProcessingTimeoutImplCopyWith<_$ProcessingTimeoutImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ImageData _$ImageDataFromJson(Map<String, dynamic> json) {
  return _ImageData.fromJson(json);
}

/// @nodoc
mixin _$ImageData {
  @JsonKey(name: 'image_data')
  String get imageData => throw _privateConstructorUsedError; // Base64 encoded
  @JsonKey(name: 'image_type')
  String get imageType => throw _privateConstructorUsedError; // png, jpg, jpeg
  @JsonKey(name: 'file_name')
  String? get fileName => throw _privateConstructorUsedError;
  @JsonKey(name: 'file_size')
  int? get fileSize => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ImageDataCopyWith<ImageData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ImageDataCopyWith<$Res> {
  factory $ImageDataCopyWith(ImageData value, $Res Function(ImageData) then) =
      _$ImageDataCopyWithImpl<$Res, ImageData>;
  @useResult
  $Res call(
      {@JsonKey(name: 'image_data') String imageData,
      @JsonKey(name: 'image_type') String imageType,
      @JsonKey(name: 'file_name') String? fileName,
      @JsonKey(name: 'file_size') int? fileSize});
}

/// @nodoc
class _$ImageDataCopyWithImpl<$Res, $Val extends ImageData>
    implements $ImageDataCopyWith<$Res> {
  _$ImageDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imageData = null,
    Object? imageType = null,
    Object? fileName = freezed,
    Object? fileSize = freezed,
  }) {
    return _then(_value.copyWith(
      imageData: null == imageData
          ? _value.imageData
          : imageData // ignore: cast_nullable_to_non_nullable
              as String,
      imageType: null == imageType
          ? _value.imageType
          : imageType // ignore: cast_nullable_to_non_nullable
              as String,
      fileName: freezed == fileName
          ? _value.fileName
          : fileName // ignore: cast_nullable_to_non_nullable
              as String?,
      fileSize: freezed == fileSize
          ? _value.fileSize
          : fileSize // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ImageDataImplCopyWith<$Res>
    implements $ImageDataCopyWith<$Res> {
  factory _$$ImageDataImplCopyWith(
          _$ImageDataImpl value, $Res Function(_$ImageDataImpl) then) =
      __$$ImageDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'image_data') String imageData,
      @JsonKey(name: 'image_type') String imageType,
      @JsonKey(name: 'file_name') String? fileName,
      @JsonKey(name: 'file_size') int? fileSize});
}

/// @nodoc
class __$$ImageDataImplCopyWithImpl<$Res>
    extends _$ImageDataCopyWithImpl<$Res, _$ImageDataImpl>
    implements _$$ImageDataImplCopyWith<$Res> {
  __$$ImageDataImplCopyWithImpl(
      _$ImageDataImpl _value, $Res Function(_$ImageDataImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? imageData = null,
    Object? imageType = null,
    Object? fileName = freezed,
    Object? fileSize = freezed,
  }) {
    return _then(_$ImageDataImpl(
      imageData: null == imageData
          ? _value.imageData
          : imageData // ignore: cast_nullable_to_non_nullable
              as String,
      imageType: null == imageType
          ? _value.imageType
          : imageType // ignore: cast_nullable_to_non_nullable
              as String,
      fileName: freezed == fileName
          ? _value.fileName
          : fileName // ignore: cast_nullable_to_non_nullable
              as String?,
      fileSize: freezed == fileSize
          ? _value.fileSize
          : fileSize // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ImageDataImpl with DiagnosticableTreeMixin implements _ImageData {
  const _$ImageDataImpl(
      {@JsonKey(name: 'image_data') required this.imageData,
      @JsonKey(name: 'image_type') required this.imageType,
      @JsonKey(name: 'file_name') this.fileName,
      @JsonKey(name: 'file_size') this.fileSize});

  factory _$ImageDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ImageDataImplFromJson(json);

  @override
  @JsonKey(name: 'image_data')
  final String imageData;
// Base64 encoded
  @override
  @JsonKey(name: 'image_type')
  final String imageType;
// png, jpg, jpeg
  @override
  @JsonKey(name: 'file_name')
  final String? fileName;
  @override
  @JsonKey(name: 'file_size')
  final int? fileSize;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'ImageData(imageData: $imageData, imageType: $imageType, fileName: $fileName, fileSize: $fileSize)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'ImageData'))
      ..add(DiagnosticsProperty('imageData', imageData))
      ..add(DiagnosticsProperty('imageType', imageType))
      ..add(DiagnosticsProperty('fileName', fileName))
      ..add(DiagnosticsProperty('fileSize', fileSize));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImageDataImpl &&
            (identical(other.imageData, imageData) ||
                other.imageData == imageData) &&
            (identical(other.imageType, imageType) ||
                other.imageType == imageType) &&
            (identical(other.fileName, fileName) ||
                other.fileName == fileName) &&
            (identical(other.fileSize, fileSize) ||
                other.fileSize == fileSize));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, imageData, imageType, fileName, fileSize);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ImageDataImplCopyWith<_$ImageDataImpl> get copyWith =>
      __$$ImageDataImplCopyWithImpl<_$ImageDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ImageDataImplToJson(
      this,
    );
  }
}

abstract class _ImageData implements ImageData {
  const factory _ImageData(
      {@JsonKey(name: 'image_data') required final String imageData,
      @JsonKey(name: 'image_type') required final String imageType,
      @JsonKey(name: 'file_name') final String? fileName,
      @JsonKey(name: 'file_size') final int? fileSize}) = _$ImageDataImpl;

  factory _ImageData.fromJson(Map<String, dynamic> json) =
      _$ImageDataImpl.fromJson;

  @override
  @JsonKey(name: 'image_data')
  String get imageData;
  @override // Base64 encoded
  @JsonKey(name: 'image_type')
  String get imageType;
  @override // png, jpg, jpeg
  @JsonKey(name: 'file_name')
  String? get fileName;
  @override
  @JsonKey(name: 'file_size')
  int? get fileSize;
  @override
  @JsonKey(ignore: true)
  _$$ImageDataImplCopyWith<_$ImageDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

CreateBatchOCRRequest _$CreateBatchOCRRequestFromJson(
    Map<String, dynamic> json) {
  return _CreateBatchOCRRequest.fromJson(json);
}

/// @nodoc
mixin _$CreateBatchOCRRequest {
  List<ImageData> get images => throw _privateConstructorUsedError;
  @JsonKey(name: 'shop_id')
  String get shopId => throw _privateConstructorUsedError;
  String get sessionType => throw _privateConstructorUsedError;
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CreateBatchOCRRequestCopyWith<CreateBatchOCRRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CreateBatchOCRRequestCopyWith<$Res> {
  factory $CreateBatchOCRRequestCopyWith(CreateBatchOCRRequest value,
          $Res Function(CreateBatchOCRRequest) then) =
      _$CreateBatchOCRRequestCopyWithImpl<$Res, CreateBatchOCRRequest>;
  @useResult
  $Res call(
      {List<ImageData> images,
      @JsonKey(name: 'shop_id') String shopId,
      String sessionType,
      Map<String, dynamic>? metadata});
}

/// @nodoc
class _$CreateBatchOCRRequestCopyWithImpl<$Res,
        $Val extends CreateBatchOCRRequest>
    implements $CreateBatchOCRRequestCopyWith<$Res> {
  _$CreateBatchOCRRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? images = null,
    Object? shopId = null,
    Object? sessionType = null,
    Object? metadata = freezed,
  }) {
    return _then(_value.copyWith(
      images: null == images
          ? _value.images
          : images // ignore: cast_nullable_to_non_nullable
              as List<ImageData>,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      metadata: freezed == metadata
          ? _value.metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CreateBatchOCRRequestImplCopyWith<$Res>
    implements $CreateBatchOCRRequestCopyWith<$Res> {
  factory _$$CreateBatchOCRRequestImplCopyWith(
          _$CreateBatchOCRRequestImpl value,
          $Res Function(_$CreateBatchOCRRequestImpl) then) =
      __$$CreateBatchOCRRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<ImageData> images,
      @JsonKey(name: 'shop_id') String shopId,
      String sessionType,
      Map<String, dynamic>? metadata});
}

/// @nodoc
class __$$CreateBatchOCRRequestImplCopyWithImpl<$Res>
    extends _$CreateBatchOCRRequestCopyWithImpl<$Res,
        _$CreateBatchOCRRequestImpl>
    implements _$$CreateBatchOCRRequestImplCopyWith<$Res> {
  __$$CreateBatchOCRRequestImplCopyWithImpl(_$CreateBatchOCRRequestImpl _value,
      $Res Function(_$CreateBatchOCRRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? images = null,
    Object? shopId = null,
    Object? sessionType = null,
    Object? metadata = freezed,
  }) {
    return _then(_$CreateBatchOCRRequestImpl(
      images: null == images
          ? _value._images
          : images // ignore: cast_nullable_to_non_nullable
              as List<ImageData>,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
      sessionType: null == sessionType
          ? _value.sessionType
          : sessionType // ignore: cast_nullable_to_non_nullable
              as String,
      metadata: freezed == metadata
          ? _value._metadata
          : metadata // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CreateBatchOCRRequestImpl
    with DiagnosticableTreeMixin
    implements _CreateBatchOCRRequest {
  const _$CreateBatchOCRRequestImpl(
      {required final List<ImageData> images,
      @JsonKey(name: 'shop_id') required this.shopId,
      this.sessionType = 'stock_initialization',
      final Map<String, dynamic>? metadata})
      : _images = images,
        _metadata = metadata;

  factory _$CreateBatchOCRRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$CreateBatchOCRRequestImplFromJson(json);

  final List<ImageData> _images;
  @override
  List<ImageData> get images {
    if (_images is EqualUnmodifiableListView) return _images;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_images);
  }

  @override
  @JsonKey(name: 'shop_id')
  final String shopId;
  @override
  @JsonKey()
  final String sessionType;
  final Map<String, dynamic>? _metadata;
  @override
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'CreateBatchOCRRequest(images: $images, shopId: $shopId, sessionType: $sessionType, metadata: $metadata)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'CreateBatchOCRRequest'))
      ..add(DiagnosticsProperty('images', images))
      ..add(DiagnosticsProperty('shopId', shopId))
      ..add(DiagnosticsProperty('sessionType', sessionType))
      ..add(DiagnosticsProperty('metadata', metadata));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CreateBatchOCRRequestImpl &&
            const DeepCollectionEquality().equals(other._images, _images) &&
            (identical(other.shopId, shopId) || other.shopId == shopId) &&
            (identical(other.sessionType, sessionType) ||
                other.sessionType == sessionType) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_images),
      shopId,
      sessionType,
      const DeepCollectionEquality().hash(_metadata));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CreateBatchOCRRequestImplCopyWith<_$CreateBatchOCRRequestImpl>
      get copyWith => __$$CreateBatchOCRRequestImplCopyWithImpl<
          _$CreateBatchOCRRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CreateBatchOCRRequestImplToJson(
      this,
    );
  }
}

abstract class _CreateBatchOCRRequest implements CreateBatchOCRRequest {
  const factory _CreateBatchOCRRequest(
      {required final List<ImageData> images,
      @JsonKey(name: 'shop_id') required final String shopId,
      final String sessionType,
      final Map<String, dynamic>? metadata}) = _$CreateBatchOCRRequestImpl;

  factory _CreateBatchOCRRequest.fromJson(Map<String, dynamic> json) =
      _$CreateBatchOCRRequestImpl.fromJson;

  @override
  List<ImageData> get images;
  @override
  @JsonKey(name: 'shop_id')
  String get shopId;
  @override
  String get sessionType;
  @override
  Map<String, dynamic>? get metadata;
  @override
  @JsonKey(ignore: true)
  _$$CreateBatchOCRRequestImplCopyWith<_$CreateBatchOCRRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BatchOCRResponse _$BatchOCRResponseFromJson(Map<String, dynamic> json) {
  return _BatchOCRResponse.fromJson(json);
}

/// @nodoc
mixin _$BatchOCRResponse {
  String get id => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_images')
  int get totalImages => throw _privateConstructorUsedError;
  String get message => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BatchOCRResponseCopyWith<BatchOCRResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BatchOCRResponseCopyWith<$Res> {
  factory $BatchOCRResponseCopyWith(
          BatchOCRResponse value, $Res Function(BatchOCRResponse) then) =
      _$BatchOCRResponseCopyWithImpl<$Res, BatchOCRResponse>;
  @useResult
  $Res call(
      {String id,
      String status,
      @JsonKey(name: 'total_images') int totalImages,
      String message});
}

/// @nodoc
class _$BatchOCRResponseCopyWithImpl<$Res, $Val extends BatchOCRResponse>
    implements $BatchOCRResponseCopyWith<$Res> {
  _$BatchOCRResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? status = null,
    Object? totalImages = null,
    Object? message = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      totalImages: null == totalImages
          ? _value.totalImages
          : totalImages // ignore: cast_nullable_to_non_nullable
              as int,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BatchOCRResponseImplCopyWith<$Res>
    implements $BatchOCRResponseCopyWith<$Res> {
  factory _$$BatchOCRResponseImplCopyWith(_$BatchOCRResponseImpl value,
          $Res Function(_$BatchOCRResponseImpl) then) =
      __$$BatchOCRResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String status,
      @JsonKey(name: 'total_images') int totalImages,
      String message});
}

/// @nodoc
class __$$BatchOCRResponseImplCopyWithImpl<$Res>
    extends _$BatchOCRResponseCopyWithImpl<$Res, _$BatchOCRResponseImpl>
    implements _$$BatchOCRResponseImplCopyWith<$Res> {
  __$$BatchOCRResponseImplCopyWithImpl(_$BatchOCRResponseImpl _value,
      $Res Function(_$BatchOCRResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? status = null,
    Object? totalImages = null,
    Object? message = null,
  }) {
    return _then(_$BatchOCRResponseImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      totalImages: null == totalImages
          ? _value.totalImages
          : totalImages // ignore: cast_nullable_to_non_nullable
              as int,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BatchOCRResponseImpl
    with DiagnosticableTreeMixin
    implements _BatchOCRResponse {
  const _$BatchOCRResponseImpl(
      {required this.id,
      required this.status,
      @JsonKey(name: 'total_images') required this.totalImages,
      required this.message});

  factory _$BatchOCRResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$BatchOCRResponseImplFromJson(json);

  @override
  final String id;
  @override
  final String status;
  @override
  @JsonKey(name: 'total_images')
  final int totalImages;
  @override
  final String message;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'BatchOCRResponse(id: $id, status: $status, totalImages: $totalImages, message: $message)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'BatchOCRResponse'))
      ..add(DiagnosticsProperty('id', id))
      ..add(DiagnosticsProperty('status', status))
      ..add(DiagnosticsProperty('totalImages', totalImages))
      ..add(DiagnosticsProperty('message', message));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BatchOCRResponseImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.totalImages, totalImages) ||
                other.totalImages == totalImages) &&
            (identical(other.message, message) || other.message == message));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, status, totalImages, message);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BatchOCRResponseImplCopyWith<_$BatchOCRResponseImpl> get copyWith =>
      __$$BatchOCRResponseImplCopyWithImpl<_$BatchOCRResponseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BatchOCRResponseImplToJson(
      this,
    );
  }
}

abstract class _BatchOCRResponse implements BatchOCRResponse {
  const factory _BatchOCRResponse(
      {required final String id,
      required final String status,
      @JsonKey(name: 'total_images') required final int totalImages,
      required final String message}) = _$BatchOCRResponseImpl;

  factory _BatchOCRResponse.fromJson(Map<String, dynamic> json) =
      _$BatchOCRResponseImpl.fromJson;

  @override
  String get id;
  @override
  String get status;
  @override
  @JsonKey(name: 'total_images')
  int get totalImages;
  @override
  String get message;
  @override
  @JsonKey(ignore: true)
  _$$BatchOCRResponseImplCopyWith<_$BatchOCRResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DeduplicatedItem _$DeduplicatedItemFromJson(Map<String, dynamic> json) {
  return _DeduplicatedItem.fromJson(json);
}

/// @nodoc
mixin _$DeduplicatedItem {
  @JsonKey(name: 'brand_text')
  String get brandText => throw _privateConstructorUsedError;
  @JsonKey(name: 'size_text')
  String get sizeText =>
      throw _privateConstructorUsedError; // Backend sends 'quantity', map to totalStock
  @JsonKey(name: 'quantity')
  int get totalStock =>
      throw _privateConstructorUsedError; // Backend sends 'match_confidence' - map to matchConfidence (removed averageConfidence duplicate)
  @JsonKey(name: 'source_sessions')
  List<String> get sourceSessionIds => throw _privateConstructorUsedError;
  @JsonKey(name: 'source_items')
  List<String> get sourceItemIds => throw _privateConstructorUsedError;
  @JsonKey(name: 'category_id')
  String? get categoryId => throw _privateConstructorUsedError;
  @JsonKey(name: 'subcategory_id')
  String? get subcategoryId =>
      throw _privateConstructorUsedError; // Category inference fields from backend OCR
  @JsonKey(name: 'inferred_category_name')
  String? get inferredCategoryName => throw _privateConstructorUsedError;
  @JsonKey(name: 'category_confidence')
  double? get categoryConfidence => throw _privateConstructorUsedError;
  @JsonKey(name: 'inferred_subcategory_name')
  String? get inferredSubcategoryName => throw _privateConstructorUsedError;
  @JsonKey(name: 'matched_brand_id')
  String? get matchedBrandId => throw _privateConstructorUsedError;
  @JsonKey(name: 'matched_variant_id')
  String? get matchedVariantId =>
      throw _privateConstructorUsedError; // This maps to backend's match_confidence field (for brand matching)
  @JsonKey(name: 'match_confidence')
  double get matchConfidence =>
      throw _privateConstructorUsedError; // OCR extraction confidence (for text recognition quality)
  @JsonKey(name: 'confidence')
  double? get confidence => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_duplicate')
  bool get isDuplicate => throw _privateConstructorUsedError;
  @JsonKey(name: 'row_number')
  int? get rowNumber => throw _privateConstructorUsedError;
  @JsonKey(name: 'selling_price')
  double? get sellingPrice =>
      throw _privateConstructorUsedError; // Additional fields from backend
  @JsonKey(name: 'id')
  String? get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_id')
  String? get sessionId => throw _privateConstructorUsedError;
  @JsonKey(name: 'batch_id')
  String? get batchId => throw _privateConstructorUsedError;
  @JsonKey(name: 'normalized_brand_name')
  String? get normalizedBrandName => throw _privateConstructorUsedError;
  @JsonKey(name: 'match_strategy')
  String? get matchStrategy => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_reviewed')
  bool get isReviewed => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_selected')
  bool get isSelected => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeduplicatedItemCopyWith<DeduplicatedItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeduplicatedItemCopyWith<$Res> {
  factory $DeduplicatedItemCopyWith(
          DeduplicatedItem value, $Res Function(DeduplicatedItem) then) =
      _$DeduplicatedItemCopyWithImpl<$Res, DeduplicatedItem>;
  @useResult
  $Res call(
      {@JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String sizeText,
      @JsonKey(name: 'quantity') int totalStock,
      @JsonKey(name: 'source_sessions') List<String> sourceSessionIds,
      @JsonKey(name: 'source_items') List<String> sourceItemIds,
      @JsonKey(name: 'category_id') String? categoryId,
      @JsonKey(name: 'subcategory_id') String? subcategoryId,
      @JsonKey(name: 'inferred_category_name') String? inferredCategoryName,
      @JsonKey(name: 'category_confidence') double? categoryConfidence,
      @JsonKey(name: 'inferred_subcategory_name')
      String? inferredSubcategoryName,
      @JsonKey(name: 'matched_brand_id') String? matchedBrandId,
      @JsonKey(name: 'matched_variant_id') String? matchedVariantId,
      @JsonKey(name: 'match_confidence') double matchConfidence,
      @JsonKey(name: 'confidence') double? confidence,
      @JsonKey(name: 'is_duplicate') bool isDuplicate,
      @JsonKey(name: 'row_number') int? rowNumber,
      @JsonKey(name: 'selling_price') double? sellingPrice,
      @JsonKey(name: 'id') String? id,
      @JsonKey(name: 'session_id') String? sessionId,
      @JsonKey(name: 'batch_id') String? batchId,
      @JsonKey(name: 'normalized_brand_name') String? normalizedBrandName,
      @JsonKey(name: 'match_strategy') String? matchStrategy,
      @JsonKey(name: 'is_reviewed') bool isReviewed,
      @JsonKey(name: 'is_selected') bool isSelected});
}

/// @nodoc
class _$DeduplicatedItemCopyWithImpl<$Res, $Val extends DeduplicatedItem>
    implements $DeduplicatedItemCopyWith<$Res> {
  _$DeduplicatedItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? brandText = null,
    Object? sizeText = null,
    Object? totalStock = null,
    Object? sourceSessionIds = null,
    Object? sourceItemIds = null,
    Object? categoryId = freezed,
    Object? subcategoryId = freezed,
    Object? inferredCategoryName = freezed,
    Object? categoryConfidence = freezed,
    Object? inferredSubcategoryName = freezed,
    Object? matchedBrandId = freezed,
    Object? matchedVariantId = freezed,
    Object? matchConfidence = null,
    Object? confidence = freezed,
    Object? isDuplicate = null,
    Object? rowNumber = freezed,
    Object? sellingPrice = freezed,
    Object? id = freezed,
    Object? sessionId = freezed,
    Object? batchId = freezed,
    Object? normalizedBrandName = freezed,
    Object? matchStrategy = freezed,
    Object? isReviewed = null,
    Object? isSelected = null,
  }) {
    return _then(_value.copyWith(
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: null == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String,
      totalStock: null == totalStock
          ? _value.totalStock
          : totalStock // ignore: cast_nullable_to_non_nullable
              as int,
      sourceSessionIds: null == sourceSessionIds
          ? _value.sourceSessionIds
          : sourceSessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      sourceItemIds: null == sourceItemIds
          ? _value.sourceItemIds
          : sourceItemIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      categoryId: freezed == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      inferredCategoryName: freezed == inferredCategoryName
          ? _value.inferredCategoryName
          : inferredCategoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      categoryConfidence: freezed == categoryConfidence
          ? _value.categoryConfidence
          : categoryConfidence // ignore: cast_nullable_to_non_nullable
              as double?,
      inferredSubcategoryName: freezed == inferredSubcategoryName
          ? _value.inferredSubcategoryName
          : inferredSubcategoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      matchedBrandId: freezed == matchedBrandId
          ? _value.matchedBrandId
          : matchedBrandId // ignore: cast_nullable_to_non_nullable
              as String?,
      matchedVariantId: freezed == matchedVariantId
          ? _value.matchedVariantId
          : matchedVariantId // ignore: cast_nullable_to_non_nullable
              as String?,
      matchConfidence: null == matchConfidence
          ? _value.matchConfidence
          : matchConfidence // ignore: cast_nullable_to_non_nullable
              as double,
      confidence: freezed == confidence
          ? _value.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double?,
      isDuplicate: null == isDuplicate
          ? _value.isDuplicate
          : isDuplicate // ignore: cast_nullable_to_non_nullable
              as bool,
      rowNumber: freezed == rowNumber
          ? _value.rowNumber
          : rowNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      sellingPrice: freezed == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      batchId: freezed == batchId
          ? _value.batchId
          : batchId // ignore: cast_nullable_to_non_nullable
              as String?,
      normalizedBrandName: freezed == normalizedBrandName
          ? _value.normalizedBrandName
          : normalizedBrandName // ignore: cast_nullable_to_non_nullable
              as String?,
      matchStrategy: freezed == matchStrategy
          ? _value.matchStrategy
          : matchStrategy // ignore: cast_nullable_to_non_nullable
              as String?,
      isReviewed: null == isReviewed
          ? _value.isReviewed
          : isReviewed // ignore: cast_nullable_to_non_nullable
              as bool,
      isSelected: null == isSelected
          ? _value.isSelected
          : isSelected // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeduplicatedItemImplCopyWith<$Res>
    implements $DeduplicatedItemCopyWith<$Res> {
  factory _$$DeduplicatedItemImplCopyWith(_$DeduplicatedItemImpl value,
          $Res Function(_$DeduplicatedItemImpl) then) =
      __$$DeduplicatedItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String sizeText,
      @JsonKey(name: 'quantity') int totalStock,
      @JsonKey(name: 'source_sessions') List<String> sourceSessionIds,
      @JsonKey(name: 'source_items') List<String> sourceItemIds,
      @JsonKey(name: 'category_id') String? categoryId,
      @JsonKey(name: 'subcategory_id') String? subcategoryId,
      @JsonKey(name: 'inferred_category_name') String? inferredCategoryName,
      @JsonKey(name: 'category_confidence') double? categoryConfidence,
      @JsonKey(name: 'inferred_subcategory_name')
      String? inferredSubcategoryName,
      @JsonKey(name: 'matched_brand_id') String? matchedBrandId,
      @JsonKey(name: 'matched_variant_id') String? matchedVariantId,
      @JsonKey(name: 'match_confidence') double matchConfidence,
      @JsonKey(name: 'confidence') double? confidence,
      @JsonKey(name: 'is_duplicate') bool isDuplicate,
      @JsonKey(name: 'row_number') int? rowNumber,
      @JsonKey(name: 'selling_price') double? sellingPrice,
      @JsonKey(name: 'id') String? id,
      @JsonKey(name: 'session_id') String? sessionId,
      @JsonKey(name: 'batch_id') String? batchId,
      @JsonKey(name: 'normalized_brand_name') String? normalizedBrandName,
      @JsonKey(name: 'match_strategy') String? matchStrategy,
      @JsonKey(name: 'is_reviewed') bool isReviewed,
      @JsonKey(name: 'is_selected') bool isSelected});
}

/// @nodoc
class __$$DeduplicatedItemImplCopyWithImpl<$Res>
    extends _$DeduplicatedItemCopyWithImpl<$Res, _$DeduplicatedItemImpl>
    implements _$$DeduplicatedItemImplCopyWith<$Res> {
  __$$DeduplicatedItemImplCopyWithImpl(_$DeduplicatedItemImpl _value,
      $Res Function(_$DeduplicatedItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? brandText = null,
    Object? sizeText = null,
    Object? totalStock = null,
    Object? sourceSessionIds = null,
    Object? sourceItemIds = null,
    Object? categoryId = freezed,
    Object? subcategoryId = freezed,
    Object? inferredCategoryName = freezed,
    Object? categoryConfidence = freezed,
    Object? inferredSubcategoryName = freezed,
    Object? matchedBrandId = freezed,
    Object? matchedVariantId = freezed,
    Object? matchConfidence = null,
    Object? confidence = freezed,
    Object? isDuplicate = null,
    Object? rowNumber = freezed,
    Object? sellingPrice = freezed,
    Object? id = freezed,
    Object? sessionId = freezed,
    Object? batchId = freezed,
    Object? normalizedBrandName = freezed,
    Object? matchStrategy = freezed,
    Object? isReviewed = null,
    Object? isSelected = null,
  }) {
    return _then(_$DeduplicatedItemImpl(
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: null == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String,
      totalStock: null == totalStock
          ? _value.totalStock
          : totalStock // ignore: cast_nullable_to_non_nullable
              as int,
      sourceSessionIds: null == sourceSessionIds
          ? _value._sourceSessionIds
          : sourceSessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      sourceItemIds: null == sourceItemIds
          ? _value._sourceItemIds
          : sourceItemIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      categoryId: freezed == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      inferredCategoryName: freezed == inferredCategoryName
          ? _value.inferredCategoryName
          : inferredCategoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      categoryConfidence: freezed == categoryConfidence
          ? _value.categoryConfidence
          : categoryConfidence // ignore: cast_nullable_to_non_nullable
              as double?,
      inferredSubcategoryName: freezed == inferredSubcategoryName
          ? _value.inferredSubcategoryName
          : inferredSubcategoryName // ignore: cast_nullable_to_non_nullable
              as String?,
      matchedBrandId: freezed == matchedBrandId
          ? _value.matchedBrandId
          : matchedBrandId // ignore: cast_nullable_to_non_nullable
              as String?,
      matchedVariantId: freezed == matchedVariantId
          ? _value.matchedVariantId
          : matchedVariantId // ignore: cast_nullable_to_non_nullable
              as String?,
      matchConfidence: null == matchConfidence
          ? _value.matchConfidence
          : matchConfidence // ignore: cast_nullable_to_non_nullable
              as double,
      confidence: freezed == confidence
          ? _value.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double?,
      isDuplicate: null == isDuplicate
          ? _value.isDuplicate
          : isDuplicate // ignore: cast_nullable_to_non_nullable
              as bool,
      rowNumber: freezed == rowNumber
          ? _value.rowNumber
          : rowNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      sellingPrice: freezed == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      batchId: freezed == batchId
          ? _value.batchId
          : batchId // ignore: cast_nullable_to_non_nullable
              as String?,
      normalizedBrandName: freezed == normalizedBrandName
          ? _value.normalizedBrandName
          : normalizedBrandName // ignore: cast_nullable_to_non_nullable
              as String?,
      matchStrategy: freezed == matchStrategy
          ? _value.matchStrategy
          : matchStrategy // ignore: cast_nullable_to_non_nullable
              as String?,
      isReviewed: null == isReviewed
          ? _value.isReviewed
          : isReviewed // ignore: cast_nullable_to_non_nullable
              as bool,
      isSelected: null == isSelected
          ? _value.isSelected
          : isSelected // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeduplicatedItemImpl
    with DiagnosticableTreeMixin
    implements _DeduplicatedItem {
  const _$DeduplicatedItemImpl(
      {@JsonKey(name: 'brand_text') this.brandText = '',
      @JsonKey(name: 'size_text') this.sizeText = '',
      @JsonKey(name: 'quantity') this.totalStock = 0,
      @JsonKey(name: 'source_sessions')
      final List<String> sourceSessionIds = const [],
      @JsonKey(name: 'source_items')
      final List<String> sourceItemIds = const [],
      @JsonKey(name: 'category_id') this.categoryId,
      @JsonKey(name: 'subcategory_id') this.subcategoryId,
      @JsonKey(name: 'inferred_category_name') this.inferredCategoryName,
      @JsonKey(name: 'category_confidence') this.categoryConfidence,
      @JsonKey(name: 'inferred_subcategory_name') this.inferredSubcategoryName,
      @JsonKey(name: 'matched_brand_id') this.matchedBrandId,
      @JsonKey(name: 'matched_variant_id') this.matchedVariantId,
      @JsonKey(name: 'match_confidence') this.matchConfidence = 0.0,
      @JsonKey(name: 'confidence') this.confidence,
      @JsonKey(name: 'is_duplicate') this.isDuplicate = false,
      @JsonKey(name: 'row_number') this.rowNumber,
      @JsonKey(name: 'selling_price') this.sellingPrice,
      @JsonKey(name: 'id') this.id,
      @JsonKey(name: 'session_id') this.sessionId,
      @JsonKey(name: 'batch_id') this.batchId,
      @JsonKey(name: 'normalized_brand_name') this.normalizedBrandName,
      @JsonKey(name: 'match_strategy') this.matchStrategy,
      @JsonKey(name: 'is_reviewed') this.isReviewed = false,
      @JsonKey(name: 'is_selected') this.isSelected = true})
      : _sourceSessionIds = sourceSessionIds,
        _sourceItemIds = sourceItemIds;

  factory _$DeduplicatedItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeduplicatedItemImplFromJson(json);

  @override
  @JsonKey(name: 'brand_text')
  final String brandText;
  @override
  @JsonKey(name: 'size_text')
  final String sizeText;
// Backend sends 'quantity', map to totalStock
  @override
  @JsonKey(name: 'quantity')
  final int totalStock;
// Backend sends 'match_confidence' - map to matchConfidence (removed averageConfidence duplicate)
  final List<String> _sourceSessionIds;
// Backend sends 'match_confidence' - map to matchConfidence (removed averageConfidence duplicate)
  @override
  @JsonKey(name: 'source_sessions')
  List<String> get sourceSessionIds {
    if (_sourceSessionIds is EqualUnmodifiableListView)
      return _sourceSessionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sourceSessionIds);
  }

  final List<String> _sourceItemIds;
  @override
  @JsonKey(name: 'source_items')
  List<String> get sourceItemIds {
    if (_sourceItemIds is EqualUnmodifiableListView) return _sourceItemIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sourceItemIds);
  }

  @override
  @JsonKey(name: 'category_id')
  final String? categoryId;
  @override
  @JsonKey(name: 'subcategory_id')
  final String? subcategoryId;
// Category inference fields from backend OCR
  @override
  @JsonKey(name: 'inferred_category_name')
  final String? inferredCategoryName;
  @override
  @JsonKey(name: 'category_confidence')
  final double? categoryConfidence;
  @override
  @JsonKey(name: 'inferred_subcategory_name')
  final String? inferredSubcategoryName;
  @override
  @JsonKey(name: 'matched_brand_id')
  final String? matchedBrandId;
  @override
  @JsonKey(name: 'matched_variant_id')
  final String? matchedVariantId;
// This maps to backend's match_confidence field (for brand matching)
  @override
  @JsonKey(name: 'match_confidence')
  final double matchConfidence;
// OCR extraction confidence (for text recognition quality)
  @override
  @JsonKey(name: 'confidence')
  final double? confidence;
  @override
  @JsonKey(name: 'is_duplicate')
  final bool isDuplicate;
  @override
  @JsonKey(name: 'row_number')
  final int? rowNumber;
  @override
  @JsonKey(name: 'selling_price')
  final double? sellingPrice;
// Additional fields from backend
  @override
  @JsonKey(name: 'id')
  final String? id;
  @override
  @JsonKey(name: 'session_id')
  final String? sessionId;
  @override
  @JsonKey(name: 'batch_id')
  final String? batchId;
  @override
  @JsonKey(name: 'normalized_brand_name')
  final String? normalizedBrandName;
  @override
  @JsonKey(name: 'match_strategy')
  final String? matchStrategy;
  @override
  @JsonKey(name: 'is_reviewed')
  final bool isReviewed;
  @override
  @JsonKey(name: 'is_selected')
  final bool isSelected;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'DeduplicatedItem(brandText: $brandText, sizeText: $sizeText, totalStock: $totalStock, sourceSessionIds: $sourceSessionIds, sourceItemIds: $sourceItemIds, categoryId: $categoryId, subcategoryId: $subcategoryId, inferredCategoryName: $inferredCategoryName, categoryConfidence: $categoryConfidence, inferredSubcategoryName: $inferredSubcategoryName, matchedBrandId: $matchedBrandId, matchedVariantId: $matchedVariantId, matchConfidence: $matchConfidence, confidence: $confidence, isDuplicate: $isDuplicate, rowNumber: $rowNumber, sellingPrice: $sellingPrice, id: $id, sessionId: $sessionId, batchId: $batchId, normalizedBrandName: $normalizedBrandName, matchStrategy: $matchStrategy, isReviewed: $isReviewed, isSelected: $isSelected)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'DeduplicatedItem'))
      ..add(DiagnosticsProperty('brandText', brandText))
      ..add(DiagnosticsProperty('sizeText', sizeText))
      ..add(DiagnosticsProperty('totalStock', totalStock))
      ..add(DiagnosticsProperty('sourceSessionIds', sourceSessionIds))
      ..add(DiagnosticsProperty('sourceItemIds', sourceItemIds))
      ..add(DiagnosticsProperty('categoryId', categoryId))
      ..add(DiagnosticsProperty('subcategoryId', subcategoryId))
      ..add(DiagnosticsProperty('inferredCategoryName', inferredCategoryName))
      ..add(DiagnosticsProperty('categoryConfidence', categoryConfidence))
      ..add(DiagnosticsProperty(
          'inferredSubcategoryName', inferredSubcategoryName))
      ..add(DiagnosticsProperty('matchedBrandId', matchedBrandId))
      ..add(DiagnosticsProperty('matchedVariantId', matchedVariantId))
      ..add(DiagnosticsProperty('matchConfidence', matchConfidence))
      ..add(DiagnosticsProperty('confidence', confidence))
      ..add(DiagnosticsProperty('isDuplicate', isDuplicate))
      ..add(DiagnosticsProperty('rowNumber', rowNumber))
      ..add(DiagnosticsProperty('sellingPrice', sellingPrice))
      ..add(DiagnosticsProperty('id', id))
      ..add(DiagnosticsProperty('sessionId', sessionId))
      ..add(DiagnosticsProperty('batchId', batchId))
      ..add(DiagnosticsProperty('normalizedBrandName', normalizedBrandName))
      ..add(DiagnosticsProperty('matchStrategy', matchStrategy))
      ..add(DiagnosticsProperty('isReviewed', isReviewed))
      ..add(DiagnosticsProperty('isSelected', isSelected));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeduplicatedItemImpl &&
            (identical(other.brandText, brandText) ||
                other.brandText == brandText) &&
            (identical(other.sizeText, sizeText) ||
                other.sizeText == sizeText) &&
            (identical(other.totalStock, totalStock) ||
                other.totalStock == totalStock) &&
            const DeepCollectionEquality()
                .equals(other._sourceSessionIds, _sourceSessionIds) &&
            const DeepCollectionEquality()
                .equals(other._sourceItemIds, _sourceItemIds) &&
            (identical(other.categoryId, categoryId) ||
                other.categoryId == categoryId) &&
            (identical(other.subcategoryId, subcategoryId) ||
                other.subcategoryId == subcategoryId) &&
            (identical(other.inferredCategoryName, inferredCategoryName) ||
                other.inferredCategoryName == inferredCategoryName) &&
            (identical(other.categoryConfidence, categoryConfidence) ||
                other.categoryConfidence == categoryConfidence) &&
            (identical(
                    other.inferredSubcategoryName, inferredSubcategoryName) ||
                other.inferredSubcategoryName == inferredSubcategoryName) &&
            (identical(other.matchedBrandId, matchedBrandId) ||
                other.matchedBrandId == matchedBrandId) &&
            (identical(other.matchedVariantId, matchedVariantId) ||
                other.matchedVariantId == matchedVariantId) &&
            (identical(other.matchConfidence, matchConfidence) ||
                other.matchConfidence == matchConfidence) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            (identical(other.isDuplicate, isDuplicate) ||
                other.isDuplicate == isDuplicate) &&
            (identical(other.rowNumber, rowNumber) ||
                other.rowNumber == rowNumber) &&
            (identical(other.sellingPrice, sellingPrice) ||
                other.sellingPrice == sellingPrice) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.batchId, batchId) || other.batchId == batchId) &&
            (identical(other.normalizedBrandName, normalizedBrandName) ||
                other.normalizedBrandName == normalizedBrandName) &&
            (identical(other.matchStrategy, matchStrategy) ||
                other.matchStrategy == matchStrategy) &&
            (identical(other.isReviewed, isReviewed) ||
                other.isReviewed == isReviewed) &&
            (identical(other.isSelected, isSelected) ||
                other.isSelected == isSelected));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        brandText,
        sizeText,
        totalStock,
        const DeepCollectionEquality().hash(_sourceSessionIds),
        const DeepCollectionEquality().hash(_sourceItemIds),
        categoryId,
        subcategoryId,
        inferredCategoryName,
        categoryConfidence,
        inferredSubcategoryName,
        matchedBrandId,
        matchedVariantId,
        matchConfidence,
        confidence,
        isDuplicate,
        rowNumber,
        sellingPrice,
        id,
        sessionId,
        batchId,
        normalizedBrandName,
        matchStrategy,
        isReviewed,
        isSelected
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeduplicatedItemImplCopyWith<_$DeduplicatedItemImpl> get copyWith =>
      __$$DeduplicatedItemImplCopyWithImpl<_$DeduplicatedItemImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeduplicatedItemImplToJson(
      this,
    );
  }
}

abstract class _DeduplicatedItem implements DeduplicatedItem {
  const factory _DeduplicatedItem(
      {@JsonKey(name: 'brand_text') final String brandText,
      @JsonKey(name: 'size_text') final String sizeText,
      @JsonKey(name: 'quantity') final int totalStock,
      @JsonKey(name: 'source_sessions') final List<String> sourceSessionIds,
      @JsonKey(name: 'source_items') final List<String> sourceItemIds,
      @JsonKey(name: 'category_id') final String? categoryId,
      @JsonKey(name: 'subcategory_id') final String? subcategoryId,
      @JsonKey(name: 'inferred_category_name')
      final String? inferredCategoryName,
      @JsonKey(name: 'category_confidence') final double? categoryConfidence,
      @JsonKey(name: 'inferred_subcategory_name')
      final String? inferredSubcategoryName,
      @JsonKey(name: 'matched_brand_id') final String? matchedBrandId,
      @JsonKey(name: 'matched_variant_id') final String? matchedVariantId,
      @JsonKey(name: 'match_confidence') final double matchConfidence,
      @JsonKey(name: 'confidence') final double? confidence,
      @JsonKey(name: 'is_duplicate') final bool isDuplicate,
      @JsonKey(name: 'row_number') final int? rowNumber,
      @JsonKey(name: 'selling_price') final double? sellingPrice,
      @JsonKey(name: 'id') final String? id,
      @JsonKey(name: 'session_id') final String? sessionId,
      @JsonKey(name: 'batch_id') final String? batchId,
      @JsonKey(name: 'normalized_brand_name') final String? normalizedBrandName,
      @JsonKey(name: 'match_strategy') final String? matchStrategy,
      @JsonKey(name: 'is_reviewed') final bool isReviewed,
      @JsonKey(name: 'is_selected')
      final bool isSelected}) = _$DeduplicatedItemImpl;

  factory _DeduplicatedItem.fromJson(Map<String, dynamic> json) =
      _$DeduplicatedItemImpl.fromJson;

  @override
  @JsonKey(name: 'brand_text')
  String get brandText;
  @override
  @JsonKey(name: 'size_text')
  String get sizeText;
  @override // Backend sends 'quantity', map to totalStock
  @JsonKey(name: 'quantity')
  int get totalStock;
  @override // Backend sends 'match_confidence' - map to matchConfidence (removed averageConfidence duplicate)
  @JsonKey(name: 'source_sessions')
  List<String> get sourceSessionIds;
  @override
  @JsonKey(name: 'source_items')
  List<String> get sourceItemIds;
  @override
  @JsonKey(name: 'category_id')
  String? get categoryId;
  @override
  @JsonKey(name: 'subcategory_id')
  String? get subcategoryId;
  @override // Category inference fields from backend OCR
  @JsonKey(name: 'inferred_category_name')
  String? get inferredCategoryName;
  @override
  @JsonKey(name: 'category_confidence')
  double? get categoryConfidence;
  @override
  @JsonKey(name: 'inferred_subcategory_name')
  String? get inferredSubcategoryName;
  @override
  @JsonKey(name: 'matched_brand_id')
  String? get matchedBrandId;
  @override
  @JsonKey(name: 'matched_variant_id')
  String? get matchedVariantId;
  @override // This maps to backend's match_confidence field (for brand matching)
  @JsonKey(name: 'match_confidence')
  double get matchConfidence;
  @override // OCR extraction confidence (for text recognition quality)
  @JsonKey(name: 'confidence')
  double? get confidence;
  @override
  @JsonKey(name: 'is_duplicate')
  bool get isDuplicate;
  @override
  @JsonKey(name: 'row_number')
  int? get rowNumber;
  @override
  @JsonKey(name: 'selling_price')
  double? get sellingPrice;
  @override // Additional fields from backend
  @JsonKey(name: 'id')
  String? get id;
  @override
  @JsonKey(name: 'session_id')
  String? get sessionId;
  @override
  @JsonKey(name: 'batch_id')
  String? get batchId;
  @override
  @JsonKey(name: 'normalized_brand_name')
  String? get normalizedBrandName;
  @override
  @JsonKey(name: 'match_strategy')
  String? get matchStrategy;
  @override
  @JsonKey(name: 'is_reviewed')
  bool get isReviewed;
  @override
  @JsonKey(name: 'is_selected')
  bool get isSelected;
  @override
  @JsonKey(ignore: true)
  _$$DeduplicatedItemImplCopyWith<_$DeduplicatedItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RejectedItem _$RejectedItemFromJson(Map<String, dynamic> json) {
  return _RejectedItem.fromJson(json);
}

/// @nodoc
mixin _$RejectedItem {
  @JsonKey(name: 'brand_text')
  String get brandText => throw _privateConstructorUsedError;
  @JsonKey(name: 'size_text')
  String? get sizeText => throw _privateConstructorUsedError;
  @JsonKey(name: 'quantity')
  int get totalStock => throw _privateConstructorUsedError;
  @JsonKey(name: 'selling_price')
  double? get sellingPrice => throw _privateConstructorUsedError;
  @JsonKey(name: 'rejection_reason')
  String get rejectionReason => throw _privateConstructorUsedError;
  @JsonKey(name: 'rejection_stage')
  String get rejectionStage => throw _privateConstructorUsedError;
  @JsonKey(name: 'can_recover')
  bool get canRecover => throw _privateConstructorUsedError;
  @JsonKey(name: 'confidence')
  double? get confidence => throw _privateConstructorUsedError;
  @JsonKey(name: 'id')
  String? get id => throw _privateConstructorUsedError;
  @JsonKey(name: 'source_session_id')
  String? get sourceSessionId => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $RejectedItemCopyWith<RejectedItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RejectedItemCopyWith<$Res> {
  factory $RejectedItemCopyWith(
          RejectedItem value, $Res Function(RejectedItem) then) =
      _$RejectedItemCopyWithImpl<$Res, RejectedItem>;
  @useResult
  $Res call(
      {@JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String? sizeText,
      @JsonKey(name: 'quantity') int totalStock,
      @JsonKey(name: 'selling_price') double? sellingPrice,
      @JsonKey(name: 'rejection_reason') String rejectionReason,
      @JsonKey(name: 'rejection_stage') String rejectionStage,
      @JsonKey(name: 'can_recover') bool canRecover,
      @JsonKey(name: 'confidence') double? confidence,
      @JsonKey(name: 'id') String? id,
      @JsonKey(name: 'source_session_id') String? sourceSessionId});
}

/// @nodoc
class _$RejectedItemCopyWithImpl<$Res, $Val extends RejectedItem>
    implements $RejectedItemCopyWith<$Res> {
  _$RejectedItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? brandText = null,
    Object? sizeText = freezed,
    Object? totalStock = null,
    Object? sellingPrice = freezed,
    Object? rejectionReason = null,
    Object? rejectionStage = null,
    Object? canRecover = null,
    Object? confidence = freezed,
    Object? id = freezed,
    Object? sourceSessionId = freezed,
  }) {
    return _then(_value.copyWith(
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: freezed == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String?,
      totalStock: null == totalStock
          ? _value.totalStock
          : totalStock // ignore: cast_nullable_to_non_nullable
              as int,
      sellingPrice: freezed == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      rejectionReason: null == rejectionReason
          ? _value.rejectionReason
          : rejectionReason // ignore: cast_nullable_to_non_nullable
              as String,
      rejectionStage: null == rejectionStage
          ? _value.rejectionStage
          : rejectionStage // ignore: cast_nullable_to_non_nullable
              as String,
      canRecover: null == canRecover
          ? _value.canRecover
          : canRecover // ignore: cast_nullable_to_non_nullable
              as bool,
      confidence: freezed == confidence
          ? _value.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double?,
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      sourceSessionId: freezed == sourceSessionId
          ? _value.sourceSessionId
          : sourceSessionId // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RejectedItemImplCopyWith<$Res>
    implements $RejectedItemCopyWith<$Res> {
  factory _$$RejectedItemImplCopyWith(
          _$RejectedItemImpl value, $Res Function(_$RejectedItemImpl) then) =
      __$$RejectedItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String? sizeText,
      @JsonKey(name: 'quantity') int totalStock,
      @JsonKey(name: 'selling_price') double? sellingPrice,
      @JsonKey(name: 'rejection_reason') String rejectionReason,
      @JsonKey(name: 'rejection_stage') String rejectionStage,
      @JsonKey(name: 'can_recover') bool canRecover,
      @JsonKey(name: 'confidence') double? confidence,
      @JsonKey(name: 'id') String? id,
      @JsonKey(name: 'source_session_id') String? sourceSessionId});
}

/// @nodoc
class __$$RejectedItemImplCopyWithImpl<$Res>
    extends _$RejectedItemCopyWithImpl<$Res, _$RejectedItemImpl>
    implements _$$RejectedItemImplCopyWith<$Res> {
  __$$RejectedItemImplCopyWithImpl(
      _$RejectedItemImpl _value, $Res Function(_$RejectedItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? brandText = null,
    Object? sizeText = freezed,
    Object? totalStock = null,
    Object? sellingPrice = freezed,
    Object? rejectionReason = null,
    Object? rejectionStage = null,
    Object? canRecover = null,
    Object? confidence = freezed,
    Object? id = freezed,
    Object? sourceSessionId = freezed,
  }) {
    return _then(_$RejectedItemImpl(
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: freezed == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String?,
      totalStock: null == totalStock
          ? _value.totalStock
          : totalStock // ignore: cast_nullable_to_non_nullable
              as int,
      sellingPrice: freezed == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      rejectionReason: null == rejectionReason
          ? _value.rejectionReason
          : rejectionReason // ignore: cast_nullable_to_non_nullable
              as String,
      rejectionStage: null == rejectionStage
          ? _value.rejectionStage
          : rejectionStage // ignore: cast_nullable_to_non_nullable
              as String,
      canRecover: null == canRecover
          ? _value.canRecover
          : canRecover // ignore: cast_nullable_to_non_nullable
              as bool,
      confidence: freezed == confidence
          ? _value.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double?,
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
      sourceSessionId: freezed == sourceSessionId
          ? _value.sourceSessionId
          : sourceSessionId // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RejectedItemImpl with DiagnosticableTreeMixin implements _RejectedItem {
  const _$RejectedItemImpl(
      {@JsonKey(name: 'brand_text') this.brandText = '',
      @JsonKey(name: 'size_text') this.sizeText,
      @JsonKey(name: 'quantity') this.totalStock = 0,
      @JsonKey(name: 'selling_price') this.sellingPrice,
      @JsonKey(name: 'rejection_reason')
      this.rejectionReason = 'Unknown reason',
      @JsonKey(name: 'rejection_stage') this.rejectionStage = 'validation',
      @JsonKey(name: 'can_recover') this.canRecover = true,
      @JsonKey(name: 'confidence') this.confidence,
      @JsonKey(name: 'id') this.id,
      @JsonKey(name: 'source_session_id') this.sourceSessionId});

  factory _$RejectedItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$RejectedItemImplFromJson(json);

  @override
  @JsonKey(name: 'brand_text')
  final String brandText;
  @override
  @JsonKey(name: 'size_text')
  final String? sizeText;
  @override
  @JsonKey(name: 'quantity')
  final int totalStock;
  @override
  @JsonKey(name: 'selling_price')
  final double? sellingPrice;
  @override
  @JsonKey(name: 'rejection_reason')
  final String rejectionReason;
  @override
  @JsonKey(name: 'rejection_stage')
  final String rejectionStage;
  @override
  @JsonKey(name: 'can_recover')
  final bool canRecover;
  @override
  @JsonKey(name: 'confidence')
  final double? confidence;
  @override
  @JsonKey(name: 'id')
  final String? id;
  @override
  @JsonKey(name: 'source_session_id')
  final String? sourceSessionId;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'RejectedItem(brandText: $brandText, sizeText: $sizeText, totalStock: $totalStock, sellingPrice: $sellingPrice, rejectionReason: $rejectionReason, rejectionStage: $rejectionStage, canRecover: $canRecover, confidence: $confidence, id: $id, sourceSessionId: $sourceSessionId)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'RejectedItem'))
      ..add(DiagnosticsProperty('brandText', brandText))
      ..add(DiagnosticsProperty('sizeText', sizeText))
      ..add(DiagnosticsProperty('totalStock', totalStock))
      ..add(DiagnosticsProperty('sellingPrice', sellingPrice))
      ..add(DiagnosticsProperty('rejectionReason', rejectionReason))
      ..add(DiagnosticsProperty('rejectionStage', rejectionStage))
      ..add(DiagnosticsProperty('canRecover', canRecover))
      ..add(DiagnosticsProperty('confidence', confidence))
      ..add(DiagnosticsProperty('id', id))
      ..add(DiagnosticsProperty('sourceSessionId', sourceSessionId));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RejectedItemImpl &&
            (identical(other.brandText, brandText) ||
                other.brandText == brandText) &&
            (identical(other.sizeText, sizeText) ||
                other.sizeText == sizeText) &&
            (identical(other.totalStock, totalStock) ||
                other.totalStock == totalStock) &&
            (identical(other.sellingPrice, sellingPrice) ||
                other.sellingPrice == sellingPrice) &&
            (identical(other.rejectionReason, rejectionReason) ||
                other.rejectionReason == rejectionReason) &&
            (identical(other.rejectionStage, rejectionStage) ||
                other.rejectionStage == rejectionStage) &&
            (identical(other.canRecover, canRecover) ||
                other.canRecover == canRecover) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sourceSessionId, sourceSessionId) ||
                other.sourceSessionId == sourceSessionId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      brandText,
      sizeText,
      totalStock,
      sellingPrice,
      rejectionReason,
      rejectionStage,
      canRecover,
      confidence,
      id,
      sourceSessionId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$RejectedItemImplCopyWith<_$RejectedItemImpl> get copyWith =>
      __$$RejectedItemImplCopyWithImpl<_$RejectedItemImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RejectedItemImplToJson(
      this,
    );
  }
}

abstract class _RejectedItem implements RejectedItem {
  const factory _RejectedItem(
          {@JsonKey(name: 'brand_text') final String brandText,
          @JsonKey(name: 'size_text') final String? sizeText,
          @JsonKey(name: 'quantity') final int totalStock,
          @JsonKey(name: 'selling_price') final double? sellingPrice,
          @JsonKey(name: 'rejection_reason') final String rejectionReason,
          @JsonKey(name: 'rejection_stage') final String rejectionStage,
          @JsonKey(name: 'can_recover') final bool canRecover,
          @JsonKey(name: 'confidence') final double? confidence,
          @JsonKey(name: 'id') final String? id,
          @JsonKey(name: 'source_session_id') final String? sourceSessionId}) =
      _$RejectedItemImpl;

  factory _RejectedItem.fromJson(Map<String, dynamic> json) =
      _$RejectedItemImpl.fromJson;

  @override
  @JsonKey(name: 'brand_text')
  String get brandText;
  @override
  @JsonKey(name: 'size_text')
  String? get sizeText;
  @override
  @JsonKey(name: 'quantity')
  int get totalStock;
  @override
  @JsonKey(name: 'selling_price')
  double? get sellingPrice;
  @override
  @JsonKey(name: 'rejection_reason')
  String get rejectionReason;
  @override
  @JsonKey(name: 'rejection_stage')
  String get rejectionStage;
  @override
  @JsonKey(name: 'can_recover')
  bool get canRecover;
  @override
  @JsonKey(name: 'confidence')
  double? get confidence;
  @override
  @JsonKey(name: 'id')
  String? get id;
  @override
  @JsonKey(name: 'source_session_id')
  String? get sourceSessionId;
  @override
  @JsonKey(ignore: true)
  _$$RejectedItemImplCopyWith<_$RejectedItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DeduplicateRequest _$DeduplicateRequestFromJson(Map<String, dynamic> json) {
  return _DeduplicateRequest.fromJson(json);
}

/// @nodoc
mixin _$DeduplicateRequest {
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $DeduplicateRequestCopyWith<DeduplicateRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeduplicateRequestCopyWith<$Res> {
  factory $DeduplicateRequestCopyWith(
          DeduplicateRequest value, $Res Function(DeduplicateRequest) then) =
      _$DeduplicateRequestCopyWithImpl<$Res, DeduplicateRequest>;
  @useResult
  $Res call({@JsonKey(name: 'session_ids') List<String> sessionIds});
}

/// @nodoc
class _$DeduplicateRequestCopyWithImpl<$Res, $Val extends DeduplicateRequest>
    implements $DeduplicateRequestCopyWith<$Res> {
  _$DeduplicateRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionIds = null,
  }) {
    return _then(_value.copyWith(
      sessionIds: null == sessionIds
          ? _value.sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DeduplicateRequestImplCopyWith<$Res>
    implements $DeduplicateRequestCopyWith<$Res> {
  factory _$$DeduplicateRequestImplCopyWith(_$DeduplicateRequestImpl value,
          $Res Function(_$DeduplicateRequestImpl) then) =
      __$$DeduplicateRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({@JsonKey(name: 'session_ids') List<String> sessionIds});
}

/// @nodoc
class __$$DeduplicateRequestImplCopyWithImpl<$Res>
    extends _$DeduplicateRequestCopyWithImpl<$Res, _$DeduplicateRequestImpl>
    implements _$$DeduplicateRequestImplCopyWith<$Res> {
  __$$DeduplicateRequestImplCopyWithImpl(_$DeduplicateRequestImpl _value,
      $Res Function(_$DeduplicateRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionIds = null,
  }) {
    return _then(_$DeduplicateRequestImpl(
      sessionIds: null == sessionIds
          ? _value._sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DeduplicateRequestImpl
    with DiagnosticableTreeMixin
    implements _DeduplicateRequest {
  const _$DeduplicateRequestImpl(
      {@JsonKey(name: 'session_ids') required final List<String> sessionIds})
      : _sessionIds = sessionIds;

  factory _$DeduplicateRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$DeduplicateRequestImplFromJson(json);

  final List<String> _sessionIds;
  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds {
    if (_sessionIds is EqualUnmodifiableListView) return _sessionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sessionIds);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'DeduplicateRequest(sessionIds: $sessionIds)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'DeduplicateRequest'))
      ..add(DiagnosticsProperty('sessionIds', sessionIds));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeduplicateRequestImpl &&
            const DeepCollectionEquality()
                .equals(other._sessionIds, _sessionIds));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, const DeepCollectionEquality().hash(_sessionIds));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$DeduplicateRequestImplCopyWith<_$DeduplicateRequestImpl> get copyWith =>
      __$$DeduplicateRequestImplCopyWithImpl<_$DeduplicateRequestImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DeduplicateRequestImplToJson(
      this,
    );
  }
}

abstract class _DeduplicateRequest implements DeduplicateRequest {
  const factory _DeduplicateRequest(
      {@JsonKey(name: 'session_ids')
      required final List<String> sessionIds}) = _$DeduplicateRequestImpl;

  factory _DeduplicateRequest.fromJson(Map<String, dynamic> json) =
      _$DeduplicateRequestImpl.fromJson;

  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds;
  @override
  @JsonKey(ignore: true)
  _$$DeduplicateRequestImplCopyWith<_$DeduplicateRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

EnrichedStockItem _$EnrichedStockItemFromJson(Map<String, dynamic> json) {
  return _EnrichedStockItem.fromJson(json);
}

/// @nodoc
mixin _$EnrichedStockItem {
  @JsonKey(name: 'ocr_item_id')
  String get ocrItemId => throw _privateConstructorUsedError;
  @JsonKey(name: 'brand_text')
  String get brandText => throw _privateConstructorUsedError;
  @JsonKey(name: 'size_text')
  String get sizeText => throw _privateConstructorUsedError;
  @JsonKey(name: 'available_stock')
  int get availableStock => throw _privateConstructorUsedError;
  @JsonKey(name: 'category_id')
  String? get categoryId => throw _privateConstructorUsedError;
  @JsonKey(name: 'subcategory_id')
  String? get subcategoryId => throw _privateConstructorUsedError;
  @JsonKey(name: 'saas_brand_id')
  String? get saasBrandId => throw _privateConstructorUsedError;
  @JsonKey(name: 'brand_variant_id')
  String? get brandVariantId => throw _privateConstructorUsedError;
  @JsonKey(name: 'selling_price')
  double? get sellingPrice => throw _privateConstructorUsedError;
  @JsonKey(name: 'cost_price')
  double? get costPrice => throw _privateConstructorUsedError;
  double? get mrp => throw _privateConstructorUsedError;
  @JsonKey(name: 'reorder_level')
  int? get reorderLevel => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_duplicate')
  bool get isDuplicate => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_confirmed')
  bool get isConfirmed =>
      throw _privateConstructorUsedError; // Enrichment status
  @JsonKey(name: 'enrichment_status')
  EnrichmentStatus get enrichmentStatus => throw _privateConstructorUsedError;
  @JsonKey(name: 'validation_errors')
  List<String>? get validationErrors => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $EnrichedStockItemCopyWith<EnrichedStockItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EnrichedStockItemCopyWith<$Res> {
  factory $EnrichedStockItemCopyWith(
          EnrichedStockItem value, $Res Function(EnrichedStockItem) then) =
      _$EnrichedStockItemCopyWithImpl<$Res, EnrichedStockItem>;
  @useResult
  $Res call(
      {@JsonKey(name: 'ocr_item_id') String ocrItemId,
      @JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String sizeText,
      @JsonKey(name: 'available_stock') int availableStock,
      @JsonKey(name: 'category_id') String? categoryId,
      @JsonKey(name: 'subcategory_id') String? subcategoryId,
      @JsonKey(name: 'saas_brand_id') String? saasBrandId,
      @JsonKey(name: 'brand_variant_id') String? brandVariantId,
      @JsonKey(name: 'selling_price') double? sellingPrice,
      @JsonKey(name: 'cost_price') double? costPrice,
      double? mrp,
      @JsonKey(name: 'reorder_level') int? reorderLevel,
      @JsonKey(name: 'is_duplicate') bool isDuplicate,
      @JsonKey(name: 'is_confirmed') bool isConfirmed,
      @JsonKey(name: 'enrichment_status') EnrichmentStatus enrichmentStatus,
      @JsonKey(name: 'validation_errors') List<String>? validationErrors});
}

/// @nodoc
class _$EnrichedStockItemCopyWithImpl<$Res, $Val extends EnrichedStockItem>
    implements $EnrichedStockItemCopyWith<$Res> {
  _$EnrichedStockItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ocrItemId = null,
    Object? brandText = null,
    Object? sizeText = null,
    Object? availableStock = null,
    Object? categoryId = freezed,
    Object? subcategoryId = freezed,
    Object? saasBrandId = freezed,
    Object? brandVariantId = freezed,
    Object? sellingPrice = freezed,
    Object? costPrice = freezed,
    Object? mrp = freezed,
    Object? reorderLevel = freezed,
    Object? isDuplicate = null,
    Object? isConfirmed = null,
    Object? enrichmentStatus = null,
    Object? validationErrors = freezed,
  }) {
    return _then(_value.copyWith(
      ocrItemId: null == ocrItemId
          ? _value.ocrItemId
          : ocrItemId // ignore: cast_nullable_to_non_nullable
              as String,
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: null == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String,
      availableStock: null == availableStock
          ? _value.availableStock
          : availableStock // ignore: cast_nullable_to_non_nullable
              as int,
      categoryId: freezed == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      saasBrandId: freezed == saasBrandId
          ? _value.saasBrandId
          : saasBrandId // ignore: cast_nullable_to_non_nullable
              as String?,
      brandVariantId: freezed == brandVariantId
          ? _value.brandVariantId
          : brandVariantId // ignore: cast_nullable_to_non_nullable
              as String?,
      sellingPrice: freezed == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      costPrice: freezed == costPrice
          ? _value.costPrice
          : costPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      mrp: freezed == mrp
          ? _value.mrp
          : mrp // ignore: cast_nullable_to_non_nullable
              as double?,
      reorderLevel: freezed == reorderLevel
          ? _value.reorderLevel
          : reorderLevel // ignore: cast_nullable_to_non_nullable
              as int?,
      isDuplicate: null == isDuplicate
          ? _value.isDuplicate
          : isDuplicate // ignore: cast_nullable_to_non_nullable
              as bool,
      isConfirmed: null == isConfirmed
          ? _value.isConfirmed
          : isConfirmed // ignore: cast_nullable_to_non_nullable
              as bool,
      enrichmentStatus: null == enrichmentStatus
          ? _value.enrichmentStatus
          : enrichmentStatus // ignore: cast_nullable_to_non_nullable
              as EnrichmentStatus,
      validationErrors: freezed == validationErrors
          ? _value.validationErrors
          : validationErrors // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EnrichedStockItemImplCopyWith<$Res>
    implements $EnrichedStockItemCopyWith<$Res> {
  factory _$$EnrichedStockItemImplCopyWith(_$EnrichedStockItemImpl value,
          $Res Function(_$EnrichedStockItemImpl) then) =
      __$$EnrichedStockItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'ocr_item_id') String ocrItemId,
      @JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String sizeText,
      @JsonKey(name: 'available_stock') int availableStock,
      @JsonKey(name: 'category_id') String? categoryId,
      @JsonKey(name: 'subcategory_id') String? subcategoryId,
      @JsonKey(name: 'saas_brand_id') String? saasBrandId,
      @JsonKey(name: 'brand_variant_id') String? brandVariantId,
      @JsonKey(name: 'selling_price') double? sellingPrice,
      @JsonKey(name: 'cost_price') double? costPrice,
      double? mrp,
      @JsonKey(name: 'reorder_level') int? reorderLevel,
      @JsonKey(name: 'is_duplicate') bool isDuplicate,
      @JsonKey(name: 'is_confirmed') bool isConfirmed,
      @JsonKey(name: 'enrichment_status') EnrichmentStatus enrichmentStatus,
      @JsonKey(name: 'validation_errors') List<String>? validationErrors});
}

/// @nodoc
class __$$EnrichedStockItemImplCopyWithImpl<$Res>
    extends _$EnrichedStockItemCopyWithImpl<$Res, _$EnrichedStockItemImpl>
    implements _$$EnrichedStockItemImplCopyWith<$Res> {
  __$$EnrichedStockItemImplCopyWithImpl(_$EnrichedStockItemImpl _value,
      $Res Function(_$EnrichedStockItemImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ocrItemId = null,
    Object? brandText = null,
    Object? sizeText = null,
    Object? availableStock = null,
    Object? categoryId = freezed,
    Object? subcategoryId = freezed,
    Object? saasBrandId = freezed,
    Object? brandVariantId = freezed,
    Object? sellingPrice = freezed,
    Object? costPrice = freezed,
    Object? mrp = freezed,
    Object? reorderLevel = freezed,
    Object? isDuplicate = null,
    Object? isConfirmed = null,
    Object? enrichmentStatus = null,
    Object? validationErrors = freezed,
  }) {
    return _then(_$EnrichedStockItemImpl(
      ocrItemId: null == ocrItemId
          ? _value.ocrItemId
          : ocrItemId // ignore: cast_nullable_to_non_nullable
              as String,
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: null == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String,
      availableStock: null == availableStock
          ? _value.availableStock
          : availableStock // ignore: cast_nullable_to_non_nullable
              as int,
      categoryId: freezed == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      saasBrandId: freezed == saasBrandId
          ? _value.saasBrandId
          : saasBrandId // ignore: cast_nullable_to_non_nullable
              as String?,
      brandVariantId: freezed == brandVariantId
          ? _value.brandVariantId
          : brandVariantId // ignore: cast_nullable_to_non_nullable
              as String?,
      sellingPrice: freezed == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      costPrice: freezed == costPrice
          ? _value.costPrice
          : costPrice // ignore: cast_nullable_to_non_nullable
              as double?,
      mrp: freezed == mrp
          ? _value.mrp
          : mrp // ignore: cast_nullable_to_non_nullable
              as double?,
      reorderLevel: freezed == reorderLevel
          ? _value.reorderLevel
          : reorderLevel // ignore: cast_nullable_to_non_nullable
              as int?,
      isDuplicate: null == isDuplicate
          ? _value.isDuplicate
          : isDuplicate // ignore: cast_nullable_to_non_nullable
              as bool,
      isConfirmed: null == isConfirmed
          ? _value.isConfirmed
          : isConfirmed // ignore: cast_nullable_to_non_nullable
              as bool,
      enrichmentStatus: null == enrichmentStatus
          ? _value.enrichmentStatus
          : enrichmentStatus // ignore: cast_nullable_to_non_nullable
              as EnrichmentStatus,
      validationErrors: freezed == validationErrors
          ? _value._validationErrors
          : validationErrors // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EnrichedStockItemImpl extends _EnrichedStockItem
    with DiagnosticableTreeMixin {
  const _$EnrichedStockItemImpl(
      {@JsonKey(name: 'ocr_item_id') required this.ocrItemId,
      @JsonKey(name: 'brand_text') required this.brandText,
      @JsonKey(name: 'size_text') required this.sizeText,
      @JsonKey(name: 'available_stock') required this.availableStock,
      @JsonKey(name: 'category_id') this.categoryId,
      @JsonKey(name: 'subcategory_id') this.subcategoryId,
      @JsonKey(name: 'saas_brand_id') this.saasBrandId,
      @JsonKey(name: 'brand_variant_id') this.brandVariantId,
      @JsonKey(name: 'selling_price') this.sellingPrice,
      @JsonKey(name: 'cost_price') this.costPrice,
      this.mrp,
      @JsonKey(name: 'reorder_level') this.reorderLevel,
      @JsonKey(name: 'is_duplicate') this.isDuplicate = false,
      @JsonKey(name: 'is_confirmed') this.isConfirmed = false,
      @JsonKey(name: 'enrichment_status')
      this.enrichmentStatus = EnrichmentStatus.pending,
      @JsonKey(name: 'validation_errors') final List<String>? validationErrors})
      : _validationErrors = validationErrors,
        super._();

  factory _$EnrichedStockItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$EnrichedStockItemImplFromJson(json);

  @override
  @JsonKey(name: 'ocr_item_id')
  final String ocrItemId;
  @override
  @JsonKey(name: 'brand_text')
  final String brandText;
  @override
  @JsonKey(name: 'size_text')
  final String sizeText;
  @override
  @JsonKey(name: 'available_stock')
  final int availableStock;
  @override
  @JsonKey(name: 'category_id')
  final String? categoryId;
  @override
  @JsonKey(name: 'subcategory_id')
  final String? subcategoryId;
  @override
  @JsonKey(name: 'saas_brand_id')
  final String? saasBrandId;
  @override
  @JsonKey(name: 'brand_variant_id')
  final String? brandVariantId;
  @override
  @JsonKey(name: 'selling_price')
  final double? sellingPrice;
  @override
  @JsonKey(name: 'cost_price')
  final double? costPrice;
  @override
  final double? mrp;
  @override
  @JsonKey(name: 'reorder_level')
  final int? reorderLevel;
  @override
  @JsonKey(name: 'is_duplicate')
  final bool isDuplicate;
  @override
  @JsonKey(name: 'is_confirmed')
  final bool isConfirmed;
// Enrichment status
  @override
  @JsonKey(name: 'enrichment_status')
  final EnrichmentStatus enrichmentStatus;
  final List<String>? _validationErrors;
  @override
  @JsonKey(name: 'validation_errors')
  List<String>? get validationErrors {
    final value = _validationErrors;
    if (value == null) return null;
    if (_validationErrors is EqualUnmodifiableListView)
      return _validationErrors;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'EnrichedStockItem(ocrItemId: $ocrItemId, brandText: $brandText, sizeText: $sizeText, availableStock: $availableStock, categoryId: $categoryId, subcategoryId: $subcategoryId, saasBrandId: $saasBrandId, brandVariantId: $brandVariantId, sellingPrice: $sellingPrice, costPrice: $costPrice, mrp: $mrp, reorderLevel: $reorderLevel, isDuplicate: $isDuplicate, isConfirmed: $isConfirmed, enrichmentStatus: $enrichmentStatus, validationErrors: $validationErrors)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'EnrichedStockItem'))
      ..add(DiagnosticsProperty('ocrItemId', ocrItemId))
      ..add(DiagnosticsProperty('brandText', brandText))
      ..add(DiagnosticsProperty('sizeText', sizeText))
      ..add(DiagnosticsProperty('availableStock', availableStock))
      ..add(DiagnosticsProperty('categoryId', categoryId))
      ..add(DiagnosticsProperty('subcategoryId', subcategoryId))
      ..add(DiagnosticsProperty('saasBrandId', saasBrandId))
      ..add(DiagnosticsProperty('brandVariantId', brandVariantId))
      ..add(DiagnosticsProperty('sellingPrice', sellingPrice))
      ..add(DiagnosticsProperty('costPrice', costPrice))
      ..add(DiagnosticsProperty('mrp', mrp))
      ..add(DiagnosticsProperty('reorderLevel', reorderLevel))
      ..add(DiagnosticsProperty('isDuplicate', isDuplicate))
      ..add(DiagnosticsProperty('isConfirmed', isConfirmed))
      ..add(DiagnosticsProperty('enrichmentStatus', enrichmentStatus))
      ..add(DiagnosticsProperty('validationErrors', validationErrors));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EnrichedStockItemImpl &&
            (identical(other.ocrItemId, ocrItemId) ||
                other.ocrItemId == ocrItemId) &&
            (identical(other.brandText, brandText) ||
                other.brandText == brandText) &&
            (identical(other.sizeText, sizeText) ||
                other.sizeText == sizeText) &&
            (identical(other.availableStock, availableStock) ||
                other.availableStock == availableStock) &&
            (identical(other.categoryId, categoryId) ||
                other.categoryId == categoryId) &&
            (identical(other.subcategoryId, subcategoryId) ||
                other.subcategoryId == subcategoryId) &&
            (identical(other.saasBrandId, saasBrandId) ||
                other.saasBrandId == saasBrandId) &&
            (identical(other.brandVariantId, brandVariantId) ||
                other.brandVariantId == brandVariantId) &&
            (identical(other.sellingPrice, sellingPrice) ||
                other.sellingPrice == sellingPrice) &&
            (identical(other.costPrice, costPrice) ||
                other.costPrice == costPrice) &&
            (identical(other.mrp, mrp) || other.mrp == mrp) &&
            (identical(other.reorderLevel, reorderLevel) ||
                other.reorderLevel == reorderLevel) &&
            (identical(other.isDuplicate, isDuplicate) ||
                other.isDuplicate == isDuplicate) &&
            (identical(other.isConfirmed, isConfirmed) ||
                other.isConfirmed == isConfirmed) &&
            (identical(other.enrichmentStatus, enrichmentStatus) ||
                other.enrichmentStatus == enrichmentStatus) &&
            const DeepCollectionEquality()
                .equals(other._validationErrors, _validationErrors));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      ocrItemId,
      brandText,
      sizeText,
      availableStock,
      categoryId,
      subcategoryId,
      saasBrandId,
      brandVariantId,
      sellingPrice,
      costPrice,
      mrp,
      reorderLevel,
      isDuplicate,
      isConfirmed,
      enrichmentStatus,
      const DeepCollectionEquality().hash(_validationErrors));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$EnrichedStockItemImplCopyWith<_$EnrichedStockItemImpl> get copyWith =>
      __$$EnrichedStockItemImplCopyWithImpl<_$EnrichedStockItemImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EnrichedStockItemImplToJson(
      this,
    );
  }
}

abstract class _EnrichedStockItem extends EnrichedStockItem {
  const factory _EnrichedStockItem(
      {@JsonKey(name: 'ocr_item_id') required final String ocrItemId,
      @JsonKey(name: 'brand_text') required final String brandText,
      @JsonKey(name: 'size_text') required final String sizeText,
      @JsonKey(name: 'available_stock') required final int availableStock,
      @JsonKey(name: 'category_id') final String? categoryId,
      @JsonKey(name: 'subcategory_id') final String? subcategoryId,
      @JsonKey(name: 'saas_brand_id') final String? saasBrandId,
      @JsonKey(name: 'brand_variant_id') final String? brandVariantId,
      @JsonKey(name: 'selling_price') final double? sellingPrice,
      @JsonKey(name: 'cost_price') final double? costPrice,
      final double? mrp,
      @JsonKey(name: 'reorder_level') final int? reorderLevel,
      @JsonKey(name: 'is_duplicate') final bool isDuplicate,
      @JsonKey(name: 'is_confirmed') final bool isConfirmed,
      @JsonKey(name: 'enrichment_status')
      final EnrichmentStatus enrichmentStatus,
      @JsonKey(name: 'validation_errors')
      final List<String>? validationErrors}) = _$EnrichedStockItemImpl;
  const _EnrichedStockItem._() : super._();

  factory _EnrichedStockItem.fromJson(Map<String, dynamic> json) =
      _$EnrichedStockItemImpl.fromJson;

  @override
  @JsonKey(name: 'ocr_item_id')
  String get ocrItemId;
  @override
  @JsonKey(name: 'brand_text')
  String get brandText;
  @override
  @JsonKey(name: 'size_text')
  String get sizeText;
  @override
  @JsonKey(name: 'available_stock')
  int get availableStock;
  @override
  @JsonKey(name: 'category_id')
  String? get categoryId;
  @override
  @JsonKey(name: 'subcategory_id')
  String? get subcategoryId;
  @override
  @JsonKey(name: 'saas_brand_id')
  String? get saasBrandId;
  @override
  @JsonKey(name: 'brand_variant_id')
  String? get brandVariantId;
  @override
  @JsonKey(name: 'selling_price')
  double? get sellingPrice;
  @override
  @JsonKey(name: 'cost_price')
  double? get costPrice;
  @override
  double? get mrp;
  @override
  @JsonKey(name: 'reorder_level')
  int? get reorderLevel;
  @override
  @JsonKey(name: 'is_duplicate')
  bool get isDuplicate;
  @override
  @JsonKey(name: 'is_confirmed')
  bool get isConfirmed;
  @override // Enrichment status
  @JsonKey(name: 'enrichment_status')
  EnrichmentStatus get enrichmentStatus;
  @override
  @JsonKey(name: 'validation_errors')
  List<String>? get validationErrors;
  @override
  @JsonKey(ignore: true)
  _$$EnrichedStockItemImplCopyWith<_$EnrichedStockItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

InitializeStockFromOCRRequest _$InitializeStockFromOCRRequestFromJson(
    Map<String, dynamic> json) {
  return _InitializeStockFromOCRRequest.fromJson(json);
}

/// @nodoc
mixin _$InitializeStockFromOCRRequest {
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds => throw _privateConstructorUsedError;
  @JsonKey(name: 'shop_id')
  String get shopId => throw _privateConstructorUsedError;
  String get reason => throw _privateConstructorUsedError;
  List<EnrichedStockItemRequest> get items =>
      throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $InitializeStockFromOCRRequestCopyWith<InitializeStockFromOCRRequest>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InitializeStockFromOCRRequestCopyWith<$Res> {
  factory $InitializeStockFromOCRRequestCopyWith(
          InitializeStockFromOCRRequest value,
          $Res Function(InitializeStockFromOCRRequest) then) =
      _$InitializeStockFromOCRRequestCopyWithImpl<$Res,
          InitializeStockFromOCRRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'session_ids') List<String> sessionIds,
      @JsonKey(name: 'shop_id') String shopId,
      String reason,
      List<EnrichedStockItemRequest> items});
}

/// @nodoc
class _$InitializeStockFromOCRRequestCopyWithImpl<$Res,
        $Val extends InitializeStockFromOCRRequest>
    implements $InitializeStockFromOCRRequestCopyWith<$Res> {
  _$InitializeStockFromOCRRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionIds = null,
    Object? shopId = null,
    Object? reason = null,
    Object? items = null,
  }) {
    return _then(_value.copyWith(
      sessionIds: null == sessionIds
          ? _value.sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<EnrichedStockItemRequest>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$InitializeStockFromOCRRequestImplCopyWith<$Res>
    implements $InitializeStockFromOCRRequestCopyWith<$Res> {
  factory _$$InitializeStockFromOCRRequestImplCopyWith(
          _$InitializeStockFromOCRRequestImpl value,
          $Res Function(_$InitializeStockFromOCRRequestImpl) then) =
      __$$InitializeStockFromOCRRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'session_ids') List<String> sessionIds,
      @JsonKey(name: 'shop_id') String shopId,
      String reason,
      List<EnrichedStockItemRequest> items});
}

/// @nodoc
class __$$InitializeStockFromOCRRequestImplCopyWithImpl<$Res>
    extends _$InitializeStockFromOCRRequestCopyWithImpl<$Res,
        _$InitializeStockFromOCRRequestImpl>
    implements _$$InitializeStockFromOCRRequestImplCopyWith<$Res> {
  __$$InitializeStockFromOCRRequestImplCopyWithImpl(
      _$InitializeStockFromOCRRequestImpl _value,
      $Res Function(_$InitializeStockFromOCRRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sessionIds = null,
    Object? shopId = null,
    Object? reason = null,
    Object? items = null,
  }) {
    return _then(_$InitializeStockFromOCRRequestImpl(
      sessionIds: null == sessionIds
          ? _value._sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      shopId: null == shopId
          ? _value.shopId
          : shopId // ignore: cast_nullable_to_non_nullable
              as String,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<EnrichedStockItemRequest>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$InitializeStockFromOCRRequestImpl
    with DiagnosticableTreeMixin
    implements _InitializeStockFromOCRRequest {
  const _$InitializeStockFromOCRRequestImpl(
      {@JsonKey(name: 'session_ids') required final List<String> sessionIds,
      @JsonKey(name: 'shop_id') required this.shopId,
      required this.reason,
      required final List<EnrichedStockItemRequest> items})
      : _sessionIds = sessionIds,
        _items = items;

  factory _$InitializeStockFromOCRRequestImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$InitializeStockFromOCRRequestImplFromJson(json);

  final List<String> _sessionIds;
  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds {
    if (_sessionIds is EqualUnmodifiableListView) return _sessionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sessionIds);
  }

  @override
  @JsonKey(name: 'shop_id')
  final String shopId;
  @override
  final String reason;
  final List<EnrichedStockItemRequest> _items;
  @override
  List<EnrichedStockItemRequest> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'InitializeStockFromOCRRequest(sessionIds: $sessionIds, shopId: $shopId, reason: $reason, items: $items)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'InitializeStockFromOCRRequest'))
      ..add(DiagnosticsProperty('sessionIds', sessionIds))
      ..add(DiagnosticsProperty('shopId', shopId))
      ..add(DiagnosticsProperty('reason', reason))
      ..add(DiagnosticsProperty('items', items));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InitializeStockFromOCRRequestImpl &&
            const DeepCollectionEquality()
                .equals(other._sessionIds, _sessionIds) &&
            (identical(other.shopId, shopId) || other.shopId == shopId) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_sessionIds),
      shopId,
      reason,
      const DeepCollectionEquality().hash(_items));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$InitializeStockFromOCRRequestImplCopyWith<
          _$InitializeStockFromOCRRequestImpl>
      get copyWith => __$$InitializeStockFromOCRRequestImplCopyWithImpl<
          _$InitializeStockFromOCRRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$InitializeStockFromOCRRequestImplToJson(
      this,
    );
  }
}

abstract class _InitializeStockFromOCRRequest
    implements InitializeStockFromOCRRequest {
  const factory _InitializeStockFromOCRRequest(
          {@JsonKey(name: 'session_ids') required final List<String> sessionIds,
          @JsonKey(name: 'shop_id') required final String shopId,
          required final String reason,
          required final List<EnrichedStockItemRequest> items}) =
      _$InitializeStockFromOCRRequestImpl;

  factory _InitializeStockFromOCRRequest.fromJson(Map<String, dynamic> json) =
      _$InitializeStockFromOCRRequestImpl.fromJson;

  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds;
  @override
  @JsonKey(name: 'shop_id')
  String get shopId;
  @override
  String get reason;
  @override
  List<EnrichedStockItemRequest> get items;
  @override
  @JsonKey(ignore: true)
  _$$InitializeStockFromOCRRequestImplCopyWith<
          _$InitializeStockFromOCRRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

EnrichedStockItemRequest _$EnrichedStockItemRequestFromJson(
    Map<String, dynamic> json) {
  return _EnrichedStockItemRequest.fromJson(json);
}

/// @nodoc
mixin _$EnrichedStockItemRequest {
  @JsonKey(name: 'ocr_item_id')
  String get ocrItemId => throw _privateConstructorUsedError;
  @JsonKey(name: 'brand_text')
  String get brandText => throw _privateConstructorUsedError;
  @JsonKey(name: 'size_text')
  String get sizeText => throw _privateConstructorUsedError;
  @JsonKey(name: 'category_id')
  String get categoryId => throw _privateConstructorUsedError;
  @JsonKey(name: 'subcategory_id')
  String? get subcategoryId => throw _privateConstructorUsedError;
  @JsonKey(name: 'selling_price')
  double get sellingPrice => throw _privateConstructorUsedError;
  @JsonKey(name: 'cost_price')
  double get costPrice => throw _privateConstructorUsedError;
  double get mrp => throw _privateConstructorUsedError;
  @JsonKey(name: 'available_stock')
  int get availableStock => throw _privateConstructorUsedError;
  @JsonKey(name: 'reorder_level')
  int? get reorderLevel => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_duplicate')
  bool get isDuplicate => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $EnrichedStockItemRequestCopyWith<EnrichedStockItemRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EnrichedStockItemRequestCopyWith<$Res> {
  factory $EnrichedStockItemRequestCopyWith(EnrichedStockItemRequest value,
          $Res Function(EnrichedStockItemRequest) then) =
      _$EnrichedStockItemRequestCopyWithImpl<$Res, EnrichedStockItemRequest>;
  @useResult
  $Res call(
      {@JsonKey(name: 'ocr_item_id') String ocrItemId,
      @JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String sizeText,
      @JsonKey(name: 'category_id') String categoryId,
      @JsonKey(name: 'subcategory_id') String? subcategoryId,
      @JsonKey(name: 'selling_price') double sellingPrice,
      @JsonKey(name: 'cost_price') double costPrice,
      double mrp,
      @JsonKey(name: 'available_stock') int availableStock,
      @JsonKey(name: 'reorder_level') int? reorderLevel,
      @JsonKey(name: 'is_duplicate') bool isDuplicate});
}

/// @nodoc
class _$EnrichedStockItemRequestCopyWithImpl<$Res,
        $Val extends EnrichedStockItemRequest>
    implements $EnrichedStockItemRequestCopyWith<$Res> {
  _$EnrichedStockItemRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ocrItemId = null,
    Object? brandText = null,
    Object? sizeText = null,
    Object? categoryId = null,
    Object? subcategoryId = freezed,
    Object? sellingPrice = null,
    Object? costPrice = null,
    Object? mrp = null,
    Object? availableStock = null,
    Object? reorderLevel = freezed,
    Object? isDuplicate = null,
  }) {
    return _then(_value.copyWith(
      ocrItemId: null == ocrItemId
          ? _value.ocrItemId
          : ocrItemId // ignore: cast_nullable_to_non_nullable
              as String,
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: null == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String,
      categoryId: null == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      sellingPrice: null == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double,
      costPrice: null == costPrice
          ? _value.costPrice
          : costPrice // ignore: cast_nullable_to_non_nullable
              as double,
      mrp: null == mrp
          ? _value.mrp
          : mrp // ignore: cast_nullable_to_non_nullable
              as double,
      availableStock: null == availableStock
          ? _value.availableStock
          : availableStock // ignore: cast_nullable_to_non_nullable
              as int,
      reorderLevel: freezed == reorderLevel
          ? _value.reorderLevel
          : reorderLevel // ignore: cast_nullable_to_non_nullable
              as int?,
      isDuplicate: null == isDuplicate
          ? _value.isDuplicate
          : isDuplicate // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EnrichedStockItemRequestImplCopyWith<$Res>
    implements $EnrichedStockItemRequestCopyWith<$Res> {
  factory _$$EnrichedStockItemRequestImplCopyWith(
          _$EnrichedStockItemRequestImpl value,
          $Res Function(_$EnrichedStockItemRequestImpl) then) =
      __$$EnrichedStockItemRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'ocr_item_id') String ocrItemId,
      @JsonKey(name: 'brand_text') String brandText,
      @JsonKey(name: 'size_text') String sizeText,
      @JsonKey(name: 'category_id') String categoryId,
      @JsonKey(name: 'subcategory_id') String? subcategoryId,
      @JsonKey(name: 'selling_price') double sellingPrice,
      @JsonKey(name: 'cost_price') double costPrice,
      double mrp,
      @JsonKey(name: 'available_stock') int availableStock,
      @JsonKey(name: 'reorder_level') int? reorderLevel,
      @JsonKey(name: 'is_duplicate') bool isDuplicate});
}

/// @nodoc
class __$$EnrichedStockItemRequestImplCopyWithImpl<$Res>
    extends _$EnrichedStockItemRequestCopyWithImpl<$Res,
        _$EnrichedStockItemRequestImpl>
    implements _$$EnrichedStockItemRequestImplCopyWith<$Res> {
  __$$EnrichedStockItemRequestImplCopyWithImpl(
      _$EnrichedStockItemRequestImpl _value,
      $Res Function(_$EnrichedStockItemRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ocrItemId = null,
    Object? brandText = null,
    Object? sizeText = null,
    Object? categoryId = null,
    Object? subcategoryId = freezed,
    Object? sellingPrice = null,
    Object? costPrice = null,
    Object? mrp = null,
    Object? availableStock = null,
    Object? reorderLevel = freezed,
    Object? isDuplicate = null,
  }) {
    return _then(_$EnrichedStockItemRequestImpl(
      ocrItemId: null == ocrItemId
          ? _value.ocrItemId
          : ocrItemId // ignore: cast_nullable_to_non_nullable
              as String,
      brandText: null == brandText
          ? _value.brandText
          : brandText // ignore: cast_nullable_to_non_nullable
              as String,
      sizeText: null == sizeText
          ? _value.sizeText
          : sizeText // ignore: cast_nullable_to_non_nullable
              as String,
      categoryId: null == categoryId
          ? _value.categoryId
          : categoryId // ignore: cast_nullable_to_non_nullable
              as String,
      subcategoryId: freezed == subcategoryId
          ? _value.subcategoryId
          : subcategoryId // ignore: cast_nullable_to_non_nullable
              as String?,
      sellingPrice: null == sellingPrice
          ? _value.sellingPrice
          : sellingPrice // ignore: cast_nullable_to_non_nullable
              as double,
      costPrice: null == costPrice
          ? _value.costPrice
          : costPrice // ignore: cast_nullable_to_non_nullable
              as double,
      mrp: null == mrp
          ? _value.mrp
          : mrp // ignore: cast_nullable_to_non_nullable
              as double,
      availableStock: null == availableStock
          ? _value.availableStock
          : availableStock // ignore: cast_nullable_to_non_nullable
              as int,
      reorderLevel: freezed == reorderLevel
          ? _value.reorderLevel
          : reorderLevel // ignore: cast_nullable_to_non_nullable
              as int?,
      isDuplicate: null == isDuplicate
          ? _value.isDuplicate
          : isDuplicate // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EnrichedStockItemRequestImpl
    with DiagnosticableTreeMixin
    implements _EnrichedStockItemRequest {
  const _$EnrichedStockItemRequestImpl(
      {@JsonKey(name: 'ocr_item_id') required this.ocrItemId,
      @JsonKey(name: 'brand_text') required this.brandText,
      @JsonKey(name: 'size_text') required this.sizeText,
      @JsonKey(name: 'category_id') required this.categoryId,
      @JsonKey(name: 'subcategory_id') this.subcategoryId,
      @JsonKey(name: 'selling_price') required this.sellingPrice,
      @JsonKey(name: 'cost_price') required this.costPrice,
      required this.mrp,
      @JsonKey(name: 'available_stock') required this.availableStock,
      @JsonKey(name: 'reorder_level') this.reorderLevel,
      @JsonKey(name: 'is_duplicate') this.isDuplicate = false});

  factory _$EnrichedStockItemRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$EnrichedStockItemRequestImplFromJson(json);

  @override
  @JsonKey(name: 'ocr_item_id')
  final String ocrItemId;
  @override
  @JsonKey(name: 'brand_text')
  final String brandText;
  @override
  @JsonKey(name: 'size_text')
  final String sizeText;
  @override
  @JsonKey(name: 'category_id')
  final String categoryId;
  @override
  @JsonKey(name: 'subcategory_id')
  final String? subcategoryId;
  @override
  @JsonKey(name: 'selling_price')
  final double sellingPrice;
  @override
  @JsonKey(name: 'cost_price')
  final double costPrice;
  @override
  final double mrp;
  @override
  @JsonKey(name: 'available_stock')
  final int availableStock;
  @override
  @JsonKey(name: 'reorder_level')
  final int? reorderLevel;
  @override
  @JsonKey(name: 'is_duplicate')
  final bool isDuplicate;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'EnrichedStockItemRequest(ocrItemId: $ocrItemId, brandText: $brandText, sizeText: $sizeText, categoryId: $categoryId, subcategoryId: $subcategoryId, sellingPrice: $sellingPrice, costPrice: $costPrice, mrp: $mrp, availableStock: $availableStock, reorderLevel: $reorderLevel, isDuplicate: $isDuplicate)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'EnrichedStockItemRequest'))
      ..add(DiagnosticsProperty('ocrItemId', ocrItemId))
      ..add(DiagnosticsProperty('brandText', brandText))
      ..add(DiagnosticsProperty('sizeText', sizeText))
      ..add(DiagnosticsProperty('categoryId', categoryId))
      ..add(DiagnosticsProperty('subcategoryId', subcategoryId))
      ..add(DiagnosticsProperty('sellingPrice', sellingPrice))
      ..add(DiagnosticsProperty('costPrice', costPrice))
      ..add(DiagnosticsProperty('mrp', mrp))
      ..add(DiagnosticsProperty('availableStock', availableStock))
      ..add(DiagnosticsProperty('reorderLevel', reorderLevel))
      ..add(DiagnosticsProperty('isDuplicate', isDuplicate));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EnrichedStockItemRequestImpl &&
            (identical(other.ocrItemId, ocrItemId) ||
                other.ocrItemId == ocrItemId) &&
            (identical(other.brandText, brandText) ||
                other.brandText == brandText) &&
            (identical(other.sizeText, sizeText) ||
                other.sizeText == sizeText) &&
            (identical(other.categoryId, categoryId) ||
                other.categoryId == categoryId) &&
            (identical(other.subcategoryId, subcategoryId) ||
                other.subcategoryId == subcategoryId) &&
            (identical(other.sellingPrice, sellingPrice) ||
                other.sellingPrice == sellingPrice) &&
            (identical(other.costPrice, costPrice) ||
                other.costPrice == costPrice) &&
            (identical(other.mrp, mrp) || other.mrp == mrp) &&
            (identical(other.availableStock, availableStock) ||
                other.availableStock == availableStock) &&
            (identical(other.reorderLevel, reorderLevel) ||
                other.reorderLevel == reorderLevel) &&
            (identical(other.isDuplicate, isDuplicate) ||
                other.isDuplicate == isDuplicate));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      ocrItemId,
      brandText,
      sizeText,
      categoryId,
      subcategoryId,
      sellingPrice,
      costPrice,
      mrp,
      availableStock,
      reorderLevel,
      isDuplicate);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$EnrichedStockItemRequestImplCopyWith<_$EnrichedStockItemRequestImpl>
      get copyWith => __$$EnrichedStockItemRequestImplCopyWithImpl<
          _$EnrichedStockItemRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EnrichedStockItemRequestImplToJson(
      this,
    );
  }
}

abstract class _EnrichedStockItemRequest implements EnrichedStockItemRequest {
  const factory _EnrichedStockItemRequest(
          {@JsonKey(name: 'ocr_item_id') required final String ocrItemId,
          @JsonKey(name: 'brand_text') required final String brandText,
          @JsonKey(name: 'size_text') required final String sizeText,
          @JsonKey(name: 'category_id') required final String categoryId,
          @JsonKey(name: 'subcategory_id') final String? subcategoryId,
          @JsonKey(name: 'selling_price') required final double sellingPrice,
          @JsonKey(name: 'cost_price') required final double costPrice,
          required final double mrp,
          @JsonKey(name: 'available_stock') required final int availableStock,
          @JsonKey(name: 'reorder_level') final int? reorderLevel,
          @JsonKey(name: 'is_duplicate') final bool isDuplicate}) =
      _$EnrichedStockItemRequestImpl;

  factory _EnrichedStockItemRequest.fromJson(Map<String, dynamic> json) =
      _$EnrichedStockItemRequestImpl.fromJson;

  @override
  @JsonKey(name: 'ocr_item_id')
  String get ocrItemId;
  @override
  @JsonKey(name: 'brand_text')
  String get brandText;
  @override
  @JsonKey(name: 'size_text')
  String get sizeText;
  @override
  @JsonKey(name: 'category_id')
  String get categoryId;
  @override
  @JsonKey(name: 'subcategory_id')
  String? get subcategoryId;
  @override
  @JsonKey(name: 'selling_price')
  double get sellingPrice;
  @override
  @JsonKey(name: 'cost_price')
  double get costPrice;
  @override
  double get mrp;
  @override
  @JsonKey(name: 'available_stock')
  int get availableStock;
  @override
  @JsonKey(name: 'reorder_level')
  int? get reorderLevel;
  @override
  @JsonKey(name: 'is_duplicate')
  bool get isDuplicate;
  @override
  @JsonKey(ignore: true)
  _$$EnrichedStockItemRequestImplCopyWith<_$EnrichedStockItemRequestImpl>
      get copyWith => throw _privateConstructorUsedError;
}

InitializeStockResponse _$InitializeStockResponseFromJson(
    Map<String, dynamic> json) {
  return _InitializeStockResponse.fromJson(json);
}

/// @nodoc
mixin _$InitializeStockResponse {
  bool get success => throw _privateConstructorUsedError;
  String get message => throw _privateConstructorUsedError;
  @JsonKey(name: 'items_processed')
  int get itemsProcessed => throw _privateConstructorUsedError;
  @JsonKey(name: 'items_created')
  int get itemsCreated => throw _privateConstructorUsedError;
  @JsonKey(name: 'items_failed')
  int get itemsFailed => throw _privateConstructorUsedError;
  List<StockInitializationResult> get results =>
      throw _privateConstructorUsedError;
  Map<String, dynamic>? get summary => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $InitializeStockResponseCopyWith<InitializeStockResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $InitializeStockResponseCopyWith<$Res> {
  factory $InitializeStockResponseCopyWith(InitializeStockResponse value,
          $Res Function(InitializeStockResponse) then) =
      _$InitializeStockResponseCopyWithImpl<$Res, InitializeStockResponse>;
  @useResult
  $Res call(
      {bool success,
      String message,
      @JsonKey(name: 'items_processed') int itemsProcessed,
      @JsonKey(name: 'items_created') int itemsCreated,
      @JsonKey(name: 'items_failed') int itemsFailed,
      List<StockInitializationResult> results,
      Map<String, dynamic>? summary});
}

/// @nodoc
class _$InitializeStockResponseCopyWithImpl<$Res,
        $Val extends InitializeStockResponse>
    implements $InitializeStockResponseCopyWith<$Res> {
  _$InitializeStockResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? itemsProcessed = null,
    Object? itemsCreated = null,
    Object? itemsFailed = null,
    Object? results = null,
    Object? summary = freezed,
  }) {
    return _then(_value.copyWith(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      itemsProcessed: null == itemsProcessed
          ? _value.itemsProcessed
          : itemsProcessed // ignore: cast_nullable_to_non_nullable
              as int,
      itemsCreated: null == itemsCreated
          ? _value.itemsCreated
          : itemsCreated // ignore: cast_nullable_to_non_nullable
              as int,
      itemsFailed: null == itemsFailed
          ? _value.itemsFailed
          : itemsFailed // ignore: cast_nullable_to_non_nullable
              as int,
      results: null == results
          ? _value.results
          : results // ignore: cast_nullable_to_non_nullable
              as List<StockInitializationResult>,
      summary: freezed == summary
          ? _value.summary
          : summary // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$InitializeStockResponseImplCopyWith<$Res>
    implements $InitializeStockResponseCopyWith<$Res> {
  factory _$$InitializeStockResponseImplCopyWith(
          _$InitializeStockResponseImpl value,
          $Res Function(_$InitializeStockResponseImpl) then) =
      __$$InitializeStockResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool success,
      String message,
      @JsonKey(name: 'items_processed') int itemsProcessed,
      @JsonKey(name: 'items_created') int itemsCreated,
      @JsonKey(name: 'items_failed') int itemsFailed,
      List<StockInitializationResult> results,
      Map<String, dynamic>? summary});
}

/// @nodoc
class __$$InitializeStockResponseImplCopyWithImpl<$Res>
    extends _$InitializeStockResponseCopyWithImpl<$Res,
        _$InitializeStockResponseImpl>
    implements _$$InitializeStockResponseImplCopyWith<$Res> {
  __$$InitializeStockResponseImplCopyWithImpl(
      _$InitializeStockResponseImpl _value,
      $Res Function(_$InitializeStockResponseImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? success = null,
    Object? message = null,
    Object? itemsProcessed = null,
    Object? itemsCreated = null,
    Object? itemsFailed = null,
    Object? results = null,
    Object? summary = freezed,
  }) {
    return _then(_$InitializeStockResponseImpl(
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      itemsProcessed: null == itemsProcessed
          ? _value.itemsProcessed
          : itemsProcessed // ignore: cast_nullable_to_non_nullable
              as int,
      itemsCreated: null == itemsCreated
          ? _value.itemsCreated
          : itemsCreated // ignore: cast_nullable_to_non_nullable
              as int,
      itemsFailed: null == itemsFailed
          ? _value.itemsFailed
          : itemsFailed // ignore: cast_nullable_to_non_nullable
              as int,
      results: null == results
          ? _value._results
          : results // ignore: cast_nullable_to_non_nullable
              as List<StockInitializationResult>,
      summary: freezed == summary
          ? _value._summary
          : summary // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$InitializeStockResponseImpl
    with DiagnosticableTreeMixin
    implements _InitializeStockResponse {
  const _$InitializeStockResponseImpl(
      {required this.success,
      required this.message,
      @JsonKey(name: 'items_processed') required this.itemsProcessed,
      @JsonKey(name: 'items_created') required this.itemsCreated,
      @JsonKey(name: 'items_failed') required this.itemsFailed,
      final List<StockInitializationResult> results = const [],
      final Map<String, dynamic>? summary})
      : _results = results,
        _summary = summary;

  factory _$InitializeStockResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$InitializeStockResponseImplFromJson(json);

  @override
  final bool success;
  @override
  final String message;
  @override
  @JsonKey(name: 'items_processed')
  final int itemsProcessed;
  @override
  @JsonKey(name: 'items_created')
  final int itemsCreated;
  @override
  @JsonKey(name: 'items_failed')
  final int itemsFailed;
  final List<StockInitializationResult> _results;
  @override
  @JsonKey()
  List<StockInitializationResult> get results {
    if (_results is EqualUnmodifiableListView) return _results;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_results);
  }

  final Map<String, dynamic>? _summary;
  @override
  Map<String, dynamic>? get summary {
    final value = _summary;
    if (value == null) return null;
    if (_summary is EqualUnmodifiableMapView) return _summary;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'InitializeStockResponse(success: $success, message: $message, itemsProcessed: $itemsProcessed, itemsCreated: $itemsCreated, itemsFailed: $itemsFailed, results: $results, summary: $summary)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'InitializeStockResponse'))
      ..add(DiagnosticsProperty('success', success))
      ..add(DiagnosticsProperty('message', message))
      ..add(DiagnosticsProperty('itemsProcessed', itemsProcessed))
      ..add(DiagnosticsProperty('itemsCreated', itemsCreated))
      ..add(DiagnosticsProperty('itemsFailed', itemsFailed))
      ..add(DiagnosticsProperty('results', results))
      ..add(DiagnosticsProperty('summary', summary));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$InitializeStockResponseImpl &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.itemsProcessed, itemsProcessed) ||
                other.itemsProcessed == itemsProcessed) &&
            (identical(other.itemsCreated, itemsCreated) ||
                other.itemsCreated == itemsCreated) &&
            (identical(other.itemsFailed, itemsFailed) ||
                other.itemsFailed == itemsFailed) &&
            const DeepCollectionEquality().equals(other._results, _results) &&
            const DeepCollectionEquality().equals(other._summary, _summary));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      success,
      message,
      itemsProcessed,
      itemsCreated,
      itemsFailed,
      const DeepCollectionEquality().hash(_results),
      const DeepCollectionEquality().hash(_summary));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$InitializeStockResponseImplCopyWith<_$InitializeStockResponseImpl>
      get copyWith => __$$InitializeStockResponseImplCopyWithImpl<
          _$InitializeStockResponseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$InitializeStockResponseImplToJson(
      this,
    );
  }
}

abstract class _InitializeStockResponse implements InitializeStockResponse {
  const factory _InitializeStockResponse(
      {required final bool success,
      required final String message,
      @JsonKey(name: 'items_processed') required final int itemsProcessed,
      @JsonKey(name: 'items_created') required final int itemsCreated,
      @JsonKey(name: 'items_failed') required final int itemsFailed,
      final List<StockInitializationResult> results,
      final Map<String, dynamic>? summary}) = _$InitializeStockResponseImpl;

  factory _InitializeStockResponse.fromJson(Map<String, dynamic> json) =
      _$InitializeStockResponseImpl.fromJson;

  @override
  bool get success;
  @override
  String get message;
  @override
  @JsonKey(name: 'items_processed')
  int get itemsProcessed;
  @override
  @JsonKey(name: 'items_created')
  int get itemsCreated;
  @override
  @JsonKey(name: 'items_failed')
  int get itemsFailed;
  @override
  List<StockInitializationResult> get results;
  @override
  Map<String, dynamic>? get summary;
  @override
  @JsonKey(ignore: true)
  _$$InitializeStockResponseImplCopyWith<_$InitializeStockResponseImpl>
      get copyWith => throw _privateConstructorUsedError;
}

StockInitializationResult _$StockInitializationResultFromJson(
    Map<String, dynamic> json) {
  return _StockInitializationResult.fromJson(json);
}

/// @nodoc
mixin _$StockInitializationResult {
  @JsonKey(name: 'ocr_item_id')
  String get ocrItemId => throw _privateConstructorUsedError;
  bool get success => throw _privateConstructorUsedError;
  @JsonKey(name: 'product_id')
  String? get productId => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;
  Map<String, dynamic>? get details => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $StockInitializationResultCopyWith<StockInitializationResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StockInitializationResultCopyWith<$Res> {
  factory $StockInitializationResultCopyWith(StockInitializationResult value,
          $Res Function(StockInitializationResult) then) =
      _$StockInitializationResultCopyWithImpl<$Res, StockInitializationResult>;
  @useResult
  $Res call(
      {@JsonKey(name: 'ocr_item_id') String ocrItemId,
      bool success,
      @JsonKey(name: 'product_id') String? productId,
      String? error,
      Map<String, dynamic>? details});
}

/// @nodoc
class _$StockInitializationResultCopyWithImpl<$Res,
        $Val extends StockInitializationResult>
    implements $StockInitializationResultCopyWith<$Res> {
  _$StockInitializationResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ocrItemId = null,
    Object? success = null,
    Object? productId = freezed,
    Object? error = freezed,
    Object? details = freezed,
  }) {
    return _then(_value.copyWith(
      ocrItemId: null == ocrItemId
          ? _value.ocrItemId
          : ocrItemId // ignore: cast_nullable_to_non_nullable
              as String,
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      productId: freezed == productId
          ? _value.productId
          : productId // ignore: cast_nullable_to_non_nullable
              as String?,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
      details: freezed == details
          ? _value.details
          : details // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$StockInitializationResultImplCopyWith<$Res>
    implements $StockInitializationResultCopyWith<$Res> {
  factory _$$StockInitializationResultImplCopyWith(
          _$StockInitializationResultImpl value,
          $Res Function(_$StockInitializationResultImpl) then) =
      __$$StockInitializationResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'ocr_item_id') String ocrItemId,
      bool success,
      @JsonKey(name: 'product_id') String? productId,
      String? error,
      Map<String, dynamic>? details});
}

/// @nodoc
class __$$StockInitializationResultImplCopyWithImpl<$Res>
    extends _$StockInitializationResultCopyWithImpl<$Res,
        _$StockInitializationResultImpl>
    implements _$$StockInitializationResultImplCopyWith<$Res> {
  __$$StockInitializationResultImplCopyWithImpl(
      _$StockInitializationResultImpl _value,
      $Res Function(_$StockInitializationResultImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ocrItemId = null,
    Object? success = null,
    Object? productId = freezed,
    Object? error = freezed,
    Object? details = freezed,
  }) {
    return _then(_$StockInitializationResultImpl(
      ocrItemId: null == ocrItemId
          ? _value.ocrItemId
          : ocrItemId // ignore: cast_nullable_to_non_nullable
              as String,
      success: null == success
          ? _value.success
          : success // ignore: cast_nullable_to_non_nullable
              as bool,
      productId: freezed == productId
          ? _value.productId
          : productId // ignore: cast_nullable_to_non_nullable
              as String?,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
      details: freezed == details
          ? _value._details
          : details // ignore: cast_nullable_to_non_nullable
              as Map<String, dynamic>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$StockInitializationResultImpl
    with DiagnosticableTreeMixin
    implements _StockInitializationResult {
  const _$StockInitializationResultImpl(
      {@JsonKey(name: 'ocr_item_id') required this.ocrItemId,
      required this.success,
      @JsonKey(name: 'product_id') this.productId,
      this.error,
      final Map<String, dynamic>? details})
      : _details = details;

  factory _$StockInitializationResultImpl.fromJson(Map<String, dynamic> json) =>
      _$$StockInitializationResultImplFromJson(json);

  @override
  @JsonKey(name: 'ocr_item_id')
  final String ocrItemId;
  @override
  final bool success;
  @override
  @JsonKey(name: 'product_id')
  final String? productId;
  @override
  final String? error;
  final Map<String, dynamic>? _details;
  @override
  Map<String, dynamic>? get details {
    final value = _details;
    if (value == null) return null;
    if (_details is EqualUnmodifiableMapView) return _details;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'StockInitializationResult(ocrItemId: $ocrItemId, success: $success, productId: $productId, error: $error, details: $details)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'StockInitializationResult'))
      ..add(DiagnosticsProperty('ocrItemId', ocrItemId))
      ..add(DiagnosticsProperty('success', success))
      ..add(DiagnosticsProperty('productId', productId))
      ..add(DiagnosticsProperty('error', error))
      ..add(DiagnosticsProperty('details', details));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StockInitializationResultImpl &&
            (identical(other.ocrItemId, ocrItemId) ||
                other.ocrItemId == ocrItemId) &&
            (identical(other.success, success) || other.success == success) &&
            (identical(other.productId, productId) ||
                other.productId == productId) &&
            (identical(other.error, error) || other.error == error) &&
            const DeepCollectionEquality().equals(other._details, _details));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, ocrItemId, success, productId,
      error, const DeepCollectionEquality().hash(_details));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$StockInitializationResultImplCopyWith<_$StockInitializationResultImpl>
      get copyWith => __$$StockInitializationResultImplCopyWithImpl<
          _$StockInitializationResultImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StockInitializationResultImplToJson(
      this,
    );
  }
}

abstract class _StockInitializationResult implements StockInitializationResult {
  const factory _StockInitializationResult(
      {@JsonKey(name: 'ocr_item_id') required final String ocrItemId,
      required final bool success,
      @JsonKey(name: 'product_id') final String? productId,
      final String? error,
      final Map<String, dynamic>? details}) = _$StockInitializationResultImpl;

  factory _StockInitializationResult.fromJson(Map<String, dynamic> json) =
      _$StockInitializationResultImpl.fromJson;

  @override
  @JsonKey(name: 'ocr_item_id')
  String get ocrItemId;
  @override
  bool get success;
  @override
  @JsonKey(name: 'product_id')
  String? get productId;
  @override
  String? get error;
  @override
  Map<String, dynamic>? get details;
  @override
  @JsonKey(ignore: true)
  _$$StockInitializationResultImplCopyWith<_$StockInitializationResultImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BatchOCRProgress _$BatchOCRProgressFromJson(Map<String, dynamic> json) {
  return _BatchOCRProgress.fromJson(json);
}

/// @nodoc
mixin _$BatchOCRProgress {
  @JsonKey(name: 'batch_id')
  String get batchId => throw _privateConstructorUsedError;
  @JsonKey(name: 'total_images')
  int get totalImages => throw _privateConstructorUsedError;
  @JsonKey(name: 'completed_images')
  int get completedImages => throw _privateConstructorUsedError;
  @JsonKey(name: 'failed_images')
  int get failedImages => throw _privateConstructorUsedError;
  @JsonKey(name: 'progress_percentage')
  double get progressPercentage => throw _privateConstructorUsedError;
  BatchStatus get status => throw _privateConstructorUsedError;
  @JsonKey(name: 'current_image_name')
  String? get currentImageName => throw _privateConstructorUsedError;
  @JsonKey(name: 'estimated_time_remaining_seconds')
  int? get estimatedTimeRemainingSeconds =>
      throw _privateConstructorUsedError; // Phase 1.2: Add stage tracking from WebSocket
  String? get stage =>
      throw _privateConstructorUsedError; // Current OCR stage: "text_extraction", "brand_matching", etc.
  @JsonKey(name: 'items_extracted')
  int? get itemsExtracted =>
      throw _privateConstructorUsedError; // Phase 2.2: Items count
  @JsonKey(name: 'current_item')
  String? get currentItem => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BatchOCRProgressCopyWith<BatchOCRProgress> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BatchOCRProgressCopyWith<$Res> {
  factory $BatchOCRProgressCopyWith(
          BatchOCRProgress value, $Res Function(BatchOCRProgress) then) =
      _$BatchOCRProgressCopyWithImpl<$Res, BatchOCRProgress>;
  @useResult
  $Res call(
      {@JsonKey(name: 'batch_id') String batchId,
      @JsonKey(name: 'total_images') int totalImages,
      @JsonKey(name: 'completed_images') int completedImages,
      @JsonKey(name: 'failed_images') int failedImages,
      @JsonKey(name: 'progress_percentage') double progressPercentage,
      BatchStatus status,
      @JsonKey(name: 'current_image_name') String? currentImageName,
      @JsonKey(name: 'estimated_time_remaining_seconds')
      int? estimatedTimeRemainingSeconds,
      String? stage,
      @JsonKey(name: 'items_extracted') int? itemsExtracted,
      @JsonKey(name: 'current_item') String? currentItem});
}

/// @nodoc
class _$BatchOCRProgressCopyWithImpl<$Res, $Val extends BatchOCRProgress>
    implements $BatchOCRProgressCopyWith<$Res> {
  _$BatchOCRProgressCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? batchId = null,
    Object? totalImages = null,
    Object? completedImages = null,
    Object? failedImages = null,
    Object? progressPercentage = null,
    Object? status = null,
    Object? currentImageName = freezed,
    Object? estimatedTimeRemainingSeconds = freezed,
    Object? stage = freezed,
    Object? itemsExtracted = freezed,
    Object? currentItem = freezed,
  }) {
    return _then(_value.copyWith(
      batchId: null == batchId
          ? _value.batchId
          : batchId // ignore: cast_nullable_to_non_nullable
              as String,
      totalImages: null == totalImages
          ? _value.totalImages
          : totalImages // ignore: cast_nullable_to_non_nullable
              as int,
      completedImages: null == completedImages
          ? _value.completedImages
          : completedImages // ignore: cast_nullable_to_non_nullable
              as int,
      failedImages: null == failedImages
          ? _value.failedImages
          : failedImages // ignore: cast_nullable_to_non_nullable
              as int,
      progressPercentage: null == progressPercentage
          ? _value.progressPercentage
          : progressPercentage // ignore: cast_nullable_to_non_nullable
              as double,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as BatchStatus,
      currentImageName: freezed == currentImageName
          ? _value.currentImageName
          : currentImageName // ignore: cast_nullable_to_non_nullable
              as String?,
      estimatedTimeRemainingSeconds: freezed == estimatedTimeRemainingSeconds
          ? _value.estimatedTimeRemainingSeconds
          : estimatedTimeRemainingSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      stage: freezed == stage
          ? _value.stage
          : stage // ignore: cast_nullable_to_non_nullable
              as String?,
      itemsExtracted: freezed == itemsExtracted
          ? _value.itemsExtracted
          : itemsExtracted // ignore: cast_nullable_to_non_nullable
              as int?,
      currentItem: freezed == currentItem
          ? _value.currentItem
          : currentItem // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BatchOCRProgressImplCopyWith<$Res>
    implements $BatchOCRProgressCopyWith<$Res> {
  factory _$$BatchOCRProgressImplCopyWith(_$BatchOCRProgressImpl value,
          $Res Function(_$BatchOCRProgressImpl) then) =
      __$$BatchOCRProgressImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'batch_id') String batchId,
      @JsonKey(name: 'total_images') int totalImages,
      @JsonKey(name: 'completed_images') int completedImages,
      @JsonKey(name: 'failed_images') int failedImages,
      @JsonKey(name: 'progress_percentage') double progressPercentage,
      BatchStatus status,
      @JsonKey(name: 'current_image_name') String? currentImageName,
      @JsonKey(name: 'estimated_time_remaining_seconds')
      int? estimatedTimeRemainingSeconds,
      String? stage,
      @JsonKey(name: 'items_extracted') int? itemsExtracted,
      @JsonKey(name: 'current_item') String? currentItem});
}

/// @nodoc
class __$$BatchOCRProgressImplCopyWithImpl<$Res>
    extends _$BatchOCRProgressCopyWithImpl<$Res, _$BatchOCRProgressImpl>
    implements _$$BatchOCRProgressImplCopyWith<$Res> {
  __$$BatchOCRProgressImplCopyWithImpl(_$BatchOCRProgressImpl _value,
      $Res Function(_$BatchOCRProgressImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? batchId = null,
    Object? totalImages = null,
    Object? completedImages = null,
    Object? failedImages = null,
    Object? progressPercentage = null,
    Object? status = null,
    Object? currentImageName = freezed,
    Object? estimatedTimeRemainingSeconds = freezed,
    Object? stage = freezed,
    Object? itemsExtracted = freezed,
    Object? currentItem = freezed,
  }) {
    return _then(_$BatchOCRProgressImpl(
      batchId: null == batchId
          ? _value.batchId
          : batchId // ignore: cast_nullable_to_non_nullable
              as String,
      totalImages: null == totalImages
          ? _value.totalImages
          : totalImages // ignore: cast_nullable_to_non_nullable
              as int,
      completedImages: null == completedImages
          ? _value.completedImages
          : completedImages // ignore: cast_nullable_to_non_nullable
              as int,
      failedImages: null == failedImages
          ? _value.failedImages
          : failedImages // ignore: cast_nullable_to_non_nullable
              as int,
      progressPercentage: null == progressPercentage
          ? _value.progressPercentage
          : progressPercentage // ignore: cast_nullable_to_non_nullable
              as double,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as BatchStatus,
      currentImageName: freezed == currentImageName
          ? _value.currentImageName
          : currentImageName // ignore: cast_nullable_to_non_nullable
              as String?,
      estimatedTimeRemainingSeconds: freezed == estimatedTimeRemainingSeconds
          ? _value.estimatedTimeRemainingSeconds
          : estimatedTimeRemainingSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      stage: freezed == stage
          ? _value.stage
          : stage // ignore: cast_nullable_to_non_nullable
              as String?,
      itemsExtracted: freezed == itemsExtracted
          ? _value.itemsExtracted
          : itemsExtracted // ignore: cast_nullable_to_non_nullable
              as int?,
      currentItem: freezed == currentItem
          ? _value.currentItem
          : currentItem // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BatchOCRProgressImpl extends _BatchOCRProgress
    with DiagnosticableTreeMixin {
  const _$BatchOCRProgressImpl(
      {@JsonKey(name: 'batch_id') required this.batchId,
      @JsonKey(name: 'total_images') required this.totalImages,
      @JsonKey(name: 'completed_images') required this.completedImages,
      @JsonKey(name: 'failed_images') required this.failedImages,
      @JsonKey(name: 'progress_percentage') required this.progressPercentage,
      required this.status,
      @JsonKey(name: 'current_image_name') this.currentImageName,
      @JsonKey(name: 'estimated_time_remaining_seconds')
      this.estimatedTimeRemainingSeconds,
      this.stage,
      @JsonKey(name: 'items_extracted') this.itemsExtracted,
      @JsonKey(name: 'current_item') this.currentItem})
      : super._();

  factory _$BatchOCRProgressImpl.fromJson(Map<String, dynamic> json) =>
      _$$BatchOCRProgressImplFromJson(json);

  @override
  @JsonKey(name: 'batch_id')
  final String batchId;
  @override
  @JsonKey(name: 'total_images')
  final int totalImages;
  @override
  @JsonKey(name: 'completed_images')
  final int completedImages;
  @override
  @JsonKey(name: 'failed_images')
  final int failedImages;
  @override
  @JsonKey(name: 'progress_percentage')
  final double progressPercentage;
  @override
  final BatchStatus status;
  @override
  @JsonKey(name: 'current_image_name')
  final String? currentImageName;
  @override
  @JsonKey(name: 'estimated_time_remaining_seconds')
  final int? estimatedTimeRemainingSeconds;
// Phase 1.2: Add stage tracking from WebSocket
  @override
  final String? stage;
// Current OCR stage: "text_extraction", "brand_matching", etc.
  @override
  @JsonKey(name: 'items_extracted')
  final int? itemsExtracted;
// Phase 2.2: Items count
  @override
  @JsonKey(name: 'current_item')
  final String? currentItem;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'BatchOCRProgress(batchId: $batchId, totalImages: $totalImages, completedImages: $completedImages, failedImages: $failedImages, progressPercentage: $progressPercentage, status: $status, currentImageName: $currentImageName, estimatedTimeRemainingSeconds: $estimatedTimeRemainingSeconds, stage: $stage, itemsExtracted: $itemsExtracted, currentItem: $currentItem)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'BatchOCRProgress'))
      ..add(DiagnosticsProperty('batchId', batchId))
      ..add(DiagnosticsProperty('totalImages', totalImages))
      ..add(DiagnosticsProperty('completedImages', completedImages))
      ..add(DiagnosticsProperty('failedImages', failedImages))
      ..add(DiagnosticsProperty('progressPercentage', progressPercentage))
      ..add(DiagnosticsProperty('status', status))
      ..add(DiagnosticsProperty('currentImageName', currentImageName))
      ..add(DiagnosticsProperty(
          'estimatedTimeRemainingSeconds', estimatedTimeRemainingSeconds))
      ..add(DiagnosticsProperty('stage', stage))
      ..add(DiagnosticsProperty('itemsExtracted', itemsExtracted))
      ..add(DiagnosticsProperty('currentItem', currentItem));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BatchOCRProgressImpl &&
            (identical(other.batchId, batchId) || other.batchId == batchId) &&
            (identical(other.totalImages, totalImages) ||
                other.totalImages == totalImages) &&
            (identical(other.completedImages, completedImages) ||
                other.completedImages == completedImages) &&
            (identical(other.failedImages, failedImages) ||
                other.failedImages == failedImages) &&
            (identical(other.progressPercentage, progressPercentage) ||
                other.progressPercentage == progressPercentage) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.currentImageName, currentImageName) ||
                other.currentImageName == currentImageName) &&
            (identical(other.estimatedTimeRemainingSeconds,
                    estimatedTimeRemainingSeconds) ||
                other.estimatedTimeRemainingSeconds ==
                    estimatedTimeRemainingSeconds) &&
            (identical(other.stage, stage) || other.stage == stage) &&
            (identical(other.itemsExtracted, itemsExtracted) ||
                other.itemsExtracted == itemsExtracted) &&
            (identical(other.currentItem, currentItem) ||
                other.currentItem == currentItem));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      batchId,
      totalImages,
      completedImages,
      failedImages,
      progressPercentage,
      status,
      currentImageName,
      estimatedTimeRemainingSeconds,
      stage,
      itemsExtracted,
      currentItem);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BatchOCRProgressImplCopyWith<_$BatchOCRProgressImpl> get copyWith =>
      __$$BatchOCRProgressImplCopyWithImpl<_$BatchOCRProgressImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BatchOCRProgressImplToJson(
      this,
    );
  }
}

abstract class _BatchOCRProgress extends BatchOCRProgress {
  const factory _BatchOCRProgress(
          {@JsonKey(name: 'batch_id') required final String batchId,
          @JsonKey(name: 'total_images') required final int totalImages,
          @JsonKey(name: 'completed_images') required final int completedImages,
          @JsonKey(name: 'failed_images') required final int failedImages,
          @JsonKey(name: 'progress_percentage')
          required final double progressPercentage,
          required final BatchStatus status,
          @JsonKey(name: 'current_image_name') final String? currentImageName,
          @JsonKey(name: 'estimated_time_remaining_seconds')
          final int? estimatedTimeRemainingSeconds,
          final String? stage,
          @JsonKey(name: 'items_extracted') final int? itemsExtracted,
          @JsonKey(name: 'current_item') final String? currentItem}) =
      _$BatchOCRProgressImpl;
  const _BatchOCRProgress._() : super._();

  factory _BatchOCRProgress.fromJson(Map<String, dynamic> json) =
      _$BatchOCRProgressImpl.fromJson;

  @override
  @JsonKey(name: 'batch_id')
  String get batchId;
  @override
  @JsonKey(name: 'total_images')
  int get totalImages;
  @override
  @JsonKey(name: 'completed_images')
  int get completedImages;
  @override
  @JsonKey(name: 'failed_images')
  int get failedImages;
  @override
  @JsonKey(name: 'progress_percentage')
  double get progressPercentage;
  @override
  BatchStatus get status;
  @override
  @JsonKey(name: 'current_image_name')
  String? get currentImageName;
  @override
  @JsonKey(name: 'estimated_time_remaining_seconds')
  int? get estimatedTimeRemainingSeconds;
  @override // Phase 1.2: Add stage tracking from WebSocket
  String? get stage;
  @override // Current OCR stage: "text_extraction", "brand_matching", etc.
  @JsonKey(name: 'items_extracted')
  int? get itemsExtracted;
  @override // Phase 2.2: Items count
  @JsonKey(name: 'current_item')
  String? get currentItem;
  @override
  @JsonKey(ignore: true)
  _$$BatchOCRProgressImplCopyWith<_$BatchOCRProgressImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

EnrichmentWorkflowState _$EnrichmentWorkflowStateFromJson(
    Map<String, dynamic> json) {
  return _EnrichmentWorkflowState.fromJson(json);
}

/// @nodoc
mixin _$EnrichmentWorkflowState {
  @JsonKey(name: 'batch_id')
  String get batchId => throw _privateConstructorUsedError;
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds => throw _privateConstructorUsedError;
  @JsonKey(name: 'deduplicated_items')
  List<DeduplicatedItem> get deduplicatedItems =>
      throw _privateConstructorUsedError;
  @JsonKey(name: 'enriched_items')
  List<EnrichedStockItem> get enrichedItems =>
      throw _privateConstructorUsedError;
  @JsonKey(name: 'current_item_index')
  int get currentItemIndex => throw _privateConstructorUsedError;
  @JsonKey(name: 'current_step')
  EnrichmentStep get currentStep => throw _privateConstructorUsedError;
  @JsonKey(name: 'is_loading')
  bool get isLoading => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $EnrichmentWorkflowStateCopyWith<EnrichmentWorkflowState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EnrichmentWorkflowStateCopyWith<$Res> {
  factory $EnrichmentWorkflowStateCopyWith(EnrichmentWorkflowState value,
          $Res Function(EnrichmentWorkflowState) then) =
      _$EnrichmentWorkflowStateCopyWithImpl<$Res, EnrichmentWorkflowState>;
  @useResult
  $Res call(
      {@JsonKey(name: 'batch_id') String batchId,
      @JsonKey(name: 'session_ids') List<String> sessionIds,
      @JsonKey(name: 'deduplicated_items')
      List<DeduplicatedItem> deduplicatedItems,
      @JsonKey(name: 'enriched_items') List<EnrichedStockItem> enrichedItems,
      @JsonKey(name: 'current_item_index') int currentItemIndex,
      @JsonKey(name: 'current_step') EnrichmentStep currentStep,
      @JsonKey(name: 'is_loading') bool isLoading,
      String? error});
}

/// @nodoc
class _$EnrichmentWorkflowStateCopyWithImpl<$Res,
        $Val extends EnrichmentWorkflowState>
    implements $EnrichmentWorkflowStateCopyWith<$Res> {
  _$EnrichmentWorkflowStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? batchId = null,
    Object? sessionIds = null,
    Object? deduplicatedItems = null,
    Object? enrichedItems = null,
    Object? currentItemIndex = null,
    Object? currentStep = null,
    Object? isLoading = null,
    Object? error = freezed,
  }) {
    return _then(_value.copyWith(
      batchId: null == batchId
          ? _value.batchId
          : batchId // ignore: cast_nullable_to_non_nullable
              as String,
      sessionIds: null == sessionIds
          ? _value.sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      deduplicatedItems: null == deduplicatedItems
          ? _value.deduplicatedItems
          : deduplicatedItems // ignore: cast_nullable_to_non_nullable
              as List<DeduplicatedItem>,
      enrichedItems: null == enrichedItems
          ? _value.enrichedItems
          : enrichedItems // ignore: cast_nullable_to_non_nullable
              as List<EnrichedStockItem>,
      currentItemIndex: null == currentItemIndex
          ? _value.currentItemIndex
          : currentItemIndex // ignore: cast_nullable_to_non_nullable
              as int,
      currentStep: null == currentStep
          ? _value.currentStep
          : currentStep // ignore: cast_nullable_to_non_nullable
              as EnrichmentStep,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EnrichmentWorkflowStateImplCopyWith<$Res>
    implements $EnrichmentWorkflowStateCopyWith<$Res> {
  factory _$$EnrichmentWorkflowStateImplCopyWith(
          _$EnrichmentWorkflowStateImpl value,
          $Res Function(_$EnrichmentWorkflowStateImpl) then) =
      __$$EnrichmentWorkflowStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(name: 'batch_id') String batchId,
      @JsonKey(name: 'session_ids') List<String> sessionIds,
      @JsonKey(name: 'deduplicated_items')
      List<DeduplicatedItem> deduplicatedItems,
      @JsonKey(name: 'enriched_items') List<EnrichedStockItem> enrichedItems,
      @JsonKey(name: 'current_item_index') int currentItemIndex,
      @JsonKey(name: 'current_step') EnrichmentStep currentStep,
      @JsonKey(name: 'is_loading') bool isLoading,
      String? error});
}

/// @nodoc
class __$$EnrichmentWorkflowStateImplCopyWithImpl<$Res>
    extends _$EnrichmentWorkflowStateCopyWithImpl<$Res,
        _$EnrichmentWorkflowStateImpl>
    implements _$$EnrichmentWorkflowStateImplCopyWith<$Res> {
  __$$EnrichmentWorkflowStateImplCopyWithImpl(
      _$EnrichmentWorkflowStateImpl _value,
      $Res Function(_$EnrichmentWorkflowStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? batchId = null,
    Object? sessionIds = null,
    Object? deduplicatedItems = null,
    Object? enrichedItems = null,
    Object? currentItemIndex = null,
    Object? currentStep = null,
    Object? isLoading = null,
    Object? error = freezed,
  }) {
    return _then(_$EnrichmentWorkflowStateImpl(
      batchId: null == batchId
          ? _value.batchId
          : batchId // ignore: cast_nullable_to_non_nullable
              as String,
      sessionIds: null == sessionIds
          ? _value._sessionIds
          : sessionIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
      deduplicatedItems: null == deduplicatedItems
          ? _value._deduplicatedItems
          : deduplicatedItems // ignore: cast_nullable_to_non_nullable
              as List<DeduplicatedItem>,
      enrichedItems: null == enrichedItems
          ? _value._enrichedItems
          : enrichedItems // ignore: cast_nullable_to_non_nullable
              as List<EnrichedStockItem>,
      currentItemIndex: null == currentItemIndex
          ? _value.currentItemIndex
          : currentItemIndex // ignore: cast_nullable_to_non_nullable
              as int,
      currentStep: null == currentStep
          ? _value.currentStep
          : currentStep // ignore: cast_nullable_to_non_nullable
              as EnrichmentStep,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      error: freezed == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EnrichmentWorkflowStateImpl extends _EnrichmentWorkflowState
    with DiagnosticableTreeMixin {
  const _$EnrichmentWorkflowStateImpl(
      {@JsonKey(name: 'batch_id') required this.batchId,
      @JsonKey(name: 'session_ids') required final List<String> sessionIds,
      @JsonKey(name: 'deduplicated_items')
      required final List<DeduplicatedItem> deduplicatedItems,
      @JsonKey(name: 'enriched_items')
      required final List<EnrichedStockItem> enrichedItems,
      @JsonKey(name: 'current_item_index') required this.currentItemIndex,
      @JsonKey(name: 'current_step') required this.currentStep,
      @JsonKey(name: 'is_loading') this.isLoading = false,
      this.error})
      : _sessionIds = sessionIds,
        _deduplicatedItems = deduplicatedItems,
        _enrichedItems = enrichedItems,
        super._();

  factory _$EnrichmentWorkflowStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$EnrichmentWorkflowStateImplFromJson(json);

  @override
  @JsonKey(name: 'batch_id')
  final String batchId;
  final List<String> _sessionIds;
  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds {
    if (_sessionIds is EqualUnmodifiableListView) return _sessionIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_sessionIds);
  }

  final List<DeduplicatedItem> _deduplicatedItems;
  @override
  @JsonKey(name: 'deduplicated_items')
  List<DeduplicatedItem> get deduplicatedItems {
    if (_deduplicatedItems is EqualUnmodifiableListView)
      return _deduplicatedItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_deduplicatedItems);
  }

  final List<EnrichedStockItem> _enrichedItems;
  @override
  @JsonKey(name: 'enriched_items')
  List<EnrichedStockItem> get enrichedItems {
    if (_enrichedItems is EqualUnmodifiableListView) return _enrichedItems;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_enrichedItems);
  }

  @override
  @JsonKey(name: 'current_item_index')
  final int currentItemIndex;
  @override
  @JsonKey(name: 'current_step')
  final EnrichmentStep currentStep;
  @override
  @JsonKey(name: 'is_loading')
  final bool isLoading;
  @override
  final String? error;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) {
    return 'EnrichmentWorkflowState(batchId: $batchId, sessionIds: $sessionIds, deduplicatedItems: $deduplicatedItems, enrichedItems: $enrichedItems, currentItemIndex: $currentItemIndex, currentStep: $currentStep, isLoading: $isLoading, error: $error)';
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('type', 'EnrichmentWorkflowState'))
      ..add(DiagnosticsProperty('batchId', batchId))
      ..add(DiagnosticsProperty('sessionIds', sessionIds))
      ..add(DiagnosticsProperty('deduplicatedItems', deduplicatedItems))
      ..add(DiagnosticsProperty('enrichedItems', enrichedItems))
      ..add(DiagnosticsProperty('currentItemIndex', currentItemIndex))
      ..add(DiagnosticsProperty('currentStep', currentStep))
      ..add(DiagnosticsProperty('isLoading', isLoading))
      ..add(DiagnosticsProperty('error', error));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EnrichmentWorkflowStateImpl &&
            (identical(other.batchId, batchId) || other.batchId == batchId) &&
            const DeepCollectionEquality()
                .equals(other._sessionIds, _sessionIds) &&
            const DeepCollectionEquality()
                .equals(other._deduplicatedItems, _deduplicatedItems) &&
            const DeepCollectionEquality()
                .equals(other._enrichedItems, _enrichedItems) &&
            (identical(other.currentItemIndex, currentItemIndex) ||
                other.currentItemIndex == currentItemIndex) &&
            (identical(other.currentStep, currentStep) ||
                other.currentStep == currentStep) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      batchId,
      const DeepCollectionEquality().hash(_sessionIds),
      const DeepCollectionEquality().hash(_deduplicatedItems),
      const DeepCollectionEquality().hash(_enrichedItems),
      currentItemIndex,
      currentStep,
      isLoading,
      error);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$EnrichmentWorkflowStateImplCopyWith<_$EnrichmentWorkflowStateImpl>
      get copyWith => __$$EnrichmentWorkflowStateImplCopyWithImpl<
          _$EnrichmentWorkflowStateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EnrichmentWorkflowStateImplToJson(
      this,
    );
  }
}

abstract class _EnrichmentWorkflowState extends EnrichmentWorkflowState {
  const factory _EnrichmentWorkflowState(
      {@JsonKey(name: 'batch_id') required final String batchId,
      @JsonKey(name: 'session_ids') required final List<String> sessionIds,
      @JsonKey(name: 'deduplicated_items')
      required final List<DeduplicatedItem> deduplicatedItems,
      @JsonKey(name: 'enriched_items')
      required final List<EnrichedStockItem> enrichedItems,
      @JsonKey(name: 'current_item_index') required final int currentItemIndex,
      @JsonKey(name: 'current_step') required final EnrichmentStep currentStep,
      @JsonKey(name: 'is_loading') final bool isLoading,
      final String? error}) = _$EnrichmentWorkflowStateImpl;
  const _EnrichmentWorkflowState._() : super._();

  factory _EnrichmentWorkflowState.fromJson(Map<String, dynamic> json) =
      _$EnrichmentWorkflowStateImpl.fromJson;

  @override
  @JsonKey(name: 'batch_id')
  String get batchId;
  @override
  @JsonKey(name: 'session_ids')
  List<String> get sessionIds;
  @override
  @JsonKey(name: 'deduplicated_items')
  List<DeduplicatedItem> get deduplicatedItems;
  @override
  @JsonKey(name: 'enriched_items')
  List<EnrichedStockItem> get enrichedItems;
  @override
  @JsonKey(name: 'current_item_index')
  int get currentItemIndex;
  @override
  @JsonKey(name: 'current_step')
  EnrichmentStep get currentStep;
  @override
  @JsonKey(name: 'is_loading')
  bool get isLoading;
  @override
  String? get error;
  @override
  @JsonKey(ignore: true)
  _$$EnrichmentWorkflowStateImplCopyWith<_$EnrichmentWorkflowStateImpl>
      get copyWith => throw _privateConstructorUsedError;
}
